mod common;

use std::{
    collections::HashMap,
    env,
    fs,
    path::{Path, PathBuf},
    process::Command,
    sync::mpsc,
};

use laniusc::gpu::{
    device,
    passes_core::{bind_group, make_pass_data},
};
use wgpu::util::DeviceExt;

const TEST_COUNT: usize = 16;
const INVALID: u32 = 0xffff_ffff;
const KIND_ROOT: u32 = 1;
const KIND_OWNER: u32 = 2;

#[test]
fn generic_gpu_tree_walk_helpers_match_cpu_oracles() {
    common::block_on_gpu_with_timeout("generic GPU tree-walk helper validation", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_validation_shader(&root);

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.gpu_tree_walk.validate",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create tree-walk validation pass");

        let inputs = TreeWalkInputs::new();
        let expected = TreeWalkExpected::from_inputs(&inputs);
        let buffers = TreeWalkBuffers::new(device, &inputs);
        let bindings = buffers.bindings();
        let resources = bindings
            .iter()
            .map(|(name, resource)| ((*name).to_string(), resource.clone()))
            .collect::<HashMap<_, _>>();
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.gpu_tree_walk.validate.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )
        .expect("create tree-walk validation bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.gpu_tree_walk.validate.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.gpu_tree_walk.validate.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        copy_to_readback(&mut encoder, &buffers.owner_out, &buffers.owner_readback);
        copy_to_readback(
            &mut encoder,
            &buffers.ancestor_out,
            &buffers.ancestor_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.keyed_ancestor_out,
            &buffers.keyed_ancestor_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.ancestor_edge_out,
            &buffers.ancestor_edge_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.has_owner_out,
            &buffers.has_owner_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.has_owner_node_out,
            &buffers.has_owner_node_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.has_strict_owner_node_out,
            &buffers.has_strict_owner_node_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.first_child_out,
            &buffers.first_child_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.next_sibling_out,
            &buffers.next_sibling_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.child_previous_out,
            &buffers.child_previous_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.child_at_one_out,
            &buffers.child_at_one_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.owner_child_out,
            &buffers.owner_child_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.subtree_end_out,
            &buffers.subtree_end_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.contains_root_out,
            &buffers.contains_root_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.preorder_next_out,
            &buffers.preorder_next_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.preorder_first_owner_out,
            &buffers.preorder_first_owner_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.preorder_descendant_owner_out,
            &buffers.preorder_descendant_owner_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.preorder_owner_count_out,
            &buffers.preorder_owner_count_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.preorder_second_owner_out,
            &buffers.preorder_second_owner_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.preorder_owner_ordinal_before_out,
            &buffers.preorder_owner_ordinal_before_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.span_first_child_out,
            &buffers.span_first_child_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.span_next_sibling_out,
            &buffers.span_next_sibling_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.span_previous_sibling_out,
            &buffers.span_previous_sibling_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.ancestor_before_root_out,
            &buffers.ancestor_before_root_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.keyed_ancestor_before_root_out,
            &buffers.keyed_ancestor_before_root_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.keyed_owner_child_out,
            &buffers.keyed_owner_child_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.ancestor_visit_out,
            &buffers.ancestor_visit_readback,
        );
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &buffers.owner_readback, TEST_COUNT),
            expected.owner,
            "self-or-ancestor owner search should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.ancestor_readback, TEST_COUNT),
            expected.root_ancestor,
            "strict ancestor root search should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.keyed_ancestor_readback, TEST_COUNT),
            expected.root_ancestor,
            "keyed ancestor root search should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.ancestor_edge_readback, TEST_COUNT * 4),
            expected.owner_ancestor_edge_packed,
            "ancestor-edge helper outputs should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.has_owner_readback, TEST_COUNT),
            expected.has_owner,
            "boolean ancestor predicate helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.has_owner_node_readback, TEST_COUNT),
            expected.has_owner_node,
            "dynamic self-or-ancestor node helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.has_strict_owner_node_readback, TEST_COUNT),
            expected.has_strict_owner_node,
            "dynamic strict ancestor node helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.first_child_readback, TEST_COUNT),
            expected.first_child,
            "preorder first-child helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.next_sibling_readback, TEST_COUNT),
            expected.next_sibling,
            "preorder next-sibling helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.child_previous_readback, TEST_COUNT),
            expected.child_previous,
            "child-chain previous-sibling helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.child_at_one_readback, TEST_COUNT),
            expected.child_at_one,
            "preorder child ordinal helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.owner_child_readback, TEST_COUNT),
            expected.owner_child,
            "preorder matching-child helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.subtree_end_readback, TEST_COUNT),
            expected.subtree_end,
            "preorder subtree-end helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.contains_root_readback, TEST_COUNT),
            expected.contains_root,
            "preorder containment helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.preorder_next_readback, TEST_COUNT),
            expected.preorder_next,
            "linked-tree preorder successor helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.preorder_first_owner_readback, TEST_COUNT),
            expected.preorder_first_owner,
            "linked-tree first preorder key search should match CPU oracle"
        );
        assert_eq!(
            read_u32s(
                device,
                &buffers.preorder_descendant_owner_readback,
                TEST_COUNT
            ),
            expected.preorder_descendant_owner,
            "linked-tree first descendant key search should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.preorder_owner_count_readback, TEST_COUNT),
            expected.preorder_owner_count,
            "linked-tree preorder matching count should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.preorder_second_owner_readback, TEST_COUNT),
            expected.preorder_second_owner,
            "linked-tree nth preorder key search should match CPU oracle"
        );
        assert_eq!(
            read_u32s(
                device,
                &buffers.preorder_owner_ordinal_before_readback,
                TEST_COUNT
            ),
            expected.preorder_owner_ordinal_before,
            "linked-tree matching ordinal-before helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.span_first_child_readback, TEST_COUNT),
            expected.span_first_child,
            "span-tree first-child helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.span_next_sibling_readback, TEST_COUNT),
            expected.span_next_sibling,
            "span-tree next-sibling helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.span_previous_sibling_readback, TEST_COUNT),
            expected.span_previous_sibling,
            "span-tree previous-sibling helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.ancestor_before_root_readback, TEST_COUNT),
            expected.ancestor_before_root,
            "bounded strict ancestor search should match CPU oracle"
        );
        assert_eq!(
            read_u32s(
                device,
                &buffers.keyed_ancestor_before_root_readback,
                TEST_COUNT
            ),
            expected.ancestor_before_root,
            "keyed bounded strict ancestor search should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.keyed_owner_child_readback, TEST_COUNT),
            expected.owner_child,
            "keyed matching-child helper should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.ancestor_visit_readback, TEST_COUNT * 4),
            expected.ancestor_visit_packed,
            "ancestor visitor and before-or-until helper outputs should match CPU oracle"
        );
    });
}

