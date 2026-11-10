# Power BI

This folder holds the build guide and the PDF export of the report. The report file (`.pbix`) stays local.

**Status:** done. The report has six pages and is exported to [`complaint_sla_report.pdf`](complaint_sla_report.pdf). The `mart` layer (`sql/common/step_7.sql`, D14) and the validation queries of the measures (`sql/common/step_8.sql`, D15) are done. The step-by-step guide, the DAX measures and the SQL reference values are in [`build_guide.md`](build_guide.md).

## Plan

- Connection: Import mode to the `mart` tables of the database `complaint_sla` (instance `.\SQLEXPRESS`).
- Model: star schema, with the relationships defined in Power BI.
- Business measures in DAX (for example median and P90 days to close, and complaints per 100,000 accesses).
- Pages of the report:
  1. Overview (KPIs and complaints by month)
  2. Resolution time (median, P90 and `% Within SLA` with a target parameter)
  3. Outcomes (conciliation rate and withdrawal share)
  4. Complaints and accesses (rate per 100,000 accesses, 2022 to 2024)
  5. Reasons and offices (top 10 claim types and PROFECO offices)
  6. Data quality and limits

## Notes

- A `.pbix` file in Import mode **contains the imported data**, including row-level complaints and monthly BIT accesses, which is finer than the aggregates allowed by D10. So the `.pbix` is not versioned (`*.pbix` in `.gitignore`, decision D16) and only the PDF and the screenshots are published.
- Every report page carries the source citations and the non-endorsement notice of `docs/sources/licenses.md`.
- Screenshots of the report go to `docs/img/` and are named `powerbi_<name>.png`.
- Power BI temporary files (`.pbi/`) are ignored by Git.