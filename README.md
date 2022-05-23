Minimal-dependency suspendable task automation program 'benmet'.

This program was written to manage numerous (hundreds+) executions of a procedure (say, sampling the performance of program executions) via parameter files.

It is self-contained Lua code, notably only requiring standard (PUC-Rio) Lua 5.3, in hopes of being maximally-portable.
Execute it using a Lua interpreter (not included) from any directory (workspace) via `<Lua> path/to/benmet/main.lua`.

## Scope / Status

The program is first and foremost a proof-of-concept prototype. Although it is actually quite usable, you'll probably find some rough edges.

For details on what it does see ['guide.md'](./guide.md), for a real-world example (with less documentation) see [examples/s-reprompi](./examples/s-reprompi).
You may also consult highly-detailed help text by executing it with the `--help` flag argument, as well as the comments present throughout the source code.

While I'm open for addressing issues and pull request within the next couple of months, the program is ___basically feature-complete___ (from my point of view)___, and no longer under active development___.

If I ___were___ to dedicate full focus to it however, I would personally like to rewrite it in [Zig](https://www.ziglang.org), for clearer code, more robustness, and even more portability. (Note that Zig is itself still under active development however, so waiting a couple more years for stabilization with version 1.0, while not strictly necessary, seems reasonable.)

## view

Also included in this repository is a general-purpose rapid-iteration visualization tool for produced metric files (in parameter file format) [view/view.html](./view/view.html).

This is a big HTML file with a bunch of JavaScript. It is also quite usable, though it was maybe my biggest JavaScript project yet, so the coding style is very pragmatic and probably not very readable.
The basic usage pattern is:

- load commit strands (generated using `benmet`'s `commit-ordering` command)
- load metrics (same format as parameter files) - in my experience this works best when navigating to a folder and selecting all files in it with Ctrl+A. I don't remember whether successive "open file" dialogues work correctly.
- configure the plotting pipeline - you basically want to:

  - ignore things you don't care about (f.e. input paths)
  - split into figures or groups the parameters you do care about
  - select one commit parameter as the x axis ("split figures, order commits oldest-left on x axis" - splits figures if there are multiple strands)
  - and then select for your y axes "use as y axis".

- configure text and graphical output as you need it, then click the button 'render'. Note this will probably freeze your browser for a bit until it's done processing.

Plotting options "boxplot" and "derive y axes (advanced)" also work, but are hard-coded for my use-case to remove the first 20% of values as warm-up. Someone needs to add UI + logic for configuring that. Maybe view.html would benefit from a UI overhaul in general. Ideas and implementations welcome!

## Licensing

View.html uses [`chart.js`](https://www.chartjs.org/) and [`charjs-chart-boxplot`](https://github.com/sgratzl/chartjs-chart-boxplot), which are vendored (included) in this repository for convenience.
___Note that my licensing (the UNLICENSE) DOES NOT apply to them.___

All of my own code is UNLICENSE-d, meaning dedicated to the public domain, as stated in the file ['UNLICENSE'](./UNLICENSE).
