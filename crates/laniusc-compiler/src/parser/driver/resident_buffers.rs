use super::{GpuParser, ResidentParserBufferCache, support::table_fingerprint};
use crate::{
    lexer::features::CONSERVATIVE_PARSER_FEATURES,
    parser::{buffers::ParserBuffers, tables::PrecomputedParseTables},
};

impl GpuParser {
    /// Returns cached resident parser buffers sized for the current token/table pair.
    pub(in crate::parser::driver) fn resident_buffers_for<'a>(
        &self,
        slot: &'a mut Option<ResidentParserBufferCache>,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
    ) -> &'a ParserBuffers {
        self.resident_buffers_for_with_tree_capacity_and_debug(
            slot,
            token_capacity,
            tables,
            None,
            false,
            CONSERVATIVE_PARSER_FEATURES,
        )
    }

    /// Returns resident parser buffers that retain extra HIR debug readback storage.
    pub(in crate::parser::driver) fn resident_debug_buffers_for<'a>(
        &self,
        slot: &'a mut Option<ResidentParserBufferCache>,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
    ) -> &'a ParserBuffers {
        self.resident_buffers_for_with_tree_capacity_and_debug(
            slot,
            token_capacity,
            tables,
            None,
            true,
            CONSERVATIVE_PARSER_FEATURES,
        )
    }

    /// Returns resident parser buffers with an explicit recovered-tree capacity.
    pub(in crate::parser::driver) fn resident_buffers_for_with_tree_capacity<'a>(
        &self,
        slot: &'a mut Option<ResidentParserBufferCache>,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
    ) -> &'a ParserBuffers {
        self.resident_buffers_for_with_tree_capacity_and_debug(
            slot,
            token_capacity,
            tables,
            tree_capacity_override,
            false,
            CONSERVATIVE_PARSER_FEATURES,
        )
    }

    /// Returns resident buffers whose optional HIR families match a
    /// conservative GPU-lexer feature summary.
    pub(in crate::parser::driver) fn resident_buffers_for_with_tree_capacity_and_features<'a>(
        &self,
        slot: &'a mut Option<ResidentParserBufferCache>,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
        parser_feature_flags: u32,
    ) -> &'a ParserBuffers {
        self.resident_buffers_for_with_tree_capacity_and_debug(
            slot,
            token_capacity,
            tables,
            tree_capacity_override,
            false,
            parser_feature_flags,
        )
    }

    fn resident_buffers_for_with_tree_capacity_and_debug<'a>(
        &self,
        slot: &'a mut Option<ResidentParserBufferCache>,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
        retain_debug_hir_buffers: bool,
        parser_feature_flags: u32,
    ) -> &'a ParserBuffers {
        let fingerprint = table_fingerprint(tables);
        let wanted_capacity = token_capacity.max(1);
        let wanted_tree_capacity = tree_capacity_override
            .map(|capacity| capacity.max(1))
            .unwrap_or_else(|| {
                crate::parser::buffers::resident_partial_parse_tree_capacity_for_tables(
                    wanted_capacity,
                    tables,
                )
            });
        let needs_allocate = slot.as_ref().is_none_or(|cached| {
            cached.table_fingerprint != fingerprint
                || cached.token_capacity != wanted_capacity
                || cached.retain_debug_hir_buffers != retain_debug_hir_buffers
                || cached.parser_feature_flags != parser_feature_flags
                || cached.buffers.tree_capacity < wanted_tree_capacity
        });

        if crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false) {
            if let Some(cached) = slot.as_ref() {
                eprintln!(
                    "[gpu_compile_host_timer] parser.resident_cache: allocate={needs_allocate} wanted_tokens={wanted_capacity} cached_tokens={} wanted_tree={wanted_tree_capacity} cached_tree={} wanted_features=0x{parser_feature_flags:08x} cached_features=0x{:08x} wanted_debug={retain_debug_hir_buffers} cached_debug={}",
                    cached.token_capacity,
                    cached.buffers.tree_capacity,
                    cached.parser_feature_flags,
                    cached.retain_debug_hir_buffers,
                );
            } else {
                eprintln!(
                    "[gpu_compile_host_timer] parser.resident_cache: allocate=true reason=empty wanted_tokens={wanted_capacity} wanted_tree={wanted_tree_capacity} wanted_features=0x{parser_feature_flags:08x} wanted_debug={retain_debug_hir_buffers}"
                );
            }
        }

        if needs_allocate {
            *slot = None;
            self.bg_cache
                .lock()
                .expect("parser.bg_cache poisoned")
                .clear();
            *self
                .resident_token_kind_bind_groups
                .lock()
                .expect("parser.resident_token_kind_bind_groups poisoned") = None;
            let _ = self.device.poll(wgpu::PollType::wait_indefinitely());

            // Resident parser buffers dominate VRAM because tree/HIR scratch scales
            // from token capacity. Allocate the exact required capacity instead of
            // doubling across increasing benchmark sizes.
            let allocated_capacity = wanted_capacity;
            let action_table_bytes = tables.to_action_header_grid_bytes();
            *slot = Some(ResidentParserBufferCache {
                token_capacity: allocated_capacity,
                table_fingerprint: fingerprint,
                retain_debug_hir_buffers,
                parser_feature_flags,
                buffers: ParserBuffers::new_resident_capacity_with_tree_capacity_debug_and_features(
                    &self.device,
                    wanted_capacity,
                    tables.n_kinds,
                    &action_table_bytes,
                    tables,
                    tree_capacity_override,
                    retain_debug_hir_buffers,
                    parser_feature_flags,
                ),
            });
            self.bg_cache
                .lock()
                .expect("parser.bg_cache poisoned")
                .clear();
        }
        &slot
            .as_ref()
            .expect("resident parser buffers allocated")
            .buffers
    }
}
