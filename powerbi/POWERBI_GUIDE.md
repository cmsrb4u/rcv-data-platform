# RCV Data Platform - Power BI Report Guide

## CNR (Customer/Compliance/Registration) Report

### Report Structure

#### Page 1: Executive Dashboard
**KPIs (Top Row)**
- Total Registrations (YTD)
- Active Registrations
- Compliance Rate %
- Verification Success Rate %

**Visualizations**
1. **Registration Trend** (Line Chart)
   - X-axis: Month (from D_Date)
   - Y-axis: Count of registrations
   - Legend: Registration Status

2. **Registrations by Geography** (Map)
   - Location: State
   - Size: Count of registrations
   - Tooltip: State name, count, % of total

3. **Top 10 States** (Bar Chart)
   - Y-axis: State name
   - X-axis: Registration count
   - Sort: Descending

4. **Registration by Type** (Donut Chart)
   - Values: Count
   - Legend: Registration Type (from D_Code)

#### Page 2: Registration Analysis
**Filters (Left Panel)**
- Date Range (Year, Quarter, Month)
- State (Multi-select)
- Registration Status
- Registration Type

**Visualizations**
1. **Registration Details Table**
   ```
   Columns:
   - Registration Date
   - State
   - Zipcode
   - Registration Type
   - Status
   - Age at Registration
   - Data Source
   ```

2. **Age Distribution** (Histogram)
   - X-axis: Age groups (18-25, 26-35, etc.)
   - Y-axis: Count

3. **Registration Method** (Pie Chart)
   - Values: Count
   - Legend: Method (Internet, IVR, DMV, etc.)

4. **Monthly Trend by Status** (Stacked Area Chart)
   - X-axis: Month
   - Y-axis: Count
   - Legend: Status

#### Page 3: Compliance Analysis
**KPIs**
- Total Compliance Checks
- Pass Rate %
- DOJ Referrals
- Avg Days to Completion

**Visualizations**
1. **Compliance Status Over Time** (Line Chart)
   - X-axis: Month
   - Y-axis: Count
   - Legend: Compliance Status

2. **Compliance by State** (Map)
   - Location: State
   - Color: Pass Rate %
   - Tooltip: State, pass rate, total checks

3. **DOJ Referrals Trend** (Column Chart)
   - X-axis: Month
   - Y-axis: Count of DOJ referrals

4. **Compliance Results Matrix** (Matrix)
   ```
   Rows: State
   Columns: Compliance Result
   Values: Count, % of total
   ```

#### Page 4: Verification Analysis
**KPIs**
- Total Verifications
- Match Rate %
- Avg Match Score
- Avg Response Time (seconds)

**Visualizations**
1. **Verification Method Performance** (Clustered Bar)
   - Y-axis: Verification Method
   - X-axis: Success Rate %
   - Color: Method

2. **Match Score Distribution** (Histogram)
   - X-axis: Match Score ranges
   - Y-axis: Count

3. **Verification Status Funnel** (Funnel Chart)
   - Stages: Requested → In Progress → Completed → Verified

4. **Response Time Trend** (Line Chart)
   - X-axis: Month
   - Y-axis: Avg response time
   - Benchmark line: SLA threshold

---

## DAX Measures

### Registration Measures
```dax
Total Registrations = COUNTROWS(F_Registration)

Active Registrations = 
CALCULATE(
    COUNTROWS(F_Registration),
    D_Code[code_value] = "ACTIVE"
)

YTD Registrations = 
TOTALYTD(
    COUNTROWS(F_Registration),
    D_Date[date_value]
)

Registration Growth % = 
VAR CurrentMonth = [Total Registrations]
VAR PreviousMonth = 
    CALCULATE(
        [Total Registrations],
        DATEADD(D_Date[date_value], -1, MONTH)
    )
RETURN
    DIVIDE(CurrentMonth - PreviousMonth, PreviousMonth, 0)
```

### Compliance Measures
```dax
Total Compliance Checks = COUNTROWS(F_Compliance)

Compliance Pass Rate = 
VAR Passed = 
    CALCULATE(
        COUNTROWS(F_Compliance),
        D_Code[code_value] = "PASSED"
    )
VAR Total = [Total Compliance Checks]
RETURN
    DIVIDE(Passed, Total, 0)

DOJ Referrals = 
CALCULATE(
    COUNTROWS(F_Compliance),
    F_Compliance[is_doj_referral] = TRUE
)

Avg Days to Completion = 
AVERAGE(F_Compliance[days_to_completion])
```

### Verification Measures
```dax
Total Verifications = COUNTROWS(F_Verification)

Match Rate = 
VAR Matches = 
    CALCULATE(
        COUNTROWS(F_Verification),
        F_Verification[is_match] = TRUE
    )
VAR Total = [Total Verifications]
RETURN
    DIVIDE(Matches, Total, 0)

Avg Match Score = 
AVERAGE(F_Verification[match_score])

Avg Response Time = 
AVERAGE(F_Verification[response_time_seconds])
```

