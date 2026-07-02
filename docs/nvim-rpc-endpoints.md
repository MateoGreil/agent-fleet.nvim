# Neovim RPC endpoints (control-bridge capability surface)

Every terminal job nvim spawns inherits `$NVIM`, the RPC socket of the host
editor. A child process (an agent launched by the fleet) can connect to that
socket and call the Neovim **MessagePack-RPC API** — the same API GUIs and
plugins use. This document is the exhaustive reference of **what that API can
do**: every non-deprecated endpoint the running nvim exposes, with its
signature and a one-line description.

This is the **raw capability surface**, not the bridge. The planned in-editor
control bridge (see [ROADMAP.md](../ROADMAP.md)) will expose only a small,
curated allowlist of verbs (`notify`, `open_file`, `show_float`,
`switch_buffer`, `resize`, `set_lines`) that wrap a safe subset of these
endpoints and scope every call to the calling agent. Nothing here is exposed
to agents yet — this file exists to inform the design pass on the verb surface
and security model.

> ⚠️ Security note: a handful of these endpoints (`nvim_exec_lua`,
> `nvim_command`, `nvim_cmd`, `nvim_exec2`, `nvim_eval`, `nvim_call_function`,
> `nvim_call_dict_function`, `nvim_buf_call`, `nvim_win_call`) execute
> arbitrary Lua/Vimscript/Ex, and several more accept callbacks or spawn
> processes. Handed to a child raw, they are equivalent to arbitrary shell
> execution on the host with the user's privileges. The bridge must never
> expose these directly.

## Source & regeneration

- Generated from the **running** nvim instance, so it always matches the
  installed version — here **NVIM v0.12.3**.
- Endpoint list: `vim.fn.api_info().functions`, filtered to non-deprecated.
- Descriptions/signatures: nvim's own meta file
  (`$VIMRUNTIME/lua/vim/_meta/api.gen.lua`), with `$VIMRUNTIME/doc/api.txt` as
  fallback for the ~13 UI/client endpoints not declared in the meta file.
- **Total: 157 non-deprecated endpoints** — Global (85), Buffers (32),
  Windows (22), Tabpages (8), UI/GUI clients (10).

To regenerate against the locally installed nvim, dump the names with
`vim.fn.api_info()` and re-extract descriptions from the meta file (see the
commit that introduced this doc for the extraction script).

## Endpoints

### Global (85)

