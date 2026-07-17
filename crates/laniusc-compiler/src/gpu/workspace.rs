//! Phase-colored whole-buffer workspace planning.
//!
//! The planner is intentionally independent of compiler semantics: phases
//! declare logical byte ranges and lifetimes, then receive stable physical slot
//! ids. Semantic passes retain ownership of active counts and buffer contents.

use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum WorkspacePhase {
    TokensAndActions,
    Brackets,
    RawTree,
    Hir,
    TypeCheck,
    Backend,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WorkspaceUsageClass {
    Storage,
    StorageIndirect,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WorkspaceRequest {
    pub name: &'static str,
    pub bytes: u64,
    pub usage: WorkspaceUsageClass,
    pub first: WorkspacePhase,
    pub last: WorkspacePhase,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WorkspaceAssignment {
    pub name: &'static str,
    pub slot: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WorkspaceSlotPlan {
    pub slot: u32,
    pub bytes: u64,
    pub usage: WorkspaceUsageClass,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WorkspacePlan {
    pub assignments: Vec<WorkspaceAssignment>,
    pub slots: Vec<WorkspaceSlotPlan>,
}

pub fn plan_workspace(requests: &[WorkspaceRequest]) -> Result<WorkspacePlan, String> {
    for request in requests {
        if request.first > request.last {
            return Err(format!(
                "workspace {} has an inverted phase lifetime",
                request.name
            ));
        }
        if request.bytes == 0 {
            return Err(format!("workspace {} has zero bytes", request.name));
        }
    }
    let mut order = (0..requests.len()).collect::<Vec<_>>();
    order.sort_unstable_by_key(|&index| {
        let request = requests[index];
        (
            request.first,
            std::cmp::Reverse(request.bytes),
            request.name,
        )
    });

    #[derive(Clone, Copy)]
    struct SlotState {
        plan: WorkspaceSlotPlan,
        last: WorkspacePhase,
    }
    let mut slots = Vec::<SlotState>::new();
    let mut assignment_by_index = vec![0u32; requests.len()];
    for index in order {
        let request = requests[index];
        let reusable = slots.iter().enumerate().find_map(|(slot_index, slot)| {
            (slot.plan.usage == request.usage && slot.last < request.first).then_some(slot_index)
        });
        let slot_index = reusable.unwrap_or_else(|| {
            let slot_index = slots.len();
            slots.push(SlotState {
                plan: WorkspaceSlotPlan {
                    slot: slot_index as u32,
                    bytes: request.bytes,
                    usage: request.usage,
                },
                last: request.last,
            });
            slot_index
        });
        let slot = &mut slots[slot_index];
        slot.plan.bytes = slot.plan.bytes.max(request.bytes);
        slot.last = request.last;
        assignment_by_index[index] = slot.plan.slot;
    }
    Ok(WorkspacePlan {
        assignments: requests
            .iter()
            .enumerate()
            .map(|(index, request)| WorkspaceAssignment {
                name: request.name,
                slot: assignment_by_index[index],
            })
            .collect(),
        slots: slots.into_iter().map(|slot| slot.plan).collect(),
    })
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BoundWorkspaceRange {
    pub logical_name: &'static str,
    pub slot: u32,
    pub offset: u64,
    pub size: u64,
    pub writable: bool,
}

pub fn validate_simultaneous_bindings(bindings: &[BoundWorkspaceRange]) -> Result<(), String> {
    let mut by_slot = BTreeMap::<u32, Vec<BoundWorkspaceRange>>::new();
    for binding in bindings {
        by_slot.entry(binding.slot).or_default().push(*binding);
    }
    for ranges in by_slot.values() {
        for (left_index, left) in ranges.iter().enumerate() {
            for right in &ranges[left_index + 1..] {
                let overlap = left.offset < right.offset.saturating_add(right.size)
                    && right.offset < left.offset.saturating_add(left.size);
                if overlap && (left.writable || right.writable) {
                    return Err(format!(
                        "workspace slot {} aliases simultaneously bound ranges {} and {} while at least one is writable",
                        left.slot, left.logical_name, right.logical_name,
                    ));
                }
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn non_overlapping_phase_lifetimes_share_one_stable_slot() {
        let plan = plan_workspace(&[
            WorkspaceRequest {
                name: "parse",
                bytes: 64,
                usage: WorkspaceUsageClass::Storage,
                first: WorkspacePhase::TokensAndActions,
                last: WorkspacePhase::RawTree,
            },
            WorkspaceRequest {
                name: "types",
                bytes: 96,
                usage: WorkspaceUsageClass::Storage,
                first: WorkspacePhase::TypeCheck,
                last: WorkspacePhase::TypeCheck,
            },
            WorkspaceRequest {
                name: "backend",
                bytes: 32,
                usage: WorkspaceUsageClass::Storage,
                first: WorkspacePhase::Backend,
                last: WorkspacePhase::Backend,
            },
        ])
        .unwrap();
        assert_eq!(plan.slots.len(), 1);
        assert_eq!(plan.slots[0].bytes, 96);
        assert!(
            plan.assignments
                .iter()
                .all(|assignment| assignment.slot == 0)
        );
    }

    #[test]
    fn overlapping_or_indirect_lifetimes_receive_distinct_slots() {
        let plan = plan_workspace(&[
            WorkspaceRequest {
                name: "read",
                bytes: 64,
                usage: WorkspaceUsageClass::Storage,
                first: WorkspacePhase::Hir,
                last: WorkspacePhase::TypeCheck,
            },
            WorkspaceRequest {
                name: "write",
                bytes: 64,
                usage: WorkspaceUsageClass::Storage,
                first: WorkspacePhase::TypeCheck,
                last: WorkspacePhase::Backend,
            },
            WorkspaceRequest {
                name: "dispatch",
                bytes: 12,
                usage: WorkspaceUsageClass::StorageIndirect,
                first: WorkspacePhase::Backend,
                last: WorkspacePhase::Backend,
            },
        ])
        .unwrap();
        assert_eq!(plan.slots.len(), 3);
    }

    #[test]
    fn writable_overlapping_aliases_are_rejected() {
        let error = validate_simultaneous_bindings(&[
            BoundWorkspaceRange {
                logical_name: "left",
                slot: 2,
                offset: 0,
                size: 64,
                writable: true,
            },
            BoundWorkspaceRange {
                logical_name: "right",
                slot: 2,
                offset: 32,
                size: 64,
                writable: false,
            },
        ])
        .unwrap_err();
        assert!(error.contains("left and right"));
    }
}
