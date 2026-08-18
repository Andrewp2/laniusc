use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData, make_pass_data_from_shader_key},
    parser::{
        buffers::ParserBuffers,
        passes::hir::{bounded_walk_step_capacity, nodes::SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN},
    },
};

/// Reusable pointer-jump operation over one tree link and one or more payloads.
pub struct TreeRelationOperation {
    data: PassData,
    pair_data: PassData,
    triple_data: PassData,
}

#[derive(Clone, Copy)]
pub(in crate::parser) struct TreeRelationInvocation {
    pub a_to_b: &'static str,
    pub b_to_a: &'static str,
    pub a_to_b_final: &'static str,
    pub finalize: &'static str,
}

pub(in crate::parser) const FN_SIGNATURE_OWNER: TreeRelationInvocation = TreeRelationInvocation {
    a_to_b: "hir_fn_signature_owner_step.a_to_b",
    b_to_a: "hir_fn_signature_owner_step.b_to_a",
    a_to_b_final: "hir_fn_signature_owner_step.a_to_b_final",
    finalize: "hir_fn_signature_owner_step.finalize",
};
pub(in crate::parser) const MATCH_ARM_OWNER: TreeRelationInvocation = TreeRelationInvocation {
    a_to_b: "hir_match_arm_owner_step.a_to_b",
    b_to_a: "hir_match_arm_owner_step.b_to_a",
    a_to_b_final: "hir_match_arm_owner_step.a_to_b_final",
    finalize: "hir_match_arm_owner_step.finalize",
};
pub(in crate::parser) const CANONICAL_VARIANT_PAYLOAD_OWNER: TreeRelationInvocation =
    TreeRelationInvocation {
        a_to_b: "hir_canonical_variant_payload_owner_step.a_to_b",
        b_to_a: "hir_canonical_variant_payload_owner_step.b_to_a",
        a_to_b_final: "hir_canonical_variant_payload_owner_step.a_to_b_final",
        finalize: "hir_canonical_variant_payload_owner_step.finalize",
    };
pub(in crate::parser) const CANONICAL_RELATIONS: TreeRelationInvocation = TreeRelationInvocation {
    a_to_b: "hir_canonical_relations_step.a_to_b",
    b_to_a: "hir_canonical_relations_step.b_to_a",
    a_to_b_final: "hir_canonical_relations_step.a_to_b_final",
    finalize: "hir_canonical_relations_step.finalize",
};

