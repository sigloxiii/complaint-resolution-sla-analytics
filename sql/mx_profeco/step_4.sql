-- =====================================================================
-- step_4.sql  |  Overlap audit of the five PROFECO cuts (decision D4)
-- =====================================================================
-- Objective   : check that the cases that appear in several cuts agree
--               with the base file, so that the base choice of D4 holds.
--               This script is read-only for the pipeline: it creates two
--               audit tables in schema stg and never touches stg.profeco_raw
--               or the clean layer.
-- Source      : the five CSV cuts of the dataset
--               "Quejas en materia de telecomunicaciones" (data/raw/).
-- Prerequisites: step_0.sql and step_1.sql executed (the base file is
--               already loaded in stg.profeco_raw: 36,034 rows).
--               The SQL Server service account must read data/raw/.
-- PATHS       : the four BULK INSERT paths below assume the CSV files are in
--               the repository folder data\raw\. If they are somewhere else
--               (step_1.sql used D:\Capstone SLA\data\raw\), change the path.
-- How to run  : run it block by block (select the block, press F5).
--               Save a capture of each check as docs/img/step_4_check_NN.png.
--
-- Basic ideas used here:
--   JOIN ... ON  matches rows of two tables that share the same case ID.
--   COLLATE Latin1_General_BIN2  compares text exactly (case and accents).
--   The default database collation ignores case and accents; comparing
--   with both tells us if a difference is only capitalization.
-- =====================================================================

USE complaint_sla;
GO

-- ---------------------------------------------------------------------
-- 4.0 Audit tables
-- ---------------------------------------------------------------------
-- SELECT ... INTO copies the column layout of stg.profeco_raw (23 text
-- columns). WHERE 1 = 0 copies the layout and no rows.
-- stg.profeco_cuts      : all the cuts together, with the name of the file.
-- stg.profeco_cut_load  : temporary landing table for one file at a time.
DROP TABLE IF EXISTS stg.profeco_cuts;
DROP TABLE IF EXISTS stg.profeco_cut_load;

SELECT CAST('' AS NVARCHAR(100)) AS source_file, *
INTO   stg.profeco_cuts
FROM   stg.profeco_raw
WHERE  1 = 0;

SELECT *
INTO   stg.profeco_cut_load
FROM   stg.profeco_raw
WHERE  1 = 0;
GO

-- The base file is already in stg.profeco_raw: copy it, do not reload it.
INSERT INTO stg.profeco_cuts
SELECT 'junio_2026 (base)', *
FROM   stg.profeco_raw;
GO

-- ---------------------------------------------------------------------
-- 4.0b Load the other four cuts, one block per file
-- ---------------------------------------------------------------------
-- Same options as step_1.sql. If a file fails with error 7301, or loads a
-- single row, its line endings are different: change ROWTERMINATOR to
-- '0x0d0a' (CR+LF) or remove that line, and run the block again.
-- After each block the row count is shown: compare it with the table of
-- docs/sources/MX_profeco.md (about 32,961 / 32,652 / 4,081 / 31,926).

-- File 1: 2022_2025
TRUNCATE TABLE stg.profeco_cut_load;
BULK INSERT stg.profeco_cut_load
FROM 'D:\Capstone SLA\github\complaint-resolution-sla-analytics\data\raw\quejas_telecomunicaciones_2022_2025.csv'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a');
INSERT INTO stg.profeco_cuts SELECT '2022_2025', * FROM stg.profeco_cut_load;
SELECT '2022_2025' AS cut, COUNT(*) AS n_rows FROM stg.profeco_cut_load;
GO

-- File 2: 2022_ene_2026
TRUNCATE TABLE stg.profeco_cut_load;
BULK INSERT stg.profeco_cut_load
FROM 'D:\Capstone SLA\github\complaint-resolution-sla-analytics\data\raw\quejas_telecomunicaciones_2022_ene_2026.csv'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a');
INSERT INTO stg.profeco_cuts SELECT 'ene_2026', * FROM stg.profeco_cut_load;
SELECT 'ene_2026' AS cut, COUNT(*) AS n_rows FROM stg.profeco_cut_load;
GO

