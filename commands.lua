--[[
This file contains the implementations and argument specifications of the main commands the program offers,
using the modules `benmet.features` and `benmet.util`.
These commands are returned as a table in the following form 'benmet.main' expects:
{
	[<command-name>] = {
		any-args_name = <name of "any args" (non-options) to display in help text>,
		any_args_min = <minimum number of "any args" (non-options), nil defaults to 0>,
		any_args_max = <maximum number of "any args" (non-options), nil defaults to unlimited,
		
		summary = <a _short descriptive text to display in the program-wide help text>,
		description = <a _longer descriptive text to display in the command-specific help text>,
		
		implementation = <the command implementation, as a function value to be called as function(<benmet.features module>, <benmet.util module>, <arguments>, <options>) that may return an integer value to determine the program return code>,
		
		allow_anything_as_args_verbatim = <flag to ignore '--' (only exception being '--help') and pass everything as an "any arg" (nothing as an option); nil defaults to false>,
		options = <table of available command options (prefixed with '--') of the form: {
			[<option-name>] = {
				description = <description to display in help text>,
				required = <if the command requires this option to run; nil defaults to false>,
				
				is_flag = <whether the option does not take an argument (via next program argument or '='-suffix) and is instead a boolean that signals whether the option was present; incmopatible with forward_as_arg, nil defaults to false>,
				shorthand_for = <list of other options (must all be flags) this flag activates>,
				
				forward_as_arg = <boolean that indicates this option is supposed to be ignored and passed through as a normal arg, as a sort of section marker f.e. "--sources a b --targets b c"; incompatible with is_flag, nil defaults to false>,
				
				allow_multiple = <boolean or number (limit) that indicates whether this option can be supplied multiple times (only supported for normal, non-flag, non-forwarded-as-args options)>,
			},
		}; nil defaults to no options>,
		
		benmet_util_skip_library_imports = <boolean that indicates whetehr benmet.util should _not try importing external dependencies (pua_lua_SHA and lunajson); nil defaults to false>,
	},
}
--]]


local relative_path_prefix = _G.benmet_relative_path_prefix

-- declaration of program argument structure

-- common options
local option_with_run_id = {description = "override the auto-generated 'RUN-id' property"}
local option_param_file = {description = "use the given parameter file as initial inputs to calculate step parameters"} --TODO (maybe): support multiple?

local option_pipeline_default_params = {is_flag = true, description = "add an instance of all-defaulted parameters, as if supplying an empty parameter file"}
local option_pipeline_all_params = {is_flag = true, description = "select all pipelines regardless of parameters"}
local option_pipeline_params_from_stdin = {is_flag = true, description = "read standard input as an additional parameter file"}
local option_pipeline_target = {description = "the target step of the pipeline(s)"} --TODO(potentially?): could be made optional if we had a default target step in steps/index.txt
local option_pipeline_all_targets = {is_flag = true, description = "select all pipelines regardless of targets"}
local option_pipeline_all = {is_flag = true, shorthand_for = {'all-targets', 'all-params'}, description = "select all pipelines"}
local option_pipeline_accept_param = {description = "accept an unused property in pipeline parameterizations", allow_multiple = true}
local option_pipeline_ignore_param = {description = "remove a property from pipeline parameterizations", allow_multiple = true}
local option_pipeline_accept_unrecognized_params = {description = "accept unrecognized properties in pipeline parameterizations", is_flag = true}
local option_pipeline_ignore_unrecognized_params = {description = "remove unrecognized properties from pipeline parameterizations", is_flag = true}

local option_to_file = {description = "The file to write output to (instead of stdout). Overwrites all previous contents!"}

-- common command structure
local pipeline_operation_structure_options = {
		['target'] = option_pipeline_target,
		['all-targets'] = option_pipeline_all_targets,
		['default-params'] = option_pipeline_default_params,
		['params-from-stdin'] = option_pipeline_params_from_stdin,
		['all-params'] = option_pipeline_all_params,
		['all'] = option_pipeline_all,
		['ignore-param'] = option_pipeline_ignore_param,
		['accept-param'] = option_pipeline_accept_param,
		['ignore-unrecognized-params'] = option_pipeline_ignore_unrecognized_params,
		['accept-unrecognized-params'] = option_pipeline_accept_unrecognized_params,
	}
local pipeline_operation_structure_options_with_error_state_handling = {
		['target'] = option_pipeline_target,
		['all-targets'] = option_pipeline_all_targets,
		['default-params'] = option_pipeline_default_params,
		['params-from-stdin'] = option_pipeline_params_from_stdin,
		['all-params'] = option_pipeline_all_params,
		['all'] = option_pipeline_all,
		['include-errors'] = {is_flag = true, description = "also select pipelines with error status"},
		['only-errors'] = {is_flag = true, description = "only select pipelines with error status"},
		['ignore-param'] = option_pipeline_ignore_param,
		['accept-param'] = option_pipeline_accept_param,
		['ignore-unrecognized-params'] = option_pipeline_ignore_unrecognized_params,
		['accept-unrecognized-params'] = option_pipeline_accept_unrecognized_params,
	}


-- FIXME: Do we want this? If so, where?
local dependencies_txt_description = "This file contains lines of the syntax '<dependers>: <dependees>', where both sides are space-separated, possibly empty lists of step names. Both dependers and dependees may appear in multiple lines. All steps must appear as dependers at least once."



-- common pipeline command routines

-- results in no iterations when used in for-in loop
local empty_iterator__next = function() end

