import json
import os
import re
import boto3
import botocore
import logging
from time import time

logging.getLogger().setLevel(logging.INFO)

sf_client = boto3.client("stepfunctions")
sts_client = boto3.client("sts")

# this function assumes a role and then
# adds/removes a user from the trust policy of another role
ROLE_ARN_TO_ASSUME = os.environ.get("ROLE_ARN_TO_ASSUME")
ROLE_NAME_TO_MODIFY = os.environ.get("ROLE_NAME_TO_MODIFY")

# we want to explicitly tell AWS step functions about the error
# if we are calling the lambda outside of step functions, just log the err


def send_task_failure(task_token, err=None):
    if task_token:
        logging.error("Notifying task of failure.")
        sf_client.send_task_failure(
            taskToken=task_token, error="error", cause=err
        )
    else:
        logging.error("No task to notify, but failure occurred.")
        logging.error(err)


def lambda_handler(event, context):

    # task token is passed from AWS step functions
    # user_arn is the user running this
    # op_type is either add or remove
    task_token = event.get("TaskToken")
    user_arn = event.get("user_arn")
    op_type = event.get("op_type")

    # validate
    if user_arn is None or op_type is None:
        send_task_failure(task_token,
                          f"user_arn is {user_arn} and op_type is {op_type},one is missing")
        return False

    # validate arn format
    if re.match('arn:aws:iam::\d{12}:user/\w+', user_arn) is None:
        send_task_failure(task_token, f"invalid arn {user_arn}")
        return False

    # assume role from mgmt (or whatever src acct) to prod
    try:
        tmp_credentials = sts_client.assume_role(
            RoleArn=ROLE_ARN_TO_ASSUME, RoleSessionName="lambda-assume-role"
        )["Credentials"]
    except botocore.exceptions.ClientError as err:
        send_task_failure(task_token,
                          f"Lambda was Unable to assume role {ROLE_ARN_TO_ASSUME} {str(err)}")
        return False

    assumed_role_session = boto3.Session(
        aws_access_key_id=tmp_credentials["AccessKeyId"],
        aws_secret_access_key=tmp_credentials["SecretAccessKey"],
        aws_session_token=tmp_credentials["SessionToken"],
    )

    logging.info("assumed role %s", ROLE_ARN_TO_ASSUME)
    # iam client is prod iam client
    iam_client = assumed_role_session.client("iam")

    role_result = modify_role(
        iam_client, ROLE_NAME_TO_MODIFY, user_arn, op_type, task_token
    )

    if not role_result:
        send_task_failure(task_token)
        return False

    # this dictionary will be used to create a DynamoDB record
    return_dict = {
        "user_arn": user_arn,
        "created_timestamp": str(int(time())),
        "removal_timestamp": str(int(time()) + 3600),
        "hours_remaining": "1",
    }

    # if this lambda was called from AWS step functions
    # then explicitly send success

    if task_token:
        sf_client.send_task_success(
            taskToken=task_token, output=json.dumps(return_dict)
        )
    # You need to return either way as send_task_success 
    # doesnt exit for you
    return return_dict


def modify_role(iam_client, role_name, user_arn, op_type, task_token):
    logging.info("%s to role %s", op_type, role_name)
    iam_role = iam_client.get_role(RoleName=role_name)

    role_policy_doc = iam_role["Role"]["AssumeRolePolicyDocument"]

    # if its just a single arn it can be a string
    # but when its more than 1 we need to convert it to a list
    aws_principals = role_policy_doc["Statement"][0]["Principal"]["AWS"]
    if isinstance(aws_principals, str):
        # split on a non-existent space in the arn
        # so that we just get 1 single list item
        aws_principals = role_policy_doc["Statement"][0]["Principal"][
            "AWS"
        ].split(" ")

    if op_type == "add":
        logging.info(
            "appending %s to %s role trust policy", user_arn, role_name
        )
        aws_principals.append(user_arn)
    elif op_type == "remove":
        logging.info(f"removing {user_arn} from {role_name} role trust policy")
        if len(aws_principals) == 1:
            send_task_failure(
                task_token, "Cannot make assume role principals empty"
            )
        try:
            aws_principals.remove(user_arn)
        except ValueError as err:
            send_task_failure(task_token, f"{user_arn} was not found in role trust policy for {role_name} role")
            return False
    else:
        send_task_failure(task_token, f"Unknown action {op_type}")

    iam_update_response = iam_client.update_assume_role_policy(
        RoleName=role_name, PolicyDocument=json.dumps(role_policy_doc)
    )

    logging.info(
        "Update role, statusCode {0}".format(
            iam_update_response["ResponseMetadata"]["HTTPStatusCode"]
        )
    )
    return True
