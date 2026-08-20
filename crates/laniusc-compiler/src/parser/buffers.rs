//! GPU buffer allocation for parser token facts, pair streams, tree rows, and HIR rows.

mod constructors;
mod model;
mod scan_steps;
mod scans;
mod sizing;
mod storage;
pub use model::{
    ActionHeader,
    GpuHirView,
    HirArrayElement,
    HirCallArg,
    HirCore,
    HirField,
    HirGenericParam,
    HirLinks,
    HirMatchArm,
    HirMatchPayload,
    HirMethodCore,
    HirMethodSignature,
    HirParam,
    HirPath,
    HirPathSegment,
    HirPayload,
    HirPredicate,
    HirRange,
    HirSemanticFacts,
    HirString,
    HirTypeArg,
    HirVariant,
    HirVariantPayload,
    ParserBuffers,
    TokenBraceMatchParams,
    TokenDelimiterParams,
};
pub use scan_steps::*;
pub(in crate::parser) use scans::pack_total_reduce_step_count;
use scans::*;
pub(crate) use sizing::resident_partial_parse_tree_capacity_for_tables;
use sizing::{
    ParserFamilyCapacities,
    resident_partial_parse_tree_capacity,
    resident_virtual_pair_width,
};
use storage::alias_storage_buffer;
pub(crate) use storage::pointer_jump_step_capacity;

use crate::gpu::buffers::{
    JobResetPolicy,
    LaniusBuffer,
    ResettableRowDomain,
    ResettableRowDomainGuard,
    TrackedBufferView,
    readback_bytes,
    storage_ro_from_bytes,
    storage_ro_from_u32s,
    storage_rw_for_array,
    uniform_from_val,
};

const RESET_TOKEN_ROWS: ResettableRowDomain = ResettableRowDomain::new(1);
const RESET_PACKED_STREAM_ROWS: ResettableRowDomain = ResettableRowDomain::new(2);
const RESET_TREE_ROWS: ResettableRowDomain = ResettableRowDomain::new(3);

pub(crate) fn write_uniform<T>(queue: &wgpu::Queue, buffer: &LaniusBuffer<T>, value: &T)
where
    T: encase::ShaderType + encase::internal::WriteInto,
{
    let mut bytes = encase::UniformBuffer::new(Vec::<u8>::new());
    bytes
        .write(value)
        .expect("failed to encode active parser parameters");
    buffer.write(queue, 0, bytes.as_ref());
}

impl ParserBuffers {
    pub(in crate::parser) fn clear_operations(
        &self,
    ) -> &crate::parser::compiler_graph::ParserClearOperations {
        self.clear_operations
            .get()
            .expect("parser clear operations were not initialized")
    }

    pub(in crate::parser) fn record_finalizer(
        &self,
        name: &'static str,
        encoder: &mut wgpu::CommandEncoder,
    ) -> anyhow::Result<()> {
        self.copy_operations.record(name, encoder)
    }

    pub(in crate::parser) fn record_graph_copy(
        &self,
        name: &'static str,
        encoder: &mut wgpu::CommandEncoder,
    ) -> anyhow::Result<()> {
        self.copy_operations.record(name, encoder)
    }

    fn clear_overwritten_allocations() -> bool {
        crate::gpu::env::env_bool_strict("LANIUS_GPU_CLEAR_OVERWRITTEN", false)
    }

    fn clears_before_job(buffer: &crate::gpu::buffers::ResettableBuffer) -> bool {
        buffer.reset_policy == JobResetPolicy::ClearBeforeJob
            || Self::clear_overwritten_allocations()
    }

    /// Updates the logical token dimensions for a reused resident allocation.
    /// Physical storage may be larger, but parser dispatches and token-boundary
    /// uniforms must describe only the current job.
    pub(crate) fn set_active_token_capacity(&mut self, queue: &wgpu::Queue, token_capacity: u32) {
        let token_capacity = token_capacity.max(1);
        let n_tokens = token_capacity.saturating_add(2);
        self.n_tokens = n_tokens;
        self.token_input_capacity = token_capacity;
        self.token_delimiter_n_blocks = self.token_input_capacity.div_ceil(256).max(1);
        let n_pairs = n_tokens.saturating_sub(1);
        self.total_sc = n_pairs.saturating_mul(self.resident_sc_width);
        self.total_emit = n_pairs.saturating_mul(self.resident_emit_width);
        write_uniform(
            queue,
            &self.pack_totals_blocks_params,
            &super::passes::pack::totals::blocks::Params { n_pairs },
        );
        write_uniform(
            queue,
            &self.pack_totals_status_params,
            &super::passes::pack::totals::status::Params {
                n_pairs,
                emit_capacity: self.tree_capacity,
                read_from_a: u32::from(pack_total_reduce_step_count(n_pairs) % 2 == 0),
            },
        );
        let mut total_items = n_pairs.div_ceil(256).max(1);
        for step in &mut self.pack_total_reduce_steps {
            step.item_count = total_items;
            write_uniform(
                queue,
                &step.params,
                &super::passes::pack::totals::reduce::Params {
                    item_count: total_items,
                },
            );
            total_items = total_items.div_ceil(256).max(1);
        }
        write_uniform(
            queue,
            &self.params_llp,
            &super::passes::llp_pairs::LLPParams {
                n_tokens,
                n_kinds: self.n_kinds,
            },
        );
        // PackParams contains table-blob offsets that are resident-allocation
        // specific. Rewrite only the logical fields and the physical output
        // capacities; leave the six table offsets resident.
        let pack_prefix = [
            n_tokens,
            self.n_kinds,
            self.total_sc,
            self.total_emit,
            self.out_sc.count as u32,
            self.out_emit.count as u32,
        ];
        let mut pack_bytes = [0u8; 24];
        for (index, value) in pack_prefix.into_iter().enumerate() {
            pack_bytes[index * 4..index * 4 + 4].copy_from_slice(&value.to_le_bytes());
        }
        self.params_pack.write(queue, 0, &pack_bytes);
        write_uniform(
            queue,
            &self.token_delimiter_params,
            &TokenDelimiterParams {
                n_tokens: self.token_input_capacity,
                n_blocks: self.token_delimiter_n_blocks,
                scan_step: 0,
            },
        );
        write_uniform(
            queue,
            &self.token_brace_match_params,
            &TokenBraceMatchParams {
                n_tokens: self.token_input_capacity,
            },
        );
        write_uniform(
            queue,
            &self.source_file_token_end_params,
            &super::passes::source_file_token_end::Params { token_capacity },
        );
        // Bracket scratch is allocated to the resident maximum, but the
        // current packed stream may be smaller. Keep the per-pass logical
        // stream bound in sync while retaining the physical block tree: the
        // latter is deliberately reused across jobs and its zeroed tail is
        // part of the stable workspace contract.
        write_uniform(
            queue,
            &self.b01_params,
            &super::passes::brackets::scan_inblock::Params {
                n_sc: self.total_sc,
                wg_size: 256,
            },
        );
        write_uniform(
            queue,
            &self.b03_params,
            &super::passes::brackets::apply_prefix::Params {
                n_sc: self.total_sc,
                wg_size: 256,
            },
        );
        write_uniform(
            queue,
            &self.b07_params,
            &super::passes::brackets::pse_pair::Params {
                n_sc: self.total_sc,
                n_blocks: self.b_n_blocks,
                leaf_base: self.b_min_tree_base,
                typed_check: 1,
                emit_matches: u32::from(self.emit_stack_matches),
            },
        );
        write_uniform(
            queue,
            &self.b_clear_matches_params,
            &super::passes::brackets::clear_matches::Params {
                n_sc: self.total_sc,
            },
        );
    }

    fn active_reset_bytes(
        &self,
        buffer: &crate::gpu::buffers::ResettableBuffer,
        active_tree_capacity: u32,
    ) -> u64 {
        let rows = buffer.allocated_rows;
        if rows == 0 || buffer.byte_size == 0 || buffer.byte_size % rows as u64 != 0 {
            return buffer.byte_size;
        }
        let active_rows = match buffer.row_domain {
            Some(RESET_TOKEN_ROWS) => self.n_tokens as usize,
            Some(RESET_PACKED_STREAM_ROWS) => self.total_sc as usize,
            Some(RESET_TREE_ROWS) => active_tree_capacity as usize,
            _ => rows,
        }
        .min(rows)
        .max(1);
        (buffer.byte_size / rows as u64)
            .saturating_mul(active_rows as u64)
            .next_multiple_of(wgpu::COPY_BUFFER_ALIGNMENT)
            .min(buffer.byte_size)
    }

    /// Restores the rows visible to the current job. Fixed-size summaries and
    /// arena allocations are cleared in full; explicitly declared token-,
    /// packed-stream-, and tree-indexed allocations clear only their active
    /// logical prefix.
    pub(crate) fn install_job_storage_reset(&mut self) {
        self.job_storage_reset = Some(
            self.compiler_graph
                .job_storage_reset_operation(&self.resettable_buffers)
                .expect("parser job reset must match the compiler graph"),
        );
    }

    pub(crate) fn clear_job_storage(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        active_tree_capacity: u32,
    ) -> u64 {
        self.job_storage_reset
            .as_ref()
            .expect("parser job reset was not installed")
            .record_ranges(
                encoder,
                self.resettable_buffers.iter().map(|buffer| {
                    Self::clears_before_job(buffer)
                        .then(|| self.active_reset_bytes(buffer, active_tree_capacity))
                        .unwrap_or(0)
                }),
            )
    }

    pub(crate) fn resettable_storage_totals(&self) -> (usize, u64) {
        let buffers = self
            .resettable_buffers
            .iter()
            .filter(|buffer| Self::clears_before_job(buffer));
        let mut allocations = 0usize;
        let mut bytes = 0u64;
        for buffer in buffers {
            allocations += 1;
            bytes = bytes.saturating_add(buffer.byte_size);
        }
        (allocations, bytes)
    }

    pub(crate) fn largest_resettable_storage(
        &self,
        active_tree_capacity: u32,
        limit: usize,
    ) -> Vec<(&str, u64)> {
        let mut rows = self
            .resettable_buffers
            .iter()
            .filter(|buffer| Self::clears_before_job(buffer))
            .map(|buffer| {
                (
                    buffer.label.as_ref(),
                    self.active_reset_bytes(buffer, active_tree_capacity),
                )
            })
            .collect::<Vec<_>>();
        rows.sort_unstable_by_key(|(_, bytes)| std::cmp::Reverse(*bytes));
        rows.truncate(limit);
        rows
    }

    /// Returns every parser allocation whose contents are dead after compact
    /// HIR materialization. An allocation containing any retained HIR range is
    /// conservatively excluded in full.
    pub(crate) fn post_hir_workspace<'a>(&'a self, hir: &GpuHirView) -> Vec<TrackedBufferView<'a>> {
        let retained = hir.retained_allocation_ids();
        let workspace = self
            .resettable_buffers
            .iter()
            .filter(|buffer| !retained.contains(&buffer.allocation_id))
            .map(crate::gpu::buffers::ResettableBuffer::tracked_view)
            .collect::<Vec<_>>();
        debug_assert!(workspace.iter().all(|buffer| {
            buffer
                .allocation_id()
                .is_none_or(|allocation| !retained.contains(&allocation))
        }));
        if crate::gpu::env::env_bool_strict("LANIUS_GPU_BUFFER_BREAKDOWN", false) {
            let (retained_allocations, retained_bytes, workspace_bytes) = self
                .resettable_buffers
                .iter()
                .fold((0usize, 0u64, 0u64), |totals, buffer| {
                    if retained.contains(&buffer.allocation_id) {
                        (
                            totals.0 + 1,
                            totals.1.saturating_add(buffer.byte_size),
                            totals.2,
                        )
                    } else {
                        (
                            totals.0,
                            totals.1,
                            totals.2.saturating_add(buffer.byte_size),
                        )
                    }
                });
            eprintln!(
                "gpu_parser_hir_liveness retained_allocations={} retained_bytes={} workspace_allocations={} workspace_bytes={}",
                retained_allocations,
                retained_bytes,
                workspace.len(),
                workspace_bytes,
            );
            let limit = std::env::var("LANIUS_GPU_BUFFER_BREAKDOWN_LIMIT")
                .ok()
                .and_then(|value| value.parse::<usize>().ok())
                .filter(|&value| value != 0)
                .unwrap_or(64)
                .min(16_384);
            let mut rows = self
                .resettable_buffers
                .iter()
                .map(|buffer| {
                    (
                        retained.contains(&buffer.allocation_id),
                        buffer.label.as_ref(),
                        buffer.byte_size,
                        buffer.allocation_id,
                    )
                })
                .collect::<Vec<_>>();
            rows.sort_unstable_by_key(|&(is_retained, _, bytes, _)| {
                (std::cmp::Reverse(bytes), std::cmp::Reverse(is_retained))
            });
            for (is_retained, label, bytes, allocation) in rows.into_iter().take(limit) {
                eprintln!(
                    "gpu_parser_hir_buffer class={} label={label:?} allocation={allocation} bytes={bytes}",
                    if is_retained { "retained" } else { "workspace" },
                );
            }
        }
        workspace
    }
}

impl crate::gpu::passes_core::CompilerGraphBuffers for ParserBuffers {
    fn validate_compiler_pass(
        &self,
        operation: &'static str,
        resources: &std::collections::HashMap<String, wgpu::BindingResource<'_>>,
        dispatch_args: Option<&crate::gpu::buffers::LaniusBuffer<u32>>,
    ) -> anyhow::Result<()> {
        self.compiler_graph
            .validate_reflected_runtime_bindings(operation, resources, dispatch_args)
    }
}

