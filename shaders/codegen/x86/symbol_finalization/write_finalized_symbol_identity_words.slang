// One lane per identity word: a word claimed by a provisional symbol takes
// the routed final identity word; every other word is copied unchanged.

import codegen.x86.symbol_finalization.symbol_finalization_layout;
import codegen.x86.symbol_finalization.symbol_publication_predicate;

StructuredBuffer<uint> fin_identity_in;
StructuredBuffer<uint> fin_word_owner;
StructuredBuffer<uint4> fin_symbol_final;
RWStructuredBuffer<uint> fin_identity_out;
RWStructuredBuffer<uint> fin_status;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint word = finalize_lane(tid);
    if (word >= gFinalize.identity_word_count || !finalize_publishable(fin_status))
        return;
    uint owner = fin_word_owner[word];
    if (owner == INVALID)
    {
        fin_identity_out[word] = fin_identity_in[word];
        return;
    }
    uint4 final_identity = fin_symbol_final[owner];
    fin_identity_out[word] = final_identity[word - final_identity.w];
}
