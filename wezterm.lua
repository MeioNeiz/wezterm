local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

-- config_builder() is strict: assigning a field it does not know raises, and a raise while
-- loading this file means wezterm throws away the entire config and falls back to defaults.
-- One typo in a cosmetic setting therefore costs every keybinding, the tab bar and the whole
-- colour scheme. Field names also come and go between versions.
--
-- So anything optional goes through here, where an unknown field is skipped with a warning.
-- Note that no `wezterm` CLI subcommand validates these - show-keys and ls-fonts both load
-- the file and report nothing - so the GUI is the only thing that will ever tell you.
local function try_set(key, value)
	if not pcall(function()
		config[key] = value
	end) then
		wezterm.log_warn("wezterm.lua: skipping unknown config field " .. key)
	end
end

local is_windows = wezterm.target_triple:find("windows") ~= nil
local is_macos = wezterm.target_triple:find("darwin") ~= nil

-- ============================================================
-- Appearance  (your original settings, preserved)
-- ============================================================
config.font = wezterm.font_with_fallback({
	{ family = "JetBrains Mono", weight = "Regular" },
})
config.font_size = 14.0
config.line_height = 1.0
config.harfbuzz_features = { "calt=1", "liga=1", "clig=1" } -- programming ligatures

config.color_scheme = "Catppuccin Mocha"
config.window_background_opacity = 1.0
config.window_padding = { left = 4, right = 4, top = 2, bottom = 0 } -- minimal perimeter; set to 0 for edge-to-edge
config.adjust_window_size_when_changing_font_size = false
config.audible_bell = "Disabled"
config.scrollback_lines = 50000 -- bumped from 10k for long-running sessions

-- Tab bar
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
config.hide_tab_bar_if_only_one_tab = false
-- Deliberately loose: this is the only width format-tab-title is told about, and
-- it is the config value, not the room actually left in the bar. The real sharing
-- happens in label_width, so this only has to be wide enough not to bind first - and
-- at 160 it was binding first, in every window wide enough to matter.
config.tab_max_width = 320
-- Two cells a tab, and nothing here is ever clicked.
--
-- Through try_set because this field has been spelled two different ways: assigning the
-- wrong one is not a warning, it is `error converting Lua table to Config` and the whole
-- file is discarded. Nothing in this config is worth that, least of all two cells.
try_set("show_close_tab_button_in_tabs", false)
-- Doubles as how often the tab bar re-reads pane state, see update-right-status.
config.status_update_interval = 1000

-- Marks a tab title pinned by the save layer rather than typed by hand (LEADER+,).
-- Invisible if it ever reaches the tab bar, so format-tab-title can tell the two
-- apart and let live pane topics win over a pin that has since gone stale.
local AUTO_TITLE_MARK = "\u{2063}"

-- A tab can carry a hand-typed name *and* the live pane row. Text before the first
-- backslash is the name, the backslash onward is the row's to fill: "dtmf \". A title
-- with no backslash still means typed by hand, shown exactly as typed.
local TAB_GROUP_SEP = "\\"

-- (Optional) On Windows, default to PowerShell 7 — uncomment if you want it.
-- This same file works on macOS, Linux, and Windows.
-- if is_windows then
-- 	config.default_prog = { "pwsh.exe", "-NoLogo" }
-- end

-- ============================================================
-- Session persistence: resurrect.wezterm
-- Saves every workspace's layout (tabs/panes/cwd) plus the Claude Code session
-- running in each pane, so a full quit comes back to the same desk.
-- Plugin auto-clones from GitHub the first time this config loads.
--
-- The plugin's own periodic_save is deliberately not used: it only snapshots
-- the *active* workspace, so everything else silently goes stale.
-- ============================================================
local resurrect = wezterm.plugin.require("https://github.com/MLFlexer/resurrect.wezterm")

local session_map_dir = wezterm.home_dir .. "/.claude/wezterm-sessions"
-- What cc-tint last painted onto each pane, `<session id>\t<hue name>`. Only read here to
-- be wiped with the rest of the pane-keyed state.
local painted_dir = wezterm.home_dir .. "/.claude/cache/cc-tint-painted"
-- What each Claude pane is doing, written by hooks/wezterm-pane-state.sh; read by
-- format-tab-title, since a pane title only ever says working or not working.
local pane_state_dir = wezterm.home_dir .. "/.claude/wezterm-state"
local brief_script = wezterm.home_dir .. "/.claude/hooks/claude-session-brief.py"
local save_interval_seconds = 120

local function is_claude(argv)
	return argv ~= nil and argv[1] ~= nil and argv[1]:match("claude$") ~= nil
end

-- The saved pane tree drops pane ids and pids, but keeps cwd and start_time from
-- the same get_foreground_process_info() call, so those identify a pane across
-- the save. Collision needs two claudes started in one cwd in the same second.
local function process_key(cwd, start_time)
	return tostring(cwd) .. "\0" .. tostring(start_time)
end

local function read_session_id(pane_id)
	local file = io.open(session_map_dir .. "/" .. pane_id, "r")
	if not file then
		return nil
	end
	local id = file:read("*line")
	file:close()
	if id and id:match("^[%x%-]+$") then
		return id
	end
end

---Claude session id and title for every live pane running Claude Code
local function live_claude_panes()
	local live = {}
	for _, mux_win in ipairs(wezterm.mux.all_windows()) do
		for _, mux_tab in ipairs(mux_win:tabs()) do
			for _, pane in ipairs(mux_tab:panes()) do
				local ok, info = pcall(pane.get_foreground_process_info, pane)
				if ok and info and is_claude(info.argv) then
					local id = read_session_id(pane:pane_id())
					if id then
						live[process_key(info.cwd, info.start_time)] = {
							session_id = id,
							title = pane:get_title(),
						}
					end
				end
			end
		end
	end
	return live
end

-- A pane already resumed once carries --resume with an id that may since have
-- been superseded, so drop any resume/continue flags before adding the current one.
local function strip_resume_flags(argv)
	local out, skip = {}, false
	for _, arg in ipairs(argv) do
		if skip then
			skip = false
		elseif arg == "--resume" or arg == "-r" then
			skip = true
		elseif arg ~= "--continue" and arg ~= "-c" then
			table.insert(out, arg)
		end
	end
	return out
end

---Rewrite Claude panes in a saved tree to resume their conversation
---@return string|nil title of the first Claude pane found, for the tab bar
local function tag_claude_panes(node, live)
	if node == nil then
		return nil
	end
	local title = nil
	local proc = node.process
	if proc and is_claude(proc.argv) then
		local found = live[process_key(proc.cwd, proc.start_time)]
		if found then
			local argv = strip_resume_flags(proc.argv)
			table.insert(argv, 2, "--resume")
			table.insert(argv, 3, found.session_id)
			proc.argv = argv
			node.claude_session = found.session_id
			title = found.title
		end
	end
	-- both subtrees must be walked, so no short-circuiting on the first title found
	local right = tag_claude_panes(node.right, live)
	local bottom = tag_claude_panes(node.bottom, live)
	return title or right or bottom
end

local function save_all_workspaces()
	local live = live_claude_panes()
	local saved = 0
	local live_names = {}

	for _, name in ipairs(wezterm.mux.get_workspace_names()) do
		local state = { workspace = name, window_states = {} }
		for _, mux_win in ipairs(wezterm.mux.all_windows()) do
			if mux_win:get_workspace() == name then
				table.insert(state.window_states, resurrect.window_state.get_window_state(mux_win))
			end
		end

		if #state.window_states > 0 then
			for _, window_state in ipairs(state.window_states) do
				for _, tab_state in ipairs(window_state.tabs) do
					local title = tag_claude_panes(tab_state.pane_tree, live)
					-- untitled tabs fall back to the pane title, which after a restore
					-- is just "zsh"; pin the Claude topic so the tab bar stays readable
					-- until the resumed sessions start announcing their own again
					if title and (tab_state.title == nil or tab_state.title == "") then
						tab_state.title = AUTO_TITLE_MARK .. title
					end
				end
			end
			resurrect.state_manager.save_state(state)
			saved = saved + 1
			table.insert(live_names, name)
		end
	end

	local file = io.open(resurrect.state_manager.save_state_dir .. "last_workspace", "w")
	if file then
		file:write(wezterm.mux.get_active_workspace())
		file:close()
	end

	-- The manifest, not the state dir, decides what comes back: saved states are
	-- never deleted, so globbing the dir resurrects every workspace that ever
	-- existed and closing one has no effect.
	local manifest = io.open(resurrect.state_manager.save_state_dir .. "live_workspaces", "w")
	if manifest then
		manifest:write(table.concat(live_names, "\n"))
		manifest:close()
	end

	return saved
end

-- Claude panes are restored armed: the resume command is typed at the prompt but
-- not run, under a header saying what the conversation was. Stops every session
-- reconnecting at once and lets you skip the ones you are done with.
local function on_pane_restore(pane_tree)
	local pane = pane_tree.pane

	if pane_tree.alt_screen_active and pane_tree.process then
		local cmd = wezterm.shell_join_args(pane_tree.process.argv)
		if pane_tree.claude_session then
			local ok, ran, stdout = pcall(wezterm.run_child_process, {
				"/usr/bin/python3", brief_script, pane_tree.claude_session,
			})
			if ok and ran and stdout ~= "" then
				pane:inject_output(stdout)
			end
			pane:send_text(cmd)
		else
			pane:send_text(cmd .. "\r\n")
		end
	elseif pane_tree.text then
		pane:inject_output(pane_tree.text:gsub("%s+$", ""))
	end
end

local function saved_workspace_names()
	local on_disk = {}
	local pattern = resurrect.state_manager.save_state_dir .. "workspace/*.json"
	for _, path in ipairs(wezterm.glob(pattern)) do
		on_disk[path:match("([^/]+)%.json$")] = true
	end

	-- Restore what was open at the last save, not everything ever saved. No
	-- manifest yet (first run after this change) means fall back to the dir.
	local names = {}
	local manifest = io.open(resurrect.state_manager.save_state_dir .. "live_workspaces", "r")
	if manifest then
		for line in manifest:lines() do
			local name = line:match("^%s*(.-)%s*$")
			if name ~= "" and on_disk[name] then
				table.insert(names, name)
			end
		end
		manifest:close()
		return names
	end

	for name in pairs(on_disk) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

