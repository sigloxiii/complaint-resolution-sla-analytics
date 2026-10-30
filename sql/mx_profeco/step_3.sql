-- =====================================================================
-- step_3.sql   (source: PROFECO telecom complaints, México)
-- Objective : build the CLEAN layer. It reads stg.profeco_raw (text) and
--             writes clean.profeco_complaint with correct types, normalized
--             values and quality flags. stg is never modified.
-- Grain     : one row per case AND provider (36,034 rows, same as stg).
-- Needs     : step_1.sql executed (stg.profeco_raw loaded).
-- How to run: open in SSMS and press F5. It runs in about a second.
-- WARNING   : running it again deletes and rebuilds the three clean tables.
-- Revision 2 (2026-10-27): more brand categories, office_code and
--             flag_central_office (results of checks 3.3.6 and 3.3.12).
--
-- Every rule below comes from evidence recorded in
-- docs/sources/MX_profeco.md (blocks of step_2.sql) and decision D7.
--
-- Quick guide to the commands used here (new compared with step_2.sql):
--   CREATE TABLE / INSERT   create a table and fill it
--   CASE WHEN ... THEN ...  chooses a value depending on a condition
--   NULLIF(a, b)            returns NULL when a equals b (turns "" into NULL)
--   LTRIM / RTRIM           remove spaces at the start / end of a text
--   TRY_CONVERT(type, x)    converts x, and gives NULL (not an error) if it fails
--   LEFT JOIN               adds columns from another table when there is a match
--   WITH name AS (...)      a named step (CTE) that the next query can read
--   ROW_NUMBER() OVER (...) numbers the rows: 1, 2, 3, ...
--   COUNT(*) OVER (PARTITION BY x)   counts the rows that share the same x,
--                                    without collapsing them like GROUP BY
-- =====================================================================

USE complaint_sla;
GO

-- ---------------------------------------------------------------------
-- 3.1 REFERENCE TABLES (small lookup tables, filled by this script)
-- Why: the file writes the same brand or state in several ways. A lookup
-- table says, in one visible place, how each written form is normalized.
-- The database collation ignores case and accents, so "TELCEL", "telcel"
-- and "Télcel" match the same row.
-- ---------------------------------------------------------------------

-- Brand table. operator_group uses the name of the group in the BIT
-- (column GRUPO of TD_ACC_BAF_ITE_VA), so subscribers can be joined later.
-- network_type: Fixed = fixed-network operator (including satellite internet),
--   Mobile = mobile operator, Pay TV (satellite) = Sky and Dish (they sell no
--   internet, so they have NO operator_group: joining them to the BIT accesses
--   would count the same customers twice), Device maker = phone and device
--   brands (the complaint is about a device, not about a network).
-- Brands that are not listed here keep their own name and get
-- network_type = 'Not classified' (check 3.3.6 lists the biggest ones).
DROP TABLE IF EXISTS clean.brand_map;
CREATE TABLE clean.brand_map (
    brand_raw       NVARCHAR(200) NOT NULL PRIMARY KEY, -- as written in the file
    brand           NVARCHAR(100) NOT NULL,             -- normalized brand
    operator_group  NVARCHAR(100) NULL,                 -- group name in the BIT
    network_type    NVARCHAR(30)  NOT NULL
);

