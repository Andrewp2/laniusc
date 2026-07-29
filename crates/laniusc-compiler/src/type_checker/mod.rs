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
mod pass_loaders;
mod preflight;
mod record;
mod resident;
mod semantic_interface;
pub use semantic_interface::RecordedSemanticInterface;
mod util;

use anyhow::Result;
use bind_models::*;
use bind_support::*;
pub(crate) use dependency_interface::GpuDependencyInterfaceState;
use module_path::*;
use operations::*;
use params::*;
use record::*;
use util::*;
use wgpu::util::DeviceExt;

use crate::gpu::{
    buffers::{LaniusBuffer, storage_ro_from_bytes, storage_ro_from_u32s, uniform_from_val},
    compiler_graph::PrefixScanWorkspace,
    device,
    passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
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

/// Parser HIR buffers consumed by type-check recording.
///
/// These are borrowed for the duration of a recorded check. Any value required
/// after parser resident buffers are released must be cloned into an owned
/// retained wrapper before this struct is constructed.
#[derive(Clone, Copy)]
pub struct GpuTypeCheckHirItemBuffers<'a> {
    /// Host-visible semantic feature summary measured by the GPU parser.
    pub parser_feature_flags: u32,
    /// Exact GPU-counted upper bound for compact module/path record families.
    pub module_record_capacity: u32,
    /// GPU-counted compact local parameters plus the dependency-parameter
    /// upper bound of one row per compact call argument.
    pub call_param_row_capacity: u32,
    /// Exact GPU-counted number of compact call-argument rows.
    pub call_arg_row_capacity: u32,
    /// The parser's compact semantic artifact. Keeping this as one typed view
    /// preserves allocation identity for compiler-graph validation and makes
    /// it impossible for type-check code to assemble a partial HIR from raw
    /// parser rows.
    pub hir: &'a crate::parser::buffers::GpuHirView,
    /// Raw-parser to dense-HIR projection. This remains a typed allocation
    /// view so compiler-graph alias validation sees the parser workspace slot
    /// that physically backs it.
    pub raw_to_compact_hir: &'a LaniusBuffer<u32>,
    pub node_kind: &'a LaniusBuffer<u32>,
    pub parent: &'a LaniusBuffer<u32>,
    pub first_child: &'a LaniusBuffer<u32>,
    pub next_sibling: &'a LaniusBuffer<u32>,
    pub subtree_end: &'a LaniusBuffer<u32>,
    pub type_form: &'a LaniusBuffer<u32>,
    pub type_value_node: &'a LaniusBuffer<u32>,
    pub type_len_token: &'a LaniusBuffer<u32>,
    pub type_len_value: &'a LaniusBuffer<u32>,
    pub type_file_id: &'a LaniusBuffer<u32>,
    pub type_path_leaf_node: &'a LaniusBuffer<u32>,
    pub bound_path_owner_by_leaf: &'a LaniusBuffer<u32>,
    pub type_arg_start: &'a LaniusBuffer<u32>,
    pub type_arg_count: &'a LaniusBuffer<u32>,
    pub type_arg_next: &'a LaniusBuffer<u32>,
    pub type_root_owner: &'a LaniusBuffer<u32>,
    pub method_impl_receiver_type_node: &'a LaniusBuffer<u32>,
    pub expr_record: &'a LaniusBuffer<u32>,
    pub expr_name_role: &'a LaniusBuffer<u32>,
    pub expr_result_root_node: &'a LaniusBuffer<u32>,
    pub member_receiver_node: &'a LaniusBuffer<u32>,
    pub member_receiver_token: &'a LaniusBuffer<u32>,
    pub member_name_token: &'a LaniusBuffer<u32>,
    pub stmt_record: &'a LaniusBuffer<u32>,
    pub nearest_loop_node: &'a LaniusBuffer<u32>,
    pub nearest_fn_node: &'a LaniusBuffer<u32>,
    pub array_lit_context_stmt_node: &'a LaniusBuffer<u32>,
    pub array_element_parent_lit: &'a LaniusBuffer<u32>,
    pub nearest_array_element_node: &'a LaniusBuffer<u32>,
    pub struct_lit_head_node: &'a LaniusBuffer<u32>,
    pub struct_lit_context_stmt_node: &'a LaniusBuffer<u32>,
    pub struct_lit_field_parent_lit: &'a LaniusBuffer<u32>,
    pub struct_lit_field_value_node: &'a LaniusBuffer<u32>,
    pub semantic_dense_node: &'a LaniusBuffer<u32>,
    /// Compact semantic row count and navigation retain their allocation
    /// identities across the parser/typecheck phase boundary.
    pub semantic_count: &'a LaniusBuffer<u32>,
    pub semantic_subtree_end: &'a LaniusBuffer<u32>,
}

