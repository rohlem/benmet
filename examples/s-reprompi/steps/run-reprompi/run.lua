--[=[

user@server:~/tmp/user$ pwd
/home/user/tmp/user

git clone https://github.com/hunsa/reprompi

# set path to new MPI library
export LD_LIBRARY_PATH=/home/user/tmp/user/openmpi-tag-slurm/lib:$LD_LIBRARY_PATH

user@server:~/tmp/user/ompi$ export LD_LIBRARY_PATH=/home/user/tmp/user/openmpi-tag-slurm/lib:$LD_LIBRARY_PATH


# run the benchmark
user@server:~/tmp/user/reprompi$ srun -N 2 --ntasks-per-node=2 ./bin/mpibenchmark  --msizes-list=1,10,100,1000,10000 --calls-list=MPI_Allreduce --nrep=10
#Command-line arguments:  /home/user/tmp/user/reprompi/./bin/mpibenchmark --msizes-list=1,10,100,1000,10000 --calls-list=MPI_Allreduce --nrep=10
#MPI calls:
#    MPI_Allreduce
#Message sizes:
#    1
#    10
#    100
#    1000
#    10000
#@operation=MPI_BOR
#@datatype=MPI_BYTE
#@datatype_extent_bytes=1
#@datatype_size_bytes=1
#@root_proc=0
#@reproMPIcommitSHA1=00325471f9a39c5ffc35796f360fb02838cbef84
#@nprocs=4
#@clocktype=local
#@clock=MPI_Wtime
#@sync=MPI_Barrier
#@nrep=10
                                              test       nrep        count    runtime_sec
                                     MPI_Allreduce          0            1   0.0000109819
                                     MPI_Allreduce          1            1   0.0000030911
                                     MPI_Allreduce          2            1   0.0000029809
                                     MPI_Allreduce          3            1   0.0000027870
                                     MPI_Allreduce          4            1   0.0000027970
                                     MPI_Allreduce          5            1   0.0000030100
                                     MPI_Allreduce          6            1   0.0000031460
                                     MPI_Allreduce          7            1   0.0000041078
                                     MPI_Allreduce          8            1   0.0000052340
                                     MPI_Allreduce          9            1   0.0000029281
                                     MPI_Allreduce          0           10   0.0000043900
                                     MPI_Allreduce          1           10   0.0000029460
                                     MPI_Allreduce          2           10   0.0000026431
                                     MPI_Allreduce          3           10   0.0000028498
                                     MPI_Allreduce          4           10   0.0000032880
                                     MPI_Allreduce          5           10   0.0000030322
                                     MPI_Allreduce          6           10   0.0000040331
                                     MPI_Allreduce          7           10   0.0000035909
                                     MPI_Allreduce          8           10   0.0000033511
                                     MPI_Allreduce          9           10   0.0000028159
                                     MPI_Allreduce          0          100   0.0000114988
                                     MPI_Allreduce          1          100   0.0000069689
                                     MPI_Allreduce          2          100   0.0000050690
                                     MPI_Allreduce          3          100   0.0000078520
                                     MPI_Allreduce          4          100   0.0000048620
                                     MPI_Allreduce          5          100   0.0000067770
                                     MPI_Allreduce          6          100   0.0000045670
                                     MPI_Allreduce          7          100   0.0000079640
                                     MPI_Allreduce          8          100   0.0000043770
                                     MPI_Allreduce          9          100   0.0000072862
                                     MPI_Allreduce          0         1000   0.0000128301
                                     MPI_Allreduce          1         1000   0.0000069591
                                     MPI_Allreduce          2         1000   0.0000067810
                                     MPI_Allreduce          3         1000   0.0000108860
                                     MPI_Allreduce          4         1000   0.0000068850
                                     MPI_Allreduce          5         1000   0.0000102632
                                     MPI_Allreduce          6         1000   0.0000077530
                                     MPI_Allreduce          7         1000   0.0000091919
                                     MPI_Allreduce          8         1000   0.0000100289
                                     MPI_Allreduce          9         1000   0.0000079849
                                     MPI_Allreduce          0        10000   0.0004525720
                                     MPI_Allreduce          1        10000   0.0000317588
                                     MPI_Allreduce          2        10000   0.0000260610
                                     MPI_Allreduce          3        10000   0.0000294531
                                     MPI_Allreduce          4        10000   0.0000327060
                                     MPI_Allreduce          5        10000   0.0000302561
                                     MPI_Allreduce          6        10000   0.0000257911
                                     MPI_Allreduce          7        10000   0.0000268391
                                     MPI_Allreduce          8        10000   0.0000296871
                                     MPI_Allreduce          9        10000   0.0000303672
# Benchmark started at Mon Oct 12 22:14:38 2020
# Execution time: 0s


# you can also run with a summary
user@server:~/tmp/user/reprompi$ srun -N 2 --ntasks-per-node=2 ./bin/mpibenchmark  --msizes-list=1,10,100,1000,10000 --calls-list=MPI_Allreduce --nrep=10 --summary
#Command-line arguments:  /home/user/tmp/user/reprompi/./bin/mpibenchmark --msizes-list=1,10,100,1000,10000 --calls-list=MPI_Allreduce --nrep=10 --summary
#MPI calls:
#    MPI_Allreduce
#Message sizes:
#    1
#    10
#    100
#    1000
#    10000
#@operation=MPI_BOR
#@datatype=MPI_BYTE
#@datatype_extent_bytes=1
#@datatype_size_bytes=1
#@root_proc=0
#@reproMPIcommitSHA1=00325471f9a39c5ffc35796f360fb02838cbef84
#@nprocs=4
#@clocktype=local
#@clock=MPI_Wtime
#@sync=MPI_Barrier
#@nrep=10
                                              test        count total_nrep valid_nrep       mean_sec     median_sec        min_sec        max_sec
                                     MPI_Allreduce            1         10         10   0.0000038767   0.0000027941   0.0000022941   0.0000097081
                                     MPI_Allreduce           10         10         10   0.0000033106   0.0000030460   0.0000028401   0.0000047381
                                     MPI_Allreduce          100         10         10   0.0000064546   0.0000060489   0.0000035870   0.0000096729
                                     MPI_Allreduce         1000         10         10   0.0000096126   0.0000105451   0.0000066999   0.0000129761
                                     MPI_Allreduce        10000         10         10   0.0000719138   0.0000303395   0.0000269210   0.0004507860
# Benchmark started at Mon Oct 12 22:15:25 2020
# Execution time: 0s

# reprompi-dev also supports limiting by execution time in addition to (or instead of) number of repetitions:

srun --distribution block:cyclic --cpu-freq=High -N 16 --ntasks-per-node=32 ./bin/mpibenchmark --msizes=10000 --calls-list=MPI_Bcast --nrep=50000 --runtime-type=global --clock-sync=None --proc-sync=roundtime --bcast-mult=10 --bcast-meas=mean --bcast-nrep=30 --rt-bench-time-ms=2000 --summary 
--]=]

