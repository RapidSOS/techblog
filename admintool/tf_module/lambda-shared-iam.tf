data "aws_iam_policy_document" "cloudwatch_logs_policy" {
  for_each = local.function_descriptions

  statement {
    actions   = ["logs:CreateLogGroup"]
    resources = ["*"]
  }

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${each.key}:*"]
  }
}

resource "aws_iam_policy" "cloudwatch_logs_policy" {
  for_each = local.function_descriptions

  name   = "cloudwatch_logs_${each.key}"
  policy = data.aws_iam_policy_document.cloudwatch_logs_policy[each.key].json
}

resource "aws_iam_role_policy_attachment" "cw-attach" {
  for_each = local.function_descriptions

  role       = aws_iam_role.lambda_role[each.key].name
  policy_arn = aws_iam_policy.cloudwatch_logs_policy[each.key].arn
}



resource "aws_iam_role" "lambda_role" {
  for_each = local.function_descriptions

  name = each.key

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
        },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}


resource "aws_iam_role_policy_attachment" "attachment" {
  for_each = local.function_descriptions

  role       = aws_iam_role.lambda_role[each.key].name
  policy_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${each.key}"
}
