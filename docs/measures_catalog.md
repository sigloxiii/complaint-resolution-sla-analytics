# DAX measures catalog

Reference of every DAX object in the Power BI model of this project: **26 measures**, **3 calculated columns** and **1 parameter table**. Use it to read the model without opening the `.pbix` (which is not versioned, decision D16) or to rebuild it. The step-by-step build is in [`build_guide.md`](build_guide.md); the decisions behind the definitions (D4, D8, D14, D15) are in [`../docs/decisions.md`](../docs/decisions.md).

## How to read this catalog

- **Home table:** all measures live in the table `_Measures`, grouped in six display folders (`1 Volume` to `6 Data quality`).
- **Population:** two populations are used, and the measure name tells which.
  - *Scope population:* complaints of fixed broadband brands (`dim_brand[in_dashboard_scope]`) = **13,358**.
  - *Duration / outcome population:* the four main operators, Conciliation procedure, with a valid close date = **12,833** duration cases (D15).
- **Where used:** pages of the report (1 Overview, 2 Resolution time, 3 Outcomes, 4 Complaints and accesses, 5 Reasons and offices, 6 Data quality) and `Validation` (the hidden page of reconciliation with SQL).
- **Validation:** the SQL check that gives the same value (`sql/common/step_8.sql` checks 8.x, `step_7` checks 7.3x, `step_8b.sql` checks P1 to P7).

## Summary

| # | Folder | Object | Type | Where used |
|---|---|---|---|---|
| 1 | 1 Volume | Complaints | Measure | 1, 4, 5, Validation |
| 2 | 2 Duration | Duration Cases | Measure | 2, Validation |
| 3 | 2 Duration | Median Days to Close | Measure | 1, 2, Validation |
| 4 | 2 Duration | P90 Days to Close | Measure | 1, 2, Validation |
| 5 | 2 Duration | Mean Days to Close | Measure | Validation |
| 6 | 2 Duration | Cohort Status | Measure | 2, 3 |
| 7 | 3 Outcomes | Outcome Cases | Measure | 3, Validation |
| 8 | 3 Outcomes | Valid Outcome Cases | Measure (helper) | 3 |
| 9 | 3 Outcomes | Conciliated Cases | Measure (helper) | none directly |
| 10 | 3 Outcomes | Withdrawn Cases | Measure (helper) | none directly |
| 11 | 3 Outcomes | Conciliation Rate | Measure | 1, 3, Validation |
| 12 | 3 Outcomes | Withdrawal Share | Measure | 1, 3, Validation |
| 13 | 3 Outcomes | Conciliation Rate Excl Withdrawals | Measure (check only) | Validation |
| 14 | 4 Service level | Selected SLA Days | Measure (helper) | none directly |
| 15 | 4 Service level | Cases Within SLA | Measure (helper) | none directly |
| 16 | 4 Service level | % Within SLA | Measure | 2, Validation |
| 17 | 4 Service level | SLA Title | Measure (text) | 2 |
| 18 | 5 Accesses and rates | Accesses December | Measure | 4, Validation |
| 19 | 5 Accesses and rates | Complaints per 100k Accesses | Measure | 4, Validation |
| 20 | 6 Data quality | Central Office Share | Measure | 5, 6 |
| 21 | 6 Data quality | DQ Missing Close Date | Measure | 6 |
| 22 | 6 Data quality | DQ Close Before Filing | Measure | 6 |
| 23 | 6 Data quality | DQ Cancelled | Measure | 6 |
| 24 | 6 Data quality | DQ Batch Closing Day | Measure | 6 |
| 25 | 6 Data quality | DQ BIT Rows Without Value | Measure | 6 |
| 26 | 6 Data quality | DQ BIT Exact Copies | Measure | 6 |
| 27 | n/a | Is Duration Case | Calculated column, `fact_complaint` | used by measures 2 to 5 |
| 28 | n/a | Operator Color | Calculated column, `dim_operator` | formatting, all pages |
| 29 | n/a | Month Start | Calculated column, `dim_date` | monthly charts |
| 30 | n/a | SLA Target | Parameter table | slicer of page 2 |

## Dependencies

```
Is Duration Case ──► Duration Cases ──► Cases Within SLA ──► % Within SLA
                 ├─► Median / P90 / Mean Days to Close      ▲
                                                  Selected SLA Days ──► SLA Title
                                                  ▲
                                           SLA Target (table)

Outcome Cases ──► Valid Outcome Cases ──► Conciliation Rate / Withdrawal Share
              ├─► Conciliated Cases ───►┘
              └─► Withdrawn Cases ─────►┘   (+ Excl Withdrawals, check only)

Complaints ──► Complaints per 100k Accesses ◄── Accesses December
           └─► Central Office Share
```

