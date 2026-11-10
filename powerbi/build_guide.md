# Power BI build guide

How to build the report from the `mart` layer. The measures and the report follow the decisions D11, D14, D15 and D16 (`docs/decisions.md`). Every measure has a **reference value** taken from a SQL check, so the report is cross-checked against SQL before it is drawn.

**Work in two blocks.** Block A (connection and model) is validated first; Block B (measures, validation page and report pages) starts after it.

## Rules that the model must respect

| Rule | Where it comes from | What it means in Power BI |
|---|---|---|
| Fixed broadband only | D11 | Every complaint measure filters `dim_brand[in_dashboard_scope]` |
| Provider metrics for four operators | D11 | Duration, outcome and rate measures filter `dim_operator[is_main_operator]`; "Other" appears only in volume |
| Duration population | D15 | Conciliation group, valid duration, four operators (12,833 cases) |
| Axis of time | D15 | The **filing year** (cohort). 2022 to 2024 complete, 2025 "incomplete tail", 2026 "partial" |
| Rate per 100,000 accesses | D14, D8 | Only at national level and by year (2022 to 2024). Never by state or month |
| Accesses are a stock | D12 | Use December; never add months |
| State is the PROFECO office | D8 | Label it "PROFECO office state"; no rates by state |
| Service-level targets are parameters | D15 | 30, 60, 90, 120 and 180 days; default 60 |

---

# Block A. Connection and model (3 tasks)

## A1. Connect and load the `mart` tables

1. Power BI Desktop → **Get data** → **SQL Server**. Server: `.\SQLEXPRESS`. Database: `complaint_sla`. Mode: **Import**. Do not write a SQL statement.
2. If a dialog about encryption appears, accept the connection without encryption (local instance).
3. In the Navigator tick the eight tables of the schema `mart`: `dim_brand`, `dim_date`, `dim_operator`, `dim_outcome`, `dim_reason`, `dim_state`, `fact_accesses`, `fact_complaint`. Do **not** tick the view `v_duration_cases` (the population is built in the model, see A3).
4. Click **Load**.
5. Save the file as `powerbi/complaint_sla.pbix`. It stays local (decision D16).

Capture: the Navigator with the eight tables ticked, before loading → `powerbi_load_tables.png` (crop the user name if it shows).

**Rename the tables (needed for the DAX below).** Power BI loads them as `mart dim_brand`, `mart fact_complaint`, etc. (schema + space + table). Rename each of the eight tables to its plain name by removing the `mart ` prefix: Data pane or Model view → right click the table → **Rename**. Relationships are kept. Without this, every `dim_*[column]` reference in this guide fails with "column doesn't exist".

## A2. Settings and relationships

**Settings (File → Options and settings → Options):**
- *Current file → Data load → Time intelligence*: uncheck **Auto date/time** (the model has its own `dim_date`).
- *Current file → Data load → Relationships*: uncheck the automatic detection, so only the relationships below exist.

**Relationships (Model view).** All are many-to-one, single direction, from the fact table to the dimension.

| From (fact) | To (dimension) | Active |
|---|---|---|
| `fact_complaint[filing_date_key]` | `dim_date[date_key]` | Yes |
| `fact_complaint[close_date_key]` | `dim_date[date_key]` | **No** (inactive; the measures of D15 use the filing date) |
| `fact_complaint[state_key]` | `dim_state[state_key]` | Yes |
| `fact_complaint[operator_key]` | `dim_operator[operator_key]` | Yes |
| `fact_complaint[brand_key]` | `dim_brand[brand_key]` | Yes |
| `fact_complaint[reason_key]` | `dim_reason[reason_key]` | Yes |
| `fact_complaint[outcome_key]` | `dim_outcome[outcome_key]` | Yes |
| `fact_accesses[period_date_key]` | `dim_date[date_key]` | Yes |
| `fact_accesses[state_key]` | `dim_state[state_key]` | Yes |
| `fact_accesses[operator_key]` | `dim_operator[operator_key]` | Yes |

There is **no relationship between the two fact tables**. They meet through the shared dimensions `dim_date`, `dim_state` and `dim_operator` (conformed dimensions, see the glossary). That is what lets one year or one operator filter both complaints and accesses.

Capture: Model view with the tables arranged as a star (dimensions around the two facts) → `powerbi_model.png`.

## A3. Date table, formatting and the population column

