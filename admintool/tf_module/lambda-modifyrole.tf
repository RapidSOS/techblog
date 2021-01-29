data "aws_iam_policy_document" "role_policy_modifyrole" {
  
  statement {

    #assume admin role to modify trust policy
    actions = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/admin"]

  }

  statement {

    actions = ["states:Send*"]
    resources = ["*"]
  }

}

resource "aws_iam_policy" "iam_policy_modifyrole" {
  name   = "modify_role"
  policy = data.aws_iam_policy_document.role_policy_modifyrole.json
}

