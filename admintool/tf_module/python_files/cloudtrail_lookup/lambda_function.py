import boto3
import botocore
import os
import json
import re
import logging
from datetime import datetime

logging.getLogger().setLevel(logging.INFO)

sf_client = boto3.client("stepfunctions")
sts_client = boto3.client("sts")

# assume readonly role to get permission for cloudtrail lookup
ROLE_ARN_TO_ASSUME = os.environ.get("ROLE_ARN_TO_ASSUME")

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
    # created/remove timestamp tell you the start and end of cloudtrail events

    task_token = event.get("TaskToken")
    user_arn = event.get("user_arn")
    created_timestamp = event.get("created_timestamp")
    removal_timestamp = event.get("removal_timestamp")

    # validate params
    if (user_arn is None or created_timestamp is None or removal_timestamp is None):
        error_msg = (
            f"user_arn is {user_arn}, created_timestamp is {created_timestamp}, "
            f"removal_timestamp is {removal_timestamp}, one is missing"
        )
        send_task_failure(task_token, error_msg)
        return False

    # validate arn format
    if re.match('arn:aws:iam::\d{12}:user/\w+', user_arn) is None:
        send_task_failure(task_token, f"invalid arn {user_arn}")
        return False

    # validate timestamp format
    if(len(created_timestamp) != 10 or not created_timestamp.isdigit()):
        send_task_failure(task_token, f"{created_timestamp} is not valid created_timestamp")
        return False

    if(len(removal_timestamp) != 10 or not removal_timestamp.isdigit()):
        send_task_failure(task_token, f"{removal_timestamp} is not a valid removal_timestamp")
        return False

    # from the arn, we care about the user after the /
    # discard the stuff before
    (*_, username) = user_arn.split("/")

    # validate user
    if not username.isalnum():
        logging.error("user_arn is not formatted properly or not passed")
        send_task_failure(task_token)
        return False

    logging.info((
        f"Obtained user_arn {user_arn}, created_timestamp {created_timestamp}, "
        f"removal_timestamp {removal_timestamp} from event"
    ))

    # this was designed to run from the mgmt acct and assume into prod acct
    # to lookup cloudtrail events
    try:
        tmp_credentials = sts_client.assume_role(
            RoleArn=ROLE_ARN_TO_ASSUME, RoleSessionName=username
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

    # use the prod assumed role for the client
    cloudtrail_client = assumed_role_session.client('cloudtrail')

    logging.info(
        f"Looking up cloudtrail events for AWS username {username}")

    # lookup the users events
    response = cloudtrail_client.lookup_events(
        LookupAttributes=[
            {
                'AttributeKey': 'Username',
                'AttributeValue': username
            },
        ],
        StartTime=datetime.fromtimestamp(int(created_timestamp)),
        EndTime=datetime.fromtimestamp(int(removal_timestamp)),
        MaxResults=50
    )

    # put this in here, so even if the results are empty theres something
    return_dict = {
        "user": username,
        "event_count": str(len(response['Events']))
    }

    # construct the dict of events
    if(response['ResponseMetadata']['HTTPStatusCode'] == 200):
        for event in response['Events']:
            return_dict[event['EventId']] = {
                "EventTime": str(event['EventTime']),
                "EventName": event['EventName'],
                "EventSource": event['EventSource']
            }
    else:
        send_task_failure(task_token, "Could not query cloudtrail events")
        return False

    # if you are coming from AWS step functions send success
    # else just return the events normally

    if task_token:
        sf_client.send_task_success(
            taskToken=task_token, output=json.dumps(return_dict))

    return return_dict
