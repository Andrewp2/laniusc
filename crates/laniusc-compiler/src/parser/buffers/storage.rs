use crate::gpu::{
    buffers::{LaniusBuffer, storage_rw_for_array},
    compiler_graph::{
        CompilerGraphBuilder,
        CompilerPhase,
        PassAccess,
        PassDesc,
        ResourceClass,
        ResourceDesc,
        ResourceDomain,
    },
    workspace::{WorkspacePlan, WorkspaceUsageClass},
};

pub(super) fn parser_phase_workspace_plan(tree_capacity: u32) -> WorkspacePlan {
    let tree_bytes = u64::from(tree_capacity) * 4;
    let mut graph = CompilerGraphBuilder::new();
    let tree_prefix_inblock = graph
        .add_resource(ResourceDesc {
            name: "tree.prefix_inblock",
            domain: ResourceDomain::RawNodes,
            class: ResourceClass::Workspace,
            bytes: tree_bytes,
            usage: WorkspaceUsageClass::Storage,
        })
        .expect("parser graph resource names are unique");
    let tree_prefix = graph
        .add_resource(ResourceDesc {
            name: "tree.prefix",
            domain: ResourceDomain::RawNodes,
            class: ResourceClass::Workspace,
            bytes: tree_bytes + 4,
            usage: WorkspaceUsageClass::Storage,
        })
        .expect("parser graph resource names are unique");
    let hir_family_flag = graph
        .add_resource(ResourceDesc {
            name: "hir.family_flag",
            domain: ResourceDomain::HirNodes,
            class: ResourceClass::Workspace,
            bytes: tree_bytes,
            usage: WorkspaceUsageClass::Storage,
        })
        .expect("parser graph resource names are unique");
    let hir_family_local_prefix = graph
        .add_resource(ResourceDesc {
            name: "hir.family_local_prefix",
            domain: ResourceDomain::HirNodes,
            class: ResourceClass::Workspace,
            // Reserve the full slot inherited from `tree.prefix`; the final
            // word is padding during HIR scans.
            bytes: tree_bytes + 4,
            usage: WorkspaceUsageClass::Storage,
        })
        .expect("parser graph resource names are unique");
    let typecheck_fn_entrypoint_tag = graph
        .add_resource(ResourceDesc {
            name: "typecheck.fn_entrypoint_tag",
            domain: ResourceDomain::HirNodes,
            class: ResourceClass::Workspace,
            bytes: tree_bytes,
            usage: WorkspaceUsageClass::Storage,
        })
        .expect("parser graph resource names are unique");

    graph
        .add_pass(PassDesc {
            name: "parser.raw_tree_prefix",
            phase: CompilerPhase::Parse,
            dispatch_domain: ResourceDomain::RawNodes,
            accesses: vec![
                PassAccess::write("prefix_inblock", tree_prefix_inblock),
                PassAccess::write("tree_prefix", tree_prefix),
            ],
        })
        .expect("parser graph pass is valid");
    graph
        .add_pass(PassDesc {
            name: "parser.hir_family_compaction",
            phase: CompilerPhase::Hir,
            dispatch_domain: ResourceDomain::HirNodes,
            accesses: vec![
                PassAccess::write("hir_family_flag", hir_family_flag),
                PassAccess::write("hir_family_local_prefix", hir_family_local_prefix),
            ],
        })
        .expect("parser graph pass is valid");
    graph
        .add_pass(PassDesc {
            name: "typecheck.function_entrypoint_tags",
            phase: CompilerPhase::TypeCheck,
            dispatch_domain: ResourceDomain::HirNodes,
            accesses: vec![PassAccess::write(
                "fn_entrypoint_tag",
                typecheck_fn_entrypoint_tag,
            )],
        })
        .expect("parser graph pass is valid");

    graph
        .build()
        .expect("parser compiler graph must be valid")
        .workspace_plan()
        .clone()
}

/// Reinterprets one typed storage buffer as another typed buffer with a new element count.
pub(super) fn alias_storage_buffer<T, U>(
    source: &LaniusBuffer<T>,
    count: usize,
) -> LaniusBuffer<U> {
    let target_stride = core::mem::size_of::<U>().max(1);
    let required_bytes = count
        .checked_mul(target_stride)
        .expect("storage alias byte size overflow");
    assert!(
        required_bytes <= source.byte_size,
        "storage alias requires {required_bytes} bytes but source only has {} bytes",
        source.byte_size,
    );
    source.alias(count)
}