INSERT INTO clean.brand_map (brand_raw, brand, operator_group, network_type)
VALUES
    (N'Telmex',       N'Telmex',        N'AMÉRICA MÓVIL',  N'Fixed'),
    (N'Izzi',         N'Izzi',          N'GRUPO TELEVISA', N'Fixed'),
    (N'Megacable',    N'Megacable',     N'MEGACABLE-MCM',  N'Fixed'),
    -- Total Play is written two ways in the file (both are the same company).
    -- Its BIT group is GRUPO SALINAS. PENDING: confirm in the BIT file that the
    -- rows with EMPRESA = TotalPlay have GRUPO = GRUPO SALINAS.
    (N'Totalplay',    N'Total Play',    N'GRUPO SALINAS',  N'Fixed'),
    (N'Total Play',   N'Total Play',    N'GRUPO SALINAS',  N'Fixed'),
    (N'Telcel',       N'Telcel',        N'AMÉRICA MÓVIL',  N'Mobile'),
    (N'Movistar',     N'Movistar',      N'TELEFÓNICA',     N'Mobile'),
    (N'At&t',         N'AT&T',          N'AT&T',           N'Mobile'),
    -- Same brand written two ways (step_2.sql, block 2.9).
    (N'Virgin',       N'Virgin Mobile', NULL,              N'Mobile'),
    (N'Virgin Mobile',N'Virgin Mobile', NULL,              N'Mobile'),
    -- Smaller operators seen in check 3.3.6. operator_group is filled only when
    -- the exact name was seen in the BIT (column GRUPO); otherwise it stays NULL.
    (N'Axtel',        N'Axtel',         N'AXTEL',          N'Fixed'),
    (N'Gigacable',    N'Gigacable',     NULL,              N'Fixed'),
    (N'Telecable',    N'Telecable',     NULL,              N'Fixed'),
    (N'Newww',        N'Newww',         N'NEWWW',          N'Fixed'),
    (N'Starlink',     N'Starlink',      N'SPACEX-STARLINK',N'Fixed'),
    (N'Bait',         N'Bait',          NULL,              N'Mobile'),
    (N'Sky',          N'Sky',           NULL,              N'Pay TV (satellite)'),
    (N'Dish',         N'Dish',          NULL,              N'Pay TV (satellite)'),
    -- Device makers (the biggest ones in check 3.3.6).
    (N'Samsung',      N'Samsung',       NULL,              N'Device maker'),
    (N'Motorola',     N'Motorola',      NULL,              N'Device maker'),
    (N'Apple',        N'Apple',         NULL,              N'Device maker'),
    (N'Xiaomi',       N'Xiaomi',        NULL,              N'Device maker'),
    (N'Zte',          N'ZTE',           NULL,              N'Device maker'),
    (N'Huawei',       N'Huawei',        NULL,              N'Device maker'),
    (N'Honor',        N'Honor',         NULL,              N'Device maker'),
    (N'Oppo',         N'Oppo',          NULL,              N'Device maker'),
    (N'Alcatel',      N'Alcatel',       NULL,              N'Device maker'),
    (N'Lg',           N'LG',            NULL,              N'Device maker'),
    (N'Hisense',      N'Hisense',       NULL,              N'Device maker'),
    (N'Telmov',       N'Telmov',        NULL,              N'Not classified'),
    (N'Telmovil',     N'Telmov',        NULL,              N'Not classified'),
    -- Generic values: they do not name a provider.
    (N'Otros',        N'Not identified', NULL,             N'Not classified'),
    (N'Otro',         N'Not identified', NULL,             N'Not classified'),
    (N'P. Moral',     N'Not identified', NULL,             N'Not classified'),
    (N'P. Física',    N'Not identified', NULL,             N'Not classified');
GO

-- State table. state_code is the INEGI code (01 to 32), the same code that
-- the BIT uses in K_ENTIDAD, so complaints and subscribers join by state.
-- Some states are listed with more than one written form.
-- Check 3.3.7 lists any state text of the file that is not matched here.
DROP TABLE IF EXISTS clean.state_map;
CREATE TABLE clean.state_map (
    state_raw   NVARCHAR(100) NOT NULL PRIMARY KEY, -- as written in the file
    state_code  CHAR(2)       NOT NULL,             -- INEGI code
    state_name  NVARCHAR(60)  NOT NULL              -- normalized name
);

INSERT INTO clean.state_map (state_raw, state_code, state_name)
VALUES
    (N'Aguascalientes',      '01', N'Aguascalientes'),
    (N'Baja California',     '02', N'Baja California'),
    (N'Baja California Sur', '03', N'Baja California Sur'),
    (N'Campeche',            '04', N'Campeche'),
    (N'Coahuila',            '05', N'Coahuila'),
    (N'Coahuila de Zaragoza','05', N'Coahuila'),
    (N'Colima',              '06', N'Colima'),
    (N'Chiapas',             '07', N'Chiapas'),
    (N'Chihuahua',           '08', N'Chihuahua'),
    (N'Ciudad de México',    '09', N'Ciudad de México'),
    (N'CDMX',                '09', N'Ciudad de México'),
    (N'Distrito Federal',    '09', N'Ciudad de México'),
    (N'Durango',             '10', N'Durango'),
    (N'Guanajuato',          '11', N'Guanajuato'),
    (N'Guerrero',            '12', N'Guerrero'),
    (N'Hidalgo',             '13', N'Hidalgo'),
    (N'Jalisco',             '14', N'Jalisco'),
    (N'México',              '15', N'Estado de México'),
    (N'Estado de México',    '15', N'Estado de México'),
    (N'Edo. de México',      '15', N'Estado de México'),
    (N'Michoacán',           '16', N'Michoacán'),
    (N'Michoacán de Ocampo', '16', N'Michoacán'),
    (N'Morelos',             '17', N'Morelos'),
    (N'Nayarit',             '18', N'Nayarit'),
    (N'Nuevo León',          '19', N'Nuevo León'),
    (N'Oaxaca',              '20', N'Oaxaca'),
    (N'Puebla',              '21', N'Puebla'),
    (N'Querétaro',           '22', N'Querétaro'),
    (N'Querétaro de Arteaga','22', N'Querétaro'),
    (N'Quintana Roo',        '23', N'Quintana Roo'),
    (N'San Luis Potosí',     '24', N'San Luis Potosí'),
    (N'Sinaloa',             '25', N'Sinaloa'),
    (N'Sonora',              '26', N'Sonora'),
    (N'Tabasco',             '27', N'Tabasco'),
    (N'Tamaulipas',          '28', N'Tamaulipas'),
    (N'Tlaxcala',            '29', N'Tlaxcala'),
    (N'Veracruz',            '30', N'Veracruz'),
    (N'Veracruz de Ignacio de la Llave', '30', N'Veracruz'),
    (N'Yucatán',             '31', N'Yucatán'),
    (N'Zacatecas',           '32', N'Zacatecas');