impl ParserBuffers {
    fn new_with_sizing(
        device: &wgpu::Device,
        n_tokens: u32,
        source_capacity: u32,
        token_kinds_u32: Option<&[u32]>,
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
        resident_partial_parse_capacity: bool,
        retain_debug_hir_buffers: bool,
        tree_capacity_override: Option<u32>,
        parser_feature_flags: u32,
        passes: &crate::parser::passes::ParserPasses,
    ) -> Self {
        let n_pairs = n_tokens.saturating_sub(1) as usize;
        let token_input_capacity = n_tokens.saturating_sub(2).max(1);
        let token_delimiter_n_blocks = token_input_capacity.div_ceil(256).max(1);
        let pair_capacity = n_pairs.max(1);
        let _token_reset_rows =
            ResettableRowDomainGuard::enter(RESET_TOKEN_ROWS, n_tokens as usize);
        let (mut acc_sc, mut acc_emit) = (0u32, 0u32);
        if resident_partial_parse_capacity {
            let max_sc_len = resident_virtual_pair_width(&tables.sc_len, n_kinds);
            let max_emit_len = resident_virtual_pair_width(&tables.pp_len, n_kinds);
            acc_sc = (n_pairs as u32).saturating_mul(max_sc_len);
            acc_emit = (n_pairs as u32).saturating_mul(max_emit_len);
        } else {
            let token_kinds_u32 =
                token_kinds_u32.expect("non-resident parser sizing requires explicit token kinds");
            let add_pair = |prev: u32, thisk: u32, acc_sc: &mut u32, acc_emit: &mut u32| {
                let idx2d = (prev as usize) * (n_kinds as usize) + (thisk as usize);
                *acc_sc += tables.sc_len[idx2d];
                *acc_emit += tables.pp_len[idx2d];
            };
            for i in 0..n_pairs {
                let encoded_prev = token_kinds_u32[i];
                let thisk = token_kinds_u32[i + 1];
                let prev = if encoded_prev & 0x8000_0000 != 0 {
                    (encoded_prev >> 15) & 0x7fff
                } else {
                    encoded_prev
                };
                if thisk & 0x8000_0000 != 0 {
                    let inner = thisk & 0x7fff;
                    let outer = (thisk >> 15) & 0x7fff;
                    add_pair(prev, inner, &mut acc_sc, &mut acc_emit);
                    add_pair(inner, outer, &mut acc_sc, &mut acc_emit);
                } else {
                    add_pair(prev, thisk, &mut acc_sc, &mut acc_emit);
                }
            }
        }
        let total_sc = acc_sc;
        let total_emit = acc_emit;
        let resident_sc_width = if resident_partial_parse_capacity {
            resident_virtual_pair_width(&tables.sc_len, n_kinds)
        } else {
            0
        };
        let resident_emit_width = if resident_partial_parse_capacity {
            resident_virtual_pair_width(&tables.pp_len, n_kinds)
        } else {
            0
        };
        let tree_count_uses_status = true;
        let tree_capacity = tree_capacity_override
            .unwrap_or_else(|| {
                if tree_count_uses_status {
                    resident_partial_parse_tree_capacity(total_emit)
                } else {
                    total_emit
                }
            })
            .max(1);
        let emit_capacity = if resident_partial_parse_capacity {
            tree_capacity
        } else {
            total_emit.max(1)
        };
        let table_blob_words = u32::try_from(
            tables.sc_superseq.len()
                + tables.sc_off.len()
                + tables.sc_len.len()
                + tables.pp_superseq.len()
                + tables.pp_off.len()
                + tables.pp_len.len(),
        )
        .expect("parser table blob exceeds the GPU u32 address domain");
        const WG: u32 = 256;
        let n_blocks = total_sc.div_ceil(WG).max(1);
        let emit_stack_matches = retain_debug_hir_buffers || !resident_partial_parse_capacity;
        let family_capacities = ParserFamilyCapacities::new(tree_capacity, parser_feature_flags);
        let tree_n_node_blocks = tree_capacity.div_ceil(WG).max(1);
        let tree_n_prefix_blocks = tree_capacity.saturating_add(1).div_ceil(WG).max(1);
        let compiler_graph = crate::parser::compiler_graph::ParserCompilerGraph::new(
            device,
            crate::parser::compiler_graph::ParserGraphCapacity {
                source_capacity,
                n_tokens,
                token_capacity: token_input_capacity,
                pair_capacity: pair_capacity as u32,
                total_sc,
                tree_capacity,
                bracket_blocks: n_blocks,
                tree_node_blocks: tree_n_node_blocks,
                tree_prefix_blocks: tree_n_prefix_blocks,
                action_table_bytes: action_table_bytes.len() as u64,
                table_blob_words,
                production_count: tables.prod_arity.len() as u32,
                parser_feature_flags,
                emit_stack_matches,
                retain_debug_hir_buffers,
                preclassified_token_kinds: token_kinds_u32.is_some(),
            },
            passes,
        )
        .expect("parser compiler graph must match the reflected parser passes");
        macro_rules! graph_buffer {
            ($type:ty, $name:literal) => {
                compiler_graph
                    .buffer::<$type>($name)
                    .unwrap_or_else(|error| panic!("parser graph must own {}: {error}", $name))
            };
        }
        macro_rules! optional_graph_buffer {
            ($type:ty, $name:literal, $enabled:expr) => {
                if $enabled {
                    graph_buffer!($type, $name)
                } else {
                    storage_rw_for_array::<$type>(device, concat!("parser.", $name, ".disabled"), 1)
                }
            };
        }
        let ll1_status = graph_buffer!(u32, "ll1_status");
        let ll1_status_readback =
            readback_bytes(device, "rb.parser.recorded_ll1_hir.status", 32, 32);
        let hir_count_readback = readback_bytes(device, "rb.parser.hir_counts", 120, 120);

        let stream_has_soi = token_kinds_u32
            .map(|kinds| kinds.first().copied() == Some(0))
            .unwrap_or(true);
        let first_input = if n_tokens > 1 && stream_has_soi { 1 } else { 0 };
        // Match the canonical LL(1) stream: the last token is the EOF sentinel and is not
        // consumed as ordinary input.
        let input_end = n_tokens.saturating_sub(1);
        let n_input_tokens = input_end.saturating_sub(first_input);
        let token_frontend_required = token_kinds_u32.is_none();
        let token_count = if token_kinds_u32.is_some() {
            storage_ro_from_u32s(device, "parser.token_count", &[n_input_tokens])
        } else {
            graph_buffer!(u32, "token_count")
        };
        let active_pair_thread_dispatch_args =
            graph_buffer!(u32, "active_pair_thread_dispatch_args");
        let active_stack_thread_dispatch_args =
            graph_buffer!(u32, "active_stack_thread_dispatch_args");
        // ---------- Pair-to-header ----------
        let semantic_token_kinds = if let Some(kinds) = token_kinds_u32 {
            // Test/debug one-shot parsing receives already-classified parser
            // token kinds. Resident compilation fills this buffer on the GPU
            // with `tokens_to_kinds` instead.
            storage_ro_from_u32s(device, "parser.semantic_token_kinds.input", kinds)
        } else {
            graph_buffer!(u32, "token_kinds")
        };
        let token_delimiter_params = uniform_from_val(
            device,
            "parser.token_delimiters.params",
            &TokenDelimiterParams {
                n_tokens: token_input_capacity,
                n_blocks: token_delimiter_n_blocks,
                scan_step: 0,
            },
        );
        let token_block_scan_plan =
            make_token_block_scan_plan(device, "parser.token_block_scan", token_delimiter_n_blocks);
        let token_depth_paren_inblock =
            optional_graph_buffer!(i32, "depth_paren_inblock", token_frontend_required);
        let token_depth_brace_inblock =
            optional_graph_buffer!(i32, "depth_brace_inblock", token_frontend_required);
        let token_depth_bracket_inblock =
            optional_graph_buffer!(i32, "depth_bracket_inblock", token_frontend_required);
        let token_depth_angle_inblock =
            optional_graph_buffer!(i32, "depth_angle_inblock", token_frontend_required);
        let token_block_sum_paren =
            optional_graph_buffer!(i32, "block_sum_paren", token_frontend_required);
        let token_block_sum_brace =
            optional_graph_buffer!(i32, "block_sum_brace", token_frontend_required);
        let token_block_sum_bracket =
            optional_graph_buffer!(i32, "block_sum_bracket", token_frontend_required);
        let token_block_sum_angle =
            optional_graph_buffer!(i32, "block_sum_angle", token_frontend_required);
        let token_prefix_paren_a =
            optional_graph_buffer!(i32, "hierarchy_paren", token_frontend_required);
        let token_block_prefix_paren =
            optional_graph_buffer!(i32, "block_prefix_paren", token_frontend_required);
        let token_prefix_brace_a =
            optional_graph_buffer!(i32, "hierarchy_brace", token_frontend_required);
        let token_block_prefix_brace =
            optional_graph_buffer!(i32, "block_prefix_brace", token_frontend_required);
        let token_prefix_bracket_a =
            optional_graph_buffer!(i32, "hierarchy_bracket", token_frontend_required);
        let token_block_prefix_bracket =
            optional_graph_buffer!(i32, "block_prefix_bracket", token_frontend_required);
        let token_prefix_angle_a =
            optional_graph_buffer!(i32, "hierarchy_angle", token_frontend_required);
        let token_block_prefix_angle =
            optional_graph_buffer!(i32, "block_prefix_angle", token_frontend_required);
        let token_top_brace_owner_block =
            optional_graph_buffer!(u32, "top_brace_owner_block", token_frontend_required);
        let token_top_brace_owner_prefix_a =
            optional_graph_buffer!(u32, "hierarchy_owner", token_frontend_required);
        let token_top_brace_owner_block_prefix =
            optional_graph_buffer!(u32, "top_brace_owner_block_prefix", token_frontend_required);
        let token_statement_event_block =
            optional_graph_buffer!(u32, "statement_event_block", token_frontend_required);
        let token_statement_event_prefix_a =
            optional_graph_buffer!(u32, "statement_event_hierarchy", token_frontend_required);
        let token_statement_event_block_prefix =
            optional_graph_buffer!(u32, "statement_event_block_prefix", token_frontend_required);
        let token_brace_semantic_kind =
            optional_graph_buffer!(u32, "brace_semantic_kind", token_frontend_required);
        let token_braced_rhs_statement_kind =
            optional_graph_buffer!(u32, "braced_rhs_statement_kind", token_frontend_required);
        let token_bracket_semantic_kind =
            optional_graph_buffer!(u32, "bracket_semantic_kind", token_frontend_required);
        let token_statement_context_kind =
            optional_graph_buffer!(u32, "statement_context_kind", token_frontend_required);
        let token_impl_header_kind =
            optional_graph_buffer!(u32, "token_impl_header_kind", token_frontend_required);
        let token_impl_context_event =
            optional_graph_buffer!(u32, "token_impl_context_event", token_frontend_required);
        let token_type_path_context_kind =
            optional_graph_buffer!(u32, "token_type_path_context_kind", token_frontend_required);
        let token_where_context_event =
            optional_graph_buffer!(u32, "token_where_context_event", token_frontend_required);
        let token_match_pattern_context_event = optional_graph_buffer!(
            u32,
            "token_match_pattern_context_event",
            token_frontend_required
        );
        let token_generic_shr_block_sum =
            optional_graph_buffer!(i32, "generic_shr_block_sum", token_frontend_required);
        let token_generic_shr_block_min =
            optional_graph_buffer!(i32, "generic_shr_block_min", token_frontend_required);
        let token_generic_shr_prefix_sum_a =
            optional_graph_buffer!(i32, "generic_shr_hierarchy_sum", token_frontend_required);
        let token_generic_shr_prefix_min_a =
            optional_graph_buffer!(i32, "generic_shr_hierarchy_min", token_frontend_required);
        let token_generic_shr_block_prefix_sum =
            optional_graph_buffer!(i32, "generic_shr_block_prefix_sum", token_frontend_required);
        let token_generic_shr_block_prefix_min =
            optional_graph_buffer!(i32, "generic_shr_block_prefix_min", token_frontend_required);
        let token_brace_match_params = uniform_from_val(
            device,
            "parser.token_brace_match.params",
            &TokenBraceMatchParams {
                n_tokens: token_input_capacity,
            },
        );
        let token_brace_match_depth = graph_buffer!(i32, "brace_match_depth");
        let token_brace_match_block_min = graph_buffer!(i32, "brace_match_block_min");
        let token_brace_match_min_tree_base =
            next_power_of_two_u32(token_delimiter_n_blocks).max(1);
        let token_brace_match_min_tree = graph_buffer!(i32, "brace_match_min_tree");
        let token_brace_match_min_tree_steps = make_tree_prefix_max_build_steps(
            device,
            token_delimiter_n_blocks,
            token_brace_match_min_tree_base,
        );
        let token_bracket_match_depth =
            optional_graph_buffer!(i32, "bracket_match_depth", token_frontend_required);
        let token_bracket_match_block_min =
            optional_graph_buffer!(i32, "bracket_match_block_min", token_frontend_required);
        let token_bracket_match_min_tree =
            optional_graph_buffer!(i32, "bracket_match_min_tree", token_frontend_required);
        let token_paren_match_depth =
            optional_graph_buffer!(i32, "paren_match_depth", token_frontend_required);
        let token_paren_match_block_min =
            optional_graph_buffer!(i32, "paren_match_block_min", token_frontend_required);
        let token_paren_match_min_tree =
            optional_graph_buffer!(i32, "paren_match_min_tree", token_frontend_required);
        let token_angle_match_depth =
            optional_graph_buffer!(i32, "angle_match_depth", token_frontend_required);
        let token_angle_match_block_min =
            optional_graph_buffer!(i32, "angle_match_block_min", token_frontend_required);
        let token_angle_match_min_tree =
            optional_graph_buffer!(i32, "angle_match_min_tree", token_frontend_required);
        let token_feature_flags = if token_kinds_u32.is_some() {
            storage_ro_from_u32s(
                device,
                "parser.token_feature_flags.conservative",
                &[u32::MAX],
            )
        } else {
            graph_buffer!(u32, "token_feature_flags")
        };

        let params_llp = uniform_from_val(
            device,
            "parser.params_llp",
            &super::passes::llp_pairs::LLPParams { n_tokens, n_kinds },
        );

        let action_table = if action_table_bytes.is_empty() {
            let one = vec![0u8; core::mem::size_of::<ActionHeader>()];
            storage_ro_from_bytes::<u8>(device, "parser.action_table", &one, one.len())
        } else {
            storage_ro_from_bytes::<u8>(
                device,
                "parser.action_table",
                action_table_bytes,
                action_table_bytes.len(),
            )
        };

        let out_headers: LaniusBuffer<ActionHeader> = graph_buffer!(ActionHeader, "out_headers");

        // ---------- Pack varlen ----------
        let mut blob: Vec<u32> = Vec::with_capacity(
            tables.sc_superseq.len()
                + tables.sc_off.len()
                + tables.sc_len.len()
                + tables.pp_superseq.len()
                + tables.pp_off.len()
                + tables.pp_len.len(),
        );

        let sc_superseq_off = blob.len() as u32;
        blob.extend_from_slice(&tables.sc_superseq);

        let sc_off_off = blob.len() as u32;
        blob.extend_from_slice(&tables.sc_off);

        let sc_len_off = blob.len() as u32;
        blob.extend_from_slice(&tables.sc_len);

        let pp_superseq_off = blob.len() as u32;
        blob.extend_from_slice(&tables.pp_superseq);

        let pp_off_off = blob.len() as u32;
        blob.extend_from_slice(&tables.pp_off);

        let pp_len_off = blob.len() as u32;
        blob.extend_from_slice(&tables.pp_len);

        let params_pack = uniform_from_val(
            device,
            "pack.params",
            &super::passes::pack::varlen::PackParams {
                n_tokens,
                n_kinds,
                total_sc,
                total_emit,
                sc_capacity: total_sc.max(1),
                emit_capacity,
                sc_superseq_off,
                sc_off_off,
                sc_len_off,
                pp_superseq_off,
                pp_off_off,
                pp_len_off,
            },
        );
        let pack_offsets_status_params = uniform_from_val(
            device,
            "pack.offset_status.params",
            &super::passes::pack::offsets::status::Params {
                n_pairs: n_tokens.saturating_sub(1),
                emit_capacity,
            },
        );

        let sc_offsets = graph_buffer!(u32, "sc_offsets");
        let emit_offsets = graph_buffer!(u32, "emit_offsets");
        let pack_sc_prefix_a = graph_buffer!(u32, "pack_sc_prefix_a");
        let pack_sc_prefix_b = graph_buffer!(u32, "pack_sc_prefix_b");
        let pack_emit_prefix_a = graph_buffer!(u32, "pack_emit_prefix_a");
        let pack_emit_prefix_b = graph_buffer!(u32, "pack_emit_prefix_b");
        let pack_offset_scan_plan = make_pack_offset_scan_plan(device, n_tokens.saturating_sub(1));
        let pack_totals_blocks_params = uniform_from_val(
            device,
            "pack.totals_blocks.params",
            &super::passes::pack::totals::blocks::Params {
                n_pairs: n_tokens.saturating_sub(1),
            },
        );
        let pack_total_reduce_steps =
            make_pack_total_reduce_steps(device, n_tokens.saturating_sub(1));
        let pack_totals_status_params = uniform_from_val(
            device,
            "pack.totals_status.params",
            &super::passes::pack::totals::status::Params {
                n_pairs: n_tokens.saturating_sub(1),
                emit_capacity,
                read_from_a: u32::from(
                    pack_total_reduce_step_count(n_tokens.saturating_sub(1)) % 2 == 0,
                ),
            },
        );
        let partial_parse_status = graph_buffer!(u32, "partial_parse_status");
        debug_assert_eq!(blob.len(), table_blob_words as usize);
        let tables_blob = storage_ro_from_u32s(device, "pack.tables_blob", &blob);

        let _packed_stream_reset_rows =
            ResettableRowDomainGuard::enter(RESET_PACKED_STREAM_ROWS, total_sc.max(1) as usize);
        // The pair-offset scan partitions `[0, total_sc)` into disjoint ranges,
        // and `pack_varlen` writes every element of every range before bracket
        // matching reads the stream.
        let out_sc = graph_buffer!(u32, "out_sc");
        // The same partition covers the production and source-position
        // streams. Later type metadata aliases are fully initialized by
        // `hir_type_fields` before those views are consumed.
        let out_emit = graph_buffer!(u32, "out_emit");
        let out_emit_pos = graph_buffer!(u32, "out_emit_pos");

        // ---------- Brackets (parallel) ----------
        //
        let b01_params = uniform_from_val(
            device,
            "brackets.b01.params",
            &super::passes::brackets::scan_inblock::Params {
                n_sc: total_sc,
                wg_size: WG,
            },
        );
        let b02_params = uniform_from_val(
            device,
            "brackets.b02.params",
            &super::passes::brackets::scan_block_prefix::Params {
                n_blocks,
                scan_step: 0,
            },
        );
        let b02_scan_plan = make_token_block_scan_plan(device, "brackets.b02.scan", n_blocks);
        let b03_params = uniform_from_val(
            device,
            "brackets.b03.params",
            &super::passes::brackets::apply_prefix::Params {
                n_sc: total_sc,
                wg_size: WG,
            },
        );

        let b07_params = uniform_from_val(
            device,
            "brackets.b07.params",
            &super::passes::brackets::pse_pair::Params {
                n_sc: total_sc,
                n_blocks,
                leaf_base: next_power_of_two_u32(n_blocks).max(1),
                typed_check: 1,
                emit_matches: u32::from(emit_stack_matches),
            },
        );
        let b_clear_matches_params = uniform_from_val(
            device,
            "brackets.clear_matches.params",
            &super::passes::brackets::clear_matches::Params { n_sc: total_sc },
        );
        let b_min_tree_base = next_power_of_two_u32(n_blocks).max(1);
        let b_min_tree = graph_buffer!(i32, "bracket_min_tree");
        let b_min_tree_steps = make_tree_prefix_max_build_steps(device, n_blocks, b_min_tree_base);

        let b_exscan_inblock = graph_buffer!(i32, "bracket_exscan_inblock");
        let b_block_sum = compiler_graph
            .buffer::<i32>("bracket_block_sum")
            .expect("parser graph must own bracket block sums");
        let b_block_minpref = compiler_graph
            .buffer::<i32>("bracket_block_minpref")
            .expect("parser graph must own bracket block minimum prefixes");
        let b_block_row_min = compiler_graph
            .buffer::<i32>("bracket_block_row_min")
            .expect("parser graph must own bracket block row minima");
        let b_block_maxdepth = compiler_graph
            .buffer::<i32>("bracket_block_maxdepth")
            .expect("parser graph must own bracket block maximum depths");
        let b_block_prefix = compiler_graph
            .buffer::<i32>("bracket_block_prefix")
            .expect("parser graph must own bracket block prefixes");
        let b_block_prefix_sum_a = graph_buffer!(i32, "bracket_prefix_sum");
        let b_block_prefix_sum_b = graph_buffer!(i32, "bracket_hierarchy_sum");
        let b_block_prefix_min_a = graph_buffer!(i32, "bracket_prefix_min");
        let b_block_prefix_min_b = graph_buffer!(i32, "bracket_hierarchy_min");

        let depths_out = graph_buffer!(i32, "bracket_depths");
        let valid_out = compiler_graph
            .buffer::<u32>("bracket_valid")
            .expect("parser graph must own bracket validity output");

        let b_layer = graph_buffer!(u32, "bracket_layer");
        let match_for_index = graph_buffer!(u32, "match_for_index");

        // ---------- Tree parent recovery ----------
        let _tree_reset_rows =
            ResettableRowDomainGuard::enter(RESET_TREE_ROWS, tree_capacity as usize);
        let tree_prefix_params_base = super::passes::tree::prefix::local::Params {
            n: tree_capacity,
            uses_status_count: u32::from(tree_count_uses_status),
            n_node_blocks: tree_n_node_blocks,
            n_prefix_blocks: tree_n_prefix_blocks,
            scan_step: 0,
        };
        let tree_prefix_params = uniform_from_val(
            device,
            "parser.tree_prefix.params",
            &tree_prefix_params_base,
        );
        let tree_active_dispatch_args = graph_buffer!(u32, "tree_active_dispatch_args");
        let tree_enum_dispatch_args = graph_buffer!(u32, "tree_enum_dispatch_args");
        let tree_match_dispatch_args = graph_buffer!(u32, "tree_match_dispatch_args");
        let tree_struct_dispatch_args = graph_buffer!(u32, "tree_struct_dispatch_args");
        let tree_depth_status = graph_buffer!(u32, "tree_depth_status");
        let raw_relation_step_capacity =
            super::passes::hir::semantic::parent::step::canonical_relation_step_capacity(
                tree_capacity,
            );
        let hir_raw_relation_dispatch_args = graph_buffer!(u32, "hir_raw_relation_dispatch_args");
        debug_assert_eq!(
            hir_raw_relation_dispatch_args.count,
            raw_relation_step_capacity.max(1) as usize * 3,
            "the graph retains one bindable indirect row when no relation-walk step is scheduled",
        );
        let local_relation_step_capacity =
            super::passes::hir::semantic::parent::step::bounded_walk_steps_after_local_span(
                tree_capacity,
                super::passes::hir::nodes::SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN,
            );
        let hir_local_relation_dispatch_args =
            graph_buffer!(u32, "hir_local_relation_dispatch_args");
        debug_assert_eq!(
            hir_local_relation_dispatch_args.count,
            local_relation_step_capacity.max(1) as usize * 3,
            "the graph retains one bindable indirect row when no local relation-walk step is scheduled",
        );
        let hir_semantic_dispatch_args = graph_buffer!(u32, "hir_semantic_dispatch_args");
        let hir_semantic_relation_dispatch_args =
            graph_buffer!(u32, "hir_semantic_relation_dispatch_args");
        debug_assert_eq!(
            hir_semantic_relation_dispatch_args.count,
            raw_relation_step_capacity.max(1) as usize * 3,
            "the graph retains one bindable semantic indirect row when no relation-walk step is scheduled",
        );
        let tree_depth_block_max = graph_buffer!(u32, "tree_depth_block_max");
        let tree_prefix_scan_steps =
            make_tree_prefix_scan_steps(device, tree_prefix_params_base, tree_n_node_blocks);
        let tree_prefix_inblock = graph_buffer!(i32, "tree_prefix_inblock");
        let tree_block_sum = compiler_graph
            .buffer::<i32>("tree_block_sum")
            .expect("parser graph must own tree block sums");
        let tree_block_prefix_a = graph_buffer!(i32, "tree_block_prefix_a");
        let tree_block_prefix_b = graph_buffer!(i32, "tree_block_prefix_b");
        let tree_block_prefix = graph_buffer!(i32, "tree_block_prefix");
        let tree_prefix = graph_buffer!(i32, "tree_prefix");
        let tree_prefix_block_max = compiler_graph
            .buffer::<i32>("tree_prefix_block_max")
            .expect("parser graph must own tree-prefix block maxima");
        let tree_prefix_block_max_tree_base = next_power_of_two_u32(tree_n_prefix_blocks).max(1);
        let tree_prefix_block_max_tree = graph_buffer!(i32, "tree_prefix_block_max_tree");
        let tree_prefix_max_build_steps = make_tree_prefix_max_build_steps(
            device,
            tree_n_prefix_blocks,
            tree_prefix_block_max_tree_base,
        );

        // Shared tables/outputs. Tree recovery and HIR classification assign
        // every active row; previous-sibling scatter has its own required
        // per-phase clear before both of its sparse scatter uses.
        let prod_arity = storage_ro_from_u32s(device, "parser.prod_arity", &tables.prod_arity);
        let node_kind = compiler_graph
            .buffer::<u32>("node_kind")
            .expect("parser graph must own raw node kinds");
        let parent = compiler_graph
            .buffer::<u32>("parent")
            .expect("parser graph must own raw parent relations");
        let tree_params = uniform_from_val(
            device,
            "parser.tree_parent.params",
            &super::passes::tree::parent::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                n_prefix_blocks: tree_n_prefix_blocks,
                max_tree_leaf_base: tree_prefix_block_max_tree_base,
            },
        );
        let tree_span_params = uniform_from_val(
            device,
            "parser.tree_spans.params",
            &super::passes::tree::spans::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                n_prefix_blocks: tree_n_prefix_blocks,
                max_tree_leaf_base: tree_prefix_block_max_tree_base,
            },
        );
        let tree_prev_sibling_params = uniform_from_val(
            device,
            "parser.tree_prev_sibling.params",
            &super::passes::tree::prev::sibling::clear::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let first_child = compiler_graph
            .buffer::<u32>("first_child")
            .expect("parser graph must own raw first-child relations");
        let next_sibling = compiler_graph
            .buffer::<u32>("next_sibling")
            .expect("parser graph must own raw next-sibling relations");
        let prev_sibling = graph_buffer!(u32, "prev_sibling");
        let subtree_end = compiler_graph
            .buffer::<u32>("subtree_end")
            .expect("parser graph must own raw subtree ends");
        let hir_params = uniform_from_val(
            device,
            "parser.hir_nodes.params",
            &super::passes::hir::nodes::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                semantic_parent_local_ancestor_span:
                    super::passes::hir::nodes::SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN,
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
                parser_feature_flags,
            },
        );
        let hir_span_params = uniform_from_val(
            device,
            "parser.hir_spans.params",
            &super::passes::hir::spans::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                token_capacity: token_input_capacity,
            },
        );
        let hir_type_fields_params = uniform_from_val(
            device,
            "parser.hir_type_fields.params",
            &super::passes::hir::types::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_item_fields_params = uniform_from_val(
            device,
            "parser.hir_item_fields.params",
            &super::passes::hir::item::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_param_fields_params = uniform_from_val(
            device,
            "parser.hir_param_fields.params",
            &super::passes::hir::param::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_method_fields_params = uniform_from_val(
            device,
            "parser.hir_method_fields.params",
            &super::passes::hir::method::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
            },
        );
        let hir_expr_fields_params = uniform_from_val(
            device,
            "parser.hir_expr_fields.params",
            &super::passes::hir::expr::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                token_capacity: token_input_capacity,
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_member_fields_params = uniform_from_val(
            device,
            "parser.hir_member_fields.params",
            &super::passes::hir::postfix_fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                parser_feature_flags,
            },
        );
        let hir_stmt_fields_params = uniform_from_val(
            device,
            "parser.hir_stmt_fields.params",
            &super::passes::hir::stmt_fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_call_fields_params = uniform_from_val(
            device,
            "parser.hir_call_fields.params",
            &super::passes::hir::call::fields::Params {
                n: tree_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_array_fields_params = uniform_from_val(
            device,
            "parser.hir_array_fields.params",
            &super::passes::hir::array::Params {
                n: family_capacities.arrays,
                uses_status_count: u32::from(tree_count_uses_status),
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_enum_match_fields_params = uniform_from_val(
            device,
            "parser.hir_enum_match_fields.params",
            &super::passes::hir::enums::Params {
                n: family_capacities.enum_match,
                uses_status_count: u32::from(tree_count_uses_status),
                family_flags: u32::from(
                    parser_feature_flags & crate::lexer::features::PARSER_FEATURE_ENUMS != 0,
                ) | (u32::from(
                    parser_feature_flags & crate::lexer::features::PARSER_FEATURE_MATCHES != 0,
                ) << 1),
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_struct_fields_params = uniform_from_val(
            device,
            "parser.hir_struct_fields.params",
            &super::passes::hir::structs::fields::Params {
                n: family_capacities.structs,
                uses_status_count: u32::from(tree_count_uses_status),
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_kind = compiler_graph
            .buffer::<u32>("hir_kind")
            .expect("parser graph must own raw HIR classifications");
        let hir_semantic_block_count = graph_buffer!(u32, "hir_semantic_block_sum");
        let hir_semantic_prefix_scan = make_hir_prefix_scan_plan(device, tree_n_node_blocks);
        // Semantic identity and canonical-family scans overlap in time, so
        // their prefix storage remains physically distinct.
        let hir_semantic_flag = compiler_graph
            .buffer::<u32>("hir_semantic_flag")
            .expect("parser graph must own semantic-node flags");
        let hir_semantic_local_prefix = compiler_graph
            .buffer::<u32>("hir_semantic_local_prefix")
            .expect("parser graph must own semantic local prefixes");
        let hir_semantic_block_prefix_a = graph_buffer!(u32, "hir_semantic_block_prefix_a");
        let hir_semantic_block_prefix_b = graph_buffer!(u32, "hir_semantic_block_prefix_b");
        let hir_node_dense_id = compiler_graph
            .buffer::<u32>("hir_node_dense_id")
            .expect("parser graph must own raw-to-semantic dense ids");
        let hir_semantic_prefix_before_node = graph_buffer!(u32, "hir_semantic_prefix_before_node");
        let hir_semantic_dense_node = compiler_graph
            .buffer::<u32>("hir_semantic_dense_node")
            .expect("parser graph must own semantic-to-raw dense ids");
        let hir_semantic_subtree_end = graph_buffer!(u32, "hir_semantic_subtree_end");
        let hir_semantic_count = graph_buffer!(u32, "hir_semantic_count");
        let hir_semantic_parent = graph_buffer!(u32, "hir_semantic_parent");
        let hir_semantic_first_child = graph_buffer!(u32, "hir_semantic_first_child");
        let hir_semantic_next_sibling = graph_buffer!(u32, "hir_semantic_next_sibling");
        let hir_semantic_depth = graph_buffer!(u32, "hir_semantic_depth");
        let hir_semantic_child_index = graph_buffer!(u32, "hir_semantic_child_index");
        let hir_semantic_parent_link_a = graph_buffer!(u32, "hir_semantic_parent_link_a");
        let hir_semantic_parent_link_b = graph_buffer!(u32, "hir_semantic_parent_link_b");
        let hir_semantic_parent_value_a = graph_buffer!(u32, "hir_semantic_parent_value_a");
        let hir_semantic_parent_value_b = graph_buffer!(u32, "hir_semantic_parent_value_b");
        let tree_depth = graph_buffer!(u32, "tree_depth");
        // File identity is fundamentally token-indexed. Production HIR
        // projection resolves it through each raw node's token anchor instead
        // of retaining a duplicate raw-tree-sized column. Debug parsing keeps
        // the historical raw row for detailed parser readback.
        let default_token_file_id = graph_buffer!(u32, "token_file_id");
        let hir_token_pos = graph_buffer!(u32, "hir_token_pos");
        let hir_token_end = graph_buffer!(u32, "hir_token_end");
        let hir_token_file_id = graph_buffer!(u32, "hir_token_file_id");
        let hir_type_form = graph_buffer!(u32, "hir_type_form");
        let hir_type_value_node = graph_buffer!(u32, "hir_type_value_node");
        let hir_type_len_token = graph_buffer!(u32, "hir_type_len_token");
        let hir_type_len_value = graph_buffer!(u32, "hir_type_len_value");
        let hir_type_file_id = if retain_debug_hir_buffers {
            alias_storage_buffer::<u32, u32>(&hir_token_file_id, tree_capacity as usize)
        } else {
            alias_storage_buffer::<u32, u32>(&default_token_file_id, token_input_capacity as usize)
        };
        // Dense subtree bounds remain live through type checking, where they
        // define flattened recursive type comparisons. Keep the later durable
        // type-leaf relation in distinct storage even in production mode.
        let hir_type_path_leaf_node = graph_buffer!(u32, "hir_type_path_leaf_node");
        // A bound-path leaf is an identifier with a distinct source-token
        // anchor. Production compilation therefore keys the reverse owner
        // relation by that token instead of retaining one row for every raw
        // grammar node. Debug parsing keeps the raw-node domain expected by
        // its detailed readbacks.
        let hir_bound_path_owner_by_leaf = graph_buffer!(u32, "hir_bound_path_owner_by_leaf");
        let hir_path_root_owner = graph_buffer!(u32, "hir_path_root_owner");
        let hir_path_segment_owner_a = graph_buffer!(u32, "hir_path_segment_owner_a");
        let hir_path_segment_owner_b = graph_buffer!(u32, "hir_path_segment_owner_b");
        let hir_path_segment_link_a = graph_buffer!(u32, "hir_path_segment_link_a");
        let hir_path_segment_link_b = graph_buffer!(u32, "hir_path_segment_link_b");
        let hir_path_segment_rank_a = graph_buffer!(u32, "hir_path_segment_rank_a");
        let hir_path_segment_rank_b = graph_buffer!(u32, "hir_path_segment_rank_b");
        let hir_path_segment_count = graph_buffer!(u32, "hir_path_segment_count");
        let hir_type_path_leaf_link_a = graph_buffer!(u32, "hir_type_path_leaf_link_a");
        let hir_type_path_leaf_link_b = graph_buffer!(u32, "hir_type_path_leaf_link_b");
        let hir_type_path_leaf_value_a = graph_buffer!(u32, "hir_type_path_leaf_value_a");
        let hir_type_path_leaf_value_b = graph_buffer!(u32, "hir_type_path_leaf_value_b");
        // Production canonical HIR compaction consumes the pointer-jumped
        // owner/rank relation directly. These raw linked-list summaries remain
        // graph workspace in production and become retained outputs only for
        // parser debug readback.
        let hir_type_arg_start = graph_buffer!(u32, "hir_type_arg_start");
        let hir_type_arg_count = graph_buffer!(u32, "hir_type_arg_count");
        let hir_type_arg_next = graph_buffer!(u32, "hir_type_arg_next");
        let hir_type_alias_target_node = graph_buffer!(u32, "hir_type_alias_target_node");
        let hir_fn_return_type_node = graph_buffer!(u32, "hir_fn_return_type_node");
        let hir_type_arg_owner_a = graph_buffer!(u32, "hir_type_arg_owner_a");
        let hir_type_arg_owner_b = graph_buffer!(u32, "hir_type_arg_owner_b");
        let hir_type_arg_link_a = graph_buffer!(u32, "hir_type_arg_link_a");
        let hir_type_arg_link_b = graph_buffer!(u32, "hir_type_arg_link_b");
        let hir_type_arg_rank_a = graph_buffer!(u32, "hir_type_arg_rank_a");
        let hir_type_arg_rank_b = graph_buffer!(u32, "hir_type_arg_rank_b");
        let hir_type_arg_previous = graph_buffer!(u32, "hir_type_arg_previous");
        let hir_type_root_owner = graph_buffer!(u32, "hir_type_root_owner");
        let hir_type_alias_owner_link_a = graph_buffer!(u32, "hir_type_alias_owner_link_a");
        let hir_type_alias_owner_link_b = graph_buffer!(u32, "hir_type_alias_owner_link_b");
        let hir_type_alias_owner_value_a = graph_buffer!(u32, "hir_type_alias_owner_value_a");
        let hir_type_alias_owner_value_b = graph_buffer!(u32, "hir_type_alias_owner_value_b");
        let hir_item_kind = graph_buffer!(u32, "hir_item_kind");
        let hir_item_name_token = graph_buffer!(u32, "hir_item_name_token");
        let hir_item_namespace = graph_buffer!(u32, "hir_item_namespace");
        let hir_item_visibility = graph_buffer!(u32, "hir_item_visibility");
        let hir_item_path_start = graph_buffer!(u32, "hir_item_path_start");
        let hir_item_path_end = graph_buffer!(u32, "hir_item_path_end");
        let hir_item_path_node = graph_buffer!(u32, "hir_item_path_node");
        let hir_item_file_id = if retain_debug_hir_buffers {
            alias_storage_buffer::<u32, u32>(&hir_token_file_id, tree_capacity as usize)
        } else {
            alias_storage_buffer::<u32, u32>(&default_token_file_id, token_input_capacity as usize)
        };
        let hir_item_import_target_kind = graph_buffer!(u32, "hir_item_import_target_kind");
        let hir_param_record = graph_buffer!(u32, "hir_param_record");
        let hir_param_type_node = graph_buffer!(u32, "hir_param_type_node");
        let match_required =
            parser_feature_flags & crate::lexer::features::PARSER_FEATURE_MATCHES != 0;
        // Method passes bind and write every method field together. The graph
        // keeps these ranges distinct while assigning a one-row sentinel when
        // predicate syntax is absent from a production job.
        let hir_method_owner_node = graph_buffer!(u32, "hir_method_owner_node");
        let hir_method_impl_node = graph_buffer!(u32, "hir_method_impl_node");
        let hir_method_name_token = graph_buffer!(u32, "hir_method_name_token");
        let hir_method_first_param_token = graph_buffer!(u32, "hir_method_first_param_token");
        let hir_method_receiver_mode = graph_buffer!(u32, "hir_method_receiver_mode");
        let hir_method_visibility = graph_buffer!(u32, "hir_method_visibility");
        let hir_method_signature_flags = graph_buffer!(u32, "hir_method_signature_flags");
        let hir_method_impl_receiver_type_node =
            graph_buffer!(u32, "hir_method_impl_receiver_type_node");
        let hir_param_owner_a = graph_buffer!(u32, "hir_param_owner_a");
        let hir_param_link_a = graph_buffer!(u32, "hir_param_link_a");
        let hir_param_rank_a = graph_buffer!(u32, "hir_param_rank_a");
        let hir_param_rank_b = graph_buffer!(u32, "hir_param_rank_b");
        let hir_stmt_record = graph_buffer!(u32, "hir_stmt_record");
        let hir_call_arg_end = graph_buffer!(u32, "hir_call_arg_end");
        let hir_call_arg_count = graph_buffer!(u32, "hir_call_arg_count");
        let hir_call_arg_parent_call = graph_buffer!(u32, "hir_call_arg_parent_call");
        let hir_call_arg_ordinal = graph_buffer!(u32, "hir_call_arg_ordinal");
        let hir_variant_parent_enum = graph_buffer!(u32, "hir_variant_parent_enum");
        let hir_variant_ordinal = graph_buffer!(u32, "hir_variant_ordinal");
        let hir_variant_payload_start = graph_buffer!(u32, "hir_variant_payload_start");
        let hir_variant_payload_count = graph_buffer!(u32, "hir_variant_payload_count");
        let hir_variant_payload_node = graph_buffer!(u32, "hir_variant_payload_node");
        let hir_variant_owner_a = graph_buffer!(u32, "hir_variant_owner_a");
        let hir_variant_owner_b = graph_buffer!(u32, "hir_variant_owner_b");
        let hir_variant_link_a = graph_buffer!(u32, "hir_variant_link_a");
        let hir_variant_link_b = graph_buffer!(u32, "hir_variant_link_b");
        let hir_variant_rank_a = graph_buffer!(u32, "hir_variant_rank_a");
        let hir_variant_rank_b = graph_buffer!(u32, "hir_variant_rank_b");
        let hir_variant_payload_owner_a = graph_buffer!(u32, "hir_variant_payload_owner_a");
        let hir_variant_payload_owner_b = graph_buffer!(u32, "hir_variant_payload_owner_b");
        let hir_variant_payload_link_a = graph_buffer!(u32, "hir_variant_payload_link_a");
        let hir_variant_payload_link_b = graph_buffer!(u32, "hir_variant_payload_link_b");
        let hir_variant_payload_rank_a = graph_buffer!(u32, "hir_variant_payload_rank_a");
        let hir_variant_payload_rank_b = graph_buffer!(u32, "hir_variant_payload_rank_b");
        let hir_list_rank_flag = graph_buffer!(u32, "hir_list_rank_flag");
        let hir_list_rank_local_prefix = graph_buffer!(u32, "hir_list_rank_local_prefix");
        let hir_list_rank_block_sum = graph_buffer!(u32, "hir_list_rank_block_sum");
        let hir_list_rank_block_prefix_a = graph_buffer!(u32, "hir_list_rank_block_prefix_a");
        let hir_list_rank_block_prefix_b = graph_buffer!(u32, "hir_list_rank_block_prefix_b");
        let hir_list_rank_node = graph_buffer!(u32, "hir_list_rank_node");
        let hir_list_rank_count = graph_buffer!(u32, "hir_list_rank_count");
        let hir_list_rank_dispatch_args = graph_buffer!(u32, "hir_list_rank_dispatch_args");
        let hir_enum_rank_flag = graph_buffer!(u32, "hir_enum_rank_flag");
        let hir_enum_rank_local_prefix = graph_buffer!(u32, "hir_enum_rank_local_prefix");
        let hir_enum_rank_block_sum = graph_buffer!(u32, "hir_enum_rank_block_sum");
        let hir_enum_rank_block_prefix_a = graph_buffer!(u32, "hir_enum_rank_block_prefix_a");
        let hir_enum_rank_block_prefix_b = graph_buffer!(u32, "hir_enum_rank_block_prefix_b");
        let hir_enum_rank_node = graph_buffer!(u32, "hir_enum_rank_node");
        let hir_enum_rank_count = graph_buffer!(u32, "hir_enum_rank_count");
        let hir_enum_rank_dispatch_args = graph_buffer!(u32, "hir_enum_rank_dispatch_args");
        let hir_match_scrutinee_node = graph_buffer!(u32, "hir_match_scrutinee_node");
        let hir_match_arm_start =
            optional_graph_buffer!(u32, "hir_match_arm_start", match_required);
        let hir_match_arm_count =
            optional_graph_buffer!(u32, "hir_match_arm_count", match_required);
        let hir_match_arm_next = optional_graph_buffer!(u32, "hir_match_arm_next", match_required);
        let hir_match_arm_pattern_node =
            optional_graph_buffer!(u32, "hir_match_arm_pattern_node", match_required);
        let hir_match_pattern_owner_arm =
            optional_graph_buffer!(u32, "hir_match_pattern_owner_arm", match_required);
        let hir_match_arm_payload_start =
            optional_graph_buffer!(u32, "hir_match_arm_payload_start", match_required);
        let hir_match_arm_payload_count =
            optional_graph_buffer!(u32, "hir_match_arm_payload_count", match_required);
        let hir_match_arm_result_node =
            optional_graph_buffer!(u32, "hir_match_arm_result_node", match_required);
        let hir_match_payload_owner_arm =
            optional_graph_buffer!(u32, "hir_match_payload_owner_arm", match_required);
        let hir_match_payload_match_node =
            optional_graph_buffer!(u32, "hir_match_payload_match_node", match_required);
        let hir_match_payload_ordinal =
            optional_graph_buffer!(u32, "hir_match_payload_ordinal", match_required);
        let hir_match_arm_owner_a =
            optional_graph_buffer!(u32, "hir_match_arm_owner_a", match_required);
        let hir_match_arm_owner_b =
            optional_graph_buffer!(u32, "hir_match_arm_owner_b", match_required);
        let hir_match_arm_link_a =
            optional_graph_buffer!(u32, "hir_match_arm_link_a", match_required);
        let hir_match_arm_link_b =
            optional_graph_buffer!(u32, "hir_match_arm_link_b", match_required);
        let hir_match_arm_rank_a =
            optional_graph_buffer!(u32, "hir_match_arm_rank_a", match_required);
        let hir_match_arm_rank_b =
            optional_graph_buffer!(u32, "hir_match_arm_rank_b", match_required);
        let hir_match_arm_previous =
            optional_graph_buffer!(u32, "hir_match_arm_previous", match_required);
        let hir_match_payload_owner_a =
            optional_graph_buffer!(u32, "hir_match_payload_owner_a", match_required);
        let hir_match_payload_owner_b =
            optional_graph_buffer!(u32, "hir_match_payload_owner_b", match_required);
        let hir_match_payload_link_a =
            optional_graph_buffer!(u32, "hir_match_payload_link_a", match_required);
        let hir_match_payload_link_b =
            optional_graph_buffer!(u32, "hir_match_payload_link_b", match_required);
        let hir_match_pattern_parent =
            optional_graph_buffer!(u32, "hir_match_pattern_parent", match_required);
        let hir_match_pattern_parent_b =
            optional_graph_buffer!(u32, "hir_match_pattern_parent_b", match_required);
        let hir_match_payload_rank_a =
            optional_graph_buffer!(u32, "hir_match_payload_rank_a", match_required);
        let hir_match_payload_rank_b =
            optional_graph_buffer!(u32, "hir_match_payload_rank_b", match_required);
        let hir_match_rank_flag =
            optional_graph_buffer!(u32, "hir_match_rank_flag", match_required);
        let hir_match_rank_local_prefix =
            optional_graph_buffer!(u32, "hir_match_rank_local_prefix", match_required);
        let hir_match_rank_block_sum =
            optional_graph_buffer!(u32, "hir_match_rank_block_sum", match_required);
        let hir_match_rank_block_prefix_a =
            optional_graph_buffer!(u32, "hir_match_rank_block_prefix_a", match_required);
        let hir_match_rank_block_prefix_b =
            optional_graph_buffer!(u32, "hir_match_rank_block_prefix_b", match_required);
        let hir_match_rank_node =
            optional_graph_buffer!(u32, "hir_match_rank_node", match_required);
        let hir_match_rank_count =
            optional_graph_buffer!(u32, "hir_match_rank_count", match_required);
        let hir_match_rank_dispatch_args = if match_required {
            graph_buffer!(u32, "hir_match_rank_dispatch_args")
        } else {
            storage_rw_for_array::<u32>(device, "parser.hir_match_rank_dispatch_args.disabled", 3)
        };
        let hir_call_callee_node = graph_buffer!(u32, "hir_call_callee_node");
        let hir_call_callee_path_node = graph_buffer!(u32, "hir_call_callee_path_node");
        let hir_call_parent_by_callee = graph_buffer!(u32, "hir_call_parent_by_callee");
        let hir_call_context_stmt_node = graph_buffer!(u32, "hir_call_context_stmt_node");
        let hir_call_arg_start = graph_buffer!(u32, "hir_call_arg_start");
        let hir_call_arg_owner_a = graph_buffer!(u32, "hir_call_arg_owner_a");
        let hir_call_arg_owner_b = graph_buffer!(u32, "hir_call_arg_owner_b");
        let hir_call_arg_link_a = graph_buffer!(u32, "hir_call_arg_link_a");
        let hir_call_arg_link_b = graph_buffer!(u32, "hir_call_arg_link_b");
        let hir_call_arg_rank_a = graph_buffer!(u32, "hir_call_arg_rank_a");
        let hir_call_arg_rank_b = graph_buffer!(u32, "hir_call_arg_rank_b");
        let hir_array_lit_first_element = graph_buffer!(u32, "hir_array_lit_first_element");
        let hir_array_lit_element_count = graph_buffer!(u32, "hir_array_lit_element_count");
        let hir_array_lit_context_stmt_node = graph_buffer!(u32, "hir_array_lit_context_stmt_node");
        let hir_array_element_parent_lit = graph_buffer!(u32, "hir_array_element_parent_lit");
        let hir_array_element_ordinal = graph_buffer!(u32, "hir_array_element_ordinal");
        let hir_array_element_next = graph_buffer!(u32, "hir_array_element_next");
        let hir_array_element_owner_a = graph_buffer!(u32, "hir_array_element_owner_a");
        let hir_array_element_owner_b = graph_buffer!(u32, "hir_array_element_owner_b");
        let hir_array_element_link_a = graph_buffer!(u32, "hir_array_element_link_a");
        let hir_array_element_link_b = graph_buffer!(u32, "hir_array_element_link_b");
        let hir_array_element_rank_a = graph_buffer!(u32, "hir_array_element_rank_a");
        let hir_array_element_rank_b = graph_buffer!(u32, "hir_array_element_rank_b");
        let hir_array_element_previous = graph_buffer!(u32, "hir_array_element_previous");
        let hir_expr_record = graph_buffer!(u32, "hir_expr_record");
        let hir_expr_name_role = graph_buffer!(u32, "hir_expr_name_role");
        let hir_expr_result_root_node = graph_buffer!(u32, "hir_expr_result_root_node");
        let hir_expr_result_root_scratch_node =
            graph_buffer!(u32, "hir_expr_result_root_scratch_node");
        let hir_binary_span_link_a = graph_buffer!(u32, "hir_binary_span_link_a");
        let hir_binary_span_start_a = graph_buffer!(u32, "hir_binary_span_start_a");
        let binary_span_steps =
            super::passes::hir::binary::span::step::pointer_jump_steps_for_items(tree_capacity);
        // Trees covered entirely by the shader's local 32-node walk schedule
        // no ping-pong pass. In that graph specialization the B resources have
        // no lifetime (and therefore no physical slot); preserve the uniform
        // buffer model with aliases that can never be bound alongside A.
        let hir_binary_span_link_b = if binary_span_steps == 0 {
            alias_storage_buffer::<u32, u32>(&hir_binary_span_link_a, hir_binary_span_link_a.count)
        } else {
            graph_buffer!(u32, "hir_binary_span_link_b")
        };
        let hir_binary_span_start_b = if binary_span_steps == 0 {
            alias_storage_buffer::<u32, u32>(
                &hir_binary_span_start_a,
                hir_binary_span_start_a.count,
            )
        } else {
            graph_buffer!(u32, "hir_binary_span_start_b")
        };
        let hir_expr_int_value = graph_buffer!(u32, "hir_expr_int_value");
        let hir_expr_float_bits = graph_buffer!(u32, "hir_expr_float_bits");
        // Literal rows are token-anchored in production. Integer and float
        // literals still initialize these columns, so an absent string family
        // uses token capacity rather than a one-row sentinel, but never raw
        // grammar-tree capacity.
        let hir_expr_string_start = graph_buffer!(u32, "hir_expr_string_start");
        let hir_expr_string_len = graph_buffer!(u32, "hir_expr_string_len");
        let hir_literal_values_params = uniform_from_val(
            device,
            "parser.hir_literal_values.params",
            &super::passes::hir::literal_values::Params {
                n: tree_capacity,
                source_len: source_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                token_capacity: token_input_capacity,
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_string_decode_params = uniform_from_val(
            device,
            "parser.hir_string_decode.params",
            &super::passes::hir::string::decode::Params {
                n: tree_capacity,
                source_len: source_capacity,
                pool_capacity: source_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                token_capacity: token_input_capacity,
                retain_debug_rows: u32::from(retain_debug_hir_buffers),
            },
        );
        let hir_string_data_offset = graph_buffer!(u32, "hir_string_data_offset");
        let hir_string_decoded_len = graph_buffer!(u32, "hir_string_decoded_len");
        let hir_string_data_words = graph_buffer!(u32, "hir_string_data_words");
        let hir_string_pool_len = graph_buffer!(u32, "hir_string_pool_len");
        let hir_string_node = graph_buffer!(u32, "hir_string_node");
        let hir_string_count = graph_buffer!(u32, "hir_string_count");
        let hir_member_receiver_node = graph_buffer!(u32, "hir_member_receiver_node");
        let hir_member_receiver_token = graph_buffer!(u32, "hir_member_receiver_token");
        let hir_member_name_token = graph_buffer!(u32, "hir_member_name_token");
        let hir_stmt_scope_end = graph_buffer!(u32, "hir_stmt_scope_end");
        let hir_nearest_stmt_node = graph_buffer!(u32, "hir_nearest_stmt_node");
        let hir_nearest_block_node = graph_buffer!(u32, "hir_nearest_block_node");
        let hir_nearest_enclosing_control_node =
            graph_buffer!(u32, "hir_nearest_enclosing_control_node");
        let hir_nearest_loop_node = graph_buffer!(u32, "hir_nearest_loop_node");
        let hir_nearest_fn_node = graph_buffer!(u32, "hir_nearest_fn_node");
        let hir_nearest_array_element_node = graph_buffer!(u32, "hir_nearest_array_element_node");
        let hir_struct_field_parent_struct = graph_buffer!(u32, "hir_struct_field_parent_struct");
        let hir_struct_field_ordinal = graph_buffer!(u32, "hir_struct_field_ordinal");
        let hir_struct_field_type_node = graph_buffer!(u32, "hir_struct_field_type_node");
        let hir_struct_decl_field_start = graph_buffer!(u32, "hir_struct_decl_field_start");
        let hir_struct_decl_field_count = graph_buffer!(u32, "hir_struct_decl_field_count");
        let hir_struct_lit_head_node = graph_buffer!(u32, "hir_struct_lit_head_node");
        let hir_struct_lit_context_stmt_node =
            graph_buffer!(u32, "hir_struct_lit_context_stmt_node");
        let hir_struct_lit_field_start = graph_buffer!(u32, "hir_struct_lit_field_start");
        let hir_struct_lit_field_count = graph_buffer!(u32, "hir_struct_lit_field_count");
        let hir_struct_lit_field_parent_lit = graph_buffer!(u32, "hir_struct_lit_field_parent_lit");
        let hir_struct_lit_field_value_node = graph_buffer!(u32, "hir_struct_lit_field_value_node");
        // `prev_sibling` is consumed for the last time by
        // `hir_struct_field_links`. The following rank/scatter passes do not
        // read it, so the final struct-literal next-link output can reuse that
        // tree-sized buffer instead of retaining one more parser allocation.
        let hir_struct_lit_field_next =
            alias_storage_buffer::<u32, u32>(&prev_sibling, tree_capacity as usize);
        let hir_struct_field_owner_a = graph_buffer!(u32, "hir_struct_field_owner_a");
        let hir_struct_field_owner_b = graph_buffer!(u32, "hir_struct_field_owner_b");
        let hir_struct_field_link_a = graph_buffer!(u32, "hir_struct_field_link_a");
        let hir_struct_field_link_b = graph_buffer!(u32, "hir_struct_field_link_b");
        let hir_struct_field_rank_a = graph_buffer!(u32, "hir_struct_field_rank_a");
        let hir_struct_field_rank_b = graph_buffer!(u32, "hir_struct_field_rank_b");
        let hir_struct_lit_field_owner_a = graph_buffer!(u32, "hir_struct_lit_field_owner_a");
        let hir_struct_lit_field_owner_b = graph_buffer!(u32, "hir_struct_lit_field_owner_b");
        let hir_struct_lit_field_link_a = graph_buffer!(u32, "hir_struct_lit_field_link_a");
        let hir_struct_lit_field_link_b = graph_buffer!(u32, "hir_struct_lit_field_link_b");
        let hir_struct_lit_field_rank_a = graph_buffer!(u32, "hir_struct_lit_field_rank_a");
        let hir_struct_lit_field_rank_b = graph_buffer!(u32, "hir_struct_lit_field_rank_b");
        let hir_struct_lit_field_previous = graph_buffer!(u32, "hir_struct_lit_field_previous");
        let hir_stmt_context_link_a = graph_buffer!(u32, "hir_stmt_context_link_a");
        let hir_stmt_context_link_b = graph_buffer!(u32, "hir_stmt_context_link_b");
        let hir_contextual_stmt_value_a = graph_buffer!(u32, "hir_contextual_stmt_value_a");
        let hir_contextual_stmt_value_b = graph_buffer!(u32, "hir_contextual_stmt_value_b");
        let hir_nearest_stmt_value_a = graph_buffer!(u32, "hir_nearest_stmt_value_a");
        let hir_nearest_stmt_value_b = graph_buffer!(u32, "hir_nearest_stmt_value_b");
        let hir_nearest_block_value_a = graph_buffer!(u32, "hir_nearest_block_value_a");
        let hir_nearest_block_value_b = graph_buffer!(u32, "hir_nearest_block_value_b");
        let hir_nearest_enclosing_control_value_a =
            graph_buffer!(u32, "hir_nearest_enclosing_control_value_a");
        let hir_nearest_enclosing_control_value_b =
            graph_buffer!(u32, "hir_nearest_enclosing_control_value_b");
        let hir_nearest_loop_value_a = graph_buffer!(u32, "hir_nearest_loop_value_a");
        let hir_nearest_loop_value_b = graph_buffer!(u32, "hir_nearest_loop_value_b");
        let hir_nearest_fn_value_a = graph_buffer!(u32, "hir_nearest_fn_value_a");
        let hir_nearest_fn_value_b = graph_buffer!(u32, "hir_nearest_fn_value_b");
        let hir_nearest_array_element_value_a =
            graph_buffer!(u32, "hir_nearest_array_element_value_a");
        let hir_nearest_array_element_value_b =
            graph_buffer!(u32, "hir_nearest_array_element_value_b");
        let hir_struct_rank_flag = graph_buffer!(u32, "hir_struct_rank_flag");
        let hir_struct_rank_local_prefix = graph_buffer!(u32, "hir_struct_rank_local_prefix");
        let hir_struct_rank_block_sum = graph_buffer!(u32, "hir_struct_rank_block_sum");
        let hir_struct_rank_block_prefix_a = graph_buffer!(u32, "hir_struct_rank_block_prefix_a");
        let hir_struct_rank_block_prefix_b = graph_buffer!(u32, "hir_struct_rank_block_prefix_b");
        let hir_struct_rank_node = graph_buffer!(u32, "hir_struct_rank_node");
        let hir_struct_rank_count = graph_buffer!(u32, "hir_struct_rank_count");
        let hir_struct_rank_dispatch_args = graph_buffer!(u32, "hir_struct_rank_dispatch_args");
        let source_file_token_end_params = uniform_from_val(
            device,
            "parser.source_file_token_end.params",
            &super::passes::source_file_token_end::Params {
                token_capacity: token_input_capacity,
            },
        );
        let source_file_token_end = graph_buffer!(u32, "source_file_token_end");

        // Canonical HIR is the durable parser phase output. Candidate rows are
        // deduplicated by source-token anchor, so the token capacity is a hard
        // checked upper bound rather than a grammar-amplified estimate.
        let hir_canonical_capacity = token_input_capacity;
        assert!(
            tree_capacity < (1u32 << 28),
            "raw parse-tree capacity exceeds canonical HIR anchor arbitration range",
        );
        let hir_canonical_params = uniform_from_val(
            device,
            "parser.hir_canonical.params",
            &super::passes::hir::canonical::CanonicalHirParams {
                raw_capacity: tree_capacity,
                canonical_capacity: hir_canonical_capacity,
                uses_status_count: u32::from(tree_count_uses_status),
                local_ancestor_span: super::passes::hir::canonical::RELATION_LOCAL_ANCESTOR_SPAN,
                records_use_token_rows: u32::from(!retain_debug_hir_buffers),
            },
        );
        let hir_canonical_scan_params = uniform_from_val(
            device,
            "parser.hir_canonical.scan_params",
            &super::passes::hir::canonical::CanonicalScanParams {
                item_count: hir_canonical_capacity,
            },
        );
        let hir_canonical_prefix_scan =
            make_hir_prefix_scan_plan(device, hir_canonical_capacity.div_ceil(WG).max(1));
        let hir_canonical_count = graph_buffer!(u32, "hir_canonical_count");
        let hir_canonical_status = graph_buffer!(u32, "hir_canonical_status");
        // Family compaction resolves structural wrappers through the elected
        // source-anchor winner. Once every compact family has materialized,
        // the declaration-index passes repurpose this storage as the compact
        // type-declaration-name-token -> dense-HIR map retained by GpuHirView.
        let hir_canonical_anchor_owner = graph_buffer!(u32, "hir_canonical_anchor_owner");
        // The graph owns the phase aliasing between dead semantic-navigation
        // rows and canonical identity maps. Debug capacities retain separate
        // outputs; production capacities reuse the earlier graph resources.
        let hir_canonical_prefix_before_raw = graph_buffer!(u32, "hir_canonical_prefix_before_raw");
        let hir_canonical_dense_to_raw = graph_buffer!(u32, "hir_canonical_dense_to_raw");
        let hir_canonical_alias_to_dense = graph_buffer!(u32, "hir_canonical_alias_to_dense");
        let hir_canonical_raw_to_dense = graph_buffer!(u32, "hir_canonical_raw_to_dense");
        // Canonical statement and expression records are both read by the
        // compact-core pass. Their simultaneous access keeps them in distinct
        // graph slots without retaining either temporary beyond that pass.
        let hir_canonical_stmt_record = graph_buffer!(u32, "hir_canonical_stmt_record");
        let hir_canonical_expr_record = graph_buffer!(u32, "hir_canonical_expr_record");
        let hir_core = graph_buffer!(HirCore, "hir_core");
        let hir_payload = graph_buffer!(HirPayload, "hir_payload");
        let hir_links = graph_buffer!(HirLinks, "hir_links");
        let hir_canonical_semantic_facts =
            graph_buffer!(HirSemanticFacts, "hir_canonical_semantic_facts");
        let hir_canonical_semantic_dense_node =
            graph_buffer!(u32, "hir_canonical_semantic_dense_node");
        let hir_canonical_scope_end = graph_buffer!(u32, "hir_canonical_scope_end");
        let hir_canonical_nearest_loop = graph_buffer!(u32, "hir_canonical_nearest_loop");
        let hir_canonical_nearest_block = graph_buffer!(u32, "hir_canonical_nearest_block");
        let hir_canonical_nearest_control = graph_buffer!(u32, "hir_canonical_nearest_control");
        let hir_canonical_nearest_fn = graph_buffer!(u32, "hir_canonical_nearest_fn");
        let hir_canonical_context_stmt = graph_buffer!(u32, "hir_canonical_context_stmt");
        let hir_canonical_fn_return_type = graph_buffer!(u32, "hir_canonical_fn_return_type");
        let hir_canonical_type_root_owner = graph_buffer!(u32, "hir_canonical_type_root_owner");
        let hir_canonical_type_alias_target = graph_buffer!(u32, "hir_canonical_type_alias_target");
        let hir_canonical_const_type = graph_buffer!(u32, "hir_canonical_const_type");
        let hir_canonical_const_value = graph_buffer!(u32, "hir_canonical_const_value");
        // Parent publication uses owner-plus-one so the buffer can be reset
        // with a native zero clear. Once root initialization has decoded it,
        // the same physical slot becomes the pointer-jump scratch buffer.
        let hir_canonical_expr_parent_encoded =
            graph_buffer!(u32, "hir_canonical_expr_parent_encoded");
        let hir_canonical_expr_parent = graph_buffer!(u32, "hir_canonical_expr_parent");
        let hir_canonical_expr_root = graph_buffer!(u32, "hir_canonical_expr_root");
        let hir_canonical_expr_root_scratch = graph_buffer!(u32, "hir_canonical_expr_root_scratch");
        let hir_canonical_expr_forest_status =
            graph_buffer!(u32, "hir_canonical_expr_forest_status");
        let hir_call_arg_table_count = graph_buffer!(u32, "hir_call_arg_table_count");
        let hir_call_arg_family_flag = graph_buffer!(u32, "hir_call_arg_family_flag");
        let hir_call_args = graph_buffer!(HirCallArg, "hir_call_args");
        let hir_call_arg_ranges = graph_buffer!(HirRange, "hir_call_arg_ranges");
        let hir_param_table_count = graph_buffer!(u32, "hir_param_table_count");
        let hir_param_family_flag = graph_buffer!(u32, "hir_param_family_flag");
        let hir_param_rows = graph_buffer!(HirParam, "hir_param_rows");
        let hir_param_ranges = graph_buffer!(HirRange, "hir_param_ranges");
        let hir_type_arg_table_count = graph_buffer!(u32, "hir_type_arg_table_count");
        let hir_type_arg_family_flag = graph_buffer!(u32, "hir_type_arg_family_flag");
        let hir_type_arg_rows = graph_buffer!(HirTypeArg, "hir_type_arg_rows");
        let hir_type_arg_ranges = graph_buffer!(HirRange, "hir_type_arg_ranges");
        let hir_generic_param_table_count = graph_buffer!(u32, "hir_generic_param_table_count");
        let hir_generic_param_family_flag = graph_buffer!(u32, "hir_generic_param_family_flag");
        let hir_generic_param_rows = graph_buffer!(HirGenericParam, "hir_generic_param_rows");
        let hir_generic_param_ranges = graph_buffer!(HirRange, "hir_generic_param_ranges");
        let hir_path_segment_rows = graph_buffer!(HirPathSegment, "hir_path_segment_rows");
        let hir_canonical_string_rows = graph_buffer!(HirString, "hir_canonical_string_rows");
        let hir_method_core_rows = graph_buffer!(HirMethodCore, "hir_method_core_rows");
        let hir_method_signature_rows =
            graph_buffer!(HirMethodSignature, "hir_method_signature_rows");
        let hir_predicate_rows = graph_buffer!(HirPredicate, "hir_predicate_rows");
        let hir_path_table_count = graph_buffer!(u32, "hir_path_table_count");
        let hir_path_family_flag = graph_buffer!(u32, "hir_path_family_flag");
        let hir_path_rows = graph_buffer!(HirPath, "hir_path_rows");
        let hir_path_segment_table_count = graph_buffer!(u32, "hir_path_segment_table_count");
        let hir_field_table_count = graph_buffer!(u32, "hir_field_table_count");
        let hir_field_family_flag = graph_buffer!(u32, "hir_field_family_flag");
        let hir_field_rows = graph_buffer!(HirField, "hir_field_rows");
        let hir_variant_table_count = graph_buffer!(u32, "hir_variant_table_count");
        let hir_variant_family_flag = graph_buffer!(u32, "hir_variant_family_flag");
        let hir_variant_rows = graph_buffer!(HirVariant, "hir_variant_rows");
        // Variant and match-arm owners are meaningful HIR constructs with
        // distinct source-token anchors. Their temporary compact-row lookup
        // therefore uses the token domain rather than raw grammar-node ids.
        let hir_variant_raw_to_row = graph_buffer!(u32, "hir_variant_raw_to_row");
        let hir_variant_compact_payload_start =
            graph_buffer!(u32, "hir_variant_compact_payload_start");
        let hir_variant_compact_payload_count =
            graph_buffer!(u32, "hir_variant_compact_payload_count");
        let hir_variant_payload_table_count = graph_buffer!(u32, "hir_variant_payload_table_count");
        let hir_variant_payload_family_flag = graph_buffer!(u32, "hir_variant_payload_family_flag");
        let hir_variant_payload_rows = graph_buffer!(HirVariantPayload, "hir_variant_payload_rows");
        let hir_match_arm_table_count = graph_buffer!(u32, "hir_match_arm_table_count");
        let hir_match_arm_family_flag = if match_required {
            graph_buffer!(u32, "hir_match_arm_family_flag")
        } else {
            storage_rw_for_array::<u32>(device, "parser.hir_match_arm_family_flag.disabled", 1)
        };
        let hir_match_arm_raw_to_row =
            optional_graph_buffer!(u32, "hir_match_arm_raw_to_row", match_required);
        let hir_match_arm_rows = graph_buffer!(HirMatchArm, "hir_match_arm_rows");
        let hir_match_arm_ranges = graph_buffer!(HirRange, "hir_match_arm_ranges");
        let hir_match_pattern_to_arm = graph_buffer!(u32, "hir_match_pattern_to_arm");
        let hir_match_compact_payload_start = graph_buffer!(u32, "hir_match_compact_payload_start");
        let hir_match_compact_payload_count = graph_buffer!(u32, "hir_match_compact_payload_count");
        let hir_match_pattern_payload_count = graph_buffer!(u32, "hir_match_pattern_payload_count");
        let hir_match_payload_table_count = graph_buffer!(u32, "hir_match_payload_table_count");
        let hir_match_payload_family_flag = if match_required {
            graph_buffer!(u32, "hir_match_payload_family_flag")
        } else {
            storage_rw_for_array::<u32>(device, "parser.hir_match_payload_family_flag.disabled", 1)
        };
        let hir_match_payload_rows = graph_buffer!(HirMatchPayload, "hir_match_payload_rows");
        let hir_array_compact_element_start = graph_buffer!(u32, "hir_array_compact_element_start");
        let hir_array_compact_element_count = graph_buffer!(u32, "hir_array_compact_element_count");
        let hir_array_element_table_count = graph_buffer!(u32, "hir_array_element_table_count");
        let hir_array_element_family_flag = graph_buffer!(u32, "hir_array_element_family_flag");
        let hir_array_element_rows = graph_buffer!(HirArrayElement, "hir_array_element_rows");
        let hir_method_table_count = graph_buffer!(u32, "hir_method_table_count");
        let hir_method_family_flag = graph_buffer!(u32, "hir_method_family_flag");
        let hir_predicate_table_count = graph_buffer!(u32, "hir_predicate_table_count");
        let status_readback_operations = compiler_graph
            .status_readback_operations(
                &ll1_status,
                &partial_parse_status,
                &token_feature_flags,
                &tree_depth_status,
                &ll1_status_readback,
            )
            .expect("parser status readbacks must match the compiler graph");
        let dispatch_operations = compiler_graph
            .dispatch_operations(
                device,
                passes,
                &params_llp,
                &token_count,
                &active_pair_thread_dispatch_args,
                &tree_prefix_params,
                &ll1_status,
                &token_feature_flags,
                &tree_enum_dispatch_args,
                &tree_match_dispatch_args,
                &tree_struct_dispatch_args,
            )
            .expect("parser dispatch operations must match the compiler graph");
        let tree_bytes = u64::from(tree_capacity) * 4;
        let canonical_bytes = u64::from(hir_canonical_capacity) * 4;
        macro_rules! finalizer {
            ($name:expr, $bytes:expr; $($source:ident => $destination:ident),+ $(,)?) => {
                (
                    $name,
                    vec![$((
                        stringify!($source),
                        (&$source).into(),
                        stringify!($destination),
                        (&$destination).into(),
                        $bytes,
                    )),+],
                )
            };
        }
        macro_rules! count_copy {
            ($source_binding:literal, $source:expr, $destination_offset:expr, $byte_size:expr $(,)?) => {
                (
                    $source_binding,
                    $source.into(),
                    "hir_count_readback",
                    crate::gpu::buffers::TrackedBufferView::from(&hir_count_readback)
                        .subrange($destination_offset, $byte_size)
                        .expect("HIR count readback slice"),
                    $byte_size,
                )
            };
        }
        let copy_operations = crate::parser::compiler_graph::ParserCopyOperations::new(
            &compiler_graph,
            [
                (
                    crate::parser::compiler_graph::HIR_COUNTS_READBACK,
                    vec![
                        count_copy!("hir_semantic_count", &hir_semantic_count, 0, 4),
                        count_copy!("hir_canonical_count", &hir_canonical_count, 4, 4),
                        count_copy!("hir_canonical_status", &hir_canonical_status, 8, 52),
                        count_copy!("hir_call_arg_table_count", &hir_call_arg_table_count, 60, 4),
                        count_copy!("hir_param_table_count", &hir_param_table_count, 64, 4),
                        count_copy!("hir_type_arg_table_count", &hir_type_arg_table_count, 68, 4),
                        count_copy!(
                            "hir_generic_param_table_count",
                            &hir_generic_param_table_count,
                            72,
                            4,
                        ),
                        count_copy!("hir_path_table_count", &hir_path_table_count, 76, 4),
                        count_copy!(
                            "hir_path_segment_table_count",
                            &hir_path_segment_table_count,
                            80,
                            4,
                        ),
                        count_copy!("hir_field_table_count", &hir_field_table_count, 84, 4),
                        count_copy!("hir_variant_table_count", &hir_variant_table_count, 88, 4),
                        count_copy!(
                            "hir_variant_payload_table_count",
                            &hir_variant_payload_table_count,
                            92,
                            4,
                        ),
                        count_copy!("hir_match_arm_table_count", &hir_match_arm_table_count, 96, 4),
                        count_copy!(
                            "hir_match_payload_table_count",
                            &hir_match_payload_table_count,
                            100,
                            4,
                        ),
                        count_copy!(
                            "hir_array_element_table_count",
                            &hir_array_element_table_count,
                            104,
                            4,
                        ),
                        count_copy!("hir_string_count", &hir_string_count, 108, 4),
                        count_copy!("hir_method_table_count", &hir_method_table_count, 112, 4),
                        count_copy!(
                            "hir_predicate_table_count",
                            &hir_predicate_table_count,
                            116,
                            4,
                        ),
                    ],
                ),
                finalizer!(
                    crate::parser::compiler_graph::PACK_STATUS_PROMOTE,
                    24;
                    partial_parse_status => ll1_status,
                ),
                finalizer!(
                    crate::parser::passes::hir::types::root::step::FINALIZE,
                    tree_bytes;
                    hir_type_arg_link_b => hir_type_arg_link_a,
                    hir_type_arg_owner_b => hir_type_root_owner,
                ),
                finalizer!(
                    crate::parser::passes::hir::types::alias::owner::step::FINALIZE,
                    tree_bytes;
                    hir_type_alias_owner_link_b => hir_type_alias_owner_link_a,
                    hir_type_alias_owner_value_b => hir_type_alias_owner_value_a,
                ),
                finalizer!(
                    crate::parser::compiler_graph::HIR_TYPE_PATH_LEAF_FINALIZE,
                    tree_bytes;
                    hir_type_path_leaf_link_b => hir_type_path_leaf_link_a,
                    hir_type_path_leaf_value_b => hir_type_path_leaf_value_a,
                ),
                finalizer!(
                    crate::parser::passes::hir::path::segment::step::FINALIZE,
                    tree_bytes;
                    hir_path_segment_owner_b => hir_path_segment_owner_a,
                    hir_path_segment_link_b => hir_path_segment_link_a,
                    hir_path_segment_rank_b => hir_path_segment_rank_a,
                ),
                finalizer!(
                    crate::parser::passes::hir::expr::result_root_step::FINALIZE,
                    tree_bytes;
                    hir_expr_result_root_scratch_node => hir_expr_result_root_node,
                ),
                finalizer!(
                    crate::parser::passes::hir::binary::span::step::FINALIZE,
                    tree_bytes;
                    hir_binary_span_link_b => hir_binary_span_link_a,
                    hir_binary_span_start_b => hir_binary_span_start_a,
                ),
                finalizer!(
                    crate::parser::passes::hir::canonical::expr_forest::root_step::FINALIZE,
                    canonical_bytes;
                    hir_canonical_expr_root_scratch => hir_canonical_expr_root,
                ),
                finalizer!(
                    crate::parser::passes::hir::context::relations::step::FINALIZE,
                    tree_bytes;
                    hir_stmt_context_link_b => hir_stmt_context_link_a,
                    hir_contextual_stmt_value_b => hir_contextual_stmt_value_a,
                    hir_nearest_stmt_value_b => hir_nearest_stmt_value_a,
                    hir_nearest_block_value_b => hir_nearest_block_value_a,
                    hir_nearest_enclosing_control_value_b => hir_nearest_enclosing_control_value_a,
                    hir_nearest_loop_value_b => hir_nearest_loop_value_a,
                    hir_nearest_fn_value_b => hir_nearest_fn_value_a,
                    hir_nearest_array_element_value_b => hir_nearest_array_element_value_a,
                ),
                finalizer!(
                    crate::parser::passes::hir::enums::variant::rank_step::FINALIZE,
                    tree_bytes;
                    hir_variant_owner_b => hir_variant_owner_a,
                    hir_variant_link_b => hir_variant_link_a,
                    hir_variant_rank_b => hir_variant_rank_a,
                    hir_variant_payload_owner_b => hir_variant_payload_owner_a,
                    hir_variant_payload_link_b => hir_variant_payload_link_a,
                    hir_variant_payload_rank_b => hir_variant_payload_rank_a,
                ),
                finalizer!(
                    crate::parser::passes::hir::matches::arm::rank_step::FINALIZE,
                    tree_bytes;
                    hir_match_arm_owner_b => hir_match_arm_owner_a,
                    hir_match_arm_link_b => hir_match_arm_link_a,
                    hir_match_arm_rank_b => hir_match_arm_rank_a,
                    hir_match_payload_owner_b => hir_match_payload_owner_a,
                    hir_match_payload_link_b => hir_match_payload_link_a,
                    hir_match_payload_rank_b => hir_match_payload_rank_a,
                    hir_match_pattern_parent_b => hir_match_pattern_parent,
                ),
                finalizer!(
                    crate::parser::passes::hir::structs::field::rank_step::FINALIZE,
                    tree_bytes;
                    hir_struct_field_owner_b => hir_struct_field_owner_a,
                    hir_struct_field_link_b => hir_struct_field_link_a,
                    hir_struct_field_rank_b => hir_struct_field_rank_a,
                    hir_struct_lit_field_owner_b => hir_struct_lit_field_owner_a,
                    hir_struct_lit_field_link_b => hir_struct_lit_field_link_a,
                    hir_struct_lit_field_rank_b => hir_struct_lit_field_rank_a,
                ),
                finalizer!(
                    crate::parser::passes::hir::semantic::parent::step::MATCH_ARM_OWNER.finalize,
                    tree_bytes;
                    hir_semantic_parent_link_b => hir_semantic_parent_link_a,
                    hir_semantic_parent_value_b => hir_match_pattern_owner_arm,
                ),
                finalizer!(
                    crate::parser::passes::hir::semantic::parent::step::CANONICAL_VARIANT_PAYLOAD_OWNER.finalize,
                    tree_bytes;
                    hir_semantic_parent_link_b => hir_semantic_parent_link_a,
                    hir_semantic_parent_value_b => hir_semantic_parent_value_a,
                ),
            ],
        )
        .expect("parser finalizers must match the compiler graph");

        let buffers = Self {
            compiler_graph,
            resettable_buffers: Vec::new(),
            source_capacity: source_capacity.max(1),
            n_tokens,
            n_kinds,
            total_sc,
            total_emit,
            resident_sc_width,
            resident_emit_width,
            tree_count_uses_status,
            tree_capacity,
            parser_feature_flags,
            hir_array_capacity: family_capacities.arrays,
            hir_enum_match_capacity: family_capacities.enum_match,
            hir_struct_capacity: family_capacities.structs,
            hir_canonical_capacity,
            retain_debug_hir_buffers,

            ll1_status,
            ll1_status_readback,
            hir_count_readback,
            status_readback_operations,
            dispatch_operations,
            copy_operations,
            clear_operations: std::sync::OnceLock::new(),
            job_storage_reset: None,
            params_llp,
            semantic_token_kinds,
            token_delimiter_params,
            token_block_scan_plan,
            token_input_capacity,
            token_delimiter_n_blocks,
            token_depth_paren_inblock,
            token_depth_brace_inblock,
            token_depth_bracket_inblock,
            token_depth_angle_inblock,
            token_block_sum_paren,
            token_block_sum_brace,
            token_block_sum_bracket,
            token_block_sum_angle,
            token_prefix_paren_a,
            token_block_prefix_paren,
            token_prefix_brace_a,
            token_block_prefix_brace,
            token_prefix_bracket_a,
            token_block_prefix_bracket,
            token_prefix_angle_a,
            token_block_prefix_angle,
            token_top_brace_owner_block,
            token_top_brace_owner_prefix_a,
            token_top_brace_owner_block_prefix,
            token_statement_event_block,
            token_statement_event_prefix_a,
            token_statement_event_block_prefix,
            token_brace_semantic_kind,
            token_braced_rhs_statement_kind,
            token_bracket_semantic_kind,
            token_statement_context_kind,
            token_impl_header_kind,
            token_impl_context_event,
            token_type_path_context_kind,
            token_where_context_event,
            token_match_pattern_context_event,
            token_generic_shr_block_sum,
            token_generic_shr_block_min,
            token_generic_shr_prefix_sum_a,
            token_generic_shr_prefix_min_a,
            token_generic_shr_block_prefix_sum,
            token_generic_shr_block_prefix_min,
            token_brace_match_params,
            token_brace_match_depth,
            token_brace_match_block_min,
            token_brace_match_min_tree_base,
            token_brace_match_min_tree,
            token_brace_match_min_tree_steps,
            token_bracket_match_depth,
            token_bracket_match_block_min,
            token_bracket_match_min_tree,
            token_paren_match_depth,
            token_paren_match_block_min,
            token_paren_match_min_tree,
            token_angle_match_depth,
            token_angle_match_block_min,
            token_angle_match_min_tree,
            token_feature_flags,
            token_count,
            default_token_file_id,
            source_file_token_end_params,
            source_file_token_end,
            active_pair_thread_dispatch_args,
            active_stack_thread_dispatch_args,
            action_table,
            out_headers,

            params_pack,
            pack_offsets_status_params,
            sc_offsets,
            emit_offsets,
            pack_sc_prefix_a,
            pack_sc_prefix_b,
            pack_emit_prefix_a,
            pack_emit_prefix_b,
            pack_offset_scan_plan,
            pack_totals_blocks_params,
            pack_total_reduce_steps,
            pack_totals_status_params,
            partial_parse_status,
            tables_blob,
            out_sc,
            out_emit,
            out_emit_pos,

            b01_params,
            b02_params,
            b02_scan_plan,
            b03_params,
            b07_params,
            b_clear_matches_params,
            emit_stack_matches,
            b_min_tree_base,
            b_min_tree,
            b_min_tree_steps,

            b_exscan_inblock,
            b_block_sum,
            b_block_minpref,
            b_block_row_min,
            b_block_maxdepth,
            b_block_prefix,
            b_block_prefix_sum_a,
            b_block_prefix_sum_b,
            b_block_prefix_min_a,
            b_block_prefix_min_b,

            depths_out,
            valid_out,

            b_layer,
            match_for_index,

            b_n_blocks: n_blocks,

            // Tree parent recovery
            tree_prefix_params,
            tree_prefix_scan_steps,
            tree_n_node_blocks,
            tree_active_dispatch_args,
            tree_enum_dispatch_args,
            tree_match_dispatch_args,
            tree_struct_dispatch_args,
            tree_depth_status,
            hir_raw_relation_dispatch_args,
            hir_local_relation_dispatch_args,
            hir_semantic_dispatch_args,
            hir_semantic_relation_dispatch_args,
            tree_depth_block_max,
            tree_prefix_inblock,
            tree_block_sum,
            tree_block_prefix_a,
            tree_block_prefix_b,
            tree_block_prefix,
            tree_prefix,
            tree_prefix_block_max,
            tree_prefix_block_max_tree,
            tree_prefix_max_build_steps,
            tree_params,
            tree_span_params,
            tree_prev_sibling_params,
            prod_arity,
            node_kind,
            parent,
            first_child,
            next_sibling,
            prev_sibling,
            subtree_end,

            // HIR-facing classification
            hir_param_rows,
            hir_param_ranges,
            hir_type_arg_table_count,
            hir_type_arg_family_flag,
            hir_type_arg_rows,
            hir_type_arg_ranges,
            hir_generic_param_table_count,
            hir_generic_param_family_flag,
            hir_generic_param_rows,
            hir_generic_param_ranges,
            hir_path_table_count,
            hir_path_family_flag,
            hir_path_rows,
            hir_path_segment_table_count,
            hir_path_segment_rows,
            hir_field_table_count,
            hir_field_family_flag,
            hir_field_rows,
            hir_variant_table_count,
            hir_variant_family_flag,
            hir_variant_rows,
            hir_variant_raw_to_row,
            hir_variant_compact_payload_start,
            hir_variant_compact_payload_count,
            hir_variant_payload_table_count,
            hir_variant_payload_family_flag,
            hir_variant_payload_rows,
            hir_match_arm_table_count,
            hir_match_arm_family_flag,
            hir_match_arm_raw_to_row,
            hir_match_arm_rows,
            hir_match_arm_ranges,
            hir_match_pattern_to_arm,
            hir_match_compact_payload_start,
            hir_match_compact_payload_count,
            hir_match_pattern_payload_count,
            hir_match_payload_table_count,
            hir_match_payload_family_flag,
            hir_match_payload_rows,
            hir_array_compact_element_start,
            hir_array_compact_element_count,
            hir_array_element_table_count,
            hir_array_element_family_flag,
            hir_array_element_rows,
            hir_canonical_string_rows,
            hir_method_table_count,
            hir_method_family_flag,
            hir_method_core_rows,
            hir_method_signature_rows,
            hir_predicate_table_count,
            hir_predicate_rows,
            hir_span_params,
            hir_type_fields_params,
            hir_item_fields_params,
            hir_param_fields_params,
            hir_method_fields_params,
            hir_expr_fields_params,
            hir_member_fields_params,
            hir_stmt_fields_params,
            hir_call_fields_params,
            hir_array_fields_params,
            hir_enum_match_fields_params,
            hir_struct_fields_params,
            hir_kind,
            hir_semantic_block_count,
            hir_semantic_prefix_scan,
            hir_canonical_prefix_scan,
            hir_semantic_flag,
            hir_semantic_local_prefix,
            hir_semantic_block_prefix_a,
            hir_semantic_block_prefix_b,
            hir_node_dense_id,
            hir_semantic_prefix_before_node,
            hir_semantic_dense_node,
            hir_semantic_subtree_end,
            hir_semantic_parent,
            hir_semantic_first_child,
            hir_semantic_next_sibling,
            hir_semantic_depth,
            hir_semantic_child_index,
            hir_semantic_parent_link_a,
            hir_semantic_parent_link_b,
            hir_semantic_parent_value_a,
            hir_semantic_parent_value_b,
            tree_depth,
            hir_semantic_count,
            hir_canonical_params,
            hir_canonical_scan_params,
            hir_canonical_count,
            hir_canonical_status,
            hir_canonical_anchor_owner,
            hir_canonical_prefix_before_raw,
            hir_canonical_dense_to_raw,
            hir_canonical_alias_to_dense,
            hir_canonical_raw_to_dense,
            hir_canonical_stmt_record,
            hir_canonical_expr_record,
            hir_core,
            hir_links,
            hir_payload,
            hir_canonical_semantic_facts,
            hir_canonical_semantic_dense_node,
            hir_canonical_scope_end,
            hir_canonical_nearest_loop,
            hir_canonical_nearest_block,
            hir_canonical_nearest_control,
            hir_canonical_nearest_fn,
            hir_canonical_context_stmt,
            hir_canonical_fn_return_type,
            hir_canonical_type_root_owner,
            hir_canonical_type_alias_target,
            hir_canonical_const_type,
            hir_canonical_const_value,
            hir_canonical_expr_parent_encoded,
            hir_canonical_expr_parent,
            hir_canonical_expr_root,
            hir_canonical_expr_root_scratch,
            hir_canonical_expr_forest_status,
            hir_call_arg_table_count,
            hir_call_arg_family_flag,
            hir_call_args,
            hir_call_arg_ranges,
            hir_param_table_count,
            hir_param_family_flag,
            hir_params,
            hir_token_pos,
            hir_token_end,
            hir_token_file_id,
            hir_type_form,
            hir_type_value_node,
            hir_type_len_token,
            hir_type_len_value,
            hir_type_file_id,
            hir_type_path_leaf_node,
            hir_bound_path_owner_by_leaf,
            hir_path_root_owner,
            hir_path_segment_owner_a,
            hir_path_segment_owner_b,
            hir_path_segment_link_a,
            hir_path_segment_link_b,
            hir_path_segment_rank_a,
            hir_path_segment_rank_b,
            hir_path_segment_count,
            hir_type_path_leaf_link_a,
            hir_type_path_leaf_link_b,
            hir_type_path_leaf_value_a,
            hir_type_path_leaf_value_b,
            hir_type_arg_start,
            hir_type_arg_count,
            hir_type_arg_next,
            hir_type_alias_target_node,
            hir_fn_return_type_node,
            hir_type_arg_owner_a,
            hir_type_arg_owner_b,
            hir_type_arg_link_a,
            hir_type_arg_link_b,
            hir_type_arg_rank_a,
            hir_type_arg_rank_b,
            hir_type_arg_previous,
            hir_type_root_owner,
            hir_type_alias_owner_link_a,
            hir_type_alias_owner_link_b,
            hir_type_alias_owner_value_a,
            hir_type_alias_owner_value_b,
            hir_item_kind,
            hir_item_name_token,
            hir_item_namespace,
            hir_item_visibility,
            hir_item_path_start,
            hir_item_path_end,
            hir_item_path_node,
            hir_item_file_id,
            hir_item_import_target_kind,
            hir_param_record,
            hir_param_type_node,
            hir_method_owner_node,
            hir_method_impl_node,
            hir_method_name_token,
            hir_method_first_param_token,
            hir_method_receiver_mode,
            hir_method_visibility,
            hir_method_signature_flags,
            hir_method_impl_receiver_type_node,
            hir_param_owner_a,
            hir_param_link_a,
            hir_param_rank_a,
            hir_param_rank_b,
            hir_variant_parent_enum,
            hir_variant_ordinal,
            hir_variant_payload_start,
            hir_variant_payload_count,
            hir_variant_payload_node,
            hir_variant_owner_a,
            hir_variant_owner_b,
            hir_variant_link_a,
            hir_variant_link_b,
            hir_variant_rank_a,
            hir_variant_rank_b,
            hir_variant_payload_owner_a,
            hir_variant_payload_owner_b,
            hir_variant_payload_link_a,
            hir_variant_payload_link_b,
            hir_variant_payload_rank_a,
            hir_variant_payload_rank_b,
            hir_list_rank_flag,
            hir_list_rank_local_prefix,
            hir_list_rank_block_sum,
            hir_list_rank_block_prefix_a,
            hir_list_rank_block_prefix_b,
            hir_list_rank_node,
            hir_list_rank_count,
            hir_list_rank_dispatch_args,
            hir_enum_rank_flag,
            hir_enum_rank_local_prefix,
            hir_enum_rank_block_sum,
            hir_enum_rank_block_prefix_a,
            hir_enum_rank_block_prefix_b,
            hir_enum_rank_node,
            hir_enum_rank_count,
            hir_enum_rank_dispatch_args,
            hir_match_scrutinee_node,
            hir_match_arm_start,
            hir_match_arm_count,
            hir_match_arm_next,
            hir_match_arm_pattern_node,
            hir_match_pattern_owner_arm,
            hir_match_arm_payload_start,
            hir_match_arm_payload_count,
            hir_match_arm_result_node,
            hir_match_payload_owner_arm,
            hir_match_payload_match_node,
            hir_match_payload_ordinal,
            hir_match_arm_owner_a,
            hir_match_arm_owner_b,
            hir_match_arm_link_a,
            hir_match_arm_link_b,
            hir_match_arm_rank_a,
            hir_match_arm_rank_b,
            hir_match_arm_previous,
            hir_match_payload_owner_a,
            hir_match_payload_owner_b,
            hir_match_payload_link_a,
            hir_match_payload_link_b,
            hir_match_pattern_parent,
            hir_match_pattern_parent_b,
            hir_match_payload_rank_a,
            hir_match_payload_rank_b,
            hir_match_rank_flag,
            hir_match_rank_local_prefix,
            hir_match_rank_block_sum,
            hir_match_rank_block_prefix_a,
            hir_match_rank_block_prefix_b,
            hir_match_rank_node,
            hir_match_rank_count,
            hir_match_rank_dispatch_args,
            hir_call_callee_node,
            hir_call_callee_path_node,
            hir_call_parent_by_callee,
            hir_call_context_stmt_node,
            hir_call_arg_start,
            hir_call_arg_end,
            hir_call_arg_count,
            hir_call_arg_parent_call,
            hir_call_arg_ordinal,
            hir_call_arg_owner_a,
            hir_call_arg_owner_b,
            hir_call_arg_link_a,
            hir_call_arg_link_b,
            hir_call_arg_rank_a,
            hir_call_arg_rank_b,
            hir_array_lit_first_element,
            hir_array_lit_element_count,
            hir_array_lit_context_stmt_node,
            hir_array_element_parent_lit,
            hir_array_element_ordinal,
            hir_array_element_next,
            hir_array_element_owner_a,
            hir_array_element_owner_b,
            hir_array_element_link_a,
            hir_array_element_link_b,
            hir_array_element_rank_a,
            hir_array_element_rank_b,
            hir_array_element_previous,
            hir_expr_record,
            hir_expr_name_role,
            hir_expr_result_root_node,
            hir_expr_result_root_scratch_node,
            hir_binary_span_link_a,
            hir_binary_span_link_b,
            hir_binary_span_start_a,
            hir_binary_span_start_b,
            hir_expr_int_value,
            hir_expr_float_bits,
            hir_expr_string_start,
            hir_expr_string_len,
            hir_literal_values_params,
            hir_string_decode_params,
            hir_string_data_offset,
            hir_string_decoded_len,
            hir_string_data_words,
            hir_string_pool_len,
            hir_string_node,
            hir_string_count,
            hir_member_receiver_node,
            hir_member_receiver_token,
            hir_member_name_token,
            hir_stmt_record,
            hir_stmt_scope_end,
            hir_nearest_stmt_node,
            hir_nearest_block_node,
            hir_nearest_enclosing_control_node,
            hir_nearest_loop_node,
            hir_nearest_fn_node,
            hir_nearest_array_element_node,
            hir_struct_field_parent_struct,
            hir_struct_field_ordinal,
            hir_struct_field_type_node,
            hir_struct_decl_field_start,
            hir_struct_decl_field_count,
            hir_struct_lit_head_node,
            hir_struct_lit_context_stmt_node,
            hir_struct_lit_field_start,
            hir_struct_lit_field_count,
            hir_struct_lit_field_parent_lit,
            hir_struct_lit_field_value_node,
            hir_struct_lit_field_next,
            hir_struct_field_owner_a,
            hir_struct_field_owner_b,
            hir_struct_field_link_a,
            hir_struct_field_link_b,
            hir_struct_field_rank_a,
            hir_struct_field_rank_b,
            hir_struct_lit_field_owner_a,
            hir_struct_lit_field_owner_b,
            hir_struct_lit_field_link_a,
            hir_struct_lit_field_link_b,
            hir_struct_lit_field_rank_a,
            hir_struct_lit_field_rank_b,
            hir_struct_lit_field_previous,
            hir_stmt_context_link_a,
            hir_stmt_context_link_b,
            hir_contextual_stmt_value_a,
            hir_contextual_stmt_value_b,
            hir_nearest_stmt_value_a,
            hir_nearest_stmt_value_b,
            hir_nearest_block_value_a,
            hir_nearest_block_value_b,
            hir_nearest_enclosing_control_value_a,
            hir_nearest_enclosing_control_value_b,
            hir_nearest_loop_value_a,
            hir_nearest_loop_value_b,
            hir_nearest_fn_value_a,
            hir_nearest_fn_value_b,
            hir_nearest_array_element_value_a,
            hir_nearest_array_element_value_b,
            hir_struct_rank_flag,
            hir_struct_rank_local_prefix,
            hir_struct_rank_block_sum,
            hir_struct_rank_block_prefix_a,
            hir_struct_rank_block_prefix_b,
            hir_struct_rank_node,
            hir_struct_rank_count,
            hir_struct_rank_dispatch_args,
        };
        let clear_operations = buffers
            .compiler_graph
            .clear_operations(&buffers)
            .expect("parser clear operations must match the compiler graph");
        assert!(
            buffers.clear_operations.set(clear_operations).is_ok(),
            "parser clear operations initialized twice"
        );
        buffers
    }
}
