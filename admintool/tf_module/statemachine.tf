resource "aws_sfn_state_machine" "admin_tool_state_machine" {
  name     = "admin-tool-state-machine"
  role_arn = aws_iam_role.state_machine_role.arn

  definition = templatefile("${path.module}/statemachine.tpl",
    { acct_id     = "${data.aws_caller_identity.current.account_id}",
      region      = "${data.aws_region.current.name}",
      dynamotable = "${local.dynamo_table}"
    }
  )
}


data "aws_iam_policy_document" "role_policy_state_machine" {

  statement {

    actions = ["lambda:InvokeFunction"]
    resources = [
      for function in keys(local.function_descriptions) :
      "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${function}"
    ]

  }

  statement {

    actions   = ["states:Send*"]
    resources = ["*"]
  }

  statement {

    actions   = ["dynamodb:*Item"]
    resources = ["${aws_dynamodb_table.adminlog.arn}"]
  }

  statement {

    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups"
    ]

    resources = ["*"]
  }

}

resource "aws_iam_policy" "iam_policy_statemachine" {
  name   = "admintool-statemachine"
  policy = data.aws_iam_policy_document.role_policy_state_machine.json
}



resource "aws_iam_role_policy_attachment" "sfn_role_attachment" {

  role       = aws_iam_role.state_machine_role.name
  policy_arn = aws_iam_policy.iam_policy_statemachine.arn
}


resource "aws_iam_role" "state_machine_role" {

  name = "admintool-statemachine"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "states.amazonaws.com"
        },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}
