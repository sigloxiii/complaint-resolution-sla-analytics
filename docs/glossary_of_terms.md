# Glossary of terms

Technical terms used in this project, in the order in which they became relevant. Each entry says what the term is, how it works and where it appeared in the project. The glossary grows as the project advances.

## File and text formats

### LF and CR+LF (line endings)

- **What they are:** two invisible characters that mark where a line of text ends.
  - **LF** (*Line Feed*, `\n`, hexadecimal `0x0a`): moves to the next line.
  - **CR** (*Carriage Return*, `\r`, hexadecimal `0x0d`): returns to the start of the line.
  - **CR+LF** (`\r\n`): both characters together.
- **Why two conventions exist:** typewriters and early teleprinters needed two separate movements (return the carriage, then advance the paper). Operating systems made different choices when they inherited that idea:

  | System | Line ending |
  |---|---|
  | Windows | CR+LF |
  | Linux, macOS | LF |

- **Why a file has one or the other:** it depends on the system or tool that exported it. Open-data portals usually generate files with scripts running on Linux servers, so their CSV files often use LF. Excel and Notepad on Windows normally save CR+LF.
- **Why it is invisible:** editors such as Excel, Power Query and VS Code accept both without complaint. Programs that read a file by exact byte pattern, such as `BULK INSERT`, do not.
- **Where it mattered here:** `quejas_telecomunicaciones_2022_junio_2026.csv` uses LF. `BULK INSERT ... FORMAT = 'CSV'` expects CR+LF by default, could not find where each row ends and failed with error 7301 (see `docs/run_log.md`, step 1).
- **How to detect it:** read the file as plain text and look for the character CR at the end of the first line:

  ```sql
  SELECT RIGHT(LEFT(BulkColumn, CHARINDEX(CHAR(10), BulkColumn) - 1), 1) AS last_char
  FROM OPENROWSET(BULK '<path to file>', SINGLE_CLOB) AS f;
  -- If last_char is CHAR(13), the file uses CR+LF. Otherwise it uses LF only.
  ```

- **How to handle it:** tell `BULK INSERT` which terminator the file uses: `ROWTERMINATOR = '0x0a'` for LF, or leave it out for CR+LF.
- **Where it mattered again:** the BIT file (`TD_ACC_BAF_ITE_VA.csv`) uses CR+LF, so `step_5.sql` sets `ROWTERMINATOR = '0x0d0a'`.
- **Rule for this project:** raw files are never edited, so the script adapts to the file, not the other way around.

### CSV (comma-separated values)

- **What it is:** a text file where each line is a row and commas separate the columns.
- **Quoted fields:** text that contains a comma or a line break is wrapped in double quotes (`"`). `FIELDQUOTE = '"'` tells `BULK INSERT` to respect them.
- **Check used here:** the number of double quotes in the file must be even; an odd number means a quote was left open.

### UTF-8 and code page

- **What it is:** UTF-8 is a text encoding that represents accents and characters such as *ñ*. A *code page* is the number SQL Server uses to name an encoding; UTF-8 is `65001`.
- **Where it mattered here:** `CODEPAGE = '65001'` in `step_1.sql`, so that *México* and *Telefonía* load without damaged characters.

### Code page 1252 (Windows Latin 1)

- **What it is:** an older encoding that uses one byte per character and covers Western European accents. It is the code page that SQL Server names `1252`.
- **How it differs from UTF-8:** the same accented letter is stored with different bytes. Reading a 1252 file as UTF-8 (or the reverse) shows damaged characters such as `Ã©` instead of `é`.
- **Where it mattered here:** the PROFECO file is UTF-8 (`CODEPAGE = '65001'`) and the BIT file is 1252 (`CODEPAGE = '1252'`). Check 5.3 confirmed that the accents of the BIT load correctly.

## SQL Server

### BULK INSERT

- **What it is:** a command that loads a text file into a table, very fast and without going through the wizard.
- **How it works:** the file is read by the SQL Server service (not by the person running the script), so the service account needs read permission on the folder. Columns are matched **by position**, not by name.
- **Why it is used here:** it is repeatable and versioned in Git (decision D6 in `docs/decisions.md`).

### OPENROWSET(BULK ..., SINGLE_CLOB)

- **What it is:** a way to read a whole file as one block of text from inside a query, without loading it into a table.
- **Where it was used:** to inspect the CSV (header, number of columns, line endings) when `BULK INSERT` failed.

### Collation

