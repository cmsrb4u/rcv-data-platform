# RCV Data Platform - Quick Reference Guide

## Common Commands

### AWS CLI - Redshift Serverless
```bash
# Get workgroup endpoint
aws redshift-serverless get-workgroup --workgroup-name rcv-dw-dev

# Connect to Redshift Serverless
psql -h <workgroup-endpoint>.redshift-serverless.amazonaws.com -U admin -d rcvdw -p 5439

# Get namespace info
aws redshift-serverless get-namespace --namespace-name rcv-dw-dev

# Update base capacity
aws redshift-serverless update-workgroup \
  --workgroup-name rcv-dw-dev \
  --base-capacity 64

# Check usage metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Redshift-Serverless \
  --metric-name ComputeCapacity \
  --dimensions Name=WorkgroupName,Value=rcv-dw-dev \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

### AWS CLI - Glue
```bash
# Start workflow
aws glue start-workflow-run --name rcv-daily-etl-dev

# Check workflow status
aws glue get-workflow-run --name rcv-daily-etl-dev --run-id <run-id>

# Start individual job
aws glue start-job-run --job-name rcv-load-to-staging-dev

# Get job status
aws glue get-job-run --job-name rcv-load-to-staging-dev --run-id <run-id>

# View job logs
aws logs tail /aws-glue/jobs/output --follow
```

### AWS CLI - S3
```bash
# List raw data
aws s3 ls s3://rcv-raw-data-dev-<account>/raw/registration/

# Copy data to S3
aws s3 cp local_file.csv s3://rcv-raw-data-dev-<account>/raw/registration/

# Sync directory
aws s3 sync ./data/ s3://rcv-raw-data-dev-<account>/raw/registration/
```

## Common SQL Queries

### Data Validation
```sql
-- Check record counts
SELECT 
    'F_Registration' AS table_name, COUNT(*) AS record_count 
FROM dw.f_registration
UNION ALL
SELECT 'F_Compliance', COUNT(*) FROM dw.f_compliance
UNION ALL
SELECT 'F_Verification', COUNT(*) FROM dw.f_verification;

-- Check for orphaned records
SELECT COUNT(*) AS orphaned_records
FROM dw.f_registration f
LEFT JOIN dw.d_date d ON f.registration_date_key = d.date_key
WHERE d.date_key IS NULL;

-- Check date range
SELECT 
    MIN(d.date_value) AS min_date,
    MAX(d.date_value) AS max_date,
    COUNT(DISTINCT f.registration_id) AS unique_registrations
FROM dw.f_registration f
JOIN dw.d_date d ON f.registration_date_key = d.date_key;

-- Check for duplicates
SELECT registration_id, COUNT(*) AS dup_count
FROM dw.f_registration
GROUP BY registration_id
HAVING COUNT(*) > 1;
```

### Performance Monitoring
```sql
-- Check table sizes
SELECT 
    "table" AS table_name,
    size AS size_mb,
    tbl_rows AS row_count
FROM svv_table_info
WHERE schema = 'dw'
ORDER BY size DESC;

-- Check query performance
SELECT 
    query,
    TRIM(querytxt) AS query_text,
    starttime,
    endtime,
    DATEDIFF(seconds, starttime, endtime) AS duration_seconds
FROM stl_query
WHERE userid > 1
ORDER BY starttime DESC
LIMIT 10;

-- Check running queries
SELECT 
    pid,
    user_name,
    starttime,
    DATEDIFF(seconds, starttime, GETDATE()) AS running_seconds,
    TRIM(query) AS query_text
FROM stv_recents
WHERE status = 'Running';
```

### Data Quality Checks
```sql
-- Check DQ results
SELECT 
    table_name,
    check_name,
    check_type,
    pass_rate,
    status,
    check_timestamp
FROM staging.dq_results
WHERE check_timestamp > DATEADD(day, -7, GETDATE())
ORDER BY check_timestamp DESC;

-- Check ETL control
SELECT 
    job_name,
    job_type,
    status,
    records_read,
    records_written,
    records_rejected,
    start_timestamp,
    end_timestamp,
    DATEDIFF(minute, start_timestamp, end_timestamp) AS duration_minutes
