This file documents a toy example showing how to use `benmet`.
For details on the inner workings of `benmet`, see ['guide.md'](./guide.md), for a real-world example (with less documentation) see ['examples/s-reprompi'](./examples/s-reprompi).

# Overview

This example samples a simple random number generator program.
The state resulting after each section is provided in a corresponding subdirectory:
- [1-setup](./1-setup) contains the number generator repository in the expected location (inside "./repos").
- [2-execution-part-1](./2-execution-part-1) has a single step configured that can be used for executing the number generator program (its Lua version) with a fixed string of default arguments.
- [3-execution-part-2](./3-execution-part-2) adds parameters to change the program invocation arguments, and introduces a run id to make the execution of the program repeat by default.
- [4-sample-collection](./4-sample-collection) has a second step added for copying identified results into a specified directory. It also showcases parameter passing between the two steps.
- [5-build](./4-build) contains a third step for building the C version of the generator program (C compiler not included).
- [6-configuration](./5-configuration) extends every step by additional configuration parameters.

# Setup

To execute `benmet`, you need a runnable Lua 5.3 interpreter, which we will refer to as `<lua>`. Common names for this program are `lua53`, `lua5.3`, or plain `lua`. You can invoke it with the `-v` flag to output version information.

`benmet` is invoked by its `main.lua` script file. From the current directory, the command would be `<lua53> ../../../main.lua`, optionally followed by further arguments. Within this file, we will refer to this base invocation by `<benmet>`.

Invoking the program as `<benmet>` without further arguments should list the program description and available commands. Note that both relative and absolute paths to the `main.lua` script file are supported.

If you haven't yet, you can execute `benmet`'s `auto-setup` command to clone `benmet`'s own required dependencies: `<benmet> auto-setup`

Create an empty directory. We will execute `benmet` within this as a working directory, which means we consider it our "workspace".

The random number generator program is hosted in a separate repository at the URL https://github.com/rohlem/benmet-tutorial-stub-numgen .
To clone this repository where it is accessible to step programs, execute `<benmet> add-repo https://github.com/rohlem/benmet-tutorial-stub-numgen` inside the created directory. This will clone it to the path `./repos/benmet-tutorial-stub-numgen`. Execute `<benmet> add-repo --help` to see further options.

# Execution Part 1 - executing numgen.lua

After the previous section "Setup", the number generator repository is now located at `./repos/benmet-tutorial-stub-numgen`.

The Lua version of it can be executed in a Lua interpreter `<lua53>`, for example as `<lua53> ./repos/benmet-tutorial-stub-numgen/numgen.lua w 0 5`, where the third argument determines the amount of numbers to generate.

To integrate this with `benmet`, we will write a step program that executes the program for us.

## integrating the step program

Create directories `./steps` and `./steps/execute-numgen`. Now create a file `./steps/execute-numgen/step.lua`, which will be our step program implementation, with the following contents:

```lua
assert(#arg == 1, "incorrect number of arguments")
local command = arg[1]
error("unrecognized command '"..command.."'")
```

Steps are always started with exactly one argument, the step command.
Our implementation checks the number of arguments, before aborting with the requested command as part of its error message.

To execute a step, `benmet` needs to know whether it depends on any other steps.
For this purpose, create a file `./steps/index.txt` with the following contents:

```
execute-numgen/step.lua:
```

The non-empty line identifies that the step `execute-numgen` is implemented by file `step.lua`, and has no dependencies (no space-separated names to the right of the colon).

We can now request a specific command from the step, for example:
```sh
$ <benmet> step.do execute-numgen --command inputs
failed to run build step command 'inputs'
```

Because our script calls `error`, which exits with non-zero status, `benmet`'s output will contain a failure message. So let's fix that next.

## implementing the 'inputs' command

The 'inputs' command is used to query which input parameters the step program accepts. These are written to stdout in JSON format, as an object with one field per input parameter, set to its default value.

