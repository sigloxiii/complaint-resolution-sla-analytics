-- =====================================================================
-- step_7.sql  |  Mart layer (star schema) for complaints and accesses
-- =====================================================================
-- Objective   : build the tables that Power BI reads. Two fact tables
--               (complaints and accesses) share the dimensions date, state
--               and operator. No cleaning happens here: the mart only
--               reshapes clean.profeco_complaint and clean.bit_access.
-- Source      : clean.profeco_complaint (step_3), clean.state_map (step_3),
--               clean.bit_access (step_6).
-- Prerequisites: steps 0, 3 and 6 executed.
-- How to run  : run it block by block (select the block, press F5).
--               Save a capture of each check as docs/img/step_7_check_NN.png.
--
-- Design (decision D14, docs/decisions.md):
--   * fact_complaint : one row per row of clean.profeco_complaint (36,034).
--   * fact_accesses  : one row per month, state and operator (BIT rows are
--                      added: D12; technology is not filtered: D13).
--   * dim_operator   : 5 rows (Telmex, Izzi, Megacable, Total Play, Other).
--                      It joins BOTH facts, so complaints and accesses can be
--                      divided by operator.
--   * dim_brand      : one row per brand of the complaints (network type,
--                      dashboard scope).
--   * dim_state      : INEGI state code. In the complaints it is the PROFECO
--                      office state, not where the consumer lives (D8).
--   * dim_date       : one row per day, 2013-01-01 to 2026-12-31. The monthly
--                      accesses use the first day of the month.
--   * dim_reason, dim_outcome: small lookup tables of the complaint.
--   * Rates per 100,000 accesses use the FILING year of the complaint and the
--     accesses of December of that year (A_TOTAL_E is a stock, never added).
-- =====================================================================

USE complaint_sla;
GO

-- ---------------------------------------------------------------------
-- 7.0 Drop and create the tables (facts first because they point to the dims)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS mart.fact_accesses;
DROP TABLE IF EXISTS mart.fact_complaint;
DROP TABLE IF EXISTS mart.dim_outcome;
DROP TABLE IF EXISTS mart.dim_reason;
DROP TABLE IF EXISTS mart.dim_brand;
DROP TABLE IF EXISTS mart.dim_operator;
DROP TABLE IF EXISTS mart.dim_state;
DROP TABLE IF EXISTS mart.dim_date;
GO

CREATE TABLE mart.dim_date (
    date_key        INT          NOT NULL PRIMARY KEY,  -- yyyymmdd, for example 20241231
    date_value      DATE         NOT NULL,
    year_num        SMALLINT     NOT NULL,
    quarter_num     TINYINT      NOT NULL,
    month_num       TINYINT      NOT NULL,
    month_name      NVARCHAR(10) NOT NULL,              -- English month name
    year_month      CHAR(7)      NOT NULL,              -- 2024-12
    is_month_start  BIT          NOT NULL,              -- 1 = first day of the month (monthly accesses)
    is_december     BIT          NOT NULL               -- 1 = month 12 (base of the denominators)
);

CREATE TABLE mart.dim_state (
    state_key   INT          NOT NULL PRIMARY KEY,
    state_code  CHAR(2)      NOT NULL,                  -- INEGI code; 99 = no information
    state_name  NVARCHAR(60) NOT NULL                   -- in the complaints: PROFECO office state (D8)
);

CREATE TABLE mart.dim_operator (
    operator_key     INT           NOT NULL PRIMARY KEY,
    operator_name    NVARCHAR(30)  NOT NULL,
    bit_group        NVARCHAR(100) NULL,                -- GRUPO of the BIT used as denominator
    is_main_operator BIT           NOT NULL,            -- 1 = one of the four operators of D11
    sort_order       TINYINT       NOT NULL
);

CREATE TABLE mart.dim_brand (
    brand_key          INT           NOT NULL PRIMARY KEY,
    brand              NVARCHAR(200) NOT NULL,
    network_type       NVARCHAR(30)  NOT NULL,          -- Fixed / Mobile / Pay TV (satellite) / Device maker / Not classified
    bit_group          NVARCHAR(100) NULL,
    in_dashboard_scope BIT           NOT NULL           -- 1 = fixed broadband (D11)
);

