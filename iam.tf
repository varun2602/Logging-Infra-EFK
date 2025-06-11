resource "aws_iam_role_policy" "athena_lambda_s3_access" {
  name = "athena-s3-access"
  role = "athena-query-lambda-s3-access"  # Must match the actual IAM role name exactly

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:ListBucket"],
        Resource = "arn:aws:s3:::hfcl-logging-s3-bucket-7f896491"
      },
      {
        Effect = "Allow",
        Action = ["s3:GetObject"],
        Resource = "arn:aws:s3:::hfcl-logging-s3-bucket-7f896491/*"
      }
    ]
  })
}