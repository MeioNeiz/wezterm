local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

-- config_builder() raises on unknown field and a raise discards the whole config. Field
-- names vary by version, so optional ones go through here.
-- Check: `wezterm --config-file wezterm.lua ls-fonts 2>&1 | grep ERROR`
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
-- Appearance
-- ============================================================
config.font = wezterm.font_with_fallback({
	{ family = "JetBrains Mono", weight = "Regular" },
})
config.font_size = 14.0
config.line_height = 1.0
config.harfbuzz_features = { "calt=1", "liga=1", "clig=1" } -- programming ligatures

config.color_scheme = "Catppuccin Mocha"
-- Lighter than the 0.8 default: FAINT text in an unfocused pane stays at 3.5:1 on base.
-- Saturation left at the default so the cc-tint identity survives.
config.inactive_pane_hsb = { saturation = 0.9, brightness = 0.85 }
config.window_background_opacity = 1.0
config.window_padding = { left = 4, right = 4, top = 2, bottom = 0 }
config.adjust_window_size_when_changing_font_size = false
config.audible_bell = "Disabled"
config.scrollback_lines = 50000

-- Tab bar. fancy_tab_bar.rs caps every tab at `pixel_width / num_tabs - 1.5 cells`,
-- unconditionally. Cap is in PIXELS, so more characters means a narrower frame font
-- (FRAME_FONT_SIZE). Retro bar: no per-tab cap but draws in the 14pt terminal font, so
-- fewer cells overall. Flip to false and label_width switches models, see FANCY.
config.use_fancy_tab_bar = true
-- no macOS title bar; RESIZE keeps window draggable/resizable
config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.tab_bar_at_bottom = false
config.hide_tab_bar_if_only_one_tab = false
-- Deliberately loose: format-tab-title only sees this config value, not the room left.
-- Real sharing is in label_width; this must just never bind first.
config.tab_max_width = 320
-- Fancy bar draws in window_frame.font, NOT terminal cells; label_width converts via
-- FRAME_CELLS. Pinned so an upgrade cannot move the default. Smaller = more chars per tab
-- (per-tab cap is pixels) but below 12 is unreadable here.
local FRAME_FONT_SIZE = 12.0
config.window_frame = {
	font = wezterm.font({ family = "Roboto", weight = "Bold" }),
	font_size = FRAME_FONT_SIZE,
	-- no native title bar, so this IS the window top; crust matches the tab bar bg
	active_titlebar_bg = "#11111b",
	inactive_titlebar_bg = "#11111b",
}
-- Frame chars per terminal cell: point-size ratio x advance (Roboto Bold ~0.52em avg vs
-- JetBrains Mono 0.586em = 1.13). MARGIN shades down since proportional widths vary and
-- overshoot makes wezterm clip. Monospace frame font: both become 1.0.
local FRAME_ADVANCE = 1.13
local FRAME_MARGIN = 0.9
-- retro bar draws in terminal font: a cell is a cell
local FANCY = config.use_fancy_tab_bar == true
local FRAME_CELLS = FANCY and ((config.font_size / FRAME_FONT_SIZE) * FRAME_ADVANCE * FRAME_MARGIN)
	or 1.0
-- try_set: field name differs across versions and a wrong one discards the whole config
try_set("show_close_tab_button_in_tabs", false)
-- also the tab bar's pane-state re-read rate, see update-right-status
config.status_update_interval = 1000

-- Invisible mark on a title pinned by the save layer (vs typed via LEADER+,), so live
-- pane topics can win over a stale pin.
local AUTO_TITLE_MARK = "\u{2063}"

-- "dtmf \": text before first backslash is a typed name, the live pane row fills the
-- rest. No backslash = typed title shown as is.
local TAB_GROUP_SEP = "\\"

-- Windows, optional:
-- if is_windows then
-- 	config.default_prog = { "pwsh.exe", "-NoLogo" }
-- end

-- ============================================================
-- Session persistence: resurrect.wezterm, every workspace plus each pane's Claude session.
-- Not the plugin's periodic_save: it only snapshots the active workspace.
-- ============================================================
local resurrect = wezterm.plugin.require("https://github.com/MLFlexer/resurrect.wezterm")

local session_map_dir = wezterm.home_dir .. "/.claude/wezterm-sessions"
-- cc-tint's paint record; only here to be wiped with the other pane-keyed state
local painted_dir = wezterm.home_dir .. "/.claude/cache/cc-tint-painted"
-- written by hooks/wezterm-pane-state.sh
local pane_state_dir = wezterm.home_dir .. "/.claude/wezterm-state"
local brief_script = wezterm.home_dir .. "/.claude/hooks/claude-session-brief.py"
local save_interval_seconds = 120

-- ============================================================
-- Registry half of pane state, via `cc-roster --digest` (hooks are the other half; see
-- pane_status and CLAUDE.md). jq over the registry is too slow for a 1s tick, so a
-- background process writes one file and this reads it.
local digest_path = wezterm.home_dir .. "/.claude/cache/fleet-digest"
local digest_writer = wezterm.home_dir .. "/.claude/bin/cc-roster"
local DIGEST_MAX_AGE = 5
local digest = { read_at = 0, epoch = 0, rows = {} }

---Rows keyed by pane id, reparsed at most once a second
local function digest_rows()
	local now = os.time()
	if now == digest.read_at then
		return digest.rows
	end
	digest.read_at = now
	local file = io.open(digest_path, "r")
	if not file then
		digest.rows = {}
		return digest.rows
	end
	local rows = {}
	for line in file:lines() do
		local stamp = line:match("^#(%d+)$")
		if stamp then
			digest.epoch = tonumber(stamp)
		else
			local pane, sid, status, detail, seen =
				line:match("^(%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(%d+)$")
			if pane then
				-- registry is ms, everything else here is s
				rows[pane] = {
					sid = sid,
					status = status,
					detail = detail,
					seen = math.floor(tonumber(seen) / 1000),
				}
			end
		end
	end
	file:close()
	digest.rows = rows
	return rows