| Function | Signature | Description |
|---|---|---|
| `nvim_call_dict_function` | `nvim_call_dict_function(dict, fn, args)` | Calls a Vimscript `Dictionary-function` with the given arguments. |
| `nvim_call_function` | `nvim_call_function(fn, args)` | Calls a Vimscript function with the given arguments. |
| `nvim_chan_send` | `nvim_chan_send(chan, data)` | Sends raw data to channel `chan`. `channel-bytes` - For a job, it writes it to the stdin of the process. - For the stdio channel `channel-stdio`, it writes to Nvim's stdout. - For an internal terminal instance (`nvim_open_term()`) it writes directly to terminal output. |
| `nvim_clear_autocmds` | `nvim_clear_autocmds(opts)` | Clears all autocommands matching the {opts} query. To delete autocmds see `nvim_del_autocmd()`. |
| `nvim_cmd` | `nvim_cmd(cmd, opts)` | Executes an Ex command `cmd`, specified as a Dict with the same structure as returned by `nvim_parse_cmd()`. |
| `nvim_command` | `nvim_command(cmd)` | Executes an Ex command. |
| `nvim_create_augroup` | `nvim_create_augroup(name, opts)` | Create or get an autocommand group `autocmd-groups`. |
| `nvim_create_autocmd` | `nvim_create_autocmd(event, opts)` | Creates an `autocommand` event handler, defined by `callback` (Lua function or Vimscript function _name_ string) or `command` (Ex command string). |
| `nvim_create_buf` | `nvim_create_buf(listed, scratch)` | Creates a new, empty, unnamed buffer. |
| `nvim_create_namespace` | `nvim_create_namespace(name)` | Creates a new namespace or gets an existing one. [namespace]() |
| `nvim_create_user_command` | `nvim_create_user_command(name, cmd, opts)` | Creates a global `user-commands` command. |
| `nvim_del_augroup_by_id` | `nvim_del_augroup_by_id(id)` | Delete an autocommand group by id. |
| `nvim_del_augroup_by_name` | `nvim_del_augroup_by_name(name)` | Delete an autocommand group by name. |
| `nvim_del_autocmd` | `nvim_del_autocmd(id)` | Deletes an autocommand by id. |
| `nvim_del_current_line` | `nvim_del_current_line()` | Deletes the current line. |
| `nvim_del_keymap` | `nvim_del_keymap(mode, lhs)` | Unmaps a global `mapping` for the given mode. |
| `nvim_del_mark` | `nvim_del_mark(name)` | Deletes an uppercase/file named mark. See `mark-motions`. |
| `nvim_del_user_command` | `nvim_del_user_command(name)` | Delete a user-defined command. |
| `nvim_del_var` | `nvim_del_var(name)` | Removes a global (g:) variable. |
| `nvim_echo` | `nvim_echo(chunks, history, opts)` | Prints a message given by a list of `[text, hl_group]` "chunks". Emits a `Progress` event if `kind='progress'`. |
| `nvim_eval` | `nvim_eval(expr)` | Evaluates a Vimscript `expression`. Dicts and Lists are recursively expanded. |
| `nvim_eval_statusline` | `nvim_eval_statusline(str, opts)` | Evaluates statusline string. |
| `nvim_exec2` | `nvim_exec2(src, opts)` | Executes Vimscript (multiline block of Ex commands), like anonymous `:source`. |
| `nvim_exec_autocmds` | `nvim_exec_autocmds(event, opts)` | Executes handlers for {event} that match the corresponding {opts} query. `autocmd-execute` - buf (`integer?`) Buffer id `autocmd-buflocal`. Not allowed with {pattern}. - data (`any`): Arbitrary data passed to the callback. See `nvim_create_autocmd()`. - group (`string\|integer?`) Group name or id to match against. `autocmd-groups`. - modeline (`boolean?`, default: true) Process the modeline after the autocommands [<nomodeline>]. - pattern (`string\|array?`, default: current file name) `autocmd-pattern`. Not allowed with {buf}. |
| `nvim_exec_lua` | `nvim_exec_lua(code, args)` | Executes Lua code. Arguments are available as `...` inside the chunk. The chunk can return a value. |
| `nvim_feedkeys` | `nvim_feedkeys(keys, mode, escape_ks)` | Sends input-keys to Nvim, subject to various quirks controlled by `mode` flags. This is a blocking call, unlike `nvim_input()`. |
| `nvim_get_all_options_info` | `nvim_get_all_options_info()` | Gets the option information for all options. |
| `nvim_get_api_info` | `nvim_get_api_info()` | Returns a 2-tuple (Array): item 0 is the current channel id and item 1 is the api-metadata map (Dict). |
| `nvim_get_autocmds` | `nvim_get_autocmds(opts)` | Gets all autocommands matching ALL criteria in the {opts} query. |
| `nvim_get_chan_info` | `nvim_get_chan_info(chan)` | Gets information about a channel. |
| `nvim_get_color_by_name` | `nvim_get_color_by_name(name)` | Returns the 24-bit RGB value of a `nvim_get_color_map()` color name or "#rrggbb" hexadecimal string. |
| `nvim_get_color_map` | `nvim_get_color_map()` | Returns a map of color names and RGB values. |
| `nvim_get_commands` | `nvim_get_commands(opts)` | Gets a map of global (non-buffer-local) Ex commands. |
| `nvim_get_context` | `nvim_get_context(opts)` | Gets a map of the current editor state. |
| `nvim_get_current_buf` | `nvim_get_current_buf()` | Gets the current buffer. |
| `nvim_get_current_line` | `nvim_get_current_line()` | Gets the current line. |
| `nvim_get_current_tabpage` | `nvim_get_current_tabpage()` | Gets the current tabpage. |
| `nvim_get_current_win` | `nvim_get_current_win()` | Gets the current window. |
| `nvim_get_hl` | `nvim_get_hl(ns_id, opts)` | Gets all or specific highlight groups in a namespace. |
| `nvim_get_hl_id_by_name` | `nvim_get_hl_id_by_name(name)` | Gets a highlight group by name |
| `nvim_get_hl_ns` | `nvim_get_hl_ns(opts)` | Gets the active highlight namespace. |
| `nvim_get_keymap` | `nvim_get_keymap(mode)` | Gets a list of global (non-buffer-local) `mapping` definitions. |
| `nvim_get_mark` | `nvim_get_mark(name, opts)` | Returns a `(row, col, buffer, buffername)` tuple representing the position of the uppercase/file named mark. "End of line" column position is returned as `v:maxcol` (big number). See `mark-motions`. |
| `nvim_get_mode` | `nvim_get_mode()` | Gets the current mode. `mode()` "blocking" is true if Nvim is waiting for input. |
| `nvim_get_namespaces` | `nvim_get_namespaces()` | Gets existing, non-anonymous `namespace`s. |
| `nvim_get_option_info2` | `nvim_get_option_info2(name, opts)` | Gets the option information for one option from arbitrary buffer or window |
| `nvim_get_option_value` | `nvim_get_option_value(name, opts)` | Gets the value of an option. The behavior of this function matches that of `:set`: the local value of an option is returned if it exists; otherwise, the global value is returned. Local values always correspond to the current buffer or window, unless "buf" or "win" is set in {opts}. |
| `nvim_get_proc` | `nvim_get_proc(pid)` | Gets info describing process `pid`. |
| `nvim_get_proc_children` | `nvim_get_proc_children(pid)` | Gets the immediate children of process `pid`. |
| `nvim_get_runtime_file` | `nvim_get_runtime_file(name, all)` | Finds files in runtime directories, in 'runtimepath' order. |
| `nvim_get_var` | `nvim_get_var(name)` | Gets a global (g:) variable. |
| `nvim_get_vvar` | `nvim_get_vvar(name)` | Gets a v: variable. |
| `nvim_input` | `nvim_input(keys)` | Queues raw user-input. Unlike `nvim_feedkeys()`, this uses a low-level input buffer and the call is non-blocking (input is processed asynchronously by the eventloop). |
| `nvim_input_mouse` | `nvim_input_mouse(button, action, modifier, grid, row, col)` | Send mouse event from GUI. |
| `nvim_list_bufs` | `nvim_list_bufs()` | Gets the current list of buffers. |
| `nvim_list_chans` | `nvim_list_chans()` | Get information about all open channels. |
| `nvim_list_runtime_paths` | `nvim_list_runtime_paths()` | Gets the paths contained in `runtime-search-path`. |
| `nvim_list_tabpages` | `nvim_list_tabpages()` | Gets the current list of `tab-ID`s. |
| `nvim_list_uis` | `nvim_list_uis()` | Gets a list of dictionaries representing attached UIs. |
| `nvim_list_wins` | `nvim_list_wins()` | Gets the current list of all `window-ID`s in all tabpages. |
| `nvim_load_context` | `nvim_load_context(dict)` | Sets the current editor state from the given `context` map. |
| `nvim_open_tabpage` | `nvim_open_tabpage(buf, enter, config)` | Opens a new tabpage. |
| `nvim_open_term` | `nvim_open_term(buf, opts)` | Open a terminal instance in a buffer |
| `nvim_open_win` | `nvim_open_win(buf, enter, config)` | Opens a new split window, floating window, or external window. |
| `nvim_parse_cmd` | `nvim_parse_cmd(str, opts)` | Parse command line. |
| `nvim_parse_expression` | `nvim_parse_expression(expr, flags, hl)` | Parse a Vimscript expression. |
| `nvim_paste` | `nvim_paste(data, crlf, phase)` | Pastes at cursor (in any mode), and sets "redo" so dot (`.`) will repeat the input. UIs call this to implement "paste", but it's also intended for use by scripts to input large, dot-repeatable blocks of text (as opposed to `nvim_input()` which is subject to mappings/events and is thus much slower). |
| `nvim_put` | `nvim_put(lines, type, after, follow)` | Puts text at cursor, in any mode. For dot-repeatable input, use `nvim_paste()`. |
| `nvim_replace_termcodes` | `nvim_replace_termcodes(str, from_part, do_lt, special)` | Replaces terminal codes and `keycodes` ([<CR>], [<Esc>], ...) in a string with the internal representation. |
| `nvim_select_popupmenu_item` | `nvim_select_popupmenu_item(item, insert, finish, opts)` | Selects an item in the completion popup menu. |
| `nvim_set_client_info` | `nvim_set_client_info(name, version, type, methods, attributes)` | Self-identifies the client, and sets optional flags on the channel. Defines the `client` object returned by nvim_get_chan_info(). |
| `nvim_set_current_buf` | `nvim_set_current_buf(buf)` | Sets the current window's buffer to `buf`. |
| `nvim_set_current_dir` | `nvim_set_current_dir(dir)` | Changes the global working directory. |
| `nvim_set_current_line` | `nvim_set_current_line(line)` | Sets the text on the current line. |
| `nvim_set_current_tabpage` | `nvim_set_current_tabpage(tabpage)` | Sets the current tabpage. |
| `nvim_set_current_win` | `nvim_set_current_win(win)` | Navigates to the given window (and tabpage, implicitly). |
| `nvim_set_decoration_provider` | `nvim_set_decoration_provider(ns_id, opts)` | Set or change decoration provider for a `namespace` |
| `nvim_set_hl` | `nvim_set_hl(ns_id, name, val)` | Sets a highlight group. By default, replaces the entire definition (e.g. `nvim_set_hl(0, 'Visual', {})` will clear the "Visual" group), unless `update` is specified. |
| `nvim_set_hl_ns` | `nvim_set_hl_ns(ns_id)` | Set active namespace for highlights defined with `nvim_set_hl()`. This can be set for a single window, see `nvim_win_set_hl_ns()`. |
| `nvim_set_hl_ns_fast` | `nvim_set_hl_ns_fast(ns_id)` | Set active namespace for highlights defined with `nvim_set_hl()` while redrawing. |
| `nvim_set_keymap` | `nvim_set_keymap(mode, lhs, rhs, opts)` | Sets a global `mapping` for the given mode. |
| `nvim_set_option_value` | `nvim_set_option_value(name, value, opts)` | Sets the value of an option. The behavior of this function matches that of `:set`: for global-local options, both the global and local value are set unless otherwise specified with {scope}. |
| `nvim_set_var` | `nvim_set_var(name, value)` | Sets a global (g:) variable. |
| `nvim_set_vvar` | `nvim_set_vvar(name, value)` | Sets a v: variable, if it is not readonly. |
| `nvim_strwidth` | `nvim_strwidth(text)` | Calculates the number of display cells occupied by `text`. Control characters including [<Tab>] count as one cell. |

