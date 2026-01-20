# RCV Data Platform - Architecture Diagrams

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          RCV SOURCE SYSTEMS                              │
│                    (Registration, Compliance, Verification)              │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │   AWS DMS / Glue       │
                    │   (Data Extraction)    │
                    └────────────┬───────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │   Amazon S3            │
                    │   Raw Landing Zone     │
                    │   (Parquet Files)      │
                    └────────────┬───────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │   AWS Glue ETL         │
                    │   Load to Staging      │
                    └────────────┬───────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      AMAZON REDSHIFT CLUSTER                            │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                     STAGING SCHEMA                                │  │
│  │  • stg_registration  • stg_compliance  • stg_verification        │  │
│  │  • Data Quality Checks  • Control Tables                         │  │
│  └────────────────────────────┬─────────────────────────────────────┘  │
│                                │                                         │
│                                ▼                                         │
│                   ┌────────────────────────┐                            │
│                   │   AWS Glue ETL         │                            │
│                   │   Transform & Load     │                            │
│                   │   (SCD Type 2 Logic)   │                            │
│                   └────────────┬───────────┘                            │
│                                │                                         │
│                                ▼                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                      DW SCHEMA (Star Schema)                      │  │
│  │                                                                    │  │
│  │  DIMENSIONS (SCD Type 2)          FACTS                          │  │
│  │  • D_Date                          • F_Registration               │  │
│  │  • D_Code                          • F_Compliance                 │  │
│  │  • D_CodeCategory                  • F_Verification               │  │
│  │  • D_Zipcode                                                      │  │
│  │  • D_State                         HISTORY FACTS                  │  │
│  │  • D_Country                       • F_Registration_Hist          │  │
│  │  • D_DataSourceConfiguration       • F_Compliance_Hist            │  │
│  │  • D_FileInformation               • F_Verification_Hist          │  │
│  │                                                                    │  │
│  │  ENRICHMENT (Type 1)                                              │  │
│  │  • D_ZipGeography                                                 │  │
│  │  • D_Census                                                       │  │
│  │  • D_CountyDemographics                                           │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────┬───────────────────────────────────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │   Power BI             │
                    │   (DirectQuery)        │
                    │   • CNR Report         │
                    │   • Dashboards         │
                    └────────────┬───────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │   Business Users       │
                    └────────────────────────┘

ARCHIVE PATH (10+ years):
Redshift DW ──────────────────────────────────────────────────────────┐
                                                                       │
                                                                       ▼
                                                          ┌────────────────────────┐
                                                          │   Amazon S3            │
                                                          │   Archive (Parquet)    │
                                                          │   Partitioned by Year  │
                                                          └────────────────────────┘

MONITORING:
┌────────────────────────────────────────────────────────────────────────┐
│                         AWS CLOUDWATCH                                  │
│  • Logs  • Metrics  • Dashboards  • Alarms  • SNS Notifications       │
└────────────────────────────────────────────────────────────────────────┘
```

## Star Schema - Registration Subject Area

```
                              ┌─────────────────┐
                              │    D_Date       │
                              │  (Conformed)    │
                              ├─────────────────┤
                              │ date_key (PK)   │
                              │ date_value      │
                              │ year            │
                              │ quarter         │
                              │ month           │
                              │ day_of_week     │
                              └────────┬────────┘
                                       │
                                       │ 1
                                       │
                                       │ M
        ┌──────────────────────────────┼──────────────────────────────┐
        │                              │                              │
        │                              │                              │
┌───────┴────────┐          ┌──────────▼──────────┐          ┌───────┴────────┐
│   D_Code       │          │  F_Registration     │          │  D_Zipcode     │
│  (SCD Type 2)  │◄─────────┤     (FACT)          │─────────►│  (SCD Type 2)  │
├────────────────┤    M     ├─────────────────────┤    M     ├────────────────┤
│ code_key (PK)  │          │ registration_key(PK)│          │ zipcode_key(PK)│
│ code_id        │          │ registration_id     │          │ zipcode_id     │
│ code_value     │          │ registration_date_key│         │ zipcode        │
│ effective_start│          │ birth_date_key      │          │ city           │
│ effective_end  │          │ reg_status_code_key │          │ state_key (FK) │
│ is_active      │          │ reg_type_code_key   │          │ effective_start│
└────────────────┘          │ zipcode_key (FK)    │          │ effective_end  │
                            │ state_key (FK)      │          │ is_active      │
                            │ data_source_key(FK) │          └────────┬───────┘
                            │ file_key (FK)       │                   │
                            │ age_at_registration │                   │ M
                            │ registration_method │                   │
                            │ created_dt          │                   │ 1
                            │ updated_dt          │                   │
                            └─────────┬───────────┘          ┌────────▼───────┐
                                      │                      │   D_State      │
                                      │ M                    │  (SCD Type 2)  │
                                      │                      ├────────────────┤
                                      │ 1                    │ state_key (PK) │
                         ┌────────────▼──────────┐           │ state_id       │
                         │ D_DataSourceConfig    │           │ state_name     │
                         │    (SCD Type 2)       │           │ state_code     │
                         ├───────────────────────┤           │ country_key(FK)│
                         │ data_source_key (PK)  │           │ effective_start│
                         │ data_source_id        │           │ effective_end  │
                         │ source_name           │           │ is_active      │
                         │ source_type           │           └────────┬───────┘
                         │ schedule_frequency    │                    │
                         │ effective_start       │                    │ M
                         │ effective_end         │                    │
                         │ is_active             │                    │ 1
                         └───────────────────────┘           ┌────────▼───────┐
                                                             │   D_Country    │
                                                             │  (SCD Type 2)  │
                                                             ├────────────────┤
                                                             │ country_key(PK)│
                                                             │ country_id     │
                                                             │ country_name   │
                                                             │ country_code   │
                                                             │ effective_start│
                                                             │ effective_end  │
                                                             │ is_active      │
                                                             └────────────────┘
