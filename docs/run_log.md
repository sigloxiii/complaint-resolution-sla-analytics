# Run log

Record of each script execution on the local instance (SQL Server 2025 Express, SSMS 22), with its evidence. Source-specific results of the feasibility gate are also summarized in `docs/sources/MX_profeco.md`.

| Step | Script | Date | Result |
|---|---|---|---|
| 0 | `sql/common/step_0.sql` | 2026-10-25 (confirm) | Done |
| 1 | `sql/mx_profeco/step_1.sql` | 2026-10-26 | Done (second attempt, see incident) |
| 2 | `sql/mx_profeco/step_2.sql` | | Pending |

## Step 0: database and schemas

![Step 0 results in SSMS](img/step_0_results.png)

What the evidence shows:

- The instance is `(local)\SQLEXPRESS`, SQL Server version 17.0 (SQL Server 2025), and the query finished with the message "Consulta ejecutada correctamente".
- The database `complaint_sla` exists and its collation is `Modern_Spanish_CI_AI`.
- The three schemas `clean`, `mart` and `stg` exist (they also appear under *Seguridad → Esquemas* in the Object Explorer).

Note: the editor shows three error markers (IntelliSense). The execution was successful, so they are probably warnings caused by the editor parsing the script before the objects existed. To be confirmed in the SSMS *Error List*.

## Step 1: raw load

### Incident: error 7301 on the first attempt

![Error 7301 in SSMS](img/step_1_error_7301.png)

The first run failed with: *"Cannot obtain the required interface ('IID_IColumnsInfo') from OLE DB provider 'BULK' for linked server '(null)'"* (message 7301). The table `stg.profeco_raw` was created, but no rows were loaded.

The file was inspected as plain text with `OPENROWSET(BULK ..., SINGLE_CLOB)`:

![Line-ending diagnostic](img/step_1_diagnostic_line_endings.png)

| Check | Result | Meaning |
|---|---|---|
| `header_columns` | 23 | Same number of columns as the table |
| `has_CR` | 0 | Lines end with LF only, not CR+LF |
| `n_line_breaks` | 36,035 | 1 header + 36,034 rows, as expected |
| `n_double_quotes` | 4,292 | Even number, so no unclosed quotes |

**Cause:** the file uses LF line endings, and `BULK INSERT` with `FORMAT = 'CSV'` expects CR+LF by default (see *LF and CR+LF* in [`glossary_of_terms.md`](glossary_of_terms.md)).
**Fix:** `ROWTERMINATOR = '0x0a'` was added to the `WITH` list of `step_1.sql`.

### Result

![Step 1 results in SSMS](img/step_1_results.png)

What the evidence shows:

- `stg.profeco_raw` contains **36,034 rows**, the same count that Power Query showed.
- The first rows have each value in its own column (case ID, dates, outcome, provider, brand, state).
- Dates arrive as text with the year first and dashes (for example `2022-01-03`). This confirms the assumption made in `step_2.sql`.
- Accents load correctly (for example *México*, *Teléfonos*, *Telefonía*), so `CODEPAGE = '65001'` works.

## Step 2: feasibility gate profiling

To be completed after running `step_2.sql`.