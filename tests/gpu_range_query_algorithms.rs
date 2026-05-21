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

const SORTED_COUNT: usize = 64;
const QUERY_COUNT: usize = 32;
const INVALID: u32 = 0xffff_ffff;

#[test]
fn generic_gpu_tuple_range_queries_match_test_only_cpu_oracles() {
    common::block_on_gpu_with_timeout("generic GPU tuple range query validation", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_validation_shader(&root);

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.gpu_range_query.validate",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create range-query validation pass");

        let inputs = RangeQueryInputs::new();
        let expected = RangeQueryExpected::from_inputs(&inputs);
        let buffers = RangeQueryBuffers::new(device, &inputs);
        let bindings = buffers.bindings();
        let resources = bindings
            .iter()
            .map(|(name, resource)| ((*name).to_string(), resource.clone()))
            .collect::<HashMap<_, _>>();
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.gpu_range_query.validate.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )
        .expect("create range-query validation bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.gpu_range_query.validate.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.gpu_range_query.validate.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        copy_to_readback(
            &mut encoder,
            &buffers.query2_begin_out,
            &buffers.query2_begin_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.query2_end_out,
            &buffers.query2_end_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.query2_row_out,
            &buffers.query2_row_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.query4_begin_out,
            &buffers.query4_begin_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.query4_end_out,
            &buffers.query4_end_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.query4_row_out,
            &buffers.query4_row_readback,
        );
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &buffers.query2_begin_readback, QUERY_COUNT),
            expected.query2_begin,
            "equal_range_query begin for pair keys should match test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.query2_end_readback, QUERY_COUNT),
            expected.query2_end,
            "equal_range_query end for pair keys should match test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.query2_row_readback, QUERY_COUNT),
            expected.query2_row,
            "find_equal_query for pair keys should match test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.query4_begin_readback, QUERY_COUNT),
            expected.query4_begin,
            "equal_range_query begin for quad keys should match test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.query4_end_readback, QUERY_COUNT),
            expected.query4_end,
            "equal_range_query end for quad keys should match test-only CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.query4_row_readback, QUERY_COUNT),
            expected.query4_row,
            "find_equal_query for quad keys should match test-only CPU oracle"
        );
    });
}

struct RangeQueryInputs {
    sorted2_a: Vec<u32>,
    sorted2_b: Vec<u32>,
    query2_a: Vec<u32>,
    query2_b: Vec<u32>,
    sorted4_a: Vec<u32>,
    sorted4_b: Vec<u32>,
    sorted4_c: Vec<u32>,
    sorted4_d: Vec<u32>,
    query4_a: Vec<u32>,
    query4_b: Vec<u32>,
    query4_c: Vec<u32>,
    query4_d: Vec<u32>,
}

impl RangeQueryInputs {
    fn new() -> Self {
        Self {
            sorted2_a: (0..SORTED_COUNT).map(|i| (i as u32) / 8).collect(),
            sorted2_b: (0..SORTED_COUNT).map(|i| ((i as u32) % 8) / 2).collect(),
            query2_a: (0..QUERY_COUNT).map(|i| (i as u32 * 5) % 11).collect(),
            query2_b: (0..QUERY_COUNT).map(|i| (i as u32 * 7) % 6).collect(),
            sorted4_a: (0..SORTED_COUNT).map(|i| (i as u32) / 16).collect(),
            sorted4_b: (0..SORTED_COUNT).map(|i| ((i as u32) / 8) % 2).collect(),
            sorted4_c: (0..SORTED_COUNT).map(|i| ((i as u32) / 4) % 2).collect(),
            sorted4_d: (0..SORTED_COUNT).map(|i| (i as u32) % 4).collect(),
            query4_a: (0..QUERY_COUNT).map(|i| (i as u32 * 3) % 5).collect(),
            query4_b: (0..QUERY_COUNT).map(|i| (i as u32 * 5) % 3).collect(),
            query4_c: (0..QUERY_COUNT).map(|i| (i as u32 * 7) % 3).collect(),
            query4_d: (0..QUERY_COUNT).map(|i| (i as u32 * 11) % 6).collect(),
        }
    }
}

struct RangeQueryExpected {
    query2_begin: Vec<u32>,
    query2_end: Vec<u32>,
    query2_row: Vec<u32>,
    query4_begin: Vec<u32>,
    query4_end: Vec<u32>,
    query4_row: Vec<u32>,
}

