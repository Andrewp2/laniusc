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

const BLOCK_COUNT: usize = 13;
const LEAF_BASE: usize = 16;
const NODE_COUNT: usize = LEAF_BASE * 2;
const QUERY_COUNT: usize = 32;
const ROW_COUNT: usize = 49;
const ROW_BLOCK_SIZE: usize = 4;
const INVALID: u32 = 0xffff_ffff;

#[test]
fn generic_gpu_range_search_tree_queries_match_test_only_cpu_oracles() {
    common::block_on_gpu_with_timeout("generic GPU range-search tree validation", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_validation_shader(&root);

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.gpu_segment_tree.validate",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create range-search tree validation pass");

        let inputs = SegmentTreeInputs::new();
        let expected = SegmentTreeExpected::from_inputs(&inputs);
        let buffers = SegmentTreeBuffers::new(device, &inputs);
        let bindings = buffers.bindings();
        let resources = bindings
            .iter()
            .map(|(name, resource)| ((*name).to_string(), resource.clone()))
            .collect::<HashMap<_, _>>();
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.gpu_segment_tree.validate.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )
        .expect("create range-search tree validation bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.gpu_segment_tree.validate.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.gpu_segment_tree.validate.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        copy_to_readback(
            &mut encoder,
            &buffers.next_block_out,
            &buffers.next_block_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.previous_block_out,
            &buffers.previous_block_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.next_index_out,
            &buffers.next_index_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.previous_index_out,
            &buffers.previous_index_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.mask_next_block_out,
            &buffers.mask_next_block_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.mask_previous_block_out,
            &buffers.mask_previous_block_readback,
        );
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &buffers.next_block_readback, QUERY_COUNT),
            expected.next_block,
            "first range-search block at or after lo should match test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.previous_block_readback, QUERY_COUNT),
            expected.previous_block,
            "last range-search block before hi should match test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.next_index_readback, QUERY_COUNT),
            expected.next_index,
            "first range-search row index at or after lo should match test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.previous_index_readback, QUERY_COUNT),
            expected.previous_index,
            "last range-search row index before hi should match test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.mask_next_block_readback, QUERY_COUNT),
            expected.mask_next_block,
            "first bitset-intersecting block at or after lo should match test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.mask_previous_block_readback, QUERY_COUNT),
            expected.mask_previous_block,
            "last bitset-intersecting block before hi should match test-only CPU oracle"
        );
    });
}

struct SegmentTreeInputs {
    row_value: Vec<u32>,
    leaf_value: Vec<u32>,
    tree_value: Vec<u32>,
    mask_leaf_value: Vec<u32>,
    mask_tree_value: Vec<u32>,
    query_lo: Vec<u32>,
    query_hi: Vec<u32>,
    query_lo_index: Vec<u32>,
    query_hi_index: Vec<u32>,
    query_target: Vec<u32>,
    mask_query: Vec<u32>,
}

impl SegmentTreeInputs {
    fn new() -> Self {
        let row_value = (0..ROW_COUNT)
            .map(|i| ((i as u32 * 17 + 3) % 23) + ((i as u32 / 11) % 3))
            .collect::<Vec<_>>();
        let leaf_value = row_value
            .chunks(ROW_BLOCK_SIZE)
            .map(|chunk| chunk.iter().copied().max().unwrap_or(0))
            .collect::<Vec<_>>();
        let tree_value = build_max_tree_nodes(&leaf_value);
        let mask_leaf_value = (0..BLOCK_COUNT)
            .map(|i| 1u32 << ((i * 5 + 3) % 11))
            .collect::<Vec<_>>();
        let mask_tree_value = build_or_tree_nodes(&mask_leaf_value);
        let query_lo = (0..QUERY_COUNT)
            .map(|i| ((i * 5) % (BLOCK_COUNT + 4)) as u32)
            .collect::<Vec<_>>();
        let query_hi = (0..QUERY_COUNT)
            .map(|i| ((i * 7) % (BLOCK_COUNT + 4)) as u32)
            .collect::<Vec<_>>();
        let query_lo_index = (0..QUERY_COUNT)
            .map(|i| ((i * 11) % (ROW_COUNT + 9)) as u32)
            .collect::<Vec<_>>();
        let query_hi_index = (0..QUERY_COUNT)
            .map(|i| ((i * 13) % (ROW_COUNT + 9)) as u32)
            .collect::<Vec<_>>();
        let query_target = (0..QUERY_COUNT)
            .map(|i| ((i * 11) % 18) as u32)
            .collect::<Vec<_>>();
        let mask_query = (0..QUERY_COUNT)
            .map(|i| {
                let a = 1u32 << ((i * 3 + 1) % 11);
                let b = 1u32 << ((i * 7 + 4) % 11);
                a | b
            })
            .collect::<Vec<_>>();
        Self {
            row_value,
            leaf_value,
            tree_value,
            mask_leaf_value,
            mask_tree_value,
            query_lo,
            query_hi,
            query_lo_index,
            query_hi_index,
            query_target,
            mask_query,
        }
    }
}

