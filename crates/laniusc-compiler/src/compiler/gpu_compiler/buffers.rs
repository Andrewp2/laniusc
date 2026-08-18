use super::*;
use crate::type_checker::GpuTypeCheckHirItemBuffers;

/// Borrows the complete compiler-graph input at the parser/type-check boundary.
///
/// The compact HIR is the persistent semantic input. Parser and lexer storage
/// whose contents are dead after HIR materialization is exposed only for the
/// duration of `consume`, allowing the type-check graph to recolor those slots
/// without accidentally retaining frontend scratch as semantic state.
pub(super) fn with_typecheck_hir_items<'a, R>(
    parser: &'a crate::parser::buffers::ParserBuffers,
    hir: &'a crate::parser::buffers::GpuHirView,
    lexer: &'a LexerBuffers,
    parser_feature_flags: u32,
    module_record_capacity: u32,
    call_param_row_capacity: u32,
    call_arg_row_capacity: u32,
    semantic_interface_required: bool,
    consume: impl FnOnce(GpuTypeCheckHirItemBuffers<'_>) -> R,
) -> R {
    let phase_workspace = parser.post_hir_workspace(hir);
    let mut upstream_workspace = Vec::with_capacity(phase_workspace.len() + 7);
    upstream_workspace.extend_from_slice(&phase_workspace);
    upstream_workspace.extend(lexer.post_lex_workspace());
    consume(GpuTypeCheckHirItemBuffers {
        parser_feature_flags,
        module_record_capacity,
        call_param_row_capacity,
        call_arg_row_capacity,
        semantic_interface_required,
        hir,
        upstream_workspace: &upstream_workspace,
    })
}

/// Builds the compact HIR view consumed by semantic-interface export.
pub(super) fn semantic_interface_hir_buffers(
    hir: &crate::parser::buffers::GpuHirView,
) -> gpu_type_checker::GpuSemanticInterfaceHirBuffers<'_> {
    gpu_type_checker::GpuSemanticInterfaceHirBuffers {
        compact_hir_capacity: hir.capacity,
        compact_hir_count: &hir.count,
        compact_hir_core: &hir.core,
        compact_hir_payload: &hir.payload,
        compact_const_value: &hir.const_value,
        compact_fn_return_type: &hir.fn_return_type,
        compact_type_alias_target: &hir.type_alias_target,
        compact_const_type: &hir.const_type,
        compact_param_count: &hir.param_count,
        compact_params: &hir.params,
        compact_param_ranges: &hir.param_ranges,
        compact_type_arg_count: &hir.type_arg_count,
        compact_type_args: &hir.type_args,
        compact_type_arg_ranges: &hir.type_arg_ranges,
        compact_generic_param_count: &hir.generic_param_count,
        compact_generic_params: &hir.generic_params,
        compact_path_count: &hir.path_count,
        compact_paths: &hir.paths,
        compact_path_segment_count: &hir.path_segment_count,
        compact_path_segments: &hir.path_segments,
        compact_field_count: &hir.field_count,
        compact_fields: &hir.fields,
        compact_variant_count: &hir.variant_count,
        compact_variants: &hir.variants,
        compact_variant_payload_count: &hir.variant_payload_count,
        compact_variant_payload_row_count: &hir.variant_payload_row_count,
        compact_variant_payloads: &hir.variant_payloads,
        compact_method_count: &hir.method_count,
        compact_method_cores: &hir.method_cores,
        compact_method_signatures: &hir.method_signatures,
    }
}
