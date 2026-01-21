#!/bin/bash
# Deploy RCV Data Platform to Isengard Account

set -e  # Exit on error

echo "🚀 RCV Data Platform - Isengard Deployment"
echo "=========================================="
echo ""

# Configuration
ENVIRONMENT="dev"
REGION="us-east-1"
STACK_NAME="rcv-data-platform-${ENVIRONMENT}"

# Prompt for Redshift credentials
echo "📝 Enter Redshift credentials:"
read -p "Master Username [admin]: " REDSHIFT_USER
REDSHIFT_USER=${REDSHIFT_USER:-admin}

read -sp "Master Password (min 8 chars): " REDSHIFT_PASSWORD
echo ""

read -p "Alert Email: " ALERT_EMAIL

# Validate inputs
if [ -z "$REDSHIFT_PASSWORD" ] || [ ${#REDSHIFT_PASSWORD} -lt 8 ]; then
    echo "❌ Password must be at least 8 characters"
    exit 1
fi

if [ -z "$ALERT_EMAIL" ]; then
    echo "❌ Alert email is required"
    exit 1
fi

# Get AWS account info
echo ""
echo "🔍 Checking AWS credentials..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "✅ Connected to AWS Account: $ACCOUNT_ID"
echo "✅ Region: $REGION"

# Create parameters file
echo ""
echo "📄 Creating parameters file..."
cat > /tmp/cfn-parameters.json << EOF
[
  {
    "ParameterKey": "Environment",
    "ParameterValue": "${ENVIRONMENT}"
  },
  {
    "ParameterKey": "RedshiftMasterUsername",
    "ParameterValue": "${REDSHIFT_USER}"
  },
  {
    "ParameterKey": "RedshiftMasterPassword",
    "ParameterValue": "${REDSHIFT_PASSWORD}"
  }
]
EOF

# Validate template
echo ""
echo "✅ Validating CloudFormation template..."
aws cloudformation validate-template \
  --template-body file://infrastructure/cloudformation-stack.yaml \
  --region ${REGION} > /dev/null

echo "✅ Template is valid"

# Deploy stack
echo ""
echo "🚀 Deploying CloudFormation stack..."
echo "   Stack Name: ${STACK_NAME}"
echo "   Region: ${REGION}"
echo ""

aws cloudformation create-stack \
  --stack-name ${STACK_NAME} \
  --template-body file://infrastructure/cloudformation-stack.yaml \
  --parameters file:///tmp/cfn-parameters.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ${REGION} \
  --tags Key=Project,Value=RCV-Data-Platform Key=Environment,Value=${ENVIRONMENT}

echo "✅ Stack creation initiated"
echo ""
echo "⏳ Waiting for stack creation to complete (this takes ~10-15 minutes)..."
echo "   You can monitor progress in the AWS Console:"
echo "   https://console.aws.amazon.com/cloudformation/home?region=${REGION}#/stacks"
echo ""

# Wait for stack creation
aws cloudformation wait stack-create-complete \
  --stack-name ${STACK_NAME} \
  --region ${REGION}

echo ""
echo "✅ Stack creation completed!"

# Get outputs
echo ""
echo "📊 Stack Outputs:"
echo "================="
aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${REGION} \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table

# Save outputs to file
echo ""
echo "💾 Saving outputs to deployment-outputs.txt..."
aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${REGION} \
  --query 'Stacks[0].Outputs' \
  --output json > deployment-outputs.txt

# Extract key values
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

# Create environment file
cat > .env.deployed << EOF
# RCV Data Platform - Deployed Configuration
ENVIRONMENT=${ENVIRONMENT}
AWS_REGION=${REGION}
AWS_ACCOUNT_ID=${ACCOUNT_ID}
STACK_NAME=${STACK_NAME}
REDSHIFT_ENDPOINT=${REDSHIFT_ENDPOINT}
REDSHIFT_USERNAME=${REDSHIFT_USER}
RAW_BUCKET=${RAW_BUCKET}
ALERT_EMAIL=${ALERT_EMAIL}
DEPLOYED_AT=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF

echo "✅ Environment variables saved to .env.deployed"

# Clean up temp files
rm -f /tmp/cfn-parameters.json

echo ""
echo "🎉 Deployment Complete!"
echo "======================="
echo ""
echo "📋 Next Steps:"
echo "1. Setup Redshift schemas and tables:"
echo "   source .env.deployed"
echo "   psql -h \${REDSHIFT_ENDPOINT} -U ${REDSHIFT_USER} -d rcvdw -p 5439"
echo ""
echo "2. Run DDL scripts:"
echo "   psql -h \${REDSHIFT_ENDPOINT} -U ${REDSHIFT_USER} -d rcvdw -f redshift/staging/00_create_staging.sql"
echo "   psql -h \${REDSHIFT_ENDPOINT} -U ${REDSHIFT_USER} -d rcvdw -f redshift/dimensions/01_create_dimensions.sql"
echo "   psql -h \${REDSHIFT_ENDPOINT} -U ${REDSHIFT_USER} -d rcvdw -f redshift/facts/02_create_facts.sql"
echo ""
echo "3. Deploy Glue jobs (see DETAILED_DEPLOYMENT_GUIDE_PART2.md)"
echo ""
echo "📖 Full deployment guide: DETAILED_DEPLOYMENT_GUIDE.md"
echo ""
