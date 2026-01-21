#!/bin/bash
# Deploy RCV Data Platform to Isengard Account (Non-Interactive)
# Usage: ./deploy-isengard-auto.sh <redshift-password> <alert-email>

set -e

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <redshift-password> <alert-email>"
    echo "Example: $0 'MySecurePass123!' 'your-email@example.com'"
    exit 1
fi

REDSHIFT_PASSWORD="$1"
ALERT_EMAIL="$2"
REDSHIFT_USER="admin"
ENVIRONMENT="dev"
REGION="us-east-1"
STACK_NAME="rcv-data-platform-${ENVIRONMENT}"

# Validate
if [ ${#REDSHIFT_PASSWORD} -lt 8 ]; then
    echo "❌ Password must be at least 8 characters"
    exit 1
fi

echo "🚀 RCV Data Platform - Isengard Deployment"
echo "=========================================="
echo ""

# Get AWS account
echo "🔍 Checking AWS credentials..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")

if [ -z "$ACCOUNT_ID" ]; then
    echo "❌ Not authenticated to AWS. Please run:"
    echo "   aws configure"
    echo "   OR"
    echo "   export AWS_PROFILE=your-isengard-profile"
    exit 1
fi

echo "✅ Connected to AWS Account: $ACCOUNT_ID"
echo "✅ Region: $REGION"

# Create parameters
cat > /tmp/cfn-parameters.json << EOF
[
  {"ParameterKey": "Environment", "ParameterValue": "${ENVIRONMENT}"},
  {"ParameterKey": "RedshiftMasterUsername", "ParameterValue": "${REDSHIFT_USER}"},
  {"ParameterKey": "RedshiftMasterPassword", "ParameterValue": "${REDSHIFT_PASSWORD}"}
]
EOF

# Validate template
echo ""
echo "✅ Validating template..."
aws cloudformation validate-template \
  --template-body file://infrastructure/cloudformation-stack.yaml \
  --region ${REGION} > /dev/null

# Deploy
echo ""
echo "🚀 Deploying stack: ${STACK_NAME}..."
aws cloudformation create-stack \
  --stack-name ${STACK_NAME} \
  --template-body file://infrastructure/cloudformation-stack.yaml \
  --parameters file:///tmp/cfn-parameters.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ${REGION}

echo "✅ Stack creation initiated"
echo ""
echo "⏳ Waiting for completion (~10-15 minutes)..."

# Wait
aws cloudformation wait stack-create-complete \
  --stack-name ${STACK_NAME} \
  --region ${REGION}

echo ""
echo "✅ Deployment complete!"

# Get outputs
aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${REGION} \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table

# Save outputs
REDSHIFT_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${REGION} \
  --query 'Stacks[0].Outputs[?OutputKey==`RedshiftServerlessEndpoint`].OutputValue' \
  --output text)

cat > .env.deployed << EOF
ENVIRONMENT=${ENVIRONMENT}
AWS_REGION=${REGION}
AWS_ACCOUNT_ID=${ACCOUNT_ID}
STACK_NAME=${STACK_NAME}
REDSHIFT_ENDPOINT=${REDSHIFT_ENDPOINT}
REDSHIFT_USERNAME=${REDSHIFT_USER}
ALERT_EMAIL=${ALERT_EMAIL}
EOF

rm -f /tmp/cfn-parameters.json

echo ""
echo "🎉 Success! Next: Run DDL scripts to setup Redshift tables"
echo "   source .env.deployed"
echo "   psql -h \${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439"