-- File 3: 2022_may_2026
TRUNCATE TABLE stg.profeco_cut_load;
BULK INSERT stg.profeco_cut_load
FROM 'D:\Capstone SLA\github\complaint-resolution-sla-analytics\data\raw\quejas_telecomunicaciones_2022_may_2026.csv'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a');
INSERT INTO stg.profeco_cuts SELECT 'may_2026', * FROM stg.profeco_cut_load;
SELECT 'may_2026' AS cut, COUNT(*) AS n_rows FROM stg.profeco_cut_load;
GO

-- File 4: jul2026 (the file name pattern is different)
TRUNCATE TABLE stg.profeco_cut_load;
BULK INSERT stg.profeco_cut_load
FROM 'D:\Capstone SLA\github\complaint-resolution-sla-analytics\data\raw\quejas_telecom_2022_jul2026.csv'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a');
INSERT INTO stg.profeco_cuts SELECT 'jul2026', * FROM stg.profeco_cut_load;
SELECT 'jul2026' AS cut, COUNT(*) AS n_rows FROM stg.profeco_cut_load;
GO

DROP TABLE stg.profeco_cut_load;   -- the landing table is not needed any more
GO

-- ---------------------------------------------------------------------
-- 4.1 Rows, distinct case IDs and empty IDs per cut
-- ---------------------------------------------------------------------
-- Look at: n_rows = n_distinct_ids means the case ID is unique inside the cut.
-- The first 3 rows of each cut (second query) confirm the columns are in the
-- same order: if estado_procesal holds a date, the cut has another layout.
SELECT source_file,
       COUNT(*)                                                    AS n_rows,
       COUNT(DISTINCT expediente COLLATE Latin1_General_BIN2)      AS n_distinct_ids,
       SUM(CASE WHEN NULLIF(LTRIM(RTRIM(expediente)), '') IS NULL THEN 1 ELSE 0 END) AS n_empty_ids
FROM   stg.profeco_cuts
GROUP BY source_file
ORDER BY source_file;

SELECT source_file, expediente, fecha_ingreso, fecha_cierre, estado_procesal, nombre_comercial
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY source_file ORDER BY (SELECT NULL)) AS rn
    FROM   stg.profeco_cuts
) AS t
WHERE rn <= 3
ORDER BY source_file, rn;

-- ---------------------------------------------------------------------
-- 4.2 Date range and date format per cut
-- ---------------------------------------------------------------------
-- TRY_CONVERT returns NULL instead of an error. n_bad_* counts values that
-- have text but are not a date in style 23 (yyyy-mm-dd): a cut with a
-- different date format shows many here.
SELECT source_file,
       MIN(TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(fecha_ingreso)), ''), 23)) AS min_filing,
       MAX(TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(fecha_ingreso)), ''), 23)) AS max_filing,
       MIN(TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(fecha_cierre)),  ''), 23)) AS min_close,
       MAX(TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(fecha_cierre)),  ''), 23)) AS max_close,
       SUM(CASE WHEN NULLIF(LTRIM(RTRIM(fecha_ingreso)), '') IS NOT NULL
                 AND TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(fecha_ingreso)), ''), 23) IS NULL
                THEN 1 ELSE 0 END) AS n_bad_filing,
       SUM(CASE WHEN NULLIF(LTRIM(RTRIM(fecha_cierre)), '') IS NOT NULL
                 AND TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(fecha_cierre)), ''), 23) IS NULL
                THEN 1 ELSE 0 END) AS n_bad_close,
       SUM(CASE WHEN NULLIF(LTRIM(RTRIM(fecha_cierre)), '') IS NULL THEN 1 ELSE 0 END) AS n_empty_close
