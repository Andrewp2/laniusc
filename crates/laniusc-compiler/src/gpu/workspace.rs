//! Physical storage plan produced from compiler-graph resource lifetimes.

use std::collections::BTreeSet;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WorkspaceUsageClass {
    Storage,
    StorageIndirect,
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

/// Adapter constraints used when placing lifetime-colored workspace slots in
/// shared physical buffers.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WorkspaceArenaLimits {
    /// Largest arena that can be allocated and exposed through the compiler's
    /// fixed storage-buffer ABI.
    pub max_arena_bytes: u64,
    /// Required alignment of every storage-buffer binding offset.
    pub offset_alignment: u64,
}

impl WorkspaceArenaLimits {
    /// Derives an arena ABI that is valid for the device rather than imposing
    /// a project-wide buffer ceiling. Keeping each arena within one storage
    /// binding lets reflected passes bind exact logical ranges from the arena.
    pub fn from_device_limits(limits: &wgpu::Limits) -> Result<Self, String> {
        let offset_alignment = u64::from(limits.min_storage_buffer_offset_alignment).max(4);
        let raw_max = limits
            .max_buffer_size
            .min(limits.max_storage_buffer_binding_size);
        let max_arena_bytes = raw_max & !(offset_alignment - 1);
        if max_arena_bytes == 0 {
            return Err(format!(
                "device storage limits cannot provide one {offset_alignment}-byte-aligned arena",
            ));
        }
        Ok(Self {
            max_arena_bytes,
            offset_alignment,
        })
    }
}

/// Byte range assigned to one lifetime-colored workspace slot.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WorkspaceArenaPlacement {
    pub slot: u32,
    pub arena: u32,
    pub byte_offset: u64,
    pub byte_size: u64,
}

/// One physical buffer in the arena plan. All arenas use the superset of
/// storage, copy, and indirect usages so slots do not need separate buffers
/// merely because one operation dispatches indirectly.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WorkspaceArenaPlan {
    pub arena: u32,
    pub bytes: u64,
}

/// Physical packing of the graph's simultaneously resident workspace slots.
/// This is deliberately separate from lifetime coloring: coloring decides
/// which logical resources may share a byte range over time, while this plan
/// places those ranges inside a small number of WGPU allocations.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WorkspaceArenaLayout {
    pub arenas: Vec<WorkspaceArenaPlan>,
    pub placements: Vec<WorkspaceArenaPlacement>,
}

/// Packs lifetime-colored slots into adapter-sized physical arenas.
///
/// Largest-first placement avoids stranding a large slot behind small aligned
/// ranges. Slot and arena numbering remain deterministic for a fixed graph and
/// capacity, which allows daemon jobs to reuse both allocations and bind
/// groups.
pub fn plan_workspace_arenas(
    workspace: &WorkspacePlan,
    limits: WorkspaceArenaLimits,
) -> Result<WorkspaceArenaLayout, String> {
    plan_workspace_arenas_with_conflicts(workspace, limits, &BTreeSet::new())
}

/// Packs slots while keeping pairs used by one GPU command in distinct
/// physical buffers. WGPU storage and indirect usage validation is performed
/// per physical buffer rather than per bound byte range, so disjoint ranges
/// cannot share an arena when a pass uses them simultaneously.
pub fn plan_workspace_arenas_with_conflicts(
    workspace: &WorkspacePlan,
    limits: WorkspaceArenaLimits,
    incompatible_slots: &BTreeSet<(u32, u32)>,
) -> Result<WorkspaceArenaLayout, String> {
    if limits.max_arena_bytes == 0 {
        return Err("workspace arena maximum must be non-zero".to_owned());
    }
    if !limits.offset_alignment.is_power_of_two() {
        return Err(format!(
            "workspace arena offset alignment {} is not a non-zero power of two",
            limits.offset_alignment,
        ));
    }

    #[derive(Clone, Copy)]
    struct OpenArena {
        used_bytes: u64,
    }

    let mut slots = workspace.slots.clone();
    slots.sort_unstable_by_key(|slot| (std::cmp::Reverse(slot.bytes), slot.slot));
    let mut arenas = Vec::<OpenArena>::new();
    let mut arena_slots = Vec::<Vec<u32>>::new();
    let mut placements = Vec::with_capacity(slots.len());
    for slot in slots {
        if slot.bytes == 0 {
            return Err(format!("workspace slot {} has zero bytes", slot.slot));
        }
        let physical_bytes = align_up(slot.bytes, 4)?;
        if physical_bytes > limits.max_arena_bytes {
            return Err(format!(
                "workspace slot {} requires {} bytes, exceeding the adapter arena limit {}",
                slot.slot, slot.bytes, limits.max_arena_bytes,
            ));
        }

        let mut selected = None;
        for (arena_index, arena) in arenas.iter().enumerate() {
            if arena_slots[arena_index]
                .iter()
                .any(|&other| incompatible_slots.contains(&ordered_pair(slot.slot, other)))
            {
                continue;
            }
            let offset = align_up(arena.used_bytes, limits.offset_alignment)?;
            let end = offset
                .checked_add(physical_bytes)
                .ok_or_else(|| format!("workspace slot {} byte range overflows", slot.slot))?;
            if end <= limits.max_arena_bytes {
                selected = Some((arena_index, offset, end));
                break;
            }
        }
        let (arena_index, byte_offset, end) = match selected {
            Some(selected) => selected,
            None => {
                let index = arenas.len();
                arenas.push(OpenArena { used_bytes: 0 });
                arena_slots.push(Vec::new());
                (index, 0, slot.bytes)
            }
        };
        arenas[arena_index].used_bytes = end;
        arena_slots[arena_index].push(slot.slot);
        placements.push(WorkspaceArenaPlacement {
            slot: slot.slot,
            arena: arena_index as u32,
            byte_offset,
            byte_size: physical_bytes,
        });
    }

    placements.sort_unstable_by_key(|placement| placement.slot);
    Ok(WorkspaceArenaLayout {
        arenas: arenas
            .into_iter()
            .enumerate()
            .map(|(arena, plan)| WorkspaceArenaPlan {
                arena: arena as u32,
                bytes: plan.used_bytes,
            })
            .collect(),
        placements,
    })
}

