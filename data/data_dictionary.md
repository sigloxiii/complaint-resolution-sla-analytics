# Data dictionary

List and description of every table and view of the database `complaint_sla` (instance `.\SQLEXPRESS`), in the order in which the scripts create them. The database has three schemas, one per layer of the pipeline (`stg` → `clean` → `mart`); the layers are explained in the README and the choices behind them are in `docs/decisions.md`.

| Schema | Layer | What it holds | Rule |
|---|---|---|---|
| `stg` | Staging (raw) | The source files as they arrive, every column as text | Never edited; kept to audit and to reload |
| `clean` | Clean | Typed, normalized rows with quality flags | Rows are flagged, not deleted (the KPI decides what to exclude) |
| `mart` | Presentation | Star schema read by Power BI | Only keys, measures' inputs and the dimensions' attributes |

## Overview

| # | Table or view | Schema | Created by | Grain (one row per…) | Rows |
|---|---|---|---|---|---|
| 1 | `stg.profeco_raw` | stg | `step_1.sql` | complaint, as in the CSV | 36,034 |
| 2 | `clean.brand_map` | clean | `step_3.sql` | brand text as written in the file | lookup |
| 3 | `clean.state_map` | clean | `step_3.sql` | state text as written in the file | lookup |
| 4 | `clean.profeco_complaint` | clean | `step_3.sql` | complaint | 36,034 |
| 5 | `stg.profeco_cut_load` | stg | `step_4.sql` | complaint (temporary landing table, one file at a time) | temporary |
| 6 | `stg.profeco_cuts` | stg | `step_4.sql` | complaint, per cut of the PROFECO file | audit |
| 7 | `stg.bit_probe` | stg | `step_5.sql` | text line of the BIT file (probe of the first lines) | 4 |
| 8 | `stg.bit_acc_baf` | stg | `step_5.sql` | BIT row, as in the CSV | 592,281 |
| 9 | `clean.bit_access` | clean | `step_6.sql` | BIT row (month × state × municipality × company × technology) | 592,281 |
| 10 | `mart.dim_date` | mart | `step_7.sql` | calendar day | 5,113 |
| 11 | `mart.dim_state` | mart | `step_7.sql` | state (32 states + code 99 "no information") | 33 |
| 12 | `mart.dim_operator` | mart | `step_7.sql` | operator (4 main + Other) | 5 |
| 13 | `mart.dim_brand` | mart | `step_7.sql` | normalized brand | 190 |
| 14 | `mart.dim_reason` | mart | `step_7.sql` | claim type × claim reason | 176 |
| 15 | `mart.dim_outcome` | mart | `step_7.sql` | outcome × conciliation type × procedure group | 39 |
| 16 | `mart.fact_complaint` | mart | `step_7.sql` | complaint | 36,034 |
| 17 | `mart.fact_accesses` | mart | `step_7.sql` | month × state × operator | 19,840 |
| 18 | `mart.v_duration_cases` (view) | mart | `step_8.sql` | complaint of the duration population | 12,833 |

## Lineage

```
PROFECO CSV ─► stg.profeco_raw ─┐
                                ├─► clean.profeco_complaint ─► mart.dim_* + mart.fact_complaint ─┐
clean.brand_map, clean.state_map┘                                                                │
                                                                                                  ├─► Power BI (Import)
BIT CSV ─► stg.bit_acc_baf ─► clean.bit_access ─► mart.fact_accesses (+ mart.dim_*) ─────────────┘
```

## Layer `stg` (staging)

| Table | Description |
|---|---|
| `stg.profeco_raw` | The PROFECO complaints file loaded with `BULK INSERT` (UTF-8, LF line ends). 23 text columns in the same order as the CSV (`expediente`, `fecha_ingreso`, `fecha_cierre`, `estado_procesal`, `nombre_comercial`, `estado`, `tipo_reclamacion`, amounts, …). Text on purpose: a dirty value loads without error and is inspected in SQL. |
| `stg.profeco_cut_load` | Temporary landing table of `step_4.sql`: each of the older cuts of the PROFECO file is loaded here and then copied to `stg.profeco_cuts`. |
| `stg.profeco_cuts` | The cuts of the PROFECO file loaded together, with the column `source_file`. Audit table that supports decision D4 (how the file changes between cuts). |
| `stg.bit_probe` | One text column (`line`) with the first lines of the BIT file, to read its format (separator, code page, line ends) before the real load. |
| `stg.bit_acc_baf` | The BIT fixed-broadband accesses file (`TD_ACC_BAF_ITE_VA`) loaded as 18 text columns: the 16 of the file plus `extra_1` and `extra_2`, the two empty columns that every line has at its end. |

## Layer `clean` (typed and normalized)

