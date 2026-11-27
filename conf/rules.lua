-- window rules
hl.window_rule({
	name = "firefox-pip",
	match = {
		class = "firefox",
		title = "Picture-in-Picture",
	},
	float = true,
})

hl.window_rule({
	name = "calculator",
	match = {
		class = "com.libnon.eva",
	},
	size = { 400, 800 },
	float = true,
})

hl.window_rule({
	name = "obsidian",
	match = {
		class = "obsidian",
	},
	workspace = "special:magic",
})

hl.window_rule({
	name = "nheko",
	match = {
		class = "nheko",
	},
	workspace = "special:alt",
})

-- open/save
hl.window_rule({
	name = "portal-dialogs",
	match = {
		class = "^xdg-desktop-portal-.*$|^org\\.freedesktop\\.impl\\.portal\\.desktop\\..*$",
	},
	float = true,
	center = true,
	size = { "monitor_w * 0.33", "monitor_h * 0.5" },
})