FROM   stg.profeco_cuts
GROUP BY source_file
ORDER BY source_file;

-- ---------------------------------------------------------------------
-- 4.3 Overlap with the base file
-- ---------------------------------------------------------------------
-- in_base       : cases of the cut that also exist in the base.
-- only_in_cut   : cases of the cut that the base does not have.
-- base_not_in_cut: cases of the base that this cut does not have.
-- Expected: the cuts that end before the base (2022_2025, ene_2026) should
-- be almost entirely inside the base. Many only_in_cut cases mean the base
-- is missing cases and must be reconsidered.
WITH base AS (
    SELECT expediente COLLATE Latin1_General_BIN2 AS case_id
    FROM   stg.profeco_cuts
    WHERE  source_file = 'junio_2026 (base)'
),
cut AS (
    SELECT source_file, expediente COLLATE Latin1_General_BIN2 AS case_id
    FROM   stg.profeco_cuts
    WHERE  source_file <> 'junio_2026 (base)'
)
SELECT c.source_file,
       COUNT(*)                                          AS n_cut,
       SUM(CASE WHEN b.case_id IS NOT NULL THEN 1 ELSE 0 END) AS in_base,
       SUM(CASE WHEN b.case_id IS NULL     THEN 1 ELSE 0 END) AS only_in_cut,
       (SELECT COUNT(*) FROM base)
         - SUM(CASE WHEN b.case_id IS NOT NULL THEN 1 ELSE 0 END) AS base_not_in_cut
FROM   cut AS c
LEFT JOIN base AS b ON b.case_id = c.case_id
GROUP BY c.source_file
ORDER BY c.source_file;

-- ---------------------------------------------------------------------
-- 4.4 Do the shared cases agree? Exact comparison, column by column
-- ---------------------------------------------------------------------
-- For each cut, among the cases that exist in the base, count the rows
-- where a column has a different value. ISNULL(x, '') makes an empty value
-- equal to another empty value. Exact = case and accents count.
SELECT c.source_file,
       COUNT(*) AS n_shared,
       SUM(CASE WHEN ISNULL(c.fecha_ingreso,'')      COLLATE Latin1_General_BIN2 <> ISNULL(b.fecha_ingreso,'')      COLLATE Latin1_General_BIN2 THEN 1 ELSE 0 END) AS d_fecha_ingreso,
       SUM(CASE WHEN ISNULL(c.fecha_cierre,'')       COLLATE Latin1_General_BIN2 <> ISNULL(b.fecha_cierre,'')       COLLATE Latin1_General_BIN2 THEN 1 ELSE 0 END) AS d_fecha_cierre,
       SUM(CASE WHEN ISNULL(c.estado_procesal,'')    COLLATE Latin1_General_BIN2 <> ISNULL(b.estado_procesal,'')    COLLATE Latin1_General_BIN2 THEN 1 ELSE 0 END) AS d_estado_procesal,
       SUM(CASE WHEN ISNULL(c.tipo_conciliacion,'')  COLLATE Latin1_General_BIN2 <> ISNULL(b.tipo_conciliacion,'')  COLLATE Latin1_General_BIN2 THEN 1 ELSE 0 END) AS d_tipo_conciliacion,
       SUM(CASE WHEN ISNULL(c.proveedor,'')          COLLATE Latin1_General_BIN2 <> ISNULL(b.proveedor,'')          COLLATE Latin1_General_BIN2 THEN 1 ELSE 0 END) AS d_proveedor,
       SUM(CASE WHEN ISNULL(c.nombre_comercial,'')   COLLATE Latin1_General_BIN2 <> ISNULL(b.nombre_comercial,'')   COLLATE Latin1_General_BIN2 THEN 1 ELSE 0 END) AS d_nombre_comercial,
       SUM(CASE WHEN ISNULL(c.odeco,'')              COLLATE Latin1_General_BIN2 <> ISNULL(b.odeco,'')              COLLATE Latin1_General_BIN2 THEN 1 ELSE 0 END) AS d_odeco,
       SUM(CASE WHEN ISNULL(c.estado,'')             COLLATE Latin1_General_BIN2 <> ISNULL(b.estado,'')             COLLATE Latin1_General_BIN2 THEN 1 ELSE 0 END) AS d_estado,
       SUM(CASE WHEN ISNULL(c.procedimiento,'')      COLLATE Latin1_General_BIN2 <> ISNULL(b.procedimiento,'')      COLLATE Latin1_General_BIN2 THEN 1 ELSE 0 END) AS d_procedimiento,
       SUM(CASE WHEN ISNULL(c.medio_ingreso,'')      COLLATE Latin1_General_BIN2 <> ISNULL(b.medio_ingreso,'')      COLLATE Latin1_General_BIN2 THEN 1 ELSE 0 END) AS d_medio_ingreso,
       SUM(CASE WHEN ISNULL(c.monto_reclamado,'')    COLLATE Latin1_General_BIN2 <> ISNULL(b.monto_reclamado,'')    COLLATE Latin1_General_BIN2 THEN 1 ELSE 0 END) AS d_monto_reclamado,
       SUM(CASE WHEN ISNULL(c.monto_recuperado,'')   COLLATE Latin1_General_BIN2 <> ISNULL(b.monto_recuperado,'')   COLLATE Latin1_General_BIN2 THEN 1 ELSE 0 END) AS d_monto_recuperado