/// Scratch and metadata buffers supplied by the caller after earlier phase data
/// has been proven dead or intentionally retained.
///
/// Buffer identity is part of the resident type-check cache contract whenever a
/// pass binds one of these buffers. Add new bind-group-affecting buffers to the
/// resident fingerprint instead of erasing allocation identity at the phase
/// boundary.
#[derive(Clone, Copy)]
pub struct GpuTypeCheckExternalScratchBuffers<'a> {
    pub record_family_flag: Option<&'a LaniusBuffer<u32>>,
    pub path_id_by_owner_hir: crate::gpu::buffers::TrackedBufferView<'a>,
    pub decl_type_key_to_decl_id: crate::gpu::buffers::TrackedBufferView<'a>,
    pub decl_value_key_to_decl_id: crate::gpu::buffers::TrackedBufferView<'a>,
    pub resolved_type_decl: crate::gpu::buffers::TrackedBufferView<'a>,
    pub resolved_value_decl: crate::gpu::buffers::TrackedBufferView<'a>,
    pub resolved_type_status: crate::gpu::buffers::TrackedBufferView<'a>,
    pub resolved_value_status: crate::gpu::buffers::TrackedBufferView<'a>,
    pub path_start: crate::gpu::buffers::TrackedBufferView<'a>,
    pub path_len: crate::gpu::buffers::TrackedBufferView<'a>,
    pub path_segment_count: crate::gpu::buffers::TrackedBufferView<'a>,
    pub path_segment_base: crate::gpu::buffers::TrackedBufferView<'a>,
    pub path_segment_name_id: crate::gpu::buffers::TrackedBufferView<'a>,
    pub path_segment_token: crate::gpu::buffers::TrackedBufferView<'a>,
    pub path_owner_hir: crate::gpu::buffers::TrackedBufferView<'a>,
    pub path_owner_token: crate::gpu::buffers::TrackedBufferView<'a>,
    pub path_owner_module_id: crate::gpu::buffers::TrackedBufferView<'a>,
    pub path_kind: crate::gpu::buffers::TrackedBufferView<'a>,
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
    resident_state: Mutex<Option<ResidentTypeCheckState>>,
}

/// Marker returned when type-check work has been recorded into a command
/// encoder and must still be submitted/read back by the caller.
pub struct RecordedTypeCheck {
    debug_semantic_rows: Option<TypeCheckSemanticDebugReadback>,
}

struct TypeCheckSemanticDebugReadback {
    buffer: wgpu::Buffer,
    hir_rows: u32,
    token_rows: u32,
}

