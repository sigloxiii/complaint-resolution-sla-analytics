# SQL scripts

SQL Server scripts that build the pipeline `stg → clean → mart` inside the database `complaint_sla`.

## Layout

```
sql/
  common/        # source-agnostic scripts (database, schemas, mart)
  mx_profeco/    # scripts specific to one data source (load, profile, clean)
  mx_bit/        # the BIT denominators source (load, clean)
```

- `common/` contains what is reused whatever the dataset is.
- `<source_id>/` (for example `mx_profeco/`, and `us_nyc311/` if the project migrates) contains what changes per source: loading the raw file into `stg` and cleaning it into `clean`.
- The repository keeps a maximum depth of two folders, so there are no deeper subfolders.

## Conventions

- Scripts are named `step_N.sql`. The number follows the **execution order across folders**.
- Every script starts with a header: objective, source, prerequisites and how to run it.
- Every step is explained with inline comments, and the SQL is kept simple on purpose.
- Layers:
  - `stg`: raw data exactly as loaded, all as text. It is never modified.
  - `clean`: the same data with correct types and normalized values.
  - `mart`: final tables prepared for Power BI.

## Execution order

| Order | Script | Purpose |
|---|---|---|
| 0 | `common/step_0.sql` | Create the database, its collation and the three schemas |
| 1 | `mx_profeco/step_1.sql` | Load the raw PROFECO complaints CSV into `stg.profeco_raw` |
| 2 | `mx_profeco/step_2.sql` | Feasibility gate profiling (read-only queries) |
| 3 | `mx_profeco/step_3.sql` | Clean layer: `clean.profeco_complaint`, brand and state lookup tables, quality flags |
| 4 | `mx_profeco/step_4.sql` | Overlap audit of the five PROFECO cuts (decision D4); audit tables in `stg`, read-only for the pipeline |
| 5 | `mx_bit/step_5.sql` | Load the BIT fixed broadband accesses (`TD_ACC_BAF_ITE_VA`) into `stg.bit_acc_baf` |
| 6 | `mx_bit/step_6.sql` | Clean layer of the BIT: `clean.bit_access` (types, date, state code, operator, flags) |

## Requirements

- SQL Server 2025 Express (instance `.\SQLEXPRESS`) and SSMS 22.
- Raw files stored in `data/raw/`. This folder is not versioned; see `docs/sources/` for where each file comes from.