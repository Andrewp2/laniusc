// Propagate nearest generic-declaration owners with pointer jumping.
//
// Each dispatch doubles the ancestor distance represented by parent_jump_*.
// Rust schedules enough ping-pong steps for the HIR capacity and leaves the
// final owner table in generic_decl_owner_by_node_a for downstream passes.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> generic_decl_owner_by_node_in;
StructuredBuffer<uint> generic_decl_parent_jump_in;

RWStructuredBuffer<uint> generic_decl_owner_by_node_out;
RWStructuredBuffer<uint> generic_decl_parent_jump_out;

static const uint INVALID = 0xffffffffu;
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    uint owner = generic_decl_owner_by_node_in[node];
    uint jump = generic_decl_parent_jump_in[node];
    if (owner == INVALID && valid_node(jump))
        owner = generic_decl_owner_by_node_in[jump];

    uint next_jump = INVALID;
    if (valid_node(jump))
        next_jump = generic_decl_parent_jump_in[jump];

    generic_decl_owner_by_node_out[node] = owner;
    generic_decl_parent_jump_out[node] = next_jump;
}
