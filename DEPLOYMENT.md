# RCV Data Platform - Deployment Guide

## Prerequisites
- AWS Account with appropriate permissions
- AWS CLI configured
- Python 3.9+
- Redshift cluster credentials

## Step 1: Deploy Infrastructure

### 1.1 Deploy Core Infrastructure
```bash
aws cloudformation create-stack \
  --stack-name rcv-data-platform-dev \
  --template-body file://infrastructure/cloudformation-stack.yaml \
  --parameters \
    ParameterKey=Environment,ParameterValue=dev \
    ParameterKey=RedshiftMasterUsername,ParameterValue=admin \
    ParameterKey=RedshiftMasterPassword,ParameterValue=YourSecurePassword123! \
  --capabilities CAPABILITY_NAMED_IAM

# Wait for stack creation
aws cloudformation wait stack-create-complete \
  --stack-name rcv-data-platform-dev
```

### 1.2 Get Stack Outputs
```bash
aws cloudformation describe-stacks \
  --stack-name rcv-data-platform-dev \
  --query 'Stacks[0].Outputs'
```

## Step 2: Setup Redshift Serverless

### 2.1 Create Schemas
```bash
# Connect to Redshift Serverless
psql -h <workgroup-endpoint>.redshift-serverless.amazonaws.com -U admin -d rcvdw -p 5439

# Create schemas
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS dw;
```

### 2.2 Create Tables
```bash
# Run DDL scripts in order
psql -h <workgroup-endpoint>.redshift-serverless.amazonaws.com -U admin -d rcvdw -f redshift/staging/00_create_staging.sql
psql -h <workgroup-endpoint>.redshift-serverless.amazonaws.com -U admin -d rcvdw -f redshift/dimensions/01_create_dimensions.sql
psql -h <workgroup-endpoint>.redshift-serverless.amazonaws.com -U admin -d rcvdw -f redshift/facts/02_create_facts.sql
psql -h <workgroup-endpoint>.redshift-serverless.amazonaws.com -U admin -d rcvdw -f redshift/dimensions/03_populate_reference_data.sql
```

## Step 3: Deploy Glue Jobs

### 3.1 Upload Glue Scripts to S3
```bash
# Get bucket name from stack outputs
RAW_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name rcv-data-platform-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`RawDataBucketName`].OutputValue' \
  --output text)

# Upload scripts
aws s3 cp glue/ s3://${RAW_BUCKET}/glue-scripts/ --recursive
```

### 3.2 Create Redshift Connection in Glue
```bash
aws glue create-connection \
  --connection-input '{
    "Name": "rcv-redshift-connection",
    "ConnectionType": "JDBC",
    "ConnectionProperties": {
      "JDBC_CONNECTION_URL": "jdbc:redshift://<redshift-endpoint>:5439/rcvdw",
      "USERNAME": "admin",
      "PASSWORD": "YourSecurePassword123!"
    },
    "PhysicalConnectionRequirements": {
      "SubnetId": "<subnet-id>",
      "SecurityGroupIdList": ["<security-group-id>"],
      "AvailabilityZone": "us-east-1a"
    }
  }'
```

### 3.3 Deploy Glue Jobs Stack
```bash
GLUE_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name rcv-data-platform-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`GlueRoleArn`].OutputValue' \
  --output text)

ARCHIVE_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name rcv-data-platform-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`ArchiveBucketName`].OutputValue' \
  --output text)

aws cloudformation create-stack \
  --stack-name rcv-glue-jobs-dev \
  --template-body file://infrastructure/glue-jobs.yaml \
  --parameters \
    ParameterKey=Environment,ParameterValue=dev \
    ParameterKey=GlueRoleArn,ParameterValue=${GLUE_ROLE_ARN} \
    ParameterKey=RedshiftConnection,ParameterValue=rcv-redshift-connection \
    ParameterKey=RawBucket,ParameterValue=${RAW_BUCKET} \
    ParameterKey=ArchiveBucket,ParameterValue=${ARCHIVE_BUCKET}
```

## Step 4: Deploy Monitoring

```bash
aws cloudformation create-stack \
  --stack-name rcv-monitoring-dev \
  --template-body file://monitoring/cloudwatch-monitoring.yaml \
  --parameters \
    ParameterKey=Environment,ParameterValue=dev \
    ParameterKey=AlertEmail,ParameterValue=data-team@example.com
```

## Step 5: Initial Historical Load

### 5.1 Prepare Historical Data
```bash
# Upload 10 years of historical data to S3
aws s3 cp historical_data/ s3://${RAW_BUCKET}/raw/registration/ --recursive
aws s3 cp historical_data/ s3://${RAW_BUCKET}/raw/compliance/ --recursive
aws s3 cp historical_data/ s3://${RAW_BUCKET}/raw/verification/ --recursive
```

