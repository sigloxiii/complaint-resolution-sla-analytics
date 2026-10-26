-- =====================================================================
-- step_2.sql   (source: PROFECO telecom complaints, México)
-- Objective : feasibility gate. Look at the raw data in stg.profeco_raw
--             and answer: is the Mexican dataset good enough to use?
-- Gate criteria:
--   1) at least 2,000 complaints against fixed-network operators
--   2) few missing close dates (less than 30%)
--   3) main providers (Telmex, Izzi, Megacable, Total Play) with at
--      least 100 complaints per year
--   4) subscribers by operator and state in BIT (checked outside SQL)
-- Needs     : step_1.sql already executed.
-- How to run: this script only READS data (SELECT). It changes nothing.
--             Select one query (its lines) and press F5, or run
--             everything and look at each result tab.
--             Save the results (screenshot or copy) for docs/sources/.
--
-- Quick guide to the commands used here:
--   SELECT ... FROM table  reads rows from a table
--   WHERE                  keeps only the rows that meet a condition
--   GROUP BY + COUNT(*)    counts how many rows each group has
--   ORDER BY ... DESC      shows the biggest values first
--   TOP n                  returns only the first n rows
--
-- Dates are still TEXT in this script. Because the format is year first
-- (for example 2022/01/03), text sorts in the same order as dates, so
-- MIN, MAX and comparisons work without converting. The real conversion
-- to the DATE type happens later, in the clean layer (step_3).
-- =====================================================================

USE complaint_sla;
GO

-- (Cleanup) An earlier draft of this script created a helper view.
-- This line removes it if it exists. If it does not, nothing happens.
DROP VIEW IF EXISTS stg.v_profeco_typed;
GO

-- ---------------------------------------------------------------------
-- 2.1 HOW MANY ROWS?   Expected: 36034
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS n_rows
FROM stg.profeco_raw;

-- ---------------------------------------------------------------------
-- 2.2 IS "expediente" (the case ID) UNIQUE?
-- DISTINCT makes COUNT ignore repeated values.
-- n_distinct_expediente must be equal to n_rows from 2.1.
-- ---------------------------------------------------------------------
SELECT COUNT(DISTINCT expediente) AS n_distinct_expediente
FROM stg.profeco_raw;

-- ---------------------------------------------------------------------
-- 2.3 LOOK AT THE RAW DATES
-- Write down the format you see (for example 2022/01/03 or 2022-01-03).
-- ---------------------------------------------------------------------
SELECT TOP 5 fecha_ingreso, fecha_cierre
FROM stg.profeco_raw;

-- ---------------------------------------------------------------------
-- 2.4 DO ALL DATES HAVE THE FORMAT yyyy/mm/dd (or yyyy-mm-dd)?
-- LIKE compares text with a pattern:
--   [0-9]  means "one digit"
--   [/-]   means "a slash or a dash"
-- Both counts must be 0. If they are not, the date format is different
-- from what we assume and step_3 must be adapted before converting.
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS bad_format_ingreso
FROM stg.profeco_raw
WHERE fecha_ingreso IS NULL
   OR fecha_ingreso NOT LIKE '[0-9][0-9][0-9][0-9][/-][0-9][0-9][/-][0-9][0-9]';

-- A missing close date is allowed (open or cancelled cases), so empties are skipped.
SELECT COUNT(*) AS bad_format_cierre
FROM stg.profeco_raw
WHERE fecha_cierre IS NOT NULL
  AND fecha_cierre <> ''
  AND fecha_cierre NOT LIKE '[0-9][0-9][0-9][0-9][/-][0-9][0-9][/-][0-9][0-9]';

-- ---------------------------------------------------------------------
-- 2.5 DATE RANGES
-- Expected (from Power Query):
--   filing: 2022-01-03 to 2026-05-27    close: 2022-01-06 to 2026-05-29
-- ---------------------------------------------------------------------
SELECT MIN(fecha_ingreso) AS first_ingreso,
       MAX(fecha_ingreso) AS last_ingreso
