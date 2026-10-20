---
name: project-review
description: Runs a full security, code-quality, architecture, and infrastructure review of the project and its applications. Use whenever the user asks for a code review, security review, project audit, or wants the codebase checked over — including when they say "review this", "audit the repo", or name a specific app to review. Produces a structured, severity-rated report and does not change code unless explicitly asked.
argument-hint: "[optional: app or directory to scope the review to]"
---

# Full Project Review

Perform a comprehensive review of this project, covering every application within it. If an argument is provided ($ARGUMENTS), scope the review to that application or directory instead of the whole project, but still apply every section below.

Ground every finding in the actual code — read the relevant files, cite file paths and line numbers, and do not flag issues you have not verified. Do not speculate; if something needs runtime context you can't confirm, say so.

This is a **review only**. Do not modify, refactor, or fix code unless the user explicitly asks you to after seeing the report.

## 1. Security

- Identify vulnerabilities: injection (SQL, command, etc.), authentication/authorization gaps, insecure secret handling, unsafe deserialization, SSRF, CSRF, XSS, path traversal.
- Flag any hardcoded secrets, credentials, API keys, or tokens.
- Review dependencies for known vulnerabilities and outdated or unmaintained packages.
- Check input validation and how untrusted data flows through the system.

## 2. Code Quality

- Assess readability, naming, consistency, and adherence to established conventions across the codebase.
- Review error handling, logging, and edge-case coverage.
- Note overly complex, brittle, or fragile logic that should be simplified.
- Comment on test coverage and the quality of existing tests.

## 3. Architecture & Structure

- Evaluate the overall project structure and how the applications are organized.
- Review how code sharing is handled through the shared packages — is the boundary between shared and app-specific code sensible, and do dependencies flow in the right direction?
- Look for code duplication that could be consolidated, especially across applications, and recommend where the consolidated code should live.
- Flag "rolled our own" implementations where a well-established, off-the-shelf library or language built-in would be more reliable and maintainable.
- Note the inverse too: dependencies pulled in for something trivial that isn't worth the weight.

## 4. Infrastructure

- Review infrastructure and configuration files (Docker, CI/CD pipelines, IaC, environment config) for correctness and consistency.
- Flag misconfigurations, security exposure, and drift between environments.

## Output Format

- Organize findings by the four areas above.
- Within each area, assign every finding a severity: **Critical / High / Medium / Low**.
- For each finding give: the location (file:line), why it matters, and a concrete recommended fix.
- End with a short prioritized summary of what to tackle first.