FROM   stg.profeco_cuts AS c
JOIN   stg.profeco_cuts AS b
       ON  b.source_file = 'junio_2026 (base)'
       AND b.expediente COLLATE Latin1_General_BIN2 = c.expediente COLLATE Latin1_General_BIN2
WHERE  c.source_file <> 'junio_2026 (base)'
GROUP BY c.source_file
ORDER BY c.source_file;

-- ---------------------------------------------------------------------
-- 4.5 Same comparison ignoring case and accents
-- ---------------------------------------------------------------------
-- Same query, but with the default database collation (Modern_Spanish_CI_AI):
-- "TELMEX" and "Telmex" are equal. If a column has differences in 4.4 and
-- none here, the cut only changes the capitalization of that column.
SELECT c.source_file,
       COUNT(*) AS n_shared,
       SUM(CASE WHEN ISNULL(c.fecha_ingreso,'')      <> ISNULL(b.fecha_ingreso,'')      THEN 1 ELSE 0 END) AS d_fecha_ingreso,
       SUM(CASE WHEN ISNULL(c.fecha_cierre,'')       <> ISNULL(b.fecha_cierre,'')       THEN 1 ELSE 0 END) AS d_fecha_cierre,
       SUM(CASE WHEN ISNULL(c.estado_procesal,'')    <> ISNULL(b.estado_procesal,'')    THEN 1 ELSE 0 END) AS d_estado_procesal,
       SUM(CASE WHEN ISNULL(c.tipo_conciliacion,'')  <> ISNULL(b.tipo_conciliacion,'')  THEN 1 ELSE 0 END) AS d_tipo_conciliacion,
       SUM(CASE WHEN ISNULL(c.proveedor,'')          <> ISNULL(b.proveedor,'')          THEN 1 ELSE 0 END) AS d_proveedor,
       SUM(CASE WHEN ISNULL(c.nombre_comercial,'')   <> ISNULL(b.nombre_comercial,'')   THEN 1 ELSE 0 END) AS d_nombre_comercial,
       SUM(CASE WHEN ISNULL(c.odeco,'')              <> ISNULL(b.odeco,'')              THEN 1 ELSE 0 END) AS d_odeco,
       SUM(CASE WHEN ISNULL(c.estado,'')             <> ISNULL(b.estado,'')             THEN 1 ELSE 0 END) AS d_estado,
       SUM(CASE WHEN ISNULL(c.procedimiento,'')      <> ISNULL(b.procedimiento,'')      THEN 1 ELSE 0 END) AS d_procedimiento,
       SUM(CASE WHEN ISNULL(c.medio_ingreso,'')      <> ISNULL(b.medio_ingreso,'')      THEN 1 ELSE 0 END) AS d_medio_ingreso,
       SUM(CASE WHEN ISNULL(c.monto_reclamado,'')    <> ISNULL(b.monto_reclamado,'')    THEN 1 ELSE 0 END) AS d_monto_reclamado,
       SUM(CASE WHEN ISNULL(c.monto_recuperado,'')   <> ISNULL(b.monto_recuperado,'')   THEN 1 ELSE 0 END) AS d_monto_recuperado
