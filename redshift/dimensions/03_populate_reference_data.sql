-- Populate Date Dimension
-- Generate 20 years of dates (2015-2035)

INSERT INTO dw.d_date (
    date_key,
    date_value,
    year,
    quarter,
    month,
    month_name,
    week_of_year,
    day_of_month,
    day_of_week,
    day_name,
    is_weekend,
    is_holiday,
    fiscal_year,
    fiscal_quarter
)
WITH date_series AS (
    SELECT 
        DATEADD(day, seq, '2015-01-01'::DATE) AS date_value
    FROM 
        (SELECT ROW_NUMBER() OVER (ORDER BY 1) - 1 AS seq
         FROM information_schema.tables
         LIMIT 7305)  -- 20 years
)
SELECT
    CAST(TO_CHAR(date_value, 'YYYYMMDD') AS INTEGER) AS date_key,
    date_value,
    EXTRACT(YEAR FROM date_value) AS year,
    EXTRACT(QUARTER FROM date_value) AS quarter,
    EXTRACT(MONTH FROM date_value) AS month,
    TO_CHAR(date_value, 'Month') AS month_name,
    EXTRACT(WEEK FROM date_value) AS week_of_year,
    EXTRACT(DAY FROM date_value) AS day_of_month,
    EXTRACT(DOW FROM date_value) AS day_of_week,
    TO_CHAR(date_value, 'Day') AS day_name,
    CASE WHEN EXTRACT(DOW FROM date_value) IN (0, 6) THEN TRUE ELSE FALSE END AS is_weekend,
    FALSE AS is_holiday,  -- Update separately with holiday calendar
    CASE 
        WHEN EXTRACT(MONTH FROM date_value) >= 10 THEN EXTRACT(YEAR FROM date_value) + 1
        ELSE EXTRACT(YEAR FROM date_value)
    END AS fiscal_year,
    CASE 
        WHEN EXTRACT(MONTH FROM date_value) IN (10, 11, 12) THEN 1
        WHEN EXTRACT(MONTH FROM date_value) IN (1, 2, 3) THEN 2
        WHEN EXTRACT(MONTH FROM date_value) IN (4, 5, 6) THEN 3
        ELSE 4
    END AS fiscal_quarter
FROM date_series;

-- Populate Code Categories
INSERT INTO dw.d_code_category (
    code_category_id,
    category_name,
    category_type,
    description,
    effective_start_dt,
    is_active
) VALUES
('REG_TYPE', 'Registration Type', 'registration', 'Types of voter registration', GETDATE(), TRUE),
('REG_STATUS', 'Registration Status', 'registration', 'Status of registration', GETDATE(), TRUE),
('COMP_STATUS', 'Compliance Status', 'compliance', 'Compliance check status', GETDATE(), TRUE),
('COMP_RESULT', 'Compliance Result', 'compliance', 'Result of compliance check', GETDATE(), TRUE),
('VERIF_METHOD', 'Verification Method', 'verification', 'Method used for verification', GETDATE(), TRUE),
('VERIF_STATUS', 'Verification Status', 'verification', 'Status of verification', GETDATE(), TRUE),
('VERIF_RESULT', 'Verification Result', 'verification', 'Result of verification', GETDATE(), TRUE),
('CLASSIFICATION', 'Classification', 'registration', 'Registration classification', GETDATE(), TRUE);

-- Populate Codes
INSERT INTO dw.d_code (
    code_id,
    code_category_key,
    code_value,
    code_description,
    display_order,
    effective_start_dt,
    is_active
)
SELECT
    'REG_TYPE_' || seq AS code_id,
    (SELECT code_category_key FROM dw.d_code_category WHERE code_category_id = 'REG_TYPE' AND is_active = TRUE) AS code_category_key,
    code_value,
    code_description,
    display_order,
    GETDATE() AS effective_start_dt,
    TRUE AS is_active
FROM (
    SELECT 'NEW' AS code_value, 'New Registration' AS code_description, 1 AS display_order, 1 AS seq
    UNION ALL SELECT 'RENEWAL', 'Renewal', 2, 2
    UNION ALL SELECT 'UPDATE', 'Update Existing', 3, 3
    UNION ALL SELECT 'TRANSFER', 'Transfer', 4, 4
);

INSERT INTO dw.d_code (code_id, code_category_key, code_value, code_description, display_order, effective_start_dt, is_active)
SELECT
    'REG_STATUS_' || seq AS code_id,
    (SELECT code_category_key FROM dw.d_code_category WHERE code_category_id = 'REG_STATUS' AND is_active = TRUE),
    code_value, code_description, display_order, GETDATE(), TRUE
FROM (
    SELECT 'ACTIVE' AS code_value, 'Active' AS code_description, 1 AS display_order, 1 AS seq
    UNION ALL SELECT 'INACTIVE', 'Inactive', 2, 2
    UNION ALL SELECT 'PENDING', 'Pending', 3, 3
    UNION ALL SELECT 'CANCELLED', 'Cancelled', 4, 4
    UNION ALL SELECT 'SUSPENDED', 'Suspended', 5, 5
);

-- Populate Data Sources
INSERT INTO dw.d_data_source_configuration (
    data_source_id,
    source_name,
    source_type,
    source_system,
    schedule_frequency,
    is_enabled,
    effective_start_dt,
    is_active
) VALUES
('SRC_INTERNET', 'Internet', 'Online', 'RCV Web Portal', 'Real-time', TRUE, GETDATE(), TRUE),
('SRC_IVR', 'IVR', 'Phone', 'RCV IVR System', 'Real-time', TRUE, GETDATE(), TRUE),
('SRC_DMV', 'DMV', 'Integration', 'DMV System', 'Daily', TRUE, GETDATE(), TRUE),
('SRC_BATCH', 'Batch File', 'File', 'Batch Processing', 'Daily', TRUE, GETDATE(), TRUE),
('SRC_MOBILE', 'Mobile App', 'Mobile', 'RCV Mobile App', 'Real-time', TRUE, GETDATE(), TRUE);

-- Populate Geography (Sample)
INSERT INTO dw.d_country (country_id, country_name, country_code_iso2, country_code_iso3, effective_start_dt, is_active)
VALUES ('USA', 'United States', 'US', 'USA', GETDATE(), TRUE);

INSERT INTO dw.d_state (state_id, state_name, state_code, country_key, effective_start_dt, is_active)
SELECT 
    state_code AS state_id,
    state_name,
    state_code,
    (SELECT country_key FROM dw.d_country WHERE country_id = 'USA' AND is_active = TRUE),
    GETDATE(),
    TRUE
FROM (
    SELECT 'CA' AS state_code, 'California' AS state_name
    UNION ALL SELECT 'NY', 'New York'
    UNION ALL SELECT 'TX', 'Texas'
    UNION ALL SELECT 'FL', 'Florida'
    -- Add all 50 states
);

COMMIT;
