terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_s3_object" "glue_job_script_upload" {
  bucket = module.s3_buckets["logging_bucket"].s3_bucket_id 
  key    = "glue_jobs_script/jobs.py"      
  source = "./glue_script/jobs.py" 
  etag = filemd5("./glue_script/jobs.py") 
  content_type = "text/x-python"
  depends_on = [
    module.s3_buckets["logging_bucket"]
  ]
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}

module "opensearch" {
  source  = "terraform-aws-modules/opensearch/aws"
  version = "1.7.0"

  domain_name     = local.opensearch_domain_name
  engine_version  = "OpenSearch_2.11"

  cluster_config = {
    instance_count        = 1
    instance_type         = "t2.small.search"
    dedicated_master_enabled = false
    zone_awareness_enabled   = false
  }

  ebs_options = {
    ebs_enabled = true
    volume_type = "gp2"
    volume_size = 10
  }

  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
  }

  encrypt_at_rest = {
    enabled = false
  }

  node_to_node_encryption = {
    enabled = false
  }

  domain_endpoint_options = {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }
  
  auto_tune_options = {
  desired_state = "DISABLED"
}

  advanced_security_options = {
    enabled                        = false
    internal_user_database_enabled = true
    anonymous_auth_enabled         = false

    # master_user_options = {
    #   master_user_name     = var.opensearch_master_user
    #   master_user_password = var.opensearch_master_pass
    # }
  }

  software_update_options = {
    auto_software_update_enabled = true
  }

  log_publishing_options = [
    { log_type = "INDEX_SLOW_LOGS" },
    { log_type = "SEARCH_SLOW_LOGS" },
  ]

  # access_policies = jsonencode({
  #   Version = "2012-10-17"
  #   Statement = [
  #     {
  #       Effect    = "Allow"
  #       Principal = "*"
  #       Action    = "es:*"
  #       Resource  = "arn:aws:es:${var.region}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain_name}/*"
  #       Condition = {
  #         IpAddress = {
  #           "aws:SourceIp" = "0.0.0.0/0"
  #         }
  #       }
  #     }
  #   ]
  # })
 access_policies = jsonencode({
  Version = "2012-10-17",
   Statement = [
      # Existing statement for the Root user
      {
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action = "es:*",
        Resource = "arn:aws:es:${var.region}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain_name}/*"
      },
      # *** THIS IS THE CRUCIAL NEW STATEMENT FOR YOUR GLUE JOB'S IAM ROLE ***
      {
        Effect = "Allow",
        Principal = {
          AWS = module.iam_role_for_glue_jobs.arn # <--- Use the ARN of your Glue Job's IAM role here
        },
        Action = [
          "es:ESHttp*", 
        ],
        Resource = "arn:aws:es:${var.region}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain_name}/*"
        # Optional: If you want to restrict access to only a specific index:
        # Resource = "arn:aws:es:${var.region}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain_name}/timestamp/*"
      }
    ]
})



  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
 

module "step-functions" {
  source  = "terraform-aws-modules/step-functions/aws"
  version = "2.5.2"
  name = "hfcl-athena-to-opensearch"

