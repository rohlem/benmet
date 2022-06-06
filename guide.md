This file describes the principle workings of `benmet`.
For a step-by-step example on how to use it see [examples/tutorial](./examples/tutorial), for a real-world example (with less documentation) see [examples/s-reprompi](./examples/s-reprompi).

# Basic idea

The basic purpose behind `benmet` is to automate already-working, suspendable processes, on the basis of their parameters.

For example, take a basic build process:

```sh
git clone https://github.com/open-mpi/ompi
cd ompi
./configure --prefix=/path/to/built
make install
```

Now, there are hundreds of build systems and projects layouts, and frankly that's your problem.
__To use benmet, you already need a working procedure (build + execute + parse results).__
All `benmet` does is let you _manage executions_ of your procedures:

- Input and output parameter processing
- Execution directory management (based on hash of input parameters)

A procedure is usually split into multiple `steps`. For example, a program can be built once (per set of build parameters) and then this build can be executed as often as you wish to sample from it.

# Writing step programs
`Step` programs implement your build procedure. They are meant to be deterministic, so try to do the same thing every time, only influenced by their `input parameters`.

`benmet` looks for steps at the path `./steps/<step-name>/<program-name>` relative to the workspace (which is the working directory `benmet` was executed in).
Notably, their directory name is considered their name, while the `<program-name>` is specified in the dependency chain file `./steps/index.txt` (see "Combining `step` programs" below).

You can use any language you want to implement `step` programs, as they are launched as child processes, as if from the system shell. Therefore, they may need execution permission, a shebang line, and/or a fitting file extension association under Windows.
A bit of special handling is however applied for files ending in `.lua`, which are given access to the `benmet.util` module for convenience.

For simplicity, `input parameters` are just named string values, that is, they are always a pair of one key and one value. Of course, programs may parse/treat these strings as numbers or other structured data (f.e. JSON-arrays) as they see fit.

A `step` program is always invoked with exactly one input parameter, named the `step command`, from the following list:
- `inputs`: output the input parameters of this step (with their default values, if any)
- `status`: output the run's current status to stdout, as one of `startable`|`pending`|`continuable`|`finished`|`error*`
- `start`: start a new run (status should be `startable`)
- `cancel`: cancel pending asynchronous operations (status should be `pending`)
- `continue`: continue if the last asynchronous operation has completed (status should be `continuable`)

`Steps` may be suspendable. That means they may start an external operation, f.e. enqueue a job via `squeue`, and check back if it has finished later.
To this end, an "execution", named `run`, may actually consist of multiple program executions, which all share a unique working directory `.`.
For example:

- launched with command `inputs` -> start execution:

  - read parameters from `./input_params.txt`
  - dispatches `squeue`
  - write job ids to new file `./job_ids.txt`
  - quits (did not write `./output_params.txt`).

- launched with command `status` -> check completion:

  - make sure the `run` has not completed yet (no file `./output_params.txt` present)
  - check async completion (f.e. whether a result file `./job_output.txt` was created)
  - read job ids from file `./job_ids.txt`
  - check pending jobs (f.e. via `sinfo` invocation)
  - return status (`pending` if still running, or `error: job not found` if not - maybe canceled by user or admin?)

- launched with command `status` -> check completion:

  - make sure the `run` has not completed yet (no file `./output_params.txt` present)
  - check async completion (whether `./job_output.txt` was created -> it was)
  - return status `continuable`

- launched with command `continue` -> check completion:

  - make sure the `run` has not completed yet (no file `./output_params.txt` present)
  - check async completion (that `./job_output.txt` was created -> it was)
  - complete the `run` by writing `./output_params.txt`

The `inputs` command is special in that it is not associated with a `run`, so it has no unique working directory and no `input` nor `output parameters` itself.

All other commands may find the supplied `input parameters` in the file `./input_params.txt`.
Errors are signaled by non-zero exit status.
A zero exit status can signal completion if `./output_params.txt` was created, or suspension if it wasn't.

## `inputs` command
Output the input parameters that are accepted by this step to stdout, as a single JSON-object with default values. By convention, the empty string is used to signal "no default value" (though it is currently internally considered a default value just the same).

## `status` command
Return a single status via stdout: `finished` (`./output_params.txt` exists), `startable` (nothing done yet), `pending` (waiting for asynchronous operation), `continuable` (asynchronous operation completed), or `error` (requires manual intervention/reset - may be followed by error message).