struct TreeWalkInputs {
    parent: Vec<u32>,
    first_child: Vec<u32>,
    next_sibling: Vec<u32>,
    subtree_end: Vec<u32>,
    kind: Vec<u32>,
}

impl TreeWalkInputs {
    fn new() -> Self {
        Self {
            parent: vec![
                INVALID, 0, 1, 2, 1, 0, 5, 5, 0, 8, 9, 10, INVALID, 12, 13, 15,
            ],
            first_child: vec![
                1, 2, 3, INVALID, INVALID, 6, INVALID, INVALID, 9, 10, 11, INVALID, 13, 14,
                INVALID, INVALID,
            ],
            next_sibling: vec![
                INVALID, 5, 4, INVALID, INVALID, 8, 7, INVALID, INVALID, INVALID, INVALID, INVALID,
                INVALID, INVALID, INVALID, INVALID,
            ],
            subtree_end: vec![12, 5, 4, 4, 5, 8, 7, 8, 12, 12, 12, 12, 15, 15, 15, 16],
            kind: vec![
                KIND_ROOT, 0, KIND_OWNER, 0, 0, 0, KIND_OWNER, 0, 0, 0, 0, 0, KIND_ROOT, 0, 0, 0,
            ],
        }
    }
}

struct TreeWalkExpected {
    owner: Vec<u32>,
    root_ancestor: Vec<u32>,
    owner_ancestor_edge_packed: Vec<u32>,
    has_owner: Vec<u32>,
    has_owner_node: Vec<u32>,
    has_strict_owner_node: Vec<u32>,
    first_child: Vec<u32>,
    next_sibling: Vec<u32>,
    child_previous: Vec<u32>,
    child_at_one: Vec<u32>,
    owner_child: Vec<u32>,
    subtree_end: Vec<u32>,
    contains_root: Vec<u32>,
    preorder_next: Vec<u32>,
    preorder_first_owner: Vec<u32>,
    preorder_descendant_owner: Vec<u32>,
    preorder_owner_count: Vec<u32>,
    preorder_second_owner: Vec<u32>,
    preorder_owner_ordinal_before: Vec<u32>,
    span_first_child: Vec<u32>,
    span_next_sibling: Vec<u32>,
    span_previous_sibling: Vec<u32>,
    ancestor_before_root: Vec<u32>,
    ancestor_visit_packed: Vec<u32>,
}

