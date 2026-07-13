#[derive(Clone, Copy)]
/// Struct declaration/member metadata buffers needed by WASM lowering.
pub struct GpuWasmStructMetadataBuffers<'a> {
    pub member_receiver_node: &'a wgpu::Buffer,
    pub struct_decl_field_count: &'a wgpu::Buffer,
    pub lit_field_parent_lit: &'a wgpu::Buffer,
    pub lit_context_stmt_node: &'a wgpu::Buffer,
    pub lit_field_start: &'a wgpu::Buffer,
    pub lit_field_count: &'a wgpu::Buffer,
    pub lit_field_value_node: &'a wgpu::Buffer,
    pub lit_field_next: &'a wgpu::Buffer,
    pub member_name_token: &'a wgpu::Buffer,
    pub member_result_field_ordinal: &'a wgpu::Buffer,
    pub member_result_field_node: &'a wgpu::Buffer,
    pub struct_init_field_ordinal_by_node: &'a wgpu::Buffer,
    pub struct_init_field_decl_node_by_node: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
/// Enum-match metadata buffers needed by WASM lowering.
pub struct GpuWasmEnumMatchMetadataBuffers<'a> {
    pub variant_ordinal: &'a wgpu::Buffer,
    pub match_scrutinee_node: &'a wgpu::Buffer,
    pub match_arm_start: &'a wgpu::Buffer,
    pub match_arm_count: &'a wgpu::Buffer,
    pub match_arm_next: &'a wgpu::Buffer,
    pub match_arm_pattern_node: &'a wgpu::Buffer,
    pub match_arm_payload_start: &'a wgpu::Buffer,
    pub match_arm_payload_count: &'a wgpu::Buffer,
    pub match_arm_result_node: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
/// Call and call-argument metadata buffers needed by WASM lowering.
pub struct GpuWasmCallMetadataBuffers<'a> {
    pub callee_node: &'a wgpu::Buffer,
    pub context_stmt: &'a wgpu::Buffer,
    pub arg_start: &'a wgpu::Buffer,
    pub arg_parent_call: &'a wgpu::Buffer,
    pub arg_end: &'a wgpu::Buffer,
    pub arg_count: &'a wgpu::Buffer,
    pub arg_ordinal: &'a wgpu::Buffer,
    pub param_row_count_out: &'a wgpu::Buffer,
    pub param_row_fn_token: &'a wgpu::Buffer,
    pub param_row_ordinal: &'a wgpu::Buffer,
    pub param_row_type: &'a wgpu::Buffer,
    pub param_row_start: &'a wgpu::Buffer,
    pub param_row_count: &'a wgpu::Buffer,
    pub arg_row_node: &'a wgpu::Buffer,
    pub arg_row_call_node: &'a wgpu::Buffer,
    pub arg_row_ordinal: &'a wgpu::Buffer,
    pub arg_row_start: &'a wgpu::Buffer,
    pub arg_row_count: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
/// Expression and statement metadata buffers needed by WASM lowering.
pub struct GpuWasmExprMetadataBuffers<'a> {
    pub record: &'a wgpu::Buffer,
    pub result_root_node: &'a wgpu::Buffer,
    pub int_value: &'a wgpu::Buffer,
    pub float_bits: &'a wgpu::Buffer,
    pub string_start: &'a wgpu::Buffer,
    pub string_len: &'a wgpu::Buffer,
    pub string_data_words: &'a wgpu::Buffer,
    pub string_pool_len: &'a wgpu::Buffer,
    pub stmt_record: &'a wgpu::Buffer,
    pub nearest_stmt_node: &'a wgpu::Buffer,
    pub nearest_block_node: &'a wgpu::Buffer,
    pub nearest_enclosing_control_node: &'a wgpu::Buffer,
    pub nearest_loop_node: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
/// Parser-owned array metadata buffers needed by WASM lowering.
pub struct GpuWasmArrayMetadataBuffers<'a> {
    pub lit_first_element: &'a wgpu::Buffer,
    pub lit_element_count: &'a wgpu::Buffer,
    pub lit_context_stmt_node: &'a wgpu::Buffer,
    pub element_parent_lit: &'a wgpu::Buffer,
    pub element_ordinal: &'a wgpu::Buffer,
    pub element_next: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
