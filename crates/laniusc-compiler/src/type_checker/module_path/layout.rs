use super::super::*;

/// Capacity and workgroup layout for module/path resident storage.
///
/// These derived sizes keep the allocation policy in one place while the
/// constructors only decide which relations to bind.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct Layout {
    pub(in crate::type_checker) n_blocks: u32,
    pub(in crate::type_checker) record_capacity: usize,
    pub(in crate::type_checker) record_capacity_u32: u32,
    pub(in crate::type_checker) record_n_blocks: u32,
    pub(in crate::type_checker) module_capacity: usize,
    pub(in crate::type_checker) module_capacity_u32: u32,
    pub(in crate::type_checker) module_n_blocks: u32,
    pub(in crate::type_checker) import_record_capacity: usize,
    pub(in crate::type_checker) import_record_capacity_u32: u32,
    pub(in crate::type_checker) import_visible_capacity: usize,
    pub(in crate::type_checker) import_visible_capacity_u32: u32,
    pub(in crate::type_checker) import_visible_n_blocks: u32,
    pub(in crate::type_checker) key_radix_histogram_len: usize,
}

impl Layout {
    /// Derives module/path allocation and dispatch sizes from input capacities.
    pub(in crate::type_checker) fn new(
        source_file_capacity: u32,
        token_capacity: u32,
        hir_node_capacity: u32,
    ) -> Self {
        let n_blocks = hir_node_capacity.div_ceil(256).max(1);
        let record_capacity = token_capacity.max(1) as usize;
        let record_capacity_u32 = token_capacity.max(1);
        let record_n_blocks = record_capacity_u32.div_ceil(256).max(1);
        let source_file_capacity = source_file_capacity.max(1);
        let module_capacity = source_file_capacity as usize;
        let module_capacity_u32 = source_file_capacity;
        let module_n_blocks = module_capacity_u32.div_ceil(256).max(1);
        let import_record_capacity = record_capacity;
        let import_record_capacity_u32 = import_record_capacity as u32;
        let import_visible_capacity = if source_file_capacity <= 1 {
            1usize
        } else {
            record_capacity
        };
        let import_visible_capacity_u32 = import_visible_capacity as u32;
        let import_visible_n_blocks = import_visible_capacity_u32.div_ceil(256).max(1);
        let key_radix_histogram_len = module_n_blocks
            .max(record_n_blocks)
            .max(import_visible_n_blocks)
            .max(1) as usize
            * NAME_RADIX_BUCKETS as usize;

        Self {
            n_blocks,
            record_capacity,
            record_capacity_u32,
            record_n_blocks,
            module_capacity,
            module_capacity_u32,
            module_n_blocks,
            import_record_capacity,
            import_record_capacity_u32,
            import_visible_capacity,
            import_visible_capacity_u32,
            import_visible_n_blocks,
            key_radix_histogram_len,
        }
    }
}
