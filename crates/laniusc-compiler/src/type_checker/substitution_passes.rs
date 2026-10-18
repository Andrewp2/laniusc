//! Substitution over canonical IDs (docs/canonical-type-ids.md,
//! "Substitution"): resources, pass names, compiler-graph registration and
//! the operations that record them. Kept out of `compiler_graph.rs` so the
//! substitution producers can change independently.

use super::*;
use crate::gpu::{
    compiler_graph::{
        CompilerGraphBuilder,
        CompilerPhase,
        ReflectedResourceBinding,
        ResourceClass,
        ResourceDesc,
        ResourceDomain,
        ResourceId,
    },
    workspace::WorkspaceUsageClass,
};

pub(super) const SUBSTITUTION_CLEAR_PASS: &str = "type_check.substitution.clear";
pub(super) const SUBSTITUTION_CLEAR_KERNEL: &str = "type_checker/substitution/00_clear";
pub(super) const SUBSTITUTION_SEED_PASS: &str = "type_check.substitution.seed";
pub(super) const SUBSTITUTION_SEED_KERNEL: &str = "type_checker/substitution/01_seed_rows";
/// A body specialization restarts the substitution state after its
/// canonical stage: the replay rewrote rows the job-start seed recorded.
pub(super) const SUBSTITUTION_BODY_CLEAR_PASS: &str = "type_check.substitution.body.clear";
pub(super) const SUBSTITUTION_BODY_SEED_PASS: &str = "type_check.substitution.body.seed";
/// Then the replay's body graph rows become the rows of their IDs, so a
/// realized type keeps each type argument's seed row and its width witness.
pub(super) const SUBSTITUTION_BODY_ROWS_PASS: &str = "type_check.substitution.body.seed_rows";
pub(super) const SUBSTITUTION_BODY_ROWS_KERNEL: &str =
    "type_checker/substitution/01b_seed_body_rows";
/// Call environments, republished each inference round before the argument
/// contexts consume them.
pub(super) const SUBSTITUTION_CALL_ENVS_PASS: &str = "type_check.substitution.call_envs";
pub(super) const SUBSTITUTION_CALL_ENVS_KERNEL: &str =
    "type_checker/substitution/02_publish_call_envs";
/// Words of `ct_subst_counts` (`CT_SUBST_COUNT_WORDS` in ct_subst.slang).
pub(super) const SUBSTITUTION_COUNT_WORDS: u64 = 8;
/// Imported alias targets (dependencies/14a) are realized after the last
/// dependency page: dispatches that leave a busy target for the next one,
/// then one that reports it. The early canonical stage re-arms the
/// candidates 14a interned (`CT_COUNT_EARLY_REARM`).
pub(super) const ALIAS_TARGETS_REALIZE_PASS: &str = "type_check.substitution.alias_targets.realize";
pub(super) const ALIAS_TARGETS_REALIZE_KERNEL: &str =
    "type_checker/substitution/08_realize_alias_targets";
pub(super) const ALIAS_TARGETS_REALIZE_FINAL_PASS: &str =
    "type_check.substitution.alias_targets.realize_final";
pub(super) const ALIAS_TARGETS_REALIZE_FINAL_KERNEL: &str =
    "type_checker/substitution/08a_realize_alias_targets_final";
/// Realization dispatches ahead of the reporting one.
const ALIAS_TARGET_RETRIES: usize = 2;

/// The field closure (ct_expand.slang): each run queues its roots, then
/// expands the queue in level rounds and closes with one more advance.
pub(super) const EXPAND_ADVANCE_KERNEL: &str = "type_checker/substitution/06_expand_advance";
pub(super) const EXPAND_LEVEL_KERNEL: &str = "type_checker/substitution/05_expand_level";
/// Level rounds per run (`CT_EXPAND_LEVELS_PER_RUN` in ct_expand.slang).
pub(super) const EXPAND_LEVELS_PER_RUN: usize = 4;
/// Words of `ct_expand_counts` (`CT_EXPAND_COUNT_WORDS`).
const EXPAND_COUNT_WORDS: u64 = 8;

