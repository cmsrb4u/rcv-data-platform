# RCV Data Platform - Detailed Deployment Guide

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Phase 1: AWS Account Setup](#phase-1-aws-account-setup)
3. [Phase 2: Deploy Infrastructure](#phase-2-deploy-infrastructure)
4. [Phase 3: Setup Redshift Serverless](#phase-3-setup-redshift-serverless)
5. [Phase 4: Deploy Glue Jobs](#phase-4-deploy-glue-jobs)
6. [Phase 5: Setup Monitoring](#phase-5-setup-monitoring)
7. [Phase 6: Initial Data Load](#phase-6-initial-data-load)
8. [Phase 7: Power BI Connection](#phase-7-power-bi-connection)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools
```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# Verify installation
aws --version  # Should show aws-cli/2.x.x

# Install PostgreSQL client (for Redshift)
brew install postgresql

# Verify psql
psql --version  # Should show psql (PostgreSQL) 14.x or higher
```

### AWS Account Requirements
- AWS Account with admin access
- AWS CLI configured with credentials
- Budget: ~$3,500/month for production

### Configure AWS CLI
```bash
# Configure credentials
aws configure

# Enter when prompted:
# AWS Access Key ID: [Your Access Key]
# AWS Secret Access Key: [Your Secret Key]
# Default region name: us-east-1
# Default output format: json

# Test configuration
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AIDACKCEVSQ6C2EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

---

## Phase 1: AWS Account Setup

### Step 1.1: Clone the Repository
```bash
cd ~
git clone https://github.com/cmsrb4u/rcv-data-platform.git
cd rcv-data-platform
```

### Step 1.2: Set Environment Variables
```bash
# Create environment configuration
cat > .env << 'EOF'
# Environment
ENVIRONMENT=dev
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Redshift Credentials
REDSHIFT_MASTER_USERNAME=admin
REDSHIFT_MASTER_PASSWORD=YourSecurePassword123!

# Email for alerts
ALERT_EMAIL=your-email@example.com

# Project naming
PROJECT_NAME=rcv-data-platform
STACK_NAME=${PROJECT_NAME}-${ENVIRONMENT}
EOF

# Load environment variables
source .env

# Verify
echo "Account ID: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "Stack Name: $STACK_NAME"
```

### Step 1.3: Validate CloudFormation Templates
```bash
# Validate main infrastructure template
aws cloudformation validate-template \
  --template-body file://infrastructure/cloudformation-stack.yaml

# Expected output: "Parameters": [...], "Description": "..."

# Validate Glue jobs template
aws cloudformation validate-template \
  --template-body file://infrastructure/glue-jobs.yaml

# Validate monitoring template
aws cloudformation validate-template \
  --template-body file://monitoring/cloudwatch-monitoring.yaml
```

---

## Phase 2: Deploy Infrastructure

### Step 2.1: Create Parameters File
```bash
# Create parameters for CloudFormation
cat > infrastructure/parameters-dev.json << EOF
[
  {
    "ParameterKey": "Environment",
    "ParameterValue": "dev"
  },
  {
    "ParameterKey": "RedshiftMasterUsername",
    "ParameterValue": "admin"
  },
  {
    "ParameterKey": "RedshiftMasterPassword",
    "ParameterValue": "YourSecurePassword123!"
  }
]
EOF
```

**⚠️ Security Note:** Never commit passwords to Git. Use AWS Secrets Manager in production.

### Step 2.2: Deploy Core Infrastructure
```bash
# Deploy the stack
aws cloudformation create-stack \
  --stack-name ${STACK_NAME} \
  --template-body file://infrastructure/cloudformation-stack.yaml \
  --parameters file://infrastructure/parameters-dev.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ${AWS_REGION}

# Expected output:
# {
#     "StackId": "arn:aws:cloudformation:us-east-1:123456789012:stack/rcv-data-platform-dev/..."
# }
```

### Step 2.3: Monitor Stack Creation
```bash
# Watch stack creation progress
aws cloudformation describe-stack-events \
  --stack-name ${STACK_NAME} \
  --query 'StackEvents[0:10].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId]' \
  --output table

# Wait for completion (takes ~10-15 minutes)
aws cloudformation wait stack-create-complete \
  --stack-name ${STACK_NAME}

echo "✅ Stack creation complete!"
```

### Step 2.4: Retrieve Stack Outputs
```bash
# Get all outputs
aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs' \
  --output table

# Save specific outputs to variables
export REDSHIFT_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`RedshiftServerlessEndpoint`].OutputValue' \
  --output text)

export RAW_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`RawDataBucketName`].OutputValue' \
  --output text)

export ARCHIVE_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`ArchiveBucketName`].OutputValue' \
  --output text)

export GLUE_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`GlueRoleArn`].OutputValue' \
  --output text)

# Verify
echo "Redshift Endpoint: $REDSHIFT_ENDPOINT"
echo "Raw Bucket: $RAW_BUCKET"
echo "Archive Bucket: $ARCHIVE_BUCKET"
echo "Glue Role ARN: $GLUE_ROLE_ARN"
```

### Step 2.5: Verify Resources Created
```bash
# Check S3 buckets
aws s3 ls | grep rcv

# Expected output:
# 2026-01-20 20:00:00 rcv-raw-data-dev-123456789012
# 2026-01-20 20:00:00 rcv-archive-dev-123456789012
# 2026-01-20 20:00:00 rcv-glue-scripts-dev-123456789012

# Check Redshift Serverless
aws redshift-serverless get-workgroup \
  --workgroup-name rcv-dw-dev \
  --query 'workgroup.[workgroupName,status,endpoint.address]' \
  --output table

# Expected status: AVAILABLE

# Check IAM roles
aws iam list-roles --query 'Roles[?contains(RoleName, `RCV`)].RoleName'
```

---

## Phase 3: Setup Redshift Serverless

### Step 3.1: Test Connection
```bash
# Test connection to Redshift Serverless
psql -h ${REDSHIFT_ENDPOINT} \
     -U admin \
     -d rcvdw \
     -p 5439 \
     -c "SELECT version();"

# You'll be prompted for password: YourSecurePassword123!

# Expected output:
# PostgreSQL 8.0.2 on ... compiled by ... Redshift ...
```

**Troubleshooting Connection Issues:**
```bash
# If connection fails, check security group
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*Redshift*" \
  --query 'SecurityGroups[0].IpPermissions'

# Add your IP if needed
MY_IP=$(curl -s https://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress \
  --group-id <security-group-id> \
  --protocol tcp \
  --port 5439 \
  --cidr ${MY_IP}/32
```

### Step 3.2: Create Schemas
```bash
# Create staging and dw schemas
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 << 'EOF'
-- Create schemas
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS dw;

-- Verify schemas created
SELECT schema_name 
FROM information_schema.schemata 
WHERE schema_name IN ('staging', 'dw');

-- Expected output:
--  schema_name
-- -------------
--  staging
--  dw
EOF
```

### Step 3.3: Create Staging Tables
```bash
# Run staging DDL script
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 \
  -f redshift/staging/00_create_staging.sql

# Verify tables created
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 << 'EOF'
SELECT 
    schemaname,
    tablename,
    tableowner
FROM pg_tables
WHERE schemaname = 'staging'
ORDER BY tablename;
EOF

# Expected output:
#  schemaname |        tablename         | tableowner
# ------------+--------------------------+------------
#  staging    | dq_results               | admin
#  staging    | etl_control              | admin
#  staging    | stg_census               | admin
#  staging    | stg_compliance           | admin
#  staging    | stg_county_demographics  | admin
#  staging    | stg_registration         | admin
#  staging    | stg_verification         | admin
#  staging    | stg_zip_geography        | admin
```

**What This Script Does:**
- Creates 8 staging tables for raw data
- Creates control tables for ETL metadata
- Creates data quality results table
- Sets up appropriate distribution styles

### Step 3.4: Create Dimension Tables
```bash
# Run dimension DDL script
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 \
  -f redshift/dimensions/01_create_dimensions.sql

# Verify dimensions created
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 << 'EOF'
SELECT 
    tablename,
    CASE 
        WHEN tablename LIKE 'd_%' THEN 'Dimension'
        ELSE 'Other'
    END as table_type
FROM pg_tables
WHERE schemaname = 'dw'
  AND tablename LIKE 'd_%'
ORDER BY tablename;
EOF

# Expected output: 9 dimension tables
#        tablename         | table_type
# -------------------------+------------
#  d_census                | Dimension
#  d_code                  | Dimension
#  d_code_category         | Dimension
#  d_country               | Dimension
#  d_county_demographics   | Dimension
#  d_data_source_config... | Dimension
#  d_date                  | Dimension
#  d_file_information      | Dimension
#  d_state                 | Dimension
#  d_zip_geography         | Dimension
#  d_zipcode               | Dimension
```

**What This Script Does:**
- Creates 11 dimension tables with SCD Type 2 support
- Sets up primary keys and foreign keys
- Creates indexes for performance
- Configures distribution styles (ALL for small dimensions)

### Step 3.5: Create Fact Tables
```bash
# Run fact DDL script
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 \
  -f redshift/facts/02_create_facts.sql

# Verify facts created
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 << 'EOF'
SELECT 
    tablename,
    CASE 
        WHEN tablename LIKE 'f_%_hist' THEN 'History Fact'
        WHEN tablename LIKE 'f_%' THEN 'Fact'
        ELSE 'Other'
    END as table_type
FROM pg_tables
WHERE schemaname = 'dw'
  AND tablename LIKE 'f_%'
ORDER BY table_type, tablename;
EOF

# Expected output: 6 fact tables (3 current + 3 history)
#        tablename         |  table_type
# -------------------------+--------------
#  f_compliance            | Fact
#  f_registration          | Fact
#  f_verification          | Fact
#  f_compliance_hist       | History Fact
#  f_registration_hist     | History Fact
#  f_verification_hist     | History Fact
```

**What This Script Does:**
- Creates 3 fact tables (Registration, Compliance, Verification)
- Creates 3 history fact tables for change tracking
- Sets up foreign keys to dimensions
- Configures distribution keys for performance
- Creates indexes on frequently queried columns

### Step 3.6: Populate Reference Data
```bash
# Run reference data population script
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 \
  -f redshift/dimensions/03_populate_reference_data.sql

# Verify data loaded
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 << 'EOF'
-- Check date dimension (should have 20 years of dates)
SELECT 
    MIN(date_value) as min_date,
    MAX(date_value) as max_date,
    COUNT(*) as total_dates
FROM dw.d_date;

-- Check code categories
SELECT category_name, COUNT(*) as code_count
FROM dw.d_code_category cc
JOIN dw.d_code c ON cc.code_category_key = c.code_category_key
WHERE cc.is_active = TRUE
GROUP BY category_name;

-- Check data sources
SELECT source_name, source_type, is_enabled
FROM dw.d_data_source_configuration
WHERE is_active = TRUE;
EOF
```

**What This Script Does:**
- Populates D_Date with 20 years of dates (2015-2035)
- Loads code categories (registration types, statuses, etc.)
- Loads codes for each category
- Populates data source configurations
- Loads sample geography data (states, countries)

---

