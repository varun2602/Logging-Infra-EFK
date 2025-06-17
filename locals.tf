locals {  
  opensearch_domain_name = "hfcl-logging-domain" 
  athena_results_store_bucket_name = "${var.athena_results_store_bucket_name}-${random_id.suffix.hex}"
  logging_bucket_name              = "${var.logging_bucket_name}-${random_id.suffix.hex}"
   s3_bucket_required_variables = {
    "athena_results_bucket" = {
      bucket_name = local.athena_results_store_bucket_name
      policy = {
        Version = "2012-10-17",
        Statement = [
          {
            Effect = "Allow",
            Action = [
              "s3:ListBucket"
            ],
            Resource = "arn:aws:s3:::${local.athena_results_store_bucket_name}"
          },
          {
            Effect = "Allow",
            Action = [
              "s3:GetObject"
            ],
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
            Effect = "Allow",
            Action = [
              "s3:ListBucket"
            ],
            Resource = "arn:aws:s3:::${local.logging_bucket_name}"
          },
          {
            Effect = "Allow",
            Action = [
              "s3:GetObject"
            ],
            Resource = "arn:aws:s3:::${local.logging_bucket_name}/*"
          }
         
        ]
      }
    }
  }
  lambda_params = {
    lambda_opensearch_transfer_params = {
       "function_name" = "${var.lambda_opensearch_transfer_name}"
       "source_path" = "${var.lambda_opensearch_transfer_source_path}"
       policy = {
          "Version": "2012-10-17",
          "Statement": [
              {
                  "Effect": "Allow",
                  "Action": [
                      "logs:CreateLogGroup",
                      "logs:CreateLogStream",
                      "logs:PutLogEvents"
                  ],
                  "Resource": "arn:aws:logs:ap-south-1:957833998600:log-group:/aws/lambda/transfer-to-opensearch:*"
                  // IMPORTANT: Replace YOUR_REGION, YOUR_ACCOUNT_ID, and YOUR_LAMBDA_FUNCTION_NAME
                  // Example: "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/my-transfer-lambda:*"
              }
          ]
      }
    }
    lambda_athena_query_params = {
      "function_name" = var.lambda_athena_query_name
      "source_path" = "${var.lambda_athena_query_source_path}" 
       policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "athena:StartQueryExecution",
                    "athena:GetQueryExecution",
                    "athena:GetQueryResults",
                    "athena:StopQueryExecution",
                    "athena:GetWorkGroup" 
                ],
                "Resource": [
        "arn:aws:athena:ap-south-1:957833998600:workgroup/primary",
        "arn:aws:athena:ap-south-1:957833998600:workgroup/primary"
     
    ]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:PutObject",
                    "s3:GetObject",
                    "s3:ListBucket",
                    "s3:DeleteObject", 
                    "s3:GetBucketLocation" 
                ],
                "Resource": [
                    "arn:aws:s3:::athena-results-store-bucket-5445463d/*", 
                    "arn:aws:s3:::athena-results-store-bucket-5445463d"    
                ]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:ListBucket",       
                    "s3:GetObject"           
                ],
                "Resource": [
                    "arn:aws:s3:::hfcl-logging-s3-bucket-5445463d/*", 
                    "arn:aws:s3:::hfcl-logging-s3-bucket-5445463d"    
                ]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "glue:GetDatabase",
                    "glue:GetTable",
                    "glue:GetPartitions"
                ],
                "Resource": "*" 
            }
        ]
    }
    }
  }
}