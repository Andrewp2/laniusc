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

const SORTED_COUNT: usize = 16;
const ITEM_CAPACITY: usize = 12;
const INVALID: u32 = 0xffff_ffff;

#[test]
fn generic_gpu_sorted_run_helpers_match_cpu_oracles() {
    common::block_on_gpu_with_timeout("generic GPU sorted-run helper validation", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_validation_shader(&root);

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.gpu_sorted_runs.validate",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create sorted-run validation pass");

        let inputs = SortedRunInputs::new();
        let expected = SortedRunExpected::from_inputs(&inputs);
        let buffers = SortedRunBuffers::new(device, &inputs);
        let bindings = buffers.bindings();
        let resources = bindings
            .iter()
            .map(|(name, resource)| ((*name).to_string(), resource.clone()))
            .collect::<HashMap<_, _>>();
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.gpu_sorted_runs.validate.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )
        .expect("create sorted-run validation bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.gpu_sorted_runs.validate.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.gpu_sorted_runs.validate.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        copy_to_readback(&mut encoder, &buffers.item_out, &buffers.item_readback);
        copy_to_readback(
            &mut encoder,
            &buffers.duplicate_prev_out,
            &buffers.duplicate_prev_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.identity_duplicate_prev_out,
            &buffers.identity_duplicate_prev_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.run_head_out,
            &buffers.run_head_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.run_tail_out,
            &buffers.run_tail_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.identity_run_head_out,
            &buffers.identity_run_head_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.identity_run_tail_out,
            &buffers.identity_run_tail_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.run_head_flag_out,
            &buffers.run_head_flag_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.run_id_from_prefix_out,
            &buffers.run_id_from_prefix_readback,
        );
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &buffers.item_readback, SORTED_COUNT),
            expected.item,
            "sorted_order_item should reject invalid rows and return valid items"
        );
        assert_eq!(
            read_u32s(device, &buffers.duplicate_prev_readback, SORTED_COUNT),
            expected.duplicate_prev,
            "sorted_adjacent_duplicate should report previous duplicate item"
        );
        assert_eq!(
            read_u32s(
                device,
                &buffers.identity_duplicate_prev_readback,
                SORTED_COUNT
            ),
            expected.identity_duplicate_prev,
            "sorted_identity_adjacent_duplicate should report previous duplicate item"
        );
        assert_eq!(
            read_u32s(device, &buffers.run_head_readback, SORTED_COUNT),
            expected.run_head,
            "sorted_run_head should report valid run heads"
        );
        assert_eq!(
            read_u32s(device, &buffers.run_tail_readback, SORTED_COUNT),
            expected.run_tail,
            "sorted_run_tail should report valid run tails"
        );
        assert_eq!(
            read_u32s(device, &buffers.identity_run_head_readback, SORTED_COUNT),
            expected.identity_run_head,
            "sorted_identity_run_head should report valid identity run heads"
        );
        assert_eq!(
            read_u32s(device, &buffers.identity_run_tail_readback, SORTED_COUNT),
            expected.identity_run_tail,
            "sorted_identity_run_tail should report valid identity run tails"
        );
        assert_eq!(
            read_u32s(device, &buffers.run_head_flag_readback, SORTED_COUNT),
            expected.run_head_flag,
            "sorted_run_head_flag should convert adjacency equality into scan flags"
        );
        assert_eq!(
            read_u32s(device, &buffers.run_id_from_prefix_readback, SORTED_COUNT),
            expected.run_id_from_prefix,
            "sorted_run_id_from_head_prefix should recover compact run ids from exclusive prefixes"
        );
    });
}

struct SortedRunInputs {
    sorted_order: Vec<u32>,
    item_key: Vec<u32>,
}

impl SortedRunInputs {
    fn new() -> Self {
        Self {
            sorted_order: vec![3, 7, 2, 9, 4, 1, 6, 10, 5, 11, 8, 0, 12, 13, 1, 6],
            item_key: vec![9, 4, 1, 1, 2, 6, 7, 1, 9, 2, 6, 8],
        }
    }
}

struct SortedRunExpected {
    item: Vec<u32>,
    duplicate_prev: Vec<u32>,
    identity_duplicate_prev: Vec<u32>,
    run_head: Vec<u32>,
    run_tail: Vec<u32>,
    identity_run_head: Vec<u32>,
    identity_run_tail: Vec<u32>,
    run_head_flag: Vec<u32>,
    run_id_from_prefix: Vec<u32>,
}

