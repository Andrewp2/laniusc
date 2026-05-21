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
const PAIR_WORDS: usize = 4;

#[test]
fn generic_gpu_segmented_helpers_match_test_only_cpu_oracles() {
    common::block_on_gpu_with_timeout("generic GPU segmented helper validation", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_validation_shader(&root);

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.gpu_segmented.validate",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create segmented validation pass");

        let inputs = SegmentedInputs::new();
        let expected = SegmentedExpected::from_inputs(&inputs);
        let buffers = SegmentedBuffers::new(device, &inputs);
        let bindings = buffers.bindings();
        let resources = bindings
            .iter()
            .map(|(name, resource)| ((*name).to_string(), resource.clone()))
            .collect::<HashMap<_, _>>();
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.gpu_segmented.validate.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )
        .expect("create segmented validation bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.gpu_segmented.validate.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.gpu_segmented.validate.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        copy_to_readback(
            &mut encoder,
            &buffers.inclusive_out,
            &buffers.inclusive_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.exclusive_out,
            &buffers.exclusive_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.direct_exclusive_out,
            &buffers.direct_exclusive_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.active_inclusive_out,
            &buffers.active_inclusive_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.active_exclusive_out,
            &buffers.active_exclusive_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.tail_total_out,
            &buffers.tail_total_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.tail_flag_out,
            &buffers.tail_flag_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.inactive_tail_flag_out,
            &buffers.inactive_tail_flag_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.pair_prefix_out,
            &buffers.pair_prefix_readback,
        );
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &buffers.inclusive_readback, TEST_COUNT),
            expected.inclusive,
            "segmented inclusive prefixes should match test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.exclusive_readback, TEST_COUNT),
            expected.exclusive,
            "segmented exclusive prefixes should match test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.direct_exclusive_readback, TEST_COUNT),
            expected.exclusive,
            "segmented_scan_exclusive wrapper should match prefix helper"
        );
        assert_eq!(
            read_u32s(device, &buffers.active_inclusive_readback, TEST_COUNT),
            expected.active_inclusive,
            "segmented active-count inclusive prefixes should match test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.active_exclusive_readback, TEST_COUNT),
            expected.active_exclusive,
            "segmented active-count exclusive prefixes should match test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.tail_total_readback, TEST_COUNT),
            expected.tail_total,
            "segment tail totals should be emitted only on segment tails"
        );
        assert_eq!(
            read_u32s(device, &buffers.tail_flag_readback, TEST_COUNT),
            expected.tail_flag,
            "segment tail predicate should match test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.inactive_tail_flag_readback, TEST_COUNT),
            expected.inactive_tail_flag,
            "segment tail predicate should reject inactive lanes"
        );
        assert_eq!(
            read_u32s(
                device,
                &buffers.pair_prefix_readback,
                TEST_COUNT * PAIR_WORDS
            ),
            expected.pair_prefix,
            "generic uint2 segmented prefixes should match test-only CPU oracle"
        );
    });
}

struct SegmentedInputs {
    values: Vec<u32>,
    segment_heads: Vec<u32>,
    active_flags: Vec<u32>,
}

impl SegmentedInputs {
    fn new() -> Self {
        let values = (0..TEST_COUNT)
            .map(|i| ((i as u32 * 23 + 7) % 19) + 1)
            .collect::<Vec<_>>();
        let mut segment_heads = (0..TEST_COUNT)
            .map(|i| {
                let x = i as u32;
                u32::from(i == 0 || x % 17 == 0 || (x * 11 + 5) % 37 == 0)
            })
            .collect::<Vec<_>>();
        segment_heads[0] = 1;
        let active_flags = (0..TEST_COUNT)
            .map(|i| u32::from(i % 5 != 0 && (i * 7 + 3) % 13 != 0))
            .collect::<Vec<_>>();
        Self {
            values,
            segment_heads,
            active_flags,
        }
    }
}

