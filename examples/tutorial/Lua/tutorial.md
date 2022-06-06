This file documents a toy example showing how to use `benmet`.
For details on the inner workings of `benmet`, see ['guide.md'](./guide.md), for a real-world example (with less documentation) see ['examples/s-reprompi'](./examples/s-reprompi).

# Overview

This example samples a simple random number generator program.
The state resulting after each section is provided in a corresponding subdirectory:
- [1-setup](./1-setup) has the number generator repository added.
- [2-execution](./2-execution) has a single step configured that can be used for executing the number generator program (Lua version).
- [3-sampling](./3-sampling) has a second step added for copying identified results into a specified directory. It also showcases parameter passing between the two steps.
- [4-build](./4-build) contains a third step for building the C version of the generator program (C compiler not included).
- [5-configuration](./5-configuration) extends every step by additional configuration parameters.

# Setup

To execute `benmet`, you need a runnable Lua 5.3 interpreter, which we will refer to as `<lua>`. Common names for this program are `lua53`, `lua5.3`, or plain `lua`. You can invoke it with the `-v` flag to output version information.

`benmet` is invoked by its `main.lua` script file. From the current directory, the command would be `<lua53> ../../../main.lua`, optionally followed by further arguments. Within this file, we will refer to this base invocation by `<benmet>`.

Invoking the program as `<benmet>` without further arguments should list the program description and available commands. Note that both relative and absolute paths to the `main.lua` script file are supported.

If you haven't yet, you can execute `benmet`'s `auto-setup` command to clone `benmet`'s own required dependencies: `<benmet> auto-setup`

Create an empty directory. We will execute `benmet` within this as a working directory, which means we consider it our "workspace".

The random number generator program is hosted in a separate repository at the URL https://github.com/rohlem/benmet-tutorial-stub-numgen .
To clone this repository where it is accessible to step programs, execute `<benmet> add-repo https://github.com/rohlem/benmet-tutorial-stub-numgen` inside the created directory. This will clone it to the path `./repos/benmet-tutorial-stub-numgen`. Execute `<benmet> add-repo --help` to see further options.

# Execution

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
```

Because our script calls `error`, which exits with non-zero status, `benmet`'s output will contain `failed to run build step command 'inputs'`. So let's fix that next.

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

## making the 'start' command repeat execution by default

As our step `execute-numgen` has no input parameters, `benmet` will cache the first execution and never start a second run. Trying to execute the 'start' command again yields a corresponding message:

```sh
$ <benmet> step.do execute-numgen --command start
found cache hit with status 'finished', eliding execution
finished
```

As this is our sampling step however, we usually want a request for new samples to re-execute the program.

The solution to this is to declare a special input parameter, named "RUN-id". This is a special parameter that always defaults to a unique value.

We can do this by adjusting the output printed by our 'inputs' command to `{"RUN-id":""}`. (You can either change the outer quotes, to `''`, or `[[` and `]]`, or use a backslash to escape nested quotation marks as `\"` ).

Upon this change, repeated execution of the start command should no longer result in cache hits, instead always creating a new run directory in `./steps/execute-numgen/runs/` .

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

You can also execute `<benmet> step.do --help` for further details on all supported options.
