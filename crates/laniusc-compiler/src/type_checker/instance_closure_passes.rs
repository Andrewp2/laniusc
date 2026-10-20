//! The instance closure of an original job (shaders/type_checker/closure,
//! D_PLAN D1): resources, pass names, compiler-graph registration and the
//! operations that record them. The closure finds, on the GPU, the concrete
//! bodies the unit's own generic calls reach at every instantiation depth,
//! so their replays can share the first replay round.

use super::*;
use crate::gpu::{
    compiler_graph::{
        CompilerGraphBuilder,
        CompilerPhase,
        PassAccess,
        PassDesc,
        ReflectedResourceBinding,
        ResourceClass,
        ResourceDesc,
        ResourceDomain,
        ResourceId,
    },
    workspace::WorkspaceUsageClass,
};

pub(super) const INSTANCE_CLOSURE_CLEAR_PASS: &str = "type_check.instance_closure.clear";
pub(super) const INSTANCE_CLOSURE_MARK_PASS: &str = "type_check.instance_closure.mark";
pub(super) const INSTANCE_CLOSURE_ADVANCE_PASS: &str = "type_check.instance_closure.advance";
pub(super) const INSTANCE_CLOSURE_EXPAND_PASS: &str = "type_check.instance_closure.expand";
pub(super) const INSTANCE_CLOSURE_EXPAND_BOUND_PASS: &str = "type_check.instance_closure.expand_bound";
pub(super) const INSTANCE_CLOSURE_EXPORT_PASS: &str = "type_check.instance_closure.export";
pub(super) const INSTANCE_CLOSURE_EXPORT_FINAL_PASS: &str =
    "type_check.instance_closure.export_final";
pub(super) const INSTANCE_CLOSURE_IMPORT_SUMMARY_PASS: &str =
    "type_check.instance_closure.import_summary";
pub(super) const INSTANCE_CLOSURE_MARK_DEPENDENCY_PASS: &str =
    "type_check.instance_closure.mark_dependency_roots";
pub(super) const INSTANCE_CLOSURE_EXPAND_DEPENDENCY_PASS: &str =
    "type_check.instance_closure.expand_dependency";
const MARK_KERNEL: &str = "type_checker/closure/01_mark";
const ADVANCE_KERNEL: &str = "type_checker/closure/02_advance";
const EXPAND_KERNEL: &str = "type_checker/closure/03_expand";
const EXPAND_BOUND_KERNEL: &str = "type_checker/closure/03c_expand_bound";
const EXPORT_KERNEL: &str = "type_checker/closure/04_export";
const EXPORT_FINAL_KERNEL: &str = "type_checker/closure/04a_export_final";
const IMPORT_SUMMARY_KERNEL: &str = "type_checker/closure/00b_import_summary";
const MARK_DEPENDENCY_KERNEL: &str = "type_checker/closure/01b_mark_dependency_roots";
const EXPAND_DEPENDENCY_KERNEL: &str = "type_checker/closure/03b_expand_dependency";
pub(super) const INSTANCE_TABLE_CLEAR_PASS: &str = "type_check.instance_table.clear";
pub(super) const INSTANCE_TABLE_KEYS_PASS: &str = "type_check.instance_table.keys";
pub(super) const INSTANCE_TABLE_RANK_PASS: &str = "type_check.instance_table.rank";
pub(super) const INSTANCE_TABLE_ARGS_PASS: &str = "type_check.instance_table.args";
pub(super) const INSTANCE_TABLE_ROWS_PASS: &str = "type_check.instance_table.rows";
pub(super) const INSTANCE_TABLE_ROWS_FINAL_PASS: &str = "type_check.instance_table.rows_final";
const TABLE_KEYS_KERNEL: &str = "type_checker/closure/05_table_keys";
const TABLE_RANK_KERNEL: &str = "type_checker/closure/05b_table_rank";
const TABLE_ARGS_KERNEL: &str = "type_checker/closure/05c_table_args";
const TABLE_ROWS_KERNEL: &str = "type_checker/closure/06_table_rows";
const TABLE_ROWS_FINAL_KERNEL: &str = "type_checker/closure/06a_table_rows_final";
/// Words of `instance_table_counts` (`IT_COUNT_WORDS`).
pub(super) const INSTANCE_TABLE_COUNT_WORDS: u64 = 4;
/// Row dispatches ahead of the final one (as the export's retries).
const TABLE_ROW_RETRIES: usize = 4;
/// The job's dependency closure summaries (D1b; closure_summary.rs).
pub(super) const CLOSURE_SUMMARY_INPUTS: &str = "closure_summary_inputs";
const CLOSURE_SUMMARY_CT: &str = "closure_summary_ct";

