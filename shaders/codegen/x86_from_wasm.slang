struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> body_words;
StructuredBuffer<uint> body_status;
StructuredBuffer<uint> bool_body_words;
StructuredBuffer<uint> bool_body_status;
StructuredBuffer<uint> functions_words;
StructuredBuffer<uint> functions_status;
StructuredBuffer<uint> reg_map;
StructuredBuffer<uint> reg_status;
RWStructuredBuffer<uint> out_words;
RWStructuredBuffer<uint> status;

static const uint BASE_VADDR = 0x400000u;
static const uint ELF_HEADER_SIZE = 64u;
static const uint PHDR_SIZE = 56u;
static const uint CODE_OFF = 256u;
static const uint ENTRY_SLOT_SIZE = 128u;
static const uint FUNCTION_SLOT_SIZE = 1024u;
static const uint MAX_FUNCTIONS = 8u;
static const uint FUNCTIONS_BASE = CODE_OFF + ENTRY_SLOT_SIZE;
static const uint HELPER_OFF = FUNCTIONS_BASE + FUNCTION_SLOT_SIZE * MAX_FUNCTIONS;
static const uint PRINT_HELPER_SIZE = 129u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

void put_byte(inout uint cursor, uint value, uint target)
{
    if (cursor < gParams.out_capacity && cursor == target)
        out_words[cursor] = value & 0xffu;
    cursor += 1u;
}

void put_byte_at(uint cursor, uint value, uint target)
{
    if (cursor < gParams.out_capacity && cursor == target)
        out_words[cursor] = value & 0xffu;
}

void put_u16(inout uint cursor, uint value, uint lane)
{
    put_byte(cursor, value, lane);
    put_byte(cursor, value >> 8u, lane);
}

void put_u32(inout uint cursor, uint value, uint lane)
{
    [unroll]
    for (uint i = 0u; i < 4u; i += 1u)
        put_byte(cursor, value >> (i * 8u), lane);
}

void put_u64(inout uint cursor, uint lo, uint hi, uint lane)
{
    put_u32(cursor, lo, lane);
    put_u32(cursor, hi, lane);
}

void patch_u32(uint cursor, uint value, uint lane)
{
    [unroll]
    for (uint i = 0u; i < 4u; i += 1u)
        put_byte_at(cursor + i, value >> (i * 8u), lane);
}

void patch_u64(uint cursor, uint lo, uint hi, uint lane)
{
    patch_u32(cursor, lo, lane);
    patch_u32(cursor + 4u, hi, lane);
}

void pad_to(inout uint cursor, uint target, uint lane)
{
    [loop]
    while (cursor < target && cursor < gParams.out_capacity)
        put_byte(cursor, 0x90u, lane);
}

void emit_elf_header(inout uint cursor, uint lane)
{
    put_byte(cursor, 0x7fu, lane);
    put_byte(cursor, 0x45u, lane);
    put_byte(cursor, 0x4cu, lane);
    put_byte(cursor, 0x46u, lane);
    put_byte(cursor, 0x02u, lane);
    put_byte(cursor, 0x01u, lane);
    put_byte(cursor, 0x01u, lane);
    put_byte(cursor, 0x00u, lane);
    [unroll]
    for (uint i = 0u; i < 8u; i += 1u)
        put_byte(cursor, 0u, lane);
    put_u16(cursor, 2u, lane);
    put_u16(cursor, 0x3eu, lane);
    put_u32(cursor, 1u, lane);
    put_u64(cursor, BASE_VADDR + CODE_OFF, 0u, lane);
    put_u64(cursor, ELF_HEADER_SIZE, 0u, lane);
    put_u64(cursor, 0u, 0u, lane);
    put_u32(cursor, 0u, lane);
    put_u16(cursor, ELF_HEADER_SIZE, lane);
    put_u16(cursor, PHDR_SIZE, lane);
    put_u16(cursor, 1u, lane);
    put_u16(cursor, 0u, lane);
    put_u16(cursor, 0u, lane);
    put_u16(cursor, 0u, lane);

    put_u32(cursor, 1u, lane);
    put_u32(cursor, 5u, lane);
    put_u64(cursor, 0u, 0u, lane);
    put_u64(cursor, BASE_VADDR, 0u, lane);
    put_u64(cursor, BASE_VADDR, 0u, lane);
    put_u64(cursor, 0u, 0u, lane);
    put_u64(cursor, 0u, 0u, lane);
    put_u64(cursor, 0x1000u, 0u, lane);
}

