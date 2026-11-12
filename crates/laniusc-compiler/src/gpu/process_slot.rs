//! Limits how many one-shot compiler processes hold a GPU device at once.
//!
//! A fresh compiler takes about 550 MB of GPU memory for a one-line program.
//! Sixteen processes started together need 9 GB. When that does not fit, the
//! driver stalls every one of them for tens of seconds. A one-shot command
//! therefore takes one of a few lock files before it creates its device, and
//! holds it until the process ends. The kernel releases the lock however the
//! process ends.
//!
//! A resident compiler (`laniusc daemon`, `laniusc lsp`) takes no slot. It
//! holds its device for hours and serializes its own jobs. A process that
//! embeds the compiler as a library takes no slot either.

use std::{
    fs::{self, File, OpenOptions},
    path::PathBuf,
    sync::{
        Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

/// Processes that may hold a device at once when `LANIUS_GPU_PROCESS_SLOTS`
/// is not set. Four fresh compilers take about 2 GB.
const DEFAULT_SLOTS: usize = 4;

const POLL_INTERVAL: Duration = Duration::from_millis(10);

/// A process that waits this long continues without a slot. A stopped
/// process that holds a slot then delays other processes but never blocks
/// them.
const MAX_WAIT: Duration = Duration::from_secs(120);

static LIMITED: AtomicBool = AtomicBool::new(false);

/// The slot of this process. It is held until the process ends.
static HELD: Mutex<Option<File>> = Mutex::new(None);

/// Marks this process as a one-shot command. Its device creation then waits
/// for a slot.
pub(crate) fn limit_this_process() {
    LIMITED.store(true, Ordering::Release);
}

/// Waits for a free slot when this process is a one-shot command. Continues
/// without one when the limit is disabled, the lock directory is not usable,
/// or the wait reaches `MAX_WAIT`.
pub(super) fn acquire_before_device_creation() {
    if !LIMITED.load(Ordering::Acquire) {
        return;
    }
    let mut held = HELD.lock().expect("gpu.process_slot poisoned");
    if held.is_none() {
        *held = acquire_file(slot_count(), MAX_WAIT);
    }
}

fn slot_count() -> usize {
    std::env::var("LANIUS_GPU_PROCESS_SLOTS")
        .ok()
        .and_then(|text| text.trim().parse::<usize>().ok())
        .unwrap_or(DEFAULT_SLOTS)
}

fn acquire_file(slots: usize, max_wait: Duration) -> Option<File> {
    if slots == 0 {
        return None;
    }
    let files = open_slot_files(slots)?;
    let start = Instant::now();
    loop {
        for file in &files {
            if file.try_lock().is_ok() {
                return file.try_clone().ok();
            }
        }
        if start.elapsed() >= max_wait {
            return None;
        }
        thread::sleep(POLL_INTERVAL);
    }
}

fn open_slot_files(slots: usize) -> Option<Vec<File>> {
    let directory = slot_directory()?;
    let mut files = Vec::with_capacity(slots);
    for slot in 0..slots {
        let path = directory.join(format!("slot-{slot}.lock"));
        let file = OpenOptions::new()
            .create(true)
            .truncate(false)
            .write(true)
            .open(&path)
            .or_else(|_| File::open(&path))
            .ok()?;
        files.push(file);
    }
    Some(files)
}

fn slot_directory() -> Option<PathBuf> {
    let candidates = [
        std::env::var_os("XDG_RUNTIME_DIR").map(|root| PathBuf::from(root).join("laniusc-gpu-slots")),
        Some(std::env::temp_dir().join("laniusc-gpu-slots")),
    ];
    candidates
        .into_iter()
        .flatten()
        .find(|directory| fs::create_dir_all(directory).is_ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_disabled_limit_takes_no_slot() {
        assert!(acquire_file(0, Duration::ZERO).is_none());
    }

    #[test]
    fn a_full_limit_is_released_when_a_holder_drops() {
        // The lock belongs to the open file description, so two acquisitions
        // in one process contend like two processes.
        let Some(first) = acquire_file(1, Duration::from_secs(120)) else {
            return;
        };
        let waiter = thread::spawn(|| acquire_file(1, Duration::from_secs(120)).is_some());
        thread::sleep(Duration::from_millis(50));
        assert!(!waiter.is_finished(), "the second acquisition waits for the slot");
        drop(first);
        assert!(waiter.join().expect("the waiter thread ends"));
    }
}
