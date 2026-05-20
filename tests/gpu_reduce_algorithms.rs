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

const TEST_COUNT: usize = 256;
const TREE_STRIDE: usize = 128;
const GROUP_OUT_COUNT: usize = 13;
const INVALID: u32 = 0xffff_ffff;

#[test]
fn generic_gpu_reduce_helpers_match_cpu_oracles() {
    common::block_on_gpu_with_timeout("generic GPU reduce helper validation", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_validation_shader(&root);

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.gpu_reduce.validate",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create reduce validation pass");

        let inputs = ReduceInputs::new();
        let expected = ReduceExpected::from_inputs(&inputs);
        let buffers = ReduceBuffers::new(device, &inputs);
        let bindings = buffers.bindings();
        let resources = bindings
            .iter()
            .map(|(name, resource)| ((*name).to_string(), resource.clone()))
            .collect::<HashMap<_, _>>();
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.gpu_reduce.validate.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )
        .expect("create reduce validation bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.gpu_reduce.validate.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.gpu_reduce.validate.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        copy_to_readback(&mut encoder, &buffers.group_out, &buffers.group_readback);
        copy_to_readback(&mut encoder, &buffers.tree_out, &buffers.tree_readback);
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &buffers.group_readback, GROUP_OUT_COUNT),
            expected.group,
            "group reductions should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.tree_readback, TREE_STRIDE),
            expected.tree,
            "pairwise reduction-tree step should match CPU oracle"
        );
    });
}

struct ReduceInputs {
    values: Vec<u32>,
    keys: Vec<u32>,
    active_flags: Vec<u32>,
}

impl ReduceInputs {
    fn new() -> Self {
        Self {
            values: (0..TEST_COUNT)
                .map(|i| ((i as u32 * 37 + 11) % 97) + 1)
                .collect(),
            keys: (0..TEST_COUNT)
                .map(|i| ((i as u32 * 19 + 5) % 31) + 1)
                .collect(),
            active_flags: (0..TEST_COUNT)
                .map(|i| u32::from(i % 7 != 0 && (i * 3 + 1) % 11 != 0))
                .collect(),
        }
    }
}

struct ReduceExpected {
    group: Vec<u32>,
    tree: Vec<u32>,
}

impl ReduceExpected {
    fn from_inputs(inputs: &ReduceInputs) -> Self {
        let sum = inputs.values.iter().copied().sum();
        let max_value = inputs.values.iter().copied().max().unwrap_or(0);
        let min_value = inputs.values.iter().copied().min().unwrap_or(INVALID);
        let active_sum = inputs
            .values
            .iter()
            .zip(&inputs.active_flags)
            .filter_map(|(&value, &active)| (active != 0).then_some(value))
            .sum();
        let min_pair = active_pairs(inputs)
            .min_by_key(|&(key, value)| (key, value))
            .unwrap_or((INVALID, INVALID));
        let max_pair = active_pairs(inputs)
            .max_by(|left, right| left.0.cmp(&right.0).then_with(|| right.1.cmp(&left.1)))
            .unwrap_or((0, INVALID));
        let tree = (0..TREE_STRIDE)
            .map(|i| inputs.values[i] + inputs.values[i + TREE_STRIDE])
            .collect();

        Self {
            group: vec![
                sum, max_value, min_value, active_sum, min_pair.0, min_pair.1, max_pair.0,
                max_pair.1, 128, 128, 129, 1, 0,
            ],
            tree,
        }
    }
}

struct ReduceBuffers {
    values: wgpu::Buffer,
    keys: wgpu::Buffer,
    active_flags: wgpu::Buffer,
    group_out: wgpu::Buffer,
    tree_out: wgpu::Buffer,
    group_readback: wgpu::Buffer,
    tree_readback: wgpu::Buffer,
}

impl ReduceBuffers {
    fn new(device: &wgpu::Device, inputs: &ReduceInputs) -> Self {
        Self {
            values: input_buffer(device, "values", &inputs.values),
            keys: input_buffer(device, "keys", &inputs.keys),
            active_flags: input_buffer(device, "active_flags", &inputs.active_flags),
            group_out: output_buffer(device, "group_out", GROUP_OUT_COUNT),
            tree_out: output_buffer(device, "tree_out", TREE_STRIDE),
            group_readback: readback_buffer(device, "group_readback", GROUP_OUT_COUNT),
            tree_readback: readback_buffer(device, "tree_readback", TREE_STRIDE),
        }
    }

    fn bindings(&self) -> Vec<(&'static str, wgpu::BindingResource<'_>)> {
        vec![
            ("values", self.values.as_entire_binding()),
            ("keys", self.keys.as_entire_binding()),
            ("active_flags", self.active_flags.as_entire_binding()),
            ("group_out", self.group_out.as_entire_binding()),
            ("tree_out", self.tree_out.as_entire_binding()),
        ]
    }
}

fn active_pairs(inputs: &ReduceInputs) -> impl Iterator<Item = (u32, u32)> + '_ {
    inputs
        .keys
        .iter()
        .copied()
        .zip(inputs.values.iter().copied())
        .zip(inputs.active_flags.iter().copied())
        .filter_map(|((key, value), active)| (active != 0).then_some((key, value)))
}

fn compile_validation_shader(root: &Path) -> (Vec<u8>, Vec<u8>) {
    let slangc = slangc_command();
    let shader = root.join("tests/shaders/gpu_reduce_validate.slang");
    let spv = common::TempArtifact::new("laniusc_gpu_reduce", "validate", Some("spv"));
    let reflection =
        common::TempArtifact::new("laniusc_gpu_reduce", "validate", Some("reflect.json"));
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
    common::assert_command_success("compile GPU reduce validation shader", &output);
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