wezterm.on("gui-startup", function()
	-- pane ids restart from 0 with a new mux, so the old map, the old pane states and the
	-- record of what colour each pane was painted would all mis-attribute; the ids we need
	-- are already baked into the saved states. A stale paint record is the subtle one: it
	-- would have a new session in pane 3 avoid the colour that the *previous* mux's pane 3
	-- was wearing.
	wezterm.background_child_process({
		"/bin/sh", "-c",
		string.format(
			"rm -rf %q %q %q && mkdir -p %q %q",
			session_map_dir,
			pane_state_dir,
			painted_dir,
			session_map_dir,
			pane_state_dir
		),
	})

	local restored = 0
	for _, name in ipairs(saved_workspace_names()) do
		-- fresh opts per workspace: restore_workspace writes its window/tab/pane
		-- back into the table, and a reused window would swallow the next workspace
		local opts = {
			relative = true,
			restore_text = true,
			spawn_in_workspace = true,
			on_pane_restore = on_pane_restore,
		}
		local ok, err = pcall(function()
			resurrect.workspace_state.restore_workspace(
				resurrect.state_manager.load_state(name, "workspace"), opts)
		end)
		if ok then
			restored = restored + 1
		else
			wezterm.log_error("resurrect: could not restore workspace " .. name .. ": " .. tostring(err))
		end
	end

	if restored == 0 then
		wezterm.mux.spawn_window({})
		return
	end

	local file = io.open(resurrect.state_manager.save_state_dir .. "last_workspace", "r")
	if file then
		local last = file:read("*line")
		file:close()
		if last and last ~= "" then
			pcall(wezterm.mux.set_active_workspace, last)
		end
	end
end)

-- Note: editing this file restarts the timer chain without stopping the previous
-- one, so repeated config reloads stack duplicate (idempotent) saves until restart.
local function periodic_save_all()
	wezterm.time.call_after(save_interval_seconds, function()
		local ok, err = pcall(save_all_workspaces)
		if not ok then
			wezterm.log_error("resurrect: periodic save failed: " .. tostring(err))
		end
		periodic_save_all()
	end)
end
periodic_save_all()

-- ============================================================
-- Multiplexing keybindings   (leader = CTRL-a, tmux-style)
-- Press the leader, release, then press the action key.
-- ============================================================
config.leader = { key = "Space", mods = "CTRL", timeout_milliseconds = 1000 }

-- Assigned in the Claude fleet section at the foot of this file, which needs the roster and
-- the tab colours. Declared here because the keys table below closes over it: declared any
-- later and the binding resolves to a nil global instead.
local workspace_picker


