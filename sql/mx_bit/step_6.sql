-- =====================================================================
-- step_6.sql  |  Clean layer of the BIT accesses: clean.bit_access
-- =====================================================================
-- Objective   : turn stg.bit_acc_baf (all text) into clean.bit_access with
--               correct types, a date, a state code that joins with the
--               PROFECO complaints, and the operator of each row (Telmex,
--               Izzi, Megacable, Total Play, Other). No row is deleted.
-- Source      : stg.bit_acc_baf (step_5.sql) and clean.state_map (step_3.sql).
-- Prerequisites: steps 0, 3 and 5 executed.
-- How to run  : run it block by block (select the block, press F5).
--               Save a capture of each check as docs/img/step_6_check_NN.png.
--
-- Rules of this layer (decisions D10, D11 and the join rules of
-- docs/sources/MX_profeco.md):
--   * A_TOTAL_E is a STOCK of accesses at the end of the month. It is never
--     added across months: the rates use one month (December of each year).
--   * Empty accesses stay NULL (they are NOT turned into 0) and are flagged.
--   * Operator of each row:
--       AMERICA MOVIL              -> Telmex       (Telmex + Telnor)
--       GRUPO TELEVISA, not SKY    -> Izzi         (the group also has SKY)
--       MEGACABLE-MCM              -> Megacable
--       GRUPO SALINAS              -> Total Play   (TOTALPLAY is its only company)
--       anything else (and SKY)    -> Other
--   * Grain (D12): the file is NOT unique per month, municipality, technology and
--     company (checks 6.2). Every row is a separate record and all are added.
--     The 325 surplus copies of identical rows are flagged (flag_exact_copy),
--     not removed.
--   * The technology (TECNO_ACCESO_INTERNET) is kept in every row. There is no
--     technology filter in the denominators (D13): the four operators have only
--     fixed technologies or "unspecified", and Sky is already outside Izzi.
-- =====================================================================

USE complaint_sla;
GO

-- ---------------------------------------------------------------------
-- 6.1 Which access technologies are in the file? (read-only)
-- ---------------------------------------------------------------------
-- 6.1a: code, name and number of rows of every technology (all operators).
SELECT k_acceso_internet, tecno_acceso_internet, COUNT(*) AS n_rows
FROM   stg.bit_acc_baf
GROUP BY k_acceso_internet, tecno_acceso_internet
ORDER BY n_rows DESC;

