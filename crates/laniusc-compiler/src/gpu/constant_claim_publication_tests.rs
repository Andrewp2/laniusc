//! Buffer-backed publication probes run production stages in their real order.
//! This harness supplies evidence only; selection, equality, fit checks and the
//! explicit mirror run on the GPU. Rust compares observations with fixed data.

use std::collections::BTreeMap;

use super::{
    buffers::{LaniusBuffer, readback_bytes, storage_rw_for_array, uniform_from_val},
    device,
    passes_core::{self, PassData, make_pass_data_from_shader_key, map_readback_blocking},
};

const INVALID: u32 = u32::MAX;
const TOKENS: usize = 32;
const HIR: usize = 4;
const CALLEE: usize = 8;
const CALL: usize = 1;
const PARAMETER: usize = 16;
const U32: u32 = 4;
const U64: u32 = 10;
const U8: u32 = 13;
const ENVIRONMENT: u32 = 0x8000_0000 | CALLEE as u32;
const K: [u32; 2] = [2, PARAMETER as u32];
const NESTED: [u32; 2] = [3, 1];

#[derive(Clone, Copy, encase::ShaderType)]
struct Params {
    first: u32,
    second: u32,
    third: u32,
    fourth: u32,
}

#[derive(Debug)]
struct Case {
    name: &'static str,
    // (source kind, source payload, evidence mode); all use callee 8 / slot 0.
    claims: Vec<[u32; 3]>,
    context: Option<[u32; 3]>,
    explicit: Option<[u32; 2]>,
    replay_atom: Option<u32>,
    provisional: bool,
    accepted: bool,
    // (kind, payload, mode, selected argument row); None means reader rejected.
    binding: Option<[u32; 4]>,
    selected: Vec<u32>,
    executable_reference: [u32; 2],
    executable: Option<[u32; 3]>,
}

impl Case {
    fn new(
        name: &'static str,
        claims: &[[u32; 3]],
        binding: Option<[u32; 4]>,
        selected: &[u32],
    ) -> Self {
        Self {
            name,
            claims: claims.to_vec(),
            context: None,
            explicit: None,
            replay_atom: None,
            provisional: false,
            accepted: true,
            binding,
            selected: selected.to_vec(),
            executable_reference: NESTED,
            executable: None,
        }
    }

    fn context(mut self, context: [u32; 3]) -> Self {
        self.context = Some(context);
        self
    }

    fn explicit(mut self, reference: [u32; 2]) -> Self {
        self.explicit = Some(reference);
        self
    }

    fn replay(mut self, atom: u32) -> Self {
        self.replay_atom = Some(atom);
        self
    }

    fn unresolved(mut self, reference: [u32; 2]) -> Self {
        self.executable_reference = reference;
        self
    }

    fn rejected(mut self) -> Self {
        self.accepted = false;
        self
    }

    fn executable(mut self, reference: [u32; 2], value: [u32; 3]) -> Self {
        self.executable_reference = reference;
        self.executable = Some(value);
        self
    }
}