 definition = jsonencode(
  {
  "Comment": "A description of my state machine",
  "QueryLanguage": "JSONPath",
  "StartAt": "CheckTransferState",
  "States": {
    "CheckTransferState": {
      "Choices": [
        {
          "Next": "StartAthenaQuery",
          "StringEquals": "querySome",
          "Variable": "$.queryMode"
        },
        {
          "Next": "GlueStartJobRun",
          "StringEquals": "queryAll",
          "Variable": "$.queryMode"
        }
      ],
      "Default": "InvalidInputMode",
      "Type": "Choice"
    },
    "GlueStartJobRun": {
      "End": true,
      # "Parameters": {
      #   "JobName": "LogTransmitt", // <<-- IMPORTANT: Replace with the exact name of your Glue job (e.g., "LogTransmitt")
      #   "Arguments": {
      #     // Conditionally set --SOURCE_S3_PATH based on queryMode
      #     "SOURCE_S3_PATH": "States.If($.queryMode == 'querySome', $.AthenaQueryResult.QueryExecution.ResultConfiguration.OutputLocation, 's3://hfcl-logging-s3-bucket-5445463d/logs')",
      #     "OPENSEARCH_ENDPOINT": "${module.opensearch.domain_endpoint}", // <<-- Replace with your actual endpoint
      #     "OPENSEARCH_INDEX": "timestamp",           // <<-- Replace with your actual target index
      #     "OPENSEARCH_CONNECTION_NAME": "${resource.aws_glue_connection.opensearch_connection.name }"         // <<-- Your Glue Connection name
      #   }
      # },
      "Parameters": {
            // It's a good practice to map JobName from input as well if you're providing it in invocation
            "JobName.$": "$.JOB_NAME", // <--- CHANGE: Get JobName from Step Function input

            "Arguments": {
              // --- CHANGES HERE: Map arguments directly from Step Function input ---
              "SOURCE_S3_PATH.$": "$.SOURCE_S3_PATH",
              "OPENSEARCH_ENDPOINT.$": "$.OPENSEARCH_ENDPOINT",
              "OPENSEARCH_INDEX.$": "$.OPENSEARCH_INDEX",
              "OPENSEARCH_CONNECTION_NAME.$": "$.OPENSEARCH_CONNECTION_NAME"
              // If you have other static arguments for Glue, you can still add them here
              // e.g., "SOME_STATIC_ARGUMENT": "value"
            }
          },
      "Resource": "arn:aws:states:::glue:startJobRun.sync",
      "Type": "Task"
    },
    "InvalidInputMode": {
      "Cause": "Invalid queryMode specified in input. Must be 'querySome' or 'queryAll'.",
      "Error": "InvalidInput",
      "Type": "Fail"
    },
    "StartAthenaQuery": {
      "Next": "GlueStartJobRun", // Proceeds directly to GlueStartJobRun
      "Parameters": {
        "QueryString.$": "$.queryString",
        "WorkGroup": "primary"
      },
      "Resource": "arn:aws:states:::athena:startQueryExecution.sync",
      "Type": "Task",
      "ResultPath": "$.AthenaQueryResult" // <<-- CRITICAL: This is still needed to capture Athena's output
    }
  }
}
 )
 attach_policy_json = true
  create_role = true
  # policy_statements = local.policy_statements_for_step_function
  policy_json = local.step_functions_full_policy_json
  depends_on = [
    aws_glue_job.log_transmitt_glue_job,
    resource.aws_glue_connection.opensearch_connection
  ]
}

module "s3_buckets"{
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "4.8.0"
  force_destroy = true
  control_object_ownership = true
  object_ownership         = "ObjectWriter"
  acl    = "private"
  for_each = local.s3_bucket_required_variables 
  bucket = each.value.bucket_name
  policy = jsonencode(each.value.policy)
}


module "aws-athena" {
  source  = "Adaptavist/aws-athena/module"
  version = "1.3.3"

  database_name             = var.athena_database_name
  bucket_name               = local.athena_results_store_bucket_name
  create_database           = true
  database_force_destroy    = true
  namespace                 = "athena-test-ns"
  stage                     = "dev"
  queries = {
    "create_logs_table" = "./athena/createTable/create_logs_table.sql"
    # Add more query files here if needed
  }
  depends_on = [
    module.s3_buckets["athena_results_bucket"]
  ]
}

resource "aws_secretsmanager_secret" "logging_infra_secret" {
  name = "logging-infra-secret"
}

resource "aws_secretsmanager_secret_version" "logging_infra_secret_version" {
  secret_id = aws_secretsmanager_secret.logging_infra_secret.id
  secret_string = jsonencode({
    "opensearch.net.http.auth.user" = var.opensearch_master_user
    "opensearch.net.http.auth.pass" = var.opensearch_master_pass
  })
}

resource "aws_glue_connection" "opensearch_connection" {
  name            = "opensearch-connection"
  connection_type = "OPENSEARCH"
  connection_properties = {
    SparkProperties = jsonencode({
      secretId                       = aws_secretsmanager_secret.logging_infra_secret.name
      "opensearch.nodes"             = module.opensearch.domain_endpoint
      "opensearch.port"              = "443"
      "opensearch.aws.sigv4.region"  = var.region
      "opensearch.nodes.wan.only"    = "true"
      "opensearch.aws.sigv4.enabled" = "true"
    })
  }
}

resource "aws_glue_job" "log_transmitt_glue_job" {
  name        = "LogTransmitt"
  description = "Glue ETL Job for processing logs via Spark to OpenSearch"
  role_arn    = module.iam_role_for_glue_jobs.arn

  glue_version      = "4.0"
  worker_type       = "Standard"
  number_of_workers = 2

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_object.glue_job_script_upload.bucket}/${aws_s3_object.glue_job_script_upload.key}"
    python_version  = 3
  }

  connections = [resource.aws_glue_connection.opensearch_connection.name]
  max_retries = 0
  timeout     = 10

  default_arguments = {
    "--TempDir": format("s3://%s/glue_tmp/", module.s3_buckets["logging_bucket"].s3_bucket_id),
  }

  tags = {
    Name        = "LogTransmitt"
    Environment = "dev"
  }

  depends_on = [
    aws_s3_object.glue_job_script_upload,
    aws_glue_connection.opensearch_connection,
    module.iam_role_for_glue_jobs
  ]
}