#[derive(Clone, Copy)]
struct ResidentTypeCheckCacheKey {
    source_file_capacity: u32,
    token_capacity: u32,
    hir_node_capacity: u32,
    parser_hir_node_capacity: u32,
    module_record_capacity: u32,
    call_param_row_capacity: u32,
    call_arg_row_capacity: u32,
    parser_feature_flags: u32,
    input_fingerprint: u64,
    uses_hir_items: bool,
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

struct TypeCheckPasses {
    interface_public_decls_clear: PassData,
    interface_public_decls_map: PassData,
    interface_type_topology_init: PassData,
    interface_type_topology_attach_unary: PassData,
    interface_type_topology_seed_declarations: PassData,
    interface_type_topology_seed_params: PassData,
    interface_type_topology_seed_fields: PassData,
    interface_type_topology_seed_variants: PassData,
    interface_type_topology_root_init: PassData,
    interface_type_topology_root_step: PassData,
    interface_type_topology_mark_reverse: PassData,
    interface_type_topology_scatter: PassData,
    interface_type_topology_validate: PassData,
    interface_type_topology_edge_counts: PassData,
    interface_type_topology_edge_scatter: PassData,
    interface_type_topology_resolve_local_decl: PassData,
    interface_type_topology_classify_path: PassData,
    interface_type_topology_type_records: PassData,
    interface_type_topology_array_lengths: PassData,
    interface_signature_flags: PassData,
    interface_signature_totals: PassData,
    interface_signature_direct_types: PassData,
    interface_signature_synthetic_types: PassData,
    interface_signature_param_edges: PassData,
    interface_signature_variant_payload_edges: PassData,
    interface_signature_return_edges: PassData,
    interface_members_variant_counts: PassData,
    interface_members_generic_counts: PassData,
    interface_members_counts: PassData,
    interface_members_scatter_hir: PassData,
    interface_members_scatter_generic: PassData,
    interface_members_normalize_types: PassData,
    interface_identity_sizes: PassData,
    interface_identity_records: PassData,
    interface_identity_bytes: PassData,
    hir_active_dispatch_args: PassData,
    semantic_features_collect: PassData,
    semantic_features_dispatch_args: PassData,
    expression_types_init: PassData,
    expression_types_step: PassData,
    semantic_calls_project: PassData,
    semantic_artifact_project: PassData,
    names_mark_lexemes: PassData,
    counted_scan_local: PassData,
    counted_scan_hierarchy_up: PassData,
    counted_scan_hierarchy_down: PassData,
    counted_scan_apply: PassData,
    count_dispatch_args: PassData,
    count_pair_max_dispatch_args: PassData,
    names_scatter_lexemes: PassData,
    names_hash_prepare: PassData,
    names_hash_insert: PassData,
    names_hash_assign_ids: PassData,
    names_radix_dispatch_args: PassData,
    names_radix_bucket_prefix: PassData,
    names_radix_bucket_bases: PassData,
    struct_field_radix_dispatch_args: PassData,
    struct_field_radix_bucket_local: PassData,
    struct_field_radix_bucket_chunks: PassData,
    struct_field_radix_bucket_apply: PassData,
    language_names_clear: PassData,
    language_type_codes_clear: PassData,
    language_decls_materialize: PassData,
    modules_mark_records: PassData,
    modules_count_record_candidates: PassData,
    modules_extract_record_flag: PassData,
    modules_scatter_paths: PassData,
    modules_count_path_segments: PassData,
    modules_scatter_path_segments: PassData,
    modules_clear_path_state: PassData,
    modules_path_prefix_dispatch_args: PassData,
    modules_path_prefix_table_clear: PassData,
    modules_path_prefix_table_insert: PassData,
    modules_path_prefix_table_lookup: PassData,
    modules_path_prefix_finalize: PassData,
    modules_scatter_module_records: PassData,
    modules_scatter_import_records: PassData,
    modules_scatter_decl_core_records: PassData,
    modules_append_variant_decl_count: PassData,
    modules_scatter_variant_decl_records: PassData,
    modules_clear_decl_lookup: PassData,
    modules_scatter_decl_span_records: PassData,
    modules_build_module_keys: PassData,
    modules_sort_module_keys_small: PassData,
    modules_sort_module_keys_histogram: PassData,
    modules_sort_module_keys_scatter: PassData,
    modules_validate_modules: PassData,
    dependencies: Box<DependencyPasses>,
    modules_resolve_imports: PassData,
    modules_seed_import_edge_key_order: PassData,
    modules_sort_import_edges_small: PassData,
    modules_sort_import_edges: PassData,
    modules_sort_import_edges_scatter: PassData,
    modules_validate_import_cycles: PassData,
    modules_clear_file_module_map: PassData,
    modules_build_file_module_map: PassData,
    modules_attach_record_modules: PassData,
    modules_seed_decl_key_order: PassData,
    modules_sort_decl_keys_small: PassData,
    modules_sort_decl_keys: PassData,
    modules_sort_decl_keys_scatter: PassData,
    modules_validate_decls: PassData,
    modules_mark_decl_namespace_keys: PassData,
    modules_scatter_decl_namespace_keys: PassData,
    modules_mark_public_decl_keys: PassData,
    modules_count_import_visibility: PassData,
    modules_scatter_import_visibility: PassData,
    modules_sort_import_visible_keys_small: PassData,
    modules_sort_import_visible_keys: PassData,
    modules_sort_import_visible_keys_scatter: PassData,
    modules_build_import_visible_key_tables: PassData,
    modules_validate_import_visible_keys: PassData,
    modules_resolve_local_paths: PassData,
    modules_resolve_imported_paths: PassData,
    modules_resolve_qualified_paths: PassData,
    modules_clear_type_path_types: PassData,
    modules_project_type_paths: PassData,
    modules_validate_type_paths: PassData,
    type_aliases: Box<TypeAliasPasses>,
    modules_project_type_instances: PassData,
    modules_mark_value_call_paths: PassData,
    modules_project_value_paths: PassData,
    modules_consume_value_calls: PassData,
    modules_mirror_value_call_leaf: PassData,
    modules_consume_value_consts: PassData,
    modules_consume_value_enum_units: PassData,
    modules_consume_value_enum_calls: PassData,
    modules_validate_value_enum_call_payloads: PassData,
    modules_finalize_value_enum_calls: PassData,
    modules_bind_match_patterns: PassData,
    modules_type_match_payloads: PassData,
    modules_type_match_exprs: PassData,
    type_instances_clear: PassData,
    type_instances_mark_generic_param_records: PassData,
    type_instances_propagate_generic_decl_owner: PassData,
    type_instances_decl_generic_params: PassData,
    type_instances_sort_generic_params_small: PassData,
    type_instances_sort_generic_param_keys: PassData,
    type_instances_sort_generic_param_keys_scatter: PassData,
    type_instances_sort_generic_param_slots: PassData,
    type_instances_sort_generic_param_slots_scatter: PassData,
    type_instances_generic_param_use_slots: PassData,
    type_instances_seed_struct_field_keys: PassData,
    type_instances_sort_struct_field_keys: PassData,
    type_instances_sort_struct_field_keys_scatter: PassData,
    type_instances_collect: PassData,
    type_instances_collect_named: PassData,
    type_instances_collect_aggregate_refs: PassData,
    type_instances_collect_aggregate_details: PassData,
    type_instances_collect_named_arg_refs: PassData,
    type_instances_hash_arg_rows: PassData,
    type_instances_clear_semantic_type_rows: Box<PassData>,
    type_instances_mark_semantic_type_rows: Box<PassData>,
    type_instances_scatter_semantic_type_rows: Box<PassData>,
    type_instances_decl_refs: PassData,
    type_instances_member_receivers: PassData,
    type_instances_member_results: PassData,
    type_instances_member_substitute: PassData,
    type_instances_struct_init_clear: PassData,
    type_instances_struct_init_contexts: PassData,
    type_instances_struct_init_fields: PassData,
    type_instances_struct_init_substitute: PassData,
    type_instances_array_return_refs: PassData,
    type_instances_array_literal_return_refs: PassData,
    type_instances_validate_aggregate_access: PassData,
    predicates_clear_syntax_tokens: PassData,
    predicates_clear_bound_arg_facts: PassData,
    predicates_collect_bound_arg_facts: PassData,
    predicates_collect_method_contracts: PassData,
    predicates_collect: PassData,
    predicates_validate_bound_args: PassData,
    predicates_collect_impls: PassData,
    predicates_seed_key_order: PassData,
    predicates_sort_keys_small: Option<PassData>,
    predicates_sort_keys: PassData,
    predicates_sort_keys_scatter: PassData,
    predicates_build_method_owner_ranges: PassData,
    predicates_emit_method_validation_rows: PassData,
    predicates_emit_method_param_validation_rows: PassData,
    predicates_validate_method_type_arg_rows: PassData,
    predicates_reduce_method_validation_errors: PassData,
    predicates_count_obligations: PassData,
    predicates_validate_obligations: PassData,
    semantic_predicate_diagnostics_clear: PassData,
    semantic_predicate_diagnostics_claim: PassData,
    semantic_predicate_diagnostics_project: PassData,
    returns_clear: PassData,
    returns_mark: PassData,
    returns_mark_if: PassData,
    returns_validate: PassData,
    conditions_compact_expr: PassData,
    conditions_compact_stmt: PassData,
    conditions_compact_calls: PassData,
    conditions_compact_types: PassData,
    conditions_compact_methods: PassData,
    conditions_compact_predicates: PassData,
    conditions_compact_names: PassData,
    conditions_compact_aggregate_requests: PassData,
    semantic_expression_refs_project: PassData,
    semantic_struct_literal_refs_project: PassData,
    semantic_array_index_refs_project: PassData,
    conditions_aggregate_args: PassData,
    conditions_type_subtree: Box<PassData>,
    scope_hir: PassData,
    calls_clear: PassData,
    calls_clear_entrypoints: PassData,
    calls_return_refs: PassData,
    calls_entrypoints: PassData,
    calls_functions: PassData,
    calls_param_types: PassData,
    calls_intrinsics: PassData,
    calls_clear_hir_call_args: PassData,
    calls_pack_hir_call_args: PassData,
    calls_mark_compact_hir_call_args: PassData,
    calls_scatter_compact_hir_call_args: PassData,
    calls_scatter_compact_hir_params: PassData,
    calls_resolve: PassData,
    calls_backend_targets: PassData,
    calls_match_arg_params_init: PassData,
    calls_collect_row_args: PassData,
    calls_emit_generic_claims: PassData,
    calls_sort_generic_claims: PassData,
    calls_sort_generic_claims_scatter: PassData,
    calls_validate_generic_claims: PassData,
    calls_clear_generic_claim_type_args: PassData,
    calls_mark_required_generics: PassData,
    calls_validate_required_generics: PassData,
    calls_validate_const_claims: PassData,
    calls_apply_row_args: PassData,
    calls_infer_array_generics: PassData,
    calls_validate_array_results: PassData,
    calls_mark_array_args: PassData,
    calls_project_result_instances: PassData,
    calls_erase_generic_params: PassData,
    methods_clear: PassData,
    methods_collect: PassData,
    methods_attach_metadata: PassData,
    methods_bind_self_receivers: PassData,
    methods_seed_key_order: PassData,
    methods_sort_keys_small: PassData,
    methods_sort_keys: PassData,
    methods_sort_keys_scatter: PassData,
    methods_validate_keys: PassData,
    methods_mark_call_keys: PassData,
    methods_mark_call_return_keys: PassData,
    methods_resolve_table: PassData,
    methods_resolve: PassData,
    visible_clear_resident: PassData,
    visible_mark_hir_decl_names: PassData,
    visible_scatter_hir_decl_records: PassData,
    visible_scatter_match_payload_decls: PassData,
    visible_finalize_decl_count: PassData,
    visible_seed_hir_decl_order: PassData,
    visible_sort_hir_decl_keys_small: PassData,
    visible_sort_hir_decl_keys: PassData,
    visible_sort_hir_decl_keys_scatter: PassData,
    visible_build_hir_decl_scope_leaves: PassData,
    visible_build_hir_decl_scope_tree: PassData,
    visible_hir_names: PassData,
    fn_context_clear: PassData,
    fn_context_mark: PassData,
    fn_context_local: PassData,
    fn_context_hierarchy_up: PassData,
    fn_context_hierarchy_down: PassData,
    fn_context_apply: PassData,
    if_depth_clear: PassData,
    if_depth_mark: PassData,
    if_depth_local: PassData,
    if_depth_hierarchy_up: PassData,
    if_depth_hierarchy_down: PassData,
    if_depth_apply: PassData,
}

struct TypeAliasPasses {
    clear_forwarding: PassData,
    init_forwarding: PassData,
    validate_forwarding_args: PassData,
    init_roots: PassData,
    jump_roots: PassData,
    clear_equivalence: PassData,
    init_decl_edges: PassData,
    init_arg_edges: PassData,
    hook_equivalence: PassData,
    jump_equivalence: PassData,
    select_generic_sources: PassData,
    select_concrete_sources: PassData,
    finalize_equivalence: PassData,
    project_instances: PassData,
    project: PassData,
}

struct DependencyPasses {
    clear_module_lookup: PassData,
    build_module_lookup: PassData,
    resolve_imports: PassData,
    count_import_visibility: PassData,
    scatter_import_visibility: PassData,
    clear_visible_lookup: PassData,
    build_visible_lookup: PassData,
    resolve_paths: PassData,
    project_calls: PassData,
    project_call_params: PassData,
    scatter_call_params: PassData,
    validate_call_args: PassData,
    validate_call_results: PassData,
    validate_call_type_args: PassData,
    canonical_types: Box<DependencyCanonicalTypePasses>,
}

struct DependencyCanonicalTypePasses {
    init_canonical_type_roots: Box<PassData>,
    jump_canonical_type_roots: Box<PassData>,
    init_canonical_type_subtree_start: Box<PassData>,
    jump_canonical_type_subtree_start: Box<PassData>,
    project_types: Box<PassData>,
    clear_declaration_generic_arity: Box<PassData>,
    count_declaration_generic_arity: Box<PassData>,
    project_type_instances: Box<PassData>,
}

// Resident type-checking keeps buffers and bind groups in this owner so GPU
// resources stay alive across the retained pipeline even when a field is only
// consumed indirectly by a reflected bind group.
#[allow(dead_code)]
struct ResidentTypeCheckState {
    cache_key: ResidentTypeCheckCacheKey,
    typecheck_graph: compiler_graph::TypeCheckCompilerGraph,
    compact_expr_scalar_type: LaniusBuffer<u32>,
    compact_expr_scalar_type_init: wgpu::BindGroup,
    compact_expr_scalar_type_steps: Vec<wgpu::BindGroup>,
    name_capacity: u32,
    name_n_blocks: u32,
    if_depth_n_blocks: u32,
    fn_n_blocks: u32,
    language_symbol_bytes: LaniusBuffer<u8>,
    name_order_in: LaniusBuffer<u32>,
    name_order_tmp: LaniusBuffer<u32>,
    name_id_by_token: LaniusBuffer<u32>,
    language_name_id: LaniusBuffer<u32>,
    language_decl_symbol_slot: LaniusBuffer<u32>,
    language_decl_kind: LaniusBuffer<u32>,
    language_decl_tag: LaniusBuffer<u32>,
    language_decl_name_id: LaniusBuffer<u32>,
    language_type_code_by_name_id: LaniusBuffer<u32>,
    language_entrypoint_tag_by_name_id: LaniusBuffer<u32>,
    language_intrinsic_tag_by_name_id: LaniusBuffer<u32>,
    radix_block_histogram: LaniusBuffer<u32>,
    radix_block_bucket_prefix: LaniusBuffer<u32>,
    module_path: Option<ModulePathState>,
    method_module_id_by_file_id_implicit_root: LaniusBuffer<u32>,
    module_type_path_type: LaniusBuffer<u32>,
    module_type_path_status: LaniusBuffer<u32>,
    module_value_path_expr_head: LaniusBuffer<u32>,
    module_value_path_call_head: LaniusBuffer<u32>,
    module_value_path_call_open: LaniusBuffer<u32>,
    module_value_path_call_path_id: LaniusBuffer<u32>,
    module_value_path_call_leaf: LaniusBuffer<u32>,
    module_value_path_associated_method_token: LaniusBuffer<u32>,
    module_value_path_associated_receiver_token: LaniusBuffer<u32>,
    module_value_path_const_head: LaniusBuffer<u32>,
    module_value_path_const_end: LaniusBuffer<u32>,
    module_value_path_status: LaniusBuffer<u32>,
    visible_decl: LaniusBuffer<u32>,
    visible_type: LaniusBuffer<u32>,
    hir_value_decl_name_present: LaniusBuffer<u32>,
    token_active_dispatch_args: LaniusBuffer<u32>,
    hir_active_dispatch_args: LaniusBuffer<u32>,
    token_hir_active_dispatch_args: LaniusBuffer<u32>,
    hir_active_count: LaniusBuffer<u32>,
    hir_active_dispatch: wgpu::BindGroup,
    semantic_features: SemanticFeaturesOperation,
    call_dependency_decl: LaniusBuffer<u32>,
    call_generic_claim_count_out: Box<LaniusBuffer<u32>>,
    call_generic_claim_scan_input: Box<LaniusBuffer<u32>>,
    call_generic_claim_prefix: Box<LaniusBuffer<u32>>,
    call_generic_claim_callee: Box<LaniusBuffer<u32>>,
    call_generic_claim_slot: Box<LaniusBuffer<u32>>,
    call_generic_claim_type: Box<LaniusBuffer<u32>>,
    call_generic_claim_ref_tag: Box<LaniusBuffer<u32>>,
    call_generic_claim_ref_payload: Box<LaniusBuffer<u32>>,
    call_generic_claim_arg_row: Box<LaniusBuffer<u32>>,
    call_generic_claim_order: Box<LaniusBuffer<u32>>,
    call_generic_claim_order_tmp: Box<LaniusBuffer<u32>>,
    call_generic_claim_radix_dispatch_args: LaniusBuffer<u32>,
    call_generic_claim_radix_block_histogram: LaniusBuffer<u32>,
    call_generic_claim_radix_block_bucket_prefix: LaniusBuffer<u32>,
    call_generic_claim_radix_bucket_total: LaniusBuffer<u32>,
    call_generic_claim_radix_bucket_base: LaniusBuffer<u32>,
    call_const_claim_callee: LaniusBuffer<u32>,
    call_const_claim_slot: LaniusBuffer<u32>,
    call_const_claim_len: LaniusBuffer<u32>,
    call_const_claim_order: LaniusBuffer<u32>,
    call_const_claim_order_tmp: LaniusBuffer<u32>,
    call_const_claim_radix_dispatch_args: LaniusBuffer<u32>,
    call_const_claim_radix_block_histogram: LaniusBuffer<u32>,
    call_const_claim_radix_block_bucket_prefix: LaniusBuffer<u32>,
    call_const_claim_radix_bucket_total: LaniusBuffer<u32>,
    call_const_claim_radix_bucket_base: LaniusBuffer<u32>,
    call_required_generic_count_out: LaniusBuffer<u32>,
    call_required_generic_scan_input: LaniusBuffer<u32>,
    call_required_generic_prefix: LaniusBuffer<u32>,
    call_required_generic_scan_local_prefix: LaniusBuffer<u32>,
    call_required_generic_scan_block_sum: LaniusBuffer<u32>,
    call_required_generic_scan_prefix_a: LaniusBuffer<u32>,
    call_required_generic_scan_prefix_b: LaniusBuffer<u32>,
    call_required_generic_dispatch_args: LaniusBuffer<u32>,
    call_generic_claim_scan_local_prefix: LaniusBuffer<u32>,
    call_generic_claim_scan_block_sum: LaniusBuffer<u32>,
    call_generic_claim_scan_prefix_a: LaniusBuffer<u32>,
    call_generic_claim_scan_prefix_b: LaniusBuffer<u32>,
    method_module_count_out_implicit_root: LaniusBuffer<u32>,
    type_instance_decl_token: LaniusBuffer<u32>,
    type_instance_external_canonical: LaniusBuffer<u32>,
    type_semantic_buffers: Box<TypeSemanticBuffers>,
    aggregate_compare_dispatch_params: LaniusBuffer<CountDispatchParams>,
    type_subtree_compare_buffers: Box<TypeSubtreeCompareBuffers>,
    decl_type_ref_tag: LaniusBuffer<u32>,
    decl_type_ref_payload: LaniusBuffer<u32>,
    name_bind_groups: NameBindGroups,
    language_name_bind_groups: LanguageNameBindGroups,
    if_depth_params: LaniusBuffer<IfDepthParams>,
    fn_params: LaniusBuffer<FnContextParams>,
    if_depth_bind_groups: IfDepthBindGroups,
    fn_context_bind_groups: FnContextBindGroups,
    visible_bind_groups: VisibleBindGroups,
    calls: CallBindGroups,
    methods: MethodBindGroups,
    predicates: Option<PredicateBindGroups>,
    type_instances: TypeInstanceBindGroups,
    returns_clear: wgpu::BindGroup,
    returns_mark: wgpu::BindGroup,
    returns_mark_if: wgpu::BindGroup,
    returns_validate: wgpu::BindGroup,
    semantic_predicate_diagnostics_clear: wgpu::BindGroup,
    semantic_predicate_diagnostics_claim: wgpu::BindGroup,
    semantic_predicate_diagnostics_project: wgpu::BindGroup,
    conditions_compact_expr: wgpu::BindGroup,
    conditions_compact_stmt: wgpu::BindGroup,
    conditions_compact_calls: wgpu::BindGroup,
    conditions_compact_types: wgpu::BindGroup,
    conditions_compact_methods: wgpu::BindGroup,
    conditions_compact_predicates: wgpu::BindGroup,
    conditions_compact_names: wgpu::BindGroup,
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

impl ResidentTypeCheckState {
    fn can_reuse_for(&self, key: ResidentTypeCheckCacheKey) -> bool {
        self.cache_key.source_file_capacity == key.source_file_capacity
            && self.cache_key.token_capacity >= key.token_capacity
            && self.cache_key.hir_node_capacity >= key.hir_node_capacity
            && self.cache_key.parser_hir_node_capacity >= key.parser_hir_node_capacity
            && self.cache_key.module_record_capacity >= key.module_record_capacity
            && self.cache_key.call_param_row_capacity >= key.call_param_row_capacity
            && self.cache_key.call_arg_row_capacity >= key.call_arg_row_capacity
            && self.cache_key.parser_feature_flags == key.parser_feature_flags
            && self.cache_key.input_fingerprint == key.input_fingerprint
            && self.cache_key.uses_hir_items == key.uses_hir_items
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
    pub dependency_decl: u32,
    pub intrinsic_tag: u32,
    pub return_type: u32,
    pub receiver_hir: u32,
    pub arg_count: u32,
    pub return_ref_tag: u32,
    pub return_ref_payload: u32,
}

#[derive(Clone, Copy)]
pub(crate) struct GpuCheckedSemanticArtifact<'a> {
    /// Resolved declaration identity for each compact HIR value row.
    pub value_decl_by_hir: &'a LaniusBuffer<u32>,
    /// Resolved type identity for each compact HIR value row.
    pub value_type_by_hir: &'a LaniusBuffer<u32>,
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
    /// Checked fixed-array length keyed by dense expression HIR row.
    pub array_length_by_hir: &'a LaniusBuffer<u32>,
    /// Checked field ordinal keyed by dense member-expression HIR row.
    pub member_field_ordinal_by_hir: &'a LaniusBuffer<u32>,
}

/// Typed allocation-preserving view used by the shared semantic lowering
/// stage. Token-indexed tables remain private to unfinished type-checking and
/// legacy backend paths; the new lowering boundary consumes compact artifacts.
#[derive(Clone, Copy)]
pub(crate) struct GpuSemanticLoweringBuffers<'a> {
    pub checked: GpuCheckedSemanticArtifact<'a>,
    pub compact_expr_scalar_type: &'a LaniusBuffer<u32>,
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
pub(crate) struct OwnedGpuSemanticArtifact {
    value_decl_by_hir: LaniusBuffer<u32>,
    value_type_by_hir: LaniusBuffer<u32>,
    param_type_by_row: LaniusBuffer<u32>,
    enclosing_fn_by_hir: LaniusBuffer<u32>,
    function_return_type_by_hir: LaniusBuffer<u32>,
    function_entrypoint_by_hir: LaniusBuffer<u32>,
    function_host_service_by_hir: LaniusBuffer<u32>,
    control_depth_by_hir: LaniusBuffer<u32>,
    calls_by_hir: LaniusBuffer<GpuCheckedCallArtifact>,
    expr_ref_tag_by_hir: LaniusBuffer<u32>,
    expr_ref_payload_by_hir: LaniusBuffer<u32>,
    array_length_by_hir: LaniusBuffer<u32>,
    member_field_ordinal_by_hir: LaniusBuffer<u32>,
    compact_expr_scalar_type: LaniusBuffer<u32>,
    public_decl_index_by_hir: LaniusBuffer<u32>,
    struct_init_field_ordinal_by_row: LaniusBuffer<u32>,
}

impl OwnedGpuSemanticArtifact {
    pub(crate) fn view(&self) -> GpuSemanticLoweringBuffers<'_> {
        GpuSemanticLoweringBuffers {
            checked: GpuCheckedSemanticArtifact {
                value_decl_by_hir: &self.value_decl_by_hir,
                value_type_by_hir: &self.value_type_by_hir,
                param_type_by_row: &self.param_type_by_row,
                enclosing_fn_by_hir: &self.enclosing_fn_by_hir,
                function_return_type_by_hir: &self.function_return_type_by_hir,
                function_entrypoint_by_hir: &self.function_entrypoint_by_hir,
                function_host_service_by_hir: &self.function_host_service_by_hir,
                control_depth_by_hir: &self.control_depth_by_hir,
                calls_by_hir: &self.calls_by_hir,
                expr_ref_tag_by_hir: &self.expr_ref_tag_by_hir,
                expr_ref_payload_by_hir: &self.expr_ref_payload_by_hir,
                array_length_by_hir: &self.array_length_by_hir,
                member_field_ordinal_by_hir: &self.member_field_ordinal_by_hir,
            },
            compact_expr_scalar_type: &self.compact_expr_scalar_type,
            public_decl_index_by_hir: &self.public_decl_index_by_hir,
            struct_init_field_ordinal_by_row: &self.struct_init_field_ordinal_by_row,
        }
    }
}

/// Canonical identities for declarations imported by one bounded unit.
/// Semantic lowering reads only these columns; the larger dependency
/// type-check state remains outside the backend contract.
#[derive(Clone, Copy)]
pub(crate) struct GpuDependencySymbolBuffers<'a> {
    pub counts: &'a LaniusBuffer<u32>,
    pub declaration_library_id: &'a LaniusBuffer<u32>,
    pub declaration_unit_id: &'a LaniusBuffer<u32>,
    pub declaration_local_index: &'a LaniusBuffer<u32>,
}