void patch_elf_sizes(uint file_size, uint lane)
{
    patch_u64(ELF_HEADER_SIZE + 32u, file_size, 0u, lane);
    patch_u64(ELF_HEADER_SIZE + 40u, file_size, 0u, lane);
}

uint wasm_byte(uint i, bool use_functions, bool use_bool_body)
{
    if (use_functions)
        return functions_words[i] & 0xffu;
    if (use_bool_body)
        return bool_body_words[i] & 0xffu;
    return body_words[i] & 0xffu;
}

uint read_u32_leb(inout uint pc, bool use_functions, bool use_bool_body)
{
    uint value = 0u;
    uint shift = 0u;
    [loop]
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint b = wasm_byte(pc, use_functions, use_bool_body);
        pc += 1u;
        value |= (b & 0x7fu) << shift;
        if ((b & 0x80u) == 0u)
            break;
        shift += 7u;
    }
    return value;
}

void read_i64_const(inout uint pc, bool use_functions, bool use_bool_body, inout uint lo, inout uint hi)
{
    lo = 0u;
    hi = 0u;
    uint shift = 0u;
    uint last = 0u;
    [loop]
    for (uint i = 0u; i < 10u; i += 1u)
    {
        uint b = wasm_byte(pc, use_functions, use_bool_body);
        pc += 1u;
        last = b;
        uint bits = b & 0x7fu;
        if (shift < 32u)
        {
            lo |= bits << shift;
            if (shift > 25u)
                hi |= bits >> (32u - shift);
        }
        else
        {
            hi |= bits << (shift - 32u);
        }
        if ((b & 0x80u) == 0u)
            break;
        shift += 7u;
    }
    if ((last & 0x40u) != 0u)
    {
        if (shift < 32u)
        {
            lo |= 0xffffffffu << shift;
            hi = 0xffffffffu;
        }
        else if (shift < 64u)
        {
            hi |= 0xffffffffu << (shift - 32u);
        }
    }
}

int stack_disp(uint local_i)
{
    return -int((local_i + 1u) * 8u);
}

uint stack_size()
{
    uint bytes = (gParams.n_tokens + 32u) * 8u;
    return (bytes + 15u) & 0xfffffff0u;
}

void emit_prologue(inout uint cursor, uint lane)
{
    put_byte(cursor, 0x55u, lane);
    put_byte(cursor, 0x48u, lane);
    put_byte(cursor, 0x89u, lane);
    put_byte(cursor, 0xe5u, lane);
    put_byte(cursor, 0x48u, lane);
    put_byte(cursor, 0x81u, lane);
    put_byte(cursor, 0xecu, lane);
    put_u32(cursor, stack_size(), lane);
}

void emit_epilogue(inout uint cursor, uint lane)
{
    put_byte(cursor, 0xc9u, lane);
    put_byte(cursor, 0xc3u, lane);
}

void emit_exit(inout uint cursor, uint lane)
{
    put_byte(cursor, 0xb8u, lane);
    put_u32(cursor, 60u, lane);
    put_byte(cursor, 0x31u, lane);
    put_byte(cursor, 0xffu, lane);
    put_byte(cursor, 0x0fu, lane);
    put_byte(cursor, 0x05u, lane);
}