CREATE TABLE mart.dim_reason (
    reason_key   INT           NOT NULL PRIMARY KEY,
    claim_type   NVARCHAR(300) NOT NULL,                -- tipo_reclamacion
    claim_reason NVARCHAR(400) NOT NULL                 -- motivo_reclamacion
);

CREATE TABLE mart.dim_outcome (
    outcome_key       INT           NOT NULL PRIMARY KEY,
    outcome           NVARCHAR(100) NOT NULL,           -- Conciliada, Desistimiento, ...
    conciliation_type NVARCHAR(50)  NOT NULL,
    procedure_group   NVARCHAR(30)  NOT NULL
);

CREATE TABLE mart.fact_complaint (
    complaint_key            INT           NOT NULL PRIMARY KEY,  -- same key as clean.profeco_complaint
    case_id                  NVARCHAR(50)  NULL,                  -- not unique (flag_shared_case_id)
    filing_date_key          INT           NULL REFERENCES mart.dim_date (date_key),
    close_date_key           INT           NULL REFERENCES mart.dim_date (date_key),  -- NULL = no close date
    state_key                INT           NOT NULL REFERENCES mart.dim_state (state_key),
    operator_key             INT           NOT NULL REFERENCES mart.dim_operator (operator_key),
    brand_key                INT           NOT NULL REFERENCES mart.dim_brand (brand_key),
    reason_key               INT           NOT NULL REFERENCES mart.dim_reason (reason_key),
    outcome_key              INT           NOT NULL REFERENCES mart.dim_outcome (outcome_key),
    channel                  NVARCHAR(100) NULL,
    service_hint             NVARCHAR(50)  NOT NULL,              -- partial hint (D7): not for headline KPIs
    office_code              NVARCHAR(10)  NULL,
    days_to_close            INT           NULL,                  -- only when flag_valid_duration = 1
    claimed_amount           DECIMAL(18,2) NULL,                  -- descriptive only (D9)
    recovered_amount         DECIMAL(18,2) NULL,                  -- descriptive only (D9)
    flag_valid_duration      BIT           NOT NULL,
    flag_cancelled           BIT           NOT NULL,
    flag_missing_close       BIT           NOT NULL,
    flag_close_before_filing BIT           NOT NULL,
    flag_shared_case_id      BIT           NOT NULL,
    flag_unusual_close_day   BIT           NOT NULL,
    flag_central_office      BIT           NOT NULL
);

CREATE TABLE mart.fact_accesses (
    period_date_key   INT    NOT NULL REFERENCES mart.dim_date (date_key),   -- first day of the month
    state_key         INT    NOT NULL REFERENCES mart.dim_state (state_key),
    operator_key      INT    NOT NULL REFERENCES mart.dim_operator (operator_key),
    accesses          BIGINT NULL,        -- stock at the end of the month (never add months)
    n_source_rows     INT    NOT NULL,    -- rows of clean.bit_access added into this row
    n_missing_rows    INT    NOT NULL,    -- of them, rows with no value in the file
    n_exact_copy_rows INT    NOT NULL,    -- of them, flagged exact copies (D12)
    PRIMARY KEY (period_date_key, state_key, operator_key)
);
GO

-- ---------------------------------------------------------------------
-- 7.1 Fill the dimensions
-- ---------------------------------------------------------------------
-- dim_date: a recursive CTE creates one row per day. MAXRECURSION 0 removes
-- the limit of 100 levels (there are 5,113 days).
WITH d AS (
    SELECT CAST('2013-01-01' AS DATE) AS dt
    UNION ALL
    SELECT DATEADD(day, 1, dt) FROM d WHERE dt < '2026-12-31'
)
INSERT INTO mart.dim_date
SELECT CONVERT(INT, CONVERT(CHAR(8), dt, 112)),            -- 112 = yyyymmdd
       dt,
       YEAR(dt),
       DATEPART(quarter, dt),
       MONTH(dt),
       CHOOSE(MONTH(dt), N'January', N'February', N'March', N'April', N'May', N'June',
                         N'July', N'August', N'September', N'October', N'November', N'December'),
       CONVERT(CHAR(7), dt, 120),                          -- 120 = yyyy-mm-dd, first 7 characters
       CASE WHEN DAY(dt) = 1 THEN 1 ELSE 0 END,
       CASE WHEN MONTH(dt) = 12 THEN 1 ELSE 0 END
