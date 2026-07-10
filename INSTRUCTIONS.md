Lanius is a programming language that compiles on the GPU. That is, it targets the CPU (x86 and WASM) but the compiler itself runs as a series of shaders on the GPU.

It's written in Rust and Slang. It uses wgpu for its graphics backend.

Our goal is to prepare Lanius to be credible enough to show publicly by making the current alpha language work end to end. It must be able to run real programs, and it must not
special case those programs in anyway. That means it cannot detect the filename and special case on that, nor should it special case on specific shapes within the program.

1. A wide variety of nontrivial programs must compile and run, including the existing PPM raytracer program through general compiler/runtime support.
2. Emit both `x86_64` and `wasm` programs from the appropriate flags. That is, it takes in Lanius source, and can either produce an x86_64 binary or a Wasm artifact that is runnable int he appropriate Wasm runtime (like wasmtime, for example). 
3. We must support facilities for stdio, filesystem, environment, process args/exit, random, time, and allocation. GPU and networking are not required for this milestone.
4. The repository must contain a checked set of examples that definitely compile and run, each with source, build/run command, expected output or exit code, and target coverage.
5. There must be benchmarks with comparable, variable, real-looking workloads for Rust, C, C++, Zig, and Lanius with commands, generator inputs/configs, outputs, machine info,
and measured results. 
6. The Lanius compiler `laniusc` must compile at speeds comparable to the papers in `/docs` or `Pareas`, which is available at `~/code/pareas`. Pareas is the GPU compiler
we are styling our project after written about in the theses in `/docs`. Specifically, the timeline is as follows: first the user starts up a `laniusc` compiler daemon process,
which should take under a minute. During this, period buffers, pipelines, and other GPU device information can be created, however care should be taken around how much memory is actually used up on the user's machine. Then, the timer starts when the daemon is sent a compilation job, upon which the compiler should finish incredibly quickly (the tagline for the project is "Compile at the speed of light", and I would like to achieve compile times 10x or even 100x `gcc`. It is a P0 goal for this compiler to be incredibly fast.)
7. The code must be at least somewhat "clean". That means files should not be extremely large, we should follow architectural principles like WET and DRY, and so on. Do not consider the current state of the code to be sacred, sometimes things were done for bad reasons or misconceptions.
8. The vast majority of the work must be done in GPU shaders that operate massively in parallel. That means it should run on the GPU, and the pattern of "using a single thread to compute something over the entire codebase" is wrong. Instead, use prefix scans, segmented scans, parallel bracket matching, the parallel stack-effects and parallel DFA algorithms mentioned in the paper, and so on.
9. You do not have to write any user-facing documentation, in this project all user-facing documentation is written by humans.
