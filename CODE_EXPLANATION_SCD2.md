# Detailed Explanation: load_dimensions_scd2.py

## Overview

This AWS Glue job implements **Slowly Changing Dimension (SCD) Type 2** logic for dimension tables in the data warehouse. SCD Type 2 tracks historical changes by creating new rows when data changes, preserving the complete history.

---

## What is SCD Type 2?

**Purpose:** Track historical changes in dimension data over time.

**Example Scenario:**
```
A registration status changes from "PENDING" to "ACTIVE"

BEFORE (1 row):
code_id | code_value | effective_start | effective_end | is_active
--------|------------|-----------------|---------------|----------
RS001   | PENDING    | 2025-01-01      | NULL          | TRUE

AFTER (2 rows - history preserved):
code_id | code_value | effective_start | effective_end | is_active
--------|------------|-----------------|---------------|----------
RS001   | PENDING    | 2025-01-01      | 2026-01-20    | FALSE  ← Expired
RS001   | ACTIVE     | 2026-01-20      | NULL          | TRUE   ← New version
```

**Benefits:**
- Point-in-time reporting ("What was the status on 2025-06-01?")
- Audit trail of all changes
- Maintains referential integrity with facts

---

## Code Breakdown

### Section 1: Imports and Setup (Lines 1-25)

```python
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, current_timestamp, lit, md5, concat_ws, when
from pyspark.sql.window import Window
from pyspark.sql import functions as F
```

**What it does:**
- Imports AWS Glue libraries for ETL operations
- Imports PySpark for distributed data processing
- Imports SQL functions for data transformations

**Key imports:**
- `md5`: Creates hash for change detection
- `concat_ws`: Concatenates columns with separator
- `current_timestamp`: Gets current time for effective dates

---

### Section 2: Job Initialization (Lines 27-35)

```python
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'REDSHIFT_CONNECTION'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

redshift_connection = args['REDSHIFT_CONNECTION']
```

**What it does:**
1. Gets job parameters from command line
2. Creates Spark context for distributed processing
3. Creates Glue context for AWS Glue operations
4. Initializes the job for tracking and logging

**Parameters:**
- `JOB_NAME`: Name of the Glue job (for logging)
- `REDSHIFT_CONNECTION`: Glue connection to Redshift

---

### Section 3: Main Function - load_scd2_dimension (Lines 37-120)

This is the core SCD Type 2 logic. Let me break it down step by step:

#### Step 3.1: Function Signature (Lines 37-46)

```python
def load_scd2_dimension(source_df, dim_table, natural_key, scd_columns):
    """
    Generic SCD Type 2 loader
    
    Args:
        source_df: Source DataFrame with new/updated records
        dim_table: Target dimension table name
        natural_key: Business key column(s)
        scd_columns: Columns to track for changes
    """
```

**Parameters explained:**
- `source_df`: New data from staging (e.g., new codes)
- `dim_table`: Target table (e.g., "dw.d_code")
- `natural_key`: Business identifier (e.g., ["code_id"])
- `scd_columns`: Columns to watch for changes (e.g., ["code_value", "code_description"])

**Example call:**
```python
load_scd2_dimension(
    source_df=staging_codes_df,
    dim_table='dw.d_code',
    natural_key=['code_id'],
    scd_columns=['code_value', 'code_description', 'code_category_key']
)
```

---

#### Step 3.2: Read Existing Dimension (Lines 48-57)

```python
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
```

**What it does:**
- Reads the current dimension table from Redshift
- Converts to Spark DataFrame for processing

**Example data read:**
```
code_key | code_id | code_value | effective_start | is_active
---------|---------|------------|-----------------|----------
101      | RS001   | PENDING    | 2025-01-01      | TRUE
102      | RS002   | ACTIVE     | 2025-01-01      | TRUE
103      | RS003   | INACTIVE   | 2025-01-01      | FALSE (expired)
```

---

#### Step 3.3: Filter Active Records (Lines 59-60)

```python
# Get current active records
current_records = existing_dim.filter(col('is_active') == True)
```

**What it does:**
- Filters to only active (current) versions
- Ignores expired historical records

**Result:**
```
code_key | code_id | code_value | is_active
---------|---------|------------|----------
101      | RS001   | PENDING    | TRUE
102      | RS002   | ACTIVE     | TRUE
(RS003 excluded because is_active = FALSE)
```

