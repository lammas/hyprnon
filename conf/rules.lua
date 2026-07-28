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
