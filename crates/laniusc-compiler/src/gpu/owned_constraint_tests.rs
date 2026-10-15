//! Four static operation-family dispatches test the production owned matcher.
//! All 32 cases retain their original IDs, operation streams and expectations.
//! The shader supplies explicit graph fixtures and binding invariants; the
//! expected result states below are independent of its reported expectations.

use super::{
    buffers::{readback_bytes, storage_ro_from_u32s, storage_rw_for_array},
    device,
    passes_core::{self, make_pass_data_from_shader_key, map_readback_blocking},
};

const MATCHED: u32 = 1;
const NO_MATCH: u32 = 2;
const INVALID: u32 = 3;
const LIMIT: u32 = 4;

const CASES: [(&str, u32, Option<u32>); 32] = [
    ("infer and extract an owned type binding", MATCHED, None),
    ("repeated variable across roots conflicts", NO_MATCH, None),
    (
        "compound addresses retain their graph namespace",
        MATCHED,
        None,
    ),
    (
        "goal atom identical to pattern atom stays rigid",
        MATCHED,
        None,
    ),
    ("array and slice cannot coerce", NO_MATCH, None),
    (
        "fixed prerequisite agrees with completed binding",
        MATCHED,
        None,
    ),
    (
        "same-header fixed prerequisite disagrees with completed binding",
        NO_MATCH,
        None,
    ),
    ("fixed match requires successful finish", INVALID, None),
    ("overlap infers variables on both sides", MATCHED, None),
    ("cross-root equations make heads disjoint", NO_MATCH, None),
    (
        "free existential representative is a valid overlap",
        MATCHED,
        None,
    ),
    (
        "occurs rejection does not install the failed binding",
        NO_MATCH,
        None,
    ),
    (
        "array element and constant length have separate domains",
        MATCHED,
        None,
    ),
    ("different array lengths are disjoint", NO_MATCH, None),
    ("unused header parameter is invalid", INVALID, None),
    (
        "head coverage sees both domains without binding",
        MATCHED,
        None,
    ),
    (
        "ancestor atom stays rigid in definition coverage",
        MATCHED,
        None,
    ),
    ("malformed later root is not hidden", INVALID, None),
    (
        "malformed graph cycle differs from occurs failure",
        INVALID,
        Some(9),
    ),
    ("pair work budget is enforced", LIMIT, Some(6)),
    ("overlap charges occurs work", LIMIT, Some(7)),
    (
        "following a binding charges substitution work",
        LIMIT,
        Some(8),
    ),
    ("depth is an independent limit", LIMIT, Some(5)),
    ("one-way binding needs no occurs work", MATCHED, None),
    (
        "all 32 type and 32 constant members are covered",
        MATCHED,
        None,
    ),
    ("33-member inventory is a resource limit", LIMIT, Some(3)),
    ("parameter atom must match its domain", INVALID, None),
    (
        "array length binding retains its constant tag",
        MATCHED,
        None,
    ),
    (
        "nominal constant operand uses the constant domain",
        MATCHED,
        None,
    ),
    ("same-ordinal foreign goal atom stays rigid", MATCHED, None),
    ("failure is sticky across later matching", NO_MATCH, None),
    ("inference cannot resume after finish", INVALID, None),
];


// Instruction data only: all matching still runs through the production GPU API.
const BEGIN_MATCH: u32 = 1;
const MATCH: u32 = 2;
const FINISH_MATCH: u32 = 3;
const FIXED_MATCH: u32 = 4;
const BEGIN_OVERLAP: u32 = 5;
const OVERLAP: u32 = 6;
const FINISH_OVERLAP: u32 = 7;
const BEGIN_PATTERN: u32 = 8;
const VISIT: u32 = 9;
const FINISH_PATTERN: u32 = 10;
const CHECK_BINDING: u32 = 11;
const SET_LIMITS: u32 = 12;

fn instruction(opcode: u32, args: [u32; 4]) -> [u32; 8] {
    [opcode, args[0], args[1], args[2], args[3], 0, 0, 0]
}

