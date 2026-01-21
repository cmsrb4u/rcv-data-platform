# RCV Data Platform - Detailed Deployment Guide (Part 3)

## Phase 6: Initial Data Load

### Step 6.1: Prepare Sample Data
```bash
# Create sample registration data
cat > sample_data/registration_sample.csv << 'EOF'
registration_id,first_name,last_name,email,phone,street_address,city,state,zipcode,country,registration_date,birth_date,registration_status,registration_type,classification,registration_method,source_system,source_file_name
REG001,John,Doe,john.doe@email.com,555-0101,123 Main St,Springfield,IL,62701,USA,2025-01-15,1990-05-20,ACTIVE,NEW,Standard,Internet,RCV Web Portal,batch_20250115.csv
REG002,Jane,Smith,jane.smith@email.com,555-0102,456 Oak Ave,Chicago,IL,60601,USA,2025-01-16,1985-08-15,ACTIVE,NEW,Standard,Internet,RCV Web Portal,batch_20250116.csv
REG003,Bob,Johnson,bob.j@email.com,555-0103,789 Elm St,Peoria,IL,61602,USA,2025-01-17,1992-03-10,PENDING,RENEWAL,Standard,DMV,DMV System,batch_20250117.csv
EOF

# Convert CSV to Parquet (requires Python with pandas and pyarrow)
python3 << 'PYTHON_SCRIPT'
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

# Read CSV
df = pd.read_csv('sample_data/registration_sample.csv')

# Convert date columns
df['registration_date'] = pd.to_datetime(df['registration_date'])
df['birth_date'] = pd.to_datetime(df['birth_date'])

# Write to Parquet
df.to_parquet('sample_data/registration_sample.parquet', 
              engine='pyarrow', 
              compression='snappy')

print(f"✅ Created Parquet file with {len(df)} records")
PYTHON_SCRIPT
```

### Step 6.2: Upload Sample Data to S3
```bash
# Upload to S3 raw landing zone
aws s3 cp sample_data/registration_sample.parquet \
  s3://${RAW_BUCKET}/raw/registration/2025/01/20/registration_sample.parquet

# Verify upload
aws s3 ls s3://${RAW_BUCKET}/raw/registration/2025/01/20/

# Expected output:
# 2026-01-20 20:00:00       1234 registration_sample.parquet
```

### Step 6.3: Run Initial Load Pipeline
```bash
# Step 1: Load to Staging
echo "Step 1: Loading to staging..."
JOB_RUN_ID=$(aws glue start-job-run \
  --job-name rcv-load-to-staging-dev \
  --arguments '{
    "--TABLE_NAME":"registration"
  }' \
  --query 'JobRunId' \
  --output text)

echo "Job Run ID: $JOB_RUN_ID"

# Wait for job to complete
while true; do
  STATUS=$(aws glue get-job-run \
    --job-name rcv-load-to-staging-dev \
    --run-id $JOB_RUN_ID \
    --query 'JobRun.JobRunState' \
    --output text)
  
  echo "Status: $STATUS"
  
  if [ "$STATUS" = "SUCCEEDED" ]; then
    echo "✅ Load to staging completed!"
    break
  elif [ "$STATUS" = "FAILED" ]; then
    echo "❌ Job failed!"
    aws glue get-job-run \
      --job-name rcv-load-to-staging-dev \
      --run-id $JOB_RUN_ID \
      --query 'JobRun.ErrorMessage'
    exit 1
  fi
  
  sleep 30
done

# Step 2: Data Quality Checks
echo "Step 2: Running data quality checks..."
DQ_RUN_ID=$(aws glue start-job-run \
  --job-name rcv-data-quality-dev \
  --arguments '{
    "--TABLE_NAME":"registration"
  }' \
  --query 'JobRunId' \
  --output text)

# Wait for DQ checks
while true; do
  STATUS=$(aws glue get-job-run \
    --job-name rcv-data-quality-dev \
    --run-id $DQ_RUN_ID \
    --query 'JobRun.JobRunState' \
    --output text)
  
  echo "DQ Status: $STATUS"
  
  if [ "$STATUS" = "SUCCEEDED" ]; then
    echo "✅ Data quality checks passed!"
    break
  elif [ "$STATUS" = "FAILED" ]; then
    echo "❌ DQ checks failed!"
    exit 1
  fi
  
  sleep 30
done

# Step 3: Load Dimensions
echo "Step 3: Loading dimensions..."
DIM_RUN_ID=$(aws glue start-job-run \
  --job-name rcv-load-dimensions-dev \
  --query 'JobRunId' \
  --output text)

# Wait for dimensions
while true; do
  STATUS=$(aws glue get-job-run \
    --job-name rcv-load-dimensions-dev \
    --run-id $DIM_RUN_ID \
    --query 'JobRun.JobRunState' \
    --output text)
  
  echo "Dimensions Status: $STATUS"
  
  if [ "$STATUS" = "SUCCEEDED" ]; then
    echo "✅ Dimensions loaded!"
    break
  elif [ "$STATUS" = "FAILED" ]; then
    echo "❌ Dimension load failed!"
    exit 1
  fi
  
  sleep 30
done

# Step 4: Load Facts
echo "Step 4: Loading facts..."
FACT_RUN_ID=$(aws glue start-job-run \
  --job-name rcv-load-facts-dev \
  --arguments '{
    "--LOAD_TYPE":"INITIAL"
  }' \
  --query 'JobRunId' \
  --output text)

# Wait for facts
while true; do
  STATUS=$(aws glue get-job-run \
    --job-name rcv-load-facts-dev \
    --run-id $FACT_RUN_ID \
    --query 'JobRun.JobRunState' \
    --output text)
  
  echo "Facts Status: $STATUS"
  
  if [ "$STATUS" = "SUCCEEDED" ]; then
    echo "✅ Facts loaded!"
    break
  elif [ "$STATUS" = "FAILED" ]; then
    echo "❌ Fact load failed!"
    exit 1
  fi
  
  sleep 30
done

echo "🎉 Initial load pipeline completed successfully!"
```

