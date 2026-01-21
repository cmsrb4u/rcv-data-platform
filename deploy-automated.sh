#!/bin/bash
# Fully Automated RCV Data Platform Deployment
# Generates credentials and deploys everything automatically

set -e

echo "🚀 RCV Data Platform - Fully Automated Deployment"
echo "=================================================="
echo ""

# Configuration
ENVIRONMENT="dev"
REGION="us-east-1"
STACK_NAME="rcv-data-platform-${ENVIRONMENT}"

# Generate secure random password
echo "🔐 Generating secure credentials..."
REDSHIFT_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
REDSHIFT_USER="admin"

# Get user email from git config or use default
ALERT_EMAIL=$(git config user.email 2>/dev/null || echo "admin@example.com")

echo "✅ Credentials generated"
echo "   Username: ${REDSHIFT_USER}"
echo "   Password: ${REDSHIFT_PASSWORD}"
echo "   Alert Email: ${ALERT_EMAIL}"
echo ""

# Check AWS authentication
echo "🔍 Checking AWS credentials..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")

if [ -z "$ACCOUNT_ID" ]; then
    echo "❌ Not authenticated to AWS"
    echo "Please run: aws configure"
    exit 1
fi

echo "✅ AWS Account: ${ACCOUNT_ID}"
echo "✅ Region: ${REGION}"
echo ""

# Create parameters file
cat > /tmp/cfn-params.json << EOF
[
  {"ParameterKey": "Environment", "ParameterValue": "${ENVIRONMENT}"},
  {"ParameterKey": "RedshiftMasterUsername", "ParameterValue": "${REDSHIFT_USER}"},
  {"ParameterKey": "RedshiftMasterPassword", "ParameterValue": "${REDSHIFT_PASSWORD}"}
]
EOF

# Validate template
echo "✅ Validating CloudFormation template..."
aws cloudformation validate-template \
  --template-body file://infrastructure/cloudformation-stack.yaml \
  --region ${REGION} > /dev/null 2>&1

# Deploy infrastructure
echo ""
echo "🚀 Deploying infrastructure stack..."
aws cloudformation create-stack \
  --stack-name ${STACK_NAME} \
  --template-body file://infrastructure/cloudformation-stack.yaml \
  --parameters file:///tmp/cfn-params.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ${REGION} \
  --tags Key=Project,Value=RCV Key=Environment,Value=${ENVIRONMENT} \
  > /dev/null 2>&1

echo "✅ Stack creation initiated"
echo ""
echo "⏳ Waiting for infrastructure deployment (~10-15 minutes)..."
echo "   Monitoring progress..."

# Wait for stack creation
aws cloudformation wait stack-create-complete \
  --stack-name ${STACK_NAME} \
  --region ${REGION}

echo ""
echo "✅ Infrastructure deployed successfully!"

# Get stack outputs
echo ""
echo "📊 Retrieving stack outputs..."
REDSHIFT_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${REGION} \
  --query 'Stacks[0].Outputs[?OutputKey==`RedshiftServerlessEndpoint`].OutputValue' \
  --output text)

RAW_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${REGION} \
  --query 'Stacks[0].Outputs[?OutputKey==`RawDataBucketName`].OutputValue' \
  --output text)

ARCHIVE_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${REGION} \
  --query 'Stacks[0].Outputs[?OutputKey==`ArchiveBucketName`].OutputValue' \
  --output text)

GLUE_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${REGION} \
  --query 'Stacks[0].Outputs[?OutputKey==`GlueRoleArn`].OutputValue' \
  --output text)

echo "✅ Outputs retrieved"
echo ""

# Save credentials and outputs
cat > .deployment-info << EOF
# RCV Data Platform - Deployment Information
# Generated: $(date)

# AWS Configuration
AWS_ACCOUNT_ID=${ACCOUNT_ID}
AWS_REGION=${REGION}
STACK_NAME=${STACK_NAME}

# Redshift Serverless
REDSHIFT_ENDPOINT=${REDSHIFT_ENDPOINT}
REDSHIFT_USERNAME=${REDSHIFT_USER}
REDSHIFT_PASSWORD=${REDSHIFT_PASSWORD}
REDSHIFT_DATABASE=rcvdw
REDSHIFT_PORT=5439

# S3 Buckets
RAW_BUCKET=${RAW_BUCKET}
ARCHIVE_BUCKET=${ARCHIVE_BUCKET}

# IAM
GLUE_ROLE_ARN=${GLUE_ROLE_ARN}

# Monitoring
ALERT_EMAIL=${ALERT_EMAIL}
EOF

echo "💾 Deployment info saved to .deployment-info"
echo ""

# Setup Redshift schemas and tables
echo "🗄️  Setting up Redshift database..."
echo "   Creating schemas..."

# Create SQL setup script
cat > /tmp/setup-redshift.sql << 'EOF'
-- Create schemas
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS dw;

-- Verify schemas
SELECT schema_name FROM information_schema.schemata 
WHERE schema_name IN ('staging', 'dw');
EOF