/// The passes of one field-closure run.
pub(super) struct FieldClosurePasses {
    pub roots: &'static str,
    pub roots_kernel: &'static str,
    pub advance: &'static str,
    pub level: &'static str,
}

/// The closed source applications, after the closed application index (in
/// place of the old per-root materializer, type/instances/02d).
pub(super) const SOURCE_FIELD_CLOSURE: FieldClosurePasses = FieldClosurePasses {
    roots: "type_check.substitution.expand.source_roots",
    roots_kernel: "type_checker/substitution/03_expand_source_roots",
    advance: "type_check.substitution.expand.source_advance",
    level: "type_check.substitution.expand.source_level",
};

/// A body specialization's applications, after its canonical stage and the
/// body application index (in place of type/instances/02d there).
pub(super) const BODY_FIELD_CLOSURE: FieldClosurePasses = FieldClosurePasses {
    roots: "type_check.body_specialization.expand.roots",
    roots_kernel: "type_checker/substitution/03_expand_source_roots",
    advance: "type_check.body_specialization.expand.advance",
    level: "type_check.body_specialization.expand.level",
};

/// Call results and argument contexts, in each inference round after the
/// return types (in place of calls/03e1).
pub(super) const CALL_FIELD_CLOSURE: FieldClosurePasses = FieldClosurePasses {
    roots: "type_check.substitution.expand.call_roots",
    roots_kernel: "type_checker/substitution/04_expand_call_roots",
    advance: "type_check.substitution.expand.call_advance",
    level: "type_check.substitution.expand.call_level",
};

/// Canonical records and argument words the substitution producers add to
/// a job beyond the candidates' own: per call, a value and an expected
/// environment for each change of its bindings and the substituted nodes of
/// its parameter patterns; array contexts add one array and one count per
/// literal level; imported alias targets intern their leaf rows ahead of
/// the early stage (a record per type row at most) and their substituted
/// signatures. A record overflow fails closed (the producers see
/// `CT_UNKNOWN`), so this bounds what a job can express rather than what
/// it uses.
pub(super) fn substitution_canonical_extra(hir_rows: u64, type_rows: u64) -> (u64, u64) {
    let records = 4 * hir_rows + type_rows;
    let argument_words = 8 * hir_rows + 4 * type_rows;
    (records, argument_words)
}

/// Largest memo growth: a retry past this canonical scale keeps the memo.
const MEMO_MAX_SCALE: u32 = 16;

/// Memo entries: a power of two, at least two per HIR row, times the
/// canonical scale. A full memo sets `CT_OVERFLOW_SUBST_MEMO`, which records
/// the job again at twice the scale (`CANONICAL_RETRY_OVERFLOW_BITS`).
pub(super) fn memo_entries(hir_rows: u64, scale: u32) -> u64 {
    ((2 * hir_rows).max(4096) * u64::from(scale.clamp(1, MEMO_MAX_SCALE))).next_power_of_two()
}

fn storage(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    bytes: u64,
) -> Result<ResourceId, String> {
    graph.add_storage(name, ResourceDomain::Types, ResourceClass::Workspace, bytes)
}

/// Declares the substitution state and registers its clear, ahead of the
/// dependency pages (imported alias targets substitute before the early
/// canonical stage). `records` is the canonical record capacity (`ct_head`
/// rows).
pub(super) fn register_substitution_state(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    token_rows: u64,
    hir_rows: u64,
    records: u64,
    scale: u32,
) -> Result<(), String> {
    storage(graph, "ct_subst_memo", memo_entries(hir_rows, scale) * 16)?;
    storage(graph, "ct_subst_counts", SUBSTITUTION_COUNT_WORDS * 4)?;
    storage(graph, "ct_row_of", records.max(1) * 4)?;
    storage(graph, "call_env_ct", token_rows.max(1) * 8)?;
    // The field closure: a mark bit per ID, and a queue in which an ID
    // appears once per job plus deferred and retried entries.
    let records = records.max(1);
    storage(graph, "ct_expand_mark", records.div_ceil(32) * 4)?;
    storage(graph, "ct_expand_queue", (records + records / 8 + 256) * 8)?;
    storage(graph, "ct_expand_deferred", (records / 8 + 256) * 8)?;
    storage(graph, "ct_expand_counts", EXPAND_COUNT_WORDS * 4)?;
    graph.add_resource(ResourceDesc {
        name: "ct_expand_args",
        domain: ResourceDomain::DispatchArguments,
        class: ResourceClass::Workspace,
        bytes: 12,
        usage: WorkspaceUsageClass::StorageIndirect,
    })?;
    graph.add_kernel_initializer_by_name(
        SUBSTITUTION_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        SUBSTITUTION_CLEAR_KERNEL,
    )?;
    Ok(())
}

