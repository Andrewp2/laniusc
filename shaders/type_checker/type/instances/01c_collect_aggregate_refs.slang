// HIR-driven array and slice instance headers.
//
// The pass publishes token-indexed instance refs for aggregate type forms.
// Element and length refs are filled in a later pass after all child type refs
// have been materialized.

import hir_records;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;

RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> type_instance_kind;
RWStructuredBuffer<uint> type_instance_head_token;
RWStructuredBuffer<uint> type_instance_state;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;

static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint HIR_TYPE_FORM_SLICE = 3u;

static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_INSTANCE_UNRESOLVED = 2u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_compact_hir_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_compact_hir_count())
        return;
    if (compact_hir_core[node].kind != HIR_TYPE)
        return;

    uint form = compact_hir_payload[node].a;
    if (form != HIR_TYPE_FORM_ARRAY && form != HIR_TYPE_FORM_SLICE)
        return;

    uint token = compact_hir_core[node].token_start;
    if (!valid_token(token))
        return;

    type_expr_ref_tag[token] = TYPE_REF_INSTANCE;
    type_expr_ref_payload[token] = token;
    type_instance_kind[token] = form == HIR_TYPE_FORM_ARRAY ? TYPE_INSTANCE_ARRAY
                                                            : TYPE_INSTANCE_SLICE;
    type_instance_head_token[token] = token;
    type_instance_state[token] = TYPE_INSTANCE_UNRESOLVED;
}
