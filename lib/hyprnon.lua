-- setup(opts) accepts:
--   defaults    -- table of default options (merged over the builtin defaults)
--   workspaces  -- per-workspace option overrides keyed by workspace id/name
--   main_mod    -- the main MOD key (default: SUPER)
--   move_bind   -- main_mod + key used for moving windows (default: "mouse:272")
--   resize_bind -- main_mod + key used for manual column resizing (default: "mouse:273")

local M = {}

local util = require("lib.util")

local dsp = hl.dsp

local COLUMNS = { "left", "center", "right" }

-- fill empty columns first: center, then left, then right
local FILL_ORDER = { "center", "left", "right" }

-- once every column has a window, stack the rest on the configured side
local STACK_ORDER = {
	left = { "left", "right", "center" },
	right = { "right", "left", "center" },
}

-- a column can never be dragged below this fraction of the total width
local MIN_WIDTH_FRACTION = 0.05

local defaults = {
	max = { left = false, center = 1, right = false },
	widths = { left = 0.33, center = 0.33, right = 0.33 },
	stack = "left",
	resize = "symmetric",
}

local workspaces = {}

-- mutable runtime overrides (toggles, manual resizes)
local runtime_overrides = {}

local function runtime_options(workspace)
	local key = tostring(workspace)
	local options = runtime_overrides[key]
	if not options then
		options = {}
		runtime_overrides[key] = options
	end
	return options
end

local function area_size(area)
	return area.w or area.width, area.h or area.height
end

local function workspace_key(workspace)
	if not workspace then
		return nil
	end

	local id = workspace.id
	if id and id < 0 and workspace.name then
		return workspace.name
	end

	return id
end

-- workspace of the first target window, or nil if there are no targets.
-- callers that want the active workspace as a fallback must opt in
-- explicitly via active_workspace() so the fallback is never accidental.
local function ctx_workspace(ctx)
	for _, target in ipairs(ctx.targets or {}) do
		local window = target.window
		local workspace = window and window.workspace
		if workspace then
			return workspace_key(workspace)
		end
	end
	return nil
end

local function active_workspace()
	return workspace_key(hl.get_active_workspace())
end

-- merge defaults <- configured <- runtime
local function options_for(workspace)
	local configured = workspaces[tostring(workspace)] or {}
	local runtime = runtime_overrides[tostring(workspace)] or {}
	local options = {}

	for key, default in pairs(defaults) do
		local value = runtime[key]
		if value == nil then
			value = configured[key]
		end

		if type(default) == "table" then
			options[key] = {}
			for column, column_default in pairs(default) do
				local column_value = value and value[column]
				if column_value == nil then
					column_value = column_default
				end
				options[key][column] = column_value
			end
		else
			if value == nil then
				value = default
			end
			options[key] = value
		end
	end

	-- sanity check widths
	local total = 0
	for _, name in ipairs(COLUMNS) do
		local width = tonumber(options.widths[name]) or 0
		if width < 0 then
			width = 0
		end
		options.widths[name] = width
		total = total + width
	end
	if total <= 0 then
		for _, name in ipairs(COLUMNS) do
			options.widths[name] = 0.33
		end
	end

	return options
end

-- distribute `count` windows into the left/center/right columns
local function distribute(count, options)
	local columns = { left = {}, center = {}, right = {} }
	local max = options.max
	-- normalize the stack side; anything other than "right" means "left"
	local stack = options.stack == "right" and "right" or "left"

	local function room(name)
		local limit = max[name]
		return not limit or #columns[name] < limit
	end

	for index = 1, count do
		local placed = false

		for _, name in ipairs(FILL_ORDER) do
			if #columns[name] == 0 and room(name) then
				table.insert(columns[name], index)
				placed = true
				break
			end
		end

		if not placed then
			-- stack the rest on the configured side, falling back to whatever column still has room
			for _, name in ipairs(STACK_ORDER[stack]) do
				if room(name) then
					table.insert(columns[name], index)
					placed = true
					break
				end
			end

			if not placed then
				-- every column is capped; overflow into the stack column anyway
				table.insert(columns[stack], index)
			end
		end
	end

	return columns
