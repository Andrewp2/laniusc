// Scatter scalar and structural WASM body fragments into the body byte stream.

import gpu_index;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<ScanParams> gScan;
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> body_fragment_len;
StructuredBuffer<uint4> body_fragment_meta;
StructuredBuffer<uint> body_scan_local_prefix;
StructuredBuffer<uint> body_scan_block_prefix;
StructuredBuffer<uint> status;

RWStructuredBuffer<uint> body_words;

static const uint BODY_FRAGMENT_LOCAL_DECL_COUNT = 1u;
static const uint BODY_FRAGMENT_PRINT_I64 = 2u;
static const uint BODY_FRAGMENT_RETURN_I32 = 3u;
static const uint BODY_FRAGMENT_LET_CONST_I32 = 4u;
static const uint BODY_FRAGMENT_ASSIGN_CONST_I32 = 5u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_CONST_I32 = 6u;
static const uint BODY_FRAGMENT_PRINT_LOCAL_I64 = 7u;
static const uint BODY_FRAGMENT_RETURN_LOCAL_I32 = 8u;
static const uint BODY_FRAGMENT_WHILE_CLOSE = 15u;
static const uint BODY_FRAGMENT_IF_ELSE = 17u;
static const uint BODY_FRAGMENT_IF_END = 18u;
static const uint BODY_FRAGMENT_BRANCH = 19u;
static const uint BODY_FRAGMENT_FUNCTION_HEADER = 22u;
static const uint BODY_FRAGMENT_FUNCTION_END = 28u;
static const uint BODY_FRAGMENT_WHILE_OPEN_LOCAL_I32 = 41u;
static const uint BODY_FRAGMENT_IF_OPEN_LOCAL_I32 = 42u;

static const uint WASM_PRINT_I64_FUNC_INDEX = 0u;
static const uint WASM_UNREACHABLE = 0x00u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_I64_CONST = 0x42u;
static const uint WASM_BLOCK = 0x02u;
static const uint WASM_LOOP = 0x03u;
static const uint WASM_IF = 0x04u;
static const uint WASM_ELSE = 0x05u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_LOCAL_SET = 0x21u;
static const uint WASM_BR = 0x0cu;
static const uint WASM_BR_IF = 0x0du;
static const uint WASM_RETURN = 0x0fu;
static const uint WASM_CALL = 0x10u;
static const uint WASM_END = 0x0bu;
static const uint WASM_BLOCK_TYPE_EMPTY = 0x40u;
static const uint WASM_I32_EQZ = 0x45u;
static const uint WASM_I64_EXTEND_I32_S = 0xacu;
static const uint WASM_I32_ADD = 0x6au;
static const uint WASM_I32_SUB = 0x6bu;
static const uint WASM_I32_MUL = 0x6cu;
static const uint WASM_I32_DIV_S = 0x6du;
static const uint WASM_I32_REM_S = 0x6fu;
static const uint WASM_VALTYPE_F32 = 0x7du;
static const uint WASM_VALTYPE_I32 = 0x7fu;
static const uint ASSIGN_OP_ADD = 2u;
static const uint ASSIGN_OP_SUB = 3u;
static const uint ASSIGN_OP_MUL = 4u;
static const uint ASSIGN_OP_DIV = 5u;
static const uint ASSIGN_OP_MOD = 6u;
static const uint WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint body_prefix_for_token(uint token_i)
{
    return global_exclusive_prefix(
        token_i,
        WG_SIZE,
        body_scan_local_prefix,
        body_scan_block_prefix);
}

uint i32_sleb_len(uint value)
{
    int current = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current = current >> 7;
        bool sign_bit_set = (byte_value & 0x40u) != 0u;
        bool done =
            (current == 0 && !sign_bit_set) ||
            (current == -1 && sign_bit_set) ||
            i == 4u;
        if (done)
            return i + 1u;
    }
    return 5u;
}

uint i32_sleb_byte(uint value, uint byte_i)
{
    int current = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current = current >> 7;
        bool sign_bit_set = (byte_value & 0x40u) != 0u;
        bool done =
            (current == 0 && !sign_bit_set) ||
            (current == -1 && sign_bit_set) ||
            i == 4u;
        if (!done)
            byte_value |= 0x80u;
        if (i == byte_i)
            return byte_value;
        if (done)
            return 0u;
    }
    return 0u;
}

uint u32_leb_len(uint value)
{
    for (uint i = 0u; i < 5u; i += 1u)
    {
        value = value >> 7u;
        if (value == 0u)
            return i + 1u;
    }
    return 5u;
}

uint u32_leb_byte(uint value, uint byte_i)
{
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = value & 0x7fu;
        value = value >> 7u;
        if (value != 0u)
            byte_value |= 0x80u;
        if (i == byte_i)
            return byte_value;
        if (value == 0u)
            return 0u;
    }
    return 0u;
}

