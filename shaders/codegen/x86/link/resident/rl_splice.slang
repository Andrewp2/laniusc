// Link-time inlining of tiny leaf bodies at call slots: a port of
// codegen/x86/link/splice.rs `splice_bytes`. A body of at most nine bytes of
// register-only instructions followed by `ret` replaces the nine-byte slot
// `E8 rel32 0F 1F 40 00`, padded with one NOP. The body is read in place:
// byte i of the copied text of `object` at `offset`.

import codegen.x86.link.resident.rl_common;

public static const uint SPLICE_SLOT_BYTES = 9u;

public uint code_at(uint object, uint offset, uint i)
{
    return object_text_byte(object, object_word(object, OB_COPY_START) + offset + i);
}

bool is_rsp(uint low, uint extension, bool byte_operand, uint rex)
{
    uint full = low | (extension << 3u);
    return full == 4u || (byte_operand && rex == 0u && low >= 4u);
}

// Length of `lea` from `at` (after the opcode), or 0.
uint lea_len(uint object, uint offset, uint len, uint at, uint rex)
{
    if (at >= len)
        return 0u;
    uint modrm = code_at(object, offset, at);
    at += 1u;
    uint mode = modrm >> 6u;
    if (mode == 3u || is_rsp((modrm >> 3u) & 7u, (rex >> 2u) & 1u, false, rex))
        return 0u;
    uint base = modrm & 7u;
    if (base == 4u)
    {
        if (at >= len)
            return 0u;
        uint sib = code_at(object, offset, at);
        at += 1u;
        base = sib & 7u;
    }
    if ((mode == 0u && base == 5u) || is_rsp(base, rex & 1u, false, rex))
        return 0u;
    at += mode == 0u ? 0u : (mode == 1u ? 1u : 4u);
    return at <= len ? at : 0u;
}

bool in_range(uint value, uint low, uint high) { return value >= low && value <= high; }

// Length of one whitelisted instruction at `start` of code_at(object, offset, 0..len), or 0.
uint register_instruction_len(uint object, uint offset, uint len, uint start)
{
    uint at = start;
    if (at >= len)
        return 0u;
    uint rex = 0u;
    if (in_range(code_at(object, offset, at), 0x40u, 0x4fu))
    {
        rex = code_at(object, offset, at);
        at += 1u;
    }
    if (at >= len)
        return 0u;
    uint opcode = code_at(object, offset, at);
    at += 1u;
    bool rm_byte;
    bool reg_byte;
    uint extensions;
    uint imm;
    if (opcode == 0x90u || opcode == 0x98u || opcode == 0x99u)
        return at - start;
    if (in_range(opcode, 0xb8u, 0xbfu) && (rex & 8u) == 0u)
    {
        if (is_rsp(opcode & 7u, rex & 1u, false, rex) || at + 4u > len)
            return 0u;
        return at + 4u - start;
    }
    if (opcode == 0x8du)
    {
        uint end = lea_len(object, offset, len, at, rex);
        return end == 0u ? 0u : end - start;
    }
    if (opcode == 0x0fu)
    {
        if (at >= len)
            return 0u;
        uint second = code_at(object, offset, at);
        at += 1u;
        bool second_rm_byte;
        bool reg_used;
        if (in_range(second, 0x90u, 0x9fu)) { second_rm_byte = true; reg_used = false; }
        else if (second == 0xb6u || second == 0xbeu) { second_rm_byte = true; reg_used = true; }
        else if (in_range(second, 0x40u, 0x4fu) || second == 0xafu || second == 0xb7u || second == 0xbfu)
        { second_rm_byte = false; reg_used = true; }
        else
            return 0u;
        if (at >= len)
            return 0u;
        uint modrm2 = code_at(object, offset, at);
        at += 1u;
        uint reg2 = (modrm2 >> 3u) & 7u;
        if ((modrm2 >> 6u) != 3u || is_rsp(modrm2 & 7u, rex & 1u, second_rm_byte, rex) ||
            (reg_used && is_rsp(reg2, (rex >> 2u) & 1u, false, rex)))
            return 0u;
        return at - start;
    }
    if (in_range(opcode, 0x00u, 0x03u) || in_range(opcode, 0x08u, 0x0bu) ||
        in_range(opcode, 0x10u, 0x13u) || in_range(opcode, 0x18u, 0x1bu) ||
        in_range(opcode, 0x20u, 0x23u) || in_range(opcode, 0x28u, 0x2bu) ||
        in_range(opcode, 0x30u, 0x33u) || in_range(opcode, 0x38u, 0x3bu) ||
        opcode == 0x84u || opcode == 0x85u || in_range(opcode, 0x88u, 0x8bu))
    {
        bool byte_form = (opcode & 1u) == 0u;
        rm_byte = byte_form; reg_byte = byte_form; extensions = 0u; imm = 0u;
    }
    else if (opcode == 0x63u) { rm_byte = false; reg_byte = false; extensions = 0u; imm = 0u; }
    else if (opcode == 0x69u) { rm_byte = false; reg_byte = false; extensions = 0u; imm = 4u; }
    else if (opcode == 0x6bu) { rm_byte = false; reg_byte = false; extensions = 0u; imm = 1u; }
    else if (opcode == 0x80u) { rm_byte = true; reg_byte = false; extensions = 0xffu; imm = 1u; }
    else if (opcode == 0x81u) { rm_byte = false; reg_byte = false; extensions = 0xffu; imm = 4u; }
    else if (opcode == 0x83u) { rm_byte = false; reg_byte = false; extensions = 0xffu; imm = 1u; }
    else if (opcode == 0xc0u) { rm_byte = true; reg_byte = false; extensions = 0xbfu; imm = 1u; }
    else if (opcode == 0xc1u) { rm_byte = false; reg_byte = false; extensions = 0xbfu; imm = 1u; }
    else if (opcode == 0xd0u) { rm_byte = true; reg_byte = false; extensions = 0xbfu; imm = 0u; }
    else if (opcode == 0xd1u || opcode == 0xd3u) { rm_byte = false; reg_byte = false; extensions = 0xbfu; imm = 0u; }
    else if (opcode == 0xc7u) { rm_byte = false; reg_byte = false; extensions = 0x01u; imm = 4u; }
    else if (opcode == 0xf6u) { rm_byte = true; reg_byte = false; extensions = 0x3du; imm = 0u; }
    else if (opcode == 0xf7u) { rm_byte = false; reg_byte = false; extensions = 0x3du; imm = 0u; }
    else if (opcode == 0xfeu) { rm_byte = true; reg_byte = false; extensions = 0x03u; imm = 0u; }
    else if (opcode == 0xffu) { rm_byte = false; reg_byte = false; extensions = 0x03u; imm = 0u; }
    else
        return 0u;
    if (at >= len)
        return 0u;
    uint modrm = code_at(object, offset, at);
    at += 1u;
    uint reg = (modrm >> 3u) & 7u;
    if ((modrm >> 6u) != 3u || is_rsp(modrm & 7u, rex & 1u, rm_byte, rex))
        return 0u;
    if (extensions == 0u)
    {
        if (is_rsp(reg, (rex >> 2u) & 1u, reg_byte, rex))
            return 0u;
    }
    else
    {
        if ((extensions & (1u << reg)) == 0u)
            return 0u;
        if (reg == 0u && (opcode == 0xf6u || opcode == 0xf7u))
            imm = opcode == 0xf6u ? 1u : 4u;
    }
    return at + imm <= len ? at + imm - start : 0u;
}

