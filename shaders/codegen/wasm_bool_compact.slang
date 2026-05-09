struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> bool_body_slots;
StructuredBuffer<uint> bool_stmt_len;
StructuredBuffer<uint> bool_stmt_offsets;
StructuredBuffer<uint> bool_scan_status;

RWStructuredBuffer<uint> bool_body_words;
RWStructuredBuffer<uint> bool_body_status;

static const uint BOOL_BODY_BYTES_PER_TOKEN = 96u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

void put_byte(inout uint cursor, uint value, bool write)
{
    if (write && cursor < gParams.out_capacity)
        bool_body_words[cursor] = value & 0xffu;
    cursor += 1u;
}

void emit_u32_leb(inout uint cursor, uint value, bool write)
{
    [loop]
    for (uint guard = 0u; guard < 5u; guard += 1u)
    {
        uint byte_value = value & 0x7fu;
        value = value >> 7u;
        if (value != 0u)
            byte_value |= 0x80u;
        put_byte(cursor, byte_value, write);
        if (value == 0u)
            break;
    }
}

void emit_u32_leb5(inout uint cursor, uint value, bool write)
{
    [unroll]
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = value & 0x7fu;
        value = value >> 7u;
        if (i != 4u)
            byte_value |= 0x80u;
        put_byte(cursor, byte_value, write);
    }
}

void emit_body_header(inout uint cursor, bool write)
{
    emit_u32_leb(cursor, 1u, write);
    emit_u32_leb5(cursor, active_token_count() + 1u, write);
    put_byte(cursor, 0x7eu, write);
}

void emit_body_footer(inout uint cursor, bool write)
{
    put_byte(cursor, 0x41u, write);
    emit_u32_leb(cursor, 0u, write);
    put_byte(cursor, 0x0bu, write);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (bool_scan_status[1u] == 0u)
        return;

    uint header_len = 0u;
    emit_body_header(header_len, false);

    uint i = linear_dispatch_id(tid);
    if (i < active_token_count())
    {
        uint len = min(bool_stmt_len[i], BOOL_BODY_BYTES_PER_TOKEN);
        uint src = i * BOOL_BODY_BYTES_PER_TOKEN;
        uint dst = header_len + bool_stmt_offsets[i];
        [loop]
        for (uint j = 0u; j < BOOL_BODY_BYTES_PER_TOKEN; j += 1u)
        {
            if (j < len && dst + j < gParams.out_capacity)
                bool_body_words[dst + j] = bool_body_slots[src + j] & 0xffu;
        }
    }

    if (i == 0u)
    {
        uint len = header_len + bool_scan_status[0u];
        uint header_cursor = 0u;
        emit_body_header(header_cursor, true);
        emit_body_footer(len, true);
        bool_body_status[0u] = len;
        bool_body_status[1u] = len <= gParams.out_capacity ? 1u : 0u;
    }
}
