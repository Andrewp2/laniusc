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

/// Hashes WGPU buffer identities that affect resident parser bind-group reuse.
pub(super) fn buffer_fingerprint(buffers: &[&wgpu::Buffer]) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    for buffer in buffers {
        buffer.hash(&mut hasher);
    }
    hasher.finish()
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

/// Loads the token-to-parser-kind frontend pass.
pub(super) fn make_tokens_to_kinds_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_to_kinds",
        shader: "parser/tokens/to/kinds"
    )
}

/// Loads the identifier refinement pass for parser token kinds.
pub(super) fn make_tokens_to_identifier_kinds_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_to_identifier_kinds",
        shader: "parser/tokens/to/identifier_kinds"
    )
}

/// Loads the local type-path context pass for parser tokens.
pub(super) fn make_tokens_type_path_context_01_local_pass(
    device: &wgpu::Device,
) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_type_path_context_01_local",
        shader: "parser/tokens/type/path/context/01_local"
    )
}

/// Loads the apply type-path context pass for parser tokens.
pub(super) fn make_tokens_type_path_context_02_apply_pass(
    device: &wgpu::Device,
) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_type_path_context_02_apply",
        shader: "parser/tokens/type/path/context/02_apply"
    )
}

/// Loads the local delimiter-depth pass for parser tokens.
pub(super) fn make_token_delimiters_01_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_delimiters_01_local",
        shader: "parser/tokens/delimiters/01_local"
    )
}

/// Loads the delimiter-depth scan pass for parser tokens.
pub(super) fn make_token_delimiters_02_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_delimiters_02_scan",
        shader: "parser/tokens/delimiters/02_scan"
    )
}

/// Loads the local delimiter-owner pass for parser tokens.
pub(super) fn make_token_delimiters_03_owner_local_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_delimiters_03_owner_local",
        shader: "parser/tokens/delimiters/03_owner_local"
    )
}

/// Loads the delimiter-owner apply pass for parser tokens.
pub(super) fn make_token_delimiters_04_owner_apply_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_delimiters_04_owner_apply",
        shader: "parser/tokens/delimiters/04_owner_apply"
    )
}

/// Loads the brace-context pass for parser tokens.
pub(super) fn make_tokens_brace_context_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_brace_context",
        shader: "parser/tokens/brace/context"
    )
}

/// Loads the local statement-phase context pass.
pub(super) fn make_tokens_statement_phase_01_local_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_statement_phase_01_local",
        shader: "parser/tokens/statement/phase/01_local"
    )
}

/// Loads the statement-phase context apply pass.
pub(super) fn make_tokens_statement_phase_02_apply_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_statement_phase_02_apply",
        shader: "parser/tokens/statement/phase/02_apply"
    )
}

/// Loads the local impl-header context pass.
pub(super) fn make_tokens_impl_header_01_local_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_impl_header_01_local",
        shader: "parser/tokens/impl/header/01_local"
    )
}

/// Loads the impl-header context apply pass.
pub(super) fn make_tokens_impl_header_02_apply_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_impl_header_02_apply",
        shader: "parser/tokens/impl/header/02_apply"
    )
}

/// Loads the local where-clause context pass.
pub(super) fn make_tokens_where_clause_01_local_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_where_clause_01_local",
        shader: "parser/tokens/where/clause/01_local"
    )
}

/// Loads the where-clause context apply pass.
pub(super) fn make_tokens_where_clause_02_apply_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_where_clause_02_apply",
        shader: "parser/tokens/where/clause/02_apply"
    )
}

/// Loads the local match-pattern context pass.
pub(super) fn make_tokens_match_pattern_01_local_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_match_pattern_01_local",
        shader: "parser/tokens/match/pattern/01_local"
    )
}

/// Loads the match-pattern context apply pass.
pub(super) fn make_tokens_match_pattern_02_apply_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_match_pattern_02_apply",
        shader: "parser/tokens/match/pattern/02_apply"
    )
}

/// Loads the parenthesis depth-block pass.
pub(super) fn make_tokens_paren_match_01_depth_blocks_pass(
    device: &wgpu::Device,
) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_paren_match_01_depth_blocks",
        shader: "parser/tokens/paren_match_01_depth_blocks"
    )
}

/// Loads the brace depth-block pass.
pub(super) fn make_tokens_brace_match_01_depth_blocks_pass(
    device: &wgpu::Device,
) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_brace_match_01_depth_blocks",
        shader: "parser/tokens/brace/match/01_depth_blocks"
    )
}

/// Loads the bracket depth-block pass.
pub(super) fn make_tokens_bracket_match_01_depth_blocks_pass(
    device: &wgpu::Device,
) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_bracket_match_01_depth_blocks",
        shader: "parser/tokens/bracket/match/01_depth_blocks"
    )
}

/// Loads the angle-bracket depth-block pass.
pub(super) fn make_tokens_angle_match_01_depth_blocks_pass(
    device: &wgpu::Device,
) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_angle_match_01_depth_blocks",
        shader: "parser/tokens/angle_match_01_depth_blocks"
    )
}

/// Loads the brace minimum-depth tree construction pass.
pub(super) fn make_tokens_brace_match_02_build_min_tree_pass(
    device: &wgpu::Device,
) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_brace_match_02_build_min_tree",
        shader: "parser/tokens/brace/match/02_build_min_tree"
    )
}

/// Loads the bracket pseudo-edge pairing pass.
pub(super) fn make_tokens_bracket_match_03_pair_pse_pass(
    device: &wgpu::Device,
) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_bracket_match_03_pair_pse",
        shader: "parser/tokens/bracket/match/03_pair_pse"
    )
}

/// Loads the brace pseudo-edge pairing pass.
pub(super) fn make_tokens_brace_match_03_pair_pse_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tokens_brace_match_03_pair_pse",
        shader: "parser/tokens/brace/match/03_pair_pse"
    )
}

/// Loads the pass that writes active tree-row dispatch arguments.
pub(super) fn make_tree_active_dispatch_args_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tree_active_dispatch_args",
        shader: "parser/tree/active_dispatch_args"
    )
}

/// Loads the pass that writes feature-specific tree dispatch arguments.
pub(super) fn make_tree_feature_dispatch_args_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_tree_feature_dispatch_args",
        shader: "parser/tree/feature_dispatch_args"
    )
}

/// Loads the pass that writes active adjacent-pair dispatch arguments.
pub(super) fn make_active_pair_dispatch_args_pass(device: &wgpu::Device) -> Result<PassData> {
    crate::gpu::passes_core::make_main_pass!(
        device,
        "parser_active_pair_dispatch_args",
        shader: "parser/active_pair_dispatch_args"
    )
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
