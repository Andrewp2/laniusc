import codegen.lowering_ir;

uint wasm_u32_leb_len(uint value)
{
    uint len = 1u;
    while (value >= 0x80u && len < 5u) { value >>= 7u; len += 1u; }
    return len;
}

uint wasm_i32_leb_len(uint value)
{
    int current = int(value);
    for (uint len = 1u; len <= 5u; len += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current >>= 7;
        bool sign = (byte_value & 0x40u) != 0u;
        if ((current == 0 && !sign) || (current == -1 && sign) || len == 5u)
            return len;
    }
    return 5u;
}

bool wasm_has_u32_immediate(uint opcode)
{
    return opcode == WASM_LIR_OP_CALL || opcode == WASM_LIR_OP_LOCAL_GET ||
        opcode == WASM_LIR_OP_LOCAL_SET || opcode == WASM_LIR_OP_BRANCH ||
        opcode == WASM_LIR_OP_BRANCH_IF || opcode == WASM_LIR_OP_GLOBAL_GET ||
        opcode == WASM_LIR_OP_GLOBAL_SET;
}

bool wasm_has_block_type(uint opcode)
{
    return opcode == WASM_LIR_OP_BLOCK || opcode == WASM_LIR_OP_LOOP ||
        opcode == WASM_LIR_OP_IF;
}

uint wasm_lir_byte_len(WasmLirInstruction inst)
{
    if (inst.opcode == WASM_LIR_OP_CALL_HOST) return 0u;
    // All language-function calls use a five-byte padded LEB. This is a valid
    // Wasm encoding and makes local and external call sites equally patchable
    // without changing any following byte offsets during object linking.
    if (inst.opcode == WASM_LIR_OP_CALL ||
        inst.opcode == WASM_LIR_OP_CALL_SYMBOL) return 6u;
    if (inst.opcode == WASM_LIR_OP_I32_CONST)
        return 1u + wasm_i32_leb_len(inst.immediate);
    if (inst.opcode == WASM_LIR_OP_F32_CONST) return 5u;
    if (inst.opcode == WASM_LIR_OP_I32_LOAD || inst.opcode == WASM_LIR_OP_F32_LOAD ||
        inst.opcode == WASM_LIR_OP_I32_STORE || inst.opcode == WASM_LIR_OP_F32_STORE)
        return 3u;
    if (wasm_has_u32_immediate(inst.opcode))
        return 1u + wasm_u32_leb_len(inst.immediate);
    if (wasm_has_block_type(inst.opcode)) return 2u;
    return 1u;
}

uint wasm_u32_leb_byte(uint value, uint byte_i)
{
    uint current = value >> (byte_i * 7u);
    uint byte_value = current & 0x7fu;
    return current >= 0x80u ? byte_value | 0x80u : byte_value;
}

uint wasm_i32_leb_byte(uint value, uint byte_i)
{
    int current = int(value);
    for (uint i = 0u; i < byte_i; i += 1u) current >>= 7;
    uint byte_value = uint(current) & 0x7fu;
    int next = current >> 7;
    bool sign = (byte_value & 0x40u) != 0u;
    bool done = (next == 0 && !sign) || (next == -1 && sign) || byte_i == 4u;
    return done ? byte_value : byte_value | 0x80u;
}

uint wasm_lir_byte(WasmLirInstruction inst, uint byte_i)
{
    if (inst.opcode == WASM_LIR_OP_CALL ||
        inst.opcode == WASM_LIR_OP_CALL_SYMBOL)
    {
        if (byte_i == 0u) return WASM_LIR_OP_CALL;
        uint value = inst.opcode == WASM_LIR_OP_CALL_SYMBOL ? 0u : inst.immediate;
        uint immediate_i = byte_i - 1u;
        uint byte_value = (value >> (immediate_i * 7u)) & 0x7fu;
        return immediate_i < 4u ? byte_value | 0x80u : byte_value;
    }
    if (byte_i == 0u) return inst.opcode;
    uint immediate_i = byte_i - 1u;
    if (inst.opcode == WASM_LIR_OP_I32_CONST)
        return wasm_i32_leb_byte(inst.immediate, immediate_i);
    if (inst.opcode == WASM_LIR_OP_F32_CONST)
        return (inst.immediate >> (immediate_i * 8u)) & 0xffu;
    if (inst.opcode == WASM_LIR_OP_I32_LOAD || inst.opcode == WASM_LIR_OP_F32_LOAD ||
        inst.opcode == WASM_LIR_OP_I32_STORE || inst.opcode == WASM_LIR_OP_F32_STORE)
        return immediate_i == 0u ? 2u : 0u;
    if (wasm_has_u32_immediate(inst.opcode))
        return wasm_u32_leb_byte(inst.immediate, immediate_i);
    if (wasm_has_block_type(inst.opcode)) return 0x40u;
    return 0u;
}