end

-- state for manual column resizing (resize_bind mouse drag)
local function new_resize_state()
	return {
		pending = false, -- bind pressed, resize-begin dispatched but not yet processed
		dragging = false,
		edge = nil, -- "left" = left|center boundary, "right" = center|right boundary
		workspace = nil,
		start_x = 0,
		area_w = 0,
		total = 0,
		start_widths = nil,
	}
end

local resize_state = new_resize_state()
local resize_timer = nil

-- layout_msg handlers: exact-match commands
local function toggle(key, a, b)
	return function(ctx)
		-- the active workspace is the intended target even when the layout has no windows
		local workspace = ctx_workspace(ctx) or active_workspace()
		runtime_options(workspace)[key] = options_for(workspace)[key] == a and b or a
	end
end

local msg_handlers = {
	["toggle-stack"] = toggle("stack", "right", "left"),

	["toggle-resize"] = toggle("resize", "symmetric", "edge"),

	["reset-widths"] = function(ctx)
		local workspace = ctx_workspace(ctx) or active_workspace()
		-- drop the runtime override; configured/default widths apply again
		runtime_options(workspace).widths = nil
	end,
}

-- layout_msg handlers: prefix commands with a single argument
local msg_prefix_handlers = {
	["resize-begin"] = function(ctx, arg)
		local cursor_x = tonumber(arg)
		if not cursor_x then
			return
		end

		local area = ctx.area
		local area_w = area_size(area)
		local workspace = ctx_workspace(ctx) or active_workspace()
		local widths = options_for(workspace).widths
		local total = widths.left + widths.center + widths.right
		-- pick the column boundary closest to the cursor
		local boundary_left = area.x + area_w * widths.left / total
		local boundary_right = boundary_left + area_w * widths.center / total

		local drag = resize_state
		drag.workspace = workspace
		drag.start_x = cursor_x
		drag.area_w = area_w
		drag.total = total
		drag.start_widths = { left = widths.left, center = widths.center, right = widths.right }
		drag.edge = math.abs(cursor_x - boundary_left) <= math.abs(cursor_x - boundary_right) and "left" or "right"
		-- only start dragging once the begin state is fully populated; this
		-- makes the resize_tick timer racing this dispatch harmless by
		-- construction (resize-drag is a no-op until dragging is true).
		-- pending is false if the bind was already released, in which case
		-- the drag must not start
		drag.dragging = drag.pending
		drag.pending = false
	end,

	["resize-drag"] = function(ctx, arg)
		local drag = resize_state
		local cursor_x = tonumber(arg)
		if not (cursor_x and drag.dragging and drag.start_widths and drag.area_w > 0) then
			return
		end

		-- abort if the workspace changed mid-drag (e.g. workspace scroll)
		if (ctx_workspace(ctx) or active_workspace()) ~= drag.workspace then
			drag.dragging = false
			return
		end

		local delta = (cursor_x - drag.start_x) / drag.area_w * drag.total
		local min = drag.total * MIN_WIDTH_FRACTION
		local widths = {
			left = drag.start_widths.left,
			center = drag.start_widths.center,
			right = drag.start_widths.right,
		}

		if options_for(drag.workspace).resize == "symmetric" then
			-- dragging away from the center grows it, dragging towards shrinks it;
			-- left and right give up/gain the same amount
			local change = drag.edge == "right" and delta or -delta
			local lo = (min - widths.center) / 2
			local hi = math.max(lo, math.min(widths.left - min, widths.right - min))
			change = math.min(math.max(change, lo), hi)
			widths.center = widths.center + 2 * change
			widths.left = widths.left - change
			widths.right = widths.right - change
		elseif drag.edge == "left" then
			delta = math.max(min - widths.left, math.min(delta, widths.center - min))
			widths.left = widths.left + delta
			widths.center = widths.center - delta
		else
			delta = math.max(min - widths.center, math.min(delta, widths.right - min))
			widths.center = widths.center + delta
			widths.right = widths.right - delta
		end

		runtime_options(drag.workspace).widths = widths
	end,
}