FROM d
OPTION (MAXRECURSION 0);

-- dim_state: the states of clean.state_map (01 to 32) plus 99 = no information.
INSERT INTO mart.dim_state
SELECT ROW_NUMBER() OVER (ORDER BY state_code), state_code, state_name
FROM (
    SELECT DISTINCT state_code, state_name FROM clean.state_map
    UNION ALL
    SELECT '99', N'Not specified'
) AS s;

-- dim_operator: the four operators of D11 and Other. bit_group is the BIT group
-- used as denominator (Izzi: GRUPO TELEVISA without EMPRESA = SKY).
INSERT INTO mart.dim_operator (operator_key, operator_name, bit_group, is_main_operator, sort_order)
VALUES (1, N'Telmex',     N'AMÉRICA MÓVIL',  1, 1),
       (2, N'Izzi',       N'GRUPO TELEVISA', 1, 2),
       (3, N'Megacable',  N'MEGACABLE-MCM',  1, 3),
       (4, N'Total Play', N'GRUPO SALINAS',  1, 4),
       (5, N'Other',      NULL,              0, 5);

-- dim_brand: one row per brand found in the complaints.
INSERT INTO mart.dim_brand
SELECT ROW_NUMBER() OVER (ORDER BY brand), brand, network_type, bit_group,
       CASE WHEN network_type = N'Fixed' THEN 1 ELSE 0 END
FROM (
    SELECT brand, MAX(network_type) AS network_type, MAX(operator_group) AS bit_group
    FROM   clean.profeco_complaint
    GROUP BY brand
) AS b;

-- dim_reason: type and reason of the claim. A missing value becomes 'Not specified'.
INSERT INTO mart.dim_reason
SELECT ROW_NUMBER() OVER (ORDER BY claim_type, claim_reason), claim_type, claim_reason
FROM (
    SELECT DISTINCT COALESCE(claim_type, N'Not specified')   AS claim_type,
                    COALESCE(claim_reason, N'Not specified') AS claim_reason
    FROM   clean.profeco_complaint
) AS r;

-- dim_outcome: outcome, type of conciliation and group of procedure.
INSERT INTO mart.dim_outcome
SELECT ROW_NUMBER() OVER (ORDER BY outcome, conciliation_type, procedure_group),
       outcome, conciliation_type, procedure_group
FROM (
    SELECT DISTINCT COALESCE(outcome, N'Not valid or missing')       AS outcome,
                    COALESCE(conciliation_type, N'Not specified')    AS conciliation_type,
                    procedure_group
    FROM   clean.profeco_complaint
) AS o;
GO

-- ---------------------------------------------------------------------
-- 7.2 Fill the facts
-- ---------------------------------------------------------------------
-- fact_complaint: every complaint keeps its key and gets the keys of the dimensions.
-- Joins use the same COALESCE as the dimensions, so no row is lost.
INSERT INTO mart.fact_complaint
SELECT c.complaint_key,
       c.case_id,
       CONVERT(INT, CONVERT(CHAR(8), c.filing_date, 112)),    -- NULL stays NULL
       CONVERT(INT, CONVERT(CHAR(8), c.close_date, 112)),
       st.state_key,
       op.operator_key,
       br.brand_key,
       re.reason_key,
       ou.outcome_key,
       c.channel,
       c.service_hint,
       c.office_code,
       c.days_to_close,
       c.claimed_amount,
       c.recovered_amount,
       c.flag_valid_duration,
       c.flag_cancelled,
       c.flag_missing_close,
       c.flag_close_before_filing,
       c.flag_shared_case_id,
       c.flag_unusual_close_day,
       c.flag_central_office
FROM   clean.profeco_complaint AS c
JOIN   mart.dim_state    AS st ON st.state_code = COALESCE(c.state_code, '99')
JOIN   mart.dim_operator AS op ON op.operator_name =
           CASE WHEN c.brand IN (N'Telmex', N'Izzi', N'Megacable', N'Total Play')
                THEN c.brand ELSE N'Other' END
