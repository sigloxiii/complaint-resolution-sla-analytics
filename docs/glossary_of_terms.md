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
- **Rule for this project:** raw files are never edited, so the script adapts to the file, not the other way around.

### CSV (comma-separated values)

- **What it is:** a text file where each line is a row and commas separate the columns.
- **Quoted fields:** text that contains a comma or a line break is wrapped in double quotes (`"`). `FIELDQUOTE = '"'` tells `BULK INSERT` to respect them.
- **Check used here:** the number of double quotes in the file must be even; an odd number means a quote was left open.

### UTF-8 and code page

- **What it is:** UTF-8 is a text encoding that represents accents and characters such as *ñ*. A *code page* is the number SQL Server uses to name an encoding; UTF-8 is `65001`.
- **Where it mattered here:** `CODEPAGE = '65001'` in `step_1.sql`, so that *México* and *Telefonía* load without damaged characters.

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

### Schema

- **What it is:** a folder inside a database that groups tables.
- **In this project:** `stg`, `clean` and `mart`, one per layer of the pipeline.

### TRY_CONVERT

- **What it is:** a function that tries to convert a value to another type (for example text to number) and returns `NULL` instead of an error when it cannot.
- **Where it is used:** to find and later clean values such as `-` in amount columns.

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