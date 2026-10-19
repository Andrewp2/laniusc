//! Per-round state that lets bounded relation walks stop early on the GPU.
//!
//! A walk records `bounded_walk_step_capacity` ping-pong rounds, enough for
//! the longest chain the tree capacity allows. Each walk owns a slot of round
//! regions in `hir_walk_state` (two words each: changed, ran). Round `k` reads
//! region `k` (the previous round's; region 0 is never written) and writes
//! region `k + 1`; a uniform record per (walk, round) tells the kernel which
//! word indices those are. A round whose previous round changed nothing
//! returns at once (see `shaders/hir_walk_state.slang`). The recorded
//! dispatches, their order and the ping-pong parity are the same as without
//! the early exit, and no value is read back.

use encase::ShaderType;

use super::list::rank::ListRankInvocation;
use crate::{
    gpu::buffers::{DynamicUniformBuffer, dynamic_uniforms_from_vals},
    parser::buffers::ParserBuffers,
};

/// A walk over `u32` items needs at most 8 rounds of 16 links.
const MAX_ROUNDS: u64 = 8;
/// One leading region nothing writes, plus one per round.
const REGIONS_PER_WALK: u64 = MAX_ROUNDS + 1;
const WORDS_PER_REGION: u64 = 2;

/// Walks that use the early exit. Each has its own slot of round regions.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::parser) enum HirWalk {
    TypePathLeaf,
    ContextRelations,
    ExprResultRoot,
    TypeAliasOwner,
    EnumVariantRank,
    StructFieldRank,
    ListRank(ListRankInvocation),
}

const FIXED_WALKS: u64 = 6;
const LIST_RANK_INVOCATIONS: u64 = 10;
const WALK_SLOTS: u64 = FIXED_WALKS + LIST_RANK_INVOCATIONS;

/// Size of the `hir_walk_state` graph resource.
pub(in crate::parser) const HIR_WALK_STATE_BYTES: u64 =
    WALK_SLOTS * REGIONS_PER_WALK * WORDS_PER_REGION * 4;

impl HirWalk {
    const fn slot(self) -> u64 {
        match self {
            Self::TypePathLeaf => 0,
            Self::ContextRelations => 1,
            Self::ExprResultRoot => 2,
            Self::TypeAliasOwner => 3,
            Self::EnumVariantRank => 4,
            Self::StructFieldRank => 5,
            Self::ListRank(invocation) => {
                FIXED_WALKS
                    + match invocation {
                        ListRankInvocation::TypeArguments => 0,
                        ListRankInvocation::Parameters => 1,
                        ListRankInvocation::CallArguments => 2,
                        ListRankInvocation::ArrayElements => 3,
                        ListRankInvocation::StringRecords => 4,
                        ListRankInvocation::StringOffsets => 5,
                        ListRankInvocation::PathSegments => 6,
                        ListRankInvocation::TypeRoots => 7,
                        ListRankInvocation::VariantPayloadOwners => 8,
                        ListRankInvocation::BinarySpans => 9,
                    }
            }
        }
    }

    fn record(self, step: u32) -> usize {
        assert!(
            u64::from(step) < MAX_ROUNDS,
            "bounded walk round {step} exceeds the walk-state regions"
        );
        (self.slot() * MAX_ROUNDS + u64::from(step)) as usize
    }
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Word indices, in `hir_walk_state`, of one round's previous and own region.
pub(in crate::parser) struct HirWalkRound {
    pub previous: u32,
    pub this_round: u32,
}

/// One uniform record per (walk, round), written once at creation.
pub(in crate::parser) fn hir_walk_rounds(device: &wgpu::Device) -> DynamicUniformBuffer<HirWalkRound> {
    let records = (0..WALK_SLOTS)
        .flat_map(|slot| {
            (0..MAX_ROUNDS).map(move |round| {
                let region = slot * REGIONS_PER_WALK + round;
                HirWalkRound {
                    previous: (region * WORDS_PER_REGION) as u32,
                    this_round: ((region + 1) * WORDS_PER_REGION) as u32,
                }
            })
        })
        .collect::<Vec<_>>();
    dynamic_uniforms_from_vals(device, "parser.hir_walk_rounds", &records)
}

impl ParserBuffers {
    /// The `hir_walk_state` and `gHirWalkRound` bindings for round `step` of
    /// `walk`.
    pub(in crate::parser) fn hir_walk_bindings(
        &self,
        walk: HirWalk,
        step: u32,
    ) -> [(String, wgpu::BindingResource<'_>); 2] {
        [
            ("hir_walk_state".into(), self.hir_walk_state.as_entire_binding()),
            (
                "gHirWalkRound".into(),
                self.hir_walk_rounds.record_binding(walk.record(step)),
            ),
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn walk_slots_are_distinct_and_fit_the_resource() {
        let invocations = [
            ListRankInvocation::TypeArguments,
            ListRankInvocation::Parameters,
            ListRankInvocation::CallArguments,
            ListRankInvocation::ArrayElements,
            ListRankInvocation::StringRecords,
            ListRankInvocation::StringOffsets,
            ListRankInvocation::PathSegments,
            ListRankInvocation::TypeRoots,
            ListRankInvocation::VariantPayloadOwners,
            ListRankInvocation::BinarySpans,
        ];
        let mut slots: Vec<u64> = [
            HirWalk::TypePathLeaf,
            HirWalk::ContextRelations,
            HirWalk::ExprResultRoot,
            HirWalk::TypeAliasOwner,
            HirWalk::EnumVariantRank,
            HirWalk::StructFieldRank,
        ]
        .into_iter()
        .chain(invocations.into_iter().map(HirWalk::ListRank))
        .map(HirWalk::slot)
        .collect();
        slots.sort_unstable();
        slots.dedup();
        assert_eq!(slots.len() as u64, WALK_SLOTS);
        let last = HirWalk::ListRank(ListRankInvocation::BinarySpans).record(7) as u64;
        assert_eq!(last + 1, WALK_SLOTS * MAX_ROUNDS);
        // The last round's own region is the last region of the resource.
        let region = (WALK_SLOTS - 1) * REGIONS_PER_WALK + MAX_ROUNDS;
        assert_eq!((region + 1) * WORDS_PER_REGION * 4, HIR_WALK_STATE_BYTES);
    }
}
