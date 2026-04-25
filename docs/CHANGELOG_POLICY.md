# Changelog Policy

## Purpose

This policy defines when and how meaningful repository changes are recorded in changelog-style entries.

## Scope

Applies to script and governance-document changes in this repository.

## When To Record A Changelog Entry

A changelog entry SHOULD be added when a change:

- Alters script behavior or operational impact.
- Changes safety assumptions or execution context.
- Adds, removes, or substantially rewrites a script.
- Introduces, updates, or retires governance standards.

Small typo-only edits MAY be grouped or omitted.

## Entry Requirements

Each entry SHOULD include:

1. Date (`YYYY-MM-DD`)
2. Area (`scripts`, `docs`, `structure`, etc.)
3. Summary of what changed
4. Why the change was made
5. Impact notes (operator-facing effects, if any)

## Entry Format

Use concise bullet entries in policy docs and related changelog sections, for example:

```markdown
- 2026-04-24 (`scripts`): Updated script prompting flow to collect required inputs before execution. Improves one-paste operator experience.
```

## Script And Doc Change Relationship

- Script behavior changes SHOULD include corresponding readme/doc updates in the same change where practical.
- Governance doc changes SHOULD include a change-log line in that doc.
- If script behavior changes without documentation updates, reviewer SHOULD request follow-up before approval.

## Granularity Guidance

- Group tightly related changes into one entry.
- Split unrelated changes into separate entries.
- Avoid overly broad entries that hide risk or impact.

## Ownership And Review Cadence

- Owner: repository maintainers.
- Last reviewed: 2026-04-24.

Review this policy whenever release/change-tracking practice evolves.

## Change Log

- 2026-04-24: Initial changelog policy created.
