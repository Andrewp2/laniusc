//! Canonical type identities (docs/canonical-type-ids.md): pass names,
//! capacities and compiler-graph registration. Kept out of the large
//! `compiler_graph.rs` so the canonical phases can change independently.

use crate::gpu::{
    compiler_graph::{
        AccessMode,
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

pub(super) const CANONICAL_CLEAR_PASS: &str = "type_check.canonical.clear";
pub(super) const CANONICAL_CLEAR_KERNEL: &str = "type_checker/canonical/00_clear";
pub(super) const CANONICAL_INTERN_KERNEL: &str = "type_checker/canonical/01_intern";
pub(super) const CANONICAL_ROUND_ARGS_KERNEL: &str = "type_checker/canonical/02_round_args";
/// The early and late stages re-arm empty and unknown candidates and keep
/// the table (the dependency pages fill it first).
pub(super) const CANONICAL_EARLY_REARM_PASS: &str = "type_check.canonical.rearm";
pub(super) const CANONICAL_REARM_PASS: &str = "type_check.canonical.late.rearm";
pub(super) const CANONICAL_REARM_KERNEL: &str = "type_checker/canonical/03_rearm";
/// Dependency signature types (tag 5) are interned per page while the page
/// is resident: the begin pass makes the page's nodes the round-0
/// candidates, and the rounds are the intern rounds of 05_intern_dependency.
pub(super) const CANONICAL_DEPENDENCY_BEGIN_PASS: &str = "type_check.canonical.dependency.begin";
pub(super) const CANONICAL_DEPENDENCY_BEGIN_KERNEL: &str =
    "type_checker/canonical/04_dependency_begin";
pub(super) const CANONICAL_DEPENDENCY_INTERN_KERNEL: &str =
    "type_checker/canonical/05_intern_dependency";

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

/// Interns the resident dependency page.
pub(super) const CANONICAL_DEPENDENCY_ROUNDS: CanonicalRoundPasses = CanonicalRoundPasses {
    round0: "type_check.canonical.dependency.round0",
    round_args: "type_check.canonical.dependency.round_args",
    round: "type_check.canonical.dependency.round",
    counts_readback: "type_check.canonical.dependency.counts.readback",
};

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
pub(super) const CANONICAL_VALIDATION_WORDS: usize = 41;
/// `ct_counts` words the host reads after each batch.
pub(super) const CANONICAL_COUNT_PENDING: usize = 2;
pub(super) const CANONICAL_COUNT_OVERFLOW: usize = 3;
pub(super) const CANONICAL_COUNT_ROUND: usize = 4;
/// `CT_OVERFLOW_*` bits a larger table fixes: the slot table, the records
/// and the argument words, and (16, `CT_OVERFLOW_SUBST_MEMO` in
/// ct_subst.slang) the substitution memo, which grows with the scale
/// (`substitution_passes::memo_entries`). `CT_OVERFLOW_ROUNDS` (8) is a
/// height limit that no capacity changes, so it never retries.
pub(super) const CANONICAL_RETRY_OVERFLOW_BITS: u32 = 1 | 2 | 4 | 16;
/// Largest canonical capacity scale. Each retry doubles the scale; past this
/// limit an overflow fails the job instead of retrying it. At this scale the
/// dynamic records and the argument words reach their worst-case bounds.
pub(super) const CANONICAL_MAX_SCALE: u32 = 64;
/// Floors of the scale-1 dynamic records and argument words. Measured use is
/// far below both (docs/canonical-type-ids.md, "Capacities and overflow").
pub(super) const CANONICAL_MIN_DYNAMIC_RECORDS: u64 = 4096;
pub(super) const CANONICAL_MIN_ARGUMENT_WORDS: u64 = 16384;

/// A dynamic capacity at `scale`: 1/CANONICAL_MAX_SCALE of the worst-case
/// `bound` (at least `floor`) times the scale, never more than the bound.
pub(super) fn canonical_scaled_capacity(bound: u64, floor: u64, scale: u32) -> u64 {
    let base = bound.div_ceil(u64::from(CANONICAL_MAX_SCALE)).max(floor);
    (base * u64::from(scale.clamp(1, CANONICAL_MAX_SCALE))).min(bound.max(floor))
}

/// A canonical stage ran out of table capacity. The job is abandoned and
/// recorded again with a doubled capacity scale (docs/canonical-type-ids.md,
/// "Capacities and overflow").
#[derive(Debug)]
pub(super) struct CanonicalCapacityOverflow {
    pub bits: u32,
    pub stage: &'static str,
    pub scale: u32,
    /// Next record and next argument word, and their capacities.
    pub records: [u32; 2],
    pub args: [u32; 2],
}

impl std::fmt::Display for CanonicalCapacityOverflow {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "canonical table overflow {:#x} in the {} stage at scale {} (records {}/{}, argument words {}/{})",
            self.bits, self.stage, self.scale, self.records[0], self.records[1], self.args[0],
            self.args[1],
        )
    }
}

