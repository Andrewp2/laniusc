mod common;

const BASE: u64 = 0x400000;
const CODE: usize = 0x78;

fn elf(code: &[u8], entry_offset: usize) -> Vec<u8> {
    let mut bytes = vec![0; CODE];
    bytes[..7].copy_from_slice(b"\x7fELF\x02\x01\x01");
    bytes[16..18].copy_from_slice(&2u16.to_le_bytes());
    bytes[18..20].copy_from_slice(&62u16.to_le_bytes());
    bytes[20..24].copy_from_slice(&1u32.to_le_bytes());
    bytes[24..32].copy_from_slice(&(BASE + CODE as u64 + entry_offset as u64).to_le_bytes());
    bytes[32..40].copy_from_slice(&64u64.to_le_bytes());
    bytes[52..54].copy_from_slice(&64u16.to_le_bytes());
    bytes[54..56].copy_from_slice(&56u16.to_le_bytes());
    bytes[56..58].copy_from_slice(&1u16.to_le_bytes());
    bytes[64..68].copy_from_slice(&1u32.to_le_bytes());
    bytes[68..72].copy_from_slice(&5u32.to_le_bytes());
    bytes[80..88].copy_from_slice(&BASE.to_le_bytes());
    bytes[88..96].copy_from_slice(&BASE.to_le_bytes());
    let size = (CODE + code.len()) as u64;
    bytes[96..104].copy_from_slice(&size.to_le_bytes());
    bytes[104..112].copy_from_slice(&size.to_le_bytes());
    bytes[112..120].copy_from_slice(&0x1000u64.to_le_bytes());
    bytes.extend_from_slice(code);
    bytes
}

fn padded_entry(call_target: usize) -> Vec<u8> {
    let mut code = vec![
        0x55, 0x48, 0x89, 0xe5, // framed function before ELF entry
        0xb8, 42, 0, 0, 0, 0xc9, 0xc3,
        0, // odd padding: a linear decode swallows entry's first byte
        0x49, 0x89, 0xe7, 0xe8,
    ];
    let displacement = call_target as i32 - 20;
    code.extend_from_slice(&displacement.to_le_bytes());
    code.extend_from_slice(&[0x89, 0xc7, 0xb8, 60, 0, 0, 0, 0x0f, 0x05, 0xc3]);
    elf(&code, 12)
}

fn problems(bytes: &[u8]) -> Vec<String> {
    common::x86_jumps::check_x86_64_jumps(bytes)
        .unwrap()
        .unwrap()
        .problems
}

#[test]
fn checker_restarts_at_entry_after_odd_padding_and_keeps_backward_calls() {
    let check = common::x86_jumps::check_x86_64_jumps(&padded_entry(0))
        .unwrap()
        .unwrap();
    assert!(check.problems.is_empty(), "{:?}", check.problems);
    assert_eq!(check.functions, 2);
}

#[test]
fn checker_rejects_call_inside_pre_entry_instruction() {
    let problems = problems(&padded_entry(5)); // inside mov $42,%eax
    assert!(
        problems
            .iter()
            .any(|problem| problem.contains("not an instruction start")),
        "{problems:?}"
    );
}

#[test]
fn checker_rejects_reachable_instruction_overlapping_entry() {
    let bytes = elf(
        &[
            0x55, 0x48, 0x89, 0xe5, 0xb8, 0x90, 0x90, 0x90, 0x90, 0xc9, 0xc3,
        ],
        5,
    );
    let problems = problems(&bytes);
    assert!(
        problems
            .iter()
            .any(|problem| problem.contains("overlaps instruction")),
        "{problems:?}"
    );
}

#[test]
fn checker_rejects_reachable_malformed_and_truncated_instructions() {
    for code in [&[0x0f][..], &[0x06, 0xc3][..]] {
        let problems = problems(&elf(code, 0));
        assert!(
            problems
                .iter()
                .any(|problem| problem.contains("invalid or truncated instruction")),
            "{problems:?}"
        );
    }
}

#[test]
fn checker_rejects_out_of_segment_direct_calls_and_jumps() {
    for opcode in [0xe8, 0xe9] {
        let problems = problems(&elf(&[opcode, 0, 1, 0, 0, 0xc3], 0));
        assert!(
            problems
                .iter()
                .any(|problem| problem.contains("not an instruction start")),
            "{problems:?}"
        );
    }
}
