"""
AWS Glue Job: Archive Old Data to S3
Moves data older than 10 years from Redshift to S3 Parquet
"""
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, year, current_date, date_sub
from datetime import datetime

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'REDSHIFT_CONNECTION', 'ARCHIVE_BUCKET'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

redshift_connection = args['REDSHIFT_CONNECTION']
archive_bucket = args['ARCHIVE_BUCKET']

# Calculate cutoff date (10 years ago)
cutoff_date = date_sub(current_date(), 3650)  # 10 years

# Archive F_Registration
registration_to_archive = glueContext.read.from_jdbc_conf(
    frame=None,
    catalog_connection=redshift_connection,
    connection_options={
        "dbtable": "dw.f_registration",
        "database": "rcvdw"
    },
    transformation_ctx="read_registration"
).toDF()

# Join with d_date to filter by date
d_date = glueContext.read.from_jdbc_conf(
    frame=None,
    catalog_connection=redshift_connection,
    connection_options={"dbtable": "dw.d_date", "database": "rcvdw"},
    transformation_ctx="read_d_date"
).toDF()

old_registrations = registration_to_archive.join(
    d_date,
    registration_to_archive.registration_date_key == d_date.date_key,
    'inner'
).filter(col('date_value') < cutoff_date)

if old_registrations.count() > 0:
    # Write to S3 as Parquet (partitioned by year/month)
    old_registrations = old_registrations.withColumn('archive_year', year(col('date_value')))
    
    old_registrations.write \
        .mode('append') \
        .partitionBy('archive_year') \
        .parquet(f"s3://{archive_bucket}/archive/f_registration/")
    
    # Delete from Redshift
    registration_keys = [str(row.registration_key) for row in old_registrations.select('registration_key').collect()]
    
    if registration_keys:
        delete_sql = f"""
        DELETE FROM dw.f_registration
        WHERE registration_key IN ({','.join(registration_keys)})
        """
        
        import boto3
        redshift_data = boto3.client('redshift-data')
        redshift_data.execute_statement(
            ClusterIdentifier='rcv-dw-dev',
            Database='rcvdw',
            Sql=delete_sql
        )
    
    print(f"Archived {old_registrations.count()} registration records")

# Repeat for F_Compliance and F_Verification
# ... (similar logic)

# Create Glue Catalog table for archived data
spark.sql(f"""
CREATE EXTERNAL TABLE IF NOT EXISTS rcv_archive.f_registration_archive (
    registration_key BIGINT,
    registration_id STRING,
    registration_date_key INT,
    -- ... all columns
)
PARTITIONED BY (archive_year INT)
STORED AS PARQUET
LOCATION 's3://{archive_bucket}/archive/f_registration/'
""")

# Run MSCK REPAIR to add partitions
spark.sql("MSCK REPAIR TABLE rcv_archive.f_registration_archive")

job.commit()
