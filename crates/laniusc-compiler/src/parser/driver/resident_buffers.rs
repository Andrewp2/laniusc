use super::{GpuParser, ResidentParserBufferCache, support::table_fingerprint};
use crate::{
    gpu::buffers::collect_resettable_buffers,
    lexer::features::CONSERVATIVE_PARSER_FEATURES,
    parser::{buffers::ParserBuffers, tables::PrecomputedParseTables},
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct ResidentParserAllocation {
    token_capacity: u32,
    source_capacity: u32,
    tree_capacity: u32,
    parser_feature_flags: u32,
}

impl ResidentParserAllocation {
    fn grow_to_cover(self, required: Self) -> Self {
        let same_feature_shape = self.parser_feature_flags == required.parser_feature_flags;
        Self {
            // A feature-shape transition changes which optional HIR families
            // are real storage versus sentinels.  Do not retain the previous
            // unit's larger physical shape across that boundary: rebuilding at
            // the current unit's dimensions prevents stale family rows from
            // being addressed by the new parser.  For an unchanged shape the
            // resident workspace remains capacity-reusable and grows only as
            // required.
            token_capacity: if same_feature_shape {
                self.token_capacity.max(required.token_capacity)
            } else {
                required.token_capacity
            },
            source_capacity: if same_feature_shape {
                self.source_capacity.max(required.source_capacity)
            } else {
                required.source_capacity
            },
            tree_capacity: if same_feature_shape {
                self.tree_capacity.max(required.tree_capacity)
            } else {
                required.tree_capacity
            },
            // Feature flags select which optional HIR families are allocated and
            // which parser-family passes are valid for the current source unit.
            // They are not a monotonic capacity dimension: carrying a previous
            // unit's bits into this allocation makes absent families look
            // present after a cache transition.  The capacities themselves stay
            // monotonic; the feature mask is exactly the current requirement.
            parser_feature_flags: required.parser_feature_flags,
        }
    }
}

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
            token_capacity,
            tables,
            tree_capacity_override,
            false,
            parser_feature_flags,
        )
    }

    pub(in crate::parser::driver) fn resident_buffers_for_with_tree_capacity_and_debug<'a>(
        &self,
        slot: &'a mut Option<ResidentParserBufferCache>,
        token_capacity: u32,
        source_capacity: u32,
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
        let required = ResidentParserAllocation {
            token_capacity: wanted_capacity,
            source_capacity: source_capacity.max(1),
            tree_capacity: wanted_tree_capacity,
            parser_feature_flags,
        };
        let compatible = slot.as_ref().filter(|cached| {
            cached.table_fingerprint == fingerprint
                && cached.retain_debug_hir_buffers == retain_debug_hir_buffers
        });
        let cached_allocation = compatible.map(|cached| ResidentParserAllocation {
            token_capacity: cached.token_capacity,
            source_capacity: cached.buffers.source_capacity,
            tree_capacity: cached.buffers.tree_capacity,
            parser_feature_flags: cached.parser_feature_flags,
        });
        let allocation = cached_allocation
            .map(|cached| cached.grow_to_cover(required))
            .unwrap_or(required);
        let needs_allocate = cached_allocation != Some(allocation);

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

            let action_table_bytes = tables.to_action_header_grid_bytes();
            let (mut buffers, resettable_buffers) = collect_resettable_buffers(|| {
                ParserBuffers::new_resident_capacity_with_source_and_tree_capacity_debug_and_features(
                    &self.device,
                    allocation.token_capacity,
                    allocation.source_capacity,
                    tables.n_kinds,
                    &action_table_bytes,
                    tables,
                    Some(allocation.tree_capacity),
                    retain_debug_hir_buffers,
                    allocation.parser_feature_flags,
                )
            });
            buffers.resettable_buffers = resettable_buffers;
            *slot = Some(ResidentParserBufferCache {
                token_capacity: allocation.token_capacity,
                table_fingerprint: fingerprint,
                retain_debug_hir_buffers,
                parser_feature_flags: allocation.parser_feature_flags,
                buffers,
            });
            self.bg_cache
                .lock()
                .expect("parser.bg_cache poisoned")
                .clear();
        }
        let cached = slot.as_mut().expect("resident parser buffers allocated");
        cached
            .buffers
            .set_active_token_capacity(&self.queue, wanted_capacity);
        // Allocation capacity is intentionally monotonic, but feature
        // dispatch is a property of the current source unit.  A larger
        // preceding job may have caused the resident allocation to retain
        // optional-family storage; carrying its feature mask into the next
        // HIR view would make absent families appear present and would cause
        // type-check passes to consume stale rows.  Keep the physical
        // capacities monotonic while publishing the current unit's mask.
        cached.buffers.parser_feature_flags = parser_feature_flags;
        &cached.buffers
    }
}

#[cfg(test)]
mod tests {
    use super::ResidentParserAllocation;

    #[test]
    fn resident_allocation_grows_without_shrinking_any_capacity() {
        let first = ResidentParserAllocation {
            token_capacity: 300,
            source_capacity: 1_000,
            tree_capacity: 700,
            parser_feature_flags: 0b0011,
        };
        let next = ResidentParserAllocation {
            token_capacity: 320,
            source_capacity: 900,
            tree_capacity: 650,
            parser_feature_flags: 0b1100,
        };
        assert_eq!(
            first.grow_to_cover(next),
            ResidentParserAllocation {
                token_capacity: 320,
                source_capacity: 900,
                tree_capacity: 650,
                parser_feature_flags: 0b1100,
            }
        );
    }

    #[test]
    fn resident_allocation_grows_for_same_feature_shape() {
        let first = ResidentParserAllocation {
            token_capacity: 300,
            source_capacity: 1_000,
            tree_capacity: 700,
            parser_feature_flags: 0b0011,
        };
        let next = ResidentParserAllocation {
            token_capacity: 320,
            source_capacity: 900,
            tree_capacity: 650,
            parser_feature_flags: 0b0011,
        };
        assert_eq!(
            first.grow_to_cover(next),
            ResidentParserAllocation {
                token_capacity: 320,
                source_capacity: 1_000,
                tree_capacity: 700,
                parser_feature_flags: 0b0011,
            }
        );
    }
}
