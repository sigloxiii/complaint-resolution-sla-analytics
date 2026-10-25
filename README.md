![complaint-resolution-sla-analytics banner](assets/main.banner.png)

# complaint-resolution-sla-analytics

> SQL Server + Power BI analysis of complaint resolution times against service-level targets, by responsible party and region, built on open government data. Source-agnostic star schema with per-source ingestion adapters.

![License](https://img.shields.io/badge/License-MIT-yellow) ![Data](https://img.shields.io/badge/Data-PROFECO_%2B_BIT_M%C3%A9xico-blue) ![Status](https://img.shields.io/badge/Status-Phase_0_feasibility_gate-orange)

---

## Author

**Eng. Rafael Cansigno Peláez** ([@sigloxiii](https://github.com/sigloxiii)): telecommunications engineer transitioning into data analytics.

This is my second portfolio project, following the Google Data Analytics certificate capstone: [ftth-qos-qoe-risk-framework](https://github.com/sigloxiii/ftth-qos-qoe-risk-framework). All design decisions, scripts and findings in this repository are documented under my authorship.

---

## Learning objectives

1. Build a layered **SQL Server** pipeline (`stg` → `clean` → `mart`) with documented, re-runnable T-SQL scripts.
2. Clean real-world open data: type conversion, inconsistent date formats, negative durations, and provider-name normalization through a mapping table.
3. Apply **dimensional modeling**: define the grain, build a star schema and a role-playing date dimension.
4. Build a **Power BI** semantic model: relationships, DAX measures (percentiles, rates per 100k) and a report, with results cross-checked against SQL.
5. Define SLA-style metrics, run a sensitivity analysis on the targets, and communicate limitations honestly.
6. Design the model to be **source-agnostic**, so the same mart and report can be reused with a different dataset.
7. Follow professional repository practices: Git workflow, English documentation, and awareness of data licensing.

---

## Business questions

**Core question:** How long do complainants wait for a resolution, which responsible parties and regions are slowest, and how has this changed over time?

| # | Question | Main metrics |
|---|---|---|
| BQ1 | How long do complaints take to close, by responsible party, region and category? | Median and P90 of days to close |
| BQ2 | Which responsible parties and regions have the worst outcomes? | Conciliation rate, recovered / claimed amount |
| BQ3 | How does complaint volume compare once normalized by customer base? | Complaints per 100,000 subscribers |
| BQ4 | How have these indicators evolved over the period? | Trend and seasonality |
| BQ5 | How do results compare with published benchmarks? | Contextual comparison with regulator reports |

**Out of scope:** network technical quality (latency, jitter, packet loss). The complaint data measures consumer-protection conciliation, not network performance.

**SLA targets:** the conciliation process has no official service-level target. Targets are therefore treated as **parameters** and evaluated with a sensitivity analysis. The grid will be defined after profiling the data.

---

## Approach

The pipeline is layered, and only the first two layers depend on the data source.

```
raw CSV  →  stg (text, as loaded)  →  clean (typed, normalized)  →  mart (star schema)  →  Power BI (Import)
```

| Phase | Description | Status |
|---|---|---|
| 0 | Repository scaffold and feasibility gate on the Mexican dataset | In progress |
| 1 | Create database and schemas; load raw data into `stg` | Pending |
| 2 | Clean and normalize: types, durations, provider mapping | Pending |
| 3 | Load denominators (subscribers) and build dimensions | Pending |
| 4 | Build the `mart` star schema; SQL validation queries | Pending |
| 5 | Power BI model, DAX measures and report | Pending |
| 6 | Documentation, findings and limitations | Pending |

**Planned star schema:** `fact_complaint` (one row per case), `fact_subscribers` (provider × state × quarter), `dim_provider`, `dim_state`, `dim_reason`, `dim_date`.

---

## Initial dataset exploration: México

Desk research on the candidate sources is complete. Row-level profiling is part of the feasibility gate and is **pending**.

### Candidate sources

| Source | Grain | Role in the project |
|---|---|---|
| PROFECO telecommunications complaints (datos.gob.mx) | One row per complaint case | **Primary fact source** |
| BIT, Telecommunications Information Bank (CRT) | Quarterly, by operator / state / technology | Denominators (subscribers) |
| "Soy Usuario" quarterly reports (IFT/CRT) | Aggregated, PDF | Cross-validation of results |
| Fixed-service quality guidelines (IFT, 2020) | Regulatory thresholds | Context for benchmarks |
| Ookla Open Data / M-Lab (optional) | Tiles / test records | Optional technical layer |

### PROFECO field map (from the published data dictionary)

| Field | Meaning |
|---|---|
| `ID_EXP` | Case identifier in the dataset |
| `FECHA_INGRESO`, `FECHA_FIN` | Filing date and date the procedure ended (basis for days to close) |
| `ESTADO_PROCESAL` | Outcome or status (conciliated, not conciliated, withdrawn, in progress, etc.) |
| `PROVEEDOR` | Provider legal name |
| `ESTADO_UA` | State of the PROFECO office that received the complaint |
| `TIPO_RECLAMACION`, `MOTIVO_RECLAMACION` | Complaint type and sub-reason |
| `RECLAMADO`, `RECUPERADO` | Amount claimed and amount recovered |
| `MEDIO_INGRESO` | Filing channel |

The published file contains additional columns not listed above. The staging schema will follow the real CSV header.

### Known caveats (identified before profiling)

- **Provider names vary** between records (for example, with and without the corporate suffix), so a normalization mapping table is required.
- **Date format:** the data dictionary documents `dd-mm-yyyy`, but sample rows show `yyyy/mm/dd`. All dates are loaded as text and converted with `TRY_CONVERT`, and conversion failures are audited.
- **Retroactive updates:** the publisher warns that historical data may change. A frozen copy and the download date will be recorded.
- **Two published versions** exist (2022–2025 and 2022–2026). Which one to use, and how they overlap, will be confirmed during the gate.
- **Metric meaning:** days to close measures the duration of the PROFECO conciliation procedure, not the provider's repair time. Only complaints that reach PROFECO are recorded (self-selection bias).

### Feasibility gate

The Mexican dataset is used only if all criteria are met.

| # | Criterion | Result |
|---|---|---|
| 1 | At least 2,000 fixed-internet complaint rows | Pending |
| 2 | Missing `FECHA_FIN` below 30% among finished cases | Pending |
| 3 | Main providers (Telmex, Megacable, Izzi, Totalplay) with at least 100 cases per year | Pending |
| 4 | Subscribers by operator and state downloadable from BIT | Pending |

Evidence from the gate will be stored in `docs/` regardless of the outcome.

---

## Fallback: US datasets

If the Mexican data fails the gate, the project pivots to a US open dataset **without redesigning the pipeline**. The leading candidate is the NYC 311 Service Requests dataset from [NYC Open Data](https://opendata.cityofnewyork.us/), which has creation and closing dates, agency, complaint type and borough.

| Stays the same | Changes |
|---|---|
| Canonical `mart` schema and star model | Source adapters in `sql/sources/us_nyc311/` |
| Scripts in `sql/common/` | Responsible party = agency |
| DAX measure structure and report layout | Region = borough |
| Business questions BQ1, BQ3 (adapted), BQ4 | Normalization by population instead of subscribers |
| Documentation structure | No "recovered amount" metric, so BQ2 changes |

The reasons for any pivot will be documented in `docs/`.

---

## Tech stack

- SQL Server 2025 Express and SSMS 22 (T-SQL)
- Power BI Desktop (Import mode)
- Git and GitHub, with VS Code for version control

---

## Repository structure

```
assets/      # banner and other static images
data/        # raw/ and interim/ are not versioned; reference/ holds small seed files
sql/
  common/    # source-agnostic: database, schemas, mart, views
  sources/   # per-source adapters (stg → clean)
powerbi/     # .pbix and PDF report
docs/        # source notes, decisions, executive brief
```

---

## Data sources and licenses

To be completed during the gate: source URL, license, download date and attribution for each dataset. The code in this repository is MIT-licensed. **The data keeps the license of its original publisher.**

---

## How to reproduce

To be completed once the pipeline is implemented.

---

## Results and findings

To be completed.

---

## Limitations

To be completed. The caveats listed above will be expanded with the results of profiling.

---

## License

Code and documentation are released under the [MIT License](LICENSE).