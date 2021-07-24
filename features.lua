--[[
This file implements all "actual logic" of benmet, using platform specific functionality from module `benmet.util`.
--]]

-- IMPORTANT GLOBAL ASSUMPTION THAT SHOULD BE DOCUMENTED SOMEWHERE:
-- If a step's run directory contains "params_out.txt", it is in a finished status.

local relative_path_prefix = assert(_G.benmet_relative_path_prefix)

local util = require "benmet.util"
util.debug_detail_level = 20
local incdl = util.incdl
local decdl = util.decdl


local features = {}


-- git (repository) features
-- clones a repository to be used under the given name (or the origin's name) in the current workspace
function features.clone_new_repository(git_url, new_repository_name)
	local repositories_path = relative_path_prefix.."repos"
	new_repository_name = new_repository_name or ""
	util.logprint("cloning repository from '"..git_url.."'")
	incdl()
		util.ensure_directory(repositories_path)
		-- note: `git clone` already refuses cloning into non-empty directories, so we don't need to check existence/state of the immediate target directory
		assert(util.execute_command_at("git clone "..util.in_quotes(git_url).." "..new_repository_name, repositories_path))
	decdl()
end


-- git features: lookup commit hashes resulting from commit expressions
-- By default we assume that everything is a commit expression.
-- Only what we queried via "git log" is considered a hash, which is cached here.
local git_repository_commit_expr_is_hash_lookup_by_name = {}
-- lookup a given commit expression in a given repository, cached for the execution of the program
local lookup_git_repository_commit_expr_hash = function(repo_name, commit_expr)
	local commit_expr_hash_lookup = git_repository_commit_expr_is_hash_lookup_by_name[repo_name]
	if not commit_expr_hash_lookup then -- if we haven't looked this repository up yet, `git fetch --all`
		commit_expr_hash_lookup = {}
		git_repository_commit_expr_is_hash_lookup_by_name[repo_name] = commit_expr_hash_lookup
		
		local repo_path = relative_path_prefix.."repos/"..repo_name
		assert(util.execute_command_at("git fetch --all", repo_path))
	end
	
	local commit_hash = commit_expr_hash_lookup[commit_expr]
	if not commit_hash then -- look up the commit expression and add it to our cache
		local repo_path = relative_path_prefix.."repos/"..repo_name
		commit_hash = assert(util.get_commit_hash_of(repo_path, commit_expr))
		
		commit_expr_hash_lookup[commit_expr] = commit_hash
	end
	return commit_hash
end



-- step features: index file
local step_script_path_lookup
local step_immediate_dependency_lookup
-- parses the workspace's 'steps/index.txt' file into one lookup table of script path by step name
-- and one lookup table of direct dependency lists by step name
local get_step_script_path_and_immediate_dependency_lookups = function()
	-- if we already read them, return them cached
	if step_script_path_lookup then
		return step_script_path_lookup, step_immediate_dependency_lookup
	end
	-- otherwise read and parse the index file
	local index_spec = util.read_full_file(relative_path_prefix.."steps/index.txt")
	step_script_path_lookup = {}
	step_immediate_dependency_lookup = {}
	for line in string.gmatch(index_spec, "[^\n]+") do -- for every non-empty line
		local dependers, dependees = string.match(line, "^([^:]*):([^:]*)")
		if dependers then -- if the pattern doesn't match, we ignore the line
			local dependees_list = {}
			for dependee in string.gmatch(dependees, "%S+") do -- dependees are space-separated, possibly empty
				dependees_list[#dependees_list+1] = dependee
			end
			for depender_string in string.gmatch(dependers, "%S+") do -- dependers are space-separated, possibly empty
				-- split depender in step name and script path
				local depender, depender_script_path = string.match(depender_string, "^([^/]*)/(.*)")
				if not depender then -- check it conforms to this format
					error("invalid format of steps/index.txt: depender '"..depender.."' does not follow the format '<step-name>/<script-path>'")
				end
				local prev_script_path = step_script_path_lookup[depender]
				if step_script_path_lookup[depender] then -- check for double-assignment
					assert(prev_script_path == depender_script_path, "invalid format of steps/index.txt: step '"..depender.."' listed with different step scripts: first with '"..prev_script_path.."', then with '"..depender_script_path.."'")
				else
					step_script_path_lookup[depender] = depender_script_path
				end
				-- set or append the dependencies
				if not step_immediate_dependency_lookup[depender] then
					step_immediate_dependency_lookup[depender] = util.table_copy_shallow(dependees_list)
				else
					step_immediate_dependency_lookup[depender] = util.list_append_in_place(step_immediate_dependency_lookup[depender], dependees_list)
				end
			end
		end
	end
	return step_script_path_lookup, step_immediate_dependency_lookup
end

-- returns the script path for the given step name, relative to its step directory
local get_relative_step_script_path = function(step_name)
	local step_script_path_lookup = assert(get_step_script_path_and_immediate_dependency_lookups())
	return step_script_path_lookup[step_name]
end
features.get_relative_step_script_path = get_relative_step_script_path



-- step features: direct/simple command execution
-- environment overrides for the Lua scripts we execute (we need variants by working directory)
local benmet_lua_env_override_table_by_relative_step_dir_path
local function get_benmet_lua_env_override_table_by_relative_step_dir_path()
	_G.benmet_ensure_package_path_entries_are_absolute()
	benmet_lua_env_override_table_by_relative_step_dir_path = {
		["./"] = {
				LUA_PATH = package.path, -- "./steps/<step-name>" is exactly 2 nested
			},
		["../../"] = {
				LUA_PATH = (util.string_ends_with(package.path, ";") and package.path
						or package.path .. ";")
					.. util.prefixed_only_relative_path_templates_in_string(package.path, "../../"), -- "./runs/<param-hash>" is exactly 2 nested from its step dir
			},
	}
	-- replace self by simpler get-function
	get_benmet_lua_env_override_table_by_relative_step_dir_path = function() return benmet_lua_env_override_table_by_relative_step_dir_path end
	return benmet_lua_env_override_table_by_relative_step_dir_path
end
-- directly invoke the given command of the given step at the given path (step run directory)
local step_invoke_command_raw = function(step_name, at_path, command, relative_step_dir_path)
	local step_script_path = get_relative_step_script_path(step_name)
	local env_override_table = get_benmet_lua_env_override_table_by_relative_step_dir_path()[relative_step_dir_path]
	local success, exit_type, return_status, program_output, error_details
	if util.string_ends_with(step_script_path, ".lua") then
		if not _G.benmet_launch_steps_as_child_processes then
			local prev_lua_path = util.getenv("LUA_PATH")
			util.setenv("LUA_PATH", env_override_table.LUA_PATH)
			success, exit_type, return_status, program_output, error_details = util.execute_lua_script_as_if_program(relative_path_prefix.."steps/"..step_name.."/"..step_script_path, {command}, at_path)
			util.setenv("LUA_PATH", prev_lua_path)
		else
			success, exit_type, return_status, program_output = util.execute_command_with_env_override_at(util.in_quotes(util.get_lua_program()).." "..util.in_quotes(relative_step_dir_path..step_script_path).." "..command, env_override_table, at_path)
		end
	else
		success, exit_type, return_status, program_output = util.execute_command_with_env_override_at(util.in_quotes(relative_step_dir_path..step_script_path).." "..command, env_override_table, at_path)
	end
	return success and program_output, return_status, error_details
end

-- directly invoke command 'inputs' of the given step
local step_query_inputs_uncached = function(step_name)
	--assert(util.file_exists(relative_path_prefix.."steps/"..step_name.."/"..get_step_script_path_and_immediate_dependency_lookups()[step_name]), "step '"..step_name.."' is missing step script, failed to query its input parameters")
	return step_invoke_command_raw(step_name, relative_path_prefix.."steps/"..step_name, 'inputs', "./")
end
local step_query_inputs_cache = {}
-- query the results of invoking command 'inputs' of the given step, potentially from cache
function features.step_query_inputs(step_name)
	local inputs = step_query_inputs_cache[step_name]
	if not inputs then
		inputs = step_query_inputs_uncached(step_name)
		step_query_inputs_cache[step_name] = inputs
	end
	return inputs
end
local step_query_inputs_template_table_cache = {}
-- query and parse the results of invoking command 'inputs' of the given step, potentially from cache
function features.step_query_inputs_template_table(step_name)
	local inputs_template = step_query_inputs_template_table_cache[step_name]
	if not inputs_template then
		inputs_template = util.new_compat_deserialize(assert(features.step_query_inputs(step_name), "failed to query input params of step '"..step_name.."'"))
		step_query_inputs_template_table_cache[step_name] = inputs_template
	end
	return inputs_template
end

-- query the status of the given step run
-- TODO (maybe?): intelligent caching - this means invalidating the cache every time the status might change
function features.step_query_status(step_name, step_run_path)
	-- quick path: if a file params_out.txt exists, the step run is finished -- TODO: maybe remove once we have caching?
	if util.file_exists(step_run_path.."/params_out.txt") then
		return 'finished'
	end
	-- execute the run script which determines the run's status
	local output = step_invoke_command_raw(step_name, step_run_path, 'status', "../../")
	assert(output, "failed to query status of step '"..step_name.."' for run path '"..step_run_path.."'")
	return type(output) == 'string' and util.cut_trailing_space(output)
		or output
end



-- step features: interpreting declared step inputs
-- interprets the given step input parameters into special_params table and effective default values
function features.step_split_inputs_table_into_special_params_default_values(step_inputs_table)
	-- result tables
	local requested_repos_lookup = {}
	local special_params = {
			requested_repos_lookup = requested_repos_lookup,
		}
	local default_values = {}
	-- look through every entry
	for k,v in pairs(step_inputs_table) do
		local is_repo_path = util.string_starts_with(k, 'REPO-PATH-')
		local is_repo_gitcommithash = (not is_repo_path) and util.string_starts_with(k, 'REPO-GITCOMMITHASH-')
		local repo_name = is_repo_path or is_repo_gitcommithash
		if repo_name then
			requested_repos_lookup[repo_name] = true
			if is_repo_gitcommithash then
				default_values[k] = is_repo_gitcommithash and v or nil
			end
		elseif k == 'RUN-id' then
			special_params.wants_run_id = true
		elseif k == 'RUN-hostname' then
			special_params.wants_hostname = true
		elseif k == 'RUN-all-params' then
			special_params.wants_all_params = true
		elseif k == 'SPECIAL-line-based-params-in' then
			special_params.wants_line_based_params_in = true
		else
			if not util.string_starts_with(k, 'PARAM-') then
				util.logprint("warning: unrecognized non-PARAM step input parameter: "..k)
			end
			default_values[k] = v
		end
	end
	
	return special_params, default_values
end
local step_query_inputs_special_params_default_values_cache = {}
-- cached lookup of special_params and default_values tables for a given step name
function features.step_query_inputs_special_params_default_values(step_name)
	local entry = step_query_inputs_special_params_default_values_cache[step_name]
	local special_params, default_values
	if entry then
		special_params, default_values = entry[1], entry[2]
	else
		special_params, default_values = features.step_split_inputs_table_into_special_params_default_values(features.step_query_inputs_template_table(step_name))
		entry = {special_params, default_values}
		step_query_inputs_special_params_default_values_cache[step_name] = entry
	end
	return special_params, default_values
end

-- constructs a lookup table of the effective (non-special, user-configurable) input parameters from given special_params and default_values of a step
local step_construct_effective_inputs_lookup_from_special_params_default_values_uncached = function(special_params, default_values)
	local effective_inputs_lookup = {}
	
	for k--[[,v]] in pairs(default_values) do
		effective_inputs_lookup[k] = true
	end
	
	for repo_name--[[,v]] in pairs(special_params.requested_repos_lookup) do
		effective_inputs_lookup['REPO-GITCOMMITHASH-'..repo_name] = true
	end
	
	effective_inputs_lookup['RUN-id'] = special_params.wants_run_id or nil
	effective_inputs_lookup['RUN-hostname'] = special_params.wants_hostname or nil
	
	return effective_inputs_lookup
end
local step_query_effective_inputs_lookup_cache = {}
-- queries the effective (non-special, user-configurable) input parameters of a given step (potentially from cache)
function features.step_query_effective_inputs_lookup(step_name)
	local effective_inputs = step_query_effective_inputs_lookup_cache[step_name]
	if not effective_inputs then
		effective_inputs = step_construct_effective_inputs_lookup_from_special_params_default_values_uncached(features.step_query_inputs_special_params_default_values(step_name))
		step_query_effective_inputs_lookup_cache[step_name] = effective_inputs
	end
	return effective_inputs
end



-- step features: dependencies
-- transitively constructs the dependency graph required for the given step
-- errors in the case of cycles
-- technically we could save some time by only building the target step's list instead of the full graph's transitive dependencies if we know the program never queries different targets during one execution
local step_get_necessary_steps__necessary_steps_for_cache = {}
function features.step_get_necessary_steps(target_step_name)
	assert(target_step_name)
	local necessary_steps_for = step_get_necessary_steps__necessary_steps_for_cache -- the list of all transitive dependees for each depender step
	local --[[step_script_paths]]_, step_immediate_dependency_lists = get_step_script_path_and_immediate_dependency_lookups()
	
	-- stack-based children-first graph traversal
	local resolving_stack = {target_step_name} -- graph traversal stack / work-left stack
	local is_depender = {} -- whether encountering a step as a dependee would mean a circular dependency
	local finished_resolving_for = {} -- whether we've fully resolved a step's dependees for a given depender
	while #resolving_stack > 0 do
		local top = resolving_stack[#resolving_stack]
		local transitive_dependees_of_top = not is_depender[top] and necessary_steps_for[top]
		is_depender[top] = true
		if transitive_dependees_of_top then -- add the transitive dependees of top
			for r_i = #resolving_stack-1, 1, -1 do -- iterate over the resolving_stack before top in reverse (which holds all dependers on top that are dependencies of the target step)
				local r = resolving_stack[r_i]
				local finished_resolving_for_r = finished_resolving_for[r]
				if finished_resolving_for_r[top] then -- if r has already resolved top, then everything before it on the resolving_stack has as well
					break
				end
				for d_i = 1, #transitive_dependees_of_top do -- for every transitive dependee of top, ensure it is in r's list of transitive dependencies
					local dependee = transitive_dependees_of_top[d_i]
					if not finished_resolving_for_r[dependee] then -- r still needs to get dependee added to its transitive dependencies
						if is_depender[dependee] then
							error("caught in a dependency loop: encountered unresolved '"..dependee.."' while resolving '"..table.concat(resolving_stack, "'->'").."'")
						end
						local r_steps = necessary_steps_for[r]
						r_steps[#r_steps+1] = dependee
						finished_resolving_for_r[dependee] = true -- flag that r has now recognized dependee as a transitive dependency
					end
				end
				finished_resolving_for_r[top] = true
			end
			is_depender[top] = nil
			resolving_stack[#resolving_stack] = nil
		else -- this means the top's next immediate dependency should be pushed onto the stack, or if none remain it itself should be popped off it
			necessary_steps_for[top] = necessary_steps_for[top] or {}
			finished_resolving_for[top] = finished_resolving_for[top] or {}
			local immediate_dependees_of_top = step_immediate_dependency_lists[top]
			if not immediate_dependees_of_top then
				error("missing dependency declaration of step '"..top.."': does not appear on the left-hand side of a line in 'steps/index.txt'")
			end
			
			local unresolved_immediate_dependee
			for d_i = 1, #immediate_dependees_of_top do -- find an unresolved immediate dependee
				local dependee = immediate_dependees_of_top[d_i]
				local finished_resolving_for_top = finished_resolving_for[top]
				if not finished_resolving_for_top[dependee] then
					unresolved_immediate_dependee = dependee
					break
				end
			end
			if unresolved_immediate_dependee then
				if is_depender[unresolved_immediate_dependee] then -- check for cycle
					error("caught in a dependency loop: encountered unresolved '"..unresolved_immediate_dependee.."' while resolving '"..table.concat(resolving_stack, "'->'").."'")
				end
				resolving_stack[#resolving_stack+1] = unresolved_immediate_dependee -- push the unresolved immediate dependee onto the resolving_stack
			else -- there are no unresolved immediate dependees of top left
				is_depender[top] = nil
				resolving_stack[#resolving_stack] = nil
				for r_i = 1, #resolving_stack do -- add top itself to the dependees of all other resolving_stack entries that didn't yet have it
					local r = resolving_stack[r_i]
					local finished_resolving_for_r = finished_resolving_for[r]
					if not finished_resolving_for_r[top] then
						finished_resolving_for_r[top] = true
						local necessary_steps_for_r = necessary_steps_for[r]
						necessary_steps_for_r[#necessary_steps_for_r+1] = top
					end
				end
			end
		end
	end
	
	return necessary_steps_for[target_step_name]
end

-- small wrapper around features.step_get_necessary_steps that adds the target step itself to the list, since half our uses actually need this
function features.step_get_necessary_steps_inclusive(target_step_name)
	local steps = util.table_copy_shallow(features.step_get_necessary_steps(target_step_name))
	steps[#steps+1] = target_step_name
	return steps
end


local step_query_effective_inputs_lookup_union_cache = {}
local step_query_effective_inputs_lookup_union = function(target_step_name)
	local effective_inputs_lookup_union = step_query_effective_inputs_lookup_union_cache[target_step_name]
	if not effective_inputs_lookup_union then
		-- gather dependency step names
		local target_step_dependency_list = features.step_get_necessary_steps_inclusive(target_step_name)
		effective_inputs_lookup_union = {}
		for i = 1, #target_step_dependency_list do
			local step_name = target_step_dependency_list[i]
			local effective_inputs_lookup = features.step_query_effective_inputs_lookup(step_name)
			effective_inputs_lookup_union = util.table_patch_in_place(effective_inputs_lookup_union, effective_inputs_lookup)
		end
		step_query_effective_inputs_lookup_union_cache[target_step_name] = effective_inputs_lookup_union
	end
	return effective_inputs_lookup_union
end
features.step_query_effective_inputs_lookup_union = step_query_effective_inputs_lookup_union
-- return a list of the subset of the given parameters that applies to (is an input of) neither the given target step nor any of its dependencies
function features.list_parameters_nonapplicable_to_target_step_and_dependencies(target_step_name, initial_params)
	local effective_inputs_lookup_union = step_query_effective_inputs_lookup_union(target_step_name)
	-- create a list holding the keys only present in initial_params
	local ineffective_inputs_lookup = {}
	for k--[[,v]] in pairs(initial_params) do
		if effective_inputs_lookup_union[k] == nil then
			ineffective_inputs_lookup[#ineffective_inputs_lookup+1] = k
		end
	end
	return ineffective_inputs_lookup
end



-- step features: run status inspection/checking
-- returns if the given run directory exists, and if an incompatible run is using that directory (hash_collision)
local step_run_query_dir_status = function(step_run_path, step_run_hash_params)
	-- read the parameters the existing directory declares
	local cached_params_path = step_run_path.."/params_in.txt"
	local exists, cached_params = pcall(util.read_param_file_new_compat_deserialize, cached_params_path, "input parameters (params_in.txt) of step run directory '"..step_run_path.."' do not exist, cannot check for hash collision")
	if not exists then return false, false end
	
	-- if we expected different parameters, it's a hash collision and not an actual cache hit
	local run_dir_exists = util.tables_shallow_equal(step_run_hash_params, util.tables_intersect(cached_params, step_run_hash_params))
	local hash_collision = not run_dir_exists
	return run_dir_exists, hash_collision
end



-- step features: parameter propagation through dependencies and hashing to derive run directory names
-- helper function that sets a run id based off the current time if none exists yet
local run_id_counter = 0
local ensure_run_id_in_place = function(params)
	if not params['RUN-id'] then
		params['RUN-id'] = os.date('%Y-%m-%d-%H-%M-%S-')..os.clock().."-"..run_id_counter
		run_id_counter = run_id_counter + 1
		print("!! assigned run id: "..params['RUN-id'])
	end
end
-- constructs the input params requested by the given step using the given params as a basis
-- returns active params, in params, special params, step hash params, run path
local step_single_process_params_active_in_special_hash_run_path = function(step_name, params)
	
	-- split input template into special parameters to handle and default values to copy where our params are empty
	local special_params, default_values = features.step_query_inputs_special_params_default_values(step_name)
	local requested_repos_lookup = special_params.requested_repos_lookup
	params = util.table_patch(default_values, params) -- apply our params over default values
	
	--ensure the requested repos exist, and write their commit hashes to params where none were specified
	for repo_name, _ in pairs(requested_repos_lookup) do
		local repo_path = relative_path_prefix.."repos/"..repo_name
		--assert(util.is_working_directory_clean(repo_path), "repo '"..repo_name.."' requested via input parameters of build step '"..step_name.."' unavailable")
		
		local gitcommithash_key = 'REPO-GITCOMMITHASH-'..repo_name
		local commit_expr = params[gitcommithash_key]
		commit_expr = commit_expr ~= "" and commit_expr
			or 'HEAD' -- otherwise query the current commit
		
		-- translate a commit expression to its commit hash
		local commit_hash = lookup_git_repository_commit_expr_hash(repo_name, commit_expr)
		params[gitcommithash_key] = commit_hash
	end
	
	--provide run id if requested
	if special_params.wants_run_id then
		ensure_run_id_in_place(params)
	end
	
	-- provide hostname if requested
	if special_params.wants_hostname then
		params['RUN-hostname'] = params['RUN-hostname']
			or util.get_hostname()
	end
	
	-- calculate the step run's identifying hash
	local step_hash_params_intersector = features.step_query_effective_inputs_lookup(step_name) -- hash params are all effective params: run input params without repo paths and RUN-all-params
	local step_run_hash_params = util.tables_intersect(params, step_hash_params_intersector)
	local step_run_hash = util.hash_params(step_run_hash_params)
	
	local step_run_in_params = util.table_copy_shallow(step_run_hash_params)
	
	-- construct the paths for all requested repositories, relative to the nesting of any step run directory
	local step_run_relative_repos = "../../../"..step_name.."/runs/"..step_run_hash.."/repos/"
	for repo_name, _ in pairs(requested_repos_lookup) do
		local k = 'REPO-PATH-'..repo_name
		local v = step_run_relative_repos..repo_name.."/"
		params[k] = v
		step_run_in_params[k] = v
	end
	
	local step_path = relative_path_prefix.."steps/"..step_name
	local step_run_path = step_path.."/runs/"..step_run_hash
	
	return params, step_run_in_params, special_params, step_run_hash_params, step_run_path
end
-- writes the values found in the given step run's 'params_out.txt' to the given table params_to_write_to
local apply_params_out_onto_in_place = function(step_name, step_run_path, params_to_write_to)
	local params_out_file_path = step_run_path.."/params_out.txt"
	local params_out = util.read_param_file_new_compat_deserialize(params_out_file_path, "failed to parse 'params_out.txt' of step '"..step_name.."' ('"..step_run_path.."')")
	return util.table_patch_in_place(params_to_write_to, params_out)
end
-- the "next" / iterator function for new_iterate_step_dependency_run_paths
-- returns the next step's index, name, and if the previous step's parameters are available, derived parameter and hash values, as well as an error trace about any becoming unavailable
local new_step_dependency_run_path_iterator_next = function(state, prev_step_index)
	local step_list = state.step_list
	local step_count = step_list and #step_list
	local original_active_params = state.last_active_params
	if prev_step_index == step_count then
		return
	end
	
	local step_index = prev_step_index + 1
	local step_name = step_list[step_index]
	local error_trace = false
	
	if prev_step_index > 0 and original_active_params then
		local successful
		successful, original_active_params = xpcall(apply_params_out_onto_in_place, state.error_handler, step_list[prev_step_index], state.last_step_run_path, original_active_params)
		if not successful then
			error_trace = original_active_params
			original_active_params = nil
			state.last_active_params = nil
		end
	end
	
	local active_params_for_step, step_run_in_params, special_params, step_run_hash_params, step_run_path
	if original_active_params then
		local processing_successful
		processing_successful, active_params_for_step, step_run_in_params, special_params, step_run_hash_params, step_run_path = xpcall(step_single_process_params_active_in_special_hash_run_path, state.error_handler, step_name, original_active_params)
		
		if processing_successful then
			state.last_active_params = active_params_for_step
			state.last_step_run_path = step_run_path
		else
			error_trace = active_params_for_step
			active_params_for_step = nil
			state.last_active_params = nil
		end
	end
	
	local run_dir_exists, hash_collision
	if active_params_for_step then
		run_dir_exists, hash_collision = step_run_query_dir_status(step_run_path, step_run_hash_params)
		if hash_collision then
			error_trace = "hash collision detected, run directory '"..step_run_path.."' is not valid for the requested parameters"
			state.last_active_params = nil
			state.last_step_run_path = nil
		end
	end
	
	return step_index, step_count, step_name, original_active_params, error_trace, active_params_for_step, step_run_in_params, special_params, step_run_hash_params, step_run_path, run_dir_exists, hash_collision
end
-- as the name says, returns arguments unchanged, used as a fallback error handler argument for xpcall
local noop_passthrough = function(...) return ... end
-- the entry point for `for ... in iterate(...) do` syntax of iterating over a target step's dependency chain given initial parameters with the supplied error_handler
function features.new_iterate_step_dependency_run_paths(target_step_name, initial_params, error_handler)
	local iterator_function = new_step_dependency_run_path_iterator_next
	local state = {
		last_active_params = util.table_copy_shallow(initial_params),
		step_list = features.step_get_necessary_steps_inclusive(target_step_name),
		steps_path = relative_path_prefix.."steps/",
		error_handler = error_handler or noop_passthrough,
	}
	local first_iterator_value = 0
	return iterator_function, state, first_iterator_value
end



-- step features: managing step run directories and running commands in them
-- ensure a clean run directory, deleting its previous contents before setting up what it actually needs
local rebuild_step_run_dir = function(step_path, step_run_path, active_params, step_run_in_params, special_params)
	-- first clean everything from the run step dir
	if not pcall(util.ensure_directory_clean, step_run_path) then -- if this failed, maybe the "runs" directory doesn't exist yet
		util.create_new_directory(step_path.."/runs/")
		util.create_new_directory(step_run_path)
	end
	
	-- copy (clone) repositories we need to for the step run
	local we_have_repos -- skip this part if we can to avoid FIXME assert below
	for _ in pairs(special_params.requested_repos_lookup) do
		we_have_repos = true
		break
	end
	if we_have_repos then
		local step_run_repos = step_run_path.."/repos"
		util.create_new_directory(step_run_repos)
		assert(relative_path_prefix == "./" or relative_path_prefix == "",
			"FIXME (unimplemented): converting \""..relative_path_prefix.."repos/\" to an absolute path so we can refer to it from within directory \""..step_run_repos.."/(repo_name)/\"")
		local cwd_absolute = util.get_current_directory()
		local repos_path = cwd_absolute.."/repos/"
		for repo_name, _ in pairs(special_params.requested_repos_lookup) do
			local repo_path = repos_path..repo_name.."/"
			local run_repo_path = step_run_repos.."/"..repo_name.."/"
			-- clone && checkout
			local commit_hash = active_params['REPO-GITCOMMITHASH-'..repo_name] -- already translated at this point
			-- FIXME: Windows didn't like this combined command over in commands.lua:536: ['auto-setup'].implementation .
			-- The same 'path not found' issue might happen here, in which case they need to be separated into 2 commands
			-- (and maybe we want some other facility for this, that preserves/combines commands on Linux, where this seems to work well)
			assert(util.execute_command_at("git clone "..util.in_quotes(repo_path).." --no-checkout && cd "..util.in_quotes(repo_name).." && git checkout "..util.in_quotes(commit_hash).." --detach", step_run_repos)) -- note: prefixing with `file://` is actually a pessimization, because then git doesn't default to its more efficient `--local` transfer protocol
		end
	end
	
	-- write all-parameter file used to generate unique metric entries
	if special_params.wants_all_params then
		active_params['RUN-all-params'] = nil
		local all_params_string = "============\n"..util.new_compat_serialize(active_params).."\n\n"
		util.write_full_file(step_run_path.."/params_in_all.txt", all_params_string)
	end
	
	-- write parameter file as last step, so parameters being present means that everything is ready
	local params_in_string = special_params.wants_line_based_params_in and util.new_compat_serialize(step_run_in_params)
		or util.json_encode(step_run_in_params)
	util.write_full_file(step_run_path.."/params_in.txt", params_in_string) -- write params_in file
end
-- invokes the 'start' command of a step run directory at the given path for the given parameters is available
local step_invoke_command_start = function(step_name, step_path, step_run_path, run_dir_exists, hash_collision, active_params, step_run_in_params, special_params)
	if run_dir_exists then -- the run directory we want already exists for our parameters
		local step_status = features.step_query_status(step_name, step_run_path)
		if step_status == 'finished' then
			print("found cache hit with status 'finished', eliding execution")
			return step_status, 0
		elseif step_status == 'pending' or step_status == 'continuable' then
			print("step run already in progress with status '"..step_status.."', eliding re-execution (cancel first to restart step run)")
			return step_status, 0
		elseif step_status == 'startable' then
			print("Deleting startable step run leftovers.")
		else
			error("unrecognized step status '"..step_status.."', don't know how to execute command 'start'")
		end
	elseif hash_collision then -- the run directory that exists is not the one we want - check whether we can safely replace it
		-- It's not always safe to just delete, since the data might still be in use by later steps.
		print("Detected hash collision!")
		local step_status = features.step_query_status(step_name, step_run_path)
		if step_status == 'startable' then
			print("Previous run was startable. Discarding leftovers and rebuilding run directory.")
		elseif step_status == 'pending' or step_status == 'continuable' or step_status == 'finished' then
			-- TODO (maybe in the future): in case the step is 'finished', if we could ensure no subsequent build steps are running, we could delete the offending folder and rebuild it.
			-- Alternatively, we could implement linear-lookup collision strategy, like auto-renaming the new folder.
				-- That would however mean you can't just delete the first folder and revert to the original strategy.
			error("Collided with step run with status '"..step_status.."'. Please manually verify that the folder ('"..step_run_path.."') is no longer in use and delete it.")
		else
			error("Colliding folder ('"..step_run_path.."') reports unrecognized step status '"..step_status.."'.")
		end
	end
	
	rebuild_step_run_dir(step_path, step_run_path, active_params, step_run_in_params, special_params)
	
	-- invoke the command
	return step_invoke_command_raw(step_name, step_run_path, 'start', "../../")
end
-- invoke a step command, setting up its run directory if required
-- does not support 'inputs', which needs no run directory (use features.step_query_inputs)
local step_invoke_command__supported_commands = {
		start = true,
		cancel = true,
		status = true,
		continue = true
	}
function features.step_invoke_command(step_name, command, active_params, step_run_in_params, special_params, step_run_hash_params, step_run_path, run_dir_exists, hash_collision)
	-- argument checking
	assert(step_name)
	local step_path = relative_path_prefix.."steps/"..step_name
	assert(command ~= 'inputs', "command 'inputs' not implemented here")
	assert(step_invoke_command__supported_commands[command], "unrecognized build step command '"..tostring(command).."'")
	assert(active_params)
	assert(step_run_in_params)
	assert(special_params)
	assert(step_run_hash_params)
	assert(step_run_path)
	
	local command_can_create_run_dir = ( -- whether to create the run dir if it doesn't yet exist
			command == 'start'
		)
	
	if command_can_create_run_dir then
		assert(command == 'start', "unimplemented command that can create a run dir: '"..command.."'")
		-- handles creating the directory and invoking the command
		return step_invoke_command_start(step_name, step_path, step_run_path, run_dir_exists, hash_collision, active_params, step_run_in_params, special_params)
	end

	-- the remaining commands need the run directory to be created already
	assert(run_dir_exists, "run directory for step '"..step_name.."' with given parameters does not exist")
	if command == 'continue' then -- no-op if the step is already finished
		local step_status = features.step_query_status(step_name, step_run_path)
		if step_status == 'finished' then
			print("found cache hit with status 'finished', eliding execution")
			return step_status, 0
		end
	end
	
	-- invoke the command
	return step_invoke_command_raw(step_name, step_run_path, command, "../../")
end



-- pipeline features: calculate the path used for a pipeline file: "<target-step>/<id-less-hash>/<id>.txt"
local get_pipeline_hash_dir_name = function(initial_params)
	local initial_params_without_id = initial_params['RUN-id'] and util.table_copy_shallow(initial_params)
		or initial_params
	initial_params_without_id['RUN-id'] = nil
	return util.hash_params(initial_params_without_id)
end
features.get_pipeline_hash_dir_name = get_pipeline_hash_dir_name
function features.get_pipeline_file_path(target_step_name, initial_params)
	local pipeline_id = assert(initial_params['RUN-id'])
	
	local hash_dir_name = get_pipeline_hash_dir_name(initial_params)
	local pipeline_hash_dir_path = relative_path_prefix .. "pipelines/"..target_step_name.."/"..hash_dir_name
	if not pcall(util.ensure_directory, pipeline_hash_dir_path) then -- "pipelines/<target-step>" might not yet exist
		pcall(util.create_new_directory, relative_path_prefix.."pipelines") -- might already exist
		util.create_new_directory(relative_path_prefix.."pipelines/"..target_step_name) -- we assume the first pcall failed because this didn't exist, so creating it should work
		util.create_new_directory(pipeline_hash_dir_path)
	end
	--assert(util.directory_exists(pipeline_hash_dir_path), "ensure_directories doesn't work")
	return pipeline_hash_dir_path.."/"..pipeline_id..".txt"
end



-- pipeline features: execute a pipeline by starting/continuing its steps, creating/keeping a pipeline file on suspension
-- assumes the file at existing_pipeline_file_path already exists and has been verified to not be a hash collision if not nil
-- if the pipeline was finished, returns true,
-- if the pipeline didn't complete, returns the name of the last processed step and the status it reported, if it is pending whether it was resumed (wasn't already pending), and the pipeline file path (so that can be reported to the user)
function features.execute_pipeline_steps(target_step_name, initial_params, existing_pipeline_file_path)
	-- the path of the pipeline file corresponding to this pipeline instance
	local pipeline_file_path = existing_pipeline_file_path
	
	local initial_id = initial_params['RUN-id'] -- (also) identifies our pipeline
	if not existing_pipeline_file_path then -- we do not want to resume a previous pipeline instance
		if initial_id then -- skip this pipeline instance with a warning if it already exists
			pipeline_file_path = pipeline_file_path
				or features.get_pipeline_file_path(target_step_name, initial_params)
			if util.file_exists(pipeline_file_path) then
				print("Warning: found existing pipeline with matching parameters and id ('"..initial_id.."'), skipping.")
				return
			end
		else
			initial_params = util.table_copy_shallow(initial_params) -- do not modify the original table we're passed in (might be re-used)
			ensure_run_id_in_place(initial_params)
		end
	else -- otherwise we need to already have an id to identify the pipeline we're resuming
		assert(initial_id)
	end
	
	pipeline_file_path = pipeline_file_path
		or features.get_pipeline_file_path(target_step_name, initial_params)
	
	-- execute steps one by one, abort on error or async step
	local last_step_name, last_step_status, last_step_busy -- if we don't finish the pipeline, return the last step's name and last reported status
	local delayed_error_msg -- instead of calling error, we first want to create a pipeline file in case of failure
	for step_index, step_count, step_name, original_active_params, error_trace, active_params_for_step, step_run_in_params, special_params, step_run_hash_params, step_run_path, run_dir_exists, hash_collision in features.new_iterate_step_dependency_run_paths(target_step_name, initial_params) do
		-- check for iteration-internal errors
		if error_trace then
			delayed_error_msg = error_trace
			break
		end
		
		-- check what status the build step is in
		local status = not run_dir_exists and 'startable' -- not actually, but equivalent handling
			or features.step_query_status(step_name, step_run_path)
		
		-- check the status to decide if and how to execute the step run
		if status ~= 'finished' then -- if it's finished, skip doing anything
			local command = status == 'continuable' and 'continue'
				or status == 'startable' and 'start'
			if not command then -- step run is not executable
				if status == 'pending' then
					print("step '"..step_name.."' is waiting for asynchronous execution") -- debug print, TODO: adapt/remove
					last_step_name, last_step_status, last_step_busy = step_name, status, true
					break
				else
					delayed_error_msg = "unrecognized build status '"..status.."', don't know how to execute step '"..step_name.."' in pipeline"
					break
				end
			end
			
			-- try executing the build step
			local output, return_status, error_details = features.step_invoke_command(step_name, command, active_params_for_step, step_run_in_params, special_params, step_run_hash_params, step_run_path, run_dir_exists, hash_collision)
			if not output then
				delayed_error_msg = "failed to execute step '"..step_name.."' in pipeline; "
					.. (error_details and "error: "..error_details
							or "exit code: "..tostring(return_status))
				break
			end
			
			-- check if the step is now finished, stop here if it isn't
			status = features.step_query_status(step_name, step_run_path)
			if status ~= 'finished' then
				if status == 'pending' or status == 'continuable' then -- if it's continuable we could loop executing 'continue', but that means unbounded complexity, we might get stuck if the script is faulty
					print("step '"..step_name.."' suspended itself, waiting for asynchronous execution")
					last_step_name, last_step_status = step_name, status
					break
				elseif status == 'startable' then
					print("step '"..step_name.."' is startable, seems to have aborted execution")
					last_step_name, last_step_status = step_name, status
					break
				else
					delayed_error_msg = "unrecognized build status '"..status.."', don't know how to execute step '"..step_name.."' in pipeline"
					break
				end
			end
		end
		
		-- when we reach here, the step is finished
		if step_index == step_count then -- the pipeline instance is completed
			if not existing_pipeline_file_path then -- no pipeline file written yet, we are done
				print("finished pipeline")
				return true
			end
			print("finished pipeline - deleting pipeline file '"..pipeline_file_path.."'")
			util.remove_file(pipeline_file_path)
			return true
		end
		-- otherwise, move on to the next step
	end
	
	-- the pipeline was suspended or aborted
	if not existing_pipeline_file_path then -- no pipeline file for this instance exists yet
		util.write_param_file_new_compat_serialize(pipeline_file_path, initial_params)
		print("created pipeline file '"..pipeline_file_path.."'")
	end
	
	-- error if we aborted and set delayed_error_msg earlier
	assert(not delayed_error_msg, delayed_error_msg)
	-- otherwise report the last processed step and its last known status
	local last_step_resumed = not last_step_busy
	return last_step_name, last_step_status, last_step_resumed, pipeline_file_path
end



-- pipeline features: cancel a pipeline by cancelling its currently-suspended step run in a pipeline, optionally delete that step run's directory
-- returns the first reported step status of the last available step of the pipeline, followed by the status reported after cancellation if cancellation was attempted,
-- or nothing if either a step without run directory or the end of the pipeline are reached
function features.cancel_pipeline_instance(target_step_name, initial_params, select_pending, select_errors, select_continuable, discard_last_step_and_pipeline)
	local return_status
	local all_steps_finished
	for step_index, step_count, step_name, original_active_params, error_trace, active_params_for_step, step_run_in_params, special_params, step_run_hash_params, step_run_path, run_dir_exists, hash_collision in features.new_iterate_step_dependency_run_paths(target_step_name, initial_params) do
		-- check for iteration-internal error
		assert(not error_trace, error_trace)
		
		if not run_dir_exists then -- this step doesn't exist yet, so nothing to cancel
			return
		end
		
		-- query what state the build step is in
		local status = features.step_query_status(step_name, step_run_path)
		if status ~= 'finished' then
			local was_pending = status == 'pending'
			local was_error = util.string_starts_with(status, "error")
			local was_continuable = status == 'continuable'
			if was_pending or was_error or was_continuable then
				local selected = select_pending and was_pending
					or select_errors and was_error
					or select_continuable and was_continuable
				if selected then
					features.step_invoke_command(step_name, 'cancel', active_params_for_step, step_run_in_params, special_params, step_run_hash_params, step_run_path, run_dir_exists, hash_collision)
					local new_status = features.step_query_status(step_name, step_run_path)
					if new_status ~= 'startable' then
						print("build step '"..step_name.."' unexpectedly returned status '"..new_status.."' after cancellation"..(discard_last_step_and_pipeline and ", not deleting run directory in pipeline discard" or ""))
						return new_status
					end
					if discard_last_step_and_pipeline then
						util.remove_directory(step_run_path)
					end
					return status, new_status
				end
				return status
			elseif status ~= 'startable' then
				error("unexpected build status '"..status.."' in step '"..step_name.."', don't know how to cancel pipeline towards step '"..target_step_name.."'")
			else
				return status -- only status 'startable' should reach here
			end
		end
	end
	return
end



-- helper function: order the given commits according to some topological ordering. This means that every parent will be ordered before all of its children.
local order_commits_partially_topologically = function(repository_path, commit_hashes)
	-- query the full, topologically-ordered rev list, which essentially does the ordering for us
	local full_rev_list = util.get_rev_list_for(repository_path, commit_hashes)
	
	local string_find = string.find
	-- extract the beginning indices of our commit hashes in the full rev-list
	local commit_hash_begin_indices = {}
	local reorder_indices = {} -- also builds an index list to help with permutation later
	for i = 1, #commit_hashes do
		local begin_index = string_find(full_rev_list, commit_hashes[i], 1, true)
		assert(begin_index, "found no begin index for commit "..commit_hashes[i])
		commit_hash_begin_indices[i] = begin_index
		reorder_indices[i] = i
	end
	
	-- reorder the index list by the positions in the full rev-list
	table.sort(reorder_indices, function(a, b) return commit_hash_begin_indices[a] < commit_hash_begin_indices[b] end)
	-- now order the commit hashes by picking them according to the reordered index list
	local reordered_commit_hashes = {}
	local reordered_commit_hash_begin_indices = {}
	local reordered_commit_hash_end_indices = {}
	for i = 1, #reorder_indices do
		local ri = reorder_indices[i]
		reordered_commit_hashes[i] = commit_hashes[ri]
		reordered_commit_hash_begin_indices[i] = commit_hash_begin_indices[ri]
	end
	
	return reordered_commit_hashes
end

-- commit ordering feature: Construct an acyclic ordering graph among the supplied commit_hashes, return totally ordered lists (from oldest ancestor to newest child) of every possible full path through that graph. Abort if more than strand_count_limit paths are found.
function features.order_commits_into_strands(repository_path, commit_hashes, strand_count_limit)
	-- order commits topologically - this is currently a required precondition for either of the following logic
	commit_hashes = order_commits_partially_topologically(repository_path, commit_hashes)
	
	if strand_count_limit == 1 then -- quick path for single strand: in this case we only need to check the consistency of the topological order
		-- assert that the commits are in fact totally ordered
		local prev_commit_hash = commit_hashes[1]
		for i = 2, #commit_hashes do
			local commit_hash = commit_hashes[i]
			if not util.is_given_commit_descendant_of(repository_path, commit_hash, prev_commit_hash) then
				error("given commits are not strictly ordered in a single strand!\n"..commit_hash.." is not descendant of "..prev_commit_hash)
			end
			prev_commit_hash = commit_hash
		end
		return {commit_hashes}
	end
	
	-- otherwise we construct a graph of totally-ordered strands of commits
	local heuristic_min_strand_count = 1 -- SHOULD never exceed the actual number of strands
	local increase_heuristic_min_strand_count = strand_count_limit and function(n)
			heuristic_min_strand_count = heuristic_min_strand_count + n
			if heuristic_min_strand_count > strand_count_limit then
				error("Given strand limit exceeded: The supplied commits result in at least "..heuristic_min_strand_count.." strands!")
			end
		end
		or function() end -- or noop
	
	local first_strand = {commit_hashes[1], older = {}, newer = {}}
	local oldest_strands = {first_strand}
	local newest_strands = {first_strand}
	local get_rev_list_for__arg_cache = {}
	for i = 2, #commit_hashes do
		local hash = commit_hashes[i]
		get_rev_list_for__arg_cache[1] = hash
		-- get the complete rev-list of a given commit, to check all of its ancestors
		local rev_list = util.get_rev_list_for(repository_path, get_rev_list_for__arg_cache)
		
		local strands_full_of_ancestors = {}
		local looked_at_strand = {}
		
		local newest_candidate_strands = newest_strands
		repeat
			local next_older_candidates_lookup = {}
			for strand_i = #newest_candidate_strands, 1, -1 do
				local strand = newest_candidate_strands[strand_i]
				if not looked_at_strand[strand] then
					local newest_commit = strand[#strand]
					if string.find(rev_list, newest_commit, 1, true) then -- look for the newest commit in the ancestors of the current commit
						strands_full_of_ancestors[#strands_full_of_ancestors+1] = strand
					elseif string.find(rev_list, strand[1], 1, true) then -- look for the oldest commit in the ancestors of the current commit
						-- find the last commit that's an ancestor; TODO: bisection would be better than linear search
						local newest_ancestor_i
						for i = 2, #strand-1 do
							if not string.find(rev_list, strand[i], 1, true) then
								newest_ancestor_i = i-1
								break
							end
						end
						newest_ancestor_i = newest_ancestor_i or #strand-1
						-- split the strand into one strand that we are fully descendant of and one "sibling" tail that contains none of our ancestors
						local strand_tail = util.list_split_in_place_at_return_tail(strand, newest_ancestor_i+1)
						strand_tail.newer = strand.newer
						strand.newer = {strand_tail}
						strand_tail.older = {strand}
						
						strands_full_of_ancestors[#strands_full_of_ancestors+1] = strand
						if newest_candidate_strands == newest_strands then -- implies #strand_tail.newer == 0
							newest_candidate_strands[strand_i] = strand_tail -- note: will not be visited in this loop instance (iterations will stop at old list length)
							-- note: the old strand will be removed from newest_strands further below
						end
						
						increase_heuristic_min_strand_count(1) -- this branch results in at least one more strand
					else
						local older = strand.older
						for i = 1, #older do
							next_older_candidates_lookup[older[i]] = true
						end
					end

					looked_at_strand[strand] = true
					local older_stack = {}
					for i = 1, #strand.older do
						older_stack[i] = strand.older[i]
					end
					while #older_stack > 0 do
						local top = older_stack[#older_stack]
						older_stack[#older_stack] = nil
						if not looked_at_strand[top] then
							local onto_stack = top.older
							for i = 1, #onto_stack do
								older_stack[#older_stack+1] = i
							end
							looked_at_strand[top] = true
						end
					end
				end
			end
			newest_candidate_strands = {}
			for older_strand--[[, true]] in pairs(next_older_candidates_lookup) do
				if not looked_at_strand[older_strand] then
					next_older_candidates[#next_older_candidates+1] = older_strand
				end
			end
		until #newest_candidate_strands == 0
		
		local single_parent_strand = #strands_full_of_ancestors == 1 and strands_full_of_ancestors[1]
		if single_parent_strand and #single_parent_strand.newer == 0 then
			single_parent_strand[#single_parent_strand+1] = hash
		else
			local new_strand = {hash, newer = {}, older = strands_full_of_ancestors}
			newest_strands[#newest_strands+1] = new_strand
			if #strands_full_of_ancestors > 0 then
				for strand_i = 1, #strands_full_of_ancestors do
					local strand = strands_full_of_ancestors[strand_i]
					strand.newer[#strand.newer+1] = new_strand
				end
			else
				oldest_strands[#oldest_strands+1] = new_strand
				increase_heuristic_min_strand_count(1) -- this is a new strand
			end
		end
	end
	
	
	
	-- iterate all paths through our strand graph to materialize the strands as lists of commit hashes
	heuristic_min_strand_count = 0 -- reset our count - this time we count actual factual resulting strands
	local finished_hash_lists = {}
	local hash_list_stack = {{}}
	local next_branch_index_stack = {}
	local node_stack = {{newer = oldest_strands}} -- start with a synthetic root node
	local stack_height = #node_stack
	repeat
		local top = node_stack[stack_height]
		local next_branch_index = next_branch_index_stack[stack_height] or 1
		local top_newer = top.newer
		if #top_newer < next_branch_index then -- we've exhausted this branching point
			hash_list_stack[stack_height] = nil
			next_branch_index_stack[stack_height] = nil
			node_stack[stack_height] = nil
			stack_height = stack_height - 1
		else -- pick the next branch
			local next_top = top_newer[next_branch_index]
			next_branch_index_stack[stack_height] = next_branch_index+1
			
			local next_hash_list = util.list_append_to_new(hash_list_stack[stack_height], next_top)
			if #next_top.newer == 0 then -- we've reached the end of a strand
				finished_hash_lists[#finished_hash_lists+1] = next_hash_list
				increase_heuristic_min_strand_count(1)
			else -- push the branch onto the stack and process it in the next iteration
				stack_height = stack_height+1
				hash_list_stack[stack_height] = next_hash_list
				node_stack[stack_height] = next_top
			end
		end
	until stack_height == 0
	
	-- check that the commits are in fact totally ordered; TODO: remove, this is only for debugging and hurts our runtime!
	for i = 1, #finished_hash_lists do
		local hash_list = finished_hash_lists[i]
		local prev_commit_hash = hash_list[1]
		for i = 2, #hash_list do
			local commit_hash = hash_list[i]
			if not util.is_given_commit_descendant_of(repository_path, commit_hash, prev_commit_hash) then
				error("given commits are not strictly ordered; inconsistency detected logic bug!\n"..commit_hash.." is not descendant of "..prev_commit_hash)
			end
			prev_commit_hash = commit_hash
		end
	end
	
	return finished_hash_lists
end



return features
