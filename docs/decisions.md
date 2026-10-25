# Decision log

Each entry records the context, the options considered, the decision and the reason. Dates are `YYYY-MM-DD`.

---

## D1. Data source: México (PROFECO) or US (NYC 311)

- **Status:** Open. The provisional choice is México, subject to the feasibility gate.
- **Date:** 2026-10-25
- **Context:** The project analyzes complaint resolution times against service-level targets. A México telecom dataset fits the author's domain. NYC 311 is the US fallback, with larger volume but less domain fit.
- **Options:**
  - A. PROFECO complaints + BIT subscribers (México).
  - B. NYC 311 Service Requests (US).
  - C. Telecom SLA with synthetic or FCC MBA data. Discarded: no public real SLA data, and FCC MBA was already used in the first capstone.
- **Gate criteria (fixed before running `step_2.sql`):**
  1. At least 2,000 complaints against fixed-network operators (Telmex, Izzi, Megacable, Total Play). This is a provider-level proxy, because the dataset has no service-type column.
  2. Missing `fecha_cierre` below 30%.
  3. Each of those four operators with at least 100 complaints per year (2026 is partial).
  4. Subscribers by operator and state downloadable from BIT.
- **Decision rule:** if all four criteria are met, proceed with México. If any criterion fails, document the evidence in `docs/` and migrate to NYC 311. If a criterion fails narrowly, record the margin and revisit the scope before pivoting.
- **Evidence:** pending (`step_2.sql` results and BIT check).

---

## D2. Pipeline and tools

- **Status:** Accepted
- **Date:** 2026-10-25
- **Context:** The raw data are dirty (placeholders, inconsistent text, cancelled cases) and the work must be reproducible.
- **Options:**
  - A. Clean in Power Query inside Power BI.
  - B. Layered T-SQL in SQL Server (`stg` → `clean` → `mart`).
  - C. Python.
- **Decision:** B. SQL Server 2025 Express with SSMS 22. Power BI connects in Import mode to the `mart` tables. Power Query is used only for exploration. The database collation is `Modern_Spanish_CI_AI` (case- and accent-insensitive; "ñ" stays distinct from "n").
- **Reason:** versioned and auditable scripts, a source-agnostic mart that survives a change of dataset, and a lighter Power BI file.

---

## D3. Repository name and design

- **Status:** Accepted (may be changed later if needed)
- **Date:** 2026-10-25
- **Decision:** the repository is named `complaint-resolution-sla-analytics`. The design separates `sql/common/` (source-agnostic) from `sql/<source_id>/` (per-source adapters). The repository keeps a maximum depth of two folders.
- **Options discarded:** names tied to a country, institution, sector or tool (for example `mx-telecom-complaints-sla`, `nyc311-service-sla`).
- **Reason:** the name and structure stay valid if the project migrates from México to a US dataset.

---

## D4. Provisional base file

- **Status:** Provisional
- **Date:** 2026-10-25
- **Decision:** use `quejas_telecomunicaciones_2022_junio_2026.csv` as the base file for the gate.
- **Options:**
  - `jul2026`: discarded for now (suspicious constant close date and fewer rows).
  - Deduplicated union of all five cuts: postponed, more complexity before knowing whether the source is viable.
- **Reason:** largest volume (36,034 rows), unique `expediente`, 0.18% of rows without close date and close dates up to 2026-05-29.
- **Review:** after comparing the overlap between cuts. The other four files are used for audit only. The portal reports a last update on 2026-09-22 (see `docs/sources/MX_profeco.md`, evidence E1), so the newest cut (probably `jul2026`) must be understood before this choice becomes final.