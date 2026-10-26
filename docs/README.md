# Documentation

Index of the project documentation. Everything here is written in English.

## Contents

| File or folder | Purpose |
|---|---|
| [`decisions.md`](decisions.md) | Decision log (D1 to D6): context, options considered, decision and reason |
| [`run_log.md`](run_log.md) | Record of each script execution, with its evidence |
| [`sources/`](sources/) | One note per data source: files, evidence, observations, columns and handling rules |
| [`img/`](img/) | Evidence images (screenshots) |

## Sources

- [`sources/MX_profeco.md`](sources/MX_profeco.md): PROFECO telecommunications complaints (México).

## Suggested reading order

1. The [project README](../README.md): scope, business questions and pipeline.
2. [`decisions.md`](decisions.md): why the project is built the way it is.
3. [`sources/MX_profeco.md`](sources/MX_profeco.md): what the data look like and how the base file was chosen.
4. [`run_log.md`](run_log.md): what has been executed so far.

## Conventions

- **Images:** stored in `img/`, with no subfolders. The file name is `<topic>_<name>.png`, in lowercase with underscores. Examples: `mx_profeco_fuentes_01.png`, `step_0_results.png`, `powerbi_overview.png`.
- **Image links:** relative to the file that uses them (`../img/...` from `sources/`, `img/...` from this folder).
- **Screenshots:** crop them so that they do not show the machine name, the user name or unrelated content.
- **Decision log:** every entry has an ID, a date and a status (Open, Provisional, Accepted or Rejected). When a decision changes, the entry is updated and the reason is kept.
- **Source notes:** one per data source, named `<COUNTRY>_<source>.md` (for example `MX_profeco.md`).
- **Folder depth:** at most two folders in any path of the repository.
- **Raw data:** never stored here and never versioned (see [`../data/`](../data/)).

## Planned

- Executive brief (`executive_brief.md`), written at the end of the project.