- **What it is:** the rules for comparing and sorting text in a database.
- **In this project:** `Modern_Spanish_CI_AI` means Spanish rules, case-insensitive and accent-insensitive: `Mexico` equals `México` and `TELCEL` equals `Telcel`, while `ñ` stays different from `n`.
- **Effect on counts and keys:** `COUNT(DISTINCT ...)` and `GROUP BY` treat values that differ only in case or accents as the same value. Here, `PFC.YUC.B.3/001619-2024` and `PFC.yUC.B.3/001619-2024` looked like one ID, so `COUNT(DISTINCT expediente)` gave 36,032 instead of 36,034. It also explains why Power Query (which compares exact text) found 486 legal names and SQL found 477.
- **Exact comparison:** adding `COLLATE Latin1_General_BIN2` to a column compares the exact characters, for example `COUNT(DISTINCT expediente COLLATE Latin1_General_BIN2)`.

### Schema

- **What it is:** a folder inside a database that groups tables.
- **In this project:** `stg`, `clean` and `mart`, one per layer of the pipeline.

### TRY_CONVERT

- **What it is:** a function that tries to convert a value to another type (for example text to number) and returns `NULL` instead of an error when it cannot.
- **Where it is used:** to find and later clean values such as `-` in amount columns.

### Empty text and dates

- **What it is:** an empty text (`''`) is not `NULL`. Converted to a date, an empty text becomes `1900-01-01` instead of an error or `NULL`.
- **Where it matters here:** the 66 cases without close date. `step_3.sql` writes `NULLIF(text, '')` before `TRY_CONVERT`, so an empty value becomes `NULL` and never a false date.

### CTE (common table expression)

- **What it is:** a named step written with `WITH name AS (SELECT ...)`. The next query reads it as if it were a table.
- **Where it is used:** `step_3.sql` builds the clean table in steps (`c`, `s`, `r`): trim and convert, fix and join, derive groups. Each step is short and can be checked alone.

### Surrogate key

- **What it is:** a number the project assigns to each row, with no meaning of its own, used as its identifier.
- **Where it is used:** `complaint_key` in `clean.profeco_complaint`. `case_id` cannot be the key because 2 case IDs appear for two providers each (4 rows).

### Window function and ROW_NUMBER

- **What it is:** a function that calculates a value for each row looking at a group of rows, without collapsing them into one row as `GROUP BY` does. `ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)` numbers the rows inside each group.
- **Where it is used:** `step_6.sql` numbers the rows of each group of identical rows; the number 2 or higher marks a surplus copy (`flag_exact_copy`). The surrogate keys (`complaint_key`, `access_key`) are also built with `ROW_NUMBER()`.

### Anti-join

- **What it is:** a query that returns the rows of one table that have **no** match in another, for example `LEFT JOIN ... WHERE right.key IS NULL`.
- **Where it was used:** the overlap audit of the five PROFECO cuts (`step_4.sql`, decision D4) looked for cases of the older cuts that are missing in the base cut. The result was none.

## Data architecture

### Staging (`stg`) and raw layer

- **What it is:** the table where the data arrive exactly as they are in the file, all as text, with no cleaning. It is the starting point that can always be compared against.

### Medallion architecture (bronze, silver, gold)

- **What it is:** a way of organizing data in layers that improve in quality: bronze (raw), silver (cleaned) and gold (ready for analysis).
- **In this project:** `stg` is bronze, `clean` is silver and `mart` is gold. See decision D5 in `docs/decisions.md`.

### ELT and ETL

- **ETL:** extract, transform, then load. The cleaning happens before the data reach the database.
- **ELT:** extract, load, then transform. The raw data are loaded first and cleaned inside the database with SQL.
- **In this project:** ELT, so the raw data stay available and every cleaning rule is a documented script (decisions D2 and D5 in `docs/decisions.md`).

## Data analysis

### Placeholder value

- **What it is:** a value that stands for "no data", such as `-` or `sin dato`, instead of an empty cell.
- **Handling:** converted to `NULL` in the clean layer, never in the raw layer.

### Right-censoring

- **What it is:** a bias that appears when only finished cases are in the data, so the cases that are still open (the slowest ones) are missing.
- **Where it matters here:** the file contains closed cases only, so resolution times can look shorter than reality.

### Grain

- **What it is:** what one row of a table represents (for example "one complaint" or "one operator group, in one state, in one month").
- **Why it matters:** if the grain is not known, a sum can count the same thing twice. It is checked by counting how many rows share the same key.
- **Where it mattered here:** in the BIT, year, month, state, municipality, technology and company do not identify one row: 36,562 keys repeat. The rows turned out to be separate records and are all added (decision D12).

