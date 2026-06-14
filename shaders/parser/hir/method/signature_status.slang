// Publish parser-owned method signature flags.
//
// Function-signature owner pointer jumping already maps every parse node in a
// method/function signature back to the nearest HIR function node. This pass
// scatters method-level generic and where markers from method syntax rows into
// a method-node keyed flag table, so predicate validation does not scan method
// child lists to rediscover unsupported signature metadata.

import atomics;
import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirMethodSignatureStatus;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_fn_signature_function_owner;

RWStructuredBuffer<uint> hir_method_signature_flags;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_FN = 3u;
static const uint METHOD_SIGNATURE_HAS_GENERICS = 1u;
static const uint METHOD_SIGNATURE_HAS_WHERE = 2u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirMethodSignatureStatus.uses_status_count != 0u
               ? min(gHirMethodSignatureStatus.n, tree_count_status[5u])
               : gHirMethodSignatureStatus.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

bool method_signature_owner_node(uint node)
{
    if (!valid_node(node) || hir_kind[node] != HIR_FN)
        return false;

    uint prod = node_kind[node];
    return prod == PROD_IMPL_FN ||
           prod == PROD_TRAIT_METHOD ||
           prod == PROD_TRAIT_METHOD_PUB;
}

bool direct_method_signature_marker(uint node)
{
    uint owner = hir_fn_signature_function_owner[node];
    if (!method_signature_owner_node(owner))
        return false;

    uint p = parent[node];
    return p == owner;
}

uint signature_flag_for_node(uint node)
{
    if (!direct_method_signature_marker(node))
        return 0u;

    uint prod = node_kind[node];
    if (prod == PROD_ENUM_TYPE_PARAMS_SOME)
        return METHOD_SIGNATURE_HAS_GENERICS;
    if (prod == PROD_WHERE_SOME)
        return METHOD_SIGNATURE_HAS_WHERE;
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    uint flag = signature_flag_for_node(node);
    if (flag == 0u)
        return;

    uint method_node = hir_fn_signature_function_owner[node];
    if (!method_signature_owner_node(method_node))
        return;

    atomic_u32_or(hir_method_signature_flags, method_node, flag);
}
