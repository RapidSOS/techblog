{
  "Comment": "A secure workflow to grant prod admin access",
  "StartAt": "choice- check user_arn present",
  "States": {
    
      "choice- check user_arn present": {
      "Type" : "Choice",
      "Choices": [
        {
          "Variable": "$$.Execution.Input.user_arn",
          "IsPresent": false,
          "Next": "FAIL- user_arn missing"
        }
      ],
      "Default": "dynamo- check if existing record"
    },
    
    "dynamo- check if existing record": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:getItem",
      "Parameters": {
      "TableName": "${dynamotable}",
      "Key": { "user_arn.$": "$$.Execution.Input.user_arn"}
    },
      "Next": "choice- add more time or NEW"
  },
    "choice- add more time or NEW": {
      "Type" : "Choice",
      "Choices": [
        {
          "Variable": "$.Item.user_arn.S",
          "IsPresent": true,
          "Next": "dynamo- add another hour"
        }
      ],
      "Default": "choice- check reason present"
    },
    
    "FAIL- user_arn missing": {
      "Type": "Fail",
      "Cause": "Invalid response.",
      "Error": "missing input_arn "
    },
    "FAIL- reason missing": {
      "Type": "Fail",
      "Cause": "Invalid response.",
      "Error": "missing reason"
    },
    
    "dynamo- add another hour": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "Parameters": {
        "TableName": "${dynamotable}",
        "UpdateExpression": "SET removal_timestamp = removal_timestamp + :myValueRef1, hours_remaining = hours_remaining + :myValueRef2",
        "ExpressionAttributeValues": {
          ":myValueRef1": {"N": "3600"},
          ":myValueRef2": {"N": "1"}
        },
        "Key": { "user_arn.$": "$$.Execution.Input.user_arn"}
      },
      "End": true
    },
    
    "choice- check reason present": {
      "Type" : "Choice",
      "Choices": [
        {
          "Variable": "$$.Execution.Input.reason",
          "IsPresent": false,
          "Next": "FAIL- reason missing"
        }
      ],
      "Default": "lambda- add to admin role"
    },
    
    "lambda- add to admin role": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
        "Parameters": {
          "FunctionName": "arn:aws:lambda:${region}:${acct_id}:function:modify_role",
          "Payload":{
            "op_type":"add",
            "user_arn.$":"$$.Execution.Input.user_arn",
            "TaskToken.$": "$$.Task.Token"
          }
        },
      "Next": "dynamo- add new record"
    },
    
    "dynamo- add new record": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:putItem",
      "Parameters": {
        "TableName": "${dynamotable}",
        "Item": {
          "user_arn" : {"S.$": "$.user_arn"},
          "created_timestamp" : {"N.$": "$.created_timestamp"},
          "removal_timestamp" : {"N.$": "$.removal_timestamp"},
          "hours_remaining" : {"N.$": "$.hours_remaining"}
        }
      },
      
      "Next": "lambda- create jira ticket"
    },
    
    "lambda- create jira ticket": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
      "Parameters": {
        "FunctionName": "arn:aws:lambda:${region}:${acct_id}:function:jira_handler",
        "Payload": {
          "op_type" : "create",
          "reason.$" : "$$.Execution.Input.reason",
          "TaskToken.$": "$$.Task.Token"
        }
      },
      "Next": "dynamo- update jira ticket number"
    },
    
    "dynamo- update jira ticket number": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "Parameters": {
        "TableName": "${dynamotable}",
        "UpdateExpression": "SET jira_issue_key =  :myValueRef",
        "ExpressionAttributeValues": {
          ":myValueRef": {"S.$": "$.issue_key"}
        },
        "Key": { "user_arn.$": "$$.Execution.Input.user_arn"}
      },
      "Next": "wait an hour"
    },
    
    "wait an hour":{
      "Type": "Wait",
      "Seconds": 3600,
      "Next": "dynamo- decrement hour"
    },
    
    "dynamo- decrement hour": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "Parameters": {
      "TableName": "${dynamotable}",
      "UpdateExpression": "SET hours_remaining = hours_remaining - :myValueRef",
      "ExpressionAttributeValues": {
        ":myValueRef": {"N": "1"}
      },
        "Key": { "user_arn.$": "$$.Execution.Input.user_arn"}
      },
      "Next": "dynamo- get record"
    },
    
    "dynamo- get record": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:getItem",
      "Parameters": {
      "TableName": "${dynamotable}",
      "Key": { "user_arn.$": "$$.Execution.Input.user_arn"}
      },
      "Next": "choice- wait again or proceed"
    },
  
    "choice- wait again or proceed": {
      "Type" : "Choice",
      "Choices": [
        {
          "Variable": "$.Item.hours_remaining",
          "NumericGreaterThanEquals": 1,
          "Next": "wait an hour"
        }
        ],
          "Default": "lambda- remove from role"   
    },
    
    "lambda- remove from role": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
      "ResultPath": null,
      "Parameters": {
        "FunctionName": "arn:aws:lambda:${region}:${acct_id}:function:modify_role",
        "Payload":{
          "op_type": "remove",
          "user_arn.$" : "$$.Execution.Input.user_arn",
          "TaskToken.$": "$$.Task.Token"
        }
      },
      "Next": "dynamo- delete record"
    },
    
    "dynamo- delete record": {
      "Type": "Task",
      "ResultPath": null,
      "Resource": "arn:aws:states:::dynamodb:deleteItem",
      "Parameters": {
        "TableName": "${dynamotable}",
        "Key": { "user_arn.$": "$$.Execution.Input.user_arn"}
      },
      "Next": "wait 20 min for cloudtrail"
    },
    
    "wait 20 min for cloudtrail":{
      "Type": "Wait",
      "Seconds": 1200,
      "Next": "lambda- get cloudtrail logs"
    },
    
    "lambda- get cloudtrail logs": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
      "ResultPath": "$.cloudtrail_events",
      "Parameters":{
        "FunctionName": "arn:aws:lambda:${region}:${acct_id}:function:cloudtrail_lookup",
        "Payload":{
          "created_timestamp.$": "$.Item.created_timestamp.N",
          "removal_timestamp.$": "$.Item.removal_timestamp.N",
          "user_arn.$": "$.Item.user_arn.S",
          "TaskToken.$": "$$.Task.Token"
          }        
      },
      "Next": "lambda- add jira cloudtrail comments"
    },
    
    "lambda- add jira cloudtrail comments": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
      "Parameters":{
        "FunctionName": "arn:aws:lambda:${region}:${acct_id}:function:jira_handler",
        "Payload": {
          "op_type": "add_comments",
          "issue_key.$": "$.Item.jira_issue_key.S",
          "issue_comment.$": "$.cloudtrail_events",
          "TaskToken.$": "$$.Task.Token"
      }
      
    },    
      "End": true
  }
}
}