fn cases() -> Vec<Case> {
    let count_k = [K[0], K[1], 1];
    let exact_k = [K[0], K[1], 0];
    let count_nested = [NESTED[0], NESTED[1], 1];
    let exact_nested = [NESTED[0], NESTED[1], 0];
    let mut provisional = Case::new(
        "provisional inference clears stale acceptance flags",
        &[exact_k],
        Some([2, 16, 0, 0]),
        &[0],
    );
    provisional.provisional = true;
    vec![
        Case::new(
            "count agreement preserves first argument identity",
            &[count_k, count_nested],
            Some([2, 16, 1, 0]),
            &[1, 0],
        ),
        Case::new(
            "exact argument defeats earlier count argument",
            &[count_nested, exact_k],
            Some([2, 16, 0, 1]),
            &[0, 1],
        ),
        Case::new(
            "exact context defeats count argument",
            &[count_nested],
            Some([2, 16, 0, INVALID]),
            &[0],
        )
        .context(exact_k),
        Case::new(
            "exact context defeats exact argument",
            &[exact_k],
            Some([2, 16, 0, INVALID]),
            &[0],
        )
        .context(exact_k),
        Case::new(
            "exact argument defeats count context",
            &[exact_k],
            Some([2, 16, 0, 0]),
            &[1],
        )
        .context(count_nested),
        Case::new(
            "count context defeats count argument",
            &[count_k],
            Some([3, 1, 1, INVALID]),
            &[0],
        )
        .context(count_nested),
        Case::new(
            "explicit-only high limb survives final context mirror",
            &[],
            Some([1, 4, 0, INVALID]),
            &[],
        )
        .explicit([1, 4])
        .executable([1, 4], [U64, 3, 1]),
        Case::new(
            "explicit wins over exact context and equal distinct argument atom",
            &[[1, 1, 0]],
            Some([1, 0, 0, INVALID]),
            &[0],
        )
        .context([1, 1, 0])
        .explicit([1, 0])
        .executable([1, 0], [U64, 3, 0]),
        Case::new(
            "explicit mirror upgrades compatible count context to exact",
            &[[1, 1, 1]],
            Some([1, 0, 0, INVALID]),
            &[0],
        )
        .context([1, 1, 1])
        .explicit([1, 0])
        .executable([1, 0], [U64, 3, 0]),
        // The reader can return weak context evidence here. Status and selected
        // flags must still reject the full relation; reader presence is no gate.
        Case::new(
            "weak count context cannot hide conflicting exact arguments",
            &[exact_k, exact_nested],
            Some([2, 16, 1, INVALID]),
            &[0, 0],
        )
        .context(count_k)
        .rejected(),
        Case::new(
            "cyclic projection rejects instead of publishing",
            &[[3, 3, 1]],
            None,
            &[0],
        )
        .unresolved([3, 3])
        .rejected(),
        Case::new(
            "selected replay map discharges nested fit",
            &[count_k, count_nested],
            Some([2, 16, 1, 0]),
            &[1, 0],
        )
        .replay(0)
        .executable(NESTED, [U64, 3, 0]),
        Case::new(
            "selected replay atom must match declaration scalar",
            &[count_k, count_nested],
            None,
            &[0, 0],
        )
        .replay(3)
        .rejected(),
        Case::new(
            "selected replay still enforces inner u8 fit",
            &[count_k, count_nested],
            None,
            &[0, 0],
        )
        .replay(5)
        .rejected(),
        Case::new(
            "ordinary equality checks the high limb",
            &[[1, 0, 0], [1, 4, 0]],
            None,
            &[0, 0],
        )
        .rejected()
        .executable([1, 4], [U64, 3, 1]),
        Case::new(
            "equal typed values in distinct rows agree",
            &[[1, 0, 0], [1, 1, 0]],
            Some([1, 0, 0, 0]),
            &[1, 0],
        )
        .executable([1, 0], [U64, 3, 0]),
        provisional,
        Case::new(
            "malformed present context cannot become absent",
            &[exact_k],
            None,
            &[0],
        )
        .context([2, 16, 2])
        .rejected(),
    ]
}

type Resources = BTreeMap<&'static str, LaniusBuffer<u32>>;

fn insert(
    resources: &mut Resources,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    name: &'static str,
    values: Vec<u32>,
) {
    assert!(
        !values.is_empty(),
        "fixture buffer {name} must be allocated"
    );
    let buffer = storage_rw_for_array::<u32>(device, name, values.len());
    let bytes: Vec<u8> = values.iter().flat_map(|word| word.to_le_bytes()).collect();
    buffer.write(queue, 0, &bytes);
    assert!(
        resources.insert(name, buffer).is_none(),
        "duplicate fixture buffer {name}"
    );
}

