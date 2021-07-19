local relative_path_indirection_layer = {}

if _G.benmet_disable_relative_path_indirection_layer then
	-- only provide this function (trivially) so caching can still rely on it
	function relative_path_indirection_layer.path_to_cache_key(path) return path end
	
	return relative_path_indirection_layer
end


do -- simple implementation using the luafilesystem extension library (untested)
	
	local lfs_exists, lfs = pcall(require, 'lfs')
	if lfs_exists then
		local path_stack = {}
		local unique_keys = {}
		
		function relative_path_indirection_layer.path_to_cache_key(path)
			local cwd = assert(lfs.currentdir())
			return (string.sub(cwd, -1) == "/" and cwd or cwd .. "/") .. (string.match(path, "^%./+(.*)") or path)
		end
		
		function relative_path_indirection_layer.increase_stack(relative_path)
			path_stack[#path_stack+1] = assert(lfs.currentdir())
			assert(lfs.chdir(relative_path))
			
			local unique_key = {}
			unique_keys[#unique_keys+1] = unique_key
			return unique_key
		end
		
		function relative_path_indirection_layer.decrease_stack(unique_key)
			assert(unique_key == unique_keys[#unique_keys])
			unique_keys[#unique_keys] = nil
			
			local top = path_stack[#path_stack]
			path_stack[#path_stack] = nil
			assert(lfs.chdir(top))
		end
		
		return relative_path_indirection_layer
	end
	
end


-- complex implementation using only the standard library
-- First we replace the references to standard library functions with our own proxy functions.
	
	-- helper functions simplifying this process
	
	-- defines how to error for unexpected table entries
	local fallback_entry_handler = function(t, k, v)
			local escape = function(x)
				return type(x) == 'string' and "\""..x.."\""
					or tostring(x)
			end
			error("encountered unexpected entry ["..escape(k).."] = "..escape(v).." in '"..tostring(t).."' while scanning the environment for functions to stub")
		end
	-- look through every entry in a table:
	-- call specific handler functions matching entries in entry_handler_lookup,
	-- ignore the set given in entries_to_ignore_list,
	-- error if any other entries are present
	local handle_all_entries = function(t, entry_handler_lookup, entries_to_ignore_list)
			local entries_to_ignore_lookup = {}
			for i = 1, #entries_to_ignore_list do
				entries_to_ignore_lookup[entries_to_ignore_list[i]] = true
			end
			for k,v in pairs(t) do
				if entries_to_ignore_lookup[k] then
					assert(entry_handler_lookup[k] == nil)
				else
					local handler = entry_handler_lookup[k] or fallback_entry_handler
					handler(t, k, v)
				end
			end
		end
	
	local original_functions_by_table = {}
	local replacement_functions_by_table = {}
	-- replaces the table entry with a function forwarding to either the replacement function, or the original if no replacement is present
	local install_proxy_function = function(t, index, original_entry)
			local replacement_functions = replacement_functions_by_table[t]
			local original_functions = original_functions_by_table[t]
			if not replacement_functions then
				replacement_functions = {}
				replacement_functions_by_table[t] = replacement_functions
				original_functions = {}
				original_functions_by_table[t] = original_functions
			end
			local proxy = function(...) return (replacement_functions[index] or original_entry)(...) end
			t[index] = proxy
			original_functions[index] = original_entry
			return proxy
		end
	
	
	-- stubbing the standard library
	
	local package_loaded = package and package.loaded or _LOADED
	handle_all_entries(package_loaded, {
			_G = function(t, k, v) assert(v == _G) end,
			io = function(t, k, v) assert(v == io) end,
			package = function(t, k, v) assert(v == package) end,
		},
		-- ignore list: entries corresponding to modules that do not interact with the current working directory
		{'bit32', 'coroutine', 'string', 'table', 'utf8'}
	)
	
	local package_path = package and package.path
	if package then
		handle_all_entries(package, {
				loaded = function(t, k, v) assert(v == package_loaded) end,
				loadlib = install_proxy_function, -- args: libname, funcname
				path = function(t, k, v) assert(v == package_path) end,
				searchpath = install_proxy_function, -- args: name, path [, sep [, rep] ]
			},
			-- ignore list: entries that do not (themselves) interact with the current working directory
			{'config', 'cpath', 'loaders', 'preload', 'searchers', 'seeall'}
		)
	end
	
	handle_all_entries(io, {
			input = install_proxy_function, -- args: [file] -- if file is a string, it is a file path
			lines = install_proxy_function, -- args: [filename]
			open = install_proxy_function, -- args: filename [, mode]
			output = install_proxy_function, -- args: [file] -- if file is a string, it is a file path
			popen = install_proxy_function, -- args: prog [, mode] -- prog is a shell command
		},
		-- ignore list: entries that do not (themselves) interact with the current working directory
		{'close', 'flush', 'read', 'tmpfile', 'type', 'write'}
	)
	
	handle_all_entries(os, {
			execute = install_proxy_function, -- args: command
			remove = install_proxy_function, -- args: filename
			rename = install_proxy_function, -- args: oldname, newname
			tmpname = install_proxy_function, -- no args, returns file name
		},
		-- ignore list: entries that do not interact with the current working directory
		{'clock', 'date', 'difftime', 'exit', 'getenv', 'setlocale', 'time'}
	)
	
	local env_table = getfenv and getfenv()
		or _ENV
	handle_all_entries(env_table, {
			_G = function(env_table, index, _G) assert(_G == env_table) end,
			_LOADED = function(t, k, v) assert(v == package_loaded) end,
			LUA_PATH = function(t, k, v) assert(v == package_path) end,
			
			dofile = install_proxy_function, -- args: [filename]
			loadfile = install_proxy_function, -- args: [filename, [mode, [env] ] ]
			loadlib = install_proxy_function, -- args: libname, funcname
			
			benmet_get_lua_program_command = install_proxy_function, -- no args, returns shell command
			benmet_get_main_script_dir_path = install_proxy_function, -- no args, returns directory path
		},
		-- ignore list: these do not interact with the current working directory (except for 'require', which is handled by modifying package.path)
		{
			-- modules handled above
			'io',
			'os',
			'package',
			-- global variables set by benmet
			'benmet_disable_relative_path_indirection_layer', 'benmet_ensure_package_path_entries_are_absolute', 'benmet_launch_steps_as_child_processes', 'benmet_relative_path_prefix',
			-- functions, ordered lexicographically
			'_VERSION', 'assert', 'collectgarbage', 'error', 'getfenv', 'getmetatable', 'gcinfo', 'ipairs', 'load', 'loadstring', 'module', 'next', 'pairs', 'pcall', 'print', 'rawequal', 'rawget', 'rawlen', 'rawset', 'require', 'select', 'setfenv', 'setmetatable', 'tonumber', 'tostring', 'type', 'unpack', 'warn', 'xpcall',
			-- modules, ordered lexicographically
			'bit32', 'coroutine', 'string', 'table', 'utf8',
		}
	)


-- forward declaration for our 'benmet.util' import (which we assign later)
local util

-- now define our main interface functions

-- the current relative path indirection prefix, used by functions to translate current directory to effective path
local relative_path_indirection_prefix = ""
-- the inverse of the current relative path indirection prefix, used by functions to translate effective relative paths back to the underlying current directory
local relative_path_inverse_indirection_prefix = ""

-- takes a path, returns a string that can safely cache this path across the relative path indirection layer
function relative_path_indirection_layer.path_to_cache_key(path) -- lazy implementation, won't give false collisions, but could be improved to normalize paths
	return util.path_is_absolute(path) and path
		or relative_path_indirection_prefix..(string.match(path, "^%.[/\\]+(.*)") or path)
end

-- every entry consists of a table {accumulated relative path prefix, accumulated relative path inverse prefix, unique key}
local relative_path_indirection_stack = {}
local relative_path_indirection_stack_size = 0

-- increases the relative path indirection stack, returns a unique key required for decreasing the stack again (to guard against misuse)
function relative_path_indirection_layer.increase_stack(relative_path_prefix)
	-- normalize prefix
	relative_path_prefix = string.sub(relative_path_prefix, -1) == "/" and relative_path_prefix
		or relative_path_prefix.."/"
	assert(not util.path_is_absolute(relative_path_prefix))
	
	-- ensure our own package path entries are absolute first, because that may rely on querying the current directory
	_G.benmet_ensure_package_path_entries_are_absolute()
	
	-- calculate depth of the new prefix
	local depth = 0
	for segment in string.gmatch(relative_path_prefix, "[^/\\]+") do
		if segment ~= "." then
			if segment == ".." then
				assert(depth > 0, "relative_path_prefix escaping the current directory are currently not supported")
				depth = depth - 1
			else
				depth = depth + 1
			end
		end
	end
	
	-- save current state to the stack
	local unique_key = {}
	local n = relative_path_indirection_stack_size
	relative_path_indirection_stack[n+1] = relative_path_indirection_prefix
	relative_path_indirection_stack[n+2] = relative_path_inverse_indirection_prefix
	relative_path_indirection_stack[n+3] = package_path
	relative_path_indirection_stack[n+4] = package and package.cpath
	relative_path_indirection_stack[n+5] = unique_key
	-- grow stack
	relative_path_indirection_stack_size = relative_path_indirection_stack_size + 5
	
	-- update package.path/LUA_PATH and package.cpath
	if package_path then
		package_path = util.prefix_relative_path_templates_in_string(package_path, relative_path_prefix)
		LUA_PATH = LUA_PATH and package_path
		if package and package.path then
			package.path = package_path
		end
	end
	if package and package.cpath then
		package.cpath = util.prefix_relative_path_templates_in_string(package.cpath, relative_path_prefix)
	end
	
	-- update prefixes
	relative_path_indirection_prefix = relative_path_indirection_prefix .. relative_path_prefix
	relative_path_inverse_indirection_prefix = relative_path_inverse_indirection_prefix .. string.rep("../", depth)
	
	return unique_key
end

-- decreases the relative path indirection stack, requires the unique key returned from the matching call to relative_path_indirection_layer.increase_stack
function relative_path_indirection_layer.decrease_stack(unique_key)
	-- restore previous state from the stack
	local n = relative_path_indirection_stack_size
	assert(unique_key == relative_path_indirection_stack[n])
	
	if package and package.cpath then
		package.cpath = relative_path_indirection_stack[n-1]
	end
	
	if package_path then
		package.path = package.path and relative_path_indirection_stack[n-2]
		LUA_PATH = LUA_PATH and relative_path_indirection_stack[n-2]
	end
	
	relative_path_inverse_indirection_prefix = relative_path_indirection_stack[n-3]
	relative_path_indirection_prefix = relative_path_indirection_stack[n-4]
	
	-- shrink stack
	relative_path_indirection_stack_size = relative_path_indirection_stack_size - 5
	
	-- remove previous state from the stack (not strictly necessary)
	relative_path_indirection_stack[n] = nil
	relative_path_indirection_stack[n-1] = nil
	relative_path_indirection_stack[n-2] = nil
	relative_path_indirection_stack[n-3] = nil
	relative_path_indirection_stack[n-4] = nil
end


-- set our table as our exported require-entry
package_loaded['benmet.relative_path_indirection_layer'] = relative_path_indirection_layer

-- now we can require 'benmet.util'
util = require 'benmet.util'



-- implement the desired behaviour of our proxy functions

local prefix_indirection_if_relative = function(path)
		return util.path_is_absolute(path) and path
			or relative_path_indirection_prefix .. path
	end
local prefix_inverse_indirection_if_relative = function(path)
		return util.path_is_absolute(path) and path
			or relative_path_inverse_indirection_prefix .. path
	end

local wrap_shell_command = function(command)
	return command and (command == "" and command
			or "cd "..util.in_quotes(relative_path_indirection_prefix).." && ( "..command.." )")
end

local original_table_by_original_functions_table = {}
for original_table, original_functions_table in pairs(original_functions_by_table) do
	original_table_by_original_functions_table[original_functions_table] = original_table
end
local provide_replacement = function(replacement_provider)
	return function(original_functions_table, k, original)
		local t = original_table_by_original_functions_table[original_functions_table]
		local replacement = replacement_provider(original)
		replacement_functions_by_table[t][k] = replacement
		t[k] = replacement
	end
end

if package then
	handle_all_entries(original_functions_by_table[package], {
		loadlib = provide_replacement(function(original_loadlib)
				return function(libname, --[[funcname]]...)
					libname = prefix_indirection_if_relative(libname)
					return original_loadlib(libname, --[[funcname]]...)
				end
			end),
		searchpath = provide_replacement(function(original_searchpath)
				return function(name, path --[[ [, sep [, rep] ] ]]...)
					local prefixed_relative_elements_path = util.prefix_relative_path_templates_in_string(path, relative_path_indirection_prefix)
					return original_searchpath(name, prefixed_relative_elements_path, ...)
				end
			end),
	})
end

handle_all_entries(original_functions_by_table[io], {
	input = provide_replacement(function(original_input)
			return function(file, ...) -- if file is a string, it is a file path
				file = type(file) == 'string' and prefix_indirection_if_relative(file)
					or file
				return original_input(file, ...)
			end
		end),
	lines = provide_replacement(function(original_lines)
			return function(filename, ...)
				filename = filename and prefix_indirection_if_relative(filename)
				return original_lines(filename, ...)
			end
		end),
	open = provide_replacement(function(original_open)
			return function(filename, --[[ [, mode] ]]...)
				filename = filename and prefix_indirection_if_relative(filename)
				return original_open(filename, ...)
			end
		end),
	output = provide_replacement(function(original_output)
			return function(file, ...) -- if file is a string, it is a file path
				file = type(file) == 'string' and prefix_indirection_if_relative(file)
					or file
				return original_output(file, ...)
			end
		end),
	popen = provide_replacement(function(original_popen)
			return function(prog, --[[ [, mode] ]]...) -- prog is a shell command
				prog = wrap_shell_command(prog)
				return original_popen(prog, ...)
			end
		end),
})

handle_all_entries(original_functions_by_table[os], {
	execute = provide_replacement(function(original_execute)
			return function(command, ...)
				command = wrap_shell_command(command)
				return original_execute(command, ...)
			end
		end),
	remove = provide_replacement(function(original_remove)
			return function(filename, ...)
				filename = prefix_indirection_if_relative(filename)
				return original_remove(filename, ...)
			end
		end),
	rename = provide_replacement(function(original_rename)
			return function(oldname, newname, ...)
				oldname = prefix_indirection_if_relative(oldname)
				newname = prefix_indirection_if_relative(newname)
				return original_rename(oldname, newname, ...)
			end
		end),
	tmpname = provide_replacement(function(original_tmpname)
			return function()
				return prefix_inverse_indirection_if_relative(original_tmpname())
			end
		end),
})

handle_all_entries(original_functions_by_table[env_table], {
	dofile = provide_replacement(function(original_dofile)
			return function(filename, ...)
				filename = filename and prefix_indirection_if_relative(filename)
				return original_dofile(filename, ...)
			end
		end),
	loadfile = provide_replacement(function(original_loadfile)
			return function(filename, --[[ [mode, [env] ] ]]...)
				filename = filename and prefix_indirection_if_relative(filename)
				return original_loadfile(filename, ...)
			end
		end),
	loadlib = provide_replacement(function(original_loadlib)
			return function(libname, --[[funcname]]...)
				libname = prefix_indirection_if_relative(libname)
				return original_loadlib(libname, ...)
			end
		end),
	
	benmet_get_lua_program_command = provide_replacement(function(original_benmet_get_lua_program_command)
			return function()
				local new_function
				
				local original_lua_program = original_benmet_get_lua_program_command()
				if util.path_is_absolute(original_lua_program) then -- if it's an absolute path, nothing to adjust
					-- fallthrough
				elseif string.match(original_lua_program, "[/%\\]") then -- if it contains a directory separator, it's a path, so adjust it
					new_function = function() return prefix_indirection_if_relative(original_lua_program) end
				else -- otherwise it's a program that's looked up on PATH; we could make it absolute via util.find_program, but we can also just leave it as-is
					-- fallthrough
				end
				
				new_function = new_function
					or function() return original_lua_program end
				replacement_functions_by_table[env_table].benmet_get_lua_program_command = new_function
				
				return new_function()
			end
		end),
	benmet_get_main_script_dir_path = provide_replacement(function(original_benmet_get_main_script_dir_path)
			return function(...)
				return prefix_inverse_indirection_if_relative(original_benmet_get_main_script_dir_path(...))
			end
		end),
})



return relative_path_indirection_layer
