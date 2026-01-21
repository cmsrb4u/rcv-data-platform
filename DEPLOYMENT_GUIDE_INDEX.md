# RCV Data Platform - Complete Deployment Guide Index

## 📚 Documentation Structure

This deployment guide is split into three parts for easier navigation:

### Part 1: Prerequisites & Infrastructure Setup
**File:** `DETAILED_DEPLOYMENT_GUIDE.md`

**Contents:**
- Prerequisites and tool installation
- AWS account setup and configuration
- Phase 1: AWS Account Setup
- Phase 2: Deploy Infrastructure (CloudFormation)
- Phase 3: Setup Redshift Serverless (DDL scripts)

**Time Required:** 2-3 hours

**Key Deliverables:**
- ✅ AWS CLI configured
- ✅ Infrastructure deployed (VPC, S3, Redshift Serverless, IAM)
- ✅ Redshift schemas and tables created
- ✅ Reference data populated

---

### Part 2: Glue Jobs & Monitoring
**File:** `DETAILED_DEPLOYMENT_GUIDE_PART2.md`

**Contents:**
- Phase 4: Deploy Glue Jobs
  - Upload scripts to S3
  - Create Glue connection to Redshift
  - Deploy Glue jobs stack
  - Detailed explanation of each Glue job
  - Test each job individually
- Phase 5: Setup Monitoring
  - Deploy CloudWatch dashboards
  - Configure alarms and alerts
  - Test notifications

**Time Required:** 2-3 hours

**Key Deliverables:**
- ✅ 5 Glue jobs deployed and tested
- ✅ Glue workflow configured
- ✅ CloudWatch monitoring active
- ✅ Email alerts configured

---

### Part 3: Data Loading & Power BI
**File:** `DETAILED_DEPLOYMENT_GUIDE_PART3.md`

**Contents:**
- Phase 6: Initial Data Load
  - Prepare sample data
  - Run initial load pipeline
  - Validate data load
  - Test incremental load
- Phase 7: Power BI Connection
  - Install ODBC driver
  - Configure connection
  - Create relationships
  - Build sample report
- Phase 8: Enable Daily Automation
- Troubleshooting guide

**Time Required:** 2-3 hours

**Key Deliverables:**
- ✅ Sample data loaded
- ✅ Pipeline tested end-to-end
- ✅ Power BI connected
- ✅ Sample dashboard created
- ✅ Daily automation enabled

---

## 🚀 Quick Start

### For First-Time Deployment
Follow the guides in order:

```bash
# 1. Read Part 1
cat DETAILED_DEPLOYMENT_GUIDE.md

# 2. Read Part 2
cat DETAILED_DEPLOYMENT_GUIDE_PART2.md

# 3. Read Part 3
cat DETAILED_DEPLOYMENT_GUIDE_PART3.md
```

### For Experienced Users
Jump to specific sections:

- **Infrastructure only:** Part 1, Phases 1-2
- **Redshift setup:** Part 1, Phase 3
- **Glue jobs:** Part 2, Phase 4
- **Monitoring:** Part 2, Phase 5
- **Data loading:** Part 3, Phase 6
- **Power BI:** Part 3, Phase 7

---

## 📋 Complete Deployment Checklist

### Phase 1: Prerequisites (30 min)
- [ ] Install AWS CLI
- [ ] Install PostgreSQL client
- [ ] Configure AWS credentials
- [ ] Clone repository
- [ ] Set environment variables

### Phase 2: Infrastructure (1-2 hours)
- [ ] Validate CloudFormation templates
- [ ] Deploy core infrastructure stack
- [ ] Verify resources created
- [ ] Save stack outputs

### Phase 3: Redshift Setup (1 hour)
- [ ] Test Redshift connection
- [ ] Create schemas
- [ ] Create staging tables
- [ ] Create dimension tables
- [ ] Create fact tables
- [ ] Populate reference data
- [ ] Verify table creation

### Phase 4: Glue Jobs (1-2 hours)
- [ ] Upload Glue scripts to S3
- [ ] Create Glue connection
- [ ] Create Glue database
- [ ] Deploy Glue jobs stack
- [ ] Test load_to_staging job
- [ ] Test data_quality_checks job
- [ ] Test load_dimensions job
- [ ] Test load_facts job
- [ ] Verify workflow created

### Phase 5: Monitoring (30 min)
- [ ] Deploy monitoring stack
- [ ] Confirm SNS subscription
- [ ] View CloudWatch dashboard
- [ ] Test alerts

### Phase 6: Data Loading (1 hour)
- [ ] Prepare sample data
- [ ] Upload to S3
- [ ] Run initial load pipeline
- [ ] Validate data load
- [ ] Test incremental load

### Phase 7: Power BI (1 hour)
- [ ] Install ODBC driver
- [ ] Configure connection
- [ ] Connect Power BI
- [ ] Create relationships
- [ ] Build sample report
- [ ] Test performance

