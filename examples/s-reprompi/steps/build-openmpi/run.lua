--[=[

user@server:~/tmp/user$ pwd
/home/user/tmp/user

git clone https://github.com/open-mpi/ompi

# I use tag v3.1.6 (sha1 ea348728b4c856973b48252c8b843078b4784cc3)
cd ompi/
git checkout v3.1.6

# still in ompi
./autogen.pl

# configure ompi, build it, install
user@server:~/tmp/user/ompi$ ./configure --prefix=/home/user/tmp/user/openmpi-tag-slurm --with-slurm=/opt/slurm --with-pmi=/opt/slurm --with-psm2=/usr
make -j 16
make install

# set path to new MPI library
export PATH=/home/user/tmp/user/openmpi-tag-slurm/bin:$PATH
export LD_LIBRARY_PATH=/home/user/tmp/user/openmpi-tag-slurm/lib:$LD_LIBRARY_PATH

user@server:~/tmp/user/ompi$ export PATH=/home/user/tmp/user/openmpi-tag-slurm/bin:$PATH
user@server:~/tmp/user/ompi$ export LD_LIBRARY_PATH=/home/user/tmp/user/openmpi-tag-slurm/lib:$LD_LIBRARY_PATH
user@server:~/tmp/user/ompi$ which mpicc
/home/user/tmp/user/openmpi-tag-slurm/bin/mpicc

--]=]

local util = require "benmet.util"
local templates = require "benmet.step_templates"

local step_config = {
	name = 'build-openmpi',
	params_in = {
		['REPO-PATH-ompi'] = "",
		['REPO-GITCOMMITHASH-ompi'] = 'v3.1.6',
		['PARAM-slurm-base-path'] = "/opt/slurm",
		['PARAM-pmi-base-path'] = "", -- defaults to PARAM-slurm-base-path if empty
		['PARAM-psm2-base-path'] = "/usr",
	},
	params_in_allowed_empty = {'PARAM-pmi-base-path'},
	start_logic = function(params_in, bookkeeping) -- 'start' command
		local cwd = util.get_current_directory()
		local ompi_repo_path = params_in['REPO-PATH-ompi']
		local ompi_install_dir_absolute = cwd.."/built-openmpi-tag-slurm/"
		
		
		-- verify library directories used to build openmpi
		local slurm_base_path = params_in['PARAM-slurm-base-path']
		local pmi_base_path = params_in['PARAM-pmi-base-path']
		pmi_base_path = pmi_base_path ~= "" and pmi_base_path or slurm_base_path
		local psm2_base_path = params_in['PARAM-psm2-base-path']
		
		assert(util.directory_exists(slurm_base_path), "slurm base directory '"..slurm_base_path.."' does not exist. Please provide a different directory via parameter 'PARAM-slurm-base-path'.\nNote: directory name may contain exact version number, f.e. '/opt/slurm-19.05.2'")
		assert(util.directory_exists(pmi_base_path), "pmi base directory '"..pmi_base_path.."' does not exist. Please provide a different directory via parameter 'PARAM-pmi-base-path'.")
		assert(util.directory_exists(psm2_base_path), "psm2 base directory '"..psm2_base_path.."' does not exist. Please provide a different directory via parameter 'PARAM-psm2-base-path'.")
		

		-- build openmpi
		util.ensure_directory_clean(ompi_install_dir_absolute)
		assert(util.execute_command_at("./autogen.pl", ompi_repo_path))
		assert(util.execute_command_at("./configure"
			.. " --prefix="..ompi_install_dir_absolute
			.. " --with-slurm="..util.in_quotes(slurm_base_path)
			.. " --with-pmi="..util.in_quotes(pmi_base_path)
			.. " --with-psm2="..util.in_quotes(psm2_base_path),
			ompi_repo_path))

		assert(util.execute_command_at("make -j 16", ompi_repo_path))
		assert(util.execute_command_at("make install", ompi_repo_path))

		-- environment entries so we can use the openmpi build
		local new_path_entry = ompi_install_dir_absolute.."bin"
		local new_ld_library_path_entry = ompi_install_dir_absolute.."lib/"

		util.prependenv("PATH", new_path_entry..":")
		util.prependenv("LD_LIBRARY_PATH", new_ld_library_path_entry..":")

		-- check mpicc is the correct one
		local expected_mpicc = new_path_entry.."/mpicc"
		local found_mpicc = util.find_program("mpicc")
		assert(found_mpicc == expected_mpicc, "Could not find just-built mpicc after it was added to PATH!\nExpected: '"..expected_mpicc.."'\nFound: '"..tostring(found_mpicc).."'")


		-- declare out parameters for subsequent build steps
		bookkeeping:declare_output_parameter('PARAM-build-openmpi-env-entry-LD_LIBRARY_PATH', new_ld_library_path_entry)
		bookkeeping:declare_output_parameter('PARAM-build-openmpi-env-entry-PATH', new_path_entry)
	end,
}

os.exit(templates.run_standard_step(step_config, --[[cmd_args]] ...))
