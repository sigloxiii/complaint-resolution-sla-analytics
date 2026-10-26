# Data

This folder holds the project data. **Raw and intermediate files are not versioned** (see `.gitignore`), so `raw/` and `interim/` are created locally and do not appear in GitHub.

| Folder | Content | Versioned |
|---|---|---|
| `raw/` | Source files exactly as downloaded, with their original names | No |
| `interim/` | Intermediate files, if any are needed | No |
| `reference/` | Small files created by the project, for example the provider mapping | Yes |

## Rules

- Raw files are never edited. Mark them as read-only after downloading them.
- Every download is recorded in `docs/sources/` (URL, date, size and file identity).
- The data keep the license of their original publisher. Derived files are published only if that license allows it.
- The SQL scripts read the files from `data/raw/`. `BULK INSERT` is executed by the SQL Server service, so that service account needs read permission on the folder (see `sql/mx_profeco/step_1.sql`).