### Step 6.4: Validate Data Load
```bash
# Connect to Redshift and validate
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 << 'EOF'
-- Check staging table
SELECT 
    'Staging' as layer,
    COUNT(*) as record_count,
    COUNT(CASE WHEN dq_is_valid = TRUE THEN 1 END) as valid_records,
    COUNT(CASE WHEN dq_is_valid = FALSE THEN 1 END) as invalid_records
FROM staging.stg_registration;

-- Check fact table
SELECT 
    'Fact' as layer,
    COUNT(*) as record_count,
    COUNT(DISTINCT registration_id) as unique_registrations
FROM dw.f_registration;

-- Check data quality results
SELECT 
    check_name,
    check_type,
    pass_rate,
    status
FROM staging.dq_results
WHERE table_name = 'staging.stg_registration'
ORDER BY check_timestamp DESC
LIMIT 5;

-- Check ETL control
SELECT 
    job_name,
    status,
    records_read,
    records_written,
    records_rejected,
    start_timestamp,
    end_timestamp
FROM staging.etl_control
ORDER BY start_timestamp DESC
LIMIT 5;

-- Sample fact data with dimensions
SELECT 
    f.registration_id,
    d.date_value as registration_date,
    c.code_value as status,
    s.state_name,
    z.city,
    f.age_at_registration
FROM dw.f_registration f
JOIN dw.d_date d ON f.registration_date_key = d.date_key
JOIN dw.d_code c ON f.registration_status_code_key = c.code_key
JOIN dw.d_state s ON f.state_key = s.state_key
JOIN dw.d_zipcode z ON f.zipcode_key = z.zipcode_key
LIMIT 10;
EOF
```

Expected output:
```
  layer   | record_count | valid_records | invalid_records
----------+--------------+---------------+-----------------
 Staging  |            3 |             3 |               0

  layer  | record_count | unique_registrations
---------+--------------+---------------------
 Fact    |            3 |                   3

     check_name      | check_type  | pass_rate | status
---------------------+-------------+-----------+--------
 registration_id_... | COMPLETENESS|    100.00 | PASS
 registration_date...| VALIDITY    |    100.00 | PASS
 ...
```