# Execute schema creation
PGPASSWORD=${REDSHIFT_PASSWORD} psql \
  -h ${REDSHIFT_ENDPOINT} \
  -U ${REDSHIFT_USER} \
  -d rcvdw \
  -p 5439 \
  -f /tmp/setup-redshift.sql \
  > /dev/null 2>&1

echo "✅ Schemas created"

# Create staging tables
echo "   Creating staging tables..."
PGPASSWORD=${REDSHIFT_PASSWORD} psql \
  -h ${REDSHIFT_ENDPOINT} \
  -U ${REDSHIFT_USER} \
  -d rcvdw \
  -p 5439 \
  -f redshift/staging/00_create_staging.sql \
  > /dev/null 2>&1

echo "✅ Staging tables created"

# Create dimension tables
echo "   Creating dimension tables..."
PGPASSWORD=${REDSHIFT_PASSWORD} psql \
  -h ${REDSHIFT_ENDPOINT} \
  -U ${REDSHIFT_USER} \
  -d rcvdw \
  -p 5439 \
  -f redshift/dimensions/01_create_dimensions.sql \
  > /dev/null 2>&1

echo "✅ Dimension tables created"

# Create fact tables
echo "   Creating fact tables..."
PGPASSWORD=${REDSHIFT_PASSWORD} psql \
  -h ${REDSHIFT_ENDPOINT} \
  -U ${REDSHIFT_USER} \
  -d rcvdw \
  -p 5439 \
  -f redshift/facts/02_create_facts.sql \
  > /dev/null 2>&1

echo "✅ Fact tables created"

# Populate reference data
echo "   Populating reference data..."
PGPASSWORD=${REDSHIFT_PASSWORD} psql \
  -h ${REDSHIFT_ENDPOINT} \
  -U ${REDSHIFT_USER} \
  -d rcvdw \
  -p 5439 \
  -f redshift/dimensions/03_populate_reference_data.sql \
  > /dev/null 2>&1

echo "✅ Reference data populated"
echo ""

# Upload Glue scripts
echo "📤 Uploading Glue scripts to S3..."
aws s3 cp glue/ s3://${RAW_BUCKET}/glue-scripts/ --recursive --quiet

echo "✅ Glue scripts uploaded"
echo ""

# Create Glue connection
echo "🔗 Creating Glue connection to Redshift..."

# Get VPC info
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" \
  --query 'Vpcs[0].VpcId' \
  --output text)

SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query 'Subnets[0].SubnetId' \
  --output text)

SECURITY_GROUP=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=*Glue*" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

# Create Glue connection
aws glue create-connection \
  --connection-input "{
    \"Name\": \"rcv-redshift-connection\",
    \"ConnectionType\": \"JDBC\",
    \"ConnectionProperties\": {
      \"JDBC_CONNECTION_URL\": \"jdbc:redshift://${REDSHIFT_ENDPOINT}:5439/rcvdw\",
      \"USERNAME\": \"${REDSHIFT_USER}\",
      \"PASSWORD\": \"${REDSHIFT_PASSWORD}\"
    },
    \"PhysicalConnectionRequirements\": {
      \"SubnetId\": \"${SUBNET_ID}\",
      \"SecurityGroupIdList\": [\"${SECURITY_GROUP}\"],
      \"AvailabilityZone\": \"${REGION}a\"
    }
  }" \
  --region ${REGION} \
  > /dev/null 2>&1

echo "✅ Glue connection created"
echo ""

# Create Glue database
echo "📚 Creating Glue database..."
aws glue create-database \
  --database-input "{
    \"Name\": \"rcv_${ENVIRONMENT}\",
    \"Description\": \"RCV data catalog\"
  }" \
  --region ${REGION} \
  > /dev/null 2>&1

echo "✅ Glue database created"
echo ""

# Deploy Glue jobs stack
echo "🚀 Deploying Glue jobs..."

cat > /tmp/glue-params.json << EOF
[
  {"ParameterKey": "Environment", "ParameterValue": "${ENVIRONMENT}"},
  {"ParameterKey": "GlueRoleArn", "ParameterValue": "${GLUE_ROLE_ARN}"},
  {"ParameterKey": "RedshiftConnection", "ParameterValue": "rcv-redshift-connection"},
  {"ParameterKey": "RawBucket", "ParameterValue": "${RAW_BUCKET}"},
  {"ParameterKey": "ArchiveBucket", "ParameterValue": "${ARCHIVE_BUCKET}"}
]
EOF

aws cloudformation create-stack \
  --stack-name ${STACK_NAME}-glue-jobs \
  --template-body file://infrastructure/glue-jobs.yaml \
  --parameters file:///tmp/glue-params.json \
  --region ${REGION} \
  > /dev/null 2>&1

echo "⏳ Waiting for Glue jobs deployment..."
aws cloudformation wait stack-create-complete \
  --stack-name ${STACK_NAME}-glue-jobs \
  --region ${REGION}

echo "✅ Glue jobs deployed"
echo ""

# Deploy monitoring
echo "📊 Deploying monitoring..."

