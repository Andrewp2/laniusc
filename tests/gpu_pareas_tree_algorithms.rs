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

#[test]
fn pareas_tree_bulk_primitives_match_test_only_cpu_oracles() {
    common::block_on_gpu_with_timeout("Pareas GPU tree primitive validation", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_validation_shader(&root);

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.gpu_pareas_tree.validate",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create Pareas tree validation pass");

        let inputs = PareasTreeInputs::new();
        let expected = PareasTreeExpected::from_inputs(&inputs);
        let buffers = PareasTreeBuffers::new(device, &inputs);
        let bindings = buffers.bindings();
        let resources = bindings
            .iter()
            .map(|(name, resource)| ((*name).to_string(), resource.clone()))
            .collect::<HashMap<_, _>>();
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.gpu_pareas_tree.validate.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )
        .expect("create Pareas tree validation bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.gpu_pareas_tree.validate.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.gpu_pareas_tree.validate.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        buffers.copy_outputs(&mut encoder);
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &buffers.depth_readback, TEST_COUNT),
            expected.depth,
            "Pareas compute_depths translation should match the test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.root_readback, TEST_COUNT),
            expected.root,
            "Pareas find_roots translation should match the test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.unmarked_parent_readback, TEST_COUNT),
            expected.unmarked_parent,
            "Pareas find_unmarked_parents translation should match the test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.removed_parent_readback, TEST_COUNT),
            expected.removed_parent,
            "Pareas remove_nodes translation should match the test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.match_friend_readback, TEST_COUNT),
            expected.match_friend,
            "Pareas match_lists translation should match the test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.right_leaf_readback, TEST_COUNT),
            expected.right_leaf,
            "Pareas build_right_leaf_vector translation should match the test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.left_leaf_readback, TEST_COUNT),
            expected.left_leaf,
            "Pareas build_left_leaf_vector translation should match the test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.preorder_link_readback, TEST_COUNT),
            expected.preorder_link,
            "Pareas build_preorder_ordering link translation should match the test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.postorder_inverse_link_readback, TEST_COUNT),
            expected.postorder_inverse_link,
            "Pareas build_postorder_ordering inverse-link translation should match the test-only CPU oracle"
        );
    });
}

struct PareasTreeInputs {
    parent: Vec<u32>,
    prev_sibling: Vec<u32>,
    next_sibling: Vec<u32>,
    remove_mark: Vec<u32>,
    list_link: Vec<u32>,
    friend_seed: Vec<u32>,
}

impl PareasTreeInputs {
    fn new() -> Self {
        Self {
            parent: vec![
                INVALID, 0, 0, 1, 1, 2, 2, 3, 3, INVALID, 9, 9, 10, 10, 11, 14,
            ],
            prev_sibling: vec![
                INVALID, INVALID, 1, INVALID, 3, INVALID, 5, INVALID, 7, INVALID, INVALID, 10,
                INVALID, 12, INVALID, INVALID,
            ],
            next_sibling: vec![
                INVALID, 2, INVALID, 4, INVALID, 6, INVALID, 8, INVALID, INVALID, 11, INVALID, 13,
                INVALID, INVALID, INVALID,
            ],
            remove_mark: vec![0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0],
            list_link: vec![
                INVALID, 0, 1, 2, INVALID, 4, 5, 6, INVALID, 8, 9, 10, INVALID, 12, 13, 14,
            ],
            friend_seed: vec![
                INVALID, INVALID, INVALID, 7, INVALID, INVALID, INVALID, 3, INVALID, INVALID,
                INVALID, 15, INVALID, INVALID, INVALID, INVALID,
            ],
        }
    }
}

struct PareasTreeExpected {
    depth: Vec<u32>,
    root: Vec<u32>,
    unmarked_parent: Vec<u32>,
    removed_parent: Vec<u32>,
    match_friend: Vec<u32>,
    right_leaf: Vec<u32>,
    left_leaf: Vec<u32>,
    preorder_link: Vec<u32>,
    postorder_inverse_link: Vec<u32>,
}

