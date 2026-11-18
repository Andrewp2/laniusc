// One lane: checks the upstream readiness record. Route rows are checked
// where a provisional symbol names them (claim_provisional_symbol_identity_words.slang), so a sparse table
// whose unused rows were never written is valid.

import codegen.x86.symbol_finalization.symbol_finalization_layout;

// (generation, readiness flags, instance count, use count)
StructuredBuffer<uint4> fin_readiness;
RWStructuredBuffer<uint> fin_status;

void fail(uint code, uint detail)
{
    InterlockedMin(fin_status[failure_slot(code)], detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (finalize_lane(tid) != 0u)
        return;
    uint4 readiness = fin_readiness[0u];
    if (readiness.x != gFinalize.generation)
        fail(FAIL_READINESS, READINESS_GENERATION);
    if ((readiness.y & READY_ROUTES_PUBLISHED) == 0u)
        fail(FAIL_READINESS, READINESS_ROUTES_UNPUBLISHED);
    if ((readiness.y & READY_ABI_CERTIFIED) == 0u)
        fail(FAIL_READINESS, READINESS_ABI_UNCERTIFIED);
    if (readiness.w > gFinalize.route_capacity)
        fail(FAIL_READINESS, READINESS_ROUTE_TABLE_SHORT);
}
