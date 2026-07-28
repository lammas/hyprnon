return function(opts)
	-- monitors
	for _, monitor in pairs(opts.monitors) do
		hl.monitor(monitor)
	end

	-- envs
	hl.env("AQ_DRM_DEVICES", "/dev/dri/card0:/dev/dri/card1")
	hl.env("XCURSOR_SIZE", "24")
	hl.env("HYPRCURSOR_SIZE", "24")
	hl.env("GTK_THEME", "adw-gtk3-dark")

	-- SSH_AUTH_SOCK for ssh-agent
	local runtime_dir = os.getenv("XDG_RUNTIME_DIR")
	if runtime_dir then
		hl.env("SSH_AUTH_SOCK", runtime_dir .. "/ssh-agent.socket")
	end

	hl.config({
	-- 	debug = {
	-- 		disable_logs = false,
	-- 	},

		opengl = {
			nvidia_anti_flicker = false,
		},

		general = {
			gaps_in = 2,
			gaps_out = 2,
			border_size = 0,
			resize_on_border = false,
			allow_tearing = false,
			layout = "lua:hyprnon",
			-- layout = "master",
		},

		decoration = {
			rounding = 0,
			rounding_power = 2,
			active_opacity = 1.0,
			inactive_opacity = 0.97,

			shadow = {
				enabled = true,
				range = 4,
				render_power = 3,
				color = "rgba(1a1a1aee)",
			},

			blur = {
				enabled = true,
				size = 3,
				passes = 1,
				vibrancy = 0.1696,
			},
		},

		animations = {
			enabled = true,
		},

		-- dwindle fallback for runtime switching
		dwindle = {
			preserve_split = true,
			special_scale_factor = 0.90,
		},

		-- master fallback for runtime switching
		master = {
			allow_small_split = true,
			special_scale_factor = 0.98,
			mfact = 0.33,
			new_status = "slave",
			new_on_top = false,
			new_on_active = "none",
			orientation = "center",
			slave_count_for_center_master = 0,
			always_keep_position = false,
		},

		misc = {
			force_default_wallpaper = 0,
			disable_hyprland_logo = true,
		},

		input = {
			kb_layout = "ee",
			kb_variant = "",
			kb_model = "",
			kb_options = "",
			kb_rules = "",
			follow_mouse = 2,
			float_switch_override_focus = 0,
			sensitivity = 0,
			repeat_delay = 220,
			repeat_rate = 50,

			touchpad = {
				natural_scroll = true,
			},
		},
	})
end