void emit_exit_code(inout uint cursor, uint code, uint lane)
{
    put_byte(cursor, 0xb8u, lane);
    put_u32(cursor, 60u, lane);
    put_byte(cursor, 0xbfu, lane);
    put_u32(cursor, code, lane);
    put_byte(cursor, 0x0fu, lane);
    put_byte(cursor, 0x05u, lane);
}

void emit_mov_rax_imm64(inout uint cursor, uint lo, uint hi, uint lane)
{
    put_byte(cursor, 0x48u, lane);
    put_byte(cursor, 0xb8u, lane);
    put_u64(cursor, lo, hi, lane);
}

void emit_load_local(inout uint cursor, uint local_i, uint lane)
{
    put_byte(cursor, 0x48u, lane);
    put_byte(cursor, 0x8bu, lane);
    put_byte(cursor, 0x85u, lane);
    put_u32(cursor, uint(stack_disp(local_i)), lane);
}

void emit_store_local(inout uint cursor, uint local_i, uint lane)
{
    put_byte(cursor, 0x48u, lane);
    put_byte(cursor, 0x89u, lane);
    put_byte(cursor, 0x85u, lane);
    put_u32(cursor, uint(stack_disp(local_i)), lane);
}

void emit_store_local_rdi(inout uint cursor, uint local_i, uint lane)
{
    put_byte(cursor, 0x48u, lane);
    put_byte(cursor, 0x89u, lane);
    put_byte(cursor, 0xbdu, lane);
    put_u32(cursor, uint(stack_disp(local_i)), lane);
}

void emit_store_local_rsi(inout uint cursor, uint local_i, uint lane)
{
    put_byte(cursor, 0x48u, lane);
    put_byte(cursor, 0x89u, lane);
    put_byte(cursor, 0xb5u, lane);
    put_u32(cursor, uint(stack_disp(local_i)), lane);
}

void emit_push_rax(inout uint cursor, uint lane) { put_byte(cursor, 0x50u, lane); }
void emit_pop_rax(inout uint cursor, uint lane) { put_byte(cursor, 0x58u, lane); }
void emit_pop_rbx(inout uint cursor, uint lane) { put_byte(cursor, 0x5bu, lane); }
void emit_pop_rcx(inout uint cursor, uint lane) { put_byte(cursor, 0x59u, lane); }
void emit_pop_rdi(inout uint cursor, uint lane) { put_byte(cursor, 0x5fu, lane); }
void emit_pop_rsi(inout uint cursor, uint lane) { put_byte(cursor, 0x5eu, lane); }

void emit_call_abs(inout uint cursor, uint target, uint lane)
{
    put_byte(cursor, 0xe8u, lane);
    uint imm_pos = cursor;
    put_u32(cursor, target - (imm_pos + 4u), lane);
}

void emit_jmp_abs(inout uint cursor, uint target, uint lane)
{
    put_byte(cursor, 0xe9u, lane);
    uint imm_pos = cursor;
    put_u32(cursor, target - (imm_pos + 4u), lane);
}

uint emit_jmp_placeholder(inout uint cursor, uint lane)
{
    put_byte(cursor, 0xe9u, lane);
    uint imm_pos = cursor;
    put_u32(cursor, 0u, lane);
    return imm_pos;
}

uint emit_jz_placeholder(inout uint cursor, uint lane)
{
    emit_pop_rax(cursor, lane);
    put_byte(cursor, 0x48u, lane);
    put_byte(cursor, 0x85u, lane);
    put_byte(cursor, 0xc0u, lane);
    put_byte(cursor, 0x0fu, lane);
    put_byte(cursor, 0x84u, lane);
    uint imm_pos = cursor;
    put_u32(cursor, 0u, lane);
    return imm_pos;
}