fn fixture(device: &wgpu::Device, queue: &wgpu::Queue, case: &Case) -> Resources {
    let mut resources = BTreeMap::new();
    let mut put = |name, values| insert(&mut resources, device, queue, name, values);
    let count = case.claims.len();
    let capacity = count.max(1);
    put("token_count", vec![TOKENS as u32]);
    put("compact_hir_count", vec![HIR as u32]);
    let mut core = vec![0; HIR * 4];
    core[4..8].copy_from_slice(&[19, INVALID, CALLEE as u32, 9]);
    core[8..12].copy_from_slice(&[21, CALL as u32, CALLEE as u32, 9]);
    core[12..16].copy_from_slice(&[22, CALL as u32, 9, 10]);
    put("compact_hir_core", core);
    let mut payload = vec![0; HIR * 4];
    payload[CALL * 4] = 2;
    payload[2 * 4 + 2] = CALLEE as u32;
    put("compact_hir_payload", payload);
    put("compact_hir_links", vec![INVALID; HIR * 4]);
    put("path_id_by_owner_hir", vec![INVALID; HIR]);
    put("compact_path_count", vec![0]);
    put("compact_paths", vec![0; HIR * 4]);
    put("compact_path_segments", vec![0; TOKENS * 4]);
    put("resolved_value_type_qualifier_token", vec![INVALID; HIR]);
    let mut ranges = vec![0; TOKENS * 2];
    if case.explicit.is_some() {
        ranges[CALLEE * 2 + 1] = 1;
    }
    put("compact_path_type_arg_ranges", ranges);
    put("status", vec![1, INVALID, 0, 0]);
    let mut inference = vec![0; 8];
    inference[0] = u32::from(case.provisional);
    put("call_inference_state", inference);
    put("call_arg_row_node", vec![3]);
    put("call_arg_row_count_out", vec![1]);
    put("call_const_claim_count_out", vec![count as u32]);
    put("call_const_claim_callee", vec![CALLEE as u32; capacity]);
    put("call_const_claim_slot", vec![0; capacity]);
    put("call_const_claim_arg_row", vec![0; capacity]);
    for (column, name) in [
        "call_const_claim_ref_kind",
        "call_const_claim_ref_payload",
        "call_const_claim_identity_mode",
    ]
    .into_iter()
    .enumerate()
    {
        let mut values = vec![0; capacity];
        for (row, claim) in case.claims.iter().enumerate() {
            values[row] = claim[column];
        }
        put(name, values);
    }
    put("call_const_claim_selected", vec![7; capacity]);
    put("call_const_claim_lookup_head", vec![0; capacity]);
    put("call_const_claim_lookup_next", vec![0; capacity]);
    put("call_const_env_binding", vec![0; capacity * 4]);

    let mut atoms = vec![0; 128 * 4];
    for (row, atom) in [
        [U64, 3, 0, 0],
        [U64, 3, 0, 0],
        [U64, 4, 0, 0],
        [U32, 3, 0, 0],
        [U64, 3, 1, 0],
        [U64, 256, 0, 0],
    ]
    .into_iter()
    .enumerate()
    {
        atoms[row * 4..row * 4 + 4].copy_from_slice(&atom);
    }
    // The production contract exposes one canonical RW buffer per arena.
    // There are no read/write aliases or separate output snapshots in this probe.
    put("checked_constant_atoms", atoms);
    let mut projections = vec![0; 32 * 4];
    projections[0..4].copy_from_slice(&[U8, K[0], K[1], 0]);
    projections[4..8].copy_from_slice(&[U64, 3, 0, 0]);
    projections[12..16].copy_from_slice(&[U64, 3, 3, 0]);
    put("checked_constant_projections", projections);
    put("checked_constant_storage_state", vec![16, 32, 0, 0]);
    let mut slots = vec![INVALID; TOKENS];
    slots[PARAMETER] = 0;
    put("type_const_param_slot_by_token", slots);
    let mut scalars = vec![0; TOKENS];
    scalars[PARAMETER] = U64;
    put("type_const_param_scalar_by_token", scalars);
    let mut values = vec![INVALID; TOKENS];
    values[PARAMETER] = case.replay_atom.unwrap_or(INVALID);
    put("type_const_param_value_by_token", values);
    put("type_generic_param_slot_by_token", vec![INVALID; TOKENS]);

    let mut owners = vec![INVALID; TOKENS];
    let mut masks = vec![0; HIR];
    let mut kinds = vec![0; HIR * 32];
    let mut payloads = vec![INVALID; HIR * 32];
    let mut modes = vec![0; HIR * 32];
    if let Some(context) = case.context {
        owners[CALLEE] = CALL as u32;
        masks[CALL] = 1;
        kinds[CALL * 32] = context[0];
        payloads[CALL * 32] = context[1];
        modes[CALL * 32] = context[2];
    }
    put("call_context_owner_by_token", owners);
    put("call_context_constant_mask", masks);
    put("call_context_constant_kind", kinds);
    put("call_context_constant_payload", payloads);
    put("call_context_constant_identity_mode", modes);
    put("call_context_constant_valid_mask", vec![0; HIR]);
    put("call_context_arg_mask", vec![0; HIR]);
    put("call_context_ref_tag", vec![0; HIR * 32]);
    put("call_context_ref_payload", vec![INVALID; HIR * 32]);

    let mut owners = vec![INVALID; TOKENS];
    let mut statuses = vec![0; TOKENS];
    let mut descriptors = vec![0; TOKENS * 4];
    let mut tags = vec![0];
    let mut payloads = vec![INVALID];
    if let Some(reference) = case.explicit {
        owners[CALLEE] = CALLEE as u32;
        statuses[CALLEE] = 1;
        descriptors[CALLEE * 4..CALLEE * 4 + 4].copy_from_slice(&[1, 1, 0, 1]);
        tags[0] = 0x8000_0000 | reference[0];
        payloads[0] = reference[1];
    }
    put("call_explicit_application_owner_by_token", owners);
    put("call_explicit_application_status", statuses);
    put("call_explicit_environment", descriptors);
    put("call_explicit_binding_tag", tags);
    put("call_explicit_binding_payload", payloads);
    put("call_explicit_constant_valid_mask", vec![0; TOKENS]);
    put("explicit_environment_constant_kind", vec![0; HIR]);
    put("explicit_environment_constant_payload", vec![INVALID; HIR]);

    // Production 03a8 includes type-domain validation. This fixture supplies no type
    // bindings, so these explicitly named tables have zero live instances.
    for name in [
        "type_instance_kind",
        "type_instance_decl_token",
        "type_instance_arg_count",
        "type_instance_arg_start",
        "type_instance_arg_ref_tag",
        "type_instance_arg_ref_payload",
        "type_instance_arg_row_start",
        "type_instance_arg_row_ref_tag",
        "type_instance_arg_row_ref_payload",
        "type_instance_elem_ref_tag",
        "type_instance_elem_ref_payload",
        "type_instance_len_kind",
        "type_instance_len_payload",
        "external_type_library_id",
        "external_type_unit_id",
        "external_type_local_index",
    ] {
        put(name, vec![0; TOKENS]);
    }
    put("type_instance_arg_row_count_out", vec![0]);
    put(
        "queries",
        vec![
            ENVIRONMENT,
            0,
            case.executable_reference[0],
            case.executable_reference[1],
        ],
    );
    put("results", vec![INVALID; 16]);
    resources
}