impl TreeWalkExpected {
    fn from_inputs(inputs: &TreeWalkInputs) -> Self {
        let owner = (0..TEST_COUNT)
            .map(|node| find_self_or_ancestor(inputs, node as u32, 8, |kind| kind == KIND_OWNER))
            .collect::<Vec<_>>();
        let root_ancestor = (0..TEST_COUNT)
            .map(|node| {
                let parent = inputs.parent[node];
                if valid_node(parent) && parent != node as u32 {
                    find_self_or_ancestor(inputs, parent, 8, |kind| kind == KIND_ROOT)
                } else {
                    INVALID
                }
            })
            .collect::<Vec<_>>();
        let owner_ancestor_edges = (0..TEST_COUNT)
            .map(|node| find_ancestor_edge(inputs, node as u32, 8, |kind| kind == KIND_OWNER))
            .collect::<Vec<_>>();
        let owner_ancestor_edge_packed = owner_ancestor_edges
            .iter()
            .flat_map(|&(ancestor, child)| [ancestor, child, ancestor, child])
            .collect::<Vec<_>>();
        let has_owner = owner
            .iter()
            .map(|&node| u32::from(node != INVALID))
            .collect::<Vec<_>>();
        let has_owner_node = (0..TEST_COUNT)
            .map(|node| u32::from(has_self_or_ancestor_node(inputs, node as u32, 2, 8, false)))
            .collect::<Vec<_>>();
        let has_strict_owner_node = (0..TEST_COUNT)
            .map(|node| u32::from(has_self_or_ancestor_node(inputs, node as u32, 2, 8, true)))
            .collect::<Vec<_>>();
        let first_child = (0..TEST_COUNT)
            .map(|node| valid_first_child(inputs, node as u32))
            .collect::<Vec<_>>();
        let next_sibling = (0..TEST_COUNT)
            .map(|node| valid_next_sibling(inputs, node as u32))
            .collect::<Vec<_>>();
        let child_previous = (0..TEST_COUNT)
            .map(|node| {
                let parent = inputs.parent[node];
                child_previous(inputs, parent, node as u32, 8)
            })
            .collect::<Vec<_>>();
        let child_at_one = (0..TEST_COUNT)
            .map(|node| child_at(inputs, node as u32, 1, 8))
            .collect::<Vec<_>>();
        let owner_child = (0..TEST_COUNT)
            .map(|node| first_child_matching(inputs, node as u32, 8, |kind| kind == KIND_OWNER))
            .collect::<Vec<_>>();
        let subtree_end = (0..TEST_COUNT)
            .map(|node| valid_subtree_end(inputs, node as u32, TEST_COUNT as u32))
            .collect::<Vec<_>>();
        let contains_root = (0..TEST_COUNT)
            .map(|node| u32::from(tree_contains(inputs, 0, node as u32, TEST_COUNT as u32)))
            .collect::<Vec<_>>();
        let preorder_next = (0..TEST_COUNT)
            .map(|node| {
                let root = if node < 12 {
                    0
                } else if node < 15 {
                    12
                } else {
                    15
                };
                next_preorder_within(inputs, root, node as u32, 8)
            })
            .collect::<Vec<_>>();
        let preorder_first_owner = (0..TEST_COUNT)
            .map(|node| {
                let root = if node < 12 {
                    0
                } else if node < 15 {
                    12
                } else {
                    15
                };
                first_preorder_matching(inputs, root, 8, |kind| kind == KIND_OWNER)
            })
            .collect::<Vec<_>>();
        let preorder_descendant_owner = (0..TEST_COUNT)
            .map(|node| {
                let root = if node < 12 {
                    0
                } else if node < 15 {
                    12
                } else {
                    15
                };
                first_descendant_matching(inputs, root, 8, |kind| kind == KIND_OWNER)
            })
            .collect::<Vec<_>>();
        let preorder_owner_count = (0..TEST_COUNT)
            .map(|node| {
                let root = if node < 12 {
                    0
                } else if node < 15 {
                    12
                } else {
                    15
                };
                count_preorder_matching(inputs, root, 8, |kind| kind == KIND_OWNER)
            })
            .collect::<Vec<_>>();
        let preorder_second_owner = (0..TEST_COUNT)
            .map(|node| {
                let root = if node < 12 {
                    0
                } else if node < 15 {
                    12
                } else {
                    15
                };
                nth_preorder_matching(inputs, root, 1, 8, |kind| kind == KIND_OWNER)
            })
            .collect::<Vec<_>>();
        let preorder_owner_ordinal_before = (0..TEST_COUNT)
            .map(|node| {
                let root = if node < 12 {
                    0
                } else if node < 15 {
                    12
                } else {
                    15
                };
                matching_ordinal_before(inputs, root, node as u32, 8, |kind| kind == KIND_OWNER)
            })
            .collect::<Vec<_>>();
        let span_first_child = (0..TEST_COUNT)
            .map(|node| span_first_child(inputs, node as u32))
            .collect::<Vec<_>>();
        let span_next_sibling = (0..TEST_COUNT)
            .map(|node| span_next_sibling(inputs, node as u32))
            .collect::<Vec<_>>();
        let span_previous_sibling = (0..TEST_COUNT)
            .map(|node| span_previous_sibling(inputs, node as u32, 8))
            .collect::<Vec<_>>();
        let ancestor_before_root = (0..TEST_COUNT)
            .map(|node| find_ancestor_before(inputs, node as u32, 0, 8, |kind| kind == KIND_OWNER))
            .collect::<Vec<_>>();
        let ancestor_visit_packed = (0..TEST_COUNT)
            .flat_map(|node| {
                let (visit_count, stop_ancestor, stop_child) =
                    visit_ancestors_until(inputs, node as u32, 8, |kind| kind == KIND_ROOT);
                let keyed_before_or_until = find_ancestor_before_or_until(
                    inputs,
                    node as u32,
                    INVALID,
                    8,
                    |kind| kind == KIND_OWNER,
                    |kind| kind == KIND_ROOT,
                );
                let span_first_owner =
                    span_first_matching(inputs, node as u32, 8, |kind| kind == KIND_OWNER);
                let span_descendant_owner =
                    span_first_descendant_matching(inputs, node as u32, 8, |kind| {
                        kind == KIND_OWNER
                    });
                [
                    visit_count,
                    stop_ancestor,
                    pack_three_test_nodes(stop_child, keyed_before_or_until, span_first_owner),
                    span_descendant_owner,
                ]
            })
            .collect::<Vec<_>>();

        Self {
            owner,
            root_ancestor,
            owner_ancestor_edge_packed,
            has_owner,
            has_owner_node,
            has_strict_owner_node,
            first_child,
            next_sibling,
            child_previous,
            child_at_one,
            owner_child,
            subtree_end,
            contains_root,
            preorder_next,
            preorder_first_owner,
            preorder_descendant_owner,
            preorder_owner_count,
            preorder_second_owner,
            preorder_owner_ordinal_before,
            span_first_child,
            span_next_sibling,
            span_previous_sibling,
            ancestor_before_root,
            ancestor_visit_packed,
        }
    }
}

