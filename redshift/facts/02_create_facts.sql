-- Redshift Data Warehouse Schema
-- RCV Data Platform - Fact Tables

-- ============================================
-- FACT: REGISTRATION (Star Schema)
-- ============================================
CREATE TABLE dw.f_registration (
    registration_key BIGINT IDENTITY(1,1) NOT NULL SORTKEY,
    registration_id VARCHAR(100) NOT NULL,
    
    -- Date Foreign Keys
    registration_date_key INTEGER NOT NULL,
    birth_date_key INTEGER,
    effective_date_key INTEGER,
    
    -- Dimension Foreign Keys
    registration_status_code_key INTEGER NOT NULL,
    registration_type_code_key INTEGER,
    classification_code_key INTEGER,
    zipcode_key INTEGER,
    state_key INTEGER,
    country_key INTEGER,
    data_source_key INTEGER NOT NULL,
    file_key INTEGER NOT NULL,
    
    -- Measures and Attributes (NO PII)
    age_at_registration INTEGER,
    registration_method VARCHAR(50),
    is_first_time_registration BOOLEAN,
    previous_registration_count INTEGER,
    
    -- Operational Fields
    source_system_id VARCHAR(100),
    source_record_version INTEGER,
    record_hash VARCHAR(64),
    
    -- Audit Fields
    created_dt TIMESTAMP DEFAULT GETDATE(),
    updated_dt TIMESTAMP DEFAULT GETDATE(),
    
    PRIMARY KEY (registration_key),
    FOREIGN KEY (registration_date_key) REFERENCES dw.d_date(date_key),
    FOREIGN KEY (birth_date_key) REFERENCES dw.d_date(date_key),
    FOREIGN KEY (registration_status_code_key) REFERENCES dw.d_code(code_key),
    FOREIGN KEY (registration_type_code_key) REFERENCES dw.d_code(code_key),
    FOREIGN KEY (zipcode_key) REFERENCES dw.d_zipcode(zipcode_key),
    FOREIGN KEY (state_key) REFERENCES dw.d_state(state_key),
    FOREIGN KEY (data_source_key) REFERENCES dw.d_data_source_configuration(data_source_key),
    FOREIGN KEY (file_key) REFERENCES dw.d_file_information(file_key)
) DISTSTYLE KEY DISTKEY (registration_date_key);

-- ============================================
-- FACT: COMPLIANCE (Star Schema)
-- ============================================
CREATE TABLE dw.f_compliance (
    compliance_key BIGINT IDENTITY(1,1) NOT NULL SORTKEY,
    compliance_id VARCHAR(100) NOT NULL,
    registration_id VARCHAR(100),
    
    -- Date Foreign Keys
    compliance_date_key INTEGER NOT NULL,
    due_date_key INTEGER,
    completion_date_key INTEGER,
    
    -- Dimension Foreign Keys
    compliance_status_code_key INTEGER NOT NULL,
    compliance_result_code_key INTEGER,
    state_key INTEGER,
    data_source_key INTEGER NOT NULL,
    file_key INTEGER NOT NULL,
    
    -- Measures and Attributes
    is_doj_referral BOOLEAN,
    compliance_score DECIMAL(5,2),
    days_to_completion INTEGER,
    source_list_type VARCHAR(50),
    source_year INTEGER,
    
    -- Operational Fields
    error_message VARCHAR(2000),
    retry_count INTEGER,
    source_system_id VARCHAR(100),
    record_hash VARCHAR(64),
    
    -- Audit Fields
    created_dt TIMESTAMP DEFAULT GETDATE(),
    updated_dt TIMESTAMP DEFAULT GETDATE(),
    
    PRIMARY KEY (compliance_key),
    FOREIGN KEY (compliance_date_key) REFERENCES dw.d_date(date_key),
    FOREIGN KEY (compliance_status_code_key) REFERENCES dw.d_code(code_key),
    FOREIGN KEY (state_key) REFERENCES dw.d_state(state_key),
    FOREIGN KEY (data_source_key) REFERENCES dw.d_data_source_configuration(data_source_key),
    FOREIGN KEY (file_key) REFERENCES dw.d_file_information(file_key)
) DISTSTYLE KEY DISTKEY (compliance_date_key);

-- ============================================
-- FACT: VERIFICATION (Star Schema)
-- ============================================
CREATE TABLE dw.f_verification (
    verification_key BIGINT IDENTITY(1,1) NOT NULL SORTKEY,
    verification_id VARCHAR(100) NOT NULL,
    registration_id VARCHAR(100),
    
    -- Date Foreign Keys
    verification_date_key INTEGER NOT NULL,
    request_date_key INTEGER,
    response_date_key INTEGER,
    
    -- Dimension Foreign Keys
    verification_method_code_key INTEGER NOT NULL,
    verification_status_code_key INTEGER NOT NULL,
    verification_result_code_key INTEGER,
    state_key INTEGER,
    data_source_key INTEGER NOT NULL,
    file_key INTEGER NOT NULL,
    
    -- Measures and Attributes
    is_match BOOLEAN,
    match_score DECIMAL(5,2),
    interim_status VARCHAR(50),
    verification_flags VARCHAR(500),
    response_time_seconds INTEGER,
    
    -- Operational Fields
    error_message VARCHAR(2000),
    retry_count INTEGER,
    source_system_id VARCHAR(100),
    record_hash VARCHAR(64),
    
    -- Audit Fields
    created_dt TIMESTAMP DEFAULT GETDATE(),
    updated_dt TIMESTAMP DEFAULT GETDATE(),
    
    PRIMARY KEY (verification_key),
    FOREIGN KEY (verification_date_key) REFERENCES dw.d_date(date_key),
    FOREIGN KEY (verification_method_code_key) REFERENCES dw.d_code(code_key),
    FOREIGN KEY (verification_status_code_key) REFERENCES dw.d_code(code_key),
    FOREIGN KEY (state_key) REFERENCES dw.d_state(state_key),
    FOREIGN KEY (data_source_key) REFERENCES dw.d_data_source_configuration(data_source_key),
    FOREIGN KEY (file_key) REFERENCES dw.d_file_information(file_key)
) DISTSTYLE KEY DISTKEY (verification_date_key);

