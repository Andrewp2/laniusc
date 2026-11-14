// Resets per-job finalization state. Nothing from an earlier job survives:
// word owners, preserved-word marks, demand and failures are all rewritten.

import codegen.x86.finalize.symbol_finalize_common;

RWStructuredBuffer<uint> fin_word_owner;
RWStructuredBuffer<uint> fin_word_preserved;
RWStructuredBuffer<uint> fin_status;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = finalize_lane(tid);
    if (i < gFinalize.identity_word_count)
    {
        fin_word_owner[i] = INVALID;
        fin_word_preserved[i] = 0u;
    }
    if (i < STATUS_WORDS)
        fin_status[i] = i >= STATUS_FAILURE_BASE ? INVALID : 0u;
}
