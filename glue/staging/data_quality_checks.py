"""
AWS Glue Job: Data Quality Checks
Validates data in staging tables before transformation
"""
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, count, when, isnan, isnull, current_timestamp
from datetime import datetime

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'REDSHIFT_CONNECTION', 'TABLE_NAME'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

redshift_connection = args['REDSHIFT_CONNECTION']
table_name = args['TABLE_NAME']

# Read from staging
staging_df = glueContext.read.from_jdbc_conf(
    frame=None,
    catalog_connection=redshift_connection,
    connection_options={
        "dbtable": f"staging.stg_{table_name}",
        "database": "rcvdw"
    },
    transformation_ctx="read_staging"
).toDF()

total_records = staging_df.count()
dq_results = []

# DQ Check 1: Completeness - Required fields not null
if table_name == 'registration':
    required_fields = ['registration_id', 'registration_date', 'registration_status']
elif table_name == 'compliance':
    required_fields = ['compliance_id', 'compliance_date', 'compliance_status']
else:  # verification
    required_fields = ['verification_id', 'verification_date', 'verification_status']

for field in required_fields:
    null_count = staging_df.filter(col(field).isNull()).count()
    pass_rate = ((total_records - null_count) / total_records * 100) if total_records > 0 else 0
    
    dq_results.append({
        'table_name': f'staging.stg_{table_name}',
        'check_name': f'{field}_not_null',
        'check_type': 'COMPLETENESS',
        'records_checked': total_records,
        'records_passed': total_records - null_count,
        'records_failed': null_count,
        'pass_rate': pass_rate,
        'threshold': 100.0,
        'status': 'PASS' if pass_rate == 100 else 'FAIL'
    })

# DQ Check 2: Validity - Date ranges
date_field = f'{table_name}_date'
invalid_dates = staging_df.filter(
    (col(date_field) < '1900-01-01') | (col(date_field) > current_timestamp())
).count()
pass_rate = ((total_records - invalid_dates) / total_records * 100) if total_records > 0 else 0

dq_results.append({
    'table_name': f'staging.stg_{table_name}',
    'check_name': f'{date_field}_valid_range',
    'check_type': 'VALIDITY',
    'records_checked': total_records,
    'records_passed': total_records - invalid_dates,
    'records_failed': invalid_dates,
    'pass_rate': pass_rate,
    'threshold': 99.0,
    'status': 'PASS' if pass_rate >= 99 else 'FAIL'
})

# DQ Check 3: Consistency - Duplicate IDs
id_field = f'{table_name}_id'
duplicate_count = staging_df.groupBy(id_field).count().filter(col('count') > 1).count()
pass_rate = ((total_records - duplicate_count) / total_records * 100) if total_records > 0 else 0

dq_results.append({
    'table_name': f'staging.stg_{table_name}',
    'check_name': f'{id_field}_unique',
    'check_type': 'CONSISTENCY',
    'records_checked': total_records,
    'records_passed': total_records - duplicate_count,
    'records_failed': duplicate_count,
    'pass_rate': pass_rate,
    'threshold': 100.0,
    'status': 'PASS' if pass_rate == 100 else 'FAIL'
})

# Write DQ results to control table
dq_df = spark.createDataFrame(dq_results)
dq_df = dq_df.withColumn('check_timestamp', current_timestamp())

dq_dynamic = DynamicFrame.fromDF(dq_df, glueContext, "dq_dynamic")
glueContext.write_dynamic_frame.from_jdbc_conf(
    frame=dq_dynamic,
    catalog_connection=redshift_connection,
    connection_options={
        "dbtable": "staging.dq_results",
        "database": "rcvdw"
    },
    transformation_ctx="write_dq_results"
)

# Update staging records with DQ flags
failed_checks = [r for r in dq_results if r['status'] == 'FAIL']
if failed_checks:
    print(f"WARNING: {len(failed_checks)} DQ checks failed")
    for check in failed_checks:
        print(f"  - {check['check_name']}: {check['pass_rate']:.2f}% pass rate")

job.commit()
