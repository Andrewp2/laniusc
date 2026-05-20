use std::{
    collections::HashMap,
    hash::{Hash, Hasher},
    sync::Mutex,
};

mod bind_groups;
mod bind_support;
mod module_path;
mod pass_loaders;
mod record;
mod resident;
mod standalone;
mod util;

use anyhow::Result;
use bind_support::*;
use encase::ShaderType;
use module_path::*;
use pass_loaders::*;
use record::*;
pub use standalone::{
    check_token_buffer_on_gpu,
    check_token_buffer_with_hir_on_gpu,
    check_tokens_on_gpu,
};
use util::*;
use wgpu::util::DeviceExt;

use crate::{
    gpu::{
        buffers::{LaniusBuffer, storage_ro_from_bytes, storage_ro_from_u32s, uniform_from_val},
        device,
        passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    },
    lexer::types::Token,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct TypeCheckParams {
    n_tokens: u32,
    source_len: u32,
    n_hir_nodes: u32,
    n_source_files: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct LoopDepthParams {
    n_tokens: u32,
    n_hir_nodes: u32,
    n_blocks: u32,
    scan_step: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct FnContextParams {
    n_tokens: u32,
    n_hir_nodes: u32,
    n_blocks: u32,
    scan_step: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct NameScanParams {
    n_items: u32,
    n_blocks: u32,
    scan_step: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct VisibleDeclTreeParams {
    decl_capacity: u32,
    row_block_size: u32,
    leaf_base: u32,
    level_start: u32,
    level_count: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct NameRadixParams {
    name_count: u32,
    source_len: u32,
    n_blocks: u32,
    radix_byte_offset: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct CountDispatchParams {
    capacity: u32,
    multiplier: u32,
    reserved0: u32,
    reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct CountPairMaxDispatchParams {
    left_capacity: u32,
    right_capacity: u32,
    multiplier: u32,
    reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct RecordFamilyFlagParams {
    n_hir_nodes: u32,
    family_bit: u32,
    reserved0: u32,
    reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct ModuleKeyRadixParams {
    module_capacity: u32,
    reserved: u32,
    n_blocks: u32,
    key_step: u32,
}

struct LoopDepthScanStep {
    params: LaniusBuffer<LoopDepthParams>,
    read_from_a: bool,
    write_to_a: bool,
}

struct FnContextScanStep {
    params: LaniusBuffer<FnContextParams>,
    read_from_a: bool,
    write_to_a: bool,
}

struct NameScanStep {
    params: LaniusBuffer<NameScanParams>,
    read_from_a: bool,
    write_to_a: bool,
}

struct NameRadixStep {
    _params: LaniusBuffer<NameRadixParams>,
}

struct ModuleKeyRadixStep {
    _params: LaniusBuffer<ModuleKeyRadixParams>,
}

struct LoopDepthBindGroups {
    clear: wgpu::BindGroup,
    mark: wgpu::BindGroup,
    local: wgpu::BindGroup,
    scan: Vec<wgpu::BindGroup>,
    apply: wgpu::BindGroup,
}

struct VisibleBindGroups {
    hir_decl_scan_n_blocks: u32,
    hir_decl_record_n_blocks: u32,
    hir_semantic_dispatch_args: wgpu::Buffer,
    clear: wgpu::BindGroup,
    legacy_token_visibility: Option<LegacyVisibleBindGroups>,
    hir_semantic_dispatch: wgpu::BindGroup,
    mark_hir_decl_names: wgpu::BindGroup,
    hir_decl_scan: U32ScanBindGroups,
    scatter_hir_decl_records: wgpu::BindGroup,
    seed_hir_decl_order: wgpu::BindGroup,
    hir_decl_key_radix_dispatch: wgpu::BindGroup,
    hir_decl_key_radix_dispatch_args: wgpu::Buffer,
    _hir_semantic_dispatch_params: LaniusBuffer<CountDispatchParams>,
    _hir_decl_key_radix_dispatch_params: LaniusBuffer<ModuleKeyRadixParams>,
    _hir_decl_key_radix_steps: Vec<ModuleKeyRadixStep>,
    sort_hir_decl_key_histogram: Vec<wgpu::BindGroup>,
    sort_hir_decl_key_bucket_prefix: Vec<wgpu::BindGroup>,
    sort_hir_decl_key_bucket_bases: Vec<wgpu::BindGroup>,
    sort_hir_decl_key_scatter: Vec<wgpu::BindGroup>,
    _hir_decl_scope_leaf_params: LaniusBuffer<VisibleDeclTreeParams>,
    build_hir_decl_scope_leaves: wgpu::BindGroup,
    hir_decl_scope_leaf_work_items: u32,
    hir_decl_scope_tree_levels: Vec<VisibleDeclScopeTreeLevel>,
    hir_names: wgpu::BindGroup,
}

struct LegacyVisibleBindGroups {
    scope_blocks: wgpu::BindGroup,
    scatter: wgpu::BindGroup,
    decode: wgpu::BindGroup,
}

struct VisibleDeclScopeTreeLevel {
    _params: LaniusBuffer<VisibleDeclTreeParams>,
    bind_group: wgpu::BindGroup,
    work_items: u32,
}

struct FnContextBindGroups {
    clear: wgpu::BindGroup,
    mark: wgpu::BindGroup,
    local: wgpu::BindGroup,
    scan: Vec<wgpu::BindGroup>,
    apply: wgpu::BindGroup,
}

struct NameBindGroups {
    token_scan_n_blocks: u32,
    radix_n_blocks: u32,
    radix_dispatch_args: wgpu::Buffer,
    name_max_len: wgpu::Buffer,
    mark: wgpu::BindGroup,
    scan_local: wgpu::BindGroup,
    scan_blocks: Vec<wgpu::BindGroup>,
    scan_apply: wgpu::BindGroup,
    scatter: wgpu::BindGroup,
    radix_dispatch: wgpu::BindGroup,
    _radix_steps: Vec<NameRadixStep>,
    radix_histogram: Vec<wgpu::BindGroup>,
    radix_bucket_prefix: Vec<wgpu::BindGroup>,
    radix_bucket_bases: Vec<wgpu::BindGroup>,
    radix_scatter: Vec<wgpu::BindGroup>,
    dedup: wgpu::BindGroup,
    _run_head_scan_steps: Vec<NameScanStep>,
    run_head_scan_local: wgpu::BindGroup,
    run_head_scan_blocks: Vec<wgpu::BindGroup>,
    run_head_scan_apply: wgpu::BindGroup,
    assign_ids: wgpu::BindGroup,
}

struct LanguageNameBindGroups {
    clear: wgpu::BindGroup,
    mark: wgpu::BindGroup,
    type_codes_clear: wgpu::BindGroup,
    decls_materialize: wgpu::BindGroup,
}

struct ModulePathBindGroups {
    mark_records: wgpu::BindGroup,
    extract_path_record_flag: wgpu::BindGroup,
    path_scan: U32ScanBindGroups,
    scatter_paths: wgpu::BindGroup,
    count_path_segments: wgpu::BindGroup,
    path_segment_scan: U32ScanBindGroups,
    scatter_path_segments: wgpu::BindGroup,
    extract_module_record_flag: wgpu::BindGroup,
    module_scan: U32ScanBindGroups,
    extract_import_record_flag: wgpu::BindGroup,
    import_scan: U32ScanBindGroups,
    extract_decl_record_flag: wgpu::BindGroup,
    decl_scan: U32ScanBindGroups,
    scatter_module_records: wgpu::BindGroup,
    scatter_import_records: wgpu::BindGroup,
    scatter_decl_core_records: wgpu::BindGroup,
    clear_decl_lookup: wgpu::BindGroup,
    scatter_decl_span_records: wgpu::BindGroup,
    build_module_keys: wgpu::BindGroup,
    module_key_segment_dispatch: wgpu::BindGroup,
    module_key_radix_dispatch: wgpu::BindGroup,
    sort_module_key_histogram: Vec<wgpu::BindGroup>,
    sort_module_key_bucket_prefix: Vec<wgpu::BindGroup>,
    sort_module_key_bucket_bases: Vec<wgpu::BindGroup>,
    sort_module_key_scatter: Vec<wgpu::BindGroup>,
    validate_modules: wgpu::BindGroup,
    resolve_imports: wgpu::BindGroup,
    clear_file_module_map: wgpu::BindGroup,
    build_file_module_map: wgpu::BindGroup,
    attach_record_modules: wgpu::BindGroup,
    import_dispatch_args: wgpu::BindGroup,
    seed_decl_key_order: wgpu::BindGroup,
    decl_key_radix_dispatch: wgpu::BindGroup,
    sort_decl_key_histogram: Vec<wgpu::BindGroup>,
    sort_decl_key_bucket_prefix: Vec<wgpu::BindGroup>,
    sort_decl_key_bucket_bases: Vec<wgpu::BindGroup>,
    sort_decl_key_scatter: Vec<wgpu::BindGroup>,
    validate_decls: wgpu::BindGroup,
    mark_decl_namespace_keys: wgpu::BindGroup,
    decl_type_key_scan: U32ScanBindGroups,
    decl_value_key_scan: U32ScanBindGroups,
    scatter_decl_namespace_keys: wgpu::BindGroup,
    mark_public_decl_keys: wgpu::BindGroup,
    decl_type_public_scan: U32ScanBindGroups,
    decl_value_public_scan: U32ScanBindGroups,
    count_import_visibility: wgpu::BindGroup,
    import_visible_type_scan: U32ScanBindGroups,
    import_visible_value_scan: U32ScanBindGroups,
    scatter_import_visible_type: wgpu::BindGroup,
    scatter_import_visible_value: wgpu::BindGroup,
    import_visible_type_key_radix_dispatch: wgpu::BindGroup,
    sort_import_visible_type_key_histogram: Vec<wgpu::BindGroup>,
    sort_import_visible_type_key_bucket_prefix: Vec<wgpu::BindGroup>,
    sort_import_visible_type_key_bucket_bases: Vec<wgpu::BindGroup>,
    sort_import_visible_type_key_scatter: Vec<wgpu::BindGroup>,
    import_visible_value_key_radix_dispatch: wgpu::BindGroup,
    sort_import_visible_value_key_histogram: Vec<wgpu::BindGroup>,
    sort_import_visible_value_key_bucket_prefix: Vec<wgpu::BindGroup>,
    sort_import_visible_value_key_bucket_bases: Vec<wgpu::BindGroup>,
    sort_import_visible_value_key_scatter: Vec<wgpu::BindGroup>,
    build_import_visible_type_key_table: wgpu::BindGroup,
    build_import_visible_value_key_table: wgpu::BindGroup,
    import_visible_validate_dispatch_args: wgpu::BindGroup,
    validate_import_visible_keys: wgpu::BindGroup,
    path_dispatch_args: wgpu::BindGroup,
    path_segment_dispatch_args: wgpu::BindGroup,
    resolve_local_type_paths: wgpu::BindGroup,
    resolve_local_value_paths: wgpu::BindGroup,
    resolve_imported_type_paths: wgpu::BindGroup,
    resolve_imported_value_paths: wgpu::BindGroup,
    resolve_qualified_type_paths: wgpu::BindGroup,
    resolve_qualified_value_paths: wgpu::BindGroup,
    clear_type_path_types: wgpu::BindGroup,
    project_type_paths: wgpu::BindGroup,
    validate_type_paths: wgpu::BindGroup,
    project_type_aliases: wgpu::BindGroup,
    project_type_instances: wgpu::BindGroup,
    mark_value_call_paths: wgpu::BindGroup,
    project_value_paths: wgpu::BindGroup,
    consume_value_calls: wgpu::BindGroup,
    consume_value_consts: wgpu::BindGroup,
    consume_value_enum_units: wgpu::BindGroup,
    consume_value_enum_calls: wgpu::BindGroup,
    bind_match_patterns: wgpu::BindGroup,
    type_match_payloads: wgpu::BindGroup,
    type_match_exprs: wgpu::BindGroup,
}

struct U32ScanBindGroups {
    local: wgpu::BindGroup,
    blocks: Vec<wgpu::BindGroup>,
    apply: wgpu::BindGroup,
}

#[allow(dead_code)]
struct ModulePathState {
    n_blocks: u32,
    token_capacity: u32,
    record_family_bits: wgpu::Buffer,
    record_family_flag: wgpu::Buffer,
    module_record_flag: wgpu::Buffer,
    import_record_flag: wgpu::Buffer,
    decl_record_flag: wgpu::Buffer,
    module_record_prefix: wgpu::Buffer,
    import_record_prefix: wgpu::Buffer,
    decl_record_prefix: wgpu::Buffer,
    record_scan_local_prefix: wgpu::Buffer,
    record_scan_block_sum: wgpu::Buffer,
    record_scan_prefix_a: wgpu::Buffer,
    record_scan_prefix_b: wgpu::Buffer,
    module_count_out: wgpu::Buffer,
    import_count_out: wgpu::Buffer,
    decl_count_out: wgpu::Buffer,
    module_file_id: wgpu::Buffer,
    module_path_id: wgpu::Buffer,
    module_owner_hir: wgpu::Buffer,
    module_status: wgpu::Buffer,
    module_key_segment_count: wgpu::Buffer,
    module_key_segment_base: wgpu::Buffer,
    module_key_segment_name_id: wgpu::Buffer,
    module_key_to_module_id: wgpu::Buffer,
    module_key_order_tmp: wgpu::Buffer,
    module_key_radix_dispatch_args: wgpu::Buffer,
    module_key_radix_block_histogram: wgpu::Buffer,
    module_key_radix_block_bucket_prefix: wgpu::Buffer,
    module_key_radix_bucket_total: wgpu::Buffer,
    module_key_radix_bucket_base: wgpu::Buffer,
    module_id_by_file_id: wgpu::Buffer,
    import_module_file_id: wgpu::Buffer,
    import_path_id: wgpu::Buffer,
    import_kind: wgpu::Buffer,
    import_owner_hir: wgpu::Buffer,
    import_module_id: wgpu::Buffer,
    import_target_module_id: wgpu::Buffer,
    import_status: wgpu::Buffer,
    import_dispatch_args: wgpu::Buffer,
    decl_module_file_id: wgpu::Buffer,
    decl_module_id: wgpu::Buffer,
    decl_name_token: wgpu::Buffer,
    decl_id_by_name_token: wgpu::Buffer,
    decl_name_id: wgpu::Buffer,
    decl_kind: wgpu::Buffer,
    decl_namespace: wgpu::Buffer,
    decl_visibility: wgpu::Buffer,
    decl_hir_node: wgpu::Buffer,
    decl_parent_type_decl: wgpu::Buffer,
    decl_token_start: wgpu::Buffer,
    decl_token_end: wgpu::Buffer,
    decl_key_to_decl_id: wgpu::Buffer,
    decl_key_order_tmp: wgpu::Buffer,
    decl_key_radix_dispatch_args: wgpu::Buffer,
    decl_key_radix_block_histogram: wgpu::Buffer,
    decl_key_radix_block_bucket_prefix: wgpu::Buffer,
    decl_key_radix_bucket_total: wgpu::Buffer,
    decl_key_radix_bucket_base: wgpu::Buffer,
    decl_status: wgpu::Buffer,
    decl_duplicate_of: wgpu::Buffer,
    decl_type_key_flag: wgpu::Buffer,
    decl_value_key_flag: wgpu::Buffer,
    decl_type_key_prefix: wgpu::Buffer,
    decl_value_key_prefix: wgpu::Buffer,
    decl_type_key_count_out: wgpu::Buffer,
    decl_value_key_count_out: wgpu::Buffer,
    decl_type_key_to_decl_id: wgpu::Buffer,
    decl_value_key_to_decl_id: wgpu::Buffer,
    import_visible_type_count: wgpu::Buffer,
    import_visible_value_count: wgpu::Buffer,
    import_visible_type_prefix: wgpu::Buffer,
    import_visible_value_prefix: wgpu::Buffer,
    import_visible_type_count_out: wgpu::Buffer,
    import_visible_value_count_out: wgpu::Buffer,
    import_visible_type_module_id: wgpu::Buffer,
    import_visible_type_name_id: wgpu::Buffer,
    import_visible_type_decl_id: wgpu::Buffer,
    import_visible_type_key_order: wgpu::Buffer,
    import_visible_type_key_order_tmp: wgpu::Buffer,
    import_visible_type_key_module_id: wgpu::Buffer,
    import_visible_type_key_name_id: wgpu::Buffer,
    import_visible_type_key_to_decl_id: wgpu::Buffer,
    import_visible_type_status: wgpu::Buffer,
    import_visible_type_duplicate_of: wgpu::Buffer,
    import_visible_type_key_radix_dispatch_args: wgpu::Buffer,
    import_visible_value_module_id: wgpu::Buffer,
    import_visible_value_name_id: wgpu::Buffer,
    import_visible_value_decl_id: wgpu::Buffer,
    import_visible_value_key_order: wgpu::Buffer,
    import_visible_value_key_order_tmp: wgpu::Buffer,
    import_visible_value_key_module_id: wgpu::Buffer,
    import_visible_value_key_name_id: wgpu::Buffer,
    import_visible_value_key_to_decl_id: wgpu::Buffer,
    import_visible_value_status: wgpu::Buffer,
    import_visible_value_duplicate_of: wgpu::Buffer,
    import_visible_value_key_radix_dispatch_args: wgpu::Buffer,
    import_visible_validate_dispatch_args: wgpu::Buffer,
    import_visible_key_radix_block_histogram: wgpu::Buffer,
    import_visible_key_radix_block_bucket_prefix: wgpu::Buffer,
    import_visible_key_radix_bucket_total: wgpu::Buffer,
    import_visible_key_radix_bucket_base: wgpu::Buffer,
    resolved_type_decl: wgpu::Buffer,
    resolved_value_decl: wgpu::Buffer,
    resolved_type_status: wgpu::Buffer,
    resolved_value_status: wgpu::Buffer,
    path_record_flag: wgpu::Buffer,
    path_record_prefix: wgpu::Buffer,
    path_scan_local_prefix: wgpu::Buffer,
    path_scan_block_sum: wgpu::Buffer,
    path_scan_prefix_a: wgpu::Buffer,
    path_scan_prefix_b: wgpu::Buffer,
    path_start: wgpu::Buffer,
    path_len: wgpu::Buffer,
    path_segment_count: wgpu::Buffer,
    path_segment_base: wgpu::Buffer,
    path_segment_name_id: wgpu::Buffer,
    path_segment_token: wgpu::Buffer,
    path_segment_count_out: wgpu::Buffer,
    path_owner_hir: wgpu::Buffer,
    path_owner_token: wgpu::Buffer,
    path_id_by_owner_hir: wgpu::Buffer,
    path_owner_module_id: wgpu::Buffer,
    path_kind: wgpu::Buffer,
    path_count_out: wgpu::Buffer,
    path_dispatch_args: wgpu::Buffer,
    path_segment_dispatch_args: wgpu::Buffer,
    scan_steps: Vec<NameScanStep>,
    record_scan_steps: Vec<NameScanStep>,
    _extract_path_record_flag_params: LaniusBuffer<RecordFamilyFlagParams>,
    _extract_module_record_flag_params: LaniusBuffer<RecordFamilyFlagParams>,
    _extract_import_record_flag_params: LaniusBuffer<RecordFamilyFlagParams>,
    _extract_decl_record_flag_params: LaniusBuffer<RecordFamilyFlagParams>,
    _path_dispatch_params: LaniusBuffer<CountDispatchParams>,
    _path_segment_dispatch_params: LaniusBuffer<CountDispatchParams>,
    _import_dispatch_params: LaniusBuffer<CountDispatchParams>,
    _import_visible_validate_dispatch_params: LaniusBuffer<CountPairMaxDispatchParams>,
    _module_key_segment_dispatch_params: LaniusBuffer<CountDispatchParams>,
    _module_key_radix_dispatch_params: LaniusBuffer<ModuleKeyRadixParams>,
    _decl_key_radix_dispatch_params: LaniusBuffer<ModuleKeyRadixParams>,
    _import_visible_type_key_radix_dispatch_params: LaniusBuffer<ModuleKeyRadixParams>,
    _import_visible_value_key_radix_dispatch_params: LaniusBuffer<ModuleKeyRadixParams>,
    module_key_radix_steps: Vec<ModuleKeyRadixStep>,
    bind_groups: ModulePathBindGroups,
}

struct CallBindGroups {
    clear: wgpu::BindGroup,
    return_refs: wgpu::BindGroup,
    entrypoints: wgpu::BindGroup,
    functions: wgpu::BindGroup,
    param_types: wgpu::BindGroup,
    intrinsics: wgpu::BindGroup,
    clear_hir_call_args: wgpu::BindGroup,
    pack_hir_call_args: wgpu::BindGroup,
    resolve: wgpu::BindGroup,
    erase_generic_params: wgpu::BindGroup,
}

struct MethodBindGroups {
    clear: wgpu::BindGroup,
    collect: wgpu::BindGroup,
    attach_metadata: wgpu::BindGroup,
    bind_self_receivers: wgpu::BindGroup,
    keys: MethodKeyBindGroups,
    mark_call_keys: wgpu::BindGroup,
    mark_call_return_keys: wgpu::BindGroup,
    resolve_table: wgpu::BindGroup,
    resolve: wgpu::BindGroup,
}

struct MethodKeyBindGroups {
    _key_radix_steps: Vec<ModuleKeyRadixStep>,
    seed_key_order: wgpu::BindGroup,
    sort_key_histogram: Vec<wgpu::BindGroup>,
    sort_key_bucket_prefix: Vec<wgpu::BindGroup>,
    sort_key_bucket_bases: Vec<wgpu::BindGroup>,
    sort_key_scatter: Vec<wgpu::BindGroup>,
    validate_keys: wgpu::BindGroup,
}

const CALL_PARAM_CACHE_STRIDE: usize = 16;
pub const TYPE_INSTANCE_ARG_REF_STRIDE: usize = 4;
const NAME_RADIX_BUCKETS: u32 = 257;
const NAME_RADIX_MAX_BYTES: u32 = 64;
const LANGUAGE_SYMBOL_COUNT: u32 = 19;
const LANGUAGE_SYMBOL_BYTES: &[u8] =
    b"mainassertprintbooli8i16i32i64isizeu8u16u32u64usizef32f64charstr_";
const LANGUAGE_SYMBOL_STARTS: &[u32] = &[
    0, 4, 10, 15, 19, 21, 24, 27, 30, 35, 37, 40, 43, 46, 51, 54, 57, 61, 64,
];
const LANGUAGE_SYMBOL_LENS: &[u32] = &[4, 6, 5, 4, 2, 3, 3, 3, 5, 2, 3, 3, 3, 5, 3, 3, 4, 3, 1];
const LANGUAGE_DECL_COUNT: u32 = 18;
const LANGUAGE_DECL_KIND_ENTRYPOINT: u32 = 1;
const LANGUAGE_DECL_KIND_INTRINSIC: u32 = 2;
const LANGUAGE_DECL_KIND_PRIMITIVE_TYPE: u32 = 3;
const LANGUAGE_DECL_TAG_MAIN: u32 = 1;
const LANGUAGE_DECL_TAG_PRINT: u32 = 1;
const LANGUAGE_DECL_TAG_ASSERT: u32 = 2;
const LANGUAGE_DECL_SYMBOL_SLOTS: &[u32] =
    &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17];
const LANGUAGE_DECL_KINDS: &[u32] = &[
    LANGUAGE_DECL_KIND_ENTRYPOINT,
    LANGUAGE_DECL_KIND_INTRINSIC,
    LANGUAGE_DECL_KIND_INTRINSIC,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
];
const LANGUAGE_DECL_TAGS: &[u32] = &[
    LANGUAGE_DECL_TAG_MAIN,
    LANGUAGE_DECL_TAG_ASSERT,
    LANGUAGE_DECL_TAG_PRINT,
    2, // bool
    3, // i8
    3, // i16
    3, // i32
    3, // i64
    3, // isize
    4, // u8
    4, // u16
    4, // u32
    4, // u64
    4, // usize
    5, // f32
    5, // f64
    6, // char
    7, // str
];
const MODULE_KEY_SORT_SEGMENTS: u32 = 8;
const MODULE_KEY_SEGMENT_ROW_WIDTH: usize = MODULE_KEY_SORT_SEGMENTS as usize;
const PATH_SEGMENT_ROW_WIDTH: usize = MODULE_KEY_SORT_SEGMENTS as usize + 1;
const MODULE_KEY_RADIX_STEPS: u32 = MODULE_KEY_SORT_SEGMENTS * 4;
const DECL_KEY_RADIX_STEPS: u32 = 12;
const IMPORT_VISIBLE_KEY_RADIX_STEPS: u32 = 8;
const METHOD_KEY_RADIX_STEPS: u32 = 16;
const VISIBLE_DECL_KEY_FIELD_COUNT: u32 = 3;
const VISIBLE_DECL_KEY_MAX_RADIX_STEPS: u32 = 12;
const HIR_VISIBLE_DECL_ROW_BLOCK_SIZE: u32 = 64;

fn visible_decl_key_radix_bytes(decl_capacity: u32) -> u32 {
    let max_key = decl_capacity
        .saturating_add(LANGUAGE_SYMBOL_COUNT)
        .saturating_add(1)
        .max(1);
    if max_key <= 0xff {
        1
    } else if max_key <= 0xffff {
        2
    } else if max_key <= 0x00ff_ffff {
        3
    } else {
        4
    }
}

fn visible_decl_key_radix_steps(decl_capacity: u32) -> u32 {
    let steps = visible_decl_key_radix_bytes(decl_capacity) * VISIBLE_DECL_KEY_FIELD_COUNT;
    let even_steps = if steps % 2 == 0 { steps } else { steps + 1 };
    even_steps.min(VISIBLE_DECL_KEY_MAX_RADIX_STEPS)
}

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
            other => Self::Unknown(other),
        }
    }
}

#[derive(Debug)]
pub enum GpuTypeCheckError {
    Rejected {
        token: u32,
        code: GpuTypeCheckCode,
        detail: u32,
    },
    Gpu(anyhow::Error),
}

#[derive(Clone, Copy)]
pub struct GpuTypeCheckHirItemBuffers<'a> {
    pub node_kind: &'a wgpu::Buffer,
    pub parent: &'a wgpu::Buffer,
    pub first_child: &'a wgpu::Buffer,
    pub next_sibling: &'a wgpu::Buffer,
    pub subtree_end: &'a wgpu::Buffer,
    pub kind: &'a wgpu::Buffer,
    pub name_token: &'a wgpu::Buffer,
    pub type_form: &'a wgpu::Buffer,
    pub type_value_node: &'a wgpu::Buffer,
    pub type_len_token: &'a wgpu::Buffer,
    pub type_len_value: &'a wgpu::Buffer,
    pub type_path_leaf_node: &'a wgpu::Buffer,
    pub type_arg_start: &'a wgpu::Buffer,
    pub type_arg_count: &'a wgpu::Buffer,
    pub type_arg_next: &'a wgpu::Buffer,
    pub param_record: &'a wgpu::Buffer,
    pub expr_record: &'a wgpu::Buffer,
    pub expr_int_value: &'a wgpu::Buffer,
    pub member_receiver_node: &'a wgpu::Buffer,
    pub member_receiver_token: &'a wgpu::Buffer,
    pub member_name_token: &'a wgpu::Buffer,
    pub stmt_record: &'a wgpu::Buffer,
    pub array_lit_first_element: &'a wgpu::Buffer,
    pub array_lit_element_count: &'a wgpu::Buffer,
    pub array_element_next: &'a wgpu::Buffer,
    pub namespace: &'a wgpu::Buffer,
    pub visibility: &'a wgpu::Buffer,
    pub path_start: &'a wgpu::Buffer,
    pub path_end: &'a wgpu::Buffer,
    pub file_id: &'a wgpu::Buffer,
    pub import_target_kind: &'a wgpu::Buffer,
    pub call_callee_node: &'a wgpu::Buffer,
    pub call_arg_start: &'a wgpu::Buffer,
    pub call_arg_end: &'a wgpu::Buffer,
    pub call_arg_count: &'a wgpu::Buffer,
    pub call_arg_parent_call: &'a wgpu::Buffer,
    pub call_arg_ordinal: &'a wgpu::Buffer,
    pub variant_parent_enum: &'a wgpu::Buffer,
    pub variant_payload_start: &'a wgpu::Buffer,
    pub variant_payload_count: &'a wgpu::Buffer,
    pub match_scrutinee_node: &'a wgpu::Buffer,
    pub match_arm_start: &'a wgpu::Buffer,
    pub match_arm_count: &'a wgpu::Buffer,
    pub match_arm_next: &'a wgpu::Buffer,
    pub match_arm_pattern_node: &'a wgpu::Buffer,
    pub match_arm_payload_start: &'a wgpu::Buffer,
    pub match_arm_payload_count: &'a wgpu::Buffer,
    pub match_arm_result_node: &'a wgpu::Buffer,
    pub match_payload_owner_arm: &'a wgpu::Buffer,
    pub match_payload_match_node: &'a wgpu::Buffer,
    pub match_payload_ordinal: &'a wgpu::Buffer,
    pub struct_field_parent_struct: &'a wgpu::Buffer,
    pub struct_field_ordinal: &'a wgpu::Buffer,
    pub struct_field_type_node: &'a wgpu::Buffer,
    pub struct_decl_field_start: &'a wgpu::Buffer,
    pub struct_decl_field_count: &'a wgpu::Buffer,
    pub struct_lit_head_node: &'a wgpu::Buffer,
    pub struct_lit_field_start: &'a wgpu::Buffer,
    pub struct_lit_field_count: &'a wgpu::Buffer,
    pub struct_lit_field_parent_lit: &'a wgpu::Buffer,
    pub struct_lit_field_value_node: &'a wgpu::Buffer,
    pub semantic_dense_node: &'a wgpu::Buffer,
    pub semantic_count: &'a wgpu::Buffer,
}

impl std::fmt::Display for GpuTypeCheckError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GpuTypeCheckError::Rejected {
                token,
                code,
                detail,
            } => {
                write!(
                    f,
                    "GPU type check rejected token {token}: {code:?} ({detail})"
                )
            }
            GpuTypeCheckError::Gpu(err) => write!(f, "GPU type check failed: {err}"),
        }
    }
}

impl std::error::Error for GpuTypeCheckError {}

impl From<anyhow::Error> for GpuTypeCheckError {
    fn from(err: anyhow::Error) -> Self {
        Self::Gpu(err)
    }
}

pub struct GpuTypeChecker {
    passes: TypeCheckPasses,
    params_buf: LaniusBuffer<TypeCheckParams>,
    status_buf: wgpu::Buffer,
    status_readback: wgpu::Buffer,
    bind_groups: Mutex<Option<ResidentTypeCheckBindGroups>>,
}

pub struct RecordedTypeCheck;

struct TypeCheckPasses {
    hir_active_dispatch_args: PassData,
    names_mark_lexemes: PassData,
    counted_scan_local: PassData,
    counted_scan_blocks: PassData,
    counted_scan_apply: PassData,
    count_dispatch_args: PassData,
    count_pair_max_dispatch_args: PassData,
    names_scatter_lexemes: PassData,
    names_radix_dispatch_args: PassData,
    names_radix_histogram: PassData,
    names_radix_bucket_prefix: PassData,
    names_radix_bucket_bases: PassData,
    names_radix_scatter: PassData,
    names_radix_dedup: PassData,
    names_radix_assign_ids: PassData,
    language_names_clear: PassData,
    language_names_mark: PassData,
    language_type_codes_clear: PassData,
    language_decls_materialize: PassData,
    modules_mark_records: PassData,
    modules_extract_record_flag: PassData,
    modules_scatter_paths: PassData,
    modules_count_path_segments: PassData,
    modules_scatter_path_segments: PassData,
    modules_scatter_module_records: PassData,
    modules_scatter_import_records: PassData,
    modules_scatter_decl_core_records: PassData,
    modules_clear_decl_lookup: PassData,
    modules_scatter_decl_span_records: PassData,
    modules_build_module_keys: PassData,
    modules_sort_module_keys_histogram: PassData,
    modules_sort_module_keys_scatter: PassData,
    modules_validate_modules: PassData,
    modules_resolve_imports: PassData,
    modules_clear_file_module_map: PassData,
    modules_build_file_module_map: PassData,
    modules_attach_record_modules: PassData,
    modules_seed_decl_key_order: PassData,
    modules_sort_decl_keys: PassData,
    modules_sort_decl_keys_scatter: PassData,
    modules_validate_decls: PassData,
    modules_mark_decl_namespace_keys: PassData,
    modules_scatter_decl_namespace_keys: PassData,
    modules_mark_public_decl_keys: PassData,
    modules_count_import_visibility: PassData,
    modules_scatter_import_visibility: PassData,
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
    modules_project_type_aliases: PassData,
    modules_project_type_instances: PassData,
    modules_mark_value_call_paths: PassData,
    modules_project_value_paths: PassData,
    modules_consume_value_calls: PassData,
    modules_consume_value_consts: PassData,
    modules_consume_value_enum_units: PassData,
    modules_consume_value_enum_calls: PassData,
    modules_bind_match_patterns: PassData,
    modules_type_match_payloads: PassData,
    modules_type_match_exprs: PassData,
    type_instances_clear: PassData,
    type_instances_decl_generic_params: PassData,
    type_instances_generic_param_use_slots: PassData,
    type_instances_collect: PassData,
    type_instances_collect_named: PassData,
    type_instances_collect_aggregate_refs: PassData,
    type_instances_collect_aggregate_details: PassData,
    type_instances_collect_named_arg_refs: PassData,
    type_instances_decl_refs: PassData,
    type_instances_member_receivers: PassData,
    type_instances_member_results: PassData,
    type_instances_member_substitute: PassData,
    type_instances_struct_init_clear: PassData,
    type_instances_struct_init_fields: PassData,
    type_instances_struct_init_substitute: PassData,
    type_instances_array_return_refs: PassData,
    type_instances_array_literal_return_refs: PassData,
    type_instances_enum_ctors: PassData,
    type_instances_array_index_results: PassData,
    type_instances_validate_aggregate_access: PassData,
    conditions_hir: PassData,
    tokens: PassData,
    control: PassData,
    control_hir: PassData,
    scope: PassData,
    scope_hir: PassData,
    calls_clear: PassData,
    calls_return_refs: PassData,
    calls_entrypoints: PassData,
    calls_functions: PassData,
    calls_param_types: PassData,
    calls_intrinsics: PassData,
    calls_clear_hir_call_args: PassData,
    calls_pack_hir_call_args: PassData,
    calls_resolve: PassData,
    calls_erase_generic_params: PassData,
    methods_clear: PassData,
    methods_collect: PassData,
    methods_attach_metadata: PassData,
    methods_bind_self_receivers: PassData,
    methods_seed_key_order: PassData,
    methods_sort_keys: PassData,
    methods_sort_keys_scatter: PassData,
    methods_validate_keys: PassData,
    methods_mark_call_keys: PassData,
    methods_mark_call_return_keys: PassData,
    methods_resolve_table: PassData,
    methods_resolve: PassData,
    visible_clear_resident: PassData,
    visible_scope_blocks: PassData,
    visible_scatter: PassData,
    visible_decode: PassData,
    visible_mark_hir_decl_names: PassData,
    visible_scatter_hir_decl_records: PassData,
    visible_seed_hir_decl_order: PassData,
    visible_sort_hir_decl_keys: PassData,
    visible_sort_hir_decl_keys_scatter: PassData,
    visible_build_hir_decl_scope_leaves: PassData,
    visible_build_hir_decl_scope_tree: PassData,
    visible_hir_names: PassData,
    fn_context_clear: PassData,
    fn_context_mark: PassData,
    fn_context_local: PassData,
    fn_context_scan: PassData,
    fn_context_apply: PassData,
    loop_depth_clear: PassData,
    loop_depth_mark: PassData,
    loop_depth_local: PassData,
    loop_depth_scan: PassData,
    loop_depth_apply: PassData,
}

// Resident type-checking keeps buffers and bind groups in this owner so GPU
// resources stay alive across the retained pipeline even when a field is only
// consumed indirectly by a reflected bind group.
#[allow(dead_code)]
struct ResidentTypeCheckBindGroups {
    source_len: u32,
    source_file_capacity: u32,
    token_capacity: u32,
    hir_node_capacity: u32,
    input_fingerprint: u64,
    uses_hir_control: bool,
    uses_hir_items: bool,
    name_capacity: u32,
    name_n_blocks: u32,
    loop_n_blocks: u32,
    fn_n_blocks: u32,
    name_lexeme_flag: wgpu::Buffer,
    name_lexeme_kind: wgpu::Buffer,
    name_lexeme_prefix: wgpu::Buffer,
    name_scan_local_prefix: wgpu::Buffer,
    name_scan_block_sum: wgpu::Buffer,
    name_scan_prefix_a: wgpu::Buffer,
    name_scan_prefix_b: wgpu::Buffer,
    name_scan_total: wgpu::Buffer,
    name_spans: wgpu::Buffer,
    name_order_in: wgpu::Buffer,
    name_order_tmp: wgpu::Buffer,
    name_id_by_token: wgpu::Buffer,
    language_name_id: wgpu::Buffer,
    language_decl_symbol_slot: LaniusBuffer<u32>,
    language_decl_kind: LaniusBuffer<u32>,
    language_decl_tag: LaniusBuffer<u32>,
    language_decl_name_id: wgpu::Buffer,
    language_type_code_by_name_id: wgpu::Buffer,
    radix_block_histogram: wgpu::Buffer,
    radix_block_bucket_prefix: wgpu::Buffer,
    radix_bucket_total: wgpu::Buffer,
    radix_bucket_base: wgpu::Buffer,
    run_head_mask: wgpu::Buffer,
    adjacent_equal_mask: wgpu::Buffer,
    run_head_prefix: wgpu::Buffer,
    sorted_name_id: wgpu::Buffer,
    name_id_by_input: wgpu::Buffer,
    unique_name_count: wgpu::Buffer,
    module_path: Option<ModulePathState>,
    method_module_id_by_file_id_implicit_root: wgpu::Buffer,
    module_type_path_type: wgpu::Buffer,
    module_type_path_status: wgpu::Buffer,
    module_value_path_expr_head: wgpu::Buffer,
    module_value_path_call_head: wgpu::Buffer,
    module_value_path_call_open: wgpu::Buffer,
    module_value_path_const_head: wgpu::Buffer,
    module_value_path_const_end: wgpu::Buffer,
    module_value_path_status: wgpu::Buffer,
    visible_decl: wgpu::Buffer,
    visible_type: wgpu::Buffer,
    hir_value_decl_name_present: wgpu::Buffer,
    hir_visible_decl_flag: wgpu::Buffer,
    hir_visible_decl_prefix: wgpu::Buffer,
    hir_visible_decl_scan_local_prefix: wgpu::Buffer,
    hir_visible_decl_scan_block_sum: wgpu::Buffer,
    hir_visible_decl_scan_prefix_a: wgpu::Buffer,
    hir_visible_decl_scan_prefix_b: wgpu::Buffer,
    hir_visible_decl_count_out: wgpu::Buffer,
    hir_visible_decl_owner_fn: wgpu::Buffer,
    hir_visible_decl_name_id: wgpu::Buffer,
    hir_visible_decl_token: wgpu::Buffer,
    hir_visible_decl_scope_end: wgpu::Buffer,
    hir_visible_decl_key_order: wgpu::Buffer,
    hir_visible_decl_key_order_tmp: wgpu::Buffer,
    hir_visible_decl_key_radix_dispatch_args: wgpu::Buffer,
    hir_visible_decl_key_radix_block_histogram: wgpu::Buffer,
    hir_visible_decl_key_radix_block_bucket_prefix: wgpu::Buffer,
    hir_visible_decl_key_radix_bucket_total: wgpu::Buffer,
    hir_visible_decl_key_radix_bucket_base: wgpu::Buffer,
    hir_visible_decl_scope_tree: wgpu::Buffer,
    token_active_dispatch_args: wgpu::Buffer,
    hir_active_dispatch_args: wgpu::Buffer,
    token_hir_active_dispatch_args: wgpu::Buffer,
    hir_active_count: wgpu::Buffer,
    hir_active_dispatch: wgpu::BindGroup,
    loop_delta: wgpu::Buffer,
    loop_depth_inblock: wgpu::Buffer,
    loop_block_sum: wgpu::Buffer,
    loop_prefix_a: wgpu::Buffer,
    loop_prefix_b: wgpu::Buffer,
    loop_block_prefix: wgpu::Buffer,
    loop_depth: wgpu::Buffer,
    enclosing_fn: wgpu::Buffer,
    enclosing_fn_end: wgpu::Buffer,
    fn_event_value: wgpu::Buffer,
    fn_event_end: wgpu::Buffer,
    fn_event_index: wgpu::Buffer,
    fn_event_inblock: wgpu::Buffer,
    fn_block_sum: wgpu::Buffer,
    fn_prefix_a: wgpu::Buffer,
    fn_prefix_b: wgpu::Buffer,
    fn_block_prefix: wgpu::Buffer,
    call_fn_index: wgpu::Buffer,
    call_intrinsic_tag: wgpu::Buffer,
    fn_entrypoint_tag: wgpu::Buffer,
    call_return_type: wgpu::Buffer,
    call_return_type_token: wgpu::Buffer,
    call_param_count: wgpu::Buffer,
    call_param_type: wgpu::Buffer,
    call_arg_record: wgpu::Buffer,
    call_arg_node: wgpu::Buffer,
    function_lookup_key: wgpu::Buffer,
    function_lookup_fn: wgpu::Buffer,
    method_decl_receiver_ref_tag: wgpu::Buffer,
    method_decl_receiver_ref_payload: wgpu::Buffer,
    method_decl_module_id: wgpu::Buffer,
    method_decl_impl_node: wgpu::Buffer,
    method_decl_name_token: wgpu::Buffer,
    method_decl_name_id: wgpu::Buffer,
    method_decl_param_offset: wgpu::Buffer,
    method_decl_receiver_mode: wgpu::Buffer,
    method_decl_visibility: wgpu::Buffer,
    method_module_count_out_implicit_root: wgpu::Buffer,
    method_key_to_fn_token: wgpu::Buffer,
    method_key_order_tmp: wgpu::Buffer,
    method_key_status: wgpu::Buffer,
    method_key_duplicate_of: wgpu::Buffer,
    method_key_radix_block_histogram: wgpu::Buffer,
    method_key_radix_block_bucket_prefix: wgpu::Buffer,
    method_key_radix_bucket_total: wgpu::Buffer,
    method_key_radix_bucket_base: wgpu::Buffer,
    method_call_receiver_ref_tag: wgpu::Buffer,
    method_call_receiver_ref_payload: wgpu::Buffer,
    method_call_name_id: wgpu::Buffer,
    method_call_site_module_id: wgpu::Buffer,
    type_expr_ref_tag: wgpu::Buffer,
    type_expr_ref_payload: wgpu::Buffer,
    type_instance_kind: wgpu::Buffer,
    type_instance_head_token: wgpu::Buffer,
    type_decl_generic_param_count: wgpu::Buffer,
    type_decl_generic_param_count_by_node: wgpu::Buffer,
    type_decl_const_param_count_by_node: wgpu::Buffer,
    type_decl_hir_node_by_token: wgpu::Buffer,
    type_generic_param_slot_by_token: wgpu::Buffer,
    type_const_param_slot_by_token: wgpu::Buffer,
    type_instance_decl_token: wgpu::Buffer,
    type_instance_arg_start: wgpu::Buffer,
    type_instance_arg_count: wgpu::Buffer,
    type_instance_arg_ref_tag: wgpu::Buffer,
    type_instance_arg_ref_payload: wgpu::Buffer,
    type_instance_elem_ref_tag: wgpu::Buffer,
    type_instance_elem_ref_payload: wgpu::Buffer,
    type_instance_len_kind: wgpu::Buffer,
    type_instance_len_payload: wgpu::Buffer,
    type_instance_state: wgpu::Buffer,
    fn_return_ref_tag: wgpu::Buffer,
    fn_return_ref_payload: wgpu::Buffer,
    decl_type_ref_tag: wgpu::Buffer,
    decl_type_ref_payload: wgpu::Buffer,
    member_result_context_instance: wgpu::Buffer,
    member_result_ref_tag: wgpu::Buffer,
    member_result_ref_payload: wgpu::Buffer,
    member_result_field_ordinal: wgpu::Buffer,
    struct_init_field_expected_ref_tag: wgpu::Buffer,
    struct_init_field_expected_ref_payload: wgpu::Buffer,
    struct_init_field_context_instance: wgpu::Buffer,
    struct_init_field_ordinal: wgpu::Buffer,
    struct_init_field_ordinal_by_node: wgpu::Buffer,
    name_scan_steps: Vec<NameScanStep>,
    name_bind_groups: NameBindGroups,
    language_name_bind_groups: LanguageNameBindGroups,
    loop_params: LaniusBuffer<LoopDepthParams>,
    loop_scan_steps: Vec<LoopDepthScanStep>,
    fn_params: LaniusBuffer<FnContextParams>,
    fn_scan_steps: Vec<FnContextScanStep>,
    loop_bind_groups: LoopDepthBindGroups,
    fn_context_bind_groups: FnContextBindGroups,
    visible_bind_groups: VisibleBindGroups,
    calls: CallBindGroups,
    methods: MethodBindGroups,
    type_instances_clear: wgpu::BindGroup,
    type_instances_decl_generic_params: wgpu::BindGroup,
    type_instances_generic_param_use_slots: wgpu::BindGroup,
    type_instances_collect: wgpu::BindGroup,
    type_instances_collect_named: wgpu::BindGroup,
    type_instances_collect_aggregate_refs: wgpu::BindGroup,
    type_instances_collect_aggregate_details: wgpu::BindGroup,
    type_instances_collect_named_arg_refs: wgpu::BindGroup,
    type_instances_decl_refs: wgpu::BindGroup,
    type_instances_member_receivers: wgpu::BindGroup,
    type_instances_member_results: wgpu::BindGroup,
    type_instances_member_substitute: wgpu::BindGroup,
    type_instances_struct_init_clear: wgpu::BindGroup,
    type_instances_struct_init_fields: wgpu::BindGroup,
    type_instances_struct_init_substitute: wgpu::BindGroup,
    type_instances_array_return_refs: wgpu::BindGroup,
    type_instances_array_literal_return_refs: wgpu::BindGroup,
    type_instances_enum_ctors: wgpu::BindGroup,
    type_instances_array_index_results: wgpu::BindGroup,
    type_instances_validate_aggregate_access: wgpu::BindGroup,
    conditions_hir: wgpu::BindGroup,
    tokens: wgpu::BindGroup,
    control: wgpu::BindGroup,
    scope: wgpu::BindGroup,
    scope_hir: wgpu::BindGroup,
}

pub struct GpuCodegenBuffers<'a> {
    pub name_id_by_token: &'a wgpu::Buffer,
    pub enclosing_fn: &'a wgpu::Buffer,
    pub visible_decl: &'a wgpu::Buffer,
    pub visible_type: &'a wgpu::Buffer,
    pub path_count_out: &'a wgpu::Buffer,
    pub path_owner_token: &'a wgpu::Buffer,
    pub path_id_by_owner_hir: &'a wgpu::Buffer,
    pub resolved_value_decl: &'a wgpu::Buffer,
    pub resolved_value_status: &'a wgpu::Buffer,
    pub decl_count_out: &'a wgpu::Buffer,
    pub decl_kind: &'a wgpu::Buffer,
    pub decl_name_token: &'a wgpu::Buffer,
    pub decl_id_by_name_token: &'a wgpu::Buffer,
    pub decl_hir_node: &'a wgpu::Buffer,
    pub decl_parent_type_decl: &'a wgpu::Buffer,
    pub decl_type_ref_tag: &'a wgpu::Buffer,
    pub decl_type_ref_payload: &'a wgpu::Buffer,
    pub type_expr_ref_tag: &'a wgpu::Buffer,
    pub type_expr_ref_payload: &'a wgpu::Buffer,
    pub module_value_path_call_head: &'a wgpu::Buffer,
    pub module_value_path_call_open: &'a wgpu::Buffer,
    pub module_value_path_const_head: &'a wgpu::Buffer,
    pub module_value_path_const_end: &'a wgpu::Buffer,
    pub call_fn_index: &'a wgpu::Buffer,
    pub call_intrinsic_tag: &'a wgpu::Buffer,
    pub fn_entrypoint_tag: &'a wgpu::Buffer,
    pub call_return_type: &'a wgpu::Buffer,
    pub call_return_type_token: &'a wgpu::Buffer,
    pub call_param_count: &'a wgpu::Buffer,
    pub call_param_type: &'a wgpu::Buffer,
    pub method_decl_module_id: &'a wgpu::Buffer,
    pub method_decl_name_token: &'a wgpu::Buffer,
    pub method_decl_name_id: &'a wgpu::Buffer,
    pub method_decl_receiver_ref_tag: &'a wgpu::Buffer,
    pub method_decl_receiver_ref_payload: &'a wgpu::Buffer,
    pub method_decl_param_offset: &'a wgpu::Buffer,
    pub method_decl_receiver_mode: &'a wgpu::Buffer,
    pub method_decl_visibility: &'a wgpu::Buffer,
    pub method_key_to_fn_token: &'a wgpu::Buffer,
    pub method_key_status: &'a wgpu::Buffer,
    pub method_call_receiver_ref_tag: &'a wgpu::Buffer,
    pub method_call_receiver_ref_payload: &'a wgpu::Buffer,
    pub method_call_name_id: &'a wgpu::Buffer,
    pub method_call_site_module_id: &'a wgpu::Buffer,
    pub type_instance_kind: &'a wgpu::Buffer,
    pub type_instance_decl_token: &'a wgpu::Buffer,
    pub type_instance_arg_start: &'a wgpu::Buffer,
    pub type_instance_arg_count: &'a wgpu::Buffer,
    pub type_instance_arg_ref_tag: &'a wgpu::Buffer,
    pub type_instance_arg_ref_payload: &'a wgpu::Buffer,
    pub type_instance_len_kind: &'a wgpu::Buffer,
    pub type_instance_len_payload: &'a wgpu::Buffer,
    pub fn_return_ref_tag: &'a wgpu::Buffer,
    pub fn_return_ref_payload: &'a wgpu::Buffer,
    pub member_result_ref_tag: &'a wgpu::Buffer,
    pub member_result_ref_payload: &'a wgpu::Buffer,
    pub member_result_field_ordinal: &'a wgpu::Buffer,
    pub struct_init_field_expected_ref_tag: &'a wgpu::Buffer,
    pub struct_init_field_expected_ref_payload: &'a wgpu::Buffer,
    pub struct_init_field_ordinal: &'a wgpu::Buffer,
    pub struct_init_field_ordinal_by_node: &'a wgpu::Buffer,
}
