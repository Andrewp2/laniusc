//! GPU-resident type checking and semantic metadata retention.
//!
//! The type checker records compute passes over token and parser HIR buffers
//! rather than walking an AST on the host. It builds module, name,
//! type-instance, call, method, visibility, predicate, and backend metadata
//! relations on the GPU, then exposes retained buffers to backend phases only
//! through explicit wrapper structs. The maintainer guide for pass-family
//! ownership and resident cache invariants lives in
//! `docs/compiler/type-checker.md`.

use std::{
    collections::HashMap,
    hash::{Hash, Hasher},
    sync::Mutex,
};

mod bind_groups;
mod bind_models;
mod bind_support;
mod compiler_graph;
mod dependency_interface;
mod module_path;
mod operations;
mod params;
mod preflight;
mod record;
mod resident;
mod semantic_interface;
pub use semantic_interface::RecordedSemanticInterface;
mod util;

use anyhow::Result;
use bind_models::*;
use bind_support::*;
pub(crate) use dependency_interface::{GpuDependencyInterfacePages, GpuDependencyInterfaceState};
use module_path::*;
use operations::*;
use params::*;
use record::*;
use util::*;
use wgpu::util::DeviceExt;

use crate::gpu::{
    buffers::{
        LaniusBuffer,
        TrackedBufferView,
        storage_ro_from_bytes,
        storage_ro_from_u32s,
        uniform_from_val,
    },
    compiler_graph::{CompilerGraphBindings, PrefixScanWorkspace},
    device,
    kernels::KernelRegistry,
    operations::{
        HierarchicalRadixSortDefinition,
        HierarchicalRadixSortDispatch,
        HierarchicalRadixSortKernels,
        PrefixScanOperation,
        RadixDispatchDomain,
        RadixSortBatchItem,
        RadixSortDefinition,
        RadixSortDispatch,
        RadixSortKernels,
        RadixSortOperation,
        RadixSortPairDefinition,
        RadixSortPlan,
        RadixSortResources,
        record_radix_sort_batch,
    },
    passes_core::{
        DispatchDim,
        InputElements,
        PassData,
        count_recorded_compute_pass,
        plan_workgroups,
        recorded_compute_pass_count,
        reset_recorded_compute_pass_count,
    },
    resource_registry::{
        ResourceMap,
        reflected_bind_group_from_resources,
        reflected_bind_group_with_overrides,
        typed_buffer_from_resources,
    },
    scan::{PrefixScanHierarchyParams, PrefixScanParams},
};

/// Semantic rejection classes reported by GPU type-check status words.
///
/// The numeric mapping is owned by GPU status buffers and shader constants.
/// Host diagnostics should preserve the source token or HIR row that made the
/// rejection user-visible.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GpuTypeCheckCode {
    UnknownType,
    UnresolvedIdent,
    AssignMismatch,
    ReturnMismatch,
    ConditionType,
    BadHir,
    LoopControl,
    InvalidMemberAccess,
    InvalidArrayReturn,
    CallMismatch,
    NameLimit,
    ImportCycle,
    TraitBoundUnsatisfied,
    TraitBoundAmbiguous,
    UnresolvedImport,
    UnsupportedImport,
    DuplicateModule,
    InvalidModulePath,
    Unknown(u32),
}

impl GpuTypeCheckCode {
    fn from_u32(value: u32) -> Self {
        match value {
            1 => Self::UnknownType,
            2 => Self::UnresolvedIdent,
            3 => Self::AssignMismatch,
            4 => Self::ReturnMismatch,
            5 => Self::ConditionType,
            6 => Self::BadHir,
            7 => Self::LoopControl,
            8 => Self::InvalidMemberAccess,
            9 => Self::InvalidArrayReturn,
            10 => Self::CallMismatch,
            11 => Self::NameLimit,
            12 => Self::ImportCycle,
            13 => Self::TraitBoundUnsatisfied,
            14 => Self::TraitBoundAmbiguous,
            15 => Self::UnresolvedImport,
            16 => Self::UnsupportedImport,
            18 => Self::DuplicateModule,
            20 => Self::InvalidModulePath,
            other => Self::Unknown(other),
        }
    }