end

---Every window calls this, so duplicate writes in one second are possible; accepted, the
---write is atomic and cheaper than electing an owner window.
local function digest_refresh()
	digest_rows()
	if os.time() - digest.epoch < DIGEST_MAX_AGE then
		return
	end
	-- claim locally so a broken cc-roster is retried per DIGEST_MAX_AGE, not per second
	digest.epoch = os.time()
	wezterm.background_child_process({ digest_writer, "--digest" })
end

local function is_claude(argv)
	return argv ~= nil and argv[1] ~= nil and argv[1]:match("claude$") ~= nil
end

-- Saved tree drops pane ids and pids; cwd + start_time identify a pane across the save.
-- Collides only for two claudes started in one cwd in the same second.
local function process_key(cwd, start_time)
	return tostring(cwd) .. "\0" .. tostring(start_time)
end

-- tab bar, attention counts and pickers read the same panes in the same tick
local function memo_per_second(read)
	local at, hits = 0, {}
	return function(key)
		local now = os.time()
		if now ~= at then
			at, hits = now, {}
		end
		local hit = hits[key]
		if hit == nil then
			hit = read(key)
			if hit == nil then
				hit = false
			end
			hits[key] = hit
		end
		return hit or nil
	end
end

local read_session_id = memo_per_second(function(pane_id)
	local file = io.open(session_map_dir .. "/" .. pane_id, "r")
	if not file then
		return nil
	end
	local id = file:read("*line")
	file:close()
	if id and id:match("^[%x%-]+$") then
		return id
	end
end)

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

-- a resumed pane's --resume id may be superseded; drop old flags before adding current
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
	-- walk both subtrees, no short-circuit
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
					-- restored pane title is just "zsh"; pin Claude topic until it resumes
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

	-- manifest decides what comes back: saved states are never deleted, so globbing the
	-- dir would resurrect every workspace ever
	local manifest = io.open(resurrect.state_manager.save_state_dir .. "live_workspaces", "w")
	if manifest then
		manifest:write(table.concat(live_names, "\n"))
		manifest:close()
	end

	return saved
end

