import boto3
import json
import os
import logging
from botocore.exceptions import ClientError
from jira import JIRA
from jira import JIRAError


logging.getLogger().setLevel(logging.INFO)

sf_client = boto3.client("stepfunctions")
sm_client = boto3.client('secretsmanager')


# In the JIRA cloud API, they want you to use the unique id
# not the user friendly name ughh :( The default id
# below is for jmancuso@rapidsos.com but can be overwritten via env var
JIRA_ASSIGNEE_ID = os.environ.get("JIRA_ASSIGNEE_ID")
JIRA_SERVER = os.environ.get("JIRA_SERVER")
JIRA_PROJECT_KEY = os.environ.get("JIRA_PROJECT_KEY")

# Summary is the title of the ticket
JIRA_SUMMARY = "Requesting admin access to production"
JIRA_ISSUE_TYPE = "Task"

# we want to explicitly tell AWS step functions about the error
# if we are calling the lambda outside of step functions, just log the err


def send_task_failure(task_token, err=None):
    if task_token:
        logging.error("Notifying task of failure.", err)
        sf_client.send_task_failure(
            taskToken=task_token, error="error", cause=err)
    else:
        logging.error("No task to notify, but failure occurred.")
        logging.error(err)


def create_jira_ticket(event, task_token, jira_client):
    reason = event.get('reason')

    if reason is None:
        send_task_failure(task_token, "reason not found in input json")
        return False

    createDict = {
        "summary": JIRA_SUMMARY,
        "issuetype": {"name": JIRA_ISSUE_TYPE},
        "project": {"key": JIRA_PROJECT_KEY},
        "assignee": {"id": JIRA_ASSIGNEE_ID},
        "description": reason
    }

    logging.info(f"Creating ticket using payload: {json.dumps(createDict)}")

    try:
        # https://developer.atlassian.com/server/jira/platform/jira-rest-api-examples/#creating-an-issue-examples
        # https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/
        jira_issue = jira_client.create_issue(fields=createDict)
    except JIRAError as err:
        send_task_failure(
            task_token, f"Unable to create JIRA issue {str(err.text)}")
        return False

    if not jira_issue.key:
        send_task_failure(task_token, "Couldn't create new JIRA issue")
        return False
    else:
        logging.info("Created jira issue %s", jira_issue.key)
        return_dict = {"issue_key": jira_issue.key}

        # either you are calling the lambda directly 
        # or calling from AWS step functions with task token
        if task_token is None:
            logging.info("SUCCESS")
            return return_dict
        else:
            sf_client.send_task_success(taskToken=task_token,
                                        output=json.dumps(return_dict))
            return True


def add_comments(event, task_token, jira_client):
    ticket_key = event.get('issue_key')
    comment = json.dumps(event.get('issue_comment'), indent=4)

    if not ticket_key:
        send_task_failure(
            task_token, "issue_key was not passed in input json")
        return False

    if not comment:
        send_task_failure(
            task_token, "issue_comment not passed in input json")
        return False

    try:
        jira_client.add_comment(ticket_key, comment)
    except JIRAError as err:
        send_task_failure(task_token, ticket_key +
                            str(err.text) + str(comment))
        return False

    # either you are calling the lambda directly 
    # or calling from AWS step functions with task token
    if task_token is None:
        logging.info("SUCCESS")
        return False
    else:
        sf_client.send_task_success(taskToken=task_token,
                                    output='{"Success" : "true"}')
        return True

# either we are creating a new ticket or adding comments (op_type)
def lambda_handler(event, context):

    task_token = event.get("TaskToken")
    op_type = event.get("op_type")

    if op_type is None:
        send_task_failure(task_token, "op_type is missing")
        return False

    logging.info("Obtaining jira creds from secrets manager...")

    try:
        sm_response = sm_client.get_secret_value(
            SecretId=os.environ.get('secret', 'jira-creds-admintool'))
    except ClientError as e:
        error_msg = (
            f"Could not get jira creds from secretsmanager.",
            f"{str(e.response['Error']['Code'])}"
        )
        send_task_failure(task_token, error_msg)
        return False

    try:
        user_secret = json.loads(sm_response['SecretString'])['user']
    except (KeyError, json.decoder.JSONDecodeError):
        send_task_failure(task_token, f"Error loading user SecretString")
        return False

    try:
        pass_secret = json.loads(sm_response['SecretString'])['pass']
    except (KeyError, json.decoder.JSONDecodeError):
        send_task_failure(task_token, f"Error loading pass SecretString")
        return False

    if (user_secret is None or pass_secret is None):
        send_task_failure(task_token, "SecretString is missing")
        return False

    logging.info("Done. Connecting to %s", JIRA_SERVER)

    try:
        jira_client = JIRA(server=JIRA_SERVER,
                           basic_auth=(user_secret, pass_secret))
    except JIRAError as err:
        send_task_failure(task_token, f"unable to connect to JIRA {err.text}")
        return False

    if not jira_client:
        send_task_failure(task_token, "unable to connect to JIRA ")
        return False
    else:
        logging.info("Connected to %s", JIRA_SERVER)

    if(op_type == "create"):

        return create_jira_ticket(event, task_token, jira_client)

    elif(op_type == "add_comments"):

        return add_comments(event, task_token, jira_client)

    else:
        logging.error("""op_type not 'create' or 'add_comments'.
            No clue what you are trying to do""")
        return False