    fn description(self) -> String {
        match self {
            Self::UnknownType => "unknown type".to_string(),
            Self::UnresolvedIdent => "unresolved identifier".to_string(),
            Self::AssignMismatch => "type mismatch".to_string(),
            Self::ReturnMismatch => "return type mismatch".to_string(),
            Self::ConditionType => "condition has the wrong type".to_string(),
            Self::BadHir => "invalid syntax or lowered syntax tree".to_string(),
            Self::LoopControl => "invalid loop control".to_string(),
            Self::InvalidMemberAccess => "invalid member access".to_string(),
            Self::InvalidArrayReturn => "invalid array return".to_string(),
            Self::CallMismatch => "call does not match a resolved function or method".to_string(),
            Self::NameLimit => "name is outside the current compiler limit".to_string(),
            Self::ImportCycle => "import cycle".to_string(),
            Self::TraitBoundUnsatisfied => "unsatisfied trait bound".to_string(),
            Self::TraitBoundAmbiguous => "ambiguous trait bound".to_string(),
            Self::UnresolvedImport => "unresolved import".to_string(),
            Self::UnsupportedImport => "unsupported import form".to_string(),
            Self::DuplicateModule => "duplicate module declaration".to_string(),
            Self::InvalidModulePath => "invalid module path".to_string(),
            Self::Unknown(code) => format!("unknown type-check error (code {code})"),
        }
    }
}

/// Error returned after a recorded type-check pass sequence is finished.
#[derive(Debug)]
pub enum GpuTypeCheckError {
    /// The GPU status buffer rejected the program and supplied a token/code
    /// tuple for host-side diagnostic mapping.
    Rejected {
        token: u32,
        code: GpuTypeCheckCode,
        detail: u32,
    },
    /// GPU setup, submission, or readback failed before semantic status could
    /// be decoded.
    Gpu(anyhow::Error),
}

/// Compact HIR plus the explicitly scoped upstream workspace consumed by the
/// current type-check recording path.
///
/// This value is borrowed for the duration of a recorded check. Anything
/// needed after parser resident buffers are released must be read from `hir`.
#[derive(Clone, Copy)]
pub struct GpuTypeCheckHirItemBuffers<'a> {
    /// Host-visible semantic feature summary measured by the GPU parser.
    pub parser_feature_flags: u32,
    /// Token-bounded upper capacity for compact module/path record families.
    pub module_record_capacity: u32,
    /// GPU-counted compact local parameters plus the dependency-parameter
    /// upper bound of one row per compact call argument.
    pub call_param_row_capacity: u32,
    /// Token-bounded upper capacity for compact call-argument rows.
    pub call_arg_row_capacity: u32,
    /// The parser's compact semantic artifact. Keeping this as one typed view
    /// preserves allocation identity for compiler-graph validation and makes
    /// it impossible for type-check code to assemble a partial HIR from raw
    /// parser rows.
    pub hir: &'a crate::parser::buffers::GpuHirView,
    /// Dead parser-phase storage available to the type-check graph's slot
    /// allocator. These buffers contain no semantic input at this boundary.
    pub upstream_workspace: &'a [crate::gpu::buffers::TrackedBufferView<'a>],
}

impl std::fmt::Display for GpuTypeCheckError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GpuTypeCheckError::Rejected { code, .. } => {
                write!(f, "type check error: {}", code.description())
            }
            GpuTypeCheckError::Gpu(_) => {
                f.write_str("type-check execution failed before semantic status could be decoded")
            }
        }
    }
}

impl std::error::Error for GpuTypeCheckError {}

#[cfg(test)]
mod tests {
    use super::{GpuTypeCheckCode, GpuTypeCheckError};

    #[test]
    fn type_check_error_display_is_user_facing() {
        let error = GpuTypeCheckError::Rejected {
            token: 12,
            code: GpuTypeCheckCode::UnknownType,
            detail: 7,
        };

        let message = error.to_string();
        assert_eq!(message, "type check error: unknown type");
        assert!(!message.contains("GPU"));
        assert!(!message.contains("near token"));
        assert!(!message.contains("status token"));
    }