GO

-- ---------------------------------------------------------------------
-- 3.2 CLEAN TABLE
-- Column names are in English; the values keep the language of the source
-- when they are labels of the publisher (for example outcome).
-- Columns that start with flag_ are 1 (yes) or 0 (no). A flagged row is
-- NOT deleted: the flag lets each KPI decide what to exclude.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clean.profeco_complaint;
CREATE TABLE clean.profeco_complaint (
    complaint_key           INT           NOT NULL PRIMARY KEY, -- own ID of each row (surrogate key)
    case_id                 NVARCHAR(50)  NULL,   -- expediente, in upper case. NOT unique: see flag_shared_case_id
    filing_date             DATE          NULL,
    close_date              DATE          NULL,
    days_to_close           INT           NULL,   -- only when flag_valid_duration = 1
    outcome                 NVARCHAR(100) NULL,   -- estado_procesal (Conciliada, Desistimiento, ...)
    conciliation_type       NVARCHAR(50)  NULL,   -- Electronic means / In person / Telephone / ...
    procedure_label         NVARCHAR(100) NULL,   -- procedimiento with cut labels completed
    procedure_group         NVARCHAR(30)  NOT NULL, -- Conciliation / Queja / Other legal procedure / Not identified
    provider_legal_name     NVARCHAR(400) NULL,
    brand_raw               NVARCHAR(400) NULL,   -- nombre_comercial as loaded (trimmed)
    brand                   NVARCHAR(200) NOT NULL,
    operator_group          NVARCHAR(100) NULL,   -- group name in the BIT (only for mapped brands)
    network_type            NVARCHAR(30)  NOT NULL, -- Fixed / Mobile / Pay TV (satellite) / Device maker / Not classified
    giro                    NVARCHAR(400) NULL,   -- descriptive only (it classifies the provider, see D7)
    state_raw               NVARCHAR(100) NULL,
    state_code              CHAR(2)       NULL,   -- INEGI code, NULL if the text is not in clean.state_map
    state_name              NVARCHAR(60)  NULL,
    claim_type              NVARCHAR(300) NULL,   -- tipo_reclamacion
    claim_reason            NVARCHAR(400) NULL,   -- motivo_reclamacion
    cost_amount             DECIMAL(18,2) NULL,   -- costo_bien_servicio
    claimed_amount          DECIMAL(18,2) NULL,   -- monto_reclamado
    recovered_amount        DECIMAL(18,2) NULL,   -- monto_recuperado (NULL = unknown, NOT zero)
    channel                 NVARCHAR(100) NULL,   -- medio_ingreso, after fixing swapped rows
    item_class              NVARCHAR(50)  NULL,   -- clase: Servicio or Bien, after fixing swapped rows
    product_type            NVARCHAR(200) NULL,
    purchase_mode           NVARCHAR(200) NULL,
    payment_mode            NVARCHAR(200) NULL,
    special_problem         NVARCHAR(200) NULL,   -- problema_especial as loaded
    service_hint            NVARCHAR(50)  NOT NULL, -- PARTIAL hint of the service (D7). Never use in headline KPIs
    flag_missing_close      BIT NOT NULL,         -- no close date
    flag_close_before_filing BIT NOT NULL,        -- close date earlier than filing date
    flag_cancelled          BIT NOT NULL,         -- outcome = Cancelada
    flag_swapped_columns    BIT NOT NULL,         -- clase and medio_ingreso were swapped and fixed
    flag_shared_case_id     BIT NOT NULL,         -- the same case_id appears for more than one provider
    flag_outcome_anomaly    BIT NOT NULL,         -- outcome text is not a valid outcome
    flag_unusual_close_day  BIT NOT NULL,         -- more than 100 cases closed on that date (possible batch closing)
    flag_valid_duration     BIT NOT NULL,         -- days_to_close can be used in duration KPIs
    office_code             NVARCHAR(10)  NULL,   -- PROFECO office, taken from case_id (PFC.YUC.B.3/... gives YUC)
    office_name             NVARCHAR(200) NULL,   -- odeco as loaded (meaning to be confirmed, check 3.3.16)
    flag_central_office     BIT NOT NULL          -- office H: cases handled centrally (the state is NOT where the consumer lives)
);
GO

