// Per token: whether a generator or a `yield` starts here, the change of
// loop depth and the change of depth in the blocks that hold statements of
// a generator: its body and the blocks of `while` and `if`. The prefix sums
// of these rows number the generators and yields and give each token's
// depths. A token of `import core::option` marks its file.
import gpu_index;
import byte_packing;
import generated_token_ids;
import generator_common;

struct MarkParams
{
    uint token_count;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<MarkParams> gMarks;
StructuredBuffer<uint> tokens_out;
StructuredBuffer<uint> token_file_id;
ByteAddressBuffer in_bytes;
StructuredBuffer<uint> records;
RWStructuredBuffer<uint4> marks;
RWStructuredBuffer<uint> file_option;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint rec(uint token, uint word)
{
    return records[token * GR_WORDS + word];
}

// Whether token `t` is the identifier whose bytes are packed in `low` and
// `high`, least significant first.
bool word_is(uint t, uint low, uint high, uint count)
{
    if (token_kind(tokens_out, t) != TK_IDENT || token_len(tokens_out, t) != count)
        return false;
    uint start = token_start(tokens_out, t);
    for (uint i = 0u; i < count; i += 1u)
    {
        uint expected = i < 4u ? (low >> (i * 8u)) & 255u : (high >> ((i - 4u) * 8u)) & 255u;
        if (byte_address_load_u8(in_bytes, start + i) != expected)
            return false;
    }
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint token = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (token >= gMarks.token_count)
        return;
    uint role = rec(token, GR_ROLE);
    uint kind = 0u;
    uint delta = 0u;
    if (role == GROLE_BLOCK)
    {
        kind = rec(token, GR_KIND);
        delta = 1u;
    }
    else if (role == GROLE_CLOSE)
    {
        kind = rec(rec(token, GR_OPEN), GR_KIND);
        delta = 0xffffffffu;
    }
    bool in_loop = kind == BK_WHILE || kind == BK_FOR;
    bool statements = kind == BK_BODY || kind == BK_WHILE || kind == BK_IF;
    marks[token] = uint4(role == GROLE_GEN ? 1u : 0u, role == GROLE_YIELD ? 1u : 0u, in_loop ? delta : 0u,
                         statements ? delta : 0u);

    // `import core::option`: "core", "option".
    if (token_kind(tokens_out, token) == TK_IMPORT && token + 4u < gMarks.token_count &&
        token_file_id[token + 4u] == token_file_id[token] && word_is(token + 1u, 0x65726f63u, 0u, 4u) &&
        token_kind(tokens_out, token + 2u) == TK_COLON && token_kind(tokens_out, token + 3u) == TK_COLON &&
        word_is(token + 4u, 0x6974706fu, 0x6e6fu, 6u))
        file_option[token_file_id[token]] = 1u;
}
