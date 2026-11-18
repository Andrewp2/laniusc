// Adds each block's offset to its lanes' workgroup prefixes.
import type_checker.trait_solver.retained_catalog.retained_catalog_producer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 tid: SV_GroupThreadID)
{
    uint group = gid.x + gid.y * 65535u;
    uint lane = group * 256u + tid.x;
    if (lane >= lanes()) return;
    for (uint g = 0u; g < 4u; g++) rc_scan[lane * 4u + g] += rc_blocks[group * 4u + g];
}