---

## 1 Volume

### Complaints
```dax
Complaints =
CALCULATE ( COUNTROWS ( fact_complaint ), dim_brand[in_dashboard_scope] = TRUE () )
```
- **Meaning:** number of complaints of fixed broadband brands (the scope of the report). It includes the operator "Other" and every procedure.
- **Conditions:** the filter on `in_dashboard_scope` is inside the measure, so it holds on every visual.
- **Validation:** no filter = **13,358** (fifth validation of B2; SQL scope count).

## 2 Duration (filing-year cohorts, population of D15)

### Duration Cases
```dax
Duration Cases =
CALCULATE ( COUNTROWS ( fact_complaint ), fact_complaint[Is Duration Case] = 1 )
```
- **Meaning:** complaints with a measurable duration: four main operators, Conciliation procedure, valid close date.
- **Validation:** 12,833 in total (Telmex 2,129; Izzi 3,567; Megacable 3,873; Total Play 3,264). SQL check 8.4; view `mart.v_duration_cases` has 12,917 rows before the four-operator filter.

### Median Days to Close
```dax
Median Days to Close =
CALCULATE ( MEDIAN ( fact_complaint[days_to_close] ), fact_complaint[Is Duration Case] = 1 )
```
- **Meaning:** the typical duration: half of the cases close in this many days or fewer. Preferred over the mean because durations are right-skewed.
- **Validation:** Telmex 70.0; Izzi 35.0; Megacable 24.0; Total Play 32.0; total 35.0 (SQL 8.4).

### P90 Days to Close
```dax
P90 Days to Close =
CALCULATE ( PERCENTILE.INC ( fact_complaint[days_to_close], 0.9 ), fact_complaint[Is Duration Case] = 1 )
```
- **Meaning:** 90% of the cases close in this many days or fewer; it describes the slow tail.
- **Note:** `PERCENTILE.INC` interpolates like `PERCENTILE_CONT` in SQL, so both give the same value.
- **Validation:** Telmex 225.2; Izzi 132.0; Megacable 92.0; Total Play 130.0; total 138.0 (SQL 8.4).

### Mean Days to Close
```dax
Mean Days to Close =
CALCULATE ( AVERAGE ( fact_complaint[days_to_close] ), fact_complaint[Is Duration Case] = 1 )
```
- **Meaning:** arithmetic mean. Kept only for the reconciliation with SQL and to show how far the tail pulls it above the median.
- **Validation:** Telmex 105.2; Izzi 60.4; Megacable 42.2; Total Play 59.3; total 62.1.

### Cohort Status
```dax
Cohort Status =
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
```
- **Meaning:** text that tells if the filing-year cohort can be compared. The file holds only closed cases, so recent cohorts miss their slowest complaints (D15).
- **Conditions:** blank when the year has no complaints (so empty calendar years do not appear in matrices); "All cohorts" with several years selected.
- **Validation:** 2022 to 2024 Complete; 2025 Incomplete tail; 2026 Partial year (second validation of B2).

## 3 Outcomes (population: fixed brands, four operators, Conciliation, with close date)

### Outcome Cases
```dax
Outcome Cases =
CALCULATE (
    COUNTROWS ( fact_complaint ),
    dim_brand[in_dashboard_scope] = TRUE (),
    dim_operator[is_main_operator] = TRUE (),
    dim_outcome[procedure_group] = "Conciliation",
    fact_complaint[flag_missing_close] = FALSE ()
)
```
- **Meaning:** closed conciliation cases of the four operators, whatever their outcome. Base of the outcome measures and series of the 100% stacked bar.
- **Validation:** 12,837 in total (SQL 8.6, 8.7). It differs from Duration Cases (12,833) by cases with an outcome but without a valid duration.

### Valid Outcome Cases
```dax
Valid Outcome Cases =
CALCULATE (
    [Outcome Cases],
    KEEPFILTERS ( dim_outcome[outcome] IN { "Conciliada", "No Conciliada", "Desistimiento", "Improcedente" } )
)
```
- **Meaning:** denominator of the outcome rates: the four outcomes that close a conciliation.
- **Why `KEEPFILTERS`:** without it, a visual with `dim_outcome[outcome]` in the legend would repeat the total of the four outcomes in every segment, because `CALCULATE` would replace the outcome filter of the row.

