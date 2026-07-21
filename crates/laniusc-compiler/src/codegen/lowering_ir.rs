//! GPU-resident lowering contracts between compact semantic HIR and targets.

use encase::ShaderType;

use crate::gpu::{
    compiler_graph::{
        CompilerGraph,
        CompilerGraphBuilder,
        CompilerPhase,
        PassAccess,
        PassDesc,
        ResourceClass,
        ResourceDesc,
        ResourceDomain,
        ResourceId,
    },
    workspace::WorkspaceUsageClass,
};

/// Constants generated from `shaders/codegen/lowering_ir.slang`.
pub mod opcode {
    include!(concat!(env!("OUT_DIR"), "/lowering_ir_opcodes.rs"));
}

/// Four 32-bit schedule-key words consumed two bits per stable radix step.
pub(crate) const TARGET_SCHEDULE_RADIX_STEPS: u32 = 16;

/// Number of target-independent instructions materialized in one resident
/// lowering window. The logical stream may contain any number of pages.
pub(crate) const SEMANTIC_LIR_PAGE_ROWS: u32 = 65_536;
/// Descriptor bindings are individually addressable with wgpu storage-buffer
/// offsets, which must satisfy the common 256-byte alignment requirement.
pub(crate) const SEMANTIC_LIR_PAGE_DESCRIPTOR_STRIDE: u32 = 256;

#[derive(Clone, Copy)]
struct WasmAbiGraphResources {
    param_widths: ResourceId,
    param_prefix: ResourceId,
    param_scan_local: ResourceId,
    param_scan_block_sum: ResourceId,
    param_scan_block_prefix: ResourceId,
    param_scan_hierarchy: ResourceId,
    param_value_total: ResourceId,
    local_widths: ResourceId,
    local_prefix: ResourceId,
    local_scan_local: ResourceId,
    local_scan_block_sum: ResourceId,
    local_scan_block_prefix: ResourceId,
    local_scan_hierarchy: ResourceId,
    local_value_total: ResourceId,
    functions: ResourceId,
    local_index_by_token: ResourceId,
}

#[derive(Clone, Copy)]
struct WasmModuleGraphResources {
    type_lengths: ResourceId,
    type_offsets: ResourceId,
    type_scan_local: ResourceId,
    type_scan_block_sum: ResourceId,
    type_scan_block_prefix: ResourceId,
    type_scan_hierarchy: ResourceId,
    type_total: ResourceId,
    code_lengths: ResourceId,
    code_offsets: ResourceId,
    code_scan_local: ResourceId,
    code_scan_block_sum: ResourceId,
    code_scan_block_prefix: ResourceId,
    code_scan_hierarchy: ResourceId,
    code_total: ResourceId,
    entrypoint_state: ResourceId,
    layout: ResourceId,
    module_length: ResourceId,
    module_bytes: ResourceId,
}

#[derive(Clone, Copy)]
struct X86ArtifactGraphResources {
    body_length: ResourceId,
    entrypoint_state: ResourceId,
    layout: ResourceId,
    artifact_length: ResourceId,
    artifact_bytes: ResourceId,
}

#[derive(Clone, Copy)]
struct ScheduleGraphResources {
    total: ResourceId,
    keys: ResourceId,
    order: ResourceId,
    order_tmp: ResourceId,
    slot_count: ResourceId,
    histogram: ResourceId,
    global_prefix: ResourceId,
    scan_local: ResourceId,
    scan_block_sum: ResourceId,
    scan_block_prefix: ResourceId,
    scan_hierarchy: ResourceId,
    scan_total: ResourceId,
}

