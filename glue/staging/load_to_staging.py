"""
AWS Glue Job: Load Raw Data to Redshift Staging
Loads data from S3 raw landing zone into Redshift staging tables
"""
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql.functions import current_timestamp, lit, col
import boto3

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'REDSHIFT_CONNECTION', 'S3_RAW_BUCKET', 'TABLE_NAME'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Parameters
redshift_connection = args['REDSHIFT_CONNECTION']
s3_raw_bucket = args['S3_RAW_BUCKET']
table_name = args['TABLE_NAME']  # registration, compliance, verification

# Read from S3 raw landing
s3_path = f"s3://{s3_raw_bucket}/raw/{table_name}/"
raw_df = spark.read.parquet(s3_path)

# Add metadata columns
staging_df = raw_df \
    .withColumn("load_timestamp", current_timestamp()) \
    .withColumn("processing_status", lit("PENDING")) \
    .withColumn("dq_is_valid", lit(True))

# Convert to DynamicFrame
staging_dynamic = DynamicFrame.fromDF(staging_df, glueContext, "staging_dynamic")

# Write to Redshift staging
glueContext.write_dynamic_frame.from_jdbc_conf(
    frame=staging_dynamic,
    catalog_connection=redshift_connection,
    connection_options={
        "dbtable": f"staging.stg_{table_name}",
        "database": "rcvdw",
        "preactions": f"TRUNCATE TABLE staging.stg_{table_name};"
    },
    redshift_tmp_dir=f"s3://{s3_raw_bucket}/temp/",
    transformation_ctx="redshift_write"
)

# Log metrics
record_count = staging_df.count()
print(f"Loaded {record_count} records to staging.stg_{table_name}")

job.commit()
