# RCV Data Platform - Cost Estimation

## Monthly Cost Breakdown (Production)

### Amazon Redshift Serverless
**Workgroup Configuration**: Base capacity 32 RPUs
- Compute: Pay-per-use, auto-scaling
- Base capacity: 32 RPUs × $0.375/RPU-hour
- Estimated usage: 8 hours/day active queries
- Monthly: 32 RPUs × $0.375 × 240 hours = **$2,880/month**
- Storage: 500 GB × $0.024/GB = **$12/month**
- Backup Storage: 500 GB × $0.024/GB = **$12/month**
- **Redshift Serverless Total: ~$2,904/month**

*Cost Optimization*:
- Auto-pause when idle (no compute charges)
- Pay only for actual usage
- Scale up/down automatically based on workload
- No upfront commitment required

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
- Redshift Serverless: $580 (2 hours/day usage)
- S3: $46.50
- Glue: $100 (reduced frequency)
- CloudWatch: $15
- **Total: ~$742/month**

### Scenario 2: Standard (Production)
- Redshift Serverless: $2,904
- S3: $46.50
- Glue: $339.80
- CloudWatch: $30.30
- Data Transfer: $4.50
- **Total: ~$3,325/month**

### Scenario 3: With DMS (Production + Real-time CDC)
- Redshift Serverless: $2,904
- S3: $46.50
- Glue: $339.80
- DMS: $151.50
- CloudWatch: $30.30
- Data Transfer: $4.50
- VPC: $37.35
- **Total: ~$3,514/month**

---

## Annual Cost Projection

### Year 1 (with growth)
- Months 1-3 (Dev): $742 × 3 = $2,226
- Months 4-12 (Prod): $3,325 × 9 = $29,925
- **Year 1 Total: ~$32,151**

### Year 2-3 (Steady State)
- Monthly: $3,325
- Annual: $3,325 × 12 = **$39,900/year**

### 3-Year TCO: ~$111,951

---

## Cost Optimization Strategies

### Immediate Savings (40-50%)
1. **Redshift Serverless Auto-pause**: Automatic (no idle charges)
2. **Right-size Base Capacity**: Start with 16 RPUs, scale as needed
3. **S3 Lifecycle Policies**: Save $10/month
4. **Glue Job Optimization**: Save $100/month (reduce DPUs)

**Potential Monthly Savings: ~$1,000 (30%)**
**Optimized Production Cost: ~$2,325/month**

### Long-term Savings
1. **Redshift Serverless**: Pay per query (if usage is sporadic)
2. **S3 Intelligent-Tiering**: Automatic cost optimization
3. **Glue Flex Execution**: Save 35% on non-urgent jobs
4. **Spot Instances for EMR**: If switching from Glue

---

## Cost Comparison: Build vs Buy

### Build (This Solution - Serverless)
- **Monthly**: $2,325 (optimized)
- **Annual**: $27,900
- **3-Year**: $83,700

### Buy (Commercial DW Platform)
- **Snowflake/Databricks**: $8,000-15,000/month
- **Annual**: $96,000-180,000
- **3-Year**: $288,000-540,000

**Savings with AWS Serverless Solution: 70-85%**

---

## Resource Scaling Guidelines

### When to Scale Up Redshift Serverless
- Query latency > 10 seconds consistently
- Workload exceeds current RPU capacity
- Frequent queuing of queries

**Scaling Options**:
- Increase base capacity: 32 → 64 RPUs (+$2,880/month for 8hr/day)
- Increase max capacity for burst workloads
- Optimize queries and data distribution

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
- Infrastructure: $2,226
- Personnel (2 FTE): $60,000
- **Total: $62,226**

### Annual Operations
- Infrastructure: $27,900
- Personnel (0.5 FTE): $50,000
- Training: $5,000
- Contingency: $10,000
- **Total: $92,900/year**

---

## ROI Analysis

### Costs
- Year 1: $62,226 (dev) + $29,925 (prod) = $92,151
- Year 2-3: $27,900/year

### Benefits (Estimated)
- Reduced manual reporting: $100,000/year
- Faster decision-making: $150,000/year
- Improved compliance: $50,000/year
- **Total Annual Benefit: $300,000**

### ROI
- Year 1: ($300,000 - $92,151) / $92,151 = **226% ROI**
- Year 2+: ($300,000 - $27,900) / $27,900 = **975% ROI**

**Payback Period: 3.7 months**
