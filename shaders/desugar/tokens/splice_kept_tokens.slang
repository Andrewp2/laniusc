// Place the kept source tokens and record how many kept tokens precede
// each insertion. Only tiles with a deletion need a local prefix sum.
import shared.buffers.gpu_index;
import shared.collectives.prefix_scan;
import desugaring_layout;

StructuredBuffer<uint> sizes;
StructuredBuffer<TokenRow> tokens_out;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> drop;
StructuredBuffer<uint> generated_owner;
StructuredBuffer<uint4> splice_tiles;
StructuredBuffer<uint4> splice_scan;
RWStructuredBuffer<uint> insert_kept_prefix;
RWStructuredBuffer<TokenRow> spliced;
RWStructuredBuffer<uint> spliced_file;

groupshared uint kept_lanes[DESUGAR_SPLICE_TILE_ROWS];

[shader("compute")]
[numthreads(DESUGAR_SPLICE_TILE_ROWS, 1, 1)]
void main(uint3 gid: SV_GroupID, uint lane: SV_GroupIndex)
{
    uint tile = linear_group_id_2d(gid, DESUGAR_MAX_GROUPS_X);
    uint first = tile * DESUGAR_SPLICE_TILE_ROWS;
    uint count = sizes[S_SPLICED];
    if (first > count || sizes[S_OUT] == 0u)
        return;

    uint t = first + lane;
    uint4 span = splice_tiles[tile];
    uint source_rows = min(count - first, DESUGAR_SPLICE_TILE_ROWS);
    uint keep = t < count && drop[t] == 0u ? 1u : 0u;
    uint local_before = min(lane, source_rows);
    if (span.x != source_rows)
    {
        local_before = prefix_scan_inclusive<uint, PrefixScanU32Add, DESUGAR_SPLICE_TILE_ROWS>(
            lane, keep, kept_lanes) - keep;
    }
    if (t > count)
        return;

    uint before = (tile == 0u ? 0u : splice_scan[tile - 1u].x) + local_before;
    uint through_inserted = first_owner_at_least(generated_owner, span.y, span.z, t + 1u);
    if (through_inserted > span.y && generated_owner[through_inserted - 1u] == t)
        insert_kept_prefix[t] = before;
    if (keep != 0u)
    {
        uint out_at = before + through_inserted;
        spliced[out_at] = tokens_out[t];
        spliced_file[out_at] = token_file_id[t];
    }
}
