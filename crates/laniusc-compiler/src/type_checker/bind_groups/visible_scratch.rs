use super::super::*;

/// Scratch buffers for resident visible-declaration scans.
pub(super) struct ResidentVisibleScratch {
    pub(super) flag: LaniusBuffer<u32>,
    pub(super) prefix: LaniusBuffer<u32>,
    pub(super) scan_local_prefix: LaniusBuffer<u32>,
    pub(super) scan_block_sum: LaniusBuffer<u32>,
    pub(super) scan_prefix_a: LaniusBuffer<u32>,
    pub(super) scan_prefix_b: LaniusBuffer<u32>,
}

impl ResidentVisibleScratch {
    /// Creates visible-declaration scratch, reusing dead module-path scan storage when possible.
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
                flag: module_path.module_record_flag.alias(scan_capacity as usize),
                prefix: module_path
                    .module_record_prefix
                    .alias(scan_capacity as usize),
                scan_local_prefix: module_path
                    .record_scan_local_prefix
                    .alias(scan_capacity as usize),
                scan_block_sum: module_path
                    .record_scan_block_sum
                    .alias(scan_blocks as usize),
                scan_prefix_a: module_path.record_scan_prefix_a.alias(scan_blocks as usize),
                scan_prefix_b: module_path.record_scan_prefix_b.alias(scan_blocks as usize),
            };
        }

        Self {
            flag: typed_storage_u32_rw(
                device,
                "type_check.resident.hir_visible_decl_flag",
                scan_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            prefix: typed_storage_u32_rw(
                device,
                "type_check.resident.hir_visible_decl_prefix",
                scan_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            scan_local_prefix: typed_storage_u32_rw(
                device,
                "type_check.resident.hir_visible_decl_scan_local_prefix",
                scan_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            scan_block_sum: typed_storage_u32_rw(
                device,
                "type_check.resident.hir_visible_decl_scan_block_sum",
                scan_blocks as usize,
                wgpu::BufferUsages::empty(),
            ),
            scan_prefix_a: typed_storage_u32_rw(
                device,
                "type_check.resident.hir_visible_decl_scan_prefix_a",
                scan_blocks as usize,
                wgpu::BufferUsages::empty(),
            ),
            scan_prefix_b: typed_storage_u32_rw(
                device,
                "type_check.resident.hir_visible_decl_scan_prefix_b",
                scan_blocks as usize,
                wgpu::BufferUsages::empty(),
            ),
        }
    }

    /// Registers visible-declaration flag and prefix buffers for reflected bind groups.
    pub(super) fn register_resources<'a>(&'a self, resources: &mut ResourceMap<'a>) {
        resources.buffer("hir_visible_decl_flag", &self.flag);
        resources.buffer("hir_visible_decl_prefix", &self.prefix);
        resources.buffer(
            "hir_visible_decl_scan_local_prefix",
            &self.scan_local_prefix,
        );
        resources.buffer("hir_visible_decl_scan_block_sum", &self.scan_block_sum);
        resources.buffer("hir_visible_decl_scan_prefix_a", &self.scan_prefix_a);
        resources.buffer("hir_visible_decl_scan_prefix_b", &self.scan_prefix_b);
    }

    /// Returns the scan scratch rows used by visible-declaration bind groups.
    pub(super) fn scan_rows(&self) -> ScanRows<'_> {
        ScanRows {
            local_prefix: &self.scan_local_prefix,
            block_sum: &self.scan_block_sum,
            prefix_a: &self.scan_prefix_a,
            prefix_b: &self.scan_prefix_b,
        }
    }
}