uint emit_jnz_placeholder(inout uint cursor, uint lane)
{
    emit_pop_rax(cursor, lane);
    put_byte(cursor, 0x48u, lane);
    put_byte(cursor, 0x85u, lane);
    put_byte(cursor, 0xc0u, lane);
    put_byte(cursor, 0x0fu, lane);
    put_byte(cursor, 0x85u, lane);
    uint imm_pos = cursor;
    put_u32(cursor, 0u, lane);
    return imm_pos;
}

void patch_rel32(uint imm_pos, uint target, uint lane)
{
    patch_u32(imm_pos, target - (imm_pos + 4u), lane);
}

void emit_setcc_rax(inout uint cursor, uint cc, uint lane)
{
    put_byte(cursor, 0x0fu, lane);
    put_byte(cursor, cc, lane);
    put_byte(cursor, 0xc0u, lane);
    put_byte(cursor, 0x48u, lane);
    put_byte(cursor, 0x0fu, lane);
    put_byte(cursor, 0xb6u, lane);
    put_byte(cursor, 0xc0u, lane);
}

void emit_boolify_rax(inout uint cursor, uint lane)
{
    put_byte(cursor, 0x48u, lane);
    put_byte(cursor, 0x83u, lane);
    put_byte(cursor, 0xf8u, lane);
    put_byte(cursor, 0x00u, lane);
    emit_setcc_rax(cursor, 0x95u, lane);
}

void emit_eqz(inout uint cursor, uint lane)
{
    emit_pop_rax(cursor, lane);
    put_byte(cursor, 0x48u, lane);
    put_byte(cursor, 0x83u, lane);
    put_byte(cursor, 0xf8u, lane);
    put_byte(cursor, 0x00u, lane);
    emit_setcc_rax(cursor, 0x94u, lane);
    emit_push_rax(cursor, lane);
}

void emit_select(inout uint cursor, uint lane)
{
    emit_pop_rcx(cursor, lane);
    emit_pop_rbx(cursor, lane);
    emit_pop_rax(cursor, lane);
    put_byte(cursor, 0x48u, lane);
    put_byte(cursor, 0x85u, lane);
    put_byte(cursor, 0xc9u, lane);
    put_byte(cursor, 0x48u, lane);
    put_byte(cursor, 0x0fu, lane);
    put_byte(cursor, 0x44u, lane);
    put_byte(cursor, 0xc3u, lane);
    emit_push_rax(cursor, lane);
}