uint u32_leb5_byte(uint value, uint byte_i)
{
    uint byte_value = (value >> (byte_i * 7u)) & 0x7fu;
    if (byte_i < 4u)
        byte_value |= 0x80u;
    return byte_value;
}

uint i32_const_byte(uint value, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_I32_CONST;
    return i32_sleb_byte(value, byte_i - 1u);
}

uint local_get_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_GET;
    return u32_leb_byte(local_index, byte_i - 1u);
}

uint local_set_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_SET;
    return u32_leb_byte(local_index, byte_i - 1u);
}

uint local_decl_fragment_byte(uint local_count, uint byte_i)
{
    if (local_count == 0u)
        return 0u;
    if (byte_i == 0u)
        return 2u;
    uint count_len = u32_leb_len(local_count);
    if (byte_i <= count_len)
        return u32_leb_byte(local_count, byte_i - 1u);
    if (byte_i == count_len + 1u)
        return WASM_VALTYPE_I32;
    uint second_count_start = count_len + 2u;
    if (byte_i < second_count_start + count_len)
        return u32_leb_byte(local_count, byte_i - second_count_start);
    return WASM_VALTYPE_F32;
}

uint function_header_fragment_byte(uint body_size, uint local_count, uint byte_i)
{
    if (byte_i < 5u)
        return u32_leb5_byte(body_size, byte_i);
    return local_decl_fragment_byte(local_count, byte_i - 5u);
}

uint assign_op_byte(uint op)
{
    if (op == ASSIGN_OP_ADD) return WASM_I32_ADD;
    if (op == ASSIGN_OP_SUB) return WASM_I32_SUB;
    if (op == ASSIGN_OP_MUL) return WASM_I32_MUL;
    if (op == ASSIGN_OP_DIV) return WASM_I32_DIV_S;
    if (op == ASSIGN_OP_MOD) return WASM_I32_REM_S;
    return 0u;
}

uint print_i64_fragment_byte(uint value, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_I64_CONST;

    uint value_len = i32_sleb_len(value);
    if (byte_i <= value_len)
        return i32_sleb_byte(value, byte_i - 1u);

    if (byte_i == value_len + 1u)
        return WASM_CALL;

    return WASM_PRINT_I64_FUNC_INDEX;
}

uint print_local_i64_fragment_byte(uint local_index, uint byte_i)
{
    uint get_len = 1u + u32_leb_len(local_index);
    if (byte_i < get_len)
        return local_get_byte(local_index, byte_i);
    if (byte_i == get_len)
        return WASM_I64_EXTEND_I32_S;
    if (byte_i == get_len + 1u)
        return WASM_CALL;
    return WASM_PRINT_I64_FUNC_INDEX;
}

uint return_i32_fragment_byte(uint value, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_I32_CONST;

    uint value_len = i32_sleb_len(value);
    if (byte_i <= value_len)
        return i32_sleb_byte(value, byte_i - 1u);

    return WASM_RETURN;
}

uint return_local_i32_fragment_byte(uint local_index, uint byte_i)
{
    uint get_len = 1u + u32_leb_len(local_index);
    if (byte_i < get_len)
        return local_get_byte(local_index, byte_i);
    return WASM_RETURN;
}

uint let_const_i32_fragment_byte(uint local_index, uint value, uint byte_i)
{
    uint const_len = 1u + i32_sleb_len(value);
    if (byte_i < const_len)
        return i32_const_byte(value, byte_i);
    return local_set_byte(local_index, byte_i - const_len);
}

uint assign_compound_const_i32_fragment_byte(uint local_index, uint value, uint op, uint byte_i)
{
    uint get_len = 1u + u32_leb_len(local_index);
    if (byte_i < get_len)
        return local_get_byte(local_index, byte_i);

    uint const_start = get_len;
    uint const_len = 1u + i32_sleb_len(value);
    if (byte_i < const_start + const_len)
        return i32_const_byte(value, byte_i - const_start);

    uint op_i = const_start + const_len;
    if (byte_i == op_i)
        return assign_op_byte(op);

    return local_set_byte(local_index, byte_i - op_i - 1u);
}

uint while_open_local_i32_fragment_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_BLOCK;
    if (byte_i == 1u)
        return WASM_BLOCK_TYPE_EMPTY;
    if (byte_i == 2u)
        return WASM_LOOP;
    if (byte_i == 3u)
        return WASM_BLOCK_TYPE_EMPTY;

    uint condition_start = 4u;
    uint get_len = 1u + u32_leb_len(local_index);
    if (byte_i < condition_start + get_len)
        return local_get_byte(local_index, byte_i - condition_start);

    uint eqz_i = condition_start + get_len;
    if (byte_i == eqz_i)
        return WASM_I32_EQZ;
    if (byte_i == eqz_i + 1u)
        return WASM_BR_IF;
    return 1u;
}

