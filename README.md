# agent-fleet.nvim

Run a fleet of coding agents from Neovim — [pi](https://pi.dev), Claude Code, or
any agent CLI — each in its own native terminal, listed and switchable from a
clean UI.

Git isolation (worktrees) is left to the agent itself: a well-instructed agent
already knows whether a task needs a worktree and what to name it, so
agent-fleet doesn't create them — it just launches agents.

## Why

Built between [pi-agent-board](https://github.com/rutvikchandla3/pi-agent-board)
and orchestrators like autobahn — but with one hard rule:

> **The agent runs as its real CLI, in a native nvim terminal. Nothing
> reimplements the agent's UI.**

This matters because agents like `pi` **render inline** (no alternate screen), so
in a native nvim terminal the whole conversation stays in the buffer. Press
`<C-\><C-n>` and you scroll, search and yank the entire transcript **with your
own nvim keybindings** — the thing PTY-attach dashboards take away from you.

## Status

Built incrementally, feature by feature. Done so far:

- **[x] Launch** — `:Agent [type]` opens an agent CLI in a terminal in the current window.

Roadmap:

- **[ ] Persistence & resume** — the data layer + resume mechanism. A roster on
  disk (`id → {type, name, cwd, …}`); `:Agent` assigns a `--session-id <uuid>`
  at launch and records it. Resuming a session = relaunching `pi --session-id
  <id>` in its cwd. No UI yet; the foundation List & switch builds on.
- **[ ] List & switch** — the board UI on top: `:Agents` picker showing the
  agents of the **current directory** (live ones in this nvim + this cwd's
  sessions on disk) with status; select to switch (focus the live buffer) or
  resume (relaunch by session id). Plus `:AgentDone` / `:AgentArchive` (soft
  archive — never deletes a session file).
- **[ ] Scope config** — a `scope = "cwd" | "git-root" | "all"` option (default
  `"cwd"`) controlling which agents the board lists, plus a `:Agents!` bang to
  show all directories at once.
- **[ ] Auto-restore** — optional `VimEnter` behavior to relaunch the agents
  that were live when you quit. Off by default (manual resume from the board is
  the better default); a config flag on top of the roster.
- **[ ] Live agent state** — derive `working` / `needs_input` / `idle` for live
  agents by tailing their session `.jsonl` (v1 shows live = `running`, dead =
  `unknown`). Later: derive a final state for dead sessions too.
- **[ ] UI board** — a dedicated board buffer with per-row keybindings
  (`<CR>` switch, `d` archive, `D` done) inspired by pi-agent-board, replacing
  the `vim.ui.select` picker.
- **[ ] Detached background mode (opt-in)** — when enabled, agents run under a
  PTY detacher (`abduco`/`dtach`) so closing nvim detaches them (they keep
  working) and reopening re-attaches them into buffers. Off by default to keep
  the pure-native terminal behavior; full transcript still comes from the
  session file.
- **[ ] (later) Worktree-aware** — agent-fleet never *creates* worktrees (that's
  the agent's job), but could later *discover* them via `git worktree list` to
  show in the picker and offer cleanup. Low priority.
- **[ ] Claude & other agents resume** — extend persistence/resume beyond pi
  (`claude --resume`), incl. discovering their sessions. pi-only at first.
- **[ ] Lifecycle** — rename, stop, land changes.

## Usage

```vim
:Agent           " launch the default agent in the current working directory
:Agent claude    " launch a specific configured agent (Tab-completes)
```

Inside an agent terminal: `<C-\><C-n>` to enter Normal mode, then move / scroll /
yank with your usual nvim keys. `i` / `a` to type to the agent again.

## Configuration

```lua
require("agent-fleet").setup({
  default_agent = "pi", -- which agent `:Agent` launches with no argument
  agents = {            -- registry of agents: key -> { cmd = "<command>" }
    pi = { cmd = "pi" },
    claude = { cmd = "claude" },
  },
  window = "enew",      -- where the agent terminal opens (see below)
  start_insert = true,  -- drop straight into terminal insert mode
})
```

Add any agent CLI by giving it a key and a command:

```lua
agents = {
  pi = { cmd = "pi" },
  claude = { cmd = "claude" },
  aider = { cmd = "aider" },
  codex = { cmd = "codex" },
}
```

`:Agent <key>` then launches it, with Tab-completion over the configured keys.

`cmd` is split on spaces into an argv list and executed directly **without a
shell**, so each token becomes a separate argument — no quoting, pipes, or
`VAR=val` env prefixes. If you need shell features, point `cmd` at a wrapper
script.

### `window` — where the agent opens

`window` is run as a plain Ex command right before the buffer becomes a
terminal, so any window-opening command works. Common choices:

| Value             | Result                          |
| ----------------- | ------------------------------- |
| `"enew"`          | current window (default)        |
| `"botright vnew"` | new vertical split on the right |
| `"topleft vnew"`  | new vertical split on the left  |
| `"topleft new"`   | new horizontal split on top     |
| `"botright new"`  | new horizontal split on the bottom |
| `"tabnew"`        | new tab                         |

Power users can pass any Ex command, e.g. `window = "botright 80vnew"` for a
fixed-width split.

| Option          | Default | Description                                       |
| --------------- | ------- | ------------------------------------------------- |
| `default_agent` | `"pi"`  | Agent launched by `:Agent` with no argument.      |
| `agents`        | pi, claude | Registry of agents (`key -> { cmd }`).         |
| `window`        | `"enew"`| Ex command that opens the agent window.           |
| `start_insert`  | `true`  | Enter terminal insert mode after launching.       |

> Backward compat: a top-level `pi_cmd = "..."` still works and seeds the `pi`
> agent's command.