/// Expansion rounds (`IC_LEVELS` in instance_closure.slang): instances up
/// to depth `INSTANCE_CLOSURE_LEVELS + 1` are found.
pub(super) const INSTANCE_CLOSURE_LEVELS: usize = 6;
/// Export dispatches ahead of the final one. A lane that meets a row another
/// lane is realizing stops for the dispatch (CT_REALIZE_BUSY), so nested
/// arguments shared along a chain realize about one level per dispatch: one
/// retry per closure level keeps every found depth exportable.
const EXPORT_RETRIES: usize = INSTANCE_CLOSURE_LEVELS + 1;
/// Words of `instance_closure_counts` (`IC_COUNT_WORDS`).
pub(super) const INSTANCE_CLOSURE_COUNT_WORDS: u64 = 8;
/// Average argument words per instance the reference table holds.
const ARGUMENTS_PER_INSTANCE: u64 = 8;

/// Instances one job can hold: one per 16 HIR rows, at least 1024 and at
/// most 65536. A full table only loses instances (the replays find them).
pub(super) fn instance_capacity(hir_rows: u64) -> u64 {
    (hir_rows / 16).clamp(1024, 65536)
}

/// Canonical records and argument words the closure adds to a job: per
/// instance, its tagged environment and the substituted nodes of its
/// bindings. An overflow fails the job closed and retries it at a larger
/// canonical scale, like every other producer's.
pub(super) fn closure_canonical_extra(hir_rows: u64) -> (u64, u64) {
    let instances = instance_capacity(hir_rows);
    (4 * instances, 2 * ARGUMENTS_PER_INSTANCE * instances)
}

/// Canonical records and argument words the dependency closure (D1b) adds:
/// one record per imported summary node, with its children.
pub(super) fn closure_dependency_canonical_extra() -> (u64, u64) {
    (
        super::closure_summary::SUMMARY_MAX_NODES as u64,
        super::closure_summary::SUMMARY_MAX_ARGS as u64,
    )
}

fn storage(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    bytes: u64,
) -> Result<ResourceId, String> {
    graph.add_storage(name, ResourceDomain::Types, ResourceClass::Workspace, bytes)
}