-- Fill the table. The query is built in steps (CTEs); each step uses the
-- result of the previous one:
--   c : trims text, turns placeholders into NULL, converts dates and amounts
--   s : fixes the swapped columns and adds brand and state from the tables
--   r : adds the derived groups and counts that need to look at other rows
--   final SELECT : computes the flags and the days to close
WITH c AS (
    SELECT
        UPPER(NULLIF(LTRIM(RTRIM(expediente)), ''))                       AS case_id,
        -- NULLIF first: an empty text would be converted to 1900-01-01.
        -- Style 23 = year-month-day (2022-01-03), the format of this file.
        TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(fecha_ingreso)), ''), 23)   AS filing_date,
        TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(fecha_cierre)), ''), 23)     AS close_date,
        -- Placeholders "-" and "sin dato" mean "no value": they become NULL.
        NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(tipo_conciliacion)), ''), '-'), 'sin dato')  AS tipo_conciliacion,
        NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(estado_procesal)), ''), '-'), 'sin dato')    AS estado_procesal,
        NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(proveedor)), ''), '-'), 'sin dato')          AS proveedor,
        NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(nombre_comercial)), ''), '-'), 'sin dato')   AS nombre_comercial,
        NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(giro)), ''), '-'), 'sin dato')               AS giro,
        NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(odeco)), ''), '-'), 'sin dato')              AS odeco,
        NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(estado)), ''), '-'), 'sin dato')             AS estado,
        NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(tipo_reclamacion)), ''), '-'), 'sin dato')   AS tipo_reclamacion,
        NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(motivo_reclamacion)), ''), '-'), 'sin dato') AS motivo_reclamacion,
        -- Amounts: TRY_CONVERT gives NULL for "-", "sin dato" and "Oo".
        TRY_CONVERT(decimal(18, 2), NULLIF(LTRIM(RTRIM(costo_bien_servicio)), '')) AS cost_amount,
        TRY_CONVERT(decimal(18, 2), NULLIF(LTRIM(RTRIM(monto_reclamado)), ''))     AS claimed_amount,
        TRY_CONVERT(decimal(18, 2), NULLIF(LTRIM(RTRIM(monto_recuperado)), ''))    AS recovered_amount,
        -- In this column "0" is also a placeholder (5 rows, step_2.sql block 2.17).
        NULLIF(NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(procedimiento)), ''), '-'), 'sin dato'), '0') AS procedimiento,
        NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(medio_ingreso)), ''), '-'), 'sin dato')      AS medio_ingreso,
        NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(clase)), ''), '-'), 'sin dato')              AS clase,
        NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(tipo_producto)), ''), '-'), 'sin dato')      AS tipo_producto,
        NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(modalidad_compra)), ''), '-'), 'sin dato')   AS modalidad_compra,
        NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(modalidad_pago)), ''), '-'), 'sin dato')     AS modalidad_pago,
        NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(problema_especial)), ''), '-'), 'sin dato')  AS problema_especial
    FROM stg.profeco_raw
),
s AS (
    SELECT
        c.*,
        -- 430 rows (all of 2022) have a channel in clase and Servicio/Bien in
        -- medio_ingreso: the two columns are swapped (step_2.sql block 2.15).
        CASE WHEN c.clase IN ('Internet', 'Personal', 'Escrito', 'Correo Electrónico')
             THEN 1 ELSE 0 END                                   AS is_swapped,
        COALESCE(b.brand, c.nombre_comercial, 'Not identified')  AS brand,
        b.operator_group                                         AS operator_group,
        COALESCE(b.network_type, 'Not classified')               AS network_type,
        m.state_code                                             AS state_code,
        m.state_name                                             AS state_name
    FROM c
    LEFT JOIN clean.brand_map b ON b.brand_raw = c.nombre_comercial
    LEFT JOIN clean.state_map m ON m.state_raw = c.estado
),
r AS (
    SELECT
        s.*,
        -- Valid outcomes. Any other text (for example a conciliation type
        -- written in this column, 1 row) is not an outcome.
        CASE WHEN s.estado_procesal IN ('Conciliada', 'Desistimiento', 'No Conciliada',
                                        'Improcedente', 'Cancelada')
             THEN s.estado_procesal END                          AS outcome,
        CASE WHEN s.tipo_conciliacion LIKE 'Turnada a Concil Medios%' THEN 'Electronic means'
             WHEN s.tipo_conciliacion LIKE 'Turnada a Concil Person%' THEN 'In person'
             WHEN s.tipo_conciliacion LIKE 'Turnada a Concil Telef%'  THEN 'Telephone'
             -- En Proceso rows have final outcomes: it is not an open case (block 2.17).
             WHEN s.tipo_conciliacion = 'En Proceso'                  THEN 'Not assigned (En Proceso)'
             WHEN s.tipo_conciliacion = 'Cancelada'                   THEN 'Cancelled'
        END                                                      AS conciliation_type,
        -- Part of the labels is cut at 30 characters: complete the electronic one.
        CASE WHEN s.procedimiento LIKE 'Conciliaci_n Medios Electr%'
             THEN 'Conciliación Medios Electrónicos'
             ELSE s.procedimiento END                            AS procedure_label,
        CASE WHEN s.procedimiento LIKE 'Conciliaci%' THEN 'Conciliation'
             WHEN s.procedimiento = 'Queja'          THEN 'Queja'
             WHEN s.procedimiento IS NULL            THEN 'Not identified'
             ELSE 'Other legal procedure' END                    AS procedure_group,
        -- Partial hint of the service (decision D7): only from problema_especial.
        CASE WHEN s.problema_especial = 'Telefonía Móvil'       THEN 'Mobile telephony'
             WHEN s.problema_especial = 'Uso de Internet/datos' THEN 'Internet / data use'
             WHEN s.problema_especial = 'Internet'              THEN 'Internet'
             WHEN s.problema_especial = 'Television'            THEN 'Television'
             WHEN s.problema_especial = 'Telefonia'             THEN 'Telephony'
             ELSE 'Not specified' END                            AS service_hint,
        -- Windows over other rows: they cannot be written in the same step.
        -- The case ID starts with the office: PFC.YUC.B.3/001976-2024 -> YUC.
        -- Check 3.3.12 showed that estado is the state of that office.
        CASE WHEN s.case_id LIKE 'PFC.%.%'
             THEN SUBSTRING(s.case_id, 5, CHARINDEX('.', s.case_id, 5) - 5) END AS office_code,
        COUNT(*) OVER (PARTITION BY s.case_id)                   AS n_rows_same_case,
        COUNT(s.close_date) OVER (PARTITION BY s.close_date)     AS n_closed_same_day
    FROM s
)
INSERT INTO clean.profeco_complaint (
    complaint_key, case_id, filing_date, close_date, days_to_close,
    outcome, conciliation_type, procedure_label, procedure_group,
    provider_legal_name, brand_raw, brand, operator_group, network_type, giro,
    state_raw, state_code, state_name, claim_type, claim_reason,
    cost_amount, claimed_amount, recovered_amount,
    channel, item_class, product_type, purchase_mode, payment_mode,
    special_problem, service_hint,
    flag_missing_close, flag_close_before_filing, flag_cancelled,
    flag_swapped_columns, flag_shared_case_id, flag_outcome_anomaly,
    flag_unusual_close_day, flag_valid_duration,
    office_code, office_name, flag_central_office
)
SELECT
    -- Own ID. The order is fixed so the same data always gets the same numbers.
    ROW_NUMBER() OVER (ORDER BY r.case_id, r.proveedor, r.nombre_comercial,
                                r.filing_date, r.close_date)             AS complaint_key,
    r.case_id,
    r.filing_date,
    r.close_date,
    CASE WHEN r.filing_date IS NOT NULL AND r.close_date IS NOT NULL
              AND r.close_date >= r.filing_date
              AND COALESCE(r.outcome, '') <> 'Cancelada'
         THEN DATEDIFF(day, r.filing_date, r.close_date) END             AS days_to_close,
    r.outcome,
    r.conciliation_type,
    r.procedure_label,
    r.procedure_group,
    r.proveedor,
    r.nombre_comercial,
    r.brand,
    r.operator_group,
    r.network_type,
    r.giro,
    r.estado,
    r.state_code,
    r.state_name,
    r.tipo_reclamacion,
    r.motivo_reclamacion,
    r.cost_amount,
    r.claimed_amount,
    r.recovered_amount,
    CASE WHEN r.is_swapped = 1 THEN r.clase ELSE r.medio_ingreso END     AS channel,
    CASE WHEN r.is_swapped = 1 THEN r.medio_ingreso ELSE r.clase END     AS item_class,
    r.tipo_producto,
    r.modalidad_compra,
    r.modalidad_pago,
    r.problema_especial,
    r.service_hint,
    CASE WHEN r.close_date IS NULL THEN 1 ELSE 0 END                     AS flag_missing_close,
    CASE WHEN r.close_date < r.filing_date THEN 1 ELSE 0 END             AS flag_close_before_filing,
    CASE WHEN r.outcome = 'Cancelada' THEN 1 ELSE 0 END                  AS flag_cancelled,
    r.is_swapped                                                         AS flag_swapped_columns,
    CASE WHEN r.n_rows_same_case > 1 THEN 1 ELSE 0 END                   AS flag_shared_case_id,
    CASE WHEN r.estado_procesal IS NOT NULL AND r.outcome IS NULL
         THEN 1 ELSE 0 END                                               AS flag_outcome_anomaly,
    -- Threshold 100: only 2026-03-10 (147 cases) is above it; the next day has 94.
    CASE WHEN r.n_closed_same_day > 100 THEN 1 ELSE 0 END                AS flag_unusual_close_day,
    CASE WHEN r.filing_date IS NOT NULL AND r.close_date IS NOT NULL
              AND r.close_date >= r.filing_date
              AND COALESCE(r.outcome, '') <> 'Cancelada'
         THEN 1 ELSE 0 END                                               AS flag_valid_duration,
    r.office_code,
    r.odeco,
    -- Office H handles about 19,700 cases, all in Ciudad de México (check 3.3.12).
    CASE WHEN r.office_code = 'H' THEN 1 ELSE 0 END                      AS flag_central_office
