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
	special_scale = 1,
}

local workspaces = {}

-- mutable runtime overrides (toggles, manual resizes)
local runtime_overrides = {}

-- per-workspace column memory: order = last list order, col = address -> column
local layouts = {}

local function layout_memory(workspace)
	local key = tostring(workspace)
	local mem = layouts[key]
	if not mem then
		mem = { order = {}, col = {} }
		layouts[key] = mem
	end
	return mem
end

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

	-- 0.57 drops the numbered id for specials, name carries the full selector
	if workspace.special then
		return workspace.name
	end

	return workspace.id
end

local function is_special(workspace)
	return workspace and workspace.special or false
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

-- split `count` windows into columns purely by list order, used to realize a swap
local function distribute_by_index(count, options)
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

local function to_set(list)
	local set = {}
	for _, addr in ipairs(list) do
		set[addr] = true
	end
	return set
end

local function same_order(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

-- place windows with no remembered column: empty columns first, then stack on the configured side
local function fill_new(entries, columns, options)
	local stack = options.stack == "right" and "right" or "left"
	local max = options.max

	local function room(name)
		local limit = max[name]
		return not limit or #columns[name] < limit
	end

	for _, entry in ipairs(entries) do
		local placed = false

		for _, name in ipairs(FILL_ORDER) do
			if #columns[name] == 0 and room(name) then
				entry.column = name
				placed = true
				break
			end
		end

		if not placed then
			for _, name in ipairs(STACK_ORDER[stack]) do
				if room(name) then
					entry.column = name
					placed = true
					break
				end
			end

			if not placed then
				entry.column = stack
			end
		end

		table.insert(columns[entry.column], entry)
	end
end

-- fill an empty column from a stacked one, newest first, until no hole has a donor
local function promote_from_stacks(columns, options)
	local donor_order = { options.stack, "left", "center", "right" }

	while true do
		local empty
		for _, name in ipairs(FILL_ORDER) do
			if #columns[name] == 0 then
				empty = name
				break
			end
		end
		if not empty then
			return
		end

		local donor
		for _, name in ipairs(donor_order) do
			if name ~= empty and #columns[name] >= 2 then
				donor = name
				break
			end
		end
		if not donor then
			return
		end

		local entry = table.remove(columns[donor], #columns[donor])
		entry.column = empty
		table.insert(columns[empty], entry)
	end
end

-- give each window a column, keeping survivors put across add and remove.
-- a window keeps its column until the list order changes, which means a swap or move.
local function assign_columns(ctx, options, mem)
	local entries, addrs, entry_by_addr = {}, {}, {}
	for index = 1, #ctx.targets do
		local target = ctx.targets[index]
		local window = target.window
		local addr = window and window.address or ("#" .. index)
		local entry = { target = target, addr = addr }
		entries[index] = entry
		addrs[index] = addr
		entry_by_addr[addr] = entry
	end

	local columns = { left = {}, center = {}, right = {} }
	local current = to_set(addrs)

	local survivors_now, survivors_prev = {}, {}
	for _, addr in ipairs(addrs) do
		if mem.col[addr] then
			table.insert(survivors_now, addr)
		end
	end
	for _, addr in ipairs(mem.order) do
		if current[addr] then
			table.insert(survivors_prev, addr)
		end
	end

	if not same_order(survivors_now, survivors_prev) then
		-- the list was reordered by a swap or directional move, re-derive from list order
		local by_index = distribute_by_index(#addrs, options)
		for _, name in ipairs(COLUMNS) do
			for _, index in ipairs(by_index[name]) do
				local entry = entries[index]
				entry.column = name
				table.insert(columns[name], entry)
			end
		end
	else
		-- keep every survivor in its remembered column, then place the new windows
		local prev = to_set(mem.order)
		for _, addr in ipairs(mem.order) do
			if current[addr] then
				local entry = entry_by_addr[addr]
				entry.column = mem.col[addr]
				table.insert(columns[entry.column], entry)
			end
		end

		local fresh = {}
		for _, entry in ipairs(entries) do
			if not prev[entry.addr] then
				table.insert(fresh, entry)
			end
		end
		fill_new(fresh, columns, options)
	end

	promote_from_stacks(columns, options)

	-- remember the assignment, dropping windows that are gone
	local col = {}
	for _, name in ipairs(COLUMNS) do
		for _, entry in ipairs(columns[name]) do
			col[entry.addr] = entry.column
		end
	end
	mem.col = col
	mem.order = addrs

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
			local columns = assign_columns(ctx, options, layout_memory(workspace))

			-- scale the whole region so windows stay adjacent and direction focus works
			local window = ctx.targets[1].window
			local scale = is_special(window and window.workspace) and options.special_scale or 1
			local region_x, region_y = area.x, area.y
			local region_w, region_h = area_w, area_h
			if scale ~= 1 then
				region_w = area_w * scale
				region_h = area_h * scale
				region_x = area.x + (area_w - region_w) / 2
				region_y = area.y + (area_h - region_h) / 2
			end

			-- normalize widths across all columns so empty ones still reserve space
			local total = 0
			for _, name in ipairs(COLUMNS) do
				total = total + options.widths[name]
			end

			local x = region_x
			for _, name in ipairs(COLUMNS) do
				local width = region_w * options.widths[name] / total
				local members = columns[name]

				if #members > 0 then
					local height = region_h / #members

					for position, entry in ipairs(members) do
						entry.target:place({
							x = x,
							y = region_y + (position - 1) * height,
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

	if opts.special_scale then
		defaults.special_scale = opts.special_scale
	end

	if opts.workspaces then
		workspaces = opts.workspaces
	end

	register_layout()

	local main_mod = opts.main_mod or "SUPER"
	local move_bind = opts.move_bind or "mouse:272"
	local resize_bind = opts.resize_bind or "mouse:273"
	hl.bind(main_mod .. " + " .. resize_bind, resize_start, { mouse = true })
	hl.bind(main_mod .. " + " .. resize_bind, resize_stop, { release = true })
	hl.bind(main_mod .. " + " .. move_bind, drag_window, { mouse = true })

end

return M
