return function(opts)
	local Terminal = opts.terminal

	hl.on("hyprland.start", function()
		-- dark theme setup
		hl.exec_cmd([[gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"]])
		hl.exec_cmd([[gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark"]])

		-- shell
		hl.exec_cmd("waybar")
		hl.exec_cmd("hyprpaper")

		-- spawn terminals
		for _, workspace in ipairs({ "1", "2", "4" }) do
			for _ = 1, 3 do
				hl.exec_cmd(Terminal, { workspace = workspace .. " silent" })
			end
		end

		-- spawn other default applications
		hl.exec_cmd("obsidian", { workspace = "special:magic silent" })
		hl.exec_cmd("firefox", { workspace = "3 silent" })
	end)
end
