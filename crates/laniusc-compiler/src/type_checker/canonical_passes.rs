//! Canonical type identities (docs/canonical-type-ids.md): pass names,
//! capacities and compiler-graph registration. Kept out of the large
//! `compiler_graph.rs` so the canonical phases can change independently.

use crate::gpu::{
    compiler_graph::{CompilerGraphBuilder, CompilerPhase, ResourceClass, ResourceDesc, ResourceDomain},
    workspace::WorkspaceUsageClass,
};

pub(super) const CANONICAL_CLEAR_PASS: &str = "type_check.canonical.clear";
pub(super) const CANONICAL_CLEAR_KERNEL: &str = "type_checker/canonical/00_clear";
/// Round 0 interns every candidate (direct); later rounds walk the GPU
/// frontier (indirect), each followed by the one-lane round close.
pub(super) const CANONICAL_ROUND0_PASS: &str = "type_check.canonical.round0";
pub(super) const CANONICAL_ROUND_PASS: &str = "type_check.canonical.round";
pub(super) const CANONICAL_INTERN_KERNEL: &str = "type_checker/canonical/01_intern";
pub(super) const CANONICAL_ROUND_ARGS_PASS: &str = "type_check.canonical.round_args";
pub(super) const CANONICAL_ROUND_ARGS_KERNEL: &str = "type_checker/canonical/02_round_args";
pub(super) const CANONICAL_COUNTS_READBACK_PASS: &str = "type_check.canonical.counts.readback";
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
) -> Result<crate::gpu::compiler_graph::ResourceId, String> {
    graph.add_storage(name, ResourceDomain::Types, class, bytes)
}

/// Declares the canonical tables and registers clear, rounds, the counter
/// readback and (when enabled) the debug validation, in recording order.
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
    let validation =
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
    let validation_readback = storage(
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
    for (name, kernel) in [
        (CANONICAL_ROUND0_PASS, CANONICAL_INTERN_KERNEL),
        (CANONICAL_ROUND_ARGS_PASS, CANONICAL_ROUND_ARGS_KERNEL),
        (CANONICAL_ROUND_PASS, CANONICAL_INTERN_KERNEL),
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
    graph.add_indirect_dispatch(CANONICAL_ROUND_PASS, "canonical_round_args")?;
    // Round 0 starts from an empty table: a record is read only after its
    // publication, which follows its write. Round 0 also appends the first
    // frontier before any round reads it.
    graph.mark_pass_bindings_initialize(
        CANONICAL_ROUND0_PASS,
        &["ct_head", "ct_meta", "ct_extra", "ct_args", "canonical_frontier"],
    )?;
    graph.mark_pass_bindings_initialize(CANONICAL_ROUND_ARGS_PASS, &["canonical_round_args"])?;
    graph.add_buffer_copy_pass(
        CANONICAL_COUNTS_READBACK_PASS,
        CompilerPhase::TypeCheck,
        "ct_counts",
        counts,
        "canonical_counts_readback",
        counts_readback,
    )?;
    // Batches of frontier rounds repeat until no candidate is pending.
    graph.repeat_pass_range(
        CANONICAL_MAX_ROUNDS as u32,
        CANONICAL_ROUND_ARGS_PASS,
        CANONICAL_COUNTS_READBACK_PASS,
    )?;
    if canonical_validation_enabled() {
        // Bucket heads (a power of two at least the row count), then links.
        storage(
            graph,
            "canonical_crosscheck_links",
            workspace,
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