cat > /tmp/monitoring-params.json << EOF
[
  {"ParameterKey": "Environment", "ParameterValue": "${ENVIRONMENT}"},
  {"ParameterKey": "AlertEmail", "ParameterValue": "${ALERT_EMAIL}"}
]
EOF

aws cloudformation create-stack \
  --stack-name ${STACK_NAME}-monitoring \
  --template-body file://monitoring/cloudwatch-monitoring.yaml \
  --parameters file:///tmp/monitoring-params.json \
  --region ${REGION} \
  > /dev/null 2>&1

echo "⏳ Waiting for monitoring deployment..."
aws cloudformation wait stack-create-complete \
  --stack-name ${STACK_NAME}-monitoring \
  --region ${REGION}

echo "✅ Monitoring deployed"
echo ""

# Cleanup temp files
rm -f /tmp/cfn-params.json /tmp/glue-params.json /tmp/monitoring-params.json /tmp/setup-redshift.sql

# Generate summary report
cat > deployment-summary.txt << EOF
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║   🎉 RCV DATA PLATFORM - DEPLOYMENT COMPLETE!                        ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝

Deployment Date: $(date)
AWS Account: ${ACCOUNT_ID}
Region: ${REGION}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 DEPLOYED RESOURCES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Infrastructure Stack: ${STACK_NAME}
   - VPC with private subnets
   - Redshift Serverless (32 RPUs)
   - S3 buckets (raw, archive, scripts)
   - IAM roles (Glue, Redshift)
   - Security groups

✅ Redshift Database: rcvdw
   - Schemas: staging, dw
   - Staging tables: 8 tables
   - Dimension tables: 11 tables
   - Fact tables: 6 tables (3 current + 3 history)
   - Reference data: 20 years of dates, codes, data sources

✅ Glue Jobs: 5 ETL jobs
   - load_to_staging
   - data_quality_checks
   - load_dimensions_scd2
   - load_fact_registration
   - archive_old_data

✅ Glue Workflow: rcv-daily-etl-${ENVIRONMENT}
   - Scheduled: Daily at 2 AM
   - Orchestrates all ETL jobs

✅ Monitoring: CloudWatch + SNS
   - Dashboard: RCV-Pipeline-${ENVIRONMENT}
   - Alarms: Job failures, performance
   - Alerts: ${ALERT_EMAIL}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔐 CREDENTIALS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Redshift Endpoint: ${REDSHIFT_ENDPOINT}
Database: rcvdw
Port: 5439
Username: ${REDSHIFT_USER}
Password: ${REDSHIFT_PASSWORD}

⚠️  IMPORTANT: Save these credentials securely!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔗 ACCESS URLS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CloudFormation Console:
https://console.aws.amazon.com/cloudformation/home?region=${REGION}#/stacks

Redshift Console:
https://console.aws.amazon.com/redshiftv2/home?region=${REGION}#serverless

Glue Console:
https://console.aws.amazon.com/glue/home?region=${REGION}#/v2/etl-configuration/jobs

CloudWatch Dashboard:
https://console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards:name=RCV-Pipeline-${ENVIRONMENT}

S3 Buckets:
https://s3.console.aws.amazon.com/s3/buckets/${RAW_BUCKET}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 NEXT STEPS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Connect to Redshift:
   psql -h ${REDSHIFT_ENDPOINT} -U ${REDSHIFT_USER} -d rcvdw -p 5439

2. Verify tables created:
   SELECT schemaname, tablename FROM pg_tables 
   WHERE schemaname IN ('staging', 'dw');

3. Upload sample data to S3:
   aws s3 cp sample_data/ s3://${RAW_BUCKET}/raw/registration/ --recursive

4. Run ETL workflow:
   aws glue start-workflow-run --name rcv-daily-etl-${ENVIRONMENT}

5. Connect Power BI:
   - Server: ${REDSHIFT_ENDPOINT}:5439
   - Database: rcvdw
   - Username: ${REDSHIFT_USER}
   - Password: ${REDSHIFT_PASSWORD}

6. Confirm SNS subscription:
   - Check email: ${ALERT_EMAIL}
   - Click "Confirm subscription" link

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💰 COST ESTIMATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Monthly (Dev - 2 hours/day usage):
- Redshift Serverless: ~\$580
- S3: ~\$47
- Glue: ~\$100
- CloudWatch: ~\$15
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total: ~\$742/month

💡 Tip: Redshift auto-pauses when idle (no charges)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📚 DOCUMENTATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- Deployment Info: .deployment-info
- Architecture: ARCHITECTURE.md
- Deployment Guide: DETAILED_DEPLOYMENT_GUIDE.md
- Cost Analysis: COST_ESTIMATION.md
- Quick Reference: QUICK_REFERENCE.md
- Code Explanations: CODE_EXPLANATION_SCD2.md

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🎉 Your RCV Data Platform is ready to use!

EOF

cat deployment-summary.txt

echo ""
echo "📄 Full summary saved to: deployment-summary.txt"
echo "📄 Credentials saved to: .deployment-info"
echo ""
echo "✅ Deployment completed successfully!"