fn fixture_programs() -> (Vec<u32>, Vec<u32>) {
    let mut all_members = vec![instruction(BEGIN_PATTERN, [16, 0, 0, 0])];
    for ordinal in 0..32 {
        all_members.push(instruction(VISIT, [2, 64 + ordinal, 0, 0]));
        all_members.push(instruction(VISIT, [0x8000_0002, 96 + ordinal, 0, 0]));
    }
    all_members.push(instruction(FINISH_PATTERN, [0; 4]));
    let programs = [
        // Case 0; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_MATCH, [10, 0, 0, 0]),
            instruction(MATCH, [2, 20, 1, 4]),
            instruction(FINISH_MATCH, [0, 0, 0, 0]),
            instruction(CHECK_BINDING, [0, 0, 1, 4]),
        ],
        // Case 1; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_MATCH, [10, 0, 0, 0]),
            instruction(MATCH, [2, 20, 1, 4]),
            instruction(MATCH, [2, 20, 1, 3]),
        ],
        // Case 2; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_MATCH, [10, 0, 0, 0]),
            instruction(MATCH, [2, 20, 3, 1]),
            instruction(MATCH, [3, 1, 3, 8]),
            instruction(FINISH_MATCH, [0, 0, 0, 0]),
            instruction(CHECK_BINDING, [0, 0, 3, 1]),
        ],
        // Case 3; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_MATCH, [10, 0, 0, 0]),
            instruction(MATCH, [2, 20, 2, 20]),
            instruction(FINISH_MATCH, [0, 0, 0, 0]),
            instruction(FIXED_MATCH, [3, 1, 3, 4]),
            instruction(CHECK_BINDING, [0, 0, 2, 20]),
        ],
        // Case 4; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_MATCH, [10, 0, 0, 0]),
            instruction(MATCH, [3, 4, 3, 2]),
        ],
        // Case 5; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_MATCH, [10, 0, 0, 0]),
            instruction(MATCH, [2, 20, 1, 4]),
            instruction(FINISH_MATCH, [0, 0, 0, 0]),
            instruction(FIXED_MATCH, [3, 1, 3, 1]),
        ],
        // Case 6; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_MATCH, [10, 0, 0, 0]),
            instruction(MATCH, [2, 20, 1, 4]),
            instruction(FINISH_MATCH, [0, 0, 0, 0]),
            instruction(FIXED_MATCH, [3, 1, 3, 15]),
        ],
        // Case 7; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_MATCH, [10, 0, 0, 0]),
            instruction(MATCH, [2, 20, 1, 4]),
            instruction(FIXED_MATCH, [3, 1, 3, 1]),
        ],
        // Case 8; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_OVERLAP, [10, 20, 0, 0]),
            instruction(OVERLAP, [3, 6, 3, 0]),
            instruction(FINISH_OVERLAP, [0, 0, 0, 0]),
        ],
        // Case 9; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_OVERLAP, [10, 14, 0, 0]),
            instruction(OVERLAP, [2, 20, 1, 3]),
            instruction(OVERLAP, [2, 20, 1, 4]),
        ],
        // Case 10; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_OVERLAP, [10, 20, 0, 0]),
            instruction(OVERLAP, [2, 20, 2, 40]),
            instruction(FINISH_OVERLAP, [0, 0, 0, 0]),
        ],
        // Case 11; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_OVERLAP, [10, 20, 0, 0]),
            instruction(OVERLAP, [2, 20, 3, 1]),
            instruction(OVERLAP, [3, 1, 2, 40]),
        ],
        // Case 12; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_OVERLAP, [12, 21, 0, 0]),
            instruction(OVERLAP, [3, 2, 3, 2]),
            instruction(FINISH_OVERLAP, [0, 0, 0, 0]),
        ],
        // Case 13; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_OVERLAP, [10, 14, 0, 0]),
            instruction(OVERLAP, [3, 16, 3, 9]),
        ],
        // Case 14; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_PATTERN, [11, 0, 0, 0]),
            instruction(VISIT, [2, 21, 0, 0]),
            instruction(FINISH_PATTERN, [0, 0, 0, 0]),
        ],
        // Case 15; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_PATTERN, [12, 0, 0, 0]),
            instruction(VISIT, [3, 2, 0, 0]),
            instruction(FINISH_PATTERN, [0, 0, 0, 0]),
        ],
        // Case 16; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_PATTERN, [10, 0, 0, 0]),
            instruction(VISIT, [2, 20, 0, 0]),
            instruction(VISIT, [3, 11, 0, 0]),
            instruction(FINISH_PATTERN, [0, 0, 0, 0]),
        ],
        // Case 17; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_PATTERN, [10, 0, 0, 0]),
            instruction(VISIT, [2, 20, 0, 0]),
            instruction(VISIT, [3, 12, 0, 0]),
        ],
        // Case 18; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_PATTERN, [14, 0, 0, 0]),
            instruction(VISIT, [3, 5, 0, 0]),
        ],
        // Case 19; order is part of the public state-machine contract.
        vec![
            instruction(SET_LIMITS, [16, 1, 512, 512]),
            instruction(BEGIN_MATCH, [10, 0, 0, 0]),
            instruction(MATCH, [3, 1, 3, 1]),
        ],
        // Case 20; order is part of the public state-machine contract.
        vec![
            instruction(SET_LIMITS, [16, 512, 0, 512]),
            instruction(BEGIN_OVERLAP, [10, 20, 0, 0]),
            instruction(OVERLAP, [2, 20, 2, 40]),
        ],
        // Case 21; order is part of the public state-machine contract.
        vec![
            instruction(SET_LIMITS, [16, 512, 512, 0]),
            instruction(BEGIN_MATCH, [10, 0, 0, 0]),
            instruction(MATCH, [2, 20, 1, 4]),
            instruction(MATCH, [2, 20, 1, 4]),
        ],
        // Case 22; order is part of the public state-machine contract.
        vec![
            instruction(SET_LIMITS, [1, 512, 512, 512]),
            instruction(BEGIN_MATCH, [10, 0, 0, 0]),
            instruction(MATCH, [3, 1, 3, 1]),
        ],
        // Case 23; order is part of the public state-machine contract.
        vec![
            instruction(SET_LIMITS, [16, 1, 0, 0]),
            instruction(BEGIN_MATCH, [10, 0, 0, 0]),
            instruction(MATCH, [2, 20, 1, 4]),
            instruction(FINISH_MATCH, [0, 0, 0, 0]),
        ],
        // Case 24; order is part of the public state-machine contract.
        all_members,
        // Case 25; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_PATTERN, [17, 0, 0, 0]),
        ],
        // Case 26; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_PATTERN, [12, 0, 0, 0]),
            instruction(VISIT, [2, 30, 0, 0]),
        ],
        // Case 27; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_MATCH, [12, 0, 0, 0]),
            instruction(MATCH, [3, 2, 3, 2]),
            instruction(FINISH_MATCH, [0, 0, 0, 0]),
            instruction(CHECK_BINDING, [1, 0, 0x8000_0001, 4]),
        ],
        // Case 28; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_MATCH, [13, 0, 0, 0]),
            instruction(MATCH, [3, 14, 3, 9]),
            instruction(FINISH_MATCH, [0, 0, 0, 0]),
            instruction(CHECK_BINDING, [1, 0, 0x8000_0001, 4]),
        ],
        // Case 29; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_MATCH, [10, 0, 0, 0]),
            instruction(MATCH, [2, 20, 2, 40]),
            instruction(FINISH_MATCH, [0, 0, 0, 0]),
            instruction(CHECK_BINDING, [0, 0, 2, 40]),
        ],
        // Case 30; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_MATCH, [10, 0, 0, 0]),
            instruction(MATCH, [1, 4, 1, 3]),
            instruction(MATCH, [2, 20, 1, 4]),
            instruction(FINISH_MATCH, [0, 0, 0, 0]),
        ],
        // Case 31; order is part of the public state-machine contract.
        vec![
            instruction(BEGIN_MATCH, [10, 0, 0, 0]),
            instruction(MATCH, [2, 20, 1, 4]),
            instruction(FINISH_MATCH, [0, 0, 0, 0]),
            instruction(MATCH, [2, 20, 1, 4]),
        ],
    ];
    assert_eq!(programs.len(), CASES.len());
    assert_eq!(programs[24].len(), 66, "all 32+32 members are visited");
    let mut ranges = Vec::with_capacity(CASES.len() * 2);
    let mut operations = Vec::new();
    for program in programs {
        assert!(!program.is_empty() && program.len() <= 66);
        ranges.push(u32::try_from(operations.len() / 8).unwrap());
        ranges.push(u32::try_from(program.len()).unwrap());
        for operation in program {
            operations.extend_from_slice(&operation);
        }
    }
    (ranges, operations)
}

