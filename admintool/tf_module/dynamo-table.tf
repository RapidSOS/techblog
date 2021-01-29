resource "aws_dynamodb_table" "adminlog" {
  name           = local.dynamo_table
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "user_arn"
  
  server_side_encryption { enabled = true }

  attribute {
    name = "user_arn"
    type = "S"
  }

  tags = {
    JIRA        = local.jira_ticket
  }

}