### Step 6.5: Test Incremental Load
```bash
# Create incremental data (new records)
cat > sample_data/registration_incremental.csv << 'EOF'
registration_id,first_name,last_name,email,phone,street_address,city,state,zipcode,country,registration_date,birth_date,registration_status,registration_type,classification,registration_method,source_system,source_file_name
REG004,Alice,Williams,alice.w@email.com,555-0104,321 Pine St,Rockford,IL,61101,USA,2025-01-21,1988-11-25,ACTIVE,NEW,Standard,Mobile,RCV Mobile App,batch_20250121.csv
REG002,Jane,Smith,jane.smith@email.com,555-0102,456 Oak Ave,Chicago,IL,60601,USA,2025-01-21,1985-08-15,INACTIVE,UPDATE,Standard,Internet,RCV Web Portal,batch_20250121.csv
EOF

# Convert to Parquet
python3 << 'PYTHON_SCRIPT'
import pandas as pd

df = pd.read_csv('sample_data/registration_incremental.csv')
df['registration_date'] = pd.to_datetime(df['registration_date'])
df['birth_date'] = pd.to_datetime(df['birth_date'])
df.to_parquet('sample_data/registration_incremental.parquet', 
              engine='pyarrow', compression='snappy')
print(f"✅ Created incremental Parquet with {len(df)} records")
PYTHON_SCRIPT

# Upload incremental data
aws s3 cp sample_data/registration_incremental.parquet \
  s3://${RAW_BUCKET}/raw/registration/2025/01/21/registration_incremental.parquet

# Run incremental load
aws glue start-job-run \
  --job-name rcv-load-to-staging-dev \
  --arguments '{"--TABLE_NAME":"registration"}'

# Wait and run subsequent jobs...
# (Same process as initial load but with LOAD_TYPE=INCREMENTAL for facts)

# Verify incremental load
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 << 'EOF'
-- Should now have 4 records (3 initial + 1 new)
SELECT COUNT(*) as total_records FROM dw.f_registration;

-- Check history table for changed record (REG002)
SELECT 
    registration_id,
    snapshot_date_key,
    change_type,
    effective_start_dt,
    is_current
FROM dw.f_registration_hist
WHERE registration_id = 'REG002'
ORDER BY effective_start_dt;
EOF
```

---

## Phase 7: Power BI Connection

### Step 7.1: Install Redshift ODBC Driver
```bash
# Download driver (macOS)
curl -O https://s3.amazonaws.com/redshift-downloads/drivers/odbc/1.4.52.1000/AmazonRedshiftODBC-1.4.52.1000.dmg

# Install
open AmazonRedshiftODBC-1.4.52.1000.dmg
# Follow installation wizard

# Verify installation
ls /Library/ODBC/Amazon\ Redshift\ ODBC\ Driver/
```

### Step 7.2: Configure ODBC Connection
```bash
# Edit ODBC configuration
sudo nano /Library/ODBC/odbc.ini

# Add this configuration:
[Amazon Redshift]
Driver=/Library/ODBC/Amazon Redshift ODBC Driver/lib/libamazonredshiftodbc.dylib
Host=<your-redshift-endpoint>
Port=5439
Database=rcvdw
```

### Step 7.3: Connect Power BI
**In Power BI Desktop:**

1. **Get Data** → **More** → **Amazon Redshift**

2. **Enter connection details:**
   - Server: `<your-redshift-endpoint>:5439`
   - Database: `rcvdw`
   - Data Connectivity mode: **DirectQuery** (recommended)

3. **Enter credentials:**
   - Username: `admin`
   - Password: `YourSecurePassword123!`

4. **Select tables:**
   - Navigate to `dw` schema
   - Select fact tables: `f_registration`, `f_compliance`, `f_verification`
   - Select dimension tables: `d_date`, `d_code`, `d_state`, `d_zipcode`, etc.

5. **Load tables** (metadata only in DirectQuery mode)

### Step 7.4: Create Relationships
**In Power BI Model view:**

```
Create relationships:
F_Registration → D_Date (registration_date_key → date_key)
F_Registration → D_Code (registration_status_code_key → code_key)
F_Registration → D_Zipcode (zipcode_key → zipcode_key)
F_Registration → D_State (state_key → state_key)

Set cardinality: Many-to-One
Set cross-filter direction: Single
```

### Step 7.5: Create Sample Report
**Create a simple dashboard:**

1. **Add KPI Card:**
   - Measure: `Total Registrations = COUNT(f_registration[registration_id])`
   - Format as number

2. **Add Line Chart:**
   - X-axis: `d_date[date_value]`
   - Y-axis: `Total Registrations`
   - Title: "Registrations Over Time"

3. **Add Bar Chart:**
   - Y-axis: `d_state[state_name]`
   - X-axis: `Total Registrations`
   - Sort: Descending
   - Title: "Top States by Registrations"

4. **Add Table:**
   - Columns: 
     - `f_registration[registration_id]`
     - `d_date[date_value]`
     - `d_code[code_value]` (status)
     - `d_state[state_name]`

5. **Test the report:**
   - Verify data loads
   - Test filters
   - Check query performance

