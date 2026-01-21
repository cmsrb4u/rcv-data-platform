# Isengard Deployment Instructions

## Quick Deploy to Isengard

### Option 1: Interactive Deployment
```bash
cd ~/rcv-data-platform
./deploy-to-isengard.sh
```

You'll be prompted for:
- Redshift master username (default: admin)
- Redshift master password (min 8 chars)
- Alert email address

### Option 2: Non-Interactive Deployment
```bash
cd ~/rcv-data-platform
./deploy-isengard-auto.sh 'YourSecurePassword123!' 'your-email@example.com'
```

## Prerequisites

### 1. AWS CLI Authentication
Make sure you're authenticated to your Isengard account:

```bash
# Check current credentials
aws sts get-caller-identity

# If not authenticated, configure AWS CLI
aws configure

# OR use AWS profile
export AWS_PROFILE=your-isengard-profile
aws sts get-caller-identity
```

### 2. Required Permissions
Your IAM user/role needs:
- CloudFormation: Full access
- S3: Create buckets
- Redshift Serverless: Create namespace/workgroup
- VPC: Create VPC, subnets, security groups
- IAM: Create roles and policies
- Glue: Create database, jobs
- CloudWatch: Create dashboards, alarms
- SNS: Create topics

## Deployment Steps

### Step 1: Deploy Infrastructure
```bash
cd ~/rcv-data-platform

# Run deployment script
./deploy-isengard-auto.sh 'MySecurePass123!' 'myemail@example.com'

# This will:
# - Validate CloudFormation template
# - Create stack (10-15 minutes)
# - Save outputs to .env.deployed
```

### Step 2: Setup Redshift
```bash
# Load environment variables
source .env.deployed

# Connect to Redshift
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439

# Create schemas
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS dw;
\q

# Run DDL scripts
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 -f redshift/staging/00_create_staging.sql
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 -f redshift/dimensions/01_create_dimensions.sql
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 -f redshift/facts/02_create_facts.sql
psql -h ${REDSHIFT_ENDPOINT} -U admin -d rcvdw -p 5439 -f redshift/dimensions/03_populate_reference_data.sql
```

### Step 3: Deploy Glue Jobs
```bash
# Get bucket name
RAW_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name rcv-data-platform-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`RawDataBucketName`].OutputValue' \
  --output text)

# Upload Glue scripts
aws s3 cp glue/ s3://${RAW_BUCKET}/glue-scripts/ --recursive

# Create Glue connection
# (See DETAILED_DEPLOYMENT_GUIDE_PART2.md for full steps)
```

## Monitoring Deployment

### Check Stack Status
```bash
aws cloudformation describe-stacks \
  --stack-name rcv-data-platform-dev \
  --query 'Stacks[0].StackStatus'
```

### View Stack Events
```bash
aws cloudformation describe-stack-events \
  --stack-name rcv-data-platform-dev \
  --max-items 10 \
  --query 'StackEvents[*].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId]' \
  --output table
```

### View in Console
```
https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks
```

## Troubleshooting

### Issue: Authentication Failed
```bash
# Check credentials
aws sts get-caller-identity

# If expired, re-authenticate
aws configure
# OR
export AWS_PROFILE=your-profile
```

### Issue: Stack Creation Failed
```bash
# Get error details
aws cloudformation describe-stack-events \
  --stack-name rcv-data-platform-dev \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]' \
  --output table

# Delete failed stack
aws cloudformation delete-stack --stack-name rcv-data-platform-dev

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name rcv-data-platform-dev

# Try again
./deploy-isengard-auto.sh 'password' 'email'
```

### Issue: Cannot Connect to Redshift
```bash
# Add your IP to security group
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

## Cleanup

### Delete Stack
```bash
# Delete CloudFormation stack
aws cloudformation delete-stack --stack-name rcv-data-platform-dev

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name rcv-data-platform-dev

# Verify deletion
aws cloudformation list-stacks \
  --stack-status-filter DELETE_COMPLETE \
  --query 'StackSummaries[?StackName==`rcv-data-platform-dev`]'
```

### Manual Cleanup (if needed)
```bash
# Delete S3 buckets (must be empty first)
aws s3 rm s3://rcv-raw-data-dev-${ACCOUNT_ID} --recursive
aws s3 rb s3://rcv-raw-data-dev-${ACCOUNT_ID}

aws s3 rm s3://rcv-archive-dev-${ACCOUNT_ID} --recursive
aws s3 rb s3://rcv-archive-dev-${ACCOUNT_ID}
```

## Cost Estimate

**Monthly cost for dev environment:**
- Redshift Serverless: ~$580 (2 hours/day)
- S3: ~$47
- Glue: ~$100
- CloudWatch: ~$15
- **Total: ~$742/month**

**To minimize costs:**
- Redshift auto-pauses when idle (no charges)
- Delete stack when not in use
- Use S3 lifecycle policies

## Next Steps

After successful deployment:

1. ✅ Review deployment outputs
2. ✅ Setup Redshift tables (DDL scripts)
3. ✅ Deploy Glue jobs
4. ✅ Setup monitoring
5. ✅ Load sample data
6. ✅ Connect Power BI

See **DETAILED_DEPLOYMENT_GUIDE.md** for complete instructions.

## Support

- Documentation: See all `*.md` files in repository
- Issues: https://github.com/cmsrb4u/rcv-data-platform/issues
- AWS Support: https://console.aws.amazon.com/support/