impl TreeRelationOperation {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            data: make_pass_data_from_shader_key(
                device,
                "hir_semantic_parent_step",
                "main",
                "parser/hir/semantic/parent/step",
            )?,
            pair_data: make_pass_data_from_shader_key(
                device,
                "hir_semantic_parent_pair_step",
                "main",
                "parser/hir/semantic/parent/pair_step",
            )?,
            triple_data: make_pass_data_from_shader_key(
                device,
                "hir_semantic_parent_triple_step",
                "main",
                "parser/hir/semantic/parent/triple_step",
            )?,
        })
    }

    /// Propagates one nearest-ancestor relation through caller-selected
    /// phase-local link/value slots.
    pub(in crate::parser) fn record_steps_for_buffers(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        link_a: &crate::gpu::buffers::LaniusBuffer<u32>,
        value_a: &crate::gpu::buffers::LaniusBuffer<u32>,
        link_b: &crate::gpu::buffers::LaniusBuffer<u32>,
        value_b: &crate::gpu::buffers::LaniusBuffer<u32>,
        invocation: TreeRelationInvocation,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        self.record_steps_for_buffers_after_local_span(
            device,
            encoder,
            buffers,
            link_a,
            value_a,
            link_b,
            value_b,
            SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN,
            invocation,
            cache,
        )
    }

    /// Propagates a canonical-family relation through the shared tree slots.
    pub(in crate::parser) fn record_canonical_steps(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        invocation: TreeRelationInvocation,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        self.record_steps_for_buffers_after_local_span(
            device,
            encoder,
            buffers,
            &buffers.hir_semantic_parent_link_a,
            &buffers.hir_semantic_parent_value_a,
            &buffers.hir_semantic_parent_link_b,
            &buffers.hir_semantic_parent_value_b,
            crate::parser::passes::hir::canonical::RELATION_LOCAL_ANCESTOR_SPAN,
            invocation,
            cache,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn record_steps_for_buffers_after_local_span(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        link_a: &crate::gpu::buffers::LaniusBuffer<u32>,
        value_a: &crate::gpu::buffers::LaniusBuffer<u32>,
        link_b: &crate::gpu::buffers::LaniusBuffer<u32>,
        value_b: &crate::gpu::buffers::LaniusBuffer<u32>,
        local_span: u32,
        invocation: TreeRelationInvocation,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        self.record_schedule(
            device,
            encoder,
            buffers,
            &self.data,
            SINGLE_NAMES,
            TreeRelationBuffers::new(link_a, link_b, [value_a], [value_b]),
            bounded_walk_steps_after_local_span(buffers.tree_capacity, local_span),
            &buffers.tree_active_dispatch_args,
            invocation,
            cache,
        )
    }

    /// Propagates three canonical ancestor payloads over one shared link.
    pub(in crate::parser) fn record_canonical_steps_for_three_values(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        relation: TreeRelationBuffers<'_, 3>,
        invocation: TreeRelationInvocation,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        self.record_schedule(
            device,
            encoder,
            buffers,
            &self.triple_data,
            TRIPLE_NAMES,
            relation,
            bounded_walk_steps_after_local_span(
                buffers.tree_capacity,
                crate::parser::passes::hir::canonical::RELATION_LOCAL_ANCESTOR_SPAN,
            ),
            &buffers.tree_active_dispatch_args,
            invocation,
            cache,
        )
    }

    /// Propagates two payload columns over links seeded directly by the caller.
    pub(in crate::parser) fn record_two_values(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        relation: TreeRelationBuffers<'_, 2>,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        invocation: TreeRelationInvocation,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        self.record_schedule(
            device,
            encoder,
            buffers,
            &self.pair_data,
            PAIR_NAMES,
            relation,
            bounded_walk_step_capacity(buffers.tree_capacity),
            dispatch_args,
            invocation,
            cache,
        )
    }

    fn record_schedule<const N: usize>(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        data: &PassData,
        names: RelationNames<N>,
        relation: TreeRelationBuffers<'_, N>,
        steps: u32,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        invocation: TreeRelationInvocation,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        for step in 0..steps {
            let mut resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                (
                    "gHirSemantic".into(),
                    buffers.hir_params.as_entire_binding(),
                ),
                (
                    "tree_count_status".into(),
                    if buffers.tree_count_uses_status {
                        buffers.partial_parse_status.as_entire_binding()
                    } else {
                        buffers.ll1_status.as_entire_binding()
                    },
                ),
            ]);
            let (link_in, values_in, link_out, values_out) = relation.for_step(step);
            resources.insert(names.link_in.into(), link_in.as_entire_binding());
            resources.insert(names.link_out.into(), link_out.as_entire_binding());
            for index in 0..N {
                resources.insert(
                    names.values_in[index].into(),
                    values_in[index].as_entire_binding(),
                );
                resources.insert(
                    names.values_out[index].into(),
                    values_out[index].as_entire_binding(),
                );
            }
            let final_unpaired_step = step + 1 == steps && steps % 2 == 1;
            let label = if final_unpaired_step {
                invocation.a_to_b_final
            } else if step % 2 == 0 {
                invocation.a_to_b
            } else {
                invocation.b_to_a
            };
            let cache_identity = format!("{label}.{step}");
            let bind_group = cache
                .reflected_for_graph_invocation(
                    device,
                    &cache_identity,
                    label,
                    data,
                    buffers,
                    &resources,
                    Some(dispatch_args),
                )?
                .into_iter()
                .next()
                .expect("tree-relation operation must have one reflected bind group");
            crate::gpu::passes_core::record_or_defer_compute_indirect(
                encoder,
                data,
                bind_group.as_ref(),
                label,
                dispatch_args,
            );
        }

        if steps % 2 == 1 {
            buffers.record_finalizer(invocation.finalize, encoder)?;
        }

        Ok(())
    }

    pub(in crate::parser) fn graph_pair_pass(&self) -> &PassData {
        &self.pair_data
    }

    pub(in crate::parser) fn graph_single_pass(&self) -> &PassData {
        &self.data
    }

    pub(in crate::parser) fn graph_triple_pass(&self) -> &PassData {
        &self.triple_data
    }
}