struct TreeWalkBuffers {
    parent: wgpu::Buffer,
    first_child: wgpu::Buffer,
    next_sibling: wgpu::Buffer,
    subtree_end: wgpu::Buffer,
    kind: wgpu::Buffer,
    owner_out: wgpu::Buffer,
    ancestor_out: wgpu::Buffer,
    keyed_ancestor_out: wgpu::Buffer,
    ancestor_edge_out: wgpu::Buffer,
    has_owner_out: wgpu::Buffer,
    has_owner_node_out: wgpu::Buffer,
    has_strict_owner_node_out: wgpu::Buffer,
    first_child_out: wgpu::Buffer,
    next_sibling_out: wgpu::Buffer,
    child_previous_out: wgpu::Buffer,
    child_at_one_out: wgpu::Buffer,
    owner_child_out: wgpu::Buffer,
    subtree_end_out: wgpu::Buffer,
    contains_root_out: wgpu::Buffer,
    preorder_next_out: wgpu::Buffer,
    preorder_first_owner_out: wgpu::Buffer,
    preorder_descendant_owner_out: wgpu::Buffer,
    preorder_owner_count_out: wgpu::Buffer,
    preorder_second_owner_out: wgpu::Buffer,
    preorder_owner_ordinal_before_out: wgpu::Buffer,
    span_first_child_out: wgpu::Buffer,
    span_next_sibling_out: wgpu::Buffer,
    span_previous_sibling_out: wgpu::Buffer,
    ancestor_before_root_out: wgpu::Buffer,
    keyed_ancestor_before_root_out: wgpu::Buffer,
    keyed_owner_child_out: wgpu::Buffer,
    ancestor_visit_out: wgpu::Buffer,
    owner_readback: wgpu::Buffer,
    ancestor_readback: wgpu::Buffer,
    keyed_ancestor_readback: wgpu::Buffer,
    ancestor_edge_readback: wgpu::Buffer,
    has_owner_readback: wgpu::Buffer,
    has_owner_node_readback: wgpu::Buffer,
    has_strict_owner_node_readback: wgpu::Buffer,
    first_child_readback: wgpu::Buffer,
    next_sibling_readback: wgpu::Buffer,
    child_previous_readback: wgpu::Buffer,
    child_at_one_readback: wgpu::Buffer,
    owner_child_readback: wgpu::Buffer,
    subtree_end_readback: wgpu::Buffer,
    contains_root_readback: wgpu::Buffer,
    preorder_next_readback: wgpu::Buffer,
    preorder_first_owner_readback: wgpu::Buffer,
    preorder_descendant_owner_readback: wgpu::Buffer,
    preorder_owner_count_readback: wgpu::Buffer,
    preorder_second_owner_readback: wgpu::Buffer,
    preorder_owner_ordinal_before_readback: wgpu::Buffer,
    span_first_child_readback: wgpu::Buffer,
    span_next_sibling_readback: wgpu::Buffer,
    span_previous_sibling_readback: wgpu::Buffer,
    ancestor_before_root_readback: wgpu::Buffer,
    keyed_ancestor_before_root_readback: wgpu::Buffer,
    keyed_owner_child_readback: wgpu::Buffer,
    ancestor_visit_readback: wgpu::Buffer,
}

