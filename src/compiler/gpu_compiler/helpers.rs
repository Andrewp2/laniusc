use super::*;

pub(super) fn x86_inst_hir_node_count_for_backend_capacity(
    parser_tree_capacity: u32,
    semantic_hir_count: u32,
) -> u32 {
    semantic_hir_count.max(1).min(parser_tree_capacity.max(1))
}

pub(super) fn buffer_if_wgpu_u32_words(
    buffer: &wgpu::Buffer,
    words: usize,
) -> Option<&wgpu::Buffer> {
    (buffer.size() >= words.saturating_mul(4) as u64).then_some(buffer)
}

pub(super) fn hir_node_capacity_for_parser_emit(
    parser_tree_capacity: u32,
    parser_emit_len: u32,
) -> u32 {
    parser_emit_len.max(1).min(parser_tree_capacity.max(1))
}

pub(super) fn trace_wasm_compile(stage: &str) {
    if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
        eprintln!("[laniusc][wasm] {stage}");
    }
}

pub(in crate::compiler) fn prepare_source_for_gpu(src: &str) -> Result<String, CompileError> {
    Ok(src.to_string())
}

pub(in crate::compiler) fn prepare_source_for_gpu_from_path(
    path: impl AsRef<Path>,
) -> Result<String, CompileError> {
    fs::read_to_string(path.as_ref()).map_err(|err| {
        CompileError::GpuFrontend(format!("read {}: {err}", path.as_ref().display()))
    })
}
