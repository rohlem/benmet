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
			},
		}; nil defaults to no options>,
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
local option_pipeline_target = {description = "the target step of the pipeline(s)"} --TODO(potentially?): could be made optional if we had a default target step in dependencies.txt
local option_pipeline_all_targets = {is_flag = true, description = "select all pipelines regardless of targets"}
local option_pipeline_all = {is_flag = true, shorthand_for = {'all-targets', 'all-params'}, description = "select all pipelines"}

local option_to_file = {description = "The file to write output to (instead of stdout). Overwrites all previous contents!"}

-- common command structure
local pipeline_operation_structure_options = {
		['target'] = option_pipeline_target,
		['all-targets'] = option_pipeline_all_targets,
		['default-params'] = option_pipeline_default_params,
		['all-params'] = option_pipeline_all_params,
		['all'] = option_pipeline_all,
	}
local pipeline_operation_structure_options_with_error_state_handling = {
		['target'] = option_pipeline_target,
		['all-targets'] = option_pipeline_all_targets,
		['default-params'] = option_pipeline_default_params,
		['all-params'] = option_pipeline_all_params,
		['all'] = option_pipeline_all,
		['include-errors'] = {is_flag = true, description = "also select pipelines with error status"},
		['only-errors'] = {is_flag = true, description = "only select pipelines with error status"},
	}


-- FIXME: Do we want this? If so, where?
local dependencies_txt_description = "This file contains lines of the syntax '<dependers>: <dependees>', where both sides are space-separated, possibly empty lists of step names. Both dependers and dependees may appear in multiple lines. All steps must appear as dependers at least once."



