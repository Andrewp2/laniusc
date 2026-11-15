//! Process counters of the frontend and replay paths, for tests that
//! must show a compile path ran neither (docs/compiler-retained-projection.md).

use std::sync::atomic::{AtomicU64, Ordering};

static FRONTEND_CHECKS: AtomicU64 = AtomicU64::new(0);
static REPLAY_LOWERINGS: AtomicU64 = AtomicU64::new(0);

/// (frontend type-check recordings, lowering jobs recorded with a replay
/// selection) since the process started.
#[doc(hidden)]
pub fn fallback_counters() -> (u64, u64) {
    (
        FRONTEND_CHECKS.load(Ordering::Relaxed),
        REPLAY_LOWERINGS.load(Ordering::Relaxed),
    )
}

pub(crate) fn count_frontend_check() {
    FRONTEND_CHECKS.fetch_add(1, Ordering::Relaxed);
}

pub(crate) fn count_replay_lowering() {
    REPLAY_LOWERINGS.fetch_add(1, Ordering::Relaxed);
}
