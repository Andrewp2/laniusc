use super::*;

const PREFLIGHT_CLEAR_PASS: &str = "type_check.preflight.clear";
const PREFLIGHT_COUNT_PASS: &str = "type_check.modules.count_record_candidates";
const PREFLIGHT_READBACK_PASS: &str = "type_check.preflight.readback";

pub(super) struct TypeCheckPreflightGraph {
    materialized: crate::gpu::compiler_graph::MaterializedCompilerGraph,
    bindings: crate::gpu::compiler_graph::CompilerGraphBindings,
    readback: LaniusBuffer<u32>,
}

impl TypeCheckPreflightGraph {
    pub(super) fn new(device: &wgpu::Device, passes: &TypeCheckPasses) -> Result<Self> {
        use crate::gpu::{
            compiler_graph::{
                CompilerGraphBuilder,
                CompilerPhase,
                PassAccess,
                PassDesc,
                ResourceClass,
                ResourceDesc,
                ResourceDomain,
            },
            workspace::WorkspaceUsageClass,
        };

        let mut graph = CompilerGraphBuilder::new();
        for name in [
            "compact_hir_count",
            "compact_hir_core",
            "compact_hir_payload",
            "compact_path_count",
            "compact_param_count",
            "compact_call_arg_count",
            "compact_variant_count",
        ] {
            graph
                .add_resource(ResourceDesc {
                    name,
                    domain: ResourceDomain::HirNodes,
                    class: ResourceClass::Input,
                    bytes: 1,
                    usage: WorkspaceUsageClass::Storage,
                })
                .map_err(anyhow::Error::msg)?;
        }
        let candidate_counts = graph
            .add_resource(ResourceDesc {
                name: "candidate_counts",
                domain: ResourceDomain::Declarations,
                class: ResourceClass::Output,
                bytes: 3 * std::mem::size_of::<u32>() as u64,
                usage: WorkspaceUsageClass::Storage,
            })
            .map_err(anyhow::Error::msg)?;
        let candidate_counts_readback = graph
            .add_resource(ResourceDesc {
                name: "candidate_counts_readback",
                domain: ResourceDomain::Declarations,
                class: ResourceClass::External,
                bytes: 3 * std::mem::size_of::<u32>() as u64,
                usage: WorkspaceUsageClass::Storage,
            })
            .map_err(anyhow::Error::msg)?;
        graph
            .add_pass(PassDesc {
                name: PREFLIGHT_CLEAR_PASS,
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Declarations,
                accesses: vec![PassAccess::write("candidate_counts", candidate_counts)],
            })
            .map_err(anyhow::Error::msg)?;
        graph
            .add_kernel_pass_by_name(
                PREFLIGHT_COUNT_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                passes,
                "type_checker/modules/00a_count_record_candidates",
                &[],
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .add_buffer_copy_pass(
                PREFLIGHT_READBACK_PASS,
                CompilerPhase::TypeCheck,
                "candidate_counts",
                candidate_counts,
                "candidate_counts_readback",
                candidate_counts_readback,
            )
            .map_err(anyhow::Error::msg)?;
        graph.add_registered_pass_arena_conflicts();
        let graph = graph.build().map_err(anyhow::Error::msg)?;
        graph
            .validate_assigned_pass_reflections(passes)
            .map_err(anyhow::Error::msg)?;
        let materialized =
            crate::gpu::compiler_graph::MaterializedCompilerGraph::new_with_upstream_storage(
                device,
                "type_check.preflight",
                graph,
                &[],
            )
            .map_err(anyhow::Error::msg)?;
        let bindings = materialized.bindings()?;
        let readback = readback_u32s(device, "rb.type_check.preflight_capacities", 3);
        Ok(Self {
            materialized,
            bindings,
            readback,
        })
    }

    fn candidate_counts(&self) -> Result<LaniusBuffer<u32>> {
        self.materialized.u32_buffer("candidate_counts")
    }

    fn register_bindings<'a>(&'a self, resources: &mut ResourceMap<'a>) {
        resources.attach_graph(self.materialized.graph(), self.materialized.allocations());
        resources.register_graph_bindings(self.materialized.graph(), &self.bindings);
    }

    fn readback(&self) -> LaniusBuffer<u32> {
        self.readback.clone()
    }
}

impl crate::gpu::operations::ComputeGraph for TypeCheckPreflightGraph {
    fn graph(&self) -> &crate::gpu::compiler_graph::CompilerGraph {
        self.materialized.graph()
    }