1. **Date table:** select `dim_date` → *Table tools* → **Mark as date table** → column `date_value`.
2. **Sort:** select `dim_date[month_name]` → *Sort by column* → `month_num`.
3. **Hide** (right click → Hide in report view) all the `*_key` columns of the eight tables, the `flag_*` columns of `fact_complaint` and the counters `n_source_rows`, `n_missing_rows` and `n_exact_copy_rows` of `fact_accesses` (the data-quality page reads them with measures).
4. **Summarization:** set `days_to_close`, `accesses`, `claimed_amount` and `recovered_amount` to **Don't summarize** (only the measures are used).
5. **Measures table:** *Home → Enter data*, one empty table named `_Measures`. All the measures go there, in display folders (`1 Volume`, `2 Duration`, `3 Outcomes`, `4 Service level`, `5 Accesses and rates`, `6 Data quality`; emojis are optional).
6. **Calculated column** in `fact_complaint` (it marks the duration population of D15 once, at refresh, so the measures do not repeat five filters):

```dax
Is Duration Case =
-- 1 = fixed broadband brand, one of the four operators, Conciliation group, valid duration (D15)
IF (
    RELATED ( dim_brand[in_dashboard_scope] )
        && RELATED ( dim_operator[is_main_operator] )
        && RELATED ( dim_outcome[procedure_group] ) = "Conciliation"
        && fact_complaint[flag_valid_duration],
    1,
    0
)
```

**Check the load** with the *DAX query view* (left bar of Power BI Desktop) and capture the result:

```dax
EVALUATE
ROW (
    "complaints",        COUNTROWS ( fact_complaint ),
    "access_rows",       COUNTROWS ( fact_accesses ),
    "days",              COUNTROWS ( dim_date ),
    "duration_cases",    SUMX ( fact_complaint, fact_complaint[Is Duration Case] ),
    "dec_2024_accesses", CALCULATE ( SUM ( fact_accesses[accesses] ), dim_date[year_num] = 2024, dim_date[month_num] = 12 )
)
```

Expected: complaints **36,034**, access_rows **19,840**, days **5,113**, duration_cases **12,833**, dec_2024_accesses **29,003,240** (four operators 11,208,977 + 5,619,403 + 5,316,545 + 5,313,779 = 27,458,704, plus Other 1,544,536; checks 6.5b and 7.3f).

Capture → `powerbi_check_01.png`.

---

# Block B. Measures, validation and report (3 tasks)

## B1. Measures

Create them in `_Measures`. Names are in English because the report is in English.

