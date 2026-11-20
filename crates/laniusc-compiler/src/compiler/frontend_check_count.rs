//! Frontend recordings, used to verify that instantiation never recompiles source.
use std::cell::Cell;

thread_local! {
    // One counter per thread: tests run in parallel in one process, and a
    // test compares the count before and after its own compiles. With a
    // process-wide counter a compile on another test's thread failed that
    // comparison. A compile records its type check on the thread that polls
    // it, which is the test's thread.
    static FRONTEND_CHECKS: Cell<u64> = const { Cell::new(0) };
}

/// Number of frontend type-check recordings made on the calling thread.
#[doc(hidden)]
pub fn frontend_check_count() -> u64 {
    FRONTEND_CHECKS.with(Cell::get)
}

pub(crate) fn count_frontend_check() {
    FRONTEND_CHECKS.with(|count| count.set(count.get() + 1));
}
