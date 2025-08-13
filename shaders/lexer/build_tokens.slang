// shaders/lex_build_tokens.slang
// Turn compacted ends into (start,len,kind), using ALL-end list for starts.

StructuredBuffer<uint> token_count;       // total *kept* tokens
StructuredBuffer<uint> end_positions;     // compacted exclusive ends (*kept*)
StructuredBuffer<uint> types_compact;     // compacted kinds         (*kept*)
StructuredBuffer<uint> all_index_compact; // 1-based ALL index for each kept token
StructuredBuffer<uint> end_positions_all; // compacted exclusive ends for *ALL* boundaries

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};
RWStructuredBuffer<TokenOut> tokens_out;

[shader("compute")]
[numthreads(256, 1, 1)]
void build_tokens(uint3 tid: SV_DispatchThreadID)
{
    uint k = tid.x;
    uint total = token_count[0];
    if (k >= total)
        return;

    // end of this token (exclusive) from kept list
    uint end_excl = end_positions[k];

    // Map kept token k to its corresponding ALL boundary index
    // (1-based in scatter; convert to 0-based here)
    uint all_idx = all_index_compact[k];
    uint all_zero = (all_idx == 0u) ? 0u : (all_idx - 1u);

    // Start is previous ALL boundary (or 0 if this is the first boundary overall)
    uint start = (all_zero == 0u) ? 0u : end_positions_all[all_zero - 1u];

    TokenOut t;
    t.kind = types_compact[k];
    t.start = start;
    t.len = end_excl - start;
    tokens_out[k] = t;
}