**Why?** We only compare new data against current versions, not historical ones.

---

#### Step 3.4: Create Hash for Change Detection (Lines 62-71)

```python
# Create hash of SCD columns for change detection
source_df = source_df.withColumn(
    'record_hash',
    md5(concat_ws('|', *[col(c) for c in scd_columns]))
)

current_records = current_records.withColumn(
    'current_hash',
    md5(concat_ws('|', *[col(c) for c in scd_columns]))
)
```

**What it does:**
- Creates MD5 hash of SCD columns
- Concatenates columns with '|' separator
- Enables fast change detection

**Example:**
```python
# If scd_columns = ['code_value', 'code_description']
# And row has: code_value='ACTIVE', code_description='Active Status'

# Step 1: Concatenate
'ACTIVE|Active Status'

# Step 2: Hash
md5('ACTIVE|Active Status') = 'a1b2c3d4e5f6...'

# Result:
code_id | code_value | code_description | record_hash
--------|------------|------------------|-------------
RS001   | ACTIVE     | Active Status    | a1b2c3d4e5f6...
```

**Why hash?**
- Fast comparison (single string vs multiple columns)
- Detects any change in tracked columns
- Efficient for large datasets

---

#### Step 3.5: Join to Find Changes (Lines 73-78)

```python
# Join to find changes
joined = source_df.alias('src').join(
    current_records.alias('cur'),
    natural_key,
    'left_outer'
)
```

**What it does:**
- Left outer join on business key (e.g., code_id)
- Keeps all source records
- Matches with current dimension records

**Example:**
```
Source (src):                    Current (cur):
code_id | code_value | hash     code_id | code_value | hash
--------|------------|------    --------|------------|------
RS001   | ACTIVE     | abc123   RS001   | PENDING    | xyz789
RS002   | ACTIVE     | def456   RS002   | ACTIVE     | def456
RS004   | NEW        | ghi789   (no match)

Result (joined):
src.code_id | src.code_value | src.hash | cur.code_id | cur.hash
------------|----------------|----------|-------------|----------
RS001       | ACTIVE         | abc123   | RS001       | xyz789  ← Changed
RS002       | ACTIVE         | def456   | RS002       | def456  ← Unchanged
RS004       | NEW            | ghi789   | NULL        | NULL    ← New
```

---

#### Step 3.6: Identify New Records (Lines 80-84)

```python
# Identify new records (no match in current)
new_records = joined.filter(col('cur.' + natural_key[0]).isNull()) \
    .select('src.*') \
    .withColumn('effective_start_dt', current_timestamp()) \
    .withColumn('effective_end_dt', lit(None).cast('timestamp')) \
    .withColumn('is_active', lit(True))
```

**What it does:**
- Finds records where current dimension has no match (NULL)
- These are brand new records
- Sets effective_start_dt to now
- Sets effective_end_dt to NULL (still active)
- Sets is_active to TRUE

**Example:**
```
Input (from joined):
src.code_id | cur.code_id
------------|------------
RS004       | NULL        ← New record

Output (new_records):
code_id | code_value | effective_start_dt | effective_end_dt | is_active
--------|------------|-------------------|------------------|----------
RS004   | NEW        | 2026-01-20 20:00  | NULL             | TRUE
```

---

#### Step 3.7: Identify Changed Records (Lines 86-91)

```python
# Identify changed records (hash mismatch)
changed_records = joined.filter(
    (col('cur.' + natural_key[0]).isNotNull()) &
    (col('record_hash') != col('current_hash'))
)
```

**What it does:**
- Finds records that exist in current dimension (not NULL)
- But have different hash (data changed)

**Example:**
```
Input (from joined):
src.code_id | src.hash | cur.code_id | cur.hash
------------|----------|-------------|----------
RS001       | abc123   | RS001       | xyz789   ← Changed (hash different)
RS002       | def456   | RS002       | def456   ← Unchanged (hash same)

Output (changed_records):
code_id | code_value | old_hash | new_hash
--------|------------|----------|----------
RS001   | ACTIVE     | xyz789   | abc123
```

---

#### Step 3.8: Expire Old Versions (Lines 93-94)

```python
# Expire old versions
expire_keys = changed_records.select('cur.' + dim_table.split('.')[1] + '_key').distinct()
```

