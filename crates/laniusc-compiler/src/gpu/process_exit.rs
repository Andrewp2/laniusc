//! Ends a process that loaded the GPU driver without running library exit
//! handlers beside the driver's worker threads.
//!
//! NVIDIA's Vulkan driver compiles some pipelines on its own worker threads
//! after `vkCreateComputePipelines` has returned. A warm run of the `retained`
//! tests spent 5 to 8 s compiling that way in its last 20 s, with no pipeline
//! creation of ours slower than 50 ms. `exit` then runs the driver's exit
//! handlers and its libraries' destructors on the main thread while a worker
//! still compiles. The worker aborts on a corrupted heap (`malloc_printerr`
//! inside `libnvidia-gpucomp`, with the main thread inside `libEGL_nvidia`'s
//! exit handler), or it spins and the process never ends. Waiting until the
//! workers are idle is not enough: a worker woke during the exit handlers and
//! crashed in `libnvidia-glvkspirv` while the main thread ran `libLLVM`'s exit
//! handler. The Vulkan loader loads every installed driver, and Mesa's `lvp`
//! and `radeon` drivers and Mesa's EGL link `libLLVM`.
//!
//! `exit` runs the exiting thread's TLS destructors before any `atexit` or
//! `__cxa_atexit` handler, whatever order the libraries registered those in.
//! [`register_before_main`] registers one such destructor for the main thread.
//! If the process loaded the driver, the destructor waits for the
//! pipeline-cache writer, then registers an `on_exit` handler. glibc runs a
//! handler registered during `exit` first, and passes it the exit status: it
//! flushes C stdio and ends the process with `_exit(status)`, so no library
//! exit handler runs. The kernel releases the device as it does for a killed
//! process. Rust has already flushed its standard streams when `exit` runs,
//! and the compiler writes its pipeline cache before `main` returns.
//!
//! The exit does not wait for the driver's workers. After a pipeline has been
//! used some number of times the driver compiles it again on one worker
//! thread. For the daemon this is 20 to 50 s of CPU after 45 to 345 builds of
//! a 33,000-line program, in every process: the next process compiles the same
//! pipelines again. An exit that waited for that worker took 30 s after 63
//! builds. `_exit` ends the worker with the process, and no exit handler runs
//! beside it.

use std::sync::atomic::{AtomicBool, Ordering};

/// Set once this process created a wgpu instance, which loads the driver.
static DRIVER_LOADED: AtomicBool = AtomicBool::new(false);

/// Records that the driver is loaded, so the exit ends with `_exit`.
pub(crate) fn note_driver_loaded() {
    DRIVER_LOADED.store(true, Ordering::Release);
}

#[cfg(all(target_os = "linux", target_env = "gnu"))]
unsafe extern "C" {
    fn __cxa_thread_atexit_impl(
        dtor: unsafe extern "C" fn(*mut std::ffi::c_void),
        obj: *mut std::ffi::c_void,
        dso_symbol: *mut std::ffi::c_void,
    ) -> std::ffi::c_int;
    fn on_exit(
        function: extern "C" fn(std::ffi::c_int, *mut std::ffi::c_void),
        arg: *mut std::ffi::c_void,
    ) -> std::ffi::c_int;
    fn fflush(stream: *mut std::ffi::c_void) -> std::ffi::c_int;
    fn _exit(status: std::ffi::c_int) -> !;
}

/// Registers the exit wait as a destructor of the calling thread. Call it on
/// the main thread before `main`.
///
/// # Safety
///
/// It must run on the thread that later calls `exit`, normally the main thread
/// from an `.init_array` constructor.
#[cfg(all(target_os = "linux", target_env = "gnu"))]
pub(crate) unsafe fn register_before_main() {
    unsafe extern "C" fn wait_at_exit(_: *mut std::ffi::c_void) {
        if wait_for_cache_writer() {
            // SAFETY: registering an exit function while `exit` runs is
            // allowed; glibc calls it before the functions registered earlier.
            unsafe { on_exit(end_process, std::ptr::null_mut()) };
        }
    }
    extern "C" fn end_process(status: std::ffi::c_int, _: *mut std::ffi::c_void) {
        // SAFETY: flushing every C stream and ending the process; nothing
        // runs after it.
        unsafe {
            fflush(std::ptr::null_mut());
            _exit(status)
        }
    }
    // glibc uses the symbol only to find the object that registered it.
    let dso_symbol = register_before_main as *const () as *mut std::ffi::c_void;
    // SAFETY: the destructor has no object and lives as long as the binary.
    unsafe { __cxa_thread_atexit_impl(wait_at_exit, std::ptr::null_mut(), dso_symbol) };
}

/// Waits for the pipeline-cache writer, if the driver was loaded, and returns
/// whether it was. It must not panic: it runs inside `exit`.
#[cfg_attr(not(all(target_os = "linux", target_env = "gnu")), allow(dead_code))]
fn wait_for_cache_writer() -> bool {
    if !DRIVER_LOADED.load(Ordering::Acquire) {
        return false;
    }
    super::device::wait_for_background_persist();
    true
}