struct SegmentedExpected {
    inclusive: Vec<u32>,
    exclusive: Vec<u32>,
    active_inclusive: Vec<u32>,
    active_exclusive: Vec<u32>,
    tail_total: Vec<u32>,
    tail_flag: Vec<u32>,
    inactive_tail_flag: Vec<u32>,
    pair_prefix: Vec<u32>,
}

impl SegmentedExpected {
    fn from_inputs(inputs: &SegmentedInputs) -> Self {
        let (inclusive, exclusive) =
            test_only_segmented_prefixes(&inputs.values, &inputs.segment_heads);
        let active_values = inputs
            .active_flags
            .iter()
            .map(|&flag| u32::from(flag != 0))
            .collect::<Vec<_>>();
        let (active_inclusive, active_exclusive) =
            test_only_segmented_prefixes(&active_values, &inputs.segment_heads);
        let tail_flag = test_only_tail_flags(&inputs.segment_heads, TEST_COUNT);
        let inactive_tail_flag = test_only_tail_flags(&inputs.segment_heads, TEST_COUNT - 17);
        let tail_total = inclusive
            .iter()
            .zip(&tail_flag)
            .map(|(&value, &tail)| if tail != 0 { value } else { 0 })
            .collect::<Vec<_>>();
        let pair_prefix = test_only_pair_prefixes(inputs);

        Self {
            inclusive,
            exclusive,
            active_inclusive,
            active_exclusive,
            tail_total,
            tail_flag,
            inactive_tail_flag,
            pair_prefix,
        }
    }
}

struct SegmentedBuffers {
    values: wgpu::Buffer,
    segment_heads: wgpu::Buffer,
    active_flags: wgpu::Buffer,
    inclusive_out: wgpu::Buffer,
    exclusive_out: wgpu::Buffer,
    direct_exclusive_out: wgpu::Buffer,
    active_inclusive_out: wgpu::Buffer,
    active_exclusive_out: wgpu::Buffer,
    tail_total_out: wgpu::Buffer,
    tail_flag_out: wgpu::Buffer,
    inactive_tail_flag_out: wgpu::Buffer,
    pair_prefix_out: wgpu::Buffer,
    inclusive_readback: wgpu::Buffer,
    exclusive_readback: wgpu::Buffer,
    direct_exclusive_readback: wgpu::Buffer,
    active_inclusive_readback: wgpu::Buffer,
    active_exclusive_readback: wgpu::Buffer,
    tail_total_readback: wgpu::Buffer,
    tail_flag_readback: wgpu::Buffer,
    inactive_tail_flag_readback: wgpu::Buffer,
    pair_prefix_readback: wgpu::Buffer,
}

impl SegmentedBuffers {
    fn new(device: &wgpu::Device, inputs: &SegmentedInputs) -> Self {
        Self {
            values: input_buffer(device, "values", &inputs.values),
            segment_heads: input_buffer(device, "segment_heads", &inputs.segment_heads),
            active_flags: input_buffer(device, "active_flags", &inputs.active_flags),
            inclusive_out: output_buffer(device, "inclusive_out", TEST_COUNT),
            exclusive_out: output_buffer(device, "exclusive_out", TEST_COUNT),
            direct_exclusive_out: output_buffer(device, "direct_exclusive_out", TEST_COUNT),
            active_inclusive_out: output_buffer(device, "active_inclusive_out", TEST_COUNT),
            active_exclusive_out: output_buffer(device, "active_exclusive_out", TEST_COUNT),
            tail_total_out: output_buffer(device, "tail_total_out", TEST_COUNT),
            tail_flag_out: output_buffer(device, "tail_flag_out", TEST_COUNT),
            inactive_tail_flag_out: output_buffer(device, "inactive_tail_flag_out", TEST_COUNT),
            pair_prefix_out: output_buffer(device, "pair_prefix_out", TEST_COUNT * PAIR_WORDS),
            inclusive_readback: readback_buffer(device, "inclusive_readback", TEST_COUNT),
            exclusive_readback: readback_buffer(device, "exclusive_readback", TEST_COUNT),
            direct_exclusive_readback: readback_buffer(
                device,
                "direct_exclusive_readback",
                TEST_COUNT,
            ),
            active_inclusive_readback: readback_buffer(
                device,
                "active_inclusive_readback",
                TEST_COUNT,
            ),
            active_exclusive_readback: readback_buffer(
                device,
                "active_exclusive_readback",
                TEST_COUNT,
            ),
            tail_total_readback: readback_buffer(device, "tail_total_readback", TEST_COUNT),
            tail_flag_readback: readback_buffer(device, "tail_flag_readback", TEST_COUNT),
            inactive_tail_flag_readback: readback_buffer(
                device,
                "inactive_tail_flag_readback",
                TEST_COUNT,
            ),
            pair_prefix_readback: readback_buffer(
                device,
                "pair_prefix_readback",
                TEST_COUNT * PAIR_WORDS,
            ),
        }
    }