    #[test]
    fn type_check_gpu_error_display_omits_backend_detail() {
        let error = GpuTypeCheckError::Gpu(anyhow::anyhow!(
            "typecheck.modules.projected_refs status readback failed"
        ));

        let message = error.to_string();
        assert_eq!(
            message,
            "type-check execution failed before semantic status could be decoded"
        );
        assert!(!message.contains("projected_refs"));
        assert!(!message.contains("readback"));
        assert!(!message.contains("GPU"));
    }
}

impl From<anyhow::Error> for GpuTypeCheckError {
    fn from(err: anyhow::Error) -> Self {
        Self::Gpu(err)
    }
}

/// GPU type-check driver and resident state cache.
///
/// A `GpuTypeChecker` owns pass pipelines, the main status buffer, and reusable
/// resident bind groups/scratch storage. Callers record type-check work into an
/// existing command encoder and finish it after submission/readback.
pub struct GpuTypeChecker {
    passes: TypeCheckPasses,
    params_buf: LaniusBuffer<TypeCheckParams>,
    status_buf: LaniusBuffer<u32>,
    status_readback: LaniusBuffer<u32>,
    resident_workspace: Mutex<Option<ResidentTypeCheckWorkspace>>,
    current_semantic_artifact: Mutex<Option<OwnedGpuSemanticArtifact>>,
}

/// Marker returned when type-check work has been recorded into a command
/// encoder and must still be submitted/read back by the caller.
pub struct RecordedTypeCheck {}

#[derive(Clone, Copy)]
struct ResidentTypeCheckCacheKey {
    source_byte_capacity: u32,
    source_file_capacity: u32,
    token_capacity: u32,
    hir_node_capacity: u32,
    parser_hir_node_capacity: u32,
    module_record_capacity: u32,
    call_param_row_capacity: u32,
    call_arg_row_capacity: u32,
    parser_feature_flags: u32,
    input_fingerprint: u64,
}

impl ResidentTypeCheckCacheKey {
    fn covers(self, required: Self) -> bool {
        self.input_fingerprint == required.input_fingerprint
            && self.source_byte_capacity >= required.source_byte_capacity
            && self.source_file_capacity >= required.source_file_capacity
            && self.token_capacity >= required.token_capacity
            && self.hir_node_capacity >= required.hir_node_capacity
            && self.parser_hir_node_capacity >= required.parser_hir_node_capacity
            && self.module_record_capacity >= required.module_record_capacity
            && self.call_param_row_capacity >= required.call_param_row_capacity
            && self.call_arg_row_capacity >= required.call_arg_row_capacity
            && self.parser_feature_flags & required.parser_feature_flags
                == required.parser_feature_flags
    }
}

struct TypeSemanticBuffers {
    row_by_token: LaniusBuffer<u32>,
    scan_input: LaniusBuffer<u32>,
    prefix: LaniusBuffer<u32>,
    count_out: LaniusBuffer<u32>,
    row_by_ordinal: LaniusBuffer<u32>,
}

struct TypeSubtreeCompareBuffers {
    scan_input: LaniusBuffer<u32>,
    prefix: LaniusBuffer<u32>,
    count_out: LaniusBuffer<u32>,
    left_root: LaniusBuffer<u32>,
    right_root: LaniusBuffer<u32>,
    error_token: LaniusBuffer<u32>,
    error_detail: LaniusBuffer<u32>,
    dispatch_args: LaniusBuffer<u32>,
    dispatch_params: LaniusBuffer<CountDispatchParams>,
}

/// Type checking uses the compiler-wide kernel registry.  Artifact keys are
/// the kernel identity; semantic graph-node names remain invocation identity.
type TypeCheckPasses = KernelRegistry;

