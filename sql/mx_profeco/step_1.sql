-- =====================================================================
-- step_1.sql   (source: PROFECO telecom complaints, México)
-- Objective : load the raw CSV file into the staging table as TEXT.
--             Nothing is converted or cleaned here: what is in the file
--             is what goes into the table.
-- File      : quejas_telecomunicaciones_2022_junio_2026.csv
--             (23 columns, UTF-8 encoding, 36,034 rows expected)
-- Needs     : step_0.sql already executed, and the CSV saved in
--             D:\Capstone SLA\data\raw\
--             (that folder is ignored by Git, so the data is not uploaded).
-- How to run: open in SSMS and press F5.
-- WARNING   : running it again deletes the table and loads it again.
-- =====================================================================

USE complaint_sla;
GO

-- Delete the table if it already exists, so the script can be run again.
DROP TABLE IF EXISTS stg.profeco_raw;
GO

-- CREATE TABLE defines the columns. The order MUST be the same as in the
-- CSV file, because BULK INSERT matches columns by position, not by name.
-- NVARCHAR(n) = text of up to n characters, with accents and ñ supported.
-- Every column is text on purpose: dirty values (a "-" inside an amount,
-- an unusual date) will load without errors and we can inspect them in SQL.
CREATE TABLE stg.profeco_raw (
    expediente          NVARCHAR(50),    -- case ID
    fecha_ingreso       NVARCHAR(30),    -- filing date (still text)
    fecha_cierre        NVARCHAR(30),    -- close date (still text)
    tipo_conciliacion   NVARCHAR(200),
    estado_procesal     NVARCHAR(100),   -- outcome: Conciliada, Desistimiento, ...
    proveedor           NVARCHAR(400),   -- provider legal name
    nombre_comercial    NVARCHAR(400),   -- provider brand (Telcel, Izzi, ...)
    giro                NVARCHAR(400),
    sector              NVARCHAR(200),
    odeco               NVARCHAR(200),
    estado              NVARCHAR(100),   -- state
    tipo_reclamacion    NVARCHAR(300),
    motivo_reclamacion  NVARCHAR(400),
    costo_bien_servicio NVARCHAR(50),    -- amounts (still text)
    monto_reclamado     NVARCHAR(50),
    monto_recuperado    NVARCHAR(50),
    procedimiento       NVARCHAR(200),
    medio_ingreso       NVARCHAR(200),
    clase               NVARCHAR(200),
    tipo_producto       NVARCHAR(200),
    modalidad_compra    NVARCHAR(200),
    modalidad_pago      NVARCHAR(200),
    problema_especial   NVARCHAR(200)
);
GO

-- BULK INSERT reads the file and fills the table.
-- IMPORTANT: the file is read by the SQL Server service, so the
-- path must be reachable from the computer where SQL Server runs.
BULK INSERT stg.profeco_raw
FROM 'D:\Capstone SLA\data\raw\quejas_telecomunicaciones_2022_junio_2026.csv'
WITH (
    FORMAT     = 'CSV',    -- the file is a standard CSV (commas between fields)
    FIELDQUOTE = '"',      -- text between double quotes may contain commas
    FIRSTROW   = 2,        -- row 1 is the header with column names: skip it
    CODEPAGE   = '65001'   -- 65001 = UTF-8, so accents (é, ñ) load correctly
);
GO

-- Check: how many rows were loaded? Expected: 36034 (same as Power Query).
SELECT COUNT(*) AS n_rows
FROM stg.profeco_raw;

-- Check: look at the first rows to confirm each value is in the right column.
SELECT TOP 5 *
FROM stg.profeco_raw;

-- ---------------------------------------------------------------------
-- If something fails:
-- * "Operating system error code 5 (Access is denied)":
--     the SQL Server service cannot read the folder. In Windows Explorer,
--     give READ permission on D:\Capstone SLA\data\raw to the account
--     NT SERVICE\MSSQL$SQLEXPRESS and run the script again.
-- * "Bulk load data conversion error (truncation)":
--     some text is longer than its column. Increase the NVARCHAR size of
--     the column named in the message and run the script again.
-- * Only one row (or a wrong count) is loaded:
--     the file may use LF-only line endings. Add this line inside the
--     WITH ( ... ) list, after CODEPAGE (remember the comma):
--         ROWTERMINATOR = '0x0a'
-- ---------------------------------------------------------------------