impl TreeWalkBuffers {
    fn new(device: &wgpu::Device, inputs: &TreeWalkInputs) -> Self {
        Self {
            parent: input_buffer(device, "parent", &inputs.parent),
            first_child: input_buffer(device, "first_child", &inputs.first_child),
            next_sibling: input_buffer(device, "next_sibling", &inputs.next_sibling),
            subtree_end: input_buffer(device, "subtree_end", &inputs.subtree_end),
            kind: input_buffer(device, "kind", &inputs.kind),
            owner_out: output_buffer(device, "owner_out", TEST_COUNT),
            ancestor_out: output_buffer(device, "ancestor_out", TEST_COUNT),
            keyed_ancestor_out: output_buffer(device, "keyed_ancestor_out", TEST_COUNT),
            ancestor_edge_out: output_buffer(device, "ancestor_edge_out", TEST_COUNT * 4),
            has_owner_out: output_buffer(device, "has_owner_out", TEST_COUNT),
            has_owner_node_out: output_buffer(device, "has_owner_node_out", TEST_COUNT),
            has_strict_owner_node_out: output_buffer(
                device,
                "has_strict_owner_node_out",
                TEST_COUNT,
            ),
            first_child_out: output_buffer(device, "first_child_out", TEST_COUNT),
            next_sibling_out: output_buffer(device, "next_sibling_out", TEST_COUNT),
            child_previous_out: output_buffer(device, "child_previous_out", TEST_COUNT),
            child_at_one_out: output_buffer(device, "child_at_one_out", TEST_COUNT),
            owner_child_out: output_buffer(device, "owner_child_out", TEST_COUNT),
            subtree_end_out: output_buffer(device, "subtree_end_out", TEST_COUNT),
            contains_root_out: output_buffer(device, "contains_root_out", TEST_COUNT),
            preorder_next_out: output_buffer(device, "preorder_next_out", TEST_COUNT),
            preorder_first_owner_out: output_buffer(device, "preorder_first_owner_out", TEST_COUNT),
            preorder_descendant_owner_out: output_buffer(
                device,
                "preorder_descendant_owner_out",
                TEST_COUNT,
            ),
            preorder_owner_count_out: output_buffer(device, "preorder_owner_count_out", TEST_COUNT),
            preorder_second_owner_out: output_buffer(
                device,
                "preorder_second_owner_out",
                TEST_COUNT,
            ),
            preorder_owner_ordinal_before_out: output_buffer(
                device,
                "preorder_owner_ordinal_before_out",
                TEST_COUNT,
            ),
            span_first_child_out: output_buffer(device, "span_first_child_out", TEST_COUNT),
            span_next_sibling_out: output_buffer(device, "span_next_sibling_out", TEST_COUNT),
            span_previous_sibling_out: output_buffer(
                device,
                "span_previous_sibling_out",
                TEST_COUNT,
            ),
            ancestor_before_root_out: output_buffer(device, "ancestor_before_root_out", TEST_COUNT),
            keyed_ancestor_before_root_out: output_buffer(
                device,
                "keyed_ancestor_before_root_out",
                TEST_COUNT,
            ),
            keyed_owner_child_out: output_buffer(device, "keyed_owner_child_out", TEST_COUNT),
            ancestor_visit_out: output_buffer(device, "ancestor_visit_out", TEST_COUNT * 4),
            owner_readback: readback_buffer(device, "owner_readback", TEST_COUNT),
            ancestor_readback: readback_buffer(device, "ancestor_readback", TEST_COUNT),
            keyed_ancestor_readback: readback_buffer(device, "keyed_ancestor_readback", TEST_COUNT),
            ancestor_edge_readback: readback_buffer(
                device,
                "ancestor_edge_readback",
                TEST_COUNT * 4,
            ),
            has_owner_readback: readback_buffer(device, "has_owner_readback", TEST_COUNT),
            has_owner_node_readback: readback_buffer(device, "has_owner_node_readback", TEST_COUNT),
            has_strict_owner_node_readback: readback_buffer(
                device,
                "has_strict_owner_node_readback",
                TEST_COUNT,
            ),
            first_child_readback: readback_buffer(device, "first_child_readback", TEST_COUNT),
            next_sibling_readback: readback_buffer(device, "next_sibling_readback", TEST_COUNT),
            child_previous_readback: readback_buffer(device, "child_previous_readback", TEST_COUNT),
            child_at_one_readback: readback_buffer(device, "child_at_one_readback", TEST_COUNT),
            owner_child_readback: readback_buffer(device, "owner_child_readback", TEST_COUNT),
            subtree_end_readback: readback_buffer(device, "subtree_end_readback", TEST_COUNT),
            contains_root_readback: readback_buffer(device, "contains_root_readback", TEST_COUNT),
            preorder_next_readback: readback_buffer(device, "preorder_next_readback", TEST_COUNT),
            preorder_first_owner_readback: readback_buffer(
                device,
                "preorder_first_owner_readback",
                TEST_COUNT,
            ),
            preorder_descendant_owner_readback: readback_buffer(
                device,
                "preorder_descendant_owner_readback",
                TEST_COUNT,
            ),
            preorder_owner_count_readback: readback_buffer(
                device,
                "preorder_owner_count_readback",
                TEST_COUNT,
            ),
            preorder_second_owner_readback: readback_buffer(
                device,
                "preorder_second_owner_readback",
                TEST_COUNT,
            ),
            preorder_owner_ordinal_before_readback: readback_buffer(
                device,
                "preorder_owner_ordinal_before_readback",
                TEST_COUNT,
            ),
            span_first_child_readback: readback_buffer(
                device,
                "span_first_child_readback",
                TEST_COUNT,
            ),
            span_next_sibling_readback: readback_buffer(
                device,
                "span_next_sibling_readback",
                TEST_COUNT,
            ),
            span_previous_sibling_readback: readback_buffer(
                device,
                "span_previous_sibling_readback",
                TEST_COUNT,
            ),
            ancestor_before_root_readback: readback_buffer(
                device,
                "ancestor_before_root_readback",
                TEST_COUNT,
            ),
            keyed_ancestor_before_root_readback: readback_buffer(
                device,
                "keyed_ancestor_before_root_readback",
                TEST_COUNT,
            ),
            keyed_owner_child_readback: readback_buffer(
                device,
                "keyed_owner_child_readback",
                TEST_COUNT,
            ),
            ancestor_visit_readback: readback_buffer(
                device,
                "ancestor_visit_readback",
                TEST_COUNT * 4,
            ),
        }
    }

    fn bindings(&self) -> Vec<(&'static str, wgpu::BindingResource<'_>)> {
        vec![
            ("parent_in", self.parent.as_entire_binding()),
            ("first_child_in", self.first_child.as_entire_binding()),
            ("next_sibling_in", self.next_sibling.as_entire_binding()),
            ("subtree_end_in", self.subtree_end.as_entire_binding()),
            ("kind", self.kind.as_entire_binding()),
            ("owner_out", self.owner_out.as_entire_binding()),
            ("ancestor_out", self.ancestor_out.as_entire_binding()),
            (
                "keyed_ancestor_out",
                self.keyed_ancestor_out.as_entire_binding(),
            ),
            (
                "ancestor_edge_out",
                self.ancestor_edge_out.as_entire_binding(),
            ),
            ("has_owner_out", self.has_owner_out.as_entire_binding()),
            (
                "has_owner_node_out",
                self.has_owner_node_out.as_entire_binding(),
            ),
            (
                "has_strict_owner_node_out",
                self.has_strict_owner_node_out.as_entire_binding(),
            ),
            ("first_child_out", self.first_child_out.as_entire_binding()),
            (
                "next_sibling_out",
                self.next_sibling_out.as_entire_binding(),
            ),
            (
                "child_previous_out",
                self.child_previous_out.as_entire_binding(),
            ),
            (
                "child_at_one_out",
                self.child_at_one_out.as_entire_binding(),
            ),
            ("owner_child_out", self.owner_child_out.as_entire_binding()),
            ("subtree_end_out", self.subtree_end_out.as_entire_binding()),
            (
                "contains_root_out",
                self.contains_root_out.as_entire_binding(),
            ),
            (
                "preorder_next_out",
                self.preorder_next_out.as_entire_binding(),
            ),
            (
                "preorder_first_owner_out",
                self.preorder_first_owner_out.as_entire_binding(),
            ),
            (
                "preorder_descendant_owner_out",
                self.preorder_descendant_owner_out.as_entire_binding(),
            ),
            (
                "preorder_owner_count_out",
                self.preorder_owner_count_out.as_entire_binding(),
            ),
            (
                "preorder_second_owner_out",
                self.preorder_second_owner_out.as_entire_binding(),
            ),
            (
                "preorder_owner_ordinal_before_out",
                self.preorder_owner_ordinal_before_out.as_entire_binding(),
            ),
            (
                "span_first_child_out",
                self.span_first_child_out.as_entire_binding(),
            ),
            (
                "span_next_sibling_out",
                self.span_next_sibling_out.as_entire_binding(),
            ),
            (
                "span_previous_sibling_out",
                self.span_previous_sibling_out.as_entire_binding(),
            ),
            (
                "ancestor_before_root_out",
                self.ancestor_before_root_out.as_entire_binding(),
            ),
            (
                "keyed_ancestor_before_root_out",
                self.keyed_ancestor_before_root_out.as_entire_binding(),
            ),
            (
                "keyed_owner_child_out",
                self.keyed_owner_child_out.as_entire_binding(),
            ),
            (
                "ancestor_visit_out",
                self.ancestor_visit_out.as_entire_binding(),
            ),
        ]
    }
}

