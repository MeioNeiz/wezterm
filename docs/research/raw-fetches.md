## 2026 Features

Based on the provided releases page, **no features from 2026 are documented**. The most recent release shown is v0.64.22 from August 2025. The page does include a reference to "Apple capability review (macOS arm64)" dated July 23, 2025, but this appears to be a pre-release artifact for Apple's review process rather than a production feature release.

The changelog entries focus on bug fixes, performance improvements, and infrastructure updates through mid-2025, with no forward-looking content describing planned 2026 features visible in this documentation snapshot.


## Key Features

**Notification System**
- Panes receive blue rings and tabs highlight when agents require attention
- Notification panel displays pending alerts; jump to most recent unread via Cmd+Shift+U
- Integrates standard terminal escape sequences (OSC 9/99/777) and CLI triggers

**Interface Elements**
- Vertical sidebar tabs showing git branch, linked PR status/number, working directory, listening ports, and latest notification text
- Horizontal and vertical split panes
- In-app browser with scriptable API (ported from agent-browser)
- Built-in browser import for cookies, history, sessions from 20+ browsers

**Agent & Workspace Support**
- Works with any CLI-based agent: Claude Code, Codex, OpenCode, Gemini CLI, etc.
- "Claude Code teams" mode spawns subagents as native splits with sidebar metadata
- SSH workspaces via `cmux ssh user@remote` with optional initial commands
- Remote tmux session attachment capability
- Session restore across restarts (layout, directories, scrollback, browser history)

**Programmability**
- CLI and Unix socket API for workspace creation, pane splitting, keystroke sending, screenshots, browser automation
- Browser automation: navigate, snapshot DOM, click, type, evaluate JavaScript
- Custom project commands via `cmux.json`
- "Skills" system for reusable workflows

## Core Functionality

The TUI organizes workspaces into status categories and displays the latest messages from conversation history when available. Key features include:

- **Workspace Management**: Lists workspaces grouped by status (needs input, working, completed)
- **Notification Tracking**: Shows unread cmux notifications as visual indicators
- **New Workspace Creation**: Supports multiline composition with image paths
- **State Persistence**: Saves prompt history, stashes, agent selection, and drafts locally

## Key Architecture Components

**Agent Spawning:** Users "select your model, write your prompt, and let multiple agents work on your codebase in parallel."

**Isolated Workspaces:** "Each agent runs in its own sandboxed environment with full VS Code, source control, and terminal access," deployable either in cloud infrastructure or local Docker containers.

**Development Environment:** Workspaces include git diff viewing, embedded terminal access, and dev server preview capabilities for real-time monitoring.

## Core Components

**AGENTS.md** serves as the control plane, listing available repositories, defining worktree locations per task, and referencing per-repository setup instructions.

**Origins** hold the base repositories that may be needed across multiple tasks.

**Worktrees** are isolated checkouts organized by task name, allowing agents to work on multiple repositories simultaneously without redundant cloning.

**Skills, data, and operating rules** support the agent's decision-making about which repositories a task requires and how to initialize them.

## Execution Mechanism

The workflow follows this process: agents read AGENTS.md to determine repository needs, create matching worktrees in the appropriate directories, read each repository's AGENTS.md, launch setup scripts immediately, and begin code work while initialization continues in the background.

Example invocation: `codex --yolo "fix CodeRouter xyz issues"`

This approach enables parallelism beyond simple worktrees, allowing agents to choose topology based on task requirements (remote sandboxes, VMs, GPU schedulers).


## The Tools

1. **cmux** — Native macOS terminal (GPL-3.0-or-later)
   - Focus: Sidebar notifications, git branch tracking, PR status
   - Worktree: Via existing git workflow
   - No diff viewer or task tracking (deliberate omission)

2. **Superset** — Desktop agent workspace (Elastic License 2.0)
   - Focus: "Run many CLI agents at once, each in its own git worktree"
   - Worktree: One per workspace with built-in diff viewer
   - Features: Comment-enabled diff review, scheduled automations, Slack/Linear integration
   - Limitation: macOS and Linux only (no Windows)

3. **Orca** — Agent Development Environment (MIT)
   - Focus: "Run Codex, ClaudeCode, OpenCode or Pi side-by-side"
   - Worktree: One per agent with SSH remote support
   - Features: Design mode for UI inspection, diff annotation, daily releases
   - All platforms: macOS, Windows, Linux, iOS, Android

4. **Paseo** — Daemon plus multi-client architecture (AGPL-3.0)
   - Focus: Inverted model with iOS/Android/web/CLI clients controlling local daemon
   - Worktree: Yes, prevents parallel work collisions
   - Features: Voice input, interchangeable agent providers, agent-to-agent prompting
   - All platforms supported

5. **Herdr** — Terminal runtime multiplexer (Apache-2.0)
   - Focus: "Cleanest answer to 'I want cmux but not on macOS'"
   - Worktree: Via existing git workflow
   - Features: Background server, pane status tracking (working/blocked/idle), plugin marketplace
   - All platforms: macOS, Windows, Linux

6. **T3 Code** — Agent harness control surface (MIT)
   - Focus: Remote control of existing agent installations
   - Worktree: Native git worktree support
   - Features: Mobile-first approach, `npx t3@latest` quick start
   - Status: Early-stage project ("very very early," discourages contributions)

7. **Goose** — General-purpose AI agent (Apache-2.0)
   - Focus: "Not just for code, use it for research, writing, automation"
   - Worktree: Not applicable (agent itself, not a workspace)
   - Features: 15+ provider support, 70+ MCP extensions, Linux Foundation governance
   - Complaint addressed: Lacks parallel session review (requires separate workspace)

8. **Warp** — Terminal with cloud orchestration platform (AGPL-3.0 client, MIT UI crates)
   - Focus: Terminal born into agent orchestration with built-in Oz agent
   - Worktree: Not the model
   - Features: Runs third-party agents, credit-based pricing on cloud platform
   - Commercial cloud component separate from open source client

---

## Key Differentiators

**Worktree isolation:** Superset, Orca, Paseo, and T3 Code provide dedicated worktree management; cmux and Herdr defer to git workflows.

**Diff review:** Superset offers comment-enabled diffs; Orca adds diff annotation for agent feedback; others lack structured review.

**Task management:** Only Nimbalyst (mentioned as reference) integrates task tracking alongside sessions.

**Mobile access:** Paseo, T3 Code, and Orca ship iOS/Android clients; cmux has iOS beta.


## Key Features

**Session Persistence**: Terminals remain active even when you close your laptop or lose network connectivity. Herdr restores the layout and resumes sessions after machine restarts.

**Agent Status Monitoring**: The system automatically marks agents as working, blocked, or idle, eliminating the need to manually search through panes to find which agent needs attention.

**Agent-Native Design**: Both the CLI and socket API enable agents to split panes, launch other agents, exchange prompts, and wait for genuine blocking conditions rather than relying on timed keystrokes.

**Cross-Platform Support**: One binary works on macOS, Linux, and Windows with no setup changes required for existing agent workflows.

**Multi-Agent Support**: Herdr integrates with 21 detected agents including Claude Code, Codex, Cursor, opencode, and others without replacing or wrapping them.

**Plugin Marketplace**: 939 community plugins are available to extend functionality.

## Status Authority & Detection Sources

Herdr uses a hierarchical approach: lifecycle hooks take precedence when installed, otherwise screen manifest detection applies. Per the documentation, "For agents with complete lifecycle hooks, the integration is authoritative when it is installed and actively reporting for the running pane."

The system classifies agents into states based on "the live bottom-buffer screen snapshot," not scrolled viewport content, ensuring detection follows active agent UI.

## What the Documentation Actually Covers

The integrations page explains how to report agent state using CLI commands:

> "An agent running in a Herdr pane inherits `HERDR_ENV`, `HERDR_PANE_ID`, `HERDR_BIN_PATH`, and `HERDR_SOCKET_PATH`."

For custom integrations, you're directed to report semantic state like this:

> "Report `idle` when the agent is ready for input and `blocked` when it needs a user decision."

## What's Missing

The documentation references that custom integrations can exist but doesn't provide:
- TOML configuration schemas
- Pattern matching rules for state detection
- Example detection regexes
- OSC sequence specifications
- Lifecycle hook wiring details

The page suggests consulting the **Socket API** documentation for direct IPC and mentions that **Prime Agent's Herdr reporter** serves as a real-world example, but the detailed manifest format isn't included on this integrations page.

You may need to check the Socket API reference or the Prime Agent repository for the comprehensive schema you're seeking.


## Superset's Approach

Superset operates as a **desktop workspace** that isolates agent work through Git worktrees. According to the comparison, it "launches Claude Code, Codex, OpenCode, Cursor Agent, Copilot, Gemini CLI, Mistral Vibe, and other agent workflows inside isolated Git worktrees with persistent terminal sessions."

Key mechanisms include:
- **Worktree isolation**: "Automatic Git worktree per task"
- **Built-in review**: A diff/file editor within the workspace for examining changes
- **Scheduling & automation**: TypeScript SDK and Slack bot for unattended agent sessions
- **Multi-agent support**: Runs "100+ AI agents in parallel"

The document does not mention Linear integration or agent-specific comment features in the provided content.

## Herdr's Approach

Herdr functions as a **persistent runtime** rather than a workspace. It is described as "a single Rust binary running an always-on server that owns real terminal sessions, organized as sessions, workspaces, tabs, and panes, with a TUI client you attach and detach like tmux."

Key mechanisms include:
- **State detection**: "Auto-detects 19 agent CLIs and visualizes their state (working, blocked, done)"
- **Socket API**: "Newline-delimited JSON socket API makes everything scriptable"
- **Terminal persistence**: Agents survive disconnects, lid-closes, and client restarts
- **Plugin ecosystem**: 500+ plugins, including Vercel Sandbox for VM isolation

## Core Features

**Workspace Management**: Each task gets its own isolated Git worktree, preventing merge conflicts when multiple agents work simultaneously.

**Multi-Agent Support**: The platform supports Claude Code, Codex, OpenCode, and other coding agents, allowing users to "switch agents" while maintaining consistent workflows across tasks.

**Parallel Execution**: Launch numerous agents simultaneously across features and bug fixes, with a status dashboard showing which are working, blocked, or awaiting input.

**Code Review**: Built-in diff review with commenting functionality that feeds feedback back to agents for refinement.

**Automations**: Schedule recurring tasks like issue triage, changelog drafts, and dependency updates to run on cron schedules, with automatic PR creation.

## Core Command Categories

| Category | Purpose |
|----------|---------|
| **Pane** | Create, split, focus, read, send input, resize, zoom, swap, and manage terminal panes |
| **Workspace** | Create, list, focus, rename workspaces and report metadata |
| **Tab** | Manage tabs within workspaces |
| **Agent** | Detect agents, report state, wait for completion, and manage agent lifecycle |
| **Events** | Subscribe to lifecycle changes across resources |
| **Layout** | Export and apply pane arrangements as portable templates |
| **Worktree** | Manage Git checkouts as separate workspaces |

## Core Agent Capabilities
- **Worktrees**: Each agent gets its own isolated git worktree, allowing parallel execution without file conflicts
- **Agent Support**: Compatible with 27+ agents including Claude Code, Codex, Grok, Gemini, GitHub Copilot, Cline, and others
- **Task Queueing**: Manage multiple tasks with clear ownership and completion tracking
- **Multi-Agent Comparison**: Run identical tasks across different agents/models to compare outputs

## Worktree Creation & Naming

**Creation Process:**
1. Users submit a Create Worktree dialog specifying task name, start-from reference, and optional GitHub/Linear/Jira/GitLab links
2. The operation runs in the background—`git fetch` and `git worktree add` continue while you use Orca
3. Progress appears in the sidebar with live setup status until checkout completes

**Naming Convention:**
Orca derives branch names from workspace names or from linked work items. Users can type Slack-style emoji shortcodes (`:rocket:`) that convert to readable branch names (🚀 becomes `rocket`). Advanced options allow explicit branch name specification, overriding automatic derivation.

## Shared Directories & Environment Setup

Orca addresses the challenge that fresh worktrees lack dependencies and cached files through three complementary mechanisms:

**1. Worktree Shared Paths:** Repository-level settings (Settings → Repository) that materialize paths from the primary checkout into new worktrees using APFS clone-copy on macOS or symlinks elsewhere.

**2. `orca.yaml` Configuration:** Repository-checked-in lists of gitignored directories to share (symlink/share, not copy), ideal for "large rebuildable trees like `node_modules` or `.cache`."

**3. `.worktreeinclude` File:** Lists gitignored files or directories to copy into each new worktree, allowing individual copies. Typical entries include `.env` and `.vscode/` settings. The format supports comments and blank lines but only literal paths.

These mechanisms complement rather than replace each other—`orca.yaml` entries add to per-user shared paths.

## Cleanup & Archival

Worktrees can be archived or deleted with one click, removing both the directory and branch (with confirmation). A **Resource Manager** feature lets users review worktrees across the setup before removal. If Git preserves branches due to unmerged commits, Orca surfaces a review step listing preserved branches for selective force-deletion.

Multi-selection deletion works via Ctrl/Cmd+click or Shift-range selection. The "Delete with Descendants" option handles nested worktrees created through orchestration.

## All 12 Tools Ranked

### **Dedicated Multiplexers (7 tools)**

1. **amux** | https://github.com/mixpeek/amux
   - Self-healing orchestration platform with mobile monitoring for unattended agent runs

2. **cmux** | https://cmux.com/
   - Native macOS terminal application with GPU-accelerated rendering and embedded browser

3. **dmux** | https://github.com/standardagents/dmux
   - Lightweight CLI using git worktrees for isolated parallel Claude Code sessions

4. **Termdock** | https://termdock.com/
   - AI-aware terminal multiplexer featuring per-session CPU/memory monitoring and health checks

5. **workmux** | https://github.com/raine/workmux
   - Shell script combining tmux with git worktrees, using YAML task definitions

6. **ittybitty** | https://github.com/adamwulf/ittybitty
   - Single ~200-line bash script spawning multiple agents with automatic branch management

7. **Superset** | https://superset.sh/
   - Visual GUI code editor wrapping parallel sessions with worktree isolation and cost tracking

### **Built-in Multi-Agent Features (2 tools)**

8. **Claude Code Agent Teams** | https://github.com/anthropics/claude-code
   - Built-in feature spawning parallel sub-agents with "lead agent decomposes the task, delegates sub-tasks, and merges results"

9. **Cursor Background Agents** | https://cursor.com/
   - Cloud-hosted agents running independently within the Cursor IDE while creating pull requests

### **Cloud Agent Platforms (3 tools)**

10. **Devin** | https://devin.ai/
    - Fully autonomous cloud AI engineer with sandboxed environment, shell, browser, and editor integration

11. **OpenAI Codex CLI** | https://github.com/openai/codex
    - Open-source terminal agent with "multimodal" capability and network-disabled sandbox mode

12. **OpenHands** | https://github.com/All-Hands-AI/OpenHands
    - Self-hostable open-source platform using Docker sandboxing with "micro-agent delegation" architecture


## Core Functionality

**Worktree + Window Creation**: The `workmux add <branch-name>` command:
- Creates a git worktree at `<project>__worktrees/<handle>`
- Establishes a matching tmux window (e.g., `wm-feature-auth`)
- Executes file operations (copy/symlink) and post-creation hooks
- Sets up configured pane layouts automatically
- Switches you to the new window immediately

**Cleanup**: The `workmux merge` command:
- Merges the branch (merge commit, rebase, or squash)
- Closes the tmux window
- Removes the worktree and local branch

## Configuration (.workmux.yaml)

Key configuration sections:

```yaml
main_branch: main
worktree_dir: <project>__worktrees/
window_prefix: wm-
merge_strategy: merge

panes:
  - command: <agent>      # AI agent placeholder
    focus: true
  - split: horizontal

files:
  copy: [.env]
  symlink: [node_modules]

post_create:
  - npm install
  - direnv allow

status_icons:
  working: 🤖
  waiting: 💬
  done: ✅
```

## Essential Commands

| Command | Purpose |
|---------|---------|
| `workmux add <branch>` | Create worktree + window with optional `-p` prompt, `--base` branch, `-A` auto-naming |
| `workmux merge [branch]` | Merge and clean up (with `--rebase`, `--squash`, `--keep` options) |
| `workmux remove [name]` | Delete worktree/window without merging (`--keep-branch` keeps git branch) |
| `workmux list` | Display all worktrees with status and merge info |
| `workmux open <name>` | Open tmux window for existing worktree |
| `workmux dashboard` | TUI showing all active agents with live status |
| `workmux path <name>` | Print worktree filesystem path |

## Advanced Features

- **Prompt templating**: Use `{{ input }}` from stdin or `{{ foreach_vars }}` for dynamic prompts
- **Sandbox isolation**: Run agents in containers (Docker/Podman) or Lima VMs with restricted file access
- **Session mode**: Each worktree gets its own tmux session with multiple windows
- **Automatic branch naming** (`-A`): LLM-generated names from prompts
- **Status tracking**: CLI agent hooks display working/waiting/done icons in tmux window names
- **Sidebar**: Persistent left/top panel showing all agents with live updates
- **PR checkout**: `workmux add --pr 123` checks out GitHub PRs directly

## https://docs.claude.com/en/docs/claude-code/agent-teams

REDIRECT DETECTED: The URL redirects to a location that was not fetched automatically.

