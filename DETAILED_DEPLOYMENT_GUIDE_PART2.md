# RCV Data Platform - Detailed Deployment Guide (Part 2)

## Phase 4: Deploy Glue Jobs

### Step 4.1: Upload Glue Scripts to S3
```bash
# Upload all Glue Python scripts
aws s3 cp glue/ s3://${RAW_BUCKET}/glue-scripts/ --recursive

# Verify upload
aws s3 ls s3://${RAW_BUCKET}/glue-scripts/ --recursive

# Expected output:
# glue-scripts/archive/archive_old_data.py
# glue-scripts/staging/data_quality_checks.py
# glue-scripts/staging/load_to_staging.py
# glue-scripts/transform/load_dimensions_scd2.py
# glue-scripts/transform/load_fact_registration.py
```

### Step 4.2: Create Glue Connection to Redshift
```bash
# Get VPC and subnet info from CloudFormation
export VPC_ID=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`VPCId`].OutputValue' \
  --output text)

export SUBNET_ID=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnet1`].OutputValue' \
  --output text)

export SECURITY_GROUP=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`GlueSecurityGroup`].OutputValue' \
  --output text)

# Create Glue connection
aws glue create-connection \
  --connection-input "{
    \"Name\": \"rcv-redshift-connection\",
    \"Description\": \"Connection to Redshift Serverless for RCV data platform\",
    \"ConnectionType\": \"JDBC\",
    \"ConnectionProperties\": {
      \"JDBC_CONNECTION_URL\": \"jdbc:redshift://${REDSHIFT_ENDPOINT}:5439/rcvdw\",
      \"USERNAME\": \"admin\",
      \"PASSWORD\": \"YourSecurePassword123!\"
    },
    \"PhysicalConnectionRequirements\": {
      \"SubnetId\": \"${SUBNET_ID}\",
      \"SecurityGroupIdList\": [\"${SECURITY_GROUP}\"],
      \"AvailabilityZone\": \"${AWS_REGION}a\"
    }
  }"

# Test connection
aws glue get-connection --name rcv-redshift-connection

# Expected output: Connection details with status
```

**What This Does:**
- Creates a JDBC connection from Glue to Redshift Serverless
- Stores credentials securely
- Configures network access through VPC

### Step 4.3: Create Glue Database
```bash
# Create Glue Data Catalog database
aws glue create-database \
  --database-input "{
    \"Name\": \"rcv_${ENVIRONMENT}\",
    \"Description\": \"RCV data catalog for ${ENVIRONMENT} environment\"
  }"

# Verify database created
aws glue get-database --name rcv_${ENVIRONMENT}
```

### Step 4.4: Deploy Glue Jobs Stack
```bash
# Create parameters file for Glue jobs
cat > infrastructure/glue-parameters-dev.json << EOF
[
  {
    "ParameterKey": "Environment",
    "ParameterValue": "dev"
  },
  {
    "ParameterKey": "GlueRoleArn",
    "ParameterValue": "${GLUE_ROLE_ARN}"
  },
  {
    "ParameterKey": "RedshiftConnection",
    "ParameterValue": "rcv-redshift-connection"
  },
  {
    "ParameterKey": "RawBucket",
    "ParameterValue": "${RAW_BUCKET}"
  },
  {
    "ParameterKey": "ArchiveBucket",
    "ParameterValue": "${ARCHIVE_BUCKET}"
  }
]
EOF

# Deploy Glue jobs stack
aws cloudformation create-stack \
  --stack-name ${STACK_NAME}-glue-jobs \
  --template-body file://infrastructure/glue-jobs.yaml \
  --parameters file://infrastructure/glue-parameters-dev.json \
  --region ${AWS_REGION}

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name ${STACK_NAME}-glue-jobs

echo "✅ Glue jobs deployed!"
```

### Step 4.5: Verify Glue Jobs Created
```bash
# List all Glue jobs
aws glue list-jobs --query 'JobNames' --output table

# Expected output:
# |                    ListJobs                    |
# +------------------------------------------------+
# |  rcv-load-to-staging-dev                       |
# |  rcv-data-quality-dev                          |
# |  rcv-load-dimensions-dev                       |
# |  rcv-load-facts-dev                            |
# |  rcv-archive-old-data-dev                      |
# +------------------------------------------------+

