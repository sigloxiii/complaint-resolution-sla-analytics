# Power BI

This folder will hold the report (`.pbix`) and its PDF export.

**Status:** not started. The report is built after the `mart` layer exists (see the phases in the root README).

## Plan

- Connection: Import mode to the `mart` tables of the database `complaint_sla` (instance `.\SQLEXPRESS`).
- Model: star schema, with the relationships defined in Power BI.
- Business measures in DAX (for example median and P90 days to close, and complaints per 100,000 subscribers).
- Planned pages:
  1. Overview (KPIs)
  2. Resolution time by provider
  3. Map by state
  4. Complaint reasons
  5. Trend over time
  6. Data quality and limitations

## Notes

- A `.pbix` file in Import mode **contains the imported data**. It is published only if the license of the source allows it; otherwise only the PDF is published.
- Screenshots of the report go to `docs/img/` and are named `powerbi_<name>.png`.
- Power BI temporary files (`.pbi/`) are ignored by Git.