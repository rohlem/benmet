--[[
This file is the program entry point.
It handles argument parsing and forwards them to the program's commands declared in 'benmet.commands'.
--]]

-- compatibility configuration variables
-- _G.benmet_launch_steps_as_child_processes = true -- set to true to force launching new Lua subprocesses for Lua step scripts, to guarantee isolation in exchange for subprocess launch overhead
-- _G.benmet_disable_indirection_layer = _G.benmet_launch_steps_as_child_processes -- set to true to disable wrapping the standard library functions to isolate subprocesses (leads to errors unless _G.benmet_launch_steps_as_child_processes is true)

-- global / general setup code

local relative_path_prefix = "./"
_G.benmet_relative_path_prefix = relative_path_prefix


local util -- forward declaration of our import of 'benmet.util'

local main_script_dir_path -- used to refer to documentation in general program description
do -- set up package.path for importing other benmet code via `require`
	local original_package_path = package.path
	
	main_script_dir_path = string.match(arg[0], "^(.-)[^/%\\]*$")
	main_script_dir_path = #main_script_dir_path > 0 and main_script_dir_path or "./"
	local benmet_path = main_script_dir_path.."../?.lua;"
	local lunajson_path = main_script_dir_path.."../lunajson/src/?.lua;"
	
	local benmet_package_path_prefix = benmet_path..lunajson_path
	
	package.path = benmet_package_path_prefix..package.path
	
	_G.benmet_get_main_script_dir_path = function() return main_script_dir_path end -- used by benmet.util in import error messages
	
	local absolute_package_path_entries_ensured
	-- ensures that the package.path entries based on our main script dir path are absolute,
	-- so that 'require' within step scripts can find our modules even though they have a different working directory
	_G.benmet_ensure_package_path_entries_are_absolute = function()
		if absolute_package_path_entries_ensured then return end
		if not util.path_is_absolute(main_script_dir_path) then
			local cwd_prefix = util.get_current_directory() .. "/"
			main_script_dir_path = cwd_prefix .. main_script_dir_path
			package.path = util.prefix_relative_path_templates_in_string(benmet_package_path_prefix, cwd_prefix)..original_package_path
		end
		absolute_package_path_entries_ensured = true
	end
end

local program_invocation_string_without_args -- used in help text syntax examples
do
	local min_index = 0
	while arg[min_index-1] ~= nil do
		min_index = min_index - 1
	end
	local benmet_lua_program_command = arg[min_index]
	_G.benmet_get_lua_program_command = function() return benmet_lua_program_command end
	program_invocation_string_without_args = table.concat(arg, " ", min_index, 0)
end



-- load program command specifications and implementations
local program_command_structures = require 'benmet.commands'



-- help text code

local help_list_commands = function()
	print("usage: "..program_invocation_string_without_args.." <command> <further-args...>"
		.."\n\nMinimal-dependency suspendable task automation program 'benmet'. See directory '"..tostring(main_script_dir_path).."' for documentation and usage pointers."
		.."\nInvoke with any of the commands below and the flag '--help' for more details on it:"
		.."\n\navailable commands:")
	local ordered_command_list = { -- ordered semantically, to be manually kept in sync with the actual command specification in 'benmet.commands'
		'auto-setup',
		'add-repo',
		'step.do',
		'step.list-dependencies',
		'step.trace-dependencies',
		'pipelines.launch',
		'pipelines.resume',
		'pipelines.poll',
		'pipelines.cancel',
		'pipelines.discard',
		'commit-ordering',
		'metrics-to-json',
		'test-command',
		'test-script',
	}
	
	local actual_commands = {} -- shallow table copy
	for k,v in pairs(program_command_structures) do
		actual_commands[k] = v
	end
	
	-- check that all expected commands are present (and output their summary texts)
	local expected_command_count = #ordered_command_list
	for i = 1, expected_command_count do
		local command = ordered_command_list[i]
		if actual_commands[command] then -- check consistency with actual program command list
			local summary = actual_commands[command].summary
			print("   "..command..(summary and " : "..summary or " (no command summary available)"))
			actual_commands[command] = nil
		else
			print("(Warning: command '"..command.."' not present)")
		end
	end
	
	-- check that no other commands are present
	for k,v in pairs(actual_commands) do
		print("(Warning: unexpected command found: '"..k.."')")
	end
	
	print("\nglobal (debug) flags:\n   --debug-output-to-file : append debug output to the file at the given path\n   --debug-detail-level : set the debug level (increase for more details, -1 to disable)")
end

