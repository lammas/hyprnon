-- hyprnon: a three-column layout for wide displays

-- c o n f i g u r a t i o n -----------------------------------------------------------------------------------------
local options = {
	main_mod           = "SUPER",
	terminal           = "ghostty",
	menu               = "wofi --show drun",
	monitors           = {
		builtin = {
			output = "eDP-1",
			mode = "2560x1600@240.00Hz",
			position = "0x0",
			scale = "1",
		},
		wide = {
			output = "HDMI-A-1",
			mode = "5120x1440@240.00Hz",
			position = "2560x0",
			scale = "1",
		}
	},
	special_workspaces = { S = "magic", A = "alt", D = "debug" },

	-- per-workspace options (workspace id as string):
	--   max     = { left, center, right }  -- max windows per column, nil/false = unlimited
	--   widths  = { left, center, right }  -- relative column widths, always applied even when a column is empty
	--   stack   = "left" | "right"         -- where extra windows go once every column has one
	--   resize  = "edge" | "symmetric"     -- "edge" moves the nearest column boundary; "symmetric" resizes the
	--                                         center column symmetrically, shrinking/growing left and right equally
	workspaces = {
		["1"] = { widths = { left = 0.33, center = 0.33, right = 0.33 }, stack = "left" },
		["2"] = { widths = { left = 0.25, center = 0.5, right = 0.25 }, stack = "left" },
		["3"] = { widths = { left = 0.25, center = 0.5, right = 0.25 }, stack = "right" },
		["4"] = { widths = { left = 0.33, center = 0.33, right = 0.33 }, stack = "left" },
		["special:magic"] = { widths = { left = 0.25, center = 0.5, right = 0.25 }, stack = "left" },
	},

	resize_bind        = "mouse:273",
	move_bind          = "mouse:272",
}
----------------------------------------------------------------------------------------------------------------------

local candidates = {}

-- relative modules path
local source_dir = debug and debug.getinfo and debug.getinfo(1, "S").source:match("^@?(.*/)")
if source_dir then
	table.insert(candidates, source_dir)
end

local xdg = os.getenv("XDG_CONFIG_HOME")
if xdg then
	table.insert(candidates, xdg .. "/hypr/")
end

local home = os.getenv("HOME")
if home then
	table.insert(candidates, home .. "/.config/hypr/")
end

-- prepend in reverse so earlier candidates take priority in package.path
for i = #candidates, 1, -1 do
	local dir = candidates[i]
	package.path = dir .. "?.lua;" .. dir .. "?/init.lua;" .. package.path
end

-- if the module returned a function, call it with the given args
local function load_module(name, ...)
	local module = require(name)
	if type(module) == "function" then
		return module(...)
	end
	return module
end

-- register the layout before conf.settings references it
load_module("lib.hyprnon").setup(options)

load_module("conf.settings", options)
load_module("conf.autostart", options)
load_module("conf.binds", options)
load_module("conf.rules")
load_module("conf.animations")
