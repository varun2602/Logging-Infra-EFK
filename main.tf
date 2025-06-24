terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
 data "aws_caller_identity" "current" {
    
}

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

  definition = jsonencode({
    StartAt = "FailState",
    States = {
    {
  "Comment": "A description of my state machine",
  "StartAt": "Choice",
  "States": {
    "Choice": {
      "Type": "Choice",
      "Choices": [
        {
          "Next": "Lambda Invoke"
        },
        {
          "Next": "Glue StartJobRun"
        }
      ]
    },
    "Lambda Invoke": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Output": "{% $states.result.Payload %}",
      "Arguments": {
        "FunctionName": "",
        "Payload": {
          "dataScale": "",
          "key2": "{% $states.input.key %}",
          "key3": 100
        }
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.TooManyRequestsException"
          ],
          "IntervalSeconds": 1,
          "MaxAttempts": 3,
          "BackoffRate": 2,
          "JitterStrategy": "FULL"
        }
      ],
      "Next": "Glue StartJobRun"
    },
    "Glue StartJobRun": {
      "Type": "Task",
      "Resource": "arn:aws:states:::glue:startJobRun",
      "Arguments": {
        "JobName": "myJobName"
      },
      "End": true
    }
  },
  "QueryLanguage": "JSONata"
}
    }
  })

  attach_policy_statements = true
  policy_statements = [
    {
      effect = "Allow"
      actions = ["lambda:InvokeFunction"]
      resources = [
        module.lambda_athena_query.lambda_function_arn,
            
      ]
    }
  ]

  create_role = true
  depends_on = [
    module.lambda_athena_query,
    module.glue
  ]
}

module "lambda_athena_query" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "7.20.2"

  function_name = "lambda-athena-query"
  runtime       = "python3.12"
  handler       = "main.handler"
  source_path = "./lambda/lambda_athena_query"
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

module "glue" {
  source  = "cloudposse/glue/aws"
  version = "0.4.0"
}