### 5.2 Run Initial Load
```bash
# Run for each table with INITIAL load type
aws glue start-job-run \
  --job-name rcv-load-to-staging-dev \
  --arguments '{"--TABLE_NAME":"registration"}'

# Wait for completion, then run DQ checks
aws glue start-job-run \
  --job-name rcv-data-quality-dev \
  --arguments '{"--TABLE_NAME":"registration"}'

# Load dimensions
aws glue start-job-run \
  --job-name rcv-load-dimensions-dev

# Load facts with INITIAL mode
aws glue start-job-run \
  --job-name rcv-load-facts-dev \
  --arguments '{"--LOAD_TYPE":"INITIAL"}'
```

### 5.3 Validate Load
```sql
-- Connect to Redshift and validate
SELECT COUNT(*) FROM dw.f_registration;
SELECT COUNT(*) FROM dw.f_compliance;
SELECT COUNT(*) FROM dw.f_verification;

-- Check date range
SELECT 
    MIN(d.date_value) AS min_date,
    MAX(d.date_value) AS max_date,
    COUNT(*) AS record_count
FROM dw.f_registration f
JOIN dw.d_date d ON f.registration_date_key = d.date_key;
```

## Step 6: Enable Daily Incremental Pipeline

### 6.1 Start Workflow
```bash
# The workflow is scheduled to run daily at 2 AM
# To run manually:
aws glue start-workflow-run \
  --name rcv-daily-etl-dev
```

### 6.2 Monitor Workflow
```bash
# Check workflow status
aws glue get-workflow-run \
  --name rcv-daily-etl-dev \
  --run-id <run-id>

# View CloudWatch Dashboard
# Navigate to: https://console.aws.amazon.com/cloudwatch/home#dashboards:name=RCV-Pipeline-dev
```

## Step 7: Connect Power BI

### 7.1 Install Redshift ODBC Driver
Download from: https://docs.aws.amazon.com/redshift/latest/mgmt/configure-odbc-connection.html

### 7.2 Configure Connection in Power BI
1. Open Power BI Desktop
2. Get Data → More → Amazon Redshift
3. Enter connection details:
   - Server: `<redshift-endpoint>:5439`
   - Database: `rcvdw`
   - Data Connectivity mode: DirectQuery (recommended)
4. Enter credentials
5. Select tables from `dw` schema

### 7.3 Create Star Schema Relationships
```
Power BI Model:
- F_Registration → D_Date (registration_date_key → date_key)
- F_Registration → D_Code (registration_status_code_key → code_key)
- F_Registration → D_Zipcode (zipcode_key → zipcode_key)
- F_Registration → D_State (state_key → state_key)
- Similar for F_Compliance and F_Verification
```

## Step 8: Validation and Testing

### 8.1 Data Quality Validation
```sql
-- Check for orphaned records
SELECT COUNT(*) 
FROM dw.f_registration f
LEFT JOIN dw.d_date d ON f.registration_date_key = d.date_key
WHERE d.date_key IS NULL;

-- Verify SCD2 logic
SELECT 
    code_id,
    code_value,
    effective_start_dt,
    effective_end_dt,
    is_active
FROM dw.d_code
WHERE code_id = 'REG_STATUS_1'
ORDER BY effective_start_dt;
```

### 8.2 Performance Testing
```sql
-- Test query performance
EXPLAIN
SELECT 
    d.year,
    d.month_name,
    c.code_value AS status,
    COUNT(*) AS registration_count
FROM dw.f_registration f
JOIN dw.d_date d ON f.registration_date_key = d.date_key
JOIN dw.d_code c ON f.registration_status_code_key = c.code_key
WHERE d.year = 2025
GROUP BY d.year, d.month_name, c.code_value;
```

## Troubleshooting

### Glue Job Failures
```bash
# View job logs
aws logs tail /aws-glue/jobs/error --follow

# Check job metrics
aws glue get-job-run \
  --job-name rcv-load-to-staging-dev \
  --run-id <run-id>
```

### Redshift Serverless Performance Issues
- Query latency > 10 seconds consistently
- RPU capacity maxed out
- Frequent query queuing

**Scaling Options**:
- Increase base capacity (32 → 64 → 128 RPUs)
- Increase max capacity for burst workloads
- Optimize queries and data distribution

### Data Quality Issues
```sql
-- Review DQ results
SELECT * FROM staging.dq_results
WHERE status = 'FAIL'
ORDER BY check_timestamp DESC;
```

## Maintenance

### Weekly Tasks
- Review CloudWatch dashboard
- Check DQ results
- Monitor disk space

### Monthly Tasks
- Run archive job
- Review and optimize queries
- Update statistics

### Quarterly Tasks
- Review and update dimension data
- Audit access logs
- Capacity planning
