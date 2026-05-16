// Bind HIR `self` member receivers to their method receiver declaration.
//
// This pass consumes method declaration metadata and parser-owned member
// receiver records. It publishes visible-decl entries for `self` receiver uses
// inside methods without inspecting token kinds, spelling, source bytes, or
// token neighborhoods.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_receiver_token;
StructuredBuffer<uint> method_decl_param_offset;

RWStructuredBuffer<uint> visible_decl;

static const uint INVALID = 0xffffffffu;

static const uint HIR_FN = 3u;
static const uint HIR_MEMBER_EXPR = 21u;

static const uint PROD_SELF_VALUE = 158u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

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

uint parent_node(uint node)
{
    uint p = valid_node(node) ? parent[node] : INVALID;
    return valid_node(p) ? p : INVALID;
}

uint enclosing_function_node(uint node)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        if (hir_kind[cur] == HIR_FN)
            return cur;

        uint p = parent_node(cur);
        if (!valid_node(p) || p == cur)
            return INVALID;
        cur = p;
    }
    return INVALID;
}

void bind_self_receiver_for_member(uint member_node)
{
    if (hir_kind[member_node] != HIR_MEMBER_EXPR)
        return;

    uint receiver_node = hir_member_receiver_node[member_node];
    if (!valid_node(receiver_node) || node_kind[receiver_node] != PROD_SELF_VALUE)
        return;

    uint self_token = hir_member_receiver_token[member_node];
    if (!valid_token(self_token))
        return;

    uint fn_node = enclosing_function_node(member_node);
    uint fn_token = valid_node(fn_node) ? hir_token_pos[fn_node] : INVALID;
    if (!valid_token(fn_token))
        return;

    uint self_decl = method_decl_param_offset[fn_token];
    if (!valid_token(self_decl))
        return;

    visible_decl[self_decl] = self_decl;
    visible_decl[self_token] = self_decl;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    bind_self_receiver_for_member(node);
}