// Disjoint case ownership is checked before any pipeline is prepared. Fixed
// cases keep their ordinary inference setup and fixed check in one state.
const FAMILIES: [(&str, &[u32]); 4] = [
    ("tests/owned_type_constraints_match", &[0, 1, 2, 4, 19, 21, 22, 23, 27, 28, 29, 30, 31]),
    ("tests/owned_type_constraints_fixed", &[3, 5, 6, 7]),
    ("tests/owned_type_constraints_overlap", &[8, 9, 10, 11, 12, 13, 20]),
    ("tests/owned_type_constraints_coverage", &[14, 15, 16, 17, 18, 24, 25, 26]),
];

#[test]
fn physical_gpu_owned_constraints_preserve_matching_overlap_and_fixed_contracts() {
    assert!(
        !super::env::env_bool_truthy("LANIUS_ALLOW_SOFTWARE_ADAPTER", false),
        "this regression requires a physical GPU"
    );
    let mut covered = [false; CASES.len()];
    for (_, case_ids) in FAMILIES {
        assert!(!case_ids.is_empty() && case_ids.len() <= 32);
        for &id in case_ids {
            let index = usize::try_from(id).unwrap();
            assert!(index < CASES.len(), "unknown matcher case {id}");
            assert!(!covered[index], "matcher case {id} dispatched twice");
            covered[index] = true;
        }
    }
    assert!(covered.into_iter().all(|present| present), "missing matcher case");
    let gpu = device::global();
    let (range_words, operation_words) = fixture_programs();
    let ranges = storage_ro_from_u32s(&gpu.device, "owned_constraints.ranges", &range_words);
    let operations = storage_ro_from_u32s(&gpu.device, "owned_constraints.operations", &operation_words);
    let word_count = CASES.len() * 4;
    let results = storage_rw_for_array::<u32>(&gpu.device, "owned_constraints.results", word_count);
    // One thread-scratch slot per lane; family passes run in order.
    let scratch = storage_rw_for_array::<u32>(
        &gpu.device,
        "owned_constraints.thread_scratch",
        super::typed_constant_tests::thread_scratch_words(32),
    );
    let mut dispatches = Vec::with_capacity(FAMILIES.len());
    for (key, case_ids) in FAMILIES {
        let case_ids = storage_ro_from_u32s(&gpu.device, &format!("{key}.case_ids"), case_ids);
        let pass = make_pass_data_from_shader_key(&gpu.device, key, "main", key).unwrap();
        assert_eq!(pass.thread_group_size, [32, 1, 1], "one lane per selected case");
        let entries = [
            ("results", results.as_entire_binding()),
            ("fixture_ranges", ranges.as_entire_binding()),
            ("fixture_ops", operations.as_entire_binding()),
            ("fixture_case_ids", case_ids.as_entire_binding()),
            ("thread_scratch", scratch.as_entire_binding()),
        ];
        passes_core::bind_group::validate_exact_binding_names(&pass, 0, &entries).unwrap();
        let group = passes_core::bind_group::create_bind_group_from_bindings(
            &gpu.device,
            Some(key),
            &pass,
            0,
            &entries,
        )
        .unwrap();
        dispatches.push((pass, group, case_ids));
    }
    let readback = readback_bytes(
        &gpu.device,
        "owned_constraints.readback",
        word_count * 4,
        word_count,
    );
    let mut encoder = gpu
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("owned_constraints.encoder"),
        });
    // Each family writes only its disjoint case-ID rows. Separate passes keep
    // their storage effects ordered before the single unchanged readback.
    for (pass, group, _case_ids) in &dispatches {
        let mut compute = passes_core::begin_counted_compute_pass(
            &mut encoder,
            &wgpu::ComputePassDescriptor {
                label: Some("owned_constraints.compute"),
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
    results.copy_to(&mut encoder, 0, &readback, 0, (word_count * 4) as u64);
    gpu.queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    map_readback_blocking(&gpu.device, &slice, "owned_constraints.readback").unwrap();
    let mapped = slice.get_mapped_range();
    let words: Vec<u32> = mapped
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect();
    drop(mapped);
    readback.unmap();
    assert_eq!(words.len(), word_count);
    for (id, ((label, expected, detail), actual)) in
        CASES.iter().zip(words.chunks_exact(4)).enumerate()
    {
        assert_eq!(actual[0], *expected, "case {id}: {label}; row={actual:?}");
        assert_eq!(
            actual[1], *expected,
            "case {id}: host/shader case expectation disagreement"
        );
        if let Some(detail) = detail {
            assert_eq!(actual[2], *detail, "case {id}: {label}; wrong failure kind");
        }
        assert_eq!(
            actual[3], 1,
            "case {id}: {label}; binding or budget invariant failed, row={actual:?}"
        );
    }
}
