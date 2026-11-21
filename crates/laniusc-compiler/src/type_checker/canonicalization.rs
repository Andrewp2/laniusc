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
pub(super) const CANONICAL_CLEAR_KERNEL: &str = "type_checker/canonicalization/clear_canonical_interning_state";
pub(super) const CANONICAL_INTERN_KERNEL: &str = "type_checker/canonicalization/intern_canonical_types";
pub(super) const CANONICAL_ROUND_ARGS_KERNEL: &str = "type_checker/canonicalization/write_canonical_round_dispatch_args";
/// The early and late stages re-arm empty and unknown candidates and keep
/// the table (the dependency pages fill it first).
pub(super) const CANONICAL_EARLY_REARM_PASS: &str = "type_check.canonical.rearm";
pub(super) const CANONICAL_BODY_REARM_PASS: &str = "type_check.canonical.body.rearm";
pub(super) const CANONICAL_REARM_PASS: &str = "type_check.canonical.late.rearm";
pub(super) const CANONICAL_REARM_KERNEL: &str = "type_checker/canonicalization/rearm_canonical_type_candidates";
/// Lanes every re-arm sweep launches; each strides its candidates by this
/// count (canonical_rearm.slang, CANONICAL_REARM_LANES).
pub(super) const CANONICAL_REARM_LANES: u32 = 1 << 19;
/// A stage's re-arm also lists the candidates it left pending
/// (`canonical_pending`); the args pass sizes round 0 over that list.
pub(super) const CANONICAL_REARM_LIST_KERNEL: &str = "type_checker/canonicalization/list_canonical_candidates_to_rearm";
pub(super) const CANONICAL_REARM_LIVE_LIST_KERNEL: &str =
    "type_checker/canonicalization/list_live_canonical_candidates_to_rearm";
pub(super) const CANONICAL_REARM_ARGS_KERNEL: &str = "type_checker/canonicalization/write_canonical_rearm_dispatch_args";
pub(super) const CANONICAL_EARLY_REARM_ARGS_PASS: &str = "type_check.canonical.rearm_args";
pub(super) const CANONICAL_BODY_REARM_ARGS_PASS: &str = "type_check.canonical.body.rearm_args";
pub(super) const CANONICAL_REARM_ARGS_PASS: &str = "type_check.canonical.late.rearm_args";
/// Dependency signature types (tag 5) are interned per page while the page
/// is resident: the begin pass makes the page's nodes the round-0
/// candidates, and the rounds are the intern rounds of intern_dependency_types.
pub(super) const CANONICAL_DEPENDENCY_BEGIN_PASS: &str = "type_check.canonical.dependency.begin";
pub(super) const CANONICAL_DEPENDENCY_BEGIN_KERNEL: &str =
    "type_checker/canonicalization/seed_dependency_type_interning";
pub(super) const CANONICAL_DEPENDENCY_INTERN_KERNEL: &str =
    "type_checker/canonicalization/intern_dependency_types";

/// Pass names of one interning stage. Round 0 interns the pending
/// candidates (direct over a dependency page, indirect over the re-arm's
/// list for the other stages); later rounds walk the GPU frontier (indirect), each
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

/// Interns a body specialization's rows and constants after its bindings,
/// ahead of the body passes that read their IDs.
pub(super) const CANONICAL_BODY_ROUNDS: CanonicalRoundPasses = CanonicalRoundPasses {
    round0: "type_check.canonical.body.round0",
    round_args: "type_check.canonical.body.round_args",
    round: "type_check.canonical.body.round",
    counts_readback: "type_check.canonical.body.counts.readback",
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
/// keeps the `validate_canonical_type_equivalence` key (and its inlined-size budget line).
pub(super) const CANONICAL_VALIDATE_PASS: &str = "type_check.canonical.validate";
pub(super) const CANONICAL_VALIDATE_KERNEL: &str = "type_checker/canonicalization/validate_canonical_type_table";
pub(super) const CANONICAL_CROSSCHECK_BUCKETS_PASS: &str = "type_check.canonical.crosscheck.buckets";
pub(super) const CANONICAL_CROSSCHECK_BUCKETS_KERNEL: &str =
    "type_checker/canonicalization/crosscheck_canonical_type_buckets";
pub(super) const CANONICAL_CROSSCHECK_PASS: &str = "type_check.canonical.crosscheck";
pub(super) const CANONICAL_CROSSCHECK_KERNEL: &str = "type_checker/canonicalization/validate_canonical_type_equivalence";
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
/// Nonzero when a stage still had pending candidates after a batch
/// (`CT_COUNT_BATCH_PENDING`); kept until the job's clear.
pub(super) const CANONICAL_COUNT_BATCH_PENDING: usize = 11;

/// Whether a job recorded with one batch per stage and no readbacks must be
/// recorded again with readbacks: some stage left candidates pending, or a
/// capacity overflowed (the synchronous recording grows the table).
pub(super) fn canonical_deferred_retry_required(counts: &[u32]) -> bool {
    counts[CANONICAL_COUNT_BATCH_PENDING] != 0
        || counts[CANONICAL_COUNT_OVERFLOW] & CANONICAL_RETRY_OVERFLOW_BITS != 0
}

/// A job recorded without canonical readbacks has to be recorded again with
/// them (`canonical_deferred_retry_required`). The type checker has already
/// selected the synchronous recording for the next job.
#[derive(Debug)]
pub(crate) struct CanonicalSynchronousRetry {
    pub batch_pending: bool,
    pub overflow: u32,
}

impl std::fmt::Display for CanonicalSynchronousRetry {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "canonical interning needs counter readbacks (pending after one batch: {}, overflow {:#x})",
            self.batch_pending, self.overflow,
        )
    }
}