fn valid_node(node: u32) -> bool {
    node != INVALID && (node as usize) < TEST_COUNT
}

fn find_self_or_ancestor(
    inputs: &TreeWalkInputs,
    node: u32,
    max_steps: usize,
    predicate: impl Fn(u32) -> bool,
) -> u32 {
    if !valid_node(node) {
        return INVALID;
    }

    let mut cur = node;
    for _ in 0..max_steps {
        if predicate(inputs.kind[cur as usize]) {
            return cur;
        }
        let parent = inputs.parent[cur as usize];
        if !valid_node(parent) || parent == cur {
            return INVALID;
        }
        cur = parent;
    }
    INVALID
}

fn has_self_or_ancestor_node(
    inputs: &TreeWalkInputs,
    node: u32,
    ancestor: u32,
    max_steps: usize,
    strict: bool,
) -> bool {
    if !valid_node(node) || !valid_node(ancestor) {
        return false;
    }

    let mut cur = if strict {
        let parent = inputs.parent[node as usize];
        if !valid_node(parent) || parent == node {
            return false;
        }
        parent
    } else {
        node
    };

    for _ in 0..max_steps {
        if cur == ancestor {
            return true;
        }
        let parent = inputs.parent[cur as usize];
        if !valid_node(parent) || parent == cur {
            return false;
        }
        cur = parent;
    }
    false
}

fn find_ancestor_before(
    inputs: &TreeWalkInputs,
    node: u32,
    stop: u32,
    max_steps: usize,
    predicate: impl Fn(u32) -> bool,
) -> u32 {
    if !valid_node(node) {
        return INVALID;
    }
    let mut cur = inputs.parent[node as usize];
    if !valid_node(cur) || cur == node {
        return INVALID;
    }
    for _ in 0..max_steps {
        if !valid_node(cur) || cur == stop {
            return INVALID;
        }
        if predicate(inputs.kind[cur as usize]) {
            return cur;
        }
        let parent = inputs.parent[cur as usize];
        if !valid_node(parent) || parent == cur {
            return INVALID;
        }
        cur = parent;
    }
    INVALID
}

fn find_ancestor_before_or_until(
    inputs: &TreeWalkInputs,
    node: u32,
    stop: u32,
    max_steps: usize,
    predicate: impl Fn(u32) -> bool,
    stop_predicate: impl Fn(u32) -> bool,
) -> u32 {
    if !valid_node(node) {
        return INVALID;
    }
    let mut cur = inputs.parent[node as usize];
    if !valid_node(cur) || cur == node {
        return INVALID;
    }
    for _ in 0..max_steps {
        if !valid_node(cur) || cur == stop || stop_predicate(inputs.kind[cur as usize]) {
            return INVALID;
        }
        if predicate(inputs.kind[cur as usize]) {
            return cur;
        }
        let parent = inputs.parent[cur as usize];
        if !valid_node(parent) || parent == cur {
            return INVALID;
        }
        cur = parent;
    }
    INVALID
}

fn visit_ancestors_until(
    inputs: &TreeWalkInputs,
    node: u32,
    max_steps: usize,
    stop_predicate: impl Fn(u32) -> bool,
) -> (u32, u32, u32) {
    if !valid_node(node) {
        return (0, INVALID, INVALID);
    }
    let mut cur = node;
    let mut visit_count = 0;
    for _ in 0..max_steps {
        let parent = inputs.parent[cur as usize];
        if !valid_node(parent) || parent == cur {
            return (visit_count, INVALID, INVALID);
        }
        if stop_predicate(inputs.kind[parent as usize]) {
            return (visit_count, parent, cur);
        }
        visit_count += 1;
        cur = parent;
    }
    (visit_count, INVALID, INVALID)
}

fn pack_test_node(node: u32) -> u32 {
    if node == INVALID { 255 } else { node }
}

fn pack_three_test_nodes(a: u32, b: u32, c: u32) -> u32 {
    pack_test_node(a) | (pack_test_node(b) << 8) | (pack_test_node(c) << 16)
}

fn span_first_matching(
    inputs: &TreeWalkInputs,
    root: u32,
    max_steps: usize,
    predicate: impl Fn(u32) -> bool,
) -> u32 {
    if !valid_node(root) {
        return INVALID;
    }
    let end = inputs.subtree_end[root as usize];
    if end <= root {
        return INVALID;
    }
    let mut cur = root;
    for _ in 0..max_steps {
        if cur >= end {
            break;
        }
        if !valid_node(cur) {
            return INVALID;
        }
        if predicate(inputs.kind[cur as usize]) {
            return cur;
        }
        cur += 1;
    }
    INVALID
}

