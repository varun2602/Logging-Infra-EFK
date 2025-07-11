# variables.tf
variable "opensearch_master_user" {
  type      = string
  sensitive = true
}

variable "opensearch_master_pass" {
  type      = string
  sensitive = true
}

variable "region" {
  type = string 
  sensitive = true
}

variable "athena_database_name"{
  type = string 
  sensitive = true
}


variable "athena_results_store_bucket_name" {
  type = string 
  sensitive = false
}

variable "logging_bucket_name" {
  type = string 
  sensitive = false
}
