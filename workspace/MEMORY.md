# MEMORY — Long-Term Curated Knowledge

## System Architecture
- OpenClaw runs on Google Cloud Platform
- Database: Supabase with pgvector for episodic memory
- Memory advantage: pgvector cosine similarity beats flat-file search for scale
- Vector embeddings generated via `text-embedding-3-small` (1536 dimensions)

## Key Decisions
- 2026-02-28: Chose pgvector over flat-file MEMORY.md for enterprise memory scaling
- 2026-02-28: Configured 5 agents: triage, coder, debugger, security, tester
- 2026-02-28: Environment overrides per worker (DEV uses gpt-4o-mini, PROD uses gpt-4o/claude)
- 2026-02-28: Execution durability via Supabase `tasks` table for crash recovery

## Patterns & Gotchas
- Always check if a branch already exists before creating one
- GitHub Actions `workflow_dispatch` requires the workflow file to exist on the default branch
- pgvector `<=>` operator = cosine distance (lower = more similar)
- Supabase RPC functions must be called via PostgREST, not direct SQL from the Go client
