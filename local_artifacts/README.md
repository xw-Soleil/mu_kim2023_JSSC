# Local artifacts

This directory keeps useful tool-session files out of the project root without changing any ICC2 run, NDM, DLib, result, report, or reference-library path.

Only this README is tracked by Git. All other contents are local, ignored artifacts.

## Layout

- `icc2/check_design/<date>/`: historical `check_design` reports grouped by run date. They are evidence of a particular stage, not automatically the final result.
- `icc2/workspace/<date>/`: ICC2 workspace EMS data.
- `icc2/interactive/<date>/`: interactive ICC2 command/output logs.
- `dc/sessions/<date>/`: Design Compiler session logs retained for debugging or reconstruction.
- `quarantine/<date>/`: files judged regenerable or obsolete but kept temporarily for recovery.

The 2026-08-06 cleanup moved 18 historical `check_design` reports here. In particular, the 2026-08-02 pre-clock-tree report records zero legality violations but also 16,226 unconstrained endpoints; it must not be presented as a final clean result.

Before clearing a quarantine directory, verify the tracked SHA256 inventory in `doc/manifests/`, search maintained scripts and documents for references, and obtain explicit user approval for permanent deletion.
