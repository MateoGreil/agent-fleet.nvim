# agent-fleet.nvim

Run a fleet of coding agents from Neovim — [pi](https://pi.dev), Claude Code, or
any agent CLI — each in its own **native terminal**, listed and switchable from a
clean board.

```
  running ──────────────────────────────────
   ● working   fix-auth-redirect          now
   ● idle      refactor-roster-dedup        5m
  done ─────────────────────────────────────
   ✓ stopped   bump-golangci-lint           2h
  archived ─────────────────────────────────
```

No PTY-attach dashboard, no reimplemented agent UI. The agent runs as its real
CLI in a real nvim terminal — so the whole conversation lives in a buffer you
can scroll, search and yank with your own keybindings.

## Features

- **Launch** agents into a native terminal, with an optional initial prompt.
- **Persist & resume** — a roster on disk; reopen a past agent (focus it if
  live, else relaunch `pi --session <id>` in its original cwd).
- **List & switch** the agents of the current directory, live ones merged with
  on-disk pi sessions and deduped.
- **Live board** (`:AgentsBoard`) — a dedicated buffer grouping agents into
  running / idle / done / archived sections, with colored state and relative
  last-activity times, refreshing on a timer.
- **Lifecycle** — mark done, archive (soft, never deletes a session), rename,
  stop; bulk actions over a visual selection.
- **Background auto-naming** (opt-in) — name an agent from its launch prompt,
  optionally via a one-shot LLM namer.

See [ROADMAP.md](ROADMAP.md) for what's shipped and what's planned. Today **pi**
is supported end-to-end; other CLIs launch but aren't yet persisted/resumed.

## Requirements

- Neovim 0.9+
- At least one agent CLI on your `PATH` ([pi](https://pi.dev), `claude`, …)

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "MateoGreil/agent-fleet.nvim",
  config = function()
    require("agent-fleet").setup()
  end,
}
```

With [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use({
  "MateoGreil/agent-fleet.nvim",
  config = function()
    require("agent-fleet").setup()
  end,
})
```

`setup()` is required (it registers defaults). Pass a table to override any
option — see [Configuration](#configuration).

## Usage

```vim
:Agent           " launch the default agent, prompting for an initial message (like the board's i)
:Agent fix auth  " launch the default agent with "fix auth" as the initial prompt
:AgentResume     " reopen a past agent of this directory (focus if live, else resume)
:Agents          " list & switch agents of this directory (focus if live, else resume)
:AgentsBoard     " open the live board buffer (sections, colors, per-row keymaps)
:AgentDone       " mark an agent done (✓)
:AgentArchive    " archive / unarchive an agent (hidden from :Agents by default)
:AgentRename foo " rename the current agent (or pick one) to "foo"
:AgentRename     " rename via a prompt (current agent, or pick one)
```

Inside an agent terminal: `<C-\><C-n>` to enter Normal mode, then move / scroll /
yank with your usual nvim keys. `i` / `a` to type to the agent again.

### The board (`:AgentsBoard`)

A dedicated, non-terminal buffer that opens in the current window and lists
this directory's agents in lifecycle sections — **running**, **idle**, **done**,
and (when toggled) **archived** — each row showing a live/dead marker, the
derived state, the name, and a relative last-activity time. It re-renders on a
timer while visible and reacts to agents exiting. Move with your normal nvim
keys (`j`/`k`/`/`/`gg`); the per-row actions are:

| Key | Action |
| --- | ------ |
| `<CR>` | switch to the agent under the cursor (focus its terminal if live, else resume `pi --session`) |
| `d` | mark done (✓) |
| `x` | archive / unarchive |
| `r` | rename (prompt) |
| `s` | stop — kill the live terminal without marking it done (still resumable) |
| `a` | launch a new agent |
| `i` | type a prompt, then launch a new agent started with it |
| `A` | toggle the archived section |
| `R` / `gr` | refresh now |

Switching, `a` and `i` hand the board's window to the agent (the board buffer
is wiped; reopen with `:AgentsBoard`). Action keys are no-ops on section
headers. `d`, `x` and `s` also work over a visual line selection (`V`): select a
span of rows and the action applies to every agent in it at once. There is
intentionally no `q` binding — leave the board with your usual buffer navigation.

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
  board = {             -- the :AgentsBoard buffer
    refresh_ms = 2000,  -- how often the open board re-renders
  },
  auto_name = {         -- background auto-naming (off by default; see below)
    enabled = false,
    model = nil,        -- e.g. "openai/gpt-4o-mini"; required to do anything
  },
})
```

| Option          | Default | Description                                       |
| --------------- | ------- | ------------------------------------------------- |
| `default_agent` | `"pi"`  | Agent launched by `:Agent` with no argument.      |
| `agents`        | pi, claude | Registry of agents (`key -> { cmd }`).         |
| `window`        | `"enew"`| Ex command that opens the agent window.           |
| `start_insert`  | `true`  | Enter terminal insert mode after launching.       |
| `board.refresh_ms` | `2000` | How often (ms) the open `:AgentsBoard` re-renders. |

### Registering agents

> **pi only, for now.** Persistence, resume and board listing are wired for
> `pi` end-to-end. You can register another CLI and it will *launch* in a
> terminal, but without pi's session integration it won't be persisted,
> resumed, or shown on the board once it exits. Full multi-agent support is on
> the [roadmap](ROADMAP.md).

The `agents` registry maps a key to a command:

```lua
agents = {
  pi = { cmd = "pi" },
  claude = { cmd = "claude" },
}
```

`default_agent` chooses which of these `:Agent` launches; the agent type is not
a command argument (all of `:Agent`'s arguments become the new agent's name).

`cmd` is split on spaces into an argv list and executed directly **without a
shell**, so each token becomes a separate argument — no quoting, pipes, or
`VAR=val` env prefixes. If you need shell features, point `cmd` at a wrapper
script.

> Backward compat: a top-level `pi_cmd = "..."` still works and seeds the `pi`
> agent's command.

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

### `auto_name` — background auto-naming

When a **pi** agent is launched with an initial prompt but without a name (board
`i`, or `:Agent <prompt>`), the plugin can rename it from that prompt: it runs a
lightweight one-shot `pi` namer (no tools, no session, no extensions) on the
prompt text, sanitizes the reply to a short name, and applies it. There is no
polling — the prompt we launched with is used directly. The agent stays
machine-named, so a manual `:AgentRename` always takes precedence and is never
overwritten.

Independently of this LLM namer, an agent launched with a prompt but no name
already gets a sensible default: the first line of the prompt (char-aware
truncated to 40 chars), instead of the numbered `<kind>-<n>` name. An agent
launched without a prompt still falls back to `<kind>-<n>`.

The LLM namer is **OFF by default** and does nothing unless you both set
`auto_name.enabled = true` **and** provide a `model`.

```lua
auto_name = {
  enabled = false,        -- master switch
  model = nil,            -- model the namer runs with (required, e.g. "openai/gpt-4o-mini")
  thinking = "off",       -- pi --thinking value for the namer
  namer_timeout_ms = 30000,  -- kill the namer subprocess after this long
  max_chars = 2000,          -- cap the prompt text sent to the namer
}
```

| Option             | Default   | Description                                              |
| ------------------ | --------- | -------------------------------------------------------- |
| `enabled`          | `false`   | Master switch for background auto-naming.                |
| `model`            | `nil`     | Model the one-shot namer runs with. Required.            |
| `thinking`         | `"off"`   | `pi --thinking` value for the namer.                     |
| `namer_timeout_ms` | `30000`   | Kill the namer subprocess after this long.               |
| `max_chars`        | `2000`    | Cap on the prompt text sent to the namer.                |

The namer is the only subprocess agent-fleet spawns itself; it runs via
`jobstart` with an argv list (no shell), and it never passes `--name` or touches
the session file.

### Board highlight groups

The board defines these highlight groups, each linked to a standard group by
default so it follows your colourscheme; override any with
`vim.api.nvim_set_hl(0, "<group>", { … })`:

| Group | Default link | Used for |
| ----- | ------------ | -------- |
| `AgentFleetWorking` | `DiagnosticInfo` | a working agent's state |
| `AgentFleetIdle` | `Normal` | an idle agent's state |
| `AgentFleetStopped` | `Comment` | a stopped agent's state |
| `AgentFleetError` | `DiagnosticError` | an errored agent's state |
| `AgentFleetNew` | `DiagnosticHint` | a brand-new agent's state |
| `AgentFleetUnknown` | `NonText` | state older than the tail read |
| `AgentFleetArchived` | `Comment` | archived rows (dimmed) |
| `AgentFleetHeader` | `Title` | section headers and the empty-state title |
| `AgentFleetTime` | `Comment` | the relative last-activity column |
