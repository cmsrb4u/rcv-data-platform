-- Redshift Data Warehouse Schema
-- RCV Data Platform - Dimension Tables

-- ============================================
-- DATE DIMENSION (Conformed)
-- ============================================
CREATE TABLE dw.d_date (
    date_key INTEGER NOT NULL SORTKEY,
    date_value DATE NOT NULL,
    year INTEGER NOT NULL,
    quarter INTEGER NOT NULL,
    month INTEGER NOT NULL,
    month_name VARCHAR(20),
    week_of_year INTEGER,
    day_of_month INTEGER,
    day_of_week INTEGER,
    day_name VARCHAR(20),
    is_weekend BOOLEAN,
    is_holiday BOOLEAN,
    fiscal_year INTEGER,
    fiscal_quarter INTEGER,
    PRIMARY KEY (date_key)
) DISTSTYLE ALL;

-- ============================================
-- CODE CATEGORY DIMENSION (SCD Type 2)
-- ============================================
CREATE TABLE dw.d_code_category (
    code_category_key INTEGER IDENTITY(1,1) NOT NULL SORTKEY,
    code_category_id VARCHAR(50) NOT NULL,
    category_name VARCHAR(100) NOT NULL,
    category_type VARCHAR(50), -- registration_type, compliance_status, verification_type
    description VARCHAR(500),
    effective_start_dt TIMESTAMP NOT NULL,
    effective_end_dt TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_dt TIMESTAMP DEFAULT GETDATE(),
    updated_dt TIMESTAMP DEFAULT GETDATE(),
    PRIMARY KEY (code_category_key)
) DISTSTYLE ALL;

-- ============================================
-- CODE DIMENSION (SCD Type 2)
-- ============================================
CREATE TABLE dw.d_code (
    code_key INTEGER IDENTITY(1,1) NOT NULL SORTKEY,
    code_id VARCHAR(50) NOT NULL,
    code_category_key INTEGER NOT NULL,
    code_value VARCHAR(100) NOT NULL,
    code_description VARCHAR(500),
    display_order INTEGER,
    effective_start_dt TIMESTAMP NOT NULL,
    effective_end_dt TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_dt TIMESTAMP DEFAULT GETDATE(),
    updated_dt TIMESTAMP DEFAULT GETDATE(),
    PRIMARY KEY (code_key),
    FOREIGN KEY (code_category_key) REFERENCES dw.d_code_category(code_category_key)
) DISTSTYLE ALL;

-- ============================================
-- GEOGRAPHY DIMENSIONS (SCD Type 2)
-- ============================================
CREATE TABLE dw.d_country (
    country_key INTEGER IDENTITY(1,1) NOT NULL SORTKEY,
    country_id VARCHAR(10) NOT NULL,
    country_name VARCHAR(100) NOT NULL,
    country_code_iso2 CHAR(2),
    country_code_iso3 CHAR(3),
    effective_start_dt TIMESTAMP NOT NULL,
    effective_end_dt TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (country_key)
) DISTSTYLE ALL;

CREATE TABLE dw.d_state (
    state_key INTEGER IDENTITY(1,1) NOT NULL SORTKEY,
    state_id VARCHAR(10) NOT NULL,
    state_name VARCHAR(100) NOT NULL,
    state_code CHAR(2),
    country_key INTEGER NOT NULL,
    effective_start_dt TIMESTAMP NOT NULL,
    effective_end_dt TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (state_key),
    FOREIGN KEY (country_key) REFERENCES dw.d_country(country_key)
) DISTSTYLE ALL;

CREATE TABLE dw.d_zipcode (
    zipcode_key INTEGER IDENTITY(1,1) NOT NULL SORTKEY,
    zipcode_id VARCHAR(20) NOT NULL,
    zipcode VARCHAR(10) NOT NULL,
    city VARCHAR(100),
    state_key INTEGER NOT NULL,
    latitude DECIMAL(10,6),
    longitude DECIMAL(10,6),
    effective_start_dt TIMESTAMP NOT NULL,
    effective_end_dt TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (zipcode_key),
    FOREIGN KEY (state_key) REFERENCES dw.d_state(state_key)
) DISTSTYLE ALL;

