# agent-fleet.nvim

Run a fleet of coding agents from Neovim — [pi](https://pi.dev), Claude Code, or
any agent CLI — each in its own native terminal, launched in its own git
worktree, listed and switchable from a clean UI.

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

- **[ ] Worktrees** — one git worktree (new branch) per agent.
- **[ ] Persistence & resume** — persist agent metadata (type, name, worktree,
  session id) so quitting nvim and coming back relaunches each agent resuming
  its session (`pi --session <id>`, `claude --resume`).
- **[ ] List & switch** — picker of running agents with status.
- **[ ] UI** — a nice board view (inspired by pi-agent-board).
- **[ ] Lifecycle** — rename, stop, clean up worktree, land changes.

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
