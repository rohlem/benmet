--[=[

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
--]=]

local util = require "benmet.util"
local templates = require "benmet.step_templates"

local step_config = {
	name = 'parse-output',
	params_in = {
		['PARAM-result-mode'] = "",
		['PARAM-srun-dispatch-count'] = "",
		['PARAM-mpibenchmark-stdout-file-path-list'] = "",
		['PARAM-mpibenchmark-stderr-file-path-list'] = "",
		['PARAM-mpibenchmark-metrics-output-directory-path'] = "../../../../metrics-mpibenchmark/",
		
		['RUN-id'] = "",
		['RUN-all-params'] = "",
		
		['PARAM-process-sync-broadcast-override-with-user-requested-interval'] = "", -- (potentially) used as the duration; only logged as part of program invocation, not separately
		['PARAM-process-sync-broadcast-duration-multiplier'] = "", -- (potentially) used for calculating the actual duration used; only logged as part of program invocation, not separately
	},
	params_in_allowed_empty = {
		-- not nice, but these need to be checked programmatically because only one may be empty
		'PARAM-process-sync-broadcast-duration-multiplier',
		'PARAM-process-sync-broadcast-override-with-user-requested-interval',
	},
	start_logic = function(params_in, bookkeeping) -- 'start' command
		-- read the input and open the output file
		local all_params_entry_heading = bookkeeping:get_all_params()
		
		local mpibenchmark_output_files = util.json_decode(params_in['PARAM-mpibenchmark-stdout-file-path-list'])
		local expected_output_file_count = params_in['PARAM-srun-dispatch-count']
		expected_output_file_count = assert(tonumber(expected_output_file_count), "parameter 'PAAM-srun-dispatch-count' must be a number, received '"..tostring(expected_output_file_count).."'")
		assert(#mpibenchmark_output_files == expected_output_file_count, "expected "..expected_output_file_count.." output files to read, received "..#mpibenchmark_output_files)
		local mpibenchmark_outputs = {}
		for i = 1, #mpibenchmark_output_files do
			mpibenchmark_outputs[i] = util.read_full_file(mpibenchmark_output_files[i])
		end
		
		local result_mode = params_in['PARAM-result-mode']
		local column_names
		if result_mode == 'summary' then
			column_names = {"test","count","total_nrep","valid_nrep","mean_sec","median_sec","min_sec","max_sec"}
		elseif result_mode == 'individual' then
			column_names = {"test", "nrep", "count", "runtime_sec"}
		else
			error("unrecognized PARAM-result-mode '"..tostring(result_mode).."'")
		end
		local metrics_output_dir = params_in['PARAM-mpibenchmark-metrics-output-directory-path']
		util.ensure_directories(metrics_output_dir)
		local metrics_output_file = assert(io.open(metrics_output_dir.."/"..bookkeeping:get_run_id()..".txt", 'a+'))
		assert(metrics_output_file:write("\n"))
		
		
		-- parsing code
		local parse_to_line_metrics = function(mpibenchmark_output)
				local metrics_by_line = {}
				local heading_pattern = "%s*"..table.concat(column_names, "%s+").."%s*"
				local found_metrics_heading
				local found_epilogue
				local max_found_column_index = 0
				for input_line in string.gmatch(mpibenchmark_output, "(.-)\n") do
					if string.match(input_line, heading_pattern) then
						if found_metrics_heading then
							print("Warning: found multiple metric headings!")
						end
						found_metrics_heading = true
					elseif found_metrics_heading then
						if string.match(input_line, "%s-Benchmark started at ") then
							if found_epilogue then
								print("Warning: found multiple epilogues")
							end
							found_epilogue = true
						else
							if not found_epilogue then
								local line_metrics = {}
								local column_index = 0
								for column_value in string.gmatch(input_line, "%s*(%S+)") do
									column_index = column_index+1
									local column_name
									if column_index <= #column_names then
										column_name = column_names[column_index]
									else
										if column_index > max_found_column_index then
											print("Warning: found unnamed column value #"..column_index)
										end
										column_name = "metrics-column-"..column_index
									end
									line_metrics[column_name] = column_value
								end
								if column_index < #column_names then
									print("Warning: failed to parse metrics line: '"..input_line.."'")
								end
								metrics_by_line[#metrics_by_line+1] = line_metrics
							end
						end
					end
				end
				return metrics_by_line
			end
		
		
		-- helper function
		local median = function(list)
				list = util.table_copy_shallow(list)
				for i = 1, #list do
					list[i] = tonumber(list[i])
				end
				table.sort(list)
				-- remember: 1-based indexing
				if #list % 2 == 1 then
					local i = (#list+1)/2
					return list[i]
				else
					local i = #list/2
					return (list[i] + list[i+1])/2
				end
			end
		
		
		local find_bcast_base_runtime_s, multiply_list_by_bcast_runtime_mult
		local user_requested_broadcast_interval = params_in['PARAM-process-sync-broadcast-override-with-user-requested-interval']
		if user_requested_broadcast_interval ~= "" then -- provide stubs
			find_bcast_base_runtime_s = function() return user_requested_broadcast_interval end
			multiply_list_by_bcast_runtime_mult = function(base_list) return base_list end
		else -- actual processing
			find_bcast_base_runtime_s = function(benchmark_output) -- returns nil if not found
				return string.match(benchmark_output, "#@bcast_runtime_s=([^\n]*)")
			end
			local bcast_runtime_mult = params_in['PARAM-process-sync-broadcast-duration-multiplier']
			bcast_runtime_mult = bcast_runtime_mult ~= "" and bcast_runtime_mult or 10 -- assert(bcast_runtime_mult ~= "", "missing parameter: either 'PARAM-process-sync-broadcast-override-with-user-requested-interval' or 'PARAM-process-sync-broadcast-duration-multiplier' must be given!")
			bcast_runtime_mult = assert(tonumber(bcast_runtime_mult), "failed to parse number from 'PARAM-process-sync-broadcast-duration-multiplier': was "..tostring(bcast_runtime_mult))
			multiply_list_by_bcast_runtime_mult = function(base_list)
				local result = {}
				for i=1, #base_list do
					local base = tonumber(base_list[i])
					result[i] = base and base * bcast_runtime_mult
				end
				return result
			end
		end
		
		-- output code
		if result_mode == 'summary' then -- in this case it makes sense to precompute min, mean, median and max; otherwise we leave that off to further analysis (recommended to remove warmup cycles)
			
			--semantically regroup metrics, because maybe one execution ordered its output differently? I guess I'm paranoid.
			local metrics_by_file_by_count_by_test = {}
			local bcast_runtime_s_by_file = {}
			for file_index = 1, #mpibenchmark_outputs do
				local metrics_by_line = parse_to_line_metrics(mpibenchmark_outputs[file_index])
				for i = 1, #metrics_by_line do
					local line_metrics = metrics_by_line[i]
					
					local metrics_by_file_by_count = metrics_by_file_by_count_by_test[line_metrics.test] or {}
					metrics_by_file_by_count_by_test[line_metrics.test] = metrics_by_file_by_count
					
					local metrics_by_file = metrics_by_file_by_count[line_metrics.count] or {}
					metrics_by_file_by_count[line_metrics.count] = metrics_by_file
					
					metrics_by_file[file_index] = line_metrics
				end
				bcast_runtime_s_by_file[file_index] = find_bcast_base_runtime_s(mpibenchmark_outputs[file_index])
			end
			local bcast_runtime_base_s_list = util.json_encode(bcast_runtime_s_by_file)
			local bcast_runtime_estimate_s_list = util.json_encode(multiply_list_by_bcast_runtime_mult(bcast_runtime_s_by_file))
			
			-- Aggregate output values. Also give them better names.
			-- For every entry, output a full value list and the median value for every property.
			
			-- fully overwritten every file loop iteration
			local total_number_repititions_list = {}
			local valid_number_repititions_list = {}
			local min_execution_time_seconds_list = {}
			local median_execution_time_seconds_list = {}
			local mean_execution_time_seconds_list = {}
			local max_execution_time_seconds_list = {}
			local output_entry = {}
			
			-- the only static entries
			output_entry['RUN-process-sync-broadcast-estimate-base-duration-seconds-list'] = bcast_runtime_base_s_list
			output_entry['RUN-process-sync-broadcast-estimate-duration-seconds-list'] = bcast_runtime_estimate_s_list
			
			for mpi_call, metrics_by_file_by_count in pairs(metrics_by_file_by_count_by_test) do
				output_entry['RUN-mpi-call-test'] = mpi_call
				for message_size_bytes, metrics_by_file in pairs(metrics_by_file_by_count) do
					output_entry['RUN-mpi-call-message-size-bytes'] = message_size_bytes
					
					for i = 1, #metrics_by_file do
						local metrics_entry = metrics_by_file[i]
						total_number_repititions_list[i] = metrics_entry.total_nrep
						valid_number_repititions_list[i] = metrics_entry.valid_nrep
						
						min_execution_time_seconds_list[i] = metrics_entry.min_sec
						median_execution_time_seconds_list[i] = metrics_entry.median_sec
						mean_execution_time_seconds_list[i] = metrics_entry.mean_sec
						max_execution_time_seconds_list[i] = metrics_entry.max_sec
					end
					
					output_entry['RUN-total-number-repititions-list'] = util.json_encode(total_number_repititions_list)
					output_entry['RUN-total-number-repititions-median'] = median(total_number_repititions_list)
					
					output_entry['RUN-valid-number-repititions-list'] = util.json_encode(valid_number_repititions_list)
					output_entry['RUN-valid-number-repititions-median'] = median(valid_number_repititions_list)
					
					output_entry['RUN-min-execution-time-seconds-list'] = util.json_encode(min_execution_time_seconds_list)
					output_entry['RUN-min-execution-time-seconds-median'] = median(min_execution_time_seconds_list)
					
					output_entry['RUN-median-execution-time-seconds-list'] = util.json_encode(median_execution_time_seconds_list)
					output_entry['RUN-median-execution-time-seconds-median'] = median(median_execution_time_seconds_list)
					-- for median runtime, also output the average of median runtimes: since average runtime is reported, maybe this could be useful too?
					local median_execution_time_seconds_average = 0
					for i = 1, #median_execution_time_seconds_list do
						median_execution_time_seconds_average = median_execution_time_seconds_average + median_execution_time_seconds_list[i]
					end
					median_execution_time_seconds_average = median_execution_time_seconds_average / #median_execution_time_seconds_list
					output_entry['RUN-median-execution-time-seconds-average'] = median_execution_time_seconds_average
					
					output_entry['RUN-mean-execution-time-seconds-list'] = util.json_encode(mean_execution_time_seconds_list)
					output_entry['RUN-mean-execution-time-seconds-median'] = median(mean_execution_time_seconds_list)
					
					output_entry['RUN-max-execution-time-seconds-list'] = util.json_encode(max_execution_time_seconds_list)
					output_entry['RUN-max-execution-time-seconds-median'] = median(max_execution_time_seconds_list)
					
					assert(metrics_output_file:write(all_params_entry_heading, util.new_compat_serialize(output_entry), "\n"))
				end
			end
			
		elseif result_mode == 'individual' then
			
			--semantically regroup metrics, because maybe one execution ordered its output differently? I guess I'm paranoid.
			local individual_metric_lists_by_file_by_count_by_test = {}
			local bcast_runtime_s_by_file = {}
			for file_index = 1, #mpibenchmark_outputs do
				local metrics_by_line = parse_to_line_metrics(mpibenchmark_outputs[file_index])
				for i = 1, #metrics_by_line do
					local line_metrics = metrics_by_line[i]
					
					local individual_metric_lists_by_file_by_count = individual_metric_lists_by_file_by_count_by_test[line_metrics.test] or {}
					individual_metric_lists_by_file_by_count_by_test[line_metrics.test] = individual_metric_lists_by_file_by_count
					
					local individual_metric_lists_by_file = individual_metric_lists_by_file_by_count[line_metrics.count] or {}
					individual_metric_lists_by_file_by_count[line_metrics.count] = individual_metric_lists_by_file
					
					local individual_metric_list = individual_metric_lists_by_file[file_index] or {}
					individual_metric_lists_by_file[file_index] = individual_metric_list
					
					individual_metric_list[#individual_metric_list+1] = line_metrics
				end
				bcast_runtime_s_by_file[file_index] = find_bcast_base_runtime_s(mpibenchmark_outputs[file_index])
			end
			local bcast_runtime_base_s_list = util.json_encode(bcast_runtime_s_by_file)
			local bcast_runtime_estimate_s_list = util.json_encode(multiply_list_by_bcast_runtime_mult(bcast_runtime_s_by_file))
			
			-- helper function: constructs a JSON array string with number values instead of strings,
			--  which removes superfluous string escaping when nested within another string (\" at start and end totals to 4 bytes per value)
			local numbers_to_json_array_string = function(number_string_array)
					local to_concat = {"["}
					local n = 2
					if #number_string_array > 0 then
						local number_string = number_string_array[1]
						if not tonumber(number_string) then error("expected a number, received "..tostring(number_string)) end
						to_concat[n] = number_string
						n = n+1
						for i = 2, #number_string_array do
							to_concat[n] = ","
							number_string = number_string_array[i]
							if not tonumber(number_string) then error("expected a number, received "..tostring(number_string)) end
							to_concat[n+1] = number_string
							n = n+2
						end
					end
					to_concat[n] = "]"
					return table.concat(to_concat)
				end
			
			-- Aggregate output values.
			-- For every parameter combination, output a list of full value lists (as a string describing a json array).
			
			-- fully overwritten every parameter loop iteration
			local execution_time_runtime_sec_lists = {}
			local output_entry = {}
			
			-- the only static entries
			output_entry['RUN-process-sync-broadcast-estimate-base-duration-seconds-list'] = bcast_runtime_base_s_list
			output_entry['RUN-process-sync-broadcast-estimate-duration-seconds-list'] = bcast_runtime_estimate_s_list
			
			for mpi_call, individual_metric_lists_by_file_by_count in pairs(individual_metric_lists_by_file_by_count_by_test) do
				output_entry['RUN-mpi-call-test'] = mpi_call
				for message_size_bytes, individual_metric_lists_by_file in pairs(individual_metric_lists_by_file_by_count) do
					output_entry['RUN-mpi-call-message-size-bytes'] = message_size_bytes
					
					for file_index = 1, #individual_metric_lists_by_file do
						local individual_metric_lists = individual_metric_lists_by_file[file_index]
						local runtime_sec_list = {}
						n = 1
						for i = 1, #individual_metric_lists do
							local metrics_entry = individual_metric_lists[i]
							runtime_sec_list[n] = metrics_entry.runtime_sec
							n = n+1
						end
						execution_time_runtime_sec_lists[file_index] = numbers_to_json_array_string(runtime_sec_list)
					end
					
					output_entry['RUN-execution-time-seconds-list-per-dispatch'] = util.json_encode(execution_time_runtime_sec_lists)
					
					assert(metrics_output_file:write(all_params_entry_heading, util.new_compat_serialize(output_entry), "\n"))
				end
			end
			
		else
			error("(unreachable) unrecognized PARAM-result-mode '"..tostring(result_mode).."'")
		end
		
		assert(metrics_output_file:close())
	end,
}

os.exit(templates.run_standard_step(step_config, --[[cmd_args]] ...))
