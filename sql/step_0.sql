-- =====================================================================
-- step_0.sql
-- Objective : create the project database and the three layers through
--             which the data will travel: stg -> clean -> mart.
-- Source    : none. This script is the same for any dataset.
-- How to run: open it in SSMS, connect to .\SQLEXPRESS and press F5.
--             Run it ONCE. If you run it again it fails with an
--             "already exists" error, which is harmless.
--             it is assumed the DB doesn´t exists
-- To start over: in SSMS, right-click the database "complaint_sla" ->
--             Delete, then run this script again.
-- =====================================================================

-- About "GO": it is not SQL. It is a separator that SSMS understands.
-- It sends everything above it to the server as one group (a "batch")
-- before reading the next lines. Some commands, like CREATE SCHEMA,
-- must be alone in their batch. That is why GO appears so often.

-- "master" is the system database. We start here to create a new database.
USE master;
GO

-- COLLATE sets the rules used to compare and sort text in the database.
-- Modern_Spanish_CI_AI means: Spanish rules, Case-Insensitive,
-- Accent-Insensitive. So 'Mexico' = 'México' and 'TELCEL' = 'Telcel'
-- are treated as equal, while 'ñ' is still a different letter than 'n'.
-- The database files are created in the default SQL Server folder (drive C:).
CREATE DATABASE complaint_sla COLLATE Modern_Spanish_CI_AI;
GO

-- From now on, every command runs inside the database.
USE complaint_sla;
GO

-- A schema works like a folder inside the database: it groups tables.
-- We use one per layer, so the table name tells you what it contains.

-- stg   (staging): raw data exactly as it comes in the file, all as text.
CREATE SCHEMA stg;
GO

-- clean: the same data with correct types (dates, numbers) and fixed values.
CREATE SCHEMA clean;
GO

-- mart: final tables, prepared for Power BI.
CREATE SCHEMA mart;
GO

-- Check 1: the database collation. Expected: Modern_Spanish_CI_AI
SELECT DATABASEPROPERTYEX('complaint_sla', 'Collation') AS database_collation;

-- Check 2: the three schemas. Expected: stg, clean and mart.
SELECT name AS schema_name
FROM sys.schemas
WHERE name IN ('stg', 'clean', 'mart');