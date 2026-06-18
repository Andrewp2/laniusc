use super::*;

mod calls;
mod compute;
mod control_flow;
mod methods;
mod module_paths;
mod names;
mod predicates;
mod type_instances;
mod visible;

pub(in crate::type_checker) use calls::*;
pub(in crate::type_checker) use compute::*;
pub(in crate::type_checker) use control_flow::*;
pub(in crate::type_checker) use methods::*;
pub(in crate::type_checker) use module_paths::*;
pub(in crate::type_checker) use names::*;
pub(in crate::type_checker) use predicates::*;
pub(in crate::type_checker) use type_instances::*;
pub(in crate::type_checker) use visible::*;

/// Timer labels used for one type-instance collection sweep.
pub(super) struct TypeInstanceCollectionTimerLabels {
    pub scalar: &'static str,
    pub named: &'static str,
    pub aggregate_refs: &'static str,
    pub aggregate_details: &'static str,
}

/// Timer labels for the initial type-instance collection before projection.
pub(super) const TYPE_INSTANCE_COLLECTION_INITIAL_LABELS: TypeInstanceCollectionTimerLabels =
    TypeInstanceCollectionTimerLabels {
        scalar: "typecheck.type_instances.initial.collect_scalar.done",
        named: "typecheck.type_instances.initial.collect_named.done",
        aggregate_refs: "typecheck.type_instances.initial.collect_aggregate_refs.done",
        aggregate_details: "typecheck.type_instances.initial.collect_aggregate_details.done",
    };

/// Timer labels for the post-projection type-instance collection sweep.
pub(super) const TYPE_INSTANCE_COLLECTION_PROJECTED_LABELS: TypeInstanceCollectionTimerLabels =
    TypeInstanceCollectionTimerLabels {
        scalar: "typecheck.type_instances.projected.collect_scalar.done",
        named: "typecheck.type_instances.projected.collect_named.done",
        aggregate_refs: "typecheck.type_instances.projected.collect_aggregate_refs.done",
        aggregate_details: "typecheck.type_instances.projected.collect_aggregate_details.done",
    };
