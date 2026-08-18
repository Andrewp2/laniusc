use anyhow::Result;

use super::{Pass, passes::LexerPasses};
use crate::{
    gpu::{
        compiler_graph::{
            AccessMode,
            CompilerGraphBuilder,
            CompilerPhase,
            MaterializedCompilerGraph,
            PassAccess,
            PassDesc,
            ReflectedResourceBinding,
            ResourceClass,
            ResourceDesc,
            ResourceDomain,
            ResourceId,
        },
        operations::{ClearBuffersOperation, CopyBufferOperation},
        passes_core::PassData,
        workspace::WorkspaceUsageClass,
    },
    lexer::{debug::DebugOutput, tables::dfa::N_STATES},
};

pub(in crate::lexer) struct LexerCompilerGraph {
    materialized: MaterializedCompilerGraph,
}

#[derive(Clone, Copy)]
struct LexerGraphResources {
    in_bytes: ResourceId,
    next_emit: ResourceId,
    next_u8: ResourceId,
    token_map: ResourceId,
    source_file_count: ResourceId,
    source_file_start: ResourceId,
    source_file_len: ResourceId,
    source_file_start_flags: ResourceId,
    source_file_end_flags: ResourceId,
    dfa_ping: ResourceId,
    dfa_pong: ResourceId,
    dfa_chunk_summaries: ResourceId,
    tok_types: ResourceId,
    flags_packed: ResourceId,
    s_all_final: ResourceId,
    s_keep_final: ResourceId,
    end_positions: ResourceId,
    types_compact: ResourceId,
    all_index_compact: ResourceId,
    token_count: ResourceId,
    parser_feature_flags: ResourceId,
    tokens_out: ResourceId,
    token_file_id: ResourceId,
    token_count_readback: ResourceId,
}

impl LexerCompilerGraph {
    pub(in crate::lexer) fn new(
        device: &wgpu::Device,
        byte_capacity: u32,
        source_file_capacity: u32,
        next_emit_words: usize,
        next_u8_words: usize,
        token_map_words: usize,
        passes: &LexerPasses,
    ) -> Result<Self> {
        let (graph, _) = build_graph(
            byte_capacity,
            source_file_capacity,
            next_emit_words,
            next_u8_words,
            token_map_words,
            passes,
        )
        .map_err(anyhow::Error::msg)?;
        let materialized =
            MaterializedCompilerGraph::new_with_upstream_storage(device, "lexer", graph, &[])
                .map_err(anyhow::Error::msg)?;
        Ok(Self { materialized })
    }

    pub(in crate::lexer) fn buffer<T>(
        &self,
        name: &str,
    ) -> Result<crate::gpu::buffers::LaniusBuffer<T>> {
        self.materialized.buffer(name)
    }

    pub(in crate::lexer) fn validate_reflected_runtime_bindings(
        &self,
        operation: &'static str,
        resources: &std::collections::HashMap<String, wgpu::BindingResource<'_>>,
        dispatch_args: Option<&crate::gpu::buffers::LaniusBuffer<u32>>,
    ) -> Result<()> {
        self.materialized
            .validate_reflected_runtime_bindings(operation, resources, dispatch_args)
    }

    pub(in crate::lexer) fn job_initialize_operation(
        &self,
        flags_packed: &crate::gpu::buffers::LaniusBuffer<u32>,
        source_file_start_flags: &crate::gpu::buffers::LaniusBuffer<u32>,
        source_file_end_flags: &crate::gpu::buffers::LaniusBuffer<u32>,
        token_count: &crate::gpu::buffers::LaniusBuffer<u32>,
        parser_feature_flags: &crate::gpu::buffers::LaniusBuffer<u32>,
    ) -> Result<ClearBuffersOperation> {
        ClearBuffersOperation::new(
            &self.materialized,
            "lexer.job_initialize",
            &[
                ("flags_packed", flags_packed.into()),
                ("source_file_start_flags", source_file_start_flags.into()),
                ("source_file_end_flags", source_file_end_flags.into()),
                ("token_count", token_count.into()),
                ("parser_feature_flags", parser_feature_flags.into()),
            ],
        )
    }

