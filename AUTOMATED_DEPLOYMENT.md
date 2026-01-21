# Fully Automated Deployment - README

## 🚀 One-Command Deployment

I've created a **fully automated deployment script** that:
- ✅ Generates secure credentials automatically
- ✅ Deploys all infrastructure (VPC, Redshift, S3, IAM)
- ✅ Creates all Redshift tables (staging, dimensions, facts)
- ✅ Populates reference data (dates, codes)
- ✅ Deploys all Glue ETL jobs
- ✅ Sets up monitoring and alerts
- ✅ Saves all credentials and outputs

## Prerequisites

You need AWS CLI configured with Isengard credentials:

```bash
# Check if authenticated
aws sts get-caller-identity

# If not, configure AWS CLI
aws configure
# OR
export AWS_PROFILE=your-isengard-profile
```

## Deploy Everything

### Single Command Deployment
```bash
cd ~/rcv-data-platform
./deploy-automated.sh
```

That's it! The script will:
1. Generate secure Redshift password
2. Deploy infrastructure (~10-15 min)
3. Create all database tables
4. Deploy Glue jobs
5. Setup monitoring
6. Generate complete summary

### What Gets Deployed

**Infrastructure:**
- VPC with private subnets
- Redshift Serverless (32 RPUs, auto-pause)
- 3 S3 buckets (raw, archive, scripts)
- IAM roles (Glue, Redshift)
- Security groups

**Database:**
- 2 schemas (staging, dw)
- 8 staging tables
- 11 dimension tables (with SCD Type 2)
- 6 fact tables (3 current + 3 history)
- 20 years of reference data

**ETL:**
- 5 Glue jobs (staging, DQ, dimensions, facts, archive)
- 1 Glue workflow (daily at 2 AM)
- Glue connection to Redshift

**Monitoring:**
- CloudWatch dashboard
- 5 alarms (failures, performance)
- SNS email alerts

## After Deployment

### Files Created

1. **`.deployment-info`** - All credentials and endpoints
2. **`deployment-summary.txt`** - Complete deployment report
3. **`deployment.log`** - Full deployment log

### Access Your Platform

```bash
# Load credentials
source .deployment-info

# Connect to Redshift
psql -h ${REDSHIFT_ENDPOINT} -U ${REDSHIFT_USER} -d rcvdw -p 5439

# View tables
\dt staging.*
\dt dw.*
```

### View in AWS Console

The summary includes direct links to:
- CloudFormation stacks
- Redshift Serverless
- Glue jobs
- CloudWatch dashboard
- S3 buckets

## Cost

**Monthly cost (dev environment):**
- ~$742/month with 2 hours/day usage
- Redshift auto-pauses when idle (no charges)

## Cleanup

To delete everything:
```bash
# Delete all stacks
aws cloudformation delete-stack --stack-name rcv-data-platform-dev-monitoring
aws cloudformation delete-stack --stack-name rcv-data-platform-dev-glue-jobs
aws cloudformation delete-stack --stack-name rcv-data-platform-dev

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name rcv-data-platform-dev
```

## Troubleshooting

### Issue: Not authenticated to AWS
```bash
# Configure AWS CLI
aws configure

# OR use profile
export AWS_PROFILE=isengard
aws sts get-caller-identity
```

### Issue: Stack already exists
```bash
# Delete existing stack first
aws cloudformation delete-stack --stack-name rcv-data-platform-dev
aws cloudformation wait stack-delete-complete --stack-name rcv-data-platform-dev

# Then run deployment again
./deploy-automated.sh
```

### Issue: Deployment failed
```bash
# Check deployment log
cat deployment.log

# Get error details
aws cloudformation describe-stack-events \
  --stack-name rcv-data-platform-dev \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

## Manual Deployment (Alternative)

If you prefer step-by-step control, use:
```bash
./deploy-to-isengard.sh  # Interactive
# OR
./deploy-isengard-auto.sh 'password' 'email'  # Non-interactive
```

## What Makes This Special

✅ **Zero manual steps** - Everything automated
✅ **Secure by default** - Generates strong passwords
✅ **Complete setup** - Database, ETL, monitoring
✅ **Production-ready** - Follows AWS best practices
✅ **Well-documented** - Detailed summary and logs
✅ **Easy cleanup** - Single command to delete

## Time Required

- **Deployment**: 15-20 minutes (automated)
- **Your time**: 1 minute (run command, wait)

## Next Steps After Deployment

1. ✅ Review `deployment-summary.txt`
2. ✅ Confirm SNS email subscription
3. ✅ Upload sample data to S3
4. ✅ Run test ETL workflow
5. ✅ Connect Power BI

See **DETAILED_DEPLOYMENT_GUIDE.md** for detailed instructions on each step.

---

**Ready to deploy?** Just run: `./deploy-automated.sh` 🚀
