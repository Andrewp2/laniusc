//! Direct coverage of the private runtime producer/indirect-emitter boundary.

use super::*;
use crate::gpu::{
    buffers::storage_ro_from_bytes,
    compiler_graph::{
        CompilerGraphBuilder,
        CompilerPhase,
        INDIRECT_DISPATCH_BINDING,
        PassAccess,
        PassDesc,
        ResourceClass,
        ResourceDomain,
    },
    device,
};

const PRODUCER: &str = "codegen/lir/x86/runtime_dispatch_args";
const EMITTER: &str = "codegen/lir/x86/runtime_emit";
const CAPACITY: usize = 2208;
const CANARY: u8 = 0xa5;

fn words(values: &[u32]) -> Vec<u8> {
    values
        .iter()
        .flat_map(|value| value.to_le_bytes())
        .collect()
}

fn read_bytes(device: &wgpu::Device, buffer: &LaniusBuffer<u8>) -> Vec<u8> {
    let slice = buffer.slice(..);
    map_readback_blocking(device, &slice, "runtime dispatch regression").unwrap();
    let mapped = slice.get_mapped_range();
    let result = mapped.to_vec();
    drop(mapped);
    buffer.unmap();
    result
}

/// The CPU oracle reads the declared literal tables, without calling the GPU
/// byte selector or deriving expected bytes from a previous GPU dispatch. The
/// separate native width gate also checks these tables against assembly.
fn runtime_literal_bytes() -> Vec<u8> {
    let source = include_str!("../../../../shaders/codegen/lir/x86/runtime_abi.slang");
    let mut result = Vec::new();
    for declaration in source.split("static const uint ").skip(1) {
        let (header, initializer) = declaration.split_once('=').unwrap();
        let Some((name, count)) = header.trim().split_once('[') else {
            continue;
        };
        assert!(name.ends_with("_bytes"), "unexpected runtime table {name}");
        let count: usize = count.strip_suffix(']').unwrap().parse().unwrap();
        let body = initializer.trim_start().strip_prefix('{').unwrap();
        let (body, _) = body.split_once("};").unwrap();
        let without_comments = body
            .lines()
            .map(|line| line.split_once("//").map_or(line, |(code, _)| code))
            .collect::<Vec<_>>()
            .join(" ");
        let bytes = without_comments
            .split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(|value| {
                let value = value.strip_suffix('u').unwrap();
                if let Some(hex) = value.strip_prefix("0x") {
                    u8::from_str_radix(hex, 16).unwrap()
                } else {
                    value.parse::<u8>().unwrap()
                }
            })
            .collect::<Vec<_>>();
        assert_eq!(bytes.len(), count, "runtime table {name}");
        result.extend(bytes);
    }
    assert_eq!(
        result.len(),
        2095,
        "update the boundary cases when the runtime grows"
    );
    result
}

