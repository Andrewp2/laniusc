// Validate that concrete non-void functions have parser-owned return evidence.

import status;
import fixed.compact_method;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<CompactMethodCore> compact_method_cores;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> return_fn_flags;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_FN = 3u;
static const uint HIR_ITEM_KIND_FN = 4u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint ERR_ASSIGN_MISMATCH = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
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

uint canonical_function_token(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint dense = raw_to_compact_hir[node];
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (dense == INVALID || dense >= count)
        return INVALID;
    uint token = compact_hir_payload[dense].b;
    return valid_token(token) ? token : INVALID;
}

uint canonical_item_kind(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint dense = raw_to_compact_hir[node];
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    return dense < count ? compact_hir_payload[dense].a : INVALID;
}

bool compact_impl_method(uint node)
{
    if (!valid_node(node))
        return false;
    uint dense = raw_to_compact_hir[node];
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (dense >= hir_count)
        return false;
    uint method_count = min(compact_method_count[0u], gParams.n_hir_nodes);
    uint row = compact_method_row_for_hir(
        compact_method_cores, method_count, dense);
    return row < method_count && compact_method_cores[row].node == dense &&
           compact_method_cores[row].impl_node < hir_count;
}

bool function_with_body(uint node)
{
    return valid_node(node) &&
           hir_kind[node] == HIR_FN &&
           (canonical_item_kind(node) == HIR_ITEM_KIND_FN ||
            compact_impl_method(node));
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!function_with_body(node))
        return;

    uint fn_token = canonical_function_token(node);
    if (!valid_token(fn_token))
        return;

    uint expected = call_return_type[fn_token];
    if (expected == TY_UNKNOWN || expected == TY_VOID)
        return;

    if (return_fn_flags[node] == 0u)
        record_error(fn_token, ERR_ASSIGN_MISMATCH, expected * 256u + TY_VOID);
}