```

## ETL Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        DAILY ETL WORKFLOW                                │
│                        (Scheduled: 2 AM Daily)                           │
└─────────────────────────────────────────────────────────────────────────┘

Step 1: INGESTION
┌────────────────────────────────────────────────────────────────────────┐
│  AWS DMS / Glue Crawler                                                 │
│  • Extract new/changed records from RCV source                          │
│  • Filter by: created_date >= last_run_date OR                         │
│               updated_date >= last_run_date                             │
│  • Land in S3: s3://bucket/raw/registration/YYYY/MM/DD/                │
└────────────────────────────────┬───────────────────────────────────────┘
                                 │
                                 ▼
Step 2: LOAD TO STAGING
┌────────────────────────────────────────────────────────────────────────┐
│  Glue Job: load_to_staging.py                                          │
│  • Read from S3 raw zone                                                │
│  • Add metadata columns (load_timestamp, processing_status)             │
│  • TRUNCATE staging.stg_registration                                    │
│  • INSERT into staging.stg_registration                                 │
│  • Log record count to staging.etl_control                              │
└────────────────────────────────┬───────────────────────────────────────┘
                                 │
                                 ▼
Step 3: DATA QUALITY CHECKS
┌────────────────────────────────────────────────────────────────────────┐
│  Glue Job: data_quality_checks.py                                      │
│  • Completeness: Check required fields not null                         │
│  • Validity: Check date ranges, data types                              │
│  • Consistency: Check for duplicates                                    │
│  • Write results to staging.dq_results                                  │
│  • Update staging records: dq_is_valid flag                             │
│  • If failures > threshold: Send SNS alert                              │
└────────────────────────────────┬───────────────────────────────────────┘
                                 │
                                 ▼
Step 4: LOAD DIMENSIONS (SCD Type 2)
┌────────────────────────────────────────────────────────────────────────┐
│  Glue Job: load_dimensions_scd2.py                                     │
│  • For each dimension (D_Code, D_Zipcode, D_State, etc.):              │
│    1. Read staging data                                                 │
│    2. Read current active dimension records                             │
│    3. Calculate hash of SCD columns                                     │
│    4. Compare hashes to detect changes                                  │
│    5. INSERT new records (effective_start_dt = now, is_active = TRUE)  │
│    6. UPDATE changed records (effective_end_dt = now, is_active = FALSE)│
│    7. INSERT new versions of changed records                            │
└────────────────────────────────┬───────────────────────────────────────┘
                                 │
                                 ▼
Step 5: LOAD FACTS (Incremental)
┌────────────────────────────────────────────────────────────────────────┐
│  Glue Job: load_fact_registration.py                                   │
│  • Read staging.stg_registration (WHERE dq_is_valid = TRUE)            │
│  • Lookup surrogate keys from dimensions:                               │
│    - registration_date_key from D_Date                                  │
│    - registration_status_code_key from D_Code                           │
│    - zipcode_key from D_Zipcode                                         │
│    - state_key from D_State                                             │
│    - data_source_key from D_DataSourceConfiguration                    │
│  • Calculate record_hash (for change detection)                         │
│  • Compare with existing F_Registration:                                │
│    - New records: INSERT into F_Registration                            │
│    - Changed records: INSERT into F_Registration_Hist                   │
│                       UPDATE F_Registration                             │
│  • Exclude PII columns (names, email, addresses)                        │
└────────────────────────────────┬───────────────────────────────────────┘
                                 │
                                 ▼
Step 6: RECONCILIATION
┌────────────────────────────────────────────────────────────────────────┐
│  • Compare record counts: Source vs Staging vs DW                       │
│  • Check for orphaned records (missing dimension keys)                  │
│  • Validate referential integrity                                       │
│  • Update staging.etl_control with final status                         │
│  • If success: Send success notification                                │
│  • If failure: Send alert with error details                            │
└────────────────────────────────────────────────────────────────────────┘
```

