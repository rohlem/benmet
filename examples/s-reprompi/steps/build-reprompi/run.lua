--[=[

user@server:~/tmp/user$ pwd
/home/user/tmp/user

git clone https://github.com/hunsa/reprompi

# set path to new MPI library
export PATH=/home/user/tmp/user/openmpi-tag-slurm/bin:$PATH
export LD_LIBRARY_PATH=/home/user/tmp/user/openmpi-tag-slurm/lib:$LD_LIBRARY_PATH

user@server:~/tmp/user/ompi$ export PATH=/home/user/tmp/user/openmpi-tag-slurm/bin:$PATH
user@server:~/tmp/user/ompi$ export LD_LIBRARY_PATH=/home/user/tmp/user/openmpi-tag-slurm/lib:$LD_LIBRARY_PATH
user@server:~/tmp/user/ompi$ which mpicc
/home/user/tmp/user/openmpi-tag-slurm/bin/mpicc

user@server:~/tmp/user/reprompi$ cmake -DENABLE_GETTIME_REALTIME=ON .

make -j 16

--]=]

local util = require "benmet.util"
local templates = require "benmet.step_templates"

local step_config = {
	name = 'build-reprompi',
	params_in = {
		['REPO-PATH-reprompi'] = "",
		['REPO-GITCOMMITHASH-reprompi'] = "",
		['PARAM-build-openmpi-env-entry-LD_LIBRARY_PATH'] = "",
		['PARAM-build-openmpi-env-entry-PATH'] = "",
	},
	start_logic = function(params_in, bookkeeping) -- 'start' command
		-- add the openmpi build to our path
		local new_path_entry = params_in['PARAM-build-openmpi-env-entry-PATH']
		util.prependenv("PATH", new_path_entry..":")
		util.prependenv("LD_LIBRARY_PATH", params_in['PARAM-build-openmpi-env-entry-LD_LIBRARY_PATH']..":")
		-- check mpicc is now the correct one
		local expected_mpicc = new_path_entry.."/mpicc"
		local found_mpicc = util.find_program("mpicc")
		assert(found_mpicc == expected_mpicc, "Could not find built mpicc after it was added to PATH!\nExpected: '"..expected_mpicc.."'\nFound: '"..found_mpicc.."'")
		
		local cwd_absolute = util.get_current_directory()
		local reprompi_build_dir = cwd_absolute.."/built-reprompi/"
		local reprompi_build_bin_dir = reprompi_build_dir.."bin/"
		local reprompi_repo_path = params_in['REPO-PATH-reprompi']
		local reprompi_repo_path_from_build_dir = "../"..reprompi_repo_path
		
		
		-- build reprompi
		util.ensure_directory_clean(reprompi_build_dir)
		assert(util.execute_command_at("cmake -DENABLE_GETTIME_REALTIME=ON "..util.in_quotes(reprompi_repo_path_from_build_dir), reprompi_build_dir))
		assert(util.execute_command_at("make -j 16", reprompi_build_dir))
		
		-- check the program we just built is where we expect it to be
		assert(util.file_exists(reprompi_build_bin_dir.."/mpibenchmark"))
		
		
		-- declare out parameters for subsequent build steps
		bookkeeping:declare_output_parameter('PARAM-build-reprompi-bin-path', reprompi_build_bin_dir)
	end,
}

os.exit(templates.run_standard_step(step_config, --[[cmd_args]] ...))
