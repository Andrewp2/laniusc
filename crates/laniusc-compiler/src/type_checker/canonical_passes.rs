//! Canonical type identities (docs/canonical-type-ids.md): pass names,
//! capacities and compiler-graph registration. Kept out of the large
//! `compiler_graph.rs` so the canonical phases can change independently.

use crate::gpu::{
    compiler_graph::{
        CompilerGraphBuilder,
        CompilerPhase,
        ResourceClass,
        ResourceDesc,
        ResourceDomain,
        ResourceId,
    },
    workspace::WorkspaceUsageClass,
};

pub(super) const CANONICAL_CLEAR_PASS: &str = "type_check.canonical.clear";
pub(super) const CANONICAL_CLEAR_KERNEL: &str = "type_checker/canonical/00_clear";
pub(super) const CANONICAL_INTERN_KERNEL: &str = "type_checker/canonical/01_intern";
pub(super) const CANONICAL_ROUND_ARGS_KERNEL: &str = "type_checker/canonical/02_round_args";
/// The late stage re-arms empty and unknown candidates and keeps the table.
pub(super) const CANONICAL_REARM_PASS: &str = "type_check.canonical.late.rearm";
pub(super) const CANONICAL_REARM_KERNEL: &str = "type_checker/canonical/03_rearm";

/// Pass names of one interning stage. Round 0 interns every pending
/// candidate (direct); later rounds walk the GPU frontier (indirect), each
/// followed by the one-lane round close; every batch ends with a copy of the
/// interning counters.
pub(super) struct CanonicalRoundPasses {
    pub round0: &'static str,
    pub round_args: &'static str,
    pub round: &'static str,
    pub counts_readback: &'static str,
}

/// Interns the declared instance rows and constants, ahead of the closed
/// application index.
pub(super) const CANONICAL_EARLY_ROUNDS: CanonicalRoundPasses = CanonicalRoundPasses {
    round0: "type_check.canonical.round0",
    round_args: "type_check.canonical.round_args",
    round: "type_check.canonical.round",
    counts_readback: "type_check.canonical.counts.readback",
};

/// Interns what later producers added (generated and body applications,
/// constants published during inference) into the same table.
pub(super) const CANONICAL_LATE_ROUNDS: CanonicalRoundPasses = CanonicalRoundPasses {
    round0: "type_check.canonical.late.round0",
    round_args: "type_check.canonical.late.round_args",
    round: "type_check.canonical.late.round",
    counts_readback: "type_check.canonical.late.counts.readback",
};

/// Rounds recorded between two done-flag readbacks, and the round limit
/// (`CT_MAX_ROUNDS` in canonical_api.slang). Rounds equal the maximum
/// candidate height; the limit turns deeper candidates into UNKNOWN and sets
/// an overflow bit.
pub(super) const CANONICAL_ROUNDS_PER_BATCH: usize = 8;
pub(super) const CANONICAL_MAX_ROUNDS: usize = 64;
/// Debug validation: uniqueness and facts, the cross-check's coarse buckets,
/// then the cross-check against the previous graph equality. The cross-check
/// keeps the `90_validate` key (and its inlined-size budget line).
pub(super) const CANONICAL_VALIDATE_PASS: &str = "type_check.canonical.validate";
pub(super) const CANONICAL_VALIDATE_KERNEL: &str = "type_checker/canonical/88_validate_table";
pub(super) const CANONICAL_CROSSCHECK_BUCKETS_PASS: &str = "type_check.canonical.crosscheck.buckets";
pub(super) const CANONICAL_CROSSCHECK_BUCKETS_KERNEL: &str =
    "type_checker/canonical/89_crosscheck_buckets";
pub(super) const CANONICAL_CROSSCHECK_PASS: &str = "type_check.canonical.crosscheck";
pub(super) const CANONICAL_CROSSCHECK_KERNEL: &str = "type_checker/canonical/90_validate";
pub(super) const CANONICAL_VALIDATION_READBACK_PASS: &str =
    "type_check.canonical.validation.readback";
/// Debug kernels, prepared only when validation is enabled.
pub(super) const CANONICAL_DEBUG_KERNELS: [&str; 3] = [
    CANONICAL_VALIDATE_KERNEL,
    CANONICAL_CROSSCHECK_BUCKETS_KERNEL,
    CANONICAL_CROSSCHECK_KERNEL,
];
/// Words of `ct_counts` and of `canonical_validation`.
pub(super) const CANONICAL_COUNT_WORDS: usize = 16;
pub(super) const CANONICAL_VALIDATION_WORDS: usize = 36;
/// `ct_counts` words the host reads after each batch.
pub(super) const CANONICAL_COUNT_PENDING: usize = 2;
pub(super) const CANONICAL_COUNT_OVERFLOW: usize = 3;
pub(super) const CANONICAL_COUNT_ROUND: usize = 4;
/// Local declarations of a job without an owning library use this library
/// and unit; such jobs have no dependency interfaces to unify with.
pub(super) const CANONICAL_NO_LIBRARY: u32 = 0xffff_fffe;

