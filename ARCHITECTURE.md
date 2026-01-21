# RCV Data Platform - Architecture Decision Records

## ADR-001: Star Schema vs Snowflake Schema

**Decision**: Use Star Schema for dimensional modeling

**Rationale**:
- Simpler for Power BI users to understand
- Better query performance (fewer joins)
- Easier maintenance
- Redshift optimized for star schema queries

**Trade-offs**:
- Some data redundancy in dimensions
- Larger dimension tables

## ADR-002: SCD Type 2 for Dimensions

**Decision**: Implement SCD Type 2 for code, geography, and data source dimensions

**Rationale**:
- Track historical changes in codes and classifications
- Enable "as-of" reporting
- Maintain referential integrity over time

**Implementation**:
- effective_start_dt, effective_end_dt, is_active columns
- Hash-based change detection
- Automated expiration of old records

## ADR-003: Fact History Tables

**Decision**: Create separate history tables (F_*_Hist) for tracking fact changes

**Rationale**:
- Separate operational facts from historical snapshots
- Better query performance for current state
- Flexible history retention policies

**Trade-offs**:
- Additional storage
- More complex ETL logic

## ADR-004: Redshift Serverless

**Decision**: Use Redshift Serverless instead of provisioned clusters

**Rationale**:
- Pay-per-use pricing (no idle costs)
- Automatic scaling based on workload
- No capacity planning required
- Lower operational overhead
- Better cost efficiency for variable workloads

**Implementation**:
- Base capacity: 32 RPUs (can scale to 512)
- Auto-pause when idle
- Automatic backup and recovery
- Managed storage scales independently

**Trade-offs**:
- Cold start latency (first query after idle)
- Less control over specific node configuration
- May be more expensive for 24/7 heavy workloads

**Cost Impact**:
- ~40% cheaper than provisioned RA3 clusters
- $2,904/month vs $4,784/month (8hr/day usage)
- Better for dev/test environments

**Decision**: Use AWS Glue instead of custom EMR or Lambda

**Rationale**:
- Serverless, no infrastructure management
- Built-in job scheduling and orchestration
- Native Redshift integration
- Auto-scaling based on workload

**Trade-offs**:
- Less control over Spark configuration
- Higher cost per DPU-hour vs EMR

## ADR-006: Incremental Loading Strategy

**Decision**: Use timestamp-based CDC with job bookmarks

**Rationale**:
- Simple to implement
- Works with existing source systems
- Glue job bookmarks track progress automatically

**Implementation**:
- created_date and updated_date in source
- Hash-based change detection for updates
- Upsert logic in Glue

## ADR-007: PII Exclusion from Facts

**Decision**: Exclude PII (names, email, addresses) from fact tables

**Rationale**:
- Compliance with data privacy regulations
- Reduce risk of data breaches
- Simplify access control

**Implementation**:
- PII retained only in staging (temporary)
- Facts contain only IDs and aggregatable measures
- Separate secure PII store if needed for operations

## ADR-008: 10-Year Retention with S3 Archive

**Decision**: Keep 10 years in Redshift, archive older to S3 Parquet

**Rationale**:
- Balance performance and cost
- S3 cheaper for cold data
- Parquet enables querying via Redshift Spectrum if needed

**Implementation**:
- Monthly archive job
- Partitioned by year/month
- Glue Catalog for archived data

## ADR-009: Power BI DirectQuery Mode

**Decision**: Use DirectQuery instead of Import mode

**Rationale**:
- Always current data
- No refresh scheduling needed
- Leverage Redshift compute power
- Smaller Power BI file sizes

**Trade-offs**:
- Slower dashboard performance
- Requires good Redshift query optimization

## ADR-010: CloudWatch for Monitoring

**Decision**: Use CloudWatch Logs, Metrics, and Dashboards

**Rationale**:
- Native AWS integration
- Centralized logging
- Custom metrics and alarms
- Cost-effective

**Implementation**:
- Glue job logs to CloudWatch
- Custom metrics for DQ checks
- SNS for alerting
- Unified dashboard

## ADR-011: Conformed Dimensions

**Decision**: Share dimensions across all fact tables

**Rationale**:
- Consistent filtering and grouping
- Simplified reporting
- Reduced dimension proliferation

**Implementation**:
- D_Date used by all facts
- D_Code shared for all code lookups
- Geography dimensions shared

## ADR-012: Surrogate Keys

**Decision**: Use IDENTITY columns for surrogate keys

**Rationale**:
- Redshift auto-generates unique values
- Protects from source system key changes
- Enables SCD Type 2

**Trade-offs**:
- Requires key lookup during ETL
- Cannot pre-assign keys
