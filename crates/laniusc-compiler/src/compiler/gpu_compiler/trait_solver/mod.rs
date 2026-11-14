//! Owned definition snapshots and append-only call/evidence packets.
//! Graph comparison and implementation selection belong to GPU consumers.
//! Every issued row retains its immutable owner and referenced row closure.

mod abi;
mod catalog;
mod dispatch;
mod native_layout;
mod native_layout_work;
mod native_session;
mod packet;
mod proof_store;

pub(super) use dispatch::{SolverWorkspacePool, prepare_kernels as prepare_solver_kernels};

pub(super) use native_session::{
    CheckedReplayCalls,
    ClosureOrigin,
    DeclarationsOnlyTemplate,
    NativeProgramSession,
    ReplayScope,
    ValidatedOriginalUnit,
    ValidatedReplayRequest,
    native_program_error,
    unit_span,
};
pub(super) use packet::AdmittedCall;

// Callable native identities come from accepted owner retention; actual public
// aliases are joined against the accepted interface, never guessed from tags.