-- ============================================
-- DATA SOURCE CONFIGURATION (SCD Type 2)
-- ============================================
CREATE TABLE dw.d_data_source_configuration (
    data_source_key INTEGER IDENTITY(1,1) NOT NULL SORTKEY,
    data_source_id VARCHAR(50) NOT NULL,
    source_name VARCHAR(100) NOT NULL, -- Internet, IVR, DMV, Batch
    source_type VARCHAR(50),
    source_system VARCHAR(100),
    connection_string VARCHAR(500),
    schedule_frequency VARCHAR(50),
    is_enabled BOOLEAN DEFAULT TRUE,
    effective_start_dt TIMESTAMP NOT NULL,
    effective_end_dt TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (data_source_key)
) DISTSTYLE ALL;

-- ============================================
-- FILE INFORMATION (Operational Dimension)
-- ============================================
CREATE TABLE dw.d_file_information (
    file_key INTEGER IDENTITY(1,1) NOT NULL SORTKEY,
    file_id VARCHAR(100) NOT NULL,
    data_source_key INTEGER NOT NULL,
    file_name VARCHAR(500) NOT NULL,
    file_path VARCHAR(1000),
    file_size_bytes BIGINT,
    record_count INTEGER,
    load_timestamp TIMESTAMP NOT NULL,
    processing_status VARCHAR(50), -- pending, processing, completed, failed
    error_message VARCHAR(2000),
    created_dt TIMESTAMP DEFAULT GETDATE(),
    PRIMARY KEY (file_key),
    FOREIGN KEY (data_source_key) REFERENCES dw.d_data_source_configuration(data_source_key)
) DISTSTYLE EVEN;

-- ============================================
-- ENRICHMENT DIMENSIONS (Type 1 - Overwrite)
-- ============================================
CREATE TABLE dw.d_zip_geography (
    zip_geography_key INTEGER IDENTITY(1,1) NOT NULL SORTKEY,
    zipcode VARCHAR(10) NOT NULL,
    city VARCHAR(100),
    state_code CHAR(2),
    county VARCHAR(100),
    timezone VARCHAR(50),
    area_code VARCHAR(10),
    last_updated_dt TIMESTAMP DEFAULT GETDATE(),
    PRIMARY KEY (zip_geography_key)
) DISTSTYLE ALL;

CREATE TABLE dw.d_census (
    census_key INTEGER IDENTITY(1,1) NOT NULL SORTKEY,
    census_tract VARCHAR(20) NOT NULL,
    zipcode VARCHAR(10),
    population INTEGER,
    median_income DECIMAL(12,2),
    median_age DECIMAL(5,2),
    census_year INTEGER,
    last_updated_dt TIMESTAMP DEFAULT GETDATE(),
    PRIMARY KEY (census_key)
) DISTSTYLE ALL;

CREATE TABLE dw.d_county_demographics (
    county_demo_key INTEGER IDENTITY(1,1) NOT NULL SORTKEY,
    county_fips VARCHAR(10) NOT NULL,
    county_name VARCHAR(100),
    state_code CHAR(2),
    total_population INTEGER,
    median_household_income DECIMAL(12,2),
    unemployment_rate DECIMAL(5,2),
    education_level_pct DECIMAL(5,2),
    demo_year INTEGER,
    last_updated_dt TIMESTAMP DEFAULT GETDATE(),
    PRIMARY KEY (county_demo_key)
) DISTSTYLE ALL;

-- ============================================
-- INDEXES AND CONSTRAINTS
-- ============================================
CREATE INDEX idx_d_code_category_id ON dw.d_code_category(code_category_id, is_active);
CREATE INDEX idx_d_code_id ON dw.d_code(code_id, is_active);
CREATE INDEX idx_d_zipcode_id ON dw.d_zipcode(zipcode_id, is_active);
CREATE INDEX idx_d_state_id ON dw.d_state(state_id, is_active);
CREATE INDEX idx_d_country_id ON dw.d_country(country_id, is_active);
CREATE INDEX idx_d_data_source_id ON dw.d_data_source_configuration(data_source_id, is_active);
