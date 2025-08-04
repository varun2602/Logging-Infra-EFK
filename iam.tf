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


# module "iam_role_for_glue_jobs" {
#   source  = "cloudposse/iam-role/aws"
#   version = "0.16.2"
  
#   principals = {
#     "Service" = ["glue.amazonaws.com"]
#   }
#   name        = "logging-infra"

#   managed_policy_arns = [
#     "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
#   ]

#   # Define custom inline policies here
#   policy_documents  = [
#     jsonencode({
#       Version = "2012-10-17"
#       Statement = [
#         { # S3 Read permissions for source bucket (logging_bucket)
#           Effect = "Allow"
#           Action = [
#             "s3:GetObject",
#             "s3:ListBucket"
#           ]
#           Resource = [
#             "arn:aws:s3:::${local.logging_bucket_name}",
#             "arn:aws:s3:::${local.logging_bucket_name}/*"
#           ]
#         },
#         { # S3 Read/Write permissions for Athena results bucket (and Glue temp files)
#           Effect = "Allow"
#           Action = [
#             "s3:GetObject",
#             "s3:ListBucket",
#             "s3:PutObject",
#             "s3:DeleteObject"
#           ]
#           Resource = [
#             "arn:aws:s3:::${local.athena_results_store_bucket_name}",
#             "arn:aws:s3:::${local.athena_results_store_bucket_name}/*"
#           ]
#         },
#         { # S3 Read permissions for Glue scripts bucket
#           Effect = "Allow"
#           Action = [
#             "s3:GetObject",
#             "s3:ListBucket"
#           ]
#           Resource = [
#             "arn:aws:s3:::${local.logging_bucket_name}", # Ensure you have this local defined
#             "arn:aws:s3:::${local.logging_bucket_name}/*"
#           ]
#         },
#         { # OpenSearch Write Permissions
#           Effect = "Allow"
#           Action = [
#             "es:ESHttpPost",
#             "es:ESHttpPut",
#             "es:ESHttpGet", # Often needed for checks
#             "es:DescribeElasticsearchDomains",
#             "es:DescribeElasticsearchDomainConfig"
#           ]
#           Resource = "${module.opensearch.domain_arn}/*" # Grant access to all indices/resources in the domain
#         }
#       ]
#     })
#   ]

#   policy_description = "Policy for AWS Glue with access to S3 buckets, OpenSearch, and Cloudwatch Logs"
#   role_description   = "Role for AWS Glue with access to S3 buckets, OpenSearch, and Cloudwatch Logs"

# }

module "iam_role_for_glue_jobs" {
  source  = "cloudposse/iam-role/aws"
  version = "0.16.2"

  principals = {
    "Service" = ["glue.amazonaws.com"]
  }
  name        = "logging-infra" 

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
  ]

  # Define custom inline policies here
  policy_documents = [
    jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
        Effect   = "Allow"
        Action   = [
          "secretsmanager:GetSecretValue",
          # Potentially other secretsmanager actions if needed, e.g., "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.logging_infra_secret.arn # Grants access to your specific secret
        },
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:ListBucket"
          ]
          Resource = [
            "arn:aws:s3:::${local.logging_bucket_name}",
            "arn:aws:s3:::${local.logging_bucket_name}/*"
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:ListBucket",
            "s3:PutObject",
            "s3:DeleteObject"
          ]
          Resource = [
            "arn:aws:s3:::${local.athena_results_store_bucket_name}",
            "arn:aws:s3:::${local.athena_results_store_bucket_name}/*"
          ]
        },


        { 
          Effect = "Allow"
          Action = [
            "es:ESHttpPost",
            "es:ESHttpPut",
            "es:ESHttpGet",
            "es:DescribeElasticsearchDomains",
            "es:DescribeElasticsearchDomainConfig"
          ]
          Resource = "${module.opensearch.domain_arn}/*" 
        },
        # { # ADD THIS BLOCK: Permissions to access the OpenSearch secret in Secrets Manager
        #   Effect = "Allow"
        #   Action = [
        #     "secretsmanager:GetSecretValue",
        #     "secretsmanager:DescribeSecret" # DescribeSecret is often useful for debugging/metadata
        #   ]
        #   Resource = module.secrets_manager_opensearch_secret.arn # Assuming you have a module for Secrets Manager
        # }
      ]
    })
  ]

  policy_description = "Policy for AWS Glue with access to S3 buckets, OpenSearch, and Cloudwatch Logs"
  role_description   = "Role for AWS Glue with access to S3 buckets, OpenSearch, and Cloudwatch Logs"

}