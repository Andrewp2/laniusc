import utils;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> token_count;
ByteAddressBuffer source_bytes;
RWStructuredBuffer<uint> body_words;
RWStructuredBuffer<uint> body_status;
RWStructuredBuffer<uint> body_dispatch_args;
RWStructuredBuffer<uint> out_words;
RWStructuredBuffer<uint> status;

static const uint TK_INT = 2u;
static const uint TK_IDENT = 1u;
static const uint TK_ASSIGN = 8u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_LET = 68u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_FOR = 100u;

static const uint BODY_OFF = 80u;
static const uint BODY_HEADER_LEN = 7u;
static const uint SIMPLE_LET_BODY_LEN = 17u;
static const uint BODY_FOOTER_LEN = 3u;
static const uint MAX_DISPATCH_X = 65535u;
static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;
static const uint ERR_UNSUPPORTED_FOR_LOOP = 2u;

uint active_token_count()
{
    return min(token_count[0u], gParams.n_tokens);
}

uint token_kind(uint i)
{
    return i < active_token_count() ? token_words[i].kind : 0u;
}

uint token_start(uint i)
{
    return i < active_token_count() ? token_words[i].start : 0u;
}

uint token_len(uint i)
{
    return i < active_token_count() ? token_words[i].len : 0u;
}

uint source_at(uint start, uint delta)
{
    uint idx = start + delta;
    return idx < gParams.source_len ? load_byte_at(source_bytes, idx) : 0u;
}

uint parse_uint_token(uint token_i)
{
    uint value = 0u;
    uint start = token_start(token_i);
    uint len = token_len(token_i);
    [loop]
    for (uint i = 0u; i < len && i < 10u; i += 1u)
    {
        uint ch = source_at(start, i);
        if (ch < 48u || ch > 57u)
            break;
        value = value * 10u + (ch - 48u);
    }
    return value;
}

void record_codegen_error(uint code, uint token_i)
{
    uint old;
    InterlockedMin(status[3u], token_i, old);
    if (token_i <= old)
        status[2u] = code;
    InterlockedAnd(status[1u], 0u, old);
}

void invalidate_fast_path()
{
    uint groups = (gParams.out_capacity + 255u) / 256u;
    body_dispatch_args[0u] = min(groups, MAX_DISPATCH_X);
    body_dispatch_args[1u] = (groups + MAX_DISPATCH_X - 1u) / MAX_DISPATCH_X;
    body_dispatch_args[2u] = 1u;
    record_codegen_error(ERR_UNSUPPORTED_SOURCE_SHAPE, active_token_count());
    InterlockedAnd(body_status[1u], 0u);
}

void put_body(uint pos, uint value)
{
    if (pos < gParams.out_capacity)
        body_words[pos] = value & 0xffu;
}

void put_out(uint pos, uint value)
{
    if (pos < gParams.out_capacity)
        out_words[pos] = value & 0xffu;
}

void put_both(uint body_pos, uint value)
{
    put_body(body_pos, value);
}

uint leb5_byte(uint value, uint i)
{
    uint byte_value = (value >> (i * 7u)) & 0x7fu;
    return i < 4u ? (byte_value | 0x80u) : byte_value;
}

void put_u32_leb5_body(uint pos, uint value)
{
    [unroll]
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = (value >> (i * 7u)) & 0x7fu;
        if (i < 4u)
            byte_value |= 0x80u;
        put_both(pos + i, byte_value);
    }
}

void put_u32_leb5_out(uint pos, uint value)
{
    [unroll]
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = (value >> (i * 7u)) & 0x7fu;
        if (i < 4u)
            byte_value |= 0x80u;
        put_out(pos + i, byte_value);
    }
}