impl RangeQueryExpected {
    fn from_inputs(inputs: &RangeQueryInputs) -> Self {
        let (query2_begin, query2_end) = (0..QUERY_COUNT)
            .map(|i| {
                equal_range_2(
                    &inputs.sorted2_a,
                    &inputs.sorted2_b,
                    inputs.query2_a[i],
                    inputs.query2_b[i],
                )
            })
            .unzip();
        let query2_row = (0..QUERY_COUNT)
            .map(|i| {
                find_pair(
                    &inputs.sorted2_a,
                    &inputs.sorted2_b,
                    inputs.query2_a[i],
                    inputs.query2_b[i],
                )
            })
            .collect();
        let (query4_begin, query4_end) = (0..QUERY_COUNT)
            .map(|i| {
                equal_range_4(
                    &inputs.sorted4_a,
                    &inputs.sorted4_b,
                    &inputs.sorted4_c,
                    &inputs.sorted4_d,
                    [
                        inputs.query4_a[i],
                        inputs.query4_b[i],
                        inputs.query4_c[i],
                        inputs.query4_d[i],
                    ],
                )
            })
            .unzip();
        let query4_row = (0..QUERY_COUNT)
            .map(|i| {
                find_quad(
                    &inputs.sorted4_a,
                    &inputs.sorted4_b,
                    &inputs.sorted4_c,
                    &inputs.sorted4_d,
                    [
                        inputs.query4_a[i],
                        inputs.query4_b[i],
                        inputs.query4_c[i],
                        inputs.query4_d[i],
                    ],
                )
            })
            .collect();

        Self {
            query2_begin,
            query2_end,
            query2_row,
            query4_begin,
            query4_end,
            query4_row,
        }
    }
}

struct RangeQueryBuffers {
    sorted2_a: wgpu::Buffer,
    sorted2_b: wgpu::Buffer,
    query2_a: wgpu::Buffer,
    query2_b: wgpu::Buffer,
    sorted4_a: wgpu::Buffer,
    sorted4_b: wgpu::Buffer,
    sorted4_c: wgpu::Buffer,
    sorted4_d: wgpu::Buffer,
    query4_a: wgpu::Buffer,
    query4_b: wgpu::Buffer,
    query4_c: wgpu::Buffer,
    query4_d: wgpu::Buffer,
    query2_begin_out: wgpu::Buffer,
    query2_end_out: wgpu::Buffer,
    query2_row_out: wgpu::Buffer,
    query4_begin_out: wgpu::Buffer,
    query4_end_out: wgpu::Buffer,
    query4_row_out: wgpu::Buffer,
    query2_begin_readback: wgpu::Buffer,
    query2_end_readback: wgpu::Buffer,
    query2_row_readback: wgpu::Buffer,
    query4_begin_readback: wgpu::Buffer,
    query4_end_readback: wgpu::Buffer,
    query4_row_readback: wgpu::Buffer,
}

impl RangeQueryBuffers {
    fn new(device: &wgpu::Device, inputs: &RangeQueryInputs) -> Self {
        Self {
            sorted2_a: input_buffer(device, "sorted2_a", &inputs.sorted2_a),
            sorted2_b: input_buffer(device, "sorted2_b", &inputs.sorted2_b),
            query2_a: input_buffer(device, "query2_a", &inputs.query2_a),
            query2_b: input_buffer(device, "query2_b", &inputs.query2_b),
            sorted4_a: input_buffer(device, "sorted4_a", &inputs.sorted4_a),
            sorted4_b: input_buffer(device, "sorted4_b", &inputs.sorted4_b),
            sorted4_c: input_buffer(device, "sorted4_c", &inputs.sorted4_c),
            sorted4_d: input_buffer(device, "sorted4_d", &inputs.sorted4_d),
            query4_a: input_buffer(device, "query4_a", &inputs.query4_a),
            query4_b: input_buffer(device, "query4_b", &inputs.query4_b),
            query4_c: input_buffer(device, "query4_c", &inputs.query4_c),
            query4_d: input_buffer(device, "query4_d", &inputs.query4_d),
            query2_begin_out: output_buffer(device, "query2_begin_out", QUERY_COUNT),
            query2_end_out: output_buffer(device, "query2_end_out", QUERY_COUNT),
            query2_row_out: output_buffer(device, "query2_row_out", QUERY_COUNT),
            query4_begin_out: output_buffer(device, "query4_begin_out", QUERY_COUNT),
            query4_end_out: output_buffer(device, "query4_end_out", QUERY_COUNT),
            query4_row_out: output_buffer(device, "query4_row_out", QUERY_COUNT),
            query2_begin_readback: readback_buffer(device, "query2_begin_readback", QUERY_COUNT),
            query2_end_readback: readback_buffer(device, "query2_end_readback", QUERY_COUNT),
            query2_row_readback: readback_buffer(device, "query2_row_readback", QUERY_COUNT),
            query4_begin_readback: readback_buffer(device, "query4_begin_readback", QUERY_COUNT),
            query4_end_readback: readback_buffer(device, "query4_end_readback", QUERY_COUNT),
            query4_row_readback: readback_buffer(device, "query4_row_readback", QUERY_COUNT),
        }
    }