FROM r;
GO

-- ---------------------------------------------------------------------
-- 3.3 CHECKS (read-only). Each one says what result is expected.
-- Save the results as docs/img/step_3_check_<NN>.png (for example
-- step_3_check_03.png; two result tables of one check: ..._06p1 and ..._06p2)
-- and compare them with the expected values.
-- ---------------------------------------------------------------------

-- 3.3.1 Same number of rows as the raw table. Expected: 36034 and 36034.
SELECT (SELECT COUNT(*) FROM stg.profeco_raw)       AS rows_stg,
       (SELECT COUNT(*) FROM clean.profeco_complaint) AS rows_clean;

-- 3.3.2 Text that could not be converted. Expected: 0 in every column.
-- A value that is not empty but gives NULL after TRY_CONVERT would be a
-- date that is not year-month-day. (The amounts are checked in 3.3.9.)
SELECT
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(fecha_ingreso)), '') IS NOT NULL
              AND TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(fecha_ingreso)), ''), 23) IS NULL
             THEN 1 ELSE 0 END) AS bad_filing_dates,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(fecha_cierre)), '') IS NOT NULL
              AND TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(fecha_cierre)), ''), 23) IS NULL
             THEN 1 ELSE 0 END) AS bad_close_dates,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(expediente)), '') IS NULL
             THEN 1 ELSE 0 END) AS empty_case_ids