void emit_binary_op(inout uint cursor, uint op, uint lane)
{
    emit_pop_rbx(cursor, lane);
    emit_pop_rax(cursor, lane);
    if (op == 0x7cu)
    {
        put_byte(cursor, 0x48u, lane); put_byte(cursor, 0x01u, lane); put_byte(cursor, 0xd8u, lane);
    }
    else if (op == 0x7du)
    {
        put_byte(cursor, 0x48u, lane); put_byte(cursor, 0x29u, lane); put_byte(cursor, 0xd8u, lane);
    }
    else if (op == 0x7eu)
    {
        put_byte(cursor, 0x48u, lane); put_byte(cursor, 0x0fu, lane); put_byte(cursor, 0xafu, lane); put_byte(cursor, 0xc3u, lane);
    }
    else if (op == 0x7fu || op == 0x81u)
    {
        put_byte(cursor, 0x48u, lane); put_byte(cursor, 0x99u, lane);
        put_byte(cursor, 0x48u, lane); put_byte(cursor, 0xf7u, lane); put_byte(cursor, 0xfbu, lane);
        if (op == 0x81u)
        {
            put_byte(cursor, 0x48u, lane); put_byte(cursor, 0x89u, lane); put_byte(cursor, 0xd0u, lane);
        }
    }
    else if (op == 0x83u || op == 0x71u)
    {
        put_byte(cursor, 0x48u, lane); put_byte(cursor, 0x21u, lane); put_byte(cursor, 0xd8u, lane);
    }
    else if (op == 0x84u || op == 0x72u)
    {
        put_byte(cursor, 0x48u, lane); put_byte(cursor, 0x09u, lane); put_byte(cursor, 0xd8u, lane);
    }
    else if (op == 0x85u)
    {
        put_byte(cursor, 0x48u, lane); put_byte(cursor, 0x31u, lane); put_byte(cursor, 0xd8u, lane);
    }
    else if (op == 0x86u || op == 0x87u)
    {
        put_byte(cursor, 0x48u, lane); put_byte(cursor, 0x89u, lane); put_byte(cursor, 0xd9u, lane);
        if (op == 0x86u)
        {
            put_byte(cursor, 0x48u, lane); put_byte(cursor, 0xd3u, lane); put_byte(cursor, 0xe0u, lane);
        }
        else
        {
            put_byte(cursor, 0x48u, lane); put_byte(cursor, 0xd3u, lane); put_byte(cursor, 0xf8u, lane);
        }
    }
    else
    {
        put_byte(cursor, 0x48u, lane); put_byte(cursor, 0x39u, lane); put_byte(cursor, 0xd8u, lane);
        if (op == 0x46u || op == 0x51u) emit_setcc_rax(cursor, 0x94u, lane);
        else if (op == 0x52u) emit_setcc_rax(cursor, 0x95u, lane);
        else if (op == 0x53u) emit_setcc_rax(cursor, 0x9cu, lane);
        else if (op == 0x55u) emit_setcc_rax(cursor, 0x9fu, lane);
        else if (op == 0x57u) emit_setcc_rax(cursor, 0x9eu, lane);
        else emit_setcc_rax(cursor, 0x9du, lane);
    }
    emit_push_rax(cursor, lane);
}

bool is_binary_wasm_op(uint op)
{
    return op == 0x7cu || op == 0x7du || op == 0x7eu || op == 0x7fu ||
           op == 0x81u || op == 0x83u || op == 0x84u || op == 0x85u ||
           op == 0x86u || op == 0x87u || op == 0x46u || op == 0x51u ||
           op == 0x52u || op == 0x53u || op == 0x55u || op == 0x57u ||
           op == 0x59u || op == 0x71u || op == 0x72u;
}

uint function_slot(uint order)
{
    return FUNCTIONS_BASE + order * FUNCTION_SLOT_SIZE;
}

