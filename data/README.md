# Data

This folder holds the project data. **Raw and intermediate files are not versioned** (see `.gitignore`), so `raw/` and `interim/` are created locally and do not appear in GitHub.

| Folder | Content | Versioned |
|---|---|---|
| `raw/` | Source files exactly as downloaded, with their original names. PROFECO CSV files at the top level; BIT files in `raw/bit/baf/` (broadband) and `raw/bit/tf/` (telephony) | No |
| `interim/` | Intermediate files, if any are needed | No |
| `reference/` | Small files created by the project, if any (the provider mapping lives in SQL: `clean.brand_map`) | Yes |

## Rules

- Raw files are never edited. Mark them as read-only after downloading them.
- Every download is recorded in `docs/sources/` (URL, date, size and file identity).
- The data keep the license of their original publisher. Only aggregated results are published, with source and date (decision D10, see `docs/sources/licenses.md`).
- The SQL scripts read the files from `data/raw/`. `BULK INSERT` is executed by the SQL Server service, so that service account needs read permission on the folder (see `sql/mx_profeco/step_1.sql`).