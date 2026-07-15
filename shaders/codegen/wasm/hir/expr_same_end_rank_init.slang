// Seed the same-source-end expression ancestor rank.
//
// Expression bytecode is emitted in source-end order. When an expression and
// one or more of its ancestors end at the same token, descendants must precede
// those ancestors. The following pointer-jump pass turns this immediate-parent
// seed into the complete same-end ancestor count used by the radix key.

struct Params { uint n_items; uint n_blocks; uint key_step; uint reserved; };
ConstantBuffer<Params> gExprRadix;
StructuredBuffer<uint> hir_expr_parent_node;
StructuredBuffer<uint> hir_token_end;
RWStructuredBuffer<uint> expr_same_end_link;
RWStructuredBuffer<uint> expr_same_end_rank;

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
    bool same_end_parent = parent != INVALID &&
                           parent < gExprRadix.n_items &&
                           hir_token_end[parent] == hir_token_end[node];
    expr_same_end_link[node] = same_end_parent ? parent : INVALID;
    expr_same_end_rank[node] = same_end_parent ? 1u : 0u;
}
