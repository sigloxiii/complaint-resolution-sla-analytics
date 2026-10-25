# SQL scripts

SQL Server scripts that build the pipeline `stg → clean → mart` inside the database `complaint_sla`.

## Layout

```
sql/
  common/              # source-agnostic scripts (database, schemas, mart)
  sources/
    mx_profeco/        # scripts specific to one data source (load, profile, clean)
```

- `common/` contains what is reused whatever the dataset is.
- `sources/<source_id>/` contains what changes per source: loading the raw file into `stg` and cleaning it into `clean`.

## Conventions

- Scripts are named `step_N.sql`. The number follows the **execution order across folders**.
- Every script starts with a header: objective, source, prerequisites and how to run it.
- Every step is explained with inline comments, and the SQL is kept simple on purpose.
- Layers:
  - `stg`: raw data exactly as loaded, all as text. It is never modified. (Storage)
  - `clean`: the same data with correct types and normalized values.    (Cleaning)
  - `mart`: final tables prepared for Power BI.

## Execution order

| Order | Script | Purpose |
|---|---|---|
| 0 | `common/step_0.sql` | Create the database, its collation and the three schemas |
| 1 | `sources/mx_profeco/step_1.sql` | Load the raw PROFECO complaints CSV into `stg.profeco_raw` |
| 2 | `sources/mx_profeco/step_2.sql` | Feasibility gate profiling (read-only queries) |

## Requirements

- SQL Server 2025 Express (instance `.\SQLEXPRESS`) and SSMS 22.
- Raw files stored in `data/raw/<source>/`. These folders are not versioned; see `docs/sources/` for where each file comes from.