void emit_static_module_prefix(uint body_len)
{
    put_out(0u, 0x00u);
    put_out(1u, 0x61u);
    put_out(2u, 0x73u);
    put_out(3u, 0x6du);
    put_out(4u, 0x01u);
    put_out(5u, 0x00u);
    put_out(6u, 0x00u);
    put_out(7u, 0x00u);

    put_out(8u, 1u);
    put_u32_leb5_out(9u, 9u);
    put_out(14u, 2u);
    put_out(15u, 0x60u);
    put_out(16u, 1u);
    put_out(17u, 0x7eu);
    put_out(18u, 0u);
    put_out(19u, 0x60u);
    put_out(20u, 0u);
    put_out(21u, 1u);
    put_out(22u, 0x7fu);

    put_out(23u, 2u);
    put_u32_leb5_out(24u, 17u);
    put_out(29u, 1u);
    put_out(30u, 3u);
    put_out(31u, 101u);
    put_out(32u, 110u);
    put_out(33u, 118u);
    put_out(34u, 9u);
    put_out(35u, 112u);
    put_out(36u, 114u);
    put_out(37u, 105u);
    put_out(38u, 110u);
    put_out(39u, 116u);
    put_out(40u, 95u);
    put_out(41u, 105u);
    put_out(42u, 54u);
    put_out(43u, 52u);
    put_out(44u, 0u);
    put_out(45u, 0u);

    put_out(46u, 3u);
    put_u32_leb5_out(47u, 2u);
    put_out(52u, 1u);
    put_out(53u, 1u);

    put_out(54u, 7u);
    put_u32_leb5_out(55u, 8u);
    put_out(60u, 1u);
    put_out(61u, 4u);
    put_out(62u, 109u);
    put_out(63u, 97u);
    put_out(64u, 105u);
    put_out(65u, 110u);
    put_out(66u, 0u);
    put_out(67u, 1u);

    put_out(68u, 10u);
    put_u32_leb5_out(69u, body_len + 6u);
    put_out(74u, 1u);
    put_u32_leb5_out(75u, body_len);
}

void emit_body_fixed(uint n, uint body_len)
{
    put_both(0u, 1u);
    put_u32_leb5_body(1u, n + 1u);
    put_both(6u, 0x7eu);
    put_both(body_len - 3u, 0x41u);
    put_both(body_len - 2u, 0u);
    put_both(body_len - 1u, 0x0bu);
}

void emit_simple_let(uint statement_i)
{
    uint base = statement_i * 5u;
    if (token_kind(base) != TK_LET ||
        (token_kind(base + 1u) != TK_LET_IDENT && token_kind(base + 1u) != TK_IDENT) ||
        (token_kind(base + 2u) != TK_LET_ASSIGN && token_kind(base + 2u) != TK_ASSIGN) ||
        token_kind(base + 3u) != TK_INT ||
        token_kind(base + 4u) != TK_SEMICOLON)
    {
        invalidate_fast_path();
        return;
    }

    uint cursor = BODY_HEADER_LEN + statement_i * SIMPLE_LET_BODY_LEN;
    uint value = parse_uint_token(base + 3u);
    put_both(cursor + 0u, 0x42u);
    [unroll]
    for (uint i = 0u; i < 10u; i += 1u)
    {
        uint byte_value = 0u;
        if (i < 5u)
            byte_value = ((value >> (i * 7u)) & 0x7fu) | 0x80u;
        else if (i < 9u)
            byte_value = 0x80u;
        else
            byte_value = 0x00u;
        put_both(cursor + 1u + i, byte_value);
    }
    put_both(cursor + 11u, 0x21u);
    put_u32_leb5_body(cursor + 12u, base + 1u);
}

uint static_module_byte(uint pos, uint body_len)
{
    if (pos == 0u) return 0x00u;
    if (pos == 1u) return 0x61u;
    if (pos == 2u) return 0x73u;
    if (pos == 3u) return 0x6du;
    if (pos == 4u) return 0x01u;
    if (pos == 5u) return 0x00u;
    if (pos == 6u) return 0x00u;
    if (pos == 7u) return 0x00u;

    if (pos == 8u) return 1u;
    if (pos >= 9u && pos < 14u) return leb5_byte(9u, pos - 9u);
    if (pos == 14u) return 2u;
    if (pos == 15u) return 0x60u;
    if (pos == 16u) return 1u;
    if (pos == 17u) return 0x7eu;
    if (pos == 18u) return 0u;
    if (pos == 19u) return 0x60u;
    if (pos == 20u) return 0u;
    if (pos == 21u) return 1u;
    if (pos == 22u) return 0x7fu;

    if (pos == 23u) return 2u;
    if (pos >= 24u && pos < 29u) return leb5_byte(17u, pos - 24u);
    if (pos == 29u) return 1u;
    if (pos == 30u) return 3u;
    if (pos == 31u) return 101u;
    if (pos == 32u) return 110u;
    if (pos == 33u) return 118u;
    if (pos == 34u) return 9u;
    if (pos == 35u) return 112u;
    if (pos == 36u) return 114u;
    if (pos == 37u) return 105u;
    if (pos == 38u) return 110u;
    if (pos == 39u) return 116u;
    if (pos == 40u) return 95u;
    if (pos == 41u) return 105u;
    if (pos == 42u) return 54u;
    if (pos == 43u) return 52u;
    if (pos == 44u) return 0u;
    if (pos == 45u) return 0u;

    if (pos == 46u) return 3u;
    if (pos >= 47u && pos < 52u) return leb5_byte(2u, pos - 47u);
    if (pos == 52u) return 1u;
    if (pos == 53u) return 1u;

    if (pos == 54u) return 7u;
    if (pos >= 55u && pos < 60u) return leb5_byte(8u, pos - 55u);
    if (pos == 60u) return 1u;
    if (pos == 61u) return 4u;
    if (pos == 62u) return 109u;
    if (pos == 63u) return 97u;
    if (pos == 64u) return 105u;
    if (pos == 65u) return 110u;
    if (pos == 66u) return 0u;
    if (pos == 67u) return 1u;

    if (pos == 68u) return 10u;
    if (pos >= 69u && pos < 74u) return leb5_byte(body_len + 6u, pos - 69u);
    if (pos == 74u) return 1u;
    if (pos >= 75u && pos < BODY_OFF) return leb5_byte(body_len, pos - 75u);
    return 0u;
}

