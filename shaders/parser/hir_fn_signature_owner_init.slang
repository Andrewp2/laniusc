// Seed nearest function-signature owner propagation over parse-tree rows.
//
// The production tree may place a function return type under grammar tails such
// as parameter/type-path continuations. This pass seeds parse-tree pointer
// jumping so a later HIR pass can identify type nodes that are inside a
// return_type_opt production and the nearest function declaration that owns
// them, without inspecting source bytes or token spellings.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirFnSignatureOwner;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;

RWStructuredBuffer<uint> hir_fn_signature_owner_link_a;
RWStructuredBuffer<uint> hir_fn_signature_return_owner_a;
RWStructuredBuffer<uint> hir_fn_signature_function_owner_a;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_FN = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirFnSignatureOwner.uses_ll1 != 0u
               ? min(gHirFnSignatureOwner.n, ll1_status[5u])
               : gHirFnSignatureOwner.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

bool function_decl_node(uint node)
{
    if (!valid_node(node) || hir_kind[node] != HIR_FN)
        return false;
    uint prod = node_kind[node];
    return prod == PROD_FN || prod == PROD_EXTERN_FN || prod == PROD_IMPL_FN;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    uint p = parent[node];
    hir_fn_signature_owner_link_a[node] = valid_node(p) ? p : INVALID;
    hir_fn_signature_return_owner_a[node] = node_kind[node] == PROD_RET_TYPE ? node : INVALID;
    hir_fn_signature_function_owner_a[node] = function_decl_node(node) ? node : INVALID;
}