fn add_schedule_graph_passes(
    graph: &mut CompilerGraphBuilder,
    phase: CompilerPhase,
    domain: ResourceDomain,
    resources: ScheduleGraphResources,
) -> Result<(), String> {
    let names = [
        "lir.semantic.schedule.slot_count",
        "lir.semantic.schedule.histogram.even",
        "lir.semantic.schedule.scan.local.even",
        "lir.semantic.schedule.scan.hierarchy_up.even",
        "lir.semantic.schedule.scan.hierarchy_down.even",
        "lir.semantic.schedule.scan.apply.even",
        "lir.semantic.schedule.scatter.even",
        "lir.semantic.schedule.histogram.odd",
        "lir.semantic.schedule.scan.local.odd",
        "lir.semantic.schedule.scan.hierarchy_up.odd",
        "lir.semantic.schedule.scan.hierarchy_down.odd",
        "lir.semantic.schedule.scan.apply.odd",
        "lir.semantic.schedule.scatter.odd",
    ];
    graph.add_pass(PassDesc {
        name: names[0],
        phase,
        dispatch_domain: domain,
        accesses: vec![
            PassAccess::read("target_lir_total", resources.total),
            PassAccess::write("target_schedule_slot_count", resources.slot_count),
        ],
    })?;
    let mut body = Vec::with_capacity(12);
    for base in [1usize, 7usize] {
        let (order_in, order_out) = if base == 1 {
            (resources.order, resources.order_tmp)
        } else {
            (resources.order_tmp, resources.order)
        };
        body.extend([
            PassDesc {
                name: names[base],
                phase,
                dispatch_domain: domain,
                accesses: vec![
                    PassAccess::read("target_lir_total", resources.total),
                    PassAccess::read("target_schedule_key", resources.keys),
                    PassAccess::read("target_schedule_order_in", order_in),
                    PassAccess::write("target_schedule_histogram", resources.histogram),
                ],
            },
            PassDesc {
                name: names[base + 1],
                phase,
                dispatch_domain: domain,
                accesses: vec![
                    PassAccess::read("scan_count", resources.slot_count),
                    PassAccess::read("scan_input", resources.histogram),
                    PassAccess::write("scan_local_prefix", resources.scan_local),
                    PassAccess::write("scan_block_sum", resources.scan_block_sum),
                ],
            },
            PassDesc {
                name: names[base + 2],
                phase,
                dispatch_domain: domain,
                accesses: vec![
                    PassAccess::read("scan_count", resources.slot_count),
                    PassAccess::read("scan_block_sum", resources.scan_block_sum),
                    PassAccess::write("scan_block_prefix", resources.scan_block_prefix),
                    PassAccess::write("scan_hierarchy", resources.scan_hierarchy),
                ],
            },
            PassDesc {
                name: names[base + 3],
                phase,
                dispatch_domain: domain,
                accesses: vec![
                    PassAccess::read("scan_count", resources.slot_count),
                    PassAccess::read_write("scan_block_prefix", resources.scan_block_prefix),
                    PassAccess::read_write("scan_hierarchy", resources.scan_hierarchy),
                ],
            },
            PassDesc {
                name: names[base + 4],
                phase,
                dispatch_domain: domain,
                accesses: vec![
                    PassAccess::read("scan_count", resources.slot_count),
                    PassAccess::read("scan_local_prefix", resources.scan_local),
                    PassAccess::read("scan_block_prefix", resources.scan_block_prefix),
                    PassAccess::write("scan_output_prefix", resources.global_prefix),
                    PassAccess::write("scan_total", resources.scan_total),
                ],
            },
            PassDesc {
                name: names[base + 5],
                phase,
                dispatch_domain: domain,
                accesses: vec![
                    PassAccess::read("target_lir_total", resources.total),
                    PassAccess::read("target_schedule_key", resources.keys),
                    PassAccess::read("target_schedule_order_in", order_in),
                    PassAccess::read("target_schedule_global_prefix", resources.global_prefix),
                    PassAccess::write("target_schedule_order_out", order_out),
                ],
            },
        ]);
    }
    graph.add_repeated_region(TARGET_SCHEDULE_RADIX_STEPS / 2, body)?;
    Ok(())
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirCore {
    pub op: u32,
    pub type_id: u32,
    pub source_hir: u32,
    pub flags: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirOperands {
    pub result: u32,
    pub a: u32,
    pub b: u32,
    pub c: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirCallArg {
    pub call_instruction: u32,
    pub value_instruction: u32,
    pub ordinal: u32,
    pub flags: u32,
}

/// One variable-length aggregate member. Array elements and named struct
/// fields share this representation; `name_token` is INVALID for arrays.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirAggregateElement {
    pub aggregate_instruction: u32,
    pub value_instruction: u32,
    pub ordinal: u32,
    pub name_token: u32,
}

/// A decoded string literal retained independently of compact HIR. The byte
/// range addresses `GpuSemanticLirView::string_data_words`.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirString {
    pub instruction: u32,
    pub data_offset: u32,
    pub decoded_len: u32,
    pub file_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirFunction {
    pub hir_function: u32,
    pub name_token: u32,
    pub param_start: u32,
    pub param_count: u32,
    pub result_type: u32,
    pub flags: u32,
    pub file_id: u32,
    pub local_start: u32,
    pub local_count: u32,
    pub reserved0: u32,
    pub reserved1: u32,
    pub reserved2: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirParam {
    pub function_id: u32,
    pub declaration_id: u32,
    pub ordinal: u32,
    pub type_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirLocal {
    pub function_id: u32,
    pub declaration_id: u32,
    pub ordinal: u32,
    pub type_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirSchedule {
    pub function_id: u32,
    pub execution_region: u32,
    pub execution_rank: u32,
    pub execution_tie: u32,
}

/// One bounded window of the logical semantic instruction stream. The HIR
/// range includes every source node whose variable-size lowering intersects
/// this page; page-relative scatter clips rows at both boundaries.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirPage {
    pub semantic_start: u32,
    pub semantic_count: u32,
    pub hir_start: u32,
    pub hir_count: u32,
}

/// Storage-compatible indirect dispatch record. The final word keeps records
/// 16-byte aligned while the first three words match wgpu's indirect ABI.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct LirDispatchArgs {
    pub x: u32,
    pub y: u32,
    pub z: u32,
    pub reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct LoweringStatus {
    pub flags: u32,
    pub first_unsupported_hir: u32,
    pub required_capacity: u32,
    pub available_capacity: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct TargetScheduleKey {
    pub function_id: u32,
    pub execution_region: u32,
    pub execution_rank: u32,
    pub execution_tie: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct TargetLirFunction {
    pub function_id: u32,
    pub instruction_start: u32,
    pub instruction_count: u32,
    pub flags: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct X86LirCore {
    pub source_hir: u32,
    pub local_ordinal: u32,
    pub op: u32,
    pub result_or_target: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct X86LirOperands {
    pub a: u32,
    pub b: u32,
    pub c: u32,
    pub metadata: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct WasmLirInstruction {
    pub opcode: u32,
    pub immediate: u32,
    pub semantic_instruction: u32,
    pub flags: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct WasmLirOperands {
    pub a: u32,
    pub b: u32,
    pub c: u32,
    pub metadata: u32,
}

/// Target-specialized function record. Source-level parameters and locals
/// remain addressable through the semantic family ranges while the value
/// counts reflect Wasm ABI expansion (for example, strings occupy two i32s).
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct WasmLirFunction {
    pub semantic_function: u32,
    pub type_index: u32,
    pub param_value_count: u32,
    pub local_value_count: u32,
    pub body_instruction_start: u32,
    pub body_instruction_count: u32,
    pub body_byte_start: u32,
    pub body_byte_count: u32,
    pub flags: u32,
    pub result_type: u32,
    pub param_start: u32,
    pub param_count: u32,
    pub local_start: u32,
    pub local_count: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct WasmModuleLayout {
    pub function_count: u32,
    pub entrypoint_count: u32,
    pub entrypoint_id: u32,
    pub status: u32,
    pub module_length: u32,
    pub type_section_start: u32,
    pub type_entries_start: u32,
    pub type_entries_length: u32,
    pub function_section_start: u32,
    pub function_entries_start: u32,
    pub export_section_start: u32,
    pub code_section_start: u32,
    pub code_entries_start: u32,
    pub code_entries_length: u32,
    pub reserved0: u32,
    pub reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct X86ArtifactLayout {
    pub body_length: u32,
    pub file_length: u32,
    pub entrypoint_count: u32,
    pub entrypoint_function: u32,
    pub entrypoint_body_offset: u32,
    pub text_offset: u32,
    pub body_offset: u32,
    pub status: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LoweringTarget {
    X86_64,
    Wasm,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LoweringCapacities {
    pub source_bytes: u32,
    pub tokens: u32,
    pub hir_nodes: u32,
    pub semantic_instructions: u32,
    pub call_arguments: u32,
    pub parameters: u32,
    pub aggregate_elements: u32,
    pub target_instructions: u32,
    pub artifact_bytes: u32,
}

impl LoweringCapacities {
    fn bytes<T>(count: u32) -> u64 {
        u64::from(count.max(1)) * std::mem::size_of::<T>() as u64
    }

    /// Derives lossless lowering capacities from the bounded frontend unit.
    /// These factors are structural upper bounds of the current IR contracts,
    /// not workload guesses. Although one range-loop owner expands to
    /// seventeen semantic rows, it necessarily owns three distinct compact-HIR
    /// rows: the range expression and its two endpoint roots. Those four rows
    /// produce at most twenty semantic rows together. Other structured control
    /// forms have smaller owner/child ratios, giving a five-row semantic bound
    /// per compact-HIR row over the whole tree. Target bounds are likewise
    /// coupled over distinct HIR owners and edges instead of adding mutually
    /// exclusive maxima:
    ///
    /// - x86 range lowering owns at most nineteen rows across its four-row
    ///   minimal HIR subtree, so five target rows per HIR row is sufficient;
    /// - Wasm aggregate lowering owns six rows per distinct element edge plus
    ///   five rows per owner. With at most one incoming aggregate edge per HIR
    ///   row and at most two ordinary rows for every non-owner, this is bounded
    ///   by eight target rows per HIR row;
    /// - call-argument and aggregate-element side rows are source-tree edges.
    ///   Every such edge has a distinct child HIR row, so their expansions do
    ///   not add another whole-HIR maximum on top of the range-loop maximum.
    ///
    /// These remain logical stream bounds; converting them to fixed resident
    /// pages is required before large-unit production use.
    pub fn from_frontend_unit(
        source_bytes: u32,
        token_capacity: u32,
        hir_capacity: u32,
        target: LoweringTarget,
    ) -> Result<Self, String> {
        let multiply = |value: u32, factor: u32, label: &str| {
            value.checked_mul(factor).ok_or_else(|| {
                format!("{label} capacity overflows u32 for a {value}-row frontend unit")
            })
        };
        let add = |left: u32, right: u32, label: &str| {
            left.checked_add(right)
                .ok_or_else(|| format!("{label} capacity overflows u32 for this frontend unit"))
        };
        let hir_nodes = hir_capacity.max(1);
        let semantic_instructions = multiply(hir_nodes, 5, "semantic instruction")?;
        let call_arguments = hir_nodes;
        let aggregate_elements = hir_nodes;
        let target_instructions = multiply(
            hir_nodes,
            match target {
                LoweringTarget::X86_64 => 5,
                LoweringTarget::Wasm => 8,
            },
            "target instruction",
        )?;
        let target_bytes = multiply(
            target_instructions,
            match target {
                LoweringTarget::X86_64 => 16,
                LoweringTarget::Wasm => 8,
            },
            "target artifact",
        )?;
        let table_bytes = multiply(hir_nodes, 32, "artifact table")?;
        let artifact_bytes = add(
            add(source_bytes.max(4), target_bytes, "artifact")?,
            add(table_bytes, 4096, "artifact")?,
            "artifact",
        )?;
        Ok(Self {
            source_bytes: source_bytes.max(4),
            tokens: token_capacity.max(1),
            hir_nodes,
            semantic_instructions,
            call_arguments,
            parameters: hir_nodes,
            aggregate_elements,
            target_instructions,
            artifact_bytes,
        })
    }
}

/// Builds the ownership graph for the common and target-specific lowering
/// levels. The graph is target-selected because one daemon job emits one
/// artifact kind; inactive target storage should never become resident.
pub fn lowering_compiler_graph(
    capacities: LoweringCapacities,
    target: LoweringTarget,
) -> Result<CompilerGraph, String> {
    build_lowering_compiler_graph(capacities, Some(target))
}

pub fn semantic_lowering_compiler_graph(
    capacities: LoweringCapacities,
) -> Result<CompilerGraph, String> {
    build_lowering_compiler_graph(capacities, None)
}

fn build_lowering_compiler_graph(
    capacities: LoweringCapacities,
    target: Option<LoweringTarget>,
) -> Result<CompilerGraph, String> {
    let mut graph = CompilerGraphBuilder::new();
    let value_capacity = capacities
        .tokens
        .saturating_add(capacities.hir_nodes)
        .max(1);
    // A source local contributes one row. A range loop contributes two rows,
    // but necessarily owns three additional compact-HIR rows (range and two
    // endpoints), so the dense local family cannot exceed the HIR row count.
    let local_capacity = capacities.hir_nodes.max(1);
    let input = |name, domain, bytes| ResourceDesc {
        name,
        domain,
        class: ResourceClass::Input,
        bytes,
        usage: WorkspaceUsageClass::Storage,
    };
    let workspace = |name, domain, bytes| ResourceDesc {
        name,
        domain,
        class: ResourceClass::Workspace,
        bytes,
        usage: WorkspaceUsageClass::Storage,
    };
    let artifact = |name, domain, bytes| ResourceDesc {
        name,
        domain,
        class: ResourceClass::Artifact,
        bytes,
        usage: WorkspaceUsageClass::Storage,
    };
    let retained_semantic = |name, domain, bytes| ResourceDesc {
        name,
        domain,
        class: if target.is_none() {
            ResourceClass::Output
        } else {
            ResourceClass::Artifact
        },
        bytes,
        usage: WorkspaceUsageClass::Storage,
    };

    let hir_core = graph.add_resource(input(
        "hir.core",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<crate::parser::buffers::HirCore>(capacities.hir_nodes),
    ))?;
    let hir_count = graph.add_resource(input(
        "hir.count",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_payload = graph.add_resource(input(
        "hir.payload",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<crate::parser::buffers::HirPayload>(capacities.hir_nodes),
    ))?;
    let hir_links = graph.add_resource(input(
        "hir.links",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<crate::parser::buffers::HirLinks>(capacities.hir_nodes),
    ))?;
    let hir_expr_root = graph.add_resource(input(
        "hir.expression_roots",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_expr_parent = graph.add_resource(input(
        "hir.expression_parents",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_nearest_loop = graph.add_resource(input(
        "hir.nearest_loop",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_types = graph.add_resource(input(
        "semantic.expression_types",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let visible_decls = graph.add_resource(input(
        "typecheck.visible_decls",
        ResourceDomain::Tokens,
        LoweringCapacities::bytes::<u32>(capacities.tokens),
    ))?;
    let name_ids_by_token = graph.add_resource(input(
        "typecheck.name_ids_by_token",
        ResourceDomain::Tokens,
        LoweringCapacities::bytes::<u32>(capacities.tokens),
    ))?;
    let language_name_ids = graph.add_resource(input(
        "typecheck.language_name_ids",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(63),
    ))?;
    let visible_types = graph.add_resource(input(
        "typecheck.visible_types",
        ResourceDomain::Tokens,
        LoweringCapacities::bytes::<u32>(capacities.tokens),
    ))?;
    let member_field_ordinals = graph.add_resource(input(
        "typecheck.member_field_ordinals",
        ResourceDomain::Tokens,
        LoweringCapacities::bytes::<u32>(capacities.tokens),
    ))?;
    let struct_init_field_ordinals = graph.add_resource(input(
        "typecheck.struct_init_field_ordinals",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(capacities.aggregate_elements),
    ))?;
    let call_return_types = graph.add_resource(input(
        "typecheck.call_return_types",
        ResourceDomain::Tokens,
        LoweringCapacities::bytes::<u32>(capacities.tokens),
    ))?;
    let function_entrypoint_tags = graph.add_resource(input(
        "typecheck.function_entrypoint_tags",
        ResourceDomain::Tokens,
        LoweringCapacities::bytes::<u32>(capacities.tokens),
    ))?;
    let backend_call_targets = graph.add_resource(input(
        "typecheck.backend_call_targets",
        ResourceDomain::Tokens,
        LoweringCapacities::bytes::<u32>(capacities.tokens),
    ))?;
    let call_intrinsic_tags = graph.add_resource(input(
        "typecheck.call_intrinsic_tags",
        ResourceDomain::Tokens,
        LoweringCapacities::bytes::<u32>(capacities.tokens),
    ))?;
    let enclosing_functions = graph.add_resource(input(
        "typecheck.enclosing_functions",
        ResourceDomain::Tokens,
        LoweringCapacities::bytes::<u32>(capacities.tokens),
    ))?;
    let if_depth = graph.add_resource(input(
        "typecheck.if_depth",
        ResourceDomain::Tokens,
        LoweringCapacities::bytes::<i32>(capacities.tokens),
    ))?;
    let semantic_value_ids = graph.add_resource(artifact(
        "semantic.value_ids",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_value_types = graph.add_resource(artifact(
        "semantic.value_types",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_call_targets = graph.add_resource(artifact(
        "semantic.call_targets",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_call_kinds = graph.add_resource(artifact(
        "semantic.call_kinds",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_call_result_types = graph.add_resource(artifact(
        "semantic.call_result_types",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_function_ids = graph.add_resource(artifact(
        "semantic.function_ids",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_function_flags = graph.add_resource(workspace(
        "lir.semantic.function_flags",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_function_prefix = graph.add_resource(workspace(
        "lir.semantic.function_prefix",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_function_id_by_token = graph.add_resource(workspace(
        "lir.semantic.function_id_by_token",
        ResourceDomain::Tokens,
        LoweringCapacities::bytes::<u32>(capacities.tokens),
    ))?;
    let semantic_local_flags = graph.add_resource(workspace(
        "lir.semantic.local_flags",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_local_prefix = graph.add_resource(workspace(
        "lir.semantic.local_prefix",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_call_arg_count = graph.add_resource(input(
        "hir.call_arg_count",
        ResourceDomain::CallArguments,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_call_args = graph.add_resource(input(
        "hir.call_args",
        ResourceDomain::CallArguments,
        LoweringCapacities::bytes::<crate::parser::buffers::HirCallArg>(capacities.call_arguments),
    ))?;
    let hir_param_count = graph.add_resource(input(
        "hir.param_count",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_params = graph.add_resource(input(
        "hir.params",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<crate::parser::buffers::HirParam>(capacities.parameters),
    ))?;
    let hir_param_ranges = graph.add_resource(input(
        "hir.param_ranges",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<crate::parser::buffers::HirRange>(capacities.hir_nodes),
    ))?;
    let hir_field_count = graph.add_resource(input(
        "hir.field_count",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_fields = graph.add_resource(input(
        "hir.fields",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<crate::parser::buffers::HirField>(
            capacities.aggregate_elements,
        ),
    ))?;
    let hir_array_element_count = graph.add_resource(input(
        "hir.array_element_row_count",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_array_element_start = graph.add_resource(input(
        "hir.array_element_start",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_array_element_owner_count = graph.add_resource(input(
        "hir.array_element_count",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_array_elements = graph.add_resource(input(
        "hir.array_elements",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<crate::parser::buffers::HirArrayElement>(
            capacities.aggregate_elements,
        ),
    ))?;
    let hir_string_count = graph.add_resource(input(
        "hir.string_count",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_strings = graph.add_resource(input(
        "hir.strings",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<crate::parser::buffers::HirString>(capacities.hir_nodes),
    ))?;
    let hir_string_pool_len = graph.add_resource(input(
        "hir.string_pool_len",
        ResourceDomain::SourceBytes,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_string_data = graph.add_resource(input(
        "hir.string_data",
        ResourceDomain::SourceBytes,
        u64::from(capacities.source_bytes.max(4).div_ceil(4)) * 4,
    ))?;
    let semantic_counts = graph.add_resource(workspace(
        "lir.semantic.count_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let execution_rank_link_a = graph.add_resource(workspace(
        "lir.semantic.execution_rank_link_a",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let execution_rank_a = graph.add_resource(workspace(
        "lir.semantic.execution_rank_a",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let execution_rank_link_b = graph.add_resource(workspace(
        "lir.semantic.execution_rank_link_b",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let execution_rank_b = graph.add_resource(workspace(
        "lir.semantic.execution_rank_b",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_offsets = graph.add_resource(workspace(
        "lir.semantic.offset_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_scan_local = graph.add_resource(workspace(
        "lir.semantic.scan_local",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_scan_blocks = capacities.hir_nodes.max(1).div_ceil(256);
    let semantic_scan_block_sum = graph.add_resource(workspace(
        "lir.semantic.scan_block_sum",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_scan_block_prefix = graph.add_resource(workspace(
        "lir.semantic.scan_block_prefix",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_scan_hierarchy = graph.add_resource(workspace(
        "lir.semantic.scan_hierarchy",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_function_scan_local = graph.add_resource(workspace(
        "lir.semantic.function_scan_local",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_function_scan_block_sum = graph.add_resource(workspace(
        "lir.semantic.function_scan_block_sum",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_function_scan_block_prefix = graph.add_resource(workspace(
        "lir.semantic.function_scan_block_prefix",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_function_scan_hierarchy = graph.add_resource(workspace(
        "lir.semantic.function_scan_hierarchy",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_local_scan_local = graph.add_resource(workspace(
        "lir.semantic.local_scan_local",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_local_scan_block_sum = graph.add_resource(workspace(
        "lir.semantic.local_scan_block_sum",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_local_scan_block_prefix = graph.add_resource(workspace(
        "lir.semantic.local_scan_block_prefix",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_local_scan_hierarchy = graph.add_resource(workspace(
        "lir.semantic.local_scan_hierarchy",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_total = graph.add_resource(retained_semantic(
        "lir.semantic.total",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_page_capacity = capacities
        .semantic_instructions
        .max(1)
        .div_ceil(SEMANTIC_LIR_PAGE_ROWS);
    let semantic_page_count = graph.add_resource(retained_semantic(
        "lir.semantic.page_count",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_pages = graph.add_resource(retained_semantic(
        "lir.semantic.pages",
        ResourceDomain::SemanticInstructions,
        u64::from(semantic_page_capacity) * u64::from(SEMANTIC_LIR_PAGE_DESCRIPTOR_STRIDE),
    ))?;
    let semantic_page_dispatch = graph.add_resource(ResourceDesc {
        name: "lir.semantic.page_dispatch",
        domain: ResourceDomain::DispatchArguments,
        class: if target.is_none() {
            ResourceClass::Output
        } else {
            ResourceClass::Artifact
        },
        bytes: LoweringCapacities::bytes::<LirDispatchArgs>(semantic_page_capacity),
        usage: WorkspaceUsageClass::StorageIndirect,
    })?;
    let semantic_core = graph.add_resource(retained_semantic(
        "lir.semantic.core",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<SemanticLirCore>(capacities.semantic_instructions),
    ))?;
    let semantic_operands = graph.add_resource(retained_semantic(
        "lir.semantic.operands",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<SemanticLirOperands>(capacities.semantic_instructions),
    ))?;
    let semantic_schedule = graph.add_resource(retained_semantic(
        "lir.semantic.schedule",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<SemanticLirSchedule>(capacities.semantic_instructions),
    ))?;
    let semantic_call_args = graph.add_resource(retained_semantic(
        "lir.semantic.call_args",
        ResourceDomain::CallArguments,
        LoweringCapacities::bytes::<SemanticLirCallArg>(capacities.call_arguments),
    ))?;
    let semantic_call_arg_total = graph.add_resource(retained_semantic(
        "lir.semantic.call_arg_total",
        ResourceDomain::CallArguments,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_call_arg_start = graph.add_resource(retained_semantic(
        "lir.semantic.call_arg_start_by_instruction",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let semantic_call_arg_count_by_instruction = graph.add_resource(retained_semantic(
        "lir.semantic.call_arg_count_by_instruction",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let semantic_call_arg_start_scratch = graph.add_resource(workspace(
        "lir.semantic.call_arg_start_scratch",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let semantic_call_arg_count_scratch = graph.add_resource(workspace(
        "lir.semantic.call_arg_count_scratch",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let semantic_functions = graph.add_resource(retained_semantic(
        "lir.semantic.functions",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<SemanticLirFunction>(capacities.hir_nodes),
    ))?;
    let semantic_function_total = graph.add_resource(retained_semantic(
        "lir.semantic.function_total",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_params = graph.add_resource(retained_semantic(
        "lir.semantic.params",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<SemanticLirParam>(capacities.parameters),
    ))?;
    let semantic_param_total = graph.add_resource(retained_semantic(
        "lir.semantic.param_total",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_locals = graph.add_resource(retained_semantic(
        "lir.semantic.locals",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<SemanticLirLocal>(local_capacity),
    ))?;
    let semantic_local_total = graph.add_resource(retained_semantic(
        "lir.semantic.local_total",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_aggregate_elements = graph.add_resource(retained_semantic(
        "lir.semantic.aggregate_elements",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<SemanticLirAggregateElement>(
            capacities.aggregate_elements.saturating_mul(2),
        ),
    ))?;
    let semantic_aggregate_element_total = graph.add_resource(retained_semantic(
        "lir.semantic.aggregate_element_total",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_strings = graph.add_resource(retained_semantic(
        "lir.semantic.strings",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<SemanticLirString>(capacities.hir_nodes),
    ))?;
    let semantic_string_total = graph.add_resource(retained_semantic(
        "lir.semantic.string_total",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_string_pool_len = graph.add_resource(retained_semantic(
        "lir.semantic.string_pool_len",
        ResourceDomain::SourceBytes,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_string_data = graph.add_resource(retained_semantic(
        "lir.semantic.string_data",
        ResourceDomain::SourceBytes,
        u64::from(capacities.source_bytes.max(4).div_ceil(4)) * 4,
    ))?;
    let lowering_status = graph.add_resource(ResourceDesc {
        name: "lowering.status",
        domain: ResourceDomain::ArtifactBytes,
        class: ResourceClass::Output,
        bytes: LoweringCapacities::bytes::<LoweringStatus>(1),
        usage: WorkspaceUsageClass::Storage,
    })?;

    graph.add_pass(PassDesc {
        name: "lir.status.clear",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![PassAccess::write("lowering_status", lowering_status)],
    })?;

    graph.add_pass(PassDesc {
        name: "lir.semantic.functions.mark",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::write("semantic_function_flag", semantic_function_flags),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.function_scan.local",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_input", semantic_function_flags),
            PassAccess::write("scan_local_prefix", semantic_function_scan_local),
            PassAccess::write("scan_block_sum", semantic_function_scan_block_sum),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.function_scan.hierarchy_up",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_block_sum", semantic_function_scan_block_sum),
            PassAccess::write("scan_block_prefix", semantic_function_scan_block_prefix),
            PassAccess::write("scan_hierarchy", semantic_function_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.function_scan.hierarchy_down",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read_write("scan_block_prefix", semantic_function_scan_block_prefix),
            PassAccess::read_write("scan_hierarchy", semantic_function_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.function_scan.apply",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_local_prefix", semantic_function_scan_local),
            PassAccess::read("scan_block_prefix", semantic_function_scan_block_prefix),
            PassAccess::write("scan_output_prefix", semantic_function_prefix),
            PassAccess::write("scan_total", semantic_function_total),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.locals.mark",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_hir_payload", hir_payload),
            PassAccess::write("semantic_local_flag", semantic_local_flags),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.local_scan.local",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_input", semantic_local_flags),
            PassAccess::write("scan_local_prefix", semantic_local_scan_local),
            PassAccess::write("scan_block_sum", semantic_local_scan_block_sum),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.local_scan.hierarchy_up",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_block_sum", semantic_local_scan_block_sum),
            PassAccess::write("scan_block_prefix", semantic_local_scan_block_prefix),
            PassAccess::write("scan_hierarchy", semantic_local_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.local_scan.hierarchy_down",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read_write("scan_block_prefix", semantic_local_scan_block_prefix),
            PassAccess::read_write("scan_hierarchy", semantic_local_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.local_scan.apply",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_local_prefix", semantic_local_scan_local),
            PassAccess::read("scan_block_prefix", semantic_local_scan_block_prefix),
            PassAccess::write("scan_output_prefix", semantic_local_prefix),
            PassAccess::write("scan_total", semantic_local_total),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.functions.scatter",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_hir_links", hir_links),
            PassAccess::read("compact_hir_payload", hir_payload),
            PassAccess::read("compact_param_ranges", hir_param_ranges),
            PassAccess::read("semantic_function_flag", semantic_function_flags),
            PassAccess::read("semantic_function_prefix", semantic_function_prefix),
            PassAccess::read("semantic_local_prefix", semantic_local_prefix),
            PassAccess::read("semantic_local_total", semantic_local_total),
            PassAccess::read("call_return_type", call_return_types),
            PassAccess::read("fn_entrypoint_tag", function_entrypoint_tags),
            PassAccess::write("semantic_lir_functions", semantic_functions),
            PassAccess::write(
                "semantic_function_id_by_token",
                semantic_function_id_by_token,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.functions.params",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("compact_param_count", hir_param_count),
            PassAccess::read("compact_params", hir_params),
            PassAccess::read("semantic_function_flag", semantic_function_flags),
            PassAccess::read("semantic_function_prefix", semantic_function_prefix),
            PassAccess::read("visible_type", visible_types),
            PassAccess::write("semantic_lir_param_total", semantic_param_total),
            PassAccess::write("semantic_lir_params", semantic_params),
            PassAccess::read_write("lowering_status", lowering_status),
        ],
    })?;

    graph.add_pass(PassDesc {
        name: "lir.semantic.project",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_hir_payload", hir_payload),
            PassAccess::read("visible_decl", visible_decls),
            PassAccess::read("visible_type", visible_types),
            PassAccess::read("name_id_by_token", name_ids_by_token),
            PassAccess::read("language_name_id", language_name_ids),
            PassAccess::read("backend_call_fn_index", backend_call_targets),
            PassAccess::read("call_intrinsic_tag", call_intrinsic_tags),
            PassAccess::read("enclosing_fn", enclosing_functions),
            PassAccess::read("semantic_function_flag", semantic_function_flags),
            PassAccess::read("semantic_function_prefix", semantic_function_prefix),
            PassAccess::read(
                "semantic_function_id_by_token",
                semantic_function_id_by_token,
            ),
            PassAccess::read("semantic_lir_functions", semantic_functions),
            PassAccess::write("semantic_value_id", semantic_value_ids),
            PassAccess::write("semantic_value_type", semantic_value_types),
            PassAccess::write("semantic_call_target", semantic_call_targets),
            PassAccess::write("semantic_call_kind", semantic_call_kinds),
            PassAccess::write("semantic_call_result_type", semantic_call_result_types),
            PassAccess::write("semantic_function_id", semantic_function_ids),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.locals.scatter",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_payload", hir_payload),
            PassAccess::read("semantic_local_flag", semantic_local_flags),
            PassAccess::read("semantic_local_prefix", semantic_local_prefix),
            PassAccess::read("semantic_function_id", semantic_function_ids),
            PassAccess::read("visible_type", visible_types),
            PassAccess::read("semantic_lir_functions", semantic_functions),
            PassAccess::write("semantic_lir_locals", semantic_locals),
        ],
    })?;

    graph.add_pass(PassDesc {
        name: "lir.semantic.execution_rank.init",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_expr_parent", hir_expr_parent),
            PassAccess::write("execution_rank_link", execution_rank_link_a),
            PassAccess::write("execution_rank", execution_rank_a),
        ],
    })?;
    let rank_pairs = (u32::BITS - capacities.hir_nodes.max(1).leading_zeros())
        .max(1)
        .div_ceil(2);
    graph.add_repeated_region(
        rank_pairs,
        vec![
            PassDesc {
                name: "lir.semantic.execution_rank.step_a_to_b",
                phase: CompilerPhase::SemanticLowering,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("compact_hir_count", hir_count),
                    PassAccess::read("execution_rank_link_in", execution_rank_link_a),
                    PassAccess::read("execution_rank_in", execution_rank_a),
                    PassAccess::write("execution_rank_link_out", execution_rank_link_b),
                    PassAccess::write("execution_rank_out", execution_rank_b),
                ],
            },
            PassDesc {
                name: "lir.semantic.execution_rank.step_b_to_a",
                phase: CompilerPhase::SemanticLowering,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("compact_hir_count", hir_count),
                    PassAccess::read("execution_rank_link_in", execution_rank_link_b),
                    PassAccess::read("execution_rank_in", execution_rank_b),
                    PassAccess::write("execution_rank_link_out", execution_rank_link_a),
                    PassAccess::write("execution_rank_out", execution_rank_a),
                ],
            },
        ],
    )?;

    graph.add_pass(PassDesc {
        name: "lir.semantic.count",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_hir_payload", hir_payload),
            PassAccess::read("compact_expr_parent", hir_expr_parent),
            PassAccess::write("semantic_lir_count", semantic_counts),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.scan.local",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_input", semantic_counts),
            PassAccess::write("scan_local_prefix", semantic_scan_local),
            PassAccess::write("scan_block_sum", semantic_scan_block_sum),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.scan.hierarchy_up",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_block_sum", semantic_scan_block_sum),
            PassAccess::write("scan_block_prefix", semantic_scan_block_prefix),
            PassAccess::write("scan_hierarchy", semantic_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.scan.hierarchy_down",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read_write("scan_block_prefix", semantic_scan_block_prefix),
            PassAccess::read_write("scan_hierarchy", semantic_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.scan.apply",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_local_prefix", semantic_scan_local),
            PassAccess::read("scan_block_prefix", semantic_scan_block_prefix),
            PassAccess::write("scan_output_prefix", semantic_offsets),
            PassAccess::write("scan_total", semantic_total),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.pages.plan",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("semantic_lir_count", semantic_counts),
            PassAccess::read("semantic_lir_offset", semantic_offsets),
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::write("semantic_page_count", semantic_page_count),
            PassAccess::write("semantic_pages", semantic_pages),
            PassAccess::write("semantic_page_dispatch", semantic_page_dispatch),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.scatter",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_hir_links", hir_links),
            PassAccess::read("compact_hir_payload", hir_payload),
            PassAccess::read("semantic_expr_type", semantic_types),
            PassAccess::read("semantic_value_id", semantic_value_ids),
            PassAccess::read("semantic_value_type", semantic_value_types),
            PassAccess::read("semantic_call_target", semantic_call_targets),
            PassAccess::read("semantic_call_kind", semantic_call_kinds),
            PassAccess::read("semantic_call_result_type", semantic_call_result_types),
            PassAccess::read("semantic_function_id", semantic_function_ids),
            PassAccess::read("semantic_lir_functions", semantic_functions),
            PassAccess::read("semantic_if_depth", if_depth),
            PassAccess::read("member_result_field_ordinal", member_field_ordinals),
            PassAccess::read("compact_expr_root", hir_expr_root),
            PassAccess::read("compact_nearest_loop", hir_nearest_loop),
            PassAccess::read("compact_array_element_start", hir_array_element_start),
            PassAccess::read(
                "compact_array_element_owner_count",
                hir_array_element_owner_count,
            ),
            PassAccess::read("compact_array_element_row_count", hir_array_element_count),
            PassAccess::read("semantic_lir_count", semantic_counts),
            PassAccess::read("semantic_lir_offset", semantic_offsets),
            PassAccess::read("semantic_execution_rank", execution_rank_a),
            PassAccess::read("semantic_page", semantic_pages),
            PassAccess::write("semantic_lir_core", semantic_core),
            PassAccess::write("semantic_lir_operands", semantic_operands),
            PassAccess::write("semantic_lir_schedule", semantic_schedule),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.validate",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::read("semantic_lir_core", semantic_core),
            PassAccess::read_write("lowering_status", lowering_status),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.call_arg_ranges.clear",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::write(
                "semantic_lir_call_arg_start_scratch",
                semantic_call_arg_start_scratch,
            ),
            PassAccess::write(
                "semantic_lir_call_arg_count_scratch",
                semantic_call_arg_count_scratch,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.call_args",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::CallArguments,
        accesses: vec![
            PassAccess::read("compact_call_arg_count", hir_call_arg_count),
            PassAccess::read("compact_call_args", hir_call_args),
            PassAccess::read("semantic_lir_count", semantic_counts),
            PassAccess::read("semantic_lir_offset", semantic_offsets),
            PassAccess::write("semantic_lir_call_arg_total", semantic_call_arg_total),
            PassAccess::write("semantic_lir_call_args", semantic_call_args),
            PassAccess::read_write(
                "semantic_lir_call_arg_start_scratch",
                semantic_call_arg_start_scratch,
            ),
            PassAccess::read_write(
                "semantic_lir_call_arg_count_scratch",
                semantic_call_arg_count_scratch,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.call_arg_ranges.finalize",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read(
                "semantic_lir_call_arg_start_scratch",
                semantic_call_arg_start_scratch,
            ),
            PassAccess::read(
                "semantic_lir_call_arg_count_scratch",
                semantic_call_arg_count_scratch,
            ),
            PassAccess::write("semantic_lir_call_arg_start", semantic_call_arg_start),
            PassAccess::write(
                "semantic_lir_call_arg_count",
                semantic_call_arg_count_by_instruction,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.aggregate_elements",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_field_count", hir_field_count),
            PassAccess::read("compact_fields", hir_fields),
            PassAccess::read(
                "struct_init_field_ordinal_by_row",
                struct_init_field_ordinals,
            ),
            PassAccess::read("compact_array_element_count", hir_array_element_count),
            PassAccess::read("compact_array_elements", hir_array_elements),
            PassAccess::read("semantic_lir_count", semantic_counts),
            PassAccess::read("semantic_lir_offset", semantic_offsets),
            PassAccess::write(
                "semantic_lir_aggregate_element_total",
                semantic_aggregate_element_total,
            ),
            PassAccess::write(
                "semantic_lir_aggregate_elements",
                semantic_aggregate_elements,
            ),
            PassAccess::read_write("lowering_status", lowering_status),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.strings",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::SourceBytes,
        accesses: vec![
            PassAccess::read("compact_string_count", hir_string_count),
            PassAccess::read("compact_strings", hir_strings),
            PassAccess::read("compact_string_pool_len", hir_string_pool_len),
            PassAccess::read("compact_string_data", hir_string_data),
            PassAccess::read("semantic_lir_count", semantic_counts),
            PassAccess::read("semantic_lir_offset", semantic_offsets),
            PassAccess::write("semantic_lir_string_total", semantic_string_total),
            PassAccess::write("semantic_lir_strings", semantic_strings),
            PassAccess::write("semantic_lir_string_pool_len", semantic_string_pool_len),
            PassAccess::write("semantic_lir_string_data", semantic_string_data),
            PassAccess::read_write("lowering_status", lowering_status),
        ],
    })?;

    let Some(target) = target else {
        return graph.build();
    };

    let target_domain = match target {
        LoweringTarget::X86_64 => ResourceDomain::X86Instructions,
        LoweringTarget::Wasm => ResourceDomain::WasmInstructions,
    };
    let target_phase = match target {
        LoweringTarget::X86_64 => CompilerPhase::X86Lowering,
        LoweringTarget::Wasm => CompilerPhase::WasmLowering,
    };
    let target_counts = graph.add_resource(workspace(
        match target {
            LoweringTarget::X86_64 => "lir.x86.count_by_semantic",
            LoweringTarget::Wasm => "lir.wasm.count_by_semantic",
        },
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let target_offsets = graph.add_resource(workspace(
        match target {
            LoweringTarget::X86_64 => "lir.x86.offset_by_semantic",
            LoweringTarget::Wasm => "lir.wasm.offset_by_semantic",
        },
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let semantic_to_target_start = graph.add_resource(workspace(
        "lir.target.semantic_to_target_start",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let target_total = graph.add_resource(workspace(
        match target {
            LoweringTarget::X86_64 => "lir.x86.total",
            LoweringTarget::Wasm => "lir.wasm.total",
        },
        target_domain,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let target_scan_blocks = capacities.semantic_instructions.max(1).div_ceil(256);
    let target_scan_local = graph.add_resource(workspace(
        "lir.target.count_scan_local",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let target_scan_block_sum = graph.add_resource(workspace(
        "lir.target.count_scan_block_sum",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(target_scan_blocks),
    ))?;
    let target_scan_block_prefix = graph.add_resource(workspace(
        "lir.target.count_scan_block_prefix",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(target_scan_blocks),
    ))?;
    let target_scan_hierarchy = graph.add_resource(workspace(
        "lir.target.count_scan_hierarchy",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(target_scan_blocks),
    ))?;
    let target_core_bytes = match target {
        LoweringTarget::X86_64 => {
            LoweringCapacities::bytes::<X86LirCore>(capacities.target_instructions)
        }
        LoweringTarget::Wasm => {
            LoweringCapacities::bytes::<WasmLirInstruction>(capacities.target_instructions)
        }
    };
    let target_core = graph.add_resource(match target {
        // x86 call-argument lanes and semantic-row lanes populate disjoint
        // portions of this unscheduled staging table. The single-producer
        // artifact boundary is the subsequent schedule-materialize pass.
        LoweringTarget::X86_64 => workspace("lir.x86.core", target_domain, target_core_bytes),
        LoweringTarget::Wasm => {
            workspace("lir.wasm.instructions", target_domain, target_core_bytes)
        }
    })?;
    // x86 retains virtual operands through final instruction selection. Wasm
    // has only an opcode/immediate after scatter, so a parallel operand table
    // would be dead immediately after its producer.
    let target_operands = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.operands",
            target_domain,
            LoweringCapacities::bytes::<X86LirOperands>(capacities.target_instructions),
        ))?)
    } else {
        None
    };
    // Wasm carries this in WasmLirInstruction. x86 preserves the established
    // virtual-instruction layout, so scheduling provenance is a compact side
    // table rather than an overloaded operand word.
    let target_semantic_origins = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.semantic_origins",
            target_domain,
            LoweringCapacities::bytes::<u32>(capacities.target_instructions),
        ))?)
    } else {
        None
    };
    let x86_target_flags = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.flags",
            target_domain,
            LoweringCapacities::bytes::<u32>(capacities.target_instructions),
        ))?)
    } else {
        None
    };
    let x86_frame_slot_by_decl_token = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(ResourceDesc {
            name: "lir.x86.frame_slot_by_decl_token",
            domain: ResourceDomain::Tokens,
            class: ResourceClass::Output,
            bytes: LoweringCapacities::bytes::<u32>(value_capacity),
            usage: WorkspaceUsageClass::Storage,
        })?)
    } else {
        None
    };
    let wasm_abi = if target == LoweringTarget::Wasm {
        let param_blocks = capacities.parameters.max(1).div_ceil(256);
        let local_blocks = local_capacity.div_ceil(256);
        Some(WasmAbiGraphResources {
            param_widths: graph.add_resource(workspace(
                "lir.wasm.param_widths",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(capacities.parameters),
            ))?,
            param_prefix: graph.add_resource(workspace(
                "lir.wasm.param_prefix",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(capacities.parameters),
            ))?,
            param_scan_local: graph.add_resource(workspace(
                "lir.wasm.param_scan_local",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(capacities.parameters),
            ))?,
            param_scan_block_sum: graph.add_resource(workspace(
                "lir.wasm.param_scan_block_sum",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(param_blocks),
            ))?,
            param_scan_block_prefix: graph.add_resource(workspace(
                "lir.wasm.param_scan_block_prefix",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(param_blocks),
            ))?,
            param_scan_hierarchy: graph.add_resource(workspace(
                "lir.wasm.param_scan_hierarchy",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(param_blocks),
            ))?,
            param_value_total: graph.add_resource(workspace(
                "lir.wasm.param_value_total",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(1),
            ))?,
            local_widths: graph.add_resource(workspace(
                "lir.wasm.local_widths",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(local_capacity),
            ))?,
            local_prefix: graph.add_resource(workspace(
                "lir.wasm.local_prefix",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(local_capacity),
            ))?,
            local_scan_local: graph.add_resource(workspace(
                "lir.wasm.local_scan_local",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(local_capacity),
            ))?,
            local_scan_block_sum: graph.add_resource(workspace(
                "lir.wasm.local_scan_block_sum",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(local_blocks),
            ))?,
            local_scan_block_prefix: graph.add_resource(workspace(
                "lir.wasm.local_scan_block_prefix",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(local_blocks),
            ))?,
            local_scan_hierarchy: graph.add_resource(workspace(
                "lir.wasm.local_scan_hierarchy",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(local_blocks),
            ))?,
            local_value_total: graph.add_resource(workspace(
                "lir.wasm.local_value_total",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(1),
            ))?,
            functions: graph.add_resource(ResourceDesc {
                name: "lir.wasm.functions",
                domain: ResourceDomain::Declarations,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<WasmLirFunction>(capacities.hir_nodes),
                usage: WorkspaceUsageClass::Storage,
            })?,
            local_index_by_token: graph.add_resource(workspace(
                "lir.wasm.local_index_by_token",
                ResourceDomain::Tokens,
                LoweringCapacities::bytes::<u32>(value_capacity),
            ))?,
        })
    } else {
        None
    };
    let schedule_capacity = capacities.semantic_instructions;
    let schedule_order = graph.add_resource(workspace(
        "lir.semantic.schedule_order",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_capacity),
    ))?;
    let schedule_order_tmp = graph.add_resource(workspace(
        "lir.semantic.schedule_order_tmp",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_capacity),
    ))?;
    let scheduled_function_ids = graph.add_resource(workspace(
        "lir.target.scheduled_function_ids",
        target_domain,
        LoweringCapacities::bytes::<u32>(capacities.target_instructions),
    ))?;
    let schedule_blocks = schedule_capacity.max(1).div_ceil(256);
    let schedule_slots = schedule_blocks.saturating_mul(256);
    let schedule_slot_count = graph.add_resource(workspace(
        "lir.semantic.schedule_slot_count",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let schedule_histogram = graph.add_resource(workspace(
        "lir.semantic.schedule_histogram",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_slots),
    ))?;
    let schedule_global_prefix = graph.add_resource(workspace(
        "lir.semantic.schedule_global_prefix",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_slots),
    ))?;
    let schedule_scan_local = graph.add_resource(workspace(
        "lir.semantic.schedule_scan_local",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_slots),
    ))?;
    let schedule_scan_block_sum = graph.add_resource(workspace(
        "lir.semantic.schedule_scan_block_sum",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_slots.div_ceil(256)),
    ))?;
    let schedule_scan_block_prefix = graph.add_resource(workspace(
        "lir.semantic.schedule_scan_block_prefix",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_slots.div_ceil(256)),
    ))?;
    let schedule_scan_hierarchy = graph.add_resource(workspace(
        "lir.semantic.schedule_scan_hierarchy",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_slots.div_ceil(256)),
    ))?;
    let schedule_scan_total = graph.add_resource(workspace(
        "lir.semantic.schedule_scan_total",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let byte_lengths = graph.add_resource(workspace(
        match target {
            LoweringTarget::X86_64 => "lir.x86.byte_lengths",
            LoweringTarget::Wasm => "lir.wasm.byte_lengths",
        },
        target_domain,
        LoweringCapacities::bytes::<u32>(capacities.target_instructions),
    ))?;
    let byte_offsets = graph.add_resource(workspace(
        match target {
            LoweringTarget::X86_64 => "lir.x86.byte_offsets",
            LoweringTarget::Wasm => "lir.wasm.byte_offsets",
        },
        target_domain,
        LoweringCapacities::bytes::<u32>(capacities.target_instructions),
    ))?;
    let byte_scan_blocks = capacities.target_instructions.max(1).div_ceil(256);
    let byte_scan_local = graph.add_resource(workspace(
        "lir.target.byte_scan_local",
        target_domain,
        LoweringCapacities::bytes::<u32>(capacities.target_instructions),
    ))?;
    let byte_scan_block_sum = graph.add_resource(workspace(
        "lir.target.byte_scan_block_sum",
        target_domain,
        LoweringCapacities::bytes::<u32>(byte_scan_blocks),
    ))?;
    let byte_scan_block_prefix = graph.add_resource(workspace(
        "lir.target.byte_scan_block_prefix",
        target_domain,
        LoweringCapacities::bytes::<u32>(byte_scan_blocks),
    ))?;
    let byte_scan_hierarchy = graph.add_resource(workspace(
        "lir.target.byte_scan_hierarchy",
        target_domain,
        LoweringCapacities::bytes::<u32>(byte_scan_blocks),
    ))?;
    let body_length = graph.add_resource(ResourceDesc {
        name: match target {
            LoweringTarget::X86_64 => "lir.x86.body_length",
            LoweringTarget::Wasm => "lir.wasm.body_length",
        },
        domain: ResourceDomain::ArtifactBytes,
        class: ResourceClass::Workspace,
        bytes: LoweringCapacities::bytes::<u32>(1),
        usage: WorkspaceUsageClass::Storage,
    })?;
    let output = graph.add_resource(ResourceDesc {
        name: match target {
            LoweringTarget::X86_64 => "artifact.x86.bytes",
            LoweringTarget::Wasm => "lir.wasm.body_bytes",
        },
        domain: ResourceDomain::ArtifactBytes,
        class: match target {
            LoweringTarget::X86_64 => ResourceClass::Output,
            LoweringTarget::Wasm => ResourceClass::Workspace,
        },
        // The byte emitter binds this storage as packed `u32` words. Keep the
        // logical capacity in bytes while making the physical binding large
        // enough and aligned even for a one-byte artifact.
        bytes: u64::from(capacities.artifact_bytes.max(1).div_ceil(4) * 4),
        usage: WorkspaceUsageClass::Storage,
    })?;
    let x86_artifact = if target == LoweringTarget::X86_64 {
        Some(X86ArtifactGraphResources {
            body_length,
            entrypoint_state: graph.add_resource(workspace(
                "lir.x86.entrypoint_state",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(2),
            ))?,
            layout: graph.add_resource(workspace(
                "lir.x86.artifact_layout",
                ResourceDomain::ArtifactBytes,
                LoweringCapacities::bytes::<X86ArtifactLayout>(1),
            ))?,
            artifact_length: graph.add_resource(ResourceDesc {
                name: "artifact.x86.length",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<u32>(1),
                usage: WorkspaceUsageClass::Storage,
            })?,
            artifact_bytes: output,
        })
    } else {
        None
    };
    let wasm_module = if target == LoweringTarget::Wasm {
        let function_capacity = capacities.hir_nodes.max(1);
        let blocks = function_capacity.div_ceil(256);
        let u32_rows = |graph: &mut CompilerGraphBuilder,
                        name: &'static str,
                        rows: u32|
         -> Result<ResourceId, String> {
            graph.add_resource(workspace(
                name,
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(rows),
            ))
        };
        Some(WasmModuleGraphResources {
            type_lengths: u32_rows(
                &mut graph,
                "lir.wasm.module.type_lengths",
                function_capacity,
            )?,
            type_offsets: u32_rows(
                &mut graph,
                "lir.wasm.module.type_offsets",
                function_capacity,
            )?,
            type_scan_local: u32_rows(
                &mut graph,
                "lir.wasm.module.type_scan_local",
                function_capacity,
            )?,
            type_scan_block_sum: u32_rows(
                &mut graph,
                "lir.wasm.module.type_scan_block_sum",
                blocks,
            )?,
            type_scan_block_prefix: u32_rows(
                &mut graph,
                "lir.wasm.module.type_scan_block_prefix",
                blocks,
            )?,
            type_scan_hierarchy: u32_rows(
                &mut graph,
                "lir.wasm.module.type_scan_hierarchy",
                blocks,
            )?,
            type_total: u32_rows(&mut graph, "lir.wasm.module.type_total", 1)?,
            code_lengths: u32_rows(
                &mut graph,
                "lir.wasm.module.code_lengths",
                function_capacity,
            )?,
            code_offsets: u32_rows(
                &mut graph,
                "lir.wasm.module.code_offsets",
                function_capacity,
            )?,
            code_scan_local: u32_rows(
                &mut graph,
                "lir.wasm.module.code_scan_local",
                function_capacity,
            )?,
            code_scan_block_sum: u32_rows(
                &mut graph,
                "lir.wasm.module.code_scan_block_sum",
                blocks,
            )?,
            code_scan_block_prefix: u32_rows(
                &mut graph,
                "lir.wasm.module.code_scan_block_prefix",
                blocks,
            )?,
            code_scan_hierarchy: u32_rows(
                &mut graph,
                "lir.wasm.module.code_scan_hierarchy",
                blocks,
            )?,
            code_total: u32_rows(&mut graph, "lir.wasm.module.code_total", 1)?,
            entrypoint_state: u32_rows(&mut graph, "lir.wasm.module.entrypoint_state", 2)?,
            layout: graph.add_resource(workspace(
                "lir.wasm.module.layout",
                ResourceDomain::ArtifactBytes,
                LoweringCapacities::bytes::<WasmModuleLayout>(1),
            ))?,
            module_length: graph.add_resource(ResourceDesc {
                name: "artifact.wasm.length",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<u32>(1),
                usage: WorkspaceUsageClass::Storage,
            })?,
            module_bytes: graph.add_resource(ResourceDesc {
                name: "artifact.wasm.bytes",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: u64::from(capacities.artifact_bytes.max(1).div_ceil(4) * 4),
                usage: WorkspaceUsageClass::Storage,
            })?,
        })
    } else {
        None
    };

    graph.add_pass(PassDesc {
        name: "lir.semantic.schedule.init",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::write("target_schedule_order", schedule_order),
        ],
    })?;
    let schedule_resources = ScheduleGraphResources {
        total: semantic_total,
        keys: semantic_schedule,
        order: schedule_order,
        order_tmp: schedule_order_tmp,
        slot_count: schedule_slot_count,
        histogram: schedule_histogram,
        global_prefix: schedule_global_prefix,
        scan_local: schedule_scan_local,
        scan_block_sum: schedule_scan_block_sum,
        scan_block_prefix: schedule_scan_block_prefix,
        scan_hierarchy: schedule_scan_hierarchy,
        scan_total: schedule_scan_total,
    };
    add_schedule_graph_passes(
        &mut graph,
        CompilerPhase::SemanticLowering,
        ResourceDomain::SemanticInstructions,
        schedule_resources,
    )?;

    let target_count_accesses = match target {
        LoweringTarget::Wasm => vec![
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::read("semantic_lir_core", semantic_core),
            PassAccess::read("semantic_lir_operands", semantic_operands),
            PassAccess::read("semantic_schedule_order", schedule_order),
            PassAccess::write("target_lir_count", target_counts),
        ],
        LoweringTarget::X86_64 => vec![
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::read("semantic_lir_core", semantic_core),
            PassAccess::read("semantic_lir_operands", semantic_operands),
            PassAccess::read("semantic_schedule_order", schedule_order),
            PassAccess::read(
                "semantic_lir_call_arg_count_by_instruction",
                semantic_call_arg_count_by_instruction,
            ),
            PassAccess::write("target_lir_count", target_counts),
        ],
    };
    graph.add_pass(PassDesc {
        name: match target {
            LoweringTarget::X86_64 => "lir.x86.count",
            LoweringTarget::Wasm => "lir.wasm.count",
        },
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: target_count_accesses,
    })?;
    let target_scatter_accesses = match target {
        LoweringTarget::Wasm => vec![
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::read("semantic_lir_core", semantic_core),
            PassAccess::read("semantic_lir_operands", semantic_operands),
            PassAccess::read("semantic_lir_schedule", semantic_schedule),
            PassAccess::read("semantic_schedule_order", schedule_order),
            PassAccess::read(
                "semantic_lir_aggregate_elements",
                semantic_aggregate_elements,
            ),
            PassAccess::read("target_lir_offset", target_offsets),
            PassAccess::read("target_lir_total", target_total),
            PassAccess::write("semantic_to_target_start", semantic_to_target_start),
            PassAccess::write("target_lir_core", target_core),
        ],
        LoweringTarget::X86_64 => vec![
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::read("semantic_lir_core", semantic_core),
            PassAccess::read("semantic_lir_operands", semantic_operands),
            PassAccess::read("semantic_schedule_order", schedule_order),
            PassAccess::read(
                "semantic_lir_call_arg_count_by_instruction",
                semantic_call_arg_count_by_instruction,
            ),
            PassAccess::read(
                "semantic_lir_call_arg_start_by_instruction",
                semantic_call_arg_start,
            ),
            PassAccess::read("semantic_lir_call_args", semantic_call_args),
            PassAccess::read(
                "semantic_lir_aggregate_element_total",
                semantic_aggregate_element_total,
            ),
            PassAccess::read(
                "semantic_lir_aggregate_elements",
                semantic_aggregate_elements,
            ),
            PassAccess::read("target_lir_offset", target_offsets),
            PassAccess::read("target_lir_total", target_total),
            PassAccess::write("semantic_to_target_start", semantic_to_target_start),
            PassAccess::write("target_lir_core", target_core),
            PassAccess::write(
                "target_lir_operands",
                target_operands.expect("x86 operand resource"),
            ),
            PassAccess::write(
                "target_semantic_origin",
                target_semantic_origins.expect("x86 semantic origin resource"),
            ),
            PassAccess::write(
                "target_lir_flags",
                x86_target_flags.expect("x86 target flag resource"),
            ),
        ],
    };
    graph.add_pass(PassDesc {
        name: "lir.target.count_scan.local",
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("scan_count", semantic_total),
            PassAccess::read("scan_input", target_counts),
            PassAccess::write("scan_local_prefix", target_scan_local),
            PassAccess::write("scan_block_sum", target_scan_block_sum),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.count_scan.hierarchy_up",
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("scan_count", semantic_total),
            PassAccess::read("scan_block_sum", target_scan_block_sum),
            PassAccess::write("scan_block_prefix", target_scan_block_prefix),
            PassAccess::write("scan_hierarchy", target_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.count_scan.hierarchy_down",
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("scan_count", semantic_total),
            PassAccess::read_write("scan_block_prefix", target_scan_block_prefix),
            PassAccess::read_write("scan_hierarchy", target_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.count_scan.apply",
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("scan_count", semantic_total),
            PassAccess::read("scan_local_prefix", target_scan_local),
            PassAccess::read("scan_block_prefix", target_scan_block_prefix),
            PassAccess::write("scan_output_prefix", target_offsets),
            PassAccess::write("scan_total", target_total),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: match target {
            LoweringTarget::X86_64 => "lir.x86.scatter",
            LoweringTarget::Wasm => "lir.wasm.scatter",
        },
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: target_scatter_accesses,
    })?;
    if let Some(wasm) = wasm_abi {
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.param_widths",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_param_total", semantic_param_total),
                PassAccess::read("semantic_lir_params", semantic_params),
                PassAccess::write("wasm_param_width", wasm.param_widths),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.param_scan.local",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_param_total),
                PassAccess::read("scan_input", wasm.param_widths),
                PassAccess::write("scan_local_prefix", wasm.param_scan_local),
                PassAccess::write("scan_block_sum", wasm.param_scan_block_sum),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.param_scan.hierarchy_up",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_param_total),
                PassAccess::read("scan_block_sum", wasm.param_scan_block_sum),
                PassAccess::write("scan_block_prefix", wasm.param_scan_block_prefix),
                PassAccess::write("scan_hierarchy", wasm.param_scan_hierarchy),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.param_scan.hierarchy_down",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_param_total),
                PassAccess::read_write("scan_block_prefix", wasm.param_scan_block_prefix),
                PassAccess::read_write("scan_hierarchy", wasm.param_scan_hierarchy),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.param_scan.apply",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_param_total),
                PassAccess::read("scan_local_prefix", wasm.param_scan_local),
                PassAccess::read("scan_block_prefix", wasm.param_scan_block_prefix),
                PassAccess::write("scan_output_prefix", wasm.param_prefix),
                PassAccess::write("scan_total", wasm.param_value_total),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.local_widths",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_local_total", semantic_local_total),
                PassAccess::read("semantic_lir_locals", semantic_locals),
                PassAccess::write("wasm_local_width", wasm.local_widths),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.local_scan.local",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_local_total),
                PassAccess::read("scan_input", wasm.local_widths),
                PassAccess::write("scan_local_prefix", wasm.local_scan_local),
                PassAccess::write("scan_block_sum", wasm.local_scan_block_sum),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.local_scan.hierarchy_up",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_local_total),
                PassAccess::read("scan_block_sum", wasm.local_scan_block_sum),
                PassAccess::write("scan_block_prefix", wasm.local_scan_block_prefix),
                PassAccess::write("scan_hierarchy", wasm.local_scan_hierarchy),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.local_scan.hierarchy_down",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_local_total),
                PassAccess::read_write("scan_block_prefix", wasm.local_scan_block_prefix),
                PassAccess::read_write("scan_hierarchy", wasm.local_scan_hierarchy),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.local_scan.apply",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_local_total),
                PassAccess::read("scan_local_prefix", wasm.local_scan_local),
                PassAccess::read("scan_block_prefix", wasm.local_scan_block_prefix),
                PassAccess::write("scan_output_prefix", wasm.local_prefix),
                PassAccess::write("scan_total", wasm.local_value_total),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.functions",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_function_total", semantic_function_total),
                PassAccess::read("semantic_lir_functions", semantic_functions),
                PassAccess::read("semantic_lir_param_total", semantic_param_total),
                PassAccess::read("wasm_param_prefix", wasm.param_prefix),
                PassAccess::read("wasm_param_value_total", wasm.param_value_total),
                PassAccess::read("semantic_lir_local_total", semantic_local_total),
                PassAccess::read("wasm_local_prefix", wasm.local_prefix),
                PassAccess::read("wasm_local_value_total", wasm.local_value_total),
                PassAccess::write("wasm_lir_functions", wasm.functions),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.declaration_indices",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_param_total", semantic_param_total),
                PassAccess::read("semantic_lir_params", semantic_params),
                PassAccess::read("wasm_param_prefix", wasm.param_prefix),
                PassAccess::read("semantic_lir_local_total", semantic_local_total),
                PassAccess::read("semantic_lir_locals", semantic_locals),
                PassAccess::read("wasm_local_prefix", wasm.local_prefix),
                PassAccess::read("wasm_lir_functions", wasm.functions),
                PassAccess::write("wasm_local_index_by_decl_token", wasm.local_index_by_token),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.resolve_indices",
            phase: target_phase,
            dispatch_domain: target_domain,
            accesses: vec![
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read("wasm_local_index_by_decl_token", wasm.local_index_by_token),
                PassAccess::read("semantic_lir_schedule", semantic_schedule),
                PassAccess::read("wasm_lir_functions", wasm.functions),
                PassAccess::read_write("target_lir_core", target_core),
            ],
        })?;
    }
    graph.add_pass(PassDesc {
        name: match target {
            LoweringTarget::X86_64 => "lir.x86.validate",
            LoweringTarget::Wasm => "lir.wasm.validate",
        },
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: match target {
            LoweringTarget::Wasm => vec![
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read("target_lir_core", target_core),
                PassAccess::read("semantic_lir_core", semantic_core),
                PassAccess::read_write("lowering_status", lowering_status),
            ],
            LoweringTarget::X86_64 => vec![
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read("target_lir_core", target_core),
                PassAccess::read(
                    "target_lir_flags",
                    x86_target_flags.expect("x86 target flag resource"),
                ),
                PassAccess::read_write("lowering_status", lowering_status),
            ],
        },
    })?;
    if target == LoweringTarget::X86_64 {
        graph.add_pass(PassDesc {
            name: "lir.x86.resolve",
            phase: target_phase,
            dispatch_domain: target_domain,
            accesses: vec![
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read_write("target_lir_core", target_core),
                PassAccess::read_write(
                    "target_lir_operands",
                    target_operands.expect("x86 operand resource"),
                ),
                PassAccess::read("semantic_to_target_start", semantic_to_target_start),
                PassAccess::read(
                    "target_semantic_origin",
                    target_semantic_origins.expect("x86 semantic origin resource"),
                ),
                PassAccess::read("semantic_lir_schedule", semantic_schedule),
                PassAccess::write("scheduled_function_id", scheduled_function_ids),
            ],
        })?;
    } else {
        graph.add_pass(PassDesc {
            name: "lir.wasm.schedule.function_ids",
            phase: target_phase,
            dispatch_domain: target_domain,
            accesses: vec![
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read("target_lir_core", target_core),
                PassAccess::read("semantic_lir_schedule", semantic_schedule),
                PassAccess::write("scheduled_function_id", scheduled_function_ids),
            ],
        })?;
    }
    let function_flags = graph.add_resource(workspace(
        "lir.target.function_flags",
        target_domain,
        LoweringCapacities::bytes::<u32>(capacities.target_instructions),
    ))?;
    let function_prefix = graph.add_resource(workspace(
        "lir.target.function_prefix",
        target_domain,
        LoweringCapacities::bytes::<u32>(capacities.target_instructions),
    ))?;
    let function_scan_local = graph.add_resource(workspace(
        "lir.target.function_scan_local",
        target_domain,
        LoweringCapacities::bytes::<u32>(capacities.target_instructions),
    ))?;
    let function_scan_blocks = capacities.target_instructions.max(1).div_ceil(256);
    let function_scan_block_sum = graph.add_resource(workspace(
        "lir.target.function_scan_block_sum",
        target_domain,
        LoweringCapacities::bytes::<u32>(function_scan_blocks),
    ))?;
    let function_scan_block_prefix = graph.add_resource(workspace(
        "lir.target.function_scan_block_prefix",
        target_domain,
        LoweringCapacities::bytes::<u32>(function_scan_blocks),
    ))?;
    let function_scan_hierarchy = graph.add_resource(workspace(
        "lir.target.function_scan_hierarchy",
        target_domain,
        LoweringCapacities::bytes::<u32>(function_scan_blocks),
    ))?;
    let function_count = graph.add_resource(ResourceDesc {
        name: "lir.target.function_count",
        domain: ResourceDomain::Declarations,
        class: ResourceClass::Output,
        bytes: LoweringCapacities::bytes::<u32>(1),
        usage: WorkspaceUsageClass::Storage,
    })?;
    let function_starts = graph.add_resource(workspace(
        "lir.target.function_starts",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let compact_function_ids = graph.add_resource(workspace(
        "lir.target.compact_function_ids",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let functions = graph.add_resource(ResourceDesc {
        name: "lir.target.functions",
        domain: ResourceDomain::Declarations,
        class: ResourceClass::Output,
        bytes: LoweringCapacities::bytes::<TargetLirFunction>(capacities.hir_nodes),
        usage: WorkspaceUsageClass::Storage,
    })?;
    let function_index_by_semantic = graph.add_resource(ResourceDesc {
        name: "lir.target.function_index_by_semantic",
        domain: ResourceDomain::Declarations,
        class: ResourceClass::Output,
        bytes: LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
        usage: WorkspaceUsageClass::Storage,
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.functions.mark",
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: vec![
            PassAccess::read("target_lir_total", target_total),
            PassAccess::read("scheduled_function_id", scheduled_function_ids),
            PassAccess::write("function_start_flag", function_flags),
            PassAccess::write("function_index_by_semantic", function_index_by_semantic),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.function_scan.local",
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: vec![
            PassAccess::read("scan_count", target_total),
            PassAccess::read("scan_input", function_flags),
            PassAccess::write("scan_local_prefix", function_scan_local),
            PassAccess::write("scan_block_sum", function_scan_block_sum),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.function_scan.hierarchy_up",
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: vec![
            PassAccess::read("scan_count", target_total),
            PassAccess::read("scan_block_sum", function_scan_block_sum),
            PassAccess::write("scan_block_prefix", function_scan_block_prefix),
            PassAccess::write("scan_hierarchy", function_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.function_scan.hierarchy_down",
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: vec![
            PassAccess::read("scan_count", target_total),
            PassAccess::read_write("scan_block_prefix", function_scan_block_prefix),
            PassAccess::read_write("scan_hierarchy", function_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.function_scan.apply",
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: vec![
            PassAccess::read("scan_count", target_total),
            PassAccess::read("scan_local_prefix", function_scan_local),
            PassAccess::read("scan_block_prefix", function_scan_block_prefix),
            PassAccess::write("scan_output_prefix", function_prefix),
            PassAccess::write("scan_total", function_count),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.functions.scatter_starts",
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: vec![
            PassAccess::read("target_lir_total", target_total),
            PassAccess::read("scheduled_function_id", scheduled_function_ids),
            PassAccess::read("function_start_flag", function_flags),
            PassAccess::read("function_prefix", function_prefix),
            PassAccess::write("function_start", function_starts),
            PassAccess::write("compact_function_id", compact_function_ids),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.functions.finalize",
        phase: target_phase,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("target_lir_total", target_total),
            PassAccess::read("function_count", function_count),
            PassAccess::read("function_start", function_starts),
            PassAccess::read("compact_function_id", compact_function_ids),
            PassAccess::write("target_function", functions),
            PassAccess::write("function_index_by_semantic", function_index_by_semantic),
        ],
    })?;
    if target == LoweringTarget::X86_64 {
        graph.add_pass(PassDesc {
            name: "lir.x86.decl_slots.clear",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Tokens,
            accesses: vec![PassAccess::write(
                "x86_frame_slot_by_decl_token",
                x86_frame_slot_by_decl_token.expect("x86 declaration slot resource"),
            )],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.decl_slots.scatter",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_param_total", semantic_param_total),
                PassAccess::read("semantic_lir_params", semantic_params),
                PassAccess::read("semantic_lir_local_total", semantic_local_total),
                PassAccess::read("semantic_lir_locals", semantic_locals),
                PassAccess::read("semantic_lir_function_total", semantic_function_total),
                PassAccess::read("semantic_lir_functions", semantic_functions),
                PassAccess::read("target_function_count", function_count),
                PassAccess::read("target_functions", functions),
                PassAccess::read(
                    "target_function_index_by_semantic",
                    function_index_by_semantic,
                ),
                PassAccess::read_write(
                    "x86_frame_slot_by_decl_token",
                    x86_frame_slot_by_decl_token.expect("x86 declaration slot resource"),
                ),
            ],
        })?;
    }
    let byte_count_accesses = match target {
        LoweringTarget::Wasm => vec![
            PassAccess::read("target_lir_total", target_total),
            PassAccess::read("target_lir_core", target_core),
            PassAccess::write("target_byte_length", byte_lengths),
        ],
        LoweringTarget::X86_64 => vec![
            PassAccess::read("target_lir_total", target_total),
            PassAccess::read("target_lir_core", target_core),
            // x86 encoding size depends on virtual operands and register/
            // addressing forms, unlike Wasm's opcode/immediate record.
            PassAccess::read(
                "target_lir_operands",
                target_operands.expect("x86 operand resource"),
            ),
            PassAccess::read("scheduled_function_id", scheduled_function_ids),
            PassAccess::read("target_function_count", function_count),
            PassAccess::read("target_functions", functions),
            PassAccess::read(
                "target_function_index_by_semantic",
                function_index_by_semantic,
            ),
            PassAccess::read("semantic_lir_function_total", semantic_function_total),
            PassAccess::read("semantic_lir_functions", semantic_functions),
            PassAccess::write("target_byte_length", byte_lengths),
            PassAccess::read_write("lowering_status", lowering_status),
        ],
    };
    graph.add_pass(PassDesc {
        name: match target {
            LoweringTarget::X86_64 => "lir.x86.byte_count",
            LoweringTarget::Wasm => "lir.wasm.byte_count",
        },
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: byte_count_accesses,
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.byte_scan.local",
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: vec![
            PassAccess::read("scan_count", target_total),
            PassAccess::read("scan_input", byte_lengths),
            PassAccess::write("scan_local_prefix", byte_scan_local),
            PassAccess::write("scan_block_sum", byte_scan_block_sum),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.byte_scan.hierarchy_up",
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: vec![
            PassAccess::read("scan_count", target_total),
            PassAccess::read("scan_block_sum", byte_scan_block_sum),
            PassAccess::write("scan_block_prefix", byte_scan_block_prefix),
            PassAccess::write("scan_hierarchy", byte_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.byte_scan.hierarchy_down",
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: vec![
            PassAccess::read("scan_count", target_total),
            PassAccess::read_write("scan_block_prefix", byte_scan_block_prefix),
            PassAccess::read_write("scan_hierarchy", byte_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.byte_scan.apply",
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: vec![
            PassAccess::read("scan_count", target_total),
            PassAccess::read("scan_local_prefix", byte_scan_local),
            PassAccess::read("scan_block_prefix", byte_scan_block_prefix),
            PassAccess::write("scan_output_prefix", byte_offsets),
            PassAccess::write("scan_total", body_length),
        ],
    })?;
    if let Some(wasm) = wasm_abi {
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.attach_bodies",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("target_function_count", function_count),
                PassAccess::read("target_functions", functions),
                PassAccess::read("target_byte_length", byte_lengths),
                PassAccess::read("target_byte_offset", byte_offsets),
                PassAccess::read_write("wasm_lir_functions", wasm.functions),
            ],
        })?;
    }
    if let Some(x86) = x86_artifact {
        graph.add_pass(PassDesc {
            name: "lir.x86.entrypoint.clear",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![PassAccess::write(
                "x86_entrypoint_state",
                x86.entrypoint_state,
            )],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.entrypoint.reduce",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_function_total", semantic_function_total),
                PassAccess::read("semantic_lir_functions", semantic_functions),
                PassAccess::read_write("x86_entrypoint_state", x86.entrypoint_state),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.artifact.layout",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::ArtifactBytes,
            accesses: vec![
                PassAccess::read("x86_body_length", x86.body_length),
                PassAccess::read("x86_entrypoint_state", x86.entrypoint_state),
                PassAccess::read("target_function_count", function_count),
                PassAccess::read("target_functions", functions),
                PassAccess::read(
                    "target_function_index_by_semantic",
                    function_index_by_semantic,
                ),
                PassAccess::read("target_byte_offset", byte_offsets),
                PassAccess::write("x86_artifact_layout", x86.layout),
                PassAccess::write("x86_artifact_length", x86.artifact_length),
                PassAccess::read_write("lowering_status", lowering_status),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.artifact.clear",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::ArtifactBytes,
            accesses: vec![PassAccess::write("artifact_bytes", x86.artifact_bytes)],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.emit",
            phase: CompilerPhase::Artifact,
            dispatch_domain: target_domain,
            accesses: vec![
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read("target_lir_core", target_core),
                PassAccess::read(
                    "target_lir_operands",
                    target_operands.expect("x86 operand resource"),
                ),
                PassAccess::read("scheduled_function_id", scheduled_function_ids),
                PassAccess::read("target_function_count", function_count),
                PassAccess::read("target_functions", functions),
                PassAccess::read(
                    "target_function_index_by_semantic",
                    function_index_by_semantic,
                ),
                PassAccess::read("semantic_lir_function_total", semantic_function_total),
                PassAccess::read("semantic_lir_functions", semantic_functions),
                PassAccess::read(
                    "x86_frame_slot_by_decl_token",
                    x86_frame_slot_by_decl_token.expect("x86 declaration slot resource"),
                ),
                PassAccess::read("target_byte_length", byte_lengths),
                PassAccess::read("target_byte_offset", byte_offsets),
                PassAccess::read("x86_artifact_layout", x86.layout),
                PassAccess::write("artifact_bytes", x86.artifact_bytes),
            ],
        })?;
    } else {
        graph.add_pass(PassDesc {
            name: "lir.wasm.emit",
            phase: CompilerPhase::Artifact,
            dispatch_domain: target_domain,
            accesses: vec![
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read("target_lir_core", target_core),
                PassAccess::read("target_byte_length", byte_lengths),
                PassAccess::read("target_byte_offset", byte_offsets),
                PassAccess::read("artifact_length", body_length),
                PassAccess::write("artifact_bytes", output),
            ],
        })?;
    }

    if let (Some(wasm), Some(module)) = (wasm_abi, wasm_module) {
        graph.add_pass(PassDesc {
            name: "lir.wasm.module.state_clear",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![PassAccess::write(
                "wasm_module_entrypoint_state",
                module.entrypoint_state,
            )],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.module.lengths",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("wasm_lir_function_total", semantic_function_total),
                PassAccess::read("wasm_lir_functions", wasm.functions),
                PassAccess::write("wasm_type_entry_length", module.type_lengths),
                PassAccess::write("wasm_code_entry_length", module.code_lengths),
                PassAccess::read_write("wasm_module_entrypoint_state", module.entrypoint_state),
            ],
        })?;
        for (prefix, lengths, offsets, local, block_sum, block_prefix, hierarchy, total) in [
            (
                "lir.wasm.module.type_scan",
                module.type_lengths,
                module.type_offsets,
                module.type_scan_local,
                module.type_scan_block_sum,
                module.type_scan_block_prefix,
                module.type_scan_hierarchy,
                module.type_total,
            ),
            (
                "lir.wasm.module.code_scan",
                module.code_lengths,
                module.code_offsets,
                module.code_scan_local,
                module.code_scan_block_sum,
                module.code_scan_block_prefix,
                module.code_scan_hierarchy,
                module.code_total,
            ),
        ] {
            graph.add_pass(PassDesc {
                name: if prefix.ends_with("type_scan") {
                    "lir.wasm.module.type_scan.local"
                } else {
                    "lir.wasm.module.code_scan.local"
                },
                phase: CompilerPhase::Artifact,
                dispatch_domain: ResourceDomain::Declarations,
                accesses: vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read("scan_input", lengths),
                    PassAccess::write("scan_local_prefix", local),
                    PassAccess::write("scan_block_sum", block_sum),
                ],
            })?;
            graph.add_pass(PassDesc {
                name: if prefix.ends_with("type_scan") {
                    "lir.wasm.module.type_scan.hierarchy_up"
                } else {
                    "lir.wasm.module.code_scan.hierarchy_up"
                },
                phase: CompilerPhase::Artifact,
                dispatch_domain: ResourceDomain::Declarations,
                accesses: vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read("scan_block_sum", block_sum),
                    PassAccess::write("scan_block_prefix", block_prefix),
                    PassAccess::write("scan_hierarchy", hierarchy),
                ],
            })?;
            graph.add_pass(PassDesc {
                name: if prefix.ends_with("type_scan") {
                    "lir.wasm.module.type_scan.hierarchy_down"
                } else {
                    "lir.wasm.module.code_scan.hierarchy_down"
                },
                phase: CompilerPhase::Artifact,
                dispatch_domain: ResourceDomain::Declarations,
                accesses: vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read_write("scan_block_prefix", block_prefix),
                    PassAccess::read_write("scan_hierarchy", hierarchy),
                ],
            })?;
            graph.add_pass(PassDesc {
                name: if prefix.ends_with("type_scan") {
                    "lir.wasm.module.type_scan.apply"
                } else {
                    "lir.wasm.module.code_scan.apply"
                },
                phase: CompilerPhase::Artifact,
                dispatch_domain: ResourceDomain::Declarations,
                accesses: vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read("scan_local_prefix", local),
                    PassAccess::read("scan_block_prefix", block_prefix),
                    PassAccess::write("scan_output_prefix", offsets),
                    PassAccess::write("scan_total", total),
                ],
            })?;
        }
        graph.add_pass(PassDesc {
            name: "lir.wasm.module.layout",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::ArtifactBytes,
            accesses: vec![
                PassAccess::read("wasm_lir_function_total", semantic_function_total),
                PassAccess::read("wasm_type_entries_length", module.type_total),
                PassAccess::read("wasm_code_entries_length", module.code_total),
                PassAccess::read("wasm_module_entrypoint_state", module.entrypoint_state),
                PassAccess::write("wasm_module_layout", module.layout),
                PassAccess::write("wasm_module_length", module.module_length),
                PassAccess::read_write("lowering_status", lowering_status),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.module.emit_headers",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::ArtifactBytes,
            accesses: vec![
                PassAccess::read("wasm_module_layout", module.layout),
                PassAccess::write("wasm_module_bytes", module.module_bytes),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.module.emit_functions",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("wasm_lir_function_total", semantic_function_total),
                PassAccess::read("wasm_lir_functions", wasm.functions),
                PassAccess::read("semantic_lir_params", semantic_params),
                PassAccess::read("semantic_lir_locals", semantic_locals),
                PassAccess::read("wasm_type_entry_offset", module.type_offsets),
                PassAccess::read("wasm_code_entry_offset", module.code_offsets),
                PassAccess::read("wasm_body_bytes", output),
                PassAccess::read("wasm_module_layout", module.layout),
                PassAccess::write("wasm_module_bytes", module.module_bytes),
            ],
        })?;
    }

    graph.build()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frontend_unit_capacity_uses_structural_ir_expansion_bounds() {
        let wasm =
            LoweringCapacities::from_frontend_unit(1_000, 400, 100, LoweringTarget::Wasm).unwrap();
        assert_eq!(wasm.semantic_instructions, 500);
        assert_eq!(wasm.target_instructions, 800);
        assert_eq!(wasm.call_arguments, 100);
        assert!(wasm.artifact_bytes >= 1_000 + 800 * 8 + 100 * 32);

        let x86 = LoweringCapacities::from_frontend_unit(1_000, 400, 100, LoweringTarget::X86_64)
            .unwrap();
        assert_eq!(x86.semantic_instructions, 500);
        assert_eq!(x86.target_instructions, 500);
        assert!(
            LoweringCapacities::from_frontend_unit(
                u32::MAX,
                u32::MAX,
                u32::MAX,
                LoweringTarget::Wasm,
            )
            .unwrap_err()
            .contains("semantic instruction")
        );
    }

    #[test]
    fn lowering_workspace_footprint_is_physical_slot_sum() {
        for target in [LoweringTarget::X86_64, LoweringTarget::Wasm] {
            let capacities = LoweringCapacities::from_frontend_unit(
                1024 * 1024,
                1024 * 1024,
                1024 * 1024,
                target,
            )
            .unwrap();
            let graph = lowering_compiler_graph(capacities, target).unwrap();
            let expected = graph
                .workspace_plan()
                .slots
                .iter()
                .map(|slot| slot.bytes)
                .sum::<u64>();
            assert_eq!(graph.workspace_bytes(), expected);
            eprintln!("{target:?} 1MiB lowering workspace: {expected} bytes");
            let mut slots = graph.workspace_plan().slots.clone();
            slots.sort_unstable_by_key(|slot| std::cmp::Reverse(slot.bytes));
            for slot in slots.iter().take(12) {
                let owners = graph
                    .workspace_plan()
                    .assignments
                    .iter()
                    .filter(|assignment| assignment.slot == slot.slot)
                    .map(|assignment| assignment.name)
                    .collect::<Vec<_>>();
                eprintln!("  slot {}: {} bytes {owners:?}", slot.slot, slot.bytes);
            }
        }
    }

    #[test]
    fn lowering_records_match_shader_uint4_layouts() {
        assert_eq!(std::mem::size_of::<SemanticLirCore>(), 16);
        assert_eq!(std::mem::size_of::<SemanticLirOperands>(), 16);
        assert_eq!(std::mem::size_of::<SemanticLirSchedule>(), 16);
        assert_eq!(std::mem::size_of::<SemanticLirPage>(), 16);
        assert_eq!(std::mem::size_of::<LirDispatchArgs>(), 16);
        assert_eq!(std::mem::size_of::<SemanticLirFunction>(), 48);
        assert_eq!(std::mem::size_of::<SemanticLirParam>(), 16);
        assert_eq!(std::mem::size_of::<SemanticLirLocal>(), 16);
        assert_eq!(std::mem::size_of::<LoweringStatus>(), 16);
        assert_eq!(std::mem::size_of::<TargetScheduleKey>(), 16);
        assert_eq!(std::mem::size_of::<TargetLirFunction>(), 16);
        assert_eq!(std::mem::size_of::<X86LirCore>(), 16);
        assert_eq!(std::mem::size_of::<X86LirOperands>(), 16);
        assert_eq!(std::mem::size_of::<WasmLirInstruction>(), 16);
        assert_eq!(std::mem::size_of::<WasmLirOperands>(), 16);
        assert_eq!(std::mem::size_of::<WasmLirFunction>(), 56);
        assert_eq!(std::mem::size_of::<WasmModuleLayout>(), 64);
    }

    #[test]
    fn generated_opcode_contract_uses_wasm_primary_opcode_values() {
        assert_eq!(opcode::SEMANTIC_LIR_OP_CONST_I32, 1);
        assert_eq!(opcode::WASM_LIR_OP_RETURN, 0x0f);
        assert_eq!(opcode::WASM_LIR_OP_I32_CONST, 0x41);
    }

    #[test]
    fn both_target_graphs_have_common_semantic_lowering_and_target_output() {
        let capacities = LoweringCapacities {
            source_bytes: 48,
            tokens: 48,
            hir_nodes: 32,
            semantic_instructions: 64,
            call_arguments: 16,
            parameters: 16,
            aggregate_elements: 16,
            target_instructions: 96,
            artifact_bytes: 1024,
        };
        for (target, target_pass, output) in [
            (
                LoweringTarget::X86_64,
                "lir.x86.scatter",
                "artifact.x86.bytes",
            ),
            (
                LoweringTarget::Wasm,
                "lir.wasm.scatter",
                "artifact.wasm.bytes",
            ),
        ] {
            let graph = lowering_compiler_graph(capacities, target).unwrap();
            assert_eq!(graph.repeated_regions().len(), 2);
            assert!(graph.repeated_regions().iter().any(|region| {
                region.iterations == 3
                    && region.pass_count == 2
                    && graph.passes()[region.first_pass.index()].name
                        == "lir.semantic.execution_rank.step_a_to_b"
            }));
            assert!(graph.repeated_regions().iter().any(|region| {
                region.iterations == 8
                    && region.pass_count == 12
                    && graph.passes()[region.first_pass.index()].name
                        == "lir.semantic.schedule.histogram.even"
            }));
            assert!(
                graph
                    .passes()
                    .iter()
                    .any(|pass| pass.name == "lir.semantic.scatter")
            );
            assert!(graph.passes().iter().any(|pass| pass.name == target_pass));
            assert!(
                graph
                    .resources()
                    .iter()
                    .any(|resource| resource.name == output)
            );
        }
    }

    #[test]
    fn semantic_lowering_entrypoints_match_graph_access_contracts() {
        let graph = lowering_compiler_graph(
            LoweringCapacities {
                source_bytes: 48,
                tokens: 48,
                hir_nodes: 32,
                semantic_instructions: 32,
                call_arguments: 16,
                parameters: 16,
                aggregate_elements: 16,
                target_instructions: 64,
                artifact_bytes: 512,
            },
            LoweringTarget::Wasm,
        )
        .unwrap();
        for (pass_name, artifact) in [
            ("lir.status.clear", "codegen/lir/status_clear"),
            ("lir.semantic.project", "codegen/lir/semantic/project"),
            (
                "lir.semantic.execution_rank.init",
                "codegen/lir/semantic/execution_rank_init",
            ),
            (
                "lir.semantic.execution_rank.step_a_to_b",
                "codegen/lir/semantic/execution_rank_step",
            ),
            (
                "lir.semantic.execution_rank.step_b_to_a",
                "codegen/lir/semantic/execution_rank_step",
            ),
            ("lir.semantic.count", "codegen/lir/semantic/count"),
            (
                "lir.semantic.scan.local",
                "type_checker/counted/scan/00_local",
            ),
            (
                "lir.semantic.scan.hierarchy_up",
                "type_checker/counted/scan/01_hierarchy_up",
            ),
            (
                "lir.semantic.scan.hierarchy_down",
                "type_checker/counted/scan/02_hierarchy_down",
            ),
            (
                "lir.semantic.scan.apply",
                "type_checker/counted/scan/02_apply",
            ),
            ("lir.semantic.scatter", "codegen/lir/semantic/scatter"),
            ("lir.semantic.validate", "codegen/lir/semantic/validate"),
            (
                "lir.semantic.call_arg_ranges.clear",
                "codegen/lir/semantic/call_arg_ranges_clear",
            ),
            ("lir.semantic.call_args", "codegen/lir/semantic/call_args"),
            (
                "lir.semantic.call_arg_ranges.finalize",
                "codegen/lir/semantic/call_arg_ranges_finalize",
            ),
        ] {
            let reflection = crate::reflection::parse_reflection_from_file(
                crate::shader_artifacts::artifact_path(&format!("{artifact}.reflect.json")),
            )
            .unwrap();
            graph
                .validate_pass_reflection(graph.pass_id(pass_name).unwrap(), &reflection)
                .unwrap();
        }
    }

    #[test]
    fn wasm_target_entrypoints_match_graph_access_contracts() {
        let graph = lowering_compiler_graph(
            LoweringCapacities {
                source_bytes: 48,
                tokens: 48,
                hir_nodes: 32,
                semantic_instructions: 32,
                call_arguments: 16,
                parameters: 16,
                aggregate_elements: 16,
                target_instructions: 64,
                artifact_bytes: 512,
            },
            LoweringTarget::Wasm,
        )
        .unwrap();
        for (pass_name, artifact) in [
            ("lir.wasm.count", "codegen/lir/wasm/count"),
            (
                "lir.target.count_scan.local",
                "type_checker/counted/scan/00_local",
            ),
            (
                "lir.target.count_scan.hierarchy_up",
                "type_checker/counted/scan/01_hierarchy_up",
            ),
            (
                "lir.target.count_scan.hierarchy_down",
                "type_checker/counted/scan/02_hierarchy_down",
            ),
            (
                "lir.target.count_scan.apply",
                "type_checker/counted/scan/02_apply",
            ),
            ("lir.wasm.scatter", "codegen/lir/wasm/scatter"),
            ("lir.wasm.validate", "codegen/lir/wasm/validate"),
            (
                "lir.wasm.schedule.function_ids",
                "codegen/lir/wasm/materialize_function_ids",
            ),
            ("lir.target.functions.mark", "codegen/lir/functions/mark"),
            (
                "lir.target.function_scan.local",
                "type_checker/counted/scan/00_local",
            ),
            (
                "lir.target.function_scan.hierarchy_up",
                "type_checker/counted/scan/01_hierarchy_up",
            ),
            (
                "lir.target.function_scan.hierarchy_down",
                "type_checker/counted/scan/02_hierarchy_down",
            ),
            (
                "lir.target.function_scan.apply",
                "type_checker/counted/scan/02_apply",
            ),
            (
                "lir.target.functions.scatter_starts",
                "codegen/lir/functions/scatter_starts",
            ),
            (
                "lir.target.functions.finalize",
                "codegen/lir/functions/finalize",
            ),
            ("lir.wasm.byte_count", "codegen/lir/wasm/byte_count"),
            (
                "lir.target.byte_scan.local",
                "type_checker/counted/scan/00_local",
            ),
            (
                "lir.target.byte_scan.hierarchy_up",
                "type_checker/counted/scan/01_hierarchy_up",
            ),
            (
                "lir.target.byte_scan.hierarchy_down",
                "type_checker/counted/scan/02_hierarchy_down",
            ),
            (
                "lir.target.byte_scan.apply",
                "type_checker/counted/scan/02_apply",
            ),
            ("lir.wasm.emit", "codegen/lir/wasm/emit"),
        ] {
            let reflection = crate::reflection::parse_reflection_from_file(
                crate::shader_artifacts::artifact_path(&format!("{artifact}.reflect.json")),
            )
            .unwrap();
            graph
                .validate_pass_reflection(graph.pass_id(pass_name).unwrap(), &reflection)
                .unwrap();
        }
    }

    #[test]
    fn x86_target_lir_entrypoints_match_graph_access_contracts() {
        let graph = lowering_compiler_graph(
            LoweringCapacities {
                source_bytes: 48,
                tokens: 48,
                hir_nodes: 32,
                semantic_instructions: 32,
                call_arguments: 16,
                parameters: 16,
                aggregate_elements: 16,
                target_instructions: 64,
                artifact_bytes: 512,
            },
            LoweringTarget::X86_64,
        )
        .unwrap();
        for (pass_name, artifact) in [
            ("lir.x86.count", "codegen/lir/x86/count"),
            (
                "lir.target.count_scan.local",
                "type_checker/counted/scan/00_local",
            ),
            (
                "lir.target.count_scan.hierarchy_up",
                "type_checker/counted/scan/01_hierarchy_up",
            ),
            (
                "lir.target.count_scan.hierarchy_down",
                "type_checker/counted/scan/02_hierarchy_down",
            ),
            (
                "lir.target.count_scan.apply",
                "type_checker/counted/scan/02_apply",
            ),
            ("lir.x86.scatter", "codegen/lir/x86/scatter"),
            ("lir.x86.validate", "codegen/lir/x86/validate"),
            ("lir.x86.resolve", "codegen/lir/x86/resolve"),
            ("lir.target.functions.mark", "codegen/lir/functions/mark"),
            (
                "lir.target.function_scan.local",
                "type_checker/counted/scan/00_local",
            ),
            (
                "lir.target.function_scan.hierarchy_up",
                "type_checker/counted/scan/01_hierarchy_up",
            ),
            (
                "lir.target.function_scan.hierarchy_down",
                "type_checker/counted/scan/02_hierarchy_down",
            ),
            (
                "lir.target.function_scan.apply",
                "type_checker/counted/scan/02_apply",
            ),
            (
                "lir.target.functions.scatter_starts",
                "codegen/lir/functions/scatter_starts",
            ),
            (
                "lir.target.functions.finalize",
                "codegen/lir/functions/finalize",
            ),
            (
                "lir.x86.decl_slots.clear",
                "codegen/lir/x86/decl_slots_clear",
            ),
            (
                "lir.x86.decl_slots.scatter",
                "codegen/lir/x86/decl_slots_scatter",
            ),
            ("lir.x86.byte_count", "codegen/lir/x86/byte_count"),
            (
                "lir.target.byte_scan.local",
                "type_checker/counted/scan/00_local",
            ),
            (
                "lir.target.byte_scan.hierarchy_up",
                "type_checker/counted/scan/01_hierarchy_up",
            ),
            (
                "lir.target.byte_scan.hierarchy_down",
                "type_checker/counted/scan/02_hierarchy_down",
            ),
            (
                "lir.target.byte_scan.apply",
                "type_checker/counted/scan/02_apply",
            ),
            (
                "lir.x86.entrypoint.clear",
                "codegen/lir/x86/entrypoint_clear",
            ),
            (
                "lir.x86.entrypoint.reduce",
                "codegen/lir/x86/entrypoint_reduce",
            ),
            ("lir.x86.artifact.layout", "codegen/lir/x86/artifact_layout"),
            ("lir.x86.artifact.clear", "codegen/lir/x86/artifact_clear"),
            ("lir.x86.emit", "codegen/lir/x86/emit"),
        ] {
            let reflection = crate::reflection::parse_reflection_from_file(
                crate::shader_artifacts::artifact_path(&format!("{artifact}.reflect.json")),
            )
            .unwrap();
            graph
                .validate_pass_reflection(graph.pass_id(pass_name).unwrap(), &reflection)
                .unwrap();
        }
    }
}
