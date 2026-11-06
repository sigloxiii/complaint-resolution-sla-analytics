# Run log

Record of each script execution on the local instance (SQL Server 2025 Express, SSMS 22), with its evidence. Source-specific results of the feasibility gate are also summarized in `docs/sources/MX_profeco.md`.

| Step | Script | Date | Result |
|---|---|---|---|
| 0 | `sql/common/step_0.sql` | 2026-10-25 | Done |
| 1 | `sql/mx_profeco/step_1.sql` | 2026-10-26 | Done (second attempt, see incident) |
| 2 | `sql/mx_profeco/step_2.sql` | 2026-10-26 | Done (gate passed on 2026-10-27) |
| 3 | `sql/mx_profeco/step_3.sql` | 2026-10-27 | Run 1 done (checks 1 to 13); revision 2 done (checks 14 to 17) |
| 4 | `sql/mx_profeco/step_4.sql` | 2026-10-31 | Done (checks 4.1 to 4.11); D4 accepted |
| 5 | `sql/mx_bit/step_5.sql` | 2026-11-01 | Done (592,281 rows loaded; checks 5.0 to 5.8) |
| 6 | `sql/mx_bit/step_6.sql` | 2026-11-01 | Done (`clean.bit_access`, 592,281 rows; checks 6.1 to 6.6b); D12 and D13 accepted |
| 7 | `sql/common/step_7.sql` | 2026-11-05 | Done (mart: 6 dimensions, 2 facts; checks 7.3a to 7.3f); D14 accepted |

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

Status: done. The script is read-only (SELECT). Results are summarized in `docs/sources/MX_profeco.md`; this section records what was run and what changed in the script.

| Block | Topic | Status |
|---|---|---|
| 2.1 to 2.7 | Row count, unique ID, date format and range, missing close date, close before filing | Done. 2.2: 2 IDs differ only in case and belong to different providers (not duplicates) |
| 2.8 | Type of service (checks A to I) | Done. See *Type of service* in `docs/sources/MX_profeco.md` and decision D7. The columns `sector`, `procedimiento`, `medio_ingreso` and `tipo_conciliacion` were also reviewed |
| 2.9 to 2.14 | Provider names, gate criteria 1 and 3, batch closings, amounts, cancelled cases | Done. Gate criteria 1 to 3 passed |
| 2.15, 2.16 | Values in the wrong column (`clase`), explanation of missing close dates, amounts | Done. `clase` and `medio_ingreso` are swapped in 430 rows (all from 2022) |
| 2.17 | Length of `procedimiento` values; `tipo_conciliacion` and `procedimiento` against `estado_procesal` | Done. `procedimiento` labels are cut at 30 characters in part of the rows; `En Proceso` is not an open case |

Changes made to `step_2.sql` while running it:

- **Block 2.8 rewritten.** It was written as a search for a service column. It became a test of the hypothesis that no such column exists, with checks A to I.
- **Brand variants.** Check A showed that "Totalplay" (1,816) and "Total Play" (1,531) are the same company. The brand lists of blocks 2.10 and 2.11 now include both spellings. This is the first case for the provider mapping table of the clean layer.
- **Result.** `giro` is not the service of the complaint, and `problema_especial` names a service in 27.2% of the rows, with uneven coverage (decision D7).
- **`clase` and `tipo_producto`** do not hold the telecom service. D7 moved from Provisional to Accepted.
- **New block 2.15** added to the script: `clase` holds 430 values that belong to `medio_ingreso` (Internet, Personal, Escrito, Correo Electrónico). The block checks if the two columns were swapped and in which years it happens.
- **New block 2.17** added to the script. It showed that `En Proceso` rows have final outcomes (so it is not an open case) and that 62 rows of `procedimiento` are legal procedures that are not a conciliation.

## Feasibility gate result (2026-10-27)

All four criteria passed, so decision D1 is accepted (México). Criterion 4 was checked by hand on the BIT downloads (`TD_ACC_BAF_ITE_VA`, pivot table in Excel); the details are in `docs/sources/MX_profeco.md`. Next: `step_3.sql` (clean layer).

## Step 3: clean layer

### Run 1