### Buffers (32)

| Function | Signature | Description |
|---|---|---|
| `nvim_buf_attach` | `nvim_buf_attach(buf, send_buffer, opts)` | Activates `api-buffer-updates` events on a channel, or as Lua callbacks. |
| `nvim_buf_call` | `nvim_buf_call(buf, fun)` | Call a function with buffer as temporary current buffer. |
| `nvim_buf_clear_namespace` | `nvim_buf_clear_namespace(buf, ns_id, line_start, line_end)` | Clears `namespace`d objects (highlights, `extmarks`, virtual text) from a region. |
| `nvim_buf_create_user_command` | `nvim_buf_create_user_command(buf, name, cmd, opts)` | Creates a buffer-local command `user-commands`. |
| `nvim_buf_del_extmark` | `nvim_buf_del_extmark(buf, ns_id, id)` | Removes an `extmark`. |
| `nvim_buf_del_keymap` | `nvim_buf_del_keymap(buf, mode, lhs)` | Unmaps a buffer-local `mapping` for the given mode. |
| `nvim_buf_del_mark` | `nvim_buf_del_mark(buf, name)` | Deletes a named mark in the buffer. See `mark-motions`. |
| `nvim_buf_del_user_command` | `nvim_buf_del_user_command(buf, name)` | Delete a buffer-local user-defined command. |
| `nvim_buf_del_var` | `nvim_buf_del_var(buf, name)` | Removes a buffer-scoped (b:) variable |
| `nvim_buf_delete` | `nvim_buf_delete(buf, opts)` | Deletes a buffer and its metadata (like `:bwipeout`). |
| `nvim_buf_detach` | `nvim_buf_detach(buf)` | Deactivates buffer-update events on the channel. |
| `nvim_buf_get_changedtick` | `nvim_buf_get_changedtick(buf)` | Gets a changed tick of a buffer |
| `nvim_buf_get_commands` | `nvim_buf_get_commands(buf, opts)` | Gets a map of buffer-local `user-commands`. |
| `nvim_buf_get_extmark_by_id` | `nvim_buf_get_extmark_by_id(buf, ns_id, id, opts)` | Gets the position (0-indexed) of an `extmark`. |
| `nvim_buf_get_extmarks` | `nvim_buf_get_extmarks(buf, ns_id, start, end_, opts)` | Gets `extmarks` in "traversal order" from a `charwise` region defined by buffer positions (inclusive, 0-indexed `api-indexing`). |
| `nvim_buf_get_keymap` | `nvim_buf_get_keymap(buf, mode)` | Gets a list of buffer-local `mapping` definitions. |
| `nvim_buf_get_lines` | `nvim_buf_get_lines(buf, start, end_, strict_indexing)` | Gets a line-range from the buffer. |
| `nvim_buf_get_mark` | `nvim_buf_get_mark(buf, name)` | Returns a `(row,col)` tuple representing the position of the named mark. "End of line" column position is returned as `v:maxcol` (big number). See `mark-motions`. |
| `nvim_buf_get_name` | `nvim_buf_get_name(buf)` | Gets the full file name for the buffer |
| `nvim_buf_get_offset` | `nvim_buf_get_offset(buf, index)` | Returns the byte offset of a line (0-indexed). `api-indexing` |
| `nvim_buf_get_text` | `nvim_buf_get_text(buf, start_row, start_col, end_row, end_col, opts)` | Gets a range from the buffer (may be partial lines, unlike `nvim_buf_get_lines()`). |
| `nvim_buf_get_var` | `nvim_buf_get_var(buf, name)` | Gets a buffer-scoped (b:) variable. |
| `nvim_buf_is_loaded` | `nvim_buf_is_loaded(buf)` | Checks if a buffer is valid and loaded. See `api-buffer` for more info about unloaded buffers. |
| `nvim_buf_is_valid` | `nvim_buf_is_valid(buf)` | Checks if a buffer is valid. |
| `nvim_buf_line_count` | `nvim_buf_line_count(buf)` | Returns the number of lines in the given buffer. |
| `nvim_buf_set_extmark` | `nvim_buf_set_extmark(buf, ns_id, line, col, opts)` | Creates or updates an `extmark`. |
| `nvim_buf_set_keymap` | `nvim_buf_set_keymap(buf, mode, lhs, rhs, opts)` | Sets a buffer-local `mapping` for the given mode. |
| `nvim_buf_set_lines` | `nvim_buf_set_lines(buf, start, end_, strict_indexing, replacement)` | Sets (replaces) a line-range in the buffer. |
| `nvim_buf_set_mark` | `nvim_buf_set_mark(buf, name, line, col, opts)` | Sets a named mark in the given buffer, all marks are allowed file/uppercase, visual, last change, etc. See `mark-motions`. |
| `nvim_buf_set_name` | `nvim_buf_set_name(buf, name)` | Sets the full file name for a buffer, like `:file_f` |
| `nvim_buf_set_text` | `nvim_buf_set_text(buf, start_row, start_col, end_row, end_col, replacement)` | Sets (replaces) a range in the buffer |
| `nvim_buf_set_var` | `nvim_buf_set_var(buf, name, value)` | Sets a buffer-scoped (b:) variable |

