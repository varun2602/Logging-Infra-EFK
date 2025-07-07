output "s3_buckets" {
  description = "URLs of S3 buckets"
  value = {
    for bucket_key, bucket_module in module.s3_buckets:
        bucket_key => "http://${bucket_module.s3_bucket_bucket_domain_name}"
  }
}
output "opensearch_id" {
  value = module.opensearch.domain_endpoint
}


output "athena_params" {
  description = "Athena parameters"
  value = module.aws-athena.database_name
  sensitive = true
}