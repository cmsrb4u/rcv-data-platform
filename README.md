# RCV Data Platform - AWS Implementation

## Architecture Components

### Data Flow
1. **Ingestion**: AWS DMS/Glue extracts from RCV source
2. **Landing**: Raw data lands in S3 (partitioned by date)
3. **Staging**: Glue loads to Redshift Serverless staging tables
4. **Quality**: DQ checks in staging layer
5. **Transform**: Glue applies SCD2 logic and populates DW
6. **Reporting**: Power BI connects to Redshift Serverless star schema
7. **Archive**: Data >10 years moved to S3 Parquet

### Key Features
- Star schema with 3 fact tables (Registration, Compliance, Verification)
- SCD Type 2 dimensions for history tracking
- Incremental daily loads with CDC
- **Redshift Serverless** with auto-scaling and pay-per-use pricing
- 10-year retention in Redshift, archive to S3
- CloudWatch monitoring and SNS alerting
- Power BI integration

## Directory Structure
```
rcv-data-platform/
├── infrastructure/          # CloudFormation/Terraform
├── redshift/               # DDL scripts
│   ├── staging/
│   ├── dimensions/
│   └── facts/
├── glue/                   # ETL jobs
│   ├── ingestion/
│   ├── staging/
│   ├── transform/
│   └── archive/
├── monitoring/             # CloudWatch dashboards
└── powerbi/               # Power BI templates
```

## Deployment Steps
1. Deploy infrastructure (VPC, S3, Redshift, Glue)
2. Create Redshift schemas and tables
3. Deploy Glue jobs
4. Configure monitoring and alerts
5. Initial historical load (10 years)
6. Enable daily incremental pipeline
7. Connect Power BI

## Cost Optimization
- Use Redshift Serverless with auto-pause (no idle costs)
- Right-size base capacity based on workload
- Compress S3 archives with Parquet + Snappy
- Use Glue job bookmarks for incremental processing
- Use Glue job bookmarks for incremental processing
- Enable Redshift auto-pause for dev environments
