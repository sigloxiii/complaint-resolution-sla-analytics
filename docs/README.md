# Documentation

Index of the project documentation. It is written in English, except the Spanish versions of the executive summary and of the main README.

## Contents

| File or folder | Purpose |
|---|---|
| [`decisions.md`](decisions.md) | Decision log (D1 to D16): context, options considered, decision and reason |
| [`run_log.md`](run_log.md) | Record of each script execution, with its evidence |
| [`glossary_of_terms.md`](glossary_of_terms.md) | Short definitions of the technical terms used in the project, with the case where each one mattered |
| [`executive_summary.md`](executive_summary.md) | One-page summary of the project: objective, method, main findings, limitations and deliverables |
| [`resumen_ejecutivo.md`](resumen_ejecutivo.md) | Spanish version of the executive summary |
| [`../data/data_dictionary.md`](../data/data_dictionary.md) | Every table and view of the `stg`, `clean` and `mart` layers (grain, rows, columns) |
| [`sources/`](sources/) | One note per data source (files, evidence, observations, columns and handling rules) and the license record |
| [`img/`](img/) | Evidence images (screenshots) |

## Sources

- [`sources/MX_profeco.md`](sources/MX_profeco.md): PROFECO telecommunications complaints and BIT accesses (México).
- [`sources/licenses.md`](sources/licenses.md): licenses, terms of use, citations and publishing rules for both sources.

## Suggested reading order

1. The [project README](../README.md): scope, business questions and pipeline.
2. [`decisions.md`](decisions.md): why the project is built the way it is.
3. [`sources/MX_profeco.md`](sources/MX_profeco.md): what the data look like and how the base file was chosen.
4. [`run_log.md`](run_log.md): what was executed, with its evidence.
5. [`../data/data_dictionary.md`](../data/data_dictionary.md): the tables created in SQL.
6. [`sources/licenses.md`](sources/licenses.md): what may be published and how to cite the sources.

## Conventions

- **Images:** stored in `img/`, with no subfolders. The file name is `<topic>_<name>.png`, in lowercase with underscores. Evidence of a script run is named `step_<N>_<block>.png`, where the block is the number after the dot (block 2.10 of `step_2.sql` is `step_2_10.png`), and checks inside a block add a letter (`step_2_8_a1.png`). From step 3 on, each check is `step_<N>_check_<NN>.png` (for example `step_3_check_06p1.png`), and a check with two result tables adds `p1` and `p2`. Examples: `mx_profeco_fuentes_01.png`, `step_0_results.png`, `step_2_10.png`, `step_3_check_12.png`, `powerbi_overview.png`.
- **Image links:** relative to the file that uses them (`../img/...` from `sources/`, `img/...` from this folder).
- **Screenshots:** crop them so that they do not show the machine name, the user name or unrelated content.
- **Decision log:** every entry has an ID, a date and a status (Open, Provisional, Proposed, Accepted or Rejected). When a decision changes, the entry is updated and the reason is kept.
- **Source notes:** one per data source, named `<COUNTRY>_<source>.md` (for example `MX_profeco.md`).
- **Folder depth:** at most two folders in any path of the repository.
- **SQL techniques:** every advanced technique in a script (CTE, derived table, window function, `CROSS APPLY`, view, temporary table) is explained with a `-- Technique:` comment, and the style rule is in [`../sql/README.md`](../sql/README.md).
- **Raw data:** never stored here and never versioned (see [`../data/`](../data/)).

## Maintenance

- The English README and its Spanish version (`../README.es.md`) are updated together: a change in one is made in the other in the same commit.
- The executive summary and its Spanish version follow the same rule.