    fn bindings(&self) -> Vec<(&'static str, wgpu::BindingResource<'_>)> {
        vec![
            ("values", self.values.as_entire_binding()),
            ("segment_heads", self.segment_heads.as_entire_binding()),
            ("active_flags", self.active_flags.as_entire_binding()),
            ("inclusive_out", self.inclusive_out.as_entire_binding()),
            ("exclusive_out", self.exclusive_out.as_entire_binding()),
            (
                "direct_exclusive_out",
                self.direct_exclusive_out.as_entire_binding(),
            ),
            (
                "active_inclusive_out",
                self.active_inclusive_out.as_entire_binding(),
            ),
            (
                "active_exclusive_out",
                self.active_exclusive_out.as_entire_binding(),
            ),
            ("tail_total_out", self.tail_total_out.as_entire_binding()),
            ("tail_flag_out", self.tail_flag_out.as_entire_binding()),
            (
                "inactive_tail_flag_out",
                self.inactive_tail_flag_out.as_entire_binding(),
            ),
            ("pair_prefix_out", self.pair_prefix_out.as_entire_binding()),
        ]
    }
}

fn test_only_segmented_prefixes(values: &[u32], segment_heads: &[u32]) -> (Vec<u32>, Vec<u32>) {
    let mut running = 0u32;
    let mut inclusive = Vec::with_capacity(values.len());
    let mut exclusive = Vec::with_capacity(values.len());
    for (&value, &head) in values.iter().zip(segment_heads) {
        if head != 0 {
            exclusive.push(0);
            running = value;
        } else {
            exclusive.push(running);
            running += value;
        }
        inclusive.push(running);
    }
    (inclusive, exclusive)
}

fn test_only_tail_flags(segment_heads: &[u32], active_count: usize) -> Vec<u32> {
    (0..TEST_COUNT)
        .map(|i| {
            u32::from(i < active_count && (i + 1 >= active_count || segment_heads[i + 1] != 0))
        })
        .collect()
}

fn test_only_pair_prefixes(inputs: &SegmentedInputs) -> Vec<u32> {
    let mut running = [0u32, 0u32];
    let mut out = Vec::with_capacity(TEST_COUNT * PAIR_WORDS);
    for i in 0..TEST_COUNT {
        let value = [
            inputs.values[i],
            inputs.values[i] * 3 + inputs.active_flags[i],
        ];
        let exclusive = if inputs.segment_heads[i] != 0 {
            [0, 0]
        } else {
            running
        };
        running = if inputs.segment_heads[i] != 0 {
            value
        } else {
            [running[0] + value[0], running[1] + value[1]]
        };
        out.extend_from_slice(&[running[0], running[1], exclusive[0], exclusive[1]]);
    }
    out
}

fn compile_validation_shader(root: &Path) -> (Vec<u8>, Vec<u8>) {
    let slangc = slangc_command();
    let shader = root.join("tests/shaders/gpu_segmented_validate.slang");
    let spv = common::TempArtifact::new("laniusc_gpu_segmented", "validate", Some("spv"));
    let reflection =
        common::TempArtifact::new("laniusc_gpu_segmented", "validate", Some("reflect.json"));
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
    common::assert_command_success("compile GPU segmented validation shader", &output);
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