#[derive(Clone, Copy)]
struct RelationNames<const N: usize> {
    link_in: &'static str,
    link_out: &'static str,
    values_in: [&'static str; N],
    values_out: [&'static str; N],
}

const SINGLE_NAMES: RelationNames<1> = RelationNames {
    link_in: "hir_semantic_parent_link_in",
    link_out: "hir_semantic_parent_link_out",
    values_in: ["hir_semantic_parent_value_in"],
    values_out: ["hir_semantic_parent_value_out"],
};
const PAIR_NAMES: RelationNames<2> = RelationNames {
    link_in: "relation_link_in",
    link_out: "relation_link_out",
    values_in: ["first_value_in", "second_value_in"],
    values_out: ["first_value_out", "second_value_out"],
};
const TRIPLE_NAMES: RelationNames<3> = RelationNames {
    link_in: "relation_link_in",
    link_out: "relation_link_out",
    values_in: ["first_value_in", "second_value_in", "third_value_in"],
    values_out: ["first_value_out", "second_value_out", "third_value_out"],
};

#[derive(Clone, Copy)]
pub struct TreeRelationBuffers<'a, const N: usize> {
    link_a: &'a crate::gpu::buffers::LaniusBuffer<u32>,
    link_b: &'a crate::gpu::buffers::LaniusBuffer<u32>,
    values_a: [&'a crate::gpu::buffers::LaniusBuffer<u32>; N],
    values_b: [&'a crate::gpu::buffers::LaniusBuffer<u32>; N],
}

impl<'a, const N: usize> TreeRelationBuffers<'a, N> {
    pub fn new(
        link_a: &'a crate::gpu::buffers::LaniusBuffer<u32>,
        link_b: &'a crate::gpu::buffers::LaniusBuffer<u32>,
        values_a: [&'a crate::gpu::buffers::LaniusBuffer<u32>; N],
        values_b: [&'a crate::gpu::buffers::LaniusBuffer<u32>; N],
    ) -> Self {
        Self {
            link_a,
            link_b,
            values_a,
            values_b,
        }
    }

    fn for_step(
        self,
        step: u32,
    ) -> (
        &'a crate::gpu::buffers::LaniusBuffer<u32>,
        [&'a crate::gpu::buffers::LaniusBuffer<u32>; N],
        &'a crate::gpu::buffers::LaniusBuffer<u32>,
        [&'a crate::gpu::buffers::LaniusBuffer<u32>; N],
    ) {
        if step % 2 == 0 {
            (self.link_a, self.values_a, self.link_b, self.values_b)
        } else {
            (self.link_b, self.values_b, self.link_a, self.values_a)
        }
    }
}

pub(crate) fn pointer_jump_steps_after_local_span(items: u32) -> u32 {
    crate::parser::buffers::pointer_jump_step_capacity(
        items.max(1).div_ceil(SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN),
    )
}

pub(in crate::parser) fn bounded_walk_steps_after_local_span(items: u32, local_span: u32) -> u32 {
    bounded_walk_step_capacity(items.max(1).div_ceil(local_span.max(1)))
}

pub(in crate::parser) fn canonical_relation_step_capacity(items: u32) -> u32 {
    bounded_walk_steps_after_local_span(
        items,
        crate::parser::passes::hir::canonical::RELATION_LOCAL_ANCESTOR_SPAN,
    )
}

#[cfg(test)]
mod tests {
    use super::{bounded_walk_steps_after_local_span, pointer_jump_steps_after_local_span};
    use crate::parser::{
        buffers::pointer_jump_step_capacity,
        passes::hir::nodes::SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN,
    };

    fn scheduled_steps(items: u32, max_depth: u32) -> u32 {
        let span = SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN;
        let required = pointer_jump_step_capacity((max_depth + 1).div_ceil(span));
        let capacity = pointer_jump_steps_after_local_span(items);
        required + ((required ^ capacity) & 1)
    }

    #[test]
    fn local_walk_reduces_global_pointer_jump_rounds_without_losing_depth_coverage() {
        assert_eq!(pointer_jump_steps_after_local_span(1), 0);
        assert_eq!(pointer_jump_steps_after_local_span(32), 0);
        assert_eq!(pointer_jump_steps_after_local_span(33), 1);
        assert_eq!(pointer_jump_steps_after_local_span(64), 1);
        assert_eq!(pointer_jump_steps_after_local_span(65), 2);
        assert_eq!(pointer_jump_steps_after_local_span(1_687_524), 16);
    }

    #[test]
    fn actual_depth_schedule_preserves_capacity_ping_pong_parity() {
        let items = 1_687_524;
        let capacity = pointer_jump_steps_after_local_span(items);
        for max_depth in [0, 31, 32, 63, 64, 95, 96, 511, 65_535] {
            let scheduled = scheduled_steps(items, max_depth);
            assert!(scheduled <= capacity);
            assert_eq!(scheduled % 2, capacity % 2);
        }
        assert_eq!(scheduled_steps(items, 31), 0);
        assert_eq!(scheduled_steps(items, 32), 2);
        assert_eq!(scheduled_steps(items, 64), 2);
        assert_eq!(scheduled_steps(items, 96), 2);
    }

    #[test]
    fn bounded_relation_walk_composes_local_ancestor_spans() {
        let span = SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN;
        assert_eq!(bounded_walk_steps_after_local_span(32, span), 0);
        assert_eq!(bounded_walk_steps_after_local_span(33, span), 1);
        assert_eq!(bounded_walk_steps_after_local_span(512, span), 1);
        assert_eq!(bounded_walk_steps_after_local_span(513, span), 2);
        assert_eq!(bounded_walk_steps_after_local_span(1_687_524, span), 4);
        assert_eq!(bounded_walk_steps_after_local_span(1_687_524, 1), 6);
        assert_eq!(bounded_walk_steps_after_local_span(1_687_524, 2), 5);
    }
}