impl PareasTreeExpected {
    fn from_inputs(inputs: &PareasTreeInputs) -> Self {
        let depth = test_only_compute_depths(&inputs.parent);
        let root = test_only_find_roots(&inputs.parent);
        let unmarked_parent = test_only_find_unmarked_parents(&inputs.parent, &inputs.remove_mark);
        let removed_parent = unmarked_parent
            .iter()
            .enumerate()
            .map(|(node, &parent)| {
                if inputs.remove_mark[node] != 0 {
                    node as u32
                } else {
                    parent
                }
            })
            .collect::<Vec<_>>();
        let match_friend = test_only_match_lists(&inputs.list_link, &inputs.friend_seed);
        let right_leaf = test_only_right_leaf_vector(&inputs.parent, &inputs.prev_sibling);
        let left_leaf = test_only_left_leaf_vector(&inputs.parent, &inputs.prev_sibling);
        let preorder_link = inputs
            .parent
            .iter()
            .zip(&inputs.prev_sibling)
            .map(|(&parent, &prev)| {
                if valid_index(prev) {
                    right_leaf[prev as usize]
                } else {
                    parent
                }
            })
            .collect::<Vec<_>>();
        let postorder_inverse_link = inputs
            .parent
            .iter()
            .zip(&inputs.next_sibling)
            .map(|(&parent, &next)| {
                if valid_index(next) {
                    left_leaf[next as usize]
                } else {
                    parent
                }
            })
            .collect::<Vec<_>>();

        Self {
            depth,
            root,
            unmarked_parent,
            removed_parent,
            match_friend,
            right_leaf,
            left_leaf,
            preorder_link,
            postorder_inverse_link,
        }
    }
}

struct PareasTreeBuffers {
    parent_in: wgpu::Buffer,
    prev_sibling_in: wgpu::Buffer,
    next_sibling_in: wgpu::Buffer,
    remove_mark_in: wgpu::Buffer,
    list_link_in: wgpu::Buffer,
    friend_seed_in: wgpu::Buffer,
    depth_out: wgpu::Buffer,
    root_out: wgpu::Buffer,
    unmarked_parent_out: wgpu::Buffer,
    removed_parent_out: wgpu::Buffer,
    match_friend_out: wgpu::Buffer,
    right_leaf_out: wgpu::Buffer,
    left_leaf_out: wgpu::Buffer,
    preorder_link_out: wgpu::Buffer,
    postorder_inverse_link_out: wgpu::Buffer,
    depth_readback: wgpu::Buffer,
    root_readback: wgpu::Buffer,
    unmarked_parent_readback: wgpu::Buffer,
    removed_parent_readback: wgpu::Buffer,
    match_friend_readback: wgpu::Buffer,
    right_leaf_readback: wgpu::Buffer,
    left_leaf_readback: wgpu::Buffer,
    preorder_link_readback: wgpu::Buffer,
    postorder_inverse_link_readback: wgpu::Buffer,
}

impl PareasTreeBuffers {
    fn new(device: &wgpu::Device, inputs: &PareasTreeInputs) -> Self {
        Self {
            parent_in: input_buffer(device, "parent_in", &inputs.parent),
            prev_sibling_in: input_buffer(device, "prev_sibling_in", &inputs.prev_sibling),
            next_sibling_in: input_buffer(device, "next_sibling_in", &inputs.next_sibling),
            remove_mark_in: input_buffer(device, "remove_mark_in", &inputs.remove_mark),
            list_link_in: input_buffer(device, "list_link_in", &inputs.list_link),
            friend_seed_in: input_buffer(device, "friend_seed_in", &inputs.friend_seed),
            depth_out: output_buffer(device, "depth_out", TEST_COUNT),
            root_out: output_buffer(device, "root_out", TEST_COUNT),
            unmarked_parent_out: output_buffer(device, "unmarked_parent_out", TEST_COUNT),
            removed_parent_out: output_buffer(device, "removed_parent_out", TEST_COUNT),
            match_friend_out: output_buffer(device, "match_friend_out", TEST_COUNT),
            right_leaf_out: output_buffer(device, "right_leaf_out", TEST_COUNT),
            left_leaf_out: output_buffer(device, "left_leaf_out", TEST_COUNT),
            preorder_link_out: output_buffer(device, "preorder_link_out", TEST_COUNT),
            postorder_inverse_link_out: output_buffer(
                device,
                "postorder_inverse_link_out",
                TEST_COUNT,
            ),
            depth_readback: readback_buffer(device, "depth_readback", TEST_COUNT),
            root_readback: readback_buffer(device, "root_readback", TEST_COUNT),
            unmarked_parent_readback: readback_buffer(
                device,
                "unmarked_parent_readback",
                TEST_COUNT,
            ),
            removed_parent_readback: readback_buffer(device, "removed_parent_readback", TEST_COUNT),
            match_friend_readback: readback_buffer(device, "match_friend_readback", TEST_COUNT),
            right_leaf_readback: readback_buffer(device, "right_leaf_readback", TEST_COUNT),
            left_leaf_readback: readback_buffer(device, "left_leaf_readback", TEST_COUNT),
            preorder_link_readback: readback_buffer(device, "preorder_link_readback", TEST_COUNT),
            postorder_inverse_link_readback: readback_buffer(
                device,
                "postorder_inverse_link_readback",
                TEST_COUNT,
            ),
        }
    }