fn group(
    device: &wgpu::Device,
    pass: &PassData,
    resources: &Resources,
    params: &LaniusBuffer<Params>,
) -> wgpu::BindGroup {
    let reflection = &pass.reflection;
    let parameters = if let Some(layout) = reflection
        .entry_points
        .iter()
        .find(|entry| entry.stage.as_deref() == Some("compute"))
        .and_then(|entry| entry.program_layout.as_ref())
    {
        layout
            .parameters
            .first()
            .map(|set| set.parameters.as_slice())
            .unwrap_or_default()
    } else {
        reflection.parameters.as_slice()
    };
    let entries: Vec<_> = parameters
        .iter()
        .filter(|parameter| parameter.binding.index.is_some() && parameter.ty.kind.is_some())
        .map(|parameter| {
            let name = parameter.name.as_str();
            if matches!(
                name,
                "checked_constant_atoms" | "checked_constant_projections"
            ) {
                assert!(
                    matches!(
                        crate::reflection::slang_category_and_type_to_wgpu(
                            parameter,
                            &parameter.ty
                        ),
                        Some(wgpu::BindingType::Buffer {
                            ty: wgpu::BufferBindingType::Storage { read_only: false },
                            ..
                        })
                    ),
                    "{}: {name} must use the canonical RW storage contract",
                    pass.shader_id
                );
            }
            let binding = if name == "gParams" {
                params.as_entire_binding()
            } else {
                let resource_name = match name {
                    "claim_count_in" => "call_const_claim_count_out",
                    "claim_callee" => "call_const_claim_callee",
                    "claim_slot" => "call_const_claim_slot",
                    "claim_lookup_head" => "call_const_claim_lookup_head",
                    "claim_lookup_next" => "call_const_claim_lookup_next",
                    other => other,
                };
                resources
                    .get(resource_name)
                    .unwrap_or_else(|| {
                        panic!(
                            "{} requires missing fixture buffer {resource_name}",
                            pass.shader_id
                        )
                    })
                    .as_entire_binding()
            };
            (name, binding)
        })
        .collect();
    passes_core::bind_group::validate_exact_binding_names(pass, 0, &entries).unwrap();
    passes_core::bind_group::create_bind_group_from_bindings(
        device,
        Some(&pass.shader_id),
        pass,
        0,
        &entries,
    )
    .unwrap()
}

