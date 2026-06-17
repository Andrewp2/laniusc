use super::{GpuParser, ResidentParserBufferCache, support::table_fingerprint};
use crate::parser::{buffers::ParserBuffers, tables::PrecomputedParseTables};

impl GpuParser {
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
        )
    }

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
        )
    }

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
        )
    }

    fn resident_buffers_for_with_tree_capacity_and_debug<'a>(
        &self,
        slot: &'a mut Option<ResidentParserBufferCache>,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
        retain_debug_hir_buffers: bool,
    ) -> &'a ParserBuffers {
        let fingerprint = table_fingerprint(tables);
        let wanted_capacity = token_capacity.max(1);
        let needs_allocate = slot.as_ref().is_none_or(|cached| {
            cached.table_fingerprint != fingerprint
                || cached.token_capacity != wanted_capacity
                || cached.retain_debug_hir_buffers != retain_debug_hir_buffers
                || match (cached.tree_capacity_override, tree_capacity_override) {
                    (None, None) => false,
                    (Some(_), None) | (None, Some(_)) => true,
                    (Some(_), Some(wanted_tree_capacity)) => {
                        cached.buffers.tree_capacity != wanted_tree_capacity.max(1)
                    }
                }
        });

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
                tree_capacity_override,
                table_fingerprint: fingerprint,
                retain_debug_hir_buffers,
                buffers: ParserBuffers::new_resident_capacity_with_tree_capacity_and_debug(
                    &self.device,
                    wanted_capacity,
                    tables.n_kinds,
                    &action_table_bytes,
                    tables,
                    tree_capacity_override,
                    retain_debug_hir_buffers,
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
