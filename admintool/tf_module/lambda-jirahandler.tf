data "aws_iam_policy_document" "role_policy_jirahandler" {
  
  statement {

    actions = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:jira-creds*"]

  }

  statement {

    actions = ["states:Send*"]
    resources = ["*"]
  }

}

resource "aws_iam_policy" "iam_policy_jirahandler" {
  name   = "jira_handler"
  policy = data.aws_iam_policy_document.role_policy_jirahandler.json
}


