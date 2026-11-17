//! Lets the GPU driver's worker threads finish before the process exits.
//!
//! NVIDIA's Vulkan driver compiles some pipelines on its own worker threads
//! after `vkCreateComputePipelines` has returned. A warm run of the `retained`
//! tests spent 5 to 8 s compiling that way in its last 20 s, with no pipeline
//! creation of ours slower than 50 ms. `exit` then runs the driver's exit
//! handlers and its libraries' destructors on the main thread while a worker
//! still compiles. The worker aborts on a corrupted heap (`malloc_printerr`
//! inside `libnvidia-gpucomp`, with the main thread inside `libEGL_nvidia`'s
//! exit handler), or it spins and the process never ends.
//!
//! `exit` runs the exiting thread's TLS destructors before any `atexit` or
//! `__cxa_atexit` handler, whatever order the libraries registered those in.
//! [`register_before_main`] registers one such destructor for the main thread.
//! If the process loaded the driver, the destructor waits for the
//! pipeline-cache writer and then until no other thread of the process is
//! running. Only then do the driver's own exit handlers run.

use std::{
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, Instant},
};

/// Set once this process created a wgpu instance, which loads the driver.
static DRIVER_LOADED: AtomicBool = AtomicBool::new(false);

/// How long the exit waits for busy threads before it exits anyway. The
/// longest background compile measured was about 8 s of CPU.
const MAX_WAIT: Duration = Duration::from_secs(30);
/// The interval between two looks at the process's threads. A compiling
/// worker is running nearly all the time, so two looks 1 ms apart find it;
/// an exit with idle threads costs about 1 ms.
const POLL: Duration = Duration::from_millis(1);
/// How many looks in a row must find every other thread waiting.
const QUIET_POLLS: u32 = 2;

/// Records that the driver is loaded, so the exit waits for its threads.
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
        wait_for_driver_threads();
    }
    // glibc uses the symbol only to find the object that registered it.
    let dso_symbol = register_before_main as *const () as *mut std::ffi::c_void;
    // SAFETY: the destructor has no object and lives as long as the binary.
    unsafe { __cxa_thread_atexit_impl(wait_at_exit, std::ptr::null_mut(), dso_symbol) };
}

/// Waits until no other thread of this process is running, if the driver was
/// loaded. It must not panic: it runs inside `exit`.
#[cfg_attr(not(all(target_os = "linux", target_env = "gnu")), allow(dead_code))]
fn wait_for_driver_threads() {
    if !DRIVER_LOADED.load(Ordering::Acquire) {
        return;
    }
    let start = Instant::now();
    super::device::wait_for_background_persist();
    let Some(own) = own_tid() else {
        return;
    };
    let mut quiet = 0;
    let mut busy_seen = false;
    while start.elapsed() < MAX_WAIT {
        if other_thread_running(&own) {
            quiet = 0;
            busy_seen = true;
        } else {
            quiet += 1;
            if quiet == QUIET_POLLS {
                break;
            }
        }
        std::thread::sleep(POLL);
    }
    if busy_seen && crate::options::get().report.host_timing {
        eprintln!(
            "[gpu_compile_host_timer] exit.driver_threads_wait: {:.3}ms",
            start.elapsed().as_secs_f64() * 1000.0
        );
    }
}

/// This thread's id, from `/proc/thread-self` (`<pid>/task/<tid>`).
fn own_tid() -> Option<std::ffi::OsString> {
    let link = std::fs::read_link("/proc/thread-self").ok()?;
    link.file_name().map(ToOwned::to_owned)
}

/// Whether a thread other than `own` is running or ready to run.
fn other_thread_running(own: &std::ffi::OsStr) -> bool {
    let Ok(tasks) = std::fs::read_dir("/proc/self/task") else {
        return false;
    };
    tasks.flatten().any(|task| {
        task.file_name() != own
            && std::fs::read(task.path().join("stat"))
                .ok()
                .is_some_and(|stat| thread_state(&stat) == Some(b'R'))
    })
}

/// The state field of `/proc/<pid>/task/<tid>/stat`: the first character
/// after the `)` that closes the thread name, which may itself contain `)`.
fn thread_state(stat: &[u8]) -> Option<u8> {
    let close = stat.iter().rposition(|&byte| byte == b')')?;
    stat.get(close + 2).copied()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn thread_state_follows_the_last_closing_parenthesis() {
        assert_eq!(thread_state(b"12 (a) b) S 1 2"), Some(b'S'));
        assert_eq!(thread_state(b"12 (worker) R 1 2"), Some(b'R'));
        assert_eq!(thread_state(b"12 (worker"), None);
    }
}
