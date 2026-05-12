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
RWStructuredBuffer<uint> out_words;
RWStructuredBuffer<uint> status;

static const uint BODY_OFF = 80u;
static const uint WORKGROUP_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint body_byte(uint i, bool use_bool_body)
{
    return use_bool_body ? bool_body_words[i] : body_words[i];
}

uint leb5_byte(uint value, uint i)
{
    uint byte_value = (value >> (i * 7u)) & 0x7fu;
    if (i < 4u)
        byte_value |= 0x80u;
    return byte_value;
}

uint module_prefix_byte(uint pos, uint body_len)
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

uint module_byte(uint pos, uint body_len, uint module_len, bool use_bool_body)
{
    if (pos >= module_len)
        return 0u;
    if (pos < BODY_OFF)
        return module_prefix_byte(pos, body_len);
    return body_byte(pos - BODY_OFF, use_bool_body);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[1u] == 2u || status[2u] != 0u)
        return;

    bool use_bool_body = bool_body_status[1u] != 0u;
    uint body_len = use_bool_body ? bool_body_status[0u] : body_status[0u];
    bool body_ok = use_bool_body || body_status[1u] != 0u;
    uint module_len = BODY_OFF + body_len;
    bool ok = body_ok && module_len <= gParams.out_capacity;

    if (tid.x == 0u)
    {
        status[0u] = module_len;
        status[1u] = ok ? 3u : 0u;
    }

    if (!ok)
        return;

    uint word_i = linear_dispatch_id(tid);
    uint word_count = (module_len + 3u) / 4u;
    if (word_i >= word_count)
        return;

    uint pos = word_i * 4u;
    out_words[word_i] =
        (module_byte(pos + 0u, body_len, module_len, use_bool_body) << 0u) |
        (module_byte(pos + 1u, body_len, module_len, use_bool_body) << 8u) |
        (module_byte(pos + 2u, body_len, module_len, use_bool_body) << 16u) |
        (module_byte(pos + 3u, body_len, module_len, use_bool_body) << 24u);
}