### Step 7.6: Optimize Power BI Performance
```sql
-- In Redshift, create aggregation table for better performance
CREATE TABLE dw.agg_registration_daily AS
SELECT 
    d.date_key,
    d.date_value,
    d.year,
    d.month,
    s.state_key,
    s.state_name,
    c.code_key,
    c.code_value as status,
    COUNT(*) as registration_count
FROM dw.f_registration f
JOIN dw.d_date d ON f.registration_date_key = d.date_key
JOIN dw.d_state s ON f.state_key = s.state_key
JOIN dw.d_code c ON f.registration_status_code_key = c.code_key
GROUP BY 
    d.date_key, d.date_value, d.year, d.month,
    s.state_key, s.state_name,
    c.code_key, c.code_value;

-- Use this aggregation table in Power BI for faster dashboards
```

---

## Phase 8: Enable Daily Automation

### Step 8.1: Start Workflow
```bash
# The workflow is already scheduled to run daily at 2 AM
# To manually trigger it:
aws glue start-workflow-run --name ${WORKFLOW_NAME}

# Get run ID
RUN_ID=$(aws glue list-workflow-runs \
  --name ${WORKFLOW_NAME} \
  --max-results 1 \
  --query 'Runs[0].WorkflowRunId' \
  --output text)

# Monitor workflow
aws glue get-workflow-run \
  --name ${WORKFLOW_NAME} \
  --run-id ${RUN_ID} \
  --query 'Run.[Status,Statistics]' \
  --output table
```

### Step 8.2: Monitor Daily Runs
```bash
# Create monitoring script
cat > monitor_pipeline.sh << 'EOF'
#!/bin/bash

# Get latest workflow run
RUN_ID=$(aws glue list-workflow-runs \
  --name rcv-daily-etl-dev \
  --max-results 1 \
  --query 'Runs[0].WorkflowRunId' \
  --output text)

# Get status
STATUS=$(aws glue get-workflow-run \
  --name rcv-daily-etl-dev \
  --run-id ${RUN_ID} \
  --query 'Run.Status' \
  --output text)

echo "Latest Run: $RUN_ID"
echo "Status: $STATUS"

# Get job details
aws glue get-workflow-run \
  --name rcv-daily-etl-dev \
  --run-id ${RUN_ID} \
  --query 'Run.Graph.Nodes[*].[Name,JobDetails.JobRuns[0].JobRunState]' \
  --output table
EOF

chmod +x monitor_pipeline.sh

# Run monitoring
./monitor_pipeline.sh
```

---

## Troubleshooting

### Issue 1: Cannot Connect to Redshift
```bash
# Check security group
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*Redshift*" \
  --query 'SecurityGroups[0].IpPermissions'

# Add your IP
MY_IP=$(curl -s https://checkip.amazonaws.com)
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*Redshift*" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id ${SG_ID} \
  --protocol tcp \
  --port 5439 \
  --cidr ${MY_IP}/32
```

### Issue 2: Glue Job Fails
```bash
# Get error details
aws glue get-job-run \
  --job-name rcv-load-to-staging-dev \
  --run-id <run-id> \
  --query 'JobRun.ErrorMessage'

# Check CloudWatch logs
aws logs tail /aws-glue/jobs/error --follow --filter-pattern "ERROR"
```

### Issue 3: Data Quality Checks Fail
```sql
-- Check which checks failed
SELECT 
    check_name,
    check_type,
    records_failed,
    pass_rate,
    details
FROM staging.dq_results
WHERE status = 'FAIL'
ORDER BY check_timestamp DESC;

-- Check invalid records
SELECT *
FROM staging.stg_registration
WHERE dq_is_valid = FALSE
LIMIT 10;
```

### Issue 4: Power BI Slow Performance
```sql
-- Check query performance in Redshift
SELECT 
    query,
    TRIM(querytxt) as query_text,
    starttime,
    endtime,
    DATEDIFF(seconds, starttime, endtime) as duration_seconds
FROM stl_query
WHERE userid > 1
  AND starttime > DATEADD(hour, -1, GETDATE())
ORDER BY duration_seconds DESC
LIMIT 10;

-- Analyze tables
ANALYZE dw.f_registration;
ANALYZE dw.d_date;
ANALYZE dw.d_code;
```

---

## Next Steps

1. ✅ Load historical data (10 years)
2. ✅ Build additional Power BI reports
3. ✅ Setup production environment
4. ✅ Configure backup and disaster recovery
5. ✅ Train end users
6. ✅ Document operational procedures

**Congratulations! Your RCV Data Platform is now deployed and operational!** 🎉
