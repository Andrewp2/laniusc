//! Frontend recordings, used to verify that instantiation never recompiles source.
use std::sync::atomic::{AtomicU64, Ordering};

static FRONTEND_CHECKS: AtomicU64 = AtomicU64::new(0);

/// Number of frontend type-check recordings since the process started.
#[doc(hidden)]
pub fn frontend_check_count() -> u64 {
    FRONTEND_CHECKS.load(Ordering::Relaxed)
}

pub(crate) fn count_frontend_check() {
    FRONTEND_CHECKS.fetch_add(1, Ordering::Relaxed);
}
