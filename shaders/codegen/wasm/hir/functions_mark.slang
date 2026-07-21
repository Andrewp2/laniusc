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

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirParam { uint owner; uint name_token; uint type_node; uint ordinal; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<uint> fn_entrypoint_tag;

RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> wasm_func_decl_flag;
RWStructuredBuffer<uint> wasm_func_flag;
RWStructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;

static const uint INVALID = 0xffffffffu;
static const uint HIR_FN = 3u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint ENTRYPOINT_MAIN = 1u;
static const uint WASM_ARTIFACT_ALLOW_MISSING_ENTRYPOINT = 1u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_MAIN_TOKEN_MIN = 9u;
static const uint BODY_PLAN_COLLECT_INVALID_COUNT = 10u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
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
    uint row = linear_dispatch_id(tid);
    uint hir_count = active_hir_count();
    if (row < hir_count && compact_hir_core[row].kind == HIR_FN)
    {
        HirCore core = compact_hir_core[row];
        HirPayload payload = compact_hir_payload[row];
        if (payload.a != HIR_ITEM_KIND_EXTERN_FN)
        {
            uint token = core.token_start;
            if (!valid_token(token))
                publish_collect_invalid(INVALID);
            else
            {
                atomic_u32_or(wasm_func_decl_flag, token, 1u);
                bool is_main = fn_entrypoint_tag[token] == ENTRYPOINT_MAIN;
                bool is_object_root =
                    (gParams.artifact_flags & WASM_ARTIFACT_ALLOW_MISSING_ENTRYPOINT) != 0u;
                if (is_main || is_object_root)
                    atomic_u32_or(wasm_func_flag, token, 1u);
                if (is_main)
                {
                    atomic_u32_add(body_plan, BODY_PLAN_MAIN_COUNT, 1u);
                    atomic_u32_min(body_plan, BODY_PLAN_MAIN_TOKEN_MIN, token);
                }
            }
        }

        // Function rows and parameter rows are independent compact domains
        // that merely share this dispatch lane. Never return from the
        // function-side action before publishing the parameter-side action
        // with the same numeric row.
    }

    uint param_count = min(compact_param_count[0u], gParams.n_hir_nodes);
    if (row >= param_count)
        return;

    HirParam parameter = compact_params[row];
    if (parameter.owner < hir_count &&
        compact_hir_core[parameter.owner].kind == HIR_FN &&
        valid_token(parameter.name_token) && parameter.ordinal != INVALID)
        wasm_func_param_ordinal_by_decl_token[parameter.name_token] = parameter.ordinal;
}
