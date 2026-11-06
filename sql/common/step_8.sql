-- =====================================================================
-- step_8.sql  |  Validation queries of the measures (read-only on the mart)
-- =====================================================================
-- Objective   : profile the resolution time (BQ1), the outcomes (BQ2) and the
--               service-level grid before the DAX measures are written. The
--               numbers of this step are the reference to cross-check Power BI.
-- Source      : mart tables of step_7.sql. Only the view of 8.2 is created.
-- Prerequisites: steps 0 to 7 executed.
-- How to run  : run it block by block (select the block, press F5).
--               Save a capture of each check as docs/img/step_8_check_NN.png.
--
-- Population of the duration measures (proposal, confirmed or changed by D15):
--   * brands of fixed broadband (dim_brand.in_dashboard_scope = 1), D11
--   * the four operators of dim_operator.is_main_operator = 1
--   * procedure group "Conciliation" (Queja and the other legal procedures are
--     not a conciliation, see docs/sources/MX_profeco.md)
--   * valid duration: filing and close date, close not before filing, not cancelled
--   * time axis of the duration and of the outcomes: the FILING year (cohort), the
--     same axis as the volume and the rates (decision D15). It is complete for 2022
--     to 2024; 2025 has an incomplete tail and 2026 is partial (right-censoring: the
--     file has only closed cases). The CLOSE year is not the main axis because the
--     file has no case filed before 2022, so the close years 2022 and 2023 miss the
--     long cases (left-truncation). Checks 8.4 and 8.7 (close year) are kept as the
--     comparison; 8.8 and 8.9 (filing year) are the reference values for Power BI.
-- =====================================================================

USE complaint_sla;
GO

-- ---------------------------------------------------------------------
-- 8.1 Which complaints have a usable duration? (before the view exists)
-- ---------------------------------------------------------------------
-- Expected: in total 36,034 rows and 35,961 with valid duration (step 3). Fixed
-- brands (in_dashboard_scope = 1) are 13,358 rows. n_valid_and_batch_day counts the
-- cases closed on the batch-closing day (flag_unusual_close_day).
-- Technique: conditional aggregation (SUM(CASE WHEN ...)) counts several conditions in one
-- pass over the table.
SELECT b.in_dashboard_scope, ou.procedure_group,
       COUNT(*)                                       AS n_complaints,
       SUM(CAST(f.flag_valid_duration AS INT))        AS n_valid_duration,
       SUM(CASE WHEN f.flag_valid_duration = 1 AND f.flag_unusual_close_day = 1
                THEN 1 ELSE 0 END)                    AS n_valid_and_batch_day
FROM   mart.fact_complaint AS f
JOIN   mart.dim_brand      AS b  ON b.brand_key    = f.brand_key
JOIN   mart.dim_outcome    AS ou ON ou.outcome_key = f.outcome_key
GROUP BY b.in_dashboard_scope, ou.procedure_group
ORDER BY b.in_dashboard_scope DESC, ou.procedure_group;

-- ---------------------------------------------------------------------
-- 8.2 View with the population of the duration measures
-- ---------------------------------------------------------------------
-- (run it right after 8.1: the next checks read it)
GO
-- Technique: a view holds the population once, so every check below uses the same rules.
CREATE OR ALTER VIEW mart.v_duration_cases AS
SELECT f.complaint_key,
       o.operator_name,
       o.sort_order              AS operator_sort,
       o.is_main_operator,
       b.brand,
       fd.year_num               AS filing_year,
       cd.year_num               AS close_year,
       f.days_to_close,
       ou.outcome,
       f.flag_unusual_close_day
FROM   mart.fact_complaint AS f
JOIN   mart.dim_operator   AS o  ON o.operator_key = f.operator_key
JOIN   mart.dim_brand      AS b  ON b.brand_key    = f.brand_key
JOIN   mart.dim_outcome    AS ou ON ou.outcome_key = f.outcome_key
JOIN   mart.dim_date       AS fd ON fd.date_key    = f.filing_date_key
JOIN   mart.dim_date       AS cd ON cd.date_key    = f.close_date_key
WHERE  b.in_dashboard_scope = 1
  AND  f.flag_valid_duration = 1
  AND  ou.procedure_group = N'Conciliation';
GO

-- ---------------------------------------------------------------------
-- 8.3 Batch-closing day: are those cases different?
-- ---------------------------------------------------------------------
-- If the cases closed on the batch day have much longer durations, they would
-- distort the P90 and need a decision. Compare average and maximum days.
SELECT operator_name, flag_unusual_close_day,
       COUNT(*)                                          AS n_cases,
       CAST(AVG(CAST(days_to_close AS FLOAT)) AS DECIMAL(9,1)) AS avg_days,
       MAX(days_to_close)                                AS max_days
