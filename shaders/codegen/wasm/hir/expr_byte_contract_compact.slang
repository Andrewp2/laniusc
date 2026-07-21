// Compile-time migration probe for the reusable dense-HIR byte contract.
// It is not dispatched by production until fragment metadata is dense.

import compact_expr_common;
import compact_expr_byte_common;

RWStructuredBuffer<uint> compact_expr_first_byte;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (!valid_node(node)) return;
    uint root = compact_expr_root[node];
    compact_expr_first_byte[node] = valid_node(root)
                                        ? compact_expr_tree_byte(root, 0u)
                                        : 0u;
}
