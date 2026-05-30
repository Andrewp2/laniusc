// Bind HIR `self` member receivers to their method receiver declaration.
//
// This pass consumes method declaration metadata and parser-owned member
// receiver records. It publishes visible-decl entries for `self` receiver uses
// inside methods without inspecting token kinds, spelling, source bytes, or
// token neighborhoods. Function ownership is consumed from the token-level
// enclosing_fn relation produced by the function-context scan, not rediscovered
// by walking HIR parents.

import generated_parse_production_ids;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_receiver_token;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> method_decl_param_offset;

RWStructuredBuffer<uint> visible_decl;

static const uint INVALID = 0xffffffffu;

static const uint HIR_MEMBER_EXPR = 21u;

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

uint enclosing_function_token_for_receiver(uint receiver_token)
{
    uint encoded_fn = valid_token(receiver_token) ? enclosing_fn[receiver_token] : 0u;
    return encoded_fn == 0u ? INVALID : encoded_fn - 1u;
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

    uint fn_token = enclosing_function_token_for_receiver(self_token);
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