## `start` command
Begin doing what is expected of this `step` in the overall procedure.
If it does not need to suspend, write the file `./output_params.txt` and exit, otherwise exit without creating that file.

## `cancel` command
Cancel previously-started asynchronous operations that haven't yet completed.
Additionally revert the current directory so that its status becomes `startable` again.

## `continue` command
Check the previously-started asynchronous operations have been completed, then continue.
Note that this command is free to enqueue more work and suspend again, just as the initial `continue` command.

# Combining `step` programs
For self-contained `step` program to communicate, one program needs to write `output parameters` that are `input parameters` of a subsequent step.
As the name implies, the file `output_params.txt` may hold a JSON object of output parameters (same key-value format as input parameters).

To determine that one step relies on another, `benmet` inspects the file `./steps/index.txt` (workspace-relative).
This file is given in a line-based format of `<dependers>: <dependees>`, f.e.:

```
build-openmpi/run.lua:
build-reprompi/run.lua: build-openmpi
run-reprompi/run.lua: build-reprompi
parse-output/run.lua: run-reprompi
```

Dependers must consist of `<step-name>/<program-name>`, where `<step-name>` is the directory name in `./steps`, and `<program-name>` is the file name within.
Multiple dependers and dependees are separated by spaces, and may appear in multiple lines.
Every step needs to appear at least once as depender, for explicitness.
Dependencies must be acyclic.

From the above example, `benmet` would derive that the step `parse-output` depends on the steps `build-openmpi`, `build-reprompi`, and `run-reprompi`, in that order.

## A note about caching and special parameters
By default, ReproMPI caches `step runs` with fully matching `input parameters`.
When measuring program performance, you commonly want to re-execute the program instead.

For this purpose, you can use the special input parameter `RUN-id`, which defaults to a unique value, so that the `input parameters` never fully match (unless requested).

Similarly, there are a couple of other special parameters requesting special behaviour from `benmet` (where `<name>` is a placeholder for any string):

- `RUN-all-params`: Declaring this `input parameter` triggers providing all `parameters`, of this and all preceding `steps`, in a separate file `params\_in\_all.txt`. Useful for documenting where a sample came from.
- `RUN-hostname`: Provides the hostname of the machine the program is run on. Useful for documenting where a sample came from.
- `REPO-GITCOMMITHASH-<name>`: Declares that the step will make use of repository `<name>`, and provides the exact commit hash of the state it is provided in.
- `REPO-PATH-<name>`: Declares that the step will make use of repository `<name>`, and provides the path at which a repository clone is provided.

Note that currently only `git` repositories are supported, and `git` must be accessible via system shell child process execution.
Use `benmet add-repo` for cloning repositories to be available for this purpose.

# Using `benmet`
So, you have your procedure re-written as self-contained deterministic `step` programs, explicitly parameterized, and chained them leading up to the final one which saves the results somewhere you want them.
Now, after all that work, we can use `benmet` to manage `runs` of all these `steps` in sequence. These sets of runs are named `pipelines`.

To do this, we create a parameter file, holding a JSON array of JSON objects of parameter combinations we want to execute our procedure with:

```
[
{ "first-param":"hydraulic", "size":"infinite" }
{ "first-param":["henry","john"], "size":[1,2] },
]
```

Note that this parameter file, unlike `input_params.txt` and `output_params.txt`, contains an array of JSON objects, which can itself hold JSON array values.
Within every top-level array element, all field array's elements are multiplicatively combined to create parameter combinations. For example, the above example results in 5 `pipelines`, with input parameters as follows:

```
{ "first-param":"hydraulic", "size:"infinite" }
{ "first-param":"henry", "size":1 }
{ "first-param":"henry", "size":2 }
{ "first-param":"john", "size":1 }
{ "first-param":"john", "size":2 }
```

This parameter file can be used to manage pipeline executions:

- `benmet pipelines.launch param-file.json --target <final-step>` launches the pipelines described in `param-file.json` towards `final-step`. Note that every time it is executed, new `RUN-id`s are given, so if you run it multiple times, you'll get multiple pipelines only differing in `RUN-id`.
- `benmet pipelines.poll param-file.json --target <final-step>` polls the status of all pipelines described by these parameters and the target step `final-step`.
- `benmet pipelines.cancel`, `benmet pipelines.discard`, `benmet pipelines.continue` similarly cancel, discard, or continue these pipelines.

Be sure to consult the helpful output of `--help` for all the supported options. The flag `--all` is particularly handy to target all pending pipelines at once.