The script creates `clean.brand_map`, `clean.state_map` and `clean.profeco_complaint` (36,034 rows). Checks 3.3.1 to 3.3.11 matched the expected values. The evidence is `docs/img/step_3_check_01.png` to `step_3_check_13.png` (check 6 has `06p1` and `06p2`), and the table with the results is in `docs/sources/MX_profeco.md`, section *Results of the clean layer*.

Two checks were added after the first run and gave findings that changed the design:

- **Check 3.3.12 (state):** the state is the PROFECO office that handled the case, and the Internet channel is handled by one central office in Ciudad de México (decision D8).
- **Check 3.3.13 (amounts):** the claimed amount is 0 in 78% of the rows and the recovered amount exceeds the claimed one in 24% (decision D9).

### Revision 2 (run on 2026-10-29)

Changes in `step_3.sql`, from the results of checks 3.3.6, 3.3.12 and 3.3.13:

- `clean.brand_map` has new categories: Fixed (Axtel, Gigacable, Telecable, Newww, Starlink), Mobile (Bait), Pay TV (satellite) (Sky, Dish) and Device maker (Samsung, Motorola, Apple, Xiaomi, ZTE, Huawei, Honor, Oppo, Alcatel, LG, Hisense).
- `clean.profeco_complaint` has three new columns: `office_code` (from the case ID), `office_name` (`odeco`) and `flag_central_office` (office `H`).
- New checks: 3.3.14 (office H and channel), 3.3.15 (brands by category), 3.3.16 (meaning of `odeco`) and 3.3.17 (is the state always the state of the office?).

Results (images `step_3_check_14.png` to `step_3_check_17.png` and the new `step_3_check_06p1.png` and `06p2.png`, details in `docs/sources/MX_profeco.md`):

- Office `H` has 19,798 cases and 99.2% of the Internet channel (19,607 of 19,772); the other 165 Internet cases are spread over 31 states.
- Brands by category add up to 36,034: Mobile 18,231 (5 brands), Fixed 13,358 (9 brands), Pay TV (satellite) 2,101, Device maker 1,243 (11 brands) and Not classified 1,101 (163 brands).
- `odeco` is the name of the office (zone). Office `H` has two names, "Dir. Gral. Cons. Telecom" (16,016) and "Dgpct" (3,782).

- Of the 16,236 cases not handled by `H`, 16,221 (99.9%) have the main state of their office and 15 have another one (check 3.3.17). The Fixed category now has 9 brands and 13,358 cases (check 6, part 1).

The revision 2 is finished.

## Step 5: BIT load (`sql/mx_bit/step_5.sql`, 2026-11-01)

Loads `TD_ACC_BAF_ITE_VA.csv` (downloaded 2026-10-26) into `stg.bit_acc_baf` as text. Evidence: `step_5_check_00.png` to `step_5_check_08p2.png`; the results are summarized in `docs/sources/MX_profeco.md`.

- **File layout found by the probe (5.0):** comma separator, text with commas in double quotes, lines ending in CR+LF (`0x0d0a`), accents correct with code page 1252, and **two empty extra columns** at the end of every line (`,,`). The staging table has two helper columns that are checked empty (`n_not_empty` = 0) and dropped.
- **Load:** 592,281 rows, the same as Excel.
- **Checks:** years 2013 to 2024 and months 1 to 12; no bad year, month or state; December 2024 matches the Excel pivots (the four groups 27,809,589); 33 state codes; the companies of each group reproduce the pivots.
- **Corrections to the checks:** 5.3 used a collation that ignores accents, so every row looked "broken" (fixed with a binary collation, result 0); 5.6 did not filter by group, so it showed 1,051,366 accesses without state for all operators (35,990 for the four groups, as expected).
- **Missing accesses (5.8):** 1,831 rows (0.31%) have an empty `a_total_e` (NULL, not text). 1,462 belong to the four groups, mainly 2015 to 2016 and 2020 (804 rows). In the period of the rates there are 33 rows in 2022, 12 in 2023 and none in 2024.

## Step 6: BIT clean layer (`sql/mx_bit/step_6.sql`, 2026-11-01)

Builds `clean.bit_access` from `stg.bit_acc_baf`: types, date, state code and name, operator of each row and flags. No row is deleted. Evidence: `step_6_check_01p1.png` to `step_6_check_09.png`; the results are in `docs/sources/MX_profeco.md`.

