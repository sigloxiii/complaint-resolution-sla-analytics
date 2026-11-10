# Executive summary

**Project:** complaint-resolution-sla-analytics | **Author:** Eng. Rafael Cansigno Peláez | **Español:** [`resumen_ejecutivo.md`](resumen_ejecutivo.md)

## Objective

Measure how long consumers wait for a resolution of their complaints against fixed broadband providers in México, which providers are slowest and how this changed over time, using open government data. PROFECO, the consumer protection agency, has no official service-level target for the conciliation process, so the targets are treated as parameters and evaluated with a sensitivity analysis.

## Data and method

- **Sources:** 36,034 telecommunications complaints from PROFECO (CC BY 4.0) and 592,281 rows of fixed broadband accesses from the CRT's BIT, used as denominators.
- **Pipeline:** SQL Server in three layers (`stg` → `clean` → `mart`), with documented and re-runnable T-SQL scripts, quality flags instead of deleted rows and a star schema with two fact tables (complaints and accesses) and six dimensions.
- **Report:** Power BI (Import mode) with 26 DAX measures, each one validated against an independent SQL query, and a six-page report.
- **Scope:** 13,358 fixed broadband complaints; 12,833 conciliation cases with a valid duration for the time and outcome results. The time axis is the filing year (2022 to 2024 are complete cohorts).

## Main findings

1. **Telmex is the slowest operator:** median 70 days to close and P90 of 225, against medians of 24 to 35 days for Megacable, Total Play and Izzi. Within 60 days close 44% of Telmex cases and 71% to 81% of the others.
2. **Three claim types hold 92.5% of the complaints:** improper charges, delivery of the product or service, and contracts.
3. **The conciliation rate falls from 68.1% (2022) to 60.2% (2025)**, driven by withdrawals, which grow from 24.8% to 34.8% of the cases. Among decided cases the share stays near 91%.
4. **Speed and outcome do not go together:** Telmex is the slowest but has a 67.7% conciliation rate; Total Play closes fast and has the lowest rate (60.2%).
5. **Complaints per 100,000 accesses fall from 16.60 (2022) to 9.33 (2024)** at national level.
6. **Total Play had a spike in April to July 2025** (503 cases against 200 a year earlier), 91% of it in two claim types. The data do not show the cause.

## Limitations

Only closed cases are in the file, so recent months are incomplete; the state is the PROFECO office and not the consumer's location (58% of the complaints appear in Ciudad de México); the rate per 100,000 accesses is national and limited to 2022 to 2024; the duration is that of the PROFECO procedure, not the provider's repair time; and the results describe associations, not causes. The BIT has no explicit license, so only aggregates are published.

## Deliverables

| Item | Location |
|---|---|
| Report (6 pages, PDF) | `powerbi/complaint_sla_report.pdf` |
| SQL pipeline (steps 0 to 8) | `sql/` |
| Decisions D1 to D16, run log with evidence | `docs/decisions.md`, `docs/run_log.md` |
| Data dictionary and glossary | `data/data_dictionary.md`, `docs/glossary_of_terms.md` |
| Full README with reproduction steps | `README.md` ([Español](../README.es.md)) |

## Skills shown

Layered SQL pipeline and data cleaning; dimensional modeling; DAX (measures, filter context, inactive relationships, parameter tables); validation of every measure against SQL; honest treatment of censoring and data limitations; documentation of decisions and licensing.