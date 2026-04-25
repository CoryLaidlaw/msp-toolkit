# Documentation Standards

## Purpose

This document defines the minimum quality bar for documentation in this repository. It is the source of truth for how docs are written, reviewed, and maintained by both human contributors and AI agents.

## Audience

- Technicians using scripts in operational support work.
- Maintainers updating scripts and repository structure.
- AI agents that draft or edit repository documentation.

## Scope

These standards apply to all documentation in this repository, including the root `README.md`, area readmes under `windows/`, and future docs added under `docs/`.

These standards do not define CI enforcement or lint automation.

## Core Principles

- Clarity over completeness: documentation MUST be understandable by a technician who did not write the script.
- Explicit assumptions: documentation MUST state critical runtime context (for example, LocalSystem vs. interactive user context).
- Actionable guidance: procedures SHOULD be step-by-step and easy to execute.
- Safe operations: risk and safety notes MUST be visible before destructive or high-impact steps.

## Normative Language

The keywords MUST, SHOULD, and MAY are used as follows:

- MUST: required, no exceptions unless explicitly approved.
- SHOULD: strongly recommended; deviations require a reason.
- MAY: optional guidance.

## Required Sections For New Operational Docs

Any new operational doc (or major rewrite) MUST include these sections:

1. Purpose
2. Scope
3. Preconditions and assumptions
4. Procedure
5. Validation and expected outcomes
6. Failure and rollback guidance
7. Ownership and last reviewed

## Content Requirements

- Docs MUST use specific, plain language and avoid vague words such as "maybe" or "usually" where an explicit rule exists.
- Docs MUST identify script context when relevant (for example, scripts run in LocalSystem sessions).
- Procedure steps SHOULD be numbered.
- Validation steps SHOULD include concrete success indicators (for example, expected output, log path, or observable system state).
- If a procedure can be destructive, the doc MUST include a warning before execution steps.

## AI Agent Requirements

- AI agents MUST follow this standard when generating or updating docs.
- AI agents MUST preserve human-authored safety constraints and policy language.
- AI agents MUST NOT invent operational facts; if details are unknown, the doc SHOULD explicitly say what must be verified by a human.
- AI agents SHOULD keep updates concise and scoped to the requested change.
- AI agents SHOULD add or update "Ownership and last reviewed" metadata when performing meaningful doc edits.

## Human Contributor Workflow

- Contributors MUST update docs when script behavior, folder layout, prerequisites, or safety expectations change.
- Contributors SHOULD prefer small, focused doc updates in the same change as code or structure updates.
- Contributors SHOULD request review from someone familiar with technician workflows for high-impact docs.

## Ownership And Review Cadence

Each maintained doc SHOULD include:

- Owner: person or team responsible for accuracy.
- Last reviewed: date in `YYYY-MM-DD` format.

Minimum review trigger:

- MUST review related docs whenever script behavior changes.
- SHOULD perform periodic review at least quarterly for frequently used operational docs.

## Definition Of Done For Doc Changes

A documentation change is done when all of the following are true:

- Required sections are present (or clearly marked N/A with reason).
- Runtime assumptions and safety constraints are explicit.
- Procedure and validation are actionable.
- Owner and last reviewed are present for maintained operational docs.
- Links and referenced paths are valid in the repository.

## Change Log

- 2026-04-24: Initial standard created.