/// Qualified path metadata buffers needed by WASM lowering.
pub struct GpuWasmPathMetadataBuffers<'a> {
    pub count_out: &'a wgpu::Buffer,
    pub segment_count: &'a wgpu::Buffer,
    pub segment_base: &'a wgpu::Buffer,
    pub segment_token: &'a wgpu::Buffer,
    pub id_by_owner_hir: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
/// Dense semantic-HIR tree buffers needed by WASM lowering.
pub struct GpuWasmSemanticHirBuffers<'a> {
    pub count: &'a wgpu::Buffer,
    pub prefix_before_node: &'a wgpu::Buffer,
    pub dense_node: &'a wgpu::Buffer,
    pub subtree_end: &'a wgpu::Buffer,
    pub parent: &'a wgpu::Buffer,
    pub first_child: &'a wgpu::Buffer,
    pub next_sibling: &'a wgpu::Buffer,
    pub depth: &'a wgpu::Buffer,
    pub child_index: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
/// Complete GPU-resident frontend and type-check input contract for WASM lowering.
pub struct GpuWasmCodegenInputs<'a> {
    pub token: &'a wgpu::Buffer,
    pub token_count: &'a wgpu::Buffer,
    pub active_hir_dispatch_args: &'a wgpu::Buffer,
    pub node_kind: &'a wgpu::Buffer,
    pub parent: &'a wgpu::Buffer,
    pub first_child: &'a wgpu::Buffer,
    pub next_sibling: &'a wgpu::Buffer,
    pub hir_kind: &'a wgpu::Buffer,
    pub hir_item_kind: &'a wgpu::Buffer,
    pub hir_token_pos: &'a wgpu::Buffer,
    pub hir_token_end: &'a wgpu::Buffer,
    pub hir_status: &'a wgpu::Buffer,
    pub parser_feature_flags: &'a wgpu::Buffer,
    pub visible_decl: &'a wgpu::Buffer,
    pub visible_type: &'a wgpu::Buffer,
    pub name_id_by_token: &'a wgpu::Buffer,
    pub language_name_id: &'a wgpu::Buffer,
    pub enclosing_fn: &'a wgpu::Buffer,
    pub structs: GpuWasmStructMetadataBuffers<'a>,
    pub enum_matches: GpuWasmEnumMatchMetadataBuffers<'a>,
    pub calls: GpuWasmCallMetadataBuffers<'a>,
    pub expressions: GpuWasmExprMetadataBuffers<'a>,
    pub arrays: GpuWasmArrayMetadataBuffers<'a>,
    pub paths: GpuWasmPathMetadataBuffers<'a>,
    pub semantic_hir: GpuWasmSemanticHirBuffers<'a>,
    pub hir_param_record: &'a wgpu::Buffer,
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
    pub method_decl_receiver_ref_tag: &'a wgpu::Buffer,
    pub method_decl_receiver_ref_payload: &'a wgpu::Buffer,
    pub method_decl_param_offset: &'a wgpu::Buffer,
    pub method_decl_receiver_mode: &'a wgpu::Buffer,
    pub method_call_receiver_ref_tag: &'a wgpu::Buffer,
    pub method_call_receiver_ref_payload: &'a wgpu::Buffer,
    pub type_instance_decl_token: &'a wgpu::Buffer,
    pub type_instance_arg_start: &'a wgpu::Buffer,
    pub type_instance_arg_count: &'a wgpu::Buffer,
    pub type_instance_arg_ref_tag: &'a wgpu::Buffer,
    pub type_instance_arg_ref_payload: &'a wgpu::Buffer,
    pub type_decl_hir_node_by_token: &'a wgpu::Buffer,
    pub fn_return_ref_tag: &'a wgpu::Buffer,
    pub fn_return_ref_payload: &'a wgpu::Buffer,
    pub member_result_ref_tag: &'a wgpu::Buffer,
    pub member_result_ref_payload: &'a wgpu::Buffer,
    pub struct_init_field_expected_ref_tag: &'a wgpu::Buffer,
    pub struct_init_field_expected_ref_payload: &'a wgpu::Buffer,
}