-- 6.1b: December 2024 accesses of the four groups, by technology.
-- Look at: does a technology that is not a fixed line (for example "Tecnologia
-- movil") have a large share of the accesses? The total of the column must be
-- 27,809,589, the figure that matches the Excel evidence.
SELECT grupo, k_acceso_internet, tecno_acceso_internet,
       SUM(TRY_CONVERT(decimal(18,2), a_total_e)) AS accesses_dec_2024
FROM   stg.bit_acc_baf
WHERE  TRY_CONVERT(int, anio) = 2024
  AND  TRY_CONVERT(int, mes)  = 12
  AND  grupo IN (N'AMÉRICA MÓVIL', N'GRUPO TELEVISA', N'MEGACABLE-MCM', N'GRUPO SALINAS')
GROUP BY grupo, k_acceso_internet, tecno_acceso_internet
ORDER BY grupo, accesses_dec_2024 DESC;

-- ---------------------------------------------------------------------
-- 6.2 Grain: is there one row per month, municipality, technology and company?
-- ---------------------------------------------------------------------
-- 6.2a: how many combinations of (year, month, state, municipality,
--       technology, company) appear more than once? Expected: 0. If it is not
--       0, the row is not the grain and the duplicates must be understood
--       before the accesses are added.
--       First run (2026-11-01): 36,562 repeated keys, so checks 6.2c to 6.2f
--       below find out if they are exact copies or different reports.
SELECT COUNT(*) AS n_repeated_keys
FROM (
    SELECT anio, mes, k_entidad, k_municipio, k_acceso_internet, k_empresa
    FROM   stg.bit_acc_baf
    GROUP BY anio, mes, k_entidad, k_municipio, k_acceso_internet, k_empresa
    HAVING COUNT(*) > 1
) AS d;

-- 6.2b: accesses with decimals. They are whole numbers, so the expected
--       result is 0 (the clean column is a whole number: BIGINT).
SELECT COUNT(*) AS n_with_decimals
FROM   stg.bit_acc_baf
WHERE  TRY_CONVERT(decimal(18,2), a_total_e) IS NOT NULL
  AND  TRY_CONVERT(decimal(18,2), a_total_e) <> FLOOR(TRY_CONVERT(decimal(18,2), a_total_e));

-- Results of the first run (2026-11-01) and what they mean:
--   6.2a: 36,562 repeated keys, so the row is NOT one per month, municipality,
--         technology and company. Checks 6.2c to 6.2h explain why.
--   6.2c: adding the FOLIO leaves 35,887 repeated keys: the folio does not tell
--         the repeated rows apart.
--   6.2d: only 325 groups of rows are identical in all 16 columns (325 surplus
--         rows, 0.05% of 592,281).
--   6.2e/6.2f: in December 2024 the repeated rows belong to the same
--         concessionaire and technology but carry very different accesses
--         (for example 1,105 and 69,186). They look like separate records of a
--         dimension that is not in the file (hypothesis: segment or speed range).
--   Decision (D12): all rows are kept and added. The 325 surplus copies are
--         flagged (flag_exact_copy) and measured in 6.2h, not removed.

-- 6.2c: add the FOLIO (registration of the provider) to the key. If the number
--       fell to 0 the folio would tell the repeated rows apart.
--       Result: 35,887.
SELECT COUNT(*) AS n_repeated_keys_with_folio
FROM (
    SELECT anio, mes, k_entidad, k_municipio, k_acceso_internet, k_empresa, folio
    FROM   stg.bit_acc_baf
    GROUP BY anio, mes, k_entidad, k_municipio, k_acceso_internet, k_empresa, folio
    HAVING COUNT(*) > 1
) AS d;

-- 6.2d: EXACT copies: rows identical in ALL 16 columns, accesses included.
--       These are the ones that could be the same record twice.
--       Result: 325 groups, 325 surplus rows.
SELECT COUNT(*)               AS n_exact_copy_groups,
       SUM(n_rows) - COUNT(*) AS n_extra_rows
FROM (
    SELECT COUNT(*) AS n_rows
    FROM   stg.bit_acc_baf
    GROUP BY folio, k_entidad, k_municipio, k_acceso_internet, tecno_acceso_internet,
             fecha, anio, mes, k_empresa, empresa, concesionario, a_total_e,
             k_grupo, grupo, entidad, municipio
    HAVING COUNT(*) > 1
) AS d;

-- 6.2e: repeated keys only in December 2024 and the four groups (the month and
--       groups of the denominators): keys and rows involved.
--       Result: 3,303 keys, 6,632 rows.
SELECT COUNT(*)      AS n_repeated_keys_dec_2024,
       SUM(n_rows)   AS n_rows_involved
FROM (
    SELECT COUNT(*) AS n_rows
    FROM   stg.bit_acc_baf
    WHERE  TRY_CONVERT(int, anio) = 2024 AND TRY_CONVERT(int, mes) = 12
      AND  grupo IN (N'AMÉRICA MÓVIL', N'GRUPO TELEVISA', N'MEGACABLE-MCM', N'GRUPO SALINAS')
    GROUP BY k_entidad, k_municipio, k_acceso_internet, k_empresa
    HAVING COUNT(*) > 1
) AS d;

-- 6.2f: five repeated keys of December 2024, row by row: what differs between
--       the rows (folio, concessionaire, accesses)?
-- Technique: CTE rep (the five most repeated keys) joined to the rows, so the five keys
--            are chosen once and then looked at row by row.
WITH rep AS (
    SELECT TOP 5 k_entidad, k_municipio, k_acceso_internet, k_empresa
    FROM   stg.bit_acc_baf
    WHERE  TRY_CONVERT(int, anio) = 2024 AND TRY_CONVERT(int, mes) = 12
      AND  grupo IN (N'AMÉRICA MÓVIL', N'GRUPO TELEVISA', N'MEGACABLE-MCM', N'GRUPO SALINAS')
    GROUP BY k_entidad, k_municipio, k_acceso_internet, k_empresa
    HAVING COUNT(*) > 1
    ORDER BY COUNT(*) DESC
)
SELECT s.k_entidad, s.k_municipio, s.tecno_acceso_internet, s.empresa,
       s.folio, s.concesionario, s.a_total_e
FROM   stg.bit_acc_baf AS s
JOIN   rep AS r
       ON  r.k_entidad = s.k_entidad AND r.k_municipio = s.k_municipio
       AND r.k_acceso_internet = s.k_acceso_internet AND r.k_empresa = s.k_empresa
WHERE  TRY_CONVERT(int, s.anio) = 2024 AND TRY_CONVERT(int, s.mes) = 12
ORDER BY s.k_entidad, s.k_municipio, s.k_acceso_internet, s.k_empresa, s.folio;

-- 6.2g: the same count as 6.2e for November 2024. If the repeated keys are about
--       the same number, the repetition is a stable feature of the file (a
--       segment of every month), not a one-time loading error of December.
SELECT COUNT(*)      AS n_repeated_keys_nov_2024,
       SUM(n_rows)   AS n_rows_involved
FROM (
    SELECT COUNT(*) AS n_rows
    FROM   stg.bit_acc_baf
    WHERE  TRY_CONVERT(int, anio) = 2024 AND TRY_CONVERT(int, mes) = 11
      AND  grupo IN (N'AMÉRICA MÓVIL', N'GRUPO TELEVISA', N'MEGACABLE-MCM', N'GRUPO SALINAS')
    GROUP BY k_entidad, k_municipio, k_acceso_internet, k_empresa
    HAVING COUNT(*) > 1
) AS d;

-- 6.2h: how much do the 325 surplus copies weigh in December 2024? If the share
--       is far below 0.1%, keeping or removing them does not change any rate.
--       rn > 1 marks the surplus copy of each group of identical rows.
-- Technique: window function ROW_NUMBER inside a CTE; rn > 1 marks the surplus copy
--            without deleting any row. A GROUP BY would only count, not mark.
WITH x AS (
    SELECT grupo,
           TRY_CONVERT(decimal(18,2), a_total_e) AS acc,
           ROW_NUMBER() OVER (PARTITION BY folio, k_entidad, k_municipio, k_acceso_internet,
                                           tecno_acceso_internet, fecha, anio, mes, k_empresa,
                                           empresa, concesionario, a_total_e, k_grupo, grupo,
                                           entidad, municipio
                              ORDER BY (SELECT NULL)) AS rn
    FROM   stg.bit_acc_baf
    WHERE  TRY_CONVERT(int, anio) = 2024 AND TRY_CONVERT(int, mes) = 12
      AND  grupo IN (N'AMÉRICA MÓVIL', N'GRUPO TELEVISA', N'MEGACABLE-MCM', N'GRUPO SALINAS')
)
SELECT grupo,
       SUM(acc)                                         AS accesses_dec_2024,
       SUM(CASE WHEN rn > 1 THEN acc ELSE 0 END)        AS accesses_in_surplus_copies,
       CAST(100.0 * SUM(CASE WHEN rn > 1 THEN acc ELSE 0 END) / SUM(acc) AS decimal(9,4)) AS pct_surplus
FROM   x
GROUP BY grupo
ORDER BY grupo;

-- ---------------------------------------------------------------------
-- 6.3 Months per year in the four groups
-- ---------------------------------------------------------------------
-- Expected: 12 months in every year from 2013 to 2024. A year with fewer
-- months would mean that December is not always the right month to use.
SELECT TRY_CONVERT(int, anio) AS year,
       COUNT(DISTINCT TRY_CONVERT(int, mes)) AS n_months
FROM   stg.bit_acc_baf
WHERE  grupo IN (N'AMÉRICA MÓVIL', N'GRUPO TELEVISA', N'MEGACABLE-MCM', N'GRUPO SALINAS')
GROUP BY TRY_CONVERT(int, anio)
ORDER BY year;
GO

-- ---------------------------------------------------------------------
-- 6.4 Build clean.bit_access
-- ---------------------------------------------------------------------
-- CTE c: trims the text, turns empty text into NULL and converts the types.
--   NULLIF(x, '')      turns empty text into NULL
--   TRY_CONVERT(...)   returns NULL instead of an error if it cannot convert
--   DATEFROMPARTS      builds a date (first day of the month) from year and month
DROP TABLE IF EXISTS clean.bit_access;

CREATE TABLE clean.bit_access (
    access_key            INT           NOT NULL PRIMARY KEY,  -- row number (surrogate key)
    folio                 NVARCHAR(50)  NULL,
    period_date           DATE          NULL,                  -- first day of the month
    year_num              SMALLINT      NULL,
    month_num             TINYINT       NULL,
    state_code            CHAR(2)       NULL,                  -- INEGI code, 99 = no information
    state_name            NVARCHAR(60)  NULL,                  -- from clean.state_map
    municipality_code     NVARCHAR(10)  NULL,                  -- 999 = no information
    municipality_name     NVARCHAR(200) NULL,
    technology_code       NVARCHAR(10)  NULL,
    technology_name       NVARCHAR(100) NULL,
    company_code          NVARCHAR(20)  NULL,
    company_name          NVARCHAR(200) NULL,
    concession_holder     NVARCHAR(300) NULL,
    group_code            NVARCHAR(20)  NULL,
    bit_group             NVARCHAR(200) NULL,                  -- GRUPO of the BIT
    operator              NVARCHAR(30)  NOT NULL,              -- Telmex, Izzi, Megacable, Total Play, Other
    accesses              BIGINT        NULL,                  -- stock at the end of the month
    flag_missing_accesses BIT           NOT NULL,              -- 1 = the file has no value
    flag_no_state         BIT           NOT NULL,              -- 1 = state code 99
    flag_no_municipality  BIT           NOT NULL,              -- 1 = municipality code 999
    flag_exact_copy       BIT           NOT NULL               -- 1 = surplus copy of a row identical in all 16 columns (kept, see 6.2)
);
GO

-- Technique: CTE c (types, text and flags) so that the INSERT SELECT only numbers the
--            rows; ROW_NUMBER with a full ORDER BY creates a stable surrogate key.
WITH c AS (
    SELECT NULLIF(LTRIM(RTRIM(folio)), '')                   AS folio,
           TRY_CONVERT(smallint, NULLIF(LTRIM(RTRIM(anio)), ''))  AS year_num,
           TRY_CONVERT(tinyint,  NULLIF(LTRIM(RTRIM(mes)),  ''))  AS month_num,
           NULLIF(LTRIM(RTRIM(k_entidad)), '')               AS state_code,
           NULLIF(LTRIM(RTRIM(k_municipio)), '')             AS municipality_code,
           NULLIF(LTRIM(RTRIM(municipio)), '')               AS municipality_name,
           NULLIF(LTRIM(RTRIM(k_acceso_internet)), '')       AS technology_code,
           NULLIF(LTRIM(RTRIM(tecno_acceso_internet)), '')   AS technology_name,
           NULLIF(LTRIM(RTRIM(k_empresa)), '')               AS company_code,
           NULLIF(LTRIM(RTRIM(empresa)), '')                 AS company_name,
           NULLIF(LTRIM(RTRIM(concesionario)), '')           AS concession_holder,
           NULLIF(LTRIM(RTRIM(k_grupo)), '')                 AS group_code,
           NULLIF(LTRIM(RTRIM(grupo)), '')                   AS bit_group,
           -- accesses: decimal first (so '25.0' also works), then whole number
           CAST(TRY_CONVERT(decimal(18,2), NULLIF(LTRIM(RTRIM(a_total_e)), '')) AS BIGINT) AS accesses,
           -- copy_number > 1 = surplus copy of a row identical in all 16 columns
           -- (same columns as check 6.2d). The copies are identical, so which one
           -- is flagged does not matter.
           ROW_NUMBER() OVER (PARTITION BY folio, k_entidad, k_municipio, k_acceso_internet,
                                           tecno_acceso_internet, fecha, anio, mes, k_empresa,
                                           empresa, concesionario, a_total_e, k_grupo, grupo,
                                           entidad, municipio
                              ORDER BY (SELECT NULL))            AS copy_number
    FROM   stg.bit_acc_baf
)
INSERT INTO clean.bit_access
SELECT ROW_NUMBER() OVER (ORDER BY c.year_num, c.month_num, c.state_code,
                                   c.municipality_code, c.technology_code,
                                   c.company_code, c.folio)          AS access_key,
       c.folio,
       DATEFROMPARTS(c.year_num, c.month_num, 1)                     AS period_date,
       c.year_num,
       c.month_num,
       CAST(c.state_code AS CHAR(2))                                 AS state_code,
       COALESCE(s.state_name, N'Not specified')                      AS state_name,
       c.municipality_code,
       c.municipality_name,
       c.technology_code,
       c.technology_name,
       c.company_code,
       c.company_name,
       c.concession_holder,
       c.group_code,
       c.bit_group,
       -- Operator of the row (see the rules in the header)
       CASE WHEN c.bit_group = N'AMÉRICA MÓVIL'                                    THEN N'Telmex'
            WHEN c.bit_group = N'GRUPO TELEVISA' AND COALESCE(c.company_name, '') <> N'SKY' THEN N'Izzi'
            WHEN c.bit_group = N'MEGACABLE-MCM'                                    THEN N'Megacable'
            WHEN c.bit_group = N'GRUPO SALINAS'                                    THEN N'Total Play'
            ELSE N'Other' END                                        AS operator,
       c.accesses,
       CASE WHEN c.accesses IS NULL           THEN 1 ELSE 0 END     AS flag_missing_accesses,
       CASE WHEN c.state_code = '99'          THEN 1 ELSE 0 END     AS flag_no_state,
       CASE WHEN c.municipality_code = '999'  THEN 1 ELSE 0 END     AS flag_no_municipality,
       CASE WHEN c.copy_number > 1            THEN 1 ELSE 0 END     AS flag_exact_copy
FROM   c
LEFT JOIN (SELECT DISTINCT state_code, state_name FROM clean.state_map) AS s
       ON s.state_code = c.state_code;
GO

-- ---------------------------------------------------------------------
-- 6.5 Checks of the clean layer
-- ---------------------------------------------------------------------
-- 6.5a: rows and flags. Expected: 592,281 rows; 1,831 with missing accesses;
--       flag_no_state and flag_no_municipality are the satellite and similar
--       providers that do not report a place. n_exact_copy: expected 325.
SELECT COUNT(*)                                   AS n_rows,
       SUM(CAST(flag_missing_accesses AS int))    AS n_missing_accesses,
       SUM(CAST(flag_no_state AS int))            AS n_no_state,
       SUM(CAST(flag_no_municipality AS int))     AS n_no_municipality,
       SUM(CAST(flag_exact_copy AS int))          AS n_exact_copy,
       SUM(CASE WHEN period_date IS NULL THEN 1 ELSE 0 END) AS n_no_date
FROM   clean.bit_access;

-- 6.5b: December 2024 by group and operator. Expected: Telmex 11,208,977;
--       Megacable 5,316,545; Total Play 5,313,779; and GRUPO TELEVISA split
--       into Izzi + Other (Sky) = 5,970,288. The four groups add 27,809,589.
SELECT bit_group, operator, SUM(accesses) AS accesses_dec_2024
FROM   clean.bit_access
WHERE  year_num = 2024 AND month_num = 12
  AND  bit_group IN (N'AMÉRICA MÓVIL', N'GRUPO TELEVISA', N'MEGACABLE-MCM', N'GRUPO SALINAS')
GROUP BY bit_group, operator
ORDER BY bit_group, operator;

-- 6.5c: states. Expected: 33 codes; every code except 99 has a state name from
--       clean.state_map, and only code 99 shows "Not specified".
SELECT state_code, state_name, COUNT(*) AS n_rows
FROM   clean.bit_access
GROUP BY state_code, state_name
ORDER BY state_code;

-- ---------------------------------------------------------------------
-- 6.6 Preview of the denominators: December of each year, by operator
-- ---------------------------------------------------------------------
-- Accesses at the end of December, the base of the rates per 100,000
-- accesses (years 2022 to 2024). Technologies are not filtered yet: see 6.1.
SELECT year_num, operator, SUM(accesses) AS accesses_december
FROM   clean.bit_access
WHERE  month_num = 12
  AND  year_num BETWEEN 2022 AND 2024
  AND  operator <> N'Other'
GROUP BY year_num, operator
ORDER BY year_num, operator;

-- 6.6b: technologies of the four operators in December of 2022 to 2024.
--       Expected (from check 6.1b): no "Tecnologia movil" in the four operators,
--       because in December 2024 it belongs to Sky, which is outside Izzi.
--       If a mobile technology appears, the denominator needs a filter.
SELECT year_num, operator, technology_code, technology_name, SUM(accesses) AS accesses_december
FROM   clean.bit_access
WHERE  month_num = 12
  AND  year_num BETWEEN 2022 AND 2024
  AND  operator <> N'Other'
GROUP BY year_num, operator, technology_code, technology_name
ORDER BY year_num, operator, accesses_december DESC;
-- =====================================================================