# Source record: PROFECO telecommunications complaints (México)

Exploration log of the source. The first part was written **before** running the profiling scripts, so that the starting point and the expectations are on record. Evidence images are stored in `docs/img/` and their names start with `mx_profeco_`. The results of `step_2.sql` are added after the gate (see the end of this file).

## Publisher and access

| Item | Value |
|---|---|
| Publisher | PROFECO (Procuraduría Federal del Consumidor), published on datos.gob.mx |
| Dataset page | https://www.datos.gob.mx/dataset/quejas_materia_telecomunicaciones |
| Data dictionary | https://datos.profeco.gob.mx/diccionarioDatos.php |
| Last update shown by the portal | 2026-09-22 (evidence E1) |
| Resources on the dataset page | 5 (matches the five files below) |
| License | **To be verified** before publishing any file derived from these data |
| Download date | 2026-10-24 (file modification date shown by Windows Explorer, evidence E2) |

## Downloaded files

Five cuts were published. They are **not** simple, growing versions of one another (see observations).

| File | Size (KB) | Rows | Notes |
|---|---|---|---|
| `quejas_telecomunicaciones_2022_2025.csv` | 12,877 | ≈32,961 | Row count read from Excel (header assumed in row 1) |
| `quejas_telecomunicaciones_2022_ene_2026.csv` | 14,239 | ≈32,652 | Same method. Largest file by size |
| `quejas_telecomunicaciones_2022_may_2026.csv` | 1,561 | ≈4,081 | Same method. Looks like a partial slice |
| `quejas_telecomunicaciones_2022_junio_2026.csv` | 14,010 | 36,034 | Counted in Power Query. **Provisional base file** (decision D4) |
| `quejas_telecom_2022_jul2026.csv` | 12,537 | ≈31,926 | Same method as the first rows. The file name pattern differs |

SHA-256 of the base file (optional, proves the file was not modified): TBD.

## Evidence

### E1. Dataset page on datos.gob.mx

![E1: search result on datos.gob.mx](../img/mx_profeco_fuentes_01.png)

The portal lists "Quejas en materia de telecomunicaciones" (publisher PROFECO) with **5 databases** and a last update on **22 September 2026**.

### E2. Files downloaded to the project folder

![E2: downloaded files](../img/mx_profeco_data_sources.png)

