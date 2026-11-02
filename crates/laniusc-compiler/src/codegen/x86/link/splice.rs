//! Link-time inlining of tiny leaf functions at cross-object call sites.
//!
//! The GPU emitter follows every imported scalar call (`E8 rel32`) with the
//! four-byte NOP `0F 1F 40 00`, so each such site is a nine-byte slot. When
//! the call's resolved target is a defined text symbol whose body is at most
//! nine bytes of register-only instructions followed by `ret`, the link writes
//! that body (padded with one NOP) over the slot instead of the displacement.
//!
//! This is exact: the body reads and writes only general registers other than
//! RSP and the flags, never memory or RIP, so running it in place differs from
//! calling it only in the return address it never reads. A call clobbers every
//! register the body may write, so the caller holds nothing live in them.

use std::collections::HashMap;

use super::{GpuX86LinkInput, GpuX86LinkRelocationRecord};

/// Bytes from the start of `E8` to the end of the pad.
pub(super) const SPLICE_SLOT_BYTES: usize = 9;
const CALL_PAD: [u8; 4] = [0x0f, 0x1f, 0x40, 0x00];
const SECTION_TEXT: u32 = 1;
const RELOCATION_CALL_REL32: u32 = 2;

/// The nine bytes replacing each call slot, by relocation index (`None` keeps
/// the call). Reads only candidate callees and their sites.
pub(super) fn call_splices(
    input: &GpuX86LinkInput,
    relocations: &[GpuX86LinkRelocationRecord],
) -> Result<Vec<Option<[u8; SPLICE_SLOT_BYTES]>>, String> {
    let mut small = HashMap::new();
    for symbol in &input.symbols {
        if symbol.section == SECTION_TEXT && (2..=SPLICE_SLOT_BYTES as u32 + 1).contains(&symbol.size)
        {
            small.insert((symbol.object_index, symbol.offset), symbol.size);
        }
    }
    let mut splices = vec![None; relocations.len()];
    if small.is_empty() {
        return Ok(splices);
    }
    let mut bodies: HashMap<(u32, u32), Option<[u8; SPLICE_SLOT_BYTES]>> = HashMap::new();
    for (index, relocation) in relocations.iter().enumerate() {
        if relocation.kind != RELOCATION_CALL_REL32
            || relocation.site_section != SECTION_TEXT
            || !matches!(relocation.target_kind, 2 | super::X86_LINK_TARGET_OBJECT_SECTION)
            || relocation.target_section != SECTION_TEXT
            || relocation.addend_lo != (-4i32) as u32
            || relocation.site_offset == 0
        {
            continue;
        }
        let key = (relocation.target_index, relocation.target_offset);
        let Some(&size) = small.get(&key) else {
            continue;
        };
        let body = match bodies.get(&key) {
            Some(body) => *body,
            None => {
                let body = match text_input_offset(input, key.0, key.1, size) {
                    Some(start) => {
                        splice_bytes(&input.read_text_range_borrowed(start..start + size as usize)?)
                    }
                    None => None,
                };
                bodies.insert(key, body);
                body
            }
        };
        let Some(body) = body else {
            continue;
        };
        let Some(site) = text_input_offset(
            input,
            relocation.object_index,
            relocation.site_offset - 1,
            SPLICE_SLOT_BYTES as u32,
        ) else {
            continue;
        };
        let slot = input.read_text_range_borrowed(site..site + SPLICE_SLOT_BYTES)?;
        if slot[0] == 0xe8 && slot[5..] == CALL_PAD {
            splices[index] = Some(body);
        }
    }
    Ok(splices)
}

fn text_input_offset(
    input: &GpuX86LinkInput,
    object_index: u32,
    offset: u32,
    len: u32,
) -> Option<usize> {
    let object = input.objects.get(object_index as usize)?;
    offset
        .checked_add(len)
        .filter(|&end| end <= object.text_len)
        .map(|_| object.text_input_start as usize + offset as usize)
}

/// The slot replacement for a function body `body` (ending in `ret`), or
/// `None` when it is not a short run of register-only instructions.
pub(super) fn splice_bytes(body: &[u8]) -> Option<[u8; SPLICE_SLOT_BYTES]> {
    let (&last, code) = body.split_last()?;
    if last != 0xc3 || code.is_empty() || code.len() > SPLICE_SLOT_BYTES {
        return None;
    }
    let mut at = 0;
    while at < code.len() {
        at += register_instruction_len(&code[at..])?;
    }
    if at != code.len() {
        return None;
    }
    let mut slot = [0u8; SPLICE_SLOT_BYTES];
    slot[..code.len()].copy_from_slice(code);
    slot[code.len()..].copy_from_slice(nop(SPLICE_SLOT_BYTES - code.len()));
    Some(slot)
}

