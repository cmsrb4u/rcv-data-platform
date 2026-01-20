# RCV Data Platform - Cost Estimation

## Monthly Cost Breakdown (Production)

### Amazon Redshift
**Cluster Configuration**: 2x ra3.xlplus nodes
- Compute: 2 nodes × $3.26/hour × 730 hours = **$4,760/month**
- Managed Storage: 500 GB × $0.024/GB = **$12/month**
- Backup Storage: 500 GB × $0.024/GB = **$12/month**
- **Redshift Total: ~$4,784/month**

*Cost Optimization*:
- Use auto-pause for dev (save ~70%)
- Consider Reserved Instances (save 30-40%)
- Use RA3 managed storage (cheaper than DC2)

### Amazon S3
**Raw Data Landing**: 100 GB/month new data
- Standard Storage: 100 GB × $0.023/GB = **$2.30/month**
- PUT requests: 1M × $0.005/1000 = **$5/month**

**Archive Storage**: 5 TB historical (growing)
- S3 Standard-IA: 1 TB × $0.0125/GB = **$12.80/month**
- S3 Glacier: 4 TB × $0.004/GB = **$16.38/month**
- Retrieval (occasional): **$10/month**

**Glue Scripts**: 1 GB
- Standard Storage: **$0.02/month**

- **S3 Total: ~$46.50/month**

### AWS Glue
**Daily Incremental Pipeline**:
- 5 jobs/day × 30 days = 150 job runs/month
- Average 10 DPUs × 0.5 hours = 5 DPU-hours per run
- 150 runs × 5 DPU-hours × $0.44/DPU-hour = **$330/month**

**Monthly Archive Job**:
- 1 job/month × 20 DPU-hours × $0.44 = **$8.80/month**

**Glue Data Catalog**:
- 100 tables × $1/month = **$1/month**

- **Glue Total: ~$339.80/month**

### AWS DMS (if used for CDC)
**Replication Instance**: dms.c5.large
- $0.192/hour × 730 hours = **$140/month**
- Storage: 100 GB × $0.115/GB = **$11.50/month**

- **DMS Total: ~$151.50/month** (optional)

### CloudWatch
**Logs**:
- 10 GB ingested/month × $0.50/GB = **$5/month**
- 10 GB stored × $0.03/GB = **$0.30/month**

**Metrics**:
- 50 custom metrics × $0.30 = **$15/month**

**Dashboards**:
- 3 dashboards × $3 = **$9/month**

**Alarms**:
- 10 alarms × $0.10 = **$1/month**

- **CloudWatch Total: ~$30.30/month**

### Data Transfer
**Redshift to Power BI**: 50 GB/month
- Data Transfer Out: 50 GB × $0.09/GB = **$4.50/month**

**S3 to Redshift**: 100 GB/month
- Free (same region)

- **Data Transfer Total: ~$4.50/month**

### SNS
**Email Notifications**: 1,000 emails/month
- First 1,000 free = **$0/month**

### VPC
**NAT Gateway** (if needed): 1 gateway
- $0.045/hour × 730 hours = **$32.85/month**
- Data processing: 100 GB × $0.045/GB = **$4.50/month**

- **VPC Total: ~$37.35/month** (optional)

---

## Total Monthly Cost Estimates

### Scenario 1: Minimal (Dev Environment)
- Redshift: $1,428 (auto-pause 70% of time)
- S3: $46.50
- Glue: $100 (reduced frequency)
- CloudWatch: $15
- **Total: ~$1,590/month**

### Scenario 2: Standard (Production)
- Redshift: $4,784
- S3: $46.50
- Glue: $339.80
- CloudWatch: $30.30
- Data Transfer: $4.50
- **Total: ~$5,205/month**

### Scenario 3: With DMS (Production + Real-time CDC)
- Redshift: $4,784
- S3: $46.50
- Glue: $339.80
- DMS: $151.50
- CloudWatch: $30.30
- Data Transfer: $4.50
- VPC: $37.35
- **Total: ~$5,394/month**

---

## Annual Cost Projection

### Year 1 (with growth)
- Months 1-3 (Dev): $1,590 × 3 = $4,770
- Months 4-12 (Prod): $5,205 × 9 = $46,845
- **Year 1 Total: ~$51,615**

### Year 2-3 (Steady State)
- Monthly: $5,205
- Annual: $5,205 × 12 = **$62,460/year**

### 3-Year TCO: ~$176,535

---

## Cost Optimization Strategies

### Immediate Savings (30-40%)
1. **Redshift Reserved Instances**: Save $1,430/month (30%)
2. **Auto-pause Dev Cluster**: Save $3,332/month on dev
3. **S3 Lifecycle Policies**: Save $10/month
4. **Glue Job Optimization**: Save $100/month (reduce DPUs)

**Potential Monthly Savings: ~$1,540 (30%)**
**Optimized Production Cost: ~$3,665/month**

### Long-term Savings
1. **Redshift Serverless**: Pay per query (if usage is sporadic)
2. **S3 Intelligent-Tiering**: Automatic cost optimization
3. **Glue Flex Execution**: Save 35% on non-urgent jobs
4. **Spot Instances for EMR**: If switching from Glue

---

## Cost Comparison: Build vs Buy

### Build (This Solution)
- **Monthly**: $3,665 (optimized)
- **Annual**: $43,980
- **3-Year**: $131,940

### Buy (Commercial DW Platform)
- **Snowflake/Databricks**: $8,000-15,000/month
- **Annual**: $96,000-180,000
- **3-Year**: $288,000-540,000

**Savings with AWS Solution: 50-75%**

---

## Resource Scaling Guidelines

### When to Scale Up Redshift
- Query latency > 10 seconds
- CPU utilization > 80% sustained
- Disk space > 85%

**Scaling Options**:
- Add nodes: +$2,380/month per node
- Upgrade to ra3.4xlarge: +$8,000/month

### When to Scale Up Glue
- Job duration > 2 hours
- Frequent job failures
- Backlog of pending jobs

**Scaling Options**:
- Increase DPUs: +$0.44/DPU-hour
- Add parallel jobs: +$330/month per job

---

## Budget Allocation

### Development Phase (3 months)
- Infrastructure: $4,770
- Personnel (2 FTE): $60,000
- **Total: $64,770**

### Annual Operations
- Infrastructure: $43,980
- Personnel (0.5 FTE): $50,000
- Training: $5,000
- Contingency: $10,000
- **Total: $108,980/year**

---

## ROI Analysis

### Costs
- Year 1: $64,770 (dev) + $46,845 (prod) = $111,615
- Year 2-3: $43,980/year

### Benefits (Estimated)
- Reduced manual reporting: $100,000/year
- Faster decision-making: $150,000/year
- Improved compliance: $50,000/year
- **Total Annual Benefit: $300,000**

### ROI
- Year 1: ($300,000 - $111,615) / $111,615 = **168% ROI**
- Year 2+: ($300,000 - $43,980) / $43,980 = **682% ROI**

**Payback Period: 4.5 months**
