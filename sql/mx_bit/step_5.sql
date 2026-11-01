-- =====================================================================
-- step_5.sql  |  Load the BIT fixed broadband accesses into staging
-- =====================================================================
-- Objective   : copy the BIT file TD_ACC_BAF_ITE_VA.csv into
--               stg.bit_acc_baf as TEXT, without cleaning anything
--               (same idea as step_1.sql for PROFECO).
-- Source      : CRT, Banco de Informacion de Telecomunicaciones (BIT),
--               table TD_ACC_BAF_ITE_VA (fixed broadband accesses by
--               operator group and state). Downloaded on 2026-10-26.
--               License and citation: docs/sources/licenses.md.
-- Prerequisites: step_0.sql executed (database and schemas).
--               The SQL Server service account must read data\raw\.
-- How to run  : run it block by block (select the block, press F5).
--               Save a capture of each check as docs/img/step_5_check_NN.png.
--
-- What is different from the PROFECO file (see docs/sources/MX_profeco.md):
--   * The file is NOT UTF-8 (accents such as "AMERICA MOVIL" break with 65001).
--     Here CODEPAGE = '1252' (Western European) is used.
--   * FECHA looks like 15Jan2021. It stays as text: the clean layer will use
--     the columns ANIO (year) and MES (month) instead.
--   * A_TOTAL_E is a STOCK of accesses at the end of each month. It must never
--     be added across months (see MX_profeco.md, "Do not add months").
-- =====================================================================

USE complaint_sla;
GO

-- ---------------------------------------------------------------------
-- 5.0 Probe: how do the first lines of the file look?
-- ---------------------------------------------------------------------
-- Before creating the real table we read the first 4 lines into a table with
-- ONE text column. FIELDTERMINATOR = '0x0b' (a character that does not appear
-- in the file) stops BULK INSERT from splitting the line into columns.
-- Look at the result:
--   * Which character separates the columns: comma, semicolon or tab?
--   * Do the values have double quotes?
--   * last_char = 13 means the lines end with CR+LF (ROWTERMINATOR '0x0d0a');
--     last_char = 44 or a letter/number means they end with LF only.
--     Result of the real probe: last_char = 13 (CR+LF), comma separator, text
--     with commas in double quotes, correct accents with CODEPAGE 1252, and
--     two extra empty commas at the end of every line.
--   * Do the accents look right (AMÉRICA MÓVIL)? If they look broken, change
--     CODEPAGE ('1252' or '850') and run the probe again.
DROP TABLE IF EXISTS stg.bit_probe;
CREATE TABLE stg.bit_probe (line NVARCHAR(MAX));

BULK INSERT stg.bit_probe
FROM 'D:\Capstone SLA\github\complaint-resolution-sla-analytics\data\raw\TD_ACC_BAF_ITE_VA.csv'
WITH (
    FIRSTROW = 1,
    LASTROW  = 4,
    CODEPAGE = '1252',
    FIELDTERMINATOR = '0x0b',
    ROWTERMINATOR   = '0x0a'
);

SELECT line,
       LEN(line)                    AS line_length,
       UNICODE(RIGHT(line, 1))      AS last_char   -- 13 = carriage return (CR+LF file)
FROM   stg.bit_probe;
GO

DROP TABLE stg.bit_probe;   -- the probe is not needed any more
GO

-- ---------------------------------------------------------------------
-- 5.1 Staging table: 16 text columns in the order of the CSV header, plus 2 extra
-- ---------------------------------------------------------------------
-- BULK INSERT matches columns by POSITION, not by name. Everything is text on
-- purpose, as in stg.profeco_raw.
-- The probe (5.0) showed that every line ends with two extra commas
-- (MUNICIPIO,,). BULK INSERT counts them as 2 more (empty) columns, so the
-- table needs 18 columns or the load fails.
DROP TABLE IF EXISTS stg.bit_acc_baf;

CREATE TABLE stg.bit_acc_baf (
    folio                NVARCHAR(50),
    k_entidad            NVARCHAR(10),    -- INEGI state code (01-32, 99 = no information)
    k_municipio          NVARCHAR(10),
    k_acceso_internet    NVARCHAR(10),
    tecno_acceso_internet NVARCHAR(100),  -- access technology
    fecha                NVARCHAR(20),    -- like 15Jan2021 (not used, see header)
    anio                 NVARCHAR(10),    -- year
    mes                  NVARCHAR(10),    -- month
    k_empresa            NVARCHAR(20),
    empresa              NVARCHAR(200),   -- company (TOTALPLAY, IZZI, ...)
    concesionario        NVARCHAR(300),
    a_total_e            NVARCHAR(30),    -- accesses at the end of the month (stock)
    k_grupo              NVARCHAR(20),
    grupo                NVARCHAR(200),   -- operator group (AMERICA MOVIL, ...)
    entidad              NVARCHAR(100),   -- state name
    municipio            NVARCHAR(200),
    extra_1              NVARCHAR(10),    -- the file has two empty columns at the end of
    extra_2              NVARCHAR(10)     -- every line (",,"); they are removed after the load
);
GO

