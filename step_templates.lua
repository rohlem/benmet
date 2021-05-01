local util = require "benmet.util"

local templates = {}

local nonnull_table_mt = {
	__index = function(self, key)
		error("accessing undeclared input parameter '"..tostring(key).."'")
	end,
}
local wrap_table_const = function(underlying_mutable, table_name)
	table_name = table_name or "(const table)"
	return setmetatable({}, {
		__index = function(self, key)
			return underlying_mutable[key]
		end,
		__newindex = function(self, key, value)
			error("potential error trying to assign "..table_name.."["..string.format("%q", tostring(key)).."] = "..tostring(value))
		end,
		__pairs = function(self)
			return pairs(underlying_mutable)
		end,
	})
end
local assert_in_params_nonempty_except = function(bookkeeping, keys_allowed_empty)
	local allowed_empty_lookup = {}
	for i = 1, keys_allowed_empty and #keys_allowed_empty or 0 do
		allowed_empty_lookup[keys_allowed_empty[i]] = true
	end
	allowed_empty_lookup['RUN-all-params'] = true -- this is currently only a one-way sentinel, and always left empty
	local declared_params_lookup = {}
	for k,v in pairs(bookkeeping.declared_params_in) do
		declared_params_lookup[k] = true
		if not allowed_empty_lookup[k] then
			v = bookkeeping.params_in[k]
			assert(v ~= nil and v ~= "", "input parameter '"..tostring(k).."' was unexpectedly empty")
		end
	end
	-- not THAT likely to lead to bugs, and triggers for REPO-GITCOMMITHASH-...
	--[[for k,v in pairs(bookkeeping.params_in) do
		assert(declared_params_lookup[k], "received undeclared input parameter '"..tostring(k).."'")
	end--]]
end
local try_cleaning_up_deletable_standard_repos = function(bookkeeping)
	local non_deletable_repos = bookkeeping.non_deletable_repos
	if not util.directory_exists("./repos") then return end
	util.remove_all_in_directory_except("./repos", non_deletable_repos or {})
end
local standard_step_bookkeeping_mt = {
	__index = {
		get_run_id = function(self)
			return assert(self.params_in['RUN-id'], "'RUN-id' needs to be declared as input parameter")
		end,
		get_all_params = function(self)
			assert(self.declared_params_in['RUN-all-params'], "'RUN-all-params' needs to be declared as input parameter")
			local all_params_entry_heading = self.all_params_entry_heading
				or util.read_full_file("./params_in_all.txt")
			self.all_params_entry_heading = all_params_entry_heading
			return all_params_entry_heading
		end,
		declare_output_parameter = function(self, name, value)
			name = tostring(name)
			self.params_out = self.params_out or {}
			assert(not self.params_out[name], "potential error overwriting output parameter ["..string.format("%q", name).."] = "..tostring(value))
			self.params_out[name] = value
		end,
		declare_repos_deletable_except = function(self, repo_name_list)
			assert(not self.non_deletable_repos)
			self.non_deletable_repos = repo_name_list
		end,
		after_start_logic = function(self)
			-- write out parameters for subsequent build steps
			util.write_param_file_new_compat_serialize("./params_out.txt", self.params_out or {})
			try_cleaning_up_deletable_standard_repos(self)
		end,
	},
}
local standard_step_bookkeeping = function(self, config)
	local self = self or {}
	self.declared_params_in = config.params_in
	return setmetatable(self, standard_step_bookkeeping_mt)
end
local default_command_fallback = function(command)
	error("unrecognized command (first argument) '"..command.."'")