FROM   stg.profeco_cuts AS c
JOIN   stg.profeco_cuts AS b
       ON  b.source_file = 'junio_2026 (base)'
       AND b.expediente COLLATE Latin1_General_BIN2 = c.expediente COLLATE Latin1_General_BIN2
WHERE  c.source_file <> 'junio_2026 (base)'
GROUP BY c.source_file
ORDER BY c.source_file;

-- ---------------------------------------------------------------------
-- 4.6 Cases that the base does not have: what are they?
-- ---------------------------------------------------------------------
-- For each cut, the cases missing in the base by close year and month.
-- If jul2026 has cases closed after the base (June/July 2026), it is a
-- newer publication and D4 must be revisited. If the missing cases are
-- spread over old dates, the cut has cases that the base lacks.
WITH base AS (
    SELECT expediente COLLATE Latin1_General_BIN2 AS case_id
    FROM   stg.profeco_cuts
    WHERE  source_file = 'junio_2026 (base)'
)
SELECT c.source_file,
       YEAR (TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(c.fecha_cierre)), ''), 23)) AS close_year,
       MONTH(TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(c.fecha_cierre)), ''), 23)) AS close_month,
       COUNT(*) AS n_cases_not_in_base
FROM   stg.profeco_cuts AS c
LEFT JOIN base AS b ON b.case_id = c.expediente COLLATE Latin1_General_BIN2
WHERE  c.source_file <> 'junio_2026 (base)'
  AND  b.case_id IS NULL
GROUP BY c.source_file,
         YEAR (TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(c.fecha_cierre)), ''), 23)),
         MONTH(TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(c.fecha_cierre)), ''), 23))
ORDER BY c.source_file, close_year, close_month;

-- ---------------------------------------------------------------------
-- FOLLOW-UP CHECKS (added after the first results of 4.1 to 4.6)
-- ---------------------------------------------------------------------
-- The first run showed that two cuts write dates as 2025/02/18 (slashes) and
-- that the amounts and some names differ in text. These checks separate
-- real differences from format differences.

-- ---------------------------------------------------------------------
-- 4.7 Dates compared as DATES, not as text
-- ---------------------------------------------------------------------
-- 4.4 counted every row as different in fecha_ingreso for 2022_2025 and
-- ene_2026 only because of the separator (/ versus -). Here the text is
-- converted first. A difference is: both dates exist and differ, or only one
-- of them exists.
WITH shared AS (
    SELECT c.source_file,
           TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(c.fecha_ingreso)), ''), 23) AS c_filing,
           TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(b.fecha_ingreso)), ''), 23) AS b_filing,
           TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(c.fecha_cierre)),  ''), 23) AS c_close,
           TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(b.fecha_cierre)),  ''), 23) AS b_close
    FROM   stg.profeco_cuts AS c
    JOIN   stg.profeco_cuts AS b
           ON  b.source_file = 'junio_2026 (base)'
           AND b.expediente COLLATE Latin1_General_BIN2 = c.expediente COLLATE Latin1_General_BIN2
    WHERE  c.source_file <> 'junio_2026 (base)'
)
SELECT source_file,
       COUNT(*) AS n_shared,
       SUM(CASE WHEN c_filing <> b_filing
                  OR (c_filing IS NULL AND b_filing IS NOT NULL)
                  OR (c_filing IS NOT NULL AND b_filing IS NULL) THEN 1 ELSE 0 END) AS d_filing_date,
       SUM(CASE WHEN c_close <> b_close
                  OR (c_close IS NULL AND b_close IS NOT NULL)
                  OR (c_close IS NOT NULL AND b_close IS NULL) THEN 1 ELSE 0 END) AS d_close_date