/// Whether the debug validation of canonical identities (uniqueness, facts
/// and the cross-check against the previous graph equality) is compiled and
/// recorded.
pub(super) fn canonical_validation_enabled() -> bool {
    crate::gpu::env::env_bool_truthy("LANIUS_DEBUG_VALIDATE_CANONICAL", false)
}

/// Names of the `canonical_validation` counters (88_validate_table, 90_validate).
pub(super) const CANONICAL_VALIDATION_COUNTERS: [&str; 16] = [
    "false_merges",
    "missed_merges",
    "unknown_rows",
    "resolved_rows",
    "duplicate_records",
    "broken_chains",
    "inconsistent_facts",
    "unpublished",
    "pending",
    "live_records",
    "unknown_constants",
    "resolved_constants",
    "overflow",
    "rounds",
    "witnesses",
    "normalized_merges",
];

/// One `[canonical_validate]` line: every counter, then up to ten
/// (row, other) witness pairs of false and missed merges.
pub(super) fn canonical_validation_report(words: &[u32]) -> String {
    let mut line = String::from("[canonical_validate]");
    for (name, value) in CANONICAL_VALIDATION_COUNTERS.iter().zip(words) {
        line.push_str(&format!(" {name}={value}"));
    }
    let witnesses = words.get(14).copied().unwrap_or(0).min(10) as usize;
    for pair in words.get(16..16 + 2 * witnesses).unwrap_or(&[]).chunks_exact(2) {
        line.push_str(&format!(" witness={}:{}", pair[0], pair[1]));
    }
    line
}

/// Row capacities the canonical tables are sized from.
pub(super) struct CanonicalCapacity {
    pub token_rows: u64,
    pub hir_rows: u64,
    pub type_rows: u64,
    /// Rows of `checked_constant_atoms` and of `checked_constant_projections`.
    pub constant_rows: u64,
    /// Checked argument words of body and generated rows beyond the tokens.
    pub extra_argument_rows: u64,
}

fn storage(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    class: ResourceClass,
    bytes: u64,
) -> Result<ResourceId, String> {
    graph.add_storage(name, ResourceDomain::Types, class, bytes)
}

fn resource(graph: &CompilerGraphBuilder, name: &'static str) -> Result<ResourceId, String> {
    graph
        .resource_id(name)
        .ok_or_else(|| format!("missing canonical resource {name}"))
}