fn nop(len: usize) -> &'static [u8] {
    const NOPS: [&[u8]; 10] = [
        &[],
        &[0x90],
        &[0x66, 0x90],
        &[0x0f, 0x1f, 0x00],
        &[0x0f, 0x1f, 0x40, 0x00],
        &[0x0f, 0x1f, 0x44, 0x00, 0x00],
        &[0x66, 0x0f, 0x1f, 0x44, 0x00, 0x00],
        &[0x0f, 0x1f, 0x80, 0x00, 0x00, 0x00, 0x00],
        &[0x0f, 0x1f, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00],
        &[0x66, 0x0f, 0x1f, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00],
    ];
    NOPS[len]
}

/// Length of one whitelisted instruction at the start of `code`: an optional
/// REX prefix, then an ALU, mov, test, setcc, cmovcc, movzx/movsx, imul,
/// shift, not/neg, inc/dec or lea form whose operands are general registers
/// other than RSP (lea may address through them, never through RIP or an
/// absolute displacement). `None` for anything else.
fn register_instruction_len(code: &[u8]) -> Option<usize> {
    let mut at = 0;
    let rex = match code.first()? {
        &byte @ 0x40..=0x4f => {
            at = 1;
            byte
        }
        _ => 0,
    };
    let opcode = *code.get(at)?;
    at += 1;
    // Operand shape of the ModRM forms: byte-sized rm, byte-sized reg, the
    // allowed opcode extensions (0: reg is a register operand), immediate.
    let (rm_byte, reg_byte, extensions, mut imm) = match opcode {
        0x90 | 0x98 | 0x99 => return Some(at), // nop, cdqe/cwde, cdq/cqo
        0xb8..=0xbf if rex & 8 == 0 => {
            return (!is_rsp(opcode & 7, rex & 1, false, rex))
                .then_some(at + 4)
                .filter(|&end| end <= code.len());
        }
        0x8d => return lea_len(code, at, rex),
        0x0f => {
            let second = *code.get(at)?;
            at += 1;
            let (rm_byte, reg_used) = match second {
                0x90..=0x9f => (true, false),                    // setcc r/m8
                0xb6 | 0xbe => (true, true),                     // movzx/movsx r, r/m8
                0x40..=0x4f | 0xaf | 0xb7 | 0xbf => (false, true), // cmovcc, imul, movzx/movsx r, r/m16
                _ => return None,
            };
            let modrm = *code.get(at)?;
            at += 1;
            let reg = (modrm >> 3) & 7;
            if modrm >> 6 != 3
                || is_rsp(modrm & 7, rex & 1, rm_byte, rex)
                || (reg_used && is_rsp(reg, (rex >> 2) & 1, false, rex))
            {
                return None;
            }
            return Some(at);
        }
        // add/or/adc/sbb/and/sub/xor/cmp, test, mov: byte forms have bit 0 clear
        0x00..=0x03 | 0x08..=0x0b | 0x10..=0x13 | 0x18..=0x1b | 0x20..=0x23 | 0x28..=0x2b
        | 0x30..=0x33 | 0x38..=0x3b | 0x84 | 0x85 | 0x88..=0x8b => {
            let byte = opcode & 1 == 0;
            (byte, byte, 0u8, 0usize)
        }
        0x63 => (false, false, 0, 0), // movsxd
        0x69 => (false, false, 0, 4), // imul r, r/m, imm32
        0x6b => (false, false, 0, 1), // imul r, r/m, imm8
        0x80 => (true, false, 0xff, 1),
        0x81 => (false, false, 0xff, 4),
        0x83 => (false, false, 0xff, 1),
        0xc0 => (true, false, 0b1011_1111, 1), // rol..sar, not /6
        0xc1 => (false, false, 0b1011_1111, 1),
        0xd0 => (true, false, 0b1011_1111, 0),
        0xd1 | 0xd3 => (false, false, 0b1011_1111, 0),
        0xc7 => (false, false, 0b0000_0001, 4), // mov r/m, imm32
        0xf6 => (true, false, 0b0011_1101, 0),  // test imm8, not, neg, mul, imul
        0xf7 => (false, false, 0b0011_1101, 0), // test imm32, not, neg, mul, imul
        0xfe => (true, false, 0b0000_0011, 0),  // inc, dec
        0xff => (false, false, 0b0000_0011, 0),
        _ => return None,
    };
    let modrm = *code.get(at)?;
    at += 1;
    let reg = (modrm >> 3) & 7;
    if modrm >> 6 != 3 || is_rsp(modrm & 7, rex & 1, rm_byte, rex) {
        return None;
    }
    if extensions == 0 {
        if is_rsp(reg, (rex >> 2) & 1, reg_byte, rex) {
            return None;
        }
    } else {
        if extensions & (1 << reg) == 0 {
            return None;
        }
        if reg == 0 && (opcode == 0xf6 || opcode == 0xf7) {
            imm = if opcode == 0xf6 { 1 } else { 4 };
        }
    }
    (at + imm <= code.len()).then_some(at + imm)
}

