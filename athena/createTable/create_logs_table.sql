CREATE EXTERNAL TABLE logs (
  `timestamp` string,
  `level` string,
  `message` string,
  `partition_0` string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
  'ignore.malformed.json' = 'true'
)
LOCATION 's3://hfcl-logging-s3-bucket-5445463d/logs/'
TBLPROPERTIES ('classification' = 'json');