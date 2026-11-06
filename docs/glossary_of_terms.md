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