### Phase 8: Automation (15 min)
- [ ] Verify workflow schedule
- [ ] Test manual workflow run
- [ ] Create monitoring script
- [ ] Document procedures

---

## 🎯 Learning Path

### Beginner Path
If you're new to AWS data platforms:

1. **Start with theory:**
   - Read `README.md` for architecture overview
   - Read `ARCHITECTURE.md` for design decisions
   - Read `EXECUTIVE_SUMMARY.md` for business context

2. **Follow step-by-step:**
   - Complete Part 1 fully before moving to Part 2
   - Test each component before proceeding
   - Take notes of any issues

3. **Practice:**
   - Deploy to dev environment first
   - Break things and fix them
   - Understand each error message

### Advanced Path
If you're experienced with AWS:

1. **Review architecture:**
   - Skim `ARCHITECTURE.md` for ADRs
   - Review CloudFormation templates
   - Understand Glue job logic

2. **Deploy efficiently:**
   - Run all CloudFormation stacks in parallel
   - Automate with scripts
   - Use AWS CDK if preferred

3. **Customize:**
   - Modify for your specific use case
   - Add additional subject areas
   - Integrate with existing systems

---

## 📖 Code Explanations

### CloudFormation Templates

#### infrastructure/cloudformation-stack.yaml
**Purpose:** Deploy core AWS infrastructure

**Key Resources:**
1. **VPC & Networking** (Lines 50-100)
   - Creates VPC with private subnets
   - Configures security groups
   - Sets up network isolation

2. **S3 Buckets** (Lines 20-50)
   - Raw data bucket: Stores incoming data
   - Archive bucket: Long-term storage
   - Glue scripts bucket: ETL code

3. **Redshift Serverless** (Lines 100-150)
   - Namespace: Logical container for database
   - Workgroup: Compute resources (32 RPUs)
   - Auto-pause when idle

4. **IAM Roles** (Lines 150-200)
   - Glue role: Permissions for ETL jobs
   - Redshift role: S3 access for COPY/UNLOAD

#### infrastructure/glue-jobs.yaml
**Purpose:** Deploy Glue ETL jobs and workflow

**Key Resources:**
1. **Glue Jobs** (Lines 20-150)
   - 5 jobs with specific purposes
   - Configured with DPUs, timeout, retries
   - Script locations in S3

2. **Workflow** (Lines 150-200)
   - Orchestrates job execution
   - Defines dependencies
   - Scheduled trigger (2 AM daily)

3. **Triggers** (Lines 200-250)
   - Start trigger: Scheduled
   - Conditional triggers: Wait for success

### Redshift DDL Scripts

#### redshift/staging/00_create_staging.sql
**Purpose:** Create staging tables for raw data

**Key Tables:**
1. **stg_registration** (Lines 10-40)
   - Includes PII columns (for processing only)
   - Has dq_is_valid flag
   - Temporary storage before DW

2. **etl_control** (Lines 100-120)
   - Tracks job execution
   - Records counts and status
   - Used for reconciliation

3. **dq_results** (Lines 120-140)
   - Stores data quality check results
   - Pass/fail rates
   - Error details

#### redshift/dimensions/01_create_dimensions.sql
**Purpose:** Create dimension tables with SCD Type 2

**Key Dimensions:**
1. **d_date** (Lines 10-40)
   - Pre-populated with 20 years
   - Conformed dimension
   - Used by all facts

2. **d_code** (Lines 80-120)
   - SCD Type 2 with effective dates
   - Tracks code changes over time
   - Central lookup for all codes

3. **d_zipcode** (Lines 150-180)
   - Geography hierarchy
   - Links to state and country
   - SCD Type 2 for address changes

#### redshift/facts/02_create_facts.sql
**Purpose:** Create fact tables and history tables

**Key Facts:**
1. **f_registration** (Lines 10-80)
   - Grain: 1 row per registration
   - Surrogate keys to dimensions
   - NO PII columns
   - Measures: age, counts, flags

2. **f_registration_hist** (Lines 150-200)
   - Tracks fact changes over time
   - Snapshot date for point-in-time
   - Change type (INSERT/UPDATE/DELETE)
   - Enables "as-of" reporting

### Glue ETL Jobs

#### glue/staging/load_to_staging.py
**Purpose:** Load raw data from S3 to Redshift staging

**Key Steps:**
1. **Read from S3** (Lines 20-30)
   - Uses Spark to read Parquet
   - Handles partitioned data
   - Schema inference

2. **Add Metadata** (Lines 30-40)
   - load_timestamp
   - processing_status
   - dq_is_valid flag

3. **Write to Redshift** (Lines 40-60)
   - TRUNCATE then INSERT
   - Uses COPY command (fast)
   - Logs record count