/// Declares the closure's tables and registers its passes, after the late
/// generic call results. `realize_bindings` resolve the row arena's
/// write-only layout words, as for the alias-target realization.
pub(super) fn register_instance_closure_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    hir_rows: u64,
    realize_bindings: &[ReflectedResourceBinding],
) -> Result<(), String> {
    let instances = instance_capacity(hir_rows);
    let counts = storage(graph, "instance_closure_counts", INSTANCE_CLOSURE_COUNT_WORDS * 4)?;
    let set = storage(graph, "instance_closure_set", (2 * instances).next_power_of_two() * 8)?;
    storage(graph, "instance_closure_instances", instances * 32)?;
    storage(graph, "instance_closure_refs", instances * ARGUMENTS_PER_INSTANCE * 8)?;
    storage(graph, "instance_closure_targets", instances * 16)?;
    let head = storage(graph, "instance_closure_edge_head", hir_rows.max(1) * 4)?;
    storage(graph, "instance_closure_edge_next", hir_rows.max(1) * 4)?;
    let summary_ct = storage(
        graph,
        CLOSURE_SUMMARY_CT,
        super::closure_summary::SUMMARY_MAX_NODES as u64 * 4,
    )?;
    graph.add_storage(
        CLOSURE_SUMMARY_INPUTS,
        ResourceDomain::Types,
        ResourceClass::External,
        super::closure_summary::SUMMARY_INPUT_WORDS as u64 * 4,
    )?;
    graph.add_resource(ResourceDesc {
        name: "instance_closure_args",
        domain: ResourceDomain::DispatchArguments,
        class: ResourceClass::Workspace,
        bytes: 12,
        usage: WorkspaceUsageClass::StorageIndirect,
    })?;
    graph.add_pass(PassDesc {
        name: INSTANCE_CLOSURE_CLEAR_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Types,
        accesses: vec![
            PassAccess::write("instance_closure_counts", counts),
            PassAccess::write("instance_closure_set", set),
            PassAccess::write("instance_closure_edge_head", head),
            PassAccess::write(CLOSURE_SUMMARY_CT, summary_ct),
        ],
    })?;
    // The dependency summaries' nodes intern ahead of the roots (D1b).
    graph.add_kernel_pass_by_name(
        INSTANCE_CLOSURE_IMPORT_SUMMARY_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        IMPORT_SUMMARY_KERNEL,
        &[],
    )?;
    graph.add_kernel_pass_by_name(
        INSTANCE_CLOSURE_MARK_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        MARK_KERNEL,
        &[],
    )?;
    // Mark writes every instance row and edge link it appends before any
    // pass reads it, and readers stay below the appended counts; the
    // argument table only reserves its blocks here (export fills them).
    graph.mark_pass_bindings_initialize(
        INSTANCE_CLOSURE_MARK_PASS,
        &[
            "instance_closure_instances",
            "instance_closure_refs",
            "instance_closure_targets",
            "instance_closure_edge_next",
        ],
    )?;
    // Roots into the dependencies' summary functions append after mark's.
    graph.add_kernel_pass_by_name(
        INSTANCE_CLOSURE_MARK_DEPENDENCY_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        MARK_DEPENDENCY_KERNEL,
        &[],
    )?;
    graph.add_kernel_pass_by_name(
        INSTANCE_CLOSURE_ADVANCE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        ADVANCE_KERNEL,
        &[],
    )?;
    graph.add_kernel_pass_by_name(
        INSTANCE_CLOSURE_EXPAND_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        EXPAND_KERNEL,
        &[],
    )?;
    graph.add_indirect_dispatch(INSTANCE_CLOSURE_EXPAND_PASS, "instance_closure_args")?;
    // The same frontier's bound-member edges route under each instance (D3).
    graph.add_kernel_pass_by_name(
        INSTANCE_CLOSURE_EXPAND_BOUND_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        EXPAND_BOUND_KERNEL,
        &[],
    )?;
    graph.add_indirect_dispatch(INSTANCE_CLOSURE_EXPAND_BOUND_PASS, "instance_closure_args")?;
    // The same frontier's summary instances expand through their edges.
    graph.add_kernel_pass_by_name(
        INSTANCE_CLOSURE_EXPAND_DEPENDENCY_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        EXPAND_DEPENDENCY_KERNEL,
        &[],
    )?;
    graph.add_indirect_dispatch(INSTANCE_CLOSURE_EXPAND_DEPENDENCY_PASS, "instance_closure_args")?;
    graph.mark_pass_bindings_initialize(INSTANCE_CLOSURE_ADVANCE_PASS, &["instance_closure_args"])?;
    graph.repeat_pass_range(
        INSTANCE_CLOSURE_LEVELS as u32,
        INSTANCE_CLOSURE_ADVANCE_PASS,
        INSTANCE_CLOSURE_EXPAND_DEPENDENCY_PASS,
    )?;
    for (name, kernel) in [
        (INSTANCE_CLOSURE_EXPORT_PASS, EXPORT_KERNEL),
        (INSTANCE_CLOSURE_EXPORT_FINAL_PASS, EXPORT_FINAL_KERNEL),
    ] {
        graph.add_kernel_pass_by_name(
            name,
            CompilerPhase::TypeCheck,
            ResourceDomain::Types,
            kernels,
            kernel,
            realize_bindings,
        )?;
        graph.add_indirect_dispatch(name, "instance_closure_args")?;
    }
    Ok(())
}

