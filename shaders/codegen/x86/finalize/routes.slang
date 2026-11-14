// One lane per route-table row: checks upstream readiness and that every use
// in 0..use_count has a route written for this build to an admitted final
// identity. Routes are flat: a use never targets another use.

import codegen.x86.finalize.symbol_finalize_common;

// (generation, readiness flags, instance count, use count)
StructuredBuffer<uint4> fin_readiness;
// (library, namespace or unit, local identity, generation)
StructuredBuffer<uint4> fin_routes;
RWStructuredBuffer<uint> fin_status;

void fail(uint code, uint detail)
{
    InterlockedMin(fin_status[failure_slot(code)], detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint use_i = finalize_lane(tid);
    uint4 readiness = fin_readiness[0u];
    if (use_i == 0u)
    {
        if (readiness.x != gFinalize.generation)
            fail(FAIL_READINESS, READINESS_GENERATION);
        if ((readiness.y & READY_ROUTES_PUBLISHED) == 0u)
            fail(FAIL_READINESS, READINESS_ROUTES_UNPUBLISHED);
        if ((readiness.y & READY_ABI_CERTIFIED) == 0u)
            fail(FAIL_READINESS, READINESS_ABI_UNCERTIFIED);
        if (readiness.w > gFinalize.route_capacity)
            fail(FAIL_READINESS, READINESS_ROUTE_TABLE_SHORT);
    }
    if (use_i >= min(readiness.w, gFinalize.route_capacity))
        return;
    uint4 route = fin_routes[use_i];
    if (route.w != gFinalize.generation)
    {
        fail(FAIL_ROUTE_MISSING, use_i);
        return;
    }
    if (route.x == OBJECT_LOCAL)
    {
        fail(FAIL_ROUTE_INVALID_IDENTITY, use_i);
        return;
    }
    if (route.x != RESERVED_LIB)
        return; // ordinary DeclNative identity
    if (route.y == NS_USE)
        fail(FAIL_ROUTE_USE_CHAIN, use_i);
    else if (route.y != NS_INSTANCE)
        fail(FAIL_ROUTE_INVALID_IDENTITY, use_i);
    else if (route.z >= readiness.z)
        fail(FAIL_ROUTE_OUT_OF_RANGE, use_i);
}