#[test]
fn physical_gpu_runtime_dispatch_covers_tail_and_resets_invalid_work() {
    let expected = runtime_literal_bytes();
    let gpu = device::global();
    let device = &gpu.device;
    let queue = &gpu.queue;
    let kernels = KernelRegistry::prepare_prefixes(device, &["codegen/lir/x86"], |key| {
        key == PRODUCER || key == EMITTER
    })
    .unwrap();

    // Keep the same resource ownership and indirect dependency as production,
    // with only the two kernels under test and a small packed output buffer.
    let mut builder = CompilerGraphBuilder::new();
    let layout_id = builder
        .add_storage(
            "x86_artifact_layout",
            ResourceDomain::ArtifactBytes,
            ResourceClass::Input,
            48,
        )
        .unwrap();
    let args_id = builder
        .add_indirect_storage(
            "x86_runtime_dispatch_args",
            ResourceDomain::DispatchArguments,
            ResourceClass::Workspace,
            12,
        )
        .unwrap();
    let output_id = builder
        .add_storage(
            "artifact_bytes",
            ResourceDomain::ArtifactBytes,
            ResourceClass::Output,
            CAPACITY as u64,
        )
        .unwrap();
    builder
        .add_pass(PassDesc {
            name: "lir.x86.runtime.dispatch_args",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::ArtifactBytes,
            accesses: vec![
                PassAccess::read("x86_artifact_layout", layout_id),
                PassAccess::write("x86_runtime_dispatch_args", args_id),
            ],
        })
        .unwrap();
    builder
        .add_pass(PassDesc {
            name: "lir.x86.runtime.emit",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::ArtifactBytes,
            accesses: vec![
                PassAccess::read("x86_artifact_layout", layout_id),
                PassAccess::write("artifact_bytes", output_id),
                PassAccess::indirect(INDIRECT_DISPATCH_BINDING, args_id),
            ],
        })
        .unwrap();
    let graph = builder.build().unwrap();
    let workspace = CompilerGraphWorkspace::new(device, "test.runtime_dispatch", &graph).unwrap();
    let allocations = workspace.allocations();
    let args = workspace.alias::<u32>(&graph, args_id, 3).unwrap();
    let output = workspace
        .alias::<u32>(&graph, output_id, CAPACITY / 4)
        .unwrap();
    let layout = storage_ro_from_bytes::<X86ArtifactLayout>(
        device,
        "test.runtime_dispatch.layout",
        &[0; 48],
        1,
    );
    let params = uniform_from_val(
        device,
        "test.runtime_dispatch.params",
        &X86ArtifactParams {
            target_capacity: 0,
            token_capacity: 0,
            function_capacity: 0,
            artifact_capacity: CAPACITY as u32,
            target_start: 0,
            page_capacity: 0,
            semantic_capacity: 0,
            reserved1: 0,
        },
    );
    let mut resources = ResourceMap::new();
    resources
        .graph_buffer(&graph, "x86_artifact_layout", &layout)
        .unwrap();
    resources
        .graph_buffer(&graph, "x86_runtime_dispatch_args", &args)
        .unwrap();
    resources
        .graph_buffer(&graph, "artifact_bytes", &output)
        .unwrap();
    resources.buffer("gParams", &params);
    let context = (&graph, &allocations);
    let producer = ComputeOperation::direct(
        device,
        &context,
        &resources,
        "lir.x86.runtime.dispatch_args",
        kernels.kernel(PRODUCER),
        1,
    )
    .unwrap();
    let emitter = ComputeOperation::indirect(
        device,
        &context,
        &resources,
        "lir.x86.runtime.emit",
        kernels.kernel(EMITTER),
        &args,
    )
    .unwrap();
    let args_readback = readback_bytes(device, "test.runtime_dispatch.args", 12, 12);
    let output_readback = readback_bytes(device, "test.runtime_dispatch.bytes", CAPACITY, CAPACITY);

    // Poison all three words once. Following cases deliberately reuse them,
    // including valid -> invalid transitions without a host argument reset.
    queue.write_buffer(&args.buffer, args.byte_offset, &words(&[99, 77, 55]));
    let run = |status, offset, length, capacity, emit| {
        queue.write_buffer(
            &layout.buffer,
            layout.byte_offset,
            &words(&[0, 0, 0, 0, 0, 0, 0, status, offset, length, 0, 0]),
        );
        queue.write_buffer(
            &params.buffer,
            params.byte_offset,
            &words(&[0, 0, 0, capacity, 0, 0, 0, 0]),
        );
        queue.write_buffer(&output.buffer, output.byte_offset, &[CANARY; CAPACITY]);
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("test.runtime_dispatch.encoder"),
        });
        producer.record(&mut encoder).unwrap();
        if emit {
            emitter.record(&mut encoder).unwrap();
        }
        encoder.copy_buffer_to_buffer(&args.buffer, args.byte_offset, &args_readback.buffer, 0, 12);
        encoder.copy_buffer_to_buffer(
            &output.buffer,
            output.byte_offset,
            &output_readback.buffer,
            0,
            CAPACITY as u64,
        );
        queue.submit(Some(encoder.finish()));
        let actual_args = read_bytes(device, &args_readback)
            .chunks_exact(4)
            .map(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()))
            .collect::<Vec<_>>();
        (actual_args, read_bytes(device, &output_readback))
    };

    // Check invalid input against poisoned X/Y/Z before any valid producer
    // invocation can normalize them. Keep this producer-only so a regression
    // cannot turn the deliberately poisoned words into a large dispatch.
    let (actual_args, actual) = run(1, 0, 2095, CAPACITY as u32, false);
    assert_eq!(actual_args, [0, 1, 1]);
    assert!(actual.iter().all(|byte| *byte == CANARY));

    for (length, offset, capacity, dimensions) in [
        (2048, 3, CAPACITY as u32, [8, 1, 1]),
        (2049, 3, CAPACITY as u32, [9, 1, 1]),
        // End exactly at the logical capacity while retaining physical suffix
        // canaries; neither side of a partial packed word may be clobbered.
        (2095, 5, 2100, [9, 1, 1]),
    ] {
        let (actual_args, actual) = run(0, offset, length, capacity, true);
        assert_eq!(actual_args, dimensions, "length {length}");
        let start = offset as usize;
        let end = start + length as usize;
        assert!(
            actual[..start].iter().all(|byte| *byte == CANARY),
            "prefix {length}"
        );
        assert_eq!(
            &actual[start..end],
            &expected[..length as usize],
            "runtime {length}"
        );
        assert!(
            actual[end..].iter().all(|byte| *byte == CANARY),
            "suffix {length}"
        );
    }

    for (status, offset, length, capacity) in [
        (1, 5, 2095, CAPACITY as u32),
        (0, CAPACITY as u32 + 1, 0, CAPACITY as u32),
        (0, 5, CAPACITY as u32 - 4, CAPACITY as u32),
        (0, u32::MAX, 2, CAPACITY as u32),
        (0, CAPACITY as u32, 1, CAPACITY as u32),
        (0, u32::MAX, u32::MAX, CAPACITY as u32),
        // A valid empty runtime at capacity also dispatches no work.
        (0, CAPACITY as u32, 0, CAPACITY as u32),
    ] {
        let (previous_args, _) = run(0, 3, 2049, CAPACITY as u32, true);
        assert_eq!(previous_args, [9, 1, 1]);
        let (actual_args, actual) = run(status, offset, length, capacity, true);
        assert_eq!(
            actual_args,
            [0, 1, 1],
            "layout {status}/{offset}/{length}/{capacity}"
        );
        assert!(
            actual.iter().all(|byte| *byte == CANARY),
            "invalid/empty output changed"
        );
    }

    // Test huge logical lengths using the producer only: no giant allocation
    // or dispatch is needed to check the emitter's fixed 2D linear stride.
    for (length, dimensions) in [
        (16_776_960, [65_535, 1, 1]),
        (16_776_961, [65_535, 2, 1]),
        (u32::MAX, [65_535, 257, 1]),
    ] {
        let (actual_args, actual) = run(0, 0, length, u32::MAX, false);
        assert_eq!(actual_args, dimensions, "large length {length}");
        assert!(actual.iter().all(|byte| *byte == CANARY));
    }
    // In particular, invalid input must erase the previous nontrivial Y
    // dimension as well as X. Keep this producer-only as well: a failure must
    // not submit billions of threads from the preceding logical-only case.
    let (actual_args, actual) = run(1, 0, u32::MAX, u32::MAX, false);
    assert_eq!(actual_args, [0, 1, 1]);
    assert!(actual.iter().all(|byte| *byte == CANARY));
}