impl std::error::Error for CanonicalSynchronousRetry {}
/// `CT_OVERFLOW_*` bits a larger table fixes: the slot table, the records,
/// the argument words, the substitution memo (16, `CT_OVERFLOW_SUBST_MEMO`)
/// and the frontier lists (32). `CT_OVERFLOW_ROUNDS` (8)
/// is a height limit that no capacity changes, so it never retries.
pub(super) const CANONICAL_RETRY_OVERFLOW_BITS: u32 = 1 | 2 | 4 | 16 | 32;
/// Largest canonical capacity scale. Each retry doubles the scale; past this
/// limit an overflow fails the job instead of retrying it. At this scale the
/// records, the argument words and the frontier lists reach their worst-case
/// bounds.
pub(super) const CANONICAL_MAX_SCALE: u32 = 64;
/// Floors of the scale-1 records, argument words and frontier list entries.
/// Measured use is far below them (docs/canonical-type-ids.md, "Capacities
/// and overflow").
pub(super) const CANONICAL_MIN_RECORDS: u64 = 4096;
pub(super) const CANONICAL_MIN_ARGUMENT_WORDS: u64 = 16384;
pub(super) const CANONICAL_MIN_FRONTIER_ROWS: u64 = 4096;

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

/// Debug only: divide the records, argument words and frontier lists by `2^n`
/// (`LANIUS_CHECK=canonical-retry=n`, at most 16), so that small programs
/// overflow and exercise the retry.
fn canonical_capacity_shrink() -> u32 {
    crate::options::get().check.canonical_retry
}
/// Local declarations of a job without an owning library use this library
/// and unit; such jobs have no dependency interfaces to unify with.
pub(super) const CANONICAL_NO_LIBRARY: u32 = 0xffff_fffe;

/// Whether the debug validation of canonical identities (uniqueness, facts
/// and the cross-check against the previous graph equality) is compiled and
/// recorded.
pub(super) fn canonical_validation_enabled() -> bool {
    crate::options::get().check.canonical
}

/// Names of the `canonical_validation` counters (validate_canonical_type_table, validate_canonical_type_equivalence).
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