/// Registers the row seed, after the early canonical stage has interned the
/// source rows.
pub(super) fn register_substitution_seed(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
) -> Result<(), String> {
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

/// Registers the body restart (clear, seed, then the body graph rows), after
/// the body canonical stage.
pub(super) fn register_substitution_body_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
) -> Result<(), String> {
    for (name, kernel) in [
        (SUBSTITUTION_BODY_CLEAR_PASS, SUBSTITUTION_CLEAR_KERNEL),
        (SUBSTITUTION_BODY_SEED_PASS, SUBSTITUTION_SEED_KERNEL),
        (SUBSTITUTION_BODY_ROWS_PASS, SUBSTITUTION_BODY_ROWS_KERNEL),
    ] {
        graph.add_kernel_pass_by_name(
            name,
            CompilerPhase::TypeCheck,
            ResourceDomain::Types,
            kernels,
            kernel,
            &[],
        )?;
    }
    Ok(())
}

/// Registers the realization of the imported alias targets, after
/// dependencies/14a. `realize_bindings` resolve the row arena's write-only
/// layout words and the alias targets.
pub(super) fn register_alias_target_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    realize_bindings: &[ReflectedResourceBinding],
) -> Result<(), String> {
    for (name, kernel) in [
        (ALIAS_TARGETS_REALIZE_PASS, ALIAS_TARGETS_REALIZE_KERNEL),
        (ALIAS_TARGETS_REALIZE_FINAL_PASS, ALIAS_TARGETS_REALIZE_FINAL_KERNEL),
    ] {
        graph.add_kernel_pass_by_name(
            name,
            CompilerPhase::TypeCheck,
            ResourceDomain::Tokens,
            kernels,
            kernel,
            realize_bindings,
        )?;
    }
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

/// Registers one field-closure run: its roots kernel (dispatched over
/// `roots_domain` by `roots_dispatch`), then the level rounds.
/// `level_bindings` resolve the level kernel's dependency-page and layout
/// bindings.
pub(super) fn register_field_closure_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    passes: &FieldClosurePasses,
    roots_domain: ResourceDomain,
    roots_dispatch: &'static str,
    level_bindings: &[ReflectedResourceBinding],
) -> Result<(), String> {
    graph.add_kernel_pass_by_name(
        passes.roots,
        CompilerPhase::TypeCheck,
        roots_domain,
        kernels,
        passes.roots_kernel,
        &[],
    )?;
    graph.add_indirect_dispatch(passes.roots, roots_dispatch)?;
    graph.add_kernel_pass_by_name(
        passes.advance,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        EXPAND_ADVANCE_KERNEL,
        &[],
    )?;
    graph.add_kernel_pass_by_name(
        passes.level,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        EXPAND_LEVEL_KERNEL,
        level_bindings,
    )?;
    graph.add_indirect_dispatch(passes.level, "ct_expand_args")?;
    graph.mark_pass_bindings_initialize(passes.advance, &["ct_expand_args"])?;
    graph.repeat_pass_range(EXPAND_LEVELS_PER_RUN as u32, passes.advance, passes.level)
}

/// One field-closure run: the roots, the level rounds, the closing advance.
pub(in crate::type_checker) struct FieldClosureOperations {
    roots: ComputeOperation,
    advance: ComputeOperation,
    level: ComputeOperation,
}