    fn bindings(&self) -> [(&'static str, wgpu::BindingResource<'_>); 15] {
        [
            ("parent_in", self.parent_in.as_entire_binding()),
            ("prev_sibling_in", self.prev_sibling_in.as_entire_binding()),
            ("next_sibling_in", self.next_sibling_in.as_entire_binding()),
            ("remove_mark_in", self.remove_mark_in.as_entire_binding()),
            ("list_link_in", self.list_link_in.as_entire_binding()),
            ("friend_seed_in", self.friend_seed_in.as_entire_binding()),
            ("depth_out", self.depth_out.as_entire_binding()),
            ("root_out", self.root_out.as_entire_binding()),
            (
                "unmarked_parent_out",
                self.unmarked_parent_out.as_entire_binding(),
            ),
            (
                "removed_parent_out",
                self.removed_parent_out.as_entire_binding(),
            ),
            (
                "match_friend_out",
                self.match_friend_out.as_entire_binding(),
            ),
            ("right_leaf_out", self.right_leaf_out.as_entire_binding()),
            ("left_leaf_out", self.left_leaf_out.as_entire_binding()),
            (
                "preorder_link_out",
                self.preorder_link_out.as_entire_binding(),
            ),
            (
                "postorder_inverse_link_out",
                self.postorder_inverse_link_out.as_entire_binding(),
            ),
        ]
    }

    fn copy_outputs(&self, encoder: &mut wgpu::CommandEncoder) {
        copy_to_readback(encoder, &self.depth_out, &self.depth_readback);
        copy_to_readback(encoder, &self.root_out, &self.root_readback);
        copy_to_readback(
            encoder,
            &self.unmarked_parent_out,
            &self.unmarked_parent_readback,
        );
        copy_to_readback(
            encoder,
            &self.removed_parent_out,
            &self.removed_parent_readback,
        );
        copy_to_readback(encoder, &self.match_friend_out, &self.match_friend_readback);
        copy_to_readback(encoder, &self.right_leaf_out, &self.right_leaf_readback);
        copy_to_readback(encoder, &self.left_leaf_out, &self.left_leaf_readback);
        copy_to_readback(
            encoder,
            &self.preorder_link_out,
            &self.preorder_link_readback,
        );
        copy_to_readback(
            encoder,
            &self.postorder_inverse_link_out,
            &self.postorder_inverse_link_readback,
        );
    }
}

fn test_only_compute_depths(parents: &[u32]) -> Vec<u32> {
    let mut links = parents.to_vec();
    let mut depths = vec![1u32; parents.len()];
    for _ in 0..bit_width(parents.len() as u32) {
        let old_links = links.clone();
        let old_depths = depths.clone();
        for node in 0..parents.len() {
            let link = old_links[node];
            let inherited_depth = if valid_index(link) {
                old_depths[link as usize]
            } else {
                0
            };
            depths[node] = (old_depths[node] + inherited_depth).max(old_depths[node]);
            links[node] = if valid_index(link) {
                old_links[link as usize]
            } else {
                link
            };
        }
    }
    depths
        .into_iter()
        .map(|depth| depth.saturating_sub(1))
        .collect()
}

