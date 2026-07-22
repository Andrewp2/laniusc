// Validate that concrete non-void functions have compact-HIR return evidence.

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
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<CompactMethodCore> compact_method_cores;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> return_fn_flags;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_FN = 3u;
static const uint HIR_ITEM_KIND_FN = 4u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint ERR_ASSIGN_MISMATCH = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
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
    uint token = compact_hir_payload[node].b;
    return valid_token(token) ? token : INVALID;
}

uint canonical_item_kind(uint node)
{
    return valid_node(node) ? compact_hir_payload[node].a : INVALID;
}

bool compact_impl_method(uint node)
{
    if (!valid_node(node))
        return false;
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint method_count = min(compact_method_count[0u], gParams.n_hir_nodes);
    uint row = compact_method_row_for_hir(
        compact_method_cores, method_count, node);
    return row < method_count && compact_method_cores[row].node == node &&
           compact_method_cores[row].impl_node < hir_count;
}

bool function_with_body(uint node)
{
    return valid_node(node) &&
           compact_hir_core[node].kind == HIR_FN &&
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

    uint return_tag = fn_return_ref_tag[fn_token];
    if (return_tag == TYPE_REF_INVALID)
        return;
    uint expected = return_tag == TYPE_REF_SCALAR
        ? fn_return_ref_payload[fn_token]
        : TY_UNKNOWN;
    if (expected == TY_VOID)
        return;

    if (return_fn_flags[node] == 0u)
        record_error(fn_token, ERR_ASSIGN_MISMATCH, expected * 256u + TY_VOID);
}