FROM   shared
GROUP BY source_file
ORDER BY source_file;

-- ---------------------------------------------------------------------
-- 4.8 Cases of the base that the jul2026 cut does not have
-- ---------------------------------------------------------------------
-- jul2026 lacks 6,068 cases of the base. By filing year and by outcome we
-- see if it is a specific group (for example cancelled cases) or random.
WITH missing AS (
    SELECT b.fecha_ingreso, b.estado_procesal
    FROM   stg.profeco_cuts AS b
    LEFT JOIN stg.profeco_cuts AS j
           ON  j.source_file = 'jul2026'
           AND j.expediente COLLATE Latin1_General_BIN2 = b.expediente COLLATE Latin1_General_BIN2
    WHERE  b.source_file = 'junio_2026 (base)'
      AND  j.expediente IS NULL
)
SELECT YEAR(TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(fecha_ingreso)), ''), 23)) AS filing_year,
       estado_procesal,
       COUNT(*) AS n_base_cases_not_in_jul2026
FROM   missing
GROUP BY YEAR(TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(fecha_ingreso)), ''), 23)), estado_procesal
ORDER BY filing_year, n_base_cases_not_in_jul2026 DESC;

-- ---------------------------------------------------------------------
-- 4.9 Repeated IDs inside a cut (2022_2025 and may_2026)
-- ---------------------------------------------------------------------
-- 4.1 showed 988 repeated IDs in 2022_2025 and 14 in may_2026. For each
-- repeated ID we count how many different versions of the row exist
-- (looking at the main columns). n_identical_ids = the repeated rows are
-- exact copies; n_conflicting_ids = the rows of one ID disagree.
WITH rep AS (
    SELECT source_file,
           expediente COLLATE Latin1_General_BIN2 AS case_id,
           COUNT(*) AS n_rows,
           COUNT(DISTINCT CONCAT_WS('|', fecha_ingreso, fecha_cierre, estado_procesal,
                                    proveedor, nombre_comercial, odeco, estado,
                                    monto_reclamado, monto_recuperado)) AS n_versions
    FROM   stg.profeco_cuts
    GROUP BY source_file, expediente COLLATE Latin1_General_BIN2
    HAVING COUNT(*) > 1
)
SELECT source_file,
       COUNT(*)                                          AS n_repeated_ids,
       SUM(n_rows)                                       AS n_rows_involved,
       SUM(CASE WHEN n_versions = 1 THEN 1 ELSE 0 END)   AS n_identical_ids,
       SUM(CASE WHEN n_versions > 1 THEN 1 ELSE 0 END)   AS n_conflicting_ids
FROM   rep
GROUP BY source_file
ORDER BY source_file;

-- ---------------------------------------------------------------------
-- 4.10 What the differing values look like
-- ---------------------------------------------------------------------
-- The most frequent (base value, cut value) pairs, for the columns where
-- 4.5 still shows differences. Default collation: capitalization-only pairs
-- are not listed. Take one capture per query (4.10a to 4.10e).

-- 4.10a brand (nombre_comercial) in 2022_2025
SELECT TOP 10 b.nombre_comercial AS base_value, c.nombre_comercial AS cut_value, COUNT(*) AS n
FROM stg.profeco_cuts AS c
JOIN stg.profeco_cuts AS b ON b.source_file = 'junio_2026 (base)'
     AND b.expediente COLLATE Latin1_General_BIN2 = c.expediente COLLATE Latin1_General_BIN2
