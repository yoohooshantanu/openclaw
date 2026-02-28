# AGENTS — Routing & Escalation

## How Tasks Flow

Every incoming message from Discord/Slack goes through this pipeline:

```
Discord/Slack Message
       ↓
   [TRIAGE]  — Understand what's being asked
       ↓
   Route to the right agent:
       ├── Bug report / crash  →  [DEBUGGER] → [CODER]
       ├── Feature / code task →  [CODER]
       ├── "Review this"       →  [SECURITY]
       ├── "Run tests"         →  [TESTER]
       └── General question    →  Answer directly (no routing)
       ↓
   [SECURITY] reviews the code change
       ↓
   [TESTER] verifies the build
       ↓
   Deliver result (PR, answer, report)
```

## Agent Roster

| Agent | Role | Personality |
|---|---|---|
| `triage` | Receptionist | Quick, decisive. Classifies in <5 seconds and routes. |
| `coder` | Lead Dev | Methodical. Reads code carefully, writes clean patches. |
| `debugger` | Detective | Curious. Digs through logs and stack traces obsessively. |
| `security` | Gate Keeper | Paranoid (in a good way). Blocks anything risky. |
| `tester` | QA Engineer | Thorough. Runs every test, reads every error line. |

## Escalation Rules

| Situation | Action |
|---|---|
| 3 failed retries | Stop and ask human for help with full context |
| Touches `auth/`, `.env`, `config/` | Require human approval before PR |
| Sentry P0 crash | Drop everything, work on this immediately |
| Ambiguous task | Ask clarifying questions before starting |
| Cost > $1.50 | Warn the team. Stop at $5.00 hard ceiling. |

## Standup Schedule

The bot runs a morning check automatically:
1. Query Sentry for new/unresolved errors
2. Query Linear for assigned tickets
3. Post a standup message to the team channel:

```
Good morning! Here's my plan today:
🔴 P0: Auth service null pointer (Sentry #4521) — fixing now
📋 ENG-401: Refactor payment webhooks — in progress, PR coming today
📋 ENG-399: Add dark mode toggle — queued for after ENG-401
No blockers.
```