JOIN   mart.dim_brand    AS br ON br.brand = c.brand
JOIN   mart.dim_reason   AS re ON re.claim_type   = COALESCE(c.claim_type, N'Not specified')
                              AND re.claim_reason = COALESCE(c.claim_reason, N'Not specified')
JOIN   mart.dim_outcome  AS ou ON ou.outcome           = COALESCE(c.outcome, N'Not valid or missing')
                              AND ou.conciliation_type = COALESCE(c.conciliation_type, N'Not specified')
                              AND ou.procedure_group   = c.procedure_group;

-- fact_accesses: the BIT rows of each month, state and operator are added.
-- SUM ignores empty values; n_missing_rows says how many there were.
INSERT INTO mart.fact_accesses
SELECT CONVERT(INT, CONVERT(CHAR(8), a.period_date, 112)),
       st.state_key,
       op.operator_key,
       SUM(a.accesses),
       COUNT(*),
       SUM(CAST(a.flag_missing_accesses AS INT)),
       SUM(CAST(a.flag_exact_copy AS INT))
FROM   clean.bit_access AS a
JOIN   mart.dim_state    AS st ON st.state_code    = a.state_code
JOIN   mart.dim_operator AS op ON op.operator_name = a.operator
GROUP BY CONVERT(INT, CONVERT(CHAR(8), a.period_date, 112)), st.state_key, op.operator_key;
GO

-- ---------------------------------------------------------------------
-- 7.3 Checks
-- ---------------------------------------------------------------------
-- 7.3a: rows of every table. Expected: dim_date 5,113; dim_state 33;
--       dim_operator 5; fact_complaint 36,034. First run (2026-11-05): dim_brand 190,
--       dim_reason 176, dim_outcome 39, fact_accesses 19,840.
SELECT N'dim_date' AS table_name, COUNT(*) AS n_rows FROM mart.dim_date
UNION ALL SELECT N'dim_state',      COUNT(*) FROM mart.dim_state
UNION ALL SELECT N'dim_operator',   COUNT(*) FROM mart.dim_operator
UNION ALL SELECT N'dim_brand',      COUNT(*) FROM mart.dim_brand
UNION ALL SELECT N'dim_reason',     COUNT(*) FROM mart.dim_reason
UNION ALL SELECT N'dim_outcome',    COUNT(*) FROM mart.dim_outcome
UNION ALL SELECT N'fact_complaint', COUNT(*) FROM mart.fact_complaint
UNION ALL SELECT N'fact_accesses',  COUNT(*) FROM mart.fact_accesses;

-- 7.3b: nothing is lost. Expected: complaints 36,034 in both; BIT rows 592,281 in
--       both; accesses of the mart equal to the clean layer (difference 0).
SELECT (SELECT COUNT(*) FROM clean.profeco_complaint)          AS complaints_clean,
       (SELECT COUNT(*) FROM mart.fact_complaint)              AS complaints_mart,
       (SELECT COUNT(*) FROM clean.bit_access)                 AS bit_rows_clean,
       (SELECT SUM(n_source_rows) FROM mart.fact_accesses)     AS bit_rows_mart,
       (SELECT SUM(accesses) FROM clean.bit_access)
         - (SELECT SUM(accesses) FROM mart.fact_accesses)      AS accesses_difference;

-- 7.3c: December 2024 accesses by operator. Expected: Telmex 11,208,977; Izzi 5,619,403;
--       Megacable 5,316,545; Total Play 5,313,779 (the same as check 6.5b).
--       Other: 1,544,536 (first run, 2026-11-05).
SELECT o.operator_name, SUM(f.accesses) AS accesses_dec_2024
FROM   mart.fact_accesses AS f
JOIN   mart.dim_date      AS d ON d.date_key     = f.period_date_key
JOIN   mart.dim_operator  AS o ON o.operator_key = f.operator_key
WHERE  d.year_num = 2024 AND d.month_num = 12
GROUP BY o.operator_name, o.sort_order
ORDER BY o.sort_order;