impl SortedRunExpected {
    fn from_inputs(inputs: &SortedRunInputs) -> Self {
        let item = (0..SORTED_COUNT)
            .map(|row| sorted_order_item(&inputs.sorted_order, row))
            .collect::<Vec<_>>();
        let duplicate_prev = (0..SORTED_COUNT)
            .map(|row| {
                let Some((item, prev)) = sorted_adjacent_pair(inputs, row) else {
                    return INVALID;
                };
                (inputs.item_key[item as usize] == inputs.item_key[prev as usize])
                    .then_some(prev)
                    .unwrap_or(INVALID)
            })
            .collect::<Vec<_>>();
        let run_head = (0..SORTED_COUNT)
            .map(|row| {
                let item = sorted_order_item(&inputs.sorted_order, row);
                if item == INVALID {
                    return INVALID;
                }
                if row == 0 {
                    return item;
                }
                let prev = sorted_order_item(&inputs.sorted_order, row - 1);
                if prev == INVALID
                    || inputs.item_key[item as usize] != inputs.item_key[prev as usize]
                {
                    item
                } else {
                    INVALID
                }
            })
            .collect::<Vec<_>>();
        let run_tail = (0..SORTED_COUNT)
            .map(|row| {
                let item = sorted_order_item(&inputs.sorted_order, row);
                if item == INVALID {
                    return INVALID;
                }
                if row + 1 >= SORTED_COUNT {
                    return item;
                }
                let next = sorted_order_item(&inputs.sorted_order, row + 1);
                if next == INVALID
                    || inputs.item_key[item as usize] != inputs.item_key[next as usize]
                {
                    item
                } else {
                    INVALID
                }
            })
            .collect::<Vec<_>>();
        let identity_duplicate_prev = (0..SORTED_COUNT)
            .map(|row| {
                if row == 0 || row >= ITEM_CAPACITY {
                    return INVALID;
                }
                (inputs.item_key[row] == inputs.item_key[row - 1])
                    .then_some((row - 1) as u32)
                    .unwrap_or(INVALID)
            })
            .collect::<Vec<_>>();
        let identity_run_head = (0..SORTED_COUNT)
            .map(|row| {
                if row >= ITEM_CAPACITY {
                    return INVALID;
                }
                if row == 0 || inputs.item_key[row] != inputs.item_key[row - 1] {
                    row as u32
                } else {
                    INVALID
                }
            })
            .collect::<Vec<_>>();
        let identity_run_tail = (0..SORTED_COUNT)
            .map(|row| {
                if row >= ITEM_CAPACITY {
                    return INVALID;
                }
                if row + 1 >= ITEM_CAPACITY || inputs.item_key[row] != inputs.item_key[row + 1] {
                    row as u32
                } else {
                    INVALID
                }
            })
            .collect::<Vec<_>>();
        let run_head_flag = (0..SORTED_COUNT)
            .map(|row| run_head_flag_for_row(inputs, row))
            .collect::<Vec<_>>();
        let run_id_from_prefix = (0..SORTED_COUNT)
            .map(|row| {
                let item = sorted_order_item(&inputs.sorted_order, row);
                if item == INVALID {
                    return INVALID;
                }
                let prefix = (0..row)
                    .map(|prior| run_head_flag_for_row(inputs, prior))
                    .sum::<u32>();
                run_id_from_head_prefix(run_head_flag[row], prefix)
            })
            .collect::<Vec<_>>();

        Self {
            item,
            duplicate_prev,
            identity_duplicate_prev,
            run_head,
            run_tail,
            identity_run_head,
            identity_run_tail,
            run_head_flag,
            run_id_from_prefix,
        }
    }
}

struct SortedRunBuffers {
    sorted_order: wgpu::Buffer,
    item_key: wgpu::Buffer,
    item_out: wgpu::Buffer,
    duplicate_prev_out: wgpu::Buffer,
    identity_duplicate_prev_out: wgpu::Buffer,
    run_head_out: wgpu::Buffer,
    run_tail_out: wgpu::Buffer,
    identity_run_head_out: wgpu::Buffer,
    identity_run_tail_out: wgpu::Buffer,
    run_head_flag_out: wgpu::Buffer,
    run_id_from_prefix_out: wgpu::Buffer,
    item_readback: wgpu::Buffer,
    duplicate_prev_readback: wgpu::Buffer,
    identity_duplicate_prev_readback: wgpu::Buffer,
    run_head_readback: wgpu::Buffer,
    run_tail_readback: wgpu::Buffer,
    identity_run_head_readback: wgpu::Buffer,
    identity_run_tail_readback: wgpu::Buffer,
    run_head_flag_readback: wgpu::Buffer,
    run_id_from_prefix_readback: wgpu::Buffer,
}

