//! Substitution over canonical IDs (docs/canonical-type-ids.md,
//! "Substitution"): resources, pass names, compiler-graph registration and
//! the operations that record them. Kept out of `compiler_graph.rs` so the
//! substitution producers can change independently.

use super::*;
use crate::gpu::compiler_graph::{
    CompilerGraphBuilder,
    CompilerPhase,
    ResourceClass,
    ResourceDomain,
    ResourceId,
};

pub(super) const SUBSTITUTION_CLEAR_PASS: &str = "type_check.substitution.clear";
pub(super) const SUBSTITUTION_CLEAR_KERNEL: &str = "type_checker/substitution/00_clear";
pub(super) const SUBSTITUTION_SEED_PASS: &str = "type_check.substitution.seed";
pub(super) const SUBSTITUTION_SEED_KERNEL: &str = "type_checker/substitution/01_seed_rows";
/// Call environments, republished each inference round before the argument
/// contexts consume them.
pub(super) const SUBSTITUTION_CALL_ENVS_PASS: &str = "type_check.substitution.call_envs";
pub(super) const SUBSTITUTION_CALL_ENVS_KERNEL: &str =
    "type_checker/substitution/02_publish_call_envs";
/// Words of `ct_subst_counts` (`CT_SUBST_COUNT_WORDS` in ct_subst.slang).
pub(super) const SUBSTITUTION_COUNT_WORDS: u64 = 8;

/// Canonical records and argument words the substitution producers add to
/// a job beyond the candidates' own: per call, a value and an expected
/// environment for each change of its bindings and the substituted nodes of
/// its parameter patterns; array contexts add one array and one count per
/// literal level. A record overflow fails closed (the producers see
/// `CT_UNKNOWN`), so this bounds what a job can express rather than what
/// it uses.
pub(super) fn substitution_canonical_extra(hir_rows: u64) -> (u64, u64) {
    let records = 4 * hir_rows;
    let argument_words = 8 * hir_rows;
    (records, argument_words)
}

/// Memo entries: a power of two, at least two per HIR row.
fn memo_entries(hir_rows: u64) -> u64 {
    (2 * hir_rows).max(4096).next_power_of_two()
}

fn storage(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    bytes: u64,
) -> Result<ResourceId, String> {
    graph.add_storage(name, ResourceDomain::Types, ResourceClass::Workspace, bytes)
}

/// Declares the substitution state and registers its clear and the row
/// seed, after the early canonical stage has interned the source rows.
/// `records` is the canonical record capacity (`ct_head` rows).
pub(super) fn register_substitution_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    token_rows: u64,
    hir_rows: u64,
    records: u64,
) -> Result<(), String> {
    storage(graph, "ct_subst_memo", memo_entries(hir_rows) * 16)?;
    storage(graph, "ct_subst_counts", SUBSTITUTION_COUNT_WORDS * 4)?;
    storage(graph, "ct_row_of", records.max(1) * 4)?;
    storage(graph, "call_env_ct", token_rows.max(1) * 8)?;
    graph.add_kernel_initializer_by_name(
        SUBSTITUTION_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        SUBSTITUTION_CLEAR_KERNEL,
    )?;
    graph.add_kernel_pass_by_name(
        SUBSTITUTION_SEED_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        SUBSTITUTION_SEED_KERNEL,
        &[],
    )?;
    Ok(())
}

/// Registers the call environment publication, ahead of the argument
/// contexts in the inference round.
pub(super) fn register_call_env_pass(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
) -> Result<(), String> {
    graph.add_kernel_pass_by_name(
        SUBSTITUTION_CALL_ENVS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        SUBSTITUTION_CALL_ENVS_KERNEL,
        &[],
    )?;
    graph.add_indirect_dispatch(SUBSTITUTION_CALL_ENVS_PASS, "hir_active_dispatch_args")?;
    Ok(())
}

/// The once-per-job substitution passes: clear, then seed each ID's row.
pub(in crate::type_checker) struct SubstitutionOperations {
    clear: ComputeOperation,
    seed: ComputeOperation,
}

impl SubstitutionOperations {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        passes: &TypeCheckPasses,
    ) -> Result<Self> {
        let words = |name| -> Result<u32> {
            Ok(u32::try_from(typed_buffer_from_resources::<u32>(resources, name)?.byte_size / 4)?)
        };
        let clear_elements = (words("ct_subst_memo")? / 4)
            .max(words("ct_row_of")?)
            .max(words("call_env_ct")? / 2)
            .max(SUBSTITUTION_COUNT_WORDS as u32);
        let candidates =
            words("canonical_row")? + words("canonical_atom")? + words("canonical_projection")?;
        let direct = |name, kernel, elements| {
            ComputeOperation::direct(device, graph, resources, name, &passes.kernel(kernel), elements)
        };
        Ok(Self {
            clear: direct(SUBSTITUTION_CLEAR_PASS, SUBSTITUTION_CLEAR_KERNEL, clear_elements)?,
            seed: direct(SUBSTITUTION_SEED_PASS, SUBSTITUTION_SEED_KERNEL, candidates)?,
        })
    }

    /// Records the clear and the seed; after the early canonical stage.
    pub(in crate::type_checker) fn record_job_start(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.clear.record(encoder)?;
        self.seed.record(encoder)
    }
}

/// The argument contexts of one inference round: publish the call
/// environments, then project each argument's expected type under them.
pub(in crate::type_checker) struct ArgumentContextOperations {
    pub(in crate::type_checker) call_envs: ComputeOperation,
    pub(in crate::type_checker) contexts: ComputeOperation,
}

impl ArgumentContextOperations {
    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.call_envs.record(encoder)?;
        self.contexts.record(encoder)
    }
}