bool translate_wasm_body(
    bool use_functions,
    bool use_bool_body,
    uint body_start,
    uint body_end,
    bool is_function,
    uint arity,
    uint func_arities[16],
    inout uint cursor, uint lane)
{
    emit_prologue(cursor, lane);
    if (is_function)
    {
        if (arity > 0u)
            emit_store_local_rdi(cursor, 0u, lane);
        if (arity > 1u)
            emit_store_local_rsi(cursor, 1u, lane);
    }

    uint pc = body_start;
    uint local_groups = read_u32_leb(pc, use_functions, use_bool_body);
    [loop]
    for (uint g = 0u; g < local_groups && pc < body_end; g += 1u)
    {
        read_u32_leb(pc, use_functions, use_bool_body);
        pc += 1u;
    }

    uint ctrl_type[64];
    uint ctrl_start[64];
    uint ctrl_jz[64];
    uint ctrl_jmp_end[64];
    uint ctrl_top = 0u;
    uint br_frame[128];
    uint br_patch[128];
    uint br_top = 0u;

    [loop]
    while (pc < body_end)
    {
        uint op = wasm_byte(pc, use_functions, use_bool_body);
        pc += 1u;
        if (op == 0x0bu)
        {
            if (ctrl_top == 0u)
            {
                emit_pop_rax(cursor, lane);
                if (is_function)
                    emit_epilogue(cursor, lane);
                break;
            }
            uint frame = ctrl_top - 1u;
            if (ctrl_type[frame] == 3u)
            {
                if (ctrl_jmp_end[frame] != INVALID)
                    patch_rel32(ctrl_jmp_end[frame], cursor, lane);
                else
                    patch_rel32(ctrl_jz[frame], cursor, lane);
            }
            [loop]
            for (uint p = 0u; p < br_top; p += 1u)
            {
                if (br_frame[p] == frame)
                    patch_rel32(br_patch[p], cursor, lane);
            }
            ctrl_top = frame;
        }
        else if (op == 0x00u)
        {
            emit_exit_code(cursor, 101u, lane);
        }
        else if (op == 0x02u || op == 0x03u)
        {
            pc += 1u;
            if (ctrl_top < 64u)
            {
                ctrl_type[ctrl_top] = op == 0x03u ? 2u : 1u;
                ctrl_start[ctrl_top] = cursor;
                ctrl_jz[ctrl_top] = INVALID;
                ctrl_jmp_end[ctrl_top] = INVALID;
                ctrl_top += 1u;
            }
        }
        else if (op == 0x04u)
        {
            pc += 1u;
            uint jz = emit_jz_placeholder(cursor, lane);
            if (ctrl_top < 64u)
            {
                ctrl_type[ctrl_top] = 3u;
                ctrl_start[ctrl_top] = cursor;
                ctrl_jz[ctrl_top] = jz;
                ctrl_jmp_end[ctrl_top] = INVALID;
                ctrl_top += 1u;
            }
        }
        else if (op == 0x05u)
        {
            if (ctrl_top > 0u)
            {
                uint frame = ctrl_top - 1u;
                uint jmp_end = emit_jmp_placeholder(cursor, lane);
                patch_rel32(ctrl_jz[frame], cursor, lane);
                ctrl_jmp_end[frame] = jmp_end;
            }
        }
        else if (op == 0x0cu || op == 0x0du)
        {
            uint label = read_u32_leb(pc, use_functions, use_bool_body);
            if (label < ctrl_top)
            {
                uint frame = ctrl_top - 1u - label;
                if (ctrl_type[frame] == 2u)
                {
                    if (op == 0x0du)
                    {
                        uint patch = emit_jnz_placeholder(cursor, lane);
                        patch_rel32(patch, ctrl_start[frame], lane);
                    }
                    else
                    {
                        emit_jmp_abs(cursor, ctrl_start[frame], lane);
                    }
                }
                else
                {
                    uint patch = op == 0x0du ? emit_jnz_placeholder(cursor, lane) : emit_jmp_placeholder(cursor, lane);
                    if (br_top < 128u)
                    {
                        br_frame[br_top] = frame;
                        br_patch[br_top] = patch;
                        br_top += 1u;
                    }
                }
            }
        }
        else if (op == 0x0fu)
        {
            emit_pop_rax(cursor, lane);
            emit_epilogue(cursor, lane);
        }
        else if (op == 0x10u)
        {
            uint callee = read_u32_leb(pc, use_functions, use_bool_body);
            if (callee == 0u)
            {
                emit_pop_rdi(cursor, lane);
                emit_call_abs(cursor, HELPER_OFF, lane);
            }
            else
            {
                uint order = callee - 1u;
                uint call_arity = order < 16u ? func_arities[order] : 0u;
                if (call_arity > 1u)
                    emit_pop_rsi(cursor, lane);
                if (call_arity > 0u)
                    emit_pop_rdi(cursor, lane);
                emit_call_abs(cursor, function_slot(order), lane);
                emit_push_rax(cursor, lane);
            }
        }
        else if (op == 0x20u)
        {
            uint local_i = read_u32_leb(pc, use_functions, use_bool_body);
            emit_load_local(cursor, local_i, lane);
            emit_push_rax(cursor, lane);
        }
        else if (op == 0x21u)
        {
            uint local_i = read_u32_leb(pc, use_functions, use_bool_body);
            emit_pop_rax(cursor, lane);
            emit_store_local(cursor, local_i, lane);
        }
        else if (op == 0x41u)
        {
            uint value = read_u32_leb(pc, use_functions, use_bool_body);
            emit_mov_rax_imm64(cursor, value, 0u, lane);
            emit_push_rax(cursor, lane);
        }
        else if (op == 0x42u)
        {
            uint lo = 0u;
            uint hi = 0u;
            read_i64_const(pc, use_functions, use_bool_body, lo, hi);
            emit_mov_rax_imm64(cursor, lo, hi, lane);
            emit_push_rax(cursor, lane);
        }
        else if (op == 0x45u)
        {
            emit_eqz(cursor, lane);
        }
        else if (op == 0x1bu)
        {
            emit_select(cursor, lane);
        }
        else if (op == 0xa7u || op == 0xacu)
        {
        }
        else if (is_binary_wasm_op(op))
        {
            emit_binary_op(cursor, op, lane);
        }
    }
    return true;
}