end
local default_commands = {
	['inputs'] = function(config)
		-- print all params required for this step
		print(util.new_compat_serialize(config.params_in))
		return 0
	end,
	status = function(config)
		--this step is not asynchronous, so once we've written our out parameters it is finished
		print(util.file_exists("./params_out.txt") and 'finished'
			or 'startable')
		return 0
	end,
	start = function(config)
		local params_in = util.read_param_file_new_compat_deserialize("./params_in.txt")
		params_in = wrap_table_const(setmetatable(params_in, nonnull_table_mt), "params_in")
		config.bookkeeping.params_in = params_in
		assert_in_params_nonempty_except(config.bookkeeping, config.params_in_allowed_empty)
		
		assert(config.start_logic, "missing custom start logic implementation")(params_in, config.bookkeeping)
		
		config.bookkeeping:after_start_logic()

		print("BUILD STEP "..(config.name and config.name.." " or "").."FINISHED")
		return 0
	end,
	cancel = function(config)
		error"nothing to cancel in a synchronous build step"
	end,
	continue = function(config)
		error"nothing to continue in a synchronous build step"
	end,
}
function templates.run_standard_step(config, command, --[[further cmd_args]]...)
	assert(command, "missing command (first argument)")
	if select('#', ...) > 0 then
		error("no arguments expected after command '"..command.."', received: "..table.concat({...}, ",", 2))
	end
	config.bookkeeping = standard_step_bookkeeping({}, config)
	local command_impl = config.commands and config.commands[command]
		or default_commands[command]
		or default_command_fallback
	return command_impl(config)
end

local default_async_step_get_status = function(config)
	local status = util.file_exists("./params_out.txt") and 'finished'
	local last_stage_index = #config.standard_stages
	local stage_index = last_stage_index
	if status then
		return status, stage_index
	end
	while true do
		local current_stage = config.standard_stages[stage_index]
		if stage_index < 1 then
			status = 'startable'
		elseif stage_index == last_stage_index and current_stage.is_final_synchronous then
			-- continue with status == nil
		elseif util.file_exists(assert(current_stage.completed_sentinel_file_path)) then
			status = 'continuable'
		elseif util.file_exists(assert(current_stage.pending_sentinel_file_path)) then
			status = 'pending'
		end
		if status then
			return status, stage_index
		end
		stage_index = stage_index - 1
	end
	error"unreachable"
end
local async_step_bookkeeping_declare_stage_status = function(self, status)
	assert(self.current_stage_state_decl == nil, "redeclared async stage status, was previously '"..tostring(self.current_stage_state_decl).."'")
	self.current_stage_state_decl = status
