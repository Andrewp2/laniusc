//! Resident semantic-LIR to scheduled x86 virtual-instruction lowering.

use anyhow::{Context, Result};
use encase::ShaderType;

#[cfg(test)]
use super::lowering_ir::{X86LirCore, X86LirLocations, X86LirOperands};
use super::{
    functions::GpuTargetFunctionTable,
    lowering_ir::{LoweringCapacities, SEMANTIC_LIR_PAGE_ROWS, TARGET_LIR_PAGE_ROWS},
    optimization::{GpuOptIrView, lowering_allocations_with_opt},
    scan::{GpuResidentExclusiveScan, GraphScanContract},
    target_pages::GpuTargetPagePlanner,
    x86_artifact::GpuX86ArtifactStage,
    x86_object_artifact::GpuX86ObjectStage,
};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{CompilerGraph, CompilerGraphWorkspace},
    kernels::KernelRegistry,
    operations::ComputeOperation,
    passes_core::PassData,
    resource_registry::ResourceMap,
    timer::GpuTimer,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct CountParams {
    semantic_capacity: u32,
    semantic_start: u32,
    page_capacity: u32,
    reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct TargetPageParams {
    semantic_capacity: u32,
    target_capacity: u32,
    target_start: u32,
    page_capacity: u32,
    token_capacity: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct DeclSlotParams {
    token_capacity: u32,
    parameter_capacity: u32,
    local_capacity: u32,
    function_capacity: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct X86AnalysisParams {
    semantic_capacity: u32,
    call_arg_capacity: u32,
    aggregate_capacity: u32,
    function_capacity: u32,
    token_capacity: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
}

#[cfg(test)]
pub(crate) struct GpuX86LirView<'a> {
    pub total: &'a LaniusBuffer<u32>,
    pub core: &'a LaniusBuffer<X86LirCore>,
    pub operands: &'a LaniusBuffer<X86LirOperands>,
    pub locations: &'a LaniusBuffer<X86LirLocations>,
}

/// Produces the uniform x86 virtual records consumed by register allocation
/// and instruction selection. `record` performs no setup or allocation.
pub(crate) struct GpuX86LirStage {
    count_pages: Vec<ComputeOperation>,
    pages: Vec<X86LirPage>,
    decl_slots_scatter: ComputeOperation,
    frame_finalize: ComputeOperation,
    analysis_clear: ComputeOperation,
    analysis_index: ComputeOperation,
    optimize_init: ComputeOperation,
    optimize_seed: ComputeOperation,
    optimize_close: ComputeOperation,
    if_convert: ComputeOperation,
    allocation_words: ComputeOperation,
    stack_scan: GpuResidentExclusiveScan,
    allocation_locations: ComputeOperation,
    allocation_functions: ComputeOperation,
    inline_analyze: ComputeOperation,
    count_scan: GpuResidentExclusiveScan,
    target_pages: GpuTargetPagePlanner,
    functions: GpuTargetFunctionTable,
    _count_params: Vec<LaniusBuffer<CountParams>>,
    _decl_slot_params: LaniusBuffer<DeclSlotParams>,
    _analysis_params: LaniusBuffer<X86AnalysisParams>,
    _allocation_params: LaniusBuffer<X86AnalysisParams>,
    _stack_words: LaniusBuffer<u32>,
    _stack_prefix: LaniusBuffer<u32>,
    _stack_total: LaniusBuffer<u32>,
    _counts: LaniusBuffer<u32>,
    _offsets: LaniusBuffer<u32>,
    #[cfg(test)]
    total: LaniusBuffer<u32>,
    #[cfg(test)]
    core: LaniusBuffer<X86LirCore>,
    #[cfg(test)]
    operands: LaniusBuffer<X86LirOperands>,
    #[cfg(test)]
    locations: LaniusBuffer<X86LirLocations>,
    #[cfg(test)]
    decl_location_by_token: LaniusBuffer<u32>,
    #[cfg(test)]
    saved_gpr_mask_by_function: LaniusBuffer<u32>,
    artifact: GpuX86ArtifactStage,
    object: Option<GpuX86ObjectStage>,
}

struct X86LirPage {
    _params: LaniusBuffer<TargetPageParams>,
    scatter: ComputeOperation,
    locations: ComputeOperation,
    resolve: ComputeOperation,
    replay_scatter: ComputeOperation,
    replay_locations: ComputeOperation,
    replay_resolve: ComputeOperation,
    validate: ComputeOperation,
}

impl X86LirPage {
    fn record(&self, encoder: &mut wgpu::CommandEncoder, validate: bool) -> Result<()> {
        if validate {
            self.scatter.record(encoder)?;
            self.locations.record(encoder)?;
            self.resolve.record(encoder)?;
            self.validate.record(encoder)?;
        } else {
            self.replay_scatter.record(encoder)?;
            self.replay_locations.record(encoder)?;
            self.replay_resolve.record(encoder)?;
        }
        Ok(())
    }
}

impl GpuX86LirStage {
    pub(crate) fn new(
        device: &wgpu::Device,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        capacities: LoweringCapacities,
        opt: GpuOptIrView<'_>,
        include_object: bool,
        kernels: &KernelRegistry,
    ) -> Result<Self> {
        let metadata = opt.metadata;
        let allocations = lowering_allocations_with_opt(graph, workspace, opt)?;
        let resource = |name: &str| {
            graph
                .resource_id(name)
                .with_context(|| format!("x86 lowering graph is missing {name}"))
        };
        let alias_u32 = |name: &str, rows: u32| -> Result<LaniusBuffer<u32>> {
            workspace
                .alias(graph, resource(name)?, rows.max(1) as usize)
                .map_err(anyhow::Error::msg)
        };
        let semantic_capacity = capacities.semantic_instructions.max(1);
        let target_capacity = capacities.target_instructions.max(1);
        let target_page_rows = target_capacity.min(TARGET_LIR_PAGE_ROWS);
        let _semantic_order = metadata
            .execution_order
            .context("x86 lowering requires GPU-scheduled semantic LIR")?;
        let counts = alias_u32("lir.x86.count_by_semantic", semantic_capacity)?;
        let offsets = alias_u32("lir.x86.offset_by_semantic", semantic_capacity)?;
        let total = alias_u32("lir.x86.total", 1)?;
        let stack_words = alias_u32("lir.x86.stack_words_by_position", semantic_capacity)?;
        let stack_prefix = alias_u32("lir.x86.stack_prefix_by_position", semantic_capacity)?;
        let stack_total = alias_u32("lir.x86.stack_word_total", 1)?;
        let core = workspace
            .alias(graph, resource("lir.x86.core")?, target_page_rows as usize)
            .map_err(anyhow::Error::msg)?;
        let operands = workspace
            .alias(
                graph,
                resource("lir.x86.operands")?,
                target_page_rows as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let locations = workspace
            .alias(
                graph,
                resource("lir.x86.locations")?,
                target_page_rows as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let semantic_origins = alias_u32("lir.x86.semantic_origins", target_page_rows)?;
        let decl_location_by_token = alias_u32(
            "lir.x86.decl_location_by_token",
            capacities.declaration_capacity(),
        )?;
        let saved_gpr_mask_by_function = alias_u32(
            "lir.x86.saved_gpr_mask_by_function",
            capacities.hir_nodes.max(1),
        )?;
        #[cfg(not(test))]
        let _test_only_views = (&decl_location_by_token, &saved_gpr_mask_by_function);

        let count_pass = load(kernels, "lir.x86.count", "codegen/lir/x86/count")?;
        let scatter_pass = load(kernels, "lir.x86.scatter", "codegen/lir/x86/scatter")?;
        let resolve_pass = load(kernels, "lir.x86.resolve", "codegen/lir/x86/resolve")?;
        let validate_pass = load(kernels, "lir.x86.validate", "codegen/lir/x86/validate")?;
        let locations_pass = load(kernels, "lir.x86.locations", "codegen/lir/x86/locations")?;
        let analysis_clear_pass = load(
            kernels,
            "lir.x86.analysis.clear",
            "codegen/lir/x86/analysis_clear",
        )?;
        let analysis_index_pass = load(
            kernels,
            "lir.x86.analysis.index",
            "codegen/lir/x86/analysis_index",
        )?;
        let optimize_init_pass = load(
            kernels,
            "lir.x86.optimize.init",
            "codegen/lir/x86/optimize_init",
        )?;
        let optimize_seed_pass = load(
            kernels,
            "lir.x86.optimize.seed",
            "codegen/lir/x86/optimize_seed",
        )?;
        let optimize_close_pass = load(
            kernels,
            "lir.x86.optimize.close",
            "codegen/lir/x86/optimize_close",
        )?;
        let if_convert_pass = load(kernels, "lir.x86.if_convert", "codegen/lir/x86/if_convert")?;
        let allocation_words_pass = load(
            kernels,
            "lir.x86.allocation.words",
            "codegen/lir/x86/allocation_words",
        )?;
        let allocation_locations_pass = load(
            kernels,
            "lir.x86.allocation.locations",
            "codegen/lir/x86/allocation_locations",
        )?;
        let allocation_functions_pass = load(
            kernels,
            "lir.x86.allocation.functions",
            "codegen/lir/x86/allocation_functions",
        )?;
        let inline_analyze_pass = load(
            kernels,
            "lir.x86.inline.analyze",
            "codegen/lir/x86/inline_analyze",
        )?;
        let decl_slots_scatter_pass = load(
            kernels,
            "lir.x86.decl_slots.scatter",
            "codegen/lir/x86/decl_slots_scatter",
        )?;
        let frame_finalize_pass = load(
            kernels,
            "lir.x86.frame.finalize",
            "codegen/lir/x86/frame_finalize",
        )?;
        let decl_slot_params = uniform_from_val(
            device,
            "lir.x86.decl_slots.params",
            &DeclSlotParams {
                token_capacity: capacities.declaration_capacity(),
                parameter_capacity: capacities.parameters.max(1),
                local_capacity: capacities.local_capacity(),
                function_capacity: capacities.hir_nodes.max(1),
            },
        );
        let analysis_params = uniform_from_val(
            device,
            "lir.x86.analysis.params",
            &X86AnalysisParams {
                semantic_capacity,
                call_arg_capacity: capacities.call_arguments.max(1),
                aggregate_capacity: capacities.aggregate_elements.max(1),
                function_capacity: capacities.hir_nodes.max(1),
                token_capacity: capacities.declaration_capacity(),
                reserved0: 0,
                reserved1: LoweringCapacities::OPTIMIZATION_SSA_WORKER_COUNT,
                reserved2: u32::from(include_object),
            },
        );
        let allocation_params = uniform_from_val(
            device,
            "lir.x86.allocation.params",
            &X86AnalysisParams {
                semantic_capacity,
                call_arg_capacity: capacities.call_arguments.max(1),
                aggregate_capacity: capacities.aggregate_elements.max(1),
                function_capacity: capacities.hir_nodes.max(1),
                token_capacity: capacities.declaration_capacity(),
                reserved0: 1,
                reserved1: 0,
                reserved2: 0,
            },
        );
        let graph_bindings = workspace.bindings(graph).map_err(anyhow::Error::msg)?;
        let mut resources = ResourceMap::new();
        resources.register_graph_bindings(graph, &graph_bindings);
        opt.register(graph, &mut resources)?;
        let context = (graph, &allocations);
        let count_params = (0..semantic_capacity.div_ceil(SEMANTIC_LIR_PAGE_ROWS))
            .map(|page_id| {
                let semantic_start = page_id * SEMANTIC_LIR_PAGE_ROWS;
                uniform_from_val(
                    device,
                    &format!("lir.x86.count.page.{page_id}.params"),
                    &CountParams {
                        semantic_capacity,
                        semantic_start,
                        page_capacity: semantic_capacity
                            .saturating_sub(semantic_start)
                            .min(SEMANTIC_LIR_PAGE_ROWS),
                        reserved: 0,
                    },
                )
            })
            .collect::<Vec<_>>();
        let count_pages = count_params
            .iter()
            .enumerate()
            .map(|(page_id, params)| {
                let semantic_start = page_id as u32 * SEMANTIC_LIR_PAGE_ROWS;
                let page_capacity = semantic_capacity
                    .saturating_sub(semantic_start)
                    .min(SEMANTIC_LIR_PAGE_ROWS);
                ComputeOperation::direct_with_uniform(
                    device,
                    &context,
                    &resources,
                    "lir.x86.count",
                    &count_pass,
                    params,
                    page_capacity,
                )
            })
            .collect::<Result<Vec<_>>>()
            .context("construct x86 instruction-count operations")?;
        let count_scan = GpuResidentExclusiveScan::new(
            device,
            kernels,
            graph,
            workspace,
            &allocations,
            GraphScanContract {
                local_pass: "lir.target.count_scan.local",
                up_pass: "lir.target.count_scan.hierarchy_up",
                down_pass: "lir.target.count_scan.hierarchy_down",
                apply_pass: "lir.target.count_scan.apply",
                count: "lir.opt.total",
                input: "lir.x86.count_by_semantic",
                local: "lir.target.count_scan_local",
                block_sum: "lir.target.count_scan_block_sum",
                block_prefix: "lir.target.count_scan_block_prefix",
                hierarchy: "lir.target.count_scan_hierarchy",
                output: "lir.x86.offset_by_semantic",
                total: "lir.x86.total",
            },
            semantic_capacity,
            opt.count,
            &counts,
            &offsets,
            &total,
        )
        .context("construct x86 instruction-count scan")?;
        let target_pages = GpuTargetPagePlanner::new(
            device,
            kernels,
            graph,
            workspace,
            &allocations,
            &resources,
            capacities,
        )
        .context("construct x86 target-page planner")?;
        let pages = (0..target_capacity.div_ceil(TARGET_LIR_PAGE_ROWS))
            .map(|page_id| {
                let target_start = page_id * TARGET_LIR_PAGE_ROWS;
                let page_capacity = target_capacity
                    .saturating_sub(target_start)
                    .min(TARGET_LIR_PAGE_ROWS);
                let params = uniform_from_val(
                    device,
                    &format!("lir.x86.page.{page_id}.params"),
                    &TargetPageParams {
                        semantic_capacity,
                        target_capacity,
                        target_start,
                        page_capacity,
                        token_capacity: capacities.declaration_capacity(),
                        reserved0: 0,
                        reserved1: 0,
                        reserved2: 0,
                    },
                );
                Ok(X86LirPage {
                    scatter: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.x86.scatter",
                        &scatter_pass,
                        &params,
                        page_capacity,
                    )?,
                    locations: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.x86.locations",
                        &locations_pass,
                        &params,
                        page_capacity,
                    )?,
                    resolve: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.x86.resolve",
                        &resolve_pass,
                        &params,
                        page_capacity,
                    )?,
                    replay_scatter: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.x86.scatter.replay",
                        &scatter_pass,
                        &params,
                        page_capacity,
                    )?,
                    replay_locations: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.x86.locations.replay",
                        &locations_pass,
                        &params,
                        page_capacity,
                    )?,
                    replay_resolve: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.x86.resolve.replay",
                        &resolve_pass,
                        &params,
                        page_capacity,
                    )?,
                    validate: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.x86.validate",
                        &validate_pass,
                        &params,
                        page_capacity,
                    )?,
                    _params: params,
                })
            })
            .collect::<Result<Vec<_>>>()
            .context("construct x86 target-page operations")?;
        let functions = GpuTargetFunctionTable::new(
            device,
            kernels,
            graph,
            workspace,
            &allocations,
            &resources,
            semantic_capacity,
            target_capacity,
            capacities.hir_nodes,
            opt.count,
        )
        .context("construct x86 target-function table")?;
        let decl_slots_scatter = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.decl_slots.scatter",
            &decl_slots_scatter_pass,
            &decl_slot_params,
            capacities
                .parameters
                .max(capacities.semantic_instructions)
                .max(1),
        )
        .context("construct x86 declaration-slot scatter")?;
        let frame_finalize = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.frame.finalize",
            &frame_finalize_pass,
            &decl_slot_params,
            capacities.hir_nodes.max(1),
        )
        .context("construct x86 frame finalization")?;
        let analysis_clear = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.analysis.clear",
            &analysis_clear_pass,
            &analysis_params,
            semantic_capacity
                .max(capacities.hir_nodes.max(1))
                .max(capacities.declaration_capacity()),
        )?;
        let analysis_index = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.analysis.index",
            &analysis_index_pass,
            &analysis_params,
            semantic_capacity,
        )?;
        let optimize_init = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.optimize.init",
            &optimize_init_pass,
            &analysis_params,
            semantic_capacity,
        )?;
        let optimize_seed = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.optimize.seed",
            &optimize_seed_pass,
            &analysis_params,
            semantic_capacity,
        )?;
        let optimize_close = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.optimize.close",
            &optimize_close_pass,
            &analysis_params,
            LoweringCapacities::OPTIMIZATION_SSA_WORKER_COUNT * 32,
        )?;
        let if_convert = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.if_convert",
            &if_convert_pass,
            &analysis_params,
            semantic_capacity,
        )?;
        let allocation_words = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.allocation.words",
            &allocation_words_pass,
            &allocation_params,
            semantic_capacity,
        )?;
        let stack_scan = GpuResidentExclusiveScan::new(
            device,
            kernels,
            graph,
            workspace,
            &allocations,
            GraphScanContract {
                local_pass: "lir.x86.stack_scan.local",
                up_pass: "lir.x86.stack_scan.hierarchy_up",
                down_pass: "lir.x86.stack_scan.hierarchy_down",
                apply_pass: "lir.x86.stack_scan.apply",
                count: "lir.opt.total",
                input: "lir.x86.stack_words_by_position",
                local: "lir.x86.stack_scan_local",
                block_sum: "lir.x86.stack_scan_block_sum",
                block_prefix: "lir.x86.stack_scan_block_prefix",
                hierarchy: "lir.x86.stack_scan_hierarchy",
                output: "lir.x86.stack_prefix_by_position",
                total: "lir.x86.stack_word_total",
            },
            semantic_capacity,
            opt.count,
            &stack_words,
            &stack_prefix,
            &stack_total,
        )
        .context("construct parallel x86 spill-layout scan")?;
        let allocation_locations = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.allocation.locations",
            &allocation_locations_pass,
            &allocation_params,
            semantic_capacity,
        )?;
        let allocation_functions = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.allocation.functions",
            &allocation_functions_pass,
            &allocation_params,
            capacities.hir_nodes.max(1),
        )?;
        let inline_analyze = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.inline.analyze",
            &inline_analyze_pass,
            &analysis_params,
            capacities.hir_nodes.max(1),
        )?;
        let artifact = GpuX86ArtifactStage::new(
            device,
            kernels,
            graph,
            workspace,
            &allocations,
            capacities,
            metadata,
            &total,
            &core,
            &operands,
            &locations,
            &semantic_origins,
        )
        .context("construct x86 artifact stage")?;
        let object = include_object
            .then(|| {
                GpuX86ObjectStage::new(
                    device,
                    kernels,
                    graph,
                    workspace,
                    &allocations,
                    capacities,
                    opt,
                    artifact.object_view(),
                )
            })
            .transpose()
            .context("construct x86 object stage")?;
        Ok(Self {
            count_pages,
            pages,
            decl_slots_scatter,
            frame_finalize,
            analysis_clear,
            analysis_index,
            optimize_init,
            optimize_seed,
            optimize_close,
            if_convert,
            allocation_words,
            stack_scan,
            allocation_locations,
            allocation_functions,
            inline_analyze,
            count_scan,
            target_pages,
            functions,
            _count_params: count_params,
            _decl_slot_params: decl_slot_params,
            _analysis_params: analysis_params,
            _allocation_params: allocation_params,
            _stack_words: stack_words,
            _stack_prefix: stack_prefix,
            _stack_total: stack_total,
            _counts: counts,
            _offsets: offsets,
            #[cfg(test)]
            total,
            #[cfg(test)]
            core,
            #[cfg(test)]
            operands,
            #[cfg(test)]
            locations,
            #[cfg(test)]
            decl_location_by_token,
            #[cfg(test)]
            saved_gpr_mask_by_function,
            artifact,
            object,
        })
    }

    #[cfg(test)]
    pub(crate) fn output(&self) -> GpuX86LirView<'_> {
        GpuX86LirView {
            total: &self.total,
            core: &self.core,
            operands: &self.operands,
            locations: &self.locations,
        }
    }

    pub(crate) fn record_count_page(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        page_id: usize,
        timer: &mut Option<&mut GpuTimer>,
    ) -> Result<()> {
        if page_id == 0 {
            self.analysis_clear.record(encoder)?;
            stamp(timer, encoder, "codegen.x86.analysis.clear.done");
            self.analysis_index.record(encoder)?;
            stamp(timer, encoder, "codegen.x86.analysis.index.done");
            self.optimize_init.record(encoder)?;
            self.optimize_seed.record(encoder)?;
            self.optimize_close.record(encoder)?;
            stamp(timer, encoder, "codegen.x86.optimize.parallel.done");
            self.if_convert.record(encoder)?;
            stamp(timer, encoder, "codegen.x86.if_convert.done");
            self.allocation_words.record(encoder)?;
            self.stack_scan.record(encoder)?;
            self.allocation_locations.record(encoder)?;
            self.allocation_functions.record(encoder)?;
            stamp(timer, encoder, "codegen.x86.allocation.parallel.done");
            self.decl_slots_scatter.record(encoder)?;
            stamp(timer, encoder, "codegen.x86.decl_slots.done");
            self.inline_analyze.record(encoder)?;
            stamp(timer, encoder, "codegen.x86.inline.analyze.done");
        }
        self.count_pages
            .get(page_id)
            .context("x86 semantic count page is outside the configured unit capacity")?
            .record(encoder)
    }

    pub(crate) fn count_page_count(&self) -> usize {
        self.count_pages.len()
    }

    pub(crate) fn target_page_count(&self) -> usize {
        self.pages.len()
    }

    pub(crate) fn record_before_target_pages(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.record_after_counts_prefix(encoder)
    }

    pub(crate) fn record_measure_page(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        page_id: usize,
    ) -> Result<()> {
        self.pages[page_id].record(encoder, true)?;
        self.artifact.record_byte_count(encoder, page_id)
    }

    pub(crate) fn record_between_target_pages(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        object: bool,
    ) -> Result<()> {
        self.artifact.record_layout_after_byte_counts(encoder)?;
        if object {
            self.object
                .as_ref()
                .context("x86 object projection was not allocated for this lowering job")?
                .record_status_normalization(encoder)?;
        }
        self.artifact.record_clear(encoder)?;
        Ok(())
    }

    pub(crate) fn record_emit_page(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        page_id: usize,
    ) -> Result<()> {
        self.pages[page_id].record(encoder, false)?;
        self.artifact.record_emit(encoder, page_id)
    }

    pub(crate) fn record_after_target_pages(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        object: bool,
    ) -> Result<()> {
        self.artifact
            .record_extra_emits(encoder, self.pages.len())?;
        if object {
            self.object
                .as_ref()
                .context("x86 object projection was not allocated for this lowering job")?
                .record_projection(encoder)
        } else {
            self.artifact.record_length_readback(encoder)
        }
    }

    pub(crate) fn set_object_identity(
        &self,
        queue: &wgpu::Queue,
        library_id: u32,
        unit_id: u32,
    ) -> Result<()> {
        self.object
            .as_ref()
            .context("x86 object projection was not allocated for this lowering job")?
            .set_identity(queue, library_id, unit_id);
        Ok(())
    }

    #[cfg(test)]
    fn record_counts(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        let mut timer = None;
        for page_id in 0..self.count_pages.len() {
            self.record_count_page(encoder, page_id, &mut timer)?;
        }
        Ok(())
    }

    fn record_after_counts_prefix(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.count_scan.record(encoder)?;
        self.target_pages.record(encoder)?;
        self.functions.record(encoder)?;
        self.frame_finalize.record(encoder)
    }

    #[cfg(test)]
    fn record_lir(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.record_counts(encoder)?;
        self.record_after_counts_prefix(encoder)?;
        for page in &self.pages {
            page.record(encoder, true)?;
        }
        Ok(())
    }

    pub(crate) fn finish_artifact(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
    ) -> Result<Vec<u8>> {
        self.artifact.finish(device, queue)
    }

    pub(crate) fn finish_object(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        library_id: u32,
        unit_id: u32,
    ) -> Result<super::x86::GpuX86RelocatableObject> {
        self.object
            .as_ref()
            .context("x86 object projection was not allocated for this lowering job")?
            .finish(device, queue, library_id, unit_id)
    }
}