```dax
-- VOLUME ---------------------------------------------------------
Complaints =
CALCULATE ( COUNTROWS ( fact_complaint ), dim_brand[in_dashboard_scope] = TRUE () )

-- DURATION (population of D15, filing-year cohorts) -------------
Duration Cases =
CALCULATE ( COUNTROWS ( fact_complaint ), fact_complaint[Is Duration Case] = 1 )

Median Days to Close =
CALCULATE ( MEDIAN ( fact_complaint[days_to_close] ), fact_complaint[Is Duration Case] = 1 )

P90 Days to Close =
-- PERCENTILE.INC interpolates like PERCENTILE_CONT of SQL, so both give the same value
CALCULATE ( PERCENTILE.INC ( fact_complaint[days_to_close], 0.9 ), fact_complaint[Is Duration Case] = 1 )

Mean Days to Close =
CALCULATE ( AVERAGE ( fact_complaint[days_to_close] ), fact_complaint[Is Duration Case] = 1 )

Cohort Status =
-- Text for the report: tells if the filing-year cohort is complete (D15).
-- Blank when the year has no complaints, so empty calendar years do not appear in matrices
VAR _year = SELECTEDVALUE ( dim_date[year_num] )
RETURN
    IF (
        ISBLANK ( [Complaints] ),
        BLANK (),
        SWITCH (
            TRUE (),
            ISBLANK ( _year ), "All cohorts",
            _year <= 2024,     "Complete",
            _year = 2025,      "Incomplete tail",
            "Partial year"
        )
    )

-- OUTCOMES (population: fixed brands, four operators, Conciliation, with close date) ----
Outcome Cases =
CALCULATE (
    COUNTROWS ( fact_complaint ),
    dim_brand[in_dashboard_scope] = TRUE (),
    dim_operator[is_main_operator] = TRUE (),
    dim_outcome[procedure_group] = "Conciliation",
    fact_complaint[flag_missing_close] = FALSE ()
)

Valid Outcome Cases =
-- KEEPFILTERS keeps the outcome of the current row/legend: without it, a visual with
-- dim_outcome[outcome] in the legend would repeat the total of the four outcomes in every segment
CALCULATE (
    [Outcome Cases],
    KEEPFILTERS ( dim_outcome[outcome] IN { "Conciliada", "No Conciliada", "Desistimiento", "Improcedente" } )
)

Conciliated Cases = CALCULATE ( [Outcome Cases], dim_outcome[outcome] = "Conciliada" )
Withdrawn Cases   = CALCULATE ( [Outcome Cases], dim_outcome[outcome] = "Desistimiento" )

Conciliation Rate = DIVIDE ( [Conciliated Cases], [Valid Outcome Cases] )
Withdrawal Share  = DIVIDE ( [Withdrawn Cases], [Valid Outcome Cases] )

Conciliation Rate Excl Withdrawals =
-- Only to compare with the SQL check 8.7; it is not shown in the report (D15)
DIVIDE (
    [Conciliated Cases],
    CALCULATE ( [Outcome Cases], dim_outcome[outcome] IN { "Conciliada", "No Conciliada" } )
)

-- SERVICE LEVEL (parameter table 'SLA Target', see B2) ------------
Selected SLA Days = SELECTEDVALUE ( 'SLA Target'[Days], 60 )

Cases Within SLA =
-- The target goes into a variable: a measure cannot be used inside a True/False filter
VAR _target = [Selected SLA Days]
RETURN CALCULATE ( [Duration Cases], fact_complaint[days_to_close] <= _target )

% Within SLA = DIVIDE ( [Cases Within SLA], [Duration Cases] )

-- ACCESSES AND RATES (D14, D8) ------------------------------------
Accesses December =
-- A stock: December of ONE year. With several years selected it returns blank
IF (
    HASONEVALUE ( dim_date[year_num] ),
    CALCULATE ( SUM ( fact_accesses[accesses] ), dim_date[month_num] = 12 )
)

Complaints per 100k Accesses =
-- Only by year and national: blank by month or by state (the state is the PROFECO office, D8).
-- Blank from 2025 on because the BIT file ends in December 2024.
IF (
    HASONEVALUE ( dim_date[year_num] )
        && NOT ISINSCOPE ( dim_date[year_month] )
        && NOT ISFILTERED ( dim_state[state_name] ),
    VAR _accesses   = CALCULATE ( [Accesses December], dim_operator[is_main_operator] = TRUE () )
    VAR _complaints = CALCULATE ( [Complaints],        dim_operator[is_main_operator] = TRUE () )
    RETURN DIVIDE ( _complaints, _accesses ) * 100000
)

-- OFFICES AND DATA QUALITY ----------------------------------------
Central Office Share =
DIVIDE ( CALCULATE ( [Complaints], fact_complaint[flag_central_office] = TRUE () ), [Complaints] )

DQ Missing Close Date =
CALCULATE ( COUNTROWS ( fact_complaint ), fact_complaint[flag_missing_close] = TRUE () )
DQ Close Before Filing =
CALCULATE ( COUNTROWS ( fact_complaint ), fact_complaint[flag_close_before_filing] = TRUE () )
DQ Cancelled =
CALCULATE ( COUNTROWS ( fact_complaint ), fact_complaint[flag_cancelled] = TRUE () )
DQ Batch Closing Day =
CALCULATE ( COUNTROWS ( fact_complaint ), fact_complaint[flag_unusual_close_day] = TRUE () )
DQ BIT Rows Without Value = SUM ( fact_accesses[n_missing_rows] )
DQ BIT Exact Copies       = SUM ( fact_accesses[n_exact_copy_rows] )
```

## B2. Parameter table and validation page

**Parameter table:** *Modeling → New table*:

```dax
SLA Target = DATATABLE ( "Days", INTEGER, { { 30 }, { 60 }, { 90 }, { 120 }, { 180 } } )
```

Do not relate it to any table. Use it as a slicer (single selection); the measures read the selection and use 60 when nothing is selected.

**Validation page** (a page named `Validation`, hidden when the report is exported). Use a **matrix**: rows `dim_operator[operator_name]`; values: `Duration Cases`, `Median Days to Close`, `P90 Days to Close`, `Mean Days to Close`, `% Within SLA`, `Outcome Cases`, `Conciliation Rate`, `Withdrawal Share`. No slicer selected (the target is 60). Compare with the SQL values:

