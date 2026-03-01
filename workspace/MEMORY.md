# MEMORY — Long-Term Curated Knowledge

## System Architecture
- OpenClaw runs on an Azure VM.
- Database: Local SQLite instance (`~/.openclaw/bot.db`).
- Memory is managed intrinsically by the OpenClaw engine using a local vector store.

## Key Decisions
- 2026-02-28: Migrated from GCP to Azure VM for hosting.
- 2026-02-28: Switched from Supabase/pgvector to local SQLite for reduced architecture complexity.
- 2026-02-28: Configured 5 agents: triage, coder, debugger, security, tester
- 2026-03-01: Configured Discord integration with `requireMention: false` to allow contextual listening.

## Patterns & Gotchas
- Always check if a branch already exists before creating one
- GitHub Actions `workflow_dispatch` requires the workflow file to exist on the default branch
