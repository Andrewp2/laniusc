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
pub use dispatch::{RETAINED_POISON, RetainedTraitCheck, RetainedTraitOptions, RetainedTraitStage};

impl super::GpuCompiler<'_> {
    /// Builds the program trait catalog and the bound goals of the
    /// retention store's current build on the GPU, and runs the trait
    /// solver's admission, coherence and proof kernels over them
    /// (docs/compiler-retained-trait-catalog.md). The store must be READY.
    #[doc(hidden)]
    pub fn retained_trait_check(
        &self,
        store: &crate::type_checker::program_retention::ProgramRetention,
        options: &RetainedTraitOptions,
    ) -> anyhow::Result<RetainedTraitCheck> {
        dispatch::retained_check(self.trait_solver_workspace.checkout(), store, options)
    }
}

// Callable native identities come from accepted owner retention; actual public
// aliases are joined against the accepted interface, never guessed from tags.
