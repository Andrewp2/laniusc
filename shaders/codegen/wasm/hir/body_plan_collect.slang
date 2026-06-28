// Parallel collection of global facts needed by the scalar WASM body plan.

import atomics;
import body_common;

StructuredBuffer<uint> status;
RWStructuredBuffer<uint> body_plan;

static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_MAIN_TOKEN_MIN = 9u;
static const uint BODY_PLAN_COLLECT_INVALID_COUNT = 10u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;

void publish_collect_invalid(uint detail)
{
    atomic_u32_add(body_plan, BODY_PLAN_COLLECT_INVALID_COUNT, 1u);
    atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE)
        return;

    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    if (hir_kind[node] != HIR_FN || fn_entrypoint_tag[node] != ENTRYPOINT_MAIN)
        return;

    uint token = hir_token_pos[node];
    if (!valid_token(token))
    {
        publish_collect_invalid(INVALID);
        return;
    }

    atomic_u32_add(body_plan, BODY_PLAN_MAIN_COUNT, 1u);
    atomic_u32_min(body_plan, BODY_PLAN_MAIN_TOKEN_MIN, token);
}