Add the following lines to our `step.lua` script, before the call to `error`:

```lua
if command == 'inputs' then
	print("{}")
	os.exit(0)
end
```

This makes our program output an empty JSON object, meaning that it accepts no parameters for now, and exit successfully, if the command was 'inputs'.
Now `benmet`'s output to the same request should look different:

```sh
$ <benmet> step.do execute-numgen --command inputs
{}
```

For the 'inputs' command, it simply forwarded what the step program reported, in this case the empty object.

## implementing the 'status' command

Multiple executions (named `run`s) of a step can coexist, so every execution is given a dedicated working subdirectory `./steps/<step-name>/runs/<input hash>` in which it is executed.
This directory holds a file `input_params.txt` with all input parameters in form of a JSON object.

Executions can suspend themselves if they need to wait for external work (for example a task queued on another server), or signal an execution error.

The 'status' command is a place to implement logic for checking the state of a `run`. It must output one of the predefined responses to stdout:
- `startable` means it is ready to execute (nothing done yet)
- `finished` means it finished execution
- `pending` means it cannot continue before an external operation has finished
- `continuable` means all external operations have completed and it is ready to continue
- `error` means something unexpected happened, and the step cannot continue execution (needs to be reset and/or inspected manually)

If a step exits with status 0, it either created a file `output_params.txt` to signal completion, or did not create that file to signal that it suspended.

Since our step `execute-numgen` does not support suspension, we only need to check if it has already completed, which can be done with the following code:

```lua
local util = require 'benmet.util'

if command == 'status' then
	if util.file_exists("output_params.txt") then
		print("finished")
	elseif util.file_exists("input_params.txt") then
		print("startable")
	else
		print("error: no input parameters")
		os.exit(1)
	end
	os.exit(0)
end
```