config.keys = {
	-- Press leader then Ctrl-Space to send a literal Ctrl-Space to the shell
	{ key = "Space", mods = "LEADER|CTRL", action = act.SendKey({ key = "Space", mods = "CTRL" }) },

	-- ---- Panes: split the current pane ----
	{ key = "\\", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) }, -- split RIGHT
	{ key = "-", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },     -- split DOWN

	-- ---- Panes: move focus (vim hjkl) ----
	{ key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
	{ key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
	{ key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },

	-- ---- Panes: manage ----
	{ key = "z", mods = "LEADER", action = act.TogglePaneZoomState },          -- fullscreen this pane
	{ key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
	{ key = "Space", mods = "LEADER", action = act.PaneSelect },               -- jump to a pane by label
	{ key = "o", mods = "LEADER", action = act.RotatePanes("Clockwise") },     -- shuffle the layout
	{ key = "s", mods = "LEADER", action = act.PaneSelect({ mode = "SwapWithActive" }) }, -- swap this pane with a labelled one
	{ key = "m", mods = "LEADER", action = wezterm.action_callback(function(_, pane)      -- move this pane out to a new window
		pane:move_to_new_window()
	end) },
	{ key = "r", mods = "LEADER", action = act.ActivateKeyTable({ name = "resize_pane", one_shot = false }) },

	-- ---- Tabs (a tab = a full screen of panes) ----
	{ key = "c", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },
	{
		key = ",",
		mods = "LEADER",
		action = act.PromptInputLine({
			description = "Rename tab:",
			action = wezterm.action_callback(function(window, _, line)
				if line and line ~= "" then
					window:active_tab():set_title(line)
				end
			end),
		}),
	},

	-- ---- Workspaces (a workspace = a whole project: its own set of tabs) ----
	{ key = "w", mods = "LEADER", action = wezterm.action_callback(function(window, pane)
		workspace_picker(window, pane)
	end) }, -- switch workspace, with what is in each one
	{
		key = "W",
		mods = "LEADER",
		action = act.PromptInputLine({
			description = "New workspace name:",
			action = wezterm.action_callback(function(window, pane, line)
				if line and line ~= "" then
					window:perform_action(act.SwitchToWorkspace({ name = line }), pane)
				end
			end),
		}),
	},
	{
		key = "<",
		mods = "LEADER",
		action = act.PromptInputLine({
			description = "Rename workspace:",
			action = wezterm.action_callback(function(window, _, line)
				if line and line ~= "" then
					wezterm.mux.rename_workspace(window:active_workspace(), line)
				end
			end),
		}),
	},
	{ key = "n", mods = "LEADER", action = act.SwitchWorkspaceRelative(1) },  -- next workspace
	{ key = "p", mods = "LEADER", action = act.SwitchWorkspaceRelative(-1) }, -- previous workspace

	-- ---- Session persistence (resurrect): Save / Restore ----
	{ key = "S", mods = "LEADER", action = wezterm.action_callback(function(win, _)
		local saved = save_all_workspaces()
		win:toast_notification("wezterm", "Saved " .. saved .. " workspaces", nil, 2000)
	end) },
	{ key = "R", mods = "LEADER", action = wezterm.action_callback(function(win, pane)
		resurrect.fuzzy_loader.fuzzy_load(win, pane, function(id)
			local kind = string.match(id, "^([^/]+)")       -- workspace | window | tab
			id = string.match(id, "([^/]+)$")               -- strip dir
			id = string.match(id, "(.+)%..+$")              -- strip .json
			local opts = {
				relative = true,
				restore_text = true,
				on_pane_restore = on_pane_restore,
			}
			if kind == "workspace" then
				resurrect.workspace_state.restore_workspace(
					resurrect.state_manager.load_state(id, "workspace"), opts)
			elseif kind == "window" then
				resurrect.window_state.restore_window(
					pane:window(), resurrect.state_manager.load_state(id, "window"), opts)
			elseif kind == "tab" then
				resurrect.tab_state.restore_tab(
					pane:tab(), resurrect.state_manager.load_state(id, "tab"), opts)
			end
		end)
	end) },

	-- ---- Scrollback: copy mode & search ----
	{ key = "[", mods = "LEADER", action = act.ActivateCopyMode },
	{ key = "/", mods = "LEADER", action = act.Search("CurrentSelectionOrEmptyString") },
}

-- Direct tab access: LEADER + 1..9
for i = 1, 9 do
	table.insert(config.keys, {
		key = tostring(i),
		mods = "LEADER",
		action = act.ActivateTab(i - 1),
	})
end

-- ---- Close pane / tab: consistent across macOS, Windows & Linux ----
-- Same chord everywhere so muscle memory transfers:
--   CTRL+SHIFT+W = close the focused PANE  (last pane closes its tab too, like iTerm2/VS Code)
--   CTRL+SHIFT+Q = close the whole TAB
table.insert(config.keys, { key = "w", mods = "CTRL|SHIFT", action = act.CloseCurrentPane({ confirm = true }) })
table.insert(config.keys, { key = "q", mods = "CTRL|SHIFT", action = act.CloseCurrentTab({ confirm = true }) })

-- macOS bonus: also honor the native CMD+W / CMD+SHIFT+W. Binding CMD+W here
-- is required to override WezTerm's built-in CMD+W (which would close the tab).
if is_macos then
	table.insert(config.keys, { key = "w", mods = "CMD", action = act.CloseCurrentPane({ confirm = true }) })
	table.insert(config.keys, { key = "w", mods = "CMD|SHIFT", action = act.CloseCurrentTab({ confirm = true }) })
	-- Snapshot before quitting. The macOS menu's Quit bypasses this, so the
	-- periodic save is still the backstop.
	table.insert(config.keys, { key = "q", mods = "CMD", action = wezterm.action_callback(function(win, pane)
		pcall(save_all_workspaces)
		win:perform_action(act.QuitApplication, pane)
	end) })
end

-- Resize mode: LEADER r, then hjkl to resize, Esc/Enter to exit
config.key_tables = {
	resize_pane = {
		{ key = "h", action = act.AdjustPaneSize({ "Left", 2 }) },
		{ key = "j", action = act.AdjustPaneSize({ "Down", 2 }) },
		{ key = "k", action = act.AdjustPaneSize({ "Up", 2 }) },
		{ key = "l", action = act.AdjustPaneSize({ "Right", 2 }) },
		{ key = "Escape", action = "PopKeyTable" },
		{ key = "Enter", action = "PopKeyTable" },
	},
}

-- ============================================================
-- Status bar: show LEADER indicator, resize mode, and workspace
--
-- Also the heartbeat the tab bar rides on. format-tab-title only runs when
-- something invalidates the title, and most of what colours a tab has no
-- wezterm-visible event behind it: a hook writing a state file, or a finished
-- turn ageing past FRESH_SECONDS. Setting the status is the one thing that fires
-- on a timer, and it only invalidates when the string actually changes, so the
-- trailing blank alternates between space and NBSP: identical cell, different
-- bytes, every tab re-evaluated once per status_update_interval.
-- ============================================================
local tab_geometry = {} -- tab id -> the bar's size; see label_width
local status_tick = 0

-- Assigned in the Claude fleet section at the foot of this file, which needs
-- read_pane_state and so cannot be hoisted up here. The status bar is its only caller.
local attention_elsewhere

-- Likewise: keeps LEADER+w's branch column warm from here, since the picker itself must not
-- wait on git. Throttled inside, so this costs nothing on the ticks in between.
local ws_git_refresh

-- Also assigned down there: stamps the workspace you are looking at, which is what gives
-- LEADER+w its alt-tab order. The status bar is the only thing that fires often enough to
-- notice you arriving by any route - the picker, LEADER+n/p, or clicking a window.
local ws_touch

-- Likewise, and for the workspace name: it takes the colour of the pane you are actually
-- in, so the bar answers "which chat am I typing into" as well as "where am I". Defined
-- with the tab bar's identity palette, which cannot be hoisted above this handler.
local focused_identity

wezterm.on("update-right-status", function(window, _)
	local parts = {}
	local width = 0

	if window:active_key_table() == "resize_pane" then
		table.insert(parts, { Foreground = { Color = "#fab387" } })
		table.insert(parts, { Text = " RESIZE (hjkl, Esc) " })
		width = width + 20
	end

	if window:leader_is_active() then
		table.insert(parts, { Foreground = { Color = "#f38ba8" } })
		table.insert(parts, { Text = " ⌨ LEADER " })
		width = width + 10
	end

	-- What wants you in a workspace you are not looking at. Nothing else in this config
	-- can say it, and with a dozen workspaces open a blocked pane can sit unseen for
	-- hours. Ahead of the workspace name because it is the only part of the bar that is
	-- about somewhere else.
	if attention_elsewhere then
		local away = attention_elsewhere(window)
		if away.asking > 0 then
			table.insert(parts, { Foreground = { Color = "#cba6f7" } })
			table.insert(parts, { Text = string.format(" ⚠%d", away.asking) })
			width = width + 4
		end
		if away.fresh > 0 then
			table.insert(parts, { Foreground = { Color = "#f9e2af" } })
			table.insert(parts, { Text = string.format(" ✓%d", away.fresh) })
			width = width + 4
		end
	end

	-- Kept warm from here rather than from the keypress: LEADER+w draws the branch column
	-- from the last snapshot, so the snapshot has to already exist.
	if ws_git_refresh then
		ws_git_refresh()
	end

	if ws_touch then
		local ok, focused = pcall(function()
			return window:is_focused()
		end)
		if ok and focused then
			ws_touch(window:active_workspace())
		end
	end

	local workspace = window:active_workspace()
	status_tick = status_tick + 1
	local blank = (status_tick % 2 == 0) and " " or "\u{00a0}"
	local ws_colour = "#89b4fa"
	if focused_identity then
		local ok_pane, tint = pcall(function()
			return focused_identity(window:active_pane():pane_id())
		end)
		if ok_pane and tint then
			ws_colour = tint
		end
	end
	table.insert(parts, { Foreground = { Color = ws_colour } })
	table.insert(parts, { Text = "  " .. workspace .. " " .. blank })
	width = width + #workspace + 4

	-- format-tab-title is told the config's tab_max_width, not how much bar is
	-- actually left, so measure it here where the window is in hand.
	local ok, size = pcall(function()
		return window:active_tab():get_size()
	end)
	if ok and size and size.cols then
		local tabs = window:mux_window():tabs()
		local geom = { cols = size.cols, tabs = #tabs, reserve = width }
		for _, mux_tab in ipairs(tabs) do
			tab_geometry[mux_tab:tab_id()] = geom
		end
	end

	window:set_right_status(wezterm.format(parts))
end)

-- ============================================================
-- Tab titles: name every Claude pane in the tab, not just the focused one
-- Claude Code writes each session's topic into its own pane title, prefixed with
-- a status glyph (spinner = working, anything else = waiting, see is_working), so a
-- 3-4 way split already knows what each chat is about; the tab bar has to show it.
-- Precedence: a title typed by hand (LEADER+,) wins, then live pane topics, then
-- a pin left by the save layer, then whatever the active pane calls itself.
-- ============================================================
-- A whole topic, not half of one, and the only ceiling left. At 52, with label_width's
-- predecessor also limiting, a window with one tab and four hundred spare columns still
-- wrote "Audit and sync HubSp…": two caps on the same number, and the wrong one bound.
local SOLO_BUDGET = 96
local MIN_LABEL = 10 -- a label with room for a subject, not just a verb
local TERSE_LABEL = 5 -- squeezed, but still names something
local GROUP_LABEL = 14 -- a tab's own name, the part before TAB_GROUP_SEP
-- Reserves for chrome this code cannot measure. Generous on purpose: unused bar is
-- just empty, whereas overshooting means wezterm clips the tabs itself, which is
-- the failure this whole calculation exists to avoid. Raise if tabs still clip.
-- Per-tab overhead this code cannot measure. It was 8 on the reasoning that unused bar
-- is harmless, which is true in a two-tab window and false in a ten-tab one: there it
-- was claiming 80 of 111 columns and starving every tab of a name. 5 with the close
-- button turned off. Raise it if tabs start clipping, which is the failure it exists
-- to avoid.
local TAB_CHROME = 5
local BAR_SLACK = 6 -- new tab button, and rounding

-- Titles that name a program rather than a task.
local UNINFORMATIVE = {
	zsh = true,
	bash = true,
	fish = true,
	sh = true,
	["-zsh"] = true,
	nvim = true,
	vim = true,
	node = true,
	tmux = true,
	-- The cc-board overlay, before and after strip_glyph.
	["▤ board"] = true,
	["board"] = true,
}

-- Leading verbs nearly every generated topic opens with. Dropping one keeps the
-- subject visible when four panes are sharing the budget.
local FILLER_VERBS = {
	"Set up",
	"Review", "Investigate", "Implement", "Configure", "Refactor", "Simplify",
	"Complete", "Evaluate", "Automate", "Identify", "Prepare", "Resolve",
	"Migrate", "Compare", "Execute", "Explore", "Rename", "Verify", "Update",
	"Create", "Enable", "Remove", "Finish", "Debug", "Audit", "Build", "Check",
	"Share", "Start", "Write", "Plan", "Move", "Sync", "Show", "Fix", "Add", "Set",
}

local function strip_filler(label)
	for _, verb in ipairs(FILLER_VERBS) do
		local rest = label:match("^" .. verb .. "%s+(.+)$")
		if rest then
			return rest
		end
	end
	return label
end

local function shorten(text, budget)
	if #text <= budget then
		return text
	end
	local cut = text:sub(1, budget - 1)
	-- cut back to a word boundary only when that still fills most of the budget;
	-- at 12 chars a mid-word cut carries more than a lonely first word
	local last_space = cut:match("^.*()%s")
	if last_space and last_space > budget * 0.75 then
		cut = cut:sub(1, last_space - 1)
	end
	-- never leave half a multi-byte glyph behind
	while #cut > 0 and cut:byte(#cut) >= 0x80 and cut:byte(#cut) < 0xC0 do
		cut = cut:sub(1, #cut - 1)
	end
	return cut .. "…"
end

---Claude Code leads a working session's title with the circle-halves spinner,
---◐◓◑◒ (U+25D0-U+25D3, ie. E2 97 90..93 in UTF-8), and an idle one with a dingbat
---asterisk, ✳ (U+2733). Older builds spun braille, so that range still counts.
---Worth keeping in step with Claude Code: pane_status trusts this over the state
---file, so a spinner it cannot see leaves every busy pane reading as waiting, and
---leaves an answered permission prompt stuck on asking until the turn ends.
local function is_working(title)
	local b1, b2, b3 = title:byte(1), title:byte(2) or 0, title:byte(3) or 0
	if b1 ~= 0xE2 then
		return false
	end
	return (b2 == 0x97 and b3 >= 0x90 and b3 <= 0x93) -- ◐◓◑◒
		or (b2 >= 0xA0 and b2 <= 0xA3) -- braille, pre-2.1 builds
end

---True for a title Claude wrote, whichever status glyph it happens to be carrying:
---the spinner above, or a dingbat asterisk (U+2733 and friends, E2 9C/9D xx). Used
---to spot a tab title that came from a Claude pane rather than from the keyboard,
---including pins saved before AUTO_TITLE_MARK existed.
local function has_claude_glyph(title)
	if is_working(title) then
		return true
	end
	local b2 = title:byte(2) or 0
	return title:byte(1) == 0xE2 and (b2 == 0x9C or b2 == 0x9D)
end

local function is_ascii_alnum(byte)
	return byte ~= nil
		and ((byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122))
end

---Drop the leading status glyph and the space after it.
---Done byte-wise on purpose: wezterm's Lua counts bytes above 0x7F as %w, so the
---character classes cannot be trusted to find where the title's words start.
local function strip_glyph(title)
	local at = 1
	while at <= #title and not is_ascii_alnum(title:byte(at)) do
		at = at + 1
	end
	if at == 1 then
		return title
	end
	return title:sub(at)
end

---@return string|nil label, boolean working, boolean silent pane exists but has announced no title
local function pane_label(pane)
	local raw = (pane.title or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if raw == "" then
		return nil, false, true
	end
	if UNINFORMATIVE[raw] then
		return nil, false, false
	end
	local working = is_working(raw)
	local label = strip_glyph(raw)
	if label == "" or UNINFORMATIVE[label] then
		return nil, false
	end
	if label == "Claude Code" then
		return "new", working -- a session Claude has not titled yet
	end
	return label, working
end

---Last resort when no pane in the tab has announced a title: name its directory.
---The Url object is only on recent wezterm, hence the pcall.
local function pane_dir(pane)
	local ok, path = pcall(function()
		local cwd = pane.current_working_dir
		return cwd and (cwd.file_path or tostring(cwd)) or nil
	end)
	if not ok or path == nil or path == "" then
		return nil
	end
	local dir = path:gsub("/+$", ""):match("([^/]+)$")
	return dir
end

local FRESH_SECONDS = 90 -- how long a finished turn still reads as just-finished
local STALE_SECONDS = 4 * 3600 -- past this, a waiting pane stops competing for attention

---What hooks/wezterm-pane-state.sh last recorded for a pane: state, the epoch it
---was written, and for "asking" the tool Claude is blocked on.
local function read_pane_state(pane_id)
	local file = io.open(pane_state_dir .. "/" .. pane_id, "r")
	if not file then
		return nil
	end
	local line = file:read("*line") or ""
	file:close()
	local state, at, detail = line:match("^(%a+)\t(%d+)\t(.*)$")
	if state == nil then
		return nil
	end
	return { state = state, at = tonumber(at), detail = detail }
end

---Resolve what a pane should look like. The spinner in the live title outranks the
---state file, which Claude may have died still holding.
---@return string status "working"|"asking"|"fresh"|"waiting"|"stale", string detail
local function pane_status(pane, spinning)
	if spinning then
		return "working", ""
	end
	local rec = read_pane_state(pane.pane_id)
	if rec == nil then
		return "waiting", "" -- no hook has run here yet: the old two-state behaviour
	end
	if rec.state == "asking" then
		return "asking", rec.detail
	end
	if rec.state == "ended" then
		return "stale", ""
	end
	-- "working" without a spinner means the turn is open but Claude is sitting at a
	-- prompt of its own, so it still wants you; erring towards visible on purpose.
	if rec.state == "working" then
		return "waiting", ""
	end
	local age = os.time() - (rec.at or 0)
	if age < FRESH_SECONDS then
		return "fresh", ""
	end
	if age > STALE_SECONDS then
		return "stale", ""
	end
	return "waiting", ""
end

-- Pane state reads by hue rather than brightness, so a split tab says at a glance
-- which session wants you. Blue and orange are the session-brief header's own
-- accent and title colours; green is calm on purpose, since a working pane needs
-- nothing from you. Mauve outranks the lot: that session is blocked on a prompt.
local TAB_COLOURS = {
	index = "#6c7086",
	divider = "#45475a",
	active = "#87d7ff", -- focused, nothing else to say
	asking = "#cba6f7", -- blocked on a permission or plan prompt
	fresh = "#f9e2af", -- finished in the last FRESH_SECONDS
	waiting = "#ffd7af", -- stopped, waiting on you
	working = "#a6e3a1", -- busy
	stale = "#6c7086", -- waited hours, or the session has exited
}

-- When only one of a tab's panes can be named, name the one that wants you most.
local NEED = { asking = 5, fresh = 4, waiting = 3, working = 2, stale = 1 }

-- Identity, which is a different question from status: not "what does this pane want"
-- but "which pane is this". Twenty sessions in one workspace are all named d5-lca-
-- something and all drawn in whatever hue their state happens to be, so the tab bar
-- could say a tab had four chats in it without saying which four.
--
-- Mocha's own accents, and they overlap TAB_COLOURS on purpose. What separates the two
-- channels is role rather than hue: identity never lands on a glyph or a marker, so in
-- this bar it colours only the terse dot - the one that is standing in for a whole pane
-- because nothing else fits. Status keeps every named label, the markers that mean
-- something (? blocked, ✓ just finished), the shape ◆ for focus, and the greys.
--
-- Keep in step with ~/.claude/bin/cc-colour, which is the same ladder and the same
-- hash: the board, the statusLine and this bar have to agree or the colour is noise.
local TAB_IDENTITY = {
	"#f5c2e7", "#cba6f7", "#89b4fa", "#74c7ec", "#94e2d5",
	"#a6e3a1", "#f9e2af", "#fab387", "#eba0ac",
}

local identity_pins = {}
local identity_pins_at = 0
local identity_pins_generation = 0
local IDENTITY_PIN_NAMES = {
	pink = 1, mauve = 2, blue = 3, sapphire = 4, teal = 5,
	green = 6, yellow = 7, peach = 8, maroon = 9,
}

---Pinned colours: the ones cc-tint chose for itself first, then the hand-pinned ones over
---the top, which is the precedence cc-colour's load_pins uses. Re-read on a timer rather
---than per paint, because this runs for every pane in every tab, once a second.
---
---Three seconds rather than ten. cc-tint writes an auto pin at the moment a session starts,
---so the timer is how long the label can disagree with the ground the pane is already
---wearing, and a disagreement between those two at exactly the moment you start a session
---is the thing this whole scheme is for. Two small file reads every three seconds.
local IDENTITY_PIN_FILES = { "/.claude/session-colours-auto", "/.claude/session-colours" }

local function load_identity_pins()
	local now = os.time()
	if now - identity_pins_at < 3 then
		return
	end
	identity_pins_at = now
	local fresh = {}
	for _, name in ipairs(IDENTITY_PIN_FILES) do
		local file = io.open(wezterm.home_dir .. name, "r")
		if file then
			for line in file:lines() do
				local id, hue = line:match("^(%S+)\t(%S+)$")
				if id and IDENTITY_PIN_NAMES[hue] then
					fresh[id] = IDENTITY_PIN_NAMES[hue]
				end
			end
			file:close()
		end
	end
	-- pane_identity caches the resolved colour, so a pin that changed has to invalidate it
	-- or the bar keeps the old hue for the rest of that cache's life.
	local changed = false
	for id, slot in pairs(fresh) do
		if identity_pins[id] ~= slot then
			changed = true
			break
		end
	end
	if not changed then
		for id in pairs(identity_pins) do
			if fresh[id] == nil then
				changed = true
				break
			end
		end
	end
	identity_pins = fresh
	if changed then
		identity_pins_generation = identity_pins_generation + 1
	end
end

---The first 8 hex digits of the session id, mod the palette. Stateless on purpose, so
---this agrees with cc-colour without either of them coordinating, and a colour survives
---/rename and --resume: the id is the one name a session never changes.
local function identity_of(session_id)
	if session_id == nil then
		return nil
	end
	load_identity_pins()
	local slot = identity_pins[session_id]
	if slot == nil then
		local head = session_id:sub(1, 8)
		slot = 1
		if head:match("^%x%x%x%x%x%x%x%x$") then
			slot = tonumber(head, 16) % #TAB_IDENTITY + 1
		end
	end
	return TAB_IDENTITY[slot]
end

-- pane id -> colour. read_session_id is a file open, and the bar repaints every pane
-- every second; the mapping only changes when a session starts in the pane.
local identity_cache = {}
local identity_cache_at = 0
local identity_cache_generation = 0

local function pane_identity(pane_id)
	local now = os.time()
	load_identity_pins()
	if now - identity_cache_at > 10 or identity_cache_generation ~= identity_pins_generation then
		identity_cache = {}
		identity_cache_at = now
		identity_cache_generation = identity_pins_generation
	end
	local hit = identity_cache[pane_id]
	if hit ~= nil then
		return hit ~= false and hit or nil
	end
	local colour = identity_of(read_session_id(pane_id))
	identity_cache[pane_id] = colour or false
	return colour
end

focused_identity = pane_identity

-- Status is a dot. Only asking and fresh get a shape of their own, because those are the
-- two you act on; everything else is the same ● in a different colour, which is what makes
-- a tab of four panes read as one row rather than as four unrelated marks. Giving each
-- state its own glyph was tried and it looked like punctuation.
--
-- The dot is also the whole of status in this bar now: the label text next to it belongs to
-- identity. One shape and two colours per pane, and no background tints, which is as few
-- things as this can be while still answering both questions.

---@return string colour, string marker, integer marker width in cells
local function status_style(status, detail, active, budget)
	if status == "asking" then
		-- with room, the marker names what it is blocked on: "?bash pool DDI ag…"
		if detail ~= "" and budget >= 20 then
			local tool = "?" .. detail:lower() .. " "
			return TAB_COLOURS.asking, tool, #tool
		end
		return TAB_COLOURS.asking, "?", 1
	end
	if status == "fresh" then
		return TAB_COLOURS.fresh, "✓", 1
	end
	-- calm blue only for the pane whose screen you are looking at; see on_screen
	if status == "waiting" and active then
		return TAB_COLOURS.active, "", 0
	end
	return TAB_COLOURS[status] or TAB_COLOURS.waiting, "", 0
end

-- Prefix is " 1: ", or " 10: " past nine tabs. Budgeted at the wider one, so a tenth tab
-- opening cannot make every label in the window one cell too long.
local PREFIX_CELLS = 5

---One label width for every pane in the window.
---
---This used to be a per-tab share, divided by that tab's pane count. Both halves were
---defensible - a busy tab has more topics to name, a tab you are looking at is worth more
---room - and together they made the same topic 13 cells wide in one tab and 18 in the next
---for reasons that were completely invisible from the bar. Every pane getting the same
---width turns out to be worth more than every tab getting a fair share, so the window is
---divided at once and the answer never depends on which tab a pane sits in.
---
---Nothing is held back either: what is left after chrome, prefixes and dividers is split
---between the panes on the bar, capped only at a whole topic each.
---@return integer cells per label, 0 when not even a terse row fits
local function label_width(tab, tabs)
	local geom = tab_geometry[tab.tab_id]
	if geom == nil then
		-- Not measured yet: the first paint after a config reload runs before any status
		-- tick. Claim room rather than guess narrow, so that frame shows labels and lets
		-- tab_max_width clip if it must, instead of flashing a bar full of dots.
		return SOLO_BUDGET
	end
	local ntabs, npanes = 0, 0
	if tabs ~= nil and #tabs > 0 then
		for _, other in ipairs(tabs) do
			ntabs = ntabs + 1
			npanes = npanes + math.max(1, #(other.panes or {}))
		end
	else
		ntabs = math.max(1, geom.tabs or 1)
		npanes = math.max(ntabs, #(tab.panes or {}) * ntabs)
	end
	-- one divider between panes inside a tab, so npanes - ntabs of them across the bar
	local chrome = ntabs * (TAB_CHROME + PREFIX_CELLS) + (npanes - ntabs) + BAR_SLACK
	local text = geom.cols - geom.reserve - chrome
	if text < npanes then
		return 0
	end
	local mine = math.max(1, #(tab.panes or {}))
	return math.max(
		1,
		math.min(
			SOLO_BUDGET,
			math.floor(text / npanes),
			-- never so wide that wezterm's own tab_max_width clips the tab back
			math.floor((config.tab_max_width - PREFIX_CELLS - mine) / mine)
		)
	)
end

wezterm.on("format-tab-title", function(tab, tabs, _, _, _, max_width)
	local prefix = " " .. (tab.tab_index + 1) .. ": "
	local pinned = tab.tab_title or ""
	local sep = pinned:find(TAB_GROUP_SEP, 1, true)
	local group = sep and (pinned:sub(1, sep - 1):gsub("^%s+", ""):gsub("%s+$", "")) or ""

	local ok, formatted = pcall(function()
		local auto_pin = sep ~= nil
			or pinned:find(AUTO_TITLE_MARK, 1, true) ~= nil
			or has_claude_glyph(pinned)
		-- A name typed without the separator is still a name, not an instruction to
		-- drop every pane label, so it becomes the group. A tab with no Claude panes
		-- builds no labels and falls through to the title exactly as typed.
		if pinned ~= "" and not auto_pin then
			group = pinned:gsub("^%s+", ""):gsub("%s+$", "")
		end

		-- A pane's is_active only means active *within its tab*, so all five tabs have
		-- one. What earns the calm colour and the bold is the pane actually on screen:
		-- a waiting pane in a tab you cannot see still has to shout.
		local on_screen = tab.is_active == true
		local labels = {}
		local silent = 0
		for _, pane in ipairs(tab.panes or { tab.active_pane }) do
			local label, working, quiet = pane_label(pane)
			if label then
				local status, detail = pane_status(pane, working)
				local fg = pane_identity(pane.pane_id)
				table.insert(labels, {
					text = label,
					active = on_screen and pane.is_active,
					status = status,
					detail = detail,
					identity = fg,
				})
			elseif quiet then
				silent = silent + 1 -- a pane that exists but has not said what it is
			end
		end
		if #labels == 0 then
			return nil
		end

		local zoomed = tab.active_pane.is_zoomed
		if zoomed then
			local label, working = pane_label(tab.active_pane)
			local status, detail = pane_status(tab.active_pane, working)
			local zfg = pane_identity(tab.active_pane.pane_id)
			labels = {
				{
					text = label or tab.active_pane.title or "",
					active = on_screen,
					status = status,
					detail = detail,
					identity = zfg,
				},
			}
		end

		local count = #labels
		local marks = (silent > 0 and not zoomed) and #(" +" .. silent) or 0
		local per = label_width(tab, tabs)
		-- Dropped when label_width has already said there is no room at all, so a name
		-- can never resurrect a zero budget into a one-cell label.
		local name = (group ~= "" and per > 0) and shorten(group, GROUP_LABEL) or ""
		local name_cost = name ~= "" and (#name + 2) or 0
		-- the +N, the name and the zoom arrow come out of the labels, not out of the bar
		if marks > 0 or zoomed or name_cost > 0 then
			per = math.max(1, per - math.ceil((marks + name_cost + (zoomed and 2 or 0)) / count))
		end
		-- What is left for a topic once a terse row has spent one cell per pane on its dot.
		-- Must come off the row's own budget: taking it off the bar instead is how a tab
		-- ends up wider than the share it was given and wezterm clips the lot.
		local spare = per * count - count

		local items = {
			{ Attribute = { Intensity = "Normal" } },
			{ Foreground = { Color = TAB_COLOURS.index } },
			{ Text = zoomed and (prefix .. "⤢ ") or prefix },
		}

		if name ~= "" then
			-- Bold in the index's own grey, so the name reads as chrome beside the tab
			-- number rather than as one more pane. No new hue: identity still means
			-- only "which session is this".
			table.insert(items, { Attribute = { Intensity = "Bold" } })
			table.insert(items, { Text = name })
			table.insert(items, { Attribute = { Intensity = "Normal" } })
			table.insert(items, { Foreground = { Color = TAB_COLOURS.divider } })
			table.insert(items, { Text = " │" })
		end

		if per == 0 or (count > 1 and per < TERSE_LABEL) then
			-- Too tight to name every pane, so drop to one glyph each. These used to be
			-- status dots, which said how many chats were in the tab and who wanted you
			-- but never which chats - and in a nine-tab window of four-way splits this
			-- row of dots is the entire tab bar, so "which" is what it has to carry.
			-- The dot takes the pane's identity colour; the two statuses that actually
			-- want you keep their own hue and their own shape (? blocked, ✓ just
			-- finished), focus stays the shape ◆ rather than a colour, and a stale pane
			-- stays grey because which chat it is has stopped mattering.
			for _, label in ipairs(labels) do
				local colour, marker = status_style(label.status, label.detail, label.active, 0)
				table.insert(items, { Attribute = { Intensity = label.active and "Bold" or "Normal" } })
				table.insert(items, { Foreground = { Color = colour } })
				table.insert(items, { Text = marker ~= "" and marker or (label.active and "◆" or "●") })
			end
			if spare >= TERSE_LABEL then
				-- one topic fits, so name whichever pane wants you rather than the one
				-- you are already looking at, whose screen is right there
				local pick = labels[1]
				for _, label in ipairs(labels) do
					if (NEED[label.status] or 0) > (NEED[pick.status] or 0) then
						pick = label
					end
				end
				table.insert(items, { Attribute = { Intensity = pick.active and "Bold" or "Normal" } })
				table.insert(items, { Foreground = { Color = pick.identity or TAB_COLOURS.waiting } })
				table.insert(items, { Text = " " .. shorten(strip_filler(pick.text), spare) })
			end
		else
			for i, label in ipairs(labels) do
				if i > 1 then
					table.insert(items, { Attribute = { Intensity = "Normal" } })
					table.insert(items, { Foreground = { Color = TAB_COLOURS.divider } })
					table.insert(items, { Text = "│" })
				end
				-- with the tab split, generic verbs are pure noise: three panes reading
				-- "Review customer…", "Review producti…" tell you nothing apart
				local text = (count > 1 or per < MIN_LABEL) and strip_filler(label.text) or label.text
				local colour, marker, marker_width =
					status_style(label.status, label.detail, label.active, per)
				if marker == "" then
					marker, marker_width = label.active and "◆" or "●", 1
				end
				-- The same dot as the terse row, then the name in the pane's own colour:
				-- the dot is what it wants, the name is which one it is. Two colours and
				-- one shape per pane, so a split tab still reads as a row.
				table.insert(items, { Attribute = { Intensity = label.active and "Bold" or "Normal" } })
				table.insert(items, { Foreground = { Color = colour } })
				-- a space after the dot: without it the status shape runs straight into
				-- Claude's own topic and the two read as one word
				table.insert(items, { Text = marker .. " " })
				table.insert(items, { Foreground = { Color = label.identity or TAB_COLOURS.waiting } })
				table.insert(items, { Text = shorten(text, math.max(1, per - marker_width - 1)) })
			end
		end

		table.insert(items, { Attribute = { Intensity = "Normal" } })
		if marks > 0 then
			-- panes that exist but have not announced a title yet, so the tab bar
			-- never understates how many chats are hiding in the split
			table.insert(items, { Foreground = { Color = TAB_COLOURS.divider } })
			table.insert(items, { Text = " +" .. silent })
		end
		table.insert(items, { Text = " " })
		return wezterm.format(items)
	end)

	if ok and formatted then
		return formatted
	end
	local title = sep and group or (pinned:gsub(AUTO_TITLE_MARK, ""))
	if title == "" then
		title = tab.active_pane.title or ""
	end
	if title == "" then
		title = pane_dir(tab.active_pane) or "…"
	end
	local room = math.max(TERSE_LABEL, label_width(tab, tabs))
	return prefix .. shorten(title, room) .. " "
end)

-- ============================================================
-- Claude: address another session
-- Every live Claude session answers to a name, and its SendMessage tool routes by
-- that name. LEADER+@ lists them by topic and types the chosen one in at the cursor,
-- so "send this to " can be finished without leaving the prompt; it lands on the
-- clipboard too, for when the target is a browser or another app.
--
-- Names default to the cwd basename plus a random suffix, so four panes in one repo
-- all look alike until /rename has been run in them. ~/.claude/bin/cc-peers is the
-- shared roster, read by Claude itself to turn "the window doing the migration"
-- into an address, and by the statusLine to end each pane with its own @name. The key is
-- @ because that is the sigil the statusLine uses; what it types is the bare name, since
-- a literal @ in the Claude prompt opens the file-mention menu instead.
-- ============================================================
local peers_script = wezterm.home_dir .. "/.claude/bin/cc-peers"

-- The statusLine's @name is the only @-token on its line, so quick-select
-- (CTRL+SHIFT+SPACE) can lift an address off the screen without a selection.
config.quick_select_patterns = { "@[a-z0-9][a-z0-9_.-]{1,48}" }

-- Same hues the tab bar uses, so a busy session reads as busy in both places.
local PEER_STATE_COLOURS = {
	busy = TAB_COLOURS.working,
	asking = TAB_COLOURS.asking,
	shell = TAB_COLOURS.fresh,
	idle = TAB_COLOURS.stale,
}

---@return table InputSelector choices, this pane's own session left out
local function claude_peer_choices(own_session)
	local ok, ran, stdout = pcall(wezterm.run_child_process, { peers_script, "--tsv" })
	if not ok or not ran then
		return {}
	end
	local choices = {}
	for line in stdout:gmatch("[^\n]+") do
		local name, session, state, _, dir, title =
			line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
		if name and name ~= "" and session ~= own_session then
			table.insert(choices, {
				id = name,
				label = wezterm.format({
					{ Foreground = { Color = TAB_COLOURS.asking } },
					{ Text = name },
					{ Foreground = { Color = PEER_STATE_COLOURS[state:match("^%a+") or ""] or TAB_COLOURS.stale } },
					{ Text = "  " .. state },
					{ Foreground = { Color = TAB_COLOURS.divider } },
					{ Text = "  " .. dir .. "  " },
					{ Foreground = { Color = TAB_COLOURS.active } },
					{ Text = title },
				}),
			})
		end
	end
	return choices
end

table.insert(config.keys, {
	key = "@",
	mods = "LEADER",
	action = wezterm.action_callback(function(window, pane)
		local choices = claude_peer_choices(read_session_id(pane:pane_id()))
		if #choices == 0 then
			window:toast_notification("wezterm", "No other live Claude sessions", nil, 2000)
			return
		end
		window:perform_action(
			act.InputSelector({
				title = "Claude sessions",
				description = "Pick a session: its name is typed in at the cursor.",
				fuzzy = true,
				fuzzy_description = "session: ",
				choices = choices,
				action = wezterm.action_callback(function(win, target, id)
					if not id then
						return
					end
					-- Not on every wezterm build, and the typed name is the point anyway.
					pcall(function()
						win:copy_to_clipboard(id)
					end)
					target:send_text(id)
				end),
			}),
			pane
		)
	end),
})

-- ============================================================
-- Claude: the fleet
-- A tab bar indexes the window you are already looking at. Past a dozen conversations
-- across a dozen workspaces that is the wrong index, and no amount of label_width fixes
-- it: the session you want is usually not in this window at all. Two gaps follow, and
-- this section closes both.
--
-- LEADER+; is the missing index. One fuzzy list of every live session in every
-- workspace, each with its state, how long since *you* last typed into it, and its
-- topic; picking one jumps there across the workspace boundary. Once that exists the tab
-- bar goes back to being a glance rather than navigation.
--
-- The right status gains a count of what wants you *elsewhere*, which nothing else here
-- can say: a pane sitting on a permission prompt two workspaces away is invisible until
-- you happen to switch to it.
--
-- ~/.claude/bin/cc-fleet is the shared roster underneath, read through cc-board, which is
-- the only layer that can see whether a stopped session finished or asked you something.
-- Its other half is the part no keybinding can do for you: `cc-fleet --stale` lists the
-- conversations you have not spoken to in hours, so they get closed rather than accumulated.
-- ============================================================
local board_script = wezterm.home_dir .. "/.claude/bin/cc-board"

local FLEET_GLYPH = {
	asking = { "⚠", TAB_COLOURS.asking },
	busy = { "◐", TAB_COLOURS.working },
	idle = { "✳", TAB_COLOURS.fresh },
	shell = { "›", TAB_COLOURS.stale },
}

-- Opens on whatever wants you rather than on whatever started first. Fuzzy search is the
-- main way in, but the top of an unfiltered list is free.
local FLEET_WEIGHT = { asking = 4, busy = 3, idle = 2, shell = 1 }

-- Past this, a session you have not prompted reads as archaeology rather than work, and
-- is dimmed in the picker. Matches cc-fleet's own default so the two agree.
local FLEET_STALE = 8 * 3600

---Time since your last prompt, in the width the picker can spare.
local function fleet_age(seconds)
	if seconds < 0 then
		return "never"
	elseif seconds < 90 then
		return "now"
	elseif seconds < 5400 then
		return string.format("%dm", seconds // 60)
	elseif seconds < 172800 then
		return string.format("%dh", seconds // 3600)
	end
	return string.format("%dd", seconds // 86400)
end

local function fleet_pad(text, width)
	if #text >= width then
		return text
	end
	return text .. string.rep(" ", width - #text)
end

---@return table InputSelector choices, id = the pane to jump to
---
---Fed by cc-board rather than cc-fleet, because cc-fleet cannot tell a session that
---finished from one that stopped to ask you something - only a pane's own screen can, and
---cc-board is what reads it. Costs about half a second to open, which is the price of the
---one column worth having.
local function fleet_choices()
	local ok, ran, stdout = pcall(wezterm.run_child_process, { board_script, "--tsv", "--all" })
	if not ok or not ran then
		return {}
	end
	local rows = {}
	for line in stdout:gmatch("[^\n]+") do
		local f = {}
		for field in (line .. "\t"):gmatch("([^\t]*)\t") do
			table.insert(f, field)
		end
		-- ws, pane, name, kind, asks, idle, pct, title, last, identity colour
		local pane = tonumber(f[2])
		if pane and f[3] ~= "" then
			local asks = f[5] == "yes"
			table.insert(rows, {
				pane = pane,
				ws = f[1],
				name = f[3],
				kind = f[4],
				asks = asks,
				idle = tonumber(f[6]) or -1,
				pct = f[7],
				title = f[8],
				last = f[9],
				identity = (f[10] or ""):match("^#%x%x%x%x%x%x$"),
				-- Waiting outranks working: one wants an answer, the other wants nothing.
				weight = asks and 5 or (FLEET_WEIGHT[f[4]] or 0),
			})
		end
	end

	table.sort(rows, function(a, b)
		if a.weight ~= b.weight then
			return a.weight > b.weight
		end
		-- Never-prompted sorts last within its state: it is a handover nobody has read.
		local ai = a.idle < 0 and math.huge or a.idle
		local bi = b.idle < 0 and math.huge or b.idle
		return ai < bi
	end)

	local choices = {}
	for _, r in ipairs(rows) do
		local marker, colour
		if r.asks then
			marker, colour = "⚠", TAB_COLOURS.asking
		else
			local glyph = FLEET_GLYPH[r.kind] or { "·", TAB_COLOURS.stale }
			marker, colour = glyph[1], glyph[2]
			if r.kind == "idle" and (r.idle < 0 or r.idle >= FLEET_STALE) then
				marker, colour = "·", TAB_COLOURS.stale
			end
		end
		local topic_colour = (marker == "·") and TAB_COLOURS.stale or TAB_COLOURS.active
		local label = {
			{ Foreground = { Color = colour } },
			{ Text = marker .. " " },
			{ Foreground = { Color = TAB_COLOURS.index } },
			{ Text = fleet_pad(r.ws, 13) },
			-- the name in the pane's own colour, the glyph above still in its state's:
			-- scanning this list for "the teal one" is the whole point of having colours
			{ Foreground = { Color = r.identity or colour } },
			{ Text = fleet_pad(r.name, 19) },
			{ Foreground = { Color = TAB_COLOURS.index } },
			{ Text = fleet_pad(fleet_age(r.idle), 6) },
			{ Foreground = { Color = topic_colour } },
			{ Text = fleet_pad(r.title, 44) },
		}
		-- The closing line last, so fuzzy matching reaches it: "staging?" finds the session
		-- asking whether to commit, without you remembering which one that was.
		if r.last ~= "" then
			table.insert(label, { Foreground = { Color = r.asks and TAB_COLOURS.asking or TAB_COLOURS.divider } })
			table.insert(label, { Text = "▸ " .. r.last })
		end
		table.insert(choices, { id = tostring(r.pane), label = wezterm.format(label) })
	end
	return choices
end

---Focus a pane wherever it lives. Two steps, because they are two different layers:
---activating at the mux level moves the focus within the pane's own workspace, and the
---workspace then has to be brought to the front.
---
---Which is a window raise, not a workspace switch. Every workspace here has its own GUI
---window, so SwitchToWorkspace would repoint *this* window at a workspace that already
---has one, leaving two windows claiming it and the one you came from showing the wrong
---desk. Falling back to a switch only for a workspace with no window of its own: one
---restored from a save, or left behind when its window was closed.
local function fleet_jump(window, pane, pane_id)
	local target = wezterm.mux.get_pane(pane_id)
	if not target then
		window:toast_notification("wezterm", "That pane has gone", nil, 2000)
		return
	end
	target:activate()

	local ok, mux_window = pcall(function()
		return target:tab():window()
	end)
	if not ok or not mux_window then
		return
	end

	-- Falling through rather than returning if the raise fails, so an older wezterm
	-- without GuiWindow:focus still lands you on the right desk via the switch below.
	local gui = mux_window:gui_window()
	if gui then
		local raised = pcall(function()
			gui:focus()
		end)
		if raised then
			return
		end
	end

	local workspace = mux_window:get_workspace()
	if workspace and workspace ~= window:active_workspace() then
		window:perform_action(act.SwitchToWorkspace({ name = workspace }), pane)
	end
end

table.insert(config.keys, {
	key = ";",
	mods = "LEADER",
	action = wezterm.action_callback(function(window, pane)
		local choices = fleet_choices()
		if #choices == 0 then
			window:toast_notification("wezterm", "No live Claude sessions", nil, 2000)
			return
		end
		window:perform_action(
			act.InputSelector({
				title = "Claude fleet",
				description = "Every live session, anywhere. ⚠ is waiting on you; dimmed is cold.",
				fuzzy = true,
				fuzzy_description = "jump to: ",
				choices = choices,
				action = wezterm.action_callback(function(win, target, id)
					if id then
						fleet_jump(win, target, tonumber(id))
					end
				end),
			}),
			pane
		)
	end),
})

-- Only two states are worth interrupting a different workspace for: blocked on a prompt,
-- and just finished. "Waiting" would be true of thirty panes at once and so says nothing.
--
-- Throttled because update-right-status fires every second and this walks the mux, but
-- the walk is the cheap half: the cost is one open() per off-window pane, so it is kept
-- to the panes that are not already on screen in front of you.
local fleet_attention = { at = 0, asking = 0, fresh = 0 }

attention_elsewhere = function(window)
	local now = os.time()
	if now - fleet_attention.at < 3 then
		return fleet_attention
	end
	fleet_attention.at = now
	fleet_attention.asking = 0
	fleet_attention.fresh = 0

	local here = {}
	local ok = pcall(function()
		for _, tab in ipairs(window:mux_window():tabs()) do
			for _, p in ipairs(tab:panes()) do
				here[p:pane_id()] = true
			end
		end
	end)
	if not ok then
		return fleet_attention
	end

	pcall(function()
		for _, mux_window in ipairs(wezterm.mux.all_windows()) do
			for _, tab in ipairs(mux_window:tabs()) do
				for _, p in ipairs(tab:panes()) do
					local id = p:pane_id()
					if not here[id] then
						local rec = read_pane_state(id)
						if rec and rec.state == "asking" then
							fleet_attention.asking = fleet_attention.asking + 1
						elseif rec and rec.state == "done" and now - (rec.at or 0) < FRESH_SECONDS then
							fleet_attention.fresh = fleet_attention.fresh + 1
						end
					end
				end
			end
		end
	end)
	return fleet_attention
end

-- ============================================================
-- Claude: the workspace board
-- LEADER+b brings up cc-board: every session in this workspace as a frame of its own,
-- coloured by what it wants from you, with context drawn as a bar and the last thing Claude
-- actually said underneath. Enter jumps to one, m marks and M moves the marked panes into
-- the tab you came from, which is the regrouping job done from one screen.
--
-- A left split of the pane you are on, sharing the space rather than covering it. It was a tab of its own first, then a zoomed split; both made it somewhere
-- you went instead of something you glance at beside the work. Unzoomed, so zoom stays
-- something you reach for - LEADER+z on it if you want the whole tab, and it reflows,
-- which is why the board measures itself every cycle rather than trusting a width it was
-- told once.
--
-- A tab with nothing running in it gets the board in place instead, since there is nothing
-- there to make room for.
--
-- Pressing it again puts it away, so the pair reads as one toggle.
-- ============================================================
local BOARD_TITLE = "▤ board"

local function board_in_tab(tab)
	for _, p in ipairs(tab:panes()) do
		local ok, title = pcall(function()
			return p:get_title()
		end)
		if ok and title == BOARD_TITLE then
			return p
		end
	end
	return nil
end

-- ============================================================
-- Claude: switch workspace, knowing what is in it
-- The stock launcher lists workspace names, which at thirteen of them is thirteen words with
-- nothing to choose between. This adds what is in each, in the glyphs the tab bar and the
-- status bar already use: ⚠ blocked on a prompt, ✓ just finished, ✳ stopped and waiting on
-- you, ◐ working, · cold for hours, › a pane whose session has exited. Then the topic of
-- whichever session wants you most, and the branch they are all sharing with a count of
-- dirty files - usually the deciding fact, since a workspace with a dirty tree and three
-- chats waiting is where you should be.
--
-- The counts replace one that was wrong twice over. It called a workspace's "waiting" count
-- asking+busy, so a session happily working read as one wanting you, which is the opposite
-- of what busy means; and a single number could not say whether six chats were blocked, done
-- or cold, which is the only thing you press this key to find out.
--
-- The order is alt-tab: most recently used first, so row one is the workspace you just came
-- from and LEADER+w Enter flips back to it. Deliberately not ranked by who wants you - a list
-- that reorders itself between presses cannot be learned, and the glyph and its colour say
-- who wants you without moving anything. The workspace you are in sits at the bottom, out of
-- the way, for the same reason alt-tab starts on the second window rather than the first.
--
-- Nothing here forks. Every count comes from the mux and from the state files under
-- ~/.claude/wezterm-state that pane_status already reads for the tab bar, so the picker
-- opens in the time it takes to draw. Reading pane screens is what would make it accurate
-- about a session that stopped mid-prose on a question, and it is also what costs a third of
-- a second, so that stays where it belongs: LEADER+; and LEADER+b read screens, this key
-- picks a desk. Git is the one fact no hook writes down, so it arrives from a snapshot taken
-- in the background and is read here from a file.
--
-- Workspaces with no Claude session in them are still listed, dimmed: they are where new
-- work goes.
-- ============================================================

-- Drawn in the order NEED ranks them, whatever wants you most first, so the ⚠ column is
-- always in the same place and the row it is on is the only thing that changes. "ended" is
-- pane_status's stale split in two, because a session that has exited is a pane to close
-- rather than a chat to go back to.
local WS_STATES = {
	{ key = "asking", glyph = "⚠", colour = TAB_COLOURS.asking },
	{ key = "fresh", glyph = "✓", colour = TAB_COLOURS.fresh },
	{ key = "waiting", glyph = "✳", colour = TAB_COLOURS.waiting },
	{ key = "working", glyph = "◐", colour = TAB_COLOURS.working },
	{ key = "stale", glyph = "·", colour = TAB_COLOURS.stale },
	{ key = "ended", glyph = "›", colour = TAB_COLOURS.stale },
}

local WS_NAME_W = 18
local WS_COUNT_W = 9
local WS_STATE_W = 18
local WS_GIT_W = 22

---fleet_pad counts bytes, which is right for the ASCII columns and wrong for any column with
---a glyph in it. Columns that tracked their own cell width pad with this instead, never to
---zero, so two of them cannot run together.
local function ws_pad(used, target)
	return string.rep(" ", math.max(1, target - used))
end

-- Most recent first. Kept in a file rather than in memory because editing this config
-- re-evaluates it, and an in-memory order would reset to alphabetical on every save - which
-- is the one thing an alt-tab order cannot do.
local ws_mru_path = wezterm.home_dir .. "/.claude/cache/wezterm-mru"
local WS_MRU_MAX = 40
local ws_mru

local function ws_mru_read()
	if ws_mru ~= nil then
		return ws_mru
	end
	ws_mru = {}
	local file = io.open(ws_mru_path, "r")
	if file then
		for line in file:lines() do
			if line ~= "" then
				table.insert(ws_mru, line)
			end
		end
		file:close()
	end
	return ws_mru
end

---Move a workspace to the front, and write it out only when the front actually changed: this
---runs once a second off the status bar.
ws_touch = function(ws)
	if ws == nil or ws == "" then
		return
	end
	local list = ws_mru_read()
	if list[1] == ws then
		return
	end
	for i, name in ipairs(list) do
		if name == ws then
			table.remove(list, i)
			break
		end
	end
	table.insert(list, 1, ws)
	while #list > WS_MRU_MAX do
		table.remove(list)
	end
	local file = io.open(ws_mru_path, "w")
	if file then
		file:write(table.concat(list, "\n") .. "\n")
		file:close()
	end
end

---One directory per workspace: whatever its first pane is sitting in. They nearly all share
---a checkout, which is the assumption cc-board's own header makes too.
local function workspace_dirs()
	local dirs = {}
	pcall(function()
		for _, mux_window in ipairs(wezterm.mux.all_windows()) do
			local ws = mux_window:get_workspace()
			if ws and dirs[ws] == nil then
				for _, tab in ipairs(mux_window:tabs()) do
					for _, p in ipairs(tab:panes()) do
						local got, cwd = pcall(function()
							return p:get_current_working_dir()
						end)
						if got and cwd then
							dirs[ws] = cwd.file_path or (tostring(cwd):gsub("^file://[^/]*", ""))
							break
						end
					end
					if dirs[ws] then
						break
					end
				end
			end
		end
	end)
	return dirs
end

-- $1 is the cache to write, the rest are the directories to look at. Built in a temp file
-- and moved into place, so a picker opening mid-snapshot reads the last whole one rather
-- than half of this one.
local WS_GIT_SNAPSHOT = [[
out=$1
shift
mkdir -p "${out%/*}" 2>/dev/null
tmp="$out.$$"
: >"$tmp"
for dir in "$@"; do
	branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || continue
	[ -n "$branch" ] || continue
	dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
	printf '%s\t%s\t%s\n' "$dir" "$branch" "$dirty" >>"$tmp"
done
mv "$tmp" "$out"
]]

local ws_git_path = wezterm.home_dir .. "/.claude/cache/wezterm-git"
local WS_GIT_INTERVAL = 90 -- a branch changes when you check out, not while you read a list
local ws_git_at = 0

---Kick a snapshot and do not wait for it. Called from the status bar so the cache is warm
---before the first keypress, and again on the way out of the picker so the next one is
---current. A git call per workspace is a fifth of a second of nothing happening, which is
---the difference between a picker and a pause.
ws_git_refresh = function()
	local now = os.time()
	if now - ws_git_at < WS_GIT_INTERVAL then
		return
	end
	ws_git_at = now
	local args = { "/bin/sh", "-c", WS_GIT_SNAPSHOT, "wezterm-git", ws_git_path }
	local seen = {}
	for _, dir in pairs(workspace_dirs()) do
		if dir ~= "" and not seen[dir] then
			seen[dir] = true
			table.insert(args, dir)
		end
	end
	if #args > 5 then
		pcall(wezterm.background_child_process, args)
	end
end

---@return table directory -> { branch, dirty }, empty until the first snapshot lands
local function read_git_snapshot()
	local map = {}
	local file = io.open(ws_git_path, "r")
	if not file then
		return map
	end
	for line in file:lines() do
		local dir, branch, dirty = line:match("^([^\t]*)\t([^\t]*)\t(%d*)$")
		if dir then
			map[dir] = { branch = branch, dirty = tonumber(dirty) or 0 }
		end
	end
	file:close()
	return map
end

workspace_picker = function(window, pane)
	local rooms = {}
	local order = {}

	local function room(ws)
		if rooms[ws] == nil then
			local r = { chats = 0, named = -1, weight = -1, at = 0, topic = "" }
			for _, st in ipairs(WS_STATES) do
				r[st.key] = 0
			end
			rooms[ws] = r
			table.insert(order, ws)
		end
		return rooms[ws]
	end

	for _, mux_window in ipairs(wezterm.mux.all_windows()) do
		-- Listed even with nothing in it, so an empty workspace is still somewhere you can go.
		local ws = mux_window:get_workspace()
		local r = ws and room(ws)
		for _, tab in ipairs(r and mux_window:tabs() or {}) do
			for _, p in ipairs(tab:panes()) do
				local ok, title = pcall(function()
					return p:get_title()
				end)
				title = (ok and title) or ""
				local id = p:pane_id()
				local rec = read_pane_state(id)
				-- A pane is a chat if a hook has written state for it or if Claude has titled
				-- it; anything else in the tab is a shell and none of this key's business.
				if rec ~= nil or has_claude_glyph(title) then
					local status
					if rec ~= nil and rec.state == "ended" then
						status = "ended"
					else
						status = pane_status({ pane_id = id, title = title }, is_working(title))
					end
					r[status] = r[status] + 1
					if status ~= "ended" then
						r.chats = r.chats + 1
					end
					-- Which session speaks for the workspace: a titled one first, since "new" as a
					-- topic says less than the counts beside it already do, then the loudest,
					-- then the one that moved most recently - the thread you were actually on.
					local label = pane_label({ title = title })
					local weight = NEED[status] or 0
					local named = (label ~= nil and label ~= "new") and 1 or 0
					local at = (rec and rec.at) or 0
					if named > r.named
						or (named == r.named and weight > r.weight)
						or (named == r.named and weight == r.weight and at > r.at)
					then
						r.named = named
						r.weight = weight
						r.at = at
						r.topic = label or r.topic
					end
				end
			end
		end
	end

	local current = window:active_workspace()

	-- Alt-tab: where you have been, most recent first, then a fixed tail of everywhere you
	-- have not, then where you already are.
	local rank = {}
	for i, name in ipairs(ws_mru_read()) do
		if rank[name] == nil then
			rank[name] = i
		end
	end
	table.sort(order, function(a, b)
		if (a == current) ~= (b == current) then
			return b == current -- you are already there
		end
		local ra, rb = rank[a], rank[b]
		if (ra ~= nil) ~= (rb ~= nil) then
			return ra ~= nil -- somewhere you have been beats somewhere you have not
		end
		if ra and rb then
			return ra < rb
		end
		-- Not visited yet, so nothing to be recent about: chats first, then the empties,
		-- which are somewhere to start work rather than somewhere to go back to.
		local ca, cb = rooms[a].chats > 0, rooms[b].chats > 0
		if ca ~= cb then
			return ca
		end
		return a < b
	end)

	local dirs = workspace_dirs()
	local git = read_git_snapshot()
	local choices = {}
	for _, ws in ipairs(order) do
		local r = rooms[ws]

		local marker, colour = " ", TAB_COLOURS.stale
		for _, st in ipairs(WS_STATES) do
			if r[st.key] > 0 then
				marker = st.glyph
				colour = st.colour
				break
			end
		end

		local detail = r.chats .. (r.chats == 1 and " chat" or " chats")
		if r.chats == 0 then
			detail = r.ended > 0 and "exited" or "empty"
		end

		local label = {
			{ Foreground = { Color = colour } },
			{ Text = marker .. " " },
			{ Foreground = { Color = r.chats > 0 and colour or TAB_COLOURS.stale } },
			{ Text = (ws == current and "▸ " or "  ") .. ws .. ws_pad(2 + #ws, WS_NAME_W) },
			{ Foreground = { Color = TAB_COLOURS.index } },
			{ Text = fleet_pad(detail, WS_COUNT_W) },
		}

		local used = 0
		for _, st in ipairs(WS_STATES) do
			local n = r[st.key]
			if n > 0 then
				table.insert(label, { Foreground = { Color = st.colour } })
				table.insert(label, { Text = st.glyph .. n .. " " })
				used = used + 2 + #tostring(n)
			end
		end

		-- The dirty count is never the part to drop, so the branch is measured against what
		-- is left after it: a long branch name loses its tail rather than pushing the topic.
		local repo = git[dirs[ws] or ""]
		local git_text, git_w = "", 0
		if repo then
			local dirty_w = repo.dirty > 0 and (2 + #tostring(repo.dirty)) or 0
			git_text = shorten(repo.branch, WS_GIT_W - 1 - dirty_w)
			git_w = #git_text - (git_text:sub(-3) == "…" and 2 or 0) + dirty_w
			if repo.dirty > 0 then
				git_text = git_text .. " ✎" .. repo.dirty
			end
		end
		table.insert(label, { Foreground = { Color = TAB_COLOURS.index } })
		table.insert(label, { Text = ws_pad(used, WS_STATE_W) .. git_text .. ws_pad(git_w, WS_GIT_W) })

		-- The topic last, so fuzzy matching reaches it: "wezterm" finds the desk the wezterm
		-- work is on without you remembering what that workspace ended up being called.
		if r.topic ~= "" then
			local cold = r.weight <= NEED.stale
			table.insert(label, { Foreground = { Color = cold and TAB_COLOURS.stale or TAB_COLOURS.active } })
			table.insert(label, { Text = r.topic })
		end

		table.insert(choices, { id = ws, label = wezterm.format(label) })
	end

	window:perform_action(
		act.InputSelector({
			title = "Workspaces",
			description = "Alt-tab order. ⚠ blocked · ✓ just finished · ✳ waiting on you · ◐ working · · cold · › exited",
			fuzzy = true,
			fuzzy_description = "workspace: ",
			choices = choices,
			action = wezterm.action_callback(function(win, target, ws)
				if not ws then
					return
				end
				ws_touch(ws) -- the status bar would catch this a second later; do not wait
				-- A workspace with a GUI window of its own gets raised; one whose mux
				-- window is detached, or a name typed into the picker, falls through to a
				-- switch in the current window.
				for _, mux_window in ipairs(wezterm.mux.all_windows()) do
					if mux_window:get_workspace() == ws then
						-- gui_window() RAISES for a mux window with no GUI window attached,
						-- it does not return nil, so it needs the pcall too or a detached
						-- workspace aborts the callback before the switch below.
						local got, gui = pcall(function()
							return mux_window:gui_window()
						end)
						if got and gui and pcall(function()
							gui:focus()
						end) then
							return
						end
					end
				end
				win:perform_action(act.SwitchToWorkspace({ name = ws }), target)
			end),
		}),
		pane
	)

	-- On the way out, not the way in: the snapshot the list was drawn from is the one taken
	-- last time, and this is what makes the next press current.
	ws_git_refresh()
end

-- Zoom hides every pane but one, so a board opened into a zoomed tab would be invisible and
-- the next press would open a second one.
local function tab_is_zoomed(tab)
	for _, p in ipairs(tab:panes_with_info()) do
		if p.is_zoomed then
			return true
		end
	end
	return false
end

-- The one board, wherever it currently is. There is never more than one: LEADER+b in a tab
-- that has not got it moves the running pane here rather than starting another, so the
-- filter, the marks, the grouping and the cursor survive, and one process is reading pane
-- screens rather than one per tab you happened to press the key in.
local function board_in_window(window)
	local ok, tabs = pcall(function()
		return window:mux_window():tabs()
	end)
	if not ok or not tabs then
		return nil, nil
	end
	for _, t in ipairs(tabs) do
		local p = board_in_tab(t)
		if p then
			return p, t
		end
	end
	return nil, nil
end

-- The far left of the tab, however the tab is arranged. Splitting off this pane rather than
-- off the focused one is what puts the board down the left edge instead of wherever you
-- happened to be standing when you pressed the key.
local function leftmost_pane(tab)
	local best, found
	for _, p in ipairs(tab:panes_with_info()) do
		if not best or p.left < best.left or (p.left == best.left and p.top < best.top) then
			best = p
			found = p.pane
		end
	end
	return found
end

-- A tab with nothing ongoing in it is somewhere the board can just live, rather than
-- somewhere it has to make room. "Ongoing" means a pane actually running Claude: a tab of
-- shells, or one whose sessions have exited, is scratch space.
local function tab_has_live_claude(tab)
	for _, p in ipairs(tab:panes()) do
		local ok, info = pcall(function()
			return p:get_foreground_process_info()
		end)
		if ok and info and is_claude(info.argv or {}) then
			return true
		end
	end
	return false
end

table.insert(config.keys, {
	key = "b",
	mods = "LEADER",
	action = wezterm.action_callback(function(window, pane)
		local tab = window:active_tab()
		local open = board_in_tab(tab)
		-- Zoomed on something else, so the board may be there and hidden. Unzoom and look
		-- again rather than opening a second one on top of it.
		if not open and tab_is_zoomed(tab) then
			pcall(function()
				tab:set_zoomed(false)
			end)
			open = board_in_tab(tab)
		end

		-- One key both ways. Quitting rather than killing, because the board may be running
		-- in a shell pane that was already there and is not ours to close.
		if open then
			pcall(function()
				tab:set_zoomed(false)
			end)
			pcall(function()
				open:send_text("q")
			end)
			return
		end

		local env = {
			CC_BOARD_ORIGIN = tostring(pane:pane_id()),
			CC_BOARD_TITLE = BOARD_TITLE,
		}

		if not tab_has_live_claude(tab) then
			-- Nothing to make room for, so it runs where you already are. Typed at the
			-- prompt rather than spawned, since the shell in that pane is not ours to
			-- replace; quitting the board leaves you back at it.
			pcall(function()
				pane:send_text(
					"CC_BOARD_ORIGIN=" .. env.CC_BOARD_ORIGIN ..
					" CC_BOARD_TITLE='" .. BOARD_TITLE .. "' " .. board_script .. "\n"
				)
			end)
			return
		end

		-- Open somewhere else in this workspace: move it here rather than starting a second
		-- one. Nothing in the lua API moves a pane between tabs, so this is the same
		-- `split-pane --move-pane-id` the board's own M key uses.
		local elsewhere, from_tab = board_in_window(window)
		if elsewhere then
			pcall(function()
				from_tab:set_zoomed(false)
			end)
			local host = leftmost_pane(tab) or pane
			local moved = false
			pcall(function()
				moved = wezterm.run_child_process({
					wezterm.executable_dir .. "/wezterm", "cli", "split-pane",
					"--pane-id", tostring(host:pane_id()),
					"--move-pane-id", tostring(elsewhere:pane_id()),
					"--left",
				})
			end)
			if moved then
				pcall(function()
					elsewhere:activate()
					tab:set_zoomed(true)
				end)
				return
			end
			-- Could not move it - no room in this tab, most likely. Leave it where it is and
			-- go to it, which is worse than bringing it here and better than a second board.
			pcall(function()
				elsewhere:activate()
				from_tab:activate()
				from_tab:set_zoomed(true)
			end)
			return
		end

		-- Split off the leftmost pane rather than the focused one, so the board is the left
		-- hand column of the tab wherever you were standing, and zoom it: full width is the
		-- size you actually read the fleet at, and LEADER+z drops back to the tab with the
		-- board still down its left edge.
		--
		-- Not a top_level split, which is the obvious way to get a full height column and
		-- the way that wedged a live tab: wezterm redistributes the reclaimed width
		-- unevenly, three of four panes collapsed to a single column, adjust-pane-size
		-- snapped straight back, and further splits failed with "No space for split!" until
		-- the window was resized.
		local host = leftmost_pane(tab) or pane
		local board
		local ok = pcall(function()
			board = host:split({
				direction = "Left",
				args = { "/bin/zsh", "-lc", board_script },
				set_environment_variables = env,
			})
		end)
		-- The leftmost pane can be too narrow to halve. The pane you are on is a worse
		-- place for it but a better one than a toast saying no.
		if not ok and host ~= pane then
			ok = pcall(function()
				board = pane:split({
					direction = "Left",
					args = { "/bin/zsh", "-lc", board_script },
					set_environment_variables = env,
				})
			end)
		end
		if not ok then
			window:toast_notification("wezterm", "could not open the board", nil, 2000)
			return
		end
		pcall(function()
			if board then
				board:activate()
			end
			tab:set_zoomed(true)
		end)
	end),
})

return config