/// `lea reg, [base (+ index*scale) (+ disp)]` with no RIP-relative or
/// absolute address and no RSP destination or base.
fn lea_len(code: &[u8], mut at: usize, rex: u8) -> Option<usize> {
    let modrm = *code.get(at)?;
    at += 1;
    let mode = modrm >> 6;
    if mode == 3 || is_rsp((modrm >> 3) & 7, (rex >> 2) & 1, false, rex) {
        return None;
    }
    let mut base = modrm & 7;
    if base == 4 {
        let sib = *code.get(at)?;
        at += 1;
        base = sib & 7;
    }
    if (mode == 0 && base == 5) || is_rsp(base, rex & 1, false, rex) {
        return None;
    }
    at += [0, 1, 4][mode as usize];
    (at <= code.len()).then_some(at)
}

/// Whether register field `low` (with its REX extension bit) names RSP, SPL,
/// or, for a byte operand without REX, one of AH..BH (encodings 4..7).
fn is_rsp(low: u8, extension: u8, byte: bool, rex: u8) -> bool {
    let full = low | (extension << 3);
    full == 4 || (byte && rex == 0 && low >= 4)
}

#[cfg(test)]
mod tests {
    use super::splice_bytes;

    #[test]
    fn splices_register_compare_bodies() {
        // cmp edi, esi; setl al; movzx eax, al; ret
        let lt = [0x39, 0xf7, 0x0f, 0x9c, 0xc0, 0x0f, 0xb6, 0xc0, 0xc3];
        assert_eq!(
            splice_bytes(&lt),
            Some([0x39, 0xf7, 0x0f, 0x9c, 0xc0, 0x0f, 0xb6, 0xc0, 0x90])
        );
        // cmp rdi, rsi; setl al; movzx eax, al; ret
        let lt64 = [0x48, 0x39, 0xf7, 0x0f, 0x9c, 0xc0, 0x0f, 0xb6, 0xc0, 0xc3];
        assert_eq!(splice_bytes(&lt64), Some([0x48, 0x39, 0xf7, 0x0f, 0x9c, 0xc0, 0x0f, 0xb6, 0xc0]));
        // lea eax, [rdi + rsi]; ret
        assert_eq!(
            splice_bytes(&[0x8d, 0x04, 0x37, 0xc3]),
            Some([0x8d, 0x04, 0x37, 0x66, 0x0f, 0x1f, 0x44, 0x00, 0x00])
        );
        // mov eax, edi; ret
        assert_eq!(
            splice_bytes(&[0x89, 0xf8, 0xc3]),
            Some([0x89, 0xf8, 0x0f, 0x1f, 0x80, 0x00, 0x00, 0x00, 0x00])
        );
    }

    #[test]
    fn keeps_calls_to_bodies_that_touch_memory_rsp_or_control() {
        for body in [
            &[0x8b, 0x07, 0xc3][..],                         // mov eax, [rdi]
            &[0x48, 0x89, 0xe0, 0xc3],                       // mov rax, rsp
            &[0x48, 0x8d, 0x04, 0x24, 0xc3],                 // lea rax, [rsp]
            &[0x8d, 0x05, 0, 0, 0, 0, 0xc3],                 // lea eax, [rip]
            &[0xe8, 0, 0, 0, 0, 0xc3],                       // call
            &[0x74, 0x00, 0xc3],                             // je
            &[0x53, 0xc3],                                   // push rbx
            &[0xf7, 0xf6, 0xc3],                             // div esi
            &[0x48, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0xc3],     // movabs
            &[0x89, 0xf8],                                   // no ret
            &[0xc3],                                         // empty
            &[0x31, 0xc0, 0x31, 0xc0, 0x31, 0xc0, 0x31, 0xc0, 0x31, 0xc0, 0xc3], // > 9 bytes
            &[0x88, 0xe0, 0xc3],                             // mov al, ah
        ] {
            assert_eq!(splice_bytes(body), None, "{body:02x?}");
        }
    }
}