# Get details of a specific job
aws glue get-job --job-name rcv-load-to-staging-dev \
  --query 'Job.[Name,Role,Command.ScriptLocation,MaxRetries]' \
  --output table
```

### Step 4.6: Understanding Each Glue Job

#### Job 1: load_to_staging.py
**Purpose:** Load raw data from S3 to Redshift staging tables

**What it does:**
1. Reads Parquet files from S3 raw landing zone
2. Adds metadata columns (load_timestamp, processing_status)
3. Truncates staging table
4. Loads data into staging table
5. Logs record count to control table

**When to run:** After new data arrives in S3

**Test run:**
```bash
# First, upload sample data to S3
aws s3 cp sample_data/registration.parquet \
  s3://${RAW_BUCKET}/raw/registration/2026/01/20/

# Run the job
aws glue start-job-run \
  --job-name rcv-load-to-staging-dev \
  --arguments '{
    "--TABLE_NAME":"registration"
  }'

# Get run ID from output, then check status
aws glue get-job-run \
  --job-name rcv-load-to-staging-dev \
  --run-id <run-id> \
  --query 'JobRun.[JobRunState,ExecutionTime,ErrorMessage]'
```

#### Job 2: data_quality_checks.py
**Purpose:** Validate data quality in staging tables

**What it does:**
1. Reads data from staging table
2. Runs completeness checks (required fields not null)
3. Runs validity checks (date ranges, data types)
4. Runs consistency checks (no duplicates)
5. Writes results to dq_results table
6. Updates staging records with dq_is_valid flag
7. Sends alert if failures exceed threshold

**When to run:** After load_to_staging completes

**Test run:**
```bash
aws glue start-job-run \
  --job-name rcv-data-quality-dev \
  --arguments '{
    "--TABLE_NAME":"registration"
  }'

# Check DQ results in Redshift
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 << 'EOF'
SELECT 
    check_name,
    check_type,
    records_checked,
    records_passed,
    records_failed,
    pass_rate,
    status
FROM staging.dq_results
WHERE table_name = 'staging.stg_registration'
ORDER BY check_timestamp DESC
LIMIT 10;
EOF
```

#### Job 3: load_dimensions_scd2.py
**Purpose:** Load dimensions with SCD Type 2 logic

**What it does:**
1. Reads staging data
2. Reads current active dimension records
3. Calculates hash of SCD columns for change detection
4. Identifies new records (no match in current)
5. Identifies changed records (hash mismatch)
6. Expires old versions (set effective_end_dt, is_active=FALSE)
7. Inserts new versions with new effective_start_dt

**When to run:** After data quality checks pass

**Test run:**
```bash
aws glue start-job-run \
  --job-name rcv-load-dimensions-dev

# Verify SCD Type 2 logic worked
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 << 'EOF'
-- Check for multiple versions of same code
SELECT 
    code_id,
    code_value,
    effective_start_dt,
    effective_end_dt,
    is_active
FROM dw.d_code
WHERE code_id = 'REG_STATUS_1'
ORDER BY effective_start_dt;

-- Should show history if code changed
EOF
```

#### Job 4: load_fact_registration.py
**Purpose:** Load fact tables with surrogate key lookups

**What it does:**
1. Reads staging data (only valid records)
2. Looks up surrogate keys from dimensions:
   - registration_date_key from D_Date
   - registration_status_code_key from D_Code
   - zipcode_key from D_Zipcode
   - state_key from D_State
3. Excludes PII columns (names, email, addresses)
4. For incremental loads:
   - Identifies new records (not in fact table)
   - Identifies changed records (hash mismatch)
   - Inserts changed records to history table
5. Inserts new/changed records to fact table

**When to run:** After dimensions are loaded

**Test run:**
```bash
aws glue start-job-run \
  --job-name rcv-load-facts-dev \
  --arguments '{
    "--LOAD_TYPE":"INITIAL"
  }'

# Verify data loaded
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 << 'EOF'
-- Check record count
SELECT COUNT(*) as total_registrations
FROM dw.f_registration;

-- Check date range
SELECT 
    MIN(d.date_value) as earliest_registration,
    MAX(d.date_value) as latest_registration,
    COUNT(DISTINCT f.registration_id) as unique_registrations
FROM dw.f_registration f
JOIN dw.d_date d ON f.registration_date_key = d.date_key;