Five CSV files, all modified on 24/10/2026. At this point they are still in `data\`, not yet in `data/raw/`.

### E3. Profile of `fecha_ingreso` (junio_2026, Power Query)

![E3: fecha_ingreso profile](../img/mx_profeco_inspeccion_fuentes_01.png)

36,034 rows, 0 errors, 0 empty values, 1,155 distinct dates. Minimum 03/01/2022 and maximum 27/05/2026 (the year is cut off in the capture and is to be confirmed in `step_2.sql`, block 2.5).

### E4. Profile of `fecha_cierre` (junio_2026, Power Query)

![E4: fecha_cierre profile](../img/mx_profeco_inspeccion_fuentes_02.png)

36,034 rows, 0 errors, **66 empty** (0.18%), 1,142 distinct dates. Minimum 06/01/2022 and maximum 29/05/2026. The most frequent close date is 10/03/2026, well above the typical day (possible batch closing, see block 2.12).

### E5. Dirty values in the amount columns

![E5: type errors in Power Query](../img/mx_profeco_datos_sucios.png)

Power Query "Kept Errors" view. `costo_bien_servicio`, `monto_reclamado` and `monto_recuperado` fail with "We couldn't convert to Number"; the offending value is a dash (`-`). `medio_ingreso` also contains the placeholder `sin dato`. The profile in this view uses only the top 1,000 rows, so its percentages are not reliable.

## Choosing the base cut: evidence and criteria

The five cuts were published by hand, with no documented methodology: the names follow different patterns (`quejas_telecom_2022_jul2026`, `..._ene_2026`, `..._junio_2026`), the row counts do not grow with time and the content of the close date is not consistent. Since the publisher gives no rule to choose a cut, the project defines its own criteria (decision D4 in `docs/decisions.md`):

1. **Integrity:** unique `expediente` and no type errors in the dates.
2. **Coverage:** widest date range and highest volume.
3. **Plausibility:** close dates vary and are not a single cut-off date.
4. **Consistency with the other cuts:** overlapping cases agree (overlap audit, pending).
5. **Traceability:** name, size, date and hash of the file are recorded.

Evidence: the end of each file as seen in Excel (the last rows show the latest records of each cut).

| Cut | Rows | What the end of the file shows | Verdict |
|---|---|---|---|
| `..._2022_2025.csv` | ≈32,961 | Rows sorted by filing date. The last filing is 25/11/2025 and the last close date seen is 28/11/2025, so coverage ends in November 2025 | Audit only |
| `..._2022_ene_2026.csv` | ≈32,652 | A last block sorted by office, with filings from 2025 and close dates in January 2026. The file is larger in bytes per row than the others | Audit only |
| `..._2022_may_2026.csv` | ≈4,081 | Filings from 12/05/2026 to 27/05/2026 and close dates up to 29/05/2026. Only the end was inspected; it looks like a partial slice | Audit only |
| `..._2022_junio_2026.csv` | 36,034 | Same last records as `may_2026`. Power Query: unique `expediente`, no date errors, 0.18% of close dates empty, close dates up to 29/05/2026 | **Base (provisional)** |
| `quejas_telecom_2022_jul2026.csv` | ≈31,926 | Every visible close date is 31/07/2026, even for cases filed in 2025 (it may be a cut-off date, not a real close date) | Audit only, until it is understood |

![Tail of 2022_2025](../img/mx_profeco_tail_2022_2025.png)
![Tail of ene_2026](../img/mx_profeco_tail_ene_2026.png)
![Tail of may_2026](../img/mx_profeco_tail_may_2026.png)
![Tail of junio_2026](../img/mx_profeco_tail_junio_2026.png)
![Tail of jul2026](../img/mx_profeco_tail_jul2026.png)

Only the end of each file was inspected, and the checks for criteria 1 and 4 were done only for `junio_2026`. The verdicts are therefore provisional and will be reviewed with the overlap audit.

## Observations (hypotheses to verify)

1. Row counts do not follow the order of the cuts: `ene_2026` and `jul2026` have fewer rows than `2022_2025`.
2. `junio_2026` ends with the same latest records as `may_2026` (last close date 2026-05-29), so its name does not mean it contains June closings.
3. In `jul2026`, every visible row at the end of the file has the close date 2026-07-31, even cases filed in 2025. It may be a cut-off date and not a real close date.
4. The portal reports a last update on 2026-09-22 (E1). The newest cut may be `jul2026`, which has fewer rows and a different name pattern. The relation between cuts is not understood yet.
5. `ene_2026` is the largest file by size (14,239 KB) but not by rows: about 447 bytes per row against about 400 in the other files. Its content differs (extra spaces, longer text or other quoting). To be inspected.
6. Text values differ in capitalization between cuts (for example "Cobro indebido" vs "Cobro Indebido", "DGPCT" vs "Dgpct").
7. There is **no column for the type of service** (internet, mobile, TV). `giro` describes the main business of the provider, not the service the complaint is about, so a provider that sells several services (for example Telmex) cannot be split by service. Fixed vs mobile has to be inferred from the provider, and the analysis is at provider level. Confirmed by visual inspection; to be verified in `step_2.sql` block 2.8 (checks A and B).
8. Rows with `estado_procesal` = Cancelada have provider "-", brand "Otros" and no close date.
9. Placeholders are used instead of empty values: `-` in amounts, provider and other columns, and `sin dato` in `medio_ingreso`. All of them become `NULL` in the clean layer.
10. In `junio_2026`, the last filing date is 2026-05-27 and the last close date is 2026-05-29 (E3, E4).
11. Dates appear to be text with the year first (for example 2022/01/03). To be confirmed in `step_2.sql` (block 2.4).

## Columns (23, in file order)

`expediente`, `fecha_ingreso`, `fecha_cierre`, `tipo_conciliacion`, `estado_procesal`, `proveedor`, `nombre_comercial`, `giro`, `sector`, `odeco`, `estado`, `tipo_reclamacion`, `motivo_reclamacion`, `costo_bien_servicio`, `monto_reclamado`, `monto_recuperado`, `procedimiento`, `medio_ingreso`, `clase`, `tipo_producto`, `modalidad_compra`, `modalidad_pago`, `problema_especial`.

## Handling rules

- Raw files are never edited. They are stored in `data/raw/`, which is not versioned.
- The data are loaded as text into `stg.profeco_raw` (`sql/mx_profeco/step_1.sql`) and cleaned only in SQL.
- The publisher may update the data retroactively. The download date and file identity are recorded here.

## Pending evidence

- [ ] Dataset page ("Ver base de datos") with the list of the five resources, their update dates and the license field.
- [ ] Page of the data dictionary.
- [ ] Left-hand columns of the Power Query errors view (cancelled cases with provider "-").
- [ ] Results of `step_2.sql` in SSMS (blocks 2.1, 2.4 to 2.6, 2.8 to 2.11, 2.13 and 2.14).
- [ ] Files moved to `data/raw/`.
- [ ] Save the five Excel captures of the file ends as `mx_profeco_tail_2022_2025.png`, `mx_profeco_tail_ene_2026.png`, `mx_profeco_tail_may_2026.png`, `mx_profeco_tail_junio_2026.png` and `mx_profeco_tail_jul2026.png` in `docs/img/`.
- [ ] BIT portal: download page and the list of subscriber tables.

## Results of the feasibility gate

To be completed after running `step_2.sql` (see decision D1 in `docs/decisions.md`).