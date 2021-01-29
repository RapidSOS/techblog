resource "null_resource" "lambda_build_and_zip" {
  for_each = local.function_descriptions

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command     = "./lambda_build_and_zip.sh ${each.key}"
    working_dir = path.module
  }
}

resource "aws_lambda_function" "lambda_function" {
  for_each = local.function_descriptions

  depends_on    = [null_resource.lambda_build_and_zip]
  function_name = each.key
  description   = each.value

  filename = "${path.module}/lambda-deployment-pkg-${each.key}.zip"
  handler  = "lambda_function.lambda_handler"

  role = aws_iam_role.lambda_role[each.key].arn

  #if you do this you will get "file not found" since its not available until null_resource run
  #so just use timestamp to re build and re upload every time
  #source_code_hash = filebase64sha256("${path.module}/lambda-deployment-pkg-${var.function_list[count.index]}.zip")
  
  #keeping this commented out so it doesnt rebuild every time
  #source_code_hash = base64sha256(timestamp())

  runtime = "python3.8"

  timeout = 10 # seconds

  tags = {
    JIRA = local.jira_ticket
  }

  publish = true
}
