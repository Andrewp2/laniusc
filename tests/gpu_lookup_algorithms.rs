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

const LOOKUP_CAPACITY: usize = 16;
const QUERY_COUNT: usize = 8;
const STATUS_COUNT: usize = 4;
const INVALID: u32 = 0xffff_ffff;

#[test]
fn open_address_lookup_helpers_match_cpu_oracles() {
    common::block_on_gpu_with_timeout("open-address GPU lookup helper validation", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_validation_shader(&root);

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.gpu_lookup.validate",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create lookup validation pass");

        let inputs = LookupInputs::new();
        let expected = LookupExpected::from_inputs(&inputs);
        let buffers = LookupBuffers::new(device, &inputs);
        let bindings = buffers.bindings();
        let resources = bindings
            .iter()
            .map(|(name, resource)| ((*name).to_string(), resource.clone()))
            .collect::<HashMap<_, _>>();
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.gpu_lookup.validate.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )
        .expect("create lookup validation bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.gpu_lookup.validate.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.gpu_lookup.validate.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        copy_to_readback(
            &mut encoder,
            &buffers.found_values,
            &buffers.found_values_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.found_flags,
            &buffers.found_flags_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.probe_slots,
            &buffers.probe_slots_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.publish_keys,
            &buffers.publish_keys_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.publish_values,
            &buffers.publish_values_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.publish_status,
            &buffers.publish_status_readback,
        );
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &buffers.found_values_readback, QUERY_COUNT),
            expected.found_values,
            "generic open-address lookup values should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.found_flags_readback, QUERY_COUNT),
            expected.found_flags,
            "generic open-address lookup flags should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.probe_slots_readback, QUERY_COUNT),
            expected.probe_slots,
            "open_address_probe_slot should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.publish_keys_readback, LOOKUP_CAPACITY),
            expected.publish_keys,
            "generic open-address publish-min should publish expected keys"
        );
        assert_eq!(
            read_u32s(device, &buffers.publish_values_readback, LOOKUP_CAPACITY),
            expected.publish_values,
            "generic open-address publish-min should publish min values"
        );
        assert_eq!(
            read_u32s(device, &buffers.publish_status_readback, STATUS_COUNT),
            vec![1, 1, 1, 0],
            "generic open-address publish-min should reject invalid keys"
        );
    });
}

struct LookupInputs {
    lookup_keys: Vec<u32>,
    lookup_values: Vec<u32>,
    query_keys: Vec<u32>,
    publish_keys: Vec<u32>,
    publish_values: Vec<u32>,
}

impl LookupInputs {
    fn new() -> Self {
        let mut lookup_keys = vec![0; LOOKUP_CAPACITY];
        let mut lookup_values = vec![INVALID; LOOKUP_CAPACITY];
        for (key, value) in [(3, 30), (19, 190), (35, 350), (2, 20)] {
            let slot = cpu_insert_slot(&lookup_values, key);
            lookup_keys[slot] = key;
            lookup_values[slot] = value;
        }

        Self {
            lookup_keys,
            lookup_values,
            query_keys: vec![3, 19, 35, 2, 51, 7, INVALID, 18],
            publish_keys: vec![0; LOOKUP_CAPACITY],
            publish_values: vec![INVALID; LOOKUP_CAPACITY],
        }
    }
}

struct LookupExpected {
    found_values: Vec<u32>,
    found_flags: Vec<u32>,
    probe_slots: Vec<u32>,
    publish_keys: Vec<u32>,
    publish_values: Vec<u32>,
}

impl LookupExpected {
    fn from_inputs(inputs: &LookupInputs) -> Self {
        let mut found_values = Vec::with_capacity(QUERY_COUNT);
        let mut found_flags = Vec::with_capacity(QUERY_COUNT);
        let probe_slots = inputs
            .query_keys
            .iter()
            .enumerate()
            .map(|(probe, &key)| open_address_probe_slot(key, LOOKUP_CAPACITY, probe as u32))
            .collect::<Vec<_>>();

        for &key in &inputs.query_keys {
            let found = cpu_find(&inputs.lookup_keys, &inputs.lookup_values, key);
            found_flags.push(u32::from(found.is_some()));
            found_values.push(found.unwrap_or(INVALID));
        }

        let mut publish_keys = inputs.publish_keys.clone();
        let mut publish_values = inputs.publish_values.clone();
        cpu_publish_min(&mut publish_keys, &mut publish_values, 7, 12);
        cpu_publish_min(&mut publish_keys, &mut publish_values, 7, 3);
        cpu_publish_min(&mut publish_keys, &mut publish_values, 23, 9);

        Self {
            found_values,
            found_flags,
            probe_slots,
            publish_keys,
            publish_values,
        }
    }
}