Original URL: https://docs.claude.com/en/docs/claude-code/agent-teams
Redirect URL (from the server's Location header — server-supplied, not verified): https://code.claude.com/docs/en/agent-teams
Status: 301 Moved Permanently

To complete your request, I need to fetch content from the redirected URL. Please use WebFetch again with these parameters:
- url: "https://code.claude.com/docs/en/agent-teams"
- prompt: "Full docs page: how agent teams work, enabling flag, mailbox, shared task list, how teammates are spawned (separate processes? panes?), commands (/teammate, /team?), config, limits, and how a terminal multiplexer could observe or drive them. Quote exact env vars, commands and settings keys."


## Key Functionality

**Worktree & Pane Management:**
The tool "creates a tmux pane for each task. Every pane gets its own git worktree and branch so agents work in complete isolation." When tasks complete, users can merge branches or create pull requests through the pane menu.

**Supported Agents:**
The platform integrates with Claude Code, Codex, OpenCode, Cline CLI, Gemini CLI, Qwen CLI, Amp CLI, pi CLI, Cursor CLI, Copilot CLI, and Crush CLI.

**AI-Driven Automation:**
- Automatic branch and commit message naming via inference providers
- Agent state persistence—if an agent session was running when a pane closes, dmux tracks and resumes that conversation
- macOS notifications for background panes requiring attention
- Smart merging with auto-commit and cleanup

## When to use agent teams

Agent teams are most effective for tasks where parallel exploration adds real value. See [use case examples](#use-case-examples) for full scenarios. The strongest use cases are:

* **Research and review**: multiple teammates can investigate different aspects of a problem simultaneously, then share and challenge each other's findings
* **New modules or features**: teammates can each own a separate piece without stepping on each other
* **Debugging with competing hypotheses**: teammates test different theories in parallel and converge on the answer faster
* **Cross-layer coordination**: changes that span frontend, backend, and tests, each owned by a different teammate

Agent teams add coordination overhead and use significantly more tokens than a single session. They work best when teammates can operate independently. For sequential tasks, same-file edits, or work with many dependencies, a single session or [subagents](/docs/en/sub-agents) are more effective.

### Compare with subagents

Both agent teams and [subagents](/docs/en/sub-agents) let you parallelize work, but they operate differently. For separate sessions that pass messages to each other without a team, see [cross-session messaging](/docs/en/cross-session-messaging).

<Frame caption="Subagents report results back to the main agent. In agent teams, teammates share a task list, claim work, and communicate directly with each other.">
  <img src="https://mintcdn.com/claude-code/nsvRFSDNfpSU5nT7/images/subagents-vs-agent-teams-light.png?fit=max&auto=format&n=nsvRFSDNfpSU5nT7&q=85&s=2f8db9b4f3705dd3ab931fbe2d96e42a" className="dark:hidden" alt="Diagram comparing subagent and agent team architectures. Subagents are spawned by the main agent, do work, and report results back. Agent teams coordinate through a shared task list, with teammates communicating directly with each other." width="4245" height="1615" data-path="images/subagents-vs-agent-teams-light.png" />

  <img src="https://mintcdn.com/claude-code/nsvRFSDNfpSU5nT7/images/subagents-vs-agent-teams-dark.png?fit=max&auto=format&n=nsvRFSDNfpSU5nT7&q=85&s=d573a037540f2ada6a9ae7d8285b46fd" className="hidden dark:block" alt="Diagram comparing subagent and agent team architectures. Subagents are spawned by the main agent, do work, and report results back. Agent teams coordinate through a shared task list, with teammates communicating directly with each other." width="4245" height="1615" data-path="images/subagents-vs-agent-teams-dark.png" />
</Frame>

|                   | Subagents                                                                                                                                           | Agent teams                                                                                                                                   |
| :---------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------- |
| **Context**       | Own context window; results return to the caller                                                                                                    | Own context window; fully independent                                                                                                         |
| **Communication** | Return a result to the caller. Subagents that Claude named when it spawned them can also [message each other](/docs/en/sub-agents#what-loads-at-startup) | Teammates message each other directly                                                                                                         |
| **Coordination**  | Main agent manages all work                                                                                                                         | Self-coordination through messages, plus a shared task list for [agents that have the Task tools](/docs/en/tools-reference#task-tool-availability) |
| **Best for**      | Focused tasks where only the result matters                                                                                                         | Complex work requiring discussion and collaboration                                                                                           |
| **Token cost**    | Lower: results summarized back to main context                                                                                                      | Higher: each teammate is a separate Claude instance                                                                                           |

Use subagents when you need quick, focused workers that report back. Use agent teams when teammates need to share findings, challenge each other, and coordinate on their own.

## Enable agent teams

Agent teams are disabled by default. Enable them by setting the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` environment variable to `1`, either in your shell environment or through [settings.json](/docs/en/settings):

```json settings.json theme={null}
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Enabling agent teams also changes ordinary delegation. Claude may [name a subagent](/docs/en/sub-agents#subagent-names) on its own, and while agent teams are enabled, a subagent that Claude names launches as a teammate, so teams can form even when you didn't ask for one. For more, see [How Claude starts agent teams](#how-claude-starts-agent-teams); to turn the behavior off, see [Claude spawns teammates instead of subagents](#claude-spawns-teammates-instead-of-subagents).

Spawning teammates also requires an interactive session. In [non-interactive mode](/docs/en/headless) with the `-p` flag, including Agent SDK sessions, Claude doesn't spawn teammates, and a subagent that Claude names runs as an ordinary [subagent](/docs/en/sub-agents) even with agent teams enabled.

## Start your first agent team

After enabling agent teams, describe the task and the teammates you want in natural language. Claude spawns them and coordinates work based on your prompt.

This example works well because the three roles are independent and can explore the problem without waiting on each other:

```text wrap theme={null}
I'm designing a CLI tool that helps developers track TODO comments across
their codebase. Spawn three teammates to explore this from different angles:
one on UX, one on technical architecture, one playing devil's advocate.
```

From there, Claude populates a [shared task list](/docs/en/interactive-mode#task-list) in a [session that has the Task tools](/docs/en/tools-reference#task-tool-availability), spawns teammates for each perspective, has them explore the problem, and synthesizes findings when finished.

Claude may sometimes use [subagents](/docs/en/sub-agents) instead of creating a team. Subagents appear in the same agent panel as teammates, so the panel alone doesn't confirm a team formed. If Claude spawned subagents instead, ask again and explicitly request an agent team.

The lead's terminal lists teammates in the agent panel below the prompt input. From the panel:

* **Up and down arrows**: select a teammate
* **Enter**: open the selected teammate's transcript and message it directly
* **Escape**: clear the selection. While you're viewing a teammate's transcript, Escape interrupts that teammate's current turn

As of v2.1.199, an idle teammate's row stays in the panel while any teammate or subagent is still working, so you can select it to review its transcript or send it more work. Once every agent in the panel is idle, idle rows hide after 30 seconds and reappear on the teammate's next turn; the teammate stays running and addressable while hidden. In v2.1.181 through v2.1.198, an idle row hid 30 seconds after its own turn ended, even while other teammates were still working; idle rows are not hidden on versions before v2.1.181.

When more than three teammates are idle at once, the rows beyond the first three collapse into a single row that counts the collapsed teammates, such as `2 idle agents` when five are idle. Select it and press Enter to expand the collapsed rows, or press Esc to collapse them again. Working teammates, failed teammates, and the teammate you're viewing always keep their own rows.

If you want each teammate in its own split pane, see [Choose a display mode](#choose-a-display-mode).

## Control your agent team

Tell the lead what you want in natural language. It handles team coordination, task assignment, and delegation based on your instructions.

### Choose a display mode

Agent teams support two display modes:

* **In-process**: all teammates run inside your main terminal. Use the up and down arrow keys in the agent panel to select a teammate, then press Enter to view it and type to message it directly. Works in any terminal, no extra setup required.
* **Split panes**: each teammate gets its own pane. You can see everyone's output at once and click into a pane to interact directly. Requires tmux, or iTerm2.

<Note>
  `tmux` has known limitations on certain operating systems and traditionally works best on macOS. Using `tmux -CC` in iTerm2 is the suggested entrypoint into `tmux`.
</Note>

The default is `"in-process"`. Before v2.1.179 the default was `"auto"`, so upgraded sessions that previously opened split panes now stay in one terminal unless you set the mode explicitly. Set `"auto"` to enable split panes when you're already running inside a tmux session, or when your terminal is iTerm2 with the `it2` CLI installed, falling back to in-process otherwise. The `"tmux"` setting enables split-pane mode and auto-detects whether to use tmux or iTerm2 based on your terminal.

As of v2.1.186, set `"iterm2"` to use iTerm2 native split panes explicitly. This mode requires the [`it2` CLI](https://github.com/mkusaka/it2) and shows an error with the install command if `it2` is missing. The setup prompt that offers to install `it2` or switch to tmux appears under `"auto"` or `"tmux"` when your terminal is iTerm2 and tmux is available as a fallback.

To override the default, set [`teammateMode`](/docs/en/settings-reference#teammatemode) in `~/.claude/settings.json`:

```json theme={null}
{
  "teammateMode": "auto"
}
```

To set the mode for a single session, pass it as a flag:

```bash theme={null}
claude --teammate-mode auto
```

The `--teammate-mode` flag is experimental and doesn't appear in `claude --help`.

Split-pane mode requires either [tmux](https://github.com/tmux/tmux/wiki) or iTerm2 with the [`it2` CLI](https://github.com/mkusaka/it2). To install manually:

* **tmux**: install through your system's package manager. See the [tmux wiki](https://github.com/tmux/tmux/wiki/Installing) for platform-specific instructions.
* **iTerm2**: install the [`it2` CLI](https://github.com/mkusaka/it2), then enable the Python API in **iTerm2 → Settings → General → Magic → Enable Python API**.

### Specify teammates and models

Claude decides the number of teammates to spawn based on your task, or you can specify exactly what you want:

```text wrap theme={null}
Spawn 4 teammates to refactor these modules in parallel. Use Sonnet for
each teammate.
```

Claude Code picks each teammate's model from the first of these that applies:

1. The model your spawn prompt names for that teammate.
2. For a teammate spawned from a [subagent definition](#use-subagent-definitions-for-teammates), the definition's `model`, where `inherit` selects the lead's model.
3. [`CLAUDE_CODE_SUBAGENT_MODEL`](/docs/en/model-config#environment-variables), when it's set to anything other than `inherit`.
4. The lead's current model.

[`CLAUDE_CODE_SUBAGENT_MODEL_FORCE`](/docs/en/sub-agents#run-every-subagent-on-one-model) applies to teammates as well as to subagents.

Before v2.1.251, `CLAUDE_CODE_SUBAGENT_MODEL` came first in this order.

<Note>
  `teammateDefaultModel` was removed in v2.1.234; Claude Code ignores a leftover value. Name the model in your prompt instead.
</Note>

Claude Code checks the model it selects for a teammate against your organization's [`availableModels`](/docs/en/model-config#restrict-model-selection) allowlist. When the allowlist blocks a value, Claude Code substitutes another model:

* **Family alias such as `opus`**: On the Anthropic API and Claude Platform on AWS, Claude Code runs the teammate on the newest version of that family the allowlist permits. On providers with provider-specific model IDs, where the [substitution doesn't operate](/docs/en/model-config#restrict-model-selection), a blocked alias falls back like any other blocked value per the next bullet
* **Any other blocked value, including a family alias on providers where the substitution doesn't operate, or one whose family has no permitted version**: Claude Code runs the teammate on the lead's model instead. If you set `CLAUDE_CODE_SUBAGENT_MODEL`, Claude Code tries that model first, under these same rules

Teammates inherit the lead's [effort level](/docs/en/model-config#adjust-effort-level). In split-pane mode this applies from v2.1.186; earlier versions did not pass the lead's session effort to split-pane teammates.

### Have teammates plan before implementing

For complex or risky tasks, you can have teammates plan before implementing. A teammate that Claude spawns while the lead is in [plan mode](/docs/en/permission-modes#analyze-before-you-edit-with-plan-mode) works in read-only plan mode until its plan is ready. Switch the lead into plan mode first, then ask for the teammate:

```text wrap theme={null}
Spawn an architect teammate to refactor the authentication module.
```

When a teammate finishes planning, it sends a plan approval request to the lead. Claude Code approves the plan in the lead's session as soon as the request arrives, without the lead reviewing it. The teammate's edits and commands still go through the permission prompts described in [Permissions](#permissions). Once approved, the teammate exits plan mode and begins implementation.

### Talk to teammates directly

Each teammate is a full, independent Claude Code session. You can message any teammate directly to give additional instructions, ask follow-up questions, or redirect their approach.

* **In-process mode**: use the up and down arrow keys in the agent panel to select a teammate, then press Enter to view its session and type to send it a message. Press `x` on a selected teammate to stop it. Press Ctrl+T to toggle the task list.
* **Split-pane mode**: click into a teammate's pane to interact with their session directly. Each teammate has a full view of their own terminal.

While you're viewing an in-process teammate, plain text and [skills](/docs/en/skills) go to that teammate, but built-in commands still run in the lead's session.

A teammate's model and fast mode are fixed when it spawns, so `/model` and `/fast` only change the lead's settings. As of v2.1.199, typing either command while viewing a teammate shows a notice that the change applies to the lead; earlier versions applied it to the lead with no indication. `/effort` still applies to the viewed teammate's later turns, because teammates follow the lead's [effort level](/docs/en/model-config#adjust-effort-level).

### Assign and claim tasks

The shared task list coordinates work across the team. The lead creates tasks and teammates work through them. Tasks have three states: pending, in progress, and completed. Tasks can also depend on other tasks: a pending task with unresolved dependencies cannot be claimed until those dependencies are completed.

Agents [without the Task tools](/docs/en/tools-reference#task-tool-availability) coordinate through messages instead of the shared task list.

The lead can assign tasks explicitly, or teammates can self-claim:

* **Lead assigns**: tell the lead which task to give to which teammate
* **Self-claim**: after finishing a task, a teammate picks up the next unassigned, unblocked task on its own

Task claiming uses file locking to prevent race conditions when multiple teammates try to claim the same task simultaneously.

### Shut down teammates

To gracefully end a teammate's session, refer to it by name. For example, with a teammate named researcher:

```text wrap theme={null}
Ask the researcher teammate to shut down
```

The lead sends a shutdown request. The teammate can approve, exiting gracefully, or reject with an explanation.

The team's shared directories are cleaned up automatically when the session ends, so there's no separate cleanup step. See [Architecture](#architecture) for which directories are removed and which persist for resumed sessions.

### Enforce quality gates with hooks

Use [hooks](/docs/en/hooks) to enforce rules when teammates finish work or tasks are created or completed:

* [`TeammateIdle`](/docs/en/hooks#teammateidle): runs when a teammate is about to go idle. Exit with code 2 to send feedback and keep the teammate working.
* [`TaskCreated`](/docs/en/hooks#taskcreated): runs when a task is being created. Exit with code 2 to prevent creation and send feedback.
* [`TaskCompleted`](/docs/en/hooks#taskcompleted): runs when a task is being marked complete. Exit with code 2 to prevent completion and send feedback.

## How agent teams work

This section covers the architecture and mechanics behind agent teams. If you want to start using them, see [Control your agent team](#control-your-agent-team) above.

### How Claude starts agent teams

To start a team, ask Claude for teammates. Claude launches a teammate when it calls the [Agent tool](/docs/en/tools-reference) with a [`name`](/docs/en/sub-agents#subagent-names) while agent teams are enabled, and Claude Code doesn't ask you to confirm. Claude also names ordinary subagents on its own so it can message them later, and while agent teams are enabled, a named subagent launches as a teammate, so teams can form even when you didn't ask for one.

If you want subagents instead, [turn agent teams off](#claude-spawns-teammates-instead-of-subagents).

### Architecture

An agent team consists of:

| Component     | Role                                                                    |
| :------------ | :---------------------------------------------------------------------- |
| **Team lead** | The main Claude Code session that spawns teammates and coordinates work |
| **Teammates** | Separate Claude Code instances that each work on assigned tasks         |
| **Task list** | Shared list of work items that teammates claim and complete             |
| **Mailbox**   | Messaging system for communication between agents                       |

Each agent's mailbox is a JSON file at `~/.claude/teams/{team-name}/inboxes/{agent-name}.json`. Claude Code validates every entry when it reads a mailbox file. Entries that don't match the message format are reported as errors and removed from the file; the valid messages are still delivered. Before v2.1.207, a single malformed mailbox entry caused a repeated error every second and blocked delivery for that mailbox until you deleted the file manually.

Claude Code reports a message as sent only when the write to the recipient's mailbox file succeeds, whether the message is plain text or a structured protocol message such as a plan approval or shutdown request. When the write fails, for example because the disk is full or the mailbox directory isn't writable, the sending agent receives an error and nothing is sent. See [Failed to write to a teammate's inbox](/docs/en/errors#failed-to-write-to-a-teammate-inbox) for the error messages and recovery steps.

Claude Code manages task dependencies automatically: when a teammate completes a task that other tasks depend on, it unblocks the dependent tasks without any action from you.

Teams and tasks are stored locally under a session-derived name. The name is `session-` followed by the first eight characters of the session ID:

* **Team config**: `~/.claude/teams/{team-name}/config.json`
* **Task list**: `~/.claude/tasks/{team-name}/`

Claude Code generates both of these automatically at session startup and updates them as teammates join, go idle, or leave. The team config directory is removed when the session ends. The task list directory persists locally and is never uploaded, so resumed sessions keep their tasks. Retention is governed by the same [`cleanupPeriodDays`](/docs/en/settings-reference#cleanupperioddays) you already control for session transcripts, following the [retention sweep rules](/docs/en/claude-directory#cleaned-up-automatically).

The team config holds runtime state such as session IDs and tmux pane IDs, so don't edit it by hand or pre-author it: your changes are overwritten on the next state update.

To define reusable teammate roles, use [subagent definitions](#use-subagent-definitions-for-teammates) instead.

The team config contains a `members` array with each member's name and agent ID. The lead's entry always carries the agent type `team-lead`. A teammate's entry carries whatever agent type the lead named when spawning it, whether a [built-in type](/docs/en/sub-agents#built-in-subagents) or a [subagent definition](#use-subagent-definitions-for-teammates), and omits the field when the lead named none. Teammates can read this file to discover other team members.

There is no project-level equivalent of the team config. A file like `.claude/teams/teams.json` in your project directory is not recognized as configuration; Claude treats it as an ordinary file.

### Use subagent definitions for teammates

When spawning a teammate, you can reference a [subagent](/docs/en/sub-agents) type from any [subagent scope](/docs/en/sub-agents#choose-the-subagent-scope): project, user, plugin, or CLI-defined. This lets you define a role once, such as a security-reviewer or test-runner, and reuse it both as a delegated subagent and as an agent team teammate.

To use a subagent definition, name it when you ask Claude to spawn the teammate:

```text wrap theme={null}
Spawn a teammate using the security-reviewer agent type to audit the auth module.
```

Claude Code reads the subagent definition you named and applies these parts of it to the teammate. Where a part depends on the teammate's [display mode](#choose-a-display-mode), the entry says so:

* **`tools`**: Claude Code limits the teammate to the tools in the definition's `tools` list. For an in-process teammate, Claude Code adds `SendMessage` to that list, and in a [session that has the Task tools](/docs/en/tools-reference#task-tool-availability) it adds `TaskCreate`, `TaskGet`, `TaskList`, and `TaskUpdate` too.
* **`model`**: Claude Code uses the definition's `model` in either display mode when your spawn prompt doesn't name one. See [how Claude Code picks a teammate's model](#specify-teammates-and-models).
* **Body**: for an in-process teammate, Claude Code appends the definition's body to its default system prompt as additional instructions. For a split-pane teammate, Claude Code uses the body in place of its default system prompt.
* **`skills`**: Claude Code doesn't apply the definition's `skills` to a teammate in either display mode. The teammate loads skills from your project and user settings.
* **`mcpServers`**: for a split-pane teammate, Claude Code applies the definition's `mcpServers` under the [rules for that field](/docs/en/sub-agents#scope-mcp-servers-to-a-subagent), which cover a session started with `--agent` as well. An in-process teammate ignores the field and loads MCP servers from your project and user settings.

### Permissions

Teammates start with the lead's permission settings. If the lead runs with `--dangerously-skip-permissions`, all teammates do too. After spawning, you can change individual teammate modes, but you can't set per-teammate modes at spawn time.

Teammate permission prompts appear in the lead session, so approve them there yourself. [Plan approval](#have-teammates-plan-before-implementing) is the designed exception: the lead session grants teammate plan approvals without a separate prompt to you.

#### Messages between agents

When one agent sends another a message over `SendMessage`, Claude Code tells the receiving agent the message came from another Claude session, not from you. A teammate can't approve a permission prompt or supply consent on your behalf, and a teammate that was denied an action can't relay it to another teammate to bypass the check. The same rules apply to a message that arrives from [one of your other Claude Code sessions](/docs/en/cross-session-messaging#how-a-session-treats-an-incoming-message), outside the team entirely.

In [auto mode](/docs/en/permission-modes#eliminate-prompts-with-auto-mode), the classifier applies two checks to messages between agents:

* It treats an approval claim relayed from another agent as untrusted input rather than confirmation from you.
* It reviews each message before Claude Code delivers it, whether a plain message or a structured protocol message such as a shutdown request or plan approval response. A message it blocks never reaches the recipient.

### Context and communication

Each teammate has its own context window. When spawned, a teammate loads the same project context as a regular session: CLAUDE.md, MCP servers, and skills. It also receives the spawn prompt from the lead. The lead's conversation history does not carry over.

**How teammates share information:**

* **Automatic message delivery**: when teammates send messages, they're delivered automatically to recipients. The lead doesn't need to poll for updates.
* **Idle notifications**: when a teammate finishes and stops, it automatically notifies the lead and includes its final answer in the notification. A teammate whose turn ends on an API error notifies the lead that it failed and includes the error text.
* **Shared task list**: [agents that have the Task tools](/docs/en/tools-reference#task-tool-availability) can see task status and claim available work.
* **Teammate messaging**: send a message to one specific teammate by name. To reach everyone, send one message per recipient.

The lead assigns every teammate a name when it spawns them, and any teammate can message any other by that name. To get predictable names you can reference in later prompts, tell the lead what to call each teammate in your spawn instruction.

### Token usage

Agent teams use significantly more tokens than a single session. Each teammate has its own context window, and token usage scales with the number of active teammates. For research, review, and new feature work, the extra tokens are usually worthwhile. For routine tasks, a single session is more cost-effective. See [agent team token costs](/docs/en/costs#agent-team-token-costs) for usage guidance.

An in-process teammate's requests fall outside the main conversation's [cache TTL bucket](/docs/en/prompt-caching#which-ttl-each-request-gets), so its cache holds for five minutes by default, including on a Claude subscription. To keep it for an hour, set [`subagentPromptCacheTtl`](/docs/en/settings-reference#subagentpromptcachettl) to `1h`. The API bills 1-hour cache writes at a higher rate.

## Use case examples

These examples show how agent teams handle tasks where parallel exploration adds value.

### Run a parallel code review

A single reviewer tends to gravitate toward one type of issue at a time. Splitting review criteria into independent domains means security, performance, and test coverage all get thorough attention simultaneously. The prompt assigns each teammate a distinct lens so they don't overlap:

```text wrap theme={null}
Spawn three teammates to review PR #142:
- One focused on security implications
- One checking performance impact
- One validating test coverage
Have them each review and report findings.
```

Each reviewer works from the same PR but applies a different filter. The lead synthesizes findings across all three after they finish.

### Investigate with competing hypotheses

When the root cause is unclear, a single agent tends to find one plausible explanation and stop looking. The prompt fights this by making teammates explicitly adversarial: each one's job is not only to investigate its own theory but to challenge the others'.

```text wrap theme={null}
Users report the app exits after one message instead of staying connected.
Spawn 5 agent teammates to investigate different hypotheses. Have them talk to
each other to try to disprove each other's theories, like a scientific
debate. Update the findings doc with whatever consensus emerges.
```

The debate structure is the key mechanism here. Sequential investigation suffers from anchoring: once one theory is explored, subsequent investigation is biased toward it.

With multiple independent investigators actively trying to disprove each other, the theory that survives is much more likely to be the actual root cause.

## Best practices

### Give teammates enough context

Teammates load project context automatically, including CLAUDE.md, MCP servers, and skills, but they don't inherit the lead's conversation history. See [Context and communication](#context-and-communication) for details. Include task-specific details in the spawn prompt:

```text wrap theme={null}
Spawn a security reviewer teammate with the prompt: "Review the authentication module
at src/auth/ for security vulnerabilities. Focus on token handling, session
management, and input validation. The app uses JWT tokens stored in
httpOnly cookies. Report any issues with severity ratings."
```

### Choose an appropriate team size

There's no hard limit on the number of teammates, but practical constraints apply:

* **Token costs scale linearly**: each teammate has its own context window and consumes tokens independently. See [agent team token costs](/docs/en/costs#agent-team-token-costs) for details.
* **Coordination overhead increases**: more teammates means more communication, task coordination, and potential for conflicts
* **Diminishing returns**: beyond a certain point, additional teammates don't speed up work proportionally

Start with 3-5 teammates for most workflows. This balances parallel work with manageable coordination. If you have 15 independent tasks, 3 teammates is a good starting point.

Scale up only when the work benefits from having teammates work simultaneously. Three focused teammates often outperform five scattered ones.

### Size tasks appropriately

* **Too small**: coordination overhead exceeds the benefit
* **Too large**: teammates work too long without check-ins, increasing risk of wasted effort
* **Just right**: self-contained units that produce a clear deliverable, such as a function, a test file, or a review

<Tip>
  The lead breaks work into tasks and assigns them to teammates automatically. If it isn't creating enough tasks, ask it to split the work into smaller pieces. Having 5-6 tasks per teammate keeps everyone productive and lets the lead reassign work if someone gets stuck.
</Tip>

### Wait for teammates to finish

Sometimes the lead starts implementing tasks itself instead of waiting for teammates. If you notice this:

```text wrap theme={null}
Wait for your teammates to complete their tasks before proceeding
```

### Start with research and review

If you're new to agent teams, start with tasks that have clear boundaries and don't require writing code: reviewing a PR, researching a library, or investigating a bug. These tasks show the value of parallel exploration without the coordination challenges that come with parallel implementation.

### Avoid file conflicts

Two teammates editing the same file leads to overwrites. Break the work so each teammate owns a different set of files.

### Monitor and steer

Check in on teammates' progress, redirect approaches that aren't working, and synthesize findings as they come in. Letting a team run unattended for too long increases the risk of wasted effort.

## Troubleshooting

### Teammates not appearing

If teammates aren't appearing after you ask Claude to spawn them:

* In in-process mode, teammates appear in the agent panel below the prompt input. Use the up and down arrow keys to select one, then press Enter to view it.
* A teammate row that disappeared after sitting idle has been hidden, not stopped. Idle rows hide 30 seconds after the whole panel goes idle and reappear on the teammate's next turn. When more than three teammates are idle, their surplus rows collapse into a single `N idle agents` row that Enter expands. Send the teammate a message by name to bring a hidden row back.
* Check that the task you gave Claude was complex enough to warrant a team. Claude decides whether to spawn teammates based on the task.
* If you explicitly requested split panes, ensure tmux is installed and available in your PATH:
  ```bash theme={null}
  which tmux
  ```
* For iTerm2, verify the `it2` CLI is installed and the Python API is enabled in iTerm2 preferences.

### Claude spawns teammates instead of subagents

While agent teams are enabled, a subagent that Claude names in the lead's session launches as a teammate. Claude [can name subagents on its own](#how-claude-starts-agent-teams), so this can happen during delegation you never framed as team work.

To make named subagents launch as subagents again, turn agent teams off by setting `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` to `0`:

```json settings.json theme={null}
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "0"
  }
}
```

You don't need to start a new session: Claude Code reapplies settings-file `env` values to the running session when you save, and rereads the variable each time Claude spawns a subagent, so the next subagent Claude names launches as a subagent.

Setting the variable to `0` in your user `settings.json` overrides a shell export. Other settings sources can still enable agent teams:

* **Higher-precedence settings files**: project settings, local settings, and a `--settings` payload apply after user settings, so an `env` entry that sets the variable to `1` in any of them wins. See [Settings precedence](/docs/en/settings#settings-precedence).
* **Managed settings**: [managed settings](/docs/en/server-managed-settings) apply after every other source. If your organization enables agent teams there, ask your administrator to change the managed value.

After the change, Claude may still name subagents, and the name keeps working as a [`SendMessage` address](/docs/en/sub-agents#resume-subagents). Claude receives each subagent's result when it completes.

### Too many permission prompts

Teammate permission requests bubble up to the lead, which can create friction. Pre-approve common operations in your [permission settings](/docs/en/permissions) before spawning teammates to reduce interruptions.

### Agents stopping early

Teammates may stop after encountering errors instead of recovering. Check their output by selecting the teammate in the agent panel and pressing Enter in in-process mode, or by clicking the pane in split mode, then either:

* Give them additional instructions directly
* Spawn a replacement teammate to continue the work

A message from the lead or another teammate wakes an in-process teammate that is waiting to retry a failed API request, so it retries immediately instead of waiting for the full retry delay.

The lead can stop early too, deciding the team is finished before all tasks are actually complete. If that happens, tell it to keep going.

### Orphaned tmux sessions

If a tmux session persists after the Claude Code session ends, it may not have been fully cleaned up. List sessions and end the one created by the team:

```bash theme={null}
tmux ls
tmux kill-session -t <session-name>
```

## Limitations

Agent teams are experimental. Current limitations to be aware of:

* **No session resumption with in-process teammates**: `/resume` and `/rewind` do not restore in-process teammates. After resuming a session, the lead may attempt to message teammates that no longer exist. If this happens, tell the lead to spawn new teammates.
* **Task status can lag**: teammates sometimes fail to mark tasks as completed, which blocks dependent tasks. If a task appears stuck, check whether the work is actually done and update the task status manually or tell the lead to nudge the teammate.
* **Shutdown can be slow**: teammates finish their current request or tool call before shutting down, which can take time.
* **One team per session**: a session has exactly one team, scoped to that session. You can't create additional named teams or share a team across sessions.
* **No nested teams**: teammates cannot spawn their own teammates. Only the lead can manage the team.
* **No background subagents from in-process teammates**: an in-process teammate's own subagents run in the foreground, because a teammate's background work can't outlive the lead's process. Claude Code returns an error when a teammate spawns a subagent whose definition sets `background: true`. A teammate's `run_in_background: true` request also fails, either with an error or by running silently in the foreground, as described in [how Claude Code picks foreground or background](/docs/en/sub-agents#run-subagents-in-foreground-or-background). Subagents launched from the main conversation follow the [background default](/docs/en/sub-agents#run-subagents-in-foreground-or-background).
* **Lead is fixed**: the main session is the lead for its lifetime. You can't promote a teammate to lead or transfer leadership.
* **Permissions set at spawn**: all teammates start with the lead's permission mode. You can change individual teammate modes after spawning, but you can't set per-teammate modes at spawn time.
* **Split panes require tmux or iTerm2**: the default in-process mode works in any terminal. Split-pane mode isn't supported in VS Code's integrated terminal, Windows Terminal, or Ghostty.

## Next steps

Explore related approaches for parallel work and delegation:

* **Lightweight delegation**: [subagents](/docs/en/sub-agents) spawn helper agents for research or verification within your session, better for tasks that don't need inter-agent coordination
* **Messaging between your own sessions**: [cross-session messaging](/docs/en/cross-session-messaging) lets Claude pass findings between the sessions you run yourself
* **Manual parallel sessions**: [Git worktrees](/docs/en/worktrees) let you run multiple Claude Code sessions yourself without automated team coordination



## When to use cross-session messaging

Use messaging when one of your sessions has something another session needs mid-task. Claude can send a message on its own when it sees the need, for example after making a change that affects work another session is doing, or you can ask it to send one. The common cases:

* **Hand over a finding**: when one session discovers a breaking change or makes a decision, Claude summarizes it for the session working on the affected area, instead of you re-explaining it there.
* **Coordinate parallel worktrees**: when sessions work the same repository in separate [worktrees](/docs/en/worktrees), Claude can tell the other sessions what landed.
* **Get status from long-running work**: have a migration or test run report back to the session you're watching, or ask it yourself from there. If that session is on this machine, Claude can also [ask it for one notice when it next goes idle or exits](#get-a-notice-when-another-session-goes-idle).
* **Message across machines**: reach one of your sessions on another machine or on the web.

Use messaging between independent sessions that you start and steer yourself. Claude Code has a dedicated feature for each of the other ways to run or reach multiple sessions, so use the one built for what you're doing instead:

* To continue one conversation in another terminal, or share its context with a new session, [resume the session](/docs/en/sessions#resume-a-session)
* For a coordinated team of sessions Claude spawns and supervises, use [agent teams](/docs/en/agent-teams)
* To watch and steer many sessions from one place, use [agent view](/docs/en/agent-view)
* To steer a session yourself from your phone or another device, rather than have sessions message each other, use [Remote Control](/docs/en/remote-control)
* To push external events, such as CI results or chat messages, into a session, use [channels](/docs/en/channels)

## Message another session

When one of your sessions learns something another session needs, such as a finding, a status, or a decision, Claude passes it along instead of you copy-pasting between terminals. Claude discovers the target with `ListAgents` and sends with `SendMessage`, so you never call either tool yourself. Claude can decide to send a message without being asked, and you can also prompt for one.

To prompt one yourself, tell Claude what you want the other session to know or do. This example is a prompt you type, not a message Claude sends:

```text wrap theme={null}
Ask the session running in my other terminal whether the migration finished
```

Claude writes the actual message itself, so your prompt can leave the content to Claude. This prompt asks for a summary without dictating its wording, and what Claude sends varies:

```text wrap theme={null}
Explain what we just did to the session working on the payments API
```

To name the target yourself, mention the session in your prompt: type `@` followed by the first letters of the session's name and pick the session from the typeahead, the same way you [@-mention a subagent](/docs/en/sub-agents#invoke-subagents-explicitly). Requires Claude Code v2.1.232 or later. Claude Code inserts the mention, such as `@api-worker`, and tells Claude which session it names, so Claude can message that session without listing your sessions first. This prompt names the target with a mention:

```text wrap theme={null}
Let @api-worker know the schema migration finished
```

The typeahead lists your other live sessions on this machine. Two cases need more than the first letters of a name:

* **A session beyond this machine**: a cloud or Remote Control session appears in the typeahead only after Claude has listed or messaged your sessions beyond this machine, so ask Claude to list them first.
* **A name with a space or other characters outside letters, digits, hyphens, and underscores**: type it in double quotes, such as `@"release notes"`. When you pick the session from the typeahead, Claude Code inserts the quotes for you.

You can also type the mention without the picker. When more than one live session answers to the mentioned name, Claude asks you which one you mean before sending.

For what the message Claude writes looks like when it arrives, including an example of one, see [what a message looks like](#what-a-message-looks-like).

### Message delivery

The receiving Claude reads the message between tool calls during an active turn, so a running tool is never interrupted. When the receiving session is idle, Claude Code starts a new turn with the message.

A message from another session arrives as plain text. If it mentions a file or an [MCP resource](/docs/en/mcp#use-mcp-resources) with `@`, Claude sees the mention as written and Claude Code attaches nothing, whether the message starts a new turn or arrives during one. Claude can still open a mentioned path on the receiving machine with its own tools, subject to that session's permissions. Before v2.1.251, an `@` mention in a message that started a new turn attached the file or MCP resource on the receiving side.

Claude Code refuses a message in the following cases:

* The message is [over the size cap](#limitations). Claude Code refuses it in the sending session, before it leaves.
* A rapid burst to a session on this machine has reached [what that session's inbox accepts](#limitations). Claude Code refuses further messages to that session.
* The reply target on this machine fails a safety check, such as a symlinked target or an endpoint that isn't the expected process. [Refusing to send a cross-session message](/docs/en/errors#refusing-to-send-a-cross-session-message) lists these checks.
* Claude addresses the message to this session's own name, as described under [See which sessions Claude can reach](#see-which-sessions-claude-can-reach).

The receiving session checks each arriving message against its own [inbound controls](#control-inbound-messages), and the check ends in one of three outcomes:

* **Delivered**: Claude Code passes the message to the receiving Claude.
* **Held**: Claude Code sets the message aside undelivered. A held message reaches Claude only when you approve it or a later mode or settings change allows it.
* **Refused**: Claude Code drops the message without delivering it.

Once delivered, the message counts toward [usage](/docs/en/costs) like a prompt you type, and the receiving Claude can reply to the sender the same way, except in the [one-way cross-machine case](#message-sessions-on-other-machines).

Permission boundaries stay per-session. Claude is instructed never to ask another session for an action that was denied or blocked in its own session, or that its own permission settings would block, and to route that work back to you instead. On the receiving side, the [receiving session's own permission prompts and rules still apply](#how-a-session-treats-an-incoming-message) to anything the message asks for.

### Get a notice when another session goes idle

Claude can ask one of your sessions on this machine to send back one notice when that session next goes idle or exits. Idle here means the session finished a turn with nothing queued. Use it when you're waiting on a long task in another session and want to hear when it's done instead of checking. Requires Claude Code v2.1.236 or later in both sessions.

#### Ask for a notice

Tell Claude what you're waiting on. This prompt asks for a notice from the migration session:

```text wrap theme={null}
Tell me when the migration session finishes what it's working on
```

Claude subscribes with the `SendMessage` tool's `notify_when_idle` input, either attached to a message it's sending anyway or on its own. On its own, Claude Code subscribes without starting a turn or spending tokens in the watched session, and sends the notice right away if that session is already idle. Attached to a message, Claude Code delivers the message first and sends the notice later.

#### What each session shows

The watched session shows a line saying another process asked to be told when the session is next idle. The asking session shows the notice as a line naming the watched session. The line can include the time that session's turn finished and a one-line status from that turn. If the asking session is idle, Claude Code starts a new turn with the notice.

#### Limits

The notice is one-shot: Claude Code sends it once from the watched session, and neither session polls the other. If no notice arrives within 12 hours, Claude Code drops the subscription and tells Claude, so it doesn't keep waiting.

Each side's [inbound controls](#control-inbound-messages) apply to a notice like a message:

* **`refuse` on either side**: nothing arrives. The watched session drops the request without recording or answering it, so the subscription expires unanswered after 12 hours, and an asking session with `refuse` never subscribes.
* **`hold` on either side**: the notice arrives with less. The watched session leaves the one-line status out, and the asking session shows the notice in your transcript without delivering it to Claude.

Only the Claude in your main conversation can subscribe, and only to your sessions on this machine. When a subagent or an agent team teammate sets `notify_when_idle`, Claude Code makes no subscription and tells it so. When Claude asks for a notice from any other agent, such as a teammate, a subagent, or a session beyond this machine, Claude Code refuses the whole call, including any message attached to it, and reports the refusal to Claude so it can resend the message without the request.

### See which sessions Claude can reach

Claude finds a message's target on its own, so you don't need to run anything before asking it to send. To see for yourself which sessions Claude can reach, run the `/list-agents` command. The first line, when present, is this session's own name, the one your other sessions use to message it. The rows below it are the sessions Claude can reach:

* **Subagents**: agents running inside the current session.
* **Teammates**: this session's own [agent team](/docs/en/agent-teams) teammates. Before v2.1.239, teammates didn't appear in the listing, though Claude could already message them by name.
* **Your other local sessions**: Claude Code sessions running on the same machine, including [background sessions](/docs/en/agent-view). A session appears only when it binds an [inbox socket](#the-sessions-inbox-socket).
* **Your cloud sessions**: your [Claude Code on the web](/docs/en/claude-code-on-the-web) sessions, shown while this session is connected to [Remote Control](/docs/en/remote-control). Claude Code labels them `cloud` in the listing.
* **Your Remote Control sessions on other machines**: shown while this session is connected to [Remote Control](/docs/en/remote-control), and labeled `Remote Control`. Claude Code shows `offline` as the status of a session whose Remote Control connection has dropped.

This session isn't one of the rows. If Claude addresses a message to this session's own name, Claude Code refuses it and tells Claude the target is the current session. Before v2.1.239, the listing didn't show this session's name, and Claude Code reported a message sent to it as an agent it couldn't find.

While this session is connected to [Remote Control](/docs/en/remote-control), Claude Code withholds some details of your local sessions from the `/list-agents` output, without changing what Claude itself sees when it looks for a session to message:

* **Working directories**: it leaves out each local session's working directory.
* **Session names**: it leaves out any session name it can't attribute to a person, so a row left with no name reads `(unnamed session)`.
* **The first line**: it leaves out the line with this session's own name unless you typed that name at this terminal, with `--name` or with `/rename` and the name, since you launched or last resumed the session.

When the output lists anything, it ends with a note saying details were withheld. Running `/rename` followed by an unused name at a session's own keyboard gives that session a name that appears in the output.

Claude Code reads your cloud and Remote Control session lists newest first and stops after a bounded number of pages for each. If your account has more of those sessions than fit, Claude Code doesn't list the older ones, and Claude can't message them by name. When this happens, Claude Code says so in the listing, and Claude sees the same note when it sends a message.

Claude addresses a session beyond this machine by name, the same as a local session. See [Message sessions on other machines](#message-sessions-on-other-machines) for how those messages travel.

A session answers to the name you set with the [`/rename`](/docs/en/commands) command or the [`--name`](/docs/en/cli-reference#cli-flags) flag. When you don't set one, Claude Code names the session itself. For an interactive session, that is the name shown in [listings of running sessions](/docs/en/sessions#name-your-sessions).

When you rename a session, Claude Code also updates the shared record your other sessions use to look up the session's name. If it can't update that record, it warns you in the `/rename` output that other sessions may still show the old name. Run the session with [`--debug`](/docs/en/cli-reference#cli-flags), and Claude Code logs the cause of the failed update.

When you rename a session, or start or resume an interactive one, with a name another live session on this machine already uses, Claude Code leaves the name with the session that already has it and [renames yours to a variant](/docs/en/sessions#name-your-sessions). Sessions can still share a name, for example when one of them runs an earlier version of Claude Code or the shared name is one Claude Code generated. Unless this session is connected to Remote Control, Claude Code shows each local session's working directory in the `/list-agents` output, so you can tell same-named sessions apart when they run in different directories. Claude addresses the message in one of two ways, depending on how many live sessions answer to the name:

* **One session answers to the name**: Claude Code delivers the message on the name alone.
* **Several sessions share the name, or Claude Code couldn't check everywhere your sessions run**: Claude adds a short identifier to each row of its listing and uses the identifier in the address.

### Message sessions on other machines

How a message travels, and whether it passes through Anthropic servers, depends on where the target session runs:

| Where the other session runs                            | How the message travels                                                                                                      |
| :------------------------------------------------------ | :--------------------------------------------------------------------------------------------------------------------------- |
| On this machine                                         | Over a per-session socket on macOS and Linux, or a per-session named pipe on native Windows, never through Anthropic servers |
| On another of your machines                             | Through Anthropic servers, arriving over that machine's [Remote Control](/docs/en/remote-control) connection                      |
| On [Claude Code on the web](/docs/en/claude-code-on-the-web) | Through Anthropic servers, straight to the cloud session                                                                     |

Starting a conversation with a session on another of your machines requires Claude Code v2.1.225 or later and a target that [appears in the listing](#see-which-sessions-claude-can-reach). Before v2.1.225, Claude could only reply to a message that arrived from one.

Same-machine delivery works wherever the feature is enabled. Each session registers itself in files on disk. When Claude lists or messages your local sessions, Claude Code reads those files to find the sessions, so two sessions can reach each other only when they can see the same files.

A container has its own filesystem, so a session inside it and a session on the host can't reach each other. Two sessions inside the same container can still message each other, including on a [self-hosted runner](/docs/en/self-hosted-environments). A session inside WSL 2 and a native Windows session on the same computer can't reach each other either, because they register under different home directories and listen on different socket types.

While this session is connected to Remote Control, when you message a session on another of your machines, Claude Code shows the message in that session's conversation under this session's Remote Control name. The Claude on that machine can reply to that name. For example, when this session is connected to Remote Control as `laptop-graceful-unicorn` and you message your desktop, you see the message in the desktop session under `laptop-graceful-unicorn`.

If this session isn't connected to Remote Control when Claude sends to a session beyond this machine, the message still goes through, but without a [reply address](#what-a-message-looks-like), so the receiving Claude can't answer it. Claude is told as much when it sends.

To require your approval before any message goes beyond this machine, set [`isolatePeerMachines`](#require-approval-for-cross-machine-messages).

## How a session treats an incoming message

When session A messages session B, Claude Code tells B's Claude that the message came from another session, not from you, and limits what the message can do:

* **It can't approve anything**: a message from another session never counts as your consent, so it can't answer a pending permission prompt on your behalf.
* **It can't change configuration**: Claude Code instructs the receiving Claude never to change permission settings, `CLAUDE.md`, or other configuration because another session asked.
* **Commands don't run**: a command in the message's text, such as `/compact`, arrives as plain text. Claude Code never executes it.
* **Permission prompts still fire**: if acting on the message requires a permission the receiving session doesn't have, you see the same prompt you'd see for any other work.

<h3 id="what-a-message-looks-like">
  What a message looks like
</h3>

When a message arrives, Claude Code shows it in the conversation as a dim one-line preview, and the preview line stays in the conversation afterward. The preview carries the sender's name and the first line of the message, cut with `…` when it's long, such as `› Message from @api-worker: Schema migration finished (ctrl+o to expand)`. Before v2.1.247, Claude Code showed the arriving message in full instead of a preview.

Either of these shows you the full text:

* Press `Ctrl+O` to open the [transcript viewer](/docs/en/interactive-mode#transcript-viewer) and read the full text under the sender's session name.
* In a session started with [`--verbose`](/docs/en/cli-reference#cli-flags), Claude Code shows the full text instead of the preview.

The preview shortens only what you see. Whether or not you expand it, Claude reads the full message.

Claude receives the message with the sender's name and a reply address, except for a [one-way cross-machine message](#message-sessions-on-other-machines), which carries no reply address. Beyond the name and reply address, the receiving Claude gets the message's text, never the sender's conversation history or files. [Message delivery](#message-delivery) covers `@` mentions in the text.

A message that a [subagent](/docs/en/sub-agents) wrote arrives under the sending session's name, with the subagent identified in the message text. A reply to it reaches that session's main conversation, not the subagent.

This example is a message one Claude wrote to another, as its full text reads when you expand it:

```text wrap theme={null}
Schema migration finished
The new column is tenant_id, and rebasing on main is safe now.
```

### Control inbound messages

Set [`crossSessionInbound`](/docs/en/settings-reference#crosssessioninbound) to choose what a session does with messages arriving from your other sessions:

| Value    | Behavior                                                                                                                                                                                                         |
| :------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `accept` | Claude Code delivers each message to Claude                                                                                                                                                                      |
| `hold`   | Claude Code shows a notice for each message and doesn't deliver it. If an `accept` later applies, per the [precedence rules](/docs/en/settings-reference#crosssessioninbound), Claude Code releases the held messages |
| `refuse` | Claude Code drops each message without delivering it                                                                                                                                                             |

Beyond editing a settings file, you can select the value in the `/config` row **Messages from your other sessions**. Claude Code writes the value you select to your user settings. The row requires Claude Code v2.1.232 or later and doesn't appear while managed settings or the `--settings` flag sets the key, since a user-settings value wouldn't apply then. Claude Code rejects the `/config crossSessionInbound=value` shorthand for this key.

To see which value applies, follow the `crossSessionInbound` precedence rules in the [settings reference](/docs/en/settings-reference#crosssessioninbound). When no value applies, Claude Code decides per message from the two sessions' permission modes. It groups sessions that [bypass permission prompts](/docs/en/permission-modes#skip-all-checks-with-bypasspermissions-mode) into one class, and every other session into the other. Plan mode counts as bypassing in sessions with bypass permissions available, and [auto](/docs/en/permission-modes#eliminate-prompts-with-auto-mode), `acceptEdits`, and `dontAsk` count as prompting:

* **The receiving session prompts for permissions**: Claude Code delivers each message. It holds one for your approval only when the sending session identifies itself as bypassing permission prompts.
* **The receiving session bypasses permission prompts**: Claude Code holds each message for your approval. It delivers one only when the sending session identifies itself as also bypassing.

When the default holds a message, Claude Code opens an approval dialog in the receiving session. The dialog shows the sender and a preview:

* **Approve** delivers that one message to Claude.
* **Deny**, or dismissing the dialog, drops it.
* When the dialog stays unanswered past the [`dialogExpiry`](/docs/en/settings-reference#dialogexpiry) deadline, Claude Code closes it and drops the message. The deadline defaults to five minutes. While no terminal is attached to a [background session](/docs/en/agent-view), Claude Code leaves the dialog open past the deadline. After you attach, Claude Code closes the dialog and drops the message only if it stays unanswered for a full deadline period.
* If this session's permission-mode class changes while messages are held, Claude Code re-applies the inbound rules, delivers the messages they now accept, and shows a notice.
* If a settings change makes `refuse` apply while messages are held, Claude Code drops every held message and reports a refusal to each sender it can reach.

When the sender is an interactive session on the same machine, Claude Code shows a notice there when the receiver holds the message, and a follow-up when the receiver later delivers, denies, or expires it. If the receiver refuses it, Claude Code shows a notice there that the receiver isn't accepting cross-session messages and tells the sender's Claude not to wait or resend.

Claude Code holds at most 100 messages, separately from the delivery queue, and past that drops the oldest.

### Non-interactive sessions

Claude Code binds an inbox socket for a [`claude -p`](/docs/en/headless) session like an interactive one, so a long-running `-p` worker can receive messages and appears in the listing. When you start a session in [bare mode](/docs/en/headless#start-faster-with-bare-mode), Claude Code doesn't bind the socket, so that session can't receive messages and doesn't appear in the agent list.

A `-p` session can't show the approval dialog. When the [inbound default](#control-inbound-messages) holds a message there, Claude Code keeps it for the same [`dialogExpiry`](/docs/en/settings-reference#dialogexpiry) deadline the dialog uses, five minutes by default:

* **Before the deadline**: if a mode or settings change allows the message, Claude Code delivers it.
* **Past the deadline**: Claude Code drops the message and reports it as expired to a sender it can reach.

Set `dialogExpiry` to `"never"` to keep default-held messages until the session ends. A message held by an explicit `hold` setting doesn't expire; Claude Code delivers it only when an `accept` later applies.

When the session ends with messages still held, Claude Code reports them as expired to each sender it can reach. Before v2.1.225, no deadline applied in a `-p` session: a held message stayed held unless a permission-mode change during the run delivered it, and a session that ended with held messages reported nothing to their senders.

To let a `-p` worker take messages unattended, start it with `crossSessionInbound` set to `accept` in its `--settings` value. An `accept` in your user settings also works but applies to every session you run.

<h3 id="the-sessions-inbox-socket">
  The session's inbox socket
</h3>

Read this section when a session you expect isn't in the agent list, when you want a script or hook to post into a session, or when a sandboxed command can't reach the socket.

Claude Code binds an inbox socket for each session with cross-session messaging enabled, where other sessions on the machine deliver messages. The socket is a Unix domain socket on macOS and Linux, including Linux inside WSL 2, and a named pipe on native Windows. For which session kinds bind one, see [Non-interactive sessions](#non-interactive-sessions).

You can find the socket's path in two places:

* `/status` shows it in the `Peer address` row. The path is prefixed with `uds:`.
* Claude Code exports it to [hooks](/docs/en/hooks) and Bash commands as the [`CLAUDE_CODE_MESSAGING_SOCKET`](/docs/en/env-vars#variables) environment variable:
  * In a session that starts with messaging on, Claude Code exports the variable before any hook runs, including `SessionStart`.
  * Each session exports its own socket, never one inherited from a parent session.

On macOS and Linux, Claude Code restricts the socket to your operating-system user. On native Windows, it instead requires each connection to authenticate first with a key that only your operating-system user can read. Either way, on a shared machine another user's sessions can't deliver to it.

On macOS and Linux, Claude Code also refuses to create the socket in a directory it can't accept, for example one that another user owns, and uses a private per-user directory, `/tmp/cc-socks-<uid>`, instead. When it can't accept any directory, the session runs without an inbox: Claude Code shows a notice, `/status` shows `unavailable` and the reason in its `Peer address` row, and the [`--debug`](/docs/en/cli-reference#cli-flags) log records the full refusal.

Alongside the socket's path, Claude Code exports a per-session token as [`CLAUDE_CODE_MESSAGING_TOKEN`](/docs/en/env-vars#variables). A script posting to its own session's socket can send `{"type":"auth","token":"<token>"}` as the first line of its connection, where `<token>` is the value of `CLAUDE_CODE_MESSAGING_TOKEN`. Whether Claude Code requires the line depends on the platform:

* **macOS and Linux, including WSL 2**: the line is optional. Claude Code accepts a connection with or without it.
* **Native Windows**: the line is required. Claude Code closes any connection whose first line isn't a valid auth line and delivers nothing from that connection.

Open the connection only when the message you're posting is ready. Claude Code closes a connection that hasn't sent a complete line within 30 seconds, so capture a slow command's output first and then open the connection to send it.

The [own-child rules](#own-child-messages) below say when Claude Code consults the token and how it treats a message it can't verify.

<span id="own-child-messages" />Claude Code runs messages arriving on the socket through the same [inbound controls](#control-inbound-messages) as any other peer message, with one exception and one prerequisite:

* **Own-child messages**: when no `crossSessionInbound` value applies, Claude Code delivers a message it verifies came from the session's own child processes, such as a hook or Bash command posting back to its own session's socket.
  * On Linux, including inside WSL 2, Claude Code can verify by process evidence even for a child that has already exited. On macOS it can verify that way only while the posting process is still running, and in a container where Claude Code runs as process ID 1 it has no process evidence at all. On native Windows it also has none.
  * On macOS after the posting process has exited and in containers where Claude Code runs as process ID 1, that process evidence is missing, and Claude Code instead verifies a child that sent the session's exported [`CLAUDE_CODE_MESSAGING_TOKEN`](/docs/en/env-vars#variables) in the auth line that opened its connection. On native Windows, that token is the only way Claude Code verifies an own-child message.
  * When Claude Code can verify neither way, it treats the message like any other that asserts no permission class, so a session that bypasses permission prompts holds it for your approval.
* **Sandboxed sessions**: control whether a Bash command can reach the socket from inside the [sandbox](/docs/en/sandboxing) with the sandbox's Unix-socket settings, [`sandbox.network.allowAllUnixSockets` and `sandbox.network.allowUnixSockets`](/docs/en/settings-reference#sandbox-settings).

## Restrict cross-session messaging

Beyond the per-message defaults, you can narrow messaging in two ways. Require your approval before any message leaves the machine, or turn messaging off for a session or an organization.

### Require approval for cross-machine messages

Set [`isolatePeerMachines`](/docs/en/settings-reference#isolatepeermachines) to `true` to require your explicit approval before any `SendMessage` reaches a session beyond this machine:

```json theme={null}
{
  "isolatePeerMachines": true
}
```

With this set, Claude Code asks for your approval before Claude's message to a session beyond this machine leaves, even in `bypassPermissions` mode, which skips ordinary permission prompts. A `true` from any settings scope applies, so a checked-in project file can turn the requirement on but not off. Claude Code doesn't prompt for messages between sessions on the same machine.

### Turn off cross-session messaging

Receiving and sending are separate controls, so turn off whichever direction you need, or both. Use `crossSessionInbound` for messages that arrive, and permission rules for what Claude here can send or list:

* **Stop receiving**: set `crossSessionInbound` to `refuse`, and Claude Code drops inbound peer messages without delivering them. From project or local settings, `refuse` applies over every other source, and from your user settings it applies unless managed settings or the `--settings` flag set a value.
* **Stop sending and listing**: add [permission deny rules](/docs/en/permissions#tool-specific-permission-rules) naming `SendMessage` and `ListAgents`. Both take the bare tool name with no specifier.

Administrators can turn both sides off for an organization in [managed settings](/docs/en/managed-settings), combining the deny rules with the `refuse`:

```json theme={null}
{
  "permissions": {
    "deny": ["SendMessage", "ListAgents"]
  },
  "crossSessionInbound": "refuse"
}
```

With this in place, Claude Code still binds each session's inbox socket, but drops every message that arrives on it without delivering anything to Claude. Denying `SendMessage` also removes messaging to subagents and agent-team teammates, since the same tool serves both. A refusing session shows no visible change, in its own `/status` or in the listings of other sessions on the same machine, so to confirm it, check the settings files that apply to that session rather than its status.

## Availability

Cross-session messaging requires Claude Code v2.1.224 or later on macOS, Linux, and WSL 2, and v2.1.234 or later on native Windows. Availability, and which sessions Claude can message, also depend on your operating system, provider, and configuration:

* **Operating system**: available on macOS, Windows, and Linux, including Linux inside WSL 2.

* **Sessions on this machine**: available on every provider, including Amazon Bedrock, Claude Platform on AWS, Google Cloud's Agent Platform, and Microsoft Foundry, and in sessions that run with [feature-flag fetching](/docs/en/env-vars#features-that-need-feature-flag-fetching) off. On those providers, and with flag fetching off, same-machine messaging requires Claude Code v2.1.248 or later. Claude Code delivers these messages over a [per-session socket on your machine](#the-sessions-inbox-socket), never through Anthropic servers.

  To stop a session from receiving them, set [`crossSessionInbound`](#turn-off-cross-session-messaging) to `refuse`.

* **Sessions beyond this machine**: Claude finds your [Claude Code on the web](/docs/en/claude-code-on-the-web) sessions and your sessions on other machines from a session that is connected to Remote Control, which needs a claude.ai sign-in as this session's active authentication and the other [Remote Control requirements](/docs/en/remote-control#requirements). Claude can't find those sessions with an API key or on Amazon Bedrock, Claude Platform on AWS, Google Cloud's Agent Platform, and Microsoft Foundry.

To check a session, type `/list-agents`, also available as `/peers`. The result separates a session that doesn't have the feature from a session where something narrower blocked a message, such as a missing `SendMessage` tool or a refused send:

* **`/list-agents` isn't recognized**: the session doesn't have cross-session messaging. Work through the requirements above, starting with `claude --version` for the version requirement.
* **`/list-agents` works but a send didn't arrive**: messaging is on, and something narrower applies:
  * **Deny rules**: a [permission deny rule](#turn-off-cross-session-messaging) removes the `SendMessage` and `ListAgents` tools.
  * **Inbound controls**: the [receiving session's inbound controls](#control-inbound-messages) can hold or drop what you send it.
  * **Cloud session missing**: a cloud session appears only while this session is connected to [Remote Control](/docs/en/remote-control).
  * **Other-machine session missing**: a session on another of your machines appears only when it runs with [Remote Control](/docs/en/remote-control) and this session is connected as well.
  * **Older cloud or other-machine session missing**: Claude Code [reads those session lists newest first and stops after a bounded number of pages](#see-which-sessions-claude-can-reach), so Claude can't message a session that fell past them by name.
  * **Starting a conversation**: [Message sessions on other machines](#message-sessions-on-other-machines) covers starting a conversation with a session beyond this machine.

In a session with messaging, `/status` also shows a `Peer address` row with the session's own inbox address, or `unavailable` and the reason when Claude Code [couldn't set up an inbox](#the-sessions-inbox-socket).

## Limitations

The limits here are properties of the messaging channel itself and apply wherever the feature runs. For platform and provider gaps, see [Availability](#availability) instead.

* **Plain text only**: Claude sends only plain text across sessions. Structured [agent team](/docs/en/agent-teams) protocol messages stay within a team.
* **Same-machine message size is capped**: Claude Code refuses a message to a session on this machine once its serialized form passes about a million characters. The refusal [names the exact sizes](/docs/en/errors#message-too-large-for-cross-session-delivery). Nothing reaches the receiving session.
* **Rapid bursts to one session are refused at the sender**: once a rapid burst of messages to a session on this machine reaches what that session's inbox accepts, Claude Code refuses further sends in the sending session. The [refusal names the burst](/docs/en/errors#too-many-messages-to-this-session-just-now) and tells Claude to batch the rest into one message or wait. Before v2.1.236, Claude Code reported those sends as sent while the receiving session dropped them.
* **Message loops are throttled**: in the receiving session, Claude Code rate-limits repeated messages per sender, drops identical repeats arriving within a short window, and queues at most 50 accepted messages for Claude to read. A message loop between two sessions therefore stops on its own. When the rate limit, repeat check, or queue cap drops a message from an interactive session on this machine, Claude Code tells that session which one dropped it and tells its Claude not to resend right away.

## Related resources

* [Subagents](/docs/en/sub-agents#resume-subagents) and [agent teams](/docs/en/agent-teams#messages-between-agents): messaging within a single session or team
* [Background agents](/docs/en/agent-view): dispatch and monitor the parallel sessions you might message
* [Remote Control](/docs/en/remote-control): connect this session to reach your sessions on other machines
* [Settings](/docs/en/settings-reference#all-settings): `crossSessionInbound`, `isolatePeerMachines`, and `dialogExpiry`
* [Permission modes](/docs/en/permission-modes): the modes behind the inbound default's two classes
* [Tools reference](/docs/en/tools-reference): the `ListAgents` and `SendMessage` rows in the tools table
* [Run agents in parallel](/docs/en/agents): compare the ways Claude Code runs multiple agents



## Start Claude in a worktree

Pass `--worktree` or `-w` with a name to create an isolated worktree and start Claude in it. By default, the worktree is created under `.claude/worktrees/<name>/` at your repository root, on a new branch named `worktree-<name>`:

```bash theme={null}
claude --worktree feature-auth
```

Run the command again with a different name in another terminal to start a second isolated session. If you omit the name, Claude generates one such as `bright-running-fox`.

Interactive runs require [workspace trust](/docs/en/security): if you haven't run Claude in the directory before, run `claude` once there to accept the trust dialog, or `--worktree` exits with an error prompting you to. Non-interactive runs with `-p` skip the trust check, so `claude -p --worktree` proceeds without it.

<Tip>
  Add `.claude/worktrees/` to your `.gitignore` so worktree contents don't appear as untracked files in your main checkout.
</Tip>

### Set up the worktree environment

A worktree is a fresh checkout, so initialize your development environment there: ask Claude to install dependencies, or run your project's setup yourself in the worktree directory under `.claude/worktrees/`. To carry gitignored files such as `.env` into every new worktree automatically, add a [`.worktreeinclude` file](#copy-gitignored-files-into-worktrees).

### Ask Claude to create a worktree

You can also ask Claude to "work in a worktree" during a session, and it creates one with the [`EnterWorktree`](/docs/en/tools-reference) tool. Once in a worktree, Claude can switch directly to another one under `.claude/worktrees/` by calling `EnterWorktree` with the target path; the previous worktree stays on disk untouched.

When Claude enters a path outside the repository's `.claude/worktrees/` directory, Claude Code asks for your approval first, because the move takes the session's working directory, write access, and project configuration such as `CLAUDE.md` and settings to that location. An `EnterWorktree` [permission rule](/docs/en/permissions) or choosing "don't ask again" doesn't suppress this prompt; only `bypassPermissions` mode skips it. Before v2.1.206, Claude could enter any existing worktree path without asking.

<Note>
  **Hook paths don't follow the worktree.** After Claude enters a worktree, Claude Code keeps `${CLAUDE_PROJECT_DIR}` in your [hooks](/docs/en/hooks#reference-scripts-by-path) where it was and passes the worktree path to them a different way:

  * **`${CLAUDE_PROJECT_DIR}` stays put**: it still points at the project root where the session started, so a hook command such as `${CLAUDE_PROJECT_DIR}/.claude/hooks/check-style.sh` still runs the script in the main checkout.
  * **`cwd` follows Claude**: the `cwd` field in the hook's [input JSON](/docs/en/hooks#common-input-fields) is the worktree root, and it moves again when Claude runs `cd`. Read it when a hook needs the worktree path.
</Note>

## Clean up worktrees

When you exit an interactive worktree session, Claude checks the worktree for work that removal would delete: changed or untracked files, and new commits.

* **The worktree is clean**: for an unnamed session, Claude removes the worktree and its branch automatically. A [named](/docs/en/sessions#name-your-sessions) session prompts you first so you can keep the worktree for later
* **The worktree has work in it**: Claude prompts you to keep or remove the worktree. Keeping preserves the directory and branch so you can return later. Removing deletes the worktree directory and its branch, along with all the work in them

Non-interactive runs with `-p` have no exit prompt, so Claude doesn't clean up their worktrees, and Claude Code leaves the lock it took on each one at creation in place until a later session's [stale-lock sweep](#clean-up-subagent-and-background-session-worktrees) releases it. To remove one, run `git worktree remove`; if git refuses because the worktree is locked, run `git worktree unlock` on it first.

On Windows, removing a worktree doesn't delete files outside it. If a folder inside the worktree is a link to somewhere else, such as an NTFS junction or a directory symlink, Claude Code deletes only the link and keeps the folder it points to. Before v2.1.205, removing a worktree with a link nested in a subdirectory could delete the folder it pointed to.

## Resume a worktree session

When you resume a session that was inside a worktree, Claude Code returns the session to that worktree. This holds for interactive resumes, for `--continue` and `--resume` in [non-interactive mode](/docs/en/headless) with `-p`, and for the Agent SDK. Back inside the worktree, Claude can still exit it with the [`ExitWorktree`](/docs/en/tools-reference) tool.

Before returning the session to its worktree, Claude Code verifies that the worktree is still a checkout separate from the main one, and declines to re-enter a worktree that fails the check. For a git worktree, the check reads its git metadata. A worktree without git metadata, such as one a [`WorktreeCreate` hook](#non-git-version-control) created, can pass the check; the cases Claude Code still refuses are listed with their recoveries under [Claude Code refuses to use a worktree](#claude-code-refuses-to-use-a-worktree). For the messages and how to recover from each, see [The session resumes outside its worktree](#the-session-resumes-outside-its-worktree).

Where you launch from, and how you resume, change what Claude Code re-enters:

* **Launch directory**: resume from the main checkout or another directory of the repository. Claude Code re-enters a worktree it created with git under `.claude/worktrees/` even when you launch from inside it. When you launch from inside any other worktree, Claude Code re-enters it only if it can vouch for it from there: a worktree that is its own repository, one without git metadata, or a launch from a subdirectory of a worktree you created with `git worktree add` declines, so launch those from the main checkout.
* **`--fork-session`**: the forked session starts in the directory you launched Claude from, and Claude Code leaves the original session's worktree untouched.
* **Deleted worktree**: if the worktree directory no longer exists, Claude Code resumes the session in the directory you launched Claude from. It tells you the worktree is gone and clears the session's worktree binding.

<Note>
  Before v2.1.212, a non-interactive resume stayed in the starting directory and `ExitWorktree` reported that there was no active worktree session to exit.
</Note>

When Claude enters or exits a worktree that Claude Code created with git, the transcript follows: Claude Code records the session under the session's new working directory, the same way [`/cd`](/docs/en/commands) does, so `/desktop` and `--resume` find it there. Exiting moves it back the same way. A worktree created by a [`WorktreeCreate` hook](#non-git-version-control) keeps its transcript at the launch directory. Requires Claude Code v2.1.198 or later.

## How Claude Code enforces isolation

While a session is isolated in a worktree, Claude Code blocks the tool calls the checks below define. The same rules apply whether you started the session with `--worktree`, Claude entered a worktree with `EnterWorktree`, or you resumed a worktree session.

The same enforcement covers every subagent Claude spawns from the isolated session. It applies whether the session is interactive or runs in the [background](/docs/en/agent-view#how-file-edits-are-isolated). [Subagents that run in their own worktree](#isolate-subagents-with-worktrees) carry the same checks. Their version history is under [Write subagent files](/docs/en/sub-agents#write-subagent-files).

Claude Code applies four checks:

* **File edits**: Claude Code blocks an `Edit`, `Write`, or `NotebookEdit` that targets a path in the main checkout.
* **Command working directory**: Claude Code blocks a Bash, PowerShell, or Monitor command whose working directory resolves to the main checkout, or whose working directory it can't verify stays outside it.
* **Git redirects**: Claude Code blocks a Bash or Monitor command that redirects git into the main checkout. The redirect can come through `git -C`, `--git-dir`, a `GIT_DIR` or `GIT_WORK_TREE` variable, or a `cd` into the main checkout before running git.
* **Command shape**: Claude Code blocks a Bash or Monitor command it can't verify stays inside the worktree, even when the command runs no git at all. Claude Code refuses shell constructs it can't trace without running them, such as brace expansion and heredocs with unquoted delimiters. Claude Code tells Claude how to rewrite the refused command, such as splitting it into plain, separate commands. You can't turn this check off.

The checks apply to the repository you launched Claude Code from. They also cover the main checkout a linked worktree is linked from. For PowerShell commands, Claude Code applies only the working-directory check.

Claude sees each refusal as a tool error that names the worktree and says how to proceed.

## Isolate subagents with worktrees

Subagents can run in their own worktrees so parallel edits don't conflict. Ask Claude to "use worktrees for your agents", or make the isolation permanent for a [custom subagent](/docs/en/sub-agents#supported-frontmatter-fields) by adding `isolation: worktree` to its frontmatter.

This subagent in `.claude/agents/` always runs in its own worktree:

```markdown theme={null}
---
name: refactorer
description: Applies mechanical refactors across many files
isolation: worktree
---

Apply the requested refactor across every affected file, then run the tests
and report the results.
```

Each subagent gets a temporary worktree that Claude Code removes automatically when the subagent finishes without changes; a worktree with changes stays on disk until the [periodic sweep below](#clean-up-subagent-and-background-session-worktrees) can remove it without losing work.

Subagent worktrees use the same [base branch](#choose-the-base-branch) as `--worktree`, so they branch from your repository's default branch unless `worktree.baseRef` is set to `"head"`.

### Clean up subagent and background-session worktrees

Claude Code runs a periodic sweep that removes worktrees that Claude created for subagents and [background sessions](/docs/en/agent-view#how-file-edits-are-isolated) once they are older than your [`cleanupPeriodDays`](/docs/en/settings-reference#cleanupperioddays) setting, following the [retention sweep rules](/docs/en/claude-directory#cleaned-up-automatically).

When you [background](/docs/en/agent-view#send-the-session-to-the-background) a `--worktree` session, its worktree becomes a background-session worktree that the sweep can remove. The sweep leaves a worktree in place in these cases:

* The worktree still holds work: changed or untracked files, or unpushed commits.
* Claude Code can't determine which filter drivers the repository config defines, in any of the [three cases that also block worktree creation](#git-lfs-content-is-missing-from-a-worktree-claude-code-created).
* The worktree belongs to a `--worktree` session you haven't backgrounded, whatever its age.
* You created the worktree yourself with `git worktree add`, even if you then ran a `--worktree <name>` session in it and backgrounded that session.

Claude Code writes a marker into the git metadata of every worktree it creates with git, and the sweep keeps any worktree without one, including a worktree a [`WorktreeCreate` hook](#non-git-version-control) created. Before v2.1.246, the sweep didn't check for the marker, and could remove a worktree you created yourself when an old background-session record pointed at it.

While an agent is running, Claude Code holds a `git worktree lock` on its worktree so that concurrent cleanup can't remove it, and releases the lock when the agent finishes. Claude Code holds the same lock on the worktree it created for a backgrounded session while the session runs, so the sweep leaves the worktree in place and `git worktree remove` refuses to remove it.

The sweep also releases a lock Claude Code set for a session whose process has exited, so a killed background session doesn't leave its worktree permanently locked. The sweep never releases a lock you set yourself with `git worktree lock`. Before v2.1.210, a lock left by a killed session stayed in place until you ran `git worktree unlock`.

To clean up a worktree that the sweep keeps, run `git worktree remove`, adding `--force` if the worktree has uncommitted changes or untracked files. If git refuses because the worktree is locked, run `git worktree unlock` on it first.

## Customize worktree creation

Claude Code's defaults for creating worktrees cover most sessions: it creates them under `.claude/worktrees/`, branches them from your repository's default branch, and checks out only tracked files. The options in this section change those defaults.

### Choose the base branch

New worktrees branch from the repository's default branch, so most sessions don't need this setting. Set `worktree.baseRef` in [settings](/docs/en/settings-reference#worktree) to branch from your current work instead. The setting accepts two values:

* `"fresh"` (default): branch from the repository's default branch on the remote, usually `main`, so the worktree starts from a clean tree matching the remote.
* `"head"`: branch from your current local `HEAD`, so the worktree carries your unpushed commits and feature-branch state. Use this when isolating subagents that need to operate on in-progress work. Inside a worktree, `"head"` resolves to that worktree's `HEAD`, not the main checkout's.

You can't set `worktree.baseRef` to a branch name. To start a worktree from a specific existing branch, [create it with git directly](#manage-worktrees-manually).

For a `"fresh"` base, Claude Code keeps `origin/HEAD` current: when the repository hasn't been fetched in the last 24 hours, it fetches the default branch, capped at five seconds, and uses the locally cached ref if the fetch fails. If no remote is configured, or `origin/HEAD` isn't cached locally and can't be fetched, the worktree falls back to your current local `HEAD`. Before v2.1.208, a fresh worktree used whatever `origin/HEAD` was already cached locally.

This example makes every new worktree branch from your current work:

```json theme={null}
{
  "worktree": {
    "baseRef": "head"
  }
}
```

### Branch from a pull request

To branch from a specific pull request or merge request, pass `--worktree` the number prefixed with `#`, a GitHub pull request URL, or a GitLab merge request URL such as `https://gitlab.com/group/repo/-/merge_requests/123`. Claude Code fetches that change's head commit from `origin` and creates the worktree at `.claude/worktrees/pr-<number>`. Quote the argument so your shell doesn't treat `#` as the start of a comment:

```bash theme={null}
claude --worktree "#1234"
```

Claude Code reads only the number from the URL. It always fetches from your repository's `origin` remote, and picks the fetch path by `origin`'s host:

* **github.com**: fetches `pull/<number>/head`
* **gitlab.com**: fetches `merge-requests/<number>/head`
* **GitHub Enterprise, self-managed GitLab, or any other host**: tries `pull/<number>/head` first, then `merge-requests/<number>/head`

Before v2.1.233, Claude Code accepted only `#<number>` and GitHub-style pull request URLs for `--worktree`, and always fetched `pull/<number>/head`.

### Copy gitignored files into worktrees

A worktree is a fresh checkout, so untracked files like `.env` or `.env.local` from your main repository are not present. To copy them automatically when Claude creates a worktree, add a `.worktreeinclude` file to your project root.

The file uses `.gitignore` syntax. Only files that match a pattern and are also gitignored are copied, so tracked files are never duplicated.

If you write a pattern that starts with `**/` and the files you want are inside a directory that is gitignored as a whole, Claude Code copies them only when that directory itself matches the pattern, or when the first name after the `**/` is one of the names in the directory's path. For example, if you write `**/.claude/skills/*.md`, that first name is `.claude`, so Claude Code copies the matching files out of an ignored `.claude/` directory. To copy files out of an ignored directory that a `**/` pattern doesn't reach, name the directory in the pattern instead: write `vendor/**/config.json` rather than `**/config.json`. Before v2.1.239, Claude Code copied files out of a wholly ignored directory for a `**/` pattern only when the directory itself matched the pattern.

This `.worktreeinclude` copies two env files and a secrets config into each new worktree:

```text .worktreeinclude theme={null}
.env
.env.local
config/secrets.json
```

This applies to every worktree Claude Code creates with git: `--worktree` worktrees, [subagent worktrees](#isolate-subagents-with-worktrees), and parallel sessions in the [desktop app](/docs/en/desktop#work-in-parallel-with-sessions). With a [`WorktreeCreate` hook](#non-git-version-control), copy the files inside the hook script.

### Reuse a worktree name

Passing `--worktree` a name whose directory already exists opens that existing worktree instead of creating a new one.

With the default `"fresh"` [base](#choose-the-base-branch), a reopened worktree resets to the repository's default branch instead of continuing at its old tip when all of the following hold:

* It has no uncommitted changes or untracked files.
* It is still on the branch Claude Code created for it.
* It has no commits of its own, or its pull request or merge request was merged and its remote branch deleted.

Claude Code detects the merged case from git state alone: the remote branch the worktree pushed to no longer exists, and every commit in the worktree is already on the default branch.

In every other case, Claude Code reopens the worktree at its old tip:

* The worktree fails any of the conditions.
* Claude Code can't verify the worktree's state.
* `worktree.baseRef` is `"head"`.
* The name is a pull request or merge request reference.

Before v2.1.208, when you reused a name, Claude Code always reopened the old worktree at its old tip.

### Replace worktree creation with a hook

Configure a [`WorktreeCreate` hook](/docs/en/hooks#worktreecreate) to replace the default `git worktree` logic entirely, including placing worktrees somewhere other than `.claude/worktrees/`. For a complete example, see [Non-git version control](#non-git-version-control).

## What worktrees share with the main checkout

A worktree gets its own files and branch, but it shares the repository's `.git` directory, project-scope plugins, and saved permission approvals with the main checkout:

* **The repository's `.git` directory**: git commands in a worktree write to the main repository's shared `.git` directory, and [sandboxing](/docs/en/sandboxing#filesystem-isolation) allows those writes, so commands such as `git commit` work from inside a worktree with the sandbox enabled.
* **Plugins**: plugins installed at [project scope](/docs/en/plugins-reference#plugin-installation-scopes) from the main checkout also load in worktrees of the same repository, so you don't need to reinstall them per worktree. Requires Claude Code v2.1.200 or later.
* **Permission approvals**: choosing "Yes, and don't ask again" for a Bash command in a worktree session saves the rule to the main checkout's `.claude/settings.local.json`, so it applies in the main checkout and in every other worktree of the repository, and it survives the worktree's removal. On Windows and in the other cases where Claude Code [doesn't use the repository root](/docs/en/settings#where-claude-code-looks-for-each-file), the rule stays with that worktree. Before v2.1.211, an approval granted in a worktree was saved inside that worktree, didn't apply elsewhere, and was lost when the worktree was removed. See [where approvals are saved](/docs/en/permissions#permission-system).

All three apply whether you create the worktree with `--worktree`, with `git worktree add`, or through the [desktop app](/docs/en/desktop#work-in-parallel-with-sessions).

## Manage worktrees manually

Create worktrees with Git directly when you need to check out a specific existing branch or place the worktree outside the repository.

Create a worktree on a new branch:

```bash theme={null}
git worktree add ../project-feature-a -b feature-a
```

Create a worktree from an existing branch, replacing `fix-issue-456` with a branch that already exists in your repository:

```bash theme={null}
git worktree add ../project-bugfix fix-issue-456
```

Start Claude in the worktree:

```bash theme={null}
cd ../project-feature-a
claude
```

List your worktrees:

```bash theme={null}
git worktree list
```

Remove one when you're done with it:

```bash theme={null}
git worktree remove ../project-feature-a
```

See the [Git worktree documentation](https://git-scm.com/docs/git-worktree) for the full command reference.

## Non-git version control

Worktree isolation uses git by default. For SVN, Perforce, Mercurial, or other systems, configure [`WorktreeCreate` and `WorktreeRemove` hooks](/docs/en/hooks#worktreecreate) to provide custom creation and cleanup logic. Because the hook replaces the default git behavior, [`.worktreeinclude`](#copy-gitignored-files-into-worktrees) is not processed when you use `--worktree`. Copy any local configuration files inside your hook script instead.

This `WorktreeCreate` hook reads the worktree name from the JSON on stdin with `jq`, checks out a fresh SVN working copy, and prints the directory path so Claude Code can use it as the session's working directory. Add the configuration to your [`settings.json`](/docs/en/settings#where-settings-live):

```json theme={null}
{
  "hooks": {
    "WorktreeCreate": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'NAME=$(jq -r .name); DIR=\"$HOME/.claude/worktrees/$NAME\"; svn checkout https://svn.example.com/repo/trunk \"$DIR\" >&2 && echo \"$DIR\"'"
          }
        ]
      }
    ]
  }
}
```

Pair it with a `WorktreeRemove` hook to clean up when the session ends. See the [hooks reference](/docs/en/hooks#worktreecreate) for the input schema and a removal example.

## Troubleshooting

Claude Code reports the errors below when it creates a worktree, enters one at startup, or returns a resumed session to one.

### Claude Code can't enter the worktree at startup

When Claude Code can't enter the worktree directory at startup, it prints an error naming the path and exits with code 1. This can happen when a [`WorktreeCreate` hook](/docs/en/hooks#worktreecreate) prints something other than the directory it created, or when the directory was deleted after it was set up.

### Worktree creation fails on a symlinked path

Claude Code refuses to create a worktree when `.claude`, `.claude/worktrees`, or the worktree directory itself is a symlink, and the error names the symlinked path. Remove the symlink and retry. Before v2.1.212, if the repository already contained a committed symlink at one of those paths, worktree creation followed it and could create files outside the repository.

<h3 id="git-lfs-content-is-missing-from-a-worktree-claude-code-created">
  Git LFS files are pointer files in a worktree Claude Code created
</h3>

If you set up [Git LFS](https://git-lfs.com) with `git lfs install --local`, a worktree that Claude Code creates contains LFS pointer files instead of the real files. The `--local` flag writes the LFS filter into the repository's own `.git/config` rather than your global git config. A plain `git lfs install` writes to your global config and isn't affected. The same applies to any other [filter driver](https://git-scm.com/docs/gitattributes) defined in the repository's own config.

Claude Code skips the repository's own filter drivers when it creates a worktree because a filter driver is a shell command, and anything that can write to the repository, including Claude, could have put one there. Before v2.1.247, Claude Code ran those drivers during worktree creation.

To get the real files, run `git lfs pull` inside the worktree.

In three rare cases, Claude Code can't tell which filter drivers the repository's config defines, and creates no worktree at all. Match the error to its fix:

* **`Could not read the repository git config to neutralize filter drivers`**: Claude Code couldn't read the repository's `.git/config`, for example because of its permissions. Fix that and retry.
* **`The repository git config defines a filter driver whose name cannot be neutralized (contains "=" or a newline)`**: rename or remove that filter driver in `.git/config` and retry.
* **`The repository git config has a conditional include (includeIf)`**: move the settings the `includeIf` in `.git/config` pulls in directly into that file, remove the `includeIf`, and retry. An `includeIf` in your global git config doesn't trigger this.

### Claude Code refuses to use a worktree

An error starting `Refusing to use <path> as an isolation worktree` means Claude Code checked the directory's git identity before adopting it as a session's or subagent's isolated checkout, and declined it. The check runs whether Claude Code is creating the worktree, entering an existing one, or reusing one from an earlier run.

In most cases the rest of the message says the directory's git metadata resolves into the main checkout: for example, its `.git` file points at the main repository's own `.git` directory, or git resolves its working tree to the main checkout through a `core.worktree` redirect. From such a directory, an ordinary git command such as `git reset --hard` would act on the main checkout instead of the worktree. Claude Code also refuses when the directory has a `.git` entry it can't read, rather than assuming the worktree is safe.

Claude Code leaves the refused directory in place, since it may hold work. Match the message to its recovery, whether it follows `Refusing to use <path>` or appears in a [resume message](#the-session-resumes-outside-its-worktree); some endings occur only in resume messages:

* **Says `launch from the parent checkout` or `Run the resume from the project checkout`**: you launched Claude Code from inside the worktree. Launch from the main checkout instead; the worktree needs no recreation.
* **Says `it cannot be resumed or re-entered`**: nothing in this session vouches for the worktree from where you launched. Recreate it; the directory and its work remain on disk for manual recovery, and when the worktree has a parent checkout, resuming from there also works.
* **Says `it contains the protected checkout`**: the refused directory is a parent of your main checkout, such as your home directory. Don't delete it. Change the worktree path, such as the path your `WorktreeCreate` hook returns or the `EnterWorktree` target, so the worktree doesn't contain the checkout.
* **Says `the protected checkout <path> has a .git entry that could not be examined` or `has git metadata that could not be resolved`**: the problem is the main checkout's git metadata, not the worktree's. Don't delete the worktree, and ignore the message's trailing advice to recreate it, which doesn't apply to these two endings. Repair the main checkout, for example a permissions problem or a git `dubious ownership` refusal on its `.git`, and retry.
* **Says `its recorded path has a network spelling`**: Claude Code never resumes into a worktree at a network path. Recreate the worktree at a local path.
* **Any other ending**: the message names the problem and its fix, such as removing a `core.worktree` redirect or recreating the worktree; follow it. Before deleting a directory whose message says its git identity could not be verified, address the named cause first, for example a symbolic link in the worktree's path or git itself failing to run, since the directory may be healthy. When you do recreate, salvage any changes you need from the old directory first; it stays on disk.

### The session resumes outside its worktree

When an interactive resume can't return the session to its worktree, Claude Code says so with one of the messages below.

| Message starts with                               | What happened and what to do                                                                                                                                                                                                                                                                                                                                                                                                                        |
| :------------------------------------------------ | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Your worktree <path> no longer exists`           | The worktree directory was removed. The session continues in the current directory without isolation, and Claude Code clears the worktree binding. No action needed.                                                                                                                                                                                                                                                                                |
| `Could not verify your worktree <path> this time` | Claude Code couldn't verify the worktree, usually for a transient reason; the binding is kept, and the session continues in the current directory without isolation. Resume again to retry; if it keeps happening, enter the worktree in a new session and match the refusal message under [Claude Code refuses to use a worktree](#claude-code-refuses-to-use-a-worktree), which can name the main checkout's metadata rather than the worktree's. |
| `Did not re-enter your worktree <path>`           | Claude Code refused the worktree binding as unsafe; it clears the binding and the session continues without isolation. The message includes the specific refusal: match it under [Claude Code refuses to use a worktree](#claude-code-refuses-to-use-a-worktree), since the fix is recreation for some refusals and a path change for others.                                                                                                       |
| `Could not re-enter your worktree <path>`         | Claude Code couldn't vouch for the worktree from where you launched, most commonly because you launched from inside it; the binding is kept. The rest of the message names the fix; match it under [Claude Code refuses to use a worktree](#claude-code-refuses-to-use-a-worktree).                                                                                                                                                                 |

In [non-interactive mode](/docs/en/headless) with `-p`, and on resumes the [Agent SDK](/docs/en/agent-sdk/sessions) runs, Claude Code stops the resume with a stderr error for every refusal except a gone worktree, instead of continuing without isolation, and the messages take different shapes from the ones in the table above:

* `Error: cannot resume into worktree <path>: ...This session was not started.` for a refusal the table shows as `Did not re-enter`
* `Error: could not verify worktree <path> for this resume, so the resume was aborted...` for `Could not verify`
* `Error: ...The worktree binding is kept.` for `Could not re-enter`
* `Notice: the worktree <path> for this session no longer exists...` for a gone worktree; Claude Code prints it and continues the session, as an interactive resume does

The refusal ending embedded in each error is shared with the interactive notices, so it still matches its entry under [Claude Code refuses to use a worktree](#claude-code-refuses-to-use-a-worktree).

## See also

Worktrees handle file isolation. The related pages below cover delegating work into those isolated checkouts, passing findings between them, and switching between the sessions you create:

* [Subagents](/docs/en/sub-agents): delegate work to isolated agents within a session
* [Cross-session messaging](/docs/en/cross-session-messaging): let the sessions in your worktrees pass findings to each other
* [Agent teams](/docs/en/agent-teams): coordinate multiple Claude sessions automatically
* [Manage sessions](/docs/en/sessions): name, resume, and switch between conversations
* [Desktop parallel sessions](/docs/en/desktop#work-in-parallel-with-sessions): worktree-backed sessions in the desktop app



## Supported channels

Each supported channel is a plugin that requires [Bun](https://bun.sh). For a hands-on demo of the plugin flow before connecting a real platform, try the [fakechat quickstart](#quickstart).

<Tabs>
  <Tab title="Telegram">
    View the full [Telegram plugin source](https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/telegram).

    <Steps>
      <Step title="Create a Telegram bot">
        Open [BotFather](https://t.me/BotFather) in Telegram and send `/newbot`. Give it a display name and a unique username ending in `bot`. Copy the token BotFather returns.
      </Step>

      <Step title="Install the plugin">
        In Claude Code, run:

        ```
        /plugin install telegram@claude-plugins-official
        ```

        If the install fails, match the message Claude Code reports:

        * `Marketplace "claude-plugins-official" not found`: add the marketplace with `/plugin marketplace add anthropics/claude-plugins-official`, then retry the install.
        * The plugin is [not found in the marketplace](/docs/en/discover-plugins#install-plugins): check the plugin name.

        When the install asks for an installation scope, choose the user scope option so the plugin is available across all your projects. Check the install summary: if it reports `Run /reload-plugins to activate.`, run that command to activate the plugin's configure command.
      </Step>

      <Step title="Configure your token">
        Run the configure command with the token from BotFather:

        ```
        /telegram:configure <token>
        ```

        This saves it to `~/.claude/channels/telegram/.env`. You can also set `TELEGRAM_BOT_TOKEN` in your shell environment before launching Claude Code.
      </Step>

      <Step title="Restart with channels enabled">
        Exit Claude Code and restart with the channel flag. This starts the Telegram plugin, which begins polling for messages from your bot:

        ```bash theme={null}
        claude --channels plugin:telegram@claude-plugins-official
        ```
      </Step>

      <Step title="Pair your account">
        Open Telegram and send any message to your bot. The bot replies with a pairing code.

        <Note>If your bot doesn't respond, make sure Claude Code is running with `--channels` from the previous step. The bot can only reply while the channel is active.</Note>

        Back in Claude Code, run:

        ```
        /telegram:access pair <code>
        ```

        Then lock down access so only your account can send messages:

        ```
        /telegram:access policy allowlist
        ```
      </Step>
    </Steps>
  </Tab>

  <Tab title="Discord">
    View the full [Discord plugin source](https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/discord).

    <Steps>
      <Step title="Create a Discord bot">
        Go to the [Discord Developer Portal](https://discord.com/developers/applications), click **New Application**, and name it. In the **Bot** section, create a username, then click **Reset Token** and copy the token.
      </Step>

      <Step title="Enable Message Content Intent">
        In your bot's settings, scroll to **Privileged Gateway Intents** and enable **Message Content Intent**.
      </Step>

      <Step title="Invite the bot to your server">
        Go to **OAuth2 > URL Generator**. Select the `bot` scope and enable these permissions:

        * View Channels
        * Send Messages
        * Send Messages in Threads
        * Read Message History
        * Attach Files
        * Add Reactions

        Open the generated URL to add the bot to your server.
      </Step>

      <Step title="Install the plugin">
        In Claude Code, run:

        ```
        /plugin install discord@claude-plugins-official
        ```

        If the install fails, match the message Claude Code reports:

        * `Marketplace "claude-plugins-official" not found`: add the marketplace with `/plugin marketplace add anthropics/claude-plugins-official`, then retry the install.
        * The plugin is [not found in the marketplace](/docs/en/discover-plugins#install-plugins): check the plugin name.

        When the install asks for an installation scope, choose the user scope option so the plugin is available across all your projects. Check the install summary: if it reports `Run /reload-plugins to activate.`, run that command to activate the plugin's configure command.
      </Step>

      <Step title="Configure your token">
        Run the configure command with the bot token you copied:

        ```
        /discord:configure <token>
        ```

        This saves it to `~/.claude/channels/discord/.env`. You can also set `DISCORD_BOT_TOKEN` in your shell environment before launching Claude Code.
      </Step>

      <Step title="Restart with channels enabled">
        Exit Claude Code and restart with the channel flag. This connects the Discord plugin so your bot can receive and respond to messages:

        ```bash theme={null}
        claude --channels plugin:discord@claude-plugins-official
        ```
      </Step>

      <Step title="Pair your account">
        DM your bot on Discord. The bot replies with a pairing code.

        <Note>If your bot doesn't respond, make sure Claude Code is running with `--channels` from the previous step. The bot can only reply while the channel is active.</Note>

        Back in Claude Code, run:

        ```
        /discord:access pair <code>
        ```

        Then lock down access so only your account can send messages:

        ```
        /discord:access policy allowlist
        ```
      </Step>
    </Steps>
  </Tab>

  <Tab title="iMessage">
    View the full [iMessage plugin source](https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/imessage).

    The iMessage channel reads your Messages database directly and sends replies through AppleScript. It requires macOS and needs no bot token or external service.

    <Steps>
      <Step title="Grant Full Disk Access">
        The Messages database at `~/Library/Messages/chat.db` is protected by macOS. The first time the server reads it, macOS prompts for access: click **Allow**. The prompt names whichever app launched Bun, such as Terminal, iTerm, or your IDE.

        If the prompt doesn't appear or you clicked Don't Allow, grant access manually under **System Settings > Privacy & Security > Full Disk Access** and add your terminal. Without this, the server exits immediately with `authorization denied`.
      </Step>

      <Step title="Install the plugin">
        In Claude Code, run:

        ```
        /plugin install imessage@claude-plugins-official
        ```

        If the install fails, match the message Claude Code reports:

        * `Marketplace "claude-plugins-official" not found`: add the marketplace with `/plugin marketplace add anthropics/claude-plugins-official`, then retry the install.
        * The plugin is [not found in the marketplace](/docs/en/discover-plugins#install-plugins): check the plugin name.

        When the install asks for an installation scope, choose the user scope option so the plugin is available across all your projects. If the install summary reports `Run /reload-plugins to activate.`, you can skip that here, because restarting in the next step picks up the plugin.
      </Step>

      <Step title="Restart with channels enabled">
        Exit Claude Code and restart with the channel flag:

        ```bash theme={null}
        claude --channels plugin:imessage@claude-plugins-official
        ```
      </Step>

      <Step title="Text yourself">
        Open Messages on any device signed into your Apple ID and send a message to yourself. It reaches Claude immediately: self-chat bypasses access control with no setup.

        <Note>The first reply Claude sends triggers a macOS Automation prompt asking if your terminal can control Messages. Click **OK**.</Note>
      </Step>

      <Step title="Allow other senders">
        By default, only your own messages pass through. To let another contact reach Claude, add their handle:

        ```
        /imessage:access allow +15551234567
        ```

        Handles are phone numbers in `+country` format or Apple ID emails like `user@example.com`.
      </Step>
    </Steps>
  </Tab>
</Tabs>

## Quickstart

Fakechat is an officially supported demo channel that runs a chat UI on localhost, with nothing to authenticate and no external service to configure.

Once you install and enable fakechat, you can type in the browser and the message arrives in your Claude Code session. Claude replies, and the reply shows up back in the browser. After you've tested the fakechat interface, try out [Telegram](https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/telegram), [Discord](https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/discord), or [iMessage](https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/imessage).

To try the fakechat demo, you'll need:

* Claude Code [installed and authenticated](/docs/en/quickstart#step-1-install-claude-code) with a claude.ai account or a Claude Console API key
* [Bun](https://bun.sh) installed. The pre-built channel plugins are Bun scripts. Check with `bun --version`; if that fails, [install Bun](https://bun.sh/docs/installation).
* **Team, Enterprise, or managed Console org**: your admin must [enable channels](#enterprise-controls) in managed settings

<Steps>
  <Step title="Install the fakechat channel plugin">
    Start a Claude Code session and run the install command:

    ```text theme={null}
    /plugin install fakechat@claude-plugins-official
    ```

    If the install fails, match the message Claude Code reports:

    * `Marketplace "claude-plugins-official" not found`: add the marketplace with `/plugin marketplace add anthropics/claude-plugins-official`, then retry the install.
    * The plugin is [not found in the marketplace](/docs/en/discover-plugins#install-plugins): check the plugin name.

    When the install asks for an installation scope, choose the user scope option so the plugin is available across all your projects. If the install summary reports `Run /reload-plugins to activate.`, you can skip that here, because restarting in the next step picks up the plugin.
  </Step>

  <Step title="Restart with the channel enabled">
    Exit Claude Code, then restart with `--channels` and pass the fakechat plugin you installed:

    ```bash theme={null}
    claude --channels plugin:fakechat@claude-plugins-official
    ```

    The fakechat server starts automatically. The startup screen shows a channels notice stating that messages from `plugin:fakechat@claude-plugins-official` inject directly in this session. If the plugin isn't installed or isn't on the approved allowlist, a warning line naming the problem appears below that notice.

    <Tip>
      You can pass several plugins to `--channels`, space-separated.
    </Tip>
  </Step>

  <Step title="Push a message in">
    Open the fakechat UI at [http://localhost:8787](http://localhost:8787) and type a message:

    ```text theme={null}
    what's in my working directory?
    ```

    The message arrives in your Claude Code session. The terminal shows it as an inbound channel line like `← fakechat · web: what's in my working directory?`, while the model receives it as a `<channel source="plugin:fakechat:fakechat">` event, using the plugin's scoped server name. Claude reads it, does the work, and calls fakechat's `reply` tool. If Claude Code asks for permission for the first reply, approve it. The answer shows up in the chat UI.
  </Step>
</Steps>

If Claude hits a permission prompt while you're away from the terminal, the session pauses until you respond. Channel servers that declare the [permission relay capability](/docs/en/channels-reference#relay-permission-prompts) can forward these prompts to you so you can approve or deny remotely. For unattended use, [`--dangerously-skip-permissions`](/docs/en/permission-modes#skip-all-checks-with-bypasspermissions-mode) bypasses most prompts, but only use it in environments you trust. Even then, the [actions no mode auto-approves](/docs/en/permission-modes#actions-no-mode-auto-approves) still apply.

When you run channels in non-interactive mode with `-p`, tools that need terminal input, such as multiple-choice questions and plan mode approval, are disabled so the session never stalls waiting for input.

## Security

Every approved channel plugin maintains a sender allowlist: only IDs you've added can push messages, and everyone else is silently dropped.

Telegram and Discord bootstrap the list by pairing:

1. Find your bot in Telegram or Discord and send it any message
2. The bot replies with a pairing code
3. In your Claude Code session, approve the code when prompted
4. Your sender ID is added to the allowlist

iMessage works differently: texting yourself bypasses the gate automatically, and you add other contacts by handle with `/imessage:access allow`.

On top of that, you control which servers are enabled each session with `--channels`, and your organization controls availability with [`channelsEnabled`](#enterprise-controls) on claude.ai Team and Enterprise plans and on Console organizations that deploy managed settings.

Being in `.mcp.json` isn't enough to push messages: a server also has to be named in `--channels`.

The allowlist also gates [permission relay](/docs/en/channels-reference#relay-permission-prompts) if the channel declares it. Anyone who can reply through the channel can approve or deny tool use in your session, so only allowlist senders you trust with that authority.

## Enterprise controls

Admins control availability through two [managed settings](/docs/en/settings) that users cannot override. The default depends on how you authenticate:

* **claude.ai Team and Enterprise**: channels are blocked until an Owner [enables them](#enable-channels-for-your-organization).
* **Anthropic Console with API key authentication**: channels are permitted by default. You only need this setting if your organization deploys managed settings.

In all cases, no channel runs until a user opts it in for the session with `--channels`.

| Setting                 | Purpose                                                                                                                                                                                                              | When not configured                                                                                                                                                                    |
| :---------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `channelsEnabled`       | Master switch. Must be `true` for any channel to deliver messages. Blocks all channels including the development flag when off. See [Enable channels for your organization](#enable-channels-for-your-organization). | claude.ai Team and Enterprise: channels blocked. Console: channels allowed unless your organization deploys managed settings, in which case channels are blocked until this key is set |
| `allowedChannelPlugins` | Which plugins can register once channels are enabled. Replaces the Anthropic-maintained list when set.                                                                                                               | Anthropic default list applies                                                                                                                                                         |

Pro and Max users without an organization skip these checks entirely: channels are available and users opt in per session with `--channels`.

### Enable channels for your organization

Enable channels for your organization from [**claude.ai → Admin settings → Claude Code → Channels**](https://claude.ai/admin-settings/claude-code), which requires the Owner role, or by setting `channelsEnabled` to `true` in managed settings.

Once enabled, users in your organization can use `--channels` to opt channel servers into individual sessions. If the setting is disabled or unset, the MCP server still connects and its tools work, but channel messages won't arrive. A startup warning tells the user to have an admin enable the setting.

### Restrict which channel plugins can run

By default, any plugin on the Anthropic-maintained allowlist can register as a channel. Admins on Team and Enterprise plans can replace that allowlist with their own by setting `allowedChannelPlugins` in managed settings. Use this to restrict which official plugins are allowed, approve channels from your own internal marketplace, or both. Each entry names a plugin and the marketplace it comes from:

```json theme={null}
{
  "channelsEnabled": true,
  "allowedChannelPlugins": [
    { "marketplace": "claude-plugins-official", "plugin": "telegram" },
    { "marketplace": "claude-plugins-official", "plugin": "discord" },
    { "marketplace": "acme-corp-plugins", "plugin": "internal-alerts" }
  ]
}
```

If you set an empty array, you block all channel plugins from the allowlist, but `--dangerously-load-development-channels` can still bypass that block for local testing. To block channels entirely including the development flag, leave `channelsEnabled` unset instead.

This setting requires `channelsEnabled: true`. If a user passes a plugin to `--channels` that isn't on your list, Claude Code starts normally but the channel doesn't register, and the startup notice explains that the plugin isn't on the organization's approved list. If you set `MCP_PROTOCOL_NEGOTIATION` to `auto` on the v2 MCP client runtime, a channel can also fail to register because Claude Code [doesn't register a channel server that negotiates protocol revision 2026-07-28](/docs/en/mcp#push-messages-with-channels).

## Research preview

Channels are a research preview feature. Availability is rolling out gradually, and the `--channels` flag syntax and protocol contract may change based on feedback.

Neither `--channels` nor `--dangerously-load-development-channels` appears in `claude --help` while the feature is in preview. The flags work even though they aren't listed.

During the preview, `--channels` only accepts plugins from an Anthropic-maintained allowlist, or from your organization's allowlist if an admin has set [`allowedChannelPlugins`](#restrict-which-channel-plugins-can-run). The channel plugins in [claude-plugins-official](https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins) are the default approved set. If you pass something that isn't on the effective allowlist, Claude Code starts normally but the channel doesn't register, and the startup notice tells you why.

To test a channel you're building, use `--dangerously-load-development-channels`. See [Test during the research preview](/docs/en/channels-reference#test-during-the-research-preview) for information about testing custom channels that you build.

Report issues or feedback on the [Claude Code GitHub repository](https://github.com/anthropics/claude-code/issues).

## How channels compare

Several Claude Code features connect to systems outside the terminal, each suited to a different kind of work:

| Feature                                              | What it does                                                          | Good for                                                  |
| ---------------------------------------------------- | --------------------------------------------------------------------- | --------------------------------------------------------- |
| [Claude Code on the web](/docs/en/claude-code-on-the-web) | Runs tasks in a fresh cloud sandbox, cloned from GitHub               | Delegating self-contained async work you check on later   |
| [Claude in Slack](/docs/en/slack)                         | Spawns a web session from an `@Claude` mention in a channel or thread | Starting tasks directly from team conversation context    |
| Standard [MCP server](/docs/en/mcp)                       | Claude queries it during a task; nothing is pushed to the session     | Giving Claude on-demand access to read or query a system  |
| [Remote Control](/docs/en/remote-control)                 | You drive your local session from claude.ai or the Claude mobile app  | Steering an in-progress session while away from your desk |

Channels fill the gap in that list by pushing events from non-Claude sources into your already-running local session.

* **Chat bridge**: ask Claude something from your phone via Telegram, Discord, or iMessage, and the answer comes back in the same chat while the work runs on your machine against your real files.
* **[Webhook receiver](/docs/en/channels-reference#example-build-a-webhook-receiver)**: a webhook from CI, your error tracker, a deploy pipeline, or other external service arrives where Claude already has your files open and remembers what you were debugging.

## Opening Agent View

```bash
claude agents
```

Optional flags:
- `--cwd <path>` - Scope to sessions started under that directory
- `--model <name>` - Set dispatch model default
- `--permission-mode <mode>` - Set permission mode for dispatched sessions
- `--effort <level>` - Set effort level (includes `ultracode`)
- `--agent <name>` - Set default subagent
- `--settings <file-or-json>` - Override settings
- `--add-dir <path>` - Grant file access to additional directory
- `--plugin-dir <path>` - Load a plugin
- `--mcp-config <file-or-json>` - Load MCP servers
- `--json` - Print sessions as JSON and exit
- `--all` - With `--json`, include completed sessions
- `--dangerously-skip-permissions` - Start in bypassPermissions mode
- `--allow-dangerously-skip-permissions` - Make bypassPermissions available in Shift+Tab cycle
- `--restricted` - Start every dispatched session in restricted mode

## Dispatching Sessions

### From Agent View

Type a prompt in the dispatch input and press `Enter`:

```
Type your task and press Enter to dispatch
```

**Prompt prefixes and mentions:**
- `<agent-name> <prompt>` - Run custom subagent as main agent
- `@<agent-name>` - Mention subagent anywhere to run it
- `@<repo>` - Mention repository to run session there
- `/<command>` - Suggest skills and commands
- `! <command>` - Run shell command as background job (not a Claude session)
- `#<number>` or PR/MR URL - Select existing session working on that PR/MR

**Session naming:** Sessions are auto-named by Haiku model; rename with `Ctrl+R`.

### From Shell

```bash
# Background session with prompt
claude --bg "investigate the flaky test"

# With session name
claude --bg --name "flaky-test-fix" "investigate the flaky test"

# With specific subagent
claude --agent code-reviewer --bg "address review comments on PR 1234"

# With model override
claude --bg --model opus "refactor auth module"

# Run shell command as background job
claude --bg --exec 'pytest -x'
```

### From Inside a Session

```bash
/background          # Move conversation to background, free terminal
/bg <prompt>         # Background and send follow-up prompt
/fork                # Copy conversation to new background session
/fork <prompt>       # Fork with follow-up prompt
```

## Session Management UI

### Reading Session State

**Icon colors/animations:**
- Animated icon → Working (Claude actively running tools/generating)
- Yellow icon → Needs input (waiting for permission, answer, or prompt)
- Dimmed icon → Idle (ready for next prompt)
- Green icon → Completed successfully
- Red icon → Failed with error
- Grey icon → Stopped (Ctrl+X, `claude stop`, or ended process)

**Icon shapes:**
- `✻` or animated `✽` → Process is alive
- `∙` → Process exited; conversation saved on disk
- `✢` → `/loop` session sleeping between iterations

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `↑` / `↓` | Move between rows |
| `Enter` | Attach to selected session or dispatch if text in input |
| `Space` | Open/close peek panel |
| `→` | Attach to session |
| `←` | (In session) Background and open agent view |
| `Ctrl+S` | Switch grouping (state vs directory) |
| `Ctrl+T` | Pin/unpin session (keep process running while idle) |
| `Ctrl+R` | Rename session |
| `Ctrl+X` | Stop session; press again within 2 sec to delete |
| `Shift+↑` / `Shift+↓` | Reorder session |
| `Ctrl+G` | Open dispatch prompt in `$VISUAL`/`$EDITOR` |
| `Ctrl+J` | Insert newline in dispatch input |
| `Shift+Enter` | Insert newline in dispatch input |
| `Ctrl+Enter` | Dispatch and attach immediately |
| `Tab` | Browse subagents or apply suggestion |
| `Alt+1`..`Alt+9` | Attach to sessions 1–9 in directory |
| `Esc` | Close peek panel, clear input, or exit |
| `Ctrl+C` | Clear input; press twice to exit |
| `?` | Show all shortcuts |

### Peek Panel

Press `Space` on selected row to see:
- Session waiting on you: exact question above reply input
- Finished session: its result
- Working session: full status sentence

**Reply input:**
- Type reply and press `Enter` to send
- With numbered choices, press number key to select
- `Tab` to fill with suggested reply (edit before sending)
- Prefix with `!` to send Bash command
- `↑`/`↓` to peek adjacent sessions
- `→` to attach

### Attaching to Sessions

Press `Enter` or `→` to enter full interactive session. While attached:
- All normal commands and shortcuts work
- Session renders in fullscreen mode (no scrollback)
- `/install-github-app` and `/mcp settings` work (need terminal)
- Scroll with `PgUp`, `PgDn`, or mouse wheel
- Press `Ctrl+O` for transcript mode

**Detaching:**
- Press `←` on empty prompt to background and return to agent view
- `/exit` to detach and return to agent view
- `Ctrl+Z` to detach and return to where you started
- `Ctrl+C` twice to detach (on empty prompt)
- `/stop` to end the session

### Filtering Sessions

Type in dispatch input to filter instead of dispatch:

```
a:<name>              # Sessions running named agent
s:<state>             # Sessions in given state (e.g., s:working, s:blocked)
#<number>             # Session working on PR/MR number
<url>                 # Session whose first prompt contained that URL
```

## File Isolation with Worktrees

Background sessions automatically move into git worktrees under `.claude/worktrees/` before editing files, isolating changes from parallel sessions and your working copy.

**Worktree is skipped when:**
- Session already inside a linked git worktree
- File being edited is inside a linked worktree
- Working directory isn't a git repo and no `WorktreeCreate` hook configured
- Write is outside working directory

**Disable worktree isolation** (edit working copy directly):

Add to `.claude/settings.json`:
```json
{
  "worktree": {
    "bgIsolation": "none"
  }
}
```

**Git handling:** Claude commits without asking and pushes when remote exists. Never force-pushes or merges to main/master. Respects your git instructions if specified.

## Shell Commands

### Background Session Management

```bash
claude agents                    # Open agent view
claude agents --cwd ~/path      # Scope to directory
claude agents --json            # Print sessions as JSON
claude attach <id>              # Open session in terminal
claude logs <id>                # Print recent output
claude stop <id>                # Stop session (also: claude kill)
claude respawn <id>             # Restart session
claude respawn --all            # Restart all running sessions
claude rm <id>                  # Remove from list and worktree
claude daemon status            # Show supervisor state/version
claude daemon stop --any        # Stop supervisor and sessions
claude daemon stop --any --keep-workers  # Stop supervisor, keep sessions running
```

### JSON Output

```bash
claude agents --json [--all] [--cwd <path>]
```

Fields per session:
- `cwd`, `kind`, `startedAt` - Always present
- `id`, `state` - Background sessions only
- `pid`, `status` - While process alive
- `waitingFor` - When status is "waiting"
- `sessionId`, `name` - When set

## Settings and Configuration

**Environment variables:**
- `CLAUDE_CONFIG_DIR` - Override config directory (default: `~/.claude`)
- `CLAUDE_DISABLE_AGENT_VIEW` - Disable agent view entirely
- `CLAUDE_CODE_DISABLE_ADOPT=1` - Ask before carrying over in-flight work
- `CLAUDE_CODE_DISABLE_BG_EXIT_HANDOFF=1` - Stop in-flight work with process
- `FORCE_HYPERLINK=0` - Disable PR/MR hyperlinks

**Settings keys** (`.claude/settings.json`):
- `disableAgentView: true` - Turn off agent view
- `worktree.bgIsolation: "none"` - Disable worktree isolation
- `leftArrowOpensAgents: false` - Disable `←` to open agent view

## Troubleshooting

**Sessions show as failed after shutdown:**
- Within 48 hours: attach to restart from saved state
- Past 48 hours: shows "ended while the background service was off"; press Enter twice to resume
- Use `claude respawn <id>` to run original prompt again

**Agent view won't open:**
```bash
claude update  # Install latest version
```

**Background service not responding:**
```bash
claude daemon stop --any --keep-workers
```

**Authentication issues:**
- Ensure `/login` completed or `ANTHROPIC_API_KEY` is set
- Stop supervisor to reconnect with fresh credentials: `claude daemon stop --any --keep-workers`

**macOS file access:**
- Grant System Settings > Privacy & Security > Files and Folders access for Desktop, Documents, Downloads
- Grant Local Network permission for LAN host access (macOS 15+)


## https://github.com/search?q=repo%3Amanaflow-ai%2Fmanaflow+crown&type=code

Based on the provided content, I cannot determine whether the manaflow repository contains a "crown" feature. The page shows a GitHub code search results page for "repo:manaflow-ai/manaflow crown," but the actual search results are not displayed. The page only shows a login prompt stating "Sign in to search code on GitHub Before you can access our code search functionality please sign in or create a free account."

Without access to the actual search results or repository code, I cannot summarize any matches about a crown feature for selecting optimal agent runs.


## What It Configures

According to the guide, this file handles **automatic task assignment for parallel agents**. The configuration contains two key sections:

### Windows Setup (`setup-worktree-windows`)
PowerShell commands that:
- Create a coordination directory (`.coord-*`) to track agent sessions
- Implement a task-claiming mechanism using file locks
- Assign each agent a unique number (1-8) by creating `task-*.json` claim files
- Write the assigned task number to `.agent-id`
- Clean up stale coordination directories older than 1 hour

### Unix Setup (`setup-worktree-unix`)
Bash equivalents performing identical logic:
- Session management via timestamped directories
- Atomic task claiming using `mkdir` as a lock mechanism
- Assignment of numbers 1-8 to separate agents
- Output of agent ID to `.agent-id` for agent reference

## Core Architecture

**Agent Spawning & Isolation:**
When creating an agent, the system performs three key operations: creates a dedicated git worktree on branch `agent/<id>`, launches a tmux session running Claude Code in that isolated environment, and monitors agent state throughout execution. Each agent operates within `.ittybitty/agents/<id>/` to maintain separation from the primary repository.

**Agent Types:**
The framework distinguishes between two hierarchies. Manager agents coordinate work and can spawn additional agents, while worker agents execute specific tasks and cannot create new agents.

## Essential Commands

| Command | Function |
|---------|----------|
| `ib new-agent "prompt"` | Spawn a new manager agent |
| `ib new --worker "task"` | Create a task-focused worker agent |
| `ib watch` | Interactive dashboard monitoring all agents |
| `ib list` | Display agent statuses via CLI |
| `ib send <id> "message"` | Deliver guidance to running agents |
| `ib diff <id>` | Review agent's code changes |
| `ib merge <id>` | Integrate agent's branch into primary branch |
| `ib kill <id>` | Terminate and archive agent work |

## Safety Architecture

**Permission Control:**
The framework operates safely without requiring "yolo" mode. Tools default to denied status unless explicitly allowed. Mandatory tools for core functionality remain enabled (git operations, file access, communication tools).

**Isolation Mechanisms:**
"Agents can only access files in their own worktree" via safety hooks. Path violation errors indicate expected behavior—agents cannot escape their designated environment. Emergency control exists through `ib nuke`, which immediately terminates all agents and archives complete session histories for review.

## Compare scheduling options

Claude Code offers three ways to schedule recurring or one-off work:

|                            | [Cloud](/docs/en/routines)               | [Desktop](/docs/en/desktop-scheduled-tasks) | [`/loop`](/docs/en/scheduled-tasks)      |
| :------------------------- | :---------------------------------- | :------------------------------------- | :---------------------------------- |
| Runs on                    | Cloud, Anthropic-managed by default | Your machine                           | Your machine                        |
| Requires machine on        | No                                  | Yes                                    | Yes                                 |
| Requires open session      | No                                  | No                                     | Yes                                 |
| Persistent across restarts | Yes                                 | Yes                                    | Restored on `--resume` if unexpired |
| Access to local files      | No (fresh clone)                    | Yes                                    | Yes                                 |
| MCP servers                | Connectors configured per task      | [Config files](/docs/en/mcp) and connectors | Inherits from session               |
| Permission prompts         | No (runs autonomously)              | Configurable per task                  | Inherits from session               |
| Customizable schedule      | Via `/schedule` in the CLI          | Yes                                    | Yes                                 |
| Minimum interval           | 1 hour                              | 1 minute                               | 1 minute                            |

<Tip>
  Use **cloud tasks** for work that should run reliably without your machine. Use **Desktop tasks** when you need access to local files and tools. Use **`/loop`** for quick polling during a session.
</Tip>

## Run a prompt repeatedly with /loop

The `/loop` [bundled skill](/docs/en/commands) is the quickest way to run a prompt on repeat while the session stays open. Both the interval and the prompt are optional, and what you provide determines how the loop behaves.

| What you provide          | Example                     | What happens                                                                                                  |
| :------------------------ | :-------------------------- | :------------------------------------------------------------------------------------------------------------ |
| Interval and prompt       | `/loop 5m check the deploy` | Your prompt runs on a [fixed schedule](#run-on-a-fixed-interval)                                              |
| Prompt only               | `/loop check the deploy`    | Your prompt runs at an [interval Claude chooses](#let-claude-choose-the-interval) each iteration              |
| Interval only, or nothing | `/loop`                     | The [built-in maintenance prompt](#run-the-built-in-maintenance-prompt) runs, or your `loop.md` if one exists |

You can also pass a skill as the prompt, for example `/loop 20m /review-pr 1234`, to re-run that skill each iteration. A scheduled fire only runs skills that Claude is [allowed to invoke on its own](/docs/en/skills#control-who-invokes-a-skill). The following reach Claude as plain text instead of executing:

* Built-in commands such as `/permissions`, `/model`, or `/clear`
* Skills marked [`disable-model-invocation: true`](/docs/en/skills#frontmatter-reference), including the bundled `/verify` skill
* Skills withheld from Claude by a [`skillOverrides`](/docs/en/skills#override-skill-visibility-from-settings) setting or a `Skill` [deny rule](/docs/en/skills#restrict-claude’s-skill-access)
* [MCP prompts](/docs/en/mcp#use-mcp-prompts-as-commands) such as `/mcp__github__list_prs`

### Run on a fixed interval

When you supply an interval, Claude converts it to a cron expression, schedules the job, and confirms the cadence and job ID.

```text theme={null}
/loop 5m check if the deployment finished and tell me what happened
```

The interval can lead the prompt as a bare token like `30m`, or trail it as a clause like `every 2 hours`. Supported units are `s` for seconds, `m` for minutes, `h` for hours, and `d` for days.

Seconds are rounded up to the nearest minute since cron has one-minute granularity. Intervals that don't map to a clean cron step, such as `7m` or `90m`, are rounded to the nearest interval that does and Claude tells you what it picked.

### Let Claude choose the interval

When you omit the interval, Claude chooses one dynamically instead of running on a fixed cron schedule. After each iteration it picks a delay between one minute and one hour based on what it observed: short waits while a build is finishing or a PR is active, longer waits when nothing is pending. The chosen delay and the reason for it are printed at the end of each iteration.

The example below checks CI and review comments, with Claude waiting longer between iterations once the PR goes quiet:

```text theme={null}
/loop check whether CI passed and address any review comments
```

In a session where the [Monitor tool is available](/docs/en/tools-reference#monitor-tool), Claude may use it directly when you ask for a dynamic `/loop` schedule. Monitor runs a background script and streams each output line back, which avoids polling altogether and is often more token-efficient and responsive than re-running a prompt on an interval.

A dynamically scheduled loop appears in your [scheduled task list](#manage-scheduled-tasks) like any other task, so you can list or cancel it the same way. The [jitter rules](#jitter) don't apply to it, but the [seven-day expiry](#seven-day-expiry) does.

<span id="loop-provider-differences" />

<Note>
  Dynamically chosen intervals and the [built-in maintenance prompt](#run-the-built-in-maintenance-prompt) work on every provider, and with [feature-flag fetching](/docs/en/env-vars#features-that-need-feature-flag-fetching) turned off. On Amazon Bedrock, Claude Platform on AWS, Google Cloud's Agent Platform, and Microsoft Foundry, or with fetching turned off, both require Claude Code v2.1.248 or later. In those cases, on earlier versions, a prompt with no interval runs on a fixed 10-minute schedule, and a `/loop` with no prompt prints the usage message.
</Note>

### Run the built-in maintenance prompt

When you omit the prompt, Claude uses a built-in maintenance prompt instead of one you supply. On each iteration it works through the following, in order:

* continue any unfinished work from the conversation
* tend to the current branch's pull request: review comments, failed CI runs, merge conflicts
* run cleanup passes such as bug hunts or simplification when nothing else is pending

Claude does not start new initiatives outside that scope, and irreversible actions such as pushing or deleting only proceed when they continue something the transcript already authorized.

```text theme={null}
/loop
```

A bare `/loop` runs this prompt at a [dynamically chosen interval](#let-claude-choose-the-interval). Add an interval, for example `/loop 15m`, to run it on a fixed schedule instead. To replace the built-in prompt with your own default, see [Customize the default prompt with loop.md](#customize-the-default-prompt-with-loop-md).

### Customize the default prompt with loop.md

Create a `loop.md` file to replace the [built-in maintenance prompt](#run-the-built-in-maintenance-prompt) with your own instructions. It defines a single default prompt for bare `/loop`, not a list of separate scheduled tasks, and Claude Code ignores it whenever you supply a prompt on the command line. To schedule additional prompts alongside it, use `/loop <prompt>` or [ask Claude directly](#manage-scheduled-tasks).

Claude looks for the file in two locations and uses the first one it finds.

| Path                | Scope                                                            |
| :------------------ | :--------------------------------------------------------------- |
| `.claude/loop.md`   | Project-level. Takes precedence when both files exist.           |
| `~/.claude/loop.md` | User-level. Applies in any project that does not define its own. |

The file is plain Markdown with no required structure. Write it as if you were typing the `/loop` prompt directly. The following example keeps a release branch healthy:

```markdown title=".claude/loop.md" theme={null}
Check the `release/next` PR. If CI is red, pull the failing job log,
diagnose, and push a minimal fix. If new review comments have arrived,
address each one and resolve the thread. If everything is green and
quiet, say so in one line.
```

Edits to `loop.md` take effect on the next iteration, so you can refine the instructions while a loop is running. When no `loop.md` exists in either location, the loop falls back to the built-in maintenance prompt. Keep the file concise: content beyond 25,000 bytes is truncated.

### Stop a loop

To stop a [self-paced `/loop`](#let-claude-choose-the-interval) while it is waiting for the next iteration, press `Esc`. This clears the pending wakeup so the loop does not fire again. Tasks you scheduled by [asking Claude directly](#manage-scheduled-tasks) are not affected by `Esc` and stay in place until you delete them.

In [self-paced mode](#let-claude-choose-the-interval), Claude can also end the loop on its own once the task is complete. Claude calls the [`ScheduleWakeup` tool](/docs/en/tools-reference) with `stop: true`, which cancels the pending wakeup immediately. If an iteration ends without either rescheduling or stopping, Claude Code schedules one fallback wakeup about 20 minutes later and ends the loop when that iteration doesn't reschedule either.

Loops on a fixed interval keep running until you [cancel them like any other scheduled task](#manage-scheduled-tasks) or [seven days elapse](#seven-day-expiry).

## Set a one-time reminder

For one-shot reminders, describe what you want in natural language instead of using `/loop`. Claude schedules a single-fire task that deletes itself after running.

```text theme={null}
remind me at 3pm to push the release branch
```

```text theme={null}
in 45 minutes, check whether the integration tests passed
```

Claude pins the fire time to a specific minute and hour using a cron expression and confirms when it will fire.

## Manage scheduled tasks

Ask Claude in natural language to list or cancel tasks, or reference the underlying tools directly.

```text theme={null}
what scheduled tasks do I have?
```

```text theme={null}
cancel the deploy check job
```

Under the hood, Claude uses these tools:

| Tool         | Purpose                                                                                                         |
| :----------- | :-------------------------------------------------------------------------------------------------------------- |
| `CronCreate` | Schedule a new task. Accepts a 5-field cron expression, the prompt to run, and whether it recurs or fires once. |
| `CronList`   | List all scheduled tasks with their IDs, schedules, and prompts.                                                |
| `CronDelete` | Cancel a task by ID.                                                                                            |

Each scheduled task has an 8-character ID you can pass to `CronDelete`. A session can hold up to 50 scheduled tasks at once.

## How scheduled tasks run

The scheduler checks every second for due tasks and enqueues them at low priority. A scheduled prompt fires between your turns, not while Claude is mid-response. If Claude is busy when a task comes due, the prompt waits until the current turn ends.

All times are interpreted in your local timezone. A cron expression like `0 9 * * *` means 9am wherever you're running Claude Code, not UTC.

### Jitter

To avoid every session hitting the API at the same wall-clock moment, the scheduler adds a deterministic offset to fire times:

* Recurring tasks fire up to 30 minutes after the scheduled time (or up to half the interval, for tasks that run more often than hourly). An hourly job scheduled for `:00` may fire anywhere up to `:30`.
* One-shot tasks scheduled for the top or bottom of the hour fire up to 90 seconds early.

The offset is derived from the task ID, so the same task always gets the same offset. If exact timing matters, pick a minute that is not `:00` or `:30`, for example `3 9 * * *` instead of `0 9 * * *`, and the one-shot jitter will not apply.

### Seven-day expiry

Recurring tasks automatically expire 7 days after creation. The task fires one final time, then deletes itself. This bounds how long a forgotten loop can run. If you need a recurring task to last longer, cancel and recreate it before it expires, or use [Routines](/docs/en/routines) or [Desktop scheduled tasks](/docs/en/desktop-scheduled-tasks) for durable scheduling.

## Cron expression reference

`CronCreate` accepts standard 5-field cron expressions: `minute hour day-of-month month day-of-week`. All fields support wildcards (`*`), single values (`5`), steps (`*/15`), ranges (`1-5`), and comma-separated lists (`1,15,30`).

| Example        | Meaning                      |
| :------------- | :--------------------------- |
| `*/5 * * * *`  | Every 5 minutes              |
| `0 * * * *`    | Every hour on the hour       |
| `7 * * * *`    | Every hour at 7 minutes past |
| `0 9 * * *`    | Every day at 9am local       |
| `0 9 * * 1-5`  | Weekdays at 9am local        |
| `30 14 15 3 *` | March 15 at 2:30pm local     |

Day-of-week uses `0` or `7` for Sunday through `6` for Saturday. Extended syntax like `L`, `W`, `?`, and name aliases such as `MON` or `JAN` is not supported.

When both day-of-month and day-of-week are constrained, a date matches if either field matches. This follows standard vixie-cron semantics.

## Limitations

Session-scoped scheduling has inherent constraints:

* Tasks only fire while Claude Code is running and idle. Closing the terminal or letting the session exit stops them firing. [Backgrounding the session](/docs/en/agent-view#from-inside-a-session) carries `/loop` tasks over to a background session, which keeps running without a terminal.
* No catch-up for missed fires. If a task's scheduled time passes while Claude is busy on a long-running request, it fires once when Claude becomes idle, not once per missed interval.
* Starting a fresh conversation clears all session-scoped tasks. Resuming with `claude --resume` or `claude --continue` restores recurring tasks that have not [expired](#seven-day-expiry) and one-shot tasks whose scheduled time has not yet passed. Background Bash and monitor tasks are never restored on resume.
* With [feature-flag fetching off](/docs/en/env-vars#features-that-need-feature-flag-fetching), Claude Code stores a task you asked to keep across sessions in the project's `.claude` directory. When that directory or the task file in it is a symlink, Claude Code returns an error instead of scheduling the task.

For cron-driven automation that needs to run unattended:

* [Routines](/docs/en/routines): run in the cloud on a schedule, via API call, or on GitHub events
* [GitHub Actions](/docs/en/github-actions): use a `schedule` trigger in CI
* [Desktop scheduled tasks](/docs/en/desktop-scheduled-tasks): run locally on your machine



## All Hook Events

| Event | When it fires | Key input fields | Exit code 2 effect |
|-------|---------------|------------------|-------------------|
| **SessionStart** | When a session begins or resumes | `session_id`, `cwd`, `hook_event_name` | N/A (can't block) |
| **SessionEnd** | When a session terminates | `session_id`, `cwd`, `transcript_path` | N/A (can't block) |
| **UserPromptSubmit** | Before Claude processes a user prompt | `session_id`, `cwd`, `prompt_id`, `permission_mode`, `tool_input` | **Blocks prompt**, erases input |
| **UserPromptExpansion** | When a user-typed command expands into a prompt | `session_id`, `cwd`, `prompt_id` | **Blocks expansion** |
| **PreToolUse** | Before a tool call executes | `session_id`, `cwd`, `tool_name`, `tool_input`, `tool_use_id`, `effort` | **Blocks tool call** |
| **PostToolUse** | After a tool call succeeds | `session_id`, `cwd`, `tool_name`, `tool_input`, `tool_result`, `tool_use_id` | Shows stderr to Claude (tool already ran) |
| **PostToolUseFailure** | After a tool call fails | `session_id`, `cwd`, `tool_name`, `tool_input`, `error` | Shows stderr to Claude (tool already failed) |
| **PostToolBatch** | After a full batch of parallel tool calls resolves | `session_id`, `cwd`, `tool_calls` (array) | **Stops agentic loop** before next model call |
| **PermissionRequest** | When a tool call needs a permission decision | `session_id`, `cwd`, `tool_name`, `tool_input`, `permission_mode` | Exit 2 ignored; use `decision` object instead |
| **PermissionDenied** | When auto mode denies a tool call | `session_id`, `cwd`, `tool_name`, `tool_input`, `denial_reason` | Ignored; output discarded |
| **Stop** | When Claude finishes responding | `session_id`, `cwd`, `prompt_id`, `last_assistant_message`, `effort` | **Prevents stop**, continues conversation |
| **StopFailure** | When turn ends due to API error | `session_id`, `cwd`, `error_type`, `error_message` | Output ignored (except `terminalSequence`) |
| **SubagentStart** | When a subagent is spawned | `session_id`, `cwd`, `agent_id`, `agent_type` | N/A (can't block) |
| **SubagentStop** | When a subagent finishes | `session_id`, `cwd`, `agent_id`, `agent_type`, `last_assistant_message` | **Prevents subagent stop** |
| **TaskCreated** | When a task is being created via `TaskCreate` | `session_id`, `cwd`, `task_input` | **Rolls back task creation** |
| **TaskCompleted** | When a task is marked as completed | `session_id`, `cwd`, `task_id` | **Prevents completion** |
| **TeammateIdle** | When an agent team teammate is about to go idle | `session_id`, `cwd`, `agent_type` | **Prevents idle**, teammate continues |
| **Notification** | When Claude Code sends a notification | `session_id`, `cwd`, `notification_type` | N/A (can't block) |
| **MessageDisplay** | While assistant message text is displayed | `session_id`, `cwd`, `prompt_id`, `message_text` | N/A (can't block) |
| **PreToolUse** → **PermissionRequest** | During permission request flow | `session_id`, `cwd`, `tool_name`, `tool_input` | N/A (standard flow) |
| **ConfigChange** | When a configuration file changes during session | `session_id`, `cwd`, `config_source` | **Blocks config change** (except `policy_settings`) |
| **CwdChanged** | When working directory changes (e.g., `cd` command) | `session_id`, `old_cwd`, `new_cwd` | N/A (can't block) |
| **DirectoryAdded** | When a working directory is added mid-session | `session_id`, `cwd`, `directory_path`, `add_method` | N/A (can't block) |
| **FileChanged** | When a watched file changes on disk | `session_id`, `cwd`, `file_path` | N/A (can't block) |
| **WorktreeCreate** | When a worktree is being created | `session_id`, `cwd`, `worktree_path` | **Aborts worktree creation** (any nonzero exit) |
| **WorktreeRemove** | When a worktree is being removed | `session_id`, `cwd`, `worktree_path` | N/A (can't block) |
| **PreCompact** | Before context compaction | `session_id`, `cwd`, `compaction_trigger` | N/A (can't block) |
| **PostCompact** | After context compaction completes | `session_id`, `cwd`, `compaction_trigger` | N/A (can't block) |
| **PreModelSwitch** | Before model switch (requested by user/client) | `session_id`, `cwd`, `from_model`, `to_model` | **Blocks model switch** |
| **PostModelSwitch** | After session's model changes | `session_id`, `cwd`, `from_model`, `to_model` | N/A (can't block) |
| **InstructionsLoaded** | When CLAUDE.md or .claude/rules/*.md is loaded | `session_id`, `cwd`, `file_path`, `load_reason` | N/A (can't block) |
| **Setup** | When starting with `--init-only`, `--init`, or `--maintenance` | `cwd`, `setup_trigger` | N/A (can't block) |
| **Elicitation** | When MCP server requests user input during tool call | `session_id`, `cwd`, `mcp_server`, `elicitation_prompt` | N/A (skipped on this event) |
| **ElicitationResult** | After user responds to MCP elicitation | `session_id`, `cwd`, `mcp_server`, `user_response` | N/A (skipped on this event) |

---

## Common Input Fields (All Events)

Every hook receives these JSON fields on stdin (command hooks) or POST body (HTTP hooks):

```json
{
  "session_id": "abc123",              // Current session identifier
  "prompt_id": "550e8400-e29b-41d4-a716-446655440000",  // UUID for current prompt
  "transcript_path": "/path/to/transcript.jsonl",  // Path to conversation JSON
  "cwd": "/home/user/my-project",     // Current working directory
  "permission_mode": "default",        // "default"|"plan"|"acceptEdits"|"auto"|"dontAsk"|"bypassPermissions"
  "hook_event_name": "PreToolUse",     // Name of firing event
  "effort": { "level": "medium" },     // Effort level: "low"|"medium"|"high"|"xhigh"|"max"
  "agent_id": "subagent-123",          // (only in subagents) Unique subagent ID
  "agent_type": "code-reviewer"        // (only in subagents/--agent) Agent name
}
```

### When Present
- `prompt_id`: Absent until first user input; present on all subsequent events
- `effort`: Only on events within tool-use context (PreToolUse, PostToolUse, Stop, SubagentStop)
- `permission_mode`: Not all events receive this; check each event's schema
- `agent_id`, `agent_type`: Only when running inside a subagent or with `--agent`

---

## Available Environment Variables

Hook processes inherit the parent environment with these Claude Code-specific additions:

| Variable | Value | Notes |
|----------|-------|-------|
| `$CLAUDE_PROJECT_DIR` | Project root path | Where session started; stays put in worktrees |
| `$CLAUDE_PLUGIN_ROOT` | Plugin installation directory | For plugin-bundled scripts; changes on update |
| `$CLAUDE_PLUGIN_DATA` | Plugin persistent data directory | Survives plugin updates |
| `$CLAUDE_EFFORT` | Effort level string | `"low"`, `"medium"`, `"high"`, `"xhigh"`, `"max"` |
| `$CLAUDE_CODE_REMOTE` | `"true"` or unset | `"true"` in cloud/web environments |
| `$CLAUDE_CODE_BRIDGE_SESSION_ID` | Session ID | Set while Remote Control has active connection (v2.1.199+) |
| `$CLAUDE_PLUGIN_OPTION_<KEY>` | Option value | Read plugin user config (shell-form hooks only) |
| `$ANTHROPIC_MODEL` | Model name | Only if you set it in shell; doesn't auto-update on `/model` |

Claude Code **removes** these from all subprocesses: `OTEL_*` exporter variables.

When `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, Claude Code strips additional variables (configurable).

---

## Exit Code Behavior Summary

| Exit Code | Behavior | JSON parsed? |
|-----------|----------|--------------|
| **0** | Success; action proceeds. Reads JSON output and plain text. | Yes, if valid |
| **2** | **Blocking error**: prevents action on events that support it. Always blocks, even if JSON says `allow`. | Yes, if valid |
| **1, 3-255** | Non-blocking error (action proceeds). JSON decoded for decision fields if valid schema. | Yes, if valid |
| **Timeout** | Action proceeds on most events. Exception: `PreModelSwitch` blocks on timeout. | No |

---

## Hook Input/Output Examples

### Example: PreToolUse (Bash command)

**Input (stdin):**
```json
{
  "session_id": "abc123",
  "prompt_id": "550e8400-e29b-41d4-a716-446655440000",
  "transcript_path": "/home/user/.claude/projects/.../transcript.jsonl",
  "cwd": "/home/user/my-project",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test",
    "description": "Run test suite",
    "timeout": 120000,
    "run_in_background": false
  },
  "tool_use_id": "toolu_01ABC123...",
  "effort": { "level": "medium" }
}
```

**Output (stdout) to allow/deny:**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "npm test not allowed in this workspace"
  }
}
```

Exit code 2 to block regardless:
```bash
echo "Blocked: dangerous command detected" >&2
exit 2
```

### Example: PostToolUse (after Edit tool)

**Input (stdin):**
```json
{
  "session_id": "abc123",
  "cwd": "/home/user/my-project",
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "src/main.ts",
    "operation": "replace",
    "new_content": "..."
  },
  "tool_result": {
    "success": true,
    "message": "File updated successfully"
  }
}
```

**Output (stdout) to add context:**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "TypeScript file edited; linter should run next"
  }
}
```

---

## Common Hook Patterns

### Block destructive commands (exit code 2)

```bash
#!/bin/bash
input=$(cat)
command=$(jq -r '.tool_input.command' <<<"$input")

if [[ "$command" == rm\ -rf* ]]; then
  echo "Recursive rm blocked by policy" >&2
  exit 2
fi
exit 0
```

### Allow/deny via JSON decision

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Tool not approved for this project"
  }
}
```

Exit 0 to return structured decision (no code override needed).

### Run background validation

```json
{
  "type": "command",
  "if": "Write|Edit",
  "command": "/path/to/lint-check.sh",
  "async": true,
  "asyncRewake": true
}
```

Runs hook in background; wakes Claude if exit code 2.

### HTTP hook with authentication

```json
{
  "type": "http",
  "url": "https://policy-server.example.com/hooks/pre-tool-use",
  "headers": {
    "Authorization": "Bearer $MY_TOKEN",
    "X-Session": "${session_id}"
  },
  "allowedEnvVars": ["MY_TOKEN"],
  "timeout": 10
}
```

HTTP POST with JSON body; response uses same format as command stdout.

### MCP tool hook

```json
{
  "type": "mcp_tool",
  "server": "my_server",
  "tool": "security_scan",
  "input": { "file_path": "${tool_input.file_path}" }
}
```

Calls tool on connected MCP server; tool text output treated like stdout.

### Prompt-based decision hook

```json
{
  "type": "prompt",
  "prompt": "Is this Bash command safe to run? Command: $ARGUMENTS\n\nRespond with JSON: {\"decision\": \"allow\" or \"deny\"}",
  "model": "claude-opus-5",
  "timeout": 15
}
```

Sends hook input as `$ARGUMENTS` to Claude; model returns decision JSON.

---

## Key Takeaways

1. **Exit code 2** is the only code that blocks by itself; most other codes are non-blocking unless paired with valid JSON
2. **Common fields** (`session_id`, `cwd`, `transcript_path`, `permission_mode`, `effort`) appear in nearly all events
3. **Event-specific input** like `tool_name`, `tool_input`, `agent_type` varies per event
4. **JSON output** fields like `permissionDecision`, `additionalContext`, `systemMessage` control behavior per event
5. **Async hooks** run in background with optional wake-on-exit-2 (`asyncRewake`)
6. **MCP and HTTP hooks** follow the same decision schema as command hooks


## Core Commands

**Agent Prompt:**
Submits text to a recognized agent with encoded Enter. The command `"agent prompt"` honors bracketed-paste mode and can prompt an agent already working. If blocked, it returns `agent_blocked` without sending input.

**Agent Wait:**
Monitors agent lifecycle changes. The basic form is `"agent wait"` with optional `--until` flags specifying target states. Defaults to `idle`, `done`, or `blocked`.

**Pane Wait-Output:**
Polls terminal snapshots for text or regex matches. Uses `"pane wait-output"` with `--regex` for Rust regex syntax, matching line-by-line. Default source is `recent`.

**Pane Run:**
Executes shell commands in a terminal. The form `"pane run w1:p3 \"just test --watch\""` runs the command directly.

## Categories & Highlights

**Parallel Coding Agents — Terminal (TUI/CLI)**
- [Cyclops](https://github.com/cyclops-team/cyclops) - "Coordinates coding agents running in tmux through a durable mailbox"
- [herdr](https://github.com/herdrdev/herdr) - Background runtime with session persistence across reboots
- [repomon](https://github.com/AliHamzaAzam/repomon) - Fleet supervision across repositories in durable tmux
- [thurbox](https://github.com/Thurbeen/thurbox) - Remote SSH sessions with inter-session messaging

**Parallel Coding Agents — Desktop & Web**
- [Fletch](https://github.com/fwdai/fletch) - "Seals each agent in its own repo clone under Seatbelt or Docker"
- [intentic](https://github.com/intentic/intentic) - Persistent Docker sandbox per agent, outbound-only tunnel access
- [Zaivern Code](https://github.com/tacyan/zaivern-code) - Mobile control and line-level ownership tracking
- [Tempest](https://github.com/tempestai-dev/tempest) - Shared code-knowledge graph reducing token use

**Autonomous Loop Runners**
- [bernstein](https://github.com/sipyourdrink-ltd/bernstein) - "Keeps no model in the coordination loop"
- [ralphex](https://github.com/umputun/ralphex) - Multi-phase review with automatic commit/revert

**Multi-Agent Swarms**
- [gastown](https://github.com/gastownhall/gastown) - "Scales to 20-30 agents with coordinator, git-backed issue tracking"
- [loki-mode](https://github.com/asklokesh/loki-mode) - "PRD-to-deployed-product SDLC with 41 agents in 8 swarms"
- [Fusion](https://github.com/Runfusion/Fusion) - Hierarchical missions with plan-review-execute gates

**Autonomous Task Runners**
- [aeon](https://github.com/aeonfun/aeon) - GitHub Actions with quality scoring and reactive triggers
- [symphony](https://github.com/openai/symphony) - "Turns project work into isolated autonomous runs"

**Notable Infrastructure**
- [Crewplane](https://github.com/crewplaneai/crewplane) - "Explicit artifact handoffs keep execution inspectable on disk"
- [omnigent](https://github.com/omnigent-ai/omnigent) - Policy enforcement across swappable sandbox backends


## Project Status & Adoption

The project demonstrates significant real-world traction:
- **27,000+ stars** on GitHub
- **2,800+ forks**
- **177 watchers**
- Apache 2.0 license
- Active development with 44 commits on main branch

**Important caveat:** The documentation explicitly notes Symphony is "a low-key engineering preview for testing in trusted environments," indicating it remains experimental despite community interest.

The framework represents a meaningful evolution in AI-assisted development workflows, enabling autonomous task completion with human oversight at the management rather than execution level.


## Isolation Architecture

The system employs two sandboxing mechanisms:

**Seatbelt (Default):** "Each agent runs under a per-agent macOS `sandbox-exec` profile that denies writes outside its workspace." This requires no additional installation but provides write-only protection—agents retain read access and network connectivity as your user.

**Docker (Optional):** Containers isolate agents more thoroughly, restricting filesystem visibility to mounted directories. All harnesses except Antigravity support this engine, though network access remains open.

## Run Lifecycle and States

Symphony orchestrates coding-agent work through deterministic state transitions. A run progresses through these phases:

**Preparation**: `PreparingWorkspace` → `BuildingPrompt` → `LaunchingAgentProcess` → `InitializingSession`

**Execution**: `StreamingTurn` → `Finishing`

**Terminal outcomes**: `Succeeded`, `Failed`, `TimedOut`, `Stalled`, or `CanceledByReconciliation`

Issue orchestration uses separate claim states: `Unclaimed`, `Claimed`, `Running`, `RetryQueued`, and `Released`. The spec distinguishes these from tracker states like "Todo" or "In Progress."

## Task Entry and Polling

Tasks enter through tracker polling. The orchestrator:

1. Polls every `polling.interval_ms` (default 30 seconds)
2. Fetches issues in `active_states` using `fetch_issues_by_states()`
3. Filters by `tracker.required_labels`, adapter `dispatchable` flag, and concurrency limits
4. Sorts by priority, creation time, then identifier
5. Dispatches eligible issues while slots remain

The spec states: *"An issue is dispatch-eligible only if all are true: It has `id`, `identifier`, `title`, and `state`. Its state is in `active_states` and not in `terminal_states`."*

## Isolation Mechanisms

**Workspace Safety Invariants** (mandatory):

- *"Run the coding agent only in the per-issue workspace path"*
- *"Workspace path MUST stay inside workspace root"*
- *"Workspace key is sanitized"* using only `[A-Za-z0-9._-]`, with collision-resistant hashing for sanitization collisions

Workspaces persist across runs for reuse. Each workspace maps to one issue identifier and includes optional hooks: `after_create` (new workspace only), `before_run` (fatal if fails), `after_run` (logged if fails), and `before_remove`.

## Agent Execution and Reporting

The agent subprocess launches via `bash -lc <codex.command>` in the workspace directory. Session startup requires extracting `thread_id` and `turn_id`, emitting `session_id = "<thread_id>-<turn_id>"`.

**Emitted runtime events** include: `session_started`, `startup_failed`, `turn_completed`, `turn_failed`, `turn_cancelled`, `turn_input_required`, `approval_auto_approved`, and `unsupported_tool_call`.

The client streams app-server updates with token usage, rate limits, and turn status. Completion occurs via targeted-protocol success signal, failure signal, cancellation, `turn_timeout_ms` silence, or subprocess exit.

**Continuation handling**: Within one worker lifetime, the orchestrator may start multiple turns on the same live thread up to `agent.max_turns` (default 20). *"The first turn SHOULD use the full rendered task prompt. Continuation turns SHOULD send only continuation guidance to the existing thread."*

## Retry and Escalation

Failed runs trigger exponential backoff:

- Normal exit: short 1-second continuation retry (attempt 1)
- Abnormal exit: `delay = min(10000 * 2^(attempt - 1), agent.max_retry_backoff_ms)`
- Default max backoff: 300,000 ms (5 minutes)

Stall detection kills sessions silent longer than `codex.stall_timeout_ms` (default 300,000 ms). Per-state concurrency can override global `max_concurrent_agents` using `agent.max_concurrent_agents_by_state`.

Reconciliation checks run every tick: *"For each running issue, compute elapsed_ms since last_codex_timestamp if any event has been seen, else started_at. If elapsed_ms > codex.stall_timeout_ms, terminate the worker and queue a retry."*

## Verification Artifacts

**Workflow contract** (`WORKFLOW.md`): YAML front matter containing typed config; Markdown body as prompt template.

**Config requirements**:
- `tracker.kind`: selects adapter
- `tracker.active_states`, `terminal_states`: provider-native state names
- `agent.max_turns`, `max_concurrent_agents`, `max_retry_backoff_ms`
- `codex.command`, `codex.turn_timeout_ms`, `codex.stall_timeout_ms`
- `workspace.root` with path expansion
- `hooks.*` with `timeout_ms` (default 60 seconds)

**Prompt rendering** uses strict template mode with `issue` (normalized issue object) and `attempt` (null on first run, integer on retry). *"Unknown variables MUST fail rendering. Unknown filters MUST fail rendering."*

**Run attempt metadata**:
- `issue_id`, `issue_identifier`, `attempt`, `workspace_path`, `started_at`, `status`, error
- Live session: `session_id`, `thread_id`, `turn_id`, `codex_app_server_pid`, `last_codex_event`, token counts

## Implementation Interfaces (Required)

**Orchestrator**:
- Mutable in-memory state: `running`, `claimed`, `retry_attempts`, `completed`, `codex_totals`, `codex_rate_limits`
- Poll tick that reconciles, validates, fetches, sorts, and dispatches

**Tracker Adapter**:
- `fetch_issues_by_states(state_names)` → list of normalized issues
- `fetch_issues_by_ids(issue_ids)` → current snapshots
- Error categories: `unsupported_tracker_kind`, `invalid_tracker_config`, `tracker_request`, `tracker_response`

**Workspace Manager**:
- Create per-issue workspace (derives `workspace_key` via sanitization)
- Run hooks with timeouts
- Clean workspace for terminal issues

**Agent Runner**:
- Launch app-server subprocess in workspace cwd
- Extract session identity, stream events, handle turns
- Return success/failure to orchestrator

**Observability** (required structured logs; OPTIONAL snapshot/dashboard):
- Emit logs with `issue_id`, `issue_identifier`, `session_id` context
- If snapshot API: expose `/api/v1/state` (running, retrying, token totals) and `/api/v1/<issue_identifier>`
- If HTTP server (`server.port`): host dashboard and provide `GET /`, `POST /api/v1/refresh`

The spec explicitly avoids mandating approval/sandbox posture: *"Implementations are not REQUIRED to restart in-flight agent sessions automatically when config changes."* Each implementation documents its trust model independently.


## Supported Command Translations

The shim converts these iTerm2 commands to WezTerm equivalents:

- **`session split [-v]`** → `wezterm cli split-pane` (arranged in 3-column grid)
- **`session run -s <id> <cmd>`** → `wezterm cli send-text --pane-id <id>`
- **`session close -s <id>`** → `wezterm cli kill-pane --pane-id <id>`
- **`session list`** → Minimal session table
- Other commands silently succeed

## How Automations Are Defined

Automations are configured through the UI or CLI. In the interface, you specify:

- **Title**: the automation's display name
- **Prompt**: agent instructions supporting markdown, file mentions, emoji codes, and slash commands
- **Device**: the host running the session
- **Project**: a v2 GitHub-linked project or "No project" for session-per-run mode
- **Schedule**: preset or custom RRule (RFC 5545 format)
- **Agent**: Claude, Codex, Amp, or custom agents

Schedules use RRule syntax, with examples including `FREQ=DAILY;BYHOUR=9;BYMINUTE=0` for daily 9 AM runs or `FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9;BYMINUTE=0` for weekday mornings.

## Available Documentation Sections

The docs sidebar lists these pages:
- Getting Started, cmux TUI, Concepts
- Workspace Groups, Configuration, TextBox (Beta)
- Session Restore, Vault, Task Manager
- Custom Commands, Dock, Keyboard Shortcuts
- CLI Reference, Browser Automation, Skills
- Notifications, SSH, iOS App, Remote tmux
- Agent Integrations (Claude Code Teams, oh-my-opencode, oh-my-codex, oh-my-pi, oh-my-claudecode)

## Limitations of Provided Content

The webpage excerpt provided contains only the Getting Started guide. It does not include detailed specifications for:

- **CLI commands & Socket API**: Only a basic example appears: `"cmux list-workspaces"` and `"cmux notify --title "Build Complete" --body "Your build finished""`

- **cmux.json configuration keys**: Not documented in this excerpt

- **Notifications mechanism** (OSC sequences): Not detailed here

- **Skills system**: Listed but not explained

- **Session restore hooks & agent resume tokens**: Mentioned but implementation details absent

- **Browser automation**: Listed but not documented

**To access complete specifications**, you would need to visit the full documentation pages (CLI Reference, Configuration, Notifications, Session Restore, Skills, and Browser Automation sections) at the cmux docs site, as this excerpt only covers initial installation and basic setup.


## Key Limitation

The document explicitly states that **"Puck is flexible, and we've already found more ways to use it than we expected,"** suggesting the tool's full capabilities may still be evolving. Notably, the page doesn't specify exactly what systems Puck can "see," precise permission boundaries, or what specific triggers activate different functions—only that it **"has access to many different tools to help you manage your agents in Amp."**

The announcement frames Puck as an experimental feature, implying its mechanisms and scope may not be fully documented yet.


## Use Cases (Not Implementation Details)

The content illustrates practical applications rather than technical architecture:

- Spawning agents to handle parallel tasks: **"Run four low-mode threads in parallel to test this flow in Chrome at four screen sizes"**
- Transferring assets between workspaces: **"Pull the files from my abandoned prototype thread into this workspace"**
- Cross-machine delegation: **"Start a new thread on cloud-dev-box and upload this test matrix"**

## What's Not Specified

The page does not address:
- Addressing schemes or agent identifiers
- Transport protocols or network stack details
- Data serialization formats
- CLI commands for agent spawning or messaging
- Security/authentication mechanisms between agents

For implementation details on addressing, transport layers, and CLI interfaces, you would need to consult the [Docs](/docs) or [How to Build an Agent](/notes/how-to-build-an-agent) resources referenced in the footer.


## What It Does

Ralphex is a CLI tool that orchestrates Claude Code to execute multi-task implementation plans autonomously. Rather than requiring interactive guidance through each step, it "runs in your terminal from the root of a git repository" and "executes implementation plans autonomously - no IDE plugins or cloud services required."

The core problem it solves: Claude Code sessions accumulate context, degrading output quality over long workflows. Ralphex mitigates this by "executes each task in a fresh Claude Code session with minimal context, keeping the model sharp."

## Multi-Phase Execution Loop

Ralphex follows a structured four-phase process:

**Phase 1: Task Execution** — Reads plan tasks sequentially, sends each to Claude Code, runs validation commands, marks checkboxes complete, and commits results.

**Phase 2: First Code Review** — Launches 5 review agents in parallel (quality, implementation, testing, simplification, documentation) via Claude Code Task tool.

**Phase 3: External Review** — Runs external tool (codex by default, or custom script), iterates until convergence.

**Phase 4: Second Code Review** — Final review focusing on critical/major issues only via 2 agents.

Optional **Finalize Step** — Post-review automation (rebase, squash, notifications).

## Configuration

**Global config location:** `~/.config/ralphex/` (override via `--config-dir` or `RALPHEX_CONFIG_DIR`)

**Structure:**
- `config` — INI format settings (all commented by default)
- `prompts/` — Customizable task/review prompt templates
- `agents/` — Custom review agent definitions

**Local project override:** `.ralphex/` in repository root (priority: CLI flags > local config > global config > embedded defaults)

**Key options:**
- `claude_command`, `claude_args` — Claude CLI invocation
- `executor` — `codex` routes full pipeline through codex CLI; default uses Claude Code
- `external_review_tool` — `codex` (default), `custom`, or `none`
- `finalize_enabled` — Enable post-review automation
- `plans_dir` — Plan file directory (default: `docs/plans`)

## Automatic Commit/Revert Behavior

Ralphex commits after each completed task automatically. There is no explicit revert mechanism documented; instead, execution is iterative. If a task fails, "completed tasks are already committed to the feature branch" and re-running the plan continues from incomplete tasks (detected via unchecked `[ ]` boxes).

The system relies on git branch isolation—changes accumulate on a feature branch created from the plan filename. On failure or interruption, completed work persists; resuming re-reads the plan and continues from the first incomplete task.

## Key Capabilities

**Fleet Management**
The system organizes "lanes" (repo + worktree combinations) by project and "floats the ones waiting on you" to the top for prioritization. A single interface tracks many repos × many worktrees × many agents simultaneously.

**Durability & State Persistence**
The architecture uses a background daemon (`repomond`) backed by SQLite and file watchers. On Unix systems, it leverages tmux for agent persistence; on Windows, it employs ConPTY host processes. This ensures agents survive application restarts with full scrollback intact.

**Integrated Development Environment**
The desktop app (Mission Control) includes a built-in git explorer showing branch status, working-tree changes, commit history, and a CodeMirror editor with file trees and multi-file tab support.

## Core Components

**Runs** establish a durable namespace with a coordinator inbox. The system states: "A **Run** (namespace + coordinator inbox), **Tasks**, **Dispatches**, supervised **workers**, messages, and decision gates."

**Tasks** represent work items with specifications, dependencies, and lifecycle states: `pending`, `ready`, `dispatched`, `completed`, `failed`, or `blocked`.

**Dispatches** track individual task attempts on terminals, controlling worker completion and heartbeat messaging.

**Messages** flow through the coordinator inbox with types including `status`, `dispatch`, `worker_done`, `escalation`, `question`, and `heartbeat`.

**Decision gates** are coordinator-owned questions that prevent task progression until resolved.

## Supervision Model

Completion authority originates from the active dispatch context. Workers must send `worker_done` with both `taskId` and `dispatchId` to prevent stale retries from completing wrong dispatches.

Decision authority rests with the coordinator. Gate creation requires explicit resolution:

```
orca orchestration gate-create \
  --task <taskId> \
  --question "Merge the shared button change?" \
  --options '["yes","no"]' \
  --json

orca orchestration gate-resolve --id <gateId> --resolution "yes" --json
```

## Worker Launch & Completion

Start workers with task tracking:

```
orca orchestration worker-start --task <taskId> --worktree current --agent codex --json
```

Workers report completion including evidence:

```
orca orchestration send \
  --type worker_done \
  --subject "Completed mobile audit" \
  --body "Fixed footer overlap; no follow-ups." \
  --task-id <taskId> \
  --dispatch-id <dispatchId> \
  --outcome succeeded \
  --files-modified "src/app/settings/Billing.tsx" \
  --json
```

The framework requires `--outcome succeeded|failed` for completion messages.

## Message Coordination

Retrieve pending messages with waiting capability:

```
orca orchestration check --wait --types worker_done,escalation,question \
  --timeout-ms 900000 --json
```

Workers pose blocking questions to coordinators:

```
orca orchestration ask \
  --to <coordinatorHandle> \
  --question "Update shared component or only this page?" \
  --options "shared,page-only" \
  --timeout-ms 600000 \
  --json
```

Group messaging enables broadcast: `orca orchestration send --to @all --subject "Heads up" --body "Pausing dispatches for review." --json`


## Worktree Management

Create and inspect isolated work contexts:
- `orca worktree list --repo id:<repoId> --json`
- `orca worktree create --name fix-login --agent codex --prompt "Investigate the flaky login test" --json`
- `orca worktree set --worktree active --comment "reproduced failure; testing token refresh fix" --json`

Agent startup flags control initialization: `--agent`, `--prompt`, and `--setup run|skip|inherit`.

## Terminal Operations

Interact with terminal panes programmatically:
- `orca terminal read --terminal <handle> --json` (accumulated output)
- `orca terminal read --terminal <handle> --screen --json` (current frame)
- `orca terminal send --terminal <handle> --text "continue" --enter --json`
- `orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 300000 --json`
- `orca terminal create --worktree active --title "tests" --command "npm test" --json`

As guidance states: "Read before sending when you are not sure what the terminal is waiting for."

## Browser Automation

Control the embedded browser via snapshot-act-snapshot loops:
- `orca goto --url http://localhost:3000 --worktree active --json`
- `orca snapshot --worktree active --json`
- `orca click --element @e3 --worktree active --json`
- `orca fill --element @e1 --value "[email protected]" --worktree active --json`
- `orca screenshot --worktree active --json`
- `orca tab list --worktree active --json`
- `orca set device --name "iPhone 12" --worktree active --json`

## Required Configuration

The documentation emphasizes that proper setup is critical. You must add this to `wezterm.lua`:

```lua
local config = wezterm.config_builder()
config.default_gui_startup_args = { 'connect', 'unix' }
config.unix_domains = { { name = 'unix' }, }
```

The rationale is explicit: "This ensures WEZTERM_UNIX_SOCKET is consistent across all panes." Without this, panes created through keybindings may connect to different sockets than those spawned by workmux.

Tab creation keybindings must use `CurrentPaneDomain` rather than explicitly specifying `DomainName`, ensuring new tabs inherit the correct domain context.

## Cross-Workspace Navigation

For jumping between workspaces, add this user variable handler to `wezterm.lua`:

```lua
local wezterm = require("wezterm")
wezterm.on("user-var-changed", function(window, pane, name, value)
    if name == "workmux-switch-pane" then
        local data = wezterm.json_parse(value)
        window:perform_action(
            wezterm.action.SwitchToWorkspace({ name = data.workspace }),
            pane
        )
        wezterm.time.call_after(0.1, function()
            for _, win in ipairs(wezterm.mux.all_windows()) do
                for _, tab in ipairs(win:tabs()) do
                    if tab:get_title() == data.tab_title then
                        tab:activate()
                        local panes = tab:panes()
                        if #panes > 0 then panes[1]:activate() end
                        return
                    end
                end
            end
        end)
    end
end)
```

## Compare ways to keep a session running

Three approaches keep the current session running between prompts. Pick based on what should start the next turn:

| Approach                                                            | Next turn starts when                                                                                                                                                                         | Stops when                                                                                                                                                                                      |
| :------------------------------------------------------------------ | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/goal`                                                             | The previous turn finishes, or an [idle check-in](#background-work-defers-evaluation) comes due while background work keeps the goal waiting, up to three times per goal between your prompts | A model confirms the condition is met or judges it impossible, or a turn fails on [an error you have to fix](#errors-you-have-to-fix-clear-the-goal), or you run [`/goal clear`](#clear-a-goal) |
| [`/loop`](/docs/en/scheduled-tasks#run-a-prompt-repeatedly-with-%2Floop) | A time interval elapses                                                                                                                                                                       | You stop it, or Claude decides the work is done                                                                                                                                                 |
| [Stop hook](/docs/en/hooks-guide#prompt-based-hooks)                     | The previous turn finishes                                                                                                                                                                    | Your own script or prompt decides                                                                                                                                                               |

`/goal` and a Stop hook both fire after every turn. `/goal` is a session-scoped shortcut: you type a condition and it's active for the current session only. A Stop hook lives in your settings file, applies to every session in its scope, and can run a script for deterministic checks or a prompt for model-evaluated ones.

[Auto mode](/docs/en/auto-mode-config) on its own approves tool calls within a single turn but doesn't start a new one. Claude stops when it judges the work done. `/goal` adds a separate evaluator that checks your condition after every turn, so completion is decided by a fresh model rather than the one doing the work. The two are complementary: auto mode removes per-tool prompts, and `/goal` removes per-turn prompts.

<Tip>
  The approaches above keep the current session running. You can also schedule work that runs independent of any open session, such as nightly tests or morning triage. See [scheduling options](/docs/en/scheduled-tasks#compare-scheduling-options) for cloud routines and desktop scheduled tasks.
</Tip>

## Use `/goal`

One goal can be active per session. The same command sets, checks, and clears it depending on the argument.

### Set a goal

Run `/goal` followed by the condition you want satisfied. If a goal is already active, the new one replaces it.

```text theme={null}
/goal all tests in test/auth pass and the lint step is clean
```

Setting a goal starts a turn immediately, with the condition itself as the directive. You don't need to send a separate prompt. While the goal is active, a `◎ /goal active` indicator shows how long the goal has been running.

A goal doesn't change your permission mode. To let goal turns run unattended, run `/goal` in [auto mode](/docs/en/auto-mode-config). In [Manual mode](/docs/en/permission-modes), Claude still asks before tool calls that your settings don't already allow, such as the test command above.

While the goal is active, the transcript shows each verdict the evaluator returns, and you can press Ctrl+O to see the reason behind it. The status view also shows the most recent reason, so you can see what Claude is working toward next.

### Write an effective condition

The [evaluator](#how-evaluation-works) judges your condition against what Claude has surfaced in the conversation. It doesn't run commands or read files independently, so write the condition as something Claude's own output can demonstrate. "All tests in `test/auth` pass" works because Claude runs the tests and the result lands in the transcript for the evaluator to read.

A condition that holds up across many turns usually has:

* **One measurable end state**: a test result, a build exit code, a file count, an empty queue
* **A stated check**: how Claude should prove it, such as "`npm test` exits 0" or "`git status` is clean"
* **Constraints that matter**: anything that must not change on the way there, such as "no other test file is modified"

The condition can be up to 4,000 characters.

To bound how long a goal runs, include a turn or time clause in the condition, such as `or stop after 20 turns`. Claude reports progress against that clause each turn and the evaluator judges it from the conversation.

### Check status

Run `/goal` with no arguments to see the current state.

```text theme={null}
/goal
```

If a goal is active, the status shows:

* The condition
* How long it has been running
* How many turns have been evaluated
* The current token spend
* The evaluator's most recent reason

The turn count and the most recent reason appear after the first evaluation has run.

If no goal is active but one was achieved earlier in the session, the status shows the achieved condition along with its duration, turn count, and token spend.

### Clear a goal

Run `/goal clear` to remove an active goal before it resolves.

```text theme={null}
/goal clear
```

Claude prints `Goal cleared:` followed by the condition to confirm, or `No goal set` if nothing was active.

`stop`, `off`, `reset`, `none`, and `cancel` are accepted as aliases for `clear`. Running `/clear` to start a new conversation also removes any active goal.

### Resume with an active goal

When you resume a session, Claude Code restores a goal that was still active when the session ended. Claude Code restores it on every resume route: `--continue`, `--resume` with a session ID or name, and the [session picker](/docs/en/sessions#use-the-session-picker). Before v2.1.239, Claude Code restored the goal on every route except the `claude --resume` picker.

Claude Code carries the condition over but resets the turn count, timer, and token-spend baseline. It doesn't restore a goal that was already achieved or cleared.

### Run non-interactively

`/goal` works in [non-interactive mode](/docs/en/headless), in the [desktop app](/docs/en/desktop), and through [Remote Control](/docs/en/remote-control). Setting a goal with `-p` runs the loop to completion in a single invocation:

```bash theme={null}
claude -p "/goal CHANGELOG.md has an entry for every PR merged this week"
```

With the default text output, nothing prints until the run ends, so a goal that runs many turns can look stuck. Add `--output-format stream-json --verbose` to emit each message as the loop runs.

Interrupt the process with Ctrl+C to stop a non-interactive goal before it resolves.

## How evaluation works

`/goal` is a wrapper around a session-scoped [prompt-based Stop hook](/docs/en/hooks#prompt-based-hooks). Each time Claude finishes a turn, Claude Code sends the condition and the conversation so far to your configured [small fast model](/docs/en/model-config), which defaults to Haiku on the Claude API; on a third-party provider, check your [provider page](/docs/en/third-party-integrations) for the platform's default. The model returns one of three verdicts, each with a short reason:

* **Not yet met**: Claude keeps working and takes the reason as guidance for the next turn.
* **Met**: Claude Code clears the goal and records an achieved entry in the transcript.
* **Impossible**: the evaluator judged that the condition can never be satisfied. Claude Code clears the goal and records a failed entry in the transcript along with the reason. You don't need to clear it yourself.

If Claude keeps answering the evaluator without making progress (no tool use for several turns in a row), Claude Code stops the loop, prints a warning, and returns control to you with the goal still set. Evaluation resumes after your next prompt. The [hooks guide](/docs/en/hooks-guide#stop-hook-hits-the-block-cap) explains the underlying mechanism.

### Errors you have to fix clear the goal

If a turn fails on an error that won't clear until you fix it, Claude Code clears the goal and prints a warning naming the cause. The warning starts with `Goal cleared after an unrecoverable error` and ends with `Run /goal again to continue`. Fix the cause, then [set the goal again](#set-a-goal) with `/goal <condition>`. Four kinds of failure clear the goal:

* An authentication failure, when Claude Code manages its own credentials. When a host manages them for you, such as the desktop app, the VS Code extension, or a [cloud session](/docs/en/claude-code-on-the-web), Claude Code leaves the goal active because the host restores access on its own.
* An exhausted credit balance
* A context overflow that [auto-compaction](/docs/en/model-config#set-the-auto-compact-window) couldn't clear
* A model that isn't available

After any other failure, including transient errors such as rate limits and overloaded servers, Claude Code leaves the goal active.

### Background work defers evaluation

If a subagent or a background shell command is still running when a turn ends, Claude Code skips the evaluation for that turn. It evaluates at the end of the next turn that finishes with no background work running. When the background work finishes, Claude Code delivers the result to Claude as a new turn, so you don't have to prompt.

Once background work has kept the goal waiting for 30 minutes, a check-in is due. In the check-in, Claude Code lists the running tasks and asks Claude to read their output, keep waiting if they're progressing, and fix or stop any that are stuck. After the first check-in, Claude Code waits twice as long before each later check-in, up to four times the first interval: with the default, 1 hour after the first check-in, then every 2 hours. Claude Code delivers a due check-in, the first one included, in one of two ways:

* **When a turn ends**: Claude Code delivers the check-in at the end of the next turn that finishes with the work still running. In a non-interactive session, such as one started with `-p`, this is the only way Claude Code delivers check-ins.
* **While the session is idle**: in an interactive session, Claude Code also starts a turn on its own to deliver the check-in instead of waiting for your next prompt. If the background work has stopped without reporting a result, Claude Code asks Claude to continue toward the goal. Claude Code starts at most three idle check-ins per goal between your prompts. In the third idle check-in, Claude Code says that idle check-ins are paused until you send another prompt. Before v2.1.246, idle check-ins were uncapped. Idle check-ins require Claude Code v2.1.236 or later.

Before v2.1.239, only idle check-ins backed off this way; a check-in delivered at a turn end recurred at the first interval.

To change the first interval, set [`CLAUDE_CODE_GOAL_CHECKIN_MINUTES`](/docs/en/env-vars). Claude Code uses your value in place of the 30-minute interval and scales the later intervals with it. Set it to `0` to turn check-ins off. Check-ins require Claude Code v2.1.234 or later.

### Evaluation model and cost

To evaluate on a different model, set [`ANTHROPIC_DEFAULT_HAIKU_MODEL`](/docs/en/model-config#environment-variables).

<Warning>
  Claude Code reads `ANTHROPIC_DEFAULT_HAIKU_MODEL` everywhere it uses the small fast model, not only for `/goal` evaluation. When you set it, Claude Code also resolves the [`haiku` alias](/docs/en/model-config#model-aliases) to that model and runs [background functionality](/docs/en/costs#background-token-usage), such as conversation summarization, on it.
</Warning>

The evaluator runs on whichever provider your session is configured for. It does not call tools, so it can only judge what Claude has already surfaced in the conversation.

<Note>
  Evaluation tokens are billed on the small fast model configured for your provider and are typically negligible compared to main-turn spend.
</Note>

## Requirements

Claude Code makes `/goal` available under the same [workspace trust rule as hooks in settings files](/docs/en/permissions#what-runs-before-you-trust-a-folder), because the evaluator is part of the hooks system. `/goal` is also unavailable when [`disableAllHooks`](/docs/en/hooks#disable-or-remove-hooks) is `true` after settings precedence applies, or when [`allowManagedHooksOnly`](/docs/en/settings-reference#allowmanagedhooksonly) is set in managed settings. In each case, the command tells you why instead of silently doing nothing.

## See also

* [Run a prompt repeatedly with `/loop`](/docs/en/scheduled-tasks#run-a-prompt-repeatedly-with-%2Floop): re-run on a time interval instead of toward a condition
* [Prompt-based hooks](/docs/en/hooks-guide#prompt-based-hooks): write your own Stop hook when you need custom evaluation logic
* [Auto mode](/docs/en/auto-mode-config): approve tool calls automatically so each goal turn runs unattended
* [Scheduling comparison](/docs/en/scheduled-tasks#compare-scheduling-options): run work on a schedule independent of any open session



## Choose an approach

The right approach depends on who coordinates the work, whether the workers need to communicate, and whether they edit the same files:

* **Who coordinates the work?**
  * Claude delegates and collects results inside one conversation: [subagents](/docs/en/sub-agents)
  * You hand off independent tasks and check back later: [agent view](/docs/en/agent-view)
  * Claude plans, assigns, and supervises a group of workers: [agent teams](/docs/en/agent-teams), experimental and disabled by default
  * A script holds the plan instead of Claude's turn-by-turn judgment: [dynamic workflows](/docs/en/workflows). See [how workflows compare to subagents and skills](/docs/en/workflows#when-to-use-a-workflow)
* **Do the workers need to talk to each other?** Claude can pass findings with [cross-session messaging](/docs/en/cross-session-messaging) between sessions you run yourself, including the sessions you dispatch from agent view. Subagents report results back to the conversation that spawned them, and agent view sessions report results only to you. Teammates in an agent team message each other directly and, when they [have the Task tools](/docs/en/tools-reference#task-tool-availability), share a task list.
* **Do the tasks touch the same files?** Isolate the work with [worktrees](/docs/en/worktrees). Subagents and sessions you run yourself can each use a separate worktree. Agent teams don't isolate teammates in worktrees, so [partition the work](/docs/en/agent-teams#avoid-file-conflicts) so each teammate owns a different set of files.

## Check on running work

The command for checking on running work depends on which approach you used:

* For background sessions, `claude agents` opens [agent view](/docs/en/agent-view): one screen showing every session, its state, and which ones need your input.
* For subagents in the current session, named background subagents appear in the @-mention typeahead with their status. As of v2.1.198, `/agents` no longer opens a panel; it prints a notice pointing to the subagent file locations. To [create and edit custom subagents](/docs/en/sub-agents#configure-subagents), ask Claude or edit the files directly. Despite the similar name, `/agents` is separate from `claude agents`.
* For anything running in the background of the current session, `/tasks` lists each item and lets you check on, attach to, or stop it. The list also includes subagents that have finished.
* For dynamic workflows, `/workflows` lists running and completed runs, the phase each is in, and how many agents have finished.

For a desktop view of all your sessions, see [parallel sessions in the desktop app](/docs/en/desktop#work-in-parallel-with-sessions).

## Learn more

Each guide below covers setup and configuration for one approach:

* [Create custom subagents](/docs/en/sub-agents): define reusable specialists and control which tools they can use.
* [Manage agents with agent view](/docs/en/agent-view): dispatch sessions, watch their state, and attach when one needs you.
* [Orchestrate agent teams](/docs/en/agent-teams): set up a lead and teammates, assign tasks, and review their work.
* [Orchestrate dynamic workflows](/docs/en/workflows): run a bundled workflow or have Claude write one that runs many subagents and verifies their findings against each other.
* [Run parallel sessions with worktrees](/docs/en/worktrees): start Claude in an isolated checkout, control what gets copied in, and clean up afterward.



## When to use a workflow

[Subagents](/docs/en/sub-agents), [skills](/docs/en/skills), [agent teams](/docs/en/agent-teams), and workflows can all run a multi-step task. The difference is who holds the plan:

|                                 | Subagents                      | Skills                       | Agent teams                            | Workflows                            |
| :------------------------------ | :----------------------------- | :--------------------------- | :------------------------------------- | :----------------------------------- |
| What it is                      | A worker Claude spawns         | Instructions Claude follows  | A lead agent supervising peer sessions | A script the runtime executes        |
| Who decides what runs next      | Claude, turn by turn           | Claude, following the prompt | The lead agent, turn by turn           | The script                           |
| Where intermediate results live | Claude's context window        | Claude's context window      | A shared task list                     | Script variables                     |
| What's repeatable               | The worker definition          | The instructions             | The team definition                    | The orchestration itself             |
| Scale                           | A few delegated tasks per turn | Same as subagents            | A handful of long-running peers        | Dozens to hundreds of agents per run |
| Interruption                    | Restarts the turn              | Restarts the turn            | Teammates keep running                 | Resumable in the same session        |

A workflow moves the plan into code. With subagents, skills, and agent teams, Claude is the orchestrator: it decides turn by turn what to spawn or assign next, and every result lands in a context window. A workflow script holds the loop, the branching, and the intermediate results itself, so Claude's context holds only the final answer.

Moving the plan into code also lets a workflow apply a repeatable quality pattern, not just run more agents: it can have independent agents adversarially review each other's findings before they're reported, or draft a plan from several angles and weigh them against each other, so you get a more trustworthy result than a single pass.

## Run a bundled workflow

The quickest way to see a workflow in action is to run `/deep-research`, the [built-in workflow](#bundled-workflows) Claude Code includes for investigating a question across many sources. You'll see agents work through a set of phases in the background while your session stays free, and get one report at the end instead of a turn-by-turn transcript.

<Steps>
  <Step title="Run the workflow">
    Run `/deep-research` with a question you want investigated. It fans out web searches across several angles, fetches and cross-checks the sources it finds, and synthesizes a cited report.

    ```text wrap theme={null}
    /deep-research What changed in the Node.js permission model between v20 and v22?
    ```
  </Step>

  <Step title="Allow workflows">
    Claude Code asks whether to allow the workflow. Select **Yes** to continue. The exact prompt depends on your permission mode. See [Approve the plan before it runs](#approve-the-plan-before-it-runs) for the per-mode options.
  </Step>

  <Step title="Watch progress">
    The run starts in the background. Run `/workflows`, use the arrow keys to select the run, and press Enter to open its progress view:

    ```text wrap theme={null}
    /workflows
    ```

    The view shows each phase with its agent count, token total, and elapsed time. Drill into any phase to see its agents and what each one found. See [Watch the run](#watch-the-run) for the full set of controls.

    You can also watch from the task panel below the input box: a one-line progress summary appears there while the run is going. Press the down arrow to focus it, then Enter to expand.
  </Step>

  <Step title="Read the report">
    When the run finishes, the report lands in your session. It cites the sources each claim came from, with claims that didn't survive cross-checking already filtered out.

    When the verifier agents can't check a claim, such as after a rate limit or API error, the report lists that claim as unverified instead of counting it as refuted.
  </Step>
</Steps>

To run a workflow for your own task, [have Claude write one](#have-claude-write-a-workflow), and once a run does what you wanted you can [save it](#save-the-workflow-for-reuse) as a command of your own.

### Bundled workflows

Claude Code includes `/deep-research` as a built-in workflow:

| Command                     | What it does                                                                                                                                                                                                                                                                                                      |
| :-------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/deep-research <question>` | Fans out web searches on a question across several angles, fetches and cross-checks the sources it finds, votes on each claim, and returns a cited report with claims that didn't survive cross-checking filtered out. Requires the [WebSearch tool](/docs/en/tools-reference#websearch-tool-behavior) to be available |

`/deep-research` runs only when you invoke it.

[Workflows you save](#save-the-workflow-for-reuse) yourself become commands the same way and appear in `/` autocomplete alongside the bundled ones.

### Watch the run

Workflows run in the background, so the session stays responsive while agents work. Run `/workflows` at any time to list running and completed workflows, then select one to open its progress view.

The progress view shows each phase with its agent counts, token totals, and elapsed time. The footer lists the key for each action:

| Key            | Action                                                                                                                      |
| :------------- | :-------------------------------------------------------------------------------------------------------------------------- |
| `↑` / `↓`      | Select a phase or agent                                                                                                     |
| `Enter` or `→` | Drill into the selected phase, then into an agent to read its prompt, recent tool calls, and result                         |
| `Esc` or `←`   | Back out one level. In v2.1.203 through v2.1.205, `←` didn't step back out of a phase or agent; use `Esc` on those versions |
| `j` / `k`      | Scroll within the agent detail when it overflows                                                                            |
| `f`            | Filter the agent list in the selected phase by status. Press again to cycle                                                 |
| `p`            | Pause or resume the run                                                                                                     |
| `x`            | Stop the selected agent, or stop the whole workflow when focus is on the run                                                |
| `r`            | Restart the selected running agent                                                                                          |
| `s`            | [Save](#save-the-workflow-for-reuse) the run's script as a command                                                          |

## Have Claude write a workflow

You can have Claude write a workflow for your task in two ways:

* [Ask for a workflow](#ask-for-a-workflow-in-your-prompt) in your prompt, either in your own words or by including the keyword `ultracode`, and Claude writes one for the task.
* [Let Claude decide with ultracode](#let-claude-decide-with-ultracode): set `/effort ultracode` and Claude plans a workflow for every substantive task in the session.

You can also run a workflow command that already exists: a [bundled workflow](#bundled-workflows) like `/deep-research`, or one you've [saved](#save-the-workflow-for-reuse).

### Ask for a workflow in your prompt

To run a single task as a workflow without changing the session's effort level, include the keyword `ultracode` in your prompt. Asking in your own words, for example "use a workflow" or "run a workflow", also works: Claude treats a direct request as the same opt-in. Before v2.1.160 the literal trigger keyword was `workflow`; natural-language requests work in both versions.

```text wrap theme={null}
ultracode: audit every API endpoint under src/routes/ for missing auth checks
```

Claude Code highlights the keyword in your input and Claude writes a workflow script for the task instead of working through it turn by turn. The keyword only chooses how Claude structures the work: the agents' tool calls receive the same permission checks and [sandboxing](/docs/en/sandboxing) as any other tool call in the session.

If the run does what you wanted, you can [save it as a command](#save-the-workflow-for-reuse) afterward. If you already have an orchestrator built another way, such as a folder of subagent prompts or a skill that fans work out, you can point Claude at it and ask for a workflow that does the same thing.

#### Dismiss or turn off the keyword

If you didn't mean to start a workflow, press `Option+W` on macOS or `Alt+W` on Windows and Linux to dismiss the highlight for this prompt, or press backspace while the cursor is right after the highlighted keyword. To stop the keyword from triggering at all, turn off Ultracode keyword trigger in `/config`.

#### Where the keyword works

The keyword is an opt-in only in a prompt you type yourself: at the interactive prompt, in an IDE extension panel, in a [Remote Control](/docs/en/remote-control) client, or in an Agent SDK application that stamps your keyboard input's [`origin`](/docs/en/agent-sdk/typescript#sdkmessageorigin) as `{ kind: "human" }`. It doesn't start a workflow when it reaches the session another way:

* a prompt passed with `-p`
* a prompt an Agent SDK application sends without stamping it as human input
* a scheduled task prompt
* a webhook payload or pull request comment relayed into the conversation

<Note>
  Before v2.1.210, the keyword started a workflow from any of these routes too, including a webhook payload or pull request comment relayed into the conversation.
</Note>

### Let Claude decide with ultracode

Ultracode is a Claude Code setting that combines `xhigh` [reasoning effort](/docs/en/model-config#adjust-effort-level) with automatic workflow orchestration. With it on, Claude plans a workflow for each substantive task instead of waiting for you to ask.

```text wrap theme={null}
/effort ultracode
```

To start a session with ultracode already on, launch with `claude --effort ultracode`. Requires Claude Code v2.1.203 or later.

To turn it on while you choose a model, move the `/model` picker's effort slider to `ultracode` with the arrow keys. [Adjust effort level](/docs/en/model-config#adjust-effort-level) lists the routes that turn ultracode on.

With ultracode on, Claude decides when a task warrants a workflow. A single request can turn into several workflows in a row: one to understand the code, one to make the change, and one to verify it. This applies to every task in the session, so each request uses more tokens and takes longer than at lower effort levels.

`/effort ultracode` lasts for the current session; to have every session start with it, set the [`ultracode`](/docs/en/settings-reference#ultracode) setting. Drop back with `/effort high` when you return to routine work. It's available on models that support `xhigh` [effort](/docs/en/model-config#adjust-effort-level); on other models the `/effort` menu doesn't offer it.

### Approve the plan before it runs

In the CLI, the per-run prompt shows the planned phases and these options:

* **Yes, run it**: start the run
* **Yes, and don't ask again for `<name>` in `<path>`**: start, and skip this prompt for this workflow in this project from now on. Claude Code offers this option when you run a bundled, saved, or plugin workflow by name, not for a script Claude wrote for the current task.
* **View raw script**: read the script before deciding
* **No**: cancel

`Ctrl+G` opens the script in your editor. `Tab` lets you adjust the prompt before the run starts.

Whether you see this prompt depends on your [permission mode](/docs/en/permission-modes):

| Permission mode        | When you're prompted                                                                                                                                    |
| :--------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Auto                   | First launch only. Any **Yes** records consent in your user settings, and later launches start without prompting. Skipped entirely when ultracode is on |
| Manual, accept edits   | Every run, unless you've selected **Yes, and don't ask again** for that workflow in this project                                                        |
| Bypass permissions     | Claude Code doesn't prompt you. The run starts immediately                                                                                              |
| `claude -p`, Agent SDK | Claude Code doesn't prompt you                                                                                                                          |

In `claude -p` and the Agent SDK, Claude Code never shows this prompt. It runs the Workflow tool call through the same [permission evaluation](/docs/en/agent-sdk/permissions#how-permissions-are-evaluated) as the rest of the session, so deny rules, ask rules, and `dontAsk` mode apply to the launch as they apply to every tool call. To let the workflow start in these runs, use one of these:

* **Permission rule**: `Workflow` in your allow rules approves every workflow, and `Workflow(<name>)` approves one saved workflow by name.
* **Auto permission mode**: the [classifier](/docs/en/permission-modes#eliminate-prompts-with-auto-mode) reviews the call and can approve it.
* **Bypass permissions mode**: Claude Code approves the call.
* **A `PreToolUse` hook**: a [hook](/docs/en/hooks#pretooluse) that returns `allow` for the call approves it.
* **Your host**: a [`--permission-prompt-tool`](/docs/en/cli-reference#cli-flags) approves it, or, with the Agent SDK, a [`canUseTool`](/docs/en/agent-sdk/permissions) callback or a [`PermissionRequest` hook](/docs/en/hooks#permissionrequest) approves it.

In the Desktop app, an approval card shows the workflow name, the phase list, and a token-usage caution, with **Once**, **Always**, and **Deny** actions. The progress view appears in the Background tasks side pane.

The subagents the workflow spawns use your [permission rules](/docs/en/settings-reference#permission-settings), and Claude Code picks their permission mode by the rules under [which permission mode a subagent runs in](/docs/en/sub-agents#permission-modes). To avoid prompts on a long run, add the tools the agents need to your allow rules before starting.

### Save the workflow for reuse

When Claude writes a workflow for a task you'll repeat, you can save that run's script as a command. A process like a review you run on every branch then runs the same orchestration each time.

Run `/workflows`, select the run you want to keep, and press `s`. In the save dialog, Tab toggles between the two save locations:

* `.claude/workflows/` in your project: shared with everyone who clones the repo
* `~/.claude/workflows/` in your home directory: available in every project, visible only to you. If you set [`CLAUDE_CONFIG_DIR`](/docs/en/env-vars), this location is the `workflows/` directory under that path.

The save dialog shows the resolved path for the personal location.

Press Enter to save. The workflow runs as `/<name>` in future sessions from either location.

Claude Code checks the save location for symlinks before writing, and shows an error instead of writing through one. What it checks depends on where you save:

* Project location: Claude Code refuses if `.claude`, `.claude/workflows`, or the target file is a symlink.
* Personal location: Claude Code refuses only if the target file itself is a symlink, so a `~/.claude` directory managed by a dotfiles tool still works.

Before v2.1.216, Claude Code followed the link, which could place the file outside the location you chose.

In a monorepo with several `.claude/` directories, you can keep workflows alongside the package they apply to. As of v2.1.178, saving to the project location writes to the closest `.claude/workflows/` directory that already exists between your working directory and the repository root, or to the repository root if none exists yet. Project workflows also load from every `.claude/workflows/` along that path, and when more than one defines the same name Claude Code runs the one closest to the working directory.

If a project workflow and a personal workflow share a name, the project one runs.

### Distribute a workflow in a plugin

To share a workflow across teams or repositories, include it in a [plugin](/docs/en/plugins). Place the script in a `workflows/` directory at the plugin root, or point to a different location with the [`workflows` manifest field](/docs/en/plugins-reference#component-path-fields).

Plugin workflows are namespaced by the plugin name. A plugin called `acme-tools` containing a script whose `meta.name` is `release-audit` runs as `/acme-tools:release-audit`.

### Pass input to a saved workflow

A saved workflow can accept input through the `args` parameter. The script reads it as a global named `args`. Use this to supply a research question, a list of target paths, or a configuration object at invocation time instead of editing the script for each run.

The following prompt runs a saved workflow with a list of issue numbers:

```text wrap theme={null}
Run /triage-issues on issues 1024, 1025, and 1030
```

Claude passes the list as structured data, so the script can call array and object methods on `args` directly without parsing it first. If `args` is omitted, the global is `undefined` inside the script.

## Example workflow prompts

A workflow fits best when the task is larger than one agent can hold in context, or when the same step needs to run across many items. The prompts below show common shapes. Each one asks Claude to write and run a workflow for that task; you don't write the script yourself.

### Audit many files for the same issue

Fan out one agent per file, then collect and verify the findings.

```text wrap theme={null}
use a workflow to audit every route handler under src/routes/ for missing authentication checks, and adversarially verify each finding before reporting it
```

### Keep fixing until a check passes

Run a checker, fix what failed, and repeat until it passes or stops making progress.

```text wrap theme={null}
use a workflow to run npx tsc --noEmit and keep fixing the reported errors until the type check passes or two rounds in a row make no progress
```

### Migrate many files in parallel

Discover the files to migrate, transform each one in an isolated copy so edits don't conflict, and verify each result.

```text wrap theme={null}
use a workflow to migrate every component under src/components/ from JavaScript to TypeScript, working on each file in its own isolated copy
```

### Review every changed file and write one summary

Run a reviewer per file, then hand all the findings to one agent that ranks and deduplicates them.

```text wrap theme={null}
use a workflow to review every file changed in this PR for correctness issues, then merge the per-file findings into one ranked summary
```

### Research a topic across many sources

Fan out readers across changelogs, issues, and docs, then synthesize. The bundled `/deep-research` workflow does this; you can also describe a narrower version.

```text wrap theme={null}
use a workflow to research how our three competitors handle rate limiting: read their public docs and recent changelog entries in parallel, then compare the approaches
```

### Find issues until the list stops growing

Keep searching in rounds and stop when new rounds turn up nothing new.

```text wrap theme={null}
use a workflow to find flaky tests in this repo: run the suite repeatedly, record which tests fail intermittently, and stop once two rounds in a row find nothing new
```

### What the saved script looks like

When you [save a workflow](#save-the-workflow-for-reuse), the file in `.claude/workflows/` holds a `meta` block followed by a script body that orchestrates subagents. You usually don't need to edit it, but here is the shape of a small one so you can recognize what Claude generated:

```javascript theme={null}
export const meta = {
  name: 'audit-routes',
  description: 'Audit every route handler for missing auth checks',
}

const found = await agent('List every .ts file under src/routes/.', {
  schema: { type: 'object', required: ['files'], properties: { files: { type: 'array', items: { type: 'string' } } } },
})

const audits = await pipeline(found.files, file =>
  agent(`Audit ${file} for missing authentication checks.`, { label: file }),
)

return audits.filter(Boolean)
```

The body is plain JavaScript with top-level `await`. `agent()` spawns one subagent, `pipeline()` runs one per item in a list, and `parallel()` runs a set of agent tasks at the same time and waits for all of them.

An `agent()` call resolves to `null` if you stop it mid-run or it hits an unrecoverable API error. `pipeline()` keeps that `null` in the results array, which is why the example ends with `.filter(Boolean)` to drop those entries.

### Edit a saved script

To change a [workflow you saved](#save-the-workflow-for-reuse), edit its `.js` file or ask Claude to make the change. Before you edit or ask, run the `/workflow-authoring` [bundled skill](/docs/en/skills#bundled-skills) to load the script-writing reference Claude works from. The skill requires Claude Code v2.1.248 or later.

To run the edited version in the current session, run [`/reload-skills`](/docs/en/commands#all-commands) to re-read the workflow directories, then run `/<name>` again.

Claude Code applies these rules to each part of the file when it loads and runs the script:

* **`meta` block**: keep `export const meta` as the first statement, and keep it a plain object literal with a `name` and a `description`. If it contains anything other than literal values, such as a variable, a function call, or a spread, Claude Code drops `/<name>` from `/` autocomplete.
* **Body**: besides `agent()`, `pipeline()`, and `parallel()`, you can call `phase()` to group the agents that follow under a title in the progress view, call `log()` to show a message above the phases, and read the [`args`](#pass-input-to-a-saved-workflow) global. If the body has a syntax error, Claude Code reports it when you run the workflow.
* **`phases`**: if you list them in `meta`, give each entry exactly the title you pass to `phase()`. A `phase()` title with no entry gets a progress group of its own.
* **Timestamps and randomness**: Claude Code makes `Date.now()`, `Math.random()`, and a no-argument `new Date()` throw inside the script, so that a [relaunched run](#resume-after-a-pause) repeats the same `agent()` calls. Pass a timestamp in through `args` instead.

You can also edit [the script of a single run](#how-a-workflow-runs) rather than the saved copy. [Resume after a pause](#resume-after-a-pause) covers which agents run again when you relaunch an edited script. For the Workflow tool's inputs, see its entry in the [Agent SDK reference](/docs/en/agent-sdk/typescript#workflow).

## How a workflow runs

The workflow runtime executes the script in an isolated environment, separate from your conversation. Intermediate results stay in script variables instead of landing in Claude's context.

Every run writes its script to a file under your session's directory in `~/.claude/projects/`. Claude receives the path when the run starts, so you can ask for it. You can open that file to read the orchestration Claude wrote, diff it against a previous run's script, or edit it and ask Claude to relaunch from the edited version.

Claude can start a workflow only from a script file the session is already allowed to read. To run a script kept outside your working directory, add its directory with [`/add-dir`](/docs/en/permissions#working-directories) or a [Read allow rule](/docs/en/permissions#read-and-edit) first.

The runtime tracks each agent's result as the run progresses, which is what makes a run [resumable](#resume-after-a-pause) within the same session.

### Prompt caching in a fan-out

Agents in the same run can read each other's [prompt cache](/docs/en/prompt-caching#subagents-and-the-cache). Two agents that run with the same model, effort level, agent type, tools, output schema, and working directory build the same tools-and-system-prompt prefix, so an agent that starts after a matching sibling's response has begun reads that sibling's cache on its first request.

A workflow agent's requests fall outside the main conversation's [cache TTL bucket](/docs/en/prompt-caching#which-ttl-each-request-gets), so its cache holds for five minutes by default, including on a Claude subscription. To keep it for an hour, set [`subagentPromptCacheTtl`](/docs/en/settings-reference#subagentpromptcachettl) to `1h`. The API bills 1-hour cache writes at a higher rate.

When a fan-out starts several matching agents at once, Claude Code holds all but the first until the first agent's response begins, then releases the held agents together so their first requests read the shared prefix instead of each processing it uncached. Claude Code caps the hold at [`CLAUDE_CODE_WORKFLOW_PREFIX_STAGGER_MS`](/docs/en/env-vars) milliseconds, `5000` by default. Set it to `0` to disable the hold.

### Behavior and limits

The runtime applies the following constraints:

| Constraint                                                                                                            | Why                                                                                                                             |
| :-------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------ |
| No mid-run user input                                                                                                 | Only agent permission prompts can pause a run. For sign-off between stages, run each stage as its own workflow                  |
| No direct filesystem or shell access from the workflow itself                                                         | Agents read, write, and run commands. The script coordinates the agents                                                         |
| No module loading: a script that contains `import()` fails before the run starts                                      | The script body is plain JavaScript. Put work that needs a library in an agent's task                                           |
| Up to 16 concurrent agents, fewer when Claude Code has fewer CPUs available, including inside a CPU-limited container | Bounds local resource use                                                                                                       |
| In a fan-out, agents that share the first agent's prompt-cache prefix start up to 5 seconds after it by default       | All but the first read the [prefix the first agent cached](#prompt-caching-in-a-fan-out) instead of each processing it uncached |
| Up to 4,096 items in a single `parallel()` or `pipeline()` call: the runtime rejects a longer list with an error      | A silent cap would drop part of the workload without telling the script                                                         |
| 1,000 agents total per run                                                                                            | Prevents runaway loops                                                                                                          |

## Manage runs

Once a run starts, you manage it from the `/workflows` view, or by expanding its progress line in the task panel below the input box.

### Resume after a pause

Resume a paused run from `/workflows` by selecting it and pressing `p`. For a run you stopped, ask Claude to relaunch the workflow with the same script. Claude Code replays the run in the order agents started, and each agent either returns its saved result or runs again:

* **Completed**: returns its saved result. The first agent whose prompt differs from the previous run, because you edited the script or an earlier agent returned something different, runs again, and so does every agent after it, even ones that completed.
* **Still running when you stopped**: starts over. Stopping the whole run doesn't count any agent as failed.
* **Failed**: runs again, and so does every agent that started after it, even ones that completed. Stopping one agent alone, by selecting it in [`/workflows`](#watch-the-run) and pressing `x`, counts as failing.

That last case means a failure in the middle of a fan-out reruns work that already finished. If a script starts A, B, C, and D in that order and B fails, relaunching returns A from cache and runs B, C, and D again.

You can resume a run within the same Claude Code session. What happens to a running workflow when you leave the session depends on how you leave:

* If you [background the session](/docs/en/agent-view#what-carries-over-when-you-background), Claude Code replays the run the same way in the background session and continues it.
* If you exit Claude Code while a workflow is running and [agent view is on](/docs/en/agent-view#from-inside-a-session), the exit dialog offers `Move to background and exit`, which carries the run over the same way. If you choose `Exit and stop tasks` instead, or the option isn't offered, the run stops with the session. Claude Code keeps the run's saved results under that session's directory in `~/.claude/projects/`, so a session you resume with `claude --resume` can replay them when you ask Claude to relaunch the workflow, while a session you start fresh has nothing to replay and starts the workflow over.

### Cost

A workflow spawns many agents, so a single run can use meaningfully more tokens than working through the same task in conversation. Runs count toward your plan's usage and rate limits like any other session.

To gauge the spend before committing to a large task, run the workflow on a small slice first: one directory instead of the whole repo, or a narrow question instead of a broad one. The `/workflows` view shows each agent's token usage as the run progresses, and you can stop the run there at any time, usually without losing completed work. [Resume after a pause](#resume-after-a-pause) covers what a stopped run keeps. The runtime's [agent caps](#behavior-and-limits) limit how many agents a single run can spawn, which bounds the cost of a runaway script. To keep runs to fewer agents, choose the `small` [size guideline](#set-a-size-guideline).

Claude Code also flags a run that grows unusually large. When a workflow schedules more than 25 agents, or its projected token total passes 1.5 million, its progress line in the task panel below the input box shows a `Large workflow` warning. The warning points you to [`/workflows`](#watch-the-run), where you can stop the run.

The warning is advisory: it doesn't pause or limit the run. Two settings change when you see it:

* If you choose a [size guideline](#set-a-size-guideline) yourself, its agent count replaces the 25-agent threshold. The built-in default guideline leaves the threshold at 25.
* Sessions with [ultracode](#let-claude-decide-with-ultracode) on don't show the warning, because turning ultracode on already opts you in to large runs.

Claude Code picks each workflow agent's model in the same [order it uses for subagents](/docs/en/sub-agents#choose-a-model). A model the script names for a stage counts as the per-invocation model in that order. When nothing else assigns one, the agent runs on your session's model.

To control the model cost:

* Check `/model` before a large run if you usually switch to a smaller model for routine work
* Ask Claude to use a smaller model for stages that don't need the strongest one when you describe the task

When your organization's [`availableModels` allowlist](/docs/en/model-config#restrict-model-selection) blocks a model the script requests for an agent, that agent runs on a substituted model instead, following the same [substitution rules as subagents](/docs/en/sub-agents#choose-a-model). The run's progress view in [`/workflows`](#watch-the-run) shows a warning naming both the requested and substituted models.

### Set a size guideline

A size guideline tells Claude how many agents to aim for when it writes a dynamic workflow. Claude Code sends the guideline to Claude as advice, not a cap, so a prompt that calls for a different scale still overrides it. Requires Claude Code v2.1.202 or later.

Each value maps to an agent count:

| Value          | Agent count Claude aims for                         |
| :------------- | :-------------------------------------------------- |
| `unrestricted` | No guideline: Claude sizes the workflow to the task |
| `small`        | Fewer than 5 agents                                 |
| `medium`       | Fewer than 15 agents                                |
| `large`        | Fewer than 50 agents                                |

The default is `medium`. Until you choose a value, the `/config` row shows `medium (default)` and the workflow's `Running in background` line shows `medium size (/config)`. Requires Claude Code v2.1.219 or later; earlier versions default to `unrestricted`.

To change the guideline, pick a value for the Dynamic workflow size setting in `/config`, or run `/config workflowSizeGuideline=small`. On v2.1.219 and later, you can also set the [`workflowSizeGuideline` key](/docs/en/settings-reference#workflowsizeguideline) in any settings file; that value takes precedence over `/config`, and Claude Code hides the `/config` row while a settings file provides one.

Changes take effect on the next prompt. The [runtime agent caps](#behavior-and-limits) still apply regardless of the setting.

### Turn workflows off

Workflows are available in the CLI, the Desktop app, the IDE extensions, [non-interactive mode](/docs/en/headless) with `claude -p`, and the [Agent SDK](/docs/en/agent-sdk/overview). The same disable settings apply on every surface.

To turn workflows off for yourself:

* Toggle Dynamic workflows off in `/config`. Persists across sessions.
* Set `"disableWorkflows": true` in `~/.claude/settings.json`. Persists across sessions.
* Set `CLAUDE_CODE_DISABLE_WORKFLOWS=1`. Read at startup, so it applies wherever you set it.

To turn workflows off for your whole organization, set `"disableWorkflows": true` in [managed settings](/docs/en/server-managed-settings), or use the toggle on the [Claude Code admin settings](https://claude.ai/admin-settings/claude-code) page.

When workflows are disabled, the bundled workflow commands and the `/workflow-authoring` skill are unavailable, the `ultracode` keyword no longer triggers a run, and `ultracode` is removed from the `/effort` menu.

## Core Multi-Agent Commands

| Command | Syntax | Description |
|---------|--------|-------------|
| `/batch` | `/batch <instruction>` | **[Skill]** Orchestrate large-scale changes across a codebase in parallel by decomposing work into 5-30 independent units, each run by a background subagent in an isolated git worktree. |
| `/fork` | `/fork [prompt]` | Copy the current conversation into a new background session and keep working here; pass a prompt for the copy to start working immediately. |
| `/background` | `/background [prompt]` | Detach the current session to run as a background agent and free this terminal; pass a prompt to send one more instruction before detaching. Alias: `/bg` |
| `/subtask` | *(Entry not provided in excerpt)* | Hand a side task to a subagent whose result comes back into this conversation. |
| `/tasks` | *(Entry not provided in excerpt)* | List the current session's background work, including subagents that have finished. |

## Scheduling & Automation

| Command | Syntax | Description |
|---------|--------|-------------|
| `/loop` | `/loop [interval] [prompt]` | **[Skill]** Run a prompt repeatedly while the session stays open; omit interval for self-pacing or prompt for built-in maintenance. Alias: `/proactive` |
| `/goal` | `/goal [condition\|clear]` | Set a goal: Claude keeps working across turns until the condition is met or use `clear` to remove an active goal early. |

## Discovery & Coordination

| Command | Syntax | Description |
|---------|--------|-------------|
| `/deep-research` | `/deep-research <question>` | **[Workflow]** Fan out web searches on a question, fetch and cross-check sources, and synthesize a cited report. |
| `/list-agents` | `/list-agents` | List the subagents, agent team teammates, and other Claude Code sessions Claude can message. Alias: `/peers` |

## CLI Flags for Running Multiple Sessions

| Flag | Syntax | Description |
|------|--------|-------------|
| `--bg`, `--background` | `claude --bg "task"` | Start session as background agent and return immediately. Prints session ID and management commands. Cannot combine with `-p`. |
| `--name`, `-n` | `claude -n "my-feature-work"` | Set display name for session, shown in `/resume` and terminal title. Resume named session with `claude --resume <name>`. |
| `--fork-session` | `claude --resume abc123 --fork-session` | When resuming, create new session ID instead of reusing original (use with `--resume` or `--continue`). |
| `--continue`, `-c` | `claude --continue` | Load most recent conversation in current directory, skipping background sessions and `-p` sessions. |
| `--resume`, `-r` | `claude --resume auth-refactor` | Resume specific session by ID or name, or show interactive picker. Searches current project and other projects on machine. |
| `--agent` | `claude --agent my-custom-agent` | Specify agent for current session (overrides `agent` setting). Combine with `--bg` for specific subagent. |
| `--effort` | `claude --effort high` | Set effort level: `low`, `medium`, `high`, `xhigh`, `max`, or `ultracode`. Overrides settings for this session only. |
| `--settings` | `claude --settings ./settings.json` | Path to settings JSON file or inline JSON string. Overrides same keys in settings files for this session. |
| `--add-dir` | `claude --add-dir ../apps ../lib` | Add additional working directories. Grants file access; persists with `permissions.additionalDirectories` setting. |
| `--channels` | `claude --channels plugin:my-notifier@my-marketplace` | (Research preview) MCP servers whose channel notifications Claude should listen for. Space-separated list. |
| `--cloud` | `claude --cloud "Fix the login bug"` | Create new web session on claude.ai with task description, or queue message to existing session with `-p`. |
| `--restricted` | `claude --restricted -p "query"` | Start in restricted mode. Removes built-in tools for commands/code/WebFetch. Confines file tools to working directories. |
| `--permission-mode` | `claude --permission-mode plan` | Begin in specified mode: `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`, or `manual`. |
| `--output-format` | `claude -p "query" --output-format json` | Specify output for print mode: `text`, `json`, or `stream-json`. |
| `--print`, `-p` | `claude -p "query"` | Print response without interactive mode (for scripting/SDK). |
| `--teammate-mode` | `claude --teammate-mode auto` | Set how agent team teammates display: `in-process` (default), `auto`, `tmux`, or `iterm2`. |
| `--worktree`, `-w` | `claude -w` | (Mentioned in truncated content) Flag for worktree management. |
| `--tmux` | `claude --tmux` | (Mentioned in truncated content) Integration with tmux. |

## Multi-Session Management Subcommands

| Subcommand | Syntax | Description |
|------------|--------|-------------|
| `claude agents` | `claude agents --json` | Open agent view to monitor and dispatch parallel background sessions. `--json` prints active sessions as JSON array for scripting. Supports `--cwd`, `--permission-mode`, `--model`, `--effort`, `--agent`. |
| `claude attach` | `claude attach 7c5dcf5d` | Attach to background session in current terminal by ID. |
| `claude logs` | `claude logs 7c5dcf5d` | Print recent output from background session by ID. |
| `claude stop` | `claude stop 7c5dcf5d` | Stop background session (alias: `claude kill`). |
| `claude respawn` | `claude respawn 7c5dcf5d` | Restart background session with conversation intact. Use `--all` to restart every running session. |
| `claude rm` | `claude rm 7c5dcf5d` | Remove background session from list. Conversation transcript remains available via `claude --resume`. |
| `claude daemon status` | `claude daemon status` | Print background-session supervisor's state, version, socket directory, and worker count. Exits 1 if not running. |
| `claude daemon stop` | `claude daemon stop --any --keep-workers` | Stop supervisor and sessions. `--keep-workers` leaves background sessions running for next supervisor connection. |

## Practical Examples

```bash
# Start multiple background sessions
claude --bg --name "auth-refactor" "Refactor authentication"
claude --bg --name "ui-update" --effort high "Update UI components"

# Monitor all sessions
claude agents --json

# Attach to specific session
claude attach 7c5dcf5d

# View logs from background session
claude logs 7c5dcf5d

# Continue most recent work
claude --continue

# Resume by name
claude --resume auth-refactor

# Fork session (new ID, same conversation)
claude --resume auth-refactor --fork-session

# Run non-interactive with specific settings
claude -p --settings ./prod-settings.json "Deploy to staging"
```


## Frontmatter Fields

Subagent files use YAML frontmatter to configure behavior. Key fields include:

| Field | Required | Purpose |
|-------|----------|---------|
| `name` | Yes | Unique identifier using lowercase letters and hyphens |
| `description` | Yes | When Claude should delegate to this subagent |
| `tools` | No | List of tools the subagent can use; inherits all available tools if omitted |
| `model` | No | Model to use: `sonnet`, `opus`, `haiku`, `fable`, full model ID, or `inherit` |
| `skills` | No | Skills to preload into the subagent's context at startup |
| `mcpServers` | No | MCP servers available to this subagent (name references or inline definitions) |
| `isolation` | No | Set to `worktree` to run in a temporary git worktree with isolated copy of repository |
| `background` | No | Set to `true` to keep subagent in background even when Claude asks for foreground |

Example frontmatter:
```yaml
---
name: code-reviewer
description: Reviews code for quality and best practices
tools: Read, Glob, Grep
model: sonnet
skills: api-conventions
isolation: worktree
---
```

## Subagent Definition Locations

Subagents are stored in different scopes with priority order:

1. **Managed settings** (highest priority) - Deployed by organization administrators
2. **`--agents` CLI flag** - Current session only, JSON format
3. **`.claude/agents/`** - Current project (checked into version control)
4. **`~/.claude/agents/`** - All projects on your machine
5. **Plugin `agents/` directories** (lowest priority) - Installed with plugins

Example file structure:
```markdown
---
name: code-improver
description: Scans files and suggests improvements for readability, performance, and best practices
tools: Read, Grep, Glob
model: sonnet
---

You are a code improvement specialist. For each issue you find, explain
the problem, show the current code, and provide an improved version.
```

## Named Subagents and Messaging

Claude can give a subagent a `name` parameter when spawning it. Named subagents become addressable—Claude can message or resume them after they complete using the `SendMessage` tool.

When Claude spawns a named subagent, it receives an agent ID. After completion, Claude can resume the subagent by:

```text
Continue that code review and now analyze the authorization logic
```

The `SendMessage` tool is used with the agent's ID or name as the `to` field:
- A completed subagent that receives a message auto-resumes in the background
- A subagent at its `maxTurns` limit that returns an agent ID can be resumed
- The built-in Explore and Plan agents don't return agent IDs and can't be resumed

**Important**: As of v2.1.198, `SendMessage` checks that a name still refers to the same agent. If a newer agent reused the name, Claude must use the agent ID instead.

## Foreground vs Background Subagents

**Foreground subagents** block the main conversation until complete. Permission prompts go directly to you.

**Background subagents** run concurrently while you continue working:
- Permission prompts surface in your main session naming the subagent
- Approve to continue, or press Esc to deny that single tool call
- Run with a [smaller built-in tool set](#available-tools)
- Results return to Claude as a completion notification in a later turn

Claude Code decides foreground/background from the first matching condition:

1. If an in-process [agent team](/docs/en/agent-teams) teammate spawned it, runs foreground
2. If `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`, runs foreground
3. If [fork mode](#fork-mode) is on (default in interactive sessions), runs in background
4. If fork mode is off, runs in background by default unless `background: true` in frontmatter keeps it there

You can set `background: true` in frontmatter to keep a subagent in background even when Claude needs results:
```yaml
---
name: long-running-task
background: true
---
```

You can also press **Ctrl+B** to background a running task.

## Fork Mode and `/subtask`

A **fork** is a subagent that inherits your entire current conversation, including system prompt, tools, model, and message history. Use forks for side tasks that need significant context without re-explaining.

**Fork mode** (on by default in interactive sessions) allows Claude to spawn fork subagents via the `fork` subagent type. The fork's tool calls stay out of your conversation; only its final result returns.

Start a fork yourself with `/subtask` followed by your task:
```text
/subtask draft unit tests for the parser changes so far
```

Forks appear in a panel below your prompt and run in the background. When complete, the result arrives as a message in your main conversation.

**Note**: On Claude Code v2.1.161 through v2.1.211, use `/fork` instead of `/subtask`.

### Turn fork mode on or off

Toggle fork mode in settings:
```json
{
  "forkMode": true
}
```

Or via environment variable:
```bash
CLAUDE_CODE_FORK_MODE=1
```

When fork mode is off and you spawn a fork, Claude can't ask for the foreground. When off, [resume subagents](#resume-subagents) via `SendMessage` instead of waiting for them.

---

## Quick Reference: Invoking Subagents

**Natural language** - Name the subagent; Claude decides to delegate:
```text
Use the code-reviewer subagent to look at my changes
```

**@-mention** - Guarantees that subagent runs:
```text
@"code-reviewer (agent)" look at the auth changes
```

**Session-wide** - Entire session uses that subagent:
```bash
claude --agent code-reviewer
```

Or in `.claude/settings.json`:
```json
{
  "agent": "code-reviewer"
}
```


## Monitor Tool
**Purpose**: Watches something in the background and reacts when it changes without pausing conversation.

**Key Uses**:
- Tail log files and flag errors
- Poll PR/CI job status changes
- Watch directory for file changes
- Track long-running script output
- Connect to WebSocket feeds and report messages

**Parameters**:
- `command`: Shell command to run in background
- `ws`: WebSocket source (alternative to command)
  - `url`: WebSocket endpoint (ws:// or wss://)
  - `protocols`: Optional subprotocol names
- `timeout_ms`: Deadline before watch ends
- `persistent`: If set, watch continues past timeout

**Permission**: Yes | Uses same rules as Bash tool

---

## SendMessage
**Purpose**: Sends a message to another agent (teammate, subagent, or other Claude Code session).

**Targets**:
- Agent team teammates
- Subagents (by ID or name)
- Other local Claude Code sessions
- Remote Control sessions on other machines

**Key Parameters**:
- `summary`: Optional 5-10 word preview (auto-generates from first line if omitted)
- Message content for the recipient

**Permission**: No | Requires Claude Code v2.1.224+ for cross-session messaging

---

## Task Tools

### TaskCreate
**Purpose**: Creates a new task in the task list.

**Permission**: No

### TaskGet
**Purpose**: Retrieves full details for a specific task by ID.

**Permission**: No

### TaskList
**Purpose**: Lists all tasks with current status.

**Permission**: No

### TaskUpdate
**Purpose**: Updates task status, dependencies, or details; deletes tasks.

**Permission**: No

**Availability Note**: Not available by default on Opus 4.8+, Sonnet 5+, Fable 5+, Mythos 5+ unless opted in via `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`

---

## Worktree Tools

### EnterWorktree
**Purpose**: Creates isolated git worktree or switches into existing one.

**Parameters**:
- `path`: Optional; switches to existing worktree

**Behavior**:
- Paths under `.claude/worktrees/` don't prompt
- Paths outside require approval
- From within worktree, only `path` form available; target must be under `.claude/worktrees/`

**Permission**: Yes

### ExitWorktree
**Purpose**: Exits worktree session, returns to original directory.

**Permission**: No | Not available to subagents with `isolation: worktree`

---

## Agent Tool
**Purpose**: Spawns subagent with separate context window to handle a task autonomously.

**Key Features**:
- Subagent returns single text result to parent
- Parent doesn't see intermediate tool calls
- With agent teams enabled, `name` parameter can launch teammate instead
- Set `maxTurns` to cap subagent iterations

**Subagent Tool Access**:
- **Neither `tools` nor `disallowedTools` set**: inherits all available subagent tools
- **`tools` only**: gets only listed tools
- **`disallowedTools` only**: gets all parent tools except listed ones
- **Both set**: `disallowedTools` takes precedence

**Permission**: No | Launching doesn't prompt; subagent's tool calls checked against permission rules

---


## Session Managers & Parallel Runners (Orchestration/Fleet Tools)

| Name | URL | Description |
|------|-----|-------------|
| **Orca (Stably)** | https://github.com/stablyai/orca | "Agentic development environment for a fleet of parallel agents" with git worktrees |
| **Multica** | https://github.com/multica-ai/multica | Self-hosted workspace assigning issues to multiple coding agents like teammates |
| **herdr** | https://github.com/herdrdev/herdr | Agent multiplexer coordinating multiple CLI sessions side-by-side in terminal |
| **AionUi** | https://github.com/iOfficeAI/AionUi | Desktop app running 20+ agents around the clock with multi-session management |
| **vibe-kanban** | https://github.com/BloopAI/vibe-kanban | Kanban interface for administering multiple AI coding agents |
| **cmux** | https://github.com/manaflow-ai/cmux | Platform for running multiple coding agents in parallel |
| **Paseo** | https://github.com/getpaseo/paseo | Self-hosted daemon running agents in parallel on your machines |
| **Agent Orchestrator (AO)** | https://github.com/Untrivial-ai/agent-orchestrator | Desktop app supervising multiple agents with git worktree isolation per session |
| **Claude Squad** | https://github.com/smtg-ai/claude-squad | tmux-based harness managing multiple Claude Code sessions side-by-side |
| **agent-of-empires** | https://github.com/njbrake/agent-of-empires | TUI/web UI managing multiple agents from one interface |
| **PATAPIM** | https://patapim.ai | Terminal IDE with 9-terminal grid for parallel agent execution |
| **Even** | https://even.dev | Agent-native desktop workspace running multiple CLI agents in same panes |
| **Unpeel** | https://unpeel.com | Native macOS app for running/remote-controlling multiple CLI agent sessions |

## Orchestrators & Autonomous Loops

| Name | URL | Description |
|------|-----|-------------|
| **DeerFlow** | https://github.com/bytedance/deer-flow | "Long-horizon super-agent harness orchestrating sub-agents" with sandboxed workspaces |
| **Symphony** | https://github.com/openai/symphony | Converts tracker issues into autonomous implementation runs with proof of work |
| **Omnigent** | https://github.com/omnigent-ai/omnigent | Meta-harness giving orchestration layer over multiple agent harnesses |
| **fractal** | https://github.com/plasma-ai/fractal | CLI/TUI orchestrator for hierarchical agent loops with git worktrees |

---

**Note:** This directory was last updated **2026-08-31** according to the source document, making all entries current to that date. The tools emphasize worktree isolation, parallel execution, and durable session management across multiple simultaneous agent instances.


## Key Architecture Features

**Worktree Organization**: "A node iterates toward a goal in its own `git worktree` and spawns child nodes for separable subtasks, so the tree grows to fit the problem rather than a fixed plan."

**Resource Constraints**: Hard caps govern iterations, depth, children count, cost, and time per node, with an operator able to steer or pause execution at any point.

**State Tracking**: "Run metadata (including cost) lands in one local `SQLite` database, which can be interacted with live in a terminal UI."

## https://github.com/omnigent-ai/omnigent

# Omnigent: Meta-Harness for AI Agents

**Core Function**
Omnigent is "an open-source **meta-harness** that gives you a common orchestration layer" over multiple agent platforms. It enables unified control of Claude Code, Codex, Cursor, OpenCode, Hermes, Pi, and custom agents without rewriting code when switching between them.

**Key Capabilities**

- **Multi-agent orchestration**: Run Claude, Codex, Cursor, and other agents in parallel within single sessions
- **Cross-device continuity**: Sessions sync across terminal, browser, phone, and native desktop app
- **Policy enforcement**: Define rules controlling shell access, file modifications, token spending, and approval workflows
- **Sandbox flexibility**: Deploy to Modal, Daytona, Kubernetes, E2B, CoreWeave, or local environments
- **Team collaboration**: Share live sessions, co-drive, fork conversations, and work with teammates

**Technical Configuration**

Agents are defined in YAML files specifying prompts, tools (Python functions, MCP servers), and sub-agents. The system supports four credential types: API keys, subscriptions, gateways (OpenRouter, Ollama), and Databricks workspaces.

**Project Status**

The repository shows active maintenance with 9.7k stars, 1.5k forks, 727 open pull requests, and 3,324 commits on main. It's licensed under Apache 2.0 and requires Python 3.12+.


## Core Architecture

**No LLM in coordination:** The scheduler uses plain Python, making runs reproducible end-to-end. A deterministic task graph replayed today produces yesterday's results.

**Checkable after execution:** Every step gets recorded in a lineage journal. With `BERNSTEIN_AUDIT=1`, an HMAC-chained audit log plus signed receipts enable offline verification—tampered records fail hash validation at the exact divergent step.

**Isolated by design:** Each coding task runs in its own git worktree; artifact-mode tasks get isolated working directories. Agents share only the atomic task backlog by default.

## Claude Code Hook Integration

Add this to `.claude/settings.json` for automatic conflict detection before file writes:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [{ "type": "command", "command": "clash check" }]
      }
    ]
  }
}
```

The hook reads file paths from stdin, checks for conflicts across worktrees, and returns an "ask" decision if conflicts exist.

## Key Architecture Components

**Executor/Supervisor Split:**
The system separates implementation from review. Users can choose the executor CLI (Claude, Codex, GLM, Kimi, or Grok) and model independently from the supervisor, which defaults to Claude but can be configured separately.

**Configuration Elements:**
- Task YAML files define goals, acceptance criteria, scope, and executor overrides
- Quality profiles capture repository review policy, required checks, and pass criteria
- Environment profiles establish runtime defaults for commands, executor settings, and PR behavior

**Workflow Loop:**
The process moves through isolated git worktrees where executors implement changes, then supervisors review against acceptance criteria and quality policy. Failed attempts trigger "focused retries" that preserve verified passes while focusing on unresolved work.