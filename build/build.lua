local _hjson = require "hjson"

local amalg = loadfile("./build/amalg.lua")

local OUTPUT_DIR = "./bin"

local function collect_requires(entrypoint)
	local requires = {}
	local ok, content = fs.safe_read_file(entrypoint)
	if not ok then
		return requires
	end
	for require in content:gmatch("require%s*%(?%s*['\"](.-)['\"]%s*%)?") do
		if not table.includes(requires, require) then
			-- change require to path
			local file = require:gsub("%.", "/") .. ".lua"
			if fs.file_type(file) == "file" then
				table.insert(requires, require)
				local subRequires = collect_requires(file)
				requires = util.merge_arrays(requires, subRequires) --[[ @as table ]]
			end
		end
	end
	return requires
end

local function minify(filePath)
	if not fs.exists("../build/luasrcdiet") then
		net.download_file("https://github.com/cryi/luasrcdiet/archive/refs/tags/1.1.1.zip", "../build/luasrcdiet.zip",
			{ follow_redirects = true })
		fs.mkdirp("../build/luasrcdiet")
		zip.extract("../build/luasrcdiet.zip", "../build/luasrcdiet", { flatten_root_dir = true })
	end

	local _cwd = os.cwd() or ""
	os.chdir("../build/luasrcdiet")
	local _eliPath = os.getenv("ELI_PATH") or arg[-1]
	os.execute(_eliPath .. " bin/luasrcdiet ../../bin/ami.lua -o ../../bin/ami-min.lua" ..
		" --opt-comments --noopt-whitespace --opt-emptylines" ..
		" --noopt-numbers --noopt-locals" ..
		" --opt-srcequiv --noopt-binequiv")
	os.rename("../../bin/ami-min.lua", "../../bin/ami.lua")

	os.chdir(_cwd)
end

local function inject_license(filePath)
	local _content = fs.read_file(filePath)
	local _, _shebangEnd = _content:find("#!/[^\n]*")
	local _license = [[
-- Copyright (C) 2024 alis.is

-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published
-- by the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.

-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
	]]
	local _contentWithLicense = _content:sub(1, _shebangEnd + 1) .. _license .. _content:sub(_shebangEnd + 1)
	fs.write_file(filePath, _contentWithLicense)
end

os.chdir("src")

local ascendEntrypoint = "ascend.lua"
local ascendOutput = "../bin/ascend"
amalg("-o", ascendOutput, "-s", ascendEntrypoint, table.unpack(collect_requires(ascendEntrypoint)))
inject_license(ascendOutput)

local asctlEntrypoint = "asctl.lua"
local asctlOutput = "../bin/asctl"
amalg("-o", asctlOutput, "-s", asctlEntrypoint, table.unpack(collect_requires(asctlEntrypoint)))
inject_license(asctlOutput)

fs.mkdirp("../bin/ami/")
local amiAsctlEntrypoint = "ami-plugin/asctl.lua"
local amiAsctlOutput = "../bin/ami/asctl.lua"
amalg("-o", amiAsctlOutput, "-s", amiAsctlEntrypoint, table.unpack(collect_requires(amiAsctlEntrypoint)))
local fileName = string.interpolate("${plugin_name}-${version}.zip", { plugin_name = "asctl", version = require"version-info".VERSION })
zip.compress("../bin/ami", path.combine("../bin", fileName), { recurse = true, content_only = true, overwrite = true })

-- minify
-- if not fs.exists("../build/luasrcdiet") then
-- 	net.download_file("https://github.com/cryi/luasrcdiet/archive/refs/tags/1.1.1.zip", "../build/luasrcdiet.zip", { follow_redirects = true })
-- 	fs.mkdirp("../build/luasrcdiet")
-- 	zip.extract("../build/luasrcdiet.zip", "../build/luasrcdiet", { flatten_root_dir = true })
-- end

-- local _cwd = os.cwd() or ""
-- os.chdir("../build/luasrcdiet")
-- local _eliPath = os.getenv("ELI_PATH") or arg[-1]
-- os.execute(_eliPath .. " bin/luasrcdiet ../../bin/ami.lua -o ../../bin/ami-min.lua" ..
-- 	" --opt-comments --noopt-whitespace --opt-emptylines" ..
-- 	" --noopt-numbers --noopt-locals" ..
-- 	" --opt-srcequiv --noopt-binequiv")
-- os.rename("../../bin/ami-min.lua", "../../bin/ami.lua")

-- os.chdir(_cwd)
