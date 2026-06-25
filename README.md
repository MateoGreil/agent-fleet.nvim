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
  pi_cmd = "pi",       -- command used to launch a pi agent
  window = "enew",     -- where the agent terminal opens (see below)
  start_insert = true, -- drop straight into terminal insert mode
})
```

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

| Option         | Default | Description                                  |
| -------------- | ------- | -------------------------------------------- |
| `pi_cmd`       | `"pi"`  | Command launched in the terminal.            |
| `window`       | `"enew"`| Ex command that opens the agent window.      |
| `start_insert` | `true`  | Enter terminal insert mode after launching.  |
