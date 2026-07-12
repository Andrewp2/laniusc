use super::ParserBuffers;
use crate::lexer::features::CONSERVATIVE_PARSER_FEATURES;

impl ParserBuffers {
    /// Allocates one-shot parser buffers from already-classified parser token kinds.
    pub fn new(
        device: &wgpu::Device,
        token_kinds_u32: &[u32],
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
    ) -> Self {
        Self::new_with_sizing(
            device,
            token_kinds_u32.len() as u32,
            token_kinds_u32.len() as u32,
            Some(token_kinds_u32),
            n_kinds,
            action_table_bytes,
            tables,
            false,
            true,
            None,
            CONSERVATIVE_PARSER_FEATURES,
        )
    }

    /// Allocates resident parser buffers sized by lexer token capacity.
    pub fn new_resident_capacity(
        device: &wgpu::Device,
        token_capacity: u32,
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
    ) -> Self {
        Self::new_resident_capacity_with_tree_capacity(
            device,
            token_capacity,
            n_kinds,
            action_table_bytes,
            tables,
            None,
        )
    }

    /// Allocates resident parser buffers with an optional tree-capacity override.
    pub fn new_resident_capacity_with_tree_capacity(
        device: &wgpu::Device,
        token_capacity: u32,
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
    ) -> Self {
        Self::new_resident_capacity_with_tree_capacity_and_debug(
            device,
            token_capacity,
            n_kinds,
            action_table_bytes,
            tables,
            tree_capacity_override,
            false,
        )
    }

    /// Allocates resident parser buffers with optional debug HIR retention.
    pub fn new_resident_capacity_with_tree_capacity_and_debug(
        device: &wgpu::Device,
        token_capacity: u32,
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
        retain_debug_hir_buffers: bool,
    ) -> Self {
        Self::new_resident_capacity_with_tree_capacity_debug_and_features(
            device,
            token_capacity,
            n_kinds,
            action_table_bytes,
            tables,
            tree_capacity_override,
            retain_debug_hir_buffers,
            CONSERVATIVE_PARSER_FEATURES,
        )
    }

    /// Allocates resident buffers with optional-family capacities derived from
    /// conservative GPU lexer feature flags.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new_resident_capacity_with_tree_capacity_debug_and_features(
        device: &wgpu::Device,
        token_capacity: u32,
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
        retain_debug_hir_buffers: bool,
        parser_feature_flags: u32,
    ) -> Self {
        let n_tokens = token_capacity.saturating_add(2);
        Self::new_with_sizing(
            device,
            n_tokens,
            token_capacity,
            None,
            n_kinds,
            action_table_bytes,
            tables,
            true,
            retain_debug_hir_buffers,
            tree_capacity_override,
            parser_feature_flags,
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new_resident_capacity_with_source_and_tree_capacity_debug_and_features(
        device: &wgpu::Device,
        token_capacity: u32,
        source_capacity: u32,
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
        retain_debug_hir_buffers: bool,
        parser_feature_flags: u32,
    ) -> Self {
        let n_tokens = token_capacity.saturating_add(2);
        Self::new_with_sizing(
            device,
            n_tokens,
            source_capacity,
            None,
            n_kinds,
            action_table_bytes,
            tables,
            true,
            retain_debug_hir_buffers,
            tree_capacity_override,
            parser_feature_flags,
        )
    }
}
