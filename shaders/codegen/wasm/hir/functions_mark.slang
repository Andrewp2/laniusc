// Mark HIR functions and parameter ordinals for WASM body planning.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint artifact_flags;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> fn_entrypoint_tag;
StructuredBuffer<uint4> hir_param_record;

RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> wasm_func_decl_flag;
RWStructuredBuffer<uint> wasm_func_flag;
RWStructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;

static const uint INVALID = 0xffffffffu;
static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint ENTRYPOINT_MAIN = 1u;
static const uint WASM_ARTIFACT_ALLOW_MISSING_ENTRYPOINT = 1u;
static const uint HIR_PARAM_RECORD_FN = 0u;
static const uint HIR_PARAM_RECORD_ORDINAL = 1u;
static const uint HIR_PARAM_RECORD_NAME_TOKEN = 2u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_MAIN_TOKEN_MIN = 9u;
static const uint BODY_PLAN_COLLECT_INVALID_COUNT = 10u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

void publish_collect_invalid(uint detail)
{
    atomic_u32_add(body_plan, BODY_PLAN_COLLECT_INVALID_COUNT, 1u);
    atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    if (hir_kind[node] == HIR_FN)
    {
        if (hir_item_kind[node] == HIR_ITEM_KIND_EXTERN_FN)
            return;

        uint token = hir_token_pos[node];
        if (!valid_token(token))
        {
            publish_collect_invalid(INVALID);
            return;
        }

        atomic_u32_or(wasm_func_decl_flag, token, 1u);
        bool is_main = fn_entrypoint_tag[node] == ENTRYPOINT_MAIN;
        bool is_object_root =
            (gParams.artifact_flags & WASM_ARTIFACT_ALLOW_MISSING_ENTRYPOINT) != 0u;
        if (is_main || is_object_root)
            atomic_u32_or(wasm_func_flag, token, 1u);
        if (is_main)
        {
            atomic_u32_add(body_plan, BODY_PLAN_MAIN_COUNT, 1u);
            atomic_u32_min(body_plan, BODY_PLAN_MAIN_TOKEN_MIN, token);
        }
        return;
    }

    if (hir_kind[node] != HIR_PARAM)
        return;

    uint4 record = hir_param_record[node];
    uint fn_node = record[HIR_PARAM_RECORD_FN];
    uint ordinal = record[HIR_PARAM_RECORD_ORDINAL];
    uint name_token = record[HIR_PARAM_RECORD_NAME_TOKEN];
    if (valid_node(fn_node) && valid_token(name_token) && ordinal != INVALID)
        wasm_func_param_ordinal_by_decl_token[name_token] = ordinal;
}