fn test_only_find_roots(initial_links: &[u32]) -> Vec<u32> {
    let mut links = initial_links.to_vec();
    for _ in 0..bit_width(initial_links.len() as u32) {
        let old_links = links.clone();
        for node in 0..initial_links.len() {
            let link = old_links[node];
            let ancestor_link = if valid_index(link) {
                old_links[link as usize]
            } else {
                INVALID
            };
            links[node] = if !valid_index(link) || !valid_index(ancestor_link) {
                link
            } else {
                ancestor_link
            };
        }
    }
    links
        .into_iter()
        .enumerate()
        .map(|(node, link)| {
            if valid_index(initial_links[node]) {
                link
            } else {
                node as u32
            }
        })
        .collect()
}

fn test_only_find_unmarked_parents(parents: &[u32], marks: &[u32]) -> Vec<u32> {
    let mut links = parents.to_vec();
    for _ in 0..bit_width(parents.len() as u32) {
        let old_links = links.clone();
        for node in 0..parents.len() {
            let link = old_links[node];
            let link_marked = valid_index(link) && marks[link as usize] != 0;
            let ancestor_link = if valid_index(link) {
                old_links[link as usize]
            } else {
                INVALID
            };
            links[node] = if !valid_index(link) || !link_marked {
                link
            } else {
                ancestor_link
            };
        }
    }
    links
}

fn test_only_match_lists(parents: &[u32], friend_seed: &[u32]) -> Vec<u32> {
    let mut links = parents.to_vec();
    let mut friends = friend_seed.to_vec();
    for _ in 0..bit_width(parents.len() as u32) {
        let old_links = links.clone();
        let old_friends = friends.clone();
        let mut next_friends = old_friends.clone();
        for node in 0..parents.len() {
            let friend = old_friends[node];
            if !valid_index(friend) {
                continue;
            }
            let scatter_index = old_links[node];
            if valid_index(scatter_index) {
                next_friends[scatter_index as usize] = old_links[friend as usize];
            }
        }
        links = old_links
            .iter()
            .map(|&link| {
                if valid_index(link) {
                    old_links[link as usize]
                } else {
                    link
                }
            })
            .collect();
        friends = next_friends;
    }
    friends
}

fn test_only_right_leaf_vector(parents: &[u32], prev_siblings: &[u32]) -> Vec<u32> {
    let mut is_last_child = vec![true; parents.len()];
    for &prev in prev_siblings {
        if valid_index(prev) {
            is_last_child[prev as usize] = false;
        }
    }
    let links = parents
        .iter()
        .zip(is_last_child)
        .map(|(&parent, last)| if last { parent } else { INVALID })
        .collect::<Vec<_>>();
    test_only_find_roots(&test_only_invert(&links))
}

fn test_only_left_leaf_vector(parents: &[u32], prev_siblings: &[u32]) -> Vec<u32> {
    let links = parents
        .iter()
        .zip(prev_siblings)
        .map(
            |(&parent, &prev)| {
                if !valid_index(prev) { parent } else { INVALID }
            },
        )
        .collect::<Vec<_>>();
    test_only_find_roots(&test_only_invert(&links))
}

fn test_only_invert(links: &[u32]) -> Vec<u32> {
    let mut inverted = vec![INVALID; links.len()];
    for (node, &link) in links.iter().enumerate() {
        if valid_index(link) {
            inverted[link as usize] = node as u32;
        }
    }
    inverted
}

fn valid_index(value: u32) -> bool {
    value != INVALID && (value as usize) < TEST_COUNT
}

fn bit_width(value: u32) -> usize {
    let mut width = 0;
    let mut v = value;
    while v != 0 {
        width += 1;
        v >>= 1;
    }
    width
}

fn compile_validation_shader(root: &Path) -> (Vec<u8>, Vec<u8>) {
    let slangc = slangc_command();
    let shader = root.join("tests/shaders/gpu_pareas_tree_validate.slang");
    let spv = common::TempArtifact::new("laniusc_gpu_pareas_tree", "validate", Some("spv"));
    let reflection =
        common::TempArtifact::new("laniusc_gpu_pareas_tree", "validate", Some("reflect.json"));
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
    common::assert_command_success("compile Pareas tree validation shader", &output);
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