| Table | Description |
|---|---|
| `clean.brand_map` | Lookup: brand text of the file (`brand_raw`) → normalized `brand`, `operator_group` (name of the group in the BIT) and `network_type` (Fixed, Mobile, Pay TV (satellite), Device maker, Not classified). Fixed vs mobile comes from this table, not from each complaint (D7, D11). |
| `clean.state_map` | Lookup: state text (`state_raw`) → INEGI `state_code` and normalized `state_name`. Also used by the BIT. |
| `clean.profeco_complaint` | One row per complaint with real types (dates, `days_to_close`, amounts as `DECIMAL`), the normalized brand and state, the PROFECO office (`office_code`, `office_name`) and the quality flags. Key: `complaint_key`. |
| `clean.bit_access` | One row per BIT row with real types, `period_date` (first day of the month), `operator` (Telmex, Izzi, Megacable, Total Play or Other), the `accesses` stock and the quality flags. Key: `access_key`. |

Flags of `clean.profeco_complaint` (`1` = true; the row is kept and each KPI chooses what to exclude):

| Flag | Meaning |
|---|---|
| `flag_missing_close` | No close date |
| `flag_close_before_filing` | Close date earlier than the filing date |
| `flag_cancelled` | Outcome = Cancelada |
| `flag_swapped_columns` | `clase` and `medio_ingreso` were swapped in the file and fixed |
| `flag_shared_case_id` | The same `case_id` appears for more than one provider (D4) |
| `flag_outcome_anomaly` | The outcome text is not a valid outcome |
| `flag_unusual_close_day` | More than 100 cases closed on that date (possible batch closing) |
| `flag_valid_duration` | `days_to_close` can be used in the duration KPIs |
| `flag_central_office` | Handled by the central office (office H): the state is not where the consumer lives (D8) |

Flags of `clean.bit_access`: `flag_missing_accesses` (the file has no value), `flag_no_state` (state code 99), `flag_no_municipality` (municipality code 999) and `flag_exact_copy` (surplus copy of a row identical in all 16 columns, D12).

## Layer `mart` (star schema, decision D14)

Two fact tables share three dimensions (`dim_date`, `dim_state`, `dim_operator`); three dimensions belong to the complaints only. There is no relationship between the two facts.

**Dimensions**

| Table | Key | Main attributes | Notes |
|---|---|---|---|
| `mart.dim_date` | `date_key` (yyyymmdd) | `date_value`, `year_num`, `quarter_num`, `month_num`, `month_name`, `year_month`, `is_month_start`, `is_december` | Role-playing in Power BI: filing date (active) and close date (inactive) |
| `mart.dim_state` | `state_key` | `state_code`, `state_name` | In the complaints it is the PROFECO office state (D8) |
| `mart.dim_operator` | `operator_key` | `operator_name`, `bit_group`, `is_main_operator`, `sort_order` | `bit_group` is the denominator of the rates; `is_main_operator` = the four operators of D11 |
| `mart.dim_brand` | `brand_key` | `brand`, `network_type`, `bit_group`, `in_dashboard_scope` | `in_dashboard_scope` = 1 for fixed broadband; the other brands stay so the totals reconcile with `clean` |
| `mart.dim_reason` | `reason_key` | `claim_type`, `claim_reason` | Used by page 5 |
| `mart.dim_outcome` | `outcome_key` | `outcome`, `conciliation_type`, `procedure_group` | `procedure_group` = Conciliation, Queja, Other legal procedure or Not identified |

**Facts**

| Table | Foreign keys | Measures and attributes | Notes |
|---|---|---|---|
| `mart.fact_complaint` | `filing_date_key`, `close_date_key`, `state_key`, `operator_key`, `brand_key`, `reason_key`, `outcome_key` | `case_id`, `days_to_close`, `claimed_amount`, `recovered_amount` (descriptive only, D9), `channel`, `service_hint` (partial, D7), `office_code` and the flags `flag_valid_duration`, `flag_cancelled`, `flag_missing_close`, `flag_close_before_filing`, `flag_shared_case_id`, `flag_unusual_close_day`, `flag_central_office` | Same key as `clean.profeco_complaint`; all 36,034 rows |
| `mart.fact_accesses` | `period_date_key`, `state_key`, `operator_key` | `accesses` (stock at the end of the month: never add months), `n_source_rows`, `n_missing_rows`, `n_exact_copy_rows` | Primary key = the three keys; the counts of source rows feed the data-quality cards |

**View**

| View | Description |
|---|---|
| `mart.v_duration_cases` | The population of the duration measures: fixed brands (`in_dashboard_scope = 1`), valid duration and Conciliation group, with operator, brand, filing and close year, days, outcome and batch-closing flag. Every check of `step_8.sql` reads it, so all use the same rules (D15). |

## Objects that exist only in Power BI (not in SQL Server)

| Object | Table | Description |
|---|---|---|
| `Is Duration Case` (calculated column) | `fact_complaint` | 1 when the complaint belongs to the population of the duration; the same rule as `mart.v_duration_cases` (D16) |
| `Operator Color` (calculated column) | `dim_operator` | Hex color of each operator (same on every page) |
| `Month Start` (calculated column) | `dim_date` | First day of the month, the axis of the monthly charts |
| `SLA Target` (parameter table) | none | Disconnected table with 30, 60, 90, 120 and 180 days; read with `SELECTEDVALUE` (D16) |
| Measures (28 in six display folders) | `Measures` | Volume, Duration, Outcomes, Service Level, Accesses and rate, Data quality; listed in `powerbi/build_guide.md` |