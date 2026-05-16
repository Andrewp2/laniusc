// Attach method declaration metadata from GPU module/name/type tables.
//
// The receiver type is located through parser tree children of impl_item. This
// keeps method records tied to AST/HIR structure instead of rediscovering impl
// headers by token scans.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> module_id_by_file_id;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> method_decl_impl_node;
StructuredBuffer<uint> method_decl_name_token;

RWStructuredBuffer<uint> method_decl_receiver_ref_tag;
RWStructuredBuffer<uint> method_decl_receiver_ref_payload;
RWStructuredBuffer<uint> method_decl_module_id;
RWStructuredBuffer<uint> method_decl_name_id;

static const uint INVALID = 0xffffffffu;
static const uint HIR_FN = 3u;
static const uint HIR_TYPE = 5u;
static const uint TYPE_REF_INVALID = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return gParams.n_tokens;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_hir_node_count();
}

uint module_for_token(uint i)
{
    uint file_id = i < active_token_count() ? token_file_id[i] : INVALID;
    if (file_id == INVALID)
        return INVALID;
    if (gParams.n_hir_nodes == 0u)
        return file_id == 0u ? module_id_by_file_id[0u] : INVALID;
    uint module_id = file_id < gParams.n_hir_nodes ? module_id_by_file_id[file_id] : INVALID;
    if (module_id != INVALID)
        return module_id;
    return file_id == 0u ? 0u : INVALID;
}

uint name_id_for_token(uint i)
{
    return i < active_token_count() ? name_id_by_token[i] : INVALID;
}

uint parent_node(uint node)
{
    uint p = valid_node(node) ? parent[node] : INVALID;
    return valid_node(p) ? p : INVALID;
}

bool has_ancestor_before_fn(uint node, uint ancestor)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (!valid_node(cur))
            return false;
        if (cur == ancestor)
            return true;
        if (cur != node && hir_kind[cur] == HIR_FN)
            return false;
        uint p = parent_node(cur);
        if (!valid_node(p) || p == cur)
            return false;
        cur = p;
    }
    return false;
}

bool has_type_ancestor_before(uint node, uint ancestor)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (!valid_node(cur))
            return false;
        uint p = parent_node(cur);
        if (!valid_node(p) || p == cur || p == ancestor)
            return false;
        if (hir_kind[p] == HIR_FN)
            return false;
        if (hir_kind[p] == HIR_TYPE)
            return true;
        cur = p;
    }
    return false;
}

uint impl_receiver_type_node(uint impl_node)
{
    uint receiver = INVALID;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_kind[node] == HIR_TYPE && has_ancestor_before_fn(node, impl_node) &&
            !has_type_ancestor_before(node, impl_node))
            receiver = node;
    }
    return receiver;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_token_count())
        return;

    uint impl_node = method_decl_impl_node[i];
    if (!valid_node(impl_node))
        return;

    uint impl_token = hir_token_pos[impl_node];
    uint type_node = impl_receiver_type_node(impl_node);
    uint type_i = type_node == INVALID ? INVALID : hir_token_pos[type_node];

    method_decl_receiver_ref_tag[i] =
        type_i == INVALID || type_i >= active_token_count() ? TYPE_REF_INVALID
                                                            : type_expr_ref_tag[type_i];
    method_decl_receiver_ref_payload[i] =
        type_i == INVALID || type_i >= active_token_count() ? INVALID : type_expr_ref_payload[type_i];
    method_decl_module_id[i] = module_for_token(impl_token);
    method_decl_name_id[i] = name_id_for_token(method_decl_name_token[i]);
}