-- common pipeline command implementation helper/structure
local pipeline_collective_by_individuals_command = function(features, util, arguments, options, command_infinitive, with_target_step_name_initial_params_pipeline_file_path_f)
		-- verify arguments and options
		
		local target_step_name = options.target[1]
		if options['all-targets'] then
			assert(not target_step_name, "option '--all-targets' incompatible with selecting individual '--target' step")
		else
			assert(target_step_name, "missing '--target' step specification (or '--all-targets' flag)")
		end
		
		local parameter_files = arguments
		local default_params = options['default-params']
		local initial_param_multivalues = {}
		if options['all-params'] then
			assert(#parameter_files == 0, "option '--all-params' incompatible with parameter file arguments")
			assert(not default_params, "option '--all-params' incompatible with option '--default-params'")
			parameter_files = nil
		else
			if not default_params then
				assert(#parameter_files > 0, "missing parameter files (or option '--all-params' or '--default-params')")
			end
		end
		
		
		-- actual work
		
		-- iterator function over each file name in a directory, deletes the directory if empty
		local file_name_path_in_directory_or_cleanup_iterator__next = function(file_names_in_directory, prev_i)
				if not file_names_in_directory or prev_i >= #file_names_in_directory then return end
				
				local i = prev_i+1
				local file_name = file_names_in_directory[i]
				local file_path = file_names_in_directory.file_path_prefix .. file_name
				return i, file_name, file_path
			end
		local file_name_path_in_directory_or_cleanup_iterator = function(directory_path)
				local exists, file_names_in_directory = pcall(util.files_in_directory, directory_path)
				if not exists then -- the directory doesn't exist
					file_names_in_directory = nil
				elseif #file_names_in_directory == 0 then -- the directory is empty
					util.remove_directory(directory_path)
				else -- the directory contains entries
					file_names_in_directory.file_path_prefix = directory_path.."/"
				end
				return file_name_path_in_directory_or_cleanup_iterator__next, file_names_in_directory, 0
			end
		
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
					for _, step_name, hash_dir_path in file_name_path_in_directory_or_cleanup_iterator(pipelines_path) do
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
		local collect_step_pipeline_dir_lookup__add_to_set = function(hash_dir_name, unused_hash_dir_path, hash_dir_set)
				hash_dir_set[hash_dir_name] = true
				return true
			end
		local collect_step_pipeline_dir_lookup = function(step_name, step_pipeline_dir_path)
				local hash_dir_set = {}
				local any_found
				for _, hash_dir_name in file_name_path_in_directory_or_cleanup_iterator(step_pipeline_dir_path) do
					hash_dir_set[hash_dir_name] = true
					any_found = true
				end
				if any_found then
					existing_param_hash_dir_lookup_by_target_step_name[step_name] = hash_dir_set
					return true
				end
			end
		local any_pipelines_exist = foreach_target_step_name_pipeline_dir_path_returns_disjunction(collect_step_pipeline_dir_lookup)
		
		if not any_pipelines_exist then
			print("No pipelines to "..command_infinitive.." currently exist.")
			return
		end
		
		local found_any_pipelines
		if not parameter_files then -- '--all-params' flag: do not filter based on parameters
			-- Dispatch calling the command over each found pipeline instance's set of parameters.
			-- This contains the main logic of iterating over pipeline files.
			found_any_pipelines = foreach_target_step_name_pipeline_dir_path_returns_disjunction(function(target_step_name, target_step_pipeline_dir_path)
					local any_found
					local hash_dir_path_prefix = target_step_pipeline_dir_path.."/"
					-- we iterate over the hash named directories we collected previously
					local existing_param_hash_dir_lookup = existing_param_hash_dir_lookup_by_target_step_name[target_step_name]
					for hash_dir_name--[[, true]] in pairs(existing_param_hash_dir_lookup) do
						local hash_dir_path = hash_dir_path_prefix .. hash_dir_name
						local pipeline_file_path_prefix = hash_dir_path.."/"
						-- now we iterate over the individual pipeline files within each directory
						for _, pipeline_file_name, pipeline_file_path in file_name_path_in_directory_or_cleanup_iterator(hash_dir_path) do
							-- we read the initial parameters from the pipeline file
							local initial_params = util.read_param_file_new_compat_deserialize(pipeline_file_path)
							with_target_step_name_initial_params_pipeline_file_path_f(target_step_name, initial_params, pipeline_file_path)
							any_found = true
						end
					end
					return any_found
				end, nil)
		else -- filter based on parameters
			-- Dispatch function calling the command over each set of parameters that a particular parameterization of the pipeline applies to.
			-- This contains the main logic of iterating over and checking pipeline files. It's extracted into a function to be triggered in two contexts, see below.
			local particular_pipeline_parameterization = function(target_step_name, target_step_pipeline_dir_path, initial_params)
					-- check if the directory the instance's pipeline file would be in exists
					local hash_dir_name = features.get_pipeline_hash_dir_name(initial_params)
					local hash_dirs = existing_param_hash_dir_lookup_by_target_step_name[target_step_name]
					if hash_dirs[hash_dir_name] then
						local any_found
						local hash_dir_path = target_step_pipeline_dir_path.."/"..hash_dir_name
						local pipeline_file_path_prefix = hash_dir_path.."/"
						-- now check if we were given an id
						local pipeline_id = initial_params['RUN-id']
						if pipeline_id then -- if the id was given, we try loading a specific file
							local pipeline_file_path = pipeline_file_path_prefix..pipeline_id..".txt"
							local exists, file_params = pcall(util.read_param_file_new_compat_deserialize, pipeline_file_path)
							-- if the file exists, also compare the parameters to guard against a hash collision
							if exists and util.tables_shallow_equal(file_params, initial_params) then
								with_target_step_name_initial_params_pipeline_file_path_f(target_step_name, initial_params, pipeline_file_path)
								any_found = true
							end
						else -- if no id was given, we consider every pipeline file in this directory
							-- iterate over all pipeline files
							for _, pipeline_file_name, pipeline_file_path in file_name_path_in_directory_or_cleanup_iterator(hash_dir_path) do
								-- read the parameters
								local file_params = util.read_param_file_new_compat_deserialize(pipeline_file_path)
								-- set the id equal, then compare if all parameters are equal
								initial_params['RUN-id'] = file_params['RUN-id']
								if util.tables_shallow_equal(file_params, initial_params) then
									with_target_step_name_initial_params_pipeline_file_path_f(target_step_name, file_params, pipeline_file_path)
									any_found = true
								end
							end
							-- clear the id from initial_params, just in case the table were to be reused
							initial_params['RUN-id'] = nil
						end
						return any_found
					end
				end
			
			if default_params then -- handle '--default-params' flag case first
				found_any_pipelines = foreach_target_step_name_pipeline_dir_path_returns_disjunction(particular_pipeline_parameterization, {})
					or found_any_pipelines
			end
			-- iterate over multivalue parameter files and combinations, and filter based on them
			local failed_parsing_parameter_files = {}
			for i = 1, #parameter_files do
				local param_file = parameter_files[i]
				local parsing_succeeded, initial_params_multivalue = pcall(util.read_multivalue_param_file_new_compat_deserialize, param_file)
				if parsing_succeeded then
					for initial_params in util.all_combinations_of_multivalues(initial_params_multivalue) do
						found_any_pipelines = foreach_target_step_name_pipeline_dir_path_returns_disjunction(particular_pipeline_parameterization, initial_params)
							or found_any_pipelines
					end
				else
					failed_parsing_parameter_files[#failed_parsing_parameter_files+1] = param_file
				end
			end
			-- warning message for files that could not be parsed
			if #failed_parsing_parameter_files > 0 then
				print("The following parameter files could not be parsed (were ignored):")
				for i = 1, #failed_parsing_parameter_files do
					print("- "..failed_parsing_parameter_files[i])
				end
				print("Please manually verify the existence and contents of these files.")
			end
		end
		
		if not found_any_pipelines then
			print("No pipelines "
				..(parameter_files and "that match the given parameters " or "")
				..(target_step_name and "towards the given target step " or "")
				.."could be found.")
		end
	end



-- definition of all command structures and their implementation code
local program_command_structures = {
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
						local target_step_run_script_path = target_step_path.."/run.lua"
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
			local last_params, last_step_run_in_params, last_special_params, last_step_run_hash_params, last_step_run_path, last_cache_hit, last_hash_collision
			for step_index, step_count, step_name, original_active_params, error_trace, active_params_for_step, step_run_in_params, special_params, step_run_hash_params, step_run_path, cache_hit, hash_collision in features.new_iterate_step_dependency_run_paths(target_step_name, initial_params) do
				assert(not error_trace, error_trace)
				if step_index == step_count then
					last_params, last_step_run_in_params, last_special_params, last_step_run_hash_params, last_step_run_path, last_cache_hit, last_hash_collision = active_params_for_step, step_run_in_params, special_params, step_run_hash_params, step_run_path, cache_hit, hash_collision
				end
			end
			
			-- try executing the given command
			local program_output, return_status = features.step_invoke_command(target_step_name, command, last_params, last_step_run_in_params, last_special_params, last_step_run_hash_params, last_step_run_path, last_cache_hit, last_hash_collision)
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
		description = "Analyzes the acyclic step dependency graph declared in 'steps/dependencies.txt' and outputs all steps the given step depends on.\n"..dependencies_txt_description,
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
			for step_index, step_count, step_name, original_active_params, error_trace, active_params_for_step, step_run_in_params, special_params, step_run_hash_params, step_run_path, cache_hit, hash_collision in features.new_iterate_step_dependency_run_paths(target_step_name, initial_params) do
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
			['target'] = {required = true, description = "the target step of the pipeline(s)"}, --TODO(potentially?): could be made optional if we had a default target step in dependencies.txt
			-- TODO (potentially?): also implement 'all-targets' option flag
			['default-params'] = option_pipeline_default_params,
			-- no-continue: don't continue an encountered already-continuable step
			-- force-relaunch: delete all previously-existing step runs this pipeline incorporates -- would absolutely need dependency collision detection if implemented!
		},
		description = "Constructs all parameter combinations within each supplied multi-value parameter file, and starts a pipeline instance towards the specified target step for each one.\nA pipeline instance is started by iterating over each step in the dependency chain towards the target step. If a step is already finished, it is skipped. If an encountered step finishes synchronously (that is, it doesn't suspend by reporting status 'pending'), the next step is started.\nOn the first suspending step that is encountered, the pipeline is suspended: A `pipeline file` that saves the initial parameters used for that particular instance, extended by a 'RUN-id' property if none was yet assigned, is created. Further pipeline operations on this pipeline instance use this file to retrace the pipeline's steps.\nIf no suspending step is encountered, the pipeline is completed in full.",
		implementation = function(features, util, arguments, options)
			local parameter_files = arguments
			local target_step_name = options.target[1]
			
			local launched_anything
			local launch_pipeline = function(target_step_name, initial_params)
					local successful, err = xpcall(features.execute_pipeline_steps, debug.traceback, target_step_name, initial_params)
					if successful then
						launched_anything = true
					else
						print("Error launching pipeline: "..err)
					end
				end
			
			if options['default-params'] then
				launch_pipeline(target_step_name, {})
			else
				assert(#parameter_files > 0, "no parameter files specified, no pipelines launched (pass --default-params to launch a pipeline with default parameters)")
			end
			local failed_parsing_parameter_files = {}
			for i = 1, #parameter_files do
				local param_file = parameter_files[i]
				local parsing_succeeded, initial_params_multivalue = pcall(util.read_multivalue_param_file_new_compat_deserialize, param_file)
				if parsing_succeeded then
					for initial_params in util.all_combinations_of_multivalues(initial_params_multivalue) do
						launch_pipeline(target_step_name, initial_params)
					end
				else
					failed_parsing_parameter_files[#failed_parsing_parameter_files+1] = param_file
				end
			end
			
			if #failed_parsing_parameter_files > 0 then
				print("The following parameter files could not be parsed (were ignored):")
				for i = 1, #failed_parsing_parameter_files do
					print("- "..failed_parsing_parameter_files[i])
				end
				print("Please manually verify the existence and contents of these files.")
			end
			
			return launched_anything and 0 or 1
		end,
	},
	['pipelines.resume'] = {any_args_name = 'param-files',
		summary = "resume previously-suspended pipeline instances",
		options = pipeline_operation_structure_options,
		description = "Constructs all parameter combinations within each supplied multi-value parameter file. For each one, resumes all conforming previously-suspended pipeline instances towards the specified target step that are currently ready.\nA pipeline instance is resumed by iterating the dependency chain towards the target step up to the step that previously suspended itself for asynchronous completion. If this step run still reports status 'pending', it is not yet ready, and so the pipeline remains suspended.\nIf it now reports the status 'continuable', it is continued, and the dependency chain is subsequently followed and continued, as detailed for `pipelines.launch`. On the first suspending step that is encountered, this is stopped and the pipeline remains suspended. If no such step is encountered, the pipeline instance is completed and its corresponding `pipeline file` is deleted.",
		implementation = function(features, util, arguments, options)
			return pipeline_collective_by_individuals_command(features, util, arguments, options, "resume",
				features.execute_pipeline_steps--[[(target_step_name, initial_params, existing_pipeline_file_path)]])
		end,
	},
	['pipelines.poll'] = {any_args_name = 'param-files',
		summary = "poll the status of previously-suspended pipeline instances",
		options = pipeline_operation_structure_options,
		description = "Constructs all parameter combinations within each supplied multi-value parameter file. For each one, polls all conforming previously-suspended pipeline instances towards the specified target step.\nA pipeline is polled by iterating the dependency chain towards the target step up to the step that previously suspended itself for asynchronous completion. This step run is queried for its status, which is aggregated into a statistic over all selected pipeline instances reported back by the program.",
		implementation = function(features, util, arguments, options)
			local pipeline_poll_counts = {}
			
			pipeline_collective_by_individuals_command(features, util, arguments, options, "poll",
				function(target_step_name, initial_params, existing_pipeline_file_path)
					local status = 'finished'
					local at_run_path = false
					-- run through all steps and figure out the params and run path (which is based on a hash of the relevant params subset)
					for step_index, step_count, step_name, original_active_params, error_trace, active_params_for_step, step_run_in_params, special_params, step_run_hash_params, step_run_path, cache_hit in features.new_iterate_step_dependency_run_paths(target_step_name, initial_params) do
						if error_trace then
							print(error_trace)
							status = 'status-iteration-failure'
							break
						end
						if step_index < step_count then
							status =
								-- check if the directory exists; note that a hash collision would have resulted in error_trace above
								not cache_hit and 'startable'
								-- check execution status
								or features.step_query_status(step_name, step_run_path)
							if status ~= 'finished' then
								status = status
								at_run_path = step_run_path
								break
							end
						end
					end
					
					local by_status = pipeline_poll_counts[status]
						or {}
					pipeline_poll_counts[status] = by_status
					local entry = by_status[target_step_name]
						or {count = 0, by_run_path = {}}
					by_status[target_step_name] = entry
					entry.count = entry.count + 1
					entry.by_run_path[at_run_path] = true
				end)
			
			for status, by_status in pairs(pipeline_poll_counts) do
				for step_name, entry in pairs(by_status) do
					print(entry.count.." pipelines '"..status.."' towards step '"..step_name.."'")
					if step_name ~= 'finished' then -- if the pipeline isn't finished, print the run paths at which they are currently
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
			end
		end,
	},
	['pipelines.cancel'] = {any_args_name = 'param-files',
		summary = "cancel previously-suspended pipeline instances",
		options = pipeline_operation_structure_options_with_error_state_handling,
		description = "Constructs all parameter combinations within each supplied multi-value parameter file. For each one, cancels all conforming previously-suspended pipeline instances towards the specified target step.\nA pipeline instance is cancelled by iterating the dependency chain towards the target step up to the step that previously suspended itself for asynchronous completion. This step run is cancelled, which aborts any still-running asynchronous operation and reverts the step run back to being 'startable'. Note that the affected run directories, as well as the pipeline files, are not deleted however (in contrast to 'pipelines.discard').",
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
		description = "Constructs all parameter combinations within each supplied multi-value parameter file. For each one, discards all conforming previously-suspended pipeline instances towards the specified target step.\nA pipeline instance is discarded by iterating the dependency chain towards the target step up to the step that previously suspended itself for asynchronous completion. This step run is cancelled, which aborts any still-running asynchronous operation, and its run directory is deleted. In addition, the corresponding pipeline file is also deleted (in contrast to 'pipelines.cancel').",
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
		description = "Collect commit expressions in a git repository from several sources, organize their commit hashes into totally-ordered strands and output these in a multi-entry, multi-value structure, either to a supplied output file path, or to the default path '"..relative_path_prefix.."commit-ordering-<repository-name>.txt'. Note that all previous contents of the output file are overwritten.\nPositional arguments supplied after the flag '--commits' are interpreted as commit expressions, as `git log` would expect them. Examples include regular commit hashes ('c2da14d'), tagged commits of the repository ('v3.0.1'), branch names ('HEAD'), or parent expressions ('HEAD~4').\nPositional arguments supplied after the flag '--from-params' and '--from-metrics' represent file paths to multi-value parameter files and multi-entry metric files respectively (which are both processed identically). They are searched for properties of the name 'REPO-GITCOMMITHASH-<repository>', which can similarly hold arbitrary commit expressions.\nBecause git histories can be arbitrarily complex acyclic graphs, this operation of finding every path has an exponential complexity bound in relation to the number of commits given.\nFurthermore, performance comparisons/charting may only give useful insights within a single strand. Therefore, the default '--max-strands' value is 1, and you should carefully consider your use case before increasing it.",
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
				local successful, entries, key_lookup = pcall(util.read_multivalue_param_file_new_compat_deserialize, file_path)
				if successful then
					local key = key_lookup[param_name]
					local values = key and entries[key]
					values = values and values[2]
					if not values then
						print("Warning: file '"..file_path.."' did not contain the expected value name '"..key.."'")
					else
						for i = 1, #values do
							commit_expression_list[#commit_expression_list+1] = values[i]
						end
					end
				else
					print("Warning: failed to read file '"..file_path.."'")
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
}

return program_command_structures