#### glue/staging/data_quality_checks.py
**Purpose:** Validate data quality

**Key Checks:**
1. **Completeness** (Lines 30-50)
   - Required fields not null
   - Threshold: 100%

2. **Validity** (Lines 50-70)
   - Date ranges reasonable
   - Data types correct
   - Threshold: 99%

3. **Consistency** (Lines 70-90)
   - No duplicate IDs
   - Referential integrity
   - Threshold: 100%

#### glue/transform/load_dimensions_scd2.py
**Purpose:** Load dimensions with SCD Type 2 logic

**Key Logic:**
1. **Change Detection** (Lines 40-60)
   - Hash SCD columns
   - Compare with current
   - Identify new/changed

2. **Expire Old Versions** (Lines 60-80)
   - Set effective_end_dt
   - Set is_active = FALSE
   - Preserve history

3. **Insert New Versions** (Lines 80-100)
   - New effective_start_dt
   - is_active = TRUE
   - Maintain referential integrity

#### glue/transform/load_fact_registration.py
**Purpose:** Load fact table with surrogate keys

**Key Logic:**
1. **Surrogate Key Lookup** (Lines 40-100)
   - Join to each dimension
   - Get surrogate keys
   - Handle missing keys

2. **PII Exclusion** (Lines 100-120)
   - Drop name, email, address
   - Keep only IDs and measures
   - Compliance requirement

3. **Incremental Logic** (Lines 120-160)
   - Identify new records
   - Identify changed records
   - Insert to history table
   - Upsert to fact table

---

## 🔍 Understanding the Data Flow

### End-to-End Example: Registration Record

**1. Source System (RCV)**
```
Registration ID: REG12345
Name: John Doe
Email: john@email.com
Status: ACTIVE
Date: 2025-01-20
```

**2. S3 Raw Landing**
```
s3://rcv-raw-data-dev/raw/registration/2025/01/20/batch.parquet
- Parquet format
- Compressed (Snappy)
- Partitioned by date
```

**3. Redshift Staging**
```sql
staging.stg_registration:
- registration_id: REG12345
- first_name: John
- last_name: Doe
- email: john@email.com
- registration_status: ACTIVE
- registration_date: 2025-01-20
- dq_is_valid: TRUE
```

**4. Data Quality Checks**
```sql
staging.dq_results:
- check_name: registration_id_not_null
- pass_rate: 100%
- status: PASS
```

**5. Dimension Lookup**
```sql
-- Get date key
d_date WHERE date_value = '2025-01-20'
→ date_key = 20250120

-- Get status code key
d_code WHERE code_value = 'ACTIVE' AND is_active = TRUE
→ code_key = 101
```

**6. Fact Table (NO PII)**
```sql
dw.f_registration:
- registration_key: 1 (auto-generated)
- registration_id: REG12345
- registration_date_key: 20250120
- registration_status_code_key: 101
- age_at_registration: 35
- (NO name, email, address)
```

**7. Power BI Query**
```sql
SELECT 
    f.registration_id,
    d.date_value,
    c.code_value as status,
    f.age_at_registration
FROM dw.f_registration f
JOIN dw.d_date d ON f.registration_date_key = d.date_key
JOIN dw.d_code c ON f.registration_status_code_key = c.code_key
WHERE d.year = 2025;
```

**8. Dashboard Display**
```
Registration: REG12345
Date: 2025-01-20
Status: ACTIVE
Age: 35
```

---

## 💡 Best Practices

### Development
1. Always test in dev environment first
2. Use version control for all code
3. Document all customizations
4. Keep credentials in AWS Secrets Manager

### Operations
1. Monitor daily pipeline runs
2. Review DQ results weekly
3. Analyze query performance monthly
4. Update documentation as you go

### Security
1. Never commit passwords to Git
2. Use IAM roles instead of access keys
3. Enable MFA for AWS console
4. Rotate credentials regularly

### Cost Optimization
1. Right-size Redshift base capacity
2. Use S3 lifecycle policies
3. Optimize Glue job DPUs
4. Monitor and alert on costs

---

## 📞 Getting Help

### Documentation
- Main README: `README.md`
- Architecture: `ARCHITECTURE.md`
- Cost Analysis: `COST_ESTIMATION.md`
- Quick Reference: `QUICK_REFERENCE.md`

### Troubleshooting
- See Part 3 for common issues
- Check CloudWatch logs
- Review Glue job errors
- Query Redshift system tables

### Support
- GitHub Issues: https://github.com/cmsrb4u/rcv-data-platform/issues
- AWS Support: https://console.aws.amazon.com/support/
- Community: AWS re:Post

---

**Total Deployment Time: 6-9 hours**
**Skill Level Required: Intermediate AWS knowledge**
**Prerequisites: AWS account, basic SQL, basic Python**

Good luck with your deployment! 🚀
