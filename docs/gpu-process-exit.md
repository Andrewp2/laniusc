# GPU process exit

A process that loaded the GPU driver ends through
`crates/laniusc-compiler/src/gpu/process_exit.rs`. This covers the CLI, the
daemon and the test binaries.

## The problem

NVIDIA's Vulkan driver compiles some pipelines on its own worker threads
after `vkCreateComputePipelines` has returned. A warm run of the `retained`
tests spent 5 to 8 s of CPU in such compiles during its last 20 s, while no
pipeline creation of ours took longer than 50 ms. When `exit` runs library
exit handlers beside a busy or waking worker, the process crashes or hangs
after `test result: ok`. Two cores showed this:

- `Aborted (core dumped)`, 2026-11-17 01:48: the main thread was in
  `libEGL_nvidia`'s exit handler, and a worker aborted in `malloc_printerr`
  inside `libnvidia-gpucomp` under `_nv002nvvm`.
- `Segmentation fault`, 2026-11-17 11:32: the main thread was in
  `libLLVM.so.20.1`'s exit handler, and the worker crashed in
  `libnvidia-glvkspirv` at the start of a job. The Vulkan loader loads every
  installed driver, and Mesa's `lvp` and `radeon` drivers and Mesa's EGL
  link `libLLVM`.

The hung processes showed a thread named `lanius-gpu-test` at 100% CPU. That
was a driver worker, which takes its name from the thread that created the
device.

## The exit order

1. Before `main`, the `.init_array` constructor in `gpu/device.rs`
   registers a TLS destructor for the main thread
   (`__cxa_thread_atexit_impl`). `exit` runs the exiting thread's TLS
   destructors before any `atexit` or `__cxa_atexit` handler, whatever order
   the libraries registered those in.
2. If a wgpu instance was created, the destructor waits for the
   pipeline-cache writer.
3. It then registers an `on_exit` handler. glibc runs a handler registered
   during `exit` first and passes it the exit status. The handler flushes C
   stdio and calls `_exit(status)`, so no library exit handler runs. The
   kernel releases the device as it does for a killed process, and a driver
   worker that is still compiling ends with the process.

The exit does not wait for the driver's workers. It did until 2026-11-19:
the destructor polled `/proc/self/task/*/stat` until no other thread was
running, for at most 30 s. After a pipeline has been used some number of
times the driver compiles it again on one worker thread, and the daemon
reaches that after about 25 builds of the settings program. The worker then
used 20 CPU-seconds after 45 builds and 48 CPU-seconds after 345 builds, and
a new process does the same work again. A daemon asked to shut down while the
worker ran took 4.6 s to exit after 40 builds and the full 30 s after 63.
Without the wait it exits in 0.3 s.

Rust has flushed its standard streams before `exit` runs, and the compiler
writes its pipeline cache before `main` returns. The driver's shader cache
still hits on the next start (690 pipelines in 240 to 290 ms for
`laniusc check`). A process that exits from a thread other than the main
thread, or that never created an instance, exits as before.

## Measurements

| Build | Runs | Clean | Hang | Abort or crash |
|---|---|---|---|---|
| Before, parent worktree, other agents running (`retained`) | 5 | 3 | 1 | 1 |
| Before, this worktree (`retained`) | 18 | 18 | 0 | 0 |
| Before, this worktree (`native_c`) | 19 | 18 | 1 | 0 |
| Wait only (`retained`) | 30 | 29 | 0 | 1 (the LLVM segfault) |
| Wait, then `_exit` (`retained`) | 14 | 14 | 0 | 0 |
| Wait, then `_exit` (`native_c`) | 8 | 8 | 0 | 0 |
| `_exit` without the wait (`native_c`) | 8 | 8 | 0 | 0 |
| `_exit` without the wait (daemon shutdown after 40 to 63 builds) | 3 | 3 | 0 | 0 |

The race is rare on a quiet machine, so a clean count is weaker evidence
than the two cores.
