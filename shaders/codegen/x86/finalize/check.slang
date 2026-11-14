// One lane per provisional symbol: its three words must be owned by a symbol
// with the same identity range and must not hold another symbol's bytes.

import codegen.x86.finalize.symbol_finalize_common;

StructuredBuffer<uint> fin_word_owner;
StructuredBuffer<uint> fin_word_preserved;
StructuredBuffer<uint4> fin_symbol_final;
RWStructuredBuffer<uint> fin_status;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint symbol_i = finalize_lane(tid);
    if (symbol_i >= gFinalize.symbol_count)
        return;
    uint word_base = fin_symbol_final[symbol_i].w;
    if (word_base == INVALID)
        return;
    for (uint i = 0u; i < 3u; i += 1u)
    {
        uint owner = fin_word_owner[word_base + i];
        if (fin_word_preserved[word_base + i] != 0u || owner == INVALID ||
            fin_symbol_final[owner].w != word_base)
        {
            InterlockedMin(fin_status[failure_slot(FAIL_IDENTITY_OVERLAP)], symbol_i);
            return;
        }
    }
}
