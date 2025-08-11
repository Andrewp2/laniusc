// shaders/lex_finalize.slang
// Stage 3: compute end_flags, token types; seed sum-scan source.

struct LexParams
{
    uint n;
    uint m;
    uint identity_id;
};
ConstantBuffer<LexParams> gParams;

StructuredBuffer<uint> emit_on_start; // m → {0,1}
StructuredBuffer<uint> token_of;      // m → token kind or 0xFFFF_FFFF

StructuredBuffer<uint> f_final; // length n

RWStructuredBuffer<uint> end_flags;      // length n
RWStructuredBuffer<uint> tok_types;      // length n
RWStructuredBuffer<uint> filtered_flags; // length n
RWStructuredBuffer<uint> s_ping;         // length n (sum-scan source)

[shader("compute")]
[numthreads(128, 1, 1)]
void finalize_and_post(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n)
        return;

    uint f_i = f_final[i];

    // Boundary from current prefix
    uint end_flag = emit_on_start[f_i];

    // Ensure final token: force end if accepting
    if (i + 1u == gParams.n)
    {
        uint tok_end = token_of[f_i];
        if (tok_end != 0xFFFFffffu)
        {
            end_flag = 1u;
        }
    }

    // Type from previous prefix (identity at start)
    uint f_prev = (i == 0u) ? gParams.identity_id : f_final[i - 1u];
    uint ty = token_of[f_prev];

    end_flags[i] = end_flag;
    tok_types[i] = ty;

    // Filter out invalid kinds
    uint filtered = (end_flag != 0u && ty != 0xFFFFffffu) ? 1u : 0u;
    filtered_flags[i] = filtered;

    // Seed sum-scan source here
    s_ping[i] = filtered;
}