// Resident type-checking keeps buffers and bind groups in this owner so GPU
// resources stay alive across the retained pipeline even when a field is only
// consumed indirectly by a reflected bind group.
struct ResidentTypeCheckWorkspace {
    resettable_buffers: Vec<crate::gpu::buffers::ResettableBuffer>,
    cache_key: ResidentTypeCheckCacheKey,
    typecheck_graph: compiler_graph::TypeCheckCompilerGraph,
    compact_expr_scalar_type_init: wgpu::BindGroup,
    compact_expr_scalar_type_steps: Vec<wgpu::BindGroup>,
    name_capacity: u32,
    if_depth_n_blocks: u32,
    fn_n_blocks: u32,
    if_depth_params: LaniusBuffer<IfDepthParams>,
    fn_params: LaniusBuffer<FnContextParams>,
    language_symbol_bytes: LaniusBuffer<u8>,
    _language_name_id: LaniusBuffer<u32>,
    name_order_in: LaniusBuffer<u32>,
    name_order_tmp: LaniusBuffer<u32>,
    name_id_by_token: LaniusBuffer<u32>,
    module_path: ModulePathState,
    visible_decl: LaniusBuffer<u32>,
    visible_type: LaniusBuffer<u32>,
    token_active_dispatch_args: LaniusBuffer<u32>,
    hir_active_dispatch_args: LaniusBuffer<u32>,
    token_hir_active_dispatch_args: LaniusBuffer<u32>,
    hir_active_dispatch: wgpu::BindGroup,
    semantic_features: SemanticFeaturesOperation,
    type_instance_decl_token: LaniusBuffer<u32>,
    _type_instance_aggregate_word_count: LaniusBuffer<u32>,
    _call_dependency_library_id: LaniusBuffer<u32>,
    _call_dependency_unit_id: LaniusBuffer<u32>,
    _call_dependency_local_index: LaniusBuffer<u32>,
    _call_dependency_host_service: LaniusBuffer<u32>,
    type_subtree_compare_buffers: Box<TypeSubtreeCompareBuffers>,
    name_bind_groups: NameBindGroups,
    language_name_bind_groups: LanguageNameBindGroups,
    if_depth_bind_groups: IfDepthBindGroups,
    fn_context_bind_groups: FnContextBindGroups,
    visible_bind_groups: VisibleBindGroups,
    calls: CallBindGroups,
    methods: MethodBindGroups,
    predicates: PredicateBindGroups,
    type_instances: TypeInstanceBindGroups,
    returns: ReturnValidationOperation,
    predicate_diagnostics: PredicateDiagnosticsOperation,
    conditions_compact_expr: wgpu::BindGroup,
    conditions_compact_stmt: wgpu::BindGroup,
    condition_finalization: ConditionFinalizationOperation,
    conditions_compact_aggregate_requests: wgpu::BindGroup,
    semantic_expression_refs_project: wgpu::BindGroup,
    semantic_struct_literal_refs_project: wgpu::BindGroup,
    semantic_array_index_refs_project: wgpu::BindGroup,
    semantic_calls_project: wgpu::BindGroup,
    semantic_artifact_project: wgpu::BindGroup,
    aggregate_compare_scan: PrefixScanOperation,
    aggregate_compare_dispatch: wgpu::BindGroup,
    conditions_aggregate_args: wgpu::BindGroup,
    type_subtree_compare_scan: Box<PrefixScanOperation>,
    type_subtree_compare_dispatch: Box<wgpu::BindGroup>,
    conditions_type_subtree: Box<wgpu::BindGroup>,
    scope_hir: wgpu::BindGroup,
}

impl ResidentTypeCheckWorkspace {
    fn clear_job_storage(&self, encoder: &mut wgpu::CommandEncoder) {
        for buffer in &self.resettable_buffers {
            if buffer.byte_size == 0 {
                continue;
            }
            debug_assert_eq!(buffer.byte_size % wgpu::COPY_BUFFER_ALIGNMENT, 0);
            encoder.clear_buffer(&buffer.buffer, 0, None);
        }
    }

    fn can_reuse_for(&self, key: ResidentTypeCheckCacheKey) -> bool {
        self.cache_key.covers(key)
    }