### Windows (22)

| Function | Signature | Description |
|---|---|---|
| `nvim_win_call` | `nvim_win_call(win, fun)` | Calls a function with window as temporary current window. |
| `nvim_win_close` | `nvim_win_close(win, force)` | Closes the window (like `:close` with a `window-ID`). |
| `nvim_win_del_var` | `nvim_win_del_var(win, name)` | Removes a window-scoped (w:) variable |
| `nvim_win_get_buf` | `nvim_win_get_buf(win)` | Gets the current buffer in a window |
| `nvim_win_get_config` | `nvim_win_get_config(win)` | Gets window configuration in the form of a dict which can be passed as the `config` parameter of `nvim_open_win()`. |
| `nvim_win_get_cursor` | `nvim_win_get_cursor(win)` | Gets the (1,0)-indexed, buffer-relative cursor position for a given window (different windows showing the same buffer have independent cursor positions). `api-indexing` |
| `nvim_win_get_height` | `nvim_win_get_height(win)` | Gets the window height |
| `nvim_win_get_number` | `nvim_win_get_number(win)` | Gets the window number |
| `nvim_win_get_position` | `nvim_win_get_position(win)` | Gets the window position in display cells. First position is zero. |
| `nvim_win_get_tabpage` | `nvim_win_get_tabpage(win)` | Gets the window tabpage |
| `nvim_win_get_var` | `nvim_win_get_var(win, name)` | Gets a window-scoped (w:) variable |
| `nvim_win_get_width` | `nvim_win_get_width(win)` | Gets the window width |
| `nvim_win_hide` | `nvim_win_hide(win)` | Closes the window and hide the buffer it contains (like `:hide` with a `window-ID`). |
| `nvim_win_is_valid` | `nvim_win_is_valid(win)` | Checks if a window is valid |
| `nvim_win_set_buf` | `nvim_win_set_buf(win, buf)` | Sets the current buffer in a window. |
| `nvim_win_set_config` | `nvim_win_set_config(win, config)` | Reconfigures the layout and properties of a window. |
| `nvim_win_set_cursor` | `nvim_win_set_cursor(win, pos)` | Sets the (1,0)-indexed cursor position (byte offset) in the window. `api-indexing` This scrolls the window even if it is not the current one. |
| `nvim_win_set_height` | `nvim_win_set_height(win, height)` | Sets the window height. |
| `nvim_win_set_hl_ns` | `nvim_win_set_hl_ns(win, ns_id)` | Set highlight namespace for a window. This will use highlights defined with `nvim_set_hl()` for this namespace, but fall back to global highlights (ns=0) when missing. |
| `nvim_win_set_var` | `nvim_win_set_var(win, name, value)` | Sets a window-scoped (w:) variable |
| `nvim_win_set_width` | `nvim_win_set_width(win, width)` | Sets the window width. This will only succeed if the screen is split vertically. |
| `nvim_win_text_height` | `nvim_win_text_height(win, opts)` | Computes the number of screen lines occupied by a range of text in a given window. Works for off-screen text and takes folds into account. |