local util = require "benmet.util"
local templates = require "benmet.step_templates"

local step_config = {
	name = 'run-reprompi',
	params_in = {
		-- paths that link back to the previous stages
		['PARAM-build-openmpi-env-entry-LD_LIBRARY_PATH'] = "",
		['PARAM-build-openmpi-env-entry-PATH'] = "",
		['PARAM-build-reprompi-bin-path'] = "",
		
		-- srun parameters
		['PARAM-srun-queue'] = "q_thesis",
		['PARAM-execution-nodes'] = 2,
		['PARAM-cpu-frequency-mode'] = 'high',
		['PARAM-slurm-exclude-execution-nodes'] = "",
		['PARAM-tasks-per-execution-node'] = 2,
		['PARAM-srun-time-allocated-per-dispatch'] = "1:00",
		['PARAM-srun-dispatch-count'] = "5",
		
		-- reprompi ./mpibenchmark parameters
		['PARAM-message-sizes-list'] = "1,10,100,1000,10000",
		['PARAM-calls-list'] = "MPI_Allreduce",--"MPI_Bcast",
		['PARAM-number-repetitions'] = 50000,
		['PARAM-rt-bench-time-ms'] = 4000,
		['PARAM-result-mode'] = 'individual', -- note: warmup periods make the aggregated ouptuts (which are the only outputs) of 'summary' mode less useful in many cases
		['PARAM-process-sync-broadcast-duration-base-measure'] = "", -- one of 'mean', 'median', 'max'; defaults to 'mean'
		['PARAM-process-sync-broadcast-duration-multiplier'] = "", -- defaults to 10
		['PARAM-process-sync-broadcast-repetitions'] = "", -- defaults to 30
		['PARAM-process-sync-broadcast-override-with-user-requested-interval'] = "", -- custom argument --bcast-requested-interval in custom branch proc-sync-requested-broadcast-interval
		
		-- Open MPI tuning
		['PARAM-btl-selection-priority-list'] = "", -- sensible default would be "self,vader,tcp" , but we let ompi decide if empty
		['PARAM-btl-vader-single-copy-mechanism'] = "", -- for versions 3.* one of "xpmem", "cma", "knem", "none"; versions 4.* also support "emul". Versions 5.* use vastly different structure, so no longer compatible.
		
		-- automatically generate a run id - also declares this step as nondeterministic
		['RUN-id'] = "",
		-- record the hostname, to differentiate metrics from different computers
		['RUN-hostname'] = "",
	},
	params_in_allowed_empty = {
		'PARAM-slurm-exclude-execution-nodes',
		'PARAM-btl-selection-priority-list',
		'PARAM-btl-vader-single-copy-mechanism',
		-- not nice, but these need to be defaulted/checked programmatically because they're incompatible
		'PARAM-process-sync-broadcast-duration-base-measure',
		'PARAM-process-sync-broadcast-duration-multiplier',
		'PARAM-process-sync-broadcast-repetitions',
		'PARAM-process-sync-broadcast-override-with-user-requested-interval',
	},
}