/// Reuses a dead u32 storage allocation for a later parser phase when it is
/// large enough, otherwise allocates the requested workspace normally.
pub(super) fn reuse_or_allocate_u32_workspace(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    reusable: Option<&LaniusBuffer<u32>>,
) -> LaniusBuffer<u32> {
    let required_bytes = count.saturating_mul(core::mem::size_of::<u32>());
    if let Some(buffer) = reusable.filter(|buffer| buffer.byte_size >= required_bytes) {
        buffer.alias(count)
    } else {
        storage_rw_for_array::<u32>(device, label, count)
    }
}

/// Reuses a phase-dead storage allocation for a later typed workspace when it
/// is large enough. The allocation identity stays stable, which lets resident
/// bind groups describe the complete phase schedule without retaining a
/// separate physical buffer for every logical array.
#[allow(dead_code)]
pub(super) fn reuse_or_allocate_workspace<T, U>(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    reusable: &LaniusBuffer<U>,
) -> LaniusBuffer<T>
where
    T: Default + encase::ShaderType + encase::internal::WriteInto,
{
    let mut layout = encase::StorageBuffer::new(Vec::<u8>::new());
    layout
        .write(&T::default())
        .expect("failed to measure storage workspace element");
    let required_bytes = count.saturating_mul(layout.as_ref().len());
    if reusable.byte_size >= required_bytes {
        reusable.alias(count)
    } else {
        storage_rw_for_array::<T>(device, label, count)
    }
}

/// Allocates a three-word dispatch-argument buffer usable for compute indirect dispatches.
pub(super) fn dispatch_args_buffer(device: &wgpu::Device, label: &str) -> LaniusBuffer<u32> {
    dispatch_args_schedule_buffer(device, label, 1)
}

/// Allocates consecutive three-word compute dispatch arguments.
pub(super) fn dispatch_args_schedule_buffer(
    device: &wgpu::Device,
    label: &str,
    dispatch_count: usize,
) -> LaniusBuffer<u32> {
    let word_count = dispatch_count.max(1) * 3;
    let byte_size = (word_count * std::mem::size_of::<u32>()) as u64;
    LaniusBuffer::new_labeled(
        (
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size: byte_size,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::INDIRECT
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            }),
            byte_size,
        ),
        word_count,
        label,
    )
}

/// Allocates a dispatch schedule followed by one GPU-written host metadata word.
pub(super) fn dispatch_args_schedule_with_count_buffer(
    device: &wgpu::Device,
    label: &str,
    dispatch_count: usize,
) -> LaniusBuffer<u32> {
    let word_count = dispatch_count.max(1) * 3 + 1;
    let byte_size = (word_count * std::mem::size_of::<u32>()) as u64;
    LaniusBuffer::new_labeled(
        (
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size: byte_size,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::INDIRECT
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            }),
            byte_size,
        ),
        word_count,
        label,
    )
}

pub(crate) fn dispatch_args_schedule_count_offset(dispatch_count: usize) -> u64 {
    (dispatch_count.max(1) * 3 * std::mem::size_of::<u32>()) as u64
}

pub(crate) fn pointer_jump_step_capacity(items: u32) -> u32 {
    u32::BITS - items.saturating_sub(1).leading_zeros()
}

#[cfg(test)]
mod tests {
    use super::{parser_phase_workspace_plan, pointer_jump_step_capacity};

    #[test]
    fn pointer_jump_capacity_is_ceiling_log_two() {
        assert_eq!(pointer_jump_step_capacity(0), 0);
        assert_eq!(pointer_jump_step_capacity(1), 0);
        assert_eq!(pointer_jump_step_capacity(2), 1);
        assert_eq!(pointer_jump_step_capacity(3), 2);
        assert_eq!(pointer_jump_step_capacity(4), 2);
        assert_eq!(pointer_jump_step_capacity(5), 3);
        assert_eq!(pointer_jump_step_capacity(u32::MAX), 32);
    }

    #[test]
    fn parser_raw_hir_and_typecheck_scratch_fit_two_stable_slots() {
        let plan = parser_phase_workspace_plan(1024);
        assert_eq!(plan.slots.len(), 2);
        let slot = |name| {
            plan.assignments
                .iter()
                .find(|assignment| assignment.name == name)
                .unwrap()
                .slot
        };
        assert_eq!(slot("tree.prefix_inblock"), slot("hir.family_flag"));
        assert_eq!(slot("tree.prefix"), slot("hir.family_local_prefix"));
        assert_eq!(slot("tree.prefix"), slot("typecheck.fn_entrypoint_tag"));
    }
}
