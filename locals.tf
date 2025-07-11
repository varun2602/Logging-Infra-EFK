locals {
  opensearch_domain_name           = "hfcl-logging-domain"
  athena_results_store_bucket_name = "${var.athena_results_store_bucket_name}-${random_id.suffix.hex}"
  logging_bucket_name              = "${var.logging_bucket_name}-${random_id.suffix.hex}"

  s3_bucket_required_variables = {
    "athena_results_bucket" = {
      bucket_name = local.athena_results_store_bucket_name
      policy = {
        Version = "2012-10-17",
        Statement = [
          {
            Effect   = "Allow",
            Action   = ["s3:ListBucket", "s3:GetBucketLocation"],
            Resource = "arn:aws:s3:::${local.athena_results_store_bucket_name}"
          },
          {
            Effect   = "Allow",
            Action   = ["s3:GetObject", "s3:PutObject"],
            Resource = "arn:aws:s3:::${local.athena_results_store_bucket_name}/*"
          }
        ]
      }
    },
    "logging_bucket" = {
      bucket_name = local.logging_bucket_name
      policy = {
        Version = "2012-10-17",
        Statement = [
          {
            Effect   = "Allow",
            Action   = ["s3:ListBucket", "s3:GetBucketLocation"],
            Resource = "arn:aws:s3:::${local.logging_bucket_name}"
          },
          {
            Effect   = "Allow",
            Action   = ["s3:GetObject", "s3:PutObject"],
            Resource = "arn:aws:s3:::${local.logging_bucket_name}/*"
          }
        ]
      }
    }
  }

  policy_statements_for_step_function = {
    # 1. Permission to start the Glue Job
    start_glue_job = {
      Action   = ["glue:StartJobRun"] # <-- CHANGED TO Action
      Resource = ["arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:job/LogTransmitt"] # <-- CHANGED TO Resource
      Effect   = "Allow" # <-- CHANGED TO Effect
    }
    # 2. Permissions for Athena Query Execution (if using 'querySome' path)
    athena_query = {
      Action = [ # <-- CHANGED TO Action
        "athena:StartQueryExecution",
        "athena:GetQueryExecution",
        "athena:GetQueryResults",
        "athena:StopQueryExecution",
        "athena:GetWorkGroup"
      ]
      Resource = [ # <-- CHANGED TO Resource
        "arn:aws:athena:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:workgroup/primary",
      ]
      Effect   = "Allow" # <-- CHANGED TO Effect
    }
    # 3. Permissions for S3 access (Athena results and Glue source/target data)
    s3_access = {
      Action = [ # <-- CHANGED TO Action
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject",
        "s3:GetBucketLocation"
      ]
      Resource = [ # <-- CHANGED TO Resource
        "arn:aws:s3:::athena-results-store-bucket-5445463d",
        "arn:aws:s3:::athena-results-store-bucket-5445463d/*",
        "arn:aws:s3:::hfcl-logging-s3-bucket-5445463d",
        "arn:aws:s3:::hfcl-logging-s3-bucket-5445463d/*",
      ]
      Effect   = "Allow" # <-- CHANGED TO Effect
    }
    # 4. Permissions for Glue Data Catalog (Athena and Glue depend on this)
    glue_data_catalog = {
      Action = [ # <-- CHANGED TO Action
        "glue:GetDatabase",
        "glue:GetTable",
        "glue:GetPartitions",
        "glue:GetConnection",
        "glue:GetJob",
      ]
      Resource = [ # <-- CHANGED TO Resource
        "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog",
        "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/*",
        "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/*/*",
        "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:connection/*"
      ]
      Effect   = "Allow" # <-- CHANGED TO Effect
    }
    # 5. Permissions for CloudWatch Logs (for Step Functions execution logs)
    cloudwatch_logs = {
      Action = [ # <-- CHANGED TO Action
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/step-functions/hfcl-athena-to-opensearch:*"] # <-- CHANGED TO Resource
      Effect   = "Allow" # <-- CHANGED TO Effect
    }
  }

  step_functions_full_policy_json = jsonencode({
    Version   = "2012-10-17",
    Statement = values(local.policy_statements_for_step_function)
  })
}
