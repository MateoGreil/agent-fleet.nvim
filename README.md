# pi-fleet.nvim

Run a fleet of [pi](https://pi.dev) coding agents from Neovim — each in its own
native terminal, launched in its own git worktree, listed and switchable from a
clean UI.

## Why

Built between [pi-agent-board](https://github.com/rutvikchandla3/pi-agent-board)
and orchestrators like autobahn — but with one hard rule:

> **The agent runs as the real `pi`, in a native nvim terminal. Nothing
> reimplements pi's UI.**

This matters because **pi renders inline** (no alternate screen), so in a native
nvim terminal the whole conversation stays in the buffer. Press `<C-\><C-n>` and
you scroll, search and yank the entire transcript **with your own nvim
keybindings** — the thing PTY-attach dashboards take away from you.

## Status

Built incrementally, feature by feature. Done so far:

- **[x] Launch** — `:PiAgent [name]` opens the real `pi` in a terminal in the current window.

Roadmap:

- **[ ] Worktrees** — one git worktree (new branch) per agent.
- **[ ] List & switch** — picker of running agents with status.
- **[ ] UI** — a nice board view (inspired by pi-agent-board).
- **[ ] Lifecycle** — rename, stop, clean up worktree, land changes.

## Usage

```vim
:PiAgent           " launch an agent in the current working directory
:PiAgent backend   " launch a named agent
```

Inside an agent terminal: `<C-\><C-n>` to enter Normal mode, then move / scroll /
yank with your usual nvim keys. `i` / `a` to type to pi again.

## Configuration

```lua
require("pi-fleet").setup({
  pi_cmd = "pi",
  window = "enew", -- "botright vnew" for a vertical split instead
  start_insert = true,
})
```