uint while_close_fragment_byte(uint byte_i)
{
    if (byte_i == 0u)
        return WASM_BR;
    if (byte_i == 1u)
        return 0u;
    return WASM_END;
}

uint if_open_local_i32_fragment_byte(uint local_index, uint byte_i)
{
    uint get_len = 1u + u32_leb_len(local_index);
    if (byte_i < get_len)
        return local_get_byte(local_index, byte_i);
    if (byte_i == get_len)
        return WASM_IF;
    return WASM_BLOCK_TYPE_EMPTY;
}

uint branch_fragment_byte(uint depth, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_BR;
    return u32_leb_byte(depth, byte_i - 1u);
}

bool scatter_handles_kind(uint kind)
{
    return kind == BODY_FRAGMENT_LOCAL_DECL_COUNT ||
           kind == BODY_FRAGMENT_FUNCTION_HEADER ||
           kind == BODY_FRAGMENT_FUNCTION_END ||
           kind == BODY_FRAGMENT_PRINT_I64 ||
           kind == BODY_FRAGMENT_RETURN_I32 ||
           kind == BODY_FRAGMENT_LET_CONST_I32 ||
           kind == BODY_FRAGMENT_ASSIGN_CONST_I32 ||
           kind == BODY_FRAGMENT_ASSIGN_COMPOUND_CONST_I32 ||
           kind == BODY_FRAGMENT_PRINT_LOCAL_I64 ||
           kind == BODY_FRAGMENT_RETURN_LOCAL_I32 ||
           kind == BODY_FRAGMENT_WHILE_OPEN_LOCAL_I32 ||
           kind == BODY_FRAGMENT_IF_OPEN_LOCAL_I32 ||
           kind == BODY_FRAGMENT_WHILE_CLOSE ||
           kind == BODY_FRAGMENT_IF_ELSE ||
           kind == BODY_FRAGMENT_IF_END ||
           kind == BODY_FRAGMENT_BRANCH;
}

uint fragment_byte(uint4 meta, uint fragment_len, uint byte_i)
{
    uint kind = meta.x;
    uint value = meta.y;

    if (kind == BODY_FRAGMENT_LOCAL_DECL_COUNT)
        return local_decl_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_FUNCTION_HEADER)
        return function_header_fragment_byte(meta.y, meta.z, byte_i);
    if (kind == BODY_FRAGMENT_FUNCTION_END)
        return fragment_len == 1u || byte_i != 0u ? WASM_END : WASM_UNREACHABLE;
    if (kind == BODY_FRAGMENT_PRINT_I64)
        return print_i64_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_RETURN_I32)
        return return_i32_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_LET_CONST_I32 ||
        kind == BODY_FRAGMENT_ASSIGN_CONST_I32)
        return let_const_i32_fragment_byte(meta.y, meta.z, byte_i);
    if (kind == BODY_FRAGMENT_ASSIGN_COMPOUND_CONST_I32)
        return assign_compound_const_i32_fragment_byte(meta.y, meta.z, meta.w, byte_i);
    if (kind == BODY_FRAGMENT_PRINT_LOCAL_I64)
        return print_local_i64_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_RETURN_LOCAL_I32)
        return return_local_i32_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_WHILE_OPEN_LOCAL_I32)
        return while_open_local_i32_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_IF_OPEN_LOCAL_I32)
        return if_open_local_i32_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_WHILE_CLOSE)
        return while_close_fragment_byte(byte_i);
    if (kind == BODY_FRAGMENT_IF_ELSE)
        return WASM_ELSE;
    if (kind == BODY_FRAGMENT_IF_END)
        return WASM_END;
    if (kind == BODY_FRAGMENT_BRANCH)
        return branch_fragment_byte(value, byte_i);

    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint body_byte_i = linear_dispatch_id(tid);
    if (body_byte_i >= gScan.out_capacity || status[2u] != 0u)
        return;

    uint lo = 0u;
    uint hi = gScan.n_items;
    for (uint guard = 0u; guard < 32u; guard += 1u)
    {
        if (lo >= hi)
            break;
        uint mid = lo + ((hi - lo) >> 1u);
        uint mid_start = body_prefix_for_token(mid);
        uint mid_end = mid_start + body_fragment_len[mid];
        if (mid_end <= body_byte_i)
            lo = mid + 1u;
        else
            hi = mid;
    }
    uint token_i = lo;
    if (token_i >= gScan.n_items)
        return;
    uint len = body_fragment_len[token_i];
    uint offset = body_prefix_for_token(token_i);
    if (body_byte_i < offset || body_byte_i >= offset + len)
        return;
    uint byte_i = body_byte_i - offset;
    if (byte_i >= len)
        return;

    uint4 meta = body_fragment_meta[token_i];
    if (!scatter_handles_kind(meta.x))
        return;
    body_words[offset + byte_i] = fragment_byte(meta, len, byte_i);
}
