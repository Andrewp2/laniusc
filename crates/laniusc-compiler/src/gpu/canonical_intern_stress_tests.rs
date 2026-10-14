//! Week-1 gate for single-dispatch lock-free interning on the physical GPU
//! (docs/canonical-type-ids.md, "Interning protocol"). One dispatch interns a
//! nested chain per lane with heavily shared keys; a second dispatch rehashes
//! every published record and checks uniqueness, structure and facts. Rust
//! only counts the distinct keys the chains contain.
//!
//! `LANIUS_CANONICAL_STRESS_RUNS` (default 16) sets the number of runs and
//! `LANIUS_CANONICAL_STRESS_BASE` (default 0) the first run index, so long
//! campaigns can be split into short invocations with distinct seeds.

use std::collections::{BTreeMap, HashMap};

use super::{
    buffers::{LaniusBuffer, readback_bytes, storage_rw_for_array, uniform_from_val},
    device,
    passes_core::{self, PassData, make_pass_data_from_shader_key, map_readback_blocking},
};

const STRESS: &str = "tests/canonical_intern_stress";
const CONTROL: &str = "tests/canonical_intern_incoherent";
const LANES: u32 = 1 << 20;
const RECORDS: usize = 4 << 20;
const ARGS: usize = 24 << 20;
const SLOTS: usize = 1 << 22;
const FIRST_RECORD: u32 = 32;
const ERROR_WORDS: usize = 8;

#[derive(Clone, Copy, encase::ShaderType)]
struct Params {
    lanes: u32,
    distinct: u32,
    seed: u32,
    mode: u32,
}

type Resources = BTreeMap<&'static str, LaniusBuffer<u32>>;

fn bind(device: &wgpu::Device, pass: &PassData, resources: &Resources, params: &LaniusBuffer<Params>) -> wgpu::BindGroup {
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
            let binding = if name == "gParams" {
                params.as_entire_binding()
            } else {
                resources
                    .get(name)
                    .unwrap_or_else(|| panic!("{} requires missing buffer {name}", pass.shader_id))
                    .as_entire_binding()
            };
            (name, binding)
        })
        .collect();
    passes_core::bind_group::validate_exact_binding_names(pass, 0, &entries).unwrap();
    passes_core::bind_group::create_bind_group_from_bindings(device, Some(&pass.shader_id), pass, 0, &entries)
        .unwrap()
}

fn dispatch(encoder: &mut wgpu::CommandEncoder, pass: &PassData, group: &wgpu::BindGroup, threads: u32) {
    let mut compute = passes_core::begin_counted_compute_pass(
        encoder,
        &wgpu::ComputePassDescriptor { label: Some(&pass.shader_id), timestamp_writes: None },
    );
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(group), &[]);
    passes_core::record_compute_dispatch();
    compute.dispatch_workgroups(threads.div_ceil(256), 1, 1);
}

fn read_words(device: &wgpu::Device, queue: &wgpu::Queue, buffer: &LaniusBuffer<u32>, words: usize) -> Vec<u32> {
    let readback = readback_bytes(device, "canonical_stress.readback", words * 4, words);
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
    buffer.copy_to(&mut encoder, 0, &readback, 0, (words * 4) as u64);
    queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    map_readback_blocking(device, &slice, "canonical_stress").unwrap();
    let mapped = slice.get_mapped_range();
    let out = mapped.chunks_exact(4).map(|w| u32::from_le_bytes(w.try_into().unwrap())).collect();
    drop(mapped);
    readback.unmap();
    out
}

fn words_bytes(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|word| word.to_le_bytes()).collect()
}

fn mix32(mut x: u32) -> u32 {
    x ^= x >> 16;
    x = x.wrapping_mul(0x7feb_352d);
    x ^= x >> 15;
    x = x.wrapping_mul(0x846c_a68b);
    x ^ (x >> 16)
}