    fn semantic_artifact(&self) -> Result<OwnedGpuSemanticArtifact> {
        let graph = &self.typecheck_graph;
        Ok(OwnedGpuSemanticArtifact {
            value_decl_by_hir: graph.buffer("semantic_value_decl_by_hir")?,
            value_type_by_hir: graph.buffer("semantic_value_type_by_hir")?,
            value_const_by_hir: graph.buffer("semantic_value_const_by_hir")?,
            value_const_present_by_hir: graph.buffer("semantic_value_const_present_by_hir")?,
            param_type_by_row: graph.buffer("semantic_param_type_by_row")?,
            enclosing_fn_by_hir: graph.buffer("semantic_enclosing_fn_by_hir")?,
            function_return_type_by_hir: graph.buffer("semantic_function_return_type_by_hir")?,
            function_entrypoint_by_hir: graph.buffer("semantic_function_entrypoint_by_hir")?,
            function_host_service_by_hir: graph.buffer("semantic_function_host_service_by_hir")?,
            control_depth_by_hir: graph.buffer("semantic_control_depth_by_hir")?,
            calls_by_hir: graph.buffer("semantic_calls_by_hir")?,
            expr_ref_tag_by_hir: graph.buffer("semantic_expr_ref_tag_by_hir")?,
            expr_ref_payload_by_hir: graph.buffer("semantic_expr_ref_payload_by_hir")?,
            aggregate_decl_token_by_hir: graph.buffer("semantic_aggregate_decl_token_by_hir")?,
            aggregate_word_count_by_hir: graph.buffer("semantic_aggregate_word_count_by_hir")?,
            array_length_by_hir: graph.buffer("semantic_array_length_by_hir")?,
            member_field_ordinal_by_hir: graph.buffer("semantic_member_field_ordinal_by_hir")?,
            iterable_kind_by_hir: graph.buffer("semantic_iterable_kind_by_hir")?,
            function_result_word_count_by_hir: graph
                .buffer("semantic_function_result_word_count_by_hir")?,
            expr_scalar_type_by_hir: graph.buffer("semantic_expr_scalar_type_by_hir")?,
            public_decl_index_by_hir: self.module_path.interface_public_decl_index_by_hir.clone(),
            struct_init_field_ordinal_by_row: graph.buffer("struct_init_field_ordinal_by_row")?,
        })
    }
}

/// Typed allocation-preserving view used by the shared semantic lowering
/// stage. Keeping this narrow prevents the new backend boundary from
/// inheriting the legacy backend's token-indexed metadata surface.
#[derive(Clone, Copy)]
#[repr(C)]
#[derive(encase::ShaderType)]
pub(crate) struct GpuCheckedCallArtifact {
    pub target_token: u32,
    pub dependency_library_id: u32,
    pub dependency_unit_id: u32,
    pub dependency_local_index: u32,
    pub dependency_host_service: u32,
    pub intrinsic_tag: u32,
    pub return_type: u32,
    pub receiver_hir: u32,
    pub arg_count: u32,
    pub return_ref_tag: u32,
    pub return_ref_payload: u32,
    pub callable_kind: u32,
    pub callable_hir: u32,
    pub callable_ordinal: u32,
}

#[derive(Clone, Copy)]
pub(crate) struct GpuSemanticArtifactView<'a> {
    /// Resolved declaration identity for each compact HIR value row.
    pub value_decl_by_hir: &'a LaniusBuffer<u32>,
    /// Resolved type identity for each compact HIR value row.
    pub value_type_by_hir: &'a LaniusBuffer<u32>,
    /// Literal value bits for imported constant paths, keyed by dense HIR row.
    pub value_const_by_hir: &'a LaniusBuffer<u32>,
    /// Nonzero when the corresponding row names an imported constant.
    pub value_const_present_by_hir: &'a LaniusBuffer<u32>,
    /// Resolved type identity for each compact parameter row.
    pub param_type_by_row: &'a LaniusBuffer<u32>,
    /// Encoded enclosing compact-HIR function identity for each HIR row.
    pub enclosing_fn_by_hir: &'a LaniusBuffer<u32>,
    /// Checked return type keyed by dense function HIR row.
    pub function_return_type_by_hir: &'a LaniusBuffer<u32>,
    /// Checked entrypoint tag keyed by dense function HIR row.
    pub function_entrypoint_by_hir: &'a LaniusBuffer<u32>,
    /// Resolved runtime host-service identity keyed by dense function HIR row.
    pub function_host_service_by_hir: &'a LaniusBuffer<u32>,
    /// Structured-control nesting depth keyed by dense HIR row.
    pub control_depth_by_hir: &'a LaniusBuffer<u32>,
    /// Canonical checked call resolution keyed by call-expression HIR row.
    pub calls_by_hir: &'a LaniusBuffer<GpuCheckedCallArtifact>,
    /// Canonical checked type-reference tag keyed by dense expression HIR row.
    pub expr_ref_tag_by_hir: &'a LaniusBuffer<u32>,
    /// Canonical checked type-reference payload keyed by dense expression HIR row.
    pub expr_ref_payload_by_hir: &'a LaniusBuffer<u32>,
    /// Resolved declaration-name token for named aggregate expressions.
    pub aggregate_decl_token_by_hir: &'a LaniusBuffer<u32>,
    /// Checked aggregate ABI width keyed by dense expression HIR row.
    pub aggregate_word_count_by_hir: &'a LaniusBuffer<u32>,
    /// Checked fixed-array length keyed by dense expression HIR row.
    pub array_length_by_hir: &'a LaniusBuffer<u32>,
    /// Checked field ordinal keyed by dense member-expression HIR row.
    pub member_field_ordinal_by_hir: &'a LaniusBuffer<u32>,
    /// Checked iteration representation keyed by dense for-statement HIR row.
    pub iterable_kind_by_hir: &'a LaniusBuffer<u32>,
    /// Checked target-word width keyed by dense function HIR row.
    pub function_result_word_count_by_hir: &'a LaniusBuffer<u32>,
    /// Final scalar expression type after type-checker pointer jumping.
    pub expr_scalar_type_by_hir: &'a LaniusBuffer<u32>,
    /// Persisted public-declaration index keyed by dense compact HIR node.
    pub public_decl_index_by_hir: &'a LaniusBuffer<u32>,
    /// Canonical declaration-order ordinal for each compact literal-field row.
    pub struct_init_field_ordinal_by_row: &'a LaniusBuffer<u32>,
}

