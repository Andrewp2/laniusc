// Project aggregate field ordinals for HIR-driven WASM lowering.
//
// Type checking already resolves member and struct-literal field ordinals with
// sorted HIR/type records. This active WASM boundary only copies those records
// into the legacy token-keyed buffers that the aggregate layout clear pass owns.
// Unsupported or unresolved aggregate shapes remain INVALID from the clear pass.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> member_result_field_ordinal;
StructuredBuffer<uint> struct_init_field_ordinal_by_node;

RWStructuredBuffer<uint> struct_init_field_index;
RWStructuredBuffer<uint> member_result_field_index;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

static const uint HIR_MEMBER_EXPR = 21u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_hir_node_count();
}

uint field_name_token(uint field_node)
{
    uint token_i = valid_node(field_node) ? hir_token_pos[field_node] : INVALID;
    return token_i < gParams.n_tokens ? token_i : INVALID;
}

void publish_member_projection(uint member_node)
{
    uint member_i = valid_node(member_node) ? hir_member_name_token[member_node] : INVALID;
    if (member_i >= gParams.n_tokens)
        return;

    uint index = member_result_field_ordinal[member_i];
    if (index != INVALID)
        member_result_field_index[member_i] = index;
}

void publish_struct_init_projection(uint field_node)
{
    uint field_i = field_name_token(field_node);
    if (field_i == INVALID || field_i >= gParams.n_tokens)
        return;

    uint index = struct_init_field_ordinal_by_node[field_node];
    if (index != INVALID)
        struct_init_field_index[field_i] = index;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_id(tid);
    if (i >= active_hir_node_count())
        return;

    if (hir_struct_lit_field_parent_lit[i] != INVALID)
        publish_struct_init_projection(i);
    else if (hir_kind[i] == HIR_MEMBER_EXPR)
        publish_member_projection(i);
}