impl std::error::Error for CanonicalCapacityOverflow {}

/// The capacity scale of the retry after `overflow`, or `None` when the
/// overflow is not a capacity overflow or the scale is at its limit.
pub(super) fn canonical_retry_scale(scale: u32, overflow: u32) -> Option<u32> {
    (overflow & CANONICAL_RETRY_OVERFLOW_BITS != 0 && scale < CANONICAL_MAX_SCALE)
        .then(|| scale.max(1) * 2)
}

/// Debug only: divide the dynamic records and the argument words by `2^n`
/// (`LANIUS_DEBUG_CANONICAL_SHRINK=n`, at most 16), so that small programs
/// overflow and exercise the retry.
fn canonical_capacity_shrink() -> u32 {
    std::env::var("LANIUS_DEBUG_CANONICAL_SHRINK")
        .ok()
        .and_then(|value| value.parse::<u32>().ok())
        .map_or(0, |shift| shift.min(16))
}
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

/// Counters after the witness pairs: dependency nodes (88_validate_table),
/// rows the old walker rejects against their bridged ID (90_validate), the
/// largest record height, and the generated application rows (88).
pub(super) const CANONICAL_LATE_COUNTERS: [(&str, usize); 5] = [
    ("unknown_dependency", 36),
    ("resolved_dependency", 37),
    ("bridge_mismatches", 38),
    ("max_height", 39),
    ("type_applications", 40),
];

