# Data licenses and terms of use

Record of the legal basis for using the two sources of this project and for publishing derived tables. Status of each item: **Confirmed** (evidence image or text on record), **Reported** (text taken from a secondary source, evidence image pending) or **Open**.

## 1. PROFECO complaints

| Item | Value | Status |
|---|---|---|
| Dataset | Quejas en materia de telecomunicaciones, PROFECO | Confirmed |
| Dataset page | https://www.datos.gob.mx/dataset/quejas_materia_telecomunicaciones | Confirmed (E1) |
| Resource used | "Quejas en telecomunicaciones registradas por PROFECO y cerradas en junio de 2026" (created and updated 2026-09-22, CSV) | Confirmed |
| Download date | 2026-10-24 | Confirmed (E2) |
| License | **Creative Commons Attribution 4.0 (CC BY 4.0)**, shown in the "Licencia" field of the resource page | Confirmed (`docs/img/profeco_license_note.png`) |

The license field of the resource page prevails over the generic text of the PROFECO portal ("Términos de libre uso MX"), which is compatible with CC BY 4.0 (section 3) and does not change the conditions below. CC BY 4.0 allows copying, redistributing and adapting the data for any purpose, including commercial use, with these conditions:

1. **Attribution:** name the creator (PROFECO), give the title and the source link, and link the license (https://creativecommons.org/licenses/by/4.0/).
2. **Indicate changes:** the data were cleaned and aggregated (see `sql/mx_profeco/`), and the results are not PROFECO's.
3. **No suggestion of endorsement** by the licensor.

Citation (README and dashboard footer):

```
"Quejas en materia de telecomunicaciones", PROFECO; https://www.datos.gob.mx/dataset/quejas_materia_telecomunicaciones; CC BY 4.0; 2026-10-24. Modified: cleaned and aggregated by the author.
```

Pending: the license field was seen on the resource of the base file only. The other four resources may carry another license; they are not published and the base file is the one used.

## 2. BIT (Banco de Información de Telecomunicaciones)

| Item | Value | Status |
|---|---|---|
| Publisher | Comisión Reguladora de Telecomunicaciones (CRT), formerly IFT | Confirmed |
| Portal | https://bit.crt.gob.mx/BitWebApp/ | Confirmed |
| Tables used | `TD_ACC_BAF_ITE_VA` (fixed broadband accesses by operator group and state) | Confirmed |
| Tables inspected, not used yet | `TD_MARKET_SHARE_BAF_ITE_VA`, `TD_MARKET_SHARE_TELFIJA_ITE_VA` | Confirmed |
| Data dictionary | Manual de Definiciones de Indicadores Estadísticos (IFT, March 2018) | Confirmed |
| Period in the downloaded file | January 2013 to December 2024 | Confirmed |
| Download date | 2026-10-26 | Confirmed |
| Portal footer | "Algunos Derechos Reservados" | Confirmed (read, text not captured) |
| License | **None on record.** Used under the good-faith rules of section 4 (D10) | Risk accepted |

What is on record: the IFT describes the BIT as information "en formato abierto y disponible a cualquier hora y lugar, sin necesidad de realizar trámites ni solicitudes". That statement describes the format and the access; it is not a license. The portal footer reserves "some rights", so the terms behind that link must be read.

Checked on 2026-10-29: the footer notice has **no link** to any terms, and the downloaded datasets (ZIP and CSV) include no license or terms file. So the BIT has **no explicit license on record**. The CRT was not consulted successfully (the contact form did not send), and the project proceeds under the good-faith rules of section 4.

Citation:

```
Comisión Reguladora de Telecomunicaciones, Banco de Información de Telecomunicaciones (BIT), "TD_ACC_BAF_ITE_VA"; https://bit.crt.gob.mx/BitWebApp/; 2026-10-26
```

Note: the BIT series in the downloaded file ends in December 2024, even if the portal banner announces a later update. The period used is the one verified in the file (`ANIO`, `MES`).

## 3. Terms of use MX (summary)

Source of the text: reproduction at https://wiki.openstreetmap.org/wiki/ES:LIBRE_USO_MX, which cites `datos.gob.mx/libreusomx` as the original. That original URL returned a 404 error when the research was done (evidence: `docs/img/libreusomx_404.png`).

- **Allowed:** copy, distribute, publish, adapt, extract, use commercially and create derived datasets.
- **Conditions:**
  1. Cite the dataset name, the agency, the URL of the downloaded data and the consultation date (`YYYY-MM-DD`).
  2. Do not alter the meaning or veracity of the information to mislead.
  3. Do not suggest that the use is an official position or that the source endorses it.
- Third-party works inside a dataset are not covered.
- Compatible with Creative Commons CC BY.

## 3b. General terms of the gob.mx site

Reviewed: "Términos y condiciones del uso del sitio de gob.mx" (https://www.gob.mx/terminos), text pasted by the project owner on 2026-10-29.

- They authorize viewing and downloading the **materials of the gob.mx site** for personal use only, not for commercial use.
- They forbid modifying, reproducing or showing the materials publicly or commercially, distributing them, or transferring them to third parties.
- They say nothing about open data, datasets or Libre Uso MX.

How they apply:

- They are the general terms of one portal. A dataset published under its own license (PROFECO, Libre Uso MX) is governed by that specific license, which expressly allows public reuse and derived datasets.
- They do **not** show that the BIT is open. If the BIT footer ("Algunos Derechos Reservados") links to these terms, then public display of BIT material would be restricted. The BIT footer links to nothing, so those terms were not shown to apply.
- This is a reading of the texts for a portfolio project, not legal advice.

## 4. Rules for this repository (good-faith use)

No written answer from the CRT is expected. The contact form of the BIT did not send the query on 2026-10-29 (capture stored as evidence), and the project does not wait for a reply. The use is documented and limited instead:

1. Raw files are never versioned (`data/raw/` is ignored by git). Only code, documentation, capture images and aggregated results are published.
2. BIT data are published only as aggregates (operator group, state, year). No row-level BIT data and no copy of the files are redistributed. The figures are statistics of public interest that the publisher itself offers in open format, "sin necesidad de realizar trámites ni solicitudes".
3. Every published table, dashboard page and README cites the source with the citations above, including the consultation date.
4. The README and the dashboard include this notice: *"Independent portfolio project. It is not an official product and is not endorsed by PROFECO, the CRT or the Government of México."*
5. The limitations that change the meaning of the data are stated next to the results (state = PROFECO office, D8; amounts descriptive, D9; BIT accesses are not subscriptions).
6. The README states that any BIT-derived content is removed on request of the CRT.

Risk accepted (decision D10): the BIT has no explicit license, so the permission to publish aggregates rests on the open-format statement above and not on a written license. This is a reading of the texts for a portfolio project, not legal advice.

## 5. Checklist

- [x] PROFECO dataset page and download date on record
- [x] BIT footer and datasets checked: no terms linked, no license file (2026-10-29)
- [x] BIT contact form tried on 2026-10-29: it did not send the query; no further consultation (risk accepted, D10)
- [x] License of PROFECO: CC BY 4.0 on the resource page (capture `profeco_license_note.png`, 2026-10-31)
- [x] Capture of the BIT form and footer without terms (`docs/img/bit_terms_of_use.png`)
- [x] Real download date of the BIT files in the citation (2026-10-26)
- [x] Capture of the 404 error of `datos.gob.mx/libreusomx` (`docs/img/libreusomx_404.png`)