uint body_byte(uint body_pos, uint n, uint body_len)
{
    if (body_pos == 0u) return 1u;
    if (body_pos >= 1u && body_pos < 6u) return leb5_byte(n + 1u, body_pos - 1u);
    if (body_pos == 6u) return 0x7eu;
    if (body_pos == body_len - 3u) return 0x41u;
    if (body_pos == body_len - 2u) return 0u;
    if (body_pos == body_len - 1u) return 0x0bu;
    if (body_pos < BODY_HEADER_LEN || body_pos >= body_len - BODY_FOOTER_LEN)
        return 0u;

    uint rel = body_pos - BODY_HEADER_LEN;
    uint statement_i = rel / SIMPLE_LET_BODY_LEN;
    uint field = rel - statement_i * SIMPLE_LET_BODY_LEN;
    uint base = statement_i * 5u;
    if (field == 0u) return 0x42u;
    if (field >= 1u && field < 11u)
    {
        uint value = parse_uint_token(base + 3u);
        uint i = field - 1u;
        if (i < 5u)
            return ((value >> (i * 7u)) & 0x7fu) | 0x80u;
        if (i < 9u)
            return 0x80u;
        return 0x00u;
    }
    if (field == 11u) return 0x21u;
    if (field >= 12u && field < 17u) return leb5_byte(base + 1u, field - 12u);
    return 0u;
}

uint output_byte(uint pos, uint n, uint body_len, uint module_len)
{
    if (pos >= module_len)
        return 0u;
    if (pos < BODY_OFF)
        return static_module_byte(pos, body_len);
    return body_byte(pos - BODY_OFF, n, body_len);
}

void emit_packed_out_word(uint word_i, uint n, uint body_len, uint module_len)
{
    if (word_i >= gParams.out_capacity)
        return;
    uint pos = word_i * 4u;
    uint packed =
        (output_byte(pos + 0u, n, body_len, module_len) << 0u) |
        (output_byte(pos + 1u, n, body_len, module_len) << 8u) |
        (output_byte(pos + 2u, n, body_len, module_len) << 16u) |
        (output_byte(pos + 3u, n, body_len, module_len) << 24u);
    out_words[word_i] = packed;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint n = active_token_count();
    uint statement_count = n / 5u;
    uint body_len = BODY_HEADER_LEN + statement_count * SIMPLE_LET_BODY_LEN + BODY_FOOTER_LEN;
    uint module_len = BODY_OFF + body_len;

    if (tid.x < n && token_kind(tid.x) == TK_FOR)
        record_codegen_error(ERR_UNSUPPORTED_FOR_LOOP, tid.x);

    if (tid.x == 0u)
    {
        body_status[0u] = body_len;
        status[0u] = module_len;
        if (n == 0u || (n % 5u) != 0u || module_len > gParams.out_capacity)
            invalidate_fast_path();
        emit_body_fixed(n, body_len);
    }

    if (tid.x < statement_count)
        emit_simple_let(tid.x);
    uint packed_word_count = (module_len + 3u) / 4u;
    if (tid.x < packed_word_count)
        emit_packed_out_word(tid.x, n, body_len, module_len);
}