/// Counters after the witness pairs: dependency nodes (validate_canonical_type_table),
/// rows the old walker rejects against their bridged ID (validate_canonical_type_equivalence), the
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
    /// Records and argument words of the substitution producers
    /// (`substitution::substitution_canonical_extra`), part of the
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
/// nodes. None owns a record: a key the table lacks takes one, so a
/// candidate or node takes at most one per stage that interns it, and a body
/// replay interns every candidate twice more (its body and late stages).
/// Count classes add at most one record per constant candidate or node, and
/// twice more on a replay. Arguments are bounded by the checked argument
/// storage plus an element/length pair per row, one child per projection and
/// two per dependency node (signature trees have fewer edges than nodes),
/// three times for a replay. A frontier list holds the pending candidates of one round, or
/// the nodes of one page. Those worst-case bounds are what the tables hold
/// at `CANONICAL_MAX_SCALE`, where an overflow means a broken invariant
/// rather than a large input. A job starts at scale 1, with
/// 1/CANONICAL_MAX_SCALE of each bound (`canonical_scaled_capacity`); the
/// host doubles the scale and records the job again when a stage overflows
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
    // Records, argument words and frontier lists start at
    // 1/CANONICAL_MAX_SCALE of their worst-case bounds, and reach the bounds
    // at the largest retry scale. The debug shrink divides them too, so a
    // shrunken job still succeeds once the scale covers its use.
    let record_bound =
        3 * candidates + 2 * dependency_rows + 6 * constant_rows + extra_records;
    let records = 32
        + (canonical_scaled_capacity(record_bound, CANONICAL_MIN_RECORDS, scale) >> shrink).max(1);
    let candidate_argument_bytes = token_rows * 16
        + extra_argument_rows * 128
        + hir_rows * 4
        + type_rows * 8
        + constant_rows * 8;
    let argument_words = canonical_scaled_capacity(
        (3 * candidate_argument_bytes + dependency_rows * 8) / 4 + extra_argument_words,
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
    // Non-coherent views of the record tables and counters, for records an
    // earlier dispatch wrote (canonical_api.slang, CT_COUNT_FROZEN).
    for &(alias, table) in crate::gpu::passes_core::CACHED_BUFFER_VIEWS {
        let target = resource(graph, table)?;
        graph.add_resource_alias(alias, target)?;
    }
    storage(graph, "canonical_row", workspace, type_rows * 4)?;
    storage(graph, "canonical_atom", workspace, constant_rows * 4)?;
    storage(graph, "canonical_projection", workspace, constant_rows * 4)?;
    // Rearm sweeps own disjoint entries and do not require coherent views.
    for (view, table) in [
        ("canonical_row_rearm", "canonical_row"),
        ("canonical_atom_rearm", "canonical_atom"),
        ("canonical_projection_rearm", "canonical_projection"),
    ] {
        let target = resource(graph, table)?;
        graph.add_resource_alias(view, target)?;
    }
    storage(graph, "canonical_dependency_type", workspace, dependency_rows.max(1) * 4)?;
    // Two lists, each bounded by the candidates or by one page's nodes.
    let frontier_rows = canonical_scaled_capacity(
        candidates.max(dependency_page_rows),
        CANONICAL_MIN_FRONTIER_ROWS,
        scale,
    );
    storage(graph, "canonical_frontier", workspace, (frontier_rows >> shrink).max(1) * 8)?;
    // Round 0's input: every candidate a stage's re-arm left pending.
    storage(graph, "canonical_pending", workspace, candidates.max(1) * 4)?;
    storage(graph, "canonical_validation", workspace, CANONICAL_VALIDATION_WORDS as u64 * 4)?;
    if canonical_validation_enabled() {
        // The cross-check's representative row per record (crosscheck_canonical_type_buckets).
        storage(graph, "canonical_crosscheck_owner", workspace, records * 4)?;
    }
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
    register_rearm(
        graph,
        kernels,
        CANONICAL_EARLY_REARM_PASS,
        CANONICAL_REARM_LIST_KERNEL,
        CANONICAL_EARLY_REARM_ARGS_PASS,
    )?;
    // Lanes past the list's count never read it.
    graph.mark_pass_bindings_initialize(CANONICAL_EARLY_REARM_PASS, &["canonical_pending"])?;
    register_rounds(graph, kernels, &CANONICAL_EARLY_ROUNDS, CANONICAL_INTERN_KERNEL, &[])?;
    graph.add_indirect_dispatch(CANONICAL_EARLY_ROUNDS.round0, "canonical_round_args")
}

/// Registers the body stage: re-arm (every candidate on a replay) and intern
/// the specialized rows, after the body bindings and ahead of the body
/// passes that read their IDs.
pub(super) fn register_canonical_body_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
) -> Result<(), String> {
    register_rearm(
        graph,
        kernels,
        CANONICAL_BODY_REARM_PASS,
        CANONICAL_REARM_LIVE_LIST_KERNEL,
        CANONICAL_BODY_REARM_ARGS_PASS,
    )?;
    register_rounds(graph, kernels, &CANONICAL_BODY_ROUNDS, CANONICAL_INTERN_KERNEL, &[])?;
    graph.add_indirect_dispatch(CANONICAL_BODY_ROUNDS.round0, "canonical_round_args")
}

/// A stage's re-arm, which lists the pending candidates, and the pass that
/// sizes round 0 over the list. The early stage's list kernel visits every
/// candidate; the later stages' visits only the allocated ones.
fn register_rearm(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    rearm: &'static str,
    list_kernel: &'static str,
    args: &'static str,
) -> Result<(), String> {
    for (name, kernel) in [
        (rearm, list_kernel),
        (args, CANONICAL_REARM_ARGS_KERNEL),
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
    register_rearm(
        graph,
        kernels,
        CANONICAL_REARM_PASS,
        CANONICAL_REARM_LIVE_LIST_KERNEL,
        CANONICAL_REARM_ARGS_PASS,
    )?;
    register_rounds(graph, kernels, &CANONICAL_LATE_ROUNDS, CANONICAL_INTERN_KERNEL, &[])?;
    graph.add_indirect_dispatch(CANONICAL_LATE_ROUNDS.round0, "canonical_round_args")?;
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
        // validate_canonical_type_table clears the bucket heads, the links and the owners.
        graph.mark_pass_bindings_initialize(
            CANONICAL_VALIDATE_PASS,
            &["canonical_crosscheck_links", "canonical_crosscheck_owner"],
        )?;
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
