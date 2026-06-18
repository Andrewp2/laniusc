use super::super::support::{PooledStorageBuffer, pooled_storage_u32_rw};

/// Indirect-dispatch argument buffers shared by active x86 recording stages.
pub(super) struct ActiveDispatchArgBuffers {
    pub(super) hir_count: PooledStorageBuffer,
    pub(super) hir_plus_one: PooledStorageBuffer,
    pub(super) hir_scan_block: PooledStorageBuffer,
    pub(super) node_order_scan: PooledStorageBuffer,
    pub(super) node_order_scan_block: PooledStorageBuffer,
    pub(super) function_dispatch: PooledStorageBuffer,
    pub(super) virtual_inst: PooledStorageBuffer,
    pub(super) virtual_next_call: PooledStorageBuffer,
    pub(super) virtual_regalloc: PooledStorageBuffer,
    pub(super) selected_inst: PooledStorageBuffer,
    pub(super) selected_scan_block: PooledStorageBuffer,
    pub(super) text_word: PooledStorageBuffer,
    pub(super) elf_header_word: PooledStorageBuffer,
}

impl ActiveDispatchArgBuffers {
    /// Allocates dispatch argument buffers for HIR, instruction, virtual, and output worklists.
    pub(super) fn create(
        device: &wgpu::Device,
        virtual_next_call_step_count: usize,
        virtual_regalloc_chunk_count: usize,
    ) -> Self {
        Self {
            hir_count: pooled_storage_u32_rw(
                device,
                "codegen.x86.active_hir_count_dispatch_args",
                4,
                wgpu::BufferUsages::INDIRECT | wgpu::BufferUsages::COPY_SRC,
            ),
            hir_plus_one: pooled_storage_u32_rw(
                device,
                "codegen.x86.active_hir_plus_one_dispatch_args",
                4,
                wgpu::BufferUsages::INDIRECT | wgpu::BufferUsages::COPY_SRC,
            ),
            hir_scan_block: pooled_storage_u32_rw(
                device,
                "codegen.x86.active_hir_scan_block_dispatch_args",
                4,
                wgpu::BufferUsages::INDIRECT,
            ),
            node_order_scan: pooled_storage_u32_rw(
                device,
                "codegen.x86.active_node_order_scan_dispatch_args",
                3,
                wgpu::BufferUsages::INDIRECT,
            ),
            node_order_scan_block: pooled_storage_u32_rw(
                device,
                "codegen.x86.active_node_order_scan_block_dispatch_args",
                3,
                wgpu::BufferUsages::INDIRECT,
            ),
            function_dispatch: pooled_storage_u32_rw(
                device,
                "codegen.x86.active_function_dispatch_args",
                3,
                wgpu::BufferUsages::INDIRECT,
            ),
            virtual_inst: pooled_storage_u32_rw(
                device,
                "codegen.x86.active_virtual_inst_dispatch_args",
                3,
                wgpu::BufferUsages::INDIRECT,
            ),
            virtual_next_call: pooled_storage_u32_rw(
                device,
                "codegen.x86.active_virtual_next_call_dispatch_args",
                virtual_next_call_step_count.max(1) * 3,
                wgpu::BufferUsages::INDIRECT,
            ),
            virtual_regalloc: pooled_storage_u32_rw(
                device,
                "codegen.x86.active_virtual_regalloc_dispatch_args",
                virtual_regalloc_chunk_count * 3,
                wgpu::BufferUsages::INDIRECT,
            ),
            selected_inst: pooled_storage_u32_rw(
                device,
                "codegen.x86.active_selected_inst_dispatch_args",
                3,
                wgpu::BufferUsages::INDIRECT,
            ),
            selected_scan_block: pooled_storage_u32_rw(
                device,
                "codegen.x86.active_selected_scan_block_dispatch_args",
                3,
                wgpu::BufferUsages::INDIRECT,
            ),
            text_word: pooled_storage_u32_rw(
                device,
                "codegen.x86.active_text_word_dispatch_args",
                3,
                wgpu::BufferUsages::INDIRECT,
            ),
            elf_header_word: pooled_storage_u32_rw(
                device,
                "codegen.x86.active_elf_header_word_dispatch_args",
                3,
                wgpu::BufferUsages::INDIRECT,
            ),
        }
    }
}