## SCD Type 2 Logic Example

```
SCENARIO: Registration status changes from "PENDING" to "ACTIVE"

BEFORE (D_Code table):
┌──────────┬─────────┬────────────┬──────────────────┬────────────────┬───────────┐
│ code_key │ code_id │ code_value │ effective_start  │ effective_end  │ is_active │
├──────────┼─────────┼────────────┼──────────────────┼────────────────┼───────────┤
│   101    │  RS001  │  PENDING   │ 2025-01-01 00:00 │      NULL      │   TRUE    │
└──────────┴─────────┴────────────┴──────────────────┴────────────────┴───────────┘

AFTER (D_Code table):
┌──────────┬─────────┬────────────┬──────────────────┬────────────────┬───────────┐
│ code_key │ code_id │ code_value │ effective_start  │ effective_end  │ is_active │
├──────────┼─────────┼────────────┼──────────────────┼────────────────┼───────────┤
│   101    │  RS001  │  PENDING   │ 2025-01-01 00:00 │ 2026-01-19 ... │   FALSE   │ ← Expired
│   102    │  RS001  │  ACTIVE    │ 2026-01-19 ...   │      NULL      │   TRUE    │ ← New version
└──────────┴─────────┴────────────┴──────────────────┴────────────────┴───────────┘

FACT TABLE (F_Registration):
┌────────────────┬─────────────────────┬────────────────────┐
│ registration_id│ reg_status_code_key │ registration_date  │
├────────────────┼─────────────────────┼────────────────────┤
│   REG12345     │        102          │   2026-01-19       │ ← Points to new version
└────────────────┴─────────────────────┴────────────────────┘

HISTORY TABLE (F_Registration_Hist):
┌────────────────┬─────────────────────┬──────────────────┬────────────────┬────────────┐
│ registration_id│ reg_status_code_key │ effective_start  │ effective_end  │ is_current │
├────────────────┼─────────────────────┼──────────────────┼────────────────┼────────────┤
│   REG12345     │        101          │ 2025-01-01 ...   │ 2026-01-19 ... │   FALSE    │
│   REG12345     │        102          │ 2026-01-19 ...   │      NULL      │   TRUE     │
└────────────────┴─────────────────────┴──────────────────┴────────────────┴────────────┘

QUERY: "What was the status on 2025-06-01?"
SELECT code_value
FROM F_Registration_Hist h
JOIN D_Code d ON h.reg_status_code_key = d.code_key
WHERE h.registration_id = 'REG12345'
  AND '2025-06-01' BETWEEN h.effective_start AND COALESCE(h.effective_end, '9999-12-31')
  AND '2025-06-01' BETWEEN d.effective_start_dt AND COALESCE(d.effective_end_dt, '9999-12-31');

RESULT: "PENDING"
```

## Monitoring Dashboard Layout

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    RCV PIPELINE MONITORING DASHBOARD                     │
└─────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  KPIs (Last 24 Hours)                                                     │
├──────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ Pipeline     │  │ Records      │  │ DQ Pass      │  │ Avg Job      │ │
│  │ Success Rate │  │ Processed    │  │ Rate         │  │ Duration     │ │
│  │              │  │              │  │              │  │              │ │
│  │    99.5%     │  │   1.2M       │  │   99.8%      │  │   45 min     │ │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  Glue Job Execution Status (Last 7 Days)                                 │
├──────────────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                                                                    │  │
│  │  ████████████████████████████████████████████████████  Success    │  │
│  │  ██  Failed                                                        │  │
│  │                                                                    │  │
│  │  Mon  Tue  Wed  Thu  Fri  Sat  Sun                                │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  Redshift Cluster Metrics                                                │
├──────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────┐  ┌─────────────────────────────────┐   │
│  │  CPU Utilization            │  │  Disk Space Used                │   │
│  │                             │  │                                 │   │
│  │  ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁           │  │  ▁▁▂▂▃▃▄▄▅▅▆▆▇▇                │   │
│  │                             │  │                                 │   │
│  │  Current: 45%               │  │  Current: 62%                   │   │
│  └─────────────────────────────┘  └─────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  Recent Errors (Last 24 Hours)                                           │
├──────────────────────────────────────────────────────────────────────────┤
│  Timestamp           Job Name                  Error Message             │
│  2026-01-19 02:15   load_to_staging           Connection timeout         │
│  2026-01-18 14:30   data_quality_checks       Threshold exceeded         │
└──────────────────────────────────────────────────────────────────────────┘
```

---

**Note**: These diagrams are text-based representations. For production documentation, consider creating visual diagrams using tools like:
- Lucidchart
- Draw.io
- AWS Architecture Icons
- Microsoft Visio
- PlantUML