/// Independently owned compact semantic boundary for one checked unit.
///
/// Cloning these handles does not copy GPU data. It detaches artifact lifetime
/// from the mutex-protected resident type-check workspace, allowing frontend
/// scratch to be recolored or released without changing backend contracts.
#[derive(Clone)]
pub(crate) struct OwnedGpuSemanticArtifact {
    value_decl_by_hir: LaniusBuffer<u32>,
    value_type_by_hir: LaniusBuffer<u32>,
    value_const_by_hir: LaniusBuffer<u32>,
    value_const_present_by_hir: LaniusBuffer<u32>,
    param_type_by_row: LaniusBuffer<u32>,
    enclosing_fn_by_hir: LaniusBuffer<u32>,
    function_return_type_by_hir: LaniusBuffer<u32>,
    function_entrypoint_by_hir: LaniusBuffer<u32>,
    function_host_service_by_hir: LaniusBuffer<u32>,
    control_depth_by_hir: LaniusBuffer<u32>,
    calls_by_hir: LaniusBuffer<GpuCheckedCallArtifact>,
    expr_ref_tag_by_hir: LaniusBuffer<u32>,
    expr_ref_payload_by_hir: LaniusBuffer<u32>,
    aggregate_decl_token_by_hir: LaniusBuffer<u32>,
    aggregate_word_count_by_hir: LaniusBuffer<u32>,
    array_length_by_hir: LaniusBuffer<u32>,
    member_field_ordinal_by_hir: LaniusBuffer<u32>,
    iterable_kind_by_hir: LaniusBuffer<u32>,
    function_result_word_count_by_hir: LaniusBuffer<u32>,
    expr_scalar_type_by_hir: LaniusBuffer<u32>,
    public_decl_index_by_hir: LaniusBuffer<u32>,
    struct_init_field_ordinal_by_row: LaniusBuffer<u32>,
}

