locals {

  #for more info
  jira_ticket = "XXXXX"

  #The descriptions of the lambda functions based on the name of those functions.
  function_descriptions = {
    "modify_role" : "Assumes the admin role and adds or removes the users arn from the admin role",
    "jira_handler" : "Creates a new JIRA ticket or adds comments to an existing one",
    "cloudtrail_lookup" : "Assume the readonly role and looks up cloudtrail event during a period of time"
  }

  #the name of the dynamo table that will store the temp records
  dynamo_table = "admin_logger"


}