### Repeated key and exact copy

- **Repeated key:** several rows with the same values in the columns chosen as the key. They can be different records.
- **Exact copy:** rows identical in **all** columns, accesses included. They can be the same record loaded twice, or a coincidence between small values.
- **In this project:** 325 groups of exact copies in the BIT (0.05% of the rows). They are kept and flagged, and their weight in December 2024 is 0.0009% (decision D12).

### Flag

- **What it is:** a column with value 1 or 0 that marks a row for a condition without deleting it.
- **Where it is used:** `flag_missing_accesses`, `flag_no_state`, `flag_no_municipality` and `flag_exact_copy` in `clean.bit_access`, and `flag_central_office` in `clean.profeco_complaint`. Analyses can include or exclude the marked rows.

### Sentinel code

- **What it is:** a code that stands for "no information" inside a column that normally holds real codes.
- **In the BIT:** state `99` and municipality `999`. They are kept and flagged, and are left out of the rates by state.

### Stock and flow

- **Stock:** an amount measured at one moment (accesses at the end of a month). Adding two months counts the same accesses twice.
- **Flow:** an amount that happens during a period (complaints filed in a month). It can be added across months.
- **Where it matters here:** `A_TOTAL_E` of the BIT is a stock, so the denominators use December of each year and never add months.

### Access (BIT) and subscription

- **What it is:** the BIT counts **accesses** to fixed broadband service reported by each provider. It is not a count of customers or subscriptions, and one customer can hold more than one access.
- **In this project:** "accesses" is the term used in the tables, the dashboard and the documents.

### Denominator and rate per 100,000 accesses

- **What it is:** a rate divides a count (complaints) by a base (accesses) so providers of different size can be compared. The base is the denominator, and the result is multiplied by 100,000 to read it as "complaints per 100,000 accesses".
- **Where it is used:** the denominators are the accesses of Telmex, Izzi, Megacable and Total Play at the end of December. The BIT file ends in December 2024, so the rates cover 2022 to 2024.

### Star schema, fact table and dimension table

- **What it is:** a way of organizing data for analysis. A **fact table** has one row per event or measurement (a complaint, the accesses of a month) with numbers to add or count. A **dimension table** describes the context of the facts (date, state, operator). The fact table points to each dimension by a key, and the picture looks like a star.
- **Why it is used:** Power BI filters the facts through the dimensions, so a chart by operator or by year needs no extra logic.
- **In this project:** `fact_complaint` and `fact_accesses` in the `mart` schema, with six dimensions (decision D14).

### Conformed dimension

- **What it is:** one dimension shared by several fact tables, so their numbers can be put side by side.
- **Where it is used:** `dim_operator`, `dim_state` and `dim_date` are shared by complaints and accesses. That is what allows dividing complaints by accesses for the same operator and year. `dim_brand` is not shared because the BIT has no brand.

### Foreign key

- **What it is:** a column that holds the key of a row of another table (for example `operator_key` in `fact_complaint`). The database rejects a value that does not exist in that table.
- **Where it is used:** all the keys of the two fact tables, so there are no orphan rows (check 7.3d).

### Censoring and truncation

- **Right-censoring:** the data stops before every case has ended. Here the file has only closed cases, so the cases still open are missing and the recent filing years show mostly their fast cases.
- **Left-truncation:** the data starts after some cases began. Here the file has no case filed before 2022, so the close years 2022 and 2023 miss the long cases.
- **Where it mattered:** it decided the time axis of the duration (filing year, decision D15) and the reason why 2025 and 2026 are marked as incomplete.

### Median and percentile (P90)

- **What it is:** the median is the value that leaves half of the cases below it. The P90 is the value that leaves 90% of the cases below it, so it shows how long the slowest tenth takes. Both resist extreme values better than the average.
- **Where it is used:** the duration KPIs (`PERCENTILE_CONT` in `step_8.sql`; `PERCENTILE.INC` in DAX). A median of 35 days and a P90 of 138 days mean that half of the cases close within 35 days and nine of ten within 138.

### Cohort

- **What it is:** a group of cases that share the same starting period, here the filing year. A cohort is followed until its cases end.
- **Where it is used:** the duration and the outcomes are read by filing-year cohort, the same axis as the volume and the rates per 100,000 accesses (decision D15).

### Service-level target (SLA)

- **What it is:** a time limit for a service (for example "closed within 60 days") and the share of cases that meet it.
- **In this project:** PROFECO has no official target for the conciliation time, so the targets are parameters (30, 60, 90, 120 and 180 days, default 60) and the report shows how the share changes with each one (decision D15).

