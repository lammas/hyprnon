return function(opts)
	local MainMod = opts.main_mod
	local Terminal = opts.terminal
	local Menu = opts.menu
	local SpecialWorkspaces = opts.special_workspaces

	local dsp = hl.dsp

	-- general shell
	hl.bind(MainMod .. " + Q", dsp.exec_cmd(Terminal))
	hl.bind(MainMod .. " + C", dsp.window.close())
	hl.bind(MainMod .. " + G", dsp.exec_cmd("grimblast copy area"))
	hl.bind(MainMod .. " + E", dsp.exec_cmd("ghostty --command=eva --class=com.libnon.eva"))
	hl.bind(MainMod .. " + V", dsp.window.float({ action = "toggle" }))
	hl.bind(MainMod .. " + F", dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
	hl.bind(MainMod .. " + R", dsp.exec_cmd(Menu))
	hl.bind(MainMod .. " + L", dsp.exec_cmd("pidof hyprlock || hyprlock"))

	-- navigation
	for workspace = 1, 10 do
		local key = workspace == 10 and "0" or tostring(workspace)
		hl.bind(MainMod .. " + " .. key, dsp.focus({ workspace = tostring(workspace) }))
		hl.bind(MainMod .. " + SHIFT + " .. key, dsp.window.move({ workspace = tostring(workspace) }))
	end
	for key, name in pairs(SpecialWorkspaces) do
		hl.bind(MainMod .. " + " .. key, dsp.workspace.toggle_special(name))
		hl.bind(MainMod .. " + SHIFT + " .. key, dsp.window.move({ workspace = "special:" .. name }))
	end

	-- focus
	hl.bind(MainMod .. " + left", dsp.focus({ direction = "l" }))
	hl.bind(MainMod .. " + right", dsp.focus({ direction = "r" }))
	hl.bind(MainMod .. " + up", dsp.focus({ direction = "u" }))
	hl.bind(MainMod .. " + down", dsp.focus({ direction = "d" }))
	hl.bind(MainMod .. " + mouse_down", dsp.focus({ workspace = "e+1" }))
	hl.bind(MainMod .. " + mouse_up", dsp.focus({ workspace = "e-1" }))

	-- window movement
	local directions = {
		left  = { dir = "l", x = -50, y = 0 },
		right = { dir = "r", x = 50,  y = 0 },
		up    = { dir = "u", x = 0,   y = -50 },
		down  = { dir = "d", x = 0,   y = 50 },
	}

	local function swap_or_move(spec)
		return function()
			local window = hl.get_active_window()
			if window and window.floating then
				hl.dispatch(dsp.window.move({ x = spec.x, y = spec.y, relative = true }))
			else
				hl.dispatch(dsp.window.swap({ direction = spec.dir }))
			end
		end
	end

	for key, spec in pairs(directions) do
		hl.bind(MainMod .. " + SHIFT + " .. key, swap_or_move(spec), { repeating = true })
	end

	hl.bind(MainMod .. " + CTRL + P", dsp.workspace.move({ monitor = "+1" }))
	hl.bind(MainMod .. " + T", dsp.layout("toggle-stack"))
	hl.bind(MainMod .. " + SHIFT + T", dsp.layout("reset-widths"))
	hl.bind(MainMod .. " + SHIFT + R", dsp.layout("toggle-resize"))

	-- media keys
	hl.bind("XF86MonBrightnessUp", dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
	hl.bind("XF86MonBrightnessDown", dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })
	hl.bind("XF86AudioRaiseVolume", dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
	hl.bind("XF86AudioLowerVolume", dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
	hl.bind("XF86AudioMute", dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
	hl.bind("XF86AudioMicMute", dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
	hl.bind("XF86AudioNext", dsp.exec_cmd("playerctl next"), { locked = true })
	hl.bind("XF86AudioPause", dsp.exec_cmd("playerctl play-pause"), { locked = true })
	hl.bind("XF86AudioPlay", dsp.exec_cmd("playerctl play-pause"), { locked = true })
	hl.bind("XF86AudioPrev", dsp.exec_cmd("playerctl previous"), { locked = true })
end
