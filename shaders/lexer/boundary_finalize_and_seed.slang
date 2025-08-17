
#define N_STATES 32

static const uint INVALID32 = 0xFFFFffffu;
static const uint INVALID16 = 0xFFFFu;

import utils;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
    uint skip0;
    uint skip1;
    uint skip2;
    uint skip3;
};

ConstantBuffer<Params> gParams;
ByteAddressBuffer in_bytes;
StructuredBuffer<uint> token_map;
StructuredBuffer<uint> f_final;
StructuredBuffer<uint> next_emit;
RWStructuredBuffer<uint> flags_packed;
RWStructuredBuffer<uint> tok_types;
RWStructuredBuffer<uint> end_excl_by_i;

bool is_skip(uint tk)
{
    return (tk == gParams.skip0) || (tk == gParams.skip1) || (tk == gParams.skip2) || (tk == gParams.skip3);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void boundary_finalize_and_seed(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n)
        return;

    uint b = load_byte_at(in_bytes, i);
    uint prev_state = (i == 0) ? gParams.start_state : f_final[i - 1];
    uint state_i = f_final[i];

    uint packed = load_u16_packed(next_emit, b * N_STATES + prev_state);
    uint emit_here = is_highest_bit_set(packed) ? 1u : 0u;

    uint at_eof = is_last(i, gParams.n) ? 1u : 0u;
    uint eof_accept = (at_eof != 0u && token_map[state_i] != INVALID32) ? 1u : 0u;

    uint tk_emit = token_map[prev_state];
    uint tk_eof = token_map[state_i];

    uint valid_emit = (tk_emit != INVALID32) ? 1u : 0u;
    uint valid_eof = (tk_eof != INVALID32) ? 1u : 0u;

    uint keep_emit = (valid_emit != 0u && !is_skip(tk_emit)) ? 1u : 0u;
    uint keep_eof = (valid_eof != 0u && !is_skip(tk_eof)) ? 1u : 0u;

    uint emit16 = (keep_emit != 0u && valid_emit != 0u) ? (tk_emit & 0xFFFFu) : INVALID16;
    uint eof16 = (keep_eof != 0u && valid_eof != 0u) ? (tk_eof & 0xFFFFu) : INVALID16;
    tok_types[i] = (eof16 << 16) | emit16;

    uint kept_emit_here = (emit_here != 0u && keep_emit != 0u) ? 1u : 0u;
    uint kept_eof_here = (eof_accept != 0u && keep_eof != 0u) ? 1u : 0u;
    uint ex_single = (kept_eof_here != 0u) ? gParams.n : i;

    uint f = 0u;
    f |= (emit_here != 0u) ? PF_EMIT : 0u;
    f |= (eof_accept != 0u) ? PF_EOF : 0u;
    f |= (keep_emit != 0u) ? PF_KEEP_EMIT : 0u;
    f |= (keep_eof != 0u) ? PF_KEEP_EOF : 0u;

    flags_packed[i] = f;
    end_excl_by_i[i] = ex_single;
}
