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
pub(super) const INSTANCE_CLOSURE_EXPORT_PASS: &str = "type_check.instance_closure.export";
pub(super) const INSTANCE_CLOSURE_EXPORT_FINAL_PASS: &str =
    "type_check.instance_closure.export_final";
const MARK_KERNEL: &str = "type_checker/closure/01_mark";
const ADVANCE_KERNEL: &str = "type_checker/closure/02_advance";
const EXPAND_KERNEL: &str = "type_checker/closure/03_expand";
const EXPORT_KERNEL: &str = "type_checker/closure/04_export";
const EXPORT_FINAL_KERNEL: &str = "type_checker/closure/04a_export_final";

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
    let head = storage(graph, "instance_closure_edge_head", hir_rows.max(1) * 4)?;
    storage(graph, "instance_closure_edge_next", hir_rows.max(1) * 4)?;
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
        ],
    })?;
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
        &["instance_closure_instances", "instance_closure_refs", "instance_closure_edge_next"],
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
    graph.mark_pass_bindings_initialize(INSTANCE_CLOSURE_ADVANCE_PASS, &["instance_closure_args"])?;
    graph.repeat_pass_range(
        INSTANCE_CLOSURE_LEVELS as u32,
        INSTANCE_CLOSURE_ADVANCE_PASS,
        INSTANCE_CLOSURE_EXPAND_PASS,
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
    }
    Ok(())
}

/// The closure of one original job: clear, mark the edges and roots, the
/// expansion rounds, the closing advance, then the export.
pub(in crate::type_checker) struct InstanceClosureOperations {
    clear: crate::gpu::operations::ClearBuffersOperation,
    mark: ComputeOperation,
    advance: ComputeOperation,
    expand: ComputeOperation,
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
        let instances = u32::try_from(buffer("instance_closure_instances")?.byte_size / 32)?;
        let clear = crate::gpu::operations::ClearBuffersOperation::new(
            graph,
            INSTANCE_CLOSURE_CLEAR_PASS,
            &[
                ("instance_closure_counts", (&counts).into()),
                ("instance_closure_set", (&set).into()),
                ("instance_closure_edge_head", (&head).into()),
            ],
        )?;
        let direct = |name, kernel, elements| {
            ComputeOperation::direct(device, graph, resources, name, &passes.kernel(kernel), elements)
        };
        Ok(Self {
            clear,
            mark: direct(INSTANCE_CLOSURE_MARK_PASS, MARK_KERNEL, hir_capacity)?,
            advance: direct(INSTANCE_CLOSURE_ADVANCE_PASS, ADVANCE_KERNEL, 1)?,
            expand: ComputeOperation::indirect(
                device,
                graph,
                resources,
                INSTANCE_CLOSURE_EXPAND_PASS,
                &passes.kernel(EXPAND_KERNEL),
                &buffer("instance_closure_args")?,
            )?,
            export: direct(INSTANCE_CLOSURE_EXPORT_PASS, EXPORT_KERNEL, instances)?,
            export_final: direct(INSTANCE_CLOSURE_EXPORT_FINAL_PASS, EXPORT_FINAL_KERNEL, instances)?,
        })
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.clear.record(encoder);
        self.mark.record(encoder)?;
        for _ in 0..INSTANCE_CLOSURE_LEVELS {
            self.advance.record(encoder)?;
            self.expand.record(encoder)?;
        }
        self.advance.record(encoder)?;
        for _ in 0..EXPORT_RETRIES {
            self.export.record(encoder)?;
        }
        self.export_final.record(encoder)
    }
}