**What it does:**
- Gets surrogate keys of records that changed
- These old versions need to be expired

**Example:**
```
Input (changed_records):
cur.code_key | code_id
-------------|--------
101          | RS001

Output (expire_keys):
code_key
--------
101
```

**Next step (not shown in snippet):**
These keys are used to UPDATE the dimension table:
```sql
UPDATE dw.d_code
SET effective_end_dt = GETDATE(),
    is_active = FALSE
WHERE code_key IN (101)
AND is_active = TRUE
```

---

#### Step 3.9: Create New Versions (Lines 96-100)

```python
# Create new versions for changed records
new_versions = changed_records.select('src.*') \
    .withColumn('effective_start_dt', current_timestamp()) \
    .withColumn('effective_end_dt', lit(None).cast('timestamp')) \
    .withColumn('is_active', lit(True))
```

**What it does:**
- Takes the new data from source
- Creates new version with current timestamp
- Sets as active

**Example:**
```
Input (changed_records):
src.code_id | src.code_value
------------|---------------
RS001       | ACTIVE

Output (new_versions):
code_id | code_value | effective_start_dt | effective_end_dt | is_active
--------|------------|-------------------|------------------|----------
RS001   | ACTIVE     | 2026-01-20 20:00  | NULL             | TRUE
```

---

#### Step 3.10: Combine and Return (Lines 102-105)

```python
# Combine new and changed
inserts = new_records.union(new_versions)

return inserts, expire_keys
```

**What it does:**
- Combines brand new records with new versions of changed records
- Returns both inserts and keys to expire

**Example result:**
```
inserts DataFrame:
code_id | code_value | effective_start_dt | is_active
--------|------------|-------------------|----------
RS004   | NEW        | 2026-01-20 20:00  | TRUE      ← Brand new
RS001   | ACTIVE     | 2026-01-20 20:00  | TRUE      ← New version

expire_keys DataFrame:
code_key
--------
101      ← Old version of RS001 to expire
```

---

### Section 4: Example Usage (Lines 107-150)

```python
# Example: Load D_Code dimension
staging_codes = glueContext.read.from_jdbc_conf(
    frame=None,
    catalog_connection=redshift_connection,
    connection_options={
        "dbtable": "staging.stg_codes",
        "database": "rcvdw"
    },
    transformation_ctx="read_staging_codes"
).toDF()
```

**What it does:**
- Reads staging data (new codes from source system)

---

```python
# Transform to dimension format
dim_code_df = staging_codes.select(
    col('code_id'),
    col('code_category_key'),
    col('code_value'),
    col('code_description'),
    col('display_order')
)
```

**What it does:**
- Selects only columns needed for dimension
- Transforms to match dimension schema

---

```python
# Apply SCD2 logic
inserts, expire_keys = load_scd2_dimension(
    source_df=dim_code_df,
    dim_table='dw.d_code',
    natural_key=['code_id'],
    scd_columns=['code_value', 'code_description', 'code_category_key']
)
```

**What it does:**
- Calls the SCD2 function
- Specifies which columns to track for changes
- Returns records to insert and keys to expire

---

```python
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
```

**What it does:**
- Converts Spark DataFrame to Glue DynamicFrame
- Writes new records to Redshift dimension table
- Uses JDBC connection for efficient bulk insert

---

```python
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
```

**What it does:**
- Collects surrogate keys to expire
- Builds UPDATE SQL statement
- Executes directly in Redshift using Data API
- Sets effective_end_dt and is_active=FALSE

---

## Complete Example: End-to-End Flow

### Initial State
```sql
-- dw.d_code (before)
code_key | code_id | code_value | effective_start_dt | effective_end_dt | is_active
---------|---------|------------|-------------------|------------------|----------
101      | RS001   | PENDING    | 2025-01-01        | NULL             | TRUE
102      | RS002   | ACTIVE     | 2025-01-01        | NULL             | TRUE
```

### New Data Arrives
```sql
-- staging.stg_codes (new data)
code_id | code_value
--------|------------
RS001   | ACTIVE      ← Changed from PENDING
RS002   | ACTIVE      ← Unchanged
RS003   | INACTIVE    ← New
```

### SCD2 Processing

