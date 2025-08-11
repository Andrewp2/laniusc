// shaders/lex_finalize.slang
// Compute boundaries and token types from final prefix states + emit mask.
// Seeds s_ping for the sum-scan.

#define N_STATES 32
static const uint TK_White = 3u;
static const uint TK_LineComment = 10u;
static const uint TK_BlockComment = 11u;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> in_bytes;
StructuredBuffer<uint> emit_mask; // 256, bit per DFA state
StructuredBuffer<uint> token_map; // N_STATES
StructuredBuffer<uint> f_final;   // state after prefix i

RWStructuredBuffer<uint> end_flags;
RWStructuredBuffer<uint> tok_types;
RWStructuredBuffer<uint> filtered_flags;
RWStructuredBuffer<uint> s_ping;

[numthreads(128, 1, 1)]
void finalize_and_post(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n)
        return;

    uint b = in_bytes[i] & 0xFFu;

    // previous state: start for i==0, else f_final[i-1]
    uint prev_state = (i == 0) ? gParams.start_state : f_final[i - 1];

    uint end = (emit_mask[b] >> prev_state) & 1u;
    uint tk = token_map[prev_state];

    end_flags[i] = end;
    tok_types[i] = tk;

    // filter whitespace/comments here; keep as "valid end" only if not filtered
    uint keep = (tk == TK_White || tk == TK_LineComment || tk == TK_BlockComment) ? 0u : 1u;
    uint valid = end * keep;
    filtered_flags[i] = valid;
    s_ping[i] = valid; // seed for sum-scan
}