fn span_first_descendant_matching(
    inputs: &TreeWalkInputs,
    root: u32,
    max_steps: usize,
    predicate: impl Fn(u32) -> bool,
) -> u32 {
    if !valid_node(root) {
        return INVALID;
    }
    let child = root + 1;
    if !valid_node(child) || inputs.parent[child as usize] != root {
        return INVALID;
    }
    span_first_matching(inputs, child, max_steps, predicate)
}

fn find_ancestor_edge(
    inputs: &TreeWalkInputs,
    node: u32,
    max_steps: usize,
    predicate: impl Fn(u32) -> bool,
) -> (u32, u32) {
    if !valid_node(node) {
        return (INVALID, INVALID);
    }

    let mut cur = node;
    for _ in 0..max_steps {
        let parent = inputs.parent[cur as usize];
        if !valid_node(parent) || parent == cur {
            return (INVALID, INVALID);
        }
        if predicate(inputs.kind[parent as usize]) {
            return (parent, cur);
        }
        cur = parent;
    }
    (INVALID, INVALID)
}

fn valid_first_child(inputs: &TreeWalkInputs, node: u32) -> u32 {
    if !valid_node(node) {
        return INVALID;
    }
    let child = inputs.first_child[node as usize];
    if valid_node(child) && inputs.parent[child as usize] == node {
        child
    } else {
        INVALID
    }
}

fn valid_next_sibling(inputs: &TreeWalkInputs, node: u32) -> u32 {
    if !valid_node(node) {
        return INVALID;
    }
    let parent = inputs.parent[node as usize];
    let sibling = inputs.next_sibling[node as usize];
    if valid_node(parent) && valid_node(sibling) && inputs.parent[sibling as usize] == parent {
        sibling
    } else {
        INVALID
    }
}

fn child_at(inputs: &TreeWalkInputs, node: u32, ordinal: usize, max_siblings: usize) -> u32 {
    let mut child = valid_first_child(inputs, node);
    if child == INVALID {
        return INVALID;
    }
    for step in 0..max_siblings {
        if step == ordinal {
            return child;
        }
        child = valid_next_sibling(inputs, child);
        if child == INVALID {
            return INVALID;
        }
    }
    INVALID
}

fn child_previous(inputs: &TreeWalkInputs, parent: u32, node: u32, max_siblings: usize) -> u32 {
    if !valid_node(parent) || !valid_node(node) {
        return INVALID;
    }

    let mut previous = INVALID;
    let mut child = valid_first_child(inputs, parent);
    for _ in 0..max_siblings {
        if child == INVALID {
            break;
        }
        if child == node {
            return previous;
        }
        previous = child;
        child = valid_next_sibling(inputs, child);
    }
    INVALID
}

fn first_child_matching(
    inputs: &TreeWalkInputs,
    node: u32,
    max_siblings: usize,
    predicate: impl Fn(u32) -> bool,
) -> u32 {
    let mut child = valid_first_child(inputs, node);
    for _ in 0..max_siblings {
        if child == INVALID {
            return INVALID;
        }
        if predicate(inputs.kind[child as usize]) {
            return child;
        }
        child = valid_next_sibling(inputs, child);
    }
    INVALID
}

fn valid_subtree_end(inputs: &TreeWalkInputs, node: u32, node_count: u32) -> u32 {
    if !valid_node(node) {
        return INVALID;
    }
    let end = inputs.subtree_end[node as usize];
    if end > node && end <= node_count {
        end
    } else {
        INVALID
    }
}

fn tree_contains(inputs: &TreeWalkInputs, ancestor: u32, node: u32, node_count: u32) -> bool {
    let end = valid_subtree_end(inputs, ancestor, node_count);
    valid_node(node) && end != INVALID && node >= ancestor && node < end
}

fn next_preorder_within(
    inputs: &TreeWalkInputs,
    root: u32,
    node: u32,
    max_ascend_steps: usize,
) -> u32 {
    if !valid_node(root) || !valid_node(node) {
        return INVALID;
    }

    let child = inputs.first_child[node as usize];
    if valid_node(child) {
        return child;
    }

    let mut cur = node;
    for _ in 0..max_ascend_steps {
        if cur == root {
            return INVALID;
        }
        let sibling = inputs.next_sibling[cur as usize];
        if valid_node(sibling) {
            return sibling;
        }
        let parent = inputs.parent[cur as usize];
        if !valid_node(parent) || parent == cur {
            return INVALID;
        }
        cur = parent;
    }
    INVALID
}

fn first_preorder_matching(
    inputs: &TreeWalkInputs,
    root: u32,
    max_steps: usize,
    predicate: impl Fn(u32) -> bool,
) -> u32 {
    if !valid_node(root) {
        return INVALID;
    }

    let mut cur = root;
    for _ in 0..max_steps {
        if predicate(inputs.kind[cur as usize]) {
            return cur;
        }
        cur = next_preorder_within(inputs, root, cur, max_steps);
        if cur == INVALID {
            return INVALID;
        }
    }
    INVALID
}

fn first_descendant_matching(
    inputs: &TreeWalkInputs,
    root: u32,
    max_steps: usize,
    predicate: impl Fn(u32) -> bool,
) -> u32 {
    let mut cur = valid_first_child(inputs, root);
    for _ in 0..max_steps {
        if cur == INVALID {
            return INVALID;
        }
        if predicate(inputs.kind[cur as usize]) {
            return cur;
        }
        cur = next_preorder_within(inputs, root, cur, max_steps);
    }
    INVALID
}

fn count_preorder_matching(
    inputs: &TreeWalkInputs,
    root: u32,
    max_steps: usize,
    predicate: impl Fn(u32) -> bool,
) -> u32 {
    if !valid_node(root) {
        return 0;
    }

    let mut count = 0;
    let mut cur = root;
    for _ in 0..max_steps {
        if predicate(inputs.kind[cur as usize]) {
            count += 1;
        }
        cur = next_preorder_within(inputs, root, cur, max_steps);
        if cur == INVALID {
            break;
        }
    }
    count
}

