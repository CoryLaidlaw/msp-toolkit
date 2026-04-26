Collection of PowerShell used by technicians at an MSP: troubleshooting, cleanup, and gathering information. Scripts in this repository are **self-contained** (paste into a single session); they do not depend on loading other repo paths at runtime.

## Layout

| Path | Purpose |
|------|--------|
| [windows/disk](windows/disk) | Storage, temp cleanup, page file, and related size checks. |
| [windows/user-profiles](windows/user-profiles) | Domain user profile export and removal workflows. |
| [windows/onboarding](windows/onboarding) | AD user create/copy helpers (see area readme for the CSV). |
| [windows/software-removal](windows/software-removal) | Third-party software removal (uninstall, services, leftovers). |
| [windows/network](windows/network) | Network discovery plus current-user drive/printer mapping management. |
| [data/templates](data/templates) | Sample data files, such as CSV templates (not customer data). |
| [m365](m365) | Microsoft 365 scripts (Graph, SharePoint; see folder readme). |

Many jobs are run as **LocalSystem** in remote or RMM sessions. Read each area’s readme and test in non-production where appropriate; per-script behavior under SYSTEM can differ from an interactive user session (paths, user profile access, and so on).

## Documentation

Documentation expectations for both human contributors and AI agents are defined in [docs/DOC_STANDARDS.md](docs/DOC_STANDARDS.md). Folder naming and layout governance is defined in [docs/FOLDER_STRUCTURE.md](docs/FOLDER_STRUCTURE.md). PowerShell script authoring/runtime rules are defined in [docs/POWERSHELL_SCRIPT_STANDARDS.md](docs/POWERSHELL_SCRIPT_STANDARDS.md). Script review gates are defined in [docs/SCRIPT_REVIEW_CHECKLIST.md](docs/SCRIPT_REVIEW_CHECKLIST.md). Script template guidance is defined in [docs/SCRIPT_TEMPLATE.md](docs/SCRIPT_TEMPLATE.md). Folder readme requirements are defined in [docs/README_EXPECTATIONS.md](docs/README_EXPECTATIONS.md). Temporary deviation handling is defined in [docs/EXCEPTIONS_POLICY.md](docs/EXCEPTIONS_POLICY.md). Change tracking rules are defined in [docs/CHANGELOG_POLICY.md](docs/CHANGELOG_POLICY.md).

## License

See [LICENSE](LICENSE).

## Ownership and last reviewed

- Owner: repository maintainers
- Last reviewed: 2026-04-25