### Derived table, CROSS APPLY and view

- **Derived table:** a subquery written in the `FROM` clause and given a name. It does the same as a CTE (SQL Server runs both in the same way), but it is written inside the query. It is used when the language requires it, for example to sort the result of a `SELECT DISTINCT` by an expression (`step_8.sql`).
- **`CROSS APPLY (VALUES ...)`:** repeats each row once for every value listed. In `step_8.sql` it adds the rows "All four operators" and "All years" to a result without a second query.
- **View:** a saved query that is read like a table and stores no data. `mart.v_duration_cases` keeps the population of the duration measures in one place, so every check uses the same rules.
- **Style rule of the project:** CTE for more than one level of logic, derived table only when required, temporary table only for an expensive result that is read more than once (`sql/README.md`).


## Power BI and DAX

### Measure and calculated column

- **What it is:** a measure is a formula evaluated at query time, in the context of the filters of each visual (for example `Median Days to Close`). A calculated column is evaluated once per row at refresh and stored in the table (for example `Is Duration Case`).
- **Where it is used:** the business logic is in measures; the calculated column is used only for the population of the duration (decision D16). Measures are grouped in display folders (Volume, Duration, Outcomes, Service Level, Accesses and rate, Data quality).

### Filter context and CALCULATE

- **What it is:** the set of filters that apply to a cell of a visual (the row, the column, the slicers). `CALCULATE` evaluates an expression after changing that context.
- **Where it is used:** `Duration Cases = CALCULATE(COUNTROWS(...), fact_complaint[Is Duration Case] = 1)`. `KEEPFILTERS` adds a filter without replacing the existing one, so the legend of a chart still splits the bars (`Valid Outcome Cases`).

### HASONEVALUE, ISINSCOPE and ISFILTERED

- **What it is:** functions that tell a measure how it is being read: with one value selected, at which level of a hierarchy, or with a filter applied.
- **Where it is used:** `Complaints per 100k Accesses` returns blank by month, by state or with several years selected, because the denominator is a national December stock (D8, D12 and D16).

### Parameter table (disconnected table)

- **What it is:** a table with no relationship to the model, used only to let the reader choose a value. A measure reads the choice with `SELECTEDVALUE`.
- **Where it is used:** `SLA Target` (30, 60, 90, 120 and 180 days, default 60) drives `% Within SLA` and the dynamic title of page 2.

### Active and inactive relationship, USERELATIONSHIP

- **What it is:** only one relationship between two tables can be active. An inactive one is used by a measure that asks for it with `USERELATIONSHIP`.
- **Where it is used:** `fact_complaint` has two dates: the filing date (active, the axis of the report, D15) and the close date (inactive).

### Star schema in Power BI: single direction

- **What it is:** each filter flows from the dimension (one side) to the fact (many side). Two fact tables share dimensions but are not related to each other.
- **Where it is used:** 10 many-to-one single-direction relationships; complaints and accesses are compared only through the shared dimensions and in measures (D14 and D16).

### Import mode

- **What it is:** Power BI copies the data into the file. The report works offline and is fast, but the `.pbix` contains the imported rows.
- **Where it is used:** because the file holds row-level complaints and monthly BIT accesses, it is not versioned and only the PDF and the screenshots are published (D16).

## Institutions and sources: consumer protection (government)

### PROFECO (Procuraduría Federal del Consumidor)

- **What it is:** the federal consumer protection agency of México. It receives the complaints of consumers against providers and tries to settle them (conciliation).
- **Where it is used:** the publisher of the complaints file (*Quejas en materia de telecomunicaciones*, CC BY 4.0). Every complaint, outcome and duration of the project comes from it (`docs/sources/MX_profeco.md`, decisions D1 to D9).

### PROFECO office (ODECO) and central office (office H)

- **What it is:** each complaint is handled by a PROFECO office (zone). The file names it in the column `odeco` and the office code is the second part of the case ID (for example `PFC.YUC.B.3/...` gives `YUC`).
- **Where it is used:** the "state" of a complaint is the state of the office, not of the consumer (D8). Office `H` is the central office that handles telecom cases (written "Dir. Gral. Cons. Telecom" or "Dgpct" in the file): it holds 54.9% of all complaints and 49.6% of the fixed broadband cases. `flag_central_office` marks it.

### Conciliation, Queja and the other legal procedures