fn nth_preorder_matching(
    inputs: &TreeWalkInputs,
    root: u32,
    ordinal: u32,
    max_steps: usize,
    predicate: impl Fn(u32) -> bool,
) -> u32 {
    if !valid_node(root) {
        return INVALID;
    }

    let mut seen = 0;
    let mut cur = root;
    for _ in 0..max_steps {
        if predicate(inputs.kind[cur as usize]) {
            if seen == ordinal {
                return cur;
            }
            seen += 1;
        }
        cur = next_preorder_within(inputs, root, cur, max_steps);
        if cur == INVALID {
            break;
        }
    }
    INVALID
}

fn matching_ordinal_before(
    inputs: &TreeWalkInputs,
    root: u32,
    target: u32,
    max_steps: usize,
    predicate: impl Fn(u32) -> bool,
) -> u32 {
    if !valid_node(root) || !valid_node(target) {
        return INVALID;
    }

    let mut ordinal = 0;
    let mut cur = root;
    for _ in 0..max_steps {
        if cur == target {
            return ordinal;
        }
        if predicate(inputs.kind[cur as usize]) {
            ordinal += 1;
        }
        cur = next_preorder_within(inputs, root, cur, max_steps);
        if cur == INVALID {
            break;
        }
    }
    INVALID
}

fn span_first_child(inputs: &TreeWalkInputs, node: u32) -> u32 {
    if !valid_node(node) {
        return INVALID;
    }
    let child = node + 1;
    if valid_node(child) && inputs.parent[child as usize] == node {
        child
    } else {
        INVALID
    }
}

fn span_next_sibling(inputs: &TreeWalkInputs, node: u32) -> u32 {
    if !valid_node(node) {
        return INVALID;
    }
    let parent = inputs.parent[node as usize];
    let sibling = inputs.subtree_end[node as usize];
    if valid_node(parent) && valid_node(sibling) && inputs.parent[sibling as usize] == parent {
        sibling
    } else {
        INVALID
    }
}

fn span_previous_sibling(inputs: &TreeWalkInputs, node: u32, max_siblings: usize) -> u32 {
    if !valid_node(node) {
        return INVALID;
    }
    let parent = inputs.parent[node as usize];
    if !valid_node(parent) {
        return INVALID;
    }
    let mut child = span_first_child(inputs, parent);
    let mut previous = INVALID;
    for _ in 0..max_siblings {
        if !valid_node(child) || inputs.parent[child as usize] != parent || child >= node {
            break;
        }
        previous = child;
        child = span_next_sibling(inputs, child);
    }
    previous
}

fn compile_validation_shader(root: &Path) -> (Vec<u8>, Vec<u8>) {
    let slangc = slangc_command();
    let shader = root.join("tests/shaders/gpu_tree_walk_validate.slang");
    let spv = common::TempArtifact::new("laniusc_gpu_tree_walk", "validate", Some("spv"));
    let reflection =
        common::TempArtifact::new("laniusc_gpu_tree_walk", "validate", Some("reflect.json"));
    let output = Command::new(&slangc)
        .arg("-target")
        .arg("spirv")
        .arg("-profile")
        .arg("glsl_450")
        .arg("-fvk-use-entrypoint-name")
        .arg("-reflection-json")
        .arg(reflection.path())
        .arg("-emit-spirv-directly")
        .arg("-O1")
        .arg("-I")
        .arg(root.join("shaders"))
        .arg("-o")
        .arg(spv.path())
        .arg(&shader)
        .output()
        .unwrap_or_else(|err| panic!("run slangc for {}: {err}", shader.display()));
    common::assert_command_success("compile GPU tree-walk validation shader", &output);
    (
        fs::read(spv.path()).unwrap_or_else(|err| panic!("read {}: {err}", spv.path().display())),
        fs::read(reflection.path())
            .unwrap_or_else(|err| panic!("read {}: {err}", reflection.path().display())),
    )
}

fn slangc_command() -> PathBuf {
    if let Some(path) = env::var_os("SLANGC") {
        return PathBuf::from(path);
    }
    PathBuf::from("slangc")
}

fn input_buffer(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &u32_bytes(words),
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
    })
}

fn output_buffer(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count * 4) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    })
}

fn readback_buffer(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count * 4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}

fn copy_to_readback(encoder: &mut wgpu::CommandEncoder, src: &wgpu::Buffer, dst: &wgpu::Buffer) {
    encoder.copy_buffer_to_buffer(src, 0, dst, 0, dst.size());
}

fn read_u32s(device: &wgpu::Device, buffer: &wgpu::Buffer, count: usize) -> Vec<u32> {
    let slice = buffer.slice(..);
    let (tx, rx) = mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |result| {
        tx.send(result).expect("send map result");
    });
    device
        .poll(wgpu::PollType::wait_indefinitely())
        .expect("poll readback");
    rx.recv()
        .expect("receive map result")
        .expect("map readback");
    let data = slice.get_mapped_range();
    let words = data[..count * 4]
        .chunks_exact(4)
        .map(|bytes| u32::from_le_bytes(bytes.try_into().expect("u32 bytes")))
        .collect::<Vec<_>>();
    drop(data);
    buffer.unmap();
    words
}

fn leak_bytes(bytes: Vec<u8>) -> &'static [u8] {
    Box::leak(bytes.into_boxed_slice())
}

fn u32_bytes(words: &[u32]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(words.len() * 4);
    for word in words {
        bytes.extend_from_slice(&word.to_le_bytes());
    }
    bytes
}