FROM stg.profeco_raw;

SELECT MIN(fecha_cierre) AS first_cierre,
       MAX(fecha_cierre) AS last_cierre
FROM stg.profeco_raw
WHERE fecha_cierre IS NOT NULL
  AND fecha_cierre <> '';

-- ---------------------------------------------------------------------
-- 2.6 GATE 2: HOW MANY CASES HAVE NO CLOSE DATE?
-- Expected: about 66 of 36,034 (0.18%). The limit is 30%.
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS n_missing_cierre
FROM stg.profeco_raw
WHERE fecha_cierre IS NULL
   OR fecha_cierre = '';

-- ---------------------------------------------------------------------
-- 2.7 CLOSE DATE BEFORE FILING DATE (impossible)
-- Should be 0, or very few. The text comparison is valid only if both
-- dates use the same separator (checked in 2.3 and 2.4).
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS n_close_before_filing
FROM stg.profeco_raw
WHERE fecha_cierre IS NOT NULL
  AND fecha_cierre <> ''
  AND fecha_cierre < fecha_ingreso;

-- ---------------------------------------------------------------------
-- 2.8 WHICH COLUMN SAYS THE TYPE OF SERVICE?
-- The file has no column called "service" (internet, mobile, TV).
-- These queries list the values of the columns that might help.
-- Look for values such as internet, telefonía móvil, televisión.
-- ---------------------------------------------------------------------
SELECT giro, COUNT(*) AS n
FROM stg.profeco_raw
GROUP BY giro
ORDER BY n DESC;

SELECT sector, COUNT(*) AS n
FROM stg.profeco_raw
GROUP BY sector
ORDER BY n DESC;

SELECT clase, COUNT(*) AS n
FROM stg.profeco_raw
GROUP BY clase
ORDER BY n DESC;

SELECT tipo_producto, COUNT(*) AS n
FROM stg.profeco_raw
GROUP BY tipo_producto
ORDER BY n DESC;

SELECT procedimiento, COUNT(*) AS n
FROM stg.profeco_raw
GROUP BY procedimiento
ORDER BY n DESC;

SELECT medio_ingreso, COUNT(*) AS n
FROM stg.profeco_raw
GROUP BY medio_ingreso
ORDER BY n DESC;

SELECT tipo_conciliacion, COUNT(*) AS n
FROM stg.profeco_raw
GROUP BY tipo_conciliacion
ORDER BY n DESC;

SELECT estado_procesal, COUNT(*) AS n
FROM stg.profeco_raw
GROUP BY estado_procesal
ORDER BY n DESC;

-- ---------------------------------------------------------------------
-- 2.9 HOW MESSY ARE THE PROVIDER NAMES?
-- Power Query showed 486 different legal names (column proveedor).
-- The brand (nombre_comercial) should have far fewer values.
-- ---------------------------------------------------------------------
SELECT COUNT(DISTINCT proveedor)        AS n_legal_names,
       COUNT(DISTINCT nombre_comercial) AS n_commercial_names
FROM stg.profeco_raw;

-- The 30 brands with the most complaints
SELECT TOP 30 nombre_comercial, COUNT(*) AS n_complaints
FROM stg.profeco_raw
GROUP BY nombre_comercial
ORDER BY n_complaints DESC;

-- ---------------------------------------------------------------------
-- 2.10 GATE 3: COMPLAINTS PER YEAR FOR THE MAIN FIXED-NETWORK OPERATORS
-- LEFT(text, 4) takes the first 4 characters. The date starts with the
-- year, so that gives the filing year.
-- Needed: at least 100 per provider per year. 2026 is partial (data ends in May).
-- If a provider is missing from the result, its brand is written
-- differently: look for it in the list from 2.9.
-- ---------------------------------------------------------------------
SELECT nombre_comercial,
       LEFT(fecha_ingreso, 4) AS filing_year,
       COUNT(*)               AS n_complaints