WHERE c.source_file = '2022_2025' AND ISNULL(c.nombre_comercial,'') <> ISNULL(b.nombre_comercial,'')
GROUP BY b.nombre_comercial, c.nombre_comercial ORDER BY n DESC;

-- 4.10b office (odeco) in ene_2026
SELECT TOP 10 b.odeco AS base_value, c.odeco AS cut_value, COUNT(*) AS n
FROM stg.profeco_cuts AS c
JOIN stg.profeco_cuts AS b ON b.source_file = 'junio_2026 (base)'
     AND b.expediente COLLATE Latin1_General_BIN2 = c.expediente COLLATE Latin1_General_BIN2
WHERE c.source_file = 'ene_2026' AND ISNULL(c.odeco,'') <> ISNULL(b.odeco,'')
GROUP BY b.odeco, c.odeco ORDER BY n DESC;

-- 4.10c provider (proveedor) in jul2026
SELECT TOP 10 b.proveedor AS base_value, c.proveedor AS cut_value, COUNT(*) AS n
FROM stg.profeco_cuts AS c
JOIN stg.profeco_cuts AS b ON b.source_file = 'junio_2026 (base)'
     AND b.expediente COLLATE Latin1_General_BIN2 = c.expediente COLLATE Latin1_General_BIN2
WHERE c.source_file = 'jul2026' AND ISNULL(c.proveedor,'') <> ISNULL(b.proveedor,'')
GROUP BY b.proveedor, c.proveedor ORDER BY n DESC;

-- 4.10d claimed amount (monto_reclamado) in jul2026
SELECT TOP 10 b.monto_reclamado AS base_value, c.monto_reclamado AS cut_value, COUNT(*) AS n
FROM stg.profeco_cuts AS c
JOIN stg.profeco_cuts AS b ON b.source_file = 'junio_2026 (base)'
     AND b.expediente COLLATE Latin1_General_BIN2 = c.expediente COLLATE Latin1_General_BIN2
WHERE c.source_file = 'jul2026' AND ISNULL(c.monto_reclamado,'') <> ISNULL(b.monto_reclamado,'')
GROUP BY b.monto_reclamado, c.monto_reclamado ORDER BY n DESC;

-- 4.10e recovered amount (monto_recuperado) in ene_2026
SELECT TOP 10 b.monto_recuperado AS base_value, c.monto_recuperado AS cut_value, COUNT(*) AS n
FROM stg.profeco_cuts AS c
JOIN stg.profeco_cuts AS b ON b.source_file = 'junio_2026 (base)'
     AND b.expediente COLLATE Latin1_General_BIN2 = c.expediente COLLATE Latin1_General_BIN2
WHERE c.source_file = 'ene_2026' AND ISNULL(c.monto_recuperado,'') <> ISNULL(b.monto_recuperado,'')
GROUP BY b.monto_recuperado, c.monto_recuperado ORDER BY n DESC;

-- ---------------------------------------------------------------------
-- 4.11 Repeated IDs of 2022_2025: which columns conflict, and do they matter?
-- ---------------------------------------------------------------------
-- 4.9 showed 932 IDs with two different rows in 2022_2025, while the base has
-- each ID once. 4.10a suggests that the second row belongs to another brand
-- (Telcel / Samsung): a complaint against two providers. 4.11a counts the
-- columns that conflict; 4.11b counts the IDs that involve one of the four
-- fixed operators, the only ones that the project analyses (D11).