-- parse common pipeline options and arguments into an array of iterators and a warning printer, and remove parsed arguments in-place
-- checks for option '--all-params', errors if present and any parameter iterators were created
-- handles option '--default-params' by adding an iterator returning a single {} for default parameters
-- handles all arguments by adding an iterator over all parameter combinations from the given multivalue parameter files
local parse_param_iterator_constructors_and_warning_printers_from_pipeline_arguments_options = function(features, util, arguments, options)
		
		local no_iterators_flag = options['all-params']
		local iterator_constructor_list = not no_iterators_flag and {}
		local warning_printer_list = iterator_constructor_list and {}
		
		if options['default-params'] then
			assert(not no_iterators_flag, "option '--all-params' incompatible with option '--default-params'")
			-- creating a stub parameter iterator for default params
			local default_param_iterator__next = function(state, prev_index)
					if prev_index then return nil end
					return {}
				end
			local default_param_iterator_constructor = function()
					return default_param_iterator__next, --[[state]]nil, --[[first_index]]nil
				end
			iterator_constructor_list[#iterator_constructor_list+1] = default_param_iterator_constructor
		end
		
		local param_files = {}
		for i = 1, #arguments do
			param_files[i] = arguments[i]
			arguments[i] = nil
		end
		
		local read_stdin_as_file = options['params-from-stdin']
		if #param_files > 0 or read_stdin_as_file then
			assert(not no_iterators_flag, "option '--all-params' incompatible with parameter file arguments")
			local failed_parsing_parameter_files = {}
			-- creating a parameter iterator from a given parameter file
			local initial_param_iterator_from_param_file_contents_constructor = function(param_file_name, reading_file_success, file_contents)
					-- first read the file
					local error_message, parsing_mode_hint = "(error message uninitialized)", "(error hint uninitialized)"
					local successful = reading_file_success
					if not successful then
						error_message = file_contents
						parsing_mode_hint = "(error reading file) "
						-- fallthrough
					else
						-- next see if the beginning looks like a JSON array
						if string.match(file_contents, "^%w*%[") then
							-- parse it as JSON
							parsing_mode_hint = "(tried parsing as JSON array) "
							local param_array
							successful, param_array = pcall(util.json_decode, file_contents)
							if not successful then
								error_message = param_array
								-- fallthrough
							else
								-- convert all values to strings, as our line-based format would,
								-- and check that all combinatorial arrays are non-empty
								successful, error_message = pcall(util.coerce_json_multivalue_array_in_place, param_array)
								if successful then -- else fallthrough
									-- return the resulting iterator, which iterates over all array entries,
									-- combinatorically creating all multivalues
									return util.all_combinations_of_multivalues_in_list(param_array)
								end
							end
						else
							-- parse it as a multivalue param file in our custom line-based format
							parsing_mode_hint = "(tried parsing as line-based multivalue param file) "
							local multivalue_entries
							successful, multivalue_entries = pcall(util.new_compat_deserialize_multivalue, file_contents)
							if not successful then
								error_message = multivalue_entries
								-- fallthrough
							else
								-- return the resulting iterator
								return util.all_combinations_of_multivalues(multivalue_entries)
							end
						end
					end
					-- in case of error, we fall through to here
					-- add the file to our list of parsing failures
					failed_parsing_parameter_files[#failed_parsing_parameter_files+1] = param_file_name .. ": "..tostring(parsing_mode_hint)..tostring(error_message)
					-- return an empty iterator
					return empty_iterator__next
				end
			
			for i = 1, #param_files do
				local param_file = param_files[i]
				iterator_constructor_list[#iterator_constructor_list+1] = function()
						return initial_param_iterator_from_param_file_contents_constructor(param_file, pcall(util.read_full_file, param_file))
					end
			end
			if read_stdin_as_file then
				iterator_constructor_list[#iterator_constructor_list+1] = function()
						return initial_param_iterator_from_param_file_contents_constructor('(stdin)', pcall(util.read_full_stdin))
					end
			end
			warning_printer_list[#warning_printer_list+1] = function()
					-- output all files that we failed to parse
					if #failed_parsing_parameter_files > 0 then
						print("The following parameter files could not be parsed (were ignored):")
						for i = 1, #failed_parsing_parameter_files do
							print("- "..failed_parsing_parameter_files[i])
						end
						print("Please manually verify the existence and contents of these files.")
					end
				end
		end
		
		local warning_printer = function()
				for i = 1, #warning_printer_list do
					warning_printer_list[i]()
				end
			end
		
		return iterator_constructor_list, warning_printer
	end

-- parse common pipeline options into a parameter coercion function provider and a warning printer
-- checks for options '--accept-param', '--ignore-param', '--accept-unrecognized-params' and '--ignore-unrecognized-params', errors if they overlap
-- the param coercion provider takes a target step name and returns a coercion function
-- the coercion function returns the result of the parameters specified to be ignored removed from the given initial_params table (leaving the original table unchanged), or nil if unrecognized params remained and fallback behaviour was left unspecified
local parse_unrecognized_param_coercer_provider_and_warning_printer_from_pipeline_options = function(features, util, options)
		
		-- option validation
		local default_unrecognized_param_behaviour = 'error'
		if options['ignore-unrecognized-params'] then
			assert(not options['accept-unrecognized-params'], "Flags '--ignore-unrecognized-params' and '--accept-unrecognized-params' are exclusive. Select handling of individual properties with options '--ignore-param' and '--accept-param'.")
			default_unrecognized_param_behaviour = 'ignore'
		elseif options['accept-unrecognized-params'] then
			default_unrecognized_param_behaviour = 'accept'
		end
		
		local params_to_ignore_list = options['ignore-param']
		local params_to_accept_list = options['accept-param']
		do -- check for overlap
			local params_to_ignore_lookup = util.list_to_lookup_table(params_to_ignore_list)
			local params_to_accept_lookup = util.list_to_lookup_table(params_to_accept_list)
			
			local conflict_list = {}
			for i = 1, #params_to_ignore_list do
				if params_to_accept_lookup[params_to_ignore_list[i]] then
					conflict_list[#conflict_list+1] = params_to_ignore_list[i]
				end
			end
			if #conflict_list > 0 then
				error("The following properties were specified to be both ignored and accepted: "..table.concat(conflict_list, ", ").."\n Please remove the corresponding '--ignore-param' or '--accept-param' options.")
			end
		end
		params_to_ignore_list = #params_to_ignore_list > 0 and params_to_ignore_list
		
		-- actual logic
		
		local unrecognized_parameters_total = default_unrecognized_param_behaviour == 'error' and {} -- [name] = index, [index] = {name, occurences}
		
		local param_coercer_by_target_step_name = {}
		local param_coercer_provider = function(target_step_name)
				local param_coercer = param_coercer_by_target_step_name[target_step_name]
				if not param_coercer then
					local accepted_params_lookup = features.step_query_effective_inputs_lookup_union(target_step_name)
					accepted_params_lookup = util.table_copy_shallow(accepted_params_lookup)
					for i = 1, #params_to_accept_list do
						accepted_params_lookup[params_to_accept_list[i]] = true
					end
					param_coercer = function(initial_params)
							local coerced_params = initial_params
							-- remove params to ignore
							if params_to_ignore_list then
								coerced_params = util.table_copy_shallow(coerced_params)
								for i = 1, #params_to_ignore_list do
									coerced_params[params_to_ignore_list[i]] = nil
								end
							end
							
							if default_unrecognized_param_behaviour == 'accept' then -- early return if we accept all other params
								return coerced_params
							end
							
							-- collect unrecognized present params
							local unrecognized_param_list = {}
							for k--[[,v]] in pairs(coerced_params) do
								if not accepted_params_lookup[k] then
									unrecognized_param_list[#unrecognized_param_list+1] = k
								end
							end
							
							if #unrecognized_param_list == 0 then -- early return if there were no unrecognized params
								return coerced_params
							end
							
							if default_unrecognized_param_behaviour == 'ignore' then -- remove unrecognized params
								
								coerced_params = coerced_params == initial_params and util.table_copy_shallow(coerced_params)
									or coerced_params
								for i = 1, #unrecognized_param_list do
									coerced_params[unrecognized_param_list[i]] = nil
								end
								
								return coerced_params
								
							elseif default_unrecognized_param_behaviour == 'error' then -- collect unrecognized params for warning message
								
								for i = 1, #unrecognized_param_list do
									local param_name = unrecognized_param_list[i]
									local index = unrecognized_parameters_total[param_name]
									if not index then
										index = #unrecognized_parameters_total+1
										unrecognized_parameters_total[param_name] = index
										unrecognized_parameters_total[index] = {param_name, 0}
									end
									local entry = unrecognized_parameters_total[index]
									entry[2] = entry[2]+1
								end
								
								return nil
								
							end
							
							error("unreachable: unhandled default_unrecognized_param_behaviour value of '"..tostring(default_unrecognized_param_behaviour))
						end
					param_coercer_by_target_step_name[target_step_name] = param_coercer
				end
				return param_coercer
			end
		local warning_printer = function()
				if not unrecognized_parameters_total then return end
				if #unrecognized_parameters_total > 0 then
					-- order by occurrences descendingly
					table.sort(unrecognized_parameters_total, function(a, b) return a[2] > b[2] end)
					print("Some parameter combinations contained properties not consumed by any of the involved steps:")
					for i = 1, #unrecognized_parameters_total do
						local entry = unrecognized_parameters_total[i]
						local occurrences = entry[2]
						print("- '"..tostring(entry[1]).."' (in "..tostring(occurrences).." parameter combination"..(occurrences == 1 and "" or "s")..")")
					end
					print("The offending parameter combinations were not processed.")
				end
			end
		return param_coercer_provider, warning_printer
	end

-- collects and iterates over existing pipelines, filterable by target step and initial parameters
-- implementation helper function for all pipeline commands besides 'pipelines.launch' (which creates new pipelines instead of operating on existing ones)
local pipeline_collective_by_individuals_command = function(features, util, arguments, options, command_infinitive, with_target_step_name_initial_params_pipeline_file_path_f)
		
		local target_step_name
		local parameter_iterator_constructors, parameter_iterator_warning_printer
		local param_coercer_provider, param_coercion_warning_printer
		do -- verify arguments and options
			
			-- we're either in --all-targets mode, or we have a single target_step_name
			target_step_name = options.target[1]
			if options['all-targets'] then
				assert(not target_step_name, "option '--all-targets' incompatible with selecting individual '--target' step")
			else
				assert(target_step_name, "missing '--target' step specification (or '--all-targets' flag)")
			end
			
			-- parse parameter iterators, error in case of inconsistent options, false if '--all-params' was specified
			parameter_iterator_constructors, parameter_iterator_warning_printer = parse_param_iterator_constructors_and_warning_printers_from_pipeline_arguments_options(features, util, arguments, options)
			assert(not (parameter_iterator_constructors and #parameter_iterator_constructors == 0), "missing parameter files (or option '--all-params' or '--default-params')")
			-- check for '--all-params' in combination with '--(accept|ignore)-(param|unrecognized-params)'
			if not parameter_iterator_constructors then
				assert(not (#options['accept-param'] > 0 or #options['ignore-param'] > 0 or options['accept-unrecognized-params'] or options['ignore-unrecognized-params']), "flag '--all-params' takes parameters from existing pipelines, and therefore ignores options '--accept-param' and '--ignore-param' as well as flags '--accept-unrecognized-params' and '--ignore-unrecognized-params'")
			else
				param_coercer_provider, param_coercion_warning_printer = parse_unrecognized_param_coercer_provider_and_warning_printer_from_pipeline_options(features, util, options)
			end
		end
		
		
		-- actual work
		
		-- first check what pipeline files exist
		
		local entry_index_name_path_in_directory_or_cleanup_iterator = util.entry_index_name_path_in_directory_or_cleanup_iterator
		local existing_param_hash_dir_lookup_by_target_step_name = {}
		-- dispatch function over each step name the command applies to
		-- uses existing_param_hash_dir_lookup_by_target_step_name as a cache, first call is hardcode-assumed to construct it
		local foreach_target_step_name_pipeline_dir_path_returns_disjunction -- forward declaration necessary for self-reassignment
		foreach_target_step_name_pipeline_dir_path_returns_disjunction =
			target_step_name and function(with_target_step_name_hash_dir_path_f, --[[further_args]]...)  -- forward with our single target step pipeline directory
					local target_step_pipeline_dir_path = relative_path_prefix.."pipelines/"..target_step_name
					return with_target_step_name_hash_dir_path_f(target_step_name, target_step_pipeline_dir_path, --[[further args]]...)
				end
			or function(with_target_step_name_hash_dir_path_f, --[[further_args]]...) -- iterate over the directory
					local any_found
					local pipelines_path = relative_path_prefix.."pipelines"
					for _, step_name, hash_dir_path in entry_index_name_path_in_directory_or_cleanup_iterator(pipelines_path) do
						any_found = with_target_step_name_hash_dir_path_f(step_name, hash_dir_path, --[[further args]]...)
							or any_found
					end
					-- on subsequent calls, iterate over our cache instead
					foreach_target_step_name_pipeline_dir_path_returns_disjunction = function(with_target_step_name_hash_dir_path_f, --[[further_args]]...)
						local any_found
						local pipelines_path = relative_path_prefix.."pipelines"
						local step_pipeline_dir_path_prefix = pipelines_path.."/"
						for step_name--[[, hash_dir_lookup]] in pairs(existing_param_hash_dir_lookup_by_target_step_name) do
							local hash_dir_path = step_pipeline_dir_path_prefix..step_name
							any_found = with_target_step_name_hash_dir_path_f(step_name, hash_dir_path, --[[further args]]...)
								or any_found
						end
						return any_found
					end
					return any_found
				end
		
		-- collect what param hash directories exist, as a set-like lookup table
		local any_pipelines_exist = foreach_target_step_name_pipeline_dir_path_returns_disjunction(
			function --[[collect_step_pipeline_dir_lookup]](step_name, step_pipeline_dir_path)
				local hash_dir_set = {}
				local any_found
				for _, hash_dir_name in entry_index_name_path_in_directory_or_cleanup_iterator(step_pipeline_dir_path) do
					hash_dir_set[hash_dir_name] = true
					any_found = true
				end
				if any_found then
					existing_param_hash_dir_lookup_by_target_step_name[step_name] = hash_dir_set
					return true
				end
			end)
		
		-- early return if no pipelines exist
		if not any_pipelines_exist then
			print("No pipelines to "..command_infinitive.." currently exist.")
			return
		end
		
		-- now select which pipeline files fall within the parameter selection
		
		local found_any_pipelines
		if not parameter_iterator_constructors then -- '--all-params' flag: do not filter based on parameters
			
			-- Dispatch calling the command over each found pipeline instance's set of parameters.
			found_any_pipelines = foreach_target_step_name_pipeline_dir_path_returns_disjunction(function(target_step_name, target_step_pipeline_dir_path)
					local any_found
					local hash_dir_path_prefix = target_step_pipeline_dir_path.."/"
					-- we iterate over the hash named directories we collected previously
					local existing_param_hash_dir_lookup = existing_param_hash_dir_lookup_by_target_step_name[target_step_name]
					for hash_dir_name--[[, true]] in pairs(existing_param_hash_dir_lookup) do
						local hash_dir_path = hash_dir_path_prefix .. hash_dir_name
						local pipeline_file_path_prefix = hash_dir_path.."/"
						-- now we iterate over the individual pipeline files within each directory
						for _, pipeline_file_name, pipeline_file_path in entry_index_name_path_in_directory_or_cleanup_iterator(hash_dir_path) do
							-- we read the initial parameters from the pipeline file
							local initial_params = util.read_param_file_new_compat_deserialize(pipeline_file_path, "failed reading initial params from parameter file")
							with_target_step_name_initial_params_pipeline_file_path_f(target_step_name, initial_params, pipeline_file_path)
							any_found = true
						end
					end
					return any_found
				end, nil)
				
		else -- iterate over parameters, filter based on them
			
			-- Dispatch function (iteration body) calling the command over each pipeline's file that given initial parameters apply to.
			-- Returns whether any pipeline matched.
			local call_with_matching_pipelines_returns_any_match = function(target_step_name, target_step_pipeline_dir_path, initial_params)
					local param_coercer = param_coercer_provider(target_step_name)
					local initial_params = param_coercer(initial_params)
					if not initial_params then
						return false
					end
					
					-- check if the directory the instance's pipeline file would be in exists
					local hash_dir_name = features.get_pipeline_hash_dir_name(initial_params)
					local hash_dirs = existing_param_hash_dir_lookup_by_target_step_name[target_step_name]
					if not hash_dirs[hash_dir_name] then -- early return if it doesn't exist
						return
					end
					
					local hash_dir_path = target_step_pipeline_dir_path.."/"..hash_dir_name
					
					-- now check if we were given an id
					local pipeline_id = initial_params['RUN-id']
					if pipeline_id then -- if the id was given, we try loading a specific file
						local pipeline_file_path_prefix = hash_dir_path.."/"
						local pipeline_file_path = pipeline_file_path_prefix..pipeline_id..".txt"
						local exists, file_params = pcall(util.read_param_file_new_compat_deserialize, pipeline_file_path)
						-- if the file exists, also compare the parameters to guard against a hash collision
						if not (exists and util.tables_shallow_equal(file_params, initial_params)) then
							return -- return no match
						end
						-- if everything is ok, call the given predicate
						with_target_step_name_initial_params_pipeline_file_path_f(target_step_name, initial_params, pipeline_file_path)
						return true -- return success
					end
					
					-- if no id was given, we consider every pipeline file in this directory
					local any_found
					-- iterate over all pipeline files
					for _, pipeline_file_name, pipeline_file_path in entry_index_name_path_in_directory_or_cleanup_iterator(hash_dir_path) do
						-- read the parameters
						local file_params = util.read_param_file_new_compat_deserialize(pipeline_file_path)
						-- insert this id, then compare if all parameters are equal
						initial_params['RUN-id'] = file_params['RUN-id']
						if util.tables_shallow_equal(file_params, initial_params) then
							with_target_step_name_initial_params_pipeline_file_path_f(target_step_name, file_params, pipeline_file_path)
							any_found = true
						end
					end
					-- clear the inserted id from initial_params, just in case the table were to be reused
					initial_params['RUN-id'] = nil
					return any_found
				end
			
			-- iterate over parameter iterators
			for i = 1, #parameter_iterator_constructors do
				local parameter_iterator = parameter_iterator_constructors[i]
				-- iterate over initial parameter configurations provided by the iterator,
				-- and filter pipelines based on them
				for initial_params in parameter_iterator() do
					found_any_pipelines = foreach_target_step_name_pipeline_dir_path_returns_disjunction(call_with_matching_pipelines_returns_any_match, initial_params)
						or found_any_pipelines
				end
			end
			-- print a warning message for files that could not be parsed
			parameter_iterator_warning_printer()
			
			-- print a warning message for encountered unrecognized parameters in combinations, if no fallback flag was provided
			param_coercion_warning_printer()
			
		end
		
		if not found_any_pipelines then
			print("No pipelines "
				..(parameter_iterator_constructors and "that match the given parameters " or "")
				..(target_step_name and "towards the given target step " or "")
				.."could be found.")
		end
	end



-- definition of all command structures and their implementation code
local program_command_structures = {
	['auto-setup'] = {any_args_max = 0,
		benmet_util_skip_library_imports = true,
		summary = "clone benmet's own dependencies",
		options = {
			['reliable-commits'] = {is_flag = true, description = "check out tested commit hashes instead of the upstream HEAD"}
		},
		description = "This command clones the repositories used by benmet into sibling directories, unless the modules can already be found in the current package.path .\n- https://github.com/Egor-Skriptunoff/pure_lua_SHA.git provides an implementation for md5 hashing.\n- https://github.com/grafi-tt/lunajson.git provides JSON decoding and encoding.",
		implementation = function(features, util, arguments, options)
			local specify_commit_hash = options['reliable-commits']
			local parent_dir = _G.benmet_get_main_script_dir_path() .. "/.."
			
			local ensure_repo_available = function(module_name, repo_url, repo_name, commit_hash)
					if pcall(require, module_name) then -- module found, early exit
						return
					end
					local command_string = "git clone "..util.in_quotes(repo_url)
					command_string = not commit_hash and command_string
						or command_string .. " --no-checkout"
					assert(util.execute_command_at(command_string, parent_dir))
					if commit_hash then
						-- FIXME: On Windows, combining both into a single shell command (with `&& cd ... &&`) always results in 'path not found' (as if the directory didn't exist yet).
						-- However, this works fine on Linux in features.lua:543: rebuild_step_run_dir .
						-- Windows may exhibit the same issue over there as well.
						assert(util.execute_command_at("git checkout "..util.in_quotes(commit_hash).." --detach", parent_dir.."/"..repo_name))
					end
					return repo_name
				end
			
			local cloned_list = {}
			cloned_list[#cloned_list+1] = ensure_repo_available('pure_lua_SHA.sha2', "https://github.com/Egor-Skriptunoff/pure_lua_SHA.git", "pure_lua_SHA", specify_commit_hash and "304d4121f080e68ef209d3f5fe093e5a955a4978")
			cloned_list[#cloned_list+1] = ensure_repo_available('lunajson', "https://github.com/grafi-tt/lunajson.git", "lunajson", specify_commit_hash and "1dcf3fadd001a7d75673a4354fcbf16ce72c5cdb")
			if #cloned_list == 0 then
				print("all modules found, nothing to clone")
			else
				print("successfully cloned modules: "..table.concat(cloned_list, ", "))
			end
			--assert(util.execute_command_at("git clone "..util.in_quotes(repo_path).." --no-checkout && cd "..util.in_quotes(repo_name).." && git checkout "..util.in_quotes(commit_hash).." --detach", step_run_repos))
		end,
	},
	['add-repo'] = {any_args_min = 1, any_args_max = 1, any_args_name = 'git-url',
		summary = "clone a repository",
		options = {
			['name'] = {description = "a new name for the cloned repository"},
		},
		description = "This command clones the repository from the given git-url into the expected location, which is a directory named 'repos' in the current working directory. This directory will be created if it does not yet exist.",
		implementation = function(features, util, arguments, options)
			local git_url = arguments[1]
			local new_repository_name = options.name[1]
			features.clone_new_repository(git_url, new_repository_name)
		end,
	},
	['step.do'] = {any_args_min = 1, any_args_max = 1, any_args_name = 'step-name',
		summary = "directly execute a particular step command",
		options = {
			['command'] = {required = true, description = "the command to execute"},
			['with-run-id'] = option_with_run_id,
			['param-file'] = option_param_file,
		},
		description = "This command executes the given command of the specified step. The following commands are available:\n  inputs: output the input parameters of this step (with their default values, if any)\n  status: output the run's current status (startable|pending|continuable|finished)\n  start: start a new run (status should be 'startable')\n  cancel: cancel waiting for an asynchronous operation to complete (status should be 'pending')\n  continue: continue if the last asynchronous operation has completed (status should be 'continuable')",
		implementation = function(features, util, arguments, options)
			local target_step_name = arguments[1]
			local command = options.command[1]
			local run_id_override = options['with-run-id'][1]
			local param_file_path = options['param-file'][1]
			
			if command == 'inputs' then -- special case: this is the only command that doesn't require a run directory
				assert(not run_id_override, "command 'inputs' disregards all parameters, incompatible with option '--with-run-id'")
				assert(not param_file_path, "command 'inputs' disregards all parameters, incompatible with option '--param-file'")
				local output, return_status = features.step_query_inputs(target_step_name)
				if not output then
					local target_step_path = relative_path_prefix.."steps/"..target_step_name
					if not util.directory_exists(target_step_path) then
						print("build step '"..target_step_name.."' not found (no directory '"..target_step_path.."')")
					else
						local target_step_run_script_path = target_step_path.."/"..features.get_relative_step_script_path(target_step_name)
						if not util.file_exists(target_step_run_script_path) then
							print("build step '"..target_step_name.."' not available (no run script '"..target_step_run_script_path.."')")
						else
							print("failed to run build step command '"..command.."'")
						end
					end
				else
					print(output)
				end
				return return_status
			end
			
			-- set up initial input parameters
			local initial_params = param_file_path and util.read_param_file_new_compat_deserialize(param_file_path, "failed to parse param-file '"..param_file_path.."'")
				or {}
			initial_params['RUN-id'] = run_id_override or initial_params['RUN-id']
			
			-- calculate the final target run directory and parameters
			local last_params, last_step_run_in_params, last_special_params, last_step_run_hash_params, last_step_run_path, last_run_dir_exists, last_hash_collision
			for step_index, step_count, step_name, original_active_params, error_trace, active_params_for_step, step_run_in_params, special_params, step_run_hash_params, step_run_path, run_dir_exists, hash_collision in features.new_iterate_step_dependency_run_paths(target_step_name, initial_params) do
				assert(not error_trace, error_trace)
				if step_index == step_count then
					last_params, last_step_run_in_params, last_special_params, last_step_run_hash_params, last_step_run_path, last_run_dir_exists, last_hash_collision = active_params_for_step, step_run_in_params, special_params, step_run_hash_params, step_run_path, run_dir_exists, hash_collision
				end
			end
			
			-- try executing the given command
			local program_output, return_status = features.step_invoke_command(target_step_name, command, last_params, last_step_run_in_params, last_special_params, last_step_run_hash_params, last_step_run_path, last_run_dir_exists, last_hash_collision)
			if program_output then
				print(program_output)
			else
				print("failed to run build step command '"..command.."'")
			end
			
			return return_status
		end,
	},
	['step.list-dependencies'] = {any_args_min = 1, any_args_max = 1, any_args_name = 'step-name',
		summary = "display the preceding steps the given step depends on",
		description = "Analyzes the acyclic step dependency graph declared in 'steps/index.txt' and outputs all steps the given step depends on.\n"..dependencies_txt_description,
		implementation = function(features, util, arguments, options)
			local step_name = arguments[1]
			local dependencies = features.step_get_necessary_steps_inclusive(step_name)
			print("step chain to execute step '"..step_name.."': '"..table.concat(dependencies, "'->'").."'")
		end,
	},
	['step.trace-dependencies'] = {any_args_min = 1, any_args_max = 1, any_args_name = 'step-name',
		summary = "display the known run directories a given step run will use",
		options = {
			['with-run-id'] = option_with_run_id,
			['param-file'] = option_param_file,
		},
		description = "Hashes the available input parameters of all steps towards a particular run of a target step and outputs the run directories resulting from this.",
		implementation = function(features, util, arguments, options)
			local target_step_name = arguments[1]
			local run_id_override = options['with-run-id'][1]
			local param_file_path = options['param-file'][1]
			-- set up initial input parameters
			local initial_params = param_file_path and util.read_param_file_new_compat_deserialize(param_file_path, "failed to parse param-file '"..param_file_path.."'")
				or {}
			initial_params['RUN-id'] = run_id_override or initial_params['RUN-id']
			
			-- print the introductory line
			print("step trace to execute step '"..target_step_name.."'"..(param_file_path and " with param_file '"..param_file_path.."'" or "")..(run_id_override and " with RUN-id '"..run_id_override.."'" or "")..":")
			
			-- now we print one line of the format "<step-name>: <run-path> - <validity/error>" for each step.
			-- first is the generic function for printing any such line
			local max_printed_step_index = 0
			local trace_line = function(step_index, step_name, step_run_path, error_trace)
					local line = ". "..step_name..": "
					if step_run_path then
						local validity = error_trace or "valid"
						line = line..step_run_path.." - "..validity
					else
						line = line.."<unavailable>"
						if error_trace then
							line = line.." - "..error_trace
						end
					end
					print(line)
					max_printed_step_index = step_index
				end
			-- and here we iterate over every step and its run path (which is calculated by hashing sequentially aggregated parameters) that leads us to the target step
			-- note: in case of error, we get an error_trace, but the loop continues (with information missing from further entries)
			local last_step_name, last_step_run_path
			for step_index, step_count, step_name, original_active_params, error_trace, active_params_for_step, step_run_in_params, special_params, step_run_hash_params, step_run_path, run_dir_exists, hash_collision in features.new_iterate_step_dependency_run_paths(target_step_name, initial_params) do
				-- because the last step's output is applied at the next iteration, we delay tracing in case of no error
				if last_step_name then
					if original_active_params then -- applying last step's output (if any) worked
						trace_line(step_index-1, last_step_name, last_step_run_path, false)
					else -- applying last step's output (if any) failed
						assert(last_step_name, "unreachable: nothing before the first step should be able to fail, so original active params should always be available")
						trace_line(step_index-1, last_step_name, last_step_run_path, error_trace)
						error_trace = false
					end
				end
				
				if step_run_path and not hash_collision then -- the current step's run path could be computed and is not a hash collision
					if step_index < step_count then -- delay printing to the next iteration in case of errors applying its output
						last_step_name, last_step_run_path = step_name, step_run_path
					else -- nothing left to do, print now
						trace_line(max_printed_step_index+1, step_name, step_run_path, false)
					end
				else -- failed to compute current step's run path or encountered a hash collision
					last_step_name, last_step_run_path = nil, nil
					-- print its step name and the error that caused this
					trace_line(step_index, step_name, step_run_path, error_trace)
				end
			end
		end,
	},
	['pipelines.launch'] = {any_args_name = 'param-files',
		summary = "launch new pipeline instances",
		options = {
			['target'] = {required = true, description = "the target step of the pipeline(s)"}, --TODO(potentially?): could be made optional if we had a default target step in steps/index.txt
			-- TODO (potentially?): also implement 'all-targets' option flag
			['default-params'] = option_pipeline_default_params,
			['params-from-stdin'] = option_pipeline_params_from_stdin,
			-- no-continue: don't continue an encountered already-continuable step
			-- force-relaunch: delete all previously-existing step runs this pipeline incorporates -- would absolutely need dependency collision detection if implemented!
			['ignore-param'] = option_pipeline_ignore_param,
			['accept-param'] = option_pipeline_accept_param,
			['ignore-unrecognized-params'] = option_pipeline_ignore_unrecognized_params,
			['accept-unrecognized-params'] = option_pipeline_accept_unrecognized_params,
		},
		description = "Constructs all parameter combinations within each supplied parameter file (JSON arrays of object entries and multi-value line-based parameter files are supported), and starts a pipeline instance towards the specified target step for each one.\nA pipeline instance is started by iterating over each step in the dependency chain towards the target step. If a step is already finished, it is skipped. If an encountered step finishes synchronously (that is, it doesn't suspend by reporting status 'pending'), the next step is started.\nOn the first suspending step that is encountered, the pipeline is suspended: A `pipeline file` that saves the initial parameters used for that particular instance, extended by a 'RUN-id' property if none was yet assigned, is created. Further pipeline operations on this pipeline instance use this file to retrace the pipeline's steps.\nIf no suspending step is encountered, the pipeline is completed in full.\nBy default, parameter combinations are rejected if they contain properties not consumed by any steps in the target step's dependency chain. This can be configured via options '--(ignore|accept)-param' and '--(ignore|accept)-unrecognized-params'.",
		implementation = function(features, util, arguments, options)
			local target_step_name = options.target[1]
			-- launched pipeline file paths, grouped by launch status then target step name, for user-facing program output
			local launched_pipeline_lists = {}
			local launch_status_lookup_by_error = {}
			
			-- parse parameter iterators; note that option '--all-params' is not available for this command, so would have been rejected during argument parsing
			local parameter_iterator_constructors, parameter_iterator_warning_printer = parse_param_iterator_constructors_and_warning_printers_from_pipeline_arguments_options(features, util, arguments, options)
			assert(#parameter_iterator_constructors > 0, "no parameter files specified, no pipelines launched (pass --default-params to launch a pipeline with default parameters)")
			
			-- option parsing/checking
			local param_coercer_provider, param_coercion_warning_printer = parse_unrecognized_param_coercer_provider_and_warning_printer_from_pipeline_options(features, util, options)
			
			-- actual work
			
			local launch_pipeline = function(target_step_name, initial_params)
					local successful, err_or_finished_or_last_step, last_step_status, was_resumed, pipeline_file_path = xpcall(features.execute_pipeline_steps, debug.traceback, target_step_name, initial_params)
					if not successful then
						print("Error launching pipeline: "..err)
					end
					
					-- assign the pipeline to a collection according to its status
					local launch_status_error
					if not successful then
						launch_status_error = launch_status_lookup_by_error[err_or_finished_or_last_step]
							or {'launch-error', err_or_finished_or_last_step}
						launch_status_lookup_by_error[err_or_finished_or_last_step] = launch_status_error
					end
					local launch_status = launch_status_error
						or err_or_finished_or_last_step == nil and 'launch-skipped-already-exists'
						or err_or_finished_or_last_step == true and 'finished'
						or (not was_resumed) and 'launch-hit-pending'
						or last_step_status == 'continuable' and 'pending' -- we handle suspension the same, no matter if it immediately finished or not
						or last_step_status
					local by_target_step_name = launched_pipeline_lists[launch_status]
						or {}
					launched_pipeline_lists[launch_status] = by_target_step_name
					local list = by_target_step_name[target_step_name]
						or {}
					by_target_step_name[target_step_name] = list
					list[#list+1] = pipeline_file_path
				end
			
			local param_coercer = param_coercer_provider(target_step_name)
			local parsed_anything
			-- iterate over parameter iterators
			for i = 1, #parameter_iterator_constructors do
				local parameter_iterator_constructor = parameter_iterator_constructors[i]
				-- iterate over initial parameter configurations provided by the iterator,
				-- and launch pipelines based on them
				for initial_params in parameter_iterator_constructor() do
					parsed_anything = true
					local coerced_params = param_coercer(initial_params)
					if coerced_params then
						launch_pipeline(target_step_name, coerced_params)
					end
				end
			end
			
			-- count pipelines the other way around for more immediately informative output message
			local launched_anything
			local status_counts_by_target_step_name = {}
			for launch_status, by_target_step_name in pairs(launched_pipeline_lists) do
				for target_step_name, pipeline_path_list in pairs(by_target_step_name) do
					status_counts_by_target_step_name[target_step_name] = (status_counts_by_target_step_name[target_step_name] or 0) + 1
				end
				
				local status_implies_launch = launch_status ~= 'launch-skipped-already-exists'
				launched_anything = launched_anything or status_implies_launch -- I think this is a sensible criteria for the final output message, but maybe not for the return status? Or we could provide a flag for reducing expectations.
			end
			
			
			-- report results back to the user
			local header_message_suffix_by_launch_status = {
				startable = " were launched but seem to have aborted execution (reported status 'startable')",
				pending = " were successfully launched and suspended execution",
				finished = " were successfully launched and finished execution",
				['launch-skipped-already-exists'] = " already existed (with same parameters, including id) and were therefore not launched",
				['launch-hit-pending'] = " were launched but require a step that is still pending",
			}
			for launch_status, by_target_step_name in pairs(launched_pipeline_lists) do
				
				local header_message_suffix
				if type(launch_status) == 'table' then
					header_message_suffix = " failed being launched with the following error: "..tostring(launch_status[2])
					if launch_status[1] ~= 'launch-error' then
						header_message_suffix = header_message_suffix.."\nADDITIONAL ERROR IN COLLECTION LOGIC: unexpected first element '"..tostring(launch_status[1]).."' in launch status tuple (unreachable)"
					end
				else
					launch_status = tostring(launch_status)
					header_message_suffix = header_message_suffix_by_launch_status[launch_status]
						or " were launched and suspended execution, reporting unrecognized status '"..launch_status.."'"
				end
				
				for target_step_name, pipeline_path_list in pairs(by_target_step_name) do
					local only_status_this_target = status_counts_by_target_step_name[target_step_name] == 1
					print((only_status_this_target and "all " or "")..#pipeline_path_list.." pipelines towards step '"..target_step_name.."'"..header_message_suffix)
					-- sort to be lexicographically ascending, then print
					table.sort(pipeline_path_list)
					for i = 1, #pipeline_path_list do
						print("  "..pipeline_path_list[i])
					end
				end
			end
			
			-- print a warning message for files that could not be parsed
			parameter_iterator_warning_printer()
			
			-- print a warning message for encountered unrecognized parameters in combinations, if no fallback flag was provided
			param_coercion_warning_printer()
			
			if not launched_anything then
				print(
					(parsed_anything and "" or "no parameters could be parsed, ")
					.. "no pipelines were launched"
				)
				return 1
			end
		end,
	},
	['pipelines.resume'] = {any_args_name = 'param-files',
		summary = "resume previously-suspended pipeline instances",
		options = pipeline_operation_structure_options,
		description = "Constructs all parameter combinations within each supplied parameter file (JSON arrays of object entries and multi-value line-based parameter files are supported). For each one, resumes all conforming previously-suspended pipeline instances towards the specified target step that are currently ready.\nA pipeline instance is resumed by iterating the dependency chain towards the target step up to the step that previously suspended itself for asynchronous completion. If this step run still reports status 'pending', it is not yet ready, and so the pipeline remains suspended.\nIf it now reports the status 'continuable', it is continued, and the dependency chain is subsequently followed and continued, as detailed for `pipelines.launch`. On the first suspending step that is encountered, this is stopped and the pipeline remains suspended. If no such step is encountered, the pipeline instance is completed and its corresponding `pipeline file` is deleted.\nBy default, parameter combinations are rejected if they contain properties not consumed by any steps in the target step's dependency chain. This can be configured via options '--(ignore|accept)-param' and '--(ignore|accept)-unrecognized-params'.",
		implementation = function(features, util, arguments, options)
			-- selected pipeline file paths, grouped by resumption status then target step name, for user-facing program output
			local resumed_pipeline_lists = {}
			local resumption_status_lookup_by_error = {}
			
			-- perform the operation of resuming selected pipelines
			pipeline_collective_by_individuals_command(features, util, arguments, options, "resume",
				function(target_step_name, initial_params, existing_pipeline_file_path)
					local successful, err_or_finished_or_last_step, last_step_status, was_resumed = xpcall(features.execute_pipeline_steps, debug.traceback, target_step_name, initial_params, existing_pipeline_file_path)
					if not successful then
						print("Error resuming pipeline: "..err_or_finished_or_last_step)
					end
					
					-- assign the pipeline to a collection according to its status
					local resumption_status_error
					if not successful then
						resumption_status_error = resumption_status_lookup_by_error[err_or_finished_or_last_step]
							or {'resumption-error', err_or_finished_or_last_step}
						resumption_status_lookup_by_error[err_or_finished_or_last_step] = resumption_status_error
					end
					local resumption_status = resumption_status_error
						or err_or_finished_or_last_step == true and 'finished'
						or was_resumed and 'continuable' -- we handle and report resuspension the same, no matter whether suspension finished immediately
						or last_step_status
					local by_target_step_name = resumed_pipeline_lists[resumption_status]
						or {}
					resumed_pipeline_lists[resumption_status] = by_target_step_name
					local list = by_target_step_name[target_step_name]
						or {}
					by_target_step_name[target_step_name] = list
					list[#list+1] = existing_pipeline_file_path
				end)
			
			-- count pipelines the other way around too for more immediately informative output message
			local status_counts_by_target_step_name = {}
			for resumption_status, by_target_step_name in pairs(resumed_pipeline_lists) do
				for target_step_name, pipeline_path_list in pairs(by_target_step_name) do
					status_counts_by_target_step_name[target_step_name] = (status_counts_by_target_step_name[target_step_name] or 0) + 1
				end
			end
			
			-- report results back to the user
			local header_message_suffix_by_resumption_status = {
				startable = " were resumed but seem to have aborted execution (reported status 'startable')",
				pending = " were still pending and could not be resumed",
				continuable = " were successfully resumed and resuspended execution",
				finished = " were successfully resumed and finished execution",
			}
			for resumption_status, by_target_step_name in pairs(resumed_pipeline_lists) do
				
				local header_message_suffix
				if type(resumption_status) == 'table' then
					header_message_suffix = " failed being resumed with the following error: "..tostring(resumption_status[2])
					if resumption_status[1] ~= 'resumption-error' then
						header_message_suffix = header_message_suffix.."\nADDITIONAL ERROR IN COLLECTION LOGIC: unexpected first element '"..tostring(launch_status[1]).."' in resumption status tuple (unreachable)"
					end
				else
					resumption_status = tostring(resumption_status)
					header_message_suffix = header_message_suffix_by_resumption_status[resumption_status]
						or " were resumed and resuspended execution, reporting unrecognized status '"..resumption_status.."'"
				end
				
				for target_step_name, pipeline_path_list in pairs(by_target_step_name) do
					local only_status_this_target = status_counts_by_target_step_name[target_step_name] == 1
					print((only_status_this_target and "all " or "")..#pipeline_path_list.." pipelines towards step '"..target_step_name.."'"..header_message_suffix)
					-- sort to be lexicographically ascending, then print
					table.sort(pipeline_path_list)
					for i = 1, #pipeline_path_list do
						print("  "..pipeline_path_list[i])
					end
				end
			end
		end,
	},
	['pipelines.poll'] = {any_args_name = 'param-files',
		summary = "poll the status of previously-suspended pipeline instances",
		options = pipeline_operation_structure_options,
		description = "Constructs all parameter combinations within each supplied parameter file (JSON arrays of object entries and multi-value line-based parameter files are supported). For each one, polls all conforming previously-suspended pipeline instances towards the specified target step.\nA pipeline is polled by iterating the dependency chain towards the target step up to the step that previously suspended itself for asynchronous completion. This step run is queried for its status, which is aggregated into a statistic over all selected pipeline instances reported back by the program.\nBy default, parameter combinations are rejected if they contain properties not consumed by any steps in the target step's dependency chain. This can be configured via options '--(ignore|accept)-param' and '--(ignore|accept)-unrecognized-params'.",
		implementation = function(features, util, arguments, options)
			local pipeline_poll_counts = {}
			
			pipeline_collective_by_individuals_command(features, util, arguments, options, "poll",
				function(target_step_name, initial_params, existing_pipeline_file_path)
					local status = 'finished'
					local at_run_path = false
					-- run through all steps and figure out the params and run path (which is based on a hash of the relevant params subset)
					for step_index, step_count, step_name, original_active_params, error_trace, active_params_for_step, step_run_in_params, special_params, step_run_hash_params, step_run_path, run_dir_exists in features.new_iterate_step_dependency_run_paths(target_step_name, initial_params) do
						if error_trace then
							print(error_trace)
							status = 'status-iteration-failure'
							break
						end
						if step_index < step_count then
							status =
								-- check if the directory exists; note that a hash collision would have resulted in error_trace above
								not run_dir_exists and 'startable'
								-- check execution status
								or features.step_query_status(step_name, step_run_path)
							if status ~= 'finished' then
								status = status
								at_run_path = step_run_path
								break
							end
						end
					end
					
					local by_target_step_name = pipeline_poll_counts[status]
						or {}
					pipeline_poll_counts[status] = by_target_step_name
					local entry = by_target_step_name[target_step_name]
						or {count = 0, by_run_path = {}}
					by_target_step_name[target_step_name] = entry
					entry.count = entry.count + 1
					entry.by_run_path[at_run_path] = true
				end)
			
			for status, by_target_step_name in pairs(pipeline_poll_counts) do
				for target_step_name, entry in pairs(by_target_step_name) do
					print(entry.count.." pipelines '"..status.."' towards step '"..target_step_name.."'")
					-- extract the table keys into a list
					local run_path_list = {}
					for run_path --[[, true]] in pairs(entry.by_run_path) do
						run_path_list[#run_path_list+1] = run_path
					end
					-- sort to be lexicographically ascending
					assert(run_path_list[1] ~= false)
					table.sort(run_path_list)
					-- print
					for i = 1, #run_path_list do
						print("  "..run_path_list[i])
					end
				end
			end
		end,
	},
	['pipelines.cancel'] = {any_args_name = 'param-files',
		summary = "cancel previously-suspended pipeline instances",
		options = pipeline_operation_structure_options_with_error_state_handling,
		description = "Constructs all parameter combinations within each supplied parameter file (JSON arrays of object entries and multi-value line-based parameter files are supported). For each one, cancels all conforming previously-suspended pipeline instances towards the specified target step.\nA pipeline instance is cancelled by iterating the dependency chain towards the target step up to the step that previously suspended itself for asynchronous completion. This step run is cancelled, which aborts any still-running asynchronous operation and reverts the step run back to being 'startable'. Note that the affected run directories, as well as the pipeline files, are not deleted however (in contrast to 'pipelines.discard').\nBy default, parameter combinations are rejected if they contain properties not consumed by any steps in the target step's dependency chain. This can be configured via options '--(ignore|accept)-param' and '--(ignore|accept)-unrecognized-params'.",
		implementation = function(features, util, arguments, options)
			local include_errors = options['include-errors']
			local only_errors = options['only-errors']
			
			local select_pending = not only_errors
			local select_errors = (include_errors or only_errors)
			
			return pipeline_collective_by_individuals_command(features, util, arguments, options, "cancel",
				function(target_step_name, initial_params, existing_pipeline_file_path)
					features.cancel_pipeline_instance(target_step_name, initial_params, select_pending, select_errors, false)
				end)
		end,
	},
	['pipelines.discard'] = {any_args_name = 'param-files',
		summary = "discard previously-suspended pipeline instances",
		options = pipeline_operation_structure_options_with_error_state_handling,
		description = "Constructs all parameter combinations within each supplied parameter file (JSON arrays of object entries and multi-value line-based parameter files are supported). For each one, discards all conforming previously-suspended pipeline instances towards the specified target step.\nA pipeline instance is discarded by iterating the dependency chain towards the target step up to the step that previously suspended itself for asynchronous completion. This step run is cancelled, which aborts any still-running asynchronous operation, and its run directory is deleted. In addition, the corresponding pipeline file is also deleted (in contrast to 'pipelines.cancel').\nBy default, parameter combinations are rejected if they contain properties not consumed by any steps in the target step's dependency chain. This can be configured via options '--(ignore|accept)-param' and '--(ignore|accept)-unrecognized-params'.",
		implementation = function(features, util, arguments, options)
			local include_errors = options['include-errors']
			local only_errors = options['only-errors']
			
			local select_pending = not only_errors
			local select_errors = (include_errors or only_errors)
			
			return pipeline_collective_by_individuals_command(features, util, arguments, options, "discard",
				function(target_step_name, initial_params, existing_pipeline_file_path)
					features.cancel_pipeline_instance(target_step_name, initial_params, select_pending, select_errors, true)
					-- delete the corresponding pipeline file
					local pipeline_file_path = features.get_pipeline_file_path(target_step_name, initial_params)
					util.remove_file(pipeline_file_path)
					print("deleted pipeline file '"..pipeline_file_path.."'")
				end)
		end,
	},
	['commit-ordering'] = {any_args_min = 1, any_args_name = 'commit-source', -- TODO(maybe?): add a flag to do this automatically in a default output file during pipeline execution (.launch/.resume)?
		summary = "export commit orderings to a text file",
		options = {
			['repository'] = {required = true, description = "the repository of which to order commits"},
			['max-strands'] = {description = "the maximum number of combinatorial strands before aborting"},
			['commits'] = {forward_as_arg = true, arg_help_name = 'commits', description = "indicates the subsequent arguments are commit expressions"},
			['from-params'] = {forward_as_arg = true, arg_help_name = 'param-files', description = "indicates subsequent arguments are parameter files holding commit expressions in 'REPO-GITCOMMITHASH-<repository-name>' properties"},
			['from-metrics'] = {forward_as_arg = true, arg_help_name = 'metric-files', description = "indicates subsequent arguments are metric files holding commit expressions in 'REPO-GITCOMMITHASH-<repository-name>' properties"},
			['to-file'] = option_to_file,
		},
		description = "Collect commit expressions in a git repository from several sources, organize their commit hashes into totally-ordered strands and output these as specially-structured JSON, either to a supplied output file path, or to the default path '"..relative_path_prefix.."commit-ordering-<repository-name>.txt'. Note that all previous contents of the output file are overwritten.\nPositional arguments supplied after the flag '--commits' are interpreted as commit expressions, as `git log` would expect them. Examples include regular commit hashes ('c2da14d'), tagged commits of the repository ('v3.0.1'), branch names ('HEAD'), or parent expressions ('HEAD~4').\nPositional arguments supplied after the flag '--from-params' and '--from-metrics' represent file paths to files holding either JSON arrays of object entries, or line-based multi-value parameters or multi-entry metric files respectively (which are both processed identically). They are searched for properties of the name 'REPO-GITCOMMITHASH-<repository>', which can similarly hold arbitrary commit expressions.\nBecause git histories can be arbitrarily complex acyclic graphs, this operation of finding every path has an exponential complexity bound in relation to the number of commits given.\nFurthermore, performance comparisons/charting may only give useful insights within a single strand. Therefore, the default '--max-strands' value is 1, and you should carefully consider your use case before increasing it.",
		implementation = function(features, util, arguments, options)
			-- assert that the repository exists
			local repository_name = options.repository[1]
			local repository_path = relative_path_prefix.."repos/"..repository_name
			if not util.directory_exists(repository_path) then
				error("repository '"..repository_name.."' not found (expected at '"..repository_path.."')")
			end
			local max_strands = options['max-strands'][1]
			max_strands = max_strands and assert(tonumber(max_strands), "non-numeric value '"..max_strands.."' supplied to option '--max-strands'")
				or 1
			
			-- collect arguments into lists
			local commit_expression_list = {}
			local file_path_list = {} -- we read parameter files and metric files the same way
			-- mapping of where to put arguments following these sentinel strings
			local next_args_list_lookup = {
				['--commits'] = commit_expression_list,
				['--from-params'] = file_path_list,
				['--from-metrics'] = file_path_list,
			}
			-- the fist argument must tell us what the following arguments will be
			local current_args_list = next_args_list_lookup[arguments[1]]
			assert(current_args_list, "all arguments must follow one of the source category sentinels: '--commits', '--from-params', or '--from-metrics'")
			-- parse remaining arguments
			for i = 2, #arguments do
				local argument = arguments[i]
				local next_args_list = next_args_list_lookup[argument]
				if next_args_list then
					current_args_list = next_args_list
				else
					current_args_list[#current_args_list+1] = arguments[i]
				end
			end
			
			local output_file_path = options['to-file'][1]
				or relative_path_prefix.."commit-ordering-"..repository_name..".json"
			local output_file_path_already_existed = util.file_exists(output_file_path)
			
			-- read commit expressions from all values in all files
			local param_name = 'REPO-GITCOMMITHASH-'..repository_name
			for i = 1, #file_path_list do
				local file_path = file_path_list[i]
				local successful, file_contents = pcall(util.read_full_file, file_path)
				if successful then
					if string.match(file_contents, "^%w*%[") then -- beginning looks like a JSON array
						local array
						successful, array = pcall(util.json_decode, file_contents)
						if successful then
							local all_entries_had_hash = true
							local no_entries_had_hash = true
							for i = 1, #array do
								local entry_hash = array[i][param_name]
								if entry_hash then
									local entry_hash_type = type(entry_hash) -- could be an array of hashes if it's from a multivalue parameter specification
									if entry_hash_type == 'table' then
										if #entry_hash > 0 then
											no_entries_had_hash = false
											util.list_append_in_place(commit_expression_list, entry_hash)
										else
											all_entries_had_hash = false
										end
									else
										no_entries_had_hash = false
										commit_expression_list[#commit_expression_list+1] = entry_hash
									end
								else
									all_entries_had_hash = false
								end
							end
							if no_entries_had_hash then
								print("Warning: JSON file '"..file_path.."' contained no entries with the expected property '"..param_name.."'")
							elseif not all_entries_had_hash then
								print("Warning: JSON file '"..file_path.."' contained some entries without the expected property '"..param_name.."'")
							end
						else
							print("Warning: failed to parse JSON array from file '"..file_path.."': "..tostring(array))
						end
					else -- file does not seem to contain a JSON array
						local entries, key_lookup
						successful, entries, key_lookup = pcall(util.new_compat_deserialize_multivalue, file_contents)
						if successful then
							local key = key_lookup[param_name]
							local values = key and entries[key]
							values = values and values[2]
							if not values then
								print("Warning: param file '"..file_path.."' did not contain the expected value name '"..param_name.."'")
							else
								util.list_append_in_place(commit_expression_list, values)
							end
						else
							print("Warning: failed to parse param file '"..file_path.."': "..tostring(entries))
						end
					end
				else
					print("Warning: failed to read file '"..file_path.."': "..tostring(file_contents))
				end
			end
			if #commit_expression_list == 0 then
				if #file_path_list == 0 then
					error"no commits given"
				else
					error"no commits found"
				end
			end
			
			-- translate commit expressions into hashes by looking up their commit info, and de-duplicate them
			local commit_expression_list_has = {}
			local commit_info_lookup_by_hash = {}
			local commit_expression_lookup_by_hash = {} -- lookup table of all commit expressions used to get a particular hash
			local commit_hash_list = {}
			local hash_list_has = {}
			for i = 1, #commit_expression_list do
				local commit_expression = commit_expression_list[i]
				if not commit_expression_list_has[commit_expression] then
					commit_expression_list_has[commit_expression] = true
					local successful, hash, timestamp, tags = pcall(util.get_commit_hash_timestamp_tags_of, repository_path, commit_expression)
					if successful then
						if not hash_list_has[hash] then
							hash_list_has[hash] = true
							commit_hash_list[#commit_hash_list+1] = hash
							tags[0] = #tags -- add a "length" field for the JSON encoding library to recognize it as an array, even if empty
							commit_info_lookup_by_hash[hash] = {
								timestamp = timestamp,
								tags = tags,
							}
							commit_expression_lookup_by_hash[hash] = {}
						end
						commit_expression_lookup_by_hash[hash][commit_expression] = true
					else
						print("Warning: failed to look up commit hash of commit expression '"..commit_expression.."'")
					end
				end
			end
			-- turn commit expression lookup tables into lists
			for hash, info_entry in pairs(commit_info_lookup_by_hash) do
				local commit_expressions = util.table_keys_list(commit_expression_lookup_by_hash[hash])
				commit_expressions[0] = #commit_expressions -- add a "length" field for the JSON encoding library to recognize it as an array, even if empty
				info_entry['commit-expressions'] = commit_expressions
			end
			
			-- order commit hashes
			local successful, commit_strands = pcall(features.order_commits_into_strands, repository_path, commit_hash_list, max_strands)
			if not successful then
				if string.match(commit_strands, "given commits are not strictly ordered in a single strand") then
					commit_strands = commit_strands.."\n(supply option --max-strands=<N> if multiple strands are desired/expected)"
				end
				error(commit_strands)
			end
			-- output as json
			local json_payload = {["repository-infos"] = {
				[repository_name] = {
					['commit-info-by-hash'] = commit_info_lookup_by_hash,
					['commit-strands'] = commit_strands,
				}
			}}
			-- write the output file
			util.write_full_file(output_file_path, util.json_encode(json_payload))
			print((output_file_path_already_existed and "overwrote previous" or "wrote new")
				.. " output file '"..output_file_path.."'")
		end,
	},
	['metrics-to-json'] = {any_args_min = 1, any_args_name = 'metric-files',
		summary = "convert metric files into JSON",
		options = {
			['to-file'] = option_to_file,
		},
		description = "Reads all entries from all given metric files and outputs them as a single JSON-array, either to a supplied output file path, or to the default path '"..relative_path_prefix.."exported-metrics.json'. Note that all previous contents of the output file are overwritten.",
		implementation = function(features, util, arguments, options)
			local output_file_path = options['to-file'][1]
				or relative_path_prefix.."exported-metrics.json"
			if util.file_exists(output_file_path) then
				print("overwriting previous file '"..output_file_path.."'")
			end
			local output_file = assert(io.open(output_file_path, 'w+b'))
			
			local all_metrics = {}
			for i = 1, #arguments do
				local metrics = util.read_multientry_param_file_new_compat_deserialize(arguments[i])
				if not metrics then
					error("failed to read metrics file")
				end
				for entry_i = 1, #metrics do
					all_metrics[#all_metrics+1] = metrics[entry_i]
				end
			end
			assert(output_file:write(util.json_encode(all_metrics)))
			assert(output_file:close())
			
			print("finished export to file '"..output_file_path.."'")
		end,
	},
	['test-command'] = {any_args_name = "command-fragments", allow_anything_as_args_verbatim = true,
		summary = "test a command line invocation",
		description = "execute the given command line invocation from Lua and report its return status",
		implementation = function(features, util, arguments, options)
			local command_line = table.concat(arguments, " ")
			util.debug_detail_level = math.max(util.debug_detail_level, 3)
			return util.execute_command(command_line)
		end,
	},
	['test-script'] = {any_args_name = "command-fragments", any_args_min = 1, allow_anything_as_args_verbatim = true,
		summary = "test a Lua script invocation",
		description = "execute the given Lua script inside this Lua state and report its return status as if it were an external program",
		implementation = function(features, util, arguments, options)
			local script_path = arguments[1]
			local script_args = util.table_copy_shallow(arguments)
			table.remove(script_args, 1)
			util.debug_detail_level = math.max(util.debug_detail_level, 3)
			return util.execute_lua_script_as_if_program(script_path, script_args)
		end,
	},
}

return program_command_structures