    fn allocations(&self) -> &crate::gpu::compiler_graph::CompilerGraphAllocations {
        self.materialized.allocations()
    }
}

/// GPU-measured compact capacities needed before resident typecheck allocation.
#[derive(Clone, Copy, Debug)]
pub struct TypeCheckPreflightCapacities {
    pub module_records: u32,
    pub call_param_rows: u32,
    pub call_arg_rows: u32,
}

/// Host-readable result of the GPU compact-record preflight.
pub struct RecordedModuleRecordCapacity {
    candidate_counts: LaniusBuffer<u32>,
    readback: LaniusBuffer<u32>,
}

impl GpuTypeChecker {
    /// Counts compact module, parameter-capacity, and call-argument rows on the GPU.
    ///
    /// The output is a dedicated word because typechecking still consumes the
    /// parser semantic-count buffer after this boundary.
    pub fn record_module_record_capacity_preflight(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        source_file_capacity: u32,
        token_capacity: u32,
        parse_bufs: &crate::parser::buffers::ParserBuffers,
    ) -> Result<RecordedModuleRecordCapacity> {
        let params = TypeCheckParams {
            n_tokens: token_capacity,
            source_len,
            n_hir_nodes: parse_bufs.tree_capacity,
            n_source_files: source_file_capacity,
            parser_feature_flags: parse_bufs.parser_feature_flags,
            dependency_interfaces_present: 0,
        };
        queue.write_buffer(&self.params_buf, 0, &type_check_params_bytes(&params));

        let candidate_counts = self.preflight_graph.candidate_counts()?;
        let mut resources = ResourceMap::new();
        self.preflight_graph.register_bindings(&mut resources);
        resources.add("gParams", self.params_buf.as_entire_binding());
        resources.add(
            "compact_hir_count",
            parse_bufs.hir_canonical_count.as_entire_binding(),
        );
        resources.add("compact_hir_core", parse_bufs.hir_core.as_entire_binding());
        resources.add(
            "compact_hir_payload",
            parse_bufs.hir_payload.as_entire_binding(),
        );
        resources.add(
            "compact_path_count",
            parse_bufs.hir_path_table_count.as_entire_binding(),
        );
        resources.add(
            "compact_param_count",
            parse_bufs.hir_param_table_count.as_entire_binding(),
        );
        resources.add(
            "compact_call_arg_count",
            parse_bufs.hir_call_arg_table_count.as_entire_binding(),
        );
        resources.add(
            "compact_variant_count",
            parse_bufs.hir_variant_table_count.as_entire_binding(),
        );
        let clear = crate::gpu::operations::ClearBufferOperation::entire(
            &self.preflight_graph,
            PREFLIGHT_CLEAR_PASS,
            "candidate_counts",
            &candidate_counts,
        )?;
        let count = crate::gpu::operations::ComputeOperation::direct(
            device,
            &self.preflight_graph,
            &resources,
            PREFLIGHT_COUNT_PASS,
            &self
                .passes
                .kernel("type_checker/modules/00a_count_record_candidates"),
            parse_bufs.tree_capacity,
        )?;
        clear.record(encoder);
        count.record(encoder)?;

        let readback = self.preflight_graph.readback();
        let copy = crate::gpu::operations::CopyBufferOperation::new(
            &self.preflight_graph,
            PREFLIGHT_READBACK_PASS,
            "candidate_counts",
            &candidate_counts,
            0,
            "candidate_counts_readback",
            &readback,
            0,
            12,
        )?;
        copy.record(encoder);
        Ok(RecordedModuleRecordCapacity {
            candidate_counts,
            readback,
        })
    }

    /// Finishes the three-word compact-capacity readback.
    pub fn finish_module_record_capacity_preflight(
        &self,
        device: &wgpu::Device,
        recorded: &RecordedModuleRecordCapacity,
    ) -> Result<TypeCheckPreflightCapacities> {
        let _keep_gpu_output_alive = &recorded.candidate_counts;
        let slice = recorded.readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            device,
            &slice,
            "type_check.preflight_capacities",
        )?;
        let mapped = slice.get_mapped_range();
        let [module_records, call_param_rows, call_arg_rows] =
            crate::gpu::readback::read_u32_words::<3>(&mapped, "type_check.preflight_capacities")?;
        drop(mapped);
        recorded.readback.unmap();
        Ok(TypeCheckPreflightCapacities {
            module_records: module_records.max(1),
            call_param_rows: call_param_rows.max(1),
            call_arg_rows: call_arg_rows.max(1),
        })
    }
}