This code segment needs to be added to `./steps/execute-numgen/step.lua`, again before the call to `error` (otherwise it won't be reached).

Step programs written in Lua are given access to benmet's own files. As you can see, above we use the function `file_exists` of the `benmet.util` module (source file `util.lua`).

## implementing the 'start' command

Finally, the 'start' command implements the actual operation the step represents.

For `execute-numgen` we want to execute the `numgen.lua` script with some default arguments, for example `w 0 10`.

The lua interpreter that was used to start benmet can be queried using `util.get_lua_program()`. For now let's pipe the output directly into a file `numgen_results.txt`.

The following code can be used to implement the command:

```lua
if command == 'start' then
	local lua_program = util.get_lua_program()
	
	local numgen_path = "../../../../repos/benmet-tutorial-stub-numgen/numgen.lua"
	local argument_string = "w 0 10"
	
	local output_file_path = "numgen_result.txt"
	assert(util.execute_command(lua_program.." "..numgen_path.." "..argument_string.." > "..output_file_path))
	
	util.write_full_file("params_out.txt", "{}")
	os.exit(0)
end
```

For now the argument string and the program location are simply hardcoded.

Executing the start command via `benmet` should now no longer result in an error, and executing the `status` command following this will report status `finished`.

```sh
$ <benmet> step.do execute-numgen --command start

$ <benmet> step.do execute-numgen --command status
finished
```

Note that the working directory created for this purpose can be found under `./steps/execute-numgen/runs/`.

# Execution Part 2 - parameters and repeating execution by default

## adding input parameters

Next we will discuss parameters. Every step execution has access to the set of parameters it is interested in, given in a file called `params_in.txt`.

If you have executed the 'execute-numgen' step at least once in the last section, you should see a single directory under `./steps/execute-numgen/runs/` containing such a file. If you look into it, it will only contain the empty JSON object "{}".

This is because our implementation of the 'inputs' command also returns an empty JSON object. If we add fields with defaults value to the 'inputs' response, those default values will be used to fill the execution's input parameters. For example, we can change the `print` command to the following:

```lua
print([[{
"PARAM-numgen-noise-type":"w",
"PARAM-numgen-filter-flag":"0",
"PARAM-numgen-amount":"2"
}]])
```

Here we use Lua's long string literal syntax "\[\[ ... \]\]" to allow quotation marks and line breaks; alternatively you could single-quote '' the string with \n as line ending, or prefix them with a backslash \\.

If we query the 'inputs' command again, we will see the changed default values. Invoking the 'start' command will create a new run directory with a changed `params_in.txt` containing our default parameters.

```sh
$ <benmet> step.do execute-numgen --command inputs
{
"PARAM-numgen-noise-type":"w",
"PARAM-numgen-filter-flag":"0",
"PARAM-numgen-amount":"2"
}

$ <benmet> step.do execute-numgen --command start
```

However, our code still ignores these input paramters. If you check the `numgen_result.txt` file generated in the new run directory, it still contains 10 numbers rather than 2.

We need to make our step program parse them and construct the program arguments accordingly. This can be done via the following code for the start command:

```lua
local input_params = util.read_param_file_new_compat_deserialize("params_in.txt")
local argument_string = input_params["PARAM-numgen-noise-type"]
	.." "..input_params["PARAM-numgen-filter-flag"]
	.." "..input_params["PARAM-numgen-amount"]
```

Note that we skip checking these parameters here for brevity, since numgen.lua features built-in parameter checking.

If you delete the run directory (or delete the file `params_out.txt` to reset the execution) and re-execute the 'start' command, the new `numgen_result.txt` file will only contain 2 numbers, as requested.

```sh
$ <benmet> step.do execute-numgen --command start
```

## making the 'start' command repeat execution by default

As you may have noticed sooner or later, our 'execute-numgen' step currently still only wants to execute once. Subsequent executions are skipped:

```sh
$ <benmet> step.do execute-numgen --command start
found cache hit with status 'finished', eliding execution
finished
```

This is because `benmet` recognizes parameterizations you have used before (by their hash, which is used as run directory name).

For prerequisite steps, such as building a program from source code, this behaviour is pretty handy. However, as this is our sampling step , we usually want a request for new samples to re-execute the program.

The solution to this is to declare a special input parameter, named "RUN-id". `benmet` always defaults this parameter to a unique value.

To do this, just add an entry `"RUN-id":""` to the 'inputs' command response. Upon this change, repeated execution of the start command should no longer result in cache hits, instead always creating a new run directory in `./steps/execute-numgen/runs/` .

```sh
$ <benmet> step.do execute-numgen --command start

```

You may also note that executing the `status` command will no longer report status `finished` either. To now refer to a run, you will have to explicitly assign it an id, using the `--with-run-id` option:

```sh
$ <benmet> step.do execute-numgen --command status
run directory for step 'execute-numgen' with given parameters does not exist

$ <benmet> step.do execute-numgen --command start --with-run-id="abc"

$ <benmet> step.do execute-numgen --command status --with-run-id="abc"
finished

$ <benmet> step.do execute-numgen --command start --with-run-id="abc"
found cache hit with status 'finished', eliding execution
finished
```

## manually setting parameters

So far we've just been using the default values of our step's input parameters. To actually configure it, you can supply a parameter file, which is any file holding a single JSON object. For example, create a file `params_p7.json` with the following contents:

```js
{
"PARAM-numgen-noise-type":"p",
"PARAM-numgen-amount":"7"
}
```

Parameters that are not supplied will be filled in by their default values. Note that requiring a parameter to be specified manually is not currently supported; a workaround is to assert that they differ from the empty string "" in the step program, erroring (non-zero exit) if they don't.

We can now pass the parameterization from this file to `benmet` using the `--param-file` option:
```
$ <benmet> step.do execute-numgen --command start --param-file params_p7.json
```

The newly created run directory will have input parameters indicating 7 numbers of pink noise (type "p"), and the `numgen_result.txt` file will hold 7 numbers.

You can also execute `<benmet> step.do --help` for further details on all supported options.
