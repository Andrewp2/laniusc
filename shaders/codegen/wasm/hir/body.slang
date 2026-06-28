// Per-HIR-node WASM body fragment records from the small scalar body plan.

import body_common;

StructuredBuffer<uint> body_plan;
StructuredBuffer<uint> status;

RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;

static const uint BODY_PLAN_OK = 1u;
static const uint BODY_PLAN_STATUS = 0u;
static const uint BODY_PLAN_MAIN_TOKEN = 1u;
static const uint BODY_PLAN_RETURN_TOKEN = 2u;
static const uint BODY_PLAN_RETURN_VALUE = 4u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE)
        return;

    if (body_plan[BODY_PLAN_STATUS] != BODY_PLAN_OK)
        return;

    uint main_token = body_plan[BODY_PLAN_MAIN_TOKEN];
    uint return_token = body_plan[BODY_PLAN_RETURN_TOKEN];
    uint return_value = body_plan[BODY_PLAN_RETURN_VALUE];

    uint token_i = INVALID;
    uint4 fragment_meta = uint4(BODY_FRAGMENT_NONE, 0u, 0u, INVALID);
    uint fragment_len = 0u;
    if (body_fragment_for_node(
            node,
            main_token,
            return_token,
            return_value,
            token_i,
            fragment_meta,
            fragment_len))
    {
        body_fragment_len[token_i] = fragment_len;
        body_fragment_meta[token_i] = fragment_meta;
    }
}