/// One `[canonical_validate]` line: every counter, then up to ten
/// (row, other) witness pairs of false and missed merges.
pub(super) fn canonical_validation_report(words: &[u32]) -> String {
    let mut line = String::from("[canonical_validate]");
    for (name, value) in CANONICAL_VALIDATION_COUNTERS.iter().zip(words) {
        line.push_str(&format!(" {name}={value}"));
    }
    for (name, index) in CANONICAL_LATE_COUNTERS {
        if let Some(value) = words.get(index) {
            line.push_str(&format!(" {name}={value}"));
        }
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
    /// Dependency signature nodes over every page of the job (the constant
    /// span total), and the largest page's node count.
    pub dependency_rows: u64,
    pub dependency_page_rows: u64,
    /// Capacity scale of the records and argument words: 1, doubled by each
    /// overflow retry of the job (`canonical_retry_scale`).
    pub scale: u32,
    /// Dynamic records and argument words of the substitution producers
    /// (`substitution_passes::substitution_canonical_extra`), part of the
    /// scaled bounds.
    pub extra_records: u64,
    pub extra_argument_words: u64,
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

/// Declares the canonical tables and registers the clear, ahead of the
/// dependency pages. `register_canonical_dependency_passes`,
/// `register_canonical_early_passes` and `register_canonical_late_passes`
/// add the stages in recording order.
///
/// Capacities (docs/canonical-type-ids.md, "Capacities"): candidates are
/// instance rows, constant atoms and constant projections, and dependency
/// nodes, each owning one fixed record. Dynamic records are count classes,
/// at most one per constant candidate or node. Arguments are bounded by the
/// checked argument storage plus an element/length pair per row, one child
/// per projection and two per dependency node (signature trees have fewer
/// edges than nodes). A body replay interns every candidate a second time
/// (one more key, and a dynamic record when it was rewritten), which doubles
/// the candidates' records and arguments. Those worst-case bounds are what
/// the tables hold at `CANONICAL_MAX_SCALE`, where an overflow means a broken
/// invariant rather than a large input. A job starts at scale 1, with the
/// fixed records and 1/CANONICAL_MAX_SCALE of the dynamic records and of the
/// argument words (`canonical_scaled_capacity`); the host doubles the scale
/// and records the job again when a stage overflows
/// (`CanonicalCapacityOverflow`).
pub(super) fn register_canonical_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    capacity: CanonicalCapacity,
) -> Result<u64, String> {
    let CanonicalCapacity {
        token_rows,
        hir_rows,
        type_rows,
        constant_rows,
        extra_argument_rows,
        dependency_rows,
        dependency_page_rows,
        scale,
        extra_records,
        extra_argument_words,
    } = capacity;
    let candidates = type_rows + 2 * constant_rows;
    let shrink = canonical_capacity_shrink();
    // The fixed records (ct_dynamic_base) are exact. The dynamic records and
    // the argument words start at 1/CANONICAL_MAX_SCALE of their worst-case
    // bounds, and reach the bounds at the largest retry scale.
    // The debug shrink divides only what a retry grows, so a shrunken job
    // still succeeds once the scale covers its use.
    let fixed = 32 + candidates + dependency_rows.max(1);
    let dynamic = canonical_scaled_capacity(
        candidates + 4 * constant_rows + dependency_rows + extra_records,
        CANONICAL_MIN_DYNAMIC_RECORDS,
        scale,
    );
    let records = fixed + (dynamic >> shrink).max(1);
    let candidate_argument_bytes = token_rows * 16
        + extra_argument_rows * 128
        + hir_rows * 4
        + type_rows * 8
        + constant_rows * 8;
    let argument_words = canonical_scaled_capacity(
        (2 * candidate_argument_bytes + dependency_rows * 8) / 4 + extra_argument_words,
        CANONICAL_MIN_ARGUMENT_WORDS,
        scale,
    );
    let argument_bytes = (argument_words >> shrink).max(4) * 4;
    let workspace = ResourceClass::Workspace;
    storage(graph, "ct_head", workspace, records * 16)?;
    storage(graph, "ct_meta", workspace, records * 16)?;
    storage(graph, "ct_extra", workspace, records * 8)?;
    storage(graph, "ct_args", workspace, argument_bytes)?;
    storage(graph, "ct_slot", workspace, (records * 2).next_power_of_two() * 4)?;
    storage(graph, "ct_counts", workspace, CANONICAL_COUNT_WORDS as u64 * 4)?;
    storage(graph, "canonical_row", workspace, type_rows * 4)?;
    storage(graph, "canonical_atom", workspace, constant_rows * 4)?;
    storage(graph, "canonical_projection", workspace, constant_rows * 4)?;
    storage(graph, "canonical_dependency_type", workspace, dependency_rows.max(1) * 4)?;
    // Two lists, each for every candidate or every node of one page.
    storage(graph, "canonical_frontier", workspace, candidates.max(dependency_page_rows) * 8)?;
    storage(graph, "canonical_validation", workspace, CANONICAL_VALIDATION_WORDS as u64 * 4)?;
    graph.add_resource(ResourceDesc {
        name: "canonical_round_args",
        domain: ResourceDomain::DispatchArguments,
        class: workspace,
        bytes: 12,
        usage: WorkspaceUsageClass::StorageIndirect,
    })?;
    storage(
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
    Ok(records)
}

/// Registers the per-page dependency interning, after the dependency
/// type-instance projection that shares its page. `canonical_type_roots` is
/// the page's alias-root relation.
pub(super) fn register_canonical_dependency_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    canonical_type_roots: ResourceId,
) -> Result<(), String> {
    graph.add_kernel_pass_by_name(
        CANONICAL_DEPENDENCY_BEGIN_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        CANONICAL_DEPENDENCY_BEGIN_KERNEL,
        &[],
    )?;
    let roots = [ReflectedResourceBinding {
        binding: "canonical_type_roots",
        resource: canonical_type_roots,
        mode: Some(AccessMode::Read),
    }];
    let rounds = &CANONICAL_DEPENDENCY_ROUNDS;
    register_rounds(graph, kernels, rounds, CANONICAL_DEPENDENCY_INTERN_KERNEL, &roots)?;
    // The first round of the job starts from an empty table: a record is
    // read only after its publication, which follows its write. Round 0 also
    // appends the first frontier before any round reads it.
    graph.mark_pass_bindings_initialize(
        rounds.round0,
        &["ct_head", "ct_meta", "ct_extra", "ct_args", "canonical_frontier"],
    )?;
    graph.mark_pass_bindings_initialize(rounds.round_args, &["canonical_round_args"])
}

/// Registers the early stage: re-arm the table the dependency pages started
/// and intern the declared rows and constants, ahead of the closed
/// application index.
pub(super) fn register_canonical_early_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
) -> Result<(), String> {
    graph.add_kernel_pass_by_name(
        CANONICAL_EARLY_REARM_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        CANONICAL_REARM_KERNEL,
        &[],
    )?;
    register_rounds(graph, kernels, &CANONICAL_EARLY_ROUNDS, CANONICAL_INTERN_KERNEL, &[])
}

/// Round 0, then batches of frontier rounds repeated until no candidate is
/// pending.
fn register_rounds(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    passes: &CanonicalRoundPasses,
    intern_kernel: &'static str,
    intern_bindings: &[ReflectedResourceBinding],
) -> Result<(), String> {
    let counts = resource(graph, "ct_counts")?;
    let counts_readback = resource(graph, "canonical_counts_readback")?;
    for (name, kernel, bindings) in [
        (passes.round0, intern_kernel, intern_bindings),
        (passes.round_args, CANONICAL_ROUND_ARGS_KERNEL, &[][..]),
        (passes.round, intern_kernel, intern_bindings),
    ] {
        graph.add_kernel_pass_by_name(
            name,
            CompilerPhase::TypeCheck,
            ResourceDomain::Types,
            kernels,
            kernel,
            bindings,
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

/// Registers the late stage: re-arm the empty and unknown candidates (every
/// candidate after a body replay), intern them into the same table, then
/// (when enabled) validate the final table.
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
    register_rounds(graph, kernels, &CANONICAL_LATE_ROUNDS, CANONICAL_INTERN_KERNEL, &[])?;
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
