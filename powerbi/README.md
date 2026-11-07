# Power BI

This folder holds the build guide and the PDF export of the report. The report file (`.pbix`) stays local.

**Status:** in progress. The `mart` layer (`sql/common/step_7.sql`, D14) and the validation queries of the measures (`sql/common/step_8.sql`, D15) are done. The step-by-step guide, the DAX measures and the SQL reference values are in [`build_guide.md`](build_guide.md).

## Plan

- Connection: Import mode to the `mart` tables of the database `complaint_sla` (instance `.\SQLEXPRESS`).
- Model: star schema, with the relationships defined in Power BI.
- Business measures in DAX (for example median and P90 days to close, and complaints per 100,000 accesses).
- Planned pages:
  1. Overview (KPIs)
  2. Resolution time by provider
  3. Map by state
  4. Complaint reasons
  5. Trend over time
  6. Data quality and limitations

## Notes

- A `.pbix` file in Import mode **contains the imported data**, including row-level complaints and monthly BIT accesses, which is finer than the aggregates allowed by D10. So the `.pbix` is not versioned (`*.pbix` in `.gitignore`, decision D16) and only the PDF and the screenshots are published.
- Every report page carries the source citations and the non-endorsement notice of `docs/sources/licenses.md`.
- Screenshots of the report go to `docs/img/` and are named `powerbi_<name>.png`.
- Power BI temporary files (`.pbi/`) are ignored by Git.