local stage_mpibenchmark = {
	name = 'mpibenchmark',
	completed_sentinel_file_path = './completed_mpibenchmark.txt', -- this is (at the time of writing) the default path
	cancel_logic = function(bookkeeping)
		local pending_params = bookkeeping:get_current_pending_params()
		local pending_job_ids = util.json_decode(pending_params['RUN-mpibenchmark-slurm-job-id-list'])
		assert(util.execute_command("scancel "..table.concat(pending_job_ids, " ")))
	end,
	execute_logic = function(params_in, bookkeeping)
		local result_mode = params_in['PARAM-result-mode']
		local result_mode_flag =
			assert(result_mode == 'summary' and "--summary"
				or result_mode == 'individual' and ""
				, "invalid result mode: '"..tostring(result_mode).."'")
		
		-- add the openmpi build to our path
		local new_path_entry = params_in['PARAM-build-openmpi-env-entry-PATH']
		util.prependenv("LD_LIBRARY_PATH", params_in['PARAM-build-openmpi-env-entry-LD_LIBRARY_PATH']..":")
		
		-- set openmpi tuning parameters
		local btl_selection = params_in['PARAM-btl-selection-priority-list']
		if btl_selection and btl_selection ~= "" then
			util.setenv("OMPI_MCA_btl", btl_selection)
		end
		
		local btl_vader_single_copy_mechanism = params_in['PARAM-btl-vader-single-copy-mechanism']
		if btl_vader_single_copy_mechanism and btl_vader_single_copy_mechanism ~= "" then
			util.setenv("OMPI_MCA_btl_vader_single_copy_mechanism", btl_vader_single_copy_mechanism)
		end
		
		
		local mpibenchmark_process_sync_broadcast_user_requested_interval = params_in['PARAM-process-sync-broadcast-override-with-user-requested-interval']
		local mpibenchmark_process_sync_broadcast_base_measure = params_in['PARAM-process-sync-broadcast-duration-base-measure']
		local mpibenchmark_process_sync_broadcast_duration_multiplier = params_in['PARAM-process-sync-broadcast-duration-multiplier']
		local mpibenchmark_process_sync_broadcast_repetitions = params_in['PARAM-process-sync-broadcast-repetitions']
		local broadcast_arg_string = nil
		if mpibenchmark_process_sync_broadcast_user_requested_interval ~= "" then
			-- make sure incompatible parameters weren't specified
			assert(mpibenchmark_process_sync_broadcast_base_measure == "" and
				mpibenchmark_process_sync_broadcast_duration_multiplier == "" and
				mpibenchmark_process_sync_broadcast_repetitions == "",
				"manually requested process synchronization broadcast interval ('PARAM-process-sync-broadcast-override-with-user-requested-interval') is incompatible with initial broadcast parameters 'PARAM-process-sync-broadcast-duration-base-measure', 'PARAM-process-sync-broadcast-duration-multiplier' and 'PARAM-process-sync-broadcast-repetitions'")
			mpibenchmark_process_sync_broadcast_base_measure = nil
			mpibenchmark_process_sync_broadcast_duration_multiplier = nil
			mpibenchmark_process_sync_broadcast_repetitions = nil
			
			-- construct program argument section
			broadcast_arg_string = " --bcast-requested-interval="..mpibenchmark_process_sync_broadcast_user_requested_interval
		else
			mpibenchmark_process_sync_broadcast_user_requested_interval = nil
			
			-- manual default values
			mpibenchmark_process_sync_broadcast_base_measure = mpibenchmark_process_sync_broadcast_base_measure ~= "" and mpibenchmark_process_sync_broadcast_base_measure
				or 'mean'
			mpibenchmark_process_sync_broadcast_duration_multiplier = mpibenchmark_process_sync_broadcast_duration_multiplier ~= "" and mpibenchmark_process_sync_broadcast_duration_multiplier
				or 10
			mpibenchmark_process_sync_broadcast_repetitions = mpibenchmark_process_sync_broadcast_repetitions ~= "" and mpibenchmark_process_sync_broadcast_repetitions
				or 30
			
			-- check parameters
			if mpibenchmark_process_sync_broadcast_base_measure ~= 'mean' and
				mpibenchmark_process_sync_broadcast_base_measure ~= 'median' and
				mpibenchmark_process_sync_broadcast_base_measure ~= 'max' then
				error("invalid (unrecognized) value for 'PARAM-process-sync-broadcast-duration-base-measure': '"..tostring(mpibenchmark_process_sync_broadcast_base_measure).."'")
			end
			mpibenchmark_process_sync_broadcast_duration_multiplier = assert(tonumber(mpibenchmark_process_sync_broadcast_duration_multiplier), "failed to parse numeric value from 'PARAM-process-sync-broadcast-duration-multiplier'")
			mpibenchmark_process_sync_broadcast_repetitions = assert(tonumber(mpibenchmark_process_sync_broadcast_repetitions), "failed to parse numeric value from 'PARAM-process-sync-broadcast-repetitions'")
			
			-- construct program argument section
			broadcast_arg_string = " --bcast-mult="..mpibenchmark_process_sync_broadcast_duration_multiplier
				.." --bcast-meas="..mpibenchmark_process_sync_broadcast_base_measure
				.." --bcast-nrep="..mpibenchmark_process_sync_broadcast_repetitions
		end
		assert(broadcast_arg_string)
		
		-- look for the reprompi benchmark program
		local reprompi_build_bin_dir = params_in['PARAM-build-reprompi-bin-path']
		local reprompi_mpibenchmark_path = reprompi_build_bin_dir.."/mpibenchmark"
		assert(util.file_exists(reprompi_mpibenchmark_path))
		
		
		-- we (potentially) dispatch multiple jobs for more representative result data
		local dispatch_count = params_in['PARAM-srun-dispatch-count']
		dispatch_count = assert(tonumber(dispatch_count), "parameter 'PARAM-srun-dispatch-count' should be a number, was '"..dispatch_count.."'")
		
		local job_id_list = {}
		local mpibenchmark_stdout_file_list = {}
		local mpibenchmark_stderr_file_list = {}
		
		for dispatch_index = 1, dispatch_count do
			local dispatch_file_suffix = dispatch_count == 1 and ""
				or "-"..dispatch_index
			local dispatch_message_suffix_string = dispatch_count == 1 and ""
				or " #"..dispatch_index
			
			local stdout_file = "slurm-mpibenchmark"..dispatch_file_suffix..".out"
			local stderr_file = "slurm-mpibenchmark"..dispatch_file_suffix..".err"
			
			
			local exclude_string = params_in['PARAM-slurm-exclude-execution-nodes']
			exclude_string = exclude_string and " --exclude="..exclude_string or ""
			
			-- build the job to run the reprompi benchmark program we want to dispatch via sbatch
			local slurm_dispatch_args =
				" -p "..params_in['PARAM-srun-queue']
				.." -N "..params_in['PARAM-execution-nodes']
				.." --cpu-freq="..params_in['PARAM-cpu-frequency-mode']
				..exclude_string
				.." --ntasks-per-node="..params_in['PARAM-tasks-per-execution-node']
				.." --time="..params_in['PARAM-srun-time-allocated-per-dispatch']
			local srun_job =
				"#! /bin/sh\n"
				.."srun"
				.." --kill-on-bad-exit=1"
				.." -o '"..stdout_file.."'"
				.." -e \""..stderr_file.."\""
				..slurm_dispatch_args
				.." "..reprompi_mpibenchmark_path
				.." --msizes-list="..params_in['PARAM-message-sizes-list']
				.." --calls-list="..params_in['PARAM-calls-list']
				.." --nrep="..params_in['PARAM-number-repetitions']
				.." --runtime-type=global --clock-sync=None --proc-sync=roundtime"
				..broadcast_arg_string
				.." --rt-bench-time-ms="..params_in['PARAM-rt-bench-time-ms']
				.." "..result_mode_flag
				.." && "
				.."touch "..util.in_quotes('./completed_mpibenchmark'..dispatch_file_suffix..'.txt') -- note: if dispatch_count == 1, this degenerates to .completed_sentinel_file_path, which makes step_templates skip the call t .test_pending_for_completion_logic, because the stage is already completed at that point. .ready_check_logic is still executed however.
			srun_job = string.gsub(string.gsub(string.gsub(srun_job, "\\", "\\\\") -- escape backslashes
						, "\"", "\\\""), -- so we can escape quotes
					"\n", "\\n") -- finally escape newlines
			
			-- dispatch it via printf (the shell command, apparently 'echo' is outdated?)
			local sbatch_stdout_file = "slurm-job"..dispatch_file_suffix..".out"
			local sbatch_stderr_file = "slurm-job"..dispatch_file_suffix..".err"
			local successful, exit_by, return_status, program_output = util.execute_command("printf \""..srun_job.."\" | sbatch -o '"..sbatch_stdout_file.."' -e '"..sbatch_stderr_file.."'"..slurm_dispatch_args)
			assert(successful, "failed submitting job"..dispatch_message_suffix_string.." via sbatch")
			
			
			local job_id = assert(string.match(program_output, "Submitted batch job (%S+)"))
			job_id = assert(tonumber(job_id))
			job_id_list[#job_id_list+1] = job_id
			mpibenchmark_stdout_file_list[#mpibenchmark_stdout_file_list+1] = stdout_file
			mpibenchmark_stderr_file_list[#mpibenchmark_stderr_file_list+1] = stderr_file
		end
		
		-- declare the job ids as intermediary parameters (to support 'cancel' command and 'status' to check for error)
		bookkeeping:declare_pending_parameter('RUN-mpibenchmark-slurm-job-id-list', util.json_encode(job_id_list))
		
		-- declare output parameters for subsequent steps
		local cwd = util.get_current_directory()
		for i = 1, #mpibenchmark_stdout_file_list do
			mpibenchmark_stdout_file_list[i] = cwd.."/"..mpibenchmark_stdout_file_list[i]
		end
		for i = 1, #mpibenchmark_stderr_file_list do
			mpibenchmark_stderr_file_list[i] = cwd.."/"..mpibenchmark_stderr_file_list[i]
		end
		bookkeeping:declare_output_parameter('PARAM-mpibenchmark-stdout-file-path-list', util.json_encode(mpibenchmark_stdout_file_list))
		bookkeeping:declare_output_parameter('PARAM-mpibenchmark-stderr-file-path-list', util.json_encode(mpibenchmark_stderr_file_list))
		
		bookkeeping:declare_stage_pending()
	end,
	test_pending_for_completion_logic = function(bookkeeping)
		-- query pending job ids from pending params
		local pending_params = bookkeeping:get_current_pending_params()
		local pending_job_ids = util.json_decode(pending_params['RUN-mpibenchmark-slurm-job-id-list'])
		-- check if all completion sentinel files were written, which would signal all jobs have completed
		for dispatch_index = 1, #pending_job_ids do
			local dispatch_file_suffix = #pending_job_ids == 1 and ""
				or "-"..dispatch_index
			if not util.file_exists('./completed_mpibenchmark'..dispatch_file_suffix..'.txt') then
				return false -- if one file doesn't exist, the stage isn't completed yet
			end
		end
		
		return true -- if all files existed, the stage is completed
	end,
	test_pending_for_error_logic = function(bookkeeping)
		local pending_params = bookkeeping:get_current_pending_params()
		local pending_job_ids = util.json_decode(pending_params['RUN-mpibenchmark-slurm-job-id-list'])
		
		local successful, exit_by, return_status, program_output = util.execute_command("squeue --noheader --format=\"[%i]\" --job="..table.concat(pending_job_ids, ","))
		if successful then
			for i = 1, #pending_job_ids do
				local job_id = pending_job_ids[i]
				if string.find(program_output, "["..job_id.."]", 1, true) then
					return -- at least one of the jobs we wanted to find is still pending or running, everything is in order
				end
			end
		end
		
		--local squeue_remembers = not string.find(program_output, "slurm_load_jobs error: Invalid job id specified") -- is not output as long as at least one job id is recognized
		return "no slurm job(s) found"
	end,
	ready_check_logic = function(bookkeeping)
		local cwd = util.get_current_directory()
		local params_out = bookkeeping:get_preliminary_params_out()
		local mpibenchmark_stdout_file_list = util.json_decode(params_out['PARAM-mpibenchmark-stdout-file-path-list'])
		for i = 1, #mpibenchmark_stdout_file_list do
			local stdout_file = mpibenchmark_stdout_file_list[i]
			assert(util.file_exists(stdout_file), "missing standard output file of srun dispatch #"..i.." after running mpibenchmark")
		end
		local mpibenchmark_stderr_file_list = util.json_decode(params_out['PARAM-mpibenchmark-stderr-file-path-list'])
		for i = 1, #mpibenchmark_stderr_file_list do
			local stderr_file = mpibenchmark_stderr_file_list[i]
			assert(util.file_exists(stderr_file), "missing error output file of srun dispatch #"..i.." after running mpibenchmark")
		end
	end,
}
templates.async_step_config_add_stage(step_config, stage_mpibenchmark)

os.exit(templates.run_standard_async_step(step_config, --[[cmd_args]] ...))
