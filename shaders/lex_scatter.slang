// shaders/lex_scatter.slang
// Stage 4b: scatter compacted end positions + types; write count

struct LexParams
{
    uint n;
    uint m;
    uint identity_id;
};
ConstantBuffer<LexParams> gParams;

StructuredBuffer<uint> s_final;        // inclusive sums
StructuredBuffer<uint> filtered_flags; // 0/1 per i
StructuredBuffer<uint> tok_types;      // token kind per i

RWStructuredBuffer<uint> end_positions; // compacted exclusive ends
RWStructuredBuffer<uint> types_compact; // compacted kinds
RWStructuredBuffer<uint> token_count;   // [0] = total compacted

[shader("compute")]
[numthreads(128, 1, 1)]
void scatter_compact(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n)
        return;

    uint pref = s_final[i];

    // last lane writes the total
    if (i + 1u == gParams.n)
    {
        token_count[0] = pref;
    }

    if (filtered_flags[i] == 0u)
        return;

    uint k = pref - 1u;
    uint end_excl = (i + 1u == gParams.n) ? (i + 1u) : i; // off-by-one rule
    end_positions[k] = end_excl;
    types_compact[k] = tok_types[i];
}