impl FieldClosureOperations {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        passes: &TypeCheckPasses,
        names: &FieldClosurePasses,
        roots_dispatch: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        Ok(Self {
            roots: ComputeOperation::indirect(
                device,
                graph,
                resources,
                names.roots,
                &passes.kernel(names.roots_kernel),
                roots_dispatch,
            )?,
            advance: ComputeOperation::direct(
                device,
                graph,
                resources,
                names.advance,
                &passes.kernel(EXPAND_ADVANCE_KERNEL),
                1,
            )?,
            level: ComputeOperation::indirect(
                device,
                graph,
                resources,
                names.level,
                &passes.kernel(EXPAND_LEVEL_KERNEL),
                &typed_buffer_from_resources(resources, "ct_expand_args")?,
            )?,
        })
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.roots.record(encoder)?;
        for _ in 0..EXPAND_LEVELS_PER_RUN {
            self.advance.record(encoder)?;
            self.level.record(encoder)?;
        }
        self.advance.record(encoder)
    }
}

/// The once-per-job substitution passes: clear, then seed each ID's row.
pub(in crate::type_checker) struct SubstitutionOperations {
    clear: ComputeOperation,
    seed: ComputeOperation,
    body_clear: ComputeInvocation,
    body_seed: ComputeInvocation,
    body_rows: ComputeOperation,
    alias_realize: ComputeOperation,
    alias_realize_final: ComputeOperation,
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
            .max(words("ct_expand_mark")?)
            .max(words("call_env_ct")? / 2)
            .max(SUBSTITUTION_COUNT_WORDS as u32);
        let candidates =
            words("canonical_row")? + words("canonical_atom")? + words("canonical_projection")?;
        let direct = |name, kernel, elements| {
            ComputeOperation::direct(device, graph, resources, name, &passes.kernel(kernel), elements)
        };
        let alias_targets = words("imported_type_alias_target")? / 2;
        let clear = direct(SUBSTITUTION_CLEAR_PASS, SUBSTITUTION_CLEAR_KERNEL, clear_elements)?;
        let seed = direct(SUBSTITUTION_SEED_PASS, SUBSTITUTION_SEED_KERNEL, candidates)?;
        Ok(Self {
            body_clear: clear.invocation(graph, SUBSTITUTION_BODY_CLEAR_PASS)?,
            body_seed: seed.invocation(graph, SUBSTITUTION_BODY_SEED_PASS)?,
            // One lane per body graph node.
            body_rows: direct(
                SUBSTITUTION_BODY_ROWS_PASS,
                SUBSTITUTION_BODY_ROWS_KERNEL,
                generic_body::MAX_BODY_GRAPH_NODES as u32,
            )?,
            clear,
            seed,
            alias_realize: direct(
                ALIAS_TARGETS_REALIZE_PASS,
                ALIAS_TARGETS_REALIZE_KERNEL,
                alias_targets,
            )?,
            alias_realize_final: direct(
                ALIAS_TARGETS_REALIZE_FINAL_PASS,
                ALIAS_TARGETS_REALIZE_FINAL_KERNEL,
                alias_targets,
            )?,
        })
    }

    /// Records the clear alone: ahead of the dependency pages, whose alias
    /// targets substitute before the early canonical stage.
    pub(in crate::type_checker) fn record_clear(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.clear.record(encoder)
    }

    /// Records the realization of the imported alias targets; after the last
    /// dependency page's alias targets.
    pub(in crate::type_checker) fn record_alias_targets(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        for _ in 0..ALIAS_TARGET_RETRIES {
            self.alias_realize.record(encoder)?;
        }
        self.alias_realize_final.record(encoder)
    }

    /// Records the clear and the seed again, then the body graph rows; after
    /// the body canonical stage.
    pub(in crate::type_checker) fn record_body_start(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.clear.record_invocation(encoder, &self.body_clear)?;
        self.seed.record_invocation(encoder, &self.body_seed)?;
        self.body_rows.record(encoder)
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