FROM stg.profeco_raw
WHERE nombre_comercial IN ('Telmex', 'Izzi', 'Megacable', 'Total Play')
GROUP BY nombre_comercial, LEFT(fecha_ingreso, 4)
ORDER BY nombre_comercial, filing_year;

-- ---------------------------------------------------------------------
-- 2.11 GATE 1 (proxy): TOTAL COMPLAINTS AGAINST FIXED-NETWORK OPERATORS
-- Needed: at least 2,000. This operator list is a first guess; it will be
-- refined later in the provider mapping table.
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS n_fixed_network_complaints
FROM stg.profeco_raw
WHERE nombre_comercial IN ('Telmex', 'Izzi', 'Megacable', 'Total Play');

-- ---------------------------------------------------------------------
-- 2.12 DAYS WITH MANY CLOSINGS (possible batch closings)
-- Power Query showed some close dates with many more cases than the rest.
-- ---------------------------------------------------------------------
SELECT TOP 15 fecha_cierre, COUNT(*) AS n_cases
FROM stg.profeco_raw
WHERE fecha_cierre IS NOT NULL
  AND fecha_cierre <> ''
GROUP BY fecha_cierre
ORDER BY n_cases DESC;

-- ---------------------------------------------------------------------
-- 2.13 AMOUNTS THAT ARE NOT NUMBERS
-- The amount columns are still text. TRY_CONVERT tries to turn text into
-- a number and returns NULL (instead of an error) when it cannot.
-- So "TRY_CONVERT(...) IS NULL" on a non-empty value means "this value
-- is not a valid number". Each query lists those values.
-- An empty result means there is no problem in that column.
-- Power Query already showed that the value "-" (a dash) is what fails to
-- convert. Here you will see how many rows have it in each column.
-- ---------------------------------------------------------------------
SELECT TOP 20 monto_reclamado, COUNT(*) AS n
FROM stg.profeco_raw
WHERE monto_reclamado IS NOT NULL
  AND monto_reclamado <> ''
  AND TRY_CONVERT(decimal(18, 2), monto_reclamado) IS NULL
GROUP BY monto_reclamado
ORDER BY n DESC;

SELECT TOP 20 monto_recuperado, COUNT(*) AS n
FROM stg.profeco_raw
WHERE monto_recuperado IS NOT NULL
  AND monto_recuperado <> ''
  AND TRY_CONVERT(decimal(18, 2), monto_recuperado) IS NULL
GROUP BY monto_recuperado
ORDER BY n DESC;

SELECT TOP 20 costo_bien_servicio, COUNT(*) AS n
FROM stg.profeco_raw
WHERE costo_bien_servicio IS NOT NULL
  AND costo_bien_servicio <> ''
  AND TRY_CONVERT(decimal(18, 2), costo_bien_servicio) IS NULL
GROUP BY costo_bien_servicio
ORDER BY n DESC;

-- ---------------------------------------------------------------------
-- 2.14 CANCELLED CASES AND PLACEHOLDER VALUES
-- Power Query showed rows with estado_procesal = Cancelada, provider "-"
-- and brand "Otros". How many are there?
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS n_cancelada
FROM stg.profeco_raw
WHERE estado_procesal = 'Cancelada';

SELECT COUNT(*) AS n_provider_dash
FROM stg.profeco_raw
WHERE proveedor = '-';

SELECT COUNT(*) AS n_brand_otros
FROM stg.profeco_raw
WHERE nombre_comercial = 'Otros';

-- Do cancelled cases explain the missing close dates from 2.6?
SELECT COUNT(*) AS n_cancelada_without_cierre
FROM stg.profeco_raw
WHERE estado_procesal = 'Cancelada'
  AND (fecha_cierre IS NULL OR fecha_cierre = '');

-- Cancelled cases by filing year
SELECT LEFT(fecha_ingreso, 4) AS filing_year, COUNT(*) AS n_cancelada
FROM stg.profeco_raw
WHERE estado_procesal = 'Cancelada'
GROUP BY LEFT(fecha_ingreso, 4)
ORDER BY filing_year;