    pub(in crate::lexer) fn count_readback_operations(
        &self,
        token_count: &crate::gpu::buffers::LaniusBuffer<u32>,
        parser_feature_flags: &crate::gpu::buffers::LaniusBuffer<u32>,
        readback: &crate::gpu::buffers::LaniusBuffer<u8>,
    ) -> Result<[CopyBufferOperation; 2]> {
        Ok([
            CopyBufferOperation::new(
                &self.materialized,
                "lexer.token_count.readback",
                "token_count",
                token_count,
                0,
                "token_count_readback",
                readback,
                0,
                4,
            )?,
            CopyBufferOperation::new(
                &self.materialized,
                "lexer.parser_feature_flags.readback",
                "parser_feature_flags",
                parser_feature_flags,
                0,
                "token_count_readback",
                readback,
                4,
                4,
            )?,
        ])
    }
}

fn storage(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    domain: ResourceDomain,
    class: ResourceClass,
    bytes: u64,
) -> Result<ResourceId, String> {
    graph.add_resource(ResourceDesc {
        name,
        domain,
        class,
        bytes: bytes.max(4),
        usage: WorkspaceUsageClass::Storage,
    })
}

fn reflected_pass(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    domain: ResourceDomain,
    data: &PassData,
    bindings: &[(&'static str, ResourceId, Option<AccessMode>)],
) -> Result<(), String> {
    let bindings = bindings
        .iter()
        .map(|&(binding, resource, mode)| ReflectedResourceBinding {
            binding,
            resource,
            mode,
        })
        .collect::<Vec<_>>();
    graph.add_reflected_compute_pass(
        name,
        CompilerPhase::Lex,
        domain,
        &data.reflection,
        &bindings,
    )?;
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn build_graph(
    byte_capacity: u32,
    source_file_capacity: u32,
    next_emit_words: usize,
    next_u8_words: usize,
    token_map_words: usize,
    passes: &LexerPasses,
) -> Result<
    (
        crate::gpu::compiler_graph::CompilerGraph,
        LexerGraphResources,
    ),
    String,
> {
    let bytes = u64::from(byte_capacity.max(1));
    let files = u64::from(source_file_capacity.max(1));
    let blocks = bytes.div_ceil(256);
    let dfa_words = blocks * N_STATES as u64;
    let mut graph = CompilerGraphBuilder::new();

    let resources = LexerGraphResources {
        in_bytes: storage(
            &mut graph,
            "in_bytes",
            ResourceDomain::SourceBytes,
            ResourceClass::Input,
            bytes,
        )?,
        next_emit: storage(
            &mut graph,
            "next_emit",
            ResourceDomain::Bytes,
            ResourceClass::Input,
            next_emit_words as u64 * 4,
        )?,
        next_u8: storage(
            &mut graph,
            "next_u8",
            ResourceDomain::Bytes,
            ResourceClass::Input,
            next_u8_words as u64 * 4,
        )?,
        token_map: storage(
            &mut graph,
            "token_map",
            ResourceDomain::Tokens,
            ResourceClass::Input,
            token_map_words as u64 * 4,
        )?,
        source_file_count: storage(
            &mut graph,
            "source_file_count",
            ResourceDomain::SourceBytes,
            ResourceClass::Input,
            4,
        )?,
        source_file_start: storage(
            &mut graph,
            "source_file_start",
            ResourceDomain::SourceBytes,
            ResourceClass::Input,
            files * 4,
        )?,
        source_file_len: storage(
            &mut graph,
            "source_file_len",
            ResourceDomain::SourceBytes,
            ResourceClass::Input,
            files * 4,
        )?,
        source_file_start_flags: storage(
            &mut graph,
            "source_file_start_flags",
            ResourceDomain::SourceBytes,
            ResourceClass::Workspace,
            (bytes + 1) * 4,
        )?,
        source_file_end_flags: storage(
            &mut graph,
            "source_file_end_flags",
            ResourceDomain::SourceBytes,
            ResourceClass::Workspace,
            (bytes + 1) * 4,
        )?,
        dfa_ping: storage(
            &mut graph,
            "dfa_ping",
            ResourceDomain::SourceBytes,
            ResourceClass::Workspace,
            dfa_words * 4,
        )?,
        dfa_pong: storage(
            &mut graph,
            "dfa_pong",
            ResourceDomain::SourceBytes,
            ResourceClass::Workspace,
            dfa_words * 4,
        )?,
        dfa_chunk_summaries: storage(
            &mut graph,
            "dfa_chunk_summaries",
            ResourceDomain::SourceBytes,
            ResourceClass::Workspace,
            dfa_words * 3 * 4,
        )?,
        tok_types: storage(
            &mut graph,
            "tok_types",
            ResourceDomain::Tokens,
            ResourceClass::Workspace,
            bytes * 4,
        )?,
        flags_packed: storage(
            &mut graph,
            "flags_packed",
            ResourceDomain::Tokens,
            ResourceClass::Workspace,
            bytes * 4,
        )?,
        s_all_final: storage(
            &mut graph,
            "s_all_final",
            ResourceDomain::Tokens,
            ResourceClass::Workspace,
            bytes * 4,
        )?,
        s_keep_final: storage(
            &mut graph,
            "s_keep_final",
            ResourceDomain::Tokens,
            ResourceClass::Workspace,
            bytes * 4,
        )?,
        end_positions: storage(
            &mut graph,
            "end_positions",
            ResourceDomain::Tokens,
            ResourceClass::Workspace,
            bytes * 4,
        )?,
        types_compact: storage(
            &mut graph,
            "types_compact",
            ResourceDomain::Tokens,
            ResourceClass::Workspace,
            bytes * 4,
        )?,
        all_index_compact: storage(
            &mut graph,
            "all_index_compact",
            ResourceDomain::Tokens,
            ResourceClass::Workspace,
            bytes * 4,
        )?,
        token_count: storage(
            &mut graph,
            "token_count",
            ResourceDomain::Tokens,
            ResourceClass::Output,
            4,
        )?,
        parser_feature_flags: storage(
            &mut graph,
            "parser_feature_flags",
            ResourceDomain::Tokens,
            ResourceClass::Output,
            4,
        )?,
        tokens_out: storage(
            &mut graph,
            "tokens_out",
            ResourceDomain::Tokens,
            ResourceClass::Output,
            bytes * core::mem::size_of::<super::GpuToken>() as u64,
        )?,
        token_file_id: storage(
            &mut graph,
            "token_file_id",
            ResourceDomain::Tokens,
            ResourceClass::Output,
            bytes * 4,
        )?,
        token_count_readback: storage(
            &mut graph,
            "token_count_readback",
            ResourceDomain::Tokens,
            ResourceClass::External,
            8,
        )?,
    };

    graph.add_pass(PassDesc {
        name: "lexer.job_initialize",
        phase: CompilerPhase::Lex,
        dispatch_domain: ResourceDomain::Bytes,
        accesses: vec![
            PassAccess::write("flags_packed", resources.flags_packed),
            PassAccess::write("source_file_start_flags", resources.source_file_start_flags),
            PassAccess::write("source_file_end_flags", resources.source_file_end_flags),
            PassAccess::write("token_count", resources.token_count),
            PassAccess::write("parser_feature_flags", resources.parser_feature_flags),
        ],
    })?;

    reflected_pass(
        &mut graph,
        <super::passes::source_file_boundaries::SourceFileBoundariesPass as Pass<
            super::buffers::GpuBuffers,
            DebugOutput,
        >>::NAME,
        ResourceDomain::SourceBytes,
        passes.source_file_boundaries.data(),
        &[
            ("source_file_count", resources.source_file_count, None),
            ("source_file_start", resources.source_file_start, None),
            ("source_file_len", resources.source_file_len, None),
            (
                "source_file_start_flags",
                resources.source_file_start_flags,
                Some(AccessMode::Write),
            ),
            (
                "source_file_end_flags",
                resources.source_file_end_flags,
                Some(AccessMode::Write),
            ),
        ],
    )?;
    reflected_pass(
        &mut graph,
        <super::passes::dfa::scan_inblock::Dfa01ScanInblockPass as Pass<
            super::buffers::GpuBuffers,
            DebugOutput,
        >>::NAME,
        ResourceDomain::SourceBytes,
        passes.dfa_01.data(),
        &[
            ("in_bytes", resources.in_bytes, None),
            (
                "source_file_start_flags",
                resources.source_file_start_flags,
                None,
            ),
            ("next_u8", resources.next_u8, None),
            (
                "block_summaries",
                resources.dfa_ping,
                Some(AccessMode::Write),
            ),
            (
                "chunk_summary_out",
                resources.dfa_chunk_summaries,
                Some(AccessMode::Write),
            ),
        ],
    )?;
    graph.add_pass(PassDesc {
        name: <super::passes::dfa::scan_block_summaries::Dfa02ScanBlockSummariesPass as Pass<
            super::buffers::GpuBuffers,
            DebugOutput,
        >>::NAME,
        phase: CompilerPhase::Lex,
        dispatch_domain: ResourceDomain::SourceBytes,
        accesses: vec![
            PassAccess::read_write("block_ping", resources.dfa_ping),
            PassAccess::initialize_read_write("block_pong", resources.dfa_pong),
        ],
    })?;
    reflected_pass(
        &mut graph,
        <super::passes::dfa::apply_block_prefix::Dfa03ApplyBlockPrefixPass as Pass<
            super::buffers::GpuBuffers,
            DebugOutput,
        >>::NAME,
        ResourceDomain::SourceBytes,
        passes.dfa_03.data(),
        &[
            ("in_bytes", resources.in_bytes, None),
            (
                "source_file_start_flags",
                resources.source_file_start_flags,
                None,
            ),
            (
                "source_file_end_flags",
                resources.source_file_end_flags,
                None,
            ),
            ("block_prefix_ping", resources.dfa_ping, None),
            ("block_prefix_pong", resources.dfa_pong, None),
            ("chunk_summaries", resources.dfa_chunk_summaries, None),
            ("token_map", resources.token_map, None),
            ("next_emit", resources.next_emit, None),
            (
                "flags_packed",
                resources.flags_packed,
                Some(AccessMode::Write),
            ),
            ("tok_types", resources.tok_types, Some(AccessMode::Write)),
        ],
    )?;
    reflected_pass(
        &mut graph,
        <super::passes::pair::sum_inblock::Pair01SumInblockPass as Pass<
            super::buffers::GpuBuffers,
            DebugOutput,
        >>::NAME,
        ResourceDomain::Tokens,
        passes.pair_01.data(),
        &[
            ("flags_packed", resources.flags_packed, None),
            (
                "block_totals_pair",
                resources.dfa_ping,
                Some(AccessMode::Write),
            ),
        ],
    )?;
    graph.add_pass(PassDesc {
        name: <super::passes::pair::scan_block_totals::Pair02ScanBlockTotalsPass as Pass<
            super::buffers::GpuBuffers,
            DebugOutput,
        >>::NAME,
        phase: CompilerPhase::Lex,
        dispatch_domain: ResourceDomain::Tokens,
        accesses: vec![
            PassAccess::read_write("block_pair_ping", resources.dfa_ping),
            PassAccess::initialize_read_write("block_pair_pong", resources.dfa_pong),
        ],
    })?;
    reflected_pass(
        &mut graph,
        <super::passes::pair::apply_block_prefix::Pair03ApplyBlockPrefixPass as Pass<
            super::buffers::GpuBuffers,
            DebugOutput,
        >>::NAME,
        ResourceDomain::Tokens,
        passes.pair_03.data(),
        &[
            ("flags_packed", resources.flags_packed, None),
            ("block_prefix_pair_ping", resources.dfa_ping, None),
            ("block_prefix_pair_pong", resources.dfa_pong, None),
            (
                "s_all_final",
                resources.s_all_final,
                Some(AccessMode::Write),
            ),
            (
                "s_keep_final",
                resources.s_keep_final,
                Some(AccessMode::Write),
            ),
        ],
    )?;
    reflected_pass(
        &mut graph,
        <super::passes::compact::boundaries::kept::CompactBoundariesKeptPass as Pass<
            super::buffers::GpuBuffers,
            DebugOutput,
        >>::NAME,
        ResourceDomain::Tokens,
        passes.compact_kept.data(),
        &[
            ("s_final", resources.s_keep_final, None),
            ("s_final_all", resources.s_all_final, None),
            ("flags_packed", resources.flags_packed, None),
            ("tok_types", resources.tok_types, None),
            (
                "end_positions",
                resources.end_positions,
                Some(AccessMode::Write),
            ),
            (
                "types_compact",
                resources.types_compact,
                Some(AccessMode::Write),
            ),
            (
                "all_index_compact",
                resources.all_index_compact,
                Some(AccessMode::Write),
            ),
            (
                "token_count",
                resources.token_count,
                Some(AccessMode::Write),
            ),
        ],
    )?;
    reflected_pass(
        &mut graph,
        <super::passes::compact::boundaries::all::CompactBoundariesAllPass as Pass<
            super::buffers::GpuBuffers,
            DebugOutput,
        >>::NAME,
        ResourceDomain::Tokens,
        passes.compact_all.data(),
        &[
            ("s_final", resources.s_all_final, None),
            ("s_final_all", resources.s_all_final, None),
            ("types_compact", resources.types_compact, None),
            ("all_index_compact", resources.all_index_compact, None),
            ("flags_packed", resources.flags_packed, None),
            ("tok_types", resources.flags_packed, None),
            (
                "end_positions",
                resources.tok_types,
                Some(AccessMode::Write),
            ),
            ("token_count", resources.dfa_pong, Some(AccessMode::Write)),
        ],
    )?;
    reflected_pass(
        &mut graph,
        <super::passes::tokens_build::TokensBuildPass as Pass<
            super::buffers::GpuBuffers,
            DebugOutput,
        >>::NAME,
        ResourceDomain::Tokens,
        passes.tokens_build.data(),
        &[
            ("in_bytes", resources.in_bytes, None),
            ("token_count", resources.token_count, None),
            ("end_positions", resources.end_positions, None),
            ("types_compact", resources.types_compact, None),
            ("all_index_compact", resources.all_index_compact, None),
            ("end_positions_all", resources.tok_types, None),
            ("source_file_count", resources.source_file_count, None),
            ("source_file_start", resources.source_file_start, None),
            ("source_file_len", resources.source_file_len, None),
            ("tokens_out", resources.tokens_out, Some(AccessMode::Write)),
            (
                "token_file_id",
                resources.token_file_id,
                Some(AccessMode::Write),
            ),
            ("parser_feature_flags", resources.parser_feature_flags, None),
        ],
    )?;

    graph.add_buffer_copy_pass(
        "lexer.token_count.readback",
        CompilerPhase::Lex,
        "token_count",
        resources.token_count,
        "token_count_readback",
        resources.token_count_readback,
    )?;
    graph.add_buffer_copy_pass(
        "lexer.parser_feature_flags.readback",
        CompilerPhase::Lex,
        "parser_feature_flags",
        resources.parser_feature_flags,
        "token_count_readback",
        resources.token_count_readback,
    )?;

    graph.add_registered_pass_arena_conflicts();
    Ok((graph.build()?, resources))
}