FROM   mart.v_duration_cases
WHERE  is_main_operator = 1
GROUP BY operator_name, operator_sort, flag_unusual_close_day
ORDER BY operator_sort, flag_unusual_close_day;

-- ---------------------------------------------------------------------
-- 8.4 Median and P90 of days to close, by operator and CLOSE year (comparison)
-- ---------------------------------------------------------------------
-- Technique: PERCENTILE_CONT exists in SQL Server only as a window function, so DISTINCT
-- keeps one row per group; a derived table wraps it so the outer SELECT can sort
-- (CROSS APPLY (VALUES ...) repeats each case for the totals). "All years" has year = NULL; the outer SELECT sorts (with DISTINCT, ORDER BY can only
-- use columns of the select list). The two CROSS APPLY repeat every case for the group
-- "All four operators" and for "All years".
SELECT operator_group, close_year, n_cases, median_days, p90_days, mean_days
FROM (
SELECT DISTINCT
       gg.grp                                            AS operator_group,
       gg.grp_sort,
       yy.yr                                             AS close_year,
       COUNT(*) OVER (PARTITION BY gg.grp, yy.yr)        AS n_cases,
       CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY v.days_to_close)
            OVER (PARTITION BY gg.grp, yy.yr) AS DECIMAL(9,1)) AS median_days,
       CAST(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY v.days_to_close)
            OVER (PARTITION BY gg.grp, yy.yr) AS DECIMAL(9,1)) AS p90_days,
       CAST(AVG(CAST(v.days_to_close AS FLOAT))
            OVER (PARTITION BY gg.grp, yy.yr) AS DECIMAL(9,1)) AS mean_days
FROM   mart.v_duration_cases AS v
CROSS APPLY (VALUES (v.operator_name, v.operator_sort),
                    (N'All four operators', 9)) AS gg(grp, grp_sort)
CROSS APPLY (VALUES (v.close_year), (CAST(NULL AS SMALLINT))) AS yy(yr)
WHERE  v.is_main_operator = 1
) AS t
ORDER BY grp_sort, ISNULL(close_year, 0);

-- ---------------------------------------------------------------------
-- 8.5 Right-censoring: the same measures by FILING year (four operators)
-- ---------------------------------------------------------------------
-- Result (2026-11-05): P90 169, 161, 130, 118 and 75 days for the filing years 2022 to
-- 2026, and a maximum that falls with the age of the cohort: only the cases already
-- closed are in the file. 2022 to 2024 are complete enough; 2025 and 2026 are not.
-- Technique: window functions with DISTINCT (see 8.4); here the groups are the filing years.
SELECT DISTINCT
       v.filing_year,
       COUNT(*) OVER (PARTITION BY v.filing_year)        AS n_cases,
       CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY v.days_to_close)
            OVER (PARTITION BY v.filing_year) AS DECIMAL(9,1)) AS median_days,
       CAST(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY v.days_to_close)
            OVER (PARTITION BY v.filing_year) AS DECIMAL(9,1)) AS p90_days,
       MAX(v.days_to_close) OVER (PARTITION BY v.filing_year) AS max_days
FROM   mart.v_duration_cases AS v
WHERE  v.is_main_operator = 1
ORDER BY v.filing_year;