impl OwnedGpuSemanticArtifact {
    pub(crate) fn view(&self) -> GpuSemanticArtifactView<'_> {
        GpuSemanticArtifactView {
            value_decl_by_hir: &self.value_decl_by_hir,
            value_type_by_hir: &self.value_type_by_hir,
            value_const_by_hir: &self.value_const_by_hir,
            value_const_present_by_hir: &self.value_const_present_by_hir,
            param_type_by_row: &self.param_type_by_row,
            enclosing_fn_by_hir: &self.enclosing_fn_by_hir,
            function_return_type_by_hir: &self.function_return_type_by_hir,
            function_entrypoint_by_hir: &self.function_entrypoint_by_hir,
            function_host_service_by_hir: &self.function_host_service_by_hir,
            control_depth_by_hir: &self.control_depth_by_hir,
            calls_by_hir: &self.calls_by_hir,
            expr_ref_tag_by_hir: &self.expr_ref_tag_by_hir,
            expr_ref_payload_by_hir: &self.expr_ref_payload_by_hir,
            aggregate_decl_token_by_hir: &self.aggregate_decl_token_by_hir,
            aggregate_word_count_by_hir: &self.aggregate_word_count_by_hir,
            array_length_by_hir: &self.array_length_by_hir,
            member_field_ordinal_by_hir: &self.member_field_ordinal_by_hir,
            iterable_kind_by_hir: &self.iterable_kind_by_hir,
            function_result_word_count_by_hir: &self.function_result_word_count_by_hir,
            expr_scalar_type_by_hir: &self.expr_scalar_type_by_hir,
            public_decl_index_by_hir: &self.public_decl_index_by_hir,
            struct_init_field_ordinal_by_row: &self.struct_init_field_ordinal_by_row,
        }
    }
}

/// Borrowed GPU tables required to canonicalize a bounded unit's public
/// semantic interface. Source bytes and parser-owned signature/member tables
/// are supplied separately by the compiler orchestration layer.
#[derive(Clone, Copy)]
pub struct GpuSemanticInterfaceIdentityBuffers<'a> {
    /// Logical row capacities are kept separately from the physical WGPU
    /// buffers.  A graph workspace may alias a larger dead allocation for a
    /// smaller logical resource, so `wgpu::Buffer::size()` is not a valid
    /// source of semantic-domain bounds.
    pub name_capacity: u32,
    pub module_capacity: u32,
    pub declaration_capacity: u32,
    pub module_segment_capacity: u32,
    pub name_count_out: &'a wgpu::Buffer,
    pub name_spans: &'a wgpu::Buffer,
    pub name_hash_lo: &'a wgpu::Buffer,
    pub name_hash_hi: &'a wgpu::Buffer,
    pub name_id_by_token: &'a wgpu::Buffer,
    pub language_symbol_bytes: &'a wgpu::Buffer,
    pub module_count_out: &'a wgpu::Buffer,
    pub module_key_segment_count: &'a wgpu::Buffer,
    pub module_key_segment_base: &'a wgpu::Buffer,
    pub module_key_segment_name_id: &'a wgpu::Buffer,
    pub decl_count_out: &'a wgpu::Buffer,
    pub decl_module_id: &'a wgpu::Buffer,
    pub decl_name_id: &'a wgpu::Buffer,
    pub decl_kind: &'a wgpu::Buffer,
    pub decl_namespace: &'a wgpu::Buffer,
    pub decl_visibility: &'a wgpu::Buffer,
    pub decl_parent_type_decl: &'a wgpu::Buffer,
    pub decl_hir_node: &'a wgpu::Buffer,
    /// Runtime host-service identity for an extern function declaration,
    /// keyed by its dense HIR row. Non-host declarations carry `u32::MAX`.
    pub function_host_service_by_hir: &'a wgpu::Buffer,
    pub public_decl_count: &'a wgpu::Buffer,
    pub public_decl_local_id: &'a wgpu::Buffer,
    pub public_decl_index_by_local: &'a wgpu::Buffer,
    pub public_decl_index_by_hir: &'a wgpu::Buffer,
    pub type_expr_ref_tag: &'a wgpu::Buffer,
    pub type_expr_ref_payload: &'a wgpu::Buffer,
    pub type_generic_param_slot_by_token: &'a wgpu::Buffer,
    pub type_const_param_slot_by_token: &'a wgpu::Buffer,
    pub type_instance_decl_token: &'a wgpu::Buffer,
    pub external_type_library_id: &'a wgpu::Buffer,
    pub external_type_unit_id: &'a wgpu::Buffer,
    pub external_type_local_index: &'a wgpu::Buffer,
    pub semantic_type_ref_tag_by_hir: &'a wgpu::Buffer,
    pub semantic_type_ref_payload_by_hir: &'a wgpu::Buffer,
    pub semantic_type_generic_param_slot_by_hir: &'a wgpu::Buffer,
    pub semantic_type_external_library_id_by_hir: &'a wgpu::Buffer,
    pub semantic_type_external_unit_id_by_hir: &'a wgpu::Buffer,
    pub semantic_type_external_local_index_by_hir: &'a wgpu::Buffer,
    pub resolved_dependency_library_id: &'a wgpu::Buffer,
    pub resolved_dependency_unit_id: &'a wgpu::Buffer,
    pub resolved_dependency_local_index: &'a wgpu::Buffer,
    pub path_id_by_owner_hir: &'a wgpu::Buffer,
    pub path_id_by_owner_token: &'a wgpu::Buffer,
    pub resolved_type_decl: &'a wgpu::Buffer,
    pub decl_id_by_name_token: &'a wgpu::Buffer,
    pub generic_param_count_out: &'a wgpu::Buffer,
    pub generic_param_owner_token: &'a wgpu::Buffer,
    pub generic_param_name_id: &'a wgpu::Buffer,
    pub generic_param_token: &'a wgpu::Buffer,
    pub generic_param_kind: &'a wgpu::Buffer,
    pub type_decl_generic_param_count_by_owner_token: &'a wgpu::Buffer,
    pub type_decl_const_param_count_by_owner_token: &'a wgpu::Buffer,
}