-- 4.11a Columns that disagree inside the repeated IDs
WITH rep AS (
    SELECT expediente COLLATE Latin1_General_BIN2 AS case_id,
           COUNT(DISTINCT nombre_comercial) AS n_brand,
           COUNT(DISTINCT proveedor)        AS n_provider,
           COUNT(DISTINCT fecha_ingreso)    AS n_filing,
           COUNT(DISTINCT fecha_cierre)     AS n_close,
           COUNT(DISTINCT estado_procesal)  AS n_outcome,
           COUNT(DISTINCT odeco)            AS n_office,
           COUNT(DISTINCT motivo_reclamacion) AS n_reason
    FROM   stg.profeco_cuts
    WHERE  source_file = '2022_2025'
    GROUP BY expediente COLLATE Latin1_General_BIN2
    HAVING COUNT(*) > 1
)
SELECT COUNT(*)                                         AS n_repeated_ids,
       SUM(CASE WHEN n_brand    > 1 THEN 1 ELSE 0 END)  AS differ_brand,
       SUM(CASE WHEN n_provider > 1 THEN 1 ELSE 0 END)  AS differ_provider,
       SUM(CASE WHEN n_filing   > 1 THEN 1 ELSE 0 END)  AS differ_filing,
       SUM(CASE WHEN n_close    > 1 THEN 1 ELSE 0 END)  AS differ_close,
       SUM(CASE WHEN n_outcome  > 1 THEN 1 ELSE 0 END)  AS differ_outcome,
       SUM(CASE WHEN n_office   > 1 THEN 1 ELSE 0 END)  AS differ_office,
       SUM(CASE WHEN n_reason   > 1 THEN 1 ELSE 0 END)  AS differ_reason
FROM   rep;

-- 4.11b Repeated IDs that involve a fixed operator, and what the base keeps
-- n_ids_with_fixed_brand : repeated IDs where at least one row is Telmex, Izzi,
--                          Megacable or Total Play (any spelling).
-- base_keeps_fixed       : of those, IDs whose single base row is a fixed brand.
-- base_keeps_other       : IDs whose base row is another brand (the fixed
--                          operator is lost for that complaint).
WITH rep AS (
    SELECT expediente COLLATE Latin1_General_BIN2 AS case_id
    FROM   stg.profeco_cuts
    WHERE  source_file = '2022_2025'
    GROUP BY expediente COLLATE Latin1_General_BIN2
    HAVING COUNT(*) > 1
),
fixed_ids AS (
    SELECT DISTINCT r.case_id
    FROM   rep AS r
    JOIN   stg.profeco_cuts AS c
           ON  c.source_file = '2022_2025'
           AND c.expediente COLLATE Latin1_General_BIN2 = r.case_id
    WHERE  c.nombre_comercial IN (N'Telmex', N'Izzi', N'Megacable', N'Totalplay', N'Total Play')
)
SELECT COUNT(*) AS n_ids_with_fixed_brand,
       SUM(CASE WHEN b.nombre_comercial IN (N'Telmex', N'Izzi', N'Megacable', N'Totalplay', N'Total Play')
                THEN 1 ELSE 0 END) AS base_keeps_fixed,
       SUM(CASE WHEN b.nombre_comercial IN (N'Telmex', N'Izzi', N'Megacable', N'Totalplay', N'Total Play')
                THEN 0 ELSE 1 END) AS base_keeps_other
FROM   fixed_ids AS f
JOIN   stg.profeco_cuts AS b
       ON  b.source_file = 'junio_2026 (base)'
       AND b.expediente COLLATE Latin1_General_BIN2 = f.case_id;

-- ---------------------------------------------------------------------
-- How to read the results (decision rule for D4)
-- ---------------------------------------------------------------------
-- D4 is accepted if:
--   1. In 4.4 and 4.5 the shared cases agree in the date, outcome and
--      provider columns (differences below 1%, or only capitalization).
--   2. In 4.3 and 4.6 the cases that the base lacks are few, or belong to
--      later periods that the base does not claim to cover.
-- D4 is revisited if a cut has many cases the base lacks, or if jul2026
-- looks like a corrected republication (different values for shared cases).
-- =====================================================================