struct LookupBuffers {
    lookup_keys: wgpu::Buffer,
    lookup_values: wgpu::Buffer,
    query_keys: wgpu::Buffer,
    found_values: wgpu::Buffer,
    found_flags: wgpu::Buffer,
    probe_slots: wgpu::Buffer,
    publish_keys: wgpu::Buffer,
    publish_values: wgpu::Buffer,
    publish_status: wgpu::Buffer,
    found_values_readback: wgpu::Buffer,
    found_flags_readback: wgpu::Buffer,
    probe_slots_readback: wgpu::Buffer,
    publish_keys_readback: wgpu::Buffer,
    publish_values_readback: wgpu::Buffer,
    publish_status_readback: wgpu::Buffer,
}

impl LookupBuffers {
    fn new(device: &wgpu::Device, inputs: &LookupInputs) -> Self {
        Self {
            lookup_keys: input_buffer(device, "lookup_keys", &inputs.lookup_keys),
            lookup_values: input_buffer(device, "lookup_values", &inputs.lookup_values),
            query_keys: input_buffer(device, "query_keys", &inputs.query_keys),
            found_values: output_buffer(device, "found_values", QUERY_COUNT),
            found_flags: output_buffer(device, "found_flags", QUERY_COUNT),
            probe_slots: output_buffer(device, "probe_slots", QUERY_COUNT),
            publish_keys: input_output_buffer(device, "publish_keys", &inputs.publish_keys),
            publish_values: input_output_buffer(device, "publish_values", &inputs.publish_values),
            publish_status: output_buffer(device, "publish_status", STATUS_COUNT),
            found_values_readback: readback_buffer(device, "found_values_readback", QUERY_COUNT),
            found_flags_readback: readback_buffer(device, "found_flags_readback", QUERY_COUNT),
            probe_slots_readback: readback_buffer(device, "probe_slots_readback", QUERY_COUNT),
            publish_keys_readback: readback_buffer(
                device,
                "publish_keys_readback",
                LOOKUP_CAPACITY,
            ),
            publish_values_readback: readback_buffer(
                device,
                "publish_values_readback",
                LOOKUP_CAPACITY,
            ),
            publish_status_readback: readback_buffer(
                device,
                "publish_status_readback",
                STATUS_COUNT,
            ),
        }
    }

    fn bindings(&self) -> Vec<(&'static str, wgpu::BindingResource<'_>)> {
        vec![
            ("lookup_keys", self.lookup_keys.as_entire_binding()),
            ("lookup_values", self.lookup_values.as_entire_binding()),
            ("query_keys", self.query_keys.as_entire_binding()),
            ("found_values", self.found_values.as_entire_binding()),
            ("found_flags", self.found_flags.as_entire_binding()),
            ("probe_slots", self.probe_slots.as_entire_binding()),
            ("publish_keys", self.publish_keys.as_entire_binding()),
            ("publish_values", self.publish_values.as_entire_binding()),
            ("publish_status", self.publish_status.as_entire_binding()),
        ]
    }
}

fn compile_validation_shader(root: &Path) -> (Vec<u8>, Vec<u8>) {
    let slangc = slangc_command();
    let shader = root.join("tests/shaders/gpu_lookup_validate.slang");
    let spv = common::TempArtifact::new("laniusc_gpu_lookup", "validate", Some("spv"));
    let reflection =
        common::TempArtifact::new("laniusc_gpu_lookup", "validate", Some("reflect.json"));
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
    common::assert_command_success("compile GPU lookup validation shader", &output);
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

fn input_output_buffer(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &u32_bytes(words),
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_DST
            | wgpu::BufferUsages::COPY_SRC,
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

fn open_address_probe_slot(key: u32, capacity: usize, probe: u32) -> u32 {
    (((key as usize) % capacity + probe as usize) % capacity) as u32
}

fn cpu_insert_slot(values: &[u32], key: u32) -> usize {
    for probe in 0..values.len() {
        let slot = open_address_probe_slot(key, values.len(), probe as u32) as usize;
        if values[slot] == INVALID {
            return slot;
        }
    }
    panic!("test lookup table has no empty slot");
}

fn cpu_find(keys: &[u32], values: &[u32], key: u32) -> Option<u32> {
    if key == INVALID {
        return None;
    }
    for probe in 0..values.len() {
        let slot = open_address_probe_slot(key, values.len(), probe as u32) as usize;
        if values[slot] == INVALID {
            return None;
        }
        if keys[slot] == key {
            return Some(values[slot]);
        }
    }
    None
}

fn cpu_publish_min(keys: &mut [u32], values: &mut [u32], key: u32, value: u32) {
    let slot = if let Some(probe) = (0..values.len()).find(|&probe| {
        let slot = open_address_probe_slot(key, values.len(), probe as u32) as usize;
        values[slot] == INVALID || keys[slot] == key
    }) {
        open_address_probe_slot(key, values.len(), probe as u32) as usize
    } else {
        panic!("test publish table has no matching or empty slot");
    };
    if values[slot] == INVALID {
        keys[slot] = key;
        values[slot] = value;
    } else {
        values[slot] = values[slot].min(value);
    }
}
