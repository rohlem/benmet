--[[
This file holds logic to isolate the program state in a layer of indirection.
Using this, Lua code can be instrumented to execute under a (simulated) different working directory, redirect stdout writes to a memory buffer and restore the io package and global environment table to a previous state.
This enables us to load step scripts (if they are Lua code) and run them in the same Lua VM instance, instead of launching a new subprocess.
--]]

local indirection_layer = {}

if _G.benmet_disable_indirection_layer then
	-- only provide this function (trivially) so caching can still rely on it
	function indirection_layer.path_to_cache_key(path) return path end
	
	return indirection_layer
end


do -- simple implementation of the relative path indirection using the luafilesystem extension library (untested)
--[[ this implementation is missing the stdout redirection and global table reset logic (previously not part of this file)
	
	local lfs_exists, lfs = pcall(require, 'lfs')
	if lfs_exists then
		local path_stack = {}
		local unique_keys = {}
		
		function indirection_layer.path_to_cache_key(path)
			local cwd = assert(lfs.currentdir())
			return (string.sub(cwd, -1) == "/" and cwd or cwd .. "/") .. (string.match(path, "^%./+(.*)") or path)
		end
		
		function indirection_layer.increase_stack(relative_path)
			path_stack[#path_stack+1] = assert(lfs.currentdir())
			assert(lfs.chdir(relative_path))
			
			local unique_key = {}
			unique_keys[#unique_keys+1] = unique_key
			return unique_key
		end
		
		function indirection_layer.decrease_stack(unique_key)
			assert(unique_key == unique_keys[#unique_keys])
			unique_keys[#unique_keys] = nil
			
			local top = path_stack[#path_stack]
			path_stack[#path_stack] = nil
			assert(lfs.chdir(top))
		end
		
		return indirection_layer
	end
	
--]]
end


local pairs = pairs -- table_restore_from_backup can temporarily clear the global table, but still wants to use pairs

-- complex implementation of indirection using only the standard library
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
			for i = 1, entries_to_ignore_list and #entries_to_ignore_list or 0 do
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
			os = function(t, k, v) assert(v == os) end,
			package = function(t, k, v) assert(v == package) end,
		},
		-- ignore list: entries corresponding to modules that do not interact with the current working directory, stdout and io package state
		{'benmet.commands', 'bit32', 'coroutine', 'debug', 'math', 'string', 'table', 'utf8'}
	)
	
	local original_package_path = package and package.path
	if package then
		handle_all_entries(package, {
				loaded = function(t, k, v) assert(v == package_loaded) end,
				loadlib = install_proxy_function, -- args: libname, funcname
				path = function(t, k, v) assert(v == original_package_path) end,
				searchpath = install_proxy_function, -- args: name, path [, sep [, rep] ]
			},
			-- ignore list: entries that do not (themselves) interact with the current working directory, stdout and io package state
			{'config', 'cpath', 'loaders', 'preload', 'searchers', 'seeall'}
		)
	end
	
	handle_all_entries(io, {
			close = install_proxy_function, -- args: [file] -- default output file if file is nil
			flush = install_proxy_function, -- no args -- flushes the default output file
			input = install_proxy_function, -- args: [file] -- if file is a string, it is a file path
			lines = install_proxy_function, -- args: [filename]
			open = install_proxy_function, -- args: filename [, mode]
			output = install_proxy_function, -- args: [file] -- if file is a string, it is a file path
			popen = install_proxy_function, -- args: prog [, mode] -- prog is a shell command
			read = install_proxy_function, -- args: formats... -- reads from the default input file
			type = install_proxy_function, -- takes an object, returns 'file' if it is a file handle, 'closed file' if it is a closed file handle; needs to be stubbed for our stub stdout
			write = install_proxy_function, -- args: values... -- writes to the default output file
		},
		-- ignore list: entries that do not (themselves) interact with the current working directory, stdout and io package state
		{'stderr', 'stdin', 'stdout', 'tmpfile'}
	)
	
	handle_all_entries(os, {
			execute = install_proxy_function, -- args: command
			remove = install_proxy_function, -- args: filename
			rename = install_proxy_function, -- args: oldname, newname
			tmpname = install_proxy_function, -- no args, returns file name
		},
		-- ignore list: entries that do not interact with the current working directory, stdout and io package state
		{'clock', 'date', 'difftime', 'exit', 'getenv', 'setlocale', 'time'}
	)
	
	local env_table = getfenv and getfenv()
		or _ENV
	handle_all_entries(env_table, {
			_G = function(env_table, index, _G) assert(_G == env_table) end,
			_LOADED = function(t, k, v) assert(v == package_loaded) end,
			LUA_PATH = function(t, k, v) assert(v == original_package_path) end,
			
			dofile = install_proxy_function, -- args: [filename]
			loadfile = install_proxy_function, -- args: [filename, [mode, [env] ] ]
			loadlib = install_proxy_function, -- args: libname, funcname
			
			print = install_proxy_function, -- args: values...
			
			require = install_proxy_function, -- args: module name
			
			benmet_get_lua_program_command = install_proxy_function, -- no args, returns shell command
			benmet_get_main_script_dir_path = install_proxy_function, -- no args, returns directory path
		},
		-- ignore list: these do not interact with the current working directory, stdout and io package state
		{
			-- modules handled above
			'io',
			'os',
			'package',
			-- global variables set by benmet
			'benmet_disable_indirection_layer', 'benmet_ensure_package_path_entries_are_absolute', 'benmet_launch_steps_as_child_processes', 'benmet_relative_path_prefix', 'benmet_util_skip_library_imports',
			-- global variables, ordered lexicographically
			'_VERSION', 'arg',
			-- functions, ordered lexicographically
			'assert', 'collectgarbage', 'error', 'getfenv', 'getmetatable', 'gcinfo', 'ipairs', 'load', 'loadstring', 'module', 'next', 'pairs', 'pcall', 'rawequal', 'rawget', 'rawlen', 'rawset', 'select', 'setfenv', 'setmetatable', 'tonumber', 'tostring', 'type', 'unpack', 'warn', 'xpcall',
			-- modules, ordered lexicographically
			'bit32', 'coroutine', 'debug', 'math', 'string', 'table', 'utf8',
		}
	)

-- global state of our indirect io package
local io_standard_input_file = io.input()
local io_standard_output_file = io.output()
local io_indirection_count = 0

 -- forward declarations
local io_in_memory_stdout_file
local io_in_memory_stdout_buffer

local table_backup
local table_restore_from_backup


-- forward declaration for our 'benmet.util' import (which we assign later)
local util

-- now define our main interface functions

-- the current relative path indirection prefix, used by functions to translate current directory to effective path
local relative_path_indirection_prefix = ""
-- the inverse of the current relative path indirection prefix, used by functions to translate effective relative paths back to the underlying current directory
local relative_path_inverse_indirection_prefix = ""

-- takes a path, returns a string that can safely cache this path across the relative path indirection layer
function indirection_layer.path_to_cache_key(path) -- lazy implementation, won't give false collisions, but could be improved to normalize paths
	return util.path_is_absolute(path) and path
		or relative_path_indirection_prefix..(string.match(path, "^%.[/\\]+(.*)") or path)
end

-- every entry consists of entries for accumulated relative path prefix, accumulated relative path inverse prefix, recursive global table backup, standard input file, standard output file, standard output buffer, newly acquired modules, and unique key
local indirection_stack = {}
local indirection_stack_size = 0

-- increases the relative path indirection stack, returns a unique key required for decreasing the stack again (to guard against misuse)
function indirection_layer.increase_stack(relative_path_prefix, new_arg)
	-- normalize prefix
	relative_path_prefix = relative_path_prefix or ""
	if #relative_path_prefix > 0 then
		relative_path_prefix = string.sub(relative_path_prefix, -1) == "/" and relative_path_prefix
			or relative_path_prefix.."/"
		assert(not util.path_is_absolute(relative_path_prefix))
		assert(util.directory_exists(relative_path_prefix))
	end
	
	-- ensure our own package path entries are absolute first, because the function only runs once and may rely on querying the current directory
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
	
	-- make a backup of the environment table
	local env_table_backup = table_backup(env_table)
	
	-- save current state to the stack
	local unique_key = {}
	local n = indirection_stack_size
	indirection_stack[n+1] = relative_path_indirection_prefix
	indirection_stack[n+2] = relative_path_inverse_indirection_prefix
	indirection_stack[n+3] = io_standard_input_file
	indirection_stack[n+4] = io_standard_output_file
	indirection_stack[n+5] = io_in_memory_stdout_buffer
	indirection_stack[n+6] = env_table_backup
	indirection_stack[n+7] = unique_key
	-- grow stack
	indirection_stack_size = indirection_stack_size + 7
	
	if #relative_path_prefix > 0 then
		-- update package.path/LUA_PATH and package.cpath
		local package_path = (package.path or LUA_PATH)
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
	end
	
	-- install io indirection
	io_standard_input_file = io.stdin -- strangely, the standard behaviour for io.popen(_, 'r') is to pass through our own stdin
	io_standard_output_file = io_in_memory_stdout_file
	io_in_memory_stdout_buffer = {}
	io_indirection_count = io_indirection_count + 1
	
	-- install new arg table
	arg = new_arg
	
	return unique_key
end

-- decreases the relative path indirection stack, requires the unique key returned from the matching call to indirection_layer.increase_stack
function indirection_layer.decrease_stack(unique_key)
	-- restore previous state from the stack
	assert(unique_key == indirection_stack[indirection_stack_size])
	
	-- shrink stack
	indirection_stack_size = indirection_stack_size - 7
	local n = indirection_stack_size
	
	-- restore the environment table from our backup
	table_restore_from_backup(indirection_stack[n+7])
	
	-- gather output from memory
	local in_memory_stdout_result = table.concat(io_in_memory_stdout_buffer)
	-- restore io state
	io_indirection_count = io_indirection_count - 1
	io_in_memory_stdout_buffer = indirection_stack[n+5]
	io_standard_output_file = indirection_stack[n+4]
	io_standard_input_file = indirection_stack[n+3]
	
	relative_path_inverse_indirection_prefix = indirection_stack[n+2]
	relative_path_indirection_prefix = indirection_stack[n+1]
	
	
	-- remove previous state from the stack (not strictly necessary)
	indirection_stack[n+1] = nil
	indirection_stack[n+2] = nil
	indirection_stack[n+3] = nil
	indirection_stack[n+4] = nil
	indirection_stack[n+5] = nil
	indirection_stack[n+6] = nil
	indirection_stack[n+7] = nil
	indirection_stack[n+8] = nil
	
	return in_memory_stdout_result
end


-- set our table as our exported require-entry
package_loaded['benmet.indirection_layer'] = indirection_layer

-- now we can require 'benmet.util'
util = require 'benmet.util'



-- implement the desired behaviour of our proxy functions

local prefix_indirection_if_relative = function(path)
		local had_quotes
		path, had_quotes = util.remove_quotes(path)
		path = util.path_is_absolute(path) and path
			or relative_path_indirection_prefix .. path
		return had_quotes and util.in_quotes(path)
			or path
	end
local prefix_inverse_indirection_if_relative = function(path)
		local had_quotes
		path, had_quotes = util.remove_quotes(path)
		path = util.path_is_absolute(path) and path
			or relative_path_inverse_indirection_prefix .. path
		return had_quotes and util.in_quotes(path)
			or path
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
				return function(name, path, --[[ [, sep [, rep] ] ]]...)
					local prefixed_relative_elements_path = util.prefix_relative_path_templates_in_string(path, relative_path_indirection_prefix)
					return original_searchpath(name, prefixed_relative_elements_path, ...)
				end
			end),
	})
end

handle_all_entries(original_functions_by_table[io], {
	close = provide_replacement(function(original_close)
			return function(file, ...) -- if file is nil, it refers to the default output file
				if io_indirection_count == 0 or file ~= nil then
					return original_close(file, ...)
				end
				return io_standard_output_file:close()
			end
		end),
	flush = provide_replacement(function(original_flush)
			return function()
				if io_indirection_count == 0 then
					return original_flush()
				end
				return io_standard_output_file:flush()
			end
		end),
	input = provide_replacement(function(original_input)
			return function(file, ...) -- if file is a string, it is a file path; if it is nil, we only return the default input file
				local file_is_string = type(file) == 'string'
				file = file_is_string and prefix_indirection_if_relative(file)
					or file
				if io_indirection_count == 0 then
					return original_input(file, ...)
				end
				if file ~= nil then
					io_standard_input_file = file_is_string and assert(io.open(file, 'r')) -- technically the error message is formatted a bit differently between io.input and io.open
						or file
				end
				return io_standard_input_file
			end
		end),
	lines = provide_replacement(function(original_lines)
			return function(filename, ...)
				if io_indirection_count == 0 or filename then
					filename = filename and prefix_indirection_if_relative(filename)
					return original_lines(filename, ...)
				end
				return io_standard_input_file:lines(...)
			end
		end),
	open = provide_replacement(function(original_open)
			return function(filename, --[[ [, mode] ]]...)
				filename = filename and prefix_indirection_if_relative(filename)
				return original_open(filename, ...)
			end
		end),
	output = provide_replacement(function(original_output)
			return function(file, ...) -- if file is a string, it is a file path; if it is nil, we only return the default input file
				local file_is_string = type(file) == 'string'
				file = file_is_string and prefix_indirection_if_relative(file)
					or file
				if io_indirection_count == 0 then
					return original_output(file, ...)
				end
				if file ~= nil then
					io_standard_output_file = file_is_string and assert(io.open(file, 'w')) -- technically the error message is formatted a bit differently between io.output and io.open
						or file
				end
				return io_standard_output_file
			end
		end),
	popen = provide_replacement(function(original_popen)
			return function(prog, --[[ [, mode] ]]...) -- prog is a shell command
				prog = wrap_shell_command(prog)
				return original_popen(prog, ...)
			end
		end),
	read = provide_replacement(function(original_read)
			return function(--[[formats]]...)
				if io_indirection_count == 0 then
					return original_read(...)
				end
				return io_standard_input_file:read(...)
			end
		end),
	type = provide_replacement(function(original_type)
			return function(file, ...)
				if io_indirection_count == 0 or file ~= io_in_memory_stdout_file then
					return original_type(file, ...)
				end
				return 'file'
			end
		end),
	write = provide_replacement(function(original_write)
			return function(--[[formats]]...)
				if io_indirection_count == 0 then
					return original_write(...)
				end
				return io_standard_output_file:write(...)
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
	
	print = provide_replacement(function(original_print)
			return function(--[[args]]...)
				if io_indirection_count == 0 then
					return original_print(...)
				end
				local args_list = {--[[args]]...}
				local n = #io_in_memory_stdout_buffer
				if #args_list > 0 then
					n = n + 1
					io_in_memory_stdout_buffer[n] = tostring(args_list[1])
					for i = 2, #args_list do
						n = n + 1
						io_in_memory_stdout_buffer[n] = "\t"
						n = n + 1
						io_in_memory_stdout_buffer[n] = tostring(args_list[i])
					end
				end
				n = n + 1
				io_in_memory_stdout_buffer[n] = "\n"
			end
		end),
	
	require = provide_replacement(function(original_require)
			-- cache to skip subsequent require calls
			local newly_loaded_modules = {}
			local newly_loaded_module_backups = {}
			local known_state_safe_modules_lookup = {
				['benmet.commands'] = true,
				['benmet.indirection_layer'] = true,
				['benmet.step_templates'] = true,
				['benmet.util'] = true,
				['lunajson'] = true,
				['pure_lua_SHA.sha2'] = true,
			}
			return function(module_name)
				local package_loaded = (package.loaded or _LOADED)
				local cached_module = package_loaded[module_name]
				if cached_module then
					return cached_module
				end
				
				cached_module = newly_loaded_module_backups[module_name]
				if cached_module then
					local cached_backup = newly_loaded_module_backups[cached_module]
					table_restore_from_backup(cached_backup)
					package_loaded[module_name] = cached_module
					return cached_module
				end
				
				local module = original_require(module_name)
				if known_state_safe_modules_lookup[module_name] then
					newly_loaded_modules[module_name] = module
					newly_loaded_module_backups[module] = table_backup(module)
				end
				return module
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


-- implement io_in_memory_stdout_file
local file_metatable = getmetatable(io.stdout)
local file_metatable__index = file_metatable.__index
local file_fields = type(file_metatable__index) == 'table' and file_metatable__index
	or setmetatable({}, {__index = function(self, index)
			local value = file_metatable__index(self, index)
			self[index] = value
			return value
		end})

local io_stdout_tostring = tostring(io.stdout)
io_in_memory_stdout_file = setmetatable({
	close = function(...)
		if ... ~= io_in_memory_stdout_file then
			return file_fields.close(...)
		end
		return nil, "cannot close standard file"
	end,
	flush = function(...)
		if ... ~= io_in_memory_stdout_file then
			return file_fields.flush(...)
		end
		return true
	end,
	lines = function(...)
		if ... ~= io_in_memory_stdout_file then
			return file_fields.lines(...)
		end
		local error_message = util.system_type == 'windows' and "No error"
			or "Bad file descriptor"
		return function() error(error_message) end
	end,
	read = function(...)
		if ... ~= io_in_memory_stdout_file then
			return file_fields.read(...)
		end
		-- technically format '*a' deadlocks on unix, but that's not useful behaviour
		return nil, "Bad file descriptor", 9
	end,
	seek = function(...)
		if ... ~= io_in_memory_stdout_file then
			return file_fields.seek(...)
		end
		if util.system_type == 'windows' then
			return nil, "Bad file descriptor", 9
		else -- if util.system_type == 'unix'
			return nil, "Illegal seek", 29
		end
	end,
	setvbuf = file_fields.setvbuf and function(...)
		local self, mode = ...
		if self ~= io_in_memory_stdout_file then
			return file_fields.setvbuf(...)
		end
		if mode ~= 'no' and mode ~= 'full' and mode ~= 'line' then
			error("bad argument #1 to 'setvbuf' (invalid option '"..mode.."')")
		end
		return true
	end,
	write = function(...)
		if ... ~= io_in_memory_stdout_file then
			return file_fields.write(...)
		end
		local arg_list = {--[[args]]select(2, ...)}
		local n = #io_in_memory_stdout_buffer
		for i = 1, #arg_list do
			local e = arg_list[i]
			local e_type = type(e)
			if e_type ~= 'number' and e_type ~= 'string' then
				local mt = getmetatable(e)
				local mt_name = mt and mt.__name
				mt_name = mt_name and tostring(mt_name)
					or e_type
				error("bad argument #"..i.." to 'write' (string expected, got "..mt_name..")")
			end
			io_in_memory_stdout_buffer[n+i] = e
		end
	end,
}, {
	__name = file_metatable.__name,
	__tostring = function(...)
		if ... ~= io_in_memory_stdout_file then
			return file_metatable.__tostring(...)
		end
		return io_stdout_tostring
	end
})


-- implement table_backup
local function table_backup_impl(t, backup, type_f)
	backup[t] = util.table_copy_shallow(t)
	for k,v in pairs(t) do
		if backup[k] == nil and type_f(k) == 'table' then
			table_backup_impl(k, backup, type_f)
		end
		if backup[v] == nil and type_f(v) == 'table' then
			table_backup_impl(v, backup, type_f)
		end
	end
end
table_backup = function(t, backup)
	backup = backup or {}
	table_backup_impl(t, backup, type)
	return backup
end

table_restore_from_backup = function(backup)
	for t,state in pairs(backup) do
		for k in pairs(t) do
			t[k] = nil
		end
		for k,v in pairs(state) do
			t[k] = v
		end
	end
end



return indirection_layer