end
local async_step_bookkeeping_mt = {
	__index = setmetatable({
		declare_stage_pending = function(self)
			return async_step_bookkeeping_declare_stage_status(self, 'pending')
		end,
		declare_stage_finished = function(self)
			return async_step_bookkeeping_declare_stage_status(self, 'finished')
		end,
		get_previous_stage = function(self)
			return self.standard_stages[self.current_stage_index-1]
		end,
		get_current_stage = function(self)
			return self.standard_stages[self.current_stage_index]
		end,
		get_previous_pending_params = function(self)
			local prev_params_pending_path = self:get_previous_stage().pending_sentinel_file_path
			local prev_params_pending = self.prev_params_pending
				or util.file_exists(prev_params_pending_path) and util.read_param_file_new_compat_deserialize(prev_params_pending_path)
			self.prev_params_pending = prev_params_pending
			return prev_params_pending
		end,
		get_current_pending_params = function(self)
			local params_pending_path = self:get_current_step().pending_sentinel_file_path
			local params_pending = self.params_pending
				or util.file_exists(params_pending_path) and util.read_param_file_new_compat_deserialize(params_pending_path)
			self.params_pending = params_pending
			return params_pending
		end,
		get_preliminary_params_out = function(self)
			local preliminary_params_out = self.preliminary_params_out
				or util.file_exists("./preliminary_params_out.txt") and util.read_param_file_new_compat_deserialize("./preliminary_params_out.txt")
				or {}
			self.preliminary_params_out = preliminary_params_out
			return preliminary_params_out
		end,
		declare_output_parameter = function(self, name, value)
			name = tostring(name)
			local params_out = self:get_preliminary_params_out()
			self.params_out = params_out
			assert(not params_out[name], "potential error overwriting output parameter ["..string.format("%q", name).."] = "..tostring(value))
			params_out[name] = value
		end,
		declare_pending_parameter = function(self, name, value)
			name = tostring(name)
			self.params_pending = self.params_pending
				or {}
			assert(not self.params_pending[name], "potential error overwriting pending parameter ["..string.format("%q", name).."] = "..tostring(value))
			self.params_pending[name] = value
		end,
		after_start_logic = false, -- incompatible, block lookup
		after_stage_logic = function(self)
			assert(self.current_stage_state_decl, "stage did not declare status as 'pending' or 'finished'")
			local current_stage = self:get_current_stage()
			
			local is_finished = current_stage.is_final_synchronous
			if not is_finished then
				-- write pending params for the next stage continuing this build step
				assert(not util.file_exists(current_stage.pending_sentinel_file_path), "pending file of stage already exists")
				if self.current_stage_state_decl == 'pending' then
					util.write_param_file_new_compat_serialize(current_stage.pending_sentinel_file_path, self.params_pending or {})
				else
					is_finished = true
				end
			end
			if is_finished then
				assert(not self.params_pending, "declared pending params but declared step finished")
			end
			
			-- write preliminary out params for subsequent build steps, if they were modified
			if self.params_out then
				util.write_param_file_new_compat_serialize("./preliminary_params_out.txt", self.params_out or {})
			end
		end,
		after_step_finished = function(self)
			if util.file_exists("./preliminary_params_out.txt") then
				util.move_file_in_directory(".", "preliminary_params_out.txt", "params_out.txt")
			else
				util.ensure_file("./params_out.txt")
			end
			try_cleaning_up_deletable_standard_repos(self)
		end,
	},  {__index = standard_step_bookkeeping_mt.__index}),
}
local async_step_bookkeeping = function(self, config)
	local self = self or {}
	local status, stage_index = default_async_step_get_status(config)
	self.standard_stages = config.standard_stages
	self.beginning_status = status
	if status ~= 'finished' then
		self.current_stage_index = stage_index == 0 and 1
			or stage_index
				+ (status == 'continuable' and 1
					or status == 'pending' and 0
					or error"unreachable")
	end
	return setmetatable(standard_step_bookkeeping(self, config), async_step_bookkeeping_mt)
