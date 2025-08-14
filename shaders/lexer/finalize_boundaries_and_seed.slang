// shaders/lexer/finalize_boundaries_and_seed.slang
// Compute boundaries and token types from final prefix states + emit mask.
// Also compute the exact exclusive-end index for each boundary.
//
// Handles EOF correctly even if the last byte also caused an emitting edge.

#define N_STATES 32

static const uint INVALID32 = 0xFFFFffffu;
static const uint INVALID16 = 0xFFFFu;

import utils;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
    // three token kinds to skip (e.g., White, LineComment, BlockComment) + 1 extra
    uint skip0;
    uint skip1;
    uint skip2;
    uint skip3;
};
ConstantBuffer<Params> gParams;

ByteAddressBuffer in_bytes; // byte-addressable input
StructuredBuffer<uint> token_map;
StructuredBuffer<uint> f_final;
StructuredBuffer<uint> next_emit; // 2x u16 per uint

// --------- NEW SINGLE FLAGS BUFFER ---------
RWStructuredBuffer<uint> flags_packed; // per-i packed bits: EMIT/EOF/KEEP_EMIT/KEEP_EOF

RWStructuredBuffer<uint> tok_types;     // PACKED per-i kinds for KEPT stream: (EOF<<16)|(EMIT)
RWStructuredBuffer<uint> end_excl_by_i; // KEPT exclusive end if single boundary at i

bool is_skip(uint tk)
{
    return (tk == gParams.skip0) || (tk == gParams.skip1) || (tk == gParams.skip2) || (tk == gParams.skip3);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void finalize_boundaries_and_seed(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n)
        return;

    uint b = load_byte_at(in_bytes, i);
    uint prev_state = (i == 0) ? gParams.start_state : f_final[i - 1];
    uint state_i = f_final[i];

    uint packed = load_u16_packed(next_emit, b * N_STATES + prev_state);
    uint emit_here = is_highest_bit_set(packed) ? 1u : 0u;

    // EOF acceptance
    uint at_eof = is_last(i, gParams.n) ? 1u : 0u;
    uint eof_accept = (at_eof != 0u && token_map[state_i] != INVALID32) ? 1u : 0u;

    // Candidate kinds
    uint tk_emit = token_map[prev_state];
    uint tk_eof = token_map[state_i];

    // Keepability via uniform skip set
    uint keep_emit = is_skip(tk_emit) ? 0u : 1u;
    uint keep_eof = is_skip(tk_eof) ? 0u : 1u;

    // Pack both (low16 = emit-if-kept, high16 = eof-if-kept), 0xFFFF means "none"
    uint emit16 = (keep_emit != 0u && tk_emit != INVALID32) ? (tk_emit & 0xFFFFu) : INVALID16;
    uint eof16 = (keep_eof != 0u && tk_eof != INVALID32) ? (tk_eof & 0xFFFFu) : INVALID16;
    tok_types[i] = (eof16 << 16) | emit16;

    // For single-kept case, provide the exclusive end for that kept boundary
    uint ex_single =
        (at_eof != 0u && keep_eof != 0u && (keep_emit == 0u || emit_here == 0u)) ? gParams.n : i;

    // --------- NEW: write packed flags (4 bits used) ---------
    uint f = 0u;
    f |= (emit_here != 0u) ? PF_EMIT : 0u;
    f |= (eof_accept != 0u) ? PF_EOF : 0u;
    f |= (keep_emit != 0u) ? PF_KEEP_EMIT : 0u;
    f |= (keep_eof != 0u) ? PF_KEEP_EOF : 0u;

    flags_packed[i] = f;
    end_excl_by_i[i] = ex_single;
}
