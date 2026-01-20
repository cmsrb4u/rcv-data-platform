-- Redshift Staging Schema
-- RCV Data Platform - Staging Tables

CREATE SCHEMA IF NOT EXISTS staging;

-- ============================================
-- STAGING: REGISTRATION
-- ============================================
CREATE TABLE staging.stg_registration (
    stg_registration_id BIGINT IDENTITY(1,1),
    
    -- Source Fields (including PII for processing)
    registration_id VARCHAR(100),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(200),
    phone VARCHAR(20),
    street_address VARCHAR(500),
    city VARCHAR(100),
    state VARCHAR(50),
    zipcode VARCHAR(10),
    country VARCHAR(50),
    
    -- Registration Details
    registration_date DATE,
    birth_date DATE,
    registration_status VARCHAR(50),
    registration_type VARCHAR(50),
    classification VARCHAR(50),
    registration_method VARCHAR(50),
    
    -- Metadata
    source_system VARCHAR(100),
    source_file_name VARCHAR(500),
    load_timestamp TIMESTAMP DEFAULT GETDATE(),
    processing_status VARCHAR(50) DEFAULT 'PENDING',
    error_message VARCHAR(2000),
    
    -- DQ Flags
    dq_is_valid BOOLEAN DEFAULT TRUE,
    dq_validation_errors VARCHAR(2000)
) DISTSTYLE EVEN;

-- ============================================
-- STAGING: COMPLIANCE
-- ============================================
CREATE TABLE staging.stg_compliance (
    stg_compliance_id BIGINT IDENTITY(1,1),
    
    compliance_id VARCHAR(100),
    registration_id VARCHAR(100),
    compliance_date DATE,
    due_date DATE,
    completion_date DATE,
    compliance_status VARCHAR(50),
    compliance_result VARCHAR(50),
    is_doj_referral BOOLEAN,
    source_list_type VARCHAR(50),
    source_year INTEGER,
    state VARCHAR(50),
    
    -- Metadata
    source_system VARCHAR(100),
    source_file_name VARCHAR(500),
    load_timestamp TIMESTAMP DEFAULT GETDATE(),
    processing_status VARCHAR(50) DEFAULT 'PENDING',
    error_message VARCHAR(2000),
    
    dq_is_valid BOOLEAN DEFAULT TRUE,
    dq_validation_errors VARCHAR(2000)
) DISTSTYLE EVEN;

-- ============================================
-- STAGING: VERIFICATION
-- ============================================
CREATE TABLE staging.stg_verification (
    stg_verification_id BIGINT IDENTITY(1,1),
    
    verification_id VARCHAR(100),
    registration_id VARCHAR(100),
    verification_date DATE,
    request_date DATE,
    response_date DATE,
    verification_method VARCHAR(50),
    verification_status VARCHAR(50),
    verification_result VARCHAR(50),
    interim_status VARCHAR(50),
    is_match BOOLEAN,
    match_score DECIMAL(5,2),
    verification_flags VARCHAR(500),
    state VARCHAR(50),
    
    -- Metadata
    source_system VARCHAR(100),
    source_file_name VARCHAR(500),
    load_timestamp TIMESTAMP DEFAULT GETDATE(),
    processing_status VARCHAR(50) DEFAULT 'PENDING',
    error_message VARCHAR(2000),
    
    dq_is_valid BOOLEAN DEFAULT TRUE,
    dq_validation_errors VARCHAR(2000)
) DISTSTYLE EVEN;

-- ============================================
-- STAGING: ENRICHMENT FILES
-- ============================================
CREATE TABLE staging.stg_zip_geography (
    zipcode VARCHAR(10),
    city VARCHAR(100),
    state_code CHAR(2),
    county VARCHAR(100),
    timezone VARCHAR(50),
    area_code VARCHAR(10),
    load_timestamp TIMESTAMP DEFAULT GETDATE()
) DISTSTYLE ALL;

CREATE TABLE staging.stg_census (
    census_tract VARCHAR(20),
    zipcode VARCHAR(10),
    population INTEGER,
    median_income DECIMAL(12,2),
    median_age DECIMAL(5,2),
    census_year INTEGER,
    load_timestamp TIMESTAMP DEFAULT GETDATE()
) DISTSTYLE ALL;

CREATE TABLE staging.stg_county_demographics (
    county_fips VARCHAR(10),
    county_name VARCHAR(100),
    state_code CHAR(2),
    total_population INTEGER,
    median_household_income DECIMAL(12,2),
    unemployment_rate DECIMAL(5,2),
    education_level_pct DECIMAL(5,2),
    demo_year INTEGER,
    load_timestamp TIMESTAMP DEFAULT GETDATE()
) DISTSTYLE ALL;

-- ============================================
-- CONTROL TABLE: ETL Metadata
-- ============================================
CREATE TABLE staging.etl_control (
    etl_control_id INTEGER IDENTITY(1,1),
    job_name VARCHAR(200) NOT NULL,
    job_type VARCHAR(50), -- INITIAL_LOAD, INCREMENTAL, ARCHIVE
    start_timestamp TIMESTAMP NOT NULL,
    end_timestamp TIMESTAMP,
    status VARCHAR(50), -- RUNNING, SUCCESS, FAILED
    records_read INTEGER,
    records_written INTEGER,
    records_rejected INTEGER,
    error_message VARCHAR(2000),
    last_processed_date DATE,
    PRIMARY KEY (etl_control_id)
) DISTSTYLE ALL;

-- ============================================
-- CONTROL TABLE: Data Quality Results
-- ============================================
CREATE TABLE staging.dq_results (
    dq_result_id BIGINT IDENTITY(1,1),
    table_name VARCHAR(100),
    check_name VARCHAR(200),
    check_type VARCHAR(50), -- COMPLETENESS, VALIDITY, CONSISTENCY
    check_timestamp TIMESTAMP DEFAULT GETDATE(),
    records_checked INTEGER,
    records_passed INTEGER,
    records_failed INTEGER,
    pass_rate DECIMAL(5,2),
    threshold DECIMAL(5,2),
    status VARCHAR(20), -- PASS, FAIL, WARNING
    details VARCHAR(2000),
    PRIMARY KEY (dq_result_id)
) DISTSTYLE EVEN;