/// Distinct keys reachable from all chains, mirroring `intern_chain`.
fn distinct_keys(distinct: u32, seed: u32) -> usize {
    let mut keys: HashMap<(u32, u32, u32, u32, Vec<u32>), u32> = HashMap::new();
    let mut intern = |kind: u32, words: [u32; 3], args: Vec<u32>| -> u32 {
        let next = keys.len() as u32;
        *keys.entry((kind, words[0], words[1], words[2], args)).or_insert(next)
    };
    for group in 0..distinct {
        let chain = mix32(group ^ seed.wrapping_mul(0x9e37_79b9));
        let mut id = intern(8, [4, chain % 61, 0], vec![]);
        for level in 1..=(1 + chain % 12) {
            id = match (chain >> (2 * (level % 14))) & 3 {
                0 => intern(4, [0; 3], vec![id]),
                1 => {
                    let count = intern(10, [level % 3, 0, 0], vec![]);
                    intern(3, [0; 3], vec![id, count])
                }
                2 => {
                    let arity = 3 + level % 4;
                    let args = (0..arity)
                        .map(|index| if index % 2 == 0 { id } else { intern(8, [4, (level * 7 + index) % 5, 0], vec![]) })
                        .collect();
                    intern(2, [1, 2, (chain >> level) & 3], args)
                }
                _ => intern(5, [0; 3], vec![id]),
            };
        }
    }
    keys.len()
}

fn env_u32(name: &str, default: u32) -> u32 {
    std::env::var(name).ok().and_then(|value| value.parse().ok()).unwrap_or(default)
}

#[test]
fn physical_gpu_single_dispatch_interning_is_unique_under_contention() {
    assert!(!super::env::env_bool_truthy("LANIUS_ALLOW_SOFTWARE_ADAPTER", false),
        "this gate requires a physical GPU");
    let runs = env_u32("LANIUS_CANONICAL_STRESS_RUNS", 16);
    let base = env_u32("LANIUS_CANONICAL_STRESS_BASE", 0);
    let gpu = device::global();
    let (device, queue) = (&gpu.device, &gpu.queue);
    let pass = make_pass_data_from_shader_key(device, STRESS, "main", STRESS).unwrap();
    let mut resources = Resources::new();
    for (name, words) in [
        ("ct_head", RECORDS * 4),
        ("ct_meta", RECORDS * 4),
        ("ct_extra", RECORDS * 2),
        ("ct_args", ARGS),
        ("ct_slot", SLOTS),
        ("ct_counts", 16),
        ("canonical_row", 1),
        ("canonical_atom", 1),
        ("canonical_projection", 1),
        ("canonical_dependency_type", 1),
        ("stress_result", LANES as usize),
        ("stress_errors", ERROR_WORDS),
    ] {
        resources.insert(name, storage_rw_for_array::<u32>(device, name, words));
    }
    let mut totals = [0u64; ERROR_WORDS];
    let mut intern_ms_total = 0.0f64;
    let mut intern_ms_max = 0.0f64;
    for run in base..base.saturating_add(runs) {
        let distinct = [64u32, 4096, 1 << 16, LANES][(run as usize / 2) % 4];
        let seed = (run.wrapping_mul(0x0003_1337) & !1) | (run & 1);
        let intern_params = uniform_from_val(device, "canonical_stress.intern", &Params { lanes: LANES, distinct, seed, mode: 0 });
        let validate_params = uniform_from_val(device, "canonical_stress.validate", &Params { lanes: LANES, distinct, seed, mode: 1 });
        let intern_group = bind(device, &pass, &resources, &intern_params);
        let validate_group = bind(device, &pass, &resources, &validate_params);
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(STRESS) });
        encoder.clear_buffer(&resources["ct_slot"], 0, None);
        encoder.clear_buffer(&resources["stress_errors"], 0, None);
        queue.write_buffer(&resources["ct_counts"], 0, &words_bytes(&[FIRST_RECORD, 0, 0, 0, 0, 0, 0, 0]));
        queue.submit(Some(encoder.finish()));
        let started = std::time::Instant::now();
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(STRESS) });
        dispatch(&mut encoder, &pass, &intern_group, LANES);
        queue.submit(Some(encoder.finish()));
        let counts = read_words(device, queue, &resources["ct_counts"], 8);
        let intern_ms = started.elapsed().as_secs_f64() * 1e3;
        intern_ms_total += intern_ms;
        intern_ms_max = intern_ms_max.max(intern_ms);
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(STRESS) });
        dispatch(&mut encoder, &pass, &validate_group, LANES.max(SLOTS as u32));
        queue.submit(Some(encoder.finish()));
        let errors = read_words(device, queue, &resources["stress_errors"], ERROR_WORDS);
        // The CPU mirror of a 1M-chain run is slow in debug builds; check
        // it on the first such runs of an invocation only.
        let expected = (distinct < LANES || run < base + 8).then(|| distinct_keys(distinct, seed));
        eprintln!(
            "[canonical_stress] run={run} distinct={distinct} seed={seed:#x} intern_ms={intern_ms:.2} live={} expected={expected:?} records={} args={} overflow={:#x} dup={} broken={} structure={} facts={} unpublished={} failed={}",
            errors[5], counts[0] - FIRST_RECORD, counts[1], counts[3],
            errors[0], errors[1], errors[2], errors[3], errors[4], errors[6]
        );
        assert_eq!(counts[3], 0, "run {run}: capacity overflow");
        assert_eq!(&errors[..5], &[0; 5], "run {run}: dup/broken/structure/facts/unpublished");
        assert_eq!(errors[6], 0, "run {run}: failed interns");
        if let Some(expected) = expected {
            assert_eq!(errors[5] as usize, expected, "run {run}: live records equal distinct keys");
        }
        for (total, value) in totals.iter_mut().zip(errors) {
            *total += u64::from(value);
        }
    }
    eprintln!(
        "[canonical_stress] runs {base}..{} passed; live records total {}; intern_ms mean {:.2} max {:.2}",
        base + runs, totals[5], intern_ms_total / f64::from(runs.max(1)), intern_ms_max
    );
}

