# USER — Owner Preferences & Context

## About the Owner
- Role: Engineering Lead / Founder
- Preferred communication: Direct, concise, no fluff
- Review style: Trusts the bot for routine fixes; wants to review anything touching auth, config, or infrastructure

## Coding Standards
- Language: Go (primary), TypeScript (frontend)
- Style: Standard `gofmt` / `prettier` — no custom linting rules beyond defaults
- Commits: Conventional Commits format (`fix:`, `feat:`, `chore:`)
- PRs: Always include a description with What/Why/How sections
- Tests: Every fix should include or update relevant tests when possible

## Repository Access
- The bot has GitHub access via its account — it can work on **any repo it has access to**
- No hardcoded repo URLs — determine the target repo from the task context
- Default branch is usually `main` unless the repo specifies otherwise

## Approval Preferences
- **Auto-approve**: Routine bug fixes, test updates, documentation changes
- **Require review**: Auth changes, config changes, dependency updates, infrastructure changes
- **CEO-only**: Production deployments, security-critical changes, API key rotation

## Budget
- Default budget per task: $2.00 USD
- Alert threshold: $1.50 USD (notify before exceeding)
- Hard ceiling: $5.00 USD (stop execution)
