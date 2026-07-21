// Seed same-source-end ancestor ranks in dense compact-HIR identity space.

struct Params { uint n_items; uint n_blocks; uint key_step; uint reserved; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
ConstantBuffer<Params> gExprRadix;
StructuredBuffer<uint> compact_expr_parent;
StructuredBuffer<HirCore> compact_hir_core;
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
    if (node >= gExprRadix.n_items) return;
    uint parent = compact_expr_parent[node];
    bool same_end_parent = parent != INVALID && parent < gExprRadix.n_items &&
                           compact_hir_core[parent].token_end == compact_hir_core[node].token_end;
    expr_same_end_link[node] = same_end_parent ? parent : INVALID;
    expr_same_end_rank[node] = same_end_parent ? 1u : 0u;
}