-- 7.3d: keys. Expected: 0 complaints without filing date key; complaints without
--       close date key = complaints with flag_missing_close; operator names of
--       the facts all exist (0 orphan rows).
SELECT SUM(CASE WHEN filing_date_key IS NULL THEN 1 ELSE 0 END)                AS n_no_filing_key,
       SUM(CASE WHEN close_date_key  IS NULL THEN 1 ELSE 0 END)                AS n_no_close_key,
       SUM(CAST(flag_missing_close AS INT))                                    AS n_flag_missing_close,
       (SELECT COUNT(*) FROM mart.fact_complaint AS f
         WHERE NOT EXISTS (SELECT 1 FROM mart.dim_brand AS b WHERE b.brand_key = f.brand_key)) AS n_orphan_brand
FROM   mart.fact_complaint;

-- 7.3e: complaints by filing year, fixed broadband brands only, by operator.
--       The base file holds cases closed from 2022 on, so old filing years are
--       incomplete: read it before choosing the years of the rates.
SELECT d.year_num, o.operator_name, COUNT(*) AS complaints
FROM   mart.fact_complaint AS f
JOIN   mart.dim_date       AS d ON d.date_key     = f.filing_date_key
JOIN   mart.dim_operator   AS o ON o.operator_key = f.operator_key
JOIN   mart.dim_brand      AS b ON b.brand_key    = f.brand_key
WHERE  b.in_dashboard_scope = 1
GROUP BY d.year_num, o.operator_name, o.sort_order
ORDER BY d.year_num, o.sort_order;

-- 7.3f: rate per 100,000 accesses by operator and year (2022 to 2024): complaints
--       filed in the year (fixed broadband) divided by the accesses of December of
--       that year. National level only: by state the PROFECO office is not the
--       place of the consumer (D8). Operator "Other" has no denominator.
WITH c AS (
    SELECT d.year_num, f.operator_key, COUNT(*) AS complaints
    FROM   mart.fact_complaint AS f
    JOIN   mart.dim_date       AS d ON d.date_key  = f.filing_date_key
    JOIN   mart.dim_brand      AS b ON b.brand_key = f.brand_key
    WHERE  b.in_dashboard_scope = 1
    GROUP BY d.year_num, f.operator_key
), a AS (
    SELECT d.year_num, f.operator_key, SUM(f.accesses) AS accesses_december
    FROM   mart.fact_accesses AS f
    JOIN   mart.dim_date      AS d ON d.date_key = f.period_date_key
    WHERE  d.month_num = 12
    GROUP BY d.year_num, f.operator_key
)
SELECT c.year_num, o.operator_name, c.complaints, a.accesses_december,
       CAST(100000.0 * c.complaints / a.accesses_december AS DECIMAL(9,2)) AS complaints_per_100k
FROM   c
JOIN   a ON a.year_num = c.year_num AND a.operator_key = c.operator_key
JOIN   mart.dim_operator AS o ON o.operator_key = c.operator_key
WHERE  o.is_main_operator = 1 AND c.year_num BETWEEN 2022 AND 2024
ORDER BY c.year_num, o.sort_order;

-- 7.3g: service hint of the complaints by operator (fixed brands, filed 2022 to 2024).
--       It tells if the numerator of the rates holds complaints about services other
--       than internet. The hint comes from problema_especial and covers only part of
--       the rows (D7), so it is a warning light, not a filter.
--       First run (2026-11-05): "Not specified" is 98.8% of Telmex, 89.4% of Izzi,
--       75.3% of Megacable and 78.9% of Total Play. Mobile telephony: 14 of 9,588.
SELECT o.operator_name, f.service_hint, COUNT(*) AS complaints
FROM   mart.fact_complaint AS f
JOIN   mart.dim_operator   AS o ON o.operator_key = f.operator_key
JOIN   mart.dim_brand      AS b ON b.brand_key    = f.brand_key
JOIN   mart.dim_date       AS d ON d.date_key     = f.filing_date_key
WHERE  b.in_dashboard_scope = 1 AND d.year_num BETWEEN 2022 AND 2024
GROUP BY o.operator_name, o.sort_order, f.service_hint
ORDER BY o.sort_order, complaints DESC;
-- =====================================================================