-- ---------------------------------------------------------------------
-- 5.1b Load the file
-- ---------------------------------------------------------------------
-- Options chosen with what the probe showed (capture step_5_check_00.png):
--   * commas as separators, text with commas between double quotes (FORMAT = 'CSV')
--   * lines end with CR+LF (last_char = 13): ROWTERMINATOR = '0x0d0a'
--   * accents correct with CODEPAGE = '1252'
BULK INSERT stg.bit_acc_baf
FROM 'D:\Capstone SLA\github\complaint-resolution-sla-analytics\data\raw\TD_ACC_BAF_ITE_VA.csv'
WITH (
    FORMAT     = 'CSV',
    FIELDQUOTE = '"',
    FIRSTROW   = 2,         -- row 1 is the header
    CODEPAGE   = '1252',
    ROWTERMINATOR = '0x0d0a'
);
GO

-- ---------------------------------------------------------------------
-- 5.1c The two extra columns must be empty, then they are removed
-- ---------------------------------------------------------------------
-- Expected: n_not_empty = 0. If it is not 0, those columns hold data and the
-- file layout is different from what the probe showed: do not drop them.
SELECT COUNT(*) AS n_not_empty
FROM   stg.bit_acc_baf
WHERE  ISNULL(extra_1, '') <> '' OR ISNULL(extra_2, '') <> '';
GO

ALTER TABLE stg.bit_acc_baf DROP COLUMN extra_1, extra_2;
GO

-- ---------------------------------------------------------------------
-- 5.2 Row count
-- ---------------------------------------------------------------------
-- Expected: 592,281 rows (same as Excel, header excluded).
SELECT COUNT(*) AS n_rows
FROM   stg.bit_acc_baf;

-- First rows: each value must be in the right column (for example, grupo
-- must hold a group name, not a number).
SELECT TOP 5 *
FROM   stg.bit_acc_baf;

-- ---------------------------------------------------------------------
-- 5.3 Encoding: do the accents look right?
-- ---------------------------------------------------------------------
-- Expected: the list shows AMÉRICA MÓVIL with its accents and n_broken = 0.
-- If n_broken is not 0, the CODEPAGE is wrong: truncate and load again.
-- COLLATE Latin1_General_BIN2 is needed in the LIKE: with the default collation
-- (Modern_Spanish_CI_AI) "Ã" is treated as an "A", so every group would count
-- as broken. The binary collation compares the exact characters.
SELECT grupo, COUNT(*) AS n_rows,
       SUM(CASE WHEN grupo COLLATE Latin1_General_BIN2 LIKE N'%Ã%'
                  OR grupo COLLATE Latin1_General_BIN2 LIKE N'%Â%'
                  OR grupo COLLATE Latin1_General_BIN2 LIKE N'%�%'
                THEN 1 ELSE 0 END) AS n_broken
FROM   stg.bit_acc_baf
WHERE  grupo LIKE N'AM%RICA%' OR grupo LIKE N'%TELEVISA%' OR grupo LIKE N'%SALINAS%'
   OR  grupo LIKE N'MEGACABLE%'
GROUP BY grupo;

-- ---------------------------------------------------------------------
-- 5.4 Year, month and numeric columns
-- ---------------------------------------------------------------------
-- Expected: years 2013 to 2024, months 1 to 12, and n_not_number = 0 in the
-- columns that must be numbers. A value that does not convert is shown here
-- instead of failing the load (TRY_CONVERT returns NULL).
SELECT MIN(TRY_CONVERT(int, anio)) AS min_year,
       MAX(TRY_CONVERT(int, anio)) AS max_year,
       MIN(TRY_CONVERT(int, mes))  AS min_month,
       MAX(TRY_CONVERT(int, mes))  AS max_month,
       SUM(CASE WHEN TRY_CONVERT(int, anio) IS NULL THEN 1 ELSE 0 END)           AS n_bad_year,
       SUM(CASE WHEN TRY_CONVERT(int, mes)  IS NULL THEN 1 ELSE 0 END)           AS n_bad_month,
       SUM(CASE WHEN TRY_CONVERT(decimal(18,2), a_total_e) IS NULL THEN 1 ELSE 0 END) AS n_bad_accesses,
       SUM(CASE WHEN TRY_CONVERT(int, k_entidad) IS NULL THEN 1 ELSE 0 END)      AS n_bad_state
FROM   stg.bit_acc_baf;

-- ---------------------------------------------------------------------
-- 5.5 Reconciliation with the Excel evidence (December 2024)
-- ---------------------------------------------------------------------
-- The accesses of December 2024 (the last month) by group must match the
-- pivot tables of docs/sources/MX_profeco.md:
--   MEGACABLE-MCM 5,316,545 | GRUPO SALINAS 5,313,779 | the four groups 27,809,589
-- AMERICA MOVIL and GRUPO TELEVISA add the rest (about 11.2 M and 6.0 M).
SELECT grupo,
       SUM(TRY_CONVERT(decimal(18,2), a_total_e)) AS accesses_dec_2024
