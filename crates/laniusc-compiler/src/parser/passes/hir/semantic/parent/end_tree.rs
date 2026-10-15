//! Search heaps over dense semantic subtree ends
//! (`parser/hir/semantic/parent/end_tree.slang`): the semantic-parent search
//! reads them to find each row's nearest enclosing semantic row.

use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Rows per heap block and blocks per heap group.
const FANOUT: u32 = 256;

/// Leaves of the heap over the semantic-end blocks: a power of two covering
/// every block and at least one full group of blocks.
pub fn leaf_base(tree_node_blocks: u32) -> u32 {
    tree_node_blocks.max(FANOUT).next_power_of_two()
}

/// Entries of the top heap over the block groups.
pub fn group_count(tree_node_blocks: u32) -> u32 {
    leaf_base(tree_node_blocks) / FANOUT
}

fn tree_count_status(b: &ParserBuffers) -> wgpu::BindingResource<'_> {
    if b.tree_count_uses_status {
        b.partial_parse_status.as_entire_binding()
    } else {
        b.ll1_status.as_entire_binding()
    }
}

/// Builds one local maximum heap per block of 256 dense subtree ends.
pub struct HirSemanticEndRowsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticEndRowsPass,
    label: "hir_semantic_end_rows",
    shader: "parser/hir/semantic/parent/end_rows"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticEndRowsPass {
    const NAME: &'static str = "hir_semantic_end_rows";
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
            ("gHirSemantic".into(), b.hir_params.as_entire_binding()),
            ("tree_count_status".into(), tree_count_status(b)),
            (
                "hir_semantic_count".into(),
                b.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_semantic_subtree_end".into(),
                b.hir_semantic_subtree_end.as_entire_binding(),
            ),
            (
                "hir_semantic_end_local_max".into(),
                b.hir_semantic_end_local_max.as_entire_binding(),
            ),
        ])
    }
}

/// Builds one local maximum heap per group of 256 block maxima.
pub struct HirSemanticEndBlocksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticEndBlocksPass,
    label: "hir_semantic_end_blocks",
    shader: "parser/hir/semantic/parent/end_blocks"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticEndBlocksPass {
    const NAME: &'static str = "hir_semantic_end_blocks";
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
            ("gHirSemantic".into(), b.hir_params.as_entire_binding()),
            ("tree_count_status".into(), tree_count_status(b)),
            (
                "hir_semantic_count".into(),
                b.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_semantic_end_local_max".into(),
                b.hir_semantic_end_local_max.as_entire_binding(),
            ),
            (
                "hir_semantic_end_blocks".into(),
                b.hir_semantic_end_blocks.as_entire_binding(),
            ),
        ])
    }
}

/// Builds the heap over the block-group maxima in one workgroup.
pub struct HirSemanticEndTopPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticEndTopPass,
    label: "hir_semantic_end_top",
    shader: "parser/hir/semantic/parent/end_top"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticEndTopPass {
    const NAME: &'static str = "hir_semantic_end_top";
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
            ("gHirSemantic".into(), b.hir_params.as_entire_binding()),
            ("tree_count_status".into(), tree_count_status(b)),
            (
                "hir_semantic_count".into(),
                b.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_semantic_end_blocks".into(),
                b.hir_semantic_end_blocks.as_entire_binding(),
            ),
            (
                "hir_semantic_end_top".into(),
                b.hir_semantic_end_top.as_entire_binding(),
            ),
        ])
    }
}
