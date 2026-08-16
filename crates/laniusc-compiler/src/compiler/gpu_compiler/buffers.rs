use super::*;
use crate::{gpu::buffers::TrackedBufferView, type_checker::GpuTypeCheckHirItemBuffers};

/// Builds the borrowed workspace view used by type-check recording.
///
/// The array is deliberately supplied by the caller. Its buffers are parser
/// phase storage whose contents are dead after compact HIR materialization;
/// keeping the array outside the HIR view makes that lifetime explicit and
/// lets the compiler graph recolor the slots without retaining parser state.
pub(super) fn typecheck_workspace<'a>(
    phase_workspace: &[TrackedBufferView<'a>],
    lexer: &'a LexerBuffers,
) -> Vec<TrackedBufferView<'a>> {
    let mut workspace = Vec::with_capacity(phase_workspace.len() + 7);
    workspace.extend_from_slice(phase_workspace);
    let lexer_workspace: [TrackedBufferView<'a>; 7] = [
        (&lexer.tok_types).into(),
        (&lexer.flags_packed).into(),
        (&lexer.s_all_final).into(),
        (&lexer.s_keep_final).into(),
        (&lexer.end_positions).into(),
        (&lexer.types_compact).into(),
        (&lexer.all_index_compact).into(),
    ];
    workspace.extend(lexer_workspace);
    workspace
}

/// Assembles the type-check input without cloning parser buffers. The HIR
/// handle is the persistent semantic input; upstream storage is phase-local
/// workspace only.
pub(super) fn typecheck_hir_item_buffers<'a>(
    hir: &'a crate::parser::buffers::GpuHirView,
    upstream_workspace: &'a [TrackedBufferView<'a>],
    parser_feature_flags: u32,
    module_record_capacity: u32,
    call_param_row_capacity: u32,
    call_arg_row_capacity: u32,
    semantic_interface_required: bool,
) -> GpuTypeCheckHirItemBuffers<'a> {
    GpuTypeCheckHirItemBuffers {
        parser_feature_flags,
        module_record_capacity,
        call_param_row_capacity,
        call_arg_row_capacity,
        semantic_interface_required,
        hir,
        upstream_workspace,
    }
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
