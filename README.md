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

- **[x] Launch** — `:Agent [name]` launches the default agent in a terminal in
  the current window; any arguments become the agent's name (auto-named when
  omitted).
- **[x] Persistence & resume** — a roster on disk (`id → {type, name, cwd, …}`);
  `:Agent` assigns each pi agent a `--session-id <uuid>` + `--name` at launch and
  records it. `:AgentResume` reopens a past agent of the current directory —
  focusing its live buffer if still running, else relaunching `pi --session
  <id>` in its original cwd (never touching the session file).
- **[x] List & switch** — `:Agents` lists the agents of the **current directory**
  (live ones in this nvim merged with this cwd's pi sessions on disk, deduped by
  session id) and switches to the chosen one — focus if live, else resume.
  `:AgentDone` marks an agent done (✓); `:AgentArchive` toggles archive (hidden
  by default). Soft archive only — never deletes a session file. `:AgentRename`
  renames an agent (the current agent's buffer, or a picked one). `:AgentDone` /
  `:AgentArchive` also act on the current agent's buffer, closing (killing) its
  terminal when live. Status is just live vs not for now (rich
  `working`/`needs_input` is the next item).

Roadmap:

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
- **[ ] Claude Code as a first-class fleet agent** — make `:Agents`,
  persistence, resume and per-type launch work for Claude (and other agents),
  not just pi. Today only pi is fully supported end-to-end.
- **[ ] Claude & other agents resume** — extend persistence/resume beyond pi
  (`claude --resume`), incl. discovering their sessions. pi-only at first.
- **[ ] Lifecycle** — stop, land changes.

## Usage

```vim
:Agent           " launch the default agent (auto-named) in the cwd
:Agent fix auth  " launch the default agent named "fix auth"
:AgentResume     " reopen a past agent of this directory (focus if live, else resume)
:Agents          " list & switch agents of this directory (focus if live, else resume)
:AgentDone       " mark an agent done (✓)
:AgentArchive    " archive / unarchive an agent (hidden from :Agents by default)
:AgentRename foo " rename the current agent (or pick one) to "foo"
:AgentRename     " rename via a prompt (current agent, or pick one)
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

`default_agent` chooses which of these `:Agent` launches; the `agents` registry
is kept for future multi-agent support, but the agent type is no longer a
command argument (all of `:Agent`'s arguments become the new agent's name).

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