**Step 1: Hash Comparison**
```
RS001: old_hash(PENDING) != new_hash(ACTIVE) → Changed
RS002: old_hash(ACTIVE) == new_hash(ACTIVE) → Unchanged (skip)
RS003: no match → New
```

**Step 2: Expire Old Version**
```sql
UPDATE dw.d_code
SET effective_end_dt = '2026-01-20 20:00',
    is_active = FALSE
WHERE code_key = 101;
```

**Step 3: Insert New Versions**
```sql
INSERT INTO dw.d_code (code_id, code_value, effective_start_dt, is_active)
VALUES 
  ('RS001', 'ACTIVE', '2026-01-20 20:00', TRUE),   -- New version
  ('RS003', 'INACTIVE', '2026-01-20 20:00', TRUE); -- Brand new
```

### Final State
```sql
-- dw.d_code (after)
code_key | code_id | code_value | effective_start_dt | effective_end_dt  | is_active
---------|---------|------------|-------------------|-------------------|----------
101      | RS001   | PENDING    | 2025-01-01        | 2026-01-20 20:00  | FALSE  ← Expired
102      | RS002   | ACTIVE     | 2025-01-01        | NULL              | TRUE   ← Unchanged
103      | RS001   | ACTIVE     | 2026-01-20 20:00  | NULL              | TRUE   ← New version
104      | RS003   | INACTIVE   | 2026-01-20 20:00  | NULL              | TRUE   ← Brand new
```

---

## Key Concepts

### 1. Natural Key vs Surrogate Key
- **Natural Key** (code_id): Business identifier from source system
- **Surrogate Key** (code_key): Auto-generated unique ID in warehouse
- **Why both?** Natural key can have multiple versions; surrogate key is always unique

### 2. Effective Dating
- **effective_start_dt**: When this version became active
- **effective_end_dt**: When this version was replaced (NULL if current)
- **is_active**: Quick flag for current version

### 3. Point-in-Time Queries
```sql
-- What was RS001's value on 2025-06-01?
SELECT code_value
FROM dw.d_code
WHERE code_id = 'RS001'
  AND '2025-06-01' BETWEEN effective_start_dt 
      AND COALESCE(effective_end_dt, '9999-12-31');

-- Result: PENDING
```

### 4. Current Value Queries
```sql
-- What is RS001's current value?
SELECT code_value
FROM dw.d_code
WHERE code_id = 'RS001'
  AND is_active = TRUE;

-- Result: ACTIVE
```

---

## Performance Considerations

### 1. Hash-Based Change Detection
- **Fast**: Single string comparison vs multiple columns
- **Efficient**: Works well with Spark's distributed processing
- **Scalable**: Handles millions of records

### 2. Bulk Operations
- **Inserts**: Bulk insert via JDBC (fast)
- **Updates**: Single UPDATE statement with IN clause
- **Avoids**: Row-by-row processing

### 3. Filtering Active Records
- **Reduces data**: Only compare against current versions
- **Faster joins**: Smaller dataset to join
- **Less memory**: Fewer records in memory

---

## Common Issues and Solutions

### Issue 1: Duplicate Natural Keys in Source
**Problem:** Source has multiple rows with same code_id
**Solution:** Deduplicate source before calling function
```python
dim_code_df = staging_codes.dropDuplicates(['code_id'])
```

### Issue 2: Missing SCD Columns
**Problem:** Source missing a tracked column
**Solution:** Add default value or exclude from SCD columns
```python
dim_code_df = dim_code_df.fillna({'code_description': 'Unknown'})
```

### Issue 3: Large Expire List
**Problem:** Too many keys to expire (SQL too long)
**Solution:** Batch the updates
```python
for batch in chunks(expire_list, 1000):
    expire_sql = f"UPDATE ... WHERE code_key IN ({','.join(batch)})"
    # Execute
```

---

## Summary

This Glue job implements SCD Type 2 by:

1. ✅ Reading current dimension from Redshift
2. ✅ Comparing new data with current using MD5 hashes
3. ✅ Identifying new, changed, and unchanged records
4. ✅ Expiring old versions (set effective_end_dt, is_active=FALSE)
5. ✅ Inserting new versions with new effective_start_dt
6. ✅ Preserving complete history for point-in-time reporting

**Result:** Full audit trail of all dimension changes over time!
