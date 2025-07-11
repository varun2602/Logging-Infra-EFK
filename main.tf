terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_s3_object" "glue_job_script_upload" {
  bucket = module.s3_buckets["logging_bucket"].s3_bucket_id # The ID of your S3 bucket where logs/scripts go
  key    = "glue_jobs_script/jobs.py"             # The remote path and filename in S3
  source = "./glue_script/jobs.py"                             # The local path to your script file (assuming it's named glue.py locally)

  # Optional: Add an ETag to trigger updates if the file content changes
  etag = filemd5("./glue_script/jobs.py") # Use the MD5 hash of the local file content

  # Optional: Content type (often "application/x-python" or "text/x-python")
  content_type = "text/x-python"

  # Ensure the bucket is created before attempting to upload
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
    {
      Effect = "Allow",
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      Action = "es:*",
      Resource = "arn:aws:es:${var.region}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain_name}/*"
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
      "Parameters": {
        "JobName": "LogTransmitt", // <<-- IMPORTANT: Replace with the exact name of your Glue job (e.g., "LogTransmitt")
        "Arguments": {
          // Conditionally set --SOURCE_S3_PATH based on queryMode
          "SOURCE_S3_PATH": "States.If($.queryMode == 'querySome', $.AthenaQueryResult.QueryExecution.ResultConfiguration.OutputLocation, 's3://hfcl-logging-s3-bucket-5445463d/logs')",
          "OPENSEARCH_ENDPOINT": "${module.opensearch.domain_endpoint}", // <<-- Replace with your actual endpoint
          "OPENSEARCH_INDEX": "timestamp",           // <<-- Replace with your actual target index
          "OPENSEARCH_CONNECTION_NAME": "${resource.aws_glue_connection.opensearch_connection.name }"         // <<-- Your Glue Connection name
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
    module.glue_job,
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
  name = "example-secret"
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

module "glue_job" {
  source = "cloudposse/glue/aws//modules/glue-job"

  job_name        = "LogTransmitt"
  job_description = "Glue Job for processing geo data"
  role_arn        = module.iam_role_for_glue_jobs.arn
  glue_version    = "4.0"
  default_arguments = {}
  # Add the new OpenSearch connection to the Glue job
  connections     = ["opensearch-connection"]


  max_retries = 2
  timeout     = 2000

  command = {
    name          = "pythonshell" # <-- CHANGE THIS FROM "glueetl" to "pythonshell"
    script_location = format("s3://%s/glue_jobs_script/jobs.py", module.s3_buckets["logging_bucket"].s3_bucket_id)
    python_version  = 3
  }

  depends_on = [ resource.aws_glue_connection.opensearch_connection ]

}
