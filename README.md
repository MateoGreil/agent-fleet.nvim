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
  terminal when live. Each row shows a derived state
  (`idle`/`working`/`stopped`/`error`/`new`/`unknown` — `unknown` meaning the
  state is older than the bounded tail read — tailed from the session `.jsonl`)
  and a relative last-activity time (`now`/`5m`/`3h`/`2d`/`3w`); the board is
  sorted by most-recently-active first (within the live / done / archived
  grouping).
- **[x] Background auto-naming (opt-in)** — a pi agent launched **without** a
  name can be renamed automatically in the background: the plugin polls the
  session `.jsonl` until the first user message lands, asks a lightweight
  one-shot `pi` namer to summarize it, and renames the agent (still flagged as
  machine-named, so a later manual `:AgentRename` wins). Off by default; enable
  with `auto_name.enabled = true` and set `auto_name.model`.

Roadmap:

- **[ ] Scope config** — a `scope = "cwd" | "git-root" | "all"` option (default
  `"cwd"`) controlling which agents the board lists, plus a `:Agents!` bang to
  show all directories at once.
- **[ ] Auto-restore** — optional `VimEnter` behavior to relaunch the agents
  that were live when you quit. Off by default (manual resume from the board is
  the better default); a config flag on top of the roster.
- **[x] Live agent state** — derive `idle` / `working` / `stopped` / `error` /
  `new` / `unknown` (state older than the bounded tail read) for every agent by
  tailing its session `.jsonl` (tail-bounded read, no whole-file scan), shown
  alongside a relative last-activity time, and the board is re-sorted by
  most-recently-active.
- **[ ] Per-row preview** — show each agent's last assistant message (or a short
  snippet of it) inline in the board / a preview pane. Deferred.
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
  auto_name = {         -- background auto-naming (off by default; see below)
    enabled = false,
    model = nil,        -- e.g. "openai/gpt-4o-mini"; required to do anything
  },
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

### `auto_name` — background auto-naming

When a **pi** agent is launched without a name (`:Agent` with no argument), the
plugin can rename it in the background once you've sent your first message: it
polls the session `.jsonl` until the first user message appears, runs a
lightweight one-shot `pi` namer (no tools, no session, no extensions) on that
text, sanitizes the reply to a short name, and applies it. The agent stays
machine-named, so a manual `:AgentRename` always takes precedence and is never
overwritten.

It is **OFF by default** and does nothing unless you both set
`auto_name.enabled = true` **and** provide a `model`.

```lua
auto_name = {
  enabled = false,        -- master switch
  model = nil,            -- model the namer runs with (required, e.g. "openai/gpt-4o-mini")
  thinking = "off",       -- pi --thinking value for the namer
  poll_interval_ms = 3000,   -- how often to poll the session file for the first user message
  poll_timeout_ms = 120000,  -- give up polling after this long (keeps the default name)
  namer_timeout_ms = 30000,  -- kill the namer subprocess after this long
  max_chars = 2000,          -- cap the prompt text sent to the namer
}
```

| Option             | Default   | Description                                              |
| ------------------ | --------- | -------------------------------------------------------- |
| `enabled`          | `false`   | Master switch for background auto-naming.                |
| `model`            | `nil`     | Model the one-shot namer runs with. Required.            |
| `thinking`         | `"off"`   | `pi --thinking` value for the namer.                     |
| `poll_interval_ms` | `3000`    | Poll cadence for the first user message.                 |
| `poll_timeout_ms`  | `120000`  | Stop polling after this long (keeps the default name).   |
| `namer_timeout_ms` | `30000`   | Kill the namer subprocess after this long.               |
| `max_chars`        | `2000`    | Cap on the prompt text sent to the namer.                |

The namer is the only subprocess agent-fleet spawns itself; it runs via
`jobstart` with an argv list (no shell), and it never passes `--name` or touches
the session file.