impl SortedRunBuffers {
    fn new(device: &wgpu::Device, inputs: &SortedRunInputs) -> Self {
        Self {
            sorted_order: input_buffer(device, "sorted_order", &inputs.sorted_order),
            item_key: input_buffer(device, "item_key", &inputs.item_key),
            item_out: output_buffer(device, "item_out", SORTED_COUNT),
            duplicate_prev_out: output_buffer(device, "duplicate_prev_out", SORTED_COUNT),
            identity_duplicate_prev_out: output_buffer(
                device,
                "identity_duplicate_prev_out",
                SORTED_COUNT,
            ),
            run_head_out: output_buffer(device, "run_head_out", SORTED_COUNT),
            run_tail_out: output_buffer(device, "run_tail_out", SORTED_COUNT),
            identity_run_head_out: output_buffer(device, "identity_run_head_out", SORTED_COUNT),
            identity_run_tail_out: output_buffer(device, "identity_run_tail_out", SORTED_COUNT),
            run_head_flag_out: output_buffer(device, "run_head_flag_out", SORTED_COUNT),
            run_id_from_prefix_out: output_buffer(device, "run_id_from_prefix_out", SORTED_COUNT),
            item_readback: readback_buffer(device, "item_readback", SORTED_COUNT),
            duplicate_prev_readback: readback_buffer(
                device,
                "duplicate_prev_readback",
                SORTED_COUNT,
            ),
            identity_duplicate_prev_readback: readback_buffer(
                device,
                "identity_duplicate_prev_readback",
                SORTED_COUNT,
            ),
            run_head_readback: readback_buffer(device, "run_head_readback", SORTED_COUNT),
            run_tail_readback: readback_buffer(device, "run_tail_readback", SORTED_COUNT),
            identity_run_head_readback: readback_buffer(
                device,
                "identity_run_head_readback",
                SORTED_COUNT,
            ),
            identity_run_tail_readback: readback_buffer(
                device,
                "identity_run_tail_readback",
                SORTED_COUNT,
            ),
            run_head_flag_readback: readback_buffer(device, "run_head_flag_readback", SORTED_COUNT),
            run_id_from_prefix_readback: readback_buffer(
                device,
                "run_id_from_prefix_readback",
                SORTED_COUNT,
            ),
        }
    }

    fn bindings(&self) -> Vec<(&'static str, wgpu::BindingResource<'_>)> {
        vec![
            ("sorted_order", self.sorted_order.as_entire_binding()),
            ("item_key", self.item_key.as_entire_binding()),
            ("item_out", self.item_out.as_entire_binding()),
            (
                "duplicate_prev_out",
                self.duplicate_prev_out.as_entire_binding(),
            ),
            (
                "identity_duplicate_prev_out",
                self.identity_duplicate_prev_out.as_entire_binding(),
            ),
            ("run_head_out", self.run_head_out.as_entire_binding()),
            ("run_tail_out", self.run_tail_out.as_entire_binding()),
            (
                "identity_run_head_out",
                self.identity_run_head_out.as_entire_binding(),
            ),
            (
                "identity_run_tail_out",
                self.identity_run_tail_out.as_entire_binding(),
            ),
            (
                "run_head_flag_out",
                self.run_head_flag_out.as_entire_binding(),
            ),
            (
                "run_id_from_prefix_out",
                self.run_id_from_prefix_out.as_entire_binding(),
            ),
        ]
    }
}

fn sorted_order_item(sorted_order: &[u32], row: usize) -> u32 {
    let item = sorted_order[row];
    if (item as usize) < ITEM_CAPACITY {
        item
    } else {
        INVALID
    }
}

fn sorted_adjacent_pair(inputs: &SortedRunInputs, row: usize) -> Option<(u32, u32)> {
    if row == 0 {
        return None;
    }
    let item = sorted_order_item(&inputs.sorted_order, row);
    let prev = sorted_order_item(&inputs.sorted_order, row - 1);
    (item != INVALID && prev != INVALID).then_some((item, prev))
}

fn run_head_flag_for_row(inputs: &SortedRunInputs, row: usize) -> u32 {
    let item = sorted_order_item(&inputs.sorted_order, row);
    if item == INVALID {
        return 0;
    }
    let equal_previous = row > 0 && {
        let previous = sorted_order_item(&inputs.sorted_order, row - 1);
        previous != INVALID && inputs.item_key[item as usize] == inputs.item_key[previous as usize]
    };
    u32::from(!equal_previous)
}

fn run_id_from_head_prefix(run_head: u32, exclusive_prefix: u32) -> u32 {
    if run_head != 0 {
        exclusive_prefix
    } else {
        exclusive_prefix.saturating_sub(1)
    }
}

fn compile_validation_shader(root: &Path) -> (Vec<u8>, Vec<u8>) {
    let slangc = slangc_command();
    let shader = root.join("tests/shaders/gpu_sorted_runs_validate.slang");
    let spv = common::TempArtifact::new("laniusc_gpu_sorted_runs", "validate", Some("spv"));
    let reflection =
        common::TempArtifact::new("laniusc_gpu_sorted_runs", "validate", Some("reflect.json"));
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
    common::assert_command_success("compile GPU sorted-run validation shader", &output);
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