uint section_arity(uint type_index)
{
    if (type_index == 3u)
        return 2u;
    if (type_index == 2u)
        return 1u;
    return 0u;
}

void parse_function_module(
    uint module_len,
    inout uint code_payload,
    inout uint code_len,
    inout uint code_count,
    inout uint main_order,
    inout uint func_arities[16])
{
    code_payload = 0u;
    code_len = 0u;
    code_count = 0u;
    main_order = 0u;
    [unroll]
    for (uint i = 0u; i < 16u; i += 1u)
        func_arities[i] = 0u;

    uint pc = 8u;
    [loop]
    while (pc + 1u < module_len)
    {
        uint section_id = functions_words[pc] & 0xffu;
        pc += 1u;
        uint section_len = read_u32_leb(pc, true, false);
        uint payload = pc;
        uint payload_end = payload + section_len;
        if (section_id == 3u)
        {
            uint q = payload;
            uint count = read_u32_leb(q, true, false);
            [loop]
            for (uint order = 0u; order < count && order < 16u; order += 1u)
            {
                uint type_index = read_u32_leb(q, true, false);
                func_arities[order] = section_arity(type_index);
            }
        }
        else if (section_id == 7u)
        {
            uint q = payload;
            uint exports = read_u32_leb(q, true, false);
            [loop]
            for (uint e = 0u; e < exports && q < payload_end; e += 1u)
            {
                uint name_len = read_u32_leb(q, true, false);
                q += name_len;
                uint kind = functions_words[q] & 0xffu;
                q += 1u;
                uint index = read_u32_leb(q, true, false);
                if (kind == 0u && index > 0u)
                    main_order = index - 1u;
            }
        }
        else if (section_id == 10u)
        {
            uint q = payload;
            code_count = read_u32_leb(q, true, false);
            code_payload = q;
            code_len = payload_end - q;
        }
        pc = payload_end;
    }
}

