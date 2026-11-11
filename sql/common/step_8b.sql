-- =====================================================================
-- step_8b.sql  |  Cross-checks of the Power BI report (read-only on the mart)
-- =====================================================================
-- Objective   : keep, as repeatable queries, the reference values used to check the
--               measures and visuals of the report (checks P1 to P6 and the row
--               counts of the pipeline). Power BI must show the same numbers.
-- Source      : mart tables of step_7.sql and view mart.v_duration_cases of step_8.sql.
-- Prerequisites: steps 0 to 8 executed.
-- How to run  : run it block by block (select the block, press F5).
-- Evidence    : the captures taken while the report was built keep their original
--               names: P1 and P2 = step_7_check_09.png, P3 and P4 = step_7_check_10.png,
--               P5 = step_7_check_11.png, P6 = step_7_check_12.png (see docs/run_log.md, step 9).
--               The queries were written to this file after those captures, so run
--               them once and compare with the expected values below.
-- =====================================================================

USE complaint_sla;
GO

-- ---------------------------------------------------------------------
-- P1 Share of the cases handled by the central office (office H, D8)
-- ---------------------------------------------------------------------
-- Expected: 49.6% in the fixed broadband complaints (dashboard scope) and 54.9% in
-- all the complaints. Power BI: measure Central Office Share.
-- Technique: conditional aggregation (SUM(CASE WHEN ...)) gives the share of both
-- populations in a single pass.
SELECT COUNT(*)                                                       AS all_complaints,
       CAST(100.0 * SUM(CAST(f.flag_central_office AS INT)) / COUNT(*)
            AS DECIMAL(5,1))                                          AS central_share_all_pct,
       SUM(CASE WHEN b.in_dashboard_scope = 1 THEN 1 ELSE 0 END)      AS fixed_complaints,
       CAST(100.0 * SUM(CASE WHEN b.in_dashboard_scope = 1 AND f.flag_central_office = 1
                             THEN 1 ELSE 0 END)
            / SUM(CASE WHEN b.in_dashboard_scope = 1 THEN 1 ELSE 0 END)
            AS DECIMAL(5,1))                                          AS central_share_fixed_pct
FROM   mart.fact_complaint AS f
JOIN   mart.dim_brand      AS b ON b.brand_key = f.brand_key;

-- ---------------------------------------------------------------------
-- P2 Complaints per 100,000 accesses, four operators combined, 2022 to 2024
-- ---------------------------------------------------------------------
-- Expected: 16.60 (2022), 11.51 (2023) and 9.33 (2024); accesses of December 2024:
-- 29,003,240. Power BI: measure Complaints per 100k Accesses (one year selected).
-- Technique: two CTEs, each aggregated at its own grain before the join (the same
-- pattern as 7.3f), so the sums are not repeated.
WITH c AS (
    SELECT d.year_num, COUNT(*) AS complaints
    FROM   mart.fact_complaint AS f
    JOIN   mart.dim_date       AS d ON d.date_key     = f.filing_date_key
    JOIN   mart.dim_brand      AS b ON b.brand_key    = f.brand_key
    JOIN   mart.dim_operator   AS o ON o.operator_key = f.operator_key
    WHERE  b.in_dashboard_scope = 1 AND o.is_main_operator = 1
    GROUP BY d.year_num
), a AS (
    SELECT d.year_num, SUM(f.accesses) AS accesses_december
    FROM   mart.fact_accesses AS f
    JOIN   mart.dim_date      AS d ON d.date_key     = f.period_date_key
    JOIN   mart.dim_operator  AS o ON o.operator_key = f.operator_key
    WHERE  d.month_num = 12 AND o.is_main_operator = 1
    GROUP BY d.year_num
)
SELECT c.year_num, c.complaints, a.accesses_december,
       CAST(100000.0 * c.complaints / a.accesses_december AS DECIMAL(9,2)) AS complaints_per_100k
FROM   c
JOIN   a ON a.year_num = c.year_num
WHERE  c.year_num BETWEEN 2022 AND 2024
ORDER BY c.year_num;

-- ---------------------------------------------------------------------
-- P3 Top 10 PROFECO office states (fixed broadband brands, dashboard scope)
-- ---------------------------------------------------------------------
-- Expected: Ciudad de México 7,748; Estado de México 610; Yucatán 379; San Luis
-- Potosí 345; Guanajuato 332; Morelos 290; Querétaro 290 (tie: the order of these
-- two may change); Jalisco 251; Coahuila 250; Tamaulipas 238.
SELECT TOP (10) s.state_name, COUNT(*) AS complaints
FROM   mart.fact_complaint AS c
JOIN   mart.dim_brand      AS b ON b.brand_key = c.brand_key
JOIN   mart.dim_state      AS s ON s.state_key = c.state_key
WHERE  b.in_dashboard_scope = 1
GROUP BY s.state_name
ORDER BY complaints DESC;