/// Virtual rows one job's instance table holds: half its HIR rows. A full
/// row table flags the table, and the host ignores it.
pub(super) fn instance_table_row_capacity(hir_rows: u64) -> u64 {
    (hir_rows / 2).max(1024)
}

/// Declares the instance table (D2; closure/instance_table.slang) and
/// registers its passes, after the expression references and the owner
/// spans. `realize_bindings` as for the closure's export.
pub(super) fn register_instance_table_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    hir_rows: u64,
    realize_bindings: &[ReflectedResourceBinding],
) -> Result<(), String> {
    // Off (the default), the passes are never recorded: the table keeps
    // one row of each buffer so the graph holds no workspace for it.
    let enabled = instance_table_enabled();
    let instances = if enabled { instance_capacity(hir_rows) } else { 1 };
    let row_capacity = if enabled { instance_table_row_capacity(hir_rows) } else { 1 };
    let counts = storage(graph, "instance_table_counts", INSTANCE_TABLE_COUNT_WORDS * 4)?;
    storage(graph, "instance_table_keys", instances * 16)?;
    storage(graph, "instance_table", instances * 32)?;
    let rows = storage(graph, "instance_row_refs", row_capacity * 8)?;
    graph.add_resource(ResourceDesc {
        name: "instance_table_args",
        domain: ResourceDomain::DispatchArguments,
        class: ResourceClass::Workspace,
        bytes: 12,
        usage: WorkspaceUsageClass::StorageIndirect,
    })?;
    graph.add_pass(PassDesc {
        name: INSTANCE_TABLE_CLEAR_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Types,
        accesses: vec![
            PassAccess::write("instance_table_counts", counts),
            PassAccess::write("instance_row_refs", rows),
        ],
    })?;
    for (name, kernel) in [
        (INSTANCE_TABLE_KEYS_PASS, TABLE_KEYS_KERNEL),
        (INSTANCE_TABLE_RANK_PASS, TABLE_RANK_KERNEL),
    ] {
        graph.add_kernel_pass_by_name(name, CompilerPhase::TypeCheck, ResourceDomain::Types, kernels, kernel, &[])?;
        graph.add_indirect_dispatch(name, "instance_closure_args")?;
    }
    // Keys are written for every appended instance before rank reads them;
    // the table's entries are read only below the counted entries. Every
    // kernel binds all of the table module's buffers; the keys pass never
    // touches the table itself, so it reads nothing uninitialized there.
    graph.mark_pass_bindings_initialize(INSTANCE_TABLE_KEYS_PASS, &["instance_table_keys", "instance_table"])?;
    graph.mark_pass_bindings_initialize(INSTANCE_TABLE_RANK_PASS, &["instance_table"])?;
    graph.add_kernel_pass_by_name(
        INSTANCE_TABLE_ARGS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        TABLE_ARGS_KERNEL,
        &[],
    )?;
    graph.mark_pass_bindings_initialize(INSTANCE_TABLE_ARGS_PASS, &["instance_table_args"])?;
    for (name, kernel) in [
        (INSTANCE_TABLE_ROWS_PASS, TABLE_ROWS_KERNEL),
        (INSTANCE_TABLE_ROWS_FINAL_PASS, TABLE_ROWS_FINAL_KERNEL),
    ] {
        graph.add_kernel_pass_by_name(
            name,
            CompilerPhase::TypeCheck,
            ResourceDomain::Types,
            kernels,
            kernel,
            realize_bindings,
        )?;
        graph.add_indirect_dispatch(name, "instance_table_args")?;
    }
    Ok(())
}

