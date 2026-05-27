use super::ParserBuffers;

impl ParserBuffers {
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
            Some(token_kinds_u32),
            n_kinds,
            action_table_bytes,
            tables,
            false,
            false,
            true,
            None,
        )
    }

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

    pub fn new_resident_capacity_with_tree_capacity_and_debug(
        device: &wgpu::Device,
        token_capacity: u32,
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
        retain_debug_hir_buffers: bool,
    ) -> Self {
        let n_tokens = token_capacity.saturating_add(2);
        Self::new_with_sizing(
            device,
            n_tokens,
            None,
            n_kinds,
            action_table_bytes,
            tables,
            true,
            false,
            retain_debug_hir_buffers,
            tree_capacity_override,
        )
    }
}
