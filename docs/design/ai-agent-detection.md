# AI Agent Detection — Design Document

## Goal

Detect which tmux panes/windows are running AI coding agents (Claude Code, Kimi, OpenCode) so the app can show agent status badges, filter sessions by agent, and enable resume functionality.

## Architecture

```
AIAgentPlugin (protocol)
  ├── ClaudeAgent
  ├── KimiAgent
  └── OpenCodeAgent

AIAgentRegistry (central coordinator)
  ├── detectInstalledAgents()      → which agents are available on server
  ├── detectAllRunningSessions()   → which tmux sessions run agents
  └── listAllSessions()            → resumable session history
```

### Plugin Protocol

Each agent implements `AIAgentPlugin` with:

| Method | Purpose |
|--------|---------|
| `isInstalled()` | Check if binary exists on remote server |
| `resolveBinaryPath()` | Find full path to the agent binary |
| `listSessions()` | List resumable sessions from agent's storage |
| `detectRunningSessions()` | Find tmux sessions running this agent |
| `detectRunningWindows()` | Find windows within a session running this agent |
| `resumeCommand()` | Build shell command to resume a session |
| `newCommand()` | Build shell command to start new session |

### Detection Flow

```
TmuxBrowserView.loadAIAgents()
  │
  ├─ 1. AIAgentRegistry.detectInstalledAgents()
  │     → runs `command -v <binary>` + path checks for each plugin
  │
  ├─ 2. AIAgentRegistry.listAllSessions()
  │     → each plugin scans its session storage (parallel via TaskGroup)
  │     → Claude: ~/.claude/projects/<encoded-path>/*.jsonl
  │
  └─ 3. AIAgentRegistry.detectAllRunningSessions()
        → each plugin runs process detection (parallel via TaskGroup)
        → returns [agentID: Set<tmuxSessionName>]
```

## Process Detection (Core Mechanism)

### How It Works

To determine if a tmux pane runs an AI agent, we:

1. Get all pane PIDs via `tmux list-panes -a -F '#{session_name} #{pane_pid}'`
2. For each pane PID, walk the **full descendant process tree** to find a matching binary

### Why Descendant Tree Walk (Not Direct Children)

The naive approach (`pgrep -P <pane_pid> -f "claude"`) only checks direct children. This fails because the agent binary is often a grandchild or deeper:

```
Typical process trees:

  fish (pane_pid) → claude                    ← direct child (works)
  fish (pane_pid) → fish (subshell) → claude  ← grandchild (missed by pgrep -P)
  bash (pane_pid) → node → claude             ← grandchild (missed)
  zsh  (pane_pid) → env → node → claude       ← great-grandchild (missed)
```

### Implementation

`RemotePlatform.pgrepChildCommand()` uses `ps + awk` to walk the full tree:

```bash
ps -eo pid=,ppid=,args= | awk -v root="$pane_pid" -v pat="claude" '
  { pid=$1; ppid=$2; p[pid]=ppid; a[pid]=$0 }
  END {
    for (pid in p) {
      cur=pid; d=0
      while (cur!="" && cur+0!=0 && cur!=root && d<10) { cur=p[cur]; d++ }
      if (cur==root && pid!=root && a[pid]~pat) exit 0
    }
    exit 1
  }'
```

Algorithm:
- Build a parent lookup table from `ps` output
- For every process, walk up the parent chain (max 10 levels) to see if `pane_pid` is an ancestor
- If it is, and the process command line matches the agent pattern, the pane is running that agent

This runs once per pane — the full `ps` output is read once and filtered by awk.

### Platform Awareness

`RemotePlatform` detects macOS vs Linux via `uname -s` and provides platform-specific:
- `stat` format flags (macOS `-f '%m'` vs Linux `-c '%Y'`)
- Common binary paths (macOS `/opt/homebrew/bin` vs Linux `/snap/bin`, etc.)
- tmux path resolution (`command -v tmux`)

The process detection command (`ps -eo pid=,ppid=,args=`) works on both platforms.

## Claude-Specific: Session Listing

Claude Code stores session data in `~/.claude/projects/<encoded-path>/<session-id>.jsonl`.

Detection command:
```bash
find ~/.claude/projects -maxdepth 2 -name '*.jsonl' ! -path '*/subagents/*' \
  -exec stat -f '%m %N' {} \; | sort -rn | head -20
```

For each file, extracts:
- **Session ID** from filename
- **Project path** decoded from directory name
- **Last modified** from file mtime
- **Summary** from first `"type":"user"` JSON line

## Key Files

| File | Role |
|------|------|
| `Services/AIAgent/AIAgentPlugin.swift` | Protocol + default implementations |
| `Services/AIAgent/RemotePlatform.swift` | Platform detection + process tree walk |
| `Services/AIAgent/AIAgentRegistry.swift` | Central registry, parallel detection |
| `Services/AIAgent/Plugins/ClaudeAgent.swift` | Claude session listing + parsing |
| `Views/Tmux/TmuxBrowserView.swift` | UI integration, triggers detection |
| `Views/AITools/ClaudeCodeBrowserView.swift` | Claude session browser UI |

## Adding a New Agent

1. Create `Plugins/NewAgent.swift` implementing `AIAgentPlugin`
2. Add to `AIAgentRegistry.allPlugins` array
3. Override `listSessions()` if the agent has custom session storage
4. Default implementations handle installation check, binary resolution, and process detection
