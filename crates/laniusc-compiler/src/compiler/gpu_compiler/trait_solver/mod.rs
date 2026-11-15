//! Owned definition snapshots and append-only call/evidence packets.
//! Graph comparison and implementation selection belong to GPU consumers.
//! Every issued row retains its immutable owner and referenced row closure.

mod abi;
mod catalog;
mod dispatch;
mod native_layout;
mod native_layout_work;
mod packet;
mod proof_store;

pub(super) use dispatch::{SolverWorkspacePool, prepare_kernels as prepare_solver_kernels};


pub use dispatch::{ClosedTraitCheck, ClosedTraitPublication, RETAINED_POISON, RetainedBufferRange, RetainedTraitCheck, RetainedTraitIdentity, RetainedTraitOptions, RetainedTraitPublication, RetainedTraitStage, RetainedTraitView};

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

    /// `retained_trait_check`, returning the solved check as a GPU
    /// publication that keeps its catalog, packet, proof store and routes
    /// (docs/compiler-retained-trait-catalog.md, "Publication"). None when
    /// the check stopped before the solver.
    #[doc(hidden)]
    pub fn retained_trait_publish(
        &self,
        store: &crate::type_checker::program_retention::ProgramRetention,
        options: &RetainedTraitOptions,
    ) -> anyhow::Result<(RetainedTraitCheck, Option<RetainedTraitPublication>)> {
        dispatch::retained_publish(self.trait_solver_workspace.checkout(), store, options)
    }
}

// Callable native identities come from accepted owner retention; actual public
// aliases are joined against the accepted interface, never guessed from tags.