- **Grain:** the first run of check 6.2a gave 36,562 repeated keys (expected 0). Checks 6.2c to 6.2h showed that the repeated rows are mostly different records (same concessionaire and technology, very different accesses), that only 325 rows are exact copies, and that the repetition is the same in November and December 2024. All rows are kept and the copies are flagged (D12).
- **Technology:** no filter in the denominators (D13).
- **Result:** 592,281 rows, 1,831 with missing accesses, 9,078 without state, 13,247 without municipality, 325 exact copies, 0 without date. December 2024 reproduces the totals of step 5.
- **Script changes while running it:** the old blocks 6.2c to 6.2f were replaced by 6.2c to 6.2h, column `flag_exact_copy` added to 6.4, and the technology check of the four operators renamed 6.6b.

## Step 7: mart layer (`sql/common/step_7.sql`, 2026-11-05)

Builds the star schema in `mart` from `clean.profeco_complaint` and `clean.bit_access` (decision D14). Evidence: `step_7_check_01.png` to `step_7_check_08.png`.

| Check | Result | Evidence |
|---|---|---|
| 7.0 to 7.2 Build | Rows inserted: `dim_date` 5,113; `dim_state` 33; `dim_operator` 5; `dim_brand` 190; `dim_reason` 176; `dim_outcome` 39; `fact_complaint` 36,034; `fact_accesses` 19,840. The two warnings are NULL values ignored by `MAX` and `SUM` (empty accesses and unmapped groups) | ![7.0](img/step_7_check_01.png) |
| 7.3a Rows | Same counts as the messages | ![7.3a](img/step_7_check_02.png) |
| 7.3b Reconciliation | Complaints 36,034 in `clean` and `mart`; BIT rows 592,281 in both; difference in accesses 0 | ![7.3b](img/step_7_check_03.png) |
| 7.3c December 2024 | Telmex 11,208,977; Izzi 5,619,403; Megacable 5,316,545; Total Play 5,313,779 (as in 6.5b); Other 1,544,536 | ![7.3c](img/step_7_check_04.png) |
| 7.3d Keys | 0 complaints without filing date key; 66 without close date key, the same 66 as `flag_missing_close`; 0 orphan brands | ![7.3d](img/step_7_check_05.png) |
| 7.3e Complaints by filing year | The file has no filing year before 2022. Fixed broadband totals: 2022 4,101; 2023 2,965; 2024 2,591; 2025 2,959; 2026 742 (partial year) | ![7.3e](img/step_7_check_06.png) |
| 7.3f Rate per 100,000 accesses | See the table below | ![7.3f](img/step_7_check_07.png) |
| 7.3g Service hint by operator | Fixed brands filed 2022 to 2024: 9,588 complaints (Telmex 1,803; Izzi 2,607; Megacable 3,012; Total Play 2,166; the counts match 7.3e). "Not specified" is 98.8%, 89.4%, 75.3% and 78.9%. Mobile telephony: 14 complaints (0.15%). Where the hint exists, Megacable has 513 Internet against 221 Television or Telephony, and Izzi 125 against 143 | ![7.3g](img/step_7_check_08.png) |

Preview of the rates (complaints filed in the year, fixed broadband brands, divided by the accesses of December; national level):

| Operator | 2022 | 2023 | 2024 |
|---|---|---|---|
| Telmex | 8.61 | 5.02 | 3.68 |
| Izzi | 15.25 | 16.01 | 14.08 |
| Megacable | 33.20 | 18.38 | 14.67 |
| Total Play | 20.96 | 13.74 | 10.90 |

Notes:

- The values were recalculated by hand from the counts and denominators of the checks and match.
- The numerator is every complaint of the brand, while the denominator is fixed broadband accesses only. Check 7.3g shows almost no mobile complaints (14 of 9,588), so no filter is needed, but the complaints include television and fixed telephony. The rate is read as **complaints about the fixed services of the operator per 100,000 of its broadband accesses**, with the broadband accesses as a proxy of its customer base. The hint covers only 1% to 25% of the rows, so the share of other services cannot be measured.
- Megacable's 2022 rate is the least comparable: its denominator has no technology in December 2022 and grows 28% in two years (see D13).
- Total Play has 1,017 complaints filed in 2025 against 579 in 2024. There are no BIT accesses for 2025, so it has no rate.