| Operator | Duration cases | Median | P90 | Mean | % within 60 | Conciliation rate (all cohorts) |
|---|---|---|---|---|---|---|
| Telmex | 2,129 | 70.0 | 225.2 | 105.2 | 44.3% | 67.7% |
| Izzi | 3,567 | 35.0 | 132.0 | 60.4 | 71.8% | 62.9% |
| Megacable | 3,873 | 24.0 | 92.0 | 42.2 | 81.2% | 68.9% |
| Total Play | 3,264 | 32.0 | 130.0 | 59.3 | 71.3% | 60.2% |
| Total (four operators) | 12,833 | 35.0 | 138.0 | 62.1 | 69.9% | 64.8% |

(SQL checks 8.4, 8.6 and 8.7. Outcome cases of the total: 12,837; withdrawal share 29.0%; rate without withdrawals 91.8%.)

**Second validation, by filing year** (matrix with `dim_date[year_num]` in the rows and the four operators together, no operator selected):

| Filing year | Duration cases | Median | P90 | Conciliation rate | Withdrawal share | Complaints per 100k | Cohort status |
|---|---|---|---|---|---|---|---|
| 2022 | 4,001 | 32.0 | 169.0 | 68.1% | 24.8% | see below | Complete |
| 2023 | 2,777 | 35.0 | 161.0 | 66.0% | 27.5% | see below | Complete |
| 2024 | 2,390 | 30.0 | 130.0 | 63.5% | 29.7% | see below | Complete |
| 2025 | 2,927 | 41.0 | 118.0 | 60.2% | 34.8% | blank | Incomplete tail |
| 2026 | 738 | 41.0 | 75.0 | 65.3% | 31.8% | blank | Partial year |

(SQL checks 8.8 and 8.9.)

**Third validation, rates per 100,000 accesses** (matrix: operators in the rows, years 2022 to 2024 in the columns, `Complaints per 100k Accesses`; and a second one with `Accesses December`). Reference: SQL checks 7.3c and 7.3f.

| Operator | 2022 | 2023 | 2024 | Accesses December 2024 |
|---|---|---|---|---|
| Telmex | 8.61 | 5.02 | 3.68 | 11,208,977 |
| Izzi | 15.25 | 16.01 | 14.08 | 5,619,403 |
| Megacable | 33.20 | 18.38 | 14.67 | 5,316,545 |
| Total Play | 20.96 | 13.74 | 10.90 | 5,313,779 |

**Fourth validation, the target:** select 30, 90, 120 and 180 in the slicer and check `% Within SLA` of the total: 44.9%, 81.1%, 87.8% and 93.6% (check 8.6).

**Fifth validation, volume:** `Complaints` with no filter must give **13,358**.

**A value that does not match is not corrected in the report: check the measure, then the model, and only then the SQL.** Captures: see the capture list at the end.

## B3. Report pages

**Format rules**
- Theme: light background, one font, titles that say what the chart shows ("Median days to close, by filing year").
- Colors of the operators (Okabe-Ito, readable with color blindness, the same on every page): Telmex `#0072B2`, Izzi `#E69F00`, Megacable `#009E73`, Total Play `#D55E00`, Other `#999999`.
- A text box in the footer of every page with the sources and the notice:

```
Sources: PROFECO, "Quejas en materia de telecomunicaciones", datos.gob.mx, CC BY 4.0, downloaded 2026-10-24 (cleaned and aggregated by the author). CRT, Banco de Información de Telecomunicaciones (BIT), "TD_ACC_BAF_ITE_VA", downloaded 2026-10-26. Independent portfolio project; not an official product and not endorsed by PROFECO, the CRT or the Government of México.
```

- Slicers: `dim_date[year_num]` (filing year) and `dim_operator[operator_name]` on the pages that need them. Edit interactions so the year slicer does not hide the SLA parameter.
- Every page with a duration or an outcome shows the **Cohort Status** next to the year.

