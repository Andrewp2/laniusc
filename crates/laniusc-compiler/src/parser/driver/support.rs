use super::*;
use crate::gpu::buffers::LaniusBuffer;

/// Reads a parser boolean environment flag with either truthy or strict semantics.
pub(super) fn bool_from_env(name: &str, default_true: bool) -> bool {
    if default_true {
        crate::gpu::env::env_bool_truthy(name, true)
    } else {
        crate::gpu::env::env_bool_strict(name, false)
    }
}

/// Emits a parser GPU timer stamp when timing is enabled.
pub(super) fn stamp_timer(
    timer_ref: &mut Option<&mut GpuTimer>,
    encoder: &mut wgpu::CommandEncoder,
    label: impl Into<String>,
) {
    if let Some(timer) = timer_ref.as_deref_mut() {
        timer.stamp(encoder, label);
    }
}

/// Mirrors the lexer: allow disabling readback with `LANIUS_READBACK=0`.
pub(super) fn readback_enabled() -> bool {
    bool_from_env("LANIUS_READBACK", true)
}

/// Hashes parse-table contents that affect resident parser buffer reuse.
pub(super) fn table_fingerprint(tables: &PrecomputedParseTables) -> u64 {
    if let Some(fingerprint) = tables.loaded_content_fingerprint() {
        return fingerprint;
    }
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    tables.n_kinds.hash(&mut hasher);
    tables.n_productions.hash(&mut hasher);
    tables.n_nonterminals.hash(&mut hasher);
    tables.start_nonterminal.hash(&mut hasher);
    tables.sc_superseq.hash(&mut hasher);
    tables.sc_off.hash(&mut hasher);
    tables.sc_len.hash(&mut hasher);
    tables.pp_superseq.hash(&mut hasher);
    tables.pp_off.hash(&mut hasher);
    tables.pp_len.hash(&mut hasher);
    tables.prod_arity.hash(&mut hasher);
    tables.ll1_predict.hash(&mut hasher);
    tables.prod_rhs_off.hash(&mut hasher);
    tables.prod_rhs_len.hash(&mut hasher);
    tables.prod_rhs.hash(&mut hasher);
    hasher.finish()
}

#[cfg(test)]
mod tests {
    use super::table_fingerprint;
    use crate::parser::tables::PrecomputedParseTables;

    #[test]
    fn generated_table_fingerprint_tracks_content_mutation() {
        let mut tables = PrecomputedParseTables::new(4, 1);
        let before = table_fingerprint(&tables);
        tables.prod_arity[0] = 1;

        assert_ne!(table_fingerprint(&tables), before);
    }
}

/// Hashes WGPU buffer identities that affect resident parser bind-group reuse.
pub(super) fn buffer_fingerprint(buffers: &[&wgpu::Buffer]) -> u64 {
    crate::gpu::passes_core::buffer_fingerprint(buffers)
}

/// Writes a typed parser uniform value using the shader layout expected by WGPU.
pub(super) fn write_uniform<T>(queue: &wgpu::Queue, buffer: &LaniusBuffer<T>, value: &T)
where
    T: encase::ShaderType + encase::internal::WriteInto,
{
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(value)
        .expect("failed to write parser uniform buffer");
    queue.write_buffer(buffer, 0, ub.as_ref());
}

// Optional singleton, mirroring the lexer's `lex_on_gpu`.
static GPU_PARSER: OnceLock<GpuParser> = OnceLock::new();

/// Returns the process-wide parser used by convenience GPU parser entry points.
pub async fn get_global_parser() -> &'static GpuParser {
    GPU_PARSER.get_or_init(|| pollster::block_on(GpuParser::new()).expect("GPU parser init"))
}

/// Reads little-endian `u32` words from parser status or debug readback bytes.
pub(super) fn read_u32_words(bytes: &[u8], count: usize) -> Result<Vec<u32>> {
    if bytes.len() < count * 4 {
        anyhow::bail!("parser status readback was truncated");
    }
    let mut out = Vec::with_capacity(count);
    for chunk in bytes.chunks_exact(4).take(count) {
        out.push(u32::from_le_bytes(chunk.try_into().unwrap()));
    }
    Ok(out)
}