/// Negative control: the same protocol without coherence or fences. It is
/// expected to fail sometimes; the test only reports what it observes so the
/// gate's sensitivity is documented. It never fails.
#[test]
fn physical_gpu_incoherent_interning_control_reports_duplicates() {
    let runs = env_u32("LANIUS_CANONICAL_STRESS_RUNS", 16).min(64);
    let gpu = device::global();
    let (device, queue) = (&gpu.device, &gpu.queue);
    let pass = make_pass_data_from_shader_key(device, CONTROL, "main", CONTROL).unwrap();
    let mut resources = Resources::new();
    for (name, words) in [
        ("nc_head", RECORDS * 4),
        ("nc_slot", SLOTS),
        ("nc_counts", 8),
        ("stress_result", LANES as usize),
        ("stress_errors", ERROR_WORDS),
    ] {
        resources.insert(name, storage_rw_for_array::<u32>(device, name, words));
    }
    let mut failing_runs = 0;
    for run in 0..runs {
        let distinct = [64u32, 4096, 1 << 16, LANES][(run as usize / 2) % 4];
        let seed = (run.wrapping_mul(0x0005_1337) & !1) | (run & 1);
        let intern_params = uniform_from_val(device, "canonical_control.intern", &Params { lanes: LANES, distinct, seed, mode: 0 });
        let validate_params = uniform_from_val(device, "canonical_control.validate", &Params { lanes: LANES, distinct, seed, mode: 1 });
        let intern_group = bind(device, &pass, &resources, &intern_params);
        let validate_group = bind(device, &pass, &resources, &validate_params);
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(CONTROL) });
        encoder.clear_buffer(&resources["nc_slot"], 0, None);
        encoder.clear_buffer(&resources["stress_errors"], 0, None);
        queue.write_buffer(&resources["nc_counts"], 0, &words_bytes(&[1, 0, 0, 0, 0, 0, 0, 0]));
        dispatch(&mut encoder, &pass, &intern_group, LANES);
        dispatch(&mut encoder, &pass, &validate_group, LANES.max(SLOTS as u32));
        queue.submit(Some(encoder.finish()));
        let errors = read_words(device, queue, &resources["stress_errors"], ERROR_WORDS);
        if errors[0] != 0 || errors[1] != 0 {
            failing_runs += 1;
        }
        eprintln!("[canonical_control] run={run} distinct={distinct} live={} dup={} broken={}", errors[5], errors[0], errors[1]);
    }
    eprintln!("[canonical_control] {failing_runs}/{runs} incoherent runs produced duplicates or broken chains");
}