struct SegmentTreeExpected {
    next_block: Vec<u32>,
    previous_block: Vec<u32>,
    next_index: Vec<u32>,
    previous_index: Vec<u32>,
    mask_next_block: Vec<u32>,
    mask_previous_block: Vec<u32>,
}

impl SegmentTreeExpected {
    fn from_inputs(inputs: &SegmentTreeInputs) -> Self {
        let next_block = (0..QUERY_COUNT)
            .map(|i| {
                first_block_at_or_after(
                    &inputs.leaf_value,
                    inputs.query_lo[i] as usize,
                    inputs.query_target[i],
                )
            })
            .collect::<Vec<_>>();
        let previous_block = (0..QUERY_COUNT)
            .map(|i| {
                last_block_before(
                    &inputs.leaf_value,
                    inputs.query_hi[i] as usize,
                    inputs.query_target[i],
                )
            })
            .collect::<Vec<_>>();
        let next_index = (0..QUERY_COUNT)
            .map(|i| {
                first_index_at_or_after(
                    &inputs.row_value,
                    inputs.query_lo_index[i] as usize,
                    inputs.query_target[i],
                )
            })
            .collect::<Vec<_>>();
        let previous_index = (0..QUERY_COUNT)
            .map(|i| {
                last_index_before(
                    &inputs.row_value,
                    inputs.query_hi_index[i] as usize,
                    inputs.query_target[i],
                )
            })
            .collect::<Vec<_>>();
        let mask_next_block = (0..QUERY_COUNT)
            .map(|i| {
                first_block_matching(
                    &inputs.mask_leaf_value,
                    inputs.query_lo[i] as usize,
                    |value| value & inputs.mask_query[i] != 0,
                )
            })
            .collect::<Vec<_>>();
        let mask_previous_block = (0..QUERY_COUNT)
            .map(|i| {
                last_block_matching(
                    &inputs.mask_leaf_value,
                    inputs.query_hi[i] as usize,
                    |value| value & inputs.mask_query[i] != 0,
                )
            })
            .collect::<Vec<_>>();
        Self {
            next_block,
            previous_block,
            next_index,
            previous_index,
            mask_next_block,
            mask_previous_block,
        }
    }
}

struct SegmentTreeBuffers {
    row_value: wgpu::Buffer,
    leaf_value: wgpu::Buffer,
    tree_value: wgpu::Buffer,
    mask_leaf_value: wgpu::Buffer,
    mask_tree_value: wgpu::Buffer,
    query_lo: wgpu::Buffer,
    query_hi: wgpu::Buffer,
    query_lo_index: wgpu::Buffer,
    query_hi_index: wgpu::Buffer,
    query_target: wgpu::Buffer,
    mask_query: wgpu::Buffer,
    next_block_out: wgpu::Buffer,
    previous_block_out: wgpu::Buffer,
    next_index_out: wgpu::Buffer,
    previous_index_out: wgpu::Buffer,
    mask_next_block_out: wgpu::Buffer,
    mask_previous_block_out: wgpu::Buffer,
    next_block_readback: wgpu::Buffer,
    previous_block_readback: wgpu::Buffer,
    next_index_readback: wgpu::Buffer,
    previous_index_readback: wgpu::Buffer,
    mask_next_block_readback: wgpu::Buffer,
    mask_previous_block_readback: wgpu::Buffer,
}

impl SegmentTreeBuffers {
    fn new(device: &wgpu::Device, inputs: &SegmentTreeInputs) -> Self {
        Self {
            row_value: input_buffer(device, "row_value", &inputs.row_value),
            leaf_value: input_buffer(device, "leaf_value", &inputs.leaf_value),
            tree_value: input_buffer(device, "tree_value", &inputs.tree_value),
            mask_leaf_value: input_buffer(device, "mask_leaf_value", &inputs.mask_leaf_value),
            mask_tree_value: input_buffer(device, "mask_tree_value", &inputs.mask_tree_value),
            query_lo: input_buffer(device, "query_lo", &inputs.query_lo),
            query_hi: input_buffer(device, "query_hi", &inputs.query_hi),
            query_lo_index: input_buffer(device, "query_lo_index", &inputs.query_lo_index),
            query_hi_index: input_buffer(device, "query_hi_index", &inputs.query_hi_index),
            query_target: input_buffer(device, "query_target", &inputs.query_target),
            mask_query: input_buffer(device, "mask_query", &inputs.mask_query),
            next_block_out: output_buffer(device, "next_block_out", QUERY_COUNT),
            previous_block_out: output_buffer(device, "previous_block_out", QUERY_COUNT),
            next_index_out: output_buffer(device, "next_index_out", QUERY_COUNT),
            previous_index_out: output_buffer(device, "previous_index_out", QUERY_COUNT),
            mask_next_block_out: output_buffer(device, "mask_next_block_out", QUERY_COUNT),
            mask_previous_block_out: output_buffer(device, "mask_previous_block_out", QUERY_COUNT),
            next_block_readback: readback_buffer(device, "next_block_readback", QUERY_COUNT),
            previous_block_readback: readback_buffer(
                device,
                "previous_block_readback",
                QUERY_COUNT,
            ),
            next_index_readback: readback_buffer(device, "next_index_readback", QUERY_COUNT),
            previous_index_readback: readback_buffer(
                device,
                "previous_index_readback",
                QUERY_COUNT,
            ),
            mask_next_block_readback: readback_buffer(
                device,
                "mask_next_block_readback",
                QUERY_COUNT,
            ),
            mask_previous_block_readback: readback_buffer(
                device,
                "mask_previous_block_readback",
                QUERY_COUNT,
            ),
        }
    }