### Tabpages (8)

| Function | Signature | Description |
|---|---|---|
| `nvim_tabpage_del_var` | `nvim_tabpage_del_var(tabpage, name)` | Removes a tab-scoped (t:) variable |
| `nvim_tabpage_get_number` | `nvim_tabpage_get_number(tabpage)` | Gets the tabpage number |
| `nvim_tabpage_get_var` | `nvim_tabpage_get_var(tabpage, name)` | Gets a tab-scoped (t:) variable |
| `nvim_tabpage_get_win` | `nvim_tabpage_get_win(tabpage)` | Gets the current window in a tabpage |
| `nvim_tabpage_is_valid` | `nvim_tabpage_is_valid(tabpage)` | Checks if a tabpage is valid |
| `nvim_tabpage_list_wins` | `nvim_tabpage_list_wins(tabpage)` | Gets the windows in a tabpage |
| `nvim_tabpage_set_var` | `nvim_tabpage_set_var(tabpage, name, value)` | Sets a tab-scoped (t:) variable |
| `nvim_tabpage_set_win` | `nvim_tabpage_set_win(tabpage, win)` | Sets the current window in a tabpage |

### UI / GUI clients (10)

| Function | Signature | Description |
|---|---|---|
| `nvim_ui_attach` | `nvim_ui_attach(width, height, options)` | Activates UI events on the channel. Entry point of all UI clients (GUIs). |
| `nvim_ui_detach` | `nvim_ui_detach()` | Deactivates UI events on the channel. Removes the client from the list of UIs. |
| `nvim_ui_pum_set_bounds` | `nvim_ui_pum_set_bounds(width, height, row, col)` | Tells Nvim the geometry of the popupmenu, to align floating windows with an external popup menu. |
| `nvim_ui_pum_set_height` | `nvim_ui_pum_set_height(height)` | Tells Nvim the number of elements displaying in the popupmenu, to decide <PageUp>/<PageDown> movement. |
| `nvim_ui_send` | `nvim_ui_send(content)` | Sends arbitrary data to a UI. Use this instead of `nvim_chan_send()` or `io.stdout:write()`, if you really want to write to the `TUI` host terminal. |
| `nvim_ui_set_focus` | `nvim_ui_set_focus(gained)` | Tells the nvim server if focus was gained or lost by the GUI. |
| `nvim_ui_set_option` | `nvim_ui_set_option(name, value)` | Sets a UI option on the channel (RPC only). |
| `nvim_ui_term_event` | `nvim_ui_term_event(event, value)` | Emitted by the TUI client to signal when a host-terminal event occurred. |
| `nvim_ui_try_resize` | `nvim_ui_try_resize(width, height)` | Requests the nvim screen be resized to the given dimensions (RPC only). |
| `nvim_ui_try_resize_grid` | `nvim_ui_try_resize_grid(grid, width, height)` | Tells Nvim to resize a grid; triggers a grid_resize event with the requested (or max) size. |
