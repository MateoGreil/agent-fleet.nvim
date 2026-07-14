# Roadmap

agent-fleet is built incrementally, feature by feature. This file tracks what
ships and what's planned. For the user-facing docs, see [README.md](README.md).

## Done

- **[x] Launch** — `:Agent [prompt]` launches the default agent in a terminal in
  the current window; any arguments become the agent's initial prompt. With no
  arguments it asks for one via a `New agent prompt:` input (the same as the
  board's `i` key). Agents are always auto-named.
- **[x] Persistence & resume** — a roster on disk (`id → {type, name, cwd, …}`);
  `:Agent` assigns each pi agent a `--session-id <uuid>` + `--name` at launch and
  records it. `:AgentResume` reopens a past agent of the current directory —
  focusing its live buffer if still running, else relaunching `pi --session
  <id>` in its original cwd (never touching the session file).
- **[x] List & switch** — `:Agents` lists the agents of the **current directory**
  (live ones in this nvim merged with this cwd's pi sessions on disk, deduped by
  session id) and switches to the chosen one — focus if live, else resume.
  `:AgentDone` toggles an agent done / not done (✓); `:AgentArchive` toggles archive (hidden
  by default). Soft archive only — never deletes a session file. `:AgentRename`
  renames an agent (the current agent's buffer, or a picked one). `:AgentDone` /
  `:AgentArchive` also act on the current agent's buffer, closing (killing) its
  terminal when live. Each row shows a derived state
  (`idle`/`working`/`stopped`/`error`/`new`/`unknown` — `unknown` meaning the
  state is older than the bounded tail read — tailed from the session `.jsonl`)
  and a relative last-activity time (`now`/`5m`/`3h`/`2d`/`3w`); the board is
  sorted by most-recently-active first (within the live / done / archived
  grouping).
- **[x] Live agent state** — derive `idle` / `working` / `stopped` / `error` /
  `new` / `unknown` (state older than the bounded tail read) for every agent by
  tailing its session `.jsonl` (tail-bounded read, no whole-file scan), shown
  alongside a relative last-activity time, and the board is re-sorted by
  most-recently-active.
- **[x] UI board** — `:AgentsBoard` opens a dedicated, live board buffer
  listing this directory's agents in lifecycle sections (running / idle /
  done / archived) with colored state, names and relative activity times.
  Per-row keys: `<CR>` switch/open, `d` done, `x` archive, `r` rename, `s`
  stop (kill the live terminal without filing it done), `a` launch, `i`
  launch with a typed prompt, `A` toggle archived, `R`/`gr` refresh. It
  re-renders on a timer while visible and reacts to agents exiting. The
  `vim.ui.select` pickers (`:Agents`, `:AgentDone`, …) remain unchanged.
- **[x] Background auto-naming (opt-in)** — a pi agent launched with an initial
  prompt (board `i`, `:Agent <prompt>`) but **without** a name can be renamed
  automatically: the plugin hands that prompt to a lightweight one-shot `pi`
  namer to summarize it, then renames the agent (still flagged as
  machine-named, so a later manual `:AgentRename` wins). Even with LLM
  auto-naming off, an agent launched with a prompt takes its default name from
  the first line of that prompt (char-aware truncated); only an agent launched
  without a prompt keeps the numbered `<kind>-<n>` default. Off by default;
  enable the LLM namer with `auto_name.enabled = true` and set
  `auto_name.model`.
- **[x] Claude Code as a first-class fleet agent** — `:Agents`, `:AgentsBoard`,
  persistence, resume, per-type launch and live state all work for Claude Code.
  Delivered with a full-parity backend (`backends/claude.lua`) that discovers
  Claude's on-disk sessions (`~/.claude/projects/<slug>/<uuid>.jsonl`), derives
  live state (`idle`/`working`/`error`/`unknown`) via bounded backward tail
  reads, and integrates with resume. Also includes a `generic` backend tier for
  CLIs that don't provide session files — they launch but don't appear on the
  board after exit.
- **[x] Send visual/line selection to an agent** — `:AgentSend` is range-aware:
  in normal mode it takes the current line, in visual mode (`:'<,'>AgentSend`)
  it takes the selected range. It builds a `path:line` (or `path:line1-line2`)
  reference — relative to the target agent's cwd when the file lives inside
  it, else absolute — and sends **only that reference, never the file
  content**, into the target agent's terminal input with a single trailing
  space and no newline (it never auto-submits). It never moves focus, so you
  can fire `:AgentSend` several times from different spots to stack up
  references and then switch to the agent yourself to type a question.
  Target resolution: the last-focused live agent → the single live agent when
  exactly one is running → `vim.ui.select` to pick when two or more are live
  → else it notifies and refuses when no agent is running.

## Planned

- **[ ] Pick the agent type at launch (opt-in)** — let the user choose *which*
  declared agent (`pi`, `claude`, …) `:Agent` and the board's `a` / `i` keys
  launch, instead of always using `default_agent`. Today the agent type isn't
  selectable from the commands — all of `:Agent`'s arguments become the new
  agent's name, and launching a non-default agent requires the
  `launch({ agent = … })` Lua API. Add a config flag (e.g. `pick_agent =
  true`, off by default) that inserts a `vim.ui.select` step before launch;
  when off, behavior is unchanged. The picker must **only** appear when two or
  more agents are declared — with a single declared agent there's nothing to
  choose, so the step is skipped entirely (no extra prompt on launch).
- **[ ] Visually distinguish agent type in `:Agents` / `:AgentsBoard`** — show
  each row's type (`pi` / `claude` / …) in the picker and the board so a mixed
  fleet is readable at a glance (a column or a colored badge; the row already
  carries `type`). Surface it **only when more than one type is present** in
  the listing — when every agent is the same type there's nothing to
  disambiguate, so no type marker is shown.
- **[ ] Scope config** — a `scope = "cwd" | "git-root" | "all"` option (default
  `"cwd"`) controlling which agents the board lists, plus a `:Agents!` bang to
  show all directories at once.
- **[ ] Auto-restore** — optional `VimEnter` behavior to relaunch the agents
  that were live when you quit. Off by default (manual resume from the board is
  the better default); a config flag on top of the roster.
- **[ ] Per-row preview** — show each agent's last assistant message (or a short
  snippet of it) inline in the board / a preview pane. Deferred.