/// Declares the canonical tables and registers the early stage (clear and
/// rounds) in recording order. `register_canonical_late_passes` adds the late
/// stage and the debug validation.
///
/// Capacities (docs/canonical-type-ids.md, "Capacities"): candidates are
/// instance rows, constant atoms and constant projections, each owning one
/// fixed record. Dynamic records are count classes, at most one per
/// constant candidate. Arguments are bounded by the checked argument storage
/// plus an element/length pair per row and one child per projection, so an
/// overflow means a broken invariant rather than a large input.
pub(super) fn register_canonical_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    capacity: CanonicalCapacity,
) -> Result<(), String> {
    let CanonicalCapacity { token_rows, hir_rows, type_rows, constant_rows, extra_argument_rows } =
        capacity;
    let candidates = type_rows + 2 * constant_rows;
    let records = 32 + candidates + 2 * constant_rows;
    let argument_bytes = token_rows * 16
        + extra_argument_rows * 128
        + hir_rows * 4
        + type_rows * 8
        + constant_rows * 8;
    let workspace = ResourceClass::Workspace;
    storage(graph, "ct_head", workspace, records * 16)?;
    storage(graph, "ct_meta", workspace, records * 16)?;
    storage(graph, "ct_extra", workspace, records * 8)?;
    storage(graph, "ct_args", workspace, argument_bytes)?;
    storage(graph, "ct_slot", workspace, (records * 2).next_power_of_two() * 4)?;
    let counts = storage(graph, "ct_counts", workspace, CANONICAL_COUNT_WORDS as u64 * 4)?;
    storage(graph, "canonical_row", workspace, type_rows * 4)?;
    storage(graph, "canonical_atom", workspace, constant_rows * 4)?;
    storage(graph, "canonical_projection", workspace, constant_rows * 4)?;
    storage(graph, "canonical_frontier", workspace, candidates * 8)?;
    storage(graph, "canonical_validation", workspace, CANONICAL_VALIDATION_WORDS as u64 * 4)?;
    graph.add_resource(ResourceDesc {
        name: "canonical_round_args",
        domain: ResourceDomain::DispatchArguments,
        class: workspace,
        bytes: 12,
        usage: WorkspaceUsageClass::StorageIndirect,
    })?;
    let counts_readback = storage(
        graph,
        "canonical_counts_readback",
        ResourceClass::External,
        CANONICAL_COUNT_WORDS as u64 * 4,
    )?;
    storage(
        graph,
        "canonical_validation_readback",
        ResourceClass::External,
        CANONICAL_VALIDATION_WORDS as u64 * 4,
    )?;

    graph.add_kernel_initializer_by_name(
        CANONICAL_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        CANONICAL_CLEAR_KERNEL,
    )?;
    register_rounds(graph, kernels, &CANONICAL_EARLY_ROUNDS, counts, counts_readback)?;
    // Round 0 starts from an empty table: a record is read only after its
    // publication, which follows its write. Round 0 also appends the first
    // frontier before any round reads it.
    graph.mark_pass_bindings_initialize(
        CANONICAL_EARLY_ROUNDS.round0,
        &["ct_head", "ct_meta", "ct_extra", "ct_args", "canonical_frontier"],
    )?;
    graph.mark_pass_bindings_initialize(
        CANONICAL_EARLY_ROUNDS.round_args,
        &["canonical_round_args"],
    )?;
    Ok(())
}

/// Round 0, then batches of frontier rounds repeated until no candidate is
/// pending.
fn register_rounds(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    passes: &CanonicalRoundPasses,
    counts: ResourceId,
    counts_readback: ResourceId,
) -> Result<(), String> {
    for (name, kernel) in [
        (passes.round0, CANONICAL_INTERN_KERNEL),
        (passes.round_args, CANONICAL_ROUND_ARGS_KERNEL),
        (passes.round, CANONICAL_INTERN_KERNEL),
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
    graph.add_indirect_dispatch(passes.round, "canonical_round_args")?;
    graph.add_buffer_copy_pass(
        passes.counts_readback,
        CompilerPhase::TypeCheck,
        "ct_counts",
        counts,
        "canonical_counts_readback",
        counts_readback,
    )?;
    graph.repeat_pass_range(
        CANONICAL_MAX_ROUNDS as u32,
        passes.round_args,
        passes.counts_readback,
    )
}

/// Registers the late stage: re-arm the empty and unknown candidates, intern
/// them into the same table, then (when enabled) validate the final table.
pub(super) fn register_canonical_late_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    type_rows: u64,
) -> Result<(), String> {
    graph.add_kernel_pass_by_name(
        CANONICAL_REARM_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        CANONICAL_REARM_KERNEL,
        &[],
    )?;
    let counts = resource(graph, "ct_counts")?;
    let counts_readback = resource(graph, "canonical_counts_readback")?;
    register_rounds(graph, kernels, &CANONICAL_LATE_ROUNDS, counts, counts_readback)?;
    if canonical_validation_enabled() {
        // Bucket heads (a power of two at least the row count), then links.
        storage(
            graph,
            "canonical_crosscheck_links",
            ResourceClass::Workspace,
            (type_rows.next_power_of_two() + type_rows) * 4,
        )?;
        for (name, kernel) in [
            (CANONICAL_VALIDATE_PASS, CANONICAL_VALIDATE_KERNEL),
            (CANONICAL_CROSSCHECK_BUCKETS_PASS, CANONICAL_CROSSCHECK_BUCKETS_KERNEL),
            (CANONICAL_CROSSCHECK_PASS, CANONICAL_CROSSCHECK_KERNEL),
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
        // 88_validate_table clears the bucket heads and links.
        graph.mark_pass_bindings_initialize(CANONICAL_VALIDATE_PASS, &["canonical_crosscheck_links"])?;
        let validation = resource(graph, "canonical_validation")?;
        let validation_readback = resource(graph, "canonical_validation_readback")?;
        graph.add_buffer_copy_pass(
            CANONICAL_VALIDATION_READBACK_PASS,
            CompilerPhase::TypeCheck,
            "canonical_validation",
            validation,
            "canonical_validation_readback",
            validation_readback,
        )?;
    }
    Ok(())
}