    fn bindings(&self) -> Vec<(&'static str, wgpu::BindingResource<'_>)> {
        vec![
            ("row_value_in", self.row_value.as_entire_binding()),
            ("leaf_value_in", self.leaf_value.as_entire_binding()),
            ("tree_value_in", self.tree_value.as_entire_binding()),
            (
                "mask_leaf_value_in",
                self.mask_leaf_value.as_entire_binding(),
            ),
            (
                "mask_tree_value_in",
                self.mask_tree_value.as_entire_binding(),
            ),
            ("query_lo", self.query_lo.as_entire_binding()),
            ("query_hi", self.query_hi.as_entire_binding()),
            ("query_lo_index", self.query_lo_index.as_entire_binding()),
            ("query_hi_index", self.query_hi_index.as_entire_binding()),
            ("query_target", self.query_target.as_entire_binding()),
            ("mask_query", self.mask_query.as_entire_binding()),
            ("next_block_out", self.next_block_out.as_entire_binding()),
            (
                "previous_block_out",
                self.previous_block_out.as_entire_binding(),
            ),
            ("next_index_out", self.next_index_out.as_entire_binding()),
            (
                "previous_index_out",
                self.previous_index_out.as_entire_binding(),
            ),
            (
                "mask_next_block_out",
                self.mask_next_block_out.as_entire_binding(),
            ),
            (
                "mask_previous_block_out",
                self.mask_previous_block_out.as_entire_binding(),
            ),
        ]
    }
}

fn build_max_tree_nodes(leaves: &[u32]) -> Vec<u32> {
    let mut nodes = vec![0; NODE_COUNT];
    for i in 0..LEAF_BASE {
        nodes[LEAF_BASE + i] = leaves.get(i).copied().unwrap_or(0);
    }
    for node in (1..LEAF_BASE).rev() {
        nodes[node] = nodes[node * 2].max(nodes[node * 2 + 1]);
    }
    nodes
}

fn build_or_tree_nodes(leaves: &[u32]) -> Vec<u32> {
    let mut nodes = vec![0; NODE_COUNT];
    for i in 0..LEAF_BASE {
        nodes[LEAF_BASE + i] = leaves.get(i).copied().unwrap_or(0);
    }
    for node in (1..LEAF_BASE).rev() {
        nodes[node] = nodes[node * 2] | nodes[node * 2 + 1];
    }
    nodes
}

fn first_block_at_or_after(leaves: &[u32], lo: usize, target: u32) -> u32 {
    first_block_matching(leaves, lo, |value| value >= target)
}

fn last_block_before(leaves: &[u32], hi: usize, target: u32) -> u32 {
    last_block_matching(leaves, hi, |value| value >= target)
}

fn first_index_at_or_after(rows: &[u32], lo: usize, target: u32) -> u32 {
    rows.iter()
        .copied()
        .enumerate()
        .skip(lo)
        .find(|(_, value)| *value >= target)
        .map(|(index, _)| index as u32)
        .unwrap_or(INVALID)
}

fn last_index_before(rows: &[u32], hi: usize, target: u32) -> u32 {
    let end = hi.min(rows.len());
    rows[..end]
        .iter()
        .copied()
        .rposition(|value| value >= target)
        .map(|index| index as u32)
        .unwrap_or(INVALID)
}

fn first_block_matching(leaves: &[u32], lo: usize, mut predicate: impl FnMut(u32) -> bool) -> u32 {
    leaves
        .iter()
        .copied()
        .enumerate()
        .skip(lo)
        .find(|(_, value)| predicate(*value))
        .map(|(block, _)| block as u32)
        .unwrap_or(INVALID)
}

fn last_block_matching(leaves: &[u32], hi: usize, mut predicate: impl FnMut(u32) -> bool) -> u32 {
    let end = hi.min(leaves.len());
    leaves[..end]
        .iter()
        .copied()
        .rposition(|value| predicate(value))
        .map(|block| block as u32)
        .unwrap_or(INVALID)
}

fn compile_validation_shader(root: &Path) -> (Vec<u8>, Vec<u8>) {
    let slangc = slangc_command();
    let shader = root.join("tests/shaders/gpu_segment_tree_validate.slang");
    let spv = common::TempArtifact::new("laniusc_gpu_segment_tree", "validate", Some("spv"));
    let reflection =
        common::TempArtifact::new("laniusc_gpu_segment_tree", "validate", Some("reflect.json"));
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
    common::assert_command_success("compile range-search tree validation shader", &output);
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
    device.poll(wgpu::PollType::Wait).expect("poll readback");
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