### Conciliated Cases / Withdrawn Cases
```dax
Conciliated Cases = CALCULATE ( [Outcome Cases], dim_outcome[outcome] = "Conciliada" )
Withdrawn Cases   = CALCULATE ( [Outcome Cases], dim_outcome[outcome] = "Desistimiento" )
```
- **Meaning:** numerators of the two rates. Helpers: not placed in visuals.

### Conciliation Rate
```dax
Conciliation Rate = DIVIDE ( [Conciliated Cases], [Valid Outcome Cases] )
```
- **Meaning:** share of the closed cases with a valid outcome that ended in a conciliation agreement.
- **Validation:** by year 68.1% (2022), 66.0%, 63.5%, 60.2% (2025); by operator, all cohorts: Telmex 67.7%, Izzi 62.9%, Megacable 68.9%, Total Play 60.2%; total 64.8% (SQL 8.6, 8.8).
- **Reading note:** withdrawals are inside the denominator; the fall of the rate goes with the rise of the withdrawal share (it is an association, not a cause).

### Withdrawal Share
```dax
Withdrawal Share = DIVIDE ( [Withdrawn Cases], [Valid Outcome Cases] )
```
- **Meaning:** share of the valid outcomes in which the consumer withdrew.
- **Validation:** 24.8% (2022), 27.5%, 29.7%, 34.8% (2025); total 29.0% (SQL 8.7, 8.8).

### Conciliation Rate Excl Withdrawals
```dax
Conciliation Rate Excl Withdrawals =
DIVIDE (
    [Conciliated Cases],
    CALCULATE ( [Outcome Cases], dim_outcome[outcome] IN { "Conciliada", "No Conciliada" } )
)
```
- **Meaning:** rate with only the two outcomes decided by the provider and the agency. **Check only:** it is not shown in the report (D15).
- **Validation:** total 91.8% (SQL 8.7).

## 4 Service level (parameter table `SLA Target`)

### Selected SLA Days
```dax
Selected SLA Days = SELECTEDVALUE ( 'SLA Target'[Days], 60 )
```
- **Meaning:** target read from the slicer (30, 60, 90, 120 or 180); 60 when nothing or several values are selected.

### Cases Within SLA
```dax
Cases Within SLA =
VAR _target = [Selected SLA Days]
RETURN CALCULATE ( [Duration Cases], fact_complaint[days_to_close] <= _target )
```
- **Why a variable:** a measure cannot be used inside a True/False filter argument of `CALCULATE`; the variable stores the value first.

### % Within SLA
```dax
% Within SLA = DIVIDE ( [Cases Within SLA], [Duration Cases] )
```
- **Meaning:** share of the duration cases closed within the selected target. The 60-day target is an analytical threshold, not a legal deadline.
- **Validation:** at 60 days: Telmex 44.3%, Izzi 71.8%, Total Play 71.3%, Megacable 81.2%, total 69.9%. Total at 30, 90, 120, 180 days: 44.9%, 81.1%, 87.8%, 93.6% (SQL 8.6).

### SLA Title
```dax
SLA Title =
"Cases closed within " & [Selected SLA Days] & " days, by operator"
```
- **Meaning:** dynamic title of the SLA visual on page 2. Used in *Title → fx → Field value*, so the title follows the slicer.
- **Validation:** with the slicer on 90 it reads "Cases closed within 90 days, by operator".

## 5 Accesses and rates

### Accesses December
```dax
Accesses December =
IF (
    HASONEVALUE ( dim_date[year_num] ),
    CALCULATE ( SUM ( fact_accesses[accesses] ), dim_date[month_num] = 12 )
)
```
- **Meaning:** fixed broadband accesses at the end of the year (a stock, not a flow: December is not added to the other months). Blank when several years are selected.
- **Validation:** December 2024: Telmex 11,208,977; Izzi 5,619,403; Megacable 5,316,545; Total Play 5,313,779; sum of the four **27,458,704** (29,003,240 with "Other") (SQL 7.3f, P2).
- **Limit:** the BIT file ends in December 2024.