/// Parser-owned checked HIR relations needed to discover the public signature
/// type forest without inspecting source text or function bodies.
#[derive(Clone, Copy)]
pub struct GpuSemanticInterfaceHirBuffers<'a> {
    /// Dense HIR capacity is a logical view over the parser-owned buffer;
    /// the physical allocation can be larger when workspace slots are reused.
    pub compact_hir_capacity: u32,
    pub compact_hir_count: &'a LaniusBuffer<u32>,
    pub compact_hir_core: &'a LaniusBuffer<crate::parser::buffers::HirCore>,
    pub compact_hir_payload: &'a LaniusBuffer<crate::parser::buffers::HirPayload>,
    pub compact_const_value: &'a LaniusBuffer<u32>,
    pub compact_fn_return_type: &'a LaniusBuffer<u32>,
    pub compact_type_alias_target: &'a LaniusBuffer<u32>,
    pub compact_const_type: &'a LaniusBuffer<u32>,
    pub compact_param_count: &'a LaniusBuffer<u32>,
    pub compact_params: &'a LaniusBuffer<crate::parser::buffers::HirParam>,
    pub compact_param_ranges: &'a LaniusBuffer<crate::parser::buffers::HirRange>,
    pub compact_type_arg_count: &'a LaniusBuffer<u32>,
    pub compact_type_args: &'a LaniusBuffer<crate::parser::buffers::HirTypeArg>,
    pub compact_type_arg_ranges: &'a LaniusBuffer<crate::parser::buffers::HirRange>,
    pub compact_generic_param_count: &'a LaniusBuffer<u32>,
    pub compact_generic_params: &'a LaniusBuffer<crate::parser::buffers::HirGenericParam>,
    pub compact_path_count: &'a LaniusBuffer<u32>,
    pub compact_paths: &'a LaniusBuffer<crate::parser::buffers::HirPath>,
    pub compact_path_segment_count: &'a LaniusBuffer<u32>,
    pub compact_path_segments: &'a LaniusBuffer<crate::parser::buffers::HirPathSegment>,
    pub compact_field_count: &'a LaniusBuffer<u32>,
    pub compact_fields: &'a LaniusBuffer<crate::parser::buffers::HirField>,
    pub compact_variant_count: &'a LaniusBuffer<u32>,
    pub compact_variants: &'a LaniusBuffer<crate::parser::buffers::HirVariant>,
    pub compact_variant_payload_count: &'a LaniusBuffer<u32>,
    pub compact_variant_payload_row_count: &'a LaniusBuffer<u32>,
    pub compact_variant_payloads: &'a LaniusBuffer<crate::parser::buffers::HirVariantPayload>,
    pub compact_method_count: &'a LaniusBuffer<u32>,
    pub compact_method_cores: &'a LaniusBuffer<crate::parser::buffers::HirMethodCore>,
    pub compact_method_signatures: &'a LaniusBuffer<crate::parser::buffers::HirMethodSignature>,
}
