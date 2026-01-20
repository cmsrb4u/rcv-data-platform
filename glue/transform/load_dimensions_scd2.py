"""
AWS Glue Job: Transform and Load Dimensions (SCD Type 2)
Implements Slowly Changing Dimension Type 2 logic for dimension tables
"""
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, current_timestamp, lit, md5, concat_ws, when
from pyspark.sql.window import Window
from pyspark.sql import functions as F

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'REDSHIFT_CONNECTION'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

redshift_connection = args['REDSHIFT_CONNECTION']

def load_scd2_dimension(source_df, dim_table, natural_key, scd_columns):
    """
    Generic SCD Type 2 loader
    
    Args:
        source_df: Source DataFrame with new/updated records
        dim_table: Target dimension table name
        natural_key: Business key column(s)
        scd_columns: Columns to track for changes
    """
    
    # Read existing dimension
    existing_dim = glueContext.read.from_jdbc_conf(
        frame=None,
        catalog_connection=redshift_connection,
        connection_options={
            "dbtable": dim_table,
            "database": "rcvdw"
        },
        transformation_ctx=f"read_{dim_table}"
    ).toDF()
    
    # Get current active records
    current_records = existing_dim.filter(col('is_active') == True)
    
    # Create hash of SCD columns for change detection
    source_df = source_df.withColumn(
        'record_hash',
        md5(concat_ws('|', *[col(c) for c in scd_columns]))
    )
    
    current_records = current_records.withColumn(
        'current_hash',
        md5(concat_ws('|', *[col(c) for c in scd_columns]))
    )
    
    # Join to find changes
    joined = source_df.alias('src').join(
        current_records.alias('cur'),
        natural_key,
        'left_outer'
    )
    
    # Identify new records (no match in current)
    new_records = joined.filter(col('cur.' + natural_key[0]).isNull()) \
        .select('src.*') \
        .withColumn('effective_start_dt', current_timestamp()) \
        .withColumn('effective_end_dt', lit(None).cast('timestamp')) \
        .withColumn('is_active', lit(True))
    
    # Identify changed records (hash mismatch)
    changed_records = joined.filter(
        (col('cur.' + natural_key[0]).isNotNull()) &
        (col('record_hash') != col('current_hash'))
    )
    
    # Expire old versions
    expire_keys = changed_records.select('cur.' + dim_table.split('.')[1] + '_key').distinct()
    
    # Create new versions for changed records
    new_versions = changed_records.select('src.*') \
        .withColumn('effective_start_dt', current_timestamp()) \
        .withColumn('effective_end_dt', lit(None).cast('timestamp')) \
        .withColumn('is_active', lit(True))
    
    # Combine new and changed
    inserts = new_records.union(new_versions)
    
    return inserts, expire_keys

# Example: Load D_Code dimension
staging_codes = glueContext.read.from_jdbc_conf(
    frame=None,
    catalog_connection=redshift_connection,
    connection_options={
        "dbtable": "staging.stg_codes",  # Assume codes extracted to staging
        "database": "rcvdw"
    },
    transformation_ctx="read_staging_codes"
).toDF()

# Transform to dimension format
dim_code_df = staging_codes.select(
    col('code_id'),
    col('code_category_key'),
    col('code_value'),
    col('code_description'),
    col('display_order')
)

# Apply SCD2 logic
inserts, expire_keys = load_scd2_dimension(
    source_df=dim_code_df,
    dim_table='dw.d_code',
    natural_key=['code_id'],
    scd_columns=['code_value', 'code_description', 'code_category_key']
)

# Write new/changed records
if inserts.count() > 0:
    inserts_dynamic = DynamicFrame.fromDF(inserts, glueContext, "inserts_dynamic")
    glueContext.write_dynamic_frame.from_jdbc_conf(
        frame=inserts_dynamic,
        catalog_connection=redshift_connection,
        connection_options={
            "dbtable": "dw.d_code",
            "database": "rcvdw"
        },
        transformation_ctx="write_d_code_inserts"
    )

# Expire old records (run UPDATE via Redshift)
if expire_keys.count() > 0:
    expire_list = [str(row[0]) for row in expire_keys.collect()]
    expire_sql = f"""
    UPDATE dw.d_code
    SET effective_end_dt = GETDATE(),
        is_active = FALSE
    WHERE code_key IN ({','.join(expire_list)})
    AND is_active = TRUE
    """
    
    # Execute via Redshift Data API
    import boto3
    redshift_data = boto3.client('redshift-data')
    redshift_data.execute_statement(
        ClusterIdentifier='rcv-dw-dev',
        Database='rcvdw',
        Sql=expire_sql
    )

print(f"Loaded {inserts.count()} new/changed records to dw.d_code")

job.commit()