FROM staging.etl_control
ORDER BY start_timestamp DESC
LIMIT 20;
```

### SCD Type 2 Queries
```sql
-- Check dimension history
SELECT 
    code_id,
    code_value,
    effective_start_dt,
    effective_end_dt,
    is_active
FROM dw.d_code
WHERE code_id = 'REG_STATUS_1'
ORDER BY effective_start_dt;

-- Get current active dimensions
SELECT COUNT(*) AS active_count
FROM dw.d_code
WHERE is_active = TRUE;

-- Get dimension as of specific date
SELECT *
FROM dw.d_code
WHERE code_id = 'REG_STATUS_1'
  AND effective_start_dt <= '2025-01-01'
  AND (effective_end_dt IS NULL OR effective_end_dt > '2025-01-01');
```

## Troubleshooting

### Glue Job Failures
```bash
# Check error logs
aws logs filter-log-events \
  --log-group-name /aws-glue/jobs/error \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s)000

# Check job metrics
aws cloudwatch get-metric-statistics \
  --namespace Glue \
  --metric-name glue.driver.aggregate.numFailedTasks \
  --dimensions Name=JobName,Value=rcv-load-to-staging-dev \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### Redshift Serverless Performance Issues
```sql
-- Check query performance
SELECT 
    query_id,
    user_name,
    start_time,
    end_time,
    DATEDIFF(seconds, start_time, end_time) AS duration_seconds,
    query_text
FROM sys_query_history
WHERE start_time > DATEADD(hour, -24, GETDATE())
ORDER BY duration_seconds DESC
LIMIT 10;

-- Check RPU usage
SELECT 
    start_time,
    compute_capacity,
    compute_seconds
FROM sys_serverless_usage
WHERE start_time > DATEADD(day, -7, GETDATE())
ORDER BY start_time DESC;

-- Analyze tables
ANALYZE dw.f_registration;
ANALYZE dw.d_date;
ANALYZE dw.d_code;

-- Vacuum tables
VACUUM dw.f_registration;
```

### Data Quality Issues
```sql
-- Find invalid records in staging
SELECT *
FROM staging.stg_registration
WHERE dq_is_valid = FALSE
LIMIT 100;

-- Check validation errors
SELECT 
    dq_validation_errors,
    COUNT(*) AS error_count
FROM staging.stg_registration
WHERE dq_is_valid = FALSE
GROUP BY dq_validation_errors
ORDER BY error_count DESC;
```

## Monitoring Dashboards

### CloudWatch Dashboard URL
```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=RCV-Pipeline-dev
```

### Key Metrics to Monitor
- Redshift Serverless RPU usage (target: optimize for workload)
- Query duration (target: <5 seconds for dashboards)
- Glue job success rate (target: >99%)
- Glue job duration (target: <2 hours)
- DQ check pass rate (target: >99%)

## Contacts and Escalation

### Support Contacts
- **Data Engineering Team**: data-eng@example.com
- **BI Team**: bi-team@example.com
- **Operations**: ops@example.com

### Escalation Path
1. Check CloudWatch logs and dashboard
2. Review troubleshooting guide
3. Contact Data Engineering team
4. Escalate to AWS Support (if infrastructure issue)

## Useful Links

### Documentation
- [AWS Redshift Documentation](https://docs.aws.amazon.com/redshift/)
- [AWS Glue Documentation](https://docs.aws.amazon.com/glue/)
- [Power BI Documentation](https://docs.microsoft.com/power-bi/)

### Internal
- Project Wiki: [link]
- Runbook: [link]
- Architecture Diagrams: [link]
- Training Materials: [link]

## Maintenance Schedule

### Daily
- Monitor pipeline execution (2 AM)
- Review DQ results
- Check for failed jobs

### Weekly
- Review CloudWatch dashboard
- Check disk space trends
- Review query performance

### Monthly
- Run archive job (1st of month)
- Review and optimize slow queries
- Update documentation
- Capacity planning review

### Quarterly
- Review and update dimension data
- Audit access logs
- Performance tuning
- Disaster recovery test
