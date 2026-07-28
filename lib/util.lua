local M = {}

-- true if `window` is stacked above `other`: floating windows render on top
-- of tiled ones, and among floating windows the most recently focused one
-- (lowest focusHistoryID) is topmost
local function is_above(window, other)
	if window.floating ~= other.floating then
		return window.floating
	end

	local rank, other_rank = window.focusHistoryID, other.focusHistoryID
	if rank and other_rank then
		return rank < other_rank
	end

	return false
end

-- find the topmost window under the cursor on the active workspace
function M.window_under_cursor()
	local pos = hl.get_cursor_pos()
	if not pos then
		return nil
	end

	local workspace = hl.get_active_workspace()
	local result = nil
	for _, window in ipairs(hl.get_windows()) do
		if window.workspace and workspace and window.workspace.id == workspace.id then
			local at, size = window.at, window.size
			if pos.x >= at.x and pos.x < at.x + size.x
				and pos.y >= at.y and pos.y < at.y + size.y then
				if not result or is_above(window, result) then
					result = window
				end
			end
		end
	end
	return result
end

return M
