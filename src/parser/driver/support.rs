use super::*;

pub(super) fn bool_from_env(name: &str, default_true: bool) -> bool {
    if default_true {
        crate::gpu::env::env_bool_truthy(name, true)
    } else {
        crate::gpu::env::env_bool_strict(name, false)
    }
}

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

// ---------------------------------------------------------------------

pub(super) fn decode_ll1_seed_plan(words: [u32; 8]) -> Ll1SeedPlanResult {
    Ll1SeedPlanResult {
        accepted: words[0] != 0,
        pos: words[1],
        error_code: words[2],
        detail: words[3],
        steps: words[4],
        seed_count: words[5],
        max_depth: words[6],
        emit_len: words[7],
    }
}

pub(super) fn decode_ll1_block_summaries(words: &[u32]) -> Vec<Ll1BlockSummary> {
    words
        .chunks_exact(LL1_BLOCK_STATUS_WORDS)
        .map(|chunk| Ll1BlockSummary {
            status: chunk[0],
            begin: chunk[1],
            end: chunk[2],
            pos: chunk[3],
            steps: chunk[4],
            emit_len: chunk[5],
            stack_depth: chunk[6],
            error_code: chunk[7],
            detail: chunk[8],
            first_production: chunk[9],
        })
        .collect()
}

pub(super) fn table_fingerprint(tables: &PrecomputedParseTables) -> u64 {
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

pub(super) fn buffer_fingerprint(buffers: &[&wgpu::Buffer]) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    for buffer in buffers {
        buffer.hash(&mut hasher);
    }
    hasher.finish()
}

pub(super) fn write_uniform<T>(queue: &wgpu::Queue, buffer: &LaniusBuffer<T>, value: &T)
where
    T: encase::ShaderType + encase::internal::WriteInto,
{
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(value)
        .expect("failed to write parser uniform buffer");
    queue.write_buffer(buffer, 0, ub.as_ref());
}

// Optional singleton, mirroring the lexer’s `lex_on_gpu`.
static GPU_PARSER: OnceLock<GpuParser> = OnceLock::new();

pub async fn get_global_parser() -> &'static GpuParser {
    GPU_PARSER.get_or_init(|| pollster::block_on(GpuParser::new()).expect("GPU parser init"))
}

pub(super) fn make_tokens_to_kinds_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_to_kinds",
        shader: "tokens_to_kinds"
    )
}

pub(super) fn make_direct_hir_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_direct_hir",
        shader: "direct_hir"
    )
}

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