FROM stg.profeco_raw;

-- 3.3.3 Flags. Expected (from step_2.sql):
--   missing_close 66 | close_before_filing 3 | cancelled 48 | swapped 430
--   shared_case_id 4 | outcome_anomaly 1 | unusual_close_day 147
--   valid_duration 35961 (36034 - 66 - 3 - 4 cancelled that have a close date)
SELECT
    SUM(CAST(flag_missing_close AS int))        AS missing_close,
    SUM(CAST(flag_close_before_filing AS int))  AS close_before_filing,
    SUM(CAST(flag_cancelled AS int))            AS cancelled,
    SUM(CAST(flag_swapped_columns AS int))      AS swapped,
    SUM(CAST(flag_shared_case_id AS int))       AS shared_case_id,
    SUM(CAST(flag_outcome_anomaly AS int))      AS outcome_anomaly,
    SUM(CAST(flag_unusual_close_day AS int))    AS unusual_close_day,
    SUM(CAST(flag_valid_duration AS int))       AS valid_duration
FROM clean.profeco_complaint;

-- 3.3.4 Swapped columns fixed. Expected: item_class only Servicio (31692)
-- and Bien (4304) plus NULL; channel only Internet (19772), Personal (13059),
-- Escrito (3048), Correo Electrónico (114), Teléfono (6) plus NULL (35).
SELECT 'item_class' AS column_name, item_class AS value, COUNT(*) AS n
FROM clean.profeco_complaint GROUP BY item_class
UNION ALL
SELECT 'channel', channel, COUNT(*)
FROM clean.profeco_complaint GROUP BY channel
ORDER BY column_name, n DESC;

