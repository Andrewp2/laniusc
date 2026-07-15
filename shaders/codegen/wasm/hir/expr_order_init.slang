// Initialize the expression-root radix order with original HIR node ids.

struct Params { uint n_items; uint n_blocks; uint key_step; uint reserved; };
ConstantBuffer<Params> gExprRadix;
RWStructuredBuffer<uint> expr_order;

static const uint INVALID = 0xffffffffu;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (node < gExprRadix.n_items)
        expr_order[node] = node;
}