    fn bindings(&self) -> Vec<(&'static str, wgpu::BindingResource<'_>)> {
        vec![
            ("sorted2_a", self.sorted2_a.as_entire_binding()),
            ("sorted2_b", self.sorted2_b.as_entire_binding()),
            ("query2_a", self.query2_a.as_entire_binding()),
            ("query2_b", self.query2_b.as_entire_binding()),
            ("sorted4_a", self.sorted4_a.as_entire_binding()),
            ("sorted4_b", self.sorted4_b.as_entire_binding()),
            ("sorted4_c", self.sorted4_c.as_entire_binding()),
            ("sorted4_d", self.sorted4_d.as_entire_binding()),
            ("query4_a", self.query4_a.as_entire_binding()),
            ("query4_b", self.query4_b.as_entire_binding()),
            ("query4_c", self.query4_c.as_entire_binding()),
            ("query4_d", self.query4_d.as_entire_binding()),
            (
                "query2_begin_out",
                self.query2_begin_out.as_entire_binding(),
            ),
            ("query2_end_out", self.query2_end_out.as_entire_binding()),
            ("query2_row_out", self.query2_row_out.as_entire_binding()),
            (
                "query4_begin_out",
                self.query4_begin_out.as_entire_binding(),
            ),
            ("query4_end_out", self.query4_end_out.as_entire_binding()),
            ("query4_row_out", self.query4_row_out.as_entire_binding()),
        ]
    }
}

fn equal_range_2(sorted_a: &[u32], sorted_b: &[u32], a: u32, b: u32) -> (u32, u32) {
    let begin = first_row_where(sorted_a.len(), |row| {
        (sorted_a[row], sorted_b[row]) >= (a, b)
    });
    let end = first_row_where(sorted_a.len(), |row| {
        (sorted_a[row], sorted_b[row]) > (a, b)
    });
    (begin, end)
}

fn equal_range_4(
    sorted_a: &[u32],
    sorted_b: &[u32],
    sorted_c: &[u32],
    sorted_d: &[u32],
    key: [u32; 4],
) -> (u32, u32) {
    let begin = first_row_where(sorted_a.len(), |row| {
        (sorted_a[row], sorted_b[row], sorted_c[row], sorted_d[row])
            >= (key[0], key[1], key[2], key[3])
    });
    let end = first_row_where(sorted_a.len(), |row| {
        (sorted_a[row], sorted_b[row], sorted_c[row], sorted_d[row])
            > (key[0], key[1], key[2], key[3])
    });
    (begin, end)
}

fn first_row_where(len: usize, predicate: impl Fn(usize) -> bool) -> u32 {
    (0..len)
        .find(|&row| predicate(row))
        .map(|row| row as u32)
        .unwrap_or(len as u32)
}

fn find_pair(sorted_a: &[u32], sorted_b: &[u32], a: u32, b: u32) -> u32 {
    sorted_a
        .iter()
        .zip(sorted_b)
        .position(|(&row_a, &row_b)| row_a == a && row_b == b)
        .map(|row| row as u32)
        .unwrap_or(INVALID)
}

fn find_quad(
    sorted_a: &[u32],
    sorted_b: &[u32],
    sorted_c: &[u32],
    sorted_d: &[u32],
    key: [u32; 4],
) -> u32 {
    (0..sorted_a.len())
        .find(|&row| {
            sorted_a[row] == key[0]
                && sorted_b[row] == key[1]
                && sorted_c[row] == key[2]
                && sorted_d[row] == key[3]
        })
        .map(|row| row as u32)
        .unwrap_or(INVALID)
}

fn compile_validation_shader(root: &Path) -> (Vec<u8>, Vec<u8>) {
    let slangc = slangc_command();
    let shader = root.join("tests/shaders/gpu_range_query_validate.slang");
    let spv = common::TempArtifact::new("laniusc_gpu_range_query", "validate", Some("spv"));
    let reflection =
        common::TempArtifact::new("laniusc_gpu_range_query", "validate", Some("reflect.json"));
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
    common::assert_command_success("compile GPU range-query validation shader", &output);
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