- **What it is:** the procedure group of a case. In a *conciliation* PROFECO mediates between the consumer and the provider; a *Queja* is a complaint that follows a different route; the *other legal procedures* are few (for example infraction proceedings).
- **Where it is used:** the duration and the outcome measures use only the Conciliation group (`procedure_group`, D15); the other groups stay in the tables.

## Institutions and sources: telecommunications regulation and statistics (government)

### CRT (Comisión Reguladora de Telecomunicaciones)

- **What it is:** the federal telecommunications regulator of México. It replaced the IFT and now publishes the BIT.
- **Where it is used:** the publisher of the BIT file that gives the denominators (accesses). The CRT is not the author of this analysis and does not endorse it (`docs/sources/licenses.md`).

### IFT (Instituto Federal de Telecomunicaciones)

- **What it is:** the former telecommunications regulator, replaced by the CRT.
- **Where it is used:** it wrote the *Manual de Definiciones de Indicadores Estadísticos* (2018), the data dictionary of the BIT, and appears in the older reports and guidelines listed in the README references. The delay of the BIT after the change from IFT to CRT is a possible reason for the series ending in December 2024 (`docs/sources/MX_profeco.md`).

### BIT (Banco de Información de Telecomunicaciones)

- **What it is:** the open statistics portal of the CRT, with indicators of the telecom sector by operator, state and month.
- **Where it is used:** the table `TD_ACC_BAF_ITE_VA` (fixed broadband accesses by operator group and state, January 2013 to December 2024) feeds `stg.bit_acc_baf`, `clean.bit_access` and `mart.fact_accesses`. It has no explicit license, so only aggregates are published (D10).

### INEGI (Instituto Nacional de Estadística y Geografía)

- **What it is:** the national statistics and geography institute of México.
- **Where it is used:** its state codes (01 to 32; 99 here means "no information") are the key of `clean.state_map` and `mart.dim_state`, the same in the complaints and in the BIT.

### "Soy Usuario" reports and IFT quality guidelines

- **What it is:** quarterly reports for telecom users and the quality guidelines for fixed services, both of the IFT and the CRT.
- **Where it is used:** listed in the README as references for cross-validation and for context of benchmarks; they are not loaded in the database.

## Institutions and sources: open data and licenses

### datos.gob.mx

- **What it is:** the open data portal of the Government of México.
- **Where it is used:** it hosts the PROFECO dataset and its resources (the file of June 2026 and the earlier cuts), with the license field of each resource.

### CC BY 4.0 (Creative Commons Attribution 4.0)

- **What it is:** a license that allows the use and the modification of the data if the author is named, the changes are indicated and no endorsement is suggested.
- **Where it is used:** the license of the PROFECO dataset. It sets the citation of the README and of the footer of every page of the report (`docs/sources/licenses.md`).

### MIT License

- **What it is:** a permissive license for software: it allows the use, the copy and the modification of the code if the notice is kept.
- **Where it is used:** the license of the code and the documentation of this repository. The data keep the license of their publisher.

## Operators and groups (private sector)

### América Móvil, Telmex and Telcel

- **What it is:** América Móvil is the telecom group that owns Telmex (fixed network) and Telcel (mobile).
- **Where it is used:** Telmex is one of the four operators of the analysis; its BIT group is AMÉRICA MÓVIL. Telcel appears in the complaints as a mobile brand and stays out of the scope of the fixed broadband analysis (`network_type`, D11).

### Izzi and Grupo Televisa

- **What it is:** Izzi is the cable and internet brand of Grupo Televisa.
- **Where it is used:** the denominator of Izzi is the BIT group GRUPO TELEVISA without the company SKY, because Sky is satellite TV (decided in step 4).

### Megacable and Total Play

- **What they are:** two large providers of fixed internet, TV and telephony.
- **Where they are used:** with Telmex and Izzi they are the four operators of the analysis (D11): 99.3% of the 13,358 fixed broadband complaints. The rest of the fixed brands are grouped as "Other".

### Sky and Dish

- **What they are:** pay TV providers by satellite.
- **Where they are used:** classified as `Pay TV (satellite)` in `clean.brand_map`, outside the fixed broadband scope.

## Other projects and data sources considered

### FCC MBA (Measuring Broadband America)

- **What it is:** the broadband performance program of the US Federal Communications Commission.
- **Where it is used:** the data of the first capstone (FTTH quality of experience). It was discarded as a source for this project (D1).

### NYC 311

- **What it is:** the New York City service request line and its open dataset of requests with opening and closing dates.
- **Where it is used:** the US fallback of decision D1; it was not chosen because the México telecom dataset fits the author's domain.