- **[ ] Persistent board buffer (return with `<C-o>`)** — today the board is
  `bufhidden=wipe`, so pressing `<CR>` to enter an agent destroys it and
  `<C-o>` can't jump back (you reopen with `:AgentsBoard` / `<leader>ab`).
  Switch it to `bufhidden=hide` so the board persists and `<C-o>` / `<C-^>`
  return to it; reuse the hidden buffer on reopen, and pause/resume the
  refresh timer when the board is hidden/shown (the teardown currently keys
  off `BufWipeout`).
- **[ ] In-editor control bridge (agent ↔ host nvim)** — let an agent know it
  runs inside the fleet and drive its host nvim. The back-channel is free:
  nvim already exports `$NVIM` (its RPC socket) into every terminal job, so a
  child can reach the parent (verified: a child can open splits, set buffer
  lines, resize, echo — any `nvim_*` call). Two pieces to add: (1) **identity**
  — pass `env = { AGENT_FLEET, AGENT_FLEET_ID, AGENT_FLEET_NAME,
  AGENT_FLEET_BUFNR }` in `spawn()`'s `jobstart` so the agent detects it's in
  the fleet and knows which agent/buffer it is (`$NVIM` is already inherited);
  (2) **a curated bridge** — a Lua module + thin CLI wrapper exposing a fixed,
  safe verb set (`notify`, `open_file`, `show_float`, `switch_buffer`,
  `resize`, `set_lines`) instead of handing the agent raw `nvim_exec_lua` over
  the host editor. The bridge maps a connection back to its agent via the
  `vim.b[bufnr].agent_fleet` metadata already set at launch, and refuses
  out-of-scope calls. Ship the agent-facing protocol as a doc/skill. Needs a
  design pass on the verb surface and security model before implementation.
- **[ ] Agent-side nvim RPC helper** — complement the in-editor control bridge
  above with the mirror direction made easy from the *agent's* side: since
  `$NVIM` is already inherited by every spawned terminal job, ship a small
  helper (Lua snippet / CLI one-liner) the agent can call to talk back to its
  host nvim over that RPC socket (`nvim --server $NVIM --remote-expr` /
  `--remote-send`, or the curated bridge verbs once built) without hand-rolling
  the msgpack-rpc call itself each time. Document the socket + verb set as part
  of the same agent-facing skill/doc as the control bridge.
- **[ ] Review an agent's changes and hand the review back (proposal)** — review
  the code an agent produced, right from the fleet, then feed that review back to
  the same agent in one step. Idea: shell out to a code-review TUI —
  [`tuicr`](https://github.com/agavra/tuicr), a vim-keybound, GitHub-style
  continuous-diff reviewer purpose-built for AI-generated diffs (line/range/file
  comments classified `issue`/`suggestion`/`note`/`praise`, review state
  persisted across sessions) — launched as its own fleet buffer over the
  reviewed agent's working tree / branch. Its markdown/clipboard export is
  exactly the "share it back" payload: pipe that structured review straight into
  the reviewed agent's live REPL (reusing the `:AgentSend` plumbing above) so a
  review round-trips to the agent with no copy-paste. Still just a proposal — the
  review tool (tuicr vs. alternatives), how we pin the reviewer to the right
  agent's diff, and the hand-back UX all need a design pass when we get to it.
- **[ ] Detached background mode (opt-in)** — when enabled, agents run under a
  PTY detacher (`abduco`/`dtach`) so closing nvim detaches them (they keep
  working) and reopening re-attaches them into buffers. Off by default to keep
  the pure-native terminal behavior; full transcript still comes from the
  session file.
- **[ ] (later) Worktree-aware** — agent-fleet never *creates* worktrees (that's
  the agent's job), but could later *discover* them via `git worktree list` to
  show in the picker and offer cleanup. Low priority.
- **[ ] Lifecycle** — stop, land changes.
- **[ ] :AgentAsk — throwaway agent for a one-off question** — spin up a
  disposable agent seeded with the current selection (as a reference or its
  raw content) plus a typed question, to get an answer about that one specific
  thing — a separate flow from `:AgentSend`'s "stack references into a running
  agent" model. Once `:AgentAsk` exists, `:AgentSend` can fall back to
  launching one via `:AgentAsk` when no agent is running, instead of refusing.
