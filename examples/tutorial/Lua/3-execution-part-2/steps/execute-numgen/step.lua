assert(#arg == 1, "incorrect number of arguments")
local command = arg[1]

if command == 'inputs' then
	print([[{
"RUN-id":"",
"PARAM-numgen-noise-type":"w",
"PARAM-numgen-filter-flag":"0",
"PARAM-numgen-amount":"2"
}]])
	os.exit(0)
end

local util = require 'benmet.util'

if command == 'status' then
	if util.file_exists("params_out.txt") then
		print("finished")
	elseif util.file_exists("params_in.txt") then
		print("startable")
	else
		print("error: no input parameters")
		os.exit(1)
	end
	os.exit(0)
end

if command == 'start' then
	local lua_program = util.get_lua_program()
	
	local numgen_path = "../../../../repos/benmet-tutorial-stub-numgen/numgen.lua"
	
	local input_params = util.read_param_file_new_compat_deserialize("params_in.txt")
	local argument_string = input_params["PARAM-numgen-noise-type"]
		.." "..input_params["PARAM-numgen-filter-flag"]
		.." "..input_params["PARAM-numgen-amount"]
	
	local output_file_path = "numgen_result.txt"
	assert(util.execute_command(lua_program.." "..numgen_path.." "..argument_string.." > "..output_file_path))
	
	util.write_full_file("params_out.txt", "{}")
	os.exit(0)
end

error("unrecognized command '"..command.."'")
