# Decision log

Each entry records the context, the options considered, the decision and the reason. Dates are `YYYY-MM-DD`.

| ID | Decision | Status |
|---|---|---|
| D1 | Data source: México (PROFECO) or US (NYC 311) | Open |
| D2 | Clean the data in SQL instead of Power Query | Accepted |
| D3 | Repository name and design | Accepted |
| D4 | Choice of the base CSV cut | Provisional |
| D5 | Layered architecture (medallion-lite) and ELT | Accepted |
| D6 | Load the CSV with a script instead of the SSMS wizard | Accepted |

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

## D2. Clean the data in SQL instead of Power Query

- **Status:** Accepted
- **Date:** 2026-10-25
- **Context:** The raw data are dirty: placeholders such as `-` and `sin dato`, inconsistent capitalization, cancelled cases without provider and five cuts published by hand. Power Query was used to explore them and showed these problems clearly. The question is where the cleaning rules should live.
- **Options:**
  - A. Power Query inside Power BI (M language).
  - B. Layered T-SQL in SQL Server (`stg` → `clean` → `mart`).
  - C. Python.
- **Decision:** B. SQL Server 2025 Express with SSMS 22. Power BI connects in Import mode to the `mart` tables. The database collation is `Modern_Spanish_CI_AI` (case- and accent-insensitive; "ñ" stays distinct from "n"). Power Query is kept only for exploration and quick profiling.
- **Why SQL and not Power Query:**
  1. **Versioning and review:** SQL scripts are text files in Git, with history and comments. Power Query steps live inside the `.pbix`, a binary file that is hard to review.
  2. **Raw data preserved:** the source is loaded untouched into `stg`, so any rule can be changed and re-run. With Power Query the only original is the file on disk.
  3. **Reuse and migration:** per-source scripts (`sql/<source_id>/`) and a shared mart allow switching to a US dataset without rebuilding the report.
  4. **Separation of roles:** SQL prepares the data and Power BI models and visualizes it. A new report can reuse the same clean tables.
  5. **Validation:** row counts can be reconciled between layers with simple queries.
  6. **Learning goal:** the author targets Data Engineering roles, where SQL pipelines are a core skill.
- **Trade-offs accepted:** a steeper learning curve (the author's SQL level is basic, so the scripts are kept simple and heavily commented), SQL Server is required, and Power Query is faster for a first look at the data (so it is still used for that).
- **Option C discarded:** it adds another tool without a benefit at this volume (about 36,000 rows).

---

## D3. Repository name and design

- **Status:** Accepted (may be changed later if needed)
- **Date:** 2026-10-25
- **Decision:** the repository is named `complaint-resolution-sla-analytics`. The design separates `sql/common/` (source-agnostic) from `sql/<source_id>/` (per-source adapters). The repository keeps a maximum depth of two folders.
- **Options discarded:** names tied to a country, institution, sector or tool (for example `mx-telecom-complaints-sla`, `nyc311-service-sla`).
- **Reason:** the name and structure stay valid if the project migrates from México to a US dataset.

---

## D4. Choice of the base CSV cut

- **Status:** Provisional
- **Date:** 2026-10-25
- **Context:** datos.gob.mx publishes five CSV cuts of the same dataset (evidence in `docs/sources/MX_profeco.md`). They were updated by hand and there is **no standard methodology** behind them: the file names follow different patterns, the row counts do not grow with time, one cut seems to use a cut-off date as the close date, and text capitalization differs. The portal does not explain how each cut was produced and reports a last update on 2026-09-22.
- **Options:**
  - A. One of the five cuts as the only source.
  - B. A deduplicated union of all five cuts. Postponed: more complexity before knowing whether the source is viable.
- **Selection criteria** (defined by the project, because the publisher gives none):
  1. Integrity: unique case ID and no type errors in the dates.
  2. Coverage: widest date range and highest volume.
  3. Plausibility: close dates vary (they are not a single cut-off date).
  4. Consistency with the other cuts: overlapping cases agree (overlap audit, pending).
  5. Traceability: name, size, date and hash of the file are recorded.
- **Decision:** use `quejas_telecomunicaciones_2022_junio_2026.csv` as the base for the gate. The other four cuts are kept for audit only.
- **Reason:** it is the only cut that meets criteria 1 to 3 with evidence (see the comparison in `docs/sources/MX_profeco.md`).
- **Revisit if:** the overlap audit shows differences between cuts, the newest cut (probably `jul2026`) turns out to be a corrected republication, or the gate fails.

---

## D5. Layered architecture (medallion-lite) and ELT

- **Status:** Accepted
- **Date:** 2026-10-25
- **Context:** the data must move from a dirty file to a model that Power BI can use, in a way that can be repeated and audited. The layered pattern known as **medallion architecture** (bronze, silver, gold) fits this need. It improves the structure and quality of the data step by step, and the sources used for this decision describe it as a recommended practice, not a requirement.
- **Mapping to this project:**

| Medallion layer | Schema | Role |
|---|---|---|
| Bronze | `stg` | Faithful copy of the file. Everything is text. No filters or transformations |
| Silver | `clean` | Correct types, standardized text, placeholders as `NULL`, quality flags |
| Gold | `mart` | Star schema for analysis and Power BI |

- **Why "lite":** the pattern is usually applied in lakehouses, with separate storage per layer and table formats such as Delta. Here the three layers are schemas inside one SQL Server database, with no streaming, no incremental loads and no data lake. The idea is the same (raw → clean → business-ready) with a much simpler implementation.
- **Rules kept from the pattern:** bronze is never modified, silver is always built from bronze (never directly from the file) and gold is built from silver.
- **ELT instead of ETL:**
  - ETL transforms the data before loading it (for example in Power Query or Python), and the database receives only the result.
  - ELT loads the raw data first and transforms it inside the database.
  - **Decision:** ELT.
  - **Reasons:** the raw data stay available, so a rule can change and be re-run without downloading anything again. Dirty values do not block the load, because everything enters as text. Every rule is a SQL script in Git. The database engine does the work, and the volume is small.
  - **Cost:** the raw data exist twice (file and `stg`), which is irrelevant at this size.
- **References:** see the list at the end of the README.

---

## D6. Load the CSV with a script instead of the SSMS wizard

- **Status:** Accepted
- **Date:** 2026-10-25
- **Context:** SSMS includes the *Import Flat File* wizard, which loads a CSV with a few clicks. The project needs the load to be repeatable, because up to five cuts may be loaded and reloaded.
- **Options:**
  - A. SSMS *Import Flat File* wizard.
  - B. `BULK INSERT` script (`sql/mx_profeco/step_1.sql`).
- **Decision:** B.
- **Reasons:**
  1. **Reproducible:** the same script gives the same result every time. The wizard depends on manual clicks that nobody records.
  2. **Versioned and documented:** the script lives in Git with comments that explain each option.
  3. **Controlled types:** every column is created as text, which is the bronze rule. The wizard proposes types guessed from a sample, which can convert or reject values such as dates or dashes in amount columns.
  4. **Reusable:** loading another cut only needs a different file path.
- **Costs:** the file must be readable by the SQL Server service account (permission errors are possible) and the column order must match the CSV exactly. The wizard remains acceptable for a quick, throwaway look at a file.