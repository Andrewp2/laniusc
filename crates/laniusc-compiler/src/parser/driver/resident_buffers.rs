use super::{GpuParser, ResidentParserBufferCache, support::table_fingerprint};
use crate::{
    gpu::buffers::{collect_resettable_buffers, with_uniform_buffer_arena},
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
    const GRANULARITY: u32 = 4 * 1024;

    fn capacity_bucket(value: u32) -> u32 {
        value
            .max(1)
            .div_ceil(Self::GRANULARITY)
            .saturating_mul(Self::GRANULARITY)
    }

    fn bucketed(self) -> Self {
        Self {
            token_capacity: Self::capacity_bucket(self.token_capacity),
            source_capacity: Self::capacity_bucket(self.source_capacity),
            tree_capacity: Self::capacity_bucket(self.tree_capacity),
            parser_feature_flags: self.parser_feature_flags,
        }
    }

    fn covers(self, required: Self) -> bool {
        self.token_capacity >= required.token_capacity
            && self.source_capacity >= required.source_capacity
            && self.tree_capacity >= required.tree_capacity
            && self.parser_feature_flags & required.parser_feature_flags
                == required.parser_feature_flags
    }

    fn grow_to_cover(self, required: Self) -> Self {
        Self {
            token_capacity: self.token_capacity.max(required.token_capacity),
            source_capacity: self.source_capacity.max(required.source_capacity),
            tree_capacity: self.tree_capacity.max(required.tree_capacity),
            // This mask describes allocated optional-family storage, not the
            // current job. ParserBuffers::parser_feature_flags is set to the
            // current job below, after the reusable allocation is selected.
            parser_feature_flags: self.parser_feature_flags | required.parser_feature_flags,
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
            .unwrap_or(required)
            .bucketed();
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
                .resident_token_kind_operations
                .lock()
                .expect("parser.resident_token_kind_operations poisoned") = None;
            self.token_compute_operations
                .lock()
                .expect("parser.token_compute_operations poisoned")
                .clear();
            let _ = self.device.poll(wgpu::PollType::wait_indefinitely());

            let action_table_bytes = tables.to_action_header_grid_bytes();
            let (mut buffers, resettable_buffers) = with_uniform_buffer_arena(
                &self.device,
                "parser.uniform_arena",
                || {
                    collect_resettable_buffers(|| {
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
                            &self.passes,
                        )
                    })
                },
            );
            buffers.resettable_buffers = resettable_buffers;
            buffers.install_job_storage_reset();
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

    /// Whether the current parser allocation can record this job without
    /// replacing any buffer identities.
    pub(crate) fn current_resident_allocation_covers(
        &self,
        token_capacity: u32,
        source_capacity: u32,
        tables: &PrecomputedParseTables,
        tree_capacity: u32,
        retain_debug_hir_buffers: bool,
        parser_feature_flags: u32,
    ) -> bool {
        let fingerprint = table_fingerprint(tables);
        let required = ResidentParserAllocation {
            token_capacity: token_capacity.max(1),
            source_capacity: source_capacity.max(1),
            tree_capacity: tree_capacity.max(1),
            parser_feature_flags,
        };
        self.resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned")
            .as_ref()
            .is_some_and(|cached| {
                cached.table_fingerprint == fingerprint
                    && cached.retain_debug_hir_buffers == retain_debug_hir_buffers
                    && ResidentParserAllocation {
                        token_capacity: cached.token_capacity,
                        source_capacity: cached.buffers.source_capacity,
                        tree_capacity: cached.buffers.tree_capacity,
                        parser_feature_flags: cached.parser_feature_flags,
                    }
                    .covers(required)
            })
    }

    /// Returns the retained tree capacity when every other parser-allocation
    /// dimension already covers the next job. Callers may attempt the parse
    /// directly and grow from the parser's exact overflow status when needed.
    pub(crate) fn reusable_tree_capacity(
        &self,
        token_capacity: u32,
        source_capacity: u32,
        tables: &PrecomputedParseTables,
        retain_debug_hir_buffers: bool,
        parser_feature_flags: u32,
    ) -> Option<u32> {
        let fingerprint = table_fingerprint(tables);
        let required = ResidentParserAllocation {
            token_capacity: token_capacity.max(1),
            source_capacity: source_capacity.max(1),
            tree_capacity: 1,
            parser_feature_flags,
        };
        self.resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned")
            .as_ref()
            .filter(|cached| {
                cached.table_fingerprint == fingerprint
                    && cached.retain_debug_hir_buffers == retain_debug_hir_buffers
                    && ResidentParserAllocation {
                        token_capacity: cached.token_capacity,
                        source_capacity: cached.buffers.source_capacity,
                        tree_capacity: cached.buffers.tree_capacity,
                        parser_feature_flags: cached.parser_feature_flags,
                    }
                    .covers(required)
            })
            .map(|cached| cached.buffers.tree_capacity)
    }
}

#[cfg(test)]
mod tests {
    use super::ResidentParserAllocation;

    #[test]
    fn resident_allocation_grows_without_shrinking_capacity_or_optional_storage() {
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
                source_capacity: 1_000,
                tree_capacity: 700,
                parser_feature_flags: 0b1111,
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

    #[test]
    fn resident_allocation_buckets_small_growth_without_reallocation() {
        let allocation = ResidentParserAllocation {
            token_capacity: 1_300_051,
            source_capacity: 5_100_001,
            tree_capacity: 26_001_020,
            parser_feature_flags: 0b0110,
        }
        .bucketed();
        assert!(allocation.covers(ResidentParserAllocation {
            token_capacity: 1_300_067,
            source_capacity: 5_100_080,
            tree_capacity: 26_001_340,
            parser_feature_flags: 0b0010,
        }));
    }
}