/// `LANIUS_INSTANCE_TABLE=1` builds the instance table in original jobs
/// that run the closure (D2, behind its flag);
/// `LANIUS_CHECK_INSTANCE_TABLE=1` also reads it back and checks it against
/// every copy run's own types.
pub(in crate::type_checker) fn instance_table_enabled() -> bool {
    static ENABLED: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ENABLED.get_or_init(|| instance_table_checked()
        || crate::gpu::env::env_bool_truthy("LANIUS_INSTANCE_TABLE", false))
}

pub(crate) fn instance_table_checked() -> bool {
    static ENABLED: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ENABLED.get_or_init(|| crate::gpu::env::env_bool_truthy("LANIUS_CHECK_INSTANCE_TABLE", false))
}

/// The instance table of one original job: clear, keys, ranks, the row
/// dispatch size, then the row realizations with their retries.
pub(in crate::type_checker) struct InstanceTableOperations {
    clear: crate::gpu::operations::ClearBuffersOperation,
    keys: ComputeOperation,
    rank: ComputeOperation,
    args: ComputeOperation,
    rows: ComputeOperation,
    rows_final: ComputeOperation,
}

impl InstanceTableOperations {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        passes: &TypeCheckPasses,
    ) -> Result<Self> {
        let buffer = |name| typed_buffer_from_resources::<u32>(resources, name);
        let counts = buffer("instance_table_counts")?;
        let rows = buffer("instance_row_refs")?;
        let clear = crate::gpu::operations::ClearBuffersOperation::new(
            graph,
            INSTANCE_TABLE_CLEAR_PASS,
            &[
                ("instance_table_counts", (&counts).into()),
                ("instance_row_refs", (&rows).into()),
            ],
        )?;
        let closure_args = buffer("instance_closure_args")?;
        let table_args = buffer("instance_table_args")?;
        let indirect = |name, kernel, args| {
            ComputeOperation::indirect(device, graph, resources, name, &passes.kernel(kernel), args)
        };
        Ok(Self {
            clear,
            keys: indirect(INSTANCE_TABLE_KEYS_PASS, TABLE_KEYS_KERNEL, &closure_args)?,
            rank: indirect(INSTANCE_TABLE_RANK_PASS, TABLE_RANK_KERNEL, &closure_args)?,
            args: ComputeOperation::direct(
                device,
                graph,
                resources,
                INSTANCE_TABLE_ARGS_PASS,
                &passes.kernel(TABLE_ARGS_KERNEL),
                1,
            )?,
            rows: indirect(INSTANCE_TABLE_ROWS_PASS, TABLE_ROWS_KERNEL, &table_args)?,
            rows_final: indirect(INSTANCE_TABLE_ROWS_FINAL_PASS, TABLE_ROWS_FINAL_KERNEL, &table_args)?,
        })
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.clear.record(encoder);
        self.keys.record(encoder)?;
        self.rank.record(encoder)?;
        self.args.record(encoder)?;
        for _ in 0..TABLE_ROW_RETRIES {
            self.rows.record(encoder)?;
        }
        self.rows_final.record(encoder)
    }
}

/// `LANIUS_CLOSURE_BOUND_MEMBERS=0` leaves bound-member calls to the replay
/// rounds (D3's kill switch): their edges are linked but never routed.
pub(in crate::type_checker) fn closure_bound_members_enabled() -> bool {
    static ENABLED: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ENABLED.get_or_init(|| crate::gpu::env::env_bool_truthy("LANIUS_CLOSURE_BOUND_MEMBERS", true))
}

/// The closure of one original job: clear, mark the edges and roots, the
/// expansion rounds, the closing advance, then the export. A job with
/// dependency summaries also imports them, roots its calls into them and
/// expands their instances in every round (D1b).
pub(in crate::type_checker) struct InstanceClosureOperations {
    clear: crate::gpu::operations::ClearBuffersOperation,
    import_summary: ComputeOperation,
    mark: ComputeOperation,
    mark_dependency: ComputeOperation,
    advance: ComputeOperation,
    expand: ComputeOperation,
    expand_bound: ComputeOperation,
    expand_dependency: ComputeOperation,
    export: ComputeOperation,
    export_final: ComputeOperation,
}