| # | Page | Visuals | Question |
|---|---|---|---|
| 1 | Overview | Cards: `Complaints`, `Median Days to Close`, `P90 Days to Close`, `Conciliation Rate`, `Withdrawal Share`. Line: `Complaints` by `dim_date[year_month]` (trend and seasonality), one line per operator including Other | BQ1, BQ4 |
| 2 | Resolution time | Clustered column: `Median Days to Close` and `P90 Days to Close` by operator; line: median by filing year per operator; `% Within SLA` by operator with the `SLA Target` slicer; `Cohort Status` | BQ1, BQ4 |
| 3 | Outcomes | Stacked 100% bar: `Outcome Cases` by `dim_outcome[outcome]` per operator; lines: `Conciliation Rate` and `Withdrawal Share` by year per operator | BQ2 |
| 4 | Complaints and accesses | Column: `Complaints per 100k Accesses` by operator and year (2022 to 2024); table: `Complaints`, `Accesses December`, rate; note on the definition (D14) | BQ3 |
| 5 | Reasons and offices | Bar (top 10, Top N filter by `Complaints`, data labels and axis with Display units = None): `Complaints` by `dim_reason[claim_type]`; bar (Top N 10, Ciudad de México included on purpose): `Complaints` by `dim_state[state_name]` titled "Top 10 states (PROFECO office state)"; card `Central Office Share`; text with the D8 warning | BQ1 |
| 6 | Data quality and limits | Cards `DQ ...`; text box with the limitations (D4, D7, D8, D9, D12, D13, D15) | all |

Reference values of page 5 (SQL checks P3 and P4): states Ciudad de México 7,748; Estado de México 610; Yucatán 379; San Luis Potosí 345; Guanajuato 332; Morelos 290; Querétaro 290; Jalisco 251; Coahuila 250; Tamaulipas 238. Claim types Cobro Indebido 4,343; Entrega del Producto o Servicio 4,335; Contratos 3,682; Cambios, Devoluciones o Bonificaciones 493; Trato o Servicio al Cliente 159; Publicidad, Ofertas y Promociones 138; Garantías 61; Portabilidad 45; Información Incorrecta al Consumidor Sobre… 28; Pérdidas o Deterioro 20.

Reference values of the data-quality cards (`Central Office Share` = **49.6%** for fixed broadband brands, 6,624 of 13,358; 54.9% for all 36,034 complaints, SQL check P1; combined rate per 100,000 accesses of the four operators: 16.60 in 2022, 11.51 in 2023 and 9.33 in 2024, SQL check P2): missing close date **66**, close before filing **3**, cancelled **48**, batch closing day **147**, BIT rows without value **1,831**, BIT exact copies **325**.

**Limitations text for page 6 (short):**
- The state is the PROFECO office, not the place of the consumer: 62% of all complaints are filed in Ciudad de México, and the central office alone handles 54.9% of all cases (49.6% of the fixed broadband cases shown in the report).
- The rate per 100,000 accesses uses the filing year and the accesses of December; there are no BIT accesses after December 2024.
- The numerator holds every complaint of the brand (the service type is known in 1% to 25% of the rows); the denominator is fixed broadband accesses.
- Only closed cases are in the file: the 2025 cohort has an incomplete tail and 2026 is partial.
- Amounts are not used as indicators (D9).
- One provider per complaint (D4).

## B4. Export and save

1. *File → Export → Export to PDF* → `powerbi/complaint_sla_report.pdf`, without the `Validation` pages (hide them first: right-click the tab, *Hide page*).
2. One screenshot of each page, cropped to the report → `docs/img/powerbi_page_01.png` to `powerbi_page_06.png`.
3. The `.pbix` stays local and is not versioned (decision D16).

---

## Capture list

| Block | What to capture | File |
|---|---|---|
| A1 | Navigator with the eight tables ticked | `powerbi_load_tables.png` |
| A2 | Model view (star) | `powerbi_model.png` |
| A3 | DAX query result | `powerbi_check_01.png` |
| B1 lot 1 | Matrices by operator and by filing year (duration) | `powerbi_check_02.png` |
| B1 lot 2 | Matrix by operator (outcomes, SLA) | `powerbi_check_03a.png` |
| B1 lot 2 | Matrix by filing year (outcomes) | `powerbi_check_03b.png` |
| B1 lot 2 | Matrix by SLA target (30 to 180 days) | `powerbi_check_03c.png` |
| B1 lot 3 | Rates, accesses and data-quality cards | `powerbi_check_04.png` |
| B3 | SQL check P3 and P4 (top 10 states and claim types) | `step_7_check_10.png` |
| B3 | Six pages of the report | `powerbi_page_01.png` to `powerbi_page_06.png` |
| B4 | Tab bar with only the six report pages | `powerbi_pages_final.png` |
| B4 | PDF opened, six pages | `powerbi_pdf_check.png` |
| B4 | PDF | `powerbi/complaint_sla_report.pdf` |