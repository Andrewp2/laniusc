//! ct_match cases on the physical GPU (shaders/type_checker/match/ct_match.slang).
//! One lane interns every case's pattern and actual, matches them, and
//! checks the interned environment against records it builds afterwards
//! (shaders/tests/ct_match_cases.slang). The same kernel runs on the CPU
//! replay with zero-filled buffers.

use std::collections::BTreeMap;

use super::{
    buffers::{LaniusBuffer, readback_bytes, storage_rw_for_array},
    device,
    passes_core::{self, PassData, make_pass_data_from_shader_key, map_readback_blocking},
};

const CASES_KERNEL: &str = "tests/ct_match_cases";
const CASES: usize = 25;
const CHECKS: usize = CASES * 4;

type Resources = BTreeMap<&'static str, LaniusBuffer<u32>>;

fn bind(device: &wgpu::Device, pass: &PassData, resources: &Resources) -> wgpu::BindGroup {
    let layout = pass
        .reflection
        .entry_points
        .iter()
        .find(|entry| entry.stage.as_deref() == Some("compute"))
        .and_then(|entry| entry.program_layout.as_ref());
    let parameters = match layout {
        Some(layout) => layout.parameters.first().map(|set| set.parameters.as_slice()).unwrap_or_default(),
        None => pass.reflection.parameters.as_slice(),
    };
    let entries: Vec<_> = parameters
        .iter()
        .filter(|parameter| parameter.binding.index.is_some() && parameter.ty.kind.is_some())
        .map(|parameter| {
            let name = parameter.name.as_str();
            let binding = resources
                .get(name)
                .unwrap_or_else(|| panic!("{} requires missing buffer {name}", pass.shader_id))
                .as_entire_binding();
            (name, binding)
        })
        .collect();
    passes_core::bind_group::validate_exact_binding_names(pass, 0, &entries).unwrap();
    passes_core::bind_group::create_bind_group_from_bindings(device, Some(&pass.shader_id), pass, 0, &entries)
        .unwrap()
}

fn read_words(device: &wgpu::Device, queue: &wgpu::Queue, buffer: &LaniusBuffer<u32>, words: usize) -> Vec<u32> {
    let readback = readback_bytes(device, "ct_match_cases.readback", words * 4, words);
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
    buffer.copy_to(&mut encoder, 0, &readback, 0, (words * 4) as u64);
    queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    map_readback_blocking(device, &slice, "ct_match_cases").unwrap();
    let mapped = slice.get_mapped_range();
    let out = mapped.chunks_exact(4).map(|w| u32::from_le_bytes(w.try_into().unwrap())).collect();
    drop(mapped);
    readback.unmap();
    out
}

#[test]
fn physical_gpu_ct_match_cases() {
    let gpu = device::global();
    let (device, queue) = (&gpu.device, &gpu.queue);
    let pass = make_pass_data_from_shader_key(device, CASES_KERNEL, "main", CASES_KERNEL).unwrap();
    let mut resources = Resources::new();
    for (name, words) in [
        ("ct_head", 1024 * 4),
        ("ct_meta", 1024 * 4),
        ("ct_extra", 1024 * 2),
        ("ct_args", 4096),
        ("ct_slot", 4096),
        ("ct_counts", 16),
        ("canonical_row", 16),
        ("canonical_atom", 16),
        ("canonical_projection", 16),
        ("canonical_dependency_type", 16),
        ("match_errors", 4 + CHECKS),
        ("match_ids", 128),
    ] {
        resources.insert(name, storage_rw_for_array::<u32>(device, name, words));
    }
    let group = bind(device, &pass, &resources);
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(CASES_KERNEL) });
    for buffer in resources.values() {
        encoder.clear_buffer(buffer, 0, None);
    }
    {
        let mut compute = passes_core::begin_counted_compute_pass(
            &mut encoder,
            &wgpu::ComputePassDescriptor { label: Some(&pass.shader_id), timestamp_writes: None },
        );
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(&group), &[]);
        passes_core::record_compute_dispatch();
        compute.dispatch_workgroups(1, 1, 1);
    }
    queue.submit(Some(encoder.finish()));
    let errors = read_words(device, queue, &resources["match_errors"], 4 + CHECKS);
    let ids = read_words(device, queue, &resources["match_ids"], 128);
    assert_eq!(ids[127] as usize, CASES, "ct_match cases did not all run");
    let failed: Vec<_> = (0..CHECKS)
        .filter(|check| errors[check / 32] & (1 << (check % 32)) != 0)
        .map(|check| format!("case {} check {}: {:#x}", check / 4, check % 4, errors[4 + check]))
        .collect();
    assert!(failed.is_empty(), "ct_match cases failed: {}", failed.join(", "));
}
