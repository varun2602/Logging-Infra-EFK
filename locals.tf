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
  
}