/// Borrowed GPU tables required to canonicalize a bounded unit's public
/// semantic interface. Source bytes and parser-owned signature/member tables
/// are supplied separately by the compiler orchestration layer.
#[derive(Clone, Copy)]
pub struct GpuSemanticInterfaceIdentityBuffers<'a> {
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
    pub public_decl_count: &'a wgpu::Buffer,
    pub public_decl_local_id: &'a wgpu::Buffer,
    pub public_decl_index_by_local: &'a wgpu::Buffer,
    pub public_decl_index_by_hir: &'a wgpu::Buffer,
    pub type_expr_ref_tag: &'a wgpu::Buffer,
    pub type_expr_ref_payload: &'a wgpu::Buffer,
    pub type_generic_param_slot_by_token: &'a wgpu::Buffer,
    pub type_const_param_slot_by_token: &'a wgpu::Buffer,
    pub type_instance_decl_token: &'a wgpu::Buffer,
    pub type_instance_external_canonical: &'a wgpu::Buffer,
    pub dependency_type_count: u32,
    pub dependency_type_words: &'a wgpu::Buffer,
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
    pub compact_hir_count: &'a wgpu::Buffer,
    pub compact_hir_core: &'a wgpu::Buffer,
    pub compact_hir_payload: &'a wgpu::Buffer,
    pub compact_fn_return_type: &'a wgpu::Buffer,
    pub compact_type_alias_target: &'a wgpu::Buffer,
    pub compact_const_type: &'a wgpu::Buffer,
    pub compact_param_count: &'a wgpu::Buffer,
    pub compact_params: &'a wgpu::Buffer,
    pub compact_param_ranges: &'a wgpu::Buffer,
    pub compact_type_arg_count: &'a wgpu::Buffer,
    pub compact_type_args: &'a wgpu::Buffer,
    pub compact_type_arg_ranges: &'a wgpu::Buffer,
    pub compact_field_count: &'a wgpu::Buffer,
    pub compact_fields: &'a wgpu::Buffer,
    pub compact_variant_count: &'a wgpu::Buffer,
    pub compact_variants: &'a wgpu::Buffer,
    pub compact_variant_payload_count: &'a wgpu::Buffer,
    pub compact_variant_payload_row_count: &'a wgpu::Buffer,
    pub compact_variant_payloads: &'a wgpu::Buffer,
}