const fn ordered_pair(left: u32, right: u32) -> (u32, u32) {
    if left < right {
        (left, right)
    } else {
        (right, left)
    }
}

fn align_up(value: u64, alignment: u64) -> Result<u64, String> {
    value
        .checked_add(alignment - 1)
        .map(|value| value & !(alignment - 1))
        .ok_or_else(|| "workspace arena alignment overflows".to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn slot(slot: u32, bytes: u64) -> WorkspaceSlotPlan {
        WorkspaceSlotPlan {
            slot,
            bytes,
            usage: WorkspaceUsageClass::Storage,
        }
    }

    #[test]
    fn packs_slots_into_aligned_shared_arenas() {
        let workspace = WorkspacePlan {
            assignments: Vec::new(),
            slots: vec![slot(0, 65), slot(1, 128), slot(2, 63)],
        };
        let layout = plan_workspace_arenas(
            &workspace,
            WorkspaceArenaLimits {
                max_arena_bytes: 512,
                offset_alignment: 64,
            },
        )
        .unwrap();

        assert_eq!(
            layout.arenas,
            vec![WorkspaceArenaPlan {
                arena: 0,
                bytes: 320
            }]
        );
        assert_eq!(
            layout.placements,
            vec![
                WorkspaceArenaPlacement {
                    slot: 0,
                    arena: 0,
                    byte_offset: 128,
                    byte_size: 68,
                },
                WorkspaceArenaPlacement {
                    slot: 1,
                    arena: 0,
                    byte_offset: 0,
                    byte_size: 128,
                },
                WorkspaceArenaPlacement {
                    slot: 2,
                    arena: 0,
                    byte_offset: 256,
                    byte_size: 64,
                },
            ],
        );
    }

    #[test]
    fn spills_deterministically_at_the_adapter_limit() {
        let workspace = WorkspacePlan {
            assignments: Vec::new(),
            slots: vec![slot(0, 192), slot(1, 192), slot(2, 128)],
        };
        let layout = plan_workspace_arenas(
            &workspace,
            WorkspaceArenaLimits {
                max_arena_bytes: 256,
                offset_alignment: 64,
            },
        )
        .unwrap();

        assert_eq!(layout.arenas.len(), 3);
        assert_eq!(layout.placements[0].arena, 0);
        assert_eq!(layout.placements[1].arena, 1);
        assert_eq!(layout.placements[2].arena, 2);
    }

    #[test]
    fn rejects_a_slot_larger_than_one_bindable_arena() {
        let error = plan_workspace_arenas(
            &WorkspacePlan {
                assignments: Vec::new(),
                slots: vec![slot(7, 257)],
            },
            WorkspaceArenaLimits {
                max_arena_bytes: 256,
                offset_alignment: 64,
            },
        )
        .unwrap_err();
        assert!(error.contains("slot 7"));
        assert!(error.contains("exceeding the adapter arena limit 256"));
    }

    #[test]
    fn separates_slots_used_by_one_pass_even_when_ranges_fit() {
        let workspace = WorkspacePlan {
            assignments: Vec::new(),
            slots: vec![slot(0, 64), slot(1, 64), slot(2, 64)],
        };
        let layout = plan_workspace_arenas_with_conflicts(
            &workspace,
            WorkspaceArenaLimits {
                max_arena_bytes: 512,
                offset_alignment: 64,
            },
            &BTreeSet::from([(0, 1)]),
        )
        .unwrap();

        assert_ne!(layout.placements[0].arena, layout.placements[1].arena);
        assert_eq!(layout.placements[0].arena, layout.placements[2].arena);
    }

    #[test]
    fn device_limits_keep_allocation_and_binding_caps_distinct() {
        let mut limits = wgpu::Limits::defaults();
        limits.max_buffer_size = 1024;
        limits.max_storage_buffer_binding_size = 768;
        limits.min_storage_buffer_offset_alignment = 256;

        assert_eq!(
            WorkspaceArenaLimits::from_device_limits(&limits).unwrap(),
            WorkspaceArenaLimits {
                max_arena_bytes: 768,
                offset_alignment: 256,
            },
        );
    }
}
