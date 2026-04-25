# Exceptions Policy

## Purpose

This policy defines how temporary deviations from repository standards are requested, approved, tracked, and closed.

## Scope

Applies to exceptions against standards in:

- `docs/DOC_STANDARDS.md`
- `docs/FOLDER_STRUCTURE.md`
- `docs/POWERSHELL_SCRIPT_STANDARDS.md`
- Related governance documents in `docs/`

## Exception Principles

- Exceptions MUST be temporary.
- Exceptions MUST include documented risk and mitigation.
- Exceptions MUST have a clear owner and expiry date.
- Exceptions SHOULD be used only when no compliant practical option exists.

## Required Exception Metadata

Each exception request MUST include:

1. Exception ID (unique).
2. Standard and rule being waived.
3. Reason and business/operational necessity.
4. Risk assessment.
5. Mitigation steps.
6. Owner.
7. Approval authority.
8. Start date and expiry date.
9. Cleanup or rollback plan.

## Approval Workflow

1. Author documents the exception metadata.
2. Reviewer validates necessity and mitigation.
3. Approver explicitly accepts or rejects.
4. Approved exception is tracked until closure.

High-risk exceptions SHOULD require at least one additional reviewer.

## Tracking And Closure

- Active exceptions MUST be visible in repository documentation.
- Exception owner MUST close or renew before expiry.
- Renewal MUST include updated justification and risk review.
- Closed exceptions SHOULD record final resolution outcome.

## Non-Compliance

Changes that violate standards without an approved exception MUST be blocked.

## Ownership And Review Cadence

- Owner: repository maintainers.
- Last reviewed: 2026-04-24.

Review this policy whenever governance standards or approval practices change.

## Change Log

- 2026-04-24: Initial exceptions policy created.
