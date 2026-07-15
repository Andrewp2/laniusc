// Seed expression-forest depth links for logarithmic pointer jumping.

struct Params { uint n_items; uint n_blocks; uint key_step; uint reserved; };
ConstantBuffer<Params> gExprRadix;

StructuredBuffer<uint> hir_expr_parent_node;
RWStructuredBuffer<uint2> expr_depth_state;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (node >= gExprRadix.n_items)
        return;

    uint parent = hir_expr_parent_node[node];
    bool has_parent = parent != INVALID && parent < gExprRadix.n_items && parent != node;
    expr_depth_state[node] = uint2(has_parent ? parent : INVALID, has_parent ? 1u : 0u);
}