impl InstanceClosureOperations {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        passes: &TypeCheckPasses,
        hir_capacity: u32,
    ) -> Result<Self> {
        let buffer = |name| typed_buffer_from_resources::<u32>(resources, name);
        let counts = buffer("instance_closure_counts")?;
        let set = buffer("instance_closure_set")?;
        let head = buffer("instance_closure_edge_head")?;
        let summary_ct = buffer(CLOSURE_SUMMARY_CT)?;
        let clear = crate::gpu::operations::ClearBuffersOperation::new(
            graph,
            INSTANCE_CLOSURE_CLEAR_PASS,
            &[
                ("instance_closure_counts", (&counts).into()),
                ("instance_closure_set", (&set).into()),
                ("instance_closure_edge_head", (&head).into()),
                (CLOSURE_SUMMARY_CT, (&summary_ct).into()),
            ],
        )?;
        let direct = |name, kernel, elements| {
            ComputeOperation::direct(device, graph, resources, name, &passes.kernel(kernel), elements)
        };
        let args = buffer("instance_closure_args")?;
        let indirect = |name, kernel| {
            ComputeOperation::indirect(device, graph, resources, name, &passes.kernel(kernel), &args)
        };
        Ok(Self {
            clear,
            import_summary: direct(
                INSTANCE_CLOSURE_IMPORT_SUMMARY_PASS,
                IMPORT_SUMMARY_KERNEL,
                super::closure_summary::SUMMARY_MAX_NODES as u32,
            )?,
            mark: direct(INSTANCE_CLOSURE_MARK_PASS, MARK_KERNEL, hir_capacity)?,
            mark_dependency: direct(
                INSTANCE_CLOSURE_MARK_DEPENDENCY_PASS,
                MARK_DEPENDENCY_KERNEL,
                hir_capacity,
            )?,
            advance: direct(INSTANCE_CLOSURE_ADVANCE_PASS, ADVANCE_KERNEL, 1)?,
            expand: indirect(INSTANCE_CLOSURE_EXPAND_PASS, EXPAND_KERNEL)?,
            expand_bound: indirect(INSTANCE_CLOSURE_EXPAND_BOUND_PASS, EXPAND_BOUND_KERNEL)?,
            expand_dependency: indirect(
                INSTANCE_CLOSURE_EXPAND_DEPENDENCY_PASS,
                EXPAND_DEPENDENCY_KERNEL,
            )?,
            // The closing advance writes the export's arguments: one lane
            // per appended instance, none when the table is empty.
            export: indirect(INSTANCE_CLOSURE_EXPORT_PASS, EXPORT_KERNEL)?,
            export_final: indirect(INSTANCE_CLOSURE_EXPORT_FINAL_PASS, EXPORT_FINAL_KERNEL)?,
        })
    }

    /// `import_rounds` is the summaries' import depth (0 without any: the
    /// dependency passes are then not recorded).
    pub(in crate::type_checker) fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        import_rounds: u32,
    ) -> Result<()> {
        self.clear.record(encoder);
        for _ in 0..import_rounds {
            self.import_summary.record(encoder)?;
        }
        self.mark.record(encoder)?;
        if import_rounds != 0 {
            self.mark_dependency.record(encoder)?;
        }
        for _ in 0..INSTANCE_CLOSURE_LEVELS {
            self.advance.record(encoder)?;
            self.expand.record(encoder)?;
            if closure_bound_members_enabled() {
                self.expand_bound.record(encoder)?;
            }
            if import_rounds != 0 {
                self.expand_dependency.record(encoder)?;
            }
        }
        self.advance.record(encoder)?;
        for _ in 0..EXPORT_RETRIES {
            self.export.record(encoder)?;
        }
        self.export_final.record(encoder)
    }
}