fn stamp(timer: &mut Option<&mut GpuTimer>, encoder: &mut wgpu::CommandEncoder, label: &str) {
    if let Some(timer) = timer.as_deref_mut() {
        timer.stamp(encoder, label);
    }
}

fn load(kernels: &KernelRegistry, _label: &str, shader: &str) -> Result<PassData> {
    Ok(kernels.kernel(shader).clone())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        codegen::{
            lowering::GpuSemanticLirView,
            lowering_ir::{
                LoweringStatus,
                LoweringTarget,
                SemanticLirAggregateElement,
                SemanticLirCallArg,
                SemanticLirCore,
                SemanticLirFunction,
                SemanticLirLocal,
                SemanticLirOperands,
                SemanticLirParam,
                SemanticLirString,
                lowering_compiler_graph,
                opcode,
            },
            optimization::GpuOptimizationStage,
        },
        gpu::{
            buffers::{
                readback_bytes,
                storage_ro_from_bytes,
                storage_ro_from_u32s,
                tracked_buffer_allocation_stats,
            },
            device,
            passes_core::{map_readback_blocking, pipeline_creation_count},
        },
    };

    fn record_bytes<const N: usize>(records: &[[u32; N]]) -> Vec<u8> {
        records
            .iter()
            .flat_map(|record| record.iter())
            .flat_map(|word| word.to_le_bytes())
            .collect()
    }

    fn compact_semantic_core_records(records: &[[u32; 8]]) -> Vec<[u32; 4]> {
        records
            .iter()
            .map(|record| {
                let [
                    op,
                    type_id,
                    type_ref_tag,
                    type_ref_payload,
                    _,
                    flags,
                    words,
                    _,
                ] = *record;
                [
                    type_id,
                    type_ref_payload,
                    flags | ((op & 0x3f) << 24) | ((type_ref_tag & 3) << 30),
                    words,
                ]
            })
            .collect()
    }

    fn read_words(device: &wgpu::Device, buffer: &LaniusBuffer<u8>) -> Vec<u32> {
        let slice = buffer.slice(..);
        map_readback_blocking(device, &slice, "x86 LIR readback").unwrap();
        let mapped = slice.get_mapped_range();
        let words = mapped
            .chunks_exact(4)
            .map(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()))
            .collect();
        drop(mapped);
        buffer.unmap();
        words
    }

    #[test]
    fn physical_gpu_runs_resident_semantic_to_scheduled_x86_lir() {
        let gpu = device::global();
        let capacities = LoweringCapacities {
            source_bytes: 8,
            tokens: 8,
            hir_nodes: 8,
            semantic_instructions: 9,
            call_arguments: 2,
            parameters: 2,
            aggregate_elements: 2,
            target_instructions: 10,
            artifact_bytes: 64,
        };
        let graph = lowering_compiler_graph(capacities, LoweringTarget::X86_64).unwrap();
        let workspace = CompilerGraphWorkspace::new(&gpu.device, "test.x86_lir", &graph).unwrap();
        let status: LaniusBuffer<LoweringStatus> = workspace
            .alias(&graph, graph.resource_id("lowering.status").unwrap(), 1)
            .unwrap();
        let total = storage_ro_from_u32s(&gpu.device, "test.x86_lir.total", &[8]);
        let page_core: LaniusBuffer<SemanticLirCore> = workspace
            .alias(
                &graph,
                graph.resource_id("lir.semantic.core").unwrap(),
                capacities.semantic_instructions as usize,
            )
            .unwrap();
        page_core.write(
            &gpu.queue,
            0,
            &record_bytes(&compact_semantic_core_records(&[
                [
                    opcode::SEMANTIC_LIR_OP_CONST_I32,
                    3,
                    0,
                    u32::MAX,
                    1,
                    0,
                    0,
                    u32::MAX,
                ],
                [
                    opcode::SEMANTIC_LIR_OP_CONST_I32,
                    3,
                    0,
                    u32::MAX,
                    0,
                    0,
                    0,
                    u32::MAX,
                ],
                [
                    opcode::SEMANTIC_LIR_OP_ADD,
                    3,
                    0,
                    u32::MAX,
                    2,
                    0,
                    0,
                    u32::MAX,
                ],
                [
                    opcode::SEMANTIC_LIR_OP_RETURN,
                    0,
                    0,
                    u32::MAX,
                    3,
                    0,
                    0,
                    u32::MAX,
                ],
                [
                    opcode::SEMANTIC_LIR_OP_BRANCH,
                    0,
                    0,
                    u32::MAX,
                    5,
                    0,
                    0,
                    u32::MAX,
                ],
                [
                    opcode::SEMANTIC_LIR_OP_BLOCK_BEGIN,
                    0,
                    0,
                    u32::MAX,
                    6,
                    0,
                    0,
                    u32::MAX,
                ],
                [
                    opcode::SEMANTIC_LIR_OP_CALL,
                    3,
                    0,
                    u32::MAX,
                    4,
                    0,
                    0,
                    u32::MAX,
                ],
                [
                    opcode::SEMANTIC_LIR_OP_CALL_SYMBOL,
                    3,
                    0,
                    u32::MAX,
                    7,
                    0,
                    0,
                    u32::MAX,
                ],
                [
                    opcode::SEMANTIC_LIR_OP_CONST_I32,
                    3,
                    0,
                    u32::MAX,
                    8,
                    0,
                    0,
                    u32::MAX,
                ],
            ])),
        );
        let page_operands: LaniusBuffer<SemanticLirOperands> = workspace
            .alias(
                &graph,
                graph.resource_id("lir.semantic.operands").unwrap(),
                capacities.semantic_instructions as usize,
            )
            .unwrap();
        page_operands.write(
            &gpu.queue,
            0,
            &record_bytes(&[
                [1, 9, u32::MAX, u32::MAX],
                [0, 7, u32::MAX, u32::MAX],
                [2, 1, 0, u32::MAX],
                [3, 2, u32::MAX, u32::MAX],
                [5, 6, u32::MAX, u32::MAX],
                [6, u32::MAX, u32::MAX, u32::MAX],
                [4, 0, 0, 2],
                [7, 7, 11, 23],
                [8, 42, u32::MAX, u32::MAX],
            ]),
        );
        let semantic_order: LaniusBuffer<u32> = workspace
            .alias(
                &graph,
                graph.resource_id("lir.semantic.schedule_order").unwrap(),
                9,
            )
            .unwrap();
        semantic_order.write(
            &gpu.queue,
            0,
            &record_bytes(&[[1u32, 0, 2, 3, 5, 6, 4, 7, 8]]),
        );
        let semantic_layout_metadata =
            storage_ro_from_u32s(&gpu.device, "test.x86_lir.layout_metadata", &[0; 9]);
        let semantic_owners = storage_ro_from_u32s(
            &gpu.device,
            "test.x86_lir.semantic_owners",
            &[1, 0, 2, 3, 5, 6, 4, 7, 7],
        );
        let semantic_function_ids =
            storage_ro_from_u32s(&gpu.device, "test.x86_lir.function_ids", &[0; 8]);
        let call_args = storage_ro_from_bytes::<SemanticLirCallArg>(
            &gpu.device,
            "test.x86_lir.call_args",
            &record_bytes(&[[6, 0, 0, 0], [6, 2, 1, 0]]),
            2,
        );
        let call_arg_total: LaniusBuffer<u32> = workspace
            .alias(
                &graph,
                graph.resource_id("lir.semantic.call_arg_total").unwrap(),
                1,
            )
            .unwrap();
        call_arg_total.write(&gpu.queue, 0, &2u32.to_le_bytes());
        let call_arg_start_by_hir = storage_ro_from_u32s(
            &gpu.device,
            "test.x86_lir.call_arg_start_by_hir",
            &[
                u32::MAX,
                u32::MAX,
                u32::MAX,
                u32::MAX,
                0,
                u32::MAX,
                u32::MAX,
                u32::MAX,
            ],
        );
        let call_arg_count_by_hir = storage_ro_from_u32s(
            &gpu.device,
            "test.x86_lir.call_arg_count_by_hir",
            &[0, 0, 0, 0, 2, 0, 0, 0],
        );
        let aggregate_elements = storage_ro_from_bytes::<SemanticLirAggregateElement>(
            &gpu.device,
            "test.x86_lir.aggregate_elements",
            &record_bytes(&[[u32::MAX; 7]; 4]),
            4,
        );
        let string_rows = storage_ro_from_bytes::<SemanticLirString>(
            &gpu.device,
            "test.x86_lir.strings",
            &record_bytes(&[[u32::MAX; 4]; 8]),
            8,
        );
        let empty_count = storage_ro_from_u32s(&gpu.device, "test.x86_lir.empty_count", &[0]);
        let string_data = storage_ro_from_u32s(&gpu.device, "test.x86_lir.string_data", &[0; 2]);
        let functions = storage_ro_from_bytes::<SemanticLirFunction>(
            &gpu.device,
            "test.x86_lir.functions",
            &record_bytes(&[
                [0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, u32::MAX],
                [u32::MAX; 13],
                [u32::MAX; 13],
                [u32::MAX; 13],
                [u32::MAX; 13],
                [u32::MAX; 13],
                [u32::MAX; 13],
                [u32::MAX; 13],
            ]),
            8,
        );
        let params = storage_ro_from_bytes::<SemanticLirParam>(
            &gpu.device,
            "test.x86_lir.params",
            &record_bytes(&[[0, 3, 0, 3], [u32::MAX; 4]]),
            2,
        );
        let locals = storage_ro_from_bytes::<SemanticLirLocal>(
            &gpu.device,
            "test.x86_lir.locals",
            &record_bytes(&[
                [0, 4, 0, 3],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
            ]),
            24,
        );
        let function_count = storage_ro_from_u32s(&gpu.device, "test.x86_lir.fn_count", &[1]);
        let param_count = storage_ro_from_u32s(&gpu.device, "test.x86_lir.param_count", &[1]);
        let local_count = storage_ro_from_u32s(&gpu.device, "test.x86_lir.local_count", &[1]);
        let kernels = KernelRegistry::prepare_prefixes(
            &gpu.device,
            crate::codegen::lowering::LOWERING_KERNEL_PREFIXES,
            |_| true,
        )
        .unwrap();
        let semantic = GpuSemanticLirView {
            count: &total,
            core: &page_core,
            operands: &page_operands,
            layout_word_offset: &semantic_layout_metadata,
            owner_by_instruction: &semantic_owners,
            function_id_by_hir: &semantic_function_ids,
            call_args: &call_args,
            call_arg_count: &empty_count,
            call_arg_start_by_hir: &call_arg_start_by_hir,
            call_arg_count_by_hir: &call_arg_count_by_hir,
            aggregate_elements: &aggregate_elements,
            aggregate_element_count: &empty_count,
            strings: &string_rows,
            string_count: &empty_count,
            string_data_words: &string_data,
            string_pool_len: &empty_count,
            functions: &functions,
            function_count: &function_count,
            params: &params,
            param_count: &param_count,
            locals: &locals,
            local_count: &local_count,
            execution_order: Some(&semantic_order),
            status: &status,
        };
        let optimizer = GpuOptimizationStage::new(
            &gpu.device,
            &graph,
            &workspace,
            capacities,
            semantic,
            &kernels,
        )
        .unwrap();
        let stage = GpuX86LirStage::new(
            &gpu.device,
            &graph,
            &workspace,
            capacities,
            optimizer.output(semantic),
            true,
            &kernels,
        )
        .unwrap();
        let pipelines_before = pipeline_creation_count();
        let buffers_before = tracked_buffer_allocation_stats();
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.x86_lir.encoder"),
            });
        optimizer.record(&mut encoder, None).unwrap();
        stage.record_lir(&mut encoder).unwrap();
        assert_eq!(pipeline_creation_count(), pipelines_before);
        assert_eq!(tracked_buffer_allocation_stats(), buffers_before);

        let output = stage.output();
        let functions = stage.functions.output();
        let total_rb = readback_bytes(&gpu.device, "test.x86_lir.total.rb", 4, 1);
        let core_rb = readback_bytes(&gpu.device, "test.x86_lir.core.rb", 160, 40);
        let operands_rb = readback_bytes(&gpu.device, "test.x86_lir.operands.rb", 160, 40);
        let locations_rb = readback_bytes(&gpu.device, "test.x86_lir.locations.rb", 160, 40);
        let function_count_rb = readback_bytes(&gpu.device, "test.x86_lir.function_count.rb", 4, 1);
        let functions_rb = readback_bytes(&gpu.device, "test.x86_lir.functions.rb", 64, 16);
        let status_bytes = std::mem::size_of::<super::super::lowering_ir::LoweringStatus>();
        let status_rb = readback_bytes(
            &gpu.device,
            "test.x86_lir.status.rb",
            status_bytes,
            status_bytes,
        );
        let frame_slots_rb = readback_bytes(&gpu.device, "test.x86_lir.frame_slots.rb", 32, 8);
        let saved_mask_rb = readback_bytes(&gpu.device, "test.x86_lir.saved_mask.rb", 4, 1);
        output.total.copy_to(&mut encoder, 0, &total_rb, 0, 4);
        output.core.copy_to(&mut encoder, 0, &core_rb, 0, 160);
        output
            .operands
            .copy_to(&mut encoder, 0, &operands_rb, 0, 160);
        output
            .locations
            .copy_to(&mut encoder, 0, &locations_rb, 0, 160);
        functions
            .count
            .copy_to(&mut encoder, 0, &function_count_rb, 0, 4);
        functions
            .rows
            .copy_to(&mut encoder, 0, &functions_rb, 0, 64);
        status.copy_to(&mut encoder, 0, &status_rb, 0, status_bytes as u64);
        stage
            .decl_location_by_token
            .copy_to(&mut encoder, 0, &frame_slots_rb, 0, 32);
        stage
            .saved_gpr_mask_by_function
            .copy_to(&mut encoder, 0, &saved_mask_rb, 0, 4);
        gpu.queue.submit(Some(encoder.finish()));

        assert_eq!(read_words(&gpu.device, &total_rb)[0], 9);
        let core_words = read_words(&gpu.device, &core_rb);
        assert_eq!(
            [
                core_words[2],
                core_words[6],
                core_words[10],
                core_words[14],
                core_words[18],
                core_words[22],
                core_words[26],
                core_words[30],
                core_words[34],
            ],
            [
                opcode::X86_LIR_OP_IMM_I32,
                opcode::X86_LIR_OP_IMM_I32,
                opcode::X86_LIR_OP_RETURN,
                opcode::X86_LIR_OP_LABEL,
                opcode::X86_LIR_OP_CALL_ARG,
                opcode::X86_LIR_OP_CALL_ARG,
                opcode::X86_LIR_OP_CALL,
                opcode::X86_LIR_OP_BRANCH,
                opcode::X86_LIR_OP_CALL_SYMBOL,
            ]
        );
        let operand_words = read_words(&gpu.device, &operands_rb);
        // The first constant remains live as a later call argument. The
        // constant-only `7 + 9` expression becomes one target immediate and
        // its otherwise-unused `7` producer disappears.
        assert_eq!([operand_words[0], operand_words[4]], [9, 16]);
        let location_words = read_words(&gpu.device, &locations_rb);
        // Both surviving values are consumed before the call and remain in
        // caller-saved registers. Folded immediates have no input locations.
        assert_eq!(location_words[0], opcode::X86_LOCATION_REGISTER | 8);
        assert_eq!(location_words[4], opcode::X86_LOCATION_REGISTER | 9);
        assert_eq!(
            &location_words[4..8],
            &[
                opcode::X86_LOCATION_REGISTER | 9,
                u32::MAX,
                u32::MAX,
                u32::MAX,
            ]
        );
        assert_eq!(read_words(&gpu.device, &function_count_rb)[0], 1);
        assert_eq!(&operand_words[28..32], &[u32::MAX, 6, 0, 0]);
        assert_eq!(&operand_words[32..35], &[7, 11, 23]);
        assert_eq!(&read_words(&gpu.device, &functions_rb)[..4], &[0, 0, 9, 2]);
        let frame_slots = read_words(&gpu.device, &frame_slots_rb);
        // The entrypoint parameter has a register home. Declaration 4 has no
        // live definition in this fixture, so dead-declaration filtering must
        // leave it unassigned rather than reserving a register or stack slot.
        assert_eq!(
            (frame_slots[3], frame_slots[4]),
            (opcode::X86_LOCATION_REGISTER | 7, u32::MAX)
        );
        assert_eq!(read_words(&gpu.device, &saved_mask_rb)[0], 0);
        let status_words = read_words(&gpu.device, &status_rb);
        // This fixture deliberately keeps one parameter on the entrypoint so
        // the LIR can exercise parameter/register placement. Artifact
        // validation must report that unsupported executable ABI after the
        // scheduled target rows have still been materialized.
        assert_eq!(
            status_words[0] & opcode::LOWERING_STATUS_UNSUPPORTED_TARGET,
            opcode::LOWERING_STATUS_UNSUPPORTED_TARGET,
        );
        assert_eq!(
            status_words[6],
            super::super::lowering_ir::LOWERING_DIAGNOSTIC_X86_ENTRYPOINT_PARAMETERS,
        );
        assert_ne!(status_words[1], u32::MAX, "diagnostic source HIR");
        assert_ne!(status_words[2], u32::MAX, "diagnostic semantic row");
        assert_eq!(
            status_words[2], status_words[3],
            "identity OptIR diagnostics must preserve semantic-to-OptIR row provenance"
        );
    }
}
