-- ══════════════════════════════════════════════════════════
-- OpenClaw Bot Employee — SQLite Schema
-- ══════════════════════════════════════════════════════════
-- Deployment: sqlite3 ~/.openclaw/bot.db < schema.sql
-- All tables are scoped by guild_id for multi-tenant isolation
-- ══════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════
-- 1. CONVERSATIONS (Episodic Memory)
-- ══════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS conversations (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  guild_id TEXT NOT NULL,
  thread_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  worker_id TEXT NOT NULL,
  message_text TEXT NOT NULL,
  prompt_tokens INTEGER DEFAULT 0,
  completion_tokens INTEGER DEFAULT 0,
  cost_usd REAL DEFAULT 0.0,
  execution_outcome TEXT,              -- ACCEPTED, REJECTED, REVISION_REQUIRED
  embedding BLOB,                      -- serialized float32 array (1536 dims)
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_conv_guild
  ON conversations (guild_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_conv_thread
  ON conversations (thread_id, created_at DESC);

-- ══════════════════════════════════════════════════════════
-- 2. TASKS (Execution Durability)
-- ══════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS tasks (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  task_id TEXT UNIQUE NOT NULL,
  guild_id TEXT NOT NULL,
  thread_id TEXT NOT NULL,
  agent_id TEXT NOT NULL,
  requester_id TEXT NOT NULL,
  stage TEXT NOT NULL DEFAULT 'TRIAGE',     -- TRIAGE, CODING, SECURITY, CI, PR
  status TEXT NOT NULL DEFAULT 'PENDING',   -- PENDING, IN_PROGRESS, BLOCKED_APPROVAL, COMPLETED, FAILED
  retry_count INTEGER DEFAULT 0,
  context_summary TEXT,
  repo_url TEXT,
  branch_name TEXT,
  error_log TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_tasks_guild
  ON tasks (guild_id, status);

CREATE INDEX IF NOT EXISTS idx_tasks_status
  ON tasks (status) WHERE status != 'COMPLETED';

-- ══════════════════════════════════════════════════════════
-- 3. APPROVALS (HITL Persistence)
-- ══════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS approvals (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  task_id TEXT NOT NULL REFERENCES tasks(task_id),
  guild_id TEXT NOT NULL,
  thread_id TEXT NOT NULL,
  agent_id TEXT NOT NULL,
  requester_id TEXT NOT NULL,
  approval_type TEXT NOT NULL DEFAULT 'STANDARD',
  status TEXT NOT NULL DEFAULT 'PENDING',
  approved_by TEXT,
  context TEXT,
  sensitive_files TEXT,                     -- JSON array stored as text
  created_at TEXT DEFAULT (datetime('now')),
  resolved_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_approvals_guild
  ON approvals (guild_id, status);

-- ══════════════════════════════════════════════════════════
-- 4. COST TRACKING (Per-Guild Spend)
-- ══════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS cost_tracking (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  guild_id TEXT NOT NULL,
  task_id TEXT REFERENCES tasks(task_id),
  agent_id TEXT NOT NULL,
  model TEXT NOT NULL,
  prompt_tokens INTEGER DEFAULT 0,
  completion_tokens INTEGER DEFAULT 0,
  cost_usd REAL DEFAULT 0.0,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_cost_guild
  ON cost_tracking (guild_id, created_at DESC);

-- ══════════════════════════════════════════════════════════
-- 5. VIEWS (Convenience Queries)
-- ══════════════════════════════════════════════════════════

-- Guild spend summary (last 30 days)
CREATE VIEW IF NOT EXISTS v_guild_spend AS
SELECT
  guild_id,
  SUM(cost_usd) AS total_cost,
  SUM(prompt_tokens) AS total_prompt_tokens,
  SUM(completion_tokens) AS total_completion_tokens,
  COUNT(DISTINCT task_id) AS task_count
FROM cost_tracking
WHERE created_at >= datetime('now', '-30 days')
GROUP BY guild_id;

-- Guild spend by model
CREATE VIEW IF NOT EXISTS v_guild_spend_by_model AS
SELECT
  guild_id,
  model,
  SUM(cost_usd) AS cost,
  SUM(prompt_tokens) AS prompt_tokens,
  SUM(completion_tokens) AS completion_tokens,
  COUNT(*) AS call_count
FROM cost_tracking
WHERE created_at >= datetime('now', '-30 days')
GROUP BY guild_id, model;

-- Active tasks (not completed)
CREATE VIEW IF NOT EXISTS v_active_tasks AS
SELECT
  task_id, guild_id, agent_id, requester_id,
  stage, status, retry_count,
  context_summary, repo_url, branch_name,
  created_at, updated_at
FROM tasks
WHERE status NOT IN ('COMPLETED', 'FAILED');

-- Pending approvals
CREATE VIEW IF NOT EXISTS v_pending_approvals AS
SELECT
  a.id, a.task_id, a.guild_id, a.requester_id,
  a.approval_type, a.context, a.sensitive_files,
  a.created_at,
  t.stage AS task_stage, t.context_summary AS task_summary
FROM approvals a
LEFT JOIN tasks t ON a.task_id = t.task_id
WHERE a.status = 'PENDING';