uint nop_byte(uint len, uint i)
{
    // NOPS[len][i] of splice.rs.
    if (len == 1u) return 0x90u;
    if (len == 2u) return i == 0u ? 0x66u : 0x90u;
    if (len == 3u) return i == 0u ? 0x0fu : (i == 1u ? 0x1fu : 0x00u);
    if (len == 4u) return i == 0u ? 0x0fu : (i == 1u ? 0x1fu : (i == 2u ? 0x40u : 0x00u));
    if (len == 5u) return i == 0u ? 0x0fu : (i == 1u ? 0x1fu : (i == 2u ? 0x44u : 0x00u));
    if (len == 6u) return i == 0u ? 0x66u : (i == 1u ? 0x0fu : (i == 2u ? 0x1fu : (i == 3u ? 0x44u : 0x00u)));
    if (len == 7u) return i == 0u ? 0x0fu : (i == 1u ? 0x1fu : (i == 2u ? 0x80u : 0x00u));
    if (len == 8u) return i == 0u ? 0x0fu : (i == 1u ? 0x1fu : (i == 2u ? 0x84u : 0x00u));
    if (len == 9u) return i == 0u ? 0x66u : (i == 1u ? 0x0fu : (i == 2u ? 0x1fu : (i == 3u ? 0x84u : 0x00u)));
    return 0u;
}

// Whether the body of `body_len` bytes (ending in `ret`) is a short run of
// register-only instructions; its code is then `body_len - 1` bytes.
public bool splice_ok(uint object, uint offset, uint body_len)
{
    if (body_len == 0u || code_at(object, offset, body_len - 1u) != 0xc3u)
        return false;
    uint code_len = body_len - 1u;
    if (code_len == 0u || code_len > SPLICE_SLOT_BYTES)
        return false;
    uint at = 0u;
    for (uint step = 0u; step < 10u && at < code_len; step += 1u)
    {
        uint len = register_instruction_len(object, offset, code_len, at);
        if (len == 0u)
            return false;
        at += len;
    }
    return at == code_len;
}

// Byte i of the slot replacement: the code, then one NOP.
public uint splice_slot_byte(uint object, uint offset, uint code_len, uint i)
{
    return i < code_len ? code_at(object, offset, i) : nop_byte(SPLICE_SLOT_BYTES - code_len, i - code_len);
}
