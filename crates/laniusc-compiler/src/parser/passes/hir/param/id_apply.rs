use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that writes final dense parameter IDs after list ranks have been assigned.
pub struct HirParamIdApplyPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirParamIdApplyPass,
    label: "hir_param_id_apply",
    shader: "parser/hir/param/id_apply"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirParamIdApplyPass {
    const NAME: &'static str = "hir_param_id_apply";
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
                "gHirParam".into(),
                b.hir_param_fields_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_param_owner_a".into(),
                b.hir_param_owner_a.as_entire_binding(),
            ),
            (
                "hir_param_rank_b".into(),
                b.hir_param_rank_b.as_entire_binding(),
            ),
            (
                "hir_list_rank_node".into(),
                b.hir_list_rank_node.as_entire_binding(),
            ),
            (
                "hir_list_rank_count".into(),
                b.hir_list_rank_count.as_entire_binding(),
            ),
            (
                "hir_param_rank_a".into(),
                b.hir_param_rank_a.as_entire_binding(),
            ),
        ])
    }
}

#[cfg(test)]
mod tests {
    const INVALID: u32 = u32::MAX;

    fn segmented_param_ordinals(owner_by_node: &[u32], param_nodes: &[u32]) -> Vec<u32> {
        let mut base_by_owner = vec![INVALID; owner_by_node.len()];
        for (row, &node) in param_nodes.iter().enumerate() {
            let Some(&owner) = owner_by_node.get(node as usize) else {
                continue;
            };
            let Some(base) = base_by_owner.get_mut(owner as usize) else {
                continue;
            };
            *base = (*base).min(row as u32);
        }

        let mut ordinal_by_node = vec![INVALID; owner_by_node.len()];
        for (row, &node) in param_nodes.iter().enumerate() {
            let Some(&owner) = owner_by_node.get(node as usize) else {
                continue;
            };
            let Some(&base) = base_by_owner.get(owner as usize) else {
                continue;
            };
            if base != INVALID && row as u32 >= base {
                ordinal_by_node[node as usize] = row as u32 - base;
            }
        }

        ordinal_by_node
    }

    #[test]
    fn segmented_parameter_ordinals_cover_65k_rows() {
        let wide_count = 65_535usize;
        let narrow_count = 3usize;
        let wide_owner = 0u32;
        let narrow_owner = wide_count as u32;
        let total_nodes = wide_count + narrow_count + 1;

        let mut owner_by_node = vec![INVALID; total_nodes];
        for owner in owner_by_node.iter_mut().take(wide_count) {
            *owner = wide_owner;
        }
        for owner in owner_by_node.iter_mut().skip(wide_count).take(narrow_count) {
            *owner = narrow_owner;
        }

        let param_nodes = (0..(wide_count + narrow_count))
            .map(|node| node as u32)
            .collect::<Vec<_>>();
        let ordinals = segmented_param_ordinals(&owner_by_node, &param_nodes);

        for node in [0usize, 1, 255, 256, 257, wide_count - 2, wide_count - 1] {
            assert_eq!(
                ordinals[node], node as u32,
                "wide parameter node {node} should keep its source-order ordinal"
            );
        }
        for offset in 0..narrow_count {
            let node = wide_count + offset;
            assert_eq!(
                ordinals[node], offset as u32,
                "new owner segment should restart ordinal assignment"
            );
        }
    }
}
