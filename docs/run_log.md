# Run log

Record of each script execution on the local instance (SQL Server 2025 Express, SSMS 22), with its evidence. Source-specific results of the feasibility gate are also summarized in `docs/sources/MX_profeco.md`.

| Step | Script | Date | Result |
|---|---|---|---|
| 0 | `sql/common/step_0.sql` | 2026-10-25 (confirm) | Done |
| 1 | `sql/mx_profeco/step_1.sql` | | Pending |
| 2 | `sql/mx_profeco/step_2.sql` | | Pending |

## Step 0: database and schemas

![Step 0 results in SSMS](img/step_0_results.png)

What the evidence shows:

- The instance is `(local)\SQLEXPRESS`, SQL Server version 17.0 (SQL Server 2025), and the query finished with the message "Consulta ejecutada correctamente".
- The database `complaint_sla` exists and its collation is `Modern_Spanish_CI_AI`.
- The three schemas `clean`, `mart` and `stg` exist (they also appear under *Seguridad → Esquemas* in the Object Explorer).

Note: the editor shows three error markers (IntelliSense). The execution was successful, so they are probably warnings caused by the editor parsing the script before the objects existed. To be confirmed in the SSMS *Error List*.

## Step 1: raw load

To be completed after running `step_1.sql` (expected: 36,034 rows in `stg.profeco_raw`).

## Step 2: feasibility gate profiling

To be completed after running `step_2.sql`.