local function register_layout()
	hl.layout.register("hyprnon", {
		recalculate = function(ctx)
			local count = #ctx.targets
			if count == 0 then
				return
			end

			local area = ctx.area
			local area_w, area_h = area_size(area)
			-- recalculate always has targets (count > 0 checked above)
			local workspace = ctx_workspace(ctx)
			local options = options_for(workspace)
			local columns = distribute(count, options)

			-- normalize widths across all columns so empty ones still reserve space
			local total = 0
			for _, name in ipairs(COLUMNS) do
				total = total + options.widths[name]
			end

			local x = area.x
			for _, name in ipairs(COLUMNS) do
				local width = area_w * options.widths[name] / total
				local members = columns[name]

				if #members > 0 then
					local height = area_h / #members

					for position, index in ipairs(members) do
						ctx.targets[index]:place({
							x = x,
							y = area.y + (position - 1) * height,
							w = width,
							h = height,
						})
					end
				end

				x = x + width
			end
		end,

		layout_msg = function(ctx, message)
			local handler = msg_handlers[message]
			if handler then
				handler(ctx)
				return true
			end

			local cmd, arg = message:match("^(%S+)%s+(%S+)$")
			local prefix_handler = cmd and msg_prefix_handlers[cmd]
			if prefix_handler then
				prefix_handler(ctx, arg)
				return true
			end
		end,
	})
end

-- manual resize: hold the resize bind and drag. floating windows get the
-- regular mouse resize; for tiled windows the column boundary nearest to the
-- cursor follows the mouse. single owner of the resize_bind combo.
local function resize_tick()
	if not resize_state.dragging then
		return
	end

	local pos = hl.get_cursor_pos()
	if pos then
		hl.dispatch(dsp.layout("resize-drag " .. pos.x))
	end
end

local function resize_start()
	-- with follow_mouse = 2 the active window may not be the one under the
	-- cursor, so check the window under the cursor instead
	local window = util.window_under_cursor()
	if window and window.floating then
		hl.dispatch(dsp.window.resize())
		return
	end

	local pos = hl.get_cursor_pos()
	if not pos then
		return
	end

	-- dragging is set to true by the resize-begin handler itself, so the
	-- repeating timer below cannot emit resize-drag before resize-begin
	-- has been processed and the drag state is populated
	resize_state.pending = true
	hl.dispatch(dsp.layout("resize-begin " .. pos.x))

	if resize_timer then
		resize_timer:set_enabled(true)
	else
		resize_timer = hl.timer(resize_tick, { timeout = 16, type = "repeat" })
	end
end

local function resize_stop()
	resize_state = new_resize_state()
	if resize_timer then
		resize_timer:set_enabled(false)
	end
end

local function drag_window()
	local window = util.window_under_cursor()
	if window and window.floating then
		hl.dispatch(dsp.window.drag())
	end
end

function M.setup(opts)
	opts = opts or {}

	if opts.defaults then
		for key, value in pairs(opts.defaults) do
			if type(defaults[key]) == "table" and type(value) == "table" then
				for k, v in pairs(value) do
					defaults[key][k] = v
				end
			else
				defaults[key] = value
			end
		end
	end

	if opts.workspaces then
		workspaces = opts.workspaces
	end

	register_layout()

	local main_mod = opts.main_mod or "SUPER"
	local move_bind = opts.move_bind or "mouse:272"
	local resize_bind = opts.resize_bind or "mouse:273"
	hl.bind(main_mod .. " + " .. resize_bind, resize_start, { mouse = true })
	hl.bind(main_mod .. " + " .. resize_bind, resize_stop, { release = true, mouse = true })
	hl.bind(main_mod .. " + " .. move_bind, drag_window, { mouse = true })

end

return M
