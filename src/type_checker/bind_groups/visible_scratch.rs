use super::super::*;

pub(super) struct ResidentVisibleScratch {
    pub(super) flag: wgpu::Buffer,
    pub(super) prefix: wgpu::Buffer,
    pub(super) scan_local_prefix: wgpu::Buffer,
    pub(super) scan_block_sum: wgpu::Buffer,
    pub(super) scan_prefix_a: wgpu::Buffer,
    pub(super) scan_prefix_b: wgpu::Buffer,
}

impl ResidentVisibleScratch {
    pub(super) fn new(
        device: &wgpu::Device,
        module_path: Option<&ModulePathState>,
        scan_capacity: u32,
        scan_blocks: u32,
    ) -> Self {
        if let Some(module_path) = module_path {
            // Module/path record scans have finished before resident visible
            // declaration scans run, so the HIR-sized flag/prefix scratch can
            // reuse those buffers instead of allocating another scan family.
            return Self {
                flag: alias_storage_buffer(&module_path.module_record_flag),
                prefix: alias_storage_buffer(&module_path.module_record_prefix),
                scan_local_prefix: alias_storage_buffer(&module_path.record_scan_local_prefix),
                scan_block_sum: alias_storage_buffer(&module_path.record_scan_block_sum),
                scan_prefix_a: alias_storage_buffer(&module_path.record_scan_prefix_a),
                scan_prefix_b: alias_storage_buffer(&module_path.record_scan_prefix_b),
            };
        }

        Self {
            flag: storage_u32_rw(
                device,
                "type_check.resident.hir_visible_decl_flag",
                scan_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            prefix: storage_u32_rw(
                device,
                "type_check.resident.hir_visible_decl_prefix",
                scan_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            scan_local_prefix: storage_u32_rw(
                device,
                "type_check.resident.hir_visible_decl_scan_local_prefix",
                scan_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            scan_block_sum: storage_u32_rw(
                device,
                "type_check.resident.hir_visible_decl_scan_block_sum",
                scan_blocks as usize,
                wgpu::BufferUsages::empty(),
            ),
            scan_prefix_a: storage_u32_rw(
                device,
                "type_check.resident.hir_visible_decl_scan_prefix_a",
                scan_blocks as usize,
                wgpu::BufferUsages::empty(),
            ),
            scan_prefix_b: storage_u32_rw(
                device,
                "type_check.resident.hir_visible_decl_scan_prefix_b",
                scan_blocks as usize,
                wgpu::BufferUsages::empty(),
            ),
        }
    }

    pub(super) fn register_resources<'a>(&'a self, resources: &mut ResourceMap<'a>) {
        resources.buffer("hir_visible_decl_flag", &self.flag);
        resources.buffer("hir_visible_decl_prefix", &self.prefix);
    }

    pub(super) fn scan_rows(&self) -> ScanRows<'_> {
        ScanRows {
            local_prefix: &self.scan_local_prefix,
            block_sum: &self.scan_block_sum,
            prefix_a: &self.scan_prefix_a,
            prefix_b: &self.scan_prefix_b,
        }
    }
}
