//! Search heaps over canonical subtree ends
//! (`parser/hir/canonical/parent/end_rows.slang`): the canonical core reads
//! them to find each canonical row's nearest canonical ancestor. They use the
//! semantic-end heap layout, sized for the canonical capacity.

use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Rows per heap block.
const FANOUT: u32 = 256;

/// Blocks of 256 rows in a canonical table of `canonical_capacity` rows.
pub fn block_count(canonical_capacity: u32) -> u32 {
    canonical_capacity.div_ceil(FANOUT).max(1)
}

/// Leaves of the heap over the canonical-end blocks.
pub fn leaf_base(canonical_capacity: u32) -> u32 {
    crate::parser::passes::hir::semantic::parent::end_tree::leaf_base(block_count(
        canonical_capacity,
    ))
}

/// Entries of the top heap over the block groups.
pub fn group_count(canonical_capacity: u32) -> u32 {
    crate::parser::passes::hir::semantic::parent::end_tree::group_count(block_count(
        canonical_capacity,
    ))
}

/// Builds one local maximum heap per block of 256 canonical subtree ends.
pub struct HirCanonicalEndRowsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalEndRowsPass,
    label: "hir_canonical_end_rows",
    shader: "parser/hir/canonical/parent/end_rows"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalEndRowsPass {
    const NAME: &'static str = "hir_canonical_end_rows";
    const DIM: DispatchDim = DispatchDim::D1;

    fn from_data(data: PassData) -> Self {
        Self { data }
    }

    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        b: &'a ParserBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            (
                "gCanonical".into(),
                b.hir_canonical_params.as_entire_binding(),
            ),
            (
                "canonical_count".into(),
                b.hir_canonical_count.as_entire_binding(),
            ),
            (
                "canonical_prefix_before_raw".into(),
                b.hir_canonical_prefix_before_raw.as_entire_binding(),
            ),
            (
                "canonical_dense_to_raw".into(),
                b.hir_canonical_dense_to_raw.as_entire_binding(),
            ),
            ("subtree_end".into(), b.subtree_end.as_entire_binding()),
            (
                "hir_canonical_end_local_max".into(),
                b.hir_canonical_end_local_max.as_entire_binding(),
            ),
        ])
    }
}

/// Builds one local maximum heap per group of 256 canonical block maxima.
pub struct HirCanonicalEndBlocksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalEndBlocksPass,
    label: "hir_canonical_end_blocks",
    shader: "parser/hir/canonical/parent/end_blocks"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalEndBlocksPass {
    const NAME: &'static str = "hir_canonical_end_blocks";
    const DIM: DispatchDim = DispatchDim::D1;

    fn from_data(data: PassData) -> Self {
        Self { data }
    }

    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        b: &'a ParserBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            (
                "gCanonical".into(),
                b.hir_canonical_params.as_entire_binding(),
            ),
            (
                "canonical_count".into(),
                b.hir_canonical_count.as_entire_binding(),
            ),
            (
                "hir_canonical_end_local_max".into(),
                b.hir_canonical_end_local_max.as_entire_binding(),
            ),
            (
                "hir_canonical_end_blocks".into(),
                b.hir_canonical_end_blocks.as_entire_binding(),
            ),
        ])
    }
}

/// Builds the heap over the canonical block-group maxima in one workgroup.
pub struct HirCanonicalEndTopPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalEndTopPass,
    label: "hir_canonical_end_top",
    shader: "parser/hir/canonical/parent/end_top"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalEndTopPass {
    const NAME: &'static str = "hir_canonical_end_top";
    const DIM: DispatchDim = DispatchDim::D1;

    fn from_data(data: PassData) -> Self {
        Self { data }
    }

    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        b: &'a ParserBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            (
                "gCanonical".into(),
                b.hir_canonical_params.as_entire_binding(),
            ),
            (
                "canonical_count".into(),
                b.hir_canonical_count.as_entire_binding(),
            ),
            (
                "hir_canonical_end_blocks".into(),
                b.hir_canonical_end_blocks.as_entire_binding(),
            ),
            (
                "hir_canonical_end_top".into(),
                b.hir_canonical_end_top.as_entire_binding(),
            ),
        ])
    }
}