fn dispatch(encoder: &mut wgpu::CommandEncoder, pass: &PassData, group: &wgpu::BindGroup) {
    let mut compute = passes_core::begin_counted_compute_pass(
        encoder,
        &wgpu::ComputePassDescriptor {
            label: Some(&pass.shader_id),
            timestamp_writes: None,
        },
    );
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(group), &[]);
    passes_core::record_compute_dispatch();
    if !crate::gpu::passes_core::debug_operation_skipped() {
        compute.dispatch_workgroups(1, 1, 1);
    }
}

fn assert_observation(case: &Case, words: &[u32], context: Option<[u32; 3]>, phase: &str) {
    assert_eq!(words.len(), 16);
    let label = format!("{} / {phase}: {words:?}", case.name);
    assert_eq!(
        words[0] != 0,
        case.binding.is_some(),
        "{label}: binding presence"
    );
    if let Some(binding) = case.binding {
        assert_eq!(
            [words[1], words[2], words[3], words[4]],
            binding,
            "{label}: selected reference"
        );
    }
    assert_eq!(
        words[5] != 0,
        context.is_some(),
        "{label}: context presence"
    );
    if let Some(context) = context {
        assert_eq!(
            [words[6], words[7], words[8]],
            context,
            "{label}: context reference"
        );
    }
    assert_eq!(
        words[9] != 0,
        case.executable.is_some(),
        "{label}: executable closure"
    );
    let value = [words[10], words[11], words[12]];
    assert_eq!(
        value,
        case.executable.unwrap_or([0; 3]),
        "{label}: exact scalar/limbs or no executable bits"
    );
    assert_eq!(
        words[13],
        u32::from(case.accepted),
        "{label}: accepted status"
    );
    assert_eq!(
        words[14],
        case.selected.iter().sum::<u32>(),
        "{label}: publication flags"
    );
}

