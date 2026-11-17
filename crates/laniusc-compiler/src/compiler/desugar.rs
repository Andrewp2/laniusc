//! Desugaring of machines in the token stream (docs/state-machines-design.md,
//! "Desugaring in the lexer").
//!
//! The desugaring is the last stage of the frontend lexer. It reads the token
//! rows the lexer built and writes the token rows of the desugared program.
//! The text of the generated tokens goes into a region of the lexer's byte
//! buffer after the source bytes, so every later kernel reads their names
//! from token bytes as it reads source names.

use std::sync::atomic::{AtomicU32, Ordering};

use anyhow::Result;

use crate::{gpu::passes_core::PassContext, lexer::buffers::GpuBuffers};

/// Bytes of the region after the source that the next lexer allocation
/// reserves for generated token text. It starts at zero, so a build without
/// a machine allocates and dispatches nothing for the region. A build whose
/// generated text does not fit raises it and runs again; it does not shrink,
/// so later builds of the same program do not run twice.
static REGION_FLOOR: AtomicU32 = AtomicU32::new(0);

thread_local! {
    static SUSPENDED: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

/// The byte extent of a lexer input of `n` source bytes, `aligned_len` of
/// them with word padding: the source alone when no region is reserved,
/// otherwise the padded source and the region.
pub(crate) fn byte_extent(n: u32, aligned_len: u32) -> u32 {
    match REGION_FLOOR.load(Ordering::Relaxed) {
        0 => n,
        region => aligned_len.saturating_add(region),
    }
}

/// Runs `f` with the desugaring switched off for lexer recordings on this
/// thread. The text rewrites of generators and closures lex the source for
/// their own selection and parse; those lexes must see the source tokens.
pub(crate) fn without_desugaring<T>(f: impl FnOnce() -> T) -> T {
    let previous = SUSPENDED.with(|s| s.replace(true));
    let out = f();
    SUSPENDED.with(|s| s.set(previous));
    out
}

/// Records the desugaring after the lexer's token build.
pub(crate) fn record(
    ctx: &mut PassContext<'_, GpuBuffers, crate::lexer::debug::DebugOutput>,
) -> Result<()> {
    if SUSPENDED.with(|s| s.get()) {
        return Ok(());
    }
    let _ = ctx;
    Ok(())
}
