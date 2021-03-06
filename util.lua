--[[
This file implements all "platform-specific" logic, which is generally provided via either directly by Lua's `os` and `io` standard library modules,
or by invoking external programs through `io.popen` specifically (comparable to C's `system` function in `stddef.h`, i.e. invokes programs as-if through the system shell).
Used by benmet itself, but also provided to step scripts written in Lua.
The main tested target platform is Linux, and although some efforts were also invested towards Windows support, when testing a real use case once it didn't quite work yet.
]]

-- imports from other libraries
local md5
local json_encode, json_decode

if not _G.benmet_util_skip_library_imports then
	local main_script_dir_path = _G.benmet_get_main_script_dir_path and _G.benmet_get_main_script_dir_path()
	local clone_dir_hint = main_script_dir_path and "into "..main_script_dir_path.."/.."
		or "next to 'benmet' (this file's parent directory)"
	do
		local found, sha2 = pcall(require, "pure_lua_SHA.sha2")
		if not found then
			error("Could not find Lua module `pure_lua_SHA.sha2`. Please run the command 'auto-setup', or manually clone https://github.com/Egor-Skriptunoff/pure_lua_SHA.git "..clone_dir_hint)
		end
		md5 = sha2.md5
	end
	do
		local found, lunajson = pcall(require, "lunajson")
		if not found then
			error("Could not find Lua module `lunajson`. Please run the command 'auto-setup', or manually clone https://github.com/grafi-tt/lunajson.git "..clone_dir_hint)
		end
		--[=[lunajson.encode(value, [nullv]):
			Encode value into a JSON string and return it. If nullv is specified, values equal to nullv will be encoded as null.
			This function encodes a table t as a JSON array if a value t[1] is present or a number t[0] is present. If t[0] is present, its value is considered as the length of the array. Then the array may contain nil and those will be encoded as null. Otherwise, this function scans non nil values starting from index 1, up to the first nil it finds. When the table t is not an array, it is an object and all of its keys must be strings.
		--]=]
		json_encode = lunajson.encode
		--[=[lunajson.decode(jsonstr, [pos, [nullv, [arraylen]]]):
			Decode jsonstr. If pos is specified, it starts decoding from pos until the JSON definition ends, otherwise the entire input is parsed as JSON. null inside jsonstr will be decoded as the optional sentinel value nullv if specified, and discarded otherwise. If arraylen is true, the length of an array ary will be stored in ary[0]. This behavior is useful when empty arrays should not be confused with empty objects.
			This function returns the decoded value if jsonstr contains valid JSON, otherwise an error will be raised. If pos is specified it also returns the position immediately after the end of decoded JSON.
		--]=]
		json_decode = lunajson.decode
	end
end

local util = {
	json_encode = json_encode,
	json_decode = json_decode,
}
util.debug_detail_level = 0

local detail_level = 0
local incdl = function() detail_level = detail_level+1 end
local decdl = function() detail_level = detail_level-1 assert(detail_level >= 0) end
local assertdecdl = function(condition, error_message) if not condition then decdl() error(error_message) end return condition end
util.incdl, util.decdl, util.assertdecdl = incdl, decdl, assertdecdl

-- setup features
local actual_debug_detail_level = util.debug_detail_level
util.debug_detail_level = 0
	-- debugging, logging
		local debug_write = _G.benmet_debug_output_to_file
		if debug_write then
			local debug_output_file = assert(io.open(debug_write, 'w+'), "failed to open file '"..tostring(debug_write).."' to write debug output to")
			util.debug_output_file = debug_output_file
			debug_write = function(x) debug_output_file:write(tostring(x).."\n") end
			debug_write"=={debug output start}=="
		else
			debug_write = print
		end
		
		function util.debugprint(x, indent, level, already_visited)
			if (level or util.debug_detail_level) <= detail_level then return end --skip if we're too deep already
			indent = indent or string.rep(" ", detail_level)
			if type(x) ~= 'table' then
				debug_write(indent..(--[[type(x) == 'string' and string.format("%q", x) or]] tostring(x)))
				return
			end
			already_visited = already_visited or {0}
			if already_visited[x] then
				debug_write(indent .. already_visited[x])
				return
			end
			already_visited[x] = "(table #"..already_visited[1]..")"
			already_visited[1] = already_visited[1]+1
			debug_write(indent .. already_visited[x] .. " = {")
			for k,v in pairs(x) do
				util.debugprint(k, indent .. " ", level, already_visited)
				debug_write(indent .. "=>")
				util.debugprint(v, indent .. " ", level, already_visited)
				debug_write(indent .. ",")
			end
			debug_write(indent .. "}")
		end
		
		function util.logprint(x, indent)
			return util.debugprint(x, indent--[[, util.log_detail_level]])
		end
	
	-- basic functions
		function util.string_ends_with(s, suffix)
			return (string.sub(s, -#suffix) == suffix) and string.sub(s, 1, -(#suffix+1))
		end
		
		function util.string_starts_with(s, prefix)
			return (string.sub(s, 1, #prefix) == prefix) and string.sub(s, #prefix+1)
		end
		
		-- returns list of substrings that do not contain delimiter_char
		function util.string_split(s, delimiter_char)
			local segments = {}
			for segment in string.gmatch(s, "[^%"..delimiter_char.."]*") do
				segments[#segments+1] = segment
			end
			return segments
		end
		-- (UNUSED) returns list of non-empty substrings that do not contain delimiter_char
		function util.string_tokenize(s, delimiter_char)
			local tokens = {}
			for token in string.gmatch(s, "[^%"..delimiter_char.."]+") do
				tokens[#tokens+1] = token
			end
			return tokens
		end
		
		util.cut_trailing_space = function(s)
			return string.match(s, ".*%S") or ""
		end
		
		function util.in_quotes(s)
			if util.string_starts_with(s, '"') and util.string_ends_with(s, '"') then
				error("string already has quotes: "..tostring(s)) -- I _think this helps code correctness - runtime crashes are better than bugs - but feel free to comment it out if your judgement differs.
				return s
			end
			s = string.format("%q", s) -- FIXME: probably wrong, a manual string.gsub with replacement table might be better?
			s = string.gsub(s, "\\\\", "\\") -- undo doubling by string.format "%q"
			return s
		end
		function util.in_quotes_with_backslashes(s)
			return string.gsub(util.in_quotes(s), "/", "\\")
		end
		function util.remove_quotes(s)
			if #s > 1 then
				local first_char = string.sub(s, 1, 1)
				local last_char = string.sub(s, -1)
				if first_char == last_char and (first_char == "\"" or first_char == "'") then
					return string.sub(s, 2, -2), true
				end
			end
			return s
		end
		
		function util.line_contents_from_string(s)
			local lines = {}
			for line in string.gmatch(s, "[^\n]*") do
				lines[#lines+1] = line
			end
			if lines[#lines] == "" then
				lines[#lines] = nil
			end
			return lines
		end
		
		local table_copy_shallow = function(t)
			local result
			if t then
				result = {}
				for k,v in pairs(t) do
					result[k] = v
				end
			end
			return result
		end
		util.table_copy_shallow = table_copy_shallow
		local function table_copy_deep_impl(t, copy, copy_lookup, type_f)
			for k,v in pairs(t) do
				local copy_v = copy_lookup[v]
				if copy_v == nil then
					if type_f(v) ~= 'table' then
						copy_v = v
						copy_lookup[v] = copy_v
					else
						copy_v = {}
						copy_lookup[v] = copy_v
						table_copy_deep_impl(v, copy_v, copy_lookup, type_f)
					end
				end
				copy[k] = copy_v
			end
			return copy
		end
		local table_copy_deep_into = function(t, result)
			if not t then return result end
			return table_copy_deep_impl(t, result, {[t] = result}, type)
		end
		local table_copy_deep = function(t)
			if not t then return nil end
			return table_copy_deep_into(t, {})
		end
		util.table_copy_deep = table_copy_deep
		local function table_patch_in_place(instance_to_patch, patch, --[[patches]] ...)
			if not patch then return instance_to_patch end
			for k,v in pairs(patch) do
				instance_to_patch[k] = v
			end
			return table_patch_in_place(instance_to_patch, --[[patches]] ...)
		end
		util.table_patch_in_place = table_patch_in_place
		function util.table_patch(original, --[[patches]] ...)
			return table_patch_in_place(table_copy_deep(original), ...)
		end
		
		function util.tables_shallow_equal(a, b)
			for k,v in pairs(a) do
				if b[k] ~= v then
					util.debugprint("not equal in '"..tostring(k).."': "..tostring(b[k])..", "..tostring(v))
					return false
				end
			end
			for k,v in pairs(b) do
				if a[k] ~= v then
					util.debugprint("not equal in '"..tostring(k).."': "..tostring(a[k])..", "..tostring(v))
					return false
				end
			end
			return true
		end
		
		local list_copy_shallow = function(list)
			local result = {}
			for i = 1, #list do
				result[i] = list[i]
			end
			return result
		end
		util.list_copy_shallow = list_copy_shallow
		
		local list_append_in_place = function(to, from)
			local n = #to
			for i = 1, #from do
				n = n+1
				to[n] = from[i]
			end
			return to
		end
		util.list_append_in_place = list_append_in_place
		
		function util.list_append_to_new(first, second)
			return list_append_in_place(list_copy_shallow(first), second)
		end
		
		function util.list_split_in_place_at_return_tail(list, at)
			local tail = {}
			local tail_i = 1
			for i = at, #list do
				tail[tail_i] = list[i]
				list[i] = nil
				tail_i = tail_i+1
			end
			return tail
		end
		
		function util.list_contains(list, element)
			for i = 1, #list do
				if list[i] == element then
					return true
				end
			end
		end
		function util.table_keys_list(t)
			local keys = {}
			for k in pairs(t) do
				keys[#keys+1] = k
			end
			return keys
		end
		
		function util.list_to_index_lookup_table(list)
			local index_lookup = {}
			for i = 1, #list do
				index_lookup[list[i]] = i
			end
			return index_lookup
		end
		util.list_to_lookup_table = util.list_to_index_lookup_table
		
		function util.tables_intersect(values_from, keys_from)
			local result = {}
			for k,_ in pairs(keys_from) do
				result[k] = values_from[k]
			end
			return result
		end
		function util.tables_intersect_assert(values_from, keys_from)
			local result = {}
			for k,_ in pairs(keys_from) do
				result[k] = values_from[k]
				assert(result[k] ~= nil)
			end
			return result
		end
		
		function util.list_remove_same_ordered_from_in_place(to_remove, from)
			local to_remove_n = #to_remove
			if to_remove_n == 0 then return end
			local next_to_remove_i = 1
			local next_to_remove = to_remove[next_to_remove_i]
			
			local to_index = 1
			for element_i = 1, #from do
				local element = from[element_i]
				if next_to_remove ~= element then
					from[to_index] = element
					to_index = to_index+1
				else
					next_to_remove_i = next_to_remove_i+1
					if next_to_remove_i > to_remove_n then break end
					next_to_remove = to_remove[next_to_remove_i]
				end
			end
			for i = to_index, #from do
				from[i] = nil
			end
			assert(next_to_remove_i > to_remove_n, "error: inconsistent order of elements to remove and list to remove them from")
		end
		
		local array_element_iterator__next = function(state)
				local next_index = state[1] + 1
				state[1] = next_index
				return state[2][next_index]
			end
		function util.array_element_iterator(array)
			return array_element_iterator__next, {0, array} --[[, first_index=nil]]
		end
		
		local weakly_keyed_table_mt = {__mode = 'k'}
		local new_weakly_keyed_table = function(t)
			t = t or {}
			return setmetatable(t, weakly_keyed_table_mt)
		end
		util.new_weakly_keyed_table = new_weakly_keyed_table
		
		-- This function constructs and assigns to t[index]
		-- a proxy function that selects the actual implementation from a list
		-- and then assigns and calls the selected implementation.
		-- Used so we can f.e. implement removing files based on whether 'rm' exists,
		-- but only look up whether 'rm' exists if that functionality is actually required.
		local install_delayed_impl_selector = function(t, index, condition_implementation_pair_list)
			local selected_impl
			local impl_selector_proxy = function(--[[impl_args]]...)
					if not selected_impl then -- otherwise the selection was already evaluated, maybe this function was copied out to somewhere else in the meantime
						for i = 1, #condition_implementation_pair_list, 2 do
							local condition_f = condition_implementation_pair_list[i]
							if condition_f == true or condition_f() then -- if the condition is true, choose the corresponding implementation
								selected_impl = condition_implementation_pair_list[i+1]
								break
							end
							assert(i + 1 < #condition_implementation_pair_list, "exhausted all implementations, no condition satisfied")
						end
						t[index] = selected_impl -- replace ourselves with the actual implementation
					end
					return selected_impl(--[[impl_args]]...) -- work as a proxy
				end
			t[index] = impl_selector_proxy
		end
		
		local env_override_table = {}
		local env_override_string = ""
		function util.getenv(varname)
			return env_override_table[varname]
				or os.getenv(varname)
		end
		local env_override_string_from_table = function(env_override_table)
			local s = ""
			local suffix = util.system_type == 'unix' and "\n"
				or " && "
			for k,v in pairs(env_override_table) do
				s = s..util.export_command.." "..util.in_quotes(k.."="..v)..suffix
			end
			return s
		end
		util.env_override_string_from_table = env_override_string_from_table
		function util.setenv(varname, value)
			assert(string.find(varname, "[\"`'=%-%s]") == nil, "invalid environment variable name")
			env_override_table[varname] = value
			env_override_string = env_override_string_from_table(env_override_table)
		end
		function util.prependenv(varname, value_prefix)
			local prev_value = util.getenv(varname)
			return util.setenv(varname, value_prefix..(prev_value ~= nil and prev_value or ""))
		end
		function util.appendenv(varname, value_suffix)
			local prev_value = util.getenv(varname)
			return util.setenv(varname, (prev_value ~= nil and prev_value or "")..value_suffix)
		end
		
		local execute_command_with_env_override_string = function(cmd, env_override_string, ...)
			assert(select('#', ...) == 0, "superfluous argument passed to execute_command, did you mean execute_command_at?")
			util.logprint("executing: "..cmd.."\nenv-override: "..env_override_string)
			incdl()
				local read_pipe = assertdecdl(io.popen(env_override_string..cmd))
				local program_output = read_pipe:read('*a')
				util.debugprint("the program wrote: "..program_output)
				local program_success, exit_type, return_status = read_pipe:close()
				util.debugprint("it "..(program_success and "succeeded" or "failed").." by '"..exit_type.."' with status "..return_status)
			decdl()
			return program_success, exit_type, return_status, program_output
		end
		function util.execute_command_with_env_override(cmd, env_override_table, ...)
			return execute_command_with_env_override_string(cmd, env_override_string_from_table(env_override_table), ...)
		end
		function util.execute_command(cmd, ...)
			return execute_command_with_env_override_string(cmd, env_override_string, ...)
		end
		
		function util.execute_command_with_env_override_at(cmd, env_override_table, path)
			return util.execute_command_with_env_override("cd "..util.in_quotes(path).." && "..cmd, env_override_table)
		end
		function util.execute_command_at(cmd, path)
			return util.execute_command("cd "..util.in_quotes(path).." && "..cmd)
		end
		
		local find_program_cache = {}
		do -- find our find program; we cannot delay this because we determine util.system_type (-> util.export_command) based on this (though there's probably better ways)
			-- try 'which'
			local found, exit_type, return_code, program_output = util.execute_command("which which")
			if found then
				find_program_cache['which'] = util.cut_trailing_space(program_output) -- fill the cache as a call to util.find_program would have
				util.find_program_program = 'which'
			else
				-- try 'where'
				found, exit_type, return_code, program_output = util.execute_command("where /Q where")
				if found then
					find_program_cache['where'] = util.cut_trailing_space(program_output) -- fill the cache as a call to util.find_program would have
					util.find_program_program = 'where'
				end
			end
		end
		function util.find_program(program_name)
			assert(program_name)
			assert(util.find_program_program)
			util.logprint("looking up program '"..program_name.."'")
			incdl()
				local found, exit_type, return_code, program_output = util.execute_command(util.find_program_program.." "..util.in_quotes(program_name))
			decdl()
			local result = found and (util.cut_trailing_space(program_output)
					or found)
				or false
			find_program_cache[program_name] = result
			return result
		end
		function util.find_program_cached(program_name)
			local result = find_program_cache[program_name]
			if result ~= nil then
				util.logprint("looked up program '"..program_name.."' (from cache): "..tostring(result))
			else
				result = util.find_program(program_name)
			end
			return result
		end
		util.system_type = util.find_program_program == 'which' and 'unix'
			or 'windows'
		util.export_command = util.system_type == 'unix' and 'export'
			or 'SET'
		
		function util.append_line(file_path, line)
			line = util.string_ends_with(line, "\n") and line
				or line.."\n"
			local file = assert(io.open(file_path, 'a+'))
			assert(file:write(line))
			assert(file:close())
		end
		
		function util.new_compat_serialize(t)
			if t == nil then return "" end
			assert(type(t) == 'table')
			local lines = {}
			for k, v in pairs(t) do
				k = tostring(k)
				v = tostring(v)
				-- TODO: warn about unescaped newlines
				lines[#lines+1] = k.."="..v
			end
			table.sort(lines)
			return table.concat(lines, "\n")
		end
		
		-- helper function that checks the type of the given value,
		-- asserting that it is a non-identity primitive,
		-- then returns its string representation (via tostring)
		local strict_tostring = function(x, --[[error_prefixes]]...)
				local x_type = type(x)
				if x_type ~= 'string' and x_type ~= 'number' and x_type ~= 'boolean' then
					local error_message_segments = {--[[error_prefixes]]...}
					error_message_segments[#error_message_segments+1] = "type '"
					error_message_segments[#error_message_segments+1] = x_type
					error_message_segments[#error_message_segments+1] = "'"
					error(table.concat(error_message_segments))
				end
				return tostring(x)
			end
			
		local check_json_param_key_validity = function(key)
				local key_type = type(key)
				if key_type ~= 'string' then
					error("non-string param name from parsed JSON: type '"..key_type.."'")
				end
				assert(key ~= "", "invalid param name \"\" (empty string) encountered in parsed JSON")
			end
		util.check_json_param_key_validity = check_json_param_key_validity
		-- helper function asserting that all keys are strings and
		-- all entries are non-identity primitives (strings, numbers or booleans);
		-- returns a table with values converted to strings
		local ensure_strings_in_json_param_entry = function(entry)
				local t = {}
				for k,v in pairs(entry) do -- translate keys and values to strings, as we would expect from our line-based format
					check_json_param_key_validity(k)
					t[k] = strict_tostring(v, "encountered unexpected type as value of parameter '", k, "' from parsed JSON: ")
				end
				return t
			end
		-- deserialize one coordinate of parameters from either a JSON object (starting with "{") or our line-based format
		function util.new_compat_deserialize(s, failure_message)
			local failure_prefix = failure_message and failure_message.."\n" or ""
			if string.match(s, "^%s*{") then -- looks like a JSON object
				failure_prefix = failure_prefix ~= "" and failure_prefix.."(trying to parse params as JSON object)\n"
					or "error trying to parse params as JSON object: "
				-- decode, then ensure it's all strings as it would be coming from our line-based format
				local successful, parsed = pcall(json_decode, s)
				if not successful then
					error(failure_prefix..tostring(parsed))
				end
				return ensure_strings_in_json_param_entry(parsed)
			elseif string.match(s, "^%s*%[") then -- looks like a JSON array, which is an error (we only expected a single coordinate of parameters)
				failure_prefix = failure_prefix ~= "" and failure_prefix
					or "error trying to parse params: "
				error(failure_prefix.."expected single JSON object, found JSON array")
			else -- parse as our line-based format
				local t = {}
				for k, v in string.gmatch(s, "([^%s=]*)=([^\n]*)") do
					if k ~= "" then
						if t[k] ~= nil then
							error(failure_prefix.."encountered duplicate key assignment: ["..k.."] = "..t[k]..", then = "..v)
						end
						t[k] = v
					end
				end
				return t
			end
		end
		
		-- deserialize multiple parameters from either
		-- a JSON array (starting with "[") containing objects holding parameter coordinates,
		-- or our line-based format, where entries are separated by lines starting with "="
		function util.new_compat_deserialize_multientry(s)
			if string.match(s, "^%s*%[") then -- looks like a JSON array
				-- decode the array
				local successful, parsed = pcall(json_decode, s)
				if not successful then
					error("error trying to parse multi-entry params as JSON array: "..tostring(parsed))
				end
				-- ensure every entry is all strings, as it would be coming from our line-based format
				local entries = {}
				for i = 1, #parsed do
					entry[i] = ensure_strings_in_json_param_entry(parsed[i])
				end
				return entries
			elseif string.match(s, "^%s*{") then -- looks like a JSON object
				failure_prefix = failure_prefix ~= "" and failure_prefix
					or "error trying to parse multi-entry params: "
				error(failure_prefix.."expected JSON array, found single JSON object")
			else -- parse our line-based format
				local entries = {}
				local t
				-- inline string tokenization
				local s_length_1 = #s + 1
				local prev_end_pos = 0
				repeat
					local next_start_pos, next_end_pos = string.find(s, "\n", prev_end_pos+1, true)
					local line = (next_start_pos or s_length_1) > prev_end_pos+1 and string.sub(s, prev_end_pos+1, next_start_pos and next_start_pos-1)
					prev_end_pos = next_end_pos
					if line then
						local k, v = string.match(line, "([^%s=]*)=(.*)")
						if k == "" then -- entry separator
							t = nil
						else -- property line within entry
							if not t then
								t = {}
								entries[#entries+1] = t
							end
							if t[k] ~= nil then
								error("encountered duplicate key assignment: ["..k.."] = "..t[k]..", then = "..v)
							end
							t[k] = v
						end
					end
				until not next_start_pos
				return entries
			end
		end
		
		-- deserialize multi-valued parameters from either
		-- a JSON object (starting with "{") containing either single values or arrays of values,
		-- or our line-based format allowed to contain multiple assignments to the same property
		function util.new_compat_deserialize_multivalue(s)
			local key_index_lookup = {}
			local entries = {}
			if string.match(s, "^%s*{") then -- looks like a JSON object
				local successful, parsed = pcall(json_decode, s)
				if not successful then
					error("error trying to parse multivalue params from JSON object: "..tostring(parsed))
				end
				for k, parsed_entry in pairs(parsed) do
					check_json_param_key_validity(k)
					local key_index = #entries+1
					key_index_lookup[k] = key_index
					local entry_type = type(parsed_entry)
					if entry_type == 'table' then -- table elements must be arrays holding permissible individual values
						local entry_values = {}
						entries[key_index] = {k, entry_values}
						 -- iterate over all numbered entries (assuming it is an array) and move them over to entry_values
						for i = 1, #parsed_entry do
							entry_values[i] = strict_tostring(parsed_entry[i], "encountered unexpected type as element in array value of parameter '", k, "' from parsed JSON: ")
							parsed_entry[i] = nil
						end
						-- if there are any entries left, the array contained null entries, or it was an object (with string keys)
						for k in pairs(parsed_entry) do
							if type(k) == 'number' then
								error("error trying to parse multivalue params from JSON object: did not reach index "..k.." of array value; note that 'null' in array values is not permitted")
							else
								error("error trying to parse multivalue params from JSON object: found non-number index '"..tostring(k).."', values may only be arrays, not objects")
							end
						end
						-- we additionally require that the array cannot be empty
						assert(#entry_values > 0, "error trying to parse multivalue params from JSON object: value array cannot be empty")
					else -- non-table elements are individual values, which we wrap in a table for consistency
						entries[key_index] = {k, {strict_tostring(parsed_entry, "encountered unexpected type as value of parameter '",k,"' from parsed JSON: ")}}
					end
				end
				return entries, key_index_lookup
			elseif string.match(s, "^%s*%[") then -- looks like a JSON array, which is an error (we only expected a single coordinate of parameters)
				failure_prefix = failure_prefix ~= "" and failure_prefix
					or "error trying to parse params: "
				error(failure_prefix.."expected single JSON object, found JSON array")
			else -- parse our line-based format
				for k, v in string.gmatch(s, "([^%s=]*)=([^\n]*)") do
					if k ~= "" then
						local key_index = key_index_lookup[k]
						if not key_index then
							key_index = #entries+1
							key_index_lookup[k] = key_index
						end
						local entry = entries[key_index]
						if not entry then
							entry = {k, {v}}
							entries[key_index] = entry
						else
							local values = entry[2]
							values[#values+1] = v
						end
					end
				end
				return entries, key_index_lookup
			end
		end
		local order_multivalue_entries_by_value_count_asc = function(a, b)
				return #a[2] < #b[2]
			end
		function util.sort_multivalue(multivalue_entries)
			table.sort(multivalue_entries, order_multivalue_entries_by_value_count_asc)
			return multivalue_entries
		end
		
		-- checks that all sublists are non-empty arrays and
		-- converts values to strings
		function util.coerce_json_multivalue_array_in_place(multivalue_array)
			for i = 1, #multivalue_array do
				local next_element = multivalue_array[i]
				for k,v in pairs(next_element) do
					check_json_param_key_validity(k)
					if type(v) == 'table' then
						if #v == 0 then
							error("sublists must be non-empty arrays without null entries")
						end
						for vi = 1, #v do
							v[vi] = strict_tostring(v[vi], "unsupported value type at input_array[", i, "].", k, "[", vi, "]: ")
						end
					else
						next_element[k] = strict_tostring(v, "encountered unexpected value type at input_array[", i, "].", k, ": ")
					end
				end
			end
		end
		
		-- constructs all combinations, going in reverse order
		local combinatorial_iterator_impl = function(state, combination)
				local multivalue_entries = state[1]
				local index_stack = state[2]
				local keys_length = state[3]
				if combination ~= nil then -- on all but the first call
					for i = keys_length, 1, -1 do -- check all keys, starting at the last
						if index_stack[i] > 1 then -- if there are more options left for key i, select the next one (decrementing)
							local index_i = index_stack[i] - 1
							index_stack[i] = index_i
							local entry = multivalue_entries[i]
							combination[entry[1]] = entry[2][index_i]
							for j = i+1, keys_length do -- reset all later keys back to the initial choice (the last option of each multivalue)
								entry = multivalue_entries[j]
								local values = entry[2]
								local values_count = #values
								combination[entry[1]] = values[values_count]
								index_stack[j] = values_count
							end
							return combination
						end
					end
					return
				else -- on the first call, set up combination as the last option of each multivalue
					index_stack = {}
					state[2] = index_stack
					local combination = {}
					for i = 1, keys_length do
						local entry = multivalue_entries[i]
						local values = entry[2]
						local values_count = #values
						combination[entry[1]] = values[values_count]
						index_stack[i] = values_count
					end
					return combination
				end
			end
		function util.all_combinations_of_multivalues(multivalue_entries) -- note: faster iteration over sorted multivalue
			return combinatorial_iterator_impl, {multivalue_entries, nil, #multivalue_entries}, nil
		end
		
		function util.combinatorial_iterator_one_from_each_sublist(table_of_sublists)
			-- convert to our multivalue_entries format
			local multivalue_entries = {}
			for k,v in pairs(table_of_sublists) do
				if type(v) ~= 'table' then -- auto-wrap non-list values
					v = {v}
				end
				multivalue_entries[#multivalue_entries+1] = {k, v}
			end
			-- sort the entries for asymptotically faster iteration
			util.sort_multivalue(multivalue_entries)
			-- return the iterator
			return util.all_combinations_of_multivalues(multivalue_entries)
		end
		
		local all_combinations_of_multivalues_in_list_impl_passthrough_or_recur -- forward declaration to allow mutual recursion
		local all_combinations_of_multivalues_in_list_impl = function(state, prev_nested_iterator_index)
				local current_nested_iterator, current_nested_iterator_state = state[3], state[4]
				if current_nested_iterator == nil then -- handle the next element in the input array
					-- get the next array entry
					local next_index = state[2]+1
					state[2] = next_index
					local input_array = state[1]
					if next_index > #input_array then -- we reached the end
						return nil
					end
					local next_input = input_array[next_index]
					-- determine what iterator to use for this element
					-- check if one of the elements is a list
					local has_list_element
					for k,v in pairs(next_input) do
						if type(v) == 'table' then
							has_list_element = true
						end
					end
					-- if there was no list element, the next element is just this element verbatim
					if not has_list_element then
						return next_input
					end
					-- otherwise, we set up the combinatorial iterator over this element as nested iterator
					current_nested_iterator, current_nested_iterator_state, prev_nested_iterator_index = util.combinatorial_iterator_one_from_each_sublist(next_input)
					state[3], state[4] = current_nested_iterator, current_nested_iterator_state
					-- fallthrough
				end
				
				return all_combinations_of_multivalues_in_list_impl_passthrough_or_recur(state, current_nested_iterator(current_nested_iterator_state, prev_nested_iterator_index))
			end
		-- helper function, either passes through the new index and varargs,
		-- or clears the nested iterator from the state and calls back to all_combinations_of_multivalues_in_list_impl
		all_combinations_of_multivalues_in_list_impl_passthrough_or_recur = function(state, new_nested_iterator_index, ...)
				if new_nested_iterator_index == nil then
					state[3], state[4] = nil, nil
					return all_combinations_of_multivalues_in_list_impl(state)
				else
					return new_nested_iterator_index, ...
				end
			end
		-- iterates over every entry in multivalue_entries_array,
		-- returns elements without list values directly,
		-- returns all combinations of elements with list values (via util.combinatorial_iterator_one_from_each_sublist)
		function util.all_combinations_of_multivalues_in_list(multivalue_entries_array)
				local state = {multivalue_entries_array, 0}
				return all_combinations_of_multivalues_in_list_impl, state
			end
		
		function util.hash_params(params)
			return md5(util.new_compat_serialize(params))
		end
	
	-- path operations
		-- note: this is a conservative approach that reports both
		-- paths that would be UNIX-absolute and paths that would be Windows-absolute,
		-- regardless of what system you're on, which may help with stuff like Wine and MSYS-shells
		function util.path_is_absolute(path)
			return util.string_starts_with(path, "/") -- absolute UNIX path
				or string.match(path, "^%w:[/\\]") -- absolute Windows path
		end
		
		function util.get_last_path_segment(path)
			return string.match(path, "([^/%\\]+)[/%\\]*$")
		end
		
	-- Lua stuff (for launching subprocesses):
		-- splits a path template string (used in package.path and package.searchpath) into its elements
		-- and returns a list of indices of elements that are relative paths;
		-- caches its results
		local split_path_template_string__cache = new_weakly_keyed_table()
		local relative_path_template_element_indices__cache = new_weakly_keyed_table()
		local split_path_template_string_and_collect_relative_path_element_indices = function(path_template_string)
				local split_path_template_string = split_path_template_string__cache[path_template_string]
				if not split_path_template_string then
					split_path_template_string = util.string_split(path_template_string, ";")
					split_path_template_string__cache[path_template_string] = split_path_template_string
				end
				
				local relative_path_template_element_indices = relative_path_template_element_indices__cache[path_template_string]
				if not relative_path_template_element_indices then
					relative_path_template_element_indices = {}
					for i = 1, #split_path_template_string do
						local e = split_path_template_string[i]
						if #e > 0 and not util.path_is_absolute(e) then
							relative_path_template_element_indices[#relative_path_template_element_indices+1] = i
						end
					end
					relative_path_template_element_indices__cache[path_template_string] = relative_path_template_element_indices
				end
				
				return split_path_template_string, relative_path_template_element_indices
			end
		-- return the given path template string, with all relative paths prefixed by the given prefix
		function util.prefix_relative_path_templates_in_string(path_template_string, relative_path_prefix)
				local elements, relative_element_indices = split_path_template_string_and_collect_relative_path_element_indices(path_template_string)
				elements = util.list_copy_shallow(elements)
				for i = 1, #relative_element_indices do
					local element_index = relative_element_indices[i]
					elements[element_index] = relative_path_prefix..elements[element_index]
				end
				return table.concat(elements, ";")
			end
		-- return only the relative paths from the given path template string, prefixed by the given prefix
		function util.prefixed_only_relative_path_templates_in_string(path_template_string, relative_path_prefix)
				local elements, relative_element_indices = split_path_template_string_and_collect_relative_path_element_indices(path_template_string)
				local relative_elements = {}
				for i = 1, #relative_element_indices do
					local element_index = relative_element_indices[i]
					relative_elements[#relative_elements+1] = relative_path_prefix..elements[element_index]
				end
				return table.concat(relative_elements, ";")
			end
		
		local cached_lua_program
		install_delayed_impl_selector(util, 'get_lua_program', {
			function() return _G.benmet_get_lua_program_command end, function() return _G.benmet_get_lua_program_command() end,
			function()
					cached_lua_program = util.find_program_cached("lua53")
						or util.find_program_cached("lua5.3")
						or util.find_program_cached("lua")
					return cached_lua_program
				end, function() return cached_lua_program end,
		})
		
		-- scripts loaded from files via loadfile, additionally wrapped in select(2, assert(xpcall(_, debug_traceback, ...))),
		-- associated by keys from indirection_layer.path_to_cache_key of the script file path
		local loadfile_cache = {}
		-- execute the lua script located at path as if it were launched as a subprocess
		-- with args_list as unquoted arguments, at at_relative_path relative to the script's path,
		-- with environment variables overrides provided in new_os_env_override_table;
		-- returns the same values as the util.execute_command-family of functions:
		-- success (boolean), exit type (always 'exit'), return status (0 if successful, 1 otherwise), program output (string),
		-- and as an additional fifth value (not available from util.execute_command) an error trace (or loading error message) in case of failure
		function util.execute_lua_script_as_if_program(path, args_list, at_relative_path, new_os_env_override_table)
			assert(path, "no lua script path given to util.execute_lua_script_as_if_program")
			assert(not (at_relative_path and _G.benmet_disable_indirection_layer))
			at_relative_path = at_relative_path and (
					(string.sub(at_relative_path, -1) == "/" or string.sub(at_relative_path, -1) == "\\") and at_relative_path
					or at_relative_path.."/")
			util.logprint("executing Lua script \""..path.."\" as program "..(at_relative_path and "at relative path \""..at_relative_path.."\" " or "").."with args: '"..table.concat(args_list, "' '").."'")
			incdl()
				
				-- look for the loaded script in cache
				local indirection_layer = require "benmet.indirection_layer"
				local cache_key = indirection_layer.path_to_cache_key(path)
				local loaded_script = loadfile_cache[cache_key]

				if not loaded_script then
					-- load the script in the global environmnent
					local loading_error
					loaded_script, loading_error = loadfile(path)
					if not loaded_script then
						util.debugprint("failed to load the script: "..loading_error)
						decdl()
						return false, 'exit', 1, "", loading_error
					end
					
					local unprotected = loaded_script
					local select, assert, xpcall, debug_traceback = select, assert, xpcall, debug.traceback
					loaded_script = function(...) return select(2, assert(xpcall(unprotected, debug_traceback, ...))) end
					
					loadfile_cache[cache_key] = loaded_script
				end
				
				-- simulate changing to the requested working directory, back up the global environment and replace the arg table
				indirection_stack_key = indirection_layer.increase_stack(at_relative_path, args_list, new_os_env_override_table)
				
				-- temporarily clear our env override table in util
				local prev_env_override_table = env_override_table
				env_override_table = {}
				env_override_string = ""
				
				-- copy find_program cache
				local prev_find_program_cache = table_copy_shallow(find_program_cache)
				
				-- replace os.exit with coroutine.yield, the script is run as a coroutine so we can stop execution upon this being called
				_G.benmet_ensure_package_path_entries_are_absolute()
				os.exit = coroutine.yield
				
				-- disable debug details for nested execution
				local prev_ddl = util.debug_detail_level
				local prev_dl = detail_level
				util.debug_detail_level = 0
				detail_level = 0
				
				-- run the script as a coroutine, so we can stop its execution upon call to its os.exit (-> coroutine.yield)
				local script_coroutine = coroutine.create(loaded_script)
				local successful, return_code_or_run_error = coroutine.resume(script_coroutine, (table.unpack or unpack)(args_list))
				
				-- re-enable debug details
				util.debug_detail_level = prev_ddl
				detail_level = prev_dl
				
				-- restore find_program cache, in case the script did something with PATH
				find_program_cache = prev_find_program_cache
				
				-- restore our previous env override table in util
				env_override_table = prev_env_override_table
				env_override_string = env_override_string_from_table(prev_env_override_table)
				
				-- revert working directory, io and global state
				-- read script output
				local script_output = indirection_layer.decrease_stack(indirection_stack_key)
				util.debugprint("the script wrote: "..script_output)
				
				if not successful then
					util.debugprint("the script errored: "..return_code_or_run_error)
					-- authentic behaviour would be to also call
					-- io.stderr:write(return_code_or_run_error)
					-- but additionally installing debug.traceback as error handler beforehand (in a wrapper function, or however else you do that on a coroutine)
					decdl()
					return false, 'exit', 1, script_output, return_code_or_run_error
				end
				
				if coroutine.status(script_coroutine) ~= 'suspended' then -- the script's body finished, report success (we explicitly ignore any value it returned)
					util.debugprint("the script finished execution")
					util.debugprint("it succeeded by 'exit' with status 0")
					decdl()
					return script_success, 'exit', return_status, script_output
				end
				
				-- it called its os.exit (-> coroutine.yield), report the return code
				util.debugprint("the script called os.exit")
				local script_success, return_status
				if type(return_code_or_run_error) == 'boolean' then
					script_success = return_code_or_run_error
					return_status = script_success and 0 or 1
				elseif type(return_code_or_run_error) == 'number' then
					return_status = return_code_or_run_error
					script_success = return_status == 0
				else
					script_success = true
					return_status = 0
				end
				
				util.debugprint("it "..(script_success and "succeeded" or "failed").." by 'exit' with status "..return_status)
			decdl()
			return script_success, 'exit', return_status, script_output
		end
		
	-- file system
		install_delayed_impl_selector(util, 'get_current_directory', {
			function() return util.find_program_cached("pwd") end, function()
				incdl()
					local program_success, exit_type, return_status, program_output = assert(util.execute_command("pwd"))
				decdl()
				return util.cut_trailing_space(program_output)
			end,
			--[[CD is not a program]] true, function()
				incdl()
					local program_success, exit_type, return_status, program_output = assert(util.execute_command("CD"))
				decdl()
				return util.cut_trailing_space(program_output)
			end,
		})
		
		-- new implementation, presumably much faster? TODO: re-check this works equivalently everywhere (and if it blocks or errors on files open for writing)
		util.file_exists = function(path)
				util.logprint("checking file: "..path)
				local exists
				incdl()
					local file = io.open(path, 'rb')
					if file then
						assert(file:close())
					end
				decdl()
				return file and true or false
			end
		util.discard_output_file = util.file_exists("/dev/null") and "/dev/null" -- Linux
			or "NUL" -- Windows
		util.discard_stderr_suffix = " 2>"..util.discard_output_file
		
		function util.ensure_file(path)
			util.logprint("ensuring file: '"..path.."'")
			incdl()
				local f = assert(io.open(path, "a+"))
				assert(f:close())
			decdl()
		end
		
		function util.remove_file(path)
			util.logprint("deleting file: '"..path.."'")
			incdl()
				assertdecdl(os.remove(path))
			decdl()
		end
		
		function util.remove_file_if_exists_return_existed(path)
			util.logprint("deleting file if it exists: "..path)
			incdl()
				local existed = os.remove(path)
			decdl()
			util.logprint(existed and "file deleted" or "could not delete file (-> reporting it didn't exist)")
			return existed
		end
		
		util.remove_file_if_exists = util.remove_file_if_exists_return_existed
		
		function util.directory_exists(path)
			path = util.in_quotes(path)
			return util.execute_command("cd "..path..util.discard_stderr_suffix)
		end
		
		function util.create_new_directory(path)
			path = util.in_quotes(path)
			util.logprint("creating new directory: "..path)
			incdl()
				assertdecdl(util.execute_command("mkdir "..path..util.discard_stderr_suffix))
			decdl()
		end
		
		function util.ensure_directory_return_created(path)
			util.logprint("ensuring directory: '"..path.."'")
			local created
			incdl()
				if util.directory_exists(path) then
					util.debugprint("directory already present: "..path)
					created = false
				else
					util.create_new_directory(path)
					created = true
				end
			decdl()
			return created
		end
		
		util.ensure_directory = util.ensure_directory_return_created
		
		install_delayed_impl_selector(util, 'ensure_directories', {
			function() return util.find_program_cached('mkdir') end, function(path) -- if mkdir is a program, use the '-p' flag
				path = util.in_quotes(path)
				util.logprint("ensuring directories: "..path)
				incdl()
					assert(util.execute_command("mkdir -p "..path..util.discard_stderr_suffix))
				decdl()
			end,
			--[[MKDIR might not be a program]] true, function(path) -- if MKDIR is the cmd command, this automatically creates all the parent directories as well.
				path = util.in_quotes(path)
				util.logprint("ensuring directories: "..path)
				incdl()
					assert(util.execute_command("MKDIR "..path..util.discard_stderr_suffix))
				decdl()
			end,
		})
		
		install_delayed_impl_selector(util, 'remove_directory', {
			function() return util.find_program_cached("rm") end, function(path)
				util.logprint("deleting directory: "..path)
				incdl()
					assert(util.execute_command("rm -f -R "..util.in_quotes(path)), "failed to delete directory: "..path)
				decdl()
			end,
			--[[RMDIR is not a program]] true, function(path)
				util.logprint("deleting directory: "..path)
				incdl()
					assert(util.execute_command("RMDIR /S /Q "..util.in_quotes(path)), "failed to delete directory: "..path)
				decdl()
			end,
		})
		
		util.remove_directory_if_exists = function(path)
			if util.directory_exists(path) then
				util.remove_directory(path)
			end
		end
		
		local files_in_directory_as_string_list_except = function(directory_path, except_list)
				assert(type(except_list) == 'table', "expected 'except_list' as table, was type '"..type(except_list).."'")
				local files_to_list = ""
				local files_in_directory = util.files_in_directory(directory_path)
				local list_mask = {}
				for i = 1, #files_in_directory do
					list_mask[files_in_directory[i]] = true
				end
				for i = 1, #except_list do
					list_mask[except_list[i]] = nil
				end
				local in_quotes = util.system_type == 'unix' and util.in_quotes
					or util.system_type == 'windows' and util.in_quotes_with_backslashes
				for k,v in pairs(list_mask) do
					files_to_list = files_to_list.." "..in_quotes(k)
				end
				return files_to_list
			end
		install_delayed_impl_selector(util, 'remove_all_in_directory_except', {
			function() return util.find_program_cached("rm") end, function(directory_path, files_to_keep)
				util.logprint("clearing directory '"..directory_path.."' except for '"..table.concat(files_to_keep, "', '").."'")
				incdl()
					assert(util.execute_command_at("rm -Rf "..files_in_directory_as_string_list_except(directory_path, files_to_keep), directory_path))
				decdl()
			end,
			--[[DEL is not a program]] true, function(directory_path, files_to_keep)
				util.logprint("clearing directory '"..directory_path.."' except for '"..table.concat(files_to_keep, "', '").."'")
				incdl()
					assert(util.execute_command_at("DEL /F /Q "..files_in_directory_as_string_list_except(directory_path, files_to_keep), directory_path))
				decdl()
			end,
		})
		
		util.ensure_directory_clean = function(path)
			util.remove_directory_if_exists(path)
			util.ensure_directory(path)
		end
		
		function util.move_file_in_directory(containing_dir_path, source_file_name, destination_file_name)
			util.logprint("renaming file in directory '"..containing_dir_path.."' from '"..source_file_name.."' to '"..destination_file_name.."'")
			incdl()
				assert(os.rename(containing_dir_path.."/"..source_file_name, containing_dir_path.."/"..destination_file_name))
			decdl()
		end
		
		install_delayed_impl_selector(util, 'copy_file_to_become', {
			function() return util.find_program_cached("cp") end, function(source, destination)
				util.logprint("copying file '"..source.."' to become file '"..destination.."'")
				incdl()
					assert(util.execute_command("cp "..util.in_quotes(source).." "..util.in_quotes(destination)))
				decdl()
			end,
			--[[COPY is not a program]] true, function(source, destination)
				util.logprint("copying file '"..source.."' to become file '"..destination.."'")
				incdl()
					assert(util.execute_command("COPY /Y "..util.in_quotes(source).." "..util.in_quotes(destination)))
				decdl()
			end,
		})
		
		install_delayed_impl_selector(util, 'copy_directory_recursively_to_become', {
			function() return util.find_program_cached("cp") end, function(source, destination)
				util.logprint("copying directory '"..source.."' to become directory '"..destination.."'")
				incdl()
					assert(util.execute_command("cp -R -T "..util.in_quotes(source).." "..util.in_quotes(destination)))
				decdl()
			end,
			function() return util.find_program_cached("XCOPY") end, function(source, destination)
				util.logprint("copying directory '"..source.."' to become directory '"..destination.."'")
				incdl()
					assert(util.execute_command("XCOPY /E /Q /Y "..util.in_quotes(source).." "..util.in_quotes(destination)))
				decdl()
			end,
		})
		
		install_delayed_impl_selector(util, 'files_in_directory', {
			function() return util.find_program_cached("ls") end, function(path)
				util.logprint("listing files in directory: "..path)
				incdl()
					local success, exit_type, return_status, program_output = util.execute_command("ls -1A "..util.in_quotes(path))
					assert(success, "failed to list files in directory: "..tostring(path))
				decdl()
				return util.line_contents_from_string(program_output or "")
			end,
			--[[DIR is not a program]] true, function(path)
				util.logprint("listing files in directory: "..path)
				incdl()
					local success, exit_type, return_status, program_output = util.execute_command("DIR /B "..util.in_quotes_with_backslashes(path))
					assert(success, "failed to list files in directory: "..tostring(path))
				decdl()
				return util.line_contents_from_string(program_output or "")
			end,
		})
		
		-- helper function for entry_index_name_path_in_directory_or_cleanup_iterator below
		local entry_index_name_path_in_directory_or_cleanup_iterator__next = function(file_names_in_directory, prev_i)
				if not file_names_in_directory or prev_i >= #file_names_in_directory then return end
				
				local i = prev_i+1
				local file_name = file_names_in_directory[i]
				local file_path = file_names_in_directory.file_path_prefix .. file_name
				return i, file_name, file_path
			end
		-- iterator function over each file name in a directory, deletes the directory if empty
		function util.entry_index_name_path_in_directory_or_cleanup_iterator(directory_path)
			local exists, file_names_in_directory = pcall(util.files_in_directory, directory_path)
			if not exists then -- the directory doesn't exist
				file_names_in_directory = nil
			elseif #file_names_in_directory == 0 then -- the directory is empty
				util.remove_directory(directory_path)
			else -- the directory contains entries
				file_names_in_directory.file_path_prefix = directory_path.."/"
			end
			return entry_index_name_path_in_directory_or_cleanup_iterator__next, file_names_in_directory, 0
		end
		
		local read_full_file_impl = function(path_or_nil, failure_message)
			local failure_prefix = failure_message and failure_message.."\n" or ""
			
			util.logprint("reading "..(path_or_nil and "file '"..path_or_nil.."'" or "stdin"))
			
			local file_success, file_error
			if path_or_nil then -- read from file if path was given
				file_success, file_error = io.open(path_or_nil, 'r')
			else -- read from stdin if path_or_nil is nil
				file_success, file_error = pcall(io.input)
				file_success = file_success and file_error
			end
			local file = assert(file_success, failure_prefix..tostring(file_error))
			
			local contents_success, contents_error = file:read('*a')
			local contents = assert(contents_success, failure_prefix..tostring(contents_error))
			
			if path_or_nil then -- if we try to close stdin, we apparently trigger an error "cannot close standard file"
				assert(file:close())
			end
			return contents
		end
		
		function util.read_full_file(path, failure_message)
			assert(path)
			return read_full_file_impl(path, failure_message)
		end
		function util.read_full_stdin(failure_message)
			return read_full_file_impl(nil, failure_message)
		end
		
		function util.write_full_file(path, contents)
			local file = assert(io.open(path, 'w+'))
			assert(file:write(contents))
			assert(file:close())
		end
		
		function util.read_param_file_new_compat_deserialize(path, failure_message)
			util.logprint("reading params from file: "..path)
			incdl()
				local result = util.new_compat_deserialize(util.read_full_file(path, failure_message), failure_message)
			decdl()
			return result
		end
		
		function util.read_multientry_param_file_new_compat_deserialize(path)
			util.logprint("reading params from file: "..path)
			incdl()
				local result = util.new_compat_deserialize_multientry(util.read_full_file(path))
			decdl()
			return result
		end
		
		function util.read_multivalue_param_file_new_compat_deserialize(path)
			util.logprint("reading multivalue params from file: "..path)
			incdl()
				local entries, key_lookup = util.new_compat_deserialize_multivalue(util.read_full_file(path))
			decdl()
			return entries, key_lookup
		end
		
		function util.write_param_file_new_compat_serialize(path, params)
			util.write_full_file(path, util.new_compat_serialize(params))
		end
		
		local cached_hostname
		install_delayed_impl_selector(util, 'get_hostname', {
			function() return util.find_program_cached("hostname") end, function()
				if not cached_hostname then
					local success, exit_type, return_status, program_output = util.execute_command("hostname")
					cached_hostname = program_output and util.cut_trailing_space(program_output)
						or "(hostname-failed)"
				end
				return cached_hostname
			end,
			true, function() return "(hostname-unavailable)" end,
		})
	
	-- git (repository)
		function util.is_git_repository(path)
			return util.execute_command_at("git status --porcelain"--[[ --ignored]], path)
		end
		
		function util.is_working_directory_clean(repository)
			local path = type(repository) == 'table' and repository.path
				or type(repository) == 'string' and repository
			assert(path)
			util.logprint("checking whether working directory '"..path.."' is clean")
			incdl()
				local successful, exit_type, return_status, program_output = util.execute_command_at("git status --porcelain"--[[ --ignored]], path)
				assert(successful)
			decdl()
			return program_output == "", program_output
		end
		
		function util.get_commit_hash_of(repository_path, git_commit_expr)
			git_commit_expr = util.in_quotes(git_commit_expr)
			local successful, exit_type, return_status, program_output = util.execute_command_at("git log --format=oneline -n1 "..git_commit_expr, repository_path)
			assert(successful, "git log failed (maybe not in a git repository?)")
			local gitcommithash = string.match(program_output, "^(%S+)%s")
			return gitcommithash
		end
		
		local git_supports_date_iso_strict -- nil at first, assigned true or false once we have proof
		function util.get_commit_hash_timestamp_tags_of(repository_path, git_commit_expr)
			git_commit_expr = util.in_quotes(git_commit_expr)
			local date_option = git_supports_date_iso_strict ~= false and "--date=iso-strict" or "--date=iso"
			local successful, exit_type, return_status, program_output = util.execute_command_at("git log -n1 "..date_option.." --decorate=short "..git_commit_expr, repository_path)
			if git_supports_date_iso_strict == nil then
				if successful then
					git_supports_date_iso_strict = true -- if it was successful, git supports the newer date format
				else
					-- first we assume it doesn't support the newer date format (f.e. git 1.8.3 doesn't)
					git_supports_date_iso_strict = false
					-- so we try again...
					local successful_with_older_date, gitcommithash, commit_timestamp, tags = pcall(util.get_commit_hash_timestamp_tags_of, repository_path, git_commit_expr)
					if successful_with_older_date then
						-- no support was correct, return the results
						return gitcommithash, commit_timestamp, tags
					else
						-- If it failed again, the date format wasn't the reason. Now we test that flag definitively, with the repository HEAD.
						successful_with_older_date = util.execute_command_at("git log -n1 --date=iso-strict", repository_path)
						git_supports_date_iso_strict = successful_with_older_date or false
						-- fallthrough to the assert, still report the initial failure normally
					end
				end
			end
			assert(successful, "git log failed (unrecognized commit, or not in a git repository?)")
			
			local gitcommithash, rest_of_first_line, commit_timestamp = string.match(program_output, "\n?commit%s*(%S+)([^\n]*).*Date:%s*([^\n]*)")
			
			-- parse refs string for tags
			local tags = {}
			local refs_string = string.match(rest_of_first_line, "%s*%(([^%)]*)%)")
			if refs_string then
				for tag_name in string.gmatch(refs_string, "tag: ([^,]*)") do
					tags[#tags+1] = tag_name
				end
			end
			
			return gitcommithash, commit_timestamp, tags
		end
		
		function util.get_current_commit_hash(repository_path)
			return util.get_commit_hash_of(repository_path, 'HEAD')
		end
		
		function util.get_merge_base(repository_path, space_separated_commit_hashes_string)
			local succssful, exit_type, return_status, program_output = util.execute_command_at("git merge-base "..space_separated_commit_hashes_string, repository_path)
			if not successful then return successful end
			program_output = string.match(program_output, "[0-9a-f]+")
			return program_output
		end
		
		function util.is_given_commit_descendant_of(repository_path, descendant_commit_hash, ancestor_commit_hash)
			local succssful, exit_type, return_status, program_output = util.execute_command_at("git merge-base --is-ancestor "..util.in_quotes(ancestor_commit_hash).." "..util.in_quotes(descendant_commit_hash), repository_path)
			assert(return_status == 0 or return_status == 1)
			return return_status == 0
		end
		
		function util.is_current_commit_descendant_of(repository_path, ancestor_commit_hash)
			return util.is_given_commit_descendant_of(repository_path, 'HEAD', ancestor_commit_hash)
		end
		
		function util.checkout_commit(repository_path, git_commit_expr)
			assert(git_commit_expr)
			util.logprint("checking out repository '"..repository_path.."' commit '"..git_commit_expr.."'")
			incdl()
				assert(util.execute_command_at("git checkout "..util.in_quotes(git_commit_expr), repository_path))
			decdl()
		end
		
		function util.get_local_branch_names(repository_path)
			util.logprint("getting branches of repository '"..repository_path.."'")
			local results = {}
			incdl()
				local program_success, exit_type, return_status, program_output = util.execute_command_at("git branch --list --no-color", repository_path)
				local output_lines = program_success and program_output and util.line_contents_from_string(program_output)
				for i = 1, #output_lines do
					local line = output_lines[i]
					local prefix = string.sub(line, 1, 2)
					if prefix ~= "  " and prefix ~= "* " then
						error("unexpected branch --list output line (prefix '"..prefix.."'): "..line)
					end
					local branch_name = string.sub(line, 3)
					if util.string_starts_with(branch_name, "(HEAD detached at ") then
						results[#results+1] = "HEAD"
					else
						results[#results+1] = branch_name
					end
				end
			decdl()
			return results
		end
		
		function util.get_rev_list_for(repository_path, commits)
			util.logprint("getting full rev-list of repository '"..repository_path.."'")
			incdl()
				local ddl = util.debug_detail_level
				util.debug_detail_level = 0
				local all_commits = table.concat(commits, " ")
				local program_success, exit_type, return_status, program_output = util.execute_command_at("git rev-list --topo-order --reverse "..all_commits, repository_path)
				util.debug_detail_level = ddl
			decdl()
			return program_success and program_output
		end

util.debug_detail_level = actual_debug_detail_level

return util
