"""
AWS Glue Job: Load Fact Tables
Loads fact tables with surrogate key lookups and incremental logic
"""
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, current_timestamp, lit, md5, concat_ws, to_date
from pyspark.sql import functions as F

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'REDSHIFT_CONNECTION', 'LOAD_TYPE'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

redshift_connection = args['REDSHIFT_CONNECTION']
load_type = args['LOAD_TYPE']  # INITIAL or INCREMENTAL

# Read staging data
staging_registration = glueContext.read.from_jdbc_conf(
    frame=None,
    catalog_connection=redshift_connection,
    connection_options={
        "dbtable": "staging.stg_registration",
        "database": "rcvdw"
    },
    transformation_ctx="read_staging"
).toDF()

# Filter only valid records
staging_registration = staging_registration.filter(col('dq_is_valid') == True)

# Read dimensions for surrogate key lookups
d_date = glueContext.read.from_jdbc_conf(
    frame=None,
    catalog_connection=redshift_connection,
    connection_options={"dbtable": "dw.d_date", "database": "rcvdw"},
    transformation_ctx="read_d_date"
).toDF()

d_code = glueContext.read.from_jdbc_conf(
    frame=None,
    catalog_connection=redshift_connection,
    connection_options={"dbtable": "dw.d_code", "database": "rcvdw"},
    transformation_ctx="read_d_code"
).toDF().filter(col('is_active') == True)

d_zipcode = glueContext.read.from_jdbc_conf(
    frame=None,
    catalog_connection=redshift_connection,
    connection_options={"dbtable": "dw.d_zipcode", "database": "rcvdw"},
    transformation_ctx="read_d_zipcode"
).toDF().filter(col('is_active') == True)

d_state = glueContext.read.from_jdbc_conf(
    frame=None,
    catalog_connection=redshift_connection,
    connection_options={"dbtable": "dw.d_state", "database": "rcvdw"},
    transformation_ctx="read_d_state"
).toDF().filter(col('is_active') == True)

d_data_source = glueContext.read.from_jdbc_conf(
    frame=None,
    catalog_connection=redshift_connection,
    connection_options={"dbtable": "dw.d_data_source_configuration", "database": "rcvdw"},
    transformation_ctx="read_d_data_source"
).toDF().filter(col('is_active') == True)

d_file = glueContext.read.from_jdbc_conf(
    frame=None,
    catalog_connection=redshift_connection,
    connection_options={"dbtable": "dw.d_file_information", "database": "rcvdw"},
    transformation_ctx="read_d_file"
).toDF()

# Lookup surrogate keys
fact_df = staging_registration

# Date keys
fact_df = fact_df.join(
    d_date.select(col('date_key').alias('registration_date_key'), col('date_value')),
    to_date(fact_df.registration_date) == d_date.date_value,
    'left'
).drop('date_value')

fact_df = fact_df.join(
    d_date.select(col('date_key').alias('birth_date_key'), col('date_value')),
    to_date(fact_df.birth_date) == d_date.date_value,
    'left'
).drop('date_value')

# Code keys
d_code_status = d_code.filter(col('code_value') == 'registration_status')
fact_df = fact_df.join(
    d_code_status.select(col('code_key').alias('registration_status_code_key'), col('code_value')),
    fact_df.registration_status == d_code_status.code_value,
    'left'
).drop('code_value')

# Geography keys
fact_df = fact_df.join(
    d_zipcode.select(col('zipcode_key'), col('zipcode')),
    fact_df.zipcode == d_zipcode.zipcode,
    'left'
).drop('zipcode')

fact_df = fact_df.join(
    d_state.select(col('state_key'), col('state_code')),
    fact_df.state == d_state.state_code,
    'left'
).drop('state_code')

# Data source and file keys
fact_df = fact_df.join(
    d_data_source.select(col('data_source_key'), col('source_name')),
    fact_df.source_system == d_data_source.source_name,
    'left'
).drop('source_name')

fact_df = fact_df.join(
    d_file.select(col('file_key'), col('file_name')),
    fact_df.source_file_name == d_file.file_name,
    'left'
).drop('file_name')

# Select final fact columns (NO PII)
fact_registration = fact_df.select(
    col('registration_id'),
    col('registration_date_key'),
    col('birth_date_key'),
    col('registration_status_code_key'),
    col('registration_type_code_key'),
    col('zipcode_key'),
    col('state_key'),
    col('data_source_key'),
    col('file_key'),
    F.year(col('registration_date')).alias('age_at_registration'),  # Calculate age
    col('registration_method'),
    lit(True).alias('is_first_time_registration'),
    lit(0).alias('previous_registration_count'),
    col('source_system').alias('source_system_id'),
    md5(concat_ws('|', col('registration_id'), col('registration_status'))).alias('record_hash')
).withColumn('created_dt', current_timestamp()) \
 .withColumn('updated_dt', current_timestamp())

# Incremental load logic
if load_type == 'INCREMENTAL':
    # Read existing fact
    existing_fact = glueContext.read.from_jdbc_conf(
        frame=None,
        catalog_connection=redshift_connection,
        connection_options={"dbtable": "dw.f_registration", "database": "rcvdw"},
        transformation_ctx="read_existing_fact"
    ).toDF()
    
    # Identify new records
    new_records = fact_registration.join(
        existing_fact.select('registration_id'),
        'registration_id',
        'left_anti'
    )
    
    # Identify changed records for history
    changed_records = fact_registration.join(
        existing_fact.select('registration_id', 'record_hash'),
        'registration_id',
        'inner'
    ).filter(fact_registration.record_hash != existing_fact.record_hash)
    
    fact_to_load = new_records
    
    # Insert changed records to history table
    if changed_records.count() > 0:
        hist_df = changed_records.withColumn('snapshot_date_key', lit(20260119)) \
            .withColumn('change_type', lit('UPDATE')) \
            .withColumn('effective_start_dt', current_timestamp()) \
            .withColumn('is_current', lit(True))
        
        hist_dynamic = DynamicFrame.fromDF(hist_df, glueContext, "hist_dynamic")
        glueContext.write_dynamic_frame.from_jdbc_conf(
            frame=hist_dynamic,
            catalog_connection=redshift_connection,
            connection_options={"dbtable": "dw.f_registration_hist", "database": "rcvdw"},
            transformation_ctx="write_history"
        )
else:
    fact_to_load = fact_registration

# Write to fact table
if fact_to_load.count() > 0:
    fact_dynamic = DynamicFrame.fromDF(fact_to_load, glueContext, "fact_dynamic")
    glueContext.write_dynamic_frame.from_jdbc_conf(
        frame=fact_dynamic,
        catalog_connection=redshift_connection,
        connection_options={"dbtable": "dw.f_registration", "database": "rcvdw"},
        transformation_ctx="write_fact"
    )
    
    print(f"Loaded {fact_to_load.count()} records to dw.f_registration")

job.commit()
