// One lane per symbol: writes the staged symbol row. Rewritten identities get
// their hash recomputed here; every other row is copied unchanged. Lane zero
// seals the job with its generation only after a publishable result.

import codegen.x86.finalize.symbol_finalize_common;
import codegen.x86.finalize.publish_common;

StructuredBuffer<uint> fin_symbols_in;
StructuredBuffer<uint4> fin_symbol_final;
RWStructuredBuffer<uint> fin_symbols_out;
RWStructuredBuffer<uint> fin_status;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint symbol_i = finalize_lane(tid);
    if (!finalize_publishable(fin_status))
        return;
    if (symbol_i == 0u)
        fin_status[STATUS_PUBLISHED] = gFinalize.generation;
    if (symbol_i >= gFinalize.symbol_count)
        return;
    uint row = symbol_i * SYMBOL_WORDS;
    uint4 final_identity = fin_symbol_final[symbol_i];
    uint2 hash = final_identity.w == INVALID
        ? uint2(fin_symbols_in[row], fin_symbols_in[row + 1u])
        : identity_hash(final_identity.xyz);
    fin_symbols_out[row] = hash.x;
    fin_symbols_out[row + 1u] = hash.y;
    for (uint i = 2u; i < SYMBOL_WORDS; i += 1u)
        fin_symbols_out[row + i] = fin_symbols_in[row + i];
}