### Time Intelligence
```dax
Previous Year Registrations = 
CALCULATE(
    [Total Registrations],
    SAMEPERIODLASTYEAR(D_Date[date_value])
)

YoY Growth % = 
VAR Current = [Total Registrations]
VAR Previous = [Previous Year Registrations]
RETURN
    DIVIDE(Current - Previous, Previous, 0)

Moving Average 3M = 
AVERAGEX(
    DATESINPERIOD(
        D_Date[date_value],
        LASTDATE(D_Date[date_value]),
        -3,
        MONTH
    ),
    [Total Registrations]
)
```

---

## Power BI Model Relationships

### Star Schema Configuration
```
F_Registration (Fact)
├─→ D_Date (registration_date_key → date_key) [Many-to-One]
├─→ D_Date (birth_date_key → date_key) [Many-to-One, Inactive]
├─→ D_Code (registration_status_code_key → code_key) [Many-to-One]
├─→ D_Code (registration_type_code_key → code_key) [Many-to-One, Inactive]
├─→ D_Zipcode (zipcode_key → zipcode_key) [Many-to-One]
├─→ D_State (state_key → state_key) [Many-to-One]
└─→ D_DataSourceConfiguration (data_source_key → data_source_key) [Many-to-One]

F_Compliance (Fact)
├─→ D_Date (compliance_date_key → date_key) [Many-to-One]
├─→ D_Code (compliance_status_code_key → code_key) [Many-to-One]
└─→ D_State (state_key → state_key) [Many-to-One]

F_Verification (Fact)
├─→ D_Date (verification_date_key → date_key) [Many-to-One]
├─→ D_Code (verification_status_code_key → code_key) [Many-to-One]
└─→ D_State (state_key → state_key) [Many-to-One]

D_Zipcode
└─→ D_State (state_key → state_key) [Many-to-One]

D_State
└─→ D_Country (country_key → country_key) [Many-to-One]

D_Code
└─→ D_CodeCategory (code_category_key → code_category_key) [Many-to-One]
```

### Relationship Settings
- **Cross-filter direction**: Single (except for drill-through scenarios)
- **Cardinality**: Many-to-One for all fact-to-dimension
- **Active relationships**: Only one per table pair
- **Inactive relationships**: Use USERELATIONSHIP() in DAX

---

## Performance Optimization

### Query Optimization
1. **Use DirectQuery for real-time data**
   - Pushes queries to Redshift
   - Leverages Redshift compute power

2. **Create aggregation tables** (if needed)
   ```sql
   CREATE TABLE dw.agg_registration_monthly AS
   SELECT 
       d.year,
       d.month,
       s.state_name,
       c.code_value AS status,
       COUNT(*) AS registration_count
   FROM dw.f_registration f
   JOIN dw.d_date d ON f.registration_date_key = d.date_key
   JOIN dw.d_state s ON f.state_key = s.state_key
   JOIN dw.d_code c ON f.registration_status_code_key = c.code_key
   GROUP BY d.year, d.month, s.state_name, c.code_value;
   ```

3. **Use query reduction**
   - Limit visuals per page to 5-7
   - Use bookmarks for drill-through
   - Disable auto-refresh on slicers

### Visual Best Practices
1. **Limit data points**
   - Top N filters (Top 10 states)
   - Date range filters (Last 12 months)

2. **Use appropriate visuals**
   - Tables: < 100 rows
   - Line charts: < 1000 points
   - Maps: < 500 locations

3. **Optimize DAX**
   - Use variables
   - Avoid calculated columns (use measures)
   - Filter early in calculations

---

## Row-Level Security (RLS)

### Setup RLS in Power BI
```dax
-- Create role: State Manager
[State] = USERNAME()

-- Create role: Regional Manager
[Region] IN {"West", "East", "Central"}

-- Create role: National Manager
1=1  -- See all data
```

### Apply RLS
1. Modeling → Manage Roles
2. Create role
3. Add DAX filter to D_State table
4. Test with "View as Role"

---

## Report Publishing Checklist

- [ ] Test all visuals with production data
- [ ] Verify all relationships are correct
- [ ] Test all filters and slicers
- [ ] Validate DAX measures
- [ ] Test drill-through functionality
- [ ] Configure RLS
- [ ] Test RLS with different users
- [ ] Optimize query performance
- [ ] Add report documentation
- [ ] Publish to Power BI Service
- [ ] Configure refresh schedule (if using Import)
- [ ] Share with stakeholders
- [ ] Gather feedback
- [ ] Iterate and improve
