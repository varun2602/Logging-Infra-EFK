import boto3
import json
import time # Needed for polling Athena query status

class LambdaHandler:
    def __init__(self):
        # Initialize the Athena client
        self.athena_client = boto3.client('athena')
        # We still need the S3 client to read the *results* of the Athena query
        self.s3_client = boto3.client('s3')

        # --- Athena Configuration ---
        # IMPORTANT: Replace these with your actual Athena database and table names.
        # These should align with your Athena setup (e.g., from your Terraform).
        self.athena_database_name = "athenaqueryresults"  # e.g., "hfcl_logs_db"
        self.athena_table_name = "logs"         # e.g., "app_logs_table"

        # This is the S3 bucket where Athena will write its query results.
        # It must be accessible by Athena (via its workgroup or service role)
        # and readable by this Lambda function's IAM role.
        # Ensure this bucket is different from your raw log storage bucket.
        self.athena_query_results_bucket = "athena-results-store-bucket-5445463d" # <--- Update with your actual Athena results bucket
        self.athena_output_location = f"s3://{self.athena_query_results_bucket}/athena_query_output/"

        self.query_timeout_seconds = 900 # Max time to wait for Athena query to complete (adjust as needed)

    def __call__(self, event, context):
        """
        The main Lambda handler function.
        """
        try:
            # Example: Fetching the last 10 log entries.
            # You can customize this query based on 'event' input, e.g.,
            # query_string = f"SELECT * FROM {self.athena_table_name} WHERE date = '{event['date']}' LIMIT 10;"
            query_string = f"SELECT * FROM {self.athena_table_name};"

            print(f"Executing Athena query: {query_string}")
            query_results = self.execute_athena_query(query_string)
            print(f"Athena query returned {len(query_results)} rows.")

            return self.success_response({'query_results': query_results})

        except Exception as e:
            print(f"Error in Lambda execution: {e}")
            return self.error_response(f"Failed to fetch logs via Athena: {str(e)}")

    def execute_athena_query(self, query):
        """
        Starts an Athena query, polls for its completion, and retrieves results.
        """
        try:
            # 1. Start the query execution
            response = self.athena_client.start_query_execution(
                QueryString=query,
                QueryExecutionContext={
                    'Database': self.athena_database_name
                },
                ResultConfiguration={
                    'OutputLocation': self.athena_output_location
                }
            )
            query_execution_id = response['QueryExecutionId']
            print(f"Started Athena query with ID: {query_execution_id}")

            # 2. Poll for query completion
            status = 'RUNNING'
            max_attempts = int(self.query_timeout_seconds / 5) # Check status every 5 seconds
            attempts = 0

            while status in ['RUNNING', 'QUEUED'] and attempts < max_attempts:
                attempts += 1
                time.sleep(5) # Wait before checking status again

                query_status_response = self.athena_client.get_query_execution(
                    QueryExecutionId=query_execution_id
                )
                status = query_status_response['QueryExecution']['Status']['State']
                print(f"Query ID: {query_execution_id}, Status: {status}")

                if status == 'FAILED':
                    failure_reason = query_status_response['QueryExecution']['Status'].get('StateChangeReason', 'Unknown reason')
                    raise Exception(f"Athena query failed: {failure_reason}")
                elif status == 'SUCCEEDED':
                    break

            if status not in ['SUCCEEDED']:
                raise Exception(f"Athena query timed out or did not succeed. Final status: {status}")

            # 3. Get query results
            results_response = self.athena_client.get_query_results(
                QueryExecutionId=query_execution_id
            )

            # 4. Parse the results
            rows = results_response['ResultSet']['Rows']
            if not rows or len(rows) <= 1: # Check for no rows or only header row
                return []

            # The first row contains the column names
            column_names = [col['VarCharValue'] for col in rows[0]['Data']]

            # Remaining rows contain the actual data
            data = []
            for row in rows[1:]: # Skip the header row
                row_data = [col.get('VarCharValue', None) for col in row['Data']]
                # Ensure row_data length matches column_names length in case of partial data
                if len(row_data) == len(column_names):
                    data.append(dict(zip(column_names, row_data)))
                else:
                    print(f"Warning: Skipping row due to column mismatch: {row_data}")
            print("data test", data)
            return data

        except Exception as e:
            # Re-raise with more context
            raise Exception(f"Error in execute_athena_query: {e}")

    def success_response(self, data):
        return {
            'statusCode': 200,
            'body': json.dumps(data)
        }

    def error_response(self, message):
        return {
            'statusCode': 500,
            'body': json.dumps({'error': message})
        }

# AWS Lambda expects this callable to be named 'handler'
handler = LambdaHandler()