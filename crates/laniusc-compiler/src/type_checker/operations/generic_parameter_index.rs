use super::super::*;
use crate::gpu::compiler_graph::ReflectedComputeSpec;

pub(in crate::type_checker) const GENERIC_PARAM_LOOKUP_CLEAR: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.generic_params.lookup.clear",
        Declarations,
        "type_checker/type/instances/00b1_clear_generic_param_lookup"
    )
    .initializer();

pub(in crate::type_checker) const GENERIC_PARAM_LOOKUP_BUILD: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.generic_params.lookup.build",
        Declarations,
        "type_checker/type/instances/00b2_build_generic_param_lookup"
    )
    .with_indirect_dispatch("hir_active_dispatch_args");

pub(in crate::type_checker) const GENERIC_PARAM_ROWS_SCATTER: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.generic_params.rows.scatter",
        Declarations,
        "type_checker/type/instances/00d_scatter_generic_param_rows"
    )
    .with_modes(&[(
        "generic_type_param_rows",
        crate::gpu::compiler_graph::AccessMode::Write,
    )])
    .with_indirect_dispatch("hir_active_dispatch_args");

/// Exact name lookup and stable per-kind compaction for generic parameters.
///
/// This operation preserves the compact HIR's source ordering. It does not
/// impose an additional lexicographic ordering merely to support lookup or
/// slot assignment.
pub(in crate::type_checker) struct GenericParameterIndex {
    lookup: ExactLookupOperation,
    type_scan: PrefixScanOperation,
    const_scan: PrefixScanOperation,
    scatter_rows: ComputeOperation,
}

/// The exact graph-selected schedule for producing generic-parameter rows.
/// Workspaces built for sources without generic syntax retain only the compact
/// zero-count result instead of pretending that the full indexing pipeline ran.
pub(in crate::type_checker) enum GenericParameterRecordOperation {
    Present {
        mark: ComputeOperation,
        declarations: ComputeOperation,
        index: GenericParameterIndex,
        resolve_uses: ComputeOperation,
    },
    Empty(crate::gpu::operations::EmptyRelationsOperation),
}

impl GenericParameterRecordOperation {
    pub(in crate::type_checker) fn present(
        mark: ComputeOperation,
        declarations: ComputeOperation,
        index: GenericParameterIndex,
        resolve_uses: ComputeOperation,
    ) -> Self {
        Self::Present {
            mark,
            declarations,
            index,
            resolve_uses,
        }
    }

    pub(in crate::type_checker) fn empty(
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
    ) -> Result<Self> {
        Ok(Self::Empty(
            crate::gpu::operations::EmptyRelationsOperation::new(
                graph,
                resources,
                compiler_graph::GENERIC_PARAM_EMPTY_PASS,
                &[
                    "generic_param_count_out",
                    "generic_type_param_count_out",
                    "generic_const_param_count_out",
                ],
                &[
                    "generic_decl_owner_by_node",
                    "predicate_bound_list_by_node",
                    "generic_param_owner_token",
                    "generic_param_name_id",
                    "generic_param_token",
                    "generic_param_kind",
                    "generic_param_lookup_state",
                    "generic_type_param_flag",
                    "generic_const_param_flag",
                    "generic_type_param_prefix",
                    "generic_const_param_prefix",
                    "generic_type_param_rows",
                    "generic_type_param_scan_local_prefix",
                    "generic_const_param_scan_local_prefix",
                    "generic_type_param_scan_block_sum",
                    "generic_const_param_scan_block_sum",
                    "generic_type_param_scan_prefix_a",
                    "generic_const_param_scan_prefix_a",
                    "generic_type_param_scan_prefix_b",
                    "generic_const_param_scan_prefix_b",
                ],
            )?,
        ))
    }

    pub(in crate::type_checker) fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
    ) -> Result<()> {
        let Self::Present {
            mark,
            declarations,
            index,
            resolve_uses,
        } = self
        else {
            if let Self::Empty(clear) = self {
                clear.record(encoder);
            }
            return Ok(());
        };

        mark.record(encoder)?;
        stamp_typecheck_timer(
            &mut timer,
            encoder,
            "typecheck.type_instances.generic_params.mark.done",
        );
        declarations.record(encoder)?;
        stamp_typecheck_timer(
            &mut timer,
            encoder,
            "typecheck.type_instances.decl_generic_params.done",
        );
        index.record(encoder)?;
        stamp_typecheck_timer(
            &mut timer,
            encoder,
            "typecheck.type_instances.generic_params.index.done",
        );
        resolve_uses.record(encoder)?;
        stamp_typecheck_timer(
            &mut timer,
            encoder,
            "typecheck.type_instances.generic_param_use_slots.done",
        );
        Ok(())
    }
}

impl GenericParameterIndex {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        passes: &TypeCheckPasses,
        resources: &ResourceMap<'_>,
        token_capacity: u32,
    ) -> Result<Self> {
        let hir_dispatch = typed_buffer_from_resources(resources, "hir_active_dispatch_args")?;
        let (type_scan, const_scan) = PrefixScanOperation::from_pair_spec(
            device,
            passes,
            resources,
            compiler_graph::GENERIC_PARAM_SLOT_SCAN,
        )?;
        Ok(Self {
            lookup: ExactLookupOperation::new(
                device,
                graph,
                resources,
                passes,
                GENERIC_PARAM_LOOKUP_CLEAR,
                GENERIC_PARAM_LOOKUP_BUILD,
                token_capacity.saturating_mul(2).max(1),
                &hir_dispatch,
            )?,
            type_scan,
            const_scan,
            scatter_rows: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                passes,
                GENERIC_PARAM_ROWS_SCATTER,
                &hir_dispatch,
            )?,
        })
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.lookup.record(encoder)?;
        PrefixScanOperation::record_pair(&self.type_scan, &self.const_scan, encoder)?;
        self.scatter_rows.record(encoder)
    }
}
