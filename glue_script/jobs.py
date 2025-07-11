import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue import DynamicFrame

# --- 1. Resolve Job Arguments ---
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'SOURCE_S3_PATH',          # This argument will now be passed dynamically from Step Functions
    'OPENSEARCH_ENDPOINT',
    'OPENSEARCH_INDEX',
    'OPENSEARCH_CONNECTION_NAME'
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# --- 2. Read from S3 Source ---
AmazonS3_node = glueContext.create_dynamic_frame.from_options(
    format_options={"multiLine": "false"},
    connection_type="s3",
    format="json",
    connection_options={"paths": [args['SOURCE_S3_PATH']], "recurse": True},
    transformation_ctx="AmazonS3_node"
)

# --- 3. (No Transformations) ---
output_frame = AmazonS3_node

# --- 4. Write to Amazon OpenSearch Service ---
AmazonOpenSearchService_node = glueContext.write_dynamic_frame.from_options(
    frame=output_frame,
    connection_type="opensearch",
    connection_options={
        "connectionName": args['OPENSEARCH_CONNECTION_NAME'],
        "opensearch.nodes": args['OPENSEARCH_ENDPOINT'],
        "opensearch.index": args['OPENSEARCH_INDEX'],
        "opensearch.resource": args['OPENSEARCH_INDEX'],
        "opensearch.nodes.wan.only": "true",
        "opensearch.aws.sigv4.enabled": "true",
        "opensearch.port": "443",
    },
    transformation_ctx="AmazonOpenSearchService_node"
)

job.commit()