-- ---------------------------------------------------------------------
-- P4 Top 10 claim types, same population
-- ---------------------------------------------------------------------
-- Expected: Cobro Indebido 4,343; Entrega del Producto o Servicio 4,335; Contratos
-- 3,682; Cambios, Devoluciones o Bonificaciones 493; Trato o Servicio al Cliente
-- 159; Publicidad, Ofertas y Promociones 138; Garantías 61; Portabilidad 45;
-- Información Incorrecta al Consumidor Sobre... 28; Pérdidas o Deterioro 20.
SELECT TOP (10) r.claim_type, COUNT(*) AS complaints
FROM   mart.fact_complaint AS c
JOIN   mart.dim_brand      AS b ON b.brand_key  = c.brand_key
JOIN   mart.dim_reason     AS r ON r.reason_key = c.reason_key
WHERE  b.in_dashboard_scope = 1
GROUP BY r.claim_type
ORDER BY complaints DESC;

-- ---------------------------------------------------------------------
-- P5 Monthly complaints of Total Play, 2024 and 2025 (filing month)
-- ---------------------------------------------------------------------
-- Expected: 2024 between 27 and 62 a month (579 in the year); 2025: January 59,
-- February 51, March 40, April 166, May 128, June 109, July 100, August 72,
-- September 76, October 68, November 45, December 103 (1,017 in the year).
SELECT d.year_month, COUNT(*) AS complaints
FROM   mart.fact_complaint AS c
JOIN   mart.dim_brand      AS b ON b.brand_key    = c.brand_key
JOIN   mart.dim_operator   AS o ON o.operator_key = c.operator_key
JOIN   mart.dim_date       AS d ON d.date_key     = c.filing_date_key
WHERE  b.in_dashboard_scope = 1
  AND  o.operator_name = N'Total Play'
  AND  d.year_num IN (2024, 2025)
GROUP BY d.year_month
ORDER BY d.year_month;

-- ---------------------------------------------------------------------
-- P6 Total Play, April to July: 2025 against 2024, by claim type
-- ---------------------------------------------------------------------
-- Expected (2025 / 2024): Contratos 209 / 84; Cobro Indebido 201 / 51; Entrega del
-- Producto o Servicio 70 / 51; Cambios, Devoluciones o Bonificaciones 19 / 7; Trato
-- o Servicio al Cliente 3 / 2; Publicidad, Ofertas y Promociones 1 / 5. Total 503 / 200:
-- Contratos and Cobro Indebido explain 275 of the 303 cases of increase (91%).
-- Technique: conditional aggregation puts both years side by side without a self-join.
SELECT r.claim_type,
       SUM(CASE WHEN d.year_num = 2025 THEN 1 ELSE 0 END) AS cases_2025,
       SUM(CASE WHEN d.year_num = 2024 THEN 1 ELSE 0 END) AS cases_2024
FROM   mart.fact_complaint AS c
JOIN   mart.dim_brand      AS b ON b.brand_key    = c.brand_key
JOIN   mart.dim_operator   AS o ON o.operator_key = c.operator_key
JOIN   mart.dim_date       AS d ON d.date_key     = c.filing_date_key
JOIN   mart.dim_reason     AS r ON r.reason_key   = c.reason_key
WHERE  b.in_dashboard_scope = 1
  AND  o.operator_name = N'Total Play'
  AND  d.year_num IN (2024, 2025)
  AND  d.month_num BETWEEN 4 AND 7
GROUP BY r.claim_type
ORDER BY cases_2025 DESC;

-- ---------------------------------------------------------------------
-- P7 Row counts of the pipeline against the values of the README
-- ---------------------------------------------------------------------
-- Expected: every row shows status OK. If one shows ERROR, a script of the
-- pipeline was not run completely or the source files are not the ones of the
-- project (docs/sources/ has their SHA-256).
-- Technique: UNION ALL of one count per object, with the expected value written next to
-- it, so the whole check is read at once.
SELECT t.object_name, t.rows_found, t.rows_expected,
       CASE WHEN t.rows_found = t.rows_expected THEN 'OK' ELSE 'ERROR' END AS status
FROM (
    SELECT 'stg.profeco_raw'          AS object_name, COUNT(*) AS rows_found, 36034  AS rows_expected FROM stg.profeco_raw
    UNION ALL SELECT 'clean.profeco_complaint',  COUNT(*), 36034  FROM clean.profeco_complaint
    UNION ALL SELECT 'mart.fact_complaint',      COUNT(*), 36034  FROM mart.fact_complaint
    UNION ALL SELECT 'stg.bit_acc_baf',          COUNT(*), 592281 FROM stg.bit_acc_baf
    UNION ALL SELECT 'clean.bit_access',         COUNT(*), 592281 FROM clean.bit_access
    UNION ALL SELECT 'mart.fact_accesses',       COUNT(*), 19840  FROM mart.fact_accesses
    UNION ALL SELECT 'mart.dim_date',            COUNT(*), 5113   FROM mart.dim_date
    UNION ALL SELECT 'mart.dim_state',           COUNT(*), 33     FROM mart.dim_state
    UNION ALL SELECT 'mart.dim_operator',        COUNT(*), 5      FROM mart.dim_operator
    UNION ALL SELECT 'mart.dim_brand',           COUNT(*), 190    FROM mart.dim_brand
    UNION ALL SELECT 'mart.dim_reason',          COUNT(*), 176    FROM mart.dim_reason
    UNION ALL SELECT 'mart.dim_outcome',         COUNT(*), 39     FROM mart.dim_outcome
    UNION ALL SELECT 'mart.v_duration_cases',    COUNT(*), 12833  FROM mart.v_duration_cases
) AS t
ORDER BY t.object_name;