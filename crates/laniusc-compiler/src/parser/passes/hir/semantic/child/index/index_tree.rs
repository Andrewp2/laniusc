//! Range (minimum, count) heaps over dense semantic parents
//! (`parser/hir/semantic/child/index/index_tree.slang`): the child-index
//! query reads them to count each row's earlier siblings. They use the
//! semantic-end heap layout, so `parent::end_tree::{leaf_base, group_count}`
//! size them too.

use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

fn tree_count_status(b: &ParserBuffers) -> wgpu::BindingResource<'_> {
    if b.tree_count_uses_status {
        b.partial_parse_status.as_entire_binding()
    } else {
        b.ll1_status.as_entire_binding()
    }
}

/// Builds one local (minimum, count) heap per block of 256 semantic parents.
pub struct HirSemanticChildIndexRowsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticChildIndexRowsPass,
    label: "hir_semantic_child_index_rows",
    shader: "parser/hir/semantic/child/index/index_rows"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticChildIndexRowsPass {
    const NAME: &'static str = "hir_semantic_child_index_rows";
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
                "hir_semantic_parent".into(),
                b.hir_semantic_parent.as_entire_binding(),
            ),
            (
                "hir_semantic_child_local".into(),
                b.hir_semantic_child_local.as_entire_binding(),
            ),
        ])
    }
}

/// Builds one local (minimum, count) heap per group of 256 block aggregates.
pub struct HirSemanticChildIndexBlocksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticChildIndexBlocksPass,
    label: "hir_semantic_child_index_blocks",
    shader: "parser/hir/semantic/child/index/index_blocks"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticChildIndexBlocksPass {
    const NAME: &'static str = "hir_semantic_child_index_blocks";
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
                "hir_semantic_child_local".into(),
                b.hir_semantic_child_local.as_entire_binding(),
            ),
            (
                "hir_semantic_child_blocks".into(),
                b.hir_semantic_child_blocks.as_entire_binding(),
            ),
        ])
    }
}

/// Builds the heap over the block-group aggregates in one workgroup.
pub struct HirSemanticChildIndexTopPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticChildIndexTopPass,
    label: "hir_semantic_child_index_top",
    shader: "parser/hir/semantic/child/index/index_top"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticChildIndexTopPass {
    const NAME: &'static str = "hir_semantic_child_index_top";
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
                "hir_semantic_child_blocks".into(),
                b.hir_semantic_child_blocks.as_entire_binding(),
            ),
            (
                "hir_semantic_child_top".into(),
                b.hir_semantic_child_top.as_entire_binding(),
            ),
        ])
    }
}