-- ============================================
-- HISTORY FACT: REGISTRATION (SCD for Facts)
-- ============================================
CREATE TABLE dw.f_registration_hist (
    registration_hist_key BIGINT IDENTITY(1,1) NOT NULL SORTKEY,
    registration_key BIGINT NOT NULL,
    registration_id VARCHAR(100) NOT NULL,
    
    -- Snapshot Date
    snapshot_date_key INTEGER NOT NULL,
    
    -- All dimension keys and measures from f_registration
    registration_date_key INTEGER NOT NULL,
    registration_status_code_key INTEGER NOT NULL,
    registration_type_code_key INTEGER,
    zipcode_key INTEGER,
    state_key INTEGER,
    
    -- Change tracking
    change_type VARCHAR(20), -- INSERT, UPDATE, DELETE
    effective_start_dt TIMESTAMP NOT NULL,
    effective_end_dt TIMESTAMP,
    is_current BOOLEAN DEFAULT TRUE,
    
    -- Audit
    created_dt TIMESTAMP DEFAULT GETDATE(),
    
    PRIMARY KEY (registration_hist_key),
    FOREIGN KEY (registration_key) REFERENCES dw.f_registration(registration_key),
    FOREIGN KEY (snapshot_date_key) REFERENCES dw.d_date(date_key)
) DISTSTYLE KEY DISTKEY (snapshot_date_key);

-- ============================================
-- HISTORY FACT: COMPLIANCE
-- ============================================
CREATE TABLE dw.f_compliance_hist (
    compliance_hist_key BIGINT IDENTITY(1,1) NOT NULL SORTKEY,
    compliance_key BIGINT NOT NULL,
    compliance_id VARCHAR(100) NOT NULL,
    
    snapshot_date_key INTEGER NOT NULL,
    compliance_date_key INTEGER NOT NULL,
    compliance_status_code_key INTEGER NOT NULL,
    compliance_result_code_key INTEGER,
    
    change_type VARCHAR(20),
    effective_start_dt TIMESTAMP NOT NULL,
    effective_end_dt TIMESTAMP,
    is_current BOOLEAN DEFAULT TRUE,
    created_dt TIMESTAMP DEFAULT GETDATE(),
    
    PRIMARY KEY (compliance_hist_key),
    FOREIGN KEY (compliance_key) REFERENCES dw.f_compliance(compliance_key),
    FOREIGN KEY (snapshot_date_key) REFERENCES dw.d_date(date_key)
) DISTSTYLE KEY DISTKEY (snapshot_date_key);

-- ============================================
-- HISTORY FACT: VERIFICATION
-- ============================================
CREATE TABLE dw.f_verification_hist (
    verification_hist_key BIGINT IDENTITY(1,1) NOT NULL SORTKEY,
    verification_key BIGINT NOT NULL,
    verification_id VARCHAR(100) NOT NULL,
    
    snapshot_date_key INTEGER NOT NULL,
    verification_date_key INTEGER NOT NULL,
    verification_status_code_key INTEGER NOT NULL,
    verification_result_code_key INTEGER,
    
    change_type VARCHAR(20),
    effective_start_dt TIMESTAMP NOT NULL,
    effective_end_dt TIMESTAMP,
    is_current BOOLEAN DEFAULT TRUE,
    created_dt TIMESTAMP DEFAULT GETDATE(),
    
    PRIMARY KEY (verification_hist_key),
    FOREIGN KEY (verification_key) REFERENCES dw.f_verification(verification_key),
    FOREIGN KEY (snapshot_date_key) REFERENCES dw.d_date(date_key)
) DISTSTYLE KEY DISTKEY (snapshot_date_key);

-- ============================================
-- INDEXES
-- ============================================
CREATE INDEX idx_f_registration_id ON dw.f_registration(registration_id);
CREATE INDEX idx_f_registration_date ON dw.f_registration(registration_date_key);
CREATE INDEX idx_f_compliance_id ON dw.f_compliance(compliance_id);
CREATE INDEX idx_f_compliance_date ON dw.f_compliance(compliance_date_key);
CREATE INDEX idx_f_verification_id ON dw.f_verification(verification_id);
CREATE INDEX idx_f_verification_date ON dw.f_verification(verification_date_key);
