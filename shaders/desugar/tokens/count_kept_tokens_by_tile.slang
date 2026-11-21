// Measure the kept source tokens and find the generated tokens owned by
// each source tile. The splice scans the tile counts to place the output.
import shared.buffers.gpu_index;
import desugaring_layout;

StructuredBuffer<uint> sizes;
StructuredBuffer<uint> drop;
StructuredBuffer<uint> generated_owner;
RWStructuredBuffer<uint4> splice_tiles;

groupshared uint kept;

[shader("compute")]
[numthreads(DESUGAR_SPLICE_TILE_ROWS, 1, 1)]
void main(uint3 gid: SV_GroupID, uint lane: SV_GroupIndex)
{
    uint tile = linear_group_id_2d(gid, DESUGAR_MAX_GROUPS_X);
    uint first = tile * DESUGAR_SPLICE_TILE_ROWS;
    uint tokens = sizes[S_SPLICED];
    if (first > tokens)
        return;
    if (lane == 0u)
        kept = 0u;
    GroupMemoryBarrierWithGroupSync();

    uint t = first + lane;
    bool keep = t < tokens && drop[t] == 0u;
    uint count = WaveActiveCountBits(keep);
    if (WaveIsFirstLane())
        InterlockedAdd(kept, count);
    GroupMemoryBarrierWithGroupSync();

    if (lane == 0u)
    {
        uint end = first + DESUGAR_SPLICE_TILE_ROWS;
        uint generated = sizes[S_GENERATED];
        uint lo = first_owner_at_least(generated_owner, 0u, generated, first);
        uint hi = first_owner_at_least(generated_owner, lo, generated, end);
        splice_tiles[tile] = uint4(kept, lo, hi, 0u);
    }
}