### Complaints per 100k Accesses
```dax
Complaints per 100k Accesses =
IF (
    HASONEVALUE ( dim_date[year_num] )
        && NOT ISINSCOPE ( dim_date[year_month] )
        && NOT ISFILTERED ( dim_state[state_name] ),
    VAR _accesses   = CALCULATE ( [Accesses December], dim_operator[is_main_operator] = TRUE () )
    VAR _complaints = CALCULATE ( [Complaints],        dim_operator[is_main_operator] = TRUE () )
    RETURN DIVIDE ( _complaints, _accesses ) * 100000
)
```
- **Meaning:** complaints filed in the year per 100,000 accesses of December of the same year, by operator.
- **Guards:** blank by month and by state (the state is the PROFECO office, not the consumer's, D8), blank without a single year, and blank from 2025 (no BIT accesses).
- **Limit:** the numerator counts every complaint of the brand; the service type is known in 1% to 25% of the rows (D14).
- **Validation:** Telmex 8.61 / 5.02 / 3.68; Izzi 15.25 / 16.01 / 14.08; Megacable 33.20 / 18.38 / 14.67; Total Play 20.96 / 13.74 / 10.90 (2022 / 2023 / 2024). Four operators together: 16.60 / 11.51 / 9.33 (SQL 7.3c, P2).

## 6 Data quality

### Central Office Share
```dax
Central Office Share =
DIVIDE ( CALCULATE ( [Complaints], fact_complaint[flag_central_office] = TRUE () ), [Complaints] )
```
- **Meaning:** share of the complaints handled by the central office in Ciudad de México. Shows why the state is not a geography of consumers (D8).
- **Validation:** **49.6%** for fixed broadband (6,624 of 13,358); 54.9% for all 36,034 complaints (SQL P1).

### DQ measures
```dax
DQ Missing Close Date     = CALCULATE ( COUNTROWS ( fact_complaint ), fact_complaint[flag_missing_close] = TRUE () )
DQ Close Before Filing    = CALCULATE ( COUNTROWS ( fact_complaint ), fact_complaint[flag_close_before_filing] = TRUE () )
DQ Cancelled              = CALCULATE ( COUNTROWS ( fact_complaint ), fact_complaint[flag_cancelled] = TRUE () )
DQ Batch Closing Day      = CALCULATE ( COUNTROWS ( fact_complaint ), fact_complaint[flag_unusual_close_day] = TRUE () )
DQ BIT Rows Without Value = SUM ( fact_accesses[n_missing_rows] )
DQ BIT Exact Copies       = SUM ( fact_accesses[n_exact_copy_rows] )
```

| Measure | What it counts | Value |
|---|---|---|
| DQ Missing Close Date | Complaints without a close date | 66 |
| DQ Close Before Filing | Close date earlier than the filing date | 3 |
| DQ Cancelled | Cancelled complaints | 48 |
| DQ Batch Closing Day | Close dates on unusual (batch) days | 147 |
| DQ BIT Rows Without Value | BIT source rows with no access value | 1,831 |
| DQ BIT Exact Copies | BIT rows that are exact copies of another | 325 |

These are shown as cards on page 6 and are not filtered by operator.

---

## Calculated columns and parameter table

### Is Duration Case (`fact_complaint`)
```dax
Is Duration Case =
IF (
    RELATED ( dim_brand[in_dashboard_scope] )
        && RELATED ( dim_operator[is_main_operator] )
        && RELATED ( dim_outcome[procedure_group] ) = "Conciliation"
        && fact_complaint[flag_valid_duration],
    1,
    0
)
```
- **Meaning:** marks the duration population (D15) once, at refresh, so the five duration measures do not repeat five filters.
- **Validation:** sum = 12,833.

### Operator Color (`dim_operator`)
```dax
Operator Color =
SWITCH (
    dim_operator[operator_name],
    "Telmex",     "#0072B2",
    "Izzi",       "#E69F00",
    "Megacable",  "#009E73",
    "Total Play", "#D55E00",
    "#999999"
)
```
- **Meaning:** one color per operator (Okabe-Ito palette, readable with color blindness), used with *Format by field value* so the same operator has the same color on every page. "Other" gets gray.

### Month Start (`dim_date`)
```dax
Month Start = DATE ( dim_date[year_num], dim_date[month_num], 1 )
```
- **Meaning:** first day of the month as a real date. Used as a **continuous** x-axis in the monthly charts so months follow calendar order and gaps are visible. Format `mmm yyyy`.

### SLA Target (parameter table)
```dax
SLA Target = DATATABLE ( "Days", INTEGER, { { 30 }, { 60 }, { 90 }, { 120 }, { 180 } } )
```
- **Meaning:** list of targets for the slicer of page 2. It has **no relationship** to any table; the measures read the selection (single selection; default 60).

---

## Conventions

- Measure names are in English and have no abbreviations, except `SLA` and `DQ`.
- Prefix `DQ` = data-quality counter; `_` before a variable name = local `VAR`.
- Rates use `DIVIDE`, never `/`, so an empty denominator gives blank.
- A value that does not match its SQL check is not corrected in the report: check the measure, then the model, and only then the SQL (B2 of the build guide).