-- ---------------------------------------------------------------------
-- 8.6 Service-level grid: % of cases closed within N days (all close years)
-- ---------------------------------------------------------------------
-- Candidate targets: 30, 60, 90, 120 and 180 days. The conciliation process has no
-- official target, so the targets are parameters (README). D15 keeps these five
-- values as the grid, with 60 days as the default.
-- Technique: conditional aggregation, and CROSS APPLY (VALUES ...) to add the row of
-- "All four operators" without a second query.
SELECT gg.grp AS operator_group,
       COUNT(*) AS n_cases,
       CAST(100.0 * SUM(CASE WHEN v.days_to_close <=  30 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS pct_within_30,
       CAST(100.0 * SUM(CASE WHEN v.days_to_close <=  60 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS pct_within_60,
       CAST(100.0 * SUM(CASE WHEN v.days_to_close <=  90 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS pct_within_90,
       CAST(100.0 * SUM(CASE WHEN v.days_to_close <= 120 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS pct_within_120,
       CAST(100.0 * SUM(CASE WHEN v.days_to_close <= 180 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS pct_within_180
FROM   mart.v_duration_cases AS v
CROSS APPLY (VALUES (v.operator_name, v.operator_sort),
                    (N'All four operators', 9)) AS gg(grp, grp_sort)
WHERE  v.is_main_operator = 1
GROUP BY gg.grp, gg.grp_sort
ORDER BY gg.grp_sort;

-- ---------------------------------------------------------------------
-- 8.7 Outcomes and conciliation rate by operator and CLOSE year (comparison)
-- ---------------------------------------------------------------------
-- Population: fixed brands, four operators, procedure group Conciliation, cases
-- with a close date (it does not need a valid duration).
--   rate_all         = Conciliada / (cases with a valid outcome)         <- recommended
--   rate_no_withdraw = Conciliada / (Conciliada + No Conciliada)
-- "other" = Cancelada or an outcome that is not valid or is missing.
-- Technique: as 8.4 (window functions, derived table, CROSS APPLY); the rate divides two
-- windowed sums, so it is calculated on the group and not row by row.
SELECT operator_group, close_year, n_cases, n_conciliada, n_no_conciliada, n_desistimiento,
       n_improcedente, n_other, rate_all, rate_no_withdraw
FROM (
SELECT DISTINCT
       gg.grp                                            AS operator_group,
       gg.grp_sort,
       yy.yr                                             AS close_year,
       COUNT(*) OVER (PARTITION BY gg.grp, yy.yr)        AS n_cases,
       SUM(CASE WHEN x.outcome = N'Conciliada'    THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr) AS n_conciliada,
       SUM(CASE WHEN x.outcome = N'No Conciliada' THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr) AS n_no_conciliada,
       SUM(CASE WHEN x.outcome = N'Desistimiento' THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr) AS n_desistimiento,
       SUM(CASE WHEN x.outcome = N'Improcedente'  THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr) AS n_improcedente,
       SUM(CASE WHEN x.outcome IN (N'Conciliada', N'No Conciliada', N'Desistimiento', N'Improcedente')
                THEN 0 ELSE 1 END) OVER (PARTITION BY gg.grp, yy.yr)                                   AS n_other,
       CAST(100.0 * SUM(CASE WHEN x.outcome = N'Conciliada' THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr)
            / NULLIF(SUM(CASE WHEN x.outcome IN (N'Conciliada', N'No Conciliada', N'Desistimiento', N'Improcedente')
                              THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr), 0) AS DECIMAL(5,1)) AS rate_all,
       CAST(100.0 * SUM(CASE WHEN x.outcome = N'Conciliada' THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr)
            / NULLIF(SUM(CASE WHEN x.outcome IN (N'Conciliada', N'No Conciliada')
                              THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr), 0) AS DECIMAL(5,1)) AS rate_no_withdraw
FROM (
    SELECT o.operator_name, o.sort_order AS operator_sort, ou.outcome, cd.year_num AS close_year
    FROM   mart.fact_complaint AS f
    JOIN   mart.dim_operator   AS o  ON o.operator_key = f.operator_key
    JOIN   mart.dim_brand      AS b  ON b.brand_key    = f.brand_key
    JOIN   mart.dim_outcome    AS ou ON ou.outcome_key = f.outcome_key
    JOIN   mart.dim_date       AS cd ON cd.date_key    = f.close_date_key
    WHERE  b.in_dashboard_scope = 1 AND o.is_main_operator = 1
      AND  ou.procedure_group = N'Conciliation'
) AS x
CROSS APPLY (VALUES (x.operator_name, x.operator_sort),
                    (N'All four operators', 9)) AS gg(grp, grp_sort)
CROSS APPLY (VALUES (x.close_year), (CAST(NULL AS SMALLINT))) AS yy(yr)
) AS t
ORDER BY grp_sort, ISNULL(close_year, 0);
-- ---------------------------------------------------------------------
-- 8.8 Median and P90 of days to close, by operator and FILING year (BQ1, BQ4)
-- ---------------------------------------------------------------------
-- Reference values for the DAX measures (D15). Complete for 2022 to 2024; 2025 has an
-- incomplete tail and 2026 is partial. "All years" has year = NULL.
-- Technique: as 8.4, with the filing year as the axis.
SELECT operator_group, filing_year, n_cases, median_days, p90_days, mean_days
FROM (
SELECT DISTINCT
       gg.grp                                            AS operator_group,
       gg.grp_sort,
       yy.yr                                             AS filing_year,
       COUNT(*) OVER (PARTITION BY gg.grp, yy.yr)        AS n_cases,
       CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY v.days_to_close)
            OVER (PARTITION BY gg.grp, yy.yr) AS DECIMAL(9,1)) AS median_days,
       CAST(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY v.days_to_close)
            OVER (PARTITION BY gg.grp, yy.yr) AS DECIMAL(9,1)) AS p90_days,
       CAST(AVG(CAST(v.days_to_close AS FLOAT))
            OVER (PARTITION BY gg.grp, yy.yr) AS DECIMAL(9,1)) AS mean_days
FROM   mart.v_duration_cases AS v
CROSS APPLY (VALUES (v.operator_name, v.operator_sort),
                    (N'All four operators', 9)) AS gg(grp, grp_sort)
CROSS APPLY (VALUES (v.filing_year), (CAST(NULL AS SMALLINT))) AS yy(yr)
WHERE  v.is_main_operator = 1
) AS t
ORDER BY grp_sort, ISNULL(filing_year, 0);

-- ---------------------------------------------------------------------
-- 8.9 Outcomes and conciliation rate by operator and FILING year (BQ2)
-- ---------------------------------------------------------------------
-- Same population as 8.7 (fixed brands, four operators, procedure group Conciliation,
-- cases with a close date), with the filing year as axis (D15).
--   rate_all         = Conciliada / (Conciliada + No Conciliada + Desistimiento + Improcedente)
--   rate_no_withdraw = Conciliada / (Conciliada + No Conciliada)
-- Technique: as 8.7, with the filing year as the axis.
SELECT operator_group, filing_year, n_cases, n_conciliada, n_no_conciliada, n_desistimiento,
       n_improcedente, n_other, rate_all, rate_no_withdraw
FROM (
SELECT DISTINCT
       gg.grp                                            AS operator_group,
       gg.grp_sort,
       yy.yr                                             AS filing_year,
       COUNT(*) OVER (PARTITION BY gg.grp, yy.yr)        AS n_cases,
       SUM(CASE WHEN x.outcome = N'Conciliada'    THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr) AS n_conciliada,
       SUM(CASE WHEN x.outcome = N'No Conciliada' THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr) AS n_no_conciliada,
       SUM(CASE WHEN x.outcome = N'Desistimiento' THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr) AS n_desistimiento,
       SUM(CASE WHEN x.outcome = N'Improcedente'  THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr) AS n_improcedente,
       SUM(CASE WHEN x.outcome IN (N'Conciliada', N'No Conciliada', N'Desistimiento', N'Improcedente')
                THEN 0 ELSE 1 END) OVER (PARTITION BY gg.grp, yy.yr)                                   AS n_other,
       CAST(100.0 * SUM(CASE WHEN x.outcome = N'Conciliada' THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr)
            / NULLIF(SUM(CASE WHEN x.outcome IN (N'Conciliada', N'No Conciliada', N'Desistimiento', N'Improcedente')
                              THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr), 0) AS DECIMAL(5,1)) AS rate_all,
       CAST(100.0 * SUM(CASE WHEN x.outcome = N'Conciliada' THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr)
            / NULLIF(SUM(CASE WHEN x.outcome IN (N'Conciliada', N'No Conciliada')
                              THEN 1 ELSE 0 END) OVER (PARTITION BY gg.grp, yy.yr), 0) AS DECIMAL(5,1)) AS rate_no_withdraw
FROM (
    SELECT o.operator_name, o.sort_order AS operator_sort, ou.outcome, fd.year_num AS filing_year
    FROM   mart.fact_complaint AS f
    JOIN   mart.dim_operator   AS o  ON o.operator_key = f.operator_key
    JOIN   mart.dim_brand      AS b  ON b.brand_key    = f.brand_key
    JOIN   mart.dim_outcome    AS ou ON ou.outcome_key = f.outcome_key
    JOIN   mart.dim_date       AS fd ON fd.date_key    = f.filing_date_key
    WHERE  b.in_dashboard_scope = 1 AND o.is_main_operator = 1
      AND  ou.procedure_group = N'Conciliation'
      AND  f.close_date_key IS NOT NULL
) AS x
CROSS APPLY (VALUES (x.operator_name, x.operator_sort),
                    (N'All four operators', 9)) AS gg(grp, grp_sort)
CROSS APPLY (VALUES (x.filing_year), (CAST(NULL AS SMALLINT))) AS yy(yr)
) AS t
ORDER BY grp_sort, ISNULL(filing_year, 0);
-- =====================================================================