-- Check for orphaned records (should be 0)
SELECT COUNT(*) as orphaned_records
FROM dw.f_registration f
LEFT JOIN dw.d_date d ON f.registration_date_key = d.date_key
WHERE d.date_key IS NULL;
EOF
```

#### Job 5: archive_old_data.py
**Purpose:** Archive data older than 10 years to S3

**What it does:**
1. Calculates cutoff date (10 years ago)
2. Reads fact table and joins with D_Date
3. Filters records older than cutoff
4. Writes to S3 as Parquet (partitioned by year)
5. Deletes archived records from Redshift
6. Creates Glue Catalog table for archived data
7. Runs MSCK REPAIR to add partitions

**When to run:** Monthly (1st of month)

**Test run:**
```bash
# This job should only run when you have old data
# For testing, you can modify the cutoff date in the script

aws glue start-job-run \
  --job-name rcv-archive-old-data-dev

# Check archived data in S3
aws s3 ls s3://${ARCHIVE_BUCKET}/archive/f_registration/ --recursive

# Query archived data via Redshift Spectrum
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 << 'EOF'
-- Create external schema for archived data
CREATE EXTERNAL SCHEMA IF NOT EXISTS spectrum
FROM DATA CATALOG
DATABASE 'rcv_archive'
IAM_ROLE '${GLUE_ROLE_ARN}';

-- Query archived data
SELECT 
    archive_year,
    COUNT(*) as record_count
FROM spectrum.f_registration_archive
GROUP BY archive_year
ORDER BY archive_year;
EOF
```

### Step 4.7: Create Glue Workflow
```bash
# Get workflow name from stack
export WORKFLOW_NAME=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME}-glue-jobs \
  --query 'Stacks[0].Outputs[?OutputKey==`WorkflowName`].OutputValue' \
  --output text)

# Verify workflow created
aws glue get-workflow --name ${WORKFLOW_NAME}

# List workflow triggers
aws glue list-triggers \
  --query 'TriggerNames' \
  --output table
```

**What the Workflow Does:**
1. **Start Trigger** (Scheduled): Runs daily at 2 AM
2. **Load to Staging**: Loads data from S3 to staging
3. **DQ Checks**: Validates data quality
4. **Load Dimensions**: Applies SCD Type 2 logic
5. **Load Facts**: Loads fact tables with surrogate keys

Each step waits for the previous to succeed before running.

---

## Phase 5: Setup Monitoring

### Step 5.1: Deploy Monitoring Stack
```bash
# Create parameters file
cat > monitoring/monitoring-parameters-dev.json << EOF
[
  {
    "ParameterKey": "Environment",
    "ParameterValue": "dev"
  },
  {
    "ParameterKey": "AlertEmail",
    "ParameterValue": "${ALERT_EMAIL}"
  }
]
EOF

# Deploy monitoring stack
aws cloudformation create-stack \
  --stack-name ${STACK_NAME}-monitoring \
  --template-body file://monitoring/cloudwatch-monitoring.yaml \
  --parameters file://monitoring/monitoring-parameters-dev.json \
  --region ${AWS_REGION}

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name ${STACK_NAME}-monitoring

echo "✅ Monitoring deployed!"
```

### Step 5.2: Confirm SNS Subscription
```bash
# Check your email for SNS subscription confirmation
# Click the "Confirm subscription" link

# Verify subscription
aws sns list-subscriptions-by-topic \
  --topic-arn $(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME}-monitoring \
    --query 'Stacks[0].Outputs[?OutputKey==`AlertTopicArn`].OutputValue' \
    --output text) \
  --query 'Subscriptions[*].[Protocol,Endpoint,SubscriptionArn]' \
  --output table
```

### Step 5.3: View CloudWatch Dashboard
```bash
# Get dashboard URL
aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME}-monitoring \
  --query 'Stacks[0].Outputs[?OutputKey==`DashboardURL`].OutputValue' \
  --output text

# Open in browser
open $(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME}-monitoring \
  --query 'Stacks[0].Outputs[?OutputKey==`DashboardURL`].OutputValue' \
  --output text)
```

### Step 5.4: Test Alerts
```bash
# Trigger a test alarm by running a failing Glue job
aws glue start-job-run \
  --job-name rcv-data-quality-dev \
  --arguments '{
    "--TABLE_NAME":"nonexistent_table"
  }'

# This should fail and trigger an alert email
# Check your email for the alert
```

---

