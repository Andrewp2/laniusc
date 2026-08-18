use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::{
        buffers::LaniusBuffer,
        passes_core::{BindGroupCache, PassData, make_pass_data_from_shader_key},
    },
    parser::{buffers::ParserBuffers, passes::hir::bounded_walk_step_capacity},
};

/// Reusable pointer-jump operation for compact linked-list owner/rank rows.
pub struct HirListRankStepOperation {
    data: PassData,
}

impl HirListRankStepOperation {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            data: make_pass_data_from_shader_key(
                device,
                "hir_list_rank_step",
                "main",
                "parser/hir/list/rank/step",
            )?,
        })
    }

    pub fn record<P>(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        params: &LaniusBuffer<P>,
        relation: ListRankBuffers<'_>,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        cache: &mut BindGroupCache,
        invocation: super::ListRankInvocation,
    ) -> Result<()> {
        let steps = list_rank_step_capacity(buffers.tree_capacity);
        let labels = invocation.step_labels();
        for step in 0..steps {
            let label = if step % 2 == 0 { labels.0 } else { labels.1 };
            let (owner_in, link_in, rank_in, owner_out, link_out, rank_out) =
                relation.for_step(step);
            let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                ("gHirListRank".into(), params.as_entire_binding()),
                (
                    "tree_count_status".into(),
                    if buffers.tree_count_uses_status {
                        buffers.partial_parse_status.as_entire_binding()
                    } else {
                        buffers.ll1_status.as_entire_binding()
                    },
                ),
                (
                    "hir_list_rank_node".into(),
                    buffers.hir_list_rank_node.as_entire_binding(),
                ),
                (
                    "hir_list_rank_count".into(),
                    buffers.hir_list_rank_count.as_entire_binding(),
                ),
                ("list_owner_in".into(), owner_in.as_entire_binding()),
                ("list_link_in".into(), link_in.as_entire_binding()),
                ("list_rank_in".into(), rank_in.as_entire_binding()),
                ("list_owner_out".into(), owner_out.as_entire_binding()),
                ("list_link_out".into(), link_out.as_entire_binding()),
                ("list_rank_out".into(), rank_out.as_entire_binding()),
            ]);
            let cache_identity = format!("{label}.{step}");
            let bind_group = cache
                .reflected_for_graph_invocation(
                    device,
                    &cache_identity,
                    label,
                    &self.data,
                    buffers,
                    &resources,
                    Some(dispatch_args),
                )?
                .into_iter()
                .next()
                .expect("list-rank step pass must have one reflected bind group");
            crate::gpu::passes_core::record_or_defer_compute_indirect(
                encoder,
                &self.data,
                bind_group.as_ref(),
                label,
                dispatch_args,
            );
        }

        Ok(())
    }
}

pub(in crate::parser) fn list_rank_step_capacity(items: u32) -> u32 {
    let steps = bounded_walk_step_capacity(items);
    // Finish in the A buffers without copying three tree-capacity arrays.
    steps + steps % 2
}

impl HirListRankStepOperation {
    pub(in crate::parser) fn graph_pass(&self) -> &PassData {
        &self.data
    }
}

#[derive(Clone, Copy)]
pub struct ListRankBuffers<'a> {
    owner_a: &'a LaniusBuffer<u32>,
    link_a: &'a LaniusBuffer<u32>,
    rank_a: &'a LaniusBuffer<u32>,
    owner_b: &'a LaniusBuffer<u32>,
    link_b: &'a LaniusBuffer<u32>,
    rank_b: &'a LaniusBuffer<u32>,
}

impl<'a> ListRankBuffers<'a> {
    pub fn new(
        owner_a: &'a LaniusBuffer<u32>,
        link_a: &'a LaniusBuffer<u32>,
        rank_a: &'a LaniusBuffer<u32>,
        owner_b: &'a LaniusBuffer<u32>,
        link_b: &'a LaniusBuffer<u32>,
        rank_b: &'a LaniusBuffer<u32>,
    ) -> Self {
        Self {
            owner_a,
            link_a,
            rank_a,
            owner_b,
            link_b,
            rank_b,
        }
    }

    fn for_step(
        self,
        step: u32,
    ) -> (
        &'a LaniusBuffer<u32>,
        &'a LaniusBuffer<u32>,
        &'a LaniusBuffer<u32>,
        &'a LaniusBuffer<u32>,
        &'a LaniusBuffer<u32>,
        &'a LaniusBuffer<u32>,
    ) {
        if step % 2 == 0 {
            (
                self.owner_a,
                self.link_a,
                self.rank_a,
                self.owner_b,
                self.link_b,
                self.rank_b,
            )
        } else {
            (
                self.owner_b,
                self.link_b,
                self.rank_b,
                self.owner_a,
                self.link_a,
                self.rank_a,
            )
        }
    }
}

impl ParserBuffers {
    pub fn type_argument_rank_buffers(&self) -> ListRankBuffers<'_> {
        ListRankBuffers::new(
            &self.hir_type_arg_owner_a,
            &self.hir_type_arg_link_a,
            &self.hir_type_arg_rank_a,
            &self.hir_type_arg_owner_b,
            &self.hir_type_arg_link_b,
            &self.hir_type_arg_rank_b,
        )
    }

    pub fn call_argument_rank_buffers(&self) -> ListRankBuffers<'_> {
        ListRankBuffers::new(
            &self.hir_call_arg_owner_a,
            &self.hir_call_arg_link_a,
            &self.hir_call_arg_rank_a,
            &self.hir_call_arg_owner_b,
            &self.hir_call_arg_link_b,
            &self.hir_call_arg_rank_b,
        )
    }

    pub fn array_element_rank_buffers(&self) -> ListRankBuffers<'_> {
        ListRankBuffers::new(
            &self.hir_array_element_owner_a,
            &self.hir_array_element_link_a,
            &self.hir_array_element_rank_a,
            &self.hir_array_element_owner_b,
            &self.hir_array_element_link_b,
            &self.hir_array_element_rank_b,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::list_rank_step_capacity;
    use crate::parser::passes::hir::BOUNDED_WALK_LINKS_PER_STEP;

    #[test]
    fn bounded_walk_schedule_covers_capacity_and_finishes_in_a_buffers() {
        for items in [1, 2, 16, 17, 256, 257, 65_536, 1_687_524, u32::MAX] {
            let steps = list_rank_step_capacity(items);
            assert_eq!(steps % 2, 0);
            let reach = (0..steps).fold(1u64, |reach, _| {
                reach.saturating_mul(u64::from(BOUNDED_WALK_LINKS_PER_STEP))
            });
            assert!(reach >= u64::from(items));
        }
    }

    #[test]
    fn bounded_walk_replaces_binary_capacity_rounds() {
        assert_eq!(list_rank_step_capacity(1), 0);
        assert_eq!(list_rank_step_capacity(16), 2);
        assert_eq!(list_rank_step_capacity(256), 2);
        assert_eq!(list_rank_step_capacity(257), 4);
        assert_eq!(list_rank_step_capacity(1_687_524), 6);
    }
}
