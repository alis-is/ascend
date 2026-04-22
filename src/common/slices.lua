local is_unix = package.config:sub(1, 1) == "/"
local path = path

local slices = {}

local function read_env(get_env, name)
	local value = get_env(name)
	if type(value) ~= "string" or #value == 0 then
		return nil
	end
	return value
end

local function sanitize_slice_user(user)
	user = tostring(user or ""):gsub("[^%w.%-]", "_")
	if #user == 0 then
		return "user"
	end
	return user
end

local function current_user(get_env)
	return read_env(get_env, "ASCEND_USER") or read_env(get_env, "USER") or read_env(get_env, "USERNAME")
end

local function system_socket_path()
	return is_unix and "/tmp/ascend.sock" or "\\\\.\\pipe\\ascend"
end

local function current_user_socket(get_env)
	if not is_unix then
		return "\\\\.\\pipe\\ascend-" .. sanitize_slice_user(current_user(get_env))
	end
	local runtime_dir = read_env(get_env, "XDG_RUNTIME_DIR")
	if runtime_dir then
		return path.combine(runtime_dir, "ascend.sock")
	end
	return path.combine("/tmp", "ascend-" .. sanitize_slice_user(current_user(get_env)) .. ".sock")
end

local function requested_user_socket(get_env, user)
	local requested_user = sanitize_slice_user(user)
	local current = sanitize_slice_user(current_user(get_env))
	if requested_user == current then
		return current_user_socket(get_env)
	end
	if not is_unix then
		return "\\\\.\\pipe\\ascend-" .. requested_user
	end
	return path.combine("/tmp", "ascend-" .. requested_user .. ".sock")
end

function slices.detect_is_root(get_env)
	if not is_unix then
		return false
	end
	get_env = get_env or os.getenv
	local handle = io.popen("id -u 2>/dev/null")
	if not handle then
		return current_user(get_env) == "root"
	end
	local uid = handle:read("l")
	handle:close()
	if uid ~= nil then
		return uid == "0"
	end
	return current_user(get_env) == "root"
end

function slices.resolve_ascend_defaults(options)
	options = options or {}
	local get_env = options.get_env or os.getenv
	local is_root = options.is_root
	if is_root == nil then
		is_root = slices.detect_is_root(get_env)
	end
	if is_unix and not is_root then
		local user = current_user(get_env)
		local home = read_env(get_env, "HOME")
		local tmp_root = path.combine("/tmp", "ascend-" .. sanitize_slice_user(user))
		local config_home = read_env(get_env, "XDG_CONFIG_HOME") or
			(home and path.combine(home, ".config")) or
			path.combine(tmp_root, "config")
		local state_home = read_env(get_env, "XDG_STATE_HOME") or
			(home and path.combine(home, ".local", "state")) or
			path.combine(tmp_root, "state")
		return {
			scope = "user",
			user = user,
			services_directory = path.combine(config_home, "ascend", "services"),
			healthchecksDirectory = path.combine(config_home, "ascend", "healthchecks"),
			ipcEndpoint = current_user_socket(get_env),
			logDirectory = path.combine(state_home, "ascend", "logs"),
			initScript = nil,
		}
	end
	return {
		scope = "system",
		user = nil,
		services_directory = is_unix and "/etc/ascend/services" or "C:\\ascend\\services",
		healthchecksDirectory = is_unix and "/etc/ascend/healthchecks" or "C:\\ascend\\healthchecks",
		ipcEndpoint = system_socket_path(),
		logDirectory = is_unix and "/var/log/ascend" or "C:\\ascend\\logs",
		initScript = nil,
	}
end

function slices.resolve_asctl_defaults(options)
	options = options or {}
	local get_env = options.get_env or os.getenv
	local user_option = options.user_option
	if user_option == nil or user_option == false then
		return {
			scope = "system",
			user = nil,
			ipcEndpoint = system_socket_path(),
		}
	end
	local requested_user = type(user_option) == "string" and #user_option > 0 and user_option ~= "true" and user_option or
		current_user(get_env)
	return {
		scope = "user",
		user = requested_user,
		ipcEndpoint = requested_user_socket(get_env, requested_user),
	}
end

return slices