-- Claude panes restore armed: resume typed but not run, under a brief header, so not
-- every session reconnects at once.
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

	-- no manifest: fall back to the dir
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
	-- pane ids restart from 0 with a new mux, so every pane-keyed file would mis-attribute
	-- (a stale paint record makes a new session avoid the old pane's colour). Needed ids
	-- are in the saved states.
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
		-- fresh opts per workspace: restore_workspace writes window/tab/pane back into it
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

-- reload starts a new timer chain without stopping the old; GLOBAL generation stops it
wezterm.GLOBAL.save_generation = (wezterm.GLOBAL.save_generation or 0) + 1
local function periodic_save_all(generation)
	wezterm.time.call_after(save_interval_seconds, function()
		if wezterm.GLOBAL.save_generation ~= generation then
			return
		end
		local ok, err = pcall(save_all_workspaces)
		if not ok then
			wezterm.log_error("resurrect: periodic save failed: " .. tostring(err))
		end
		periodic_save_all(generation)
	end)
end
periodic_save_all(wezterm.GLOBAL.save_generation)

-- ============================================================
-- Multiplexing keybindings (leader = CTRL-Space, tmux-style)
-- ============================================================
config.leader = { key = "Space", mods = "CTRL", timeout_milliseconds = 1000 }

-- assigned in the fleet section; declared here since config.keys closes over it
local workspace_picker


config.keys = {
	-- Press leader then Ctrl-Space to send a literal Ctrl-Space to the shell
	{ key = "Space", mods = "LEADER|CTRL", action = act.SendKey({ key = "Space", mods = "CTRL" }) },

	-- ---- Panes: split the current pane ----
	{ key = "\\", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) }, -- right
	{ key = "-", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) }, -- down

	-- ---- Panes: move focus (vim hjkl) ----
	{ key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
	{ key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
	{ key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },

	-- ---- Panes: manage ----
	{ key = "z", mods = "LEADER", action = act.TogglePaneZoomState },
	{ key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
	{ key = "Space", mods = "LEADER", action = act.PaneSelect },
	{ key = "o", mods = "LEADER", action = act.RotatePanes("Clockwise") },
	{ key = "s", mods = "LEADER", action = act.PaneSelect({ mode = "SwapWithActive" }) },
	{ key = "m", mods = "LEADER", action = wezterm.action_callback(function(_, pane)
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
	{ key = "n", mods = "LEADER", action = act.SwitchWorkspaceRelative(1) },
	{ key = "p", mods = "LEADER", action = act.SwitchWorkspaceRelative(-1) },

	-- ---- Session persistence (resurrect): Save / Restore ----
	{ key = "S", mods = "LEADER", action = wezterm.action_callback(function(win, _)
		local saved = save_all_workspaces()
		win:toast_notification("wezterm", "Saved " .. saved .. " workspaces", nil, 2000)
	end) },
	{ key = "R", mods = "LEADER", action = wezterm.action_callback(function(win, pane)
		resurrect.fuzzy_loader.fuzzy_load(win, pane, function(id)
			local kind = string.match(id, "^([^/]+)") -- workspace | window | tab
			id = string.match(id, "([^/]+)$")
			id = string.match(id, "(.+)%..+$")
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
	-- prompt to prompt: needs the shell integration sourced in .zshrc
	{ key = "UpArrow", mods = "LEADER", action = act.ScrollToPrompt(-1) },
	{ key = "DownArrow", mods = "LEADER", action = act.ScrollToPrompt(1) },
}

-- Direct tab access: LEADER + 1..9
for i = 1, 9 do
	table.insert(config.keys, {
		key = tostring(i),
		mods = "LEADER",
		action = act.ActivateTab(i - 1),
	})
end

-- LEADER+Tab flips to the tab you were last on; closing a tab lands there too
config.switch_to_last_active_tab_when_closing_tab = true
table.insert(config.keys, { key = "Tab", mods = "LEADER", action = act.ActivateLastTab })

-- Open a URL on screen from the keyboard: labels every link, the letter opens it
table.insert(config.keys, {
	key = "u",
	mods = "LEADER",
	action = act.QuickSelectArgs({
		label = "open url",
		patterns = { "https?://[^\\s\"'<>()]+" },
		action = wezterm.action_callback(function(window, pane)
			wezterm.open_with(window:get_selection_text_for_pane(pane))
		end),
	}),
})

-- links open on CMD+click only: plain click is how a pane gets focus back
config.mouse_bindings = {
	{
		event = { Up = { streak = 1, button = "Left" } },
		mods = "NONE",
		action = act.CompleteSelection("ClipboardAndPrimarySelection"),
	},
	{
		event = { Up = { streak = 1, button = "Left" } },
		mods = "CMD",
		action = act.OpenLinkAtMouseCursor,
	},
	-- else CMD-down starts a selection and the Up never sees a link
	{ event = { Down = { streak = 1, button = "Left" } }, mods = "CMD", action = act.Nop },
}

-- OSC 9 / toasts from the pane you are looking at are noise; from any other pane, not
config.notification_handling = "SuppressFromFocusedPane"

-- Close: CTRL+SHIFT+W pane, CTRL+SHIFT+Q tab, same on every OS
table.insert(config.keys, { key = "w", mods = "CTRL|SHIFT", action = act.CloseCurrentPane({ confirm = true }) })
table.insert(config.keys, { key = "q", mods = "CTRL|SHIFT", action = act.CloseCurrentTab({ confirm = true }) })

-- binding CMD+W overrides wezterm's built-in (close tab)
if is_macos then
	table.insert(config.keys, { key = "w", mods = "CMD", action = act.CloseCurrentPane({ confirm = true }) })
	table.insert(config.keys, { key = "w", mods = "CMD|SHIFT", action = act.CloseCurrentTab({ confirm = true }) })
	-- menu Quit bypasses this; periodic save is the backstop
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
-- Status bar: LEADER, resize mode, workspace.
-- Also the tab bar's heartbeat: format-tab-title only reruns on invalidation, and hook
-- writes or ageing past FRESH_SECONDS have no wezterm event. Status only invalidates when
-- the string changes, so the trailing blank toggles space/NBSP: same cell, new bytes.
-- ============================================================
local tab_geometry = {} -- tab id -> the bar's size; see label_width
local status_tick = 0

-- Forward decls, assigned in the fleet section (they need things defined later)
local attention_elsewhere

local ws_git_refresh

-- stamps the focused workspace for LEADER+w's alt-tab order; only the status tick sees
-- every route of arrival
local ws_touch

-- workspace name takes the focused pane's identity colour
local focused_identity

-- see "the chime" at the foot
local chime_overdue

---Shell -> Lua action queue: the CLI cannot switch workspace (activate-pane leaves the GUI
---where it was) and SetUserVar is dead on this build (CLAUDE.md). One tab-separated line
---per action; claimed by atomic rename so exactly one window drains a batch.
local ACTION_FILE = "/.claude/fleet/actions"

local function perform_action_line(window, pane, verb, a, b)
	if verb == "workspace" and a and a ~= "" then
		window:perform_action(act.SwitchToWorkspace({ name = a }), pane)
	elseif verb == "goto" and a and a ~= "" then
		-- workspace first: activating before the switch lands loses focus to it
		if b and b ~= "" then
			window:perform_action(act.SwitchToWorkspace({ name = b }), pane)
		end
		local id = tonumber(a)
		if id then
			pcall(function()
				for _, w in ipairs(wezterm.mux.all_windows()) do
					for _, t in ipairs(w:tabs()) do
						for _, p in ipairs(t:panes()) do
							if p:pane_id() == id then
								t:activate()
								p:activate()
								return
							end
						end
					end
				end
			end)
		end
	elseif verb == "toast" then
		-- not osascript, which toasts as Script Editor
		window:toast_notification(a or "wezterm", b or "", nil, 8000)
	end
end

local function drain_actions(window, pane)
	local path = wezterm.home_dir .. ACTION_FILE
	local probe = io.open(path, "r")
	if not probe then
		return
	end
	probe:close()
	local claimed = path .. ".taken." .. tostring(window:window_id())
	if not os.rename(path, claimed) then
		return -- another window got this batch
	end
	local file = io.open(claimed, "r")
	if not file then
		return
	end
	for line in file:lines() do
		local verb, a, b = line:match("^([^\t]*)\t?([^\t]*)\t?(.*)$")
		if verb and verb ~= "" then
			pcall(perform_action_line, window, pane, verb, a, b)
		end
	end
	file:close()
	os.remove(claimed)
end

wezterm.on("update-right-status", function(window, pane)
	drain_actions(window, pane)
	digest_refresh()
	if chime_overdue then
		pcall(chime_overdue, window)
	end

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

	-- what wants you in other workspaces
	if attention_elsewhere then
		local away = attention_elsewhere(window)
		-- first: the one channel no notification permission can drop
		if (away.needs or 0) > 0 then
			table.insert(parts, { Foreground = { Color = "#f38ba8" } })
			table.insert(parts, { Text = string.format(" ●%d needs you", away.needs) })
			width = width + 12
		end
		if away.errored > 0 then
			table.insert(parts, { Foreground = { Color = "#f38ba8" } })
			table.insert(parts, { Text = string.format(" !%d", away.errored) })
			width = width + 4
		end
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

	-- LEADER+w must not wait on git, so its branch snapshot is kept warm here (throttled)
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

	-- format-tab-title cannot see the real bar width, so measure it here
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
-- Tab titles: every Claude pane's topic, not just the focused one.
-- Precedence: typed (LEADER+,), live pane topics, save-layer pin, active pane title.
-- ============================================================
-- a whole topic; the only ceiling left
local SOLO_BUDGET = 96
local MIN_LABEL = 10 -- a label with room for a subject, not just a verb
local TERSE_LABEL = 5 -- squeezed, but still names something
local GROUP_LABEL = 14 -- a tab's own name, the part before TAB_GROUP_SEP
-- fancy bar padding+border per tab: 0.5 cells each side + 1px, in *terminal* cells, hence
-- the conversion. Raise if tabs clip.
local TAB_CHROME = math.ceil(1.3 * FRAME_CELLS)
-- retro bar: the " + " button; plus one separator cell per tab gap
local NEW_TAB_CELLS = 3
-- integrated buttons share the row but wezterm omits them from the per-tab divisor, so
-- take them off first. Estimated.
local WINDOW_BUTTON_CELLS = 10

-- program names, not tasks
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
	-- cc-board overlay, before and after strip_glyph
	["▤ board"] = true,
	["board"] = true,
}

-- dropped to keep the subject visible when panes share the budget
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
	-- word boundary only if it still fills most of the budget
	local last_space = cut:match("^.*()%s")
	if last_space and last_space > budget * 0.75 then
		cut = cut:sub(1, last_space - 1)
	end
	-- half a multibyte glyph makes wezterm reject the whole title
	while #cut > 0 and not utf8.len(cut) do
		cut = cut:sub(1, -2)
	end
	return cut .. "…"
end

---Working titles lead with ◐◓◑◒ (E2 97 90..93), idle with ✳ (U+2733); braille on old
---builds. Keep in step with Claude Code: pane_status trusts this over the state file.
local function is_working(title)
	local b1, b2, b3 = title:byte(1), title:byte(2) or 0, title:byte(3) or 0
	if b1 ~= 0xE2 then
		return false
	end
	return (b2 == 0x97 and b3 >= 0x90 and b3 <= 0x93) -- ◐◓◑◒
		or (b2 >= 0xA0 and b2 <= 0xA3) -- braille, pre-2.1 builds
end

---Title written by Claude (spinner or dingbat E2 9C/9D xx), not typed; catches pins that
---predate AUTO_TITLE_MARK.
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

---Drop leading glyph + space. Byte-wise: wezterm's Lua counts bytes > 0x7F as %w.
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

---@return string|nil label, boolean working, boolean silent: pane has no title yet
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

---Last resort title: the cwd's basename. pcall: Url object only on recent wezterm.
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
-- Must match cc-roster and cc-board. A Monitor cannot outlive an hour.
local PARKED_MONITOR_MAX = 3600
local PARKED_MAX = 4 * 3600

---Last hook record for a pane: state, epoch, detail, writing sid
local read_pane_state = memo_per_second(function(pane_id)
	local file = io.open(pane_state_dir .. "/" .. pane_id, "r")
	if not file then
		return nil
	end
	local line = file:read("*line") or ""
	file:close()
	local state, at, detail, sid = line:match("^(%a+)\t(%d+)\t([^\t]*)\t?(.*)$")
	if state == nil then
		return nil
	end
	-- panes outlive sessions: drop a record another session wrote. No sid = old, trusted.
	if sid ~= "" then
		local reg = digest_rows()[tostring(pane_id)]
		if reg ~= nil and reg.sid ~= "" and reg.sid ~= sid then
			return nil
		end
	end
	return { state = state, at = tonumber(at), detail = detail, sid = sid }
end)

---Registry + hook record, most decisive first:
--- 1. registry `waiting`: clears when answered, which no hook can do
--- 2. hook `errored`: registry reads idle after an API death. Cleared only by registry
---    busy (a new turn), not idle and not the spinner, which keeps its turn-start glyph
--- 3. hook `asking`: beats the registry by seconds; dropped once the title spins again
--- 4. spinner or registry busy: each catches what the other misses
--- 5. hook `parked`: registry also calls it idle
--- 6. age since the later of the two clocks
---@return string status working|asking|errored|parked|fresh|waiting|stale, string detail
local function pane_status(pane, spinning)
	local reg = digest_rows()[tostring(pane.pane_id)]
	local rec = read_pane_state(pane.pane_id)
	-- not a Claude pane, or one that has said nothing yet
	if reg == nil and rec == nil then
		return spinning and "working" or "waiting", ""
	end
	local busy = reg ~= nil and reg.status == "busy"
	if reg ~= nil and reg.status == "waiting" then
		return "asking", reg.detail
	end
	if rec ~= nil and rec.state == "errored" and not busy then
		return "errored", rec.detail
	end
	if rec ~= nil and rec.state == "asking" and not busy and not spinning then
		return "asking", rec.detail
	end
	if spinning or busy then
		return "working", ""
	end
	-- parked has no writer when the background work ends, so it expires (CLAUDE.md)
	if rec ~= nil and rec.state == "parked"
		and os.time() - rec.at <= (rec.detail == "monitor" and PARKED_MONITOR_MAX or PARKED_MAX)
	then
		return "parked", rec.detail
	end
	if rec ~= nil and rec.state == "ended" then
		return "stale", ""
	end
	-- later clock: a registry file that stopped moving must not overrule a newer hook
	local at = math.max(reg ~= nil and reg.seen or 0, rec ~= nil and rec.at or 0)
	local age = os.time() - at
	if age < FRESH_SECONDS then
		return "fresh", ""
	end
	if age > STALE_SECONDS then
		return "stale", ""
	end
	return "waiting", ""
end

-- status by hue, not brightness; see docs/colour.md
local TAB_COLOURS = {
	index = "#6c7086",
	divider = "#45475a",
	active = "#87d7ff", -- focused, nothing else to say
	asking = "#cba6f7", -- blocked on a permission or plan prompt
	errored = "#f38ba8", -- the turn died on an API error and will not resume itself
	fresh = "#f9e2af", -- finished in the last FRESH_SECONDS
	waiting = "#ffd7af", -- stopped, waiting on you
	working = "#a6e3a1", -- busy
	parked = "#89dceb", -- turn over, its own background work still running
	stale = "#6c7086", -- waited hours, or the session has exited
}

-- which pane to name when only one fits; errored first, a dead turn resumes for nobody
local NEED = { errored = 6, asking = 5, fresh = 4, waiting = 3, parked = 2.5, working = 2, stale = 1 }

-- Identity ("which pane is this"), a separate channel from status; see docs/colour.md.
-- Keep in step with cc-colour: same ladder, same hash.
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

---Auto pins, then hand pins over them (cc-colour's precedence). Re-read every 3s: that is
---how long a new session's label can disagree with the tint cc-tint just painted.
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
	-- a changed pin must invalidate pane_identity's cache
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

---First 8 hex of the session id mod the palette: stateless, so agrees with cc-colour and
---survives /rename and --resume.
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

-- pane id -> colour; changes only when a session starts in the pane
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

-- Status is a ●; only the states you act on (asking, errored, fresh) get their own shape.
-- Label text belongs to identity.

---@return string colour, string marker, integer marker width in cells
local function status_style(status, detail, active, budget)
	if status == "asking" then
		-- with room, name the tool: "?bash ..."
		if detail ~= "" and budget >= 20 then
			local tool = "?" .. detail:lower() .. " "
			return TAB_COLOURS.asking, tool, #tool
		end
		return TAB_COLOURS.asking, "?", 1
	end
	if status == "errored" then
		if detail ~= "" and budget >= 20 then
			local why = "!" .. detail:gsub("_", " ") .. " "
			return TAB_COLOURS.errored, why, #why
		end
		return TAB_COLOURS.errored, "!", 1
	end
	if status == "fresh" then
		return TAB_COLOURS.fresh, "✓", 1
	end
	-- calm blue only for the pane on screen; see on_screen
	if status == "waiting" and active then
		return TAB_COLOURS.active, "", 0
	end
	return TAB_COLOURS[status] or TAB_COLOURS.waiting, "", 0
end

-- " 10: " not " 1: ", so a tenth tab cannot push every label one cell over
local PREFIX_CELLS = 5

---Cells one pane wants: label + shape + space. Nil = no topic (costs a `+N` instead).
---Over-estimate is the safe direction.
local function pane_demand(pane, terse)
	local label = pane_label(pane)
	if label == nil then
		return nil
	end
	return #(terse and strip_filler(label) or label) + 2
end

---Largest cap W with sum(min(demand, W)) <= budget (water-fill). One cap per tab so
---clipped labels clip at the same width.
---@param demands integer[] mutated: sorted in place
local function fill_cap(demands, budget)
	table.sort(demands)
	local left = #demands
	for _, want in ipairs(demands) do
		if budget < want * left then
			return math.floor(budget / left)
		end
		budget = budget - want
		left = left - 1
	end
	return SOLO_BUDGET -- every topic in the tab fits whole
end

---wezterm's per-tab ceiling in frame cells: fancy_tab_bar.rs `pixel_width / num_tabs -
---1.5 cells`, num_tabs including the new-tab button, whether or not the bar is full.
---tab_max_width does not affect it in fancy mode.
---@return integer frame cells for one tab's whole row, chrome and prefix included
local function tab_ceiling(geom, ntabs)
	local bar = geom.cols * FRAME_CELLS - WINDOW_BUTTON_CELLS
	-- +1 for the new-tab button: counted in wezterm's divisor, not capped by it
	return math.floor(bar / (ntabs + 1) - 1.5 * FRAME_CELLS)
end

---Tab's own name: text before TAB_GROUP_SEP, or a hand-typed title. "" for a save-layer
---pin. Separate because label_width prices every tab's name.
local function tab_group(pinned)
	pinned = pinned or ""
	local sep = pinned:find(TAB_GROUP_SEP, 1, true)
	if sep ~= nil then
		return (pinned:sub(1, sep - 1):gsub("^%s+", ""):gsub("%s+$", ""))
	end
	if pinned == "" then
		return ""
	end
	if pinned:find(AUTO_TITLE_MARK, 1, true) ~= nil or has_claude_glyph(pinned) then
		return "" -- a pin, not a name: the pane topics are fresher
	end
	return (pinned:gsub("^%s+", ""):gsub("%s+$", ""))
end

---What a tab spends before any label: its name, and the divider after it.
local function group_cost(pinned)
	local group = tab_group(pinned)
	return group ~= "" and (#shorten(group, GROUP_LABEL) + 2) or 0
end

---Every label a tab will draw, in cells it would like to have.
---@return integer[] demands
local function tab_demands(tab)
	local panes = tab.panes or { tab.active_pane }
	if tab.active_pane ~= nil and tab.active_pane.is_zoomed then
		panes = { tab.active_pane } -- a zoomed tab draws one label whatever it contains
	end
	local demands = {}
	local terse = #panes > 1 -- format-tab-title drops filler verbs in a split
	for _, pane in ipairs(panes) do
		local want = pane_demand(pane, terse)
		if want ~= nil then
			table.insert(demands, want)
		end
	end
	return demands
end

---One label width for this tab's panes. fancy: share within the tab, capped by
---tab_ceiling. retro: share across the window; overshoot by one cell and wezterm clamps
---every tab to `available / ntabs` at once. Both water-fill. See docs/cc-board.md.
---@param overhead integer cells this row spends before any label: group name, +N, zoom
---@return integer cells per label, 0 when not even a terse row fits
local function label_width(tab, tabs, overhead)
	local geom = tab_geometry[tab.tab_id]
	if geom == nil then
		-- first paint after reload precedes any status tick; claim room, not a bar of dots
		return SOLO_BUDGET
	end
	local ntabs = (tabs ~= nil and #tabs > 0) and #tabs or math.max(1, geom.tabs or 1)
	local demands, room

	if FANCY then
		demands = tab_demands(tab)
		local mine = math.max(1, #demands)
		room = tab_ceiling(geom, ntabs) - TAB_CHROME - PREFIX_CELLS - (mine - 1) - (overhead or 0)
		if room < mine then
			return 0
		end
	else
		-- every pane on the bar; this tab's overhead is already inside the sum
		demands = {}
		local npanes = 0
		room = geom.cols - geom.reserve - NEW_TAB_CELLS - WINDOW_BUTTON_CELLS - (ntabs - 1)
		for _, other in ipairs(tabs or {}) do
			local want = tab_demands(other)
			npanes = npanes + math.max(1, #want)
			room = room - PREFIX_CELLS - group_cost(other.tab_title) - math.max(0, #want - 1)
			for _, cells in ipairs(want) do
				table.insert(demands, cells)
			end
		end
		if room < npanes then
			return 0
		end
	end

	if #demands == 0 then
		return math.max(1, math.min(SOLO_BUDGET, room))
	end
	return math.max(1, math.min(SOLO_BUDGET, fill_cap(demands, room)))
end

wezterm.on("format-tab-title", function(tab, tabs, _, _, _, max_width)
	local prefix = " " .. (tab.tab_index + 1) .. ": "
	local pinned = tab.tab_title or ""
	local sep = pinned:find(TAB_GROUP_SEP, 1, true)
	-- a typed name without the separator still becomes the group
	local group = tab_group(pinned)

	local ok, formatted = pcall(function()
		-- is_active is only within its tab; calm colour and bold are for the pane on screen
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
		-- +N, name and zoom arrow come off the ceiling before water-filling, not per label
		local named = shorten(group, GROUP_LABEL)
		local overhead = marks + (zoomed and 2 or 0) + (group ~= "" and (#named + 2) or 0)
		local per = label_width(tab, tabs, overhead)
		-- a name must not turn a zero budget into a one-cell label
		local name = (group ~= "" and per > 0) and named or ""
		-- terse row's leftover after one dot per pane; off the row's budget, not the bar's
		local spare = per * count - count

		local items = {
			{ Attribute = { Intensity = "Normal" } },
			{ Foreground = { Color = TAB_COLOURS.index } },
			{ Text = zoomed and (prefix .. "⤢ ") or prefix },
		}

		if name ~= "" then
			-- index grey, bold: chrome, not one more pane
			table.insert(items, { Attribute = { Intensity = "Bold" } })
			table.insert(items, { Text = name })
			table.insert(items, { Attribute = { Intensity = "Normal" } })
			table.insert(items, { Foreground = { Color = TAB_COLOURS.divider } })
			table.insert(items, { Text = " │" })
		end

		if per == 0 or (count > 1 and per < TERSE_LABEL) then
			-- too tight: one glyph per pane
			for _, label in ipairs(labels) do
				local colour, marker = status_style(label.status, label.detail, label.active, 0)
				table.insert(items, { Attribute = { Intensity = label.active and "Bold" or "Normal" } })
				table.insert(items, { Foreground = { Color = colour } })
				table.insert(items, { Text = marker ~= "" and marker or (label.active and "◆" or "●") })
			end
			if spare >= TERSE_LABEL then
				-- one topic fits: name the pane that wants you most
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
				local text = (count > 1 or per < MIN_LABEL) and strip_filler(label.text) or label.text
				local colour, marker, marker_width =
					status_style(label.status, label.detail, label.active, per)
				if marker == "" then
					marker, marker_width = label.active and "◆" or "●", 1
				end
				-- dot = status colour, name = identity colour
				table.insert(items, { Attribute = { Intensity = label.active and "Bold" or "Normal" } })
				table.insert(items, { Foreground = { Color = colour } })
				table.insert(items, { Text = marker .. " " })
				table.insert(items, { Foreground = { Color = label.identity or TAB_COLOURS.waiting } })
				table.insert(items, { Text = shorten(text, math.max(1, per - marker_width - 1)) })
			end
		end

		table.insert(items, { Attribute = { Intensity = "Normal" } })
		if marks > 0 then
			-- untitled panes, so the count is never understated
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
	local room = math.max(TERSE_LABEL, label_width(tab, tabs, 0))
	return prefix .. shorten(title, room) .. " "
end)

-- ============================================================
-- Claude: address another session
-- LEADER+@ picks a live session by topic and types its SendMessage name at the cursor
-- (and clipboard). Bare name: a literal @ in the Claude prompt opens file mentions.
-- ============================================================
local peers_script = wezterm.home_dir .. "/.claude/bin/cc-peers"

-- quick-select: statusLine @name, session ids, file:line (defaults cover URLs, SHAs)
config.quick_select_patterns = {
	"@[a-z0-9][a-z0-9_.-]{1,48}",
	"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
	"[\\w./~-]+\\.\\w{1,6}:\\d+(?::\\d+)?",
}

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
					-- not on every build
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
-- LEADER+; fuzzy-lists every live session in every workspace and jumps across the
-- workspace boundary. The right status counts what wants you elsewhere.
-- ============================================================
local board_script = wezterm.home_dir .. "/.claude/bin/cc-board"

local FLEET_GLYPH = {
	asking = { "⚠", TAB_COLOURS.asking },
	busy = { "◐", TAB_COLOURS.working },
	idle = { "✳", TAB_COLOURS.fresh },
	shell = { "›", TAB_COLOURS.stale },
}

-- unfiltered list opens on whatever wants you
local FLEET_WEIGHT = { asking = 4, busy = 3, idle = 2, shell = 1 }

-- dimmed past this; matches cc-fleet's default
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
---cc-board, not cc-fleet: only the pane's screen tells finished from asking (~0.5s)
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
				weight = asks and 5 or (FLEET_WEIGHT[f[4]] or 0),
			})
		end
	end

	table.sort(rows, function(a, b)
		if a.weight ~= b.weight then
			return a.weight > b.weight
		end
		-- never-prompted last within its state
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
			-- name in identity colour, glyph in status colour
			{ Foreground = { Color = r.identity or colour } },
			{ Text = fleet_pad(r.name, 19) },
			{ Foreground = { Color = TAB_COLOURS.index } },
			{ Text = fleet_pad(fleet_age(r.idle), 6) },
			{ Foreground = { Color = topic_colour } },
			{ Text = fleet_pad(r.title, 44) },
		}
		-- last line last, so fuzzy matching reaches it
		if r.last ~= "" then
			table.insert(label, { Foreground = { Color = r.asks and TAB_COLOURS.asking or TAB_COLOURS.divider } })
			table.insert(label, { Text = "▸ " .. r.last })
		end
		table.insert(choices, { id = tostring(r.pane), label = wezterm.format(label) })
	end
	return choices
end

---Focus a pane anywhere: mux activate, then raise its gui_window(). Not SwitchToWorkspace,
---which would repoint *this* window at a workspace that already has one. Switch only when
---the workspace has no window of its own.
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

	-- no GuiWindow:focus on older wezterm: fall through to the switch
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

-- Status computed once per 3s for all windows; each window counts the panes it cannot see
-- (counts per window, since "here" differs).
local fleet_panes = { at = 0, rows = {} }
local fleet_counts = {} -- window id -> counts, recomputed when fleet_panes moves

---cc-note flags per sid; `mute` keeps a session out of the elsewhere counts and the chime,
---`needs` feeds "needs you". Re-read every 3s.
local notes_flags = {}
local notes_at = 0

local function load_notes()
	local now = os.time()
	if now - notes_at < 3 then
		return
	end
	notes_at = now
	local fresh = {}
	local file = io.open(wezterm.home_dir .. "/.claude/fleet/notes.tsv", "r")
	if file then
		for line in file:lines() do
			-- sid, updated_at, flags, progress, status
			local sid, flags = line:match("^([^\t]+)\t[^\t]*\t([^\t]*)")
			if sid and flags then
				fresh[sid] = flags
			end
		end
		file:close()
	end
	notes_flags = fresh
end

---@return boolean true when this pane's session carries `flag`
local function pane_flagged(pane_id, flag)
	local sid = read_session_id(pane_id)
	if not sid then
		return false
	end
	local flags = notes_flags[sid]
	if not flags then
		return false
	end
	return flags:find(flag, 1, true) ~= nil
end

local function pane_muted(pane_id)
	return pane_flagged(pane_id, "mute")
end

local function fleet_scan()
	local now = os.time()
	if now - fleet_panes.at < 3 then
		return fleet_panes
	end
	load_notes()
	local rows = {}
	pcall(function()
		for _, mux_window in ipairs(wezterm.mux.all_windows()) do
			for _, tab in ipairs(mux_window:tabs()) do
				for _, p in ipairs(tab:panes()) do
					local id = p:pane_id()
					-- via pane_status so counts cannot disagree with the tab bar
					table.insert(rows, {
						id = id,
						needs = pane_flagged(id, "needs"),
						muted = pane_muted(id),
						status = pane_status({ pane_id = id }, is_working(p:get_title() or "")),
					})
				end
			end
		end
	end)
	fleet_panes = { at = now, rows = rows }
	return fleet_panes
end

attention_elsewhere = function(window)
	local scan = fleet_scan()
	local wid = window:window_id()
	local counts = fleet_counts[wid]
	if counts and counts.at == scan.at then
		return counts
	end
	counts = { at = scan.at, errored = 0, asking = 0, fresh = 0, needs = 0 }
	fleet_counts[wid] = counts

	local here = {}
	local ok = pcall(function()
		for _, tab in ipairs(window:mux_window():tabs()) do
			for _, p in ipairs(tab:panes()) do
				here[p:pane_id()] = true
			end
		end
	end)
	if not ok then
		return counts
	end

	for _, row in ipairs(scan.rows) do
		-- `needs` counts here too: being on screen does not discharge it
		if row.needs then
			counts.needs = counts.needs + 1
		end
		if not here[row.id] and not row.muted then
			if counts[row.status] ~= nil then
				counts[row.status] = counts[row.status] + 1
			end
		end
	end
	return counts
end

-- ============================================================
-- The chime: the only push in this config. OFF (CHIME_ENABLED) because a third
-- notification channel teaches you to ignore all of them.
local CHIME_ENABLED = false
local CHIME_AFTER = 15 * 60
local chime_dir = wezterm.home_dir .. "/.claude/cache/cc-chimed"
local chime_at = 0

-- not waiting: too common, it would be noise
local CHIME_STATES = { asking = true, errored = true }

---One chime per episode, keyed by the state record's epoch so reblocking re-arms it and a
---reload does not. True when already chimed.
local function chime_marked(pane_id, epoch)
	local path = chime_dir .. "/" .. pane_id
	local file = io.open(path, "r")
	if file then
		local was = file:read("*line")
		file:close()
		if was == tostring(epoch) then
			return true
		end
	end
	local out = io.open(path, "w")
	if not out then
		return true -- cannot record it, so do not risk chiming every thirty seconds
	end
	out:write(tostring(epoch))
	out:close()
	return false
end

chime_overdue = function(window)
	if not CHIME_ENABLED then
		return
	end
	local now = os.time()
	if now - chime_at < 30 then
		return
	end
	chime_at = now

	-- One window per pass, claimed by mkdir (atomic, fails if present). Not os.rename:
	-- POSIX rename overwrites, so every caller wins. Not lowest window id: it may not be
	-- ticking. Time-bucketed so claims expire; cleanup is the bucket before last.
	local bucket = math.floor(now / 30)
	local claimed = wezterm.run_child_process({ "/bin/mkdir", chime_dir .. "/.pass-" .. bucket })
	if not claimed then
		return
	end
	wezterm.background_child_process({ "/bin/rm", "-rf", chime_dir .. "/.pass-" .. (bucket - 2) })

	for _, mux_window in ipairs(wezterm.mux.all_windows()) do
		for _, tab in ipairs(mux_window:tabs()) do
			for _, p in ipairs(tab:panes()) do
				local id = p:pane_id()
				local rec = read_pane_state(id)
				local watched = rec ~= nil and CHIME_STATES[rec.state] == true
				if watched and not pane_muted(id) and now - (rec.at or 0) >= CHIME_AFTER then
					if not chime_marked(id, rec.at) then
						local mins = math.floor((now - rec.at) / 60)
						local who = strip_glyph(p:get_title() or "")
						if who == "" then
							who = "pane " .. id
						end
						local why = (rec.detail or ""):gsub("_", " ")
						local title, body
						if rec.state == "errored" then
							title = who .. " died on " .. (why ~= "" and why or "an api error")
							body = string.format("%dm ago, and it is not coming back on its own", mins)
						else
							title = who .. " is still asking"
							body = string.format("%dm%s", mins, why ~= "" and (" · " .. why) or "")
						end
						wezterm.background_child_process({
							wezterm.home_dir .. "/.claude/bin/wz", "notify", title, body,
						})
					end
				end
			end
		end
	end
end

-- ============================================================
-- Claude: the workspace board (LEADER+b, cc-board; see docs/cc-board.md)
-- Left split of the leftmost pane, zoomed (settled, see CLAUDE.md); in place if the tab has
-- nothing live. Press again to close.
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
-- Claude: switch workspace (LEADER+w), with per-state counts, top topic, branch + dirty.
-- Alt-tab order (MRU, current last), deliberately not ranked by need: a list that
-- reorders between presses cannot be learned. No forks and no screen reads; git comes from
-- a background snapshot.
-- ============================================================

-- NEED order. "ended" split from stale: an exited session is a pane to close.
local WS_STATES = {
	{ key = "errored", glyph = "!", colour = TAB_COLOURS.errored },
	{ key = "asking", glyph = "⚠", colour = TAB_COLOURS.asking },
	{ key = "fresh", glyph = "✓", colour = TAB_COLOURS.fresh },
	{ key = "waiting", glyph = "✳", colour = TAB_COLOURS.waiting },
	{ key = "parked", glyph = "◌", colour = TAB_COLOURS.parked },
	{ key = "working", glyph = "◐", colour = TAB_COLOURS.working },
	{ key = "stale", glyph = "·", colour = TAB_COLOURS.stale },
	{ key = "ended", glyph = "›", colour = TAB_COLOURS.stale },
}

local WS_NAME_W = 18
local WS_COUNT_W = 9
-- three cells x eight states
local WS_STATE_W = 24
local WS_GIT_W = 22

---fleet_pad counts bytes; glyph columns track their own cell width and pad with this,
---never to zero.
local function ws_pad(used, target)
	return string.rep(" ", math.max(1, target - used))
end

-- in a file, not memory: a config reload would reset it
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

---Writes only when the front changes: runs every status tick
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

---One dir per workspace: its first pane's cwd
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

-- $1 cache, rest dirs. Temp file + mv so a reader never sees half a snapshot.
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

---Background snapshot, never waited on: git per workspace would stall the picker
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
		-- listed even if empty
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
				-- a chat: hook state or a Claude title
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
					-- topic: titled first, then loudest, then most recent
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

	-- MRU, then unvisited, then current
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
		-- unvisited: chats first, then empties
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

		-- branch shortened around the dirty count, never the reverse
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

		-- topic last, so fuzzy matching reaches it
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
				-- raise its own GUI window; detached or typed names fall through to a switch
				for _, mux_window in ipairs(wezterm.mux.all_windows()) do
					if mux_window:get_workspace() == ws then
						-- gui_window() RAISES (not nil) with no GUI window attached
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

	-- on the way out, so the next press is current
	ws_git_refresh()
end

-- a board in a zoomed tab is hidden; the next press would open a second
local function tab_is_zoomed(tab)
	for _, p in ipairs(tab:panes_with_info()) do
		if p.is_zoomed then
			return true
		end
	end
	return false
end

-- Only ever one board: LEADER+b elsewhere moves the running pane, keeping its state
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

-- shells or exited sessions only: the board can run in place
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
		-- zoomed: the board may be hidden, unzoom and look again
		if not open and tab_is_zoomed(tab) then
			pcall(function()
				tab:set_zoomed(false)
			end)
			open = board_in_tab(tab)
		end

		-- quit, not kill: the board may be in a shell pane that is not ours to close
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
			-- typed at the prompt, not spawned: the shell is not ours to replace
			pcall(function()
				pane:send_text(
					"CC_BOARD_ORIGIN=" .. env.CC_BOARD_ORIGIN ..
					" CC_BOARD_TITLE='" .. BOARD_TITLE .. "' " .. board_script .. "\n"
				)
			end)
			return
		end

		-- no Lua API moves a pane between tabs, hence the CLI (as the board's M key does)
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
			-- no room to move it: go to it rather than open a second
			pcall(function()
				elsewhere:activate()
				from_tab:activate()
				from_tab:set_zoomed(true)
			end)
			return
		end

		-- Split off the leftmost pane so the board is the tab's left column.
		-- Never top_level: it wedges the tab ("No space for split!"), see CLAUDE.md.
		local host = leftmost_pane(tab) or pane
		local board
		local ok = pcall(function()
			board = host:split({
				direction = "Left",
				args = { "/bin/zsh", "-lc", board_script },
				set_environment_variables = env,
			})
		end)
		-- leftmost may be too narrow to halve
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

-- leader actions in the command palette; last because it reads the finished config.keys
local PALETTE = {
	b = "Fleet: board",
	[";"] = "Fleet: jump to any session",
	["@"] = "Fleet: type a peer session name",
	w = "Workspace: switch (alt-tab order)",
	W = "Workspace: new",
	["<"] = "Workspace: rename",
	S = "Save all workspaces",
	R = "Restore a saved workspace, window or tab",
	u = "Open a URL on screen",
}
wezterm.on("augment-command-palette", function()
	local out = {}
	for _, k in ipairs(config.keys) do
		local brief = k.mods == "LEADER" and PALETTE[k.key]
		if brief then
			table.insert(out, { brief = brief, action = k.action })
		end
	end
	return out
end)

return config
