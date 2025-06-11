import boto3
import json

class LambdaHandler:
    def __init__(self):
        self.s3 = boto3.client('s3')
        self.bucket_name = "hfcl-logging-s3-bucket-7f896491"

    def __call__(self, event, context):
        try:
            # logs = self.fetch_logs(self.bucket_name, 'logs/today.log')
            log_files = self.list_log_files(self.bucket_name)
            print("log files:", log_files)
            return
            # return self.success_response({'logs': logs})
        except Exception as e:
            return self.error_response(str(e))

    def fetch_logs(self, bucket, key):
        log_files = self.list_log_files(self.bucket_name)

    def list_log_files(self, bucket_name, prefix='logs/'):
        paginator = self.s3.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=self.bucket_name, Prefix=prefix)
        all_logs = []
        
        for page in pages:
            for obj in page.get('Contents', []):
                
 
        return all_logs

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

# AWS Lambda expects this callable
handler = LambdaHandler()