#[test]
fn physical_gpu_constant_claim_publication_preserves_precedence_replay_and_explicit_mirror() {
    assert!(
        !super::env::env_bool_truthy("LANIUS_ALLOW_SOFTWARE_ADAPTER", false),
        "this regression requires a physical GPU",
    );
    let gpu = device::global();
    const INDEX: usize = 0;
    const EXPLICIT_ADMIT: usize = 1;
    const PUBLISH: usize = 2;
    const CONTEXT_ADMIT: usize = 3;
    const VALIDATE: usize = 4;
    const MIRROR: usize = 5;
    const PROBE: usize = 6;
    let keys = [
        "type_checker/calls/03a3_build_claim_lookup",
        "type_checker/calls/03a0b_validate_explicit_constants",
        "type_checker/calls/03a3b_publish_call_environment",
        "type_checker/calls/03a4c_admit_context_constants",
        "type_checker/calls/03a5_validate_const_claims",
        "type_checker/calls/03a8_validate_explicit_applications",
        "tests/constant_claim_publication",
    ];
    let passes: Vec<_> = keys
        .iter()
        .map(|key| make_pass_data_from_shader_key(&gpu.device, key, "main", key).unwrap())
        .collect();
    for pass in &passes[..PROBE] {
        assert_eq!(pass.thread_group_size, [256, 1, 1]);
    }
    assert_eq!(passes[PROBE].thread_group_size, [1, 1, 1]);
    for case in cases() {
        assert_eq!(
            case.claims.len(),
            case.selected.len(),
            "{}: expectation length",
            case.name
        );
        assert!(case.claims.len() <= 256);
        let resources = fixture(&gpu.device, &gpu.queue, &case);
        let capacity = case.claims.len().max(1);
        let index_params = uniform_from_val(
            &gpu.device,
            "claim_publication.index_params",
            &Params {
                first: capacity as u32,
                second: 0,
                third: 0,
                fourth: 0,
            },
        );
        let source_params = uniform_from_val(
            &gpu.device,
            "claim_publication.source_params",
            &Params {
                first: TOKENS as u32,
                second: TOKENS as u32,
                third: HIR as u32,
                fourth: 1,
            },
        );
        let groups: Vec<_> = passes
            .iter()
            .enumerate()
            .map(|(index, pass)| {
                group(
                    &gpu.device,
                    pass,
                    &resources,
                    if index == INDEX {
                        &index_params
                    } else {
                        &source_params
                    },
                )
            })
            .collect();
        // Two observations prove explicit-only evidence exists in the immutable
        // environment before 03a8 and in the retained context afterward.
        let word_count = 32 + capacity + 3;
        let readback = readback_bytes(
            &gpu.device,
            "claim_publication.readback",
            word_count * 4,
            word_count,
        );
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some(case.name),
            });
        // Producers' admissions precede every binding reader, as in resident.rs.
        for stage in [INDEX, EXPLICIT_ADMIT, PUBLISH, CONTEXT_ADMIT, VALIDATE, PROBE] {
            dispatch(&mut encoder, &passes[stage], &groups[stage]);
        }
        resources["results"].copy_to(&mut encoder, 0, &readback, 0, 64);
        for stage in [MIRROR, CONTEXT_ADMIT, PROBE] {
            dispatch(&mut encoder, &passes[stage], &groups[stage]);
        }
        resources["results"].copy_to(&mut encoder, 0, &readback, 64, 64);
        resources["call_const_claim_selected"].copy_to(
            &mut encoder,
            0,
            &readback,
            128,
            (capacity * 4) as u64,
        );
        let footer = ((32 + capacity) * 4) as u64;
        resources["call_context_constant_mask"].copy_to(
            &mut encoder,
            (CALL * 4) as u64,
            &readback,
            footer,
            4,
        );
        resources["call_context_owner_by_token"].copy_to(
            &mut encoder,
            (CALLEE * 4) as u64,
            &readback,
            footer + 4,
            4,
        );
        resources["checked_constant_storage_state"].copy_to(
            &mut encoder,
            8,
            &readback,
            footer + 8,
            4,
        );
        gpu.queue.submit(Some(encoder.finish()));
        let slice = readback.slice(..);
        map_readback_blocking(&gpu.device, &slice, "claim_publication.readback").unwrap();
        let mapped = slice.get_mapped_range();
        let words: Vec<_> = mapped
            .chunks_exact(4)
            .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
            .collect();
        drop(mapped);
        readback.unmap();
        assert_eq!(words.len(), word_count, "{}: readback size", case.name);
        assert_observation(&case, &words[..16], case.context, "before explicit mirror");
        let final_context = case
            .explicit
            .map(|reference| [reference[0], reference[1], 0])
            .or(case.context);
        assert_observation(
            &case,
            &words[16..32],
            final_context,
            "after explicit mirror",
        );
        assert_eq!(
            &words[32..32 + case.claims.len()],
            case.selected.as_slice(),
            "{}: per-row publication",
            case.name
        );
        let footer = &words[32 + capacity..];
        assert_eq!(
            footer[0],
            u32::from(final_context.is_some()),
            "{}: retained mask",
            case.name
        );
        assert_eq!(
            footer[1],
            if final_context.is_some() {
                CALL as u32
            } else {
                INVALID
            },
            "{}: retained call owner",
            case.name
        );
        assert_eq!(
            footer[2], 0,
            "{}: existing explicit references must not allocate replacement atoms",
            case.name
        );
    }
}