FROM   stg.bit_acc_baf
WHERE  TRY_CONVERT(int, anio) = 2024
  AND  TRY_CONVERT(int, mes)  = 12
  AND  grupo IN (N'AMÉRICA MÓVIL', N'GRUPO TELEVISA', N'MEGACABLE-MCM', N'GRUPO SALINAS')
GROUP BY grupo
ORDER BY grupo;

-- The same, with the total of the four groups
SELECT SUM(TRY_CONVERT(decimal(18,2), a_total_e)) AS four_groups_dec_2024
FROM   stg.bit_acc_baf
WHERE  TRY_CONVERT(int, anio) = 2024
  AND  TRY_CONVERT(int, mes)  = 12
  AND  grupo IN (N'AMÉRICA MÓVIL', N'GRUPO TELEVISA', N'MEGACABLE-MCM', N'GRUPO SALINAS');

-- ---------------------------------------------------------------------
-- 5.6 States: codes and the rows without state
-- ---------------------------------------------------------------------
-- Expected: 33 distinct codes (01 to 32 and 99). The rows with code 99
-- ("Sin informacion de Entidad") are about 0.13% of the accesses of the four
-- groups in December 2024 (35,990). All the operators together have more
-- (1,051,366), because small providers do not report a state.
SELECT COUNT(DISTINCT k_entidad) AS n_state_codes
FROM   stg.bit_acc_baf;

SELECT k_entidad, entidad,
       SUM(TRY_CONVERT(decimal(18,2), a_total_e)) AS accesses_dec_2024
FROM   stg.bit_acc_baf
WHERE  TRY_CONVERT(int, anio) = 2024
  AND  TRY_CONVERT(int, mes)  = 12
  AND  TRY_CONVERT(int, k_entidad) = 99
GROUP BY k_entidad, entidad;

-- Same, only for the four groups (the figure of the project). Expected 35,990.
SELECT k_entidad, entidad,
       SUM(TRY_CONVERT(decimal(18,2), a_total_e)) AS accesses_dec_2024_four_groups
FROM   stg.bit_acc_baf
WHERE  TRY_CONVERT(int, anio) = 2024
  AND  TRY_CONVERT(int, mes)  = 12
  AND  TRY_CONVERT(int, k_entidad) = 99
  AND  grupo IN (N'AMÉRICA MÓVIL', N'GRUPO TELEVISA', N'MEGACABLE-MCM', N'GRUPO SALINAS')
GROUP BY k_entidad, entidad;

-- ---------------------------------------------------------------------
-- 5.7 Companies inside each of the four groups
-- ---------------------------------------------------------------------
-- Must reproduce the pivot of docs/sources/MX_profeco.md:
--   AMERICA MOVIL = TELMEX + TELNOR;  GRUPO SALINAS = TOTALPLAY only;
--   MEGACABLE-MCM = MEGACABLE, MCM TELECOM, TELEVIA, ...;
--   GRUPO TELEVISA = IZZI, SKY and the historical cable companies.
SELECT grupo, empresa, COUNT(*) AS n_rows
FROM   stg.bit_acc_baf
WHERE  grupo IN (N'AMÉRICA MÓVIL', N'GRUPO TELEVISA', N'MEGACABLE-MCM', N'GRUPO SALINAS')
GROUP BY grupo, empresa
ORDER BY grupo, empresa;

-- ---------------------------------------------------------------------
-- 5.8 Accesses that are not numbers (found in check 5.4: 1,831 rows)
-- ---------------------------------------------------------------------
-- 5.8a: what do these values look like? NULL means the field was empty in the
--       file (TRY_CONVERT of NULL is NULL). Other texts need a decision.
SELECT TOP 10 a_total_e, COUNT(*) AS n_rows
FROM   stg.bit_acc_baf
WHERE  TRY_CONVERT(decimal(18,2), a_total_e) IS NULL
GROUP BY a_total_e
ORDER BY n_rows DESC;

-- 5.8b: in which years and groups are they? A row with no number adds nothing
--       to the sums, so what matters is if they belong to the four groups.
SELECT TRY_CONVERT(int, anio) AS year,
       SUM(CASE WHEN grupo IN (N'AMÉRICA MÓVIL', N'GRUPO TELEVISA', N'MEGACABLE-MCM', N'GRUPO SALINAS')
                THEN 1 ELSE 0 END) AS n_four_groups,
       SUM(CASE WHEN grupo IN (N'AMÉRICA MÓVIL', N'GRUPO TELEVISA', N'MEGACABLE-MCM', N'GRUPO SALINAS')
                THEN 0 ELSE 1 END) AS n_other_operators
FROM   stg.bit_acc_baf
WHERE  TRY_CONVERT(decimal(18,2), a_total_e) IS NULL
GROUP BY TRY_CONVERT(int, anio)
ORDER BY year;
-- =====================================================================