local help_print_options = function(option_names, from_options, infix, shorthands_for)
	table.sort(option_names)
	for i = 1, #option_names do
		local option_name = option_names[i]
		local option_entry = from_options[option_name]
		local description = option_entry.description
		local description_suffix = description and " : " .. (
				shorthands_for and description .. " (shorthand for `--"..table.concat(shorthands_for[i], " --").."`)"
				or description
			) or " (no option description available)"
		print("   --"..option_name..(infix or "")..description_suffix)
	end
end

local help_print_command_details = function(command_name)
	local argument_synopsis = ""
	local selected_command_structure = program_command_structures[command_name]
	local command_options = selected_command_structure.options
	if command_options then
		argument_synopsis = " [<options...>]"
	end
	if selected_command_structure.any_args_max ~= 0 then
		argument_synopsis = argument_synopsis.." <"..selected_command_structure.any_args_name
		if selected_command_structure.any_args_max ~= 1 then
			argument_synopsis = argument_synopsis.."..."
		end
		argument_synopsis = argument_synopsis..">"
	end
	
	print("usage: "..program_invocation_string_without_args.." "..command_name..argument_synopsis
		.."\n\n"..(selected_command_structure.description or "(no command description available)"))
	if command_options then
		print("\noptions:")
		local required_options = {}
		local normal_options = {}
		local flag_shorthands = {}
		local flag_shorthands_for = {}
		local flag_options = {}
		for k,v in pairs(command_options) do
			local add_to = v.required and required_options
				or v.is_flag and (v.shorthand_for and flag_shorthands or flag_options)
				or normal_options
			add_to[#add_to+1] = k
			if v.shorthand_for then
				flag_shorthands_for[#flag_shorthands_for+1] = v.shorthand_for
			end
		end
		help_print_options(required_options, command_options, " (required)")
		help_print_options(normal_options, command_options)
		help_print_options(flag_shorthands, command_options, " (flag)", flag_shorthands_for)
		help_print_options(flag_options, command_options, " (flag)")
	end
	print()
end

local usage_error = function(error_text, display_command_help)
	local help_suffix = display_command_help and " Displaying command help:\n"
		or " Add flag '--help' for command help."
	print("Usage error: "..tostring(error_text)..help_suffix)
	if display_command_help then
		help_print_command_details(display_command_help)
	end
	os.exit(2)
end


-- command line argument parsing

-- command selection
local root_command = arg[1]
if not root_command or root_command == '--help' then
	-- check if maybe the next program argument is a recognized command
	local next_argument_command_name = arg[2]
	if next_argument_command_name then
		if program_command_structures[arg[2]] then
			print("Displaying help for command '"..tostring(next_argument_command_name).."', invoke with only '--help' to see program help.\n")
			help_print_command_details(next_argument_command_name)
			return
		else
			print("Unrecognized command '"..tostring(next_argument_command_name).."', displaying program help.\n")
		end
	end
	help_list_commands()
	if not root_command then os.exit(3) end
	return
end

local selected_command_structure = program_command_structures[root_command]
-- check the command is recognized
if not selected_command_structure then
	print("Unrecognized command '"..root_command.."'. Displaying program help.\n")
	help_list_commands();
	os.exit(2)
end

local parsed_options = {}
-- setup option parsing state (supports multiple values, even though we currently don't need it)
if selected_command_structure.options then
	for k,v in pairs(selected_command_structure.options) do
		parsed_options[k] = not v.is_flag and not v.forward_as_arg and {}
	end
end
local parsed_args = {}


local benmet_debug_detail_level = -1
-- loop over program arguments
local arg_i = 2
if selected_command_structure.allow_anything_as_args_verbatim and arg[arg_i] == '--help' then
	help_print_command_details(root_command)
	return
end
while arg_i <= #arg do
	local next_arg = arg[arg_i]
	
	local added_to_options
	local option_head = string.sub(next_arg, 1, 2) == '--'
	if option_head and not selected_command_structure.allow_anything_as_args_verbatim then
		-- look for the equal sign of '--option=value' syntax
		local equals_index = string.find(next_arg, "=", 3, true)
		local option_name = string.sub(next_arg, 3, equals_index and (equals_index-1))
		if option_name == 'help' then -- special handling for '--help'
			help_print_command_details(root_command)
			return
		end
		local option_value = equals_index and string.sub(next_arg, equals_index+1)
		if option_name == 'debug-output-to-file' then -- special handling for '--debug-output-to-file'
			if _G.benmet_debug_output_to_file then usage_error("multiple '--debug-output-to-file' options given") end
			if not option_value then
				arg_i = arg_i + 1
				option_value = arg[arg_i+1]
			end
			if not option_value then usage_error("required value missing from option '--debug-output-to-file'") end
			_G.benmet_debug_output_to_file = option_value
			added_to_options = true
		elseif option_name == 'debug-detail-level' then -- special handling for '--debug-detail-level'
			if not benmet_debug_detail_level then usage_error("multiple '--debug-detail-level' options given") end
			if not option_value then
				arg_i = arg_i + 1
				option_value = arg[arg_i+1]
			end
			if not option_value then usage_error("required value missing from option '--debug-detail-level'") end
			option_value = tonumber(option_value)
			if not option_value then usage_error("value of option '--debug-detail-level' must be a number") end
			benmet_debug_detail_level = option_value
			added_to_options = true
			
		else -- non-special option
			
			-- look up the option
			local option_entry = selected_command_structure.options[option_name]
			if not option_entry then
				return usage_error("Unrecognized option '--"..tostring(option_name).."'.", root_command)
			end
			
			if option_entry.forward_as_arg or option_entry.is_flag then
				if option_value then
					return usage_error("--option=value syntax not supported for "..(option_entry.forward_as_arg and "forwarded (grouped)" or "flag").." option '"..option_name.."'.", root_command)
				end
				if option_entry.is_flag then
					local shorthand_for = option_entry.shorthand_for
					if shorthand_for then
						for i = 1, #shorthand_for do
							parsed_options[shorthand_for[i]] = true
						end
					else
						parsed_options[option_name] = true
					end
					added_to_options = true
				else
					assert(option_entry.forward_as_arg)
				end
			else
				added_to_options = true
				if not option_value then
					arg_i = arg_i + 1
					assert(#arg >= arg_i, "missing required argument to option '"..option_name.."'")
					option_value = arg[arg_i]
				end
				local parsed_option_values = parsed_options[option_name]
				parsed_option_values[#parsed_option_values+1] = option_value
			end
		end
	end
	
	if not added_to_options then -- not yet handled: args and passthrough options
		parsed_args[#parsed_args+1] = next_arg
	end
	arg_i = arg_i + 1
end

-- check if we received too few arguments
if selected_command_structure.any_args_min then
	if #parsed_args < selected_command_structure.any_args_min then
		local expected = selected_command_structure.any_args_min
		local arguments_multiplicity = expected == 1 and " argument"
			or " arguments"
		expected = (not selected_command_structure.any_args_max or expected < selected_command_structure.any_args_max) and "at least "..expected
			or expected
		local received = #parsed_args == 0 and "none"
			or "only "..#parsed_args
		help_print_command_details(root_command)
		return usage_error("Expected "..expected.." "..selected_command_structure.any_args_name..arguments_multiplicity..", received "..received..".")
	end
end

-- check if we received too many arguments
if selected_command_structure.any_args_max then
	if #parsed_args > selected_command_structure.any_args_max then
		local expected = selected_command_structure.any_args_max
		local arguments_multiplicity = expected == 1 and " argument"
			or " arguments"
		expected = expected == 0 and "no"
			or ((not selected_command_structure.any_args_min or expected > selected_command_structure.any_args_min) and "only up to "..expected
				or "only "..expected
				).." "..selected_command_structure.any_args_name
		help_print_command_details(root_command)
		return usage_error("Expected "..expected..arguments_multiplicity..", received "..#parsed_args..".")
	end
end

-- check if we did not receive a required option, or received an option twice
if selected_command_structure.options then
	for k,v in pairs(selected_command_structure.options) do
		local values = parsed_options[k]
		if type(values) == 'table' then
			local value_count = #values
			if (v.required and value_count <= 0) then
				return usage_error("Command '"..tostring(root_command).."' is missing required option '"..k.."'.")
			end
			if not v.allow_multiple then
				if value_count > 1 then
					return usage_error("option '"..k.."' given multiple times (which command '"..tostring(root_command).." doesn't support).")
				end
			else
				if not (v.allow_multiple == true or value_count <= v.allow_multiple) then
					local occurrences_suffix = v.allow_multiple == true and ""
						or " (only "..tostring(v.allow_multiple).." occurrences supported)"
					return usage_error("option '"..k.."' given too many times"..occurrences_suffix..".")
				end
			end
		end
	end
end


-- run the selected command with the parsed arguments
local command_implementation = assert(selected_command_structure.implementation, "command has no implementation yet (FIXME)")

_G.benmet_util_skip_library_imports = selected_command_structure.benmet_util_skip_library_imports

if not _G.benmet_disable_indirection_layer then
	require "benmet.indirection_layer" -- load this module first, just to make sure the standard library is stubbed before someone saves a reference to the original functions
end

local features = require "benmet.features"
util = require "benmet.util"
util.debug_detail_level = benmet_debug_detail_level

os.exit(command_implementation(features, util, parsed_args, parsed_options))