-- 3.3.5 Procedure groups. Expected: Conciliation 34794, Queja 1126,
-- Other legal procedure 62, Not identified 52.
SELECT procedure_group, COUNT(*) AS n
FROM clean.profeco_complaint
GROUP BY procedure_group
ORDER BY n DESC;

-- 3.3.6 Brands. Part 1 expected: Telmex 2261, Izzi 3693, Megacable 3967,
-- Total Play 3347 (the two spellings merged). After revision 2 the list also
-- shows Axtel 45, Gigacable 21, Telecable 10, Starlink 9 and Newww 5.
SELECT brand, operator_group, COUNT(*) AS n
FROM clean.profeco_complaint
WHERE network_type = 'Fixed'
GROUP BY brand, operator_group
ORDER BY n DESC;

-- Part 2: the biggest brands that are NOT classified yet. If one of them is a
-- fixed or mobile operator, add it to clean.brand_map (section 3.1) and run
-- this script again.
SELECT TOP 40 brand, COUNT(*) AS n
FROM clean.profeco_complaint
WHERE network_type = 'Not classified'
GROUP BY brand
ORDER BY n DESC;

-- 3.3.7 States. Expected: no rows in part 1 (every state text is matched).
-- If rows appear, add that text to clean.state_map and run the script again.
SELECT state_raw, COUNT(*) AS n
FROM clean.profeco_complaint
WHERE state_code IS NULL
GROUP BY state_raw
ORDER BY n DESC;

-- Part 2: complaints by state (up to 32 states).
SELECT state_code, state_name, COUNT(*) AS n
FROM clean.profeco_complaint
GROUP BY state_code, state_name
ORDER BY state_code;

-- 3.3.8 Service hint. Part 1: how many rows have a hint (expected about 27%).
SELECT service_hint, COUNT(*) AS n
FROM clean.profeco_complaint
GROUP BY service_hint
ORDER BY n DESC;

-- Part 2: values of problema_especial that did NOT get a hint. If one of
-- them names a service (not "No Problema Especial" or free text), add it
-- to the CASE of the service_hint column and run the script again.
SELECT TOP 30 special_problem, COUNT(*) AS n
FROM clean.profeco_complaint
WHERE service_hint = 'Not specified'
GROUP BY special_problem
ORDER BY n DESC;

-- 3.3.9 Amounts. Expected NULLs (at least): claimed 37 (32 "-", 4 "sin dato",
-- 1 "Oo"), cost 34 (33 "-", 1 "sin dato"), recovered 1479 ("-").
SELECT
    SUM(CASE WHEN claimed_amount   IS NULL THEN 1 ELSE 0 END) AS claimed_null,
    SUM(CASE WHEN cost_amount      IS NULL THEN 1 ELSE 0 END) AS cost_null,
    SUM(CASE WHEN recovered_amount IS NULL THEN 1 ELSE 0 END) AS recovered_null,
    MIN(claimed_amount) AS claimed_min,   MAX(claimed_amount) AS claimed_max,
    MIN(recovered_amount) AS recovered_min, MAX(recovered_amount) AS recovered_max
FROM clean.profeco_complaint;

-- 3.3.10 Days to close. Sanity check: no negative values, and a plausible
-- range by procedure group. This is a first look, not a result of the project.
SELECT procedure_group,
       COUNT(days_to_close)  AS n_with_days,
       MIN(days_to_close)    AS min_days,
       MAX(days_to_close)    AS max_days,
       AVG(CAST(days_to_close AS float)) AS avg_days
FROM clean.profeco_complaint
GROUP BY procedure_group
ORDER BY procedure_group;

-- 3.3.11 Rows that are completely identical in the raw table (informational).
-- If there are any, they are kept (the grain is one row per row of the file)
-- and this is recorded in docs/sources/MX_profeco.md.
SELECT COUNT(*) AS groups_of_identical_rows
FROM (
    SELECT expediente, fecha_ingreso, fecha_cierre, tipo_conciliacion, estado_procesal,
           proveedor, nombre_comercial, giro, sector, odeco, estado, tipo_reclamacion,
           motivo_reclamacion, costo_bien_servicio, monto_reclamado, monto_recuperado,
           procedimiento, medio_ingreso, clase, tipo_producto, modalidad_compra,
           modalidad_pago, problema_especial
    FROM stg.profeco_raw
    GROUP BY expediente, fecha_ingreso, fecha_cierre, tipo_conciliacion, estado_procesal,
             proveedor, nombre_comercial, giro, sector, odeco, estado, tipo_reclamacion,
             motivo_reclamacion, costo_bien_servicio, monto_reclamado, monto_recuperado,
             procedimiento, medio_ingreso, clase, tipo_producto, modalidad_compra,
             modalidad_pago, problema_especial
    HAVING COUNT(*) > 1
) AS d;

