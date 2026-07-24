Collection of PowerShell used by technicians at an MSP: troubleshooting, cleanup, and gathering information. Scripts in this repository are **self-contained** (paste into a single session); they do not depend on loading other repo paths at runtime.

## Layout

| Path | Purpose |
|------|--------|
| [windows/disk](windows/disk) | Storage, temp cleanup, page file, and related size checks. |
| [windows/user-profiles](windows/user-profiles) | Domain user profile export and removal workflows. |
| [windows/onboarding](windows/onboarding) | AD user create/copy helpers (see area readme for the CSV). |
| [windows/software-removal](windows/software-removal) | Third-party software removal (uninstall, services, leftovers). |
| [windows/network](windows/network) | Network discovery plus current-user drive/printer mapping management. |
| [windows/monitoring](windows/monitoring) | Read-only runtime health checks and event-driven diagnostics (crash loops, etc.). |
| [data/templates](data/templates) | Sample data files, such as CSV templates (not customer data). |
| [m365](m365) | Microsoft 365 scripts (Graph, SharePoint; see folder readme). |

Many jobs are run as **LocalSystem** in remote or RMM sessions. Read each area’s readme and test in non-production where appropriate; per-script behavior under SYSTEM can differ from an interactive user session (paths, user profile access, and so on).

## Documentation

The rules for contributing (human or AI) live under `docs/`:

- [docs/DOC_STANDARDS.md](docs/DOC_STANDARDS.md): documentation expectations
- [docs/FOLDER_STRUCTURE.md](docs/FOLDER_STRUCTURE.md): folder naming and layout
- [docs/POWERSHELL_SCRIPT_STANDARDS.md](docs/POWERSHELL_SCRIPT_STANDARDS.md): script authoring/runtime rules
- [docs/SCRIPT_REVIEW_CHECKLIST.md](docs/SCRIPT_REVIEW_CHECKLIST.md): review gates
- [docs/SCRIPT_TEMPLATE.md](docs/SCRIPT_TEMPLATE.md): script template
- [docs/README_EXPECTATIONS.md](docs/README_EXPECTATIONS.md): folder readme requirements
- [docs/EXCEPTIONS_POLICY.md](docs/EXCEPTIONS_POLICY.md): approved deviations
- [docs/CHANGELOG_POLICY.md](docs/CHANGELOG_POLICY.md): change tracking

## License

See [LICENSE](LICENSE).

## Ownership and last reviewed

- Owner: repository maintainers
- Last reviewed: 2026-04-25