end
local default_async_commands
default_async_commands = util.table_patch(default_commands, {
	status = function(config)
		print(config.bookkeeping.beginning_status)
		return 0
	end,
	start = function(config)
		local continue_impl = config.commands and config.commands.continue
			or default_async_commands.continue
			or default_command_fallback
		continue_impl(config, true)
	end,
	cancel = function(config)
		local status, stage_index = default_async_step_get_status(config)
		if status == 'finished' or status == 'startable' then
			error("step "..status..", nothing left to cancel")
		end
		assert(status == 'continuable' or status == 'pending', "unreachable: invalid status encountered, don't know how to cancel '"..status.."' async step")
		if status == 'pending' then
			config.standard_stages[stage_index].cancel_logic(params_in, config.bookkeeping)
		end
		util.remove_file_if_exists("./preliminary_params_out.txt")
		for i = stage_index, 1, -1 do
			util.remove_file_if_exists(config.standard_stages[i].completed_sentinel_file_path)
			util.remove_file_if_exists(config.standard_stages[i].pending_sentinel_file_path)
		end
		return 0
	end,
	continue = function(config, called_from_start)
		local beginning_status = config.bookkeeping.beginning_status
		if beginning_status == 'finished' then
			if called_from_start then
				error"build step already finished, cannot re-start"
			else
				error"build step already finished, cannot re-continue"
			end
		elseif beginning_status == 'pending' then
			if called_from_start then
				error"build step already pending, cannot re-start"
			else
				error"build step pending, not yet ready to continue"
			end
		elseif beginning_status == 'continuable' then
			assert(not called_from_start, "build step already started, use 'continue'")
		elseif beginning_status == 'startable' then
			assert(called_from_start, "cannot continue startable build step, use 'start' to restart")
		end
		
		local params_in = util.read_param_file_new_compat_deserialize("./params_in.txt")
		config.bookkeeping.params_in = wrap_table_const(setmetatable(params_in, nonnull_table_mt), "params_in")
		
		local previous_stage = config.bookkeeping:get_previous_stage()
		local ready_check_logic = previous_stage and previous_stage.ready_check_logic
		if ready_check_logic then
			ready_check_logic(params_in, config.bookkeeping)
		end
		
		local current_stage = config.bookkeeping:get_current_stage()
		assert(current_stage.execute_logic, "missing custom start logic implementation")(params_in, config.bookkeeping)
		
		config.bookkeeping:after_stage_logic()
		local stage_state = config.bookkeeping.current_stage_state_decl
		config.bookkeeping.current_stage_state_decl = nil
		if stage_state == 'pending' then
			assert(not current_stage.is_final_synchronous, "final synchronous stage declared pending")
			print("BUILD STEP "..(config.name and config.name.." " or "").."PENDING")
			return 0
		elseif stage_state == 'finished' then
			if config.bookkeeping.current_stage_index == #config.standard_stages then
				config.bookkeeping:after_step_finished()
				print("BUILD STEP "..(config.name and config.name.." " or "").."FINISHED")
				return 0
			else
				util.ensure_file(current_stage.completed_sentinel_file_path)
				config.bookkeeping.current_stage_index = config.bookkeeping.current_stage_index+1
				local continue_impl = config.commands and config.commands.continue
					or default_async_commands.continue
					or default_command_fallback
				return continue_impl(config) -- tail-recursive call
			end
		end
		error"unreachable: invalid bookkeeping.current_stage_state_decl"
	end,
})
local default_async_step_final_sync_stage = function(params_in, bookkeeping)
	bookkeeping:declare_stage_finished()
end
function templates.run_standard_async_step(config, command, --[[further cmd_args]]...)
	assert(command, "missing command (first argument)")
	if select('#', ...) > 0 then
		error("no arguments expected after command '"..command.."', received: "..table.concat({...}, ",", 2))
	end
	if command ~= 'inputs' then -- skip more complex initialization
		config.bookkeeping = async_step_bookkeeping({}, config)
	
		local stages = config.standard_stages
		local final_stage_is_synchronous
		if not stages or #stages == 0 then
			assert(not config.allow_empty_stage_list, "running standard async step without any stages")
			stages = stages or {}
			config.standard_stages = stages
		else
			final_stage_is_synchronous = stages[#stages].is_final_synchronous
		end
		if not final_stage_is_synchronous then
			stages[#stages+1] = {
				name = 'default final stage',
				execute_logic = default_async_step_final_sync_stage,
				is_final_synchronous = true,
			}
		end
	end
	
	local command_impl = config.commands and config.commands[command]
		or default_async_commands[command]
		or default_command_fallback
	return command_impl(config)
end
function templates.async_step_config_add_stage(config, stage)
	local standard_stages = config.standard_stages or {}
	config.standard_stages = standard_stages
	local stage_name = assert(stage.name)
	assert(stage.execute_logic, "missing logic how to execute stage '"..stage_name.."'")
	if not stage.is_final_synchronous then
		stage.pending_sentinel_file_path = stage.pending_sentinel_file_path or "./pending_"..stage_name..".txt"
		stage.completed_sentinel_file_path = stage.completed_sentinel_file_path or "./completed_"..stage_name..".txt"
		assert(stage.cancel_logic, "missing logic how to cancel stage '"..stage_name.."'")
	end
	if #standard_stages > 0 then
		assert(not standard_stages[#standard_stages].is_final_synchronous, "added stage after stage tagged as final and synchronous")
	end
	standard_stages[#standard_stages+1] = stage
end

return templates
