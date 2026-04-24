local M = {}

---@param path string
---@return boolean
function M.exist_filename(path)
	local file = io.open(path, "r")
	if file ~= nil then
		file:close()
		return true
	end
	return false
end

---@return string|nil, string|nil
function M.search_setup_resource()
	local home = os.getenv("HOME") or ""
	local candidate_paths = {
		home ~= "" and (home .. "/env_setup.bash") or nil,
		"/root/env_setup.bash",
	}

	for _, path in ipairs(candidate_paths) do
		if path ~= nil and M.exist_filename(path) then
			return path, nil
		end
	end

	return nil, "env_setup.bash not found in $HOME or /root"
end

---@param command string
---@return boolean, string
function M.run(command)
	local escaped_command = command:gsub("'", [['"'"']])
	local success, reason, code = os.execute("bash -lc '" .. escaped_command .. "'")
	if success == true or success == 0 then
		return true, "ok"
	end

	local message = string.format("command failed: reason=%s, code=%s", tostring(reason), tostring(code))
	return false, message
end

return M