-- ---------------------------------------------------------------------
-- 3.3.12 and 3.3.13 were added after the first run (they only READ data,
-- so the tables do not need to be rebuilt). Save them as step_3_check_12.png
-- and step_3_check_13.png.
-- ---------------------------------------------------------------------

-- 3.3.12 Where do the complaints come from? Ciudad de México has 22,477 of
-- 36,034 complaints (62%) and Tlaxcala has none (3.3.7). The state may be the
-- PROFECO office that handled the case and not the home of the consumer.
-- Part 1: share of Ciudad de México by channel and by brand. If the share
-- is high in every group, the state does not describe where the consumer lives.
SELECT 'channel' AS grouped_by, channel AS value,
       COUNT(*) AS n,
       SUM(CASE WHEN state_code = '09' THEN 1 ELSE 0 END) AS n_cdmx,
       CAST(100.0 * SUM(CASE WHEN state_code = '09' THEN 1 ELSE 0 END) / COUNT(*) AS decimal(5, 1)) AS pct_cdmx
FROM clean.profeco_complaint
GROUP BY channel
UNION ALL
SELECT 'brand', brand,
       COUNT(*),
       SUM(CASE WHEN state_code = '09' THEN 1 ELSE 0 END),
       CAST(100.0 * SUM(CASE WHEN state_code = '09' THEN 1 ELSE 0 END) / COUNT(*) AS decimal(5, 1))
FROM clean.profeco_complaint
WHERE network_type = 'Fixed'
GROUP BY brand
ORDER BY grouped_by, n DESC;

-- Part 2: the case ID starts with the PROFECO office (for example
-- PFC.YUC.B.3/001976-2024 is the office YUC). Compare that office with the
-- state of the complaint. If they agree, the state is the office.
SELECT TOP 25
       SUBSTRING(case_id, 5, CHARINDEX('.', case_id, 5) - 5) AS office_in_case_id,
       state_name,
       COUNT(*) AS n
FROM clean.profeco_complaint
WHERE case_id LIKE 'PFC.%.%'
GROUP BY SUBSTRING(case_id, 5, CHARINDEX('.', case_id, 5) - 5), state_name
ORDER BY n DESC;

-- 3.3.13 Amounts that look wrong. The largest recovered amount (556,800.00)
-- is larger than the largest claimed amount (551,335.06).
-- Part 1: how many rows recover more than they claimed, and how many claim 0.
SELECT
    SUM(CASE WHEN recovered_amount > claimed_amount THEN 1 ELSE 0 END) AS recovered_over_claimed,
    SUM(CASE WHEN claimed_amount = 0   THEN 1 ELSE 0 END) AS claimed_zero,
    SUM(CASE WHEN recovered_amount = 0 THEN 1 ELSE 0 END) AS recovered_zero
FROM clean.profeco_complaint;

-- Part 2: the 10 biggest differences, to look at them one by one.
SELECT TOP 10 case_id, brand, outcome, claimed_amount, recovered_amount,
       recovered_amount - claimed_amount AS difference
FROM clean.profeco_complaint
WHERE recovered_amount > claimed_amount
ORDER BY recovered_amount - claimed_amount DESC;

-- 3.3.14 (revision 2) Office H and the channel. Expected: office H holds
-- almost all the Internet cases and almost none of the others, and its
-- state is always Ciudad de México.
SELECT flag_central_office, channel, state_name, COUNT(*) AS n
FROM clean.profeco_complaint
WHERE flag_central_office = 1
   OR (channel = 'Internet' AND flag_central_office = 0)
GROUP BY flag_central_office, channel, state_name
ORDER BY flag_central_office DESC, n DESC;

-- 3.3.15 (revision 2) Brands after the new categories. Expected: Fixed =
-- the 4 operators plus Axtel, Gigacable, Telecable, Newww and Starlink.
SELECT network_type, COUNT(DISTINCT brand) AS n_brands, COUNT(*) AS n
FROM clean.profeco_complaint
GROUP BY network_type
ORDER BY n DESC;

-- 3.3.16 (revision 2) What is odeco? Compare it with the office taken from the
-- case ID and with the state. If odeco is the name of the office, each
-- office_code should have one office_name.
SELECT TOP 30 office_name, office_code, state_name, COUNT(*) AS n
FROM clean.profeco_complaint
GROUP BY office_name, office_code, state_name
ORDER BY n DESC;