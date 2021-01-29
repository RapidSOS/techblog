data "aws_iam_policy_document" "role_policy_ctlookup" {
  
  statement {

    #assume a readonly role for cloudtrail lookup
    actions = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/readonly"]

  }

  statement {

    actions = ["states:Send*"]
    resources = ["*"]
  }

}

resource "aws_iam_policy" "iam_policy_ctlookup" {
  name   = "cloudtrail_lookup"
  policy = data.aws_iam_policy_document.role_policy_ctlookup.json
}


