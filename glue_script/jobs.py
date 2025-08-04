import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue import DynamicFrame

# --- 1. Resolve Job Arguments ---
# NEW CHANGE: Provide argument names to getResolvedOptions *without any hyphens*.
# This is to account for getResolvedOptions internally prepending a '--'.
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'TempDir'])
print(f"DEBUG_SYS_ARGV: {sys.argv}") # This will show actual arguments passed to the script!
print(f"DEBUG1_RESOLVED_OPTIONS_ARGS: {args}") # This will show what getResolvedOptions successfully found

# Manually parse custom arguments from sys.argv
# This part assumes they are passed as "KEY VALUE" pairs without leading '--'
custom_args = {}
i = 0
while i < len(sys.argv):
    arg = sys.argv[i]
    # Check for your custom argument keys (without '--' prefix)
    if arg == "SOURCE_S3_PATH" and i + 1 < len(sys.argv):
        custom_args['SOURCE_S3_PATH'] = sys.argv[i+1]
        i += 1
    elif arg == "OPENSEARCH_ENDPOINT" and i + 1 < len(sys.argv):
        custom_args['OPENSEARCH_ENDPOINT'] = sys.argv[i+1]
        i += 1
    elif arg == "OPENSEARCH_INDEX" and i + 1 < len(sys.argv):
        custom_args['OPENSEARCH_INDEX'] = sys.argv[i+1]
        i += 1
    elif arg == "OPENSEARCH_CONNECTION_NAME" and i + 1 < len(sys.argv):
        custom_args['OPENSEARCH_CONNECTION_NAME'] = sys.argv[i+1]
        i += 1
    i += 1

# Merge the arguments from getResolvedOptions and manual parsing
# NOTE: If getResolvedOptions is successful, it returns keys *without* the '--' prefix.
resolved_args = {**args, **custom_args}

print(f"DEBUG2_MERGED_RESOLVED_ARGS: {resolved_args}")

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)

# Access JOB_NAME without the '--' prefix, as getResolvedOptions should now return it this way
job.init(resolved_args['JOB_NAME'], resolved_args)

# --- 2. Read from S3 Source ---
AmazonS3_node = glueContext.create_dynamic_frame.from_options(
    format_options={"multiLine": "false"},
    connection_type="s3",
    format="json",
    # Access SOURCE_S3_PATH directly (from manual parsing or if getResolvedOptions suddenly works)
    connection_options={"paths": [resolved_args['SOURCE_S3_PATH']], "recurse": True},
    transformation_ctx="AmazonS3_node"
)

# --- 3. (No Transformations) ---
output_frame = AmazonS3_node

# --- 4. Write to Amazon OpenSearch Service ---
AmazonOpenSearchService_node = glueContext.write_dynamic_frame.from_options(
    frame=output_frame,
    connection_type="opensearch",
    connection_options={
        # Access OpenSearch connection options directly (from manual parsing)
        "connectionName": resolved_args['OPENSEARCH_CONNECTION_NAME'],
        "opensearch.nodes": resolved_args['OPENSEARCH_ENDPOINT'],
        "opensearch.index": resolved_args['OPENSEARCH_INDEX'],
        "opensearch.resource": resolved_args['OPENSEARCH_INDEX'],
        "opensearch.nodes.wan.only": "true",
        "opensearch.aws.sigv4.enabled": "true",
        "opensearch.port": "443",
    },
    transformation_ctx="AmazonOpenSearchService_node"
)
print(f"DEBUG3_OUTPUT_FRAME: {AmazonOpenSearchService_node}")
job.commit()

# import sys
# import json
# import boto3
# from opensearchpy import OpenSearch, RequestsHttpConnection # You'd need to package this library with your job
# from requests_aws4auth import AWS4Auth # You'd need to package this library

# from awsglue.utils import getResolvedOptions

# # --- 1. Resolve Job Arguments ---
# args = getResolvedOptions(sys.argv, [
#     'JOB_NAME',
#     'SOURCE_S3_PATH',
#     'OPENSEARCH_ENDPOINT',
#     'OPENSEARCH_INDEX',
#     'OPENSEARCH_CONNECTION_NAME' # Not strictly needed for direct HTTP, but good to keep consistent
# ])

# s3_client = boto3.client('s3')
# region = boto3.session.Session().region_name

# # OpenSearch client setup (simplified, you'll need more robust error handling and potentially host parsing)
# host = args['OPENSEARCH_ENDPOINT'] # e.g., 'your-domain.ap-south-1.es.amazonaws.com'
# auth = AWS4Auth(boto3.Session().get_credentials().access_key,
#                 boto3.Session().get_credentials().secret_key,
#                 region, 'es',
#                 session_token=boto3.Session().get_credentials().token)

# client = OpenSearch(
#     hosts=[{'host': host, 'port': 443}],
#     http_auth=auth,
#     use_ssl=True,
#     verify_certs=True,
#     connection_class=RequestsHttpConnection
# )

# # --- 2. Read from S3 Source and Process ---
# # This part would need to iterate through S3 objects based on SOURCE_S3_PATH
# # For simplicity, let's assume SOURCE_S3_PATH points directly to a file for this example
# # In a real scenario, you'd list objects in the prefix and read them.
# s3_path_parts = args['SOURCE_S3_PATH'].replace("s3://", "").split("/", 1)
# bucket_name = s3_path_parts[0]
# object_key = s3_path_parts[1]

# response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
# file_content = response['Body'].read().decode('utf-8')

# # Assuming each line is a JSON log
# logs = [json.loads(line) for line in file_content.strip().split('\n') if line.strip()]

# # --- 3. Write to Amazon OpenSearch Service ---
# for i, log_data in enumerate(logs):
#     # You might want to use a unique ID for each document, e.g., a timestamp + hash
#     document_id = f"{args['OPENSEARCH_INDEX']}-{i}" # Example ID
#     try:
#         response = client.index(
#             index=args['OPENSEARCH_INDEX'],
#             body=log_data,
#             id=document_id, # Optional: provide an ID or OpenSearch will generate one
#             refresh=True # For immediate visibility, but impacts performance
#         )
#         print(f"Indexed document {document_id}: {response}")
#     except Exception as e:
#         print(f"Error indexing document {document_data}: {e}")

# # No job.commit() equivalent needed for Python Shell

# print("Log transfer complete.")