void emit_print_helper(inout uint cursor, uint lane)
{
    uint bytes[129] = {
        0x55u,0x48u,0x89u,0xe5u,0x48u,0x83u,0xecu,0x40u,0x48u,0x89u,0xf8u,0x48u,0x8du,0x75u,0xffu,0xc6u,
        0x06u,0x0au,0x48u,0xc7u,0xc1u,0x01u,0x00u,0x00u,0x00u,0x49u,0xc7u,0xc0u,0x00u,0x00u,0x00u,0x00u,
        0x48u,0x83u,0xf8u,0x00u,0x7du,0x0au,0x48u,0xf7u,0xd8u,0x49u,0xc7u,0xc0u,0x01u,0x00u,0x00u,0x00u,
        0x48u,0x83u,0xf8u,0x00u,0x75u,0x0bu,0x48u,0xffu,0xceu,0xc6u,0x06u,0x30u,0x48u,0xffu,0xc1u,0xebu,
        0x1du,0x49u,0xc7u,0xc1u,0x0au,0x00u,0x00u,0x00u,0x48u,0x31u,0xd2u,0x49u,0xf7u,0xf1u,0x80u,0xc2u,
        0x30u,0x48u,0xffu,0xceu,0x88u,0x16u,0x48u,0xffu,0xc1u,0x48u,0x85u,0xc0u,0x75u,0xeau,0x4du,0x85u,
        0xc0u,0x74u,0x09u,0x48u,0xffu,0xceu,0xc6u,0x06u,0x2du,0x48u,0xffu,0xc1u,0x48u,0xc7u,0xc0u,0x01u,
        0x00u,0x00u,0x00u,0x48u,0xc7u,0xc7u,0x01u,0x00u,0x00u,0x00u,0x48u,0x89u,0xcau,0x0fu,0x05u,0xc9u,
        0xc3u
    };
    [loop]
    for (uint i = 0u; i < PRINT_HELPER_SIZE; i += 1u)
        put_byte(cursor, bytes[i], lane);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint target = linear_dispatch_id(tid);
    if (target >= gParams.out_capacity)
        return;

    bool regs_ok = reg_status[1u] != 0u && reg_map[0u] == 0u && reg_map[1u] == 3u;
    bool use_functions = functions_status[1u] != 0u && functions_status[0u] >= 8u &&
                         (functions_words[0u] & 0xffu) == 0x00u &&
                         (functions_words[1u] & 0xffu) == 0x61u &&
                         (functions_words[2u] & 0xffu) == 0x73u &&
                         (functions_words[3u] & 0xffu) == 0x6du;
    bool use_bool_body = !use_functions && bool_body_status[1u] != 0u;
    uint body_len = use_bool_body ? bool_body_status[0u] : body_status[0u];
    bool body_ok = use_functions || (use_bool_body ? bool_body_status[1u] != 0u : body_status[1u] != 0u);

    uint cursor = 0u;
    emit_elf_header(cursor, target);
    pad_to(cursor, CODE_OFF, target);

    uint func_arities[16];
    [unroll]
    for (uint i = 0u; i < 16u; i += 1u)
        func_arities[i] = 0u;
    bool slots_ok = true;
    if (use_functions)
    {
        uint code_payload = 0u;
        uint code_len = 0u;
        uint code_count = 0u;
        uint main_order = 0u;
        parse_function_module(functions_status[0u], code_payload, code_len, code_count, main_order, func_arities);
        emit_call_abs(cursor, function_slot(main_order), target);
        emit_exit(cursor, target);
        pad_to(cursor, FUNCTIONS_BASE, target);

        uint q = code_payload;
        [loop]
        for (uint order = 0u; order < code_count && order < MAX_FUNCTIONS; order += 1u)
        {
            uint slot = function_slot(order);
            pad_to(cursor, slot, target);
            uint body_size = read_u32_leb(q, true, false);
            uint body_start = q;
            uint body_end = q + body_size;
            slots_ok = translate_wasm_body(true, false, body_start, body_end, true, func_arities[order], func_arities, cursor, target) &&
                       cursor <= slot + FUNCTION_SLOT_SIZE && slots_ok;
            q = body_end;
            pad_to(cursor, slot + FUNCTION_SLOT_SIZE, target);
        }
        slots_ok = slots_ok && code_count <= MAX_FUNCTIONS && main_order < MAX_FUNCTIONS &&
                   code_payload != 0u && code_len != 0u;
        pad_to(cursor, HELPER_OFF, target);
    }
    else
    {
        slots_ok = translate_wasm_body(false, use_bool_body, 0u, body_len, false, 0u, func_arities, cursor, target);
        emit_exit(cursor, target);
        pad_to(cursor, HELPER_OFF, target);
    }

    emit_print_helper(cursor, target);
    patch_elf_sizes(cursor, target);
    if (target == 0u)
    {
        status[0u] = cursor;
        status[1u] = regs_ok && body_ok && slots_ok && cursor <= gParams.out_capacity ? 1u : 0u;
    }
}
