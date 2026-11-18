// Minimum heaps over the depth before each token. The closure depth scan
// already contains the inclusive depth; the preceding row is the exclusive
// depth needed to locate an enclosing opener.
import gpu_index;
import prefix_scan;
import blocked_search_tree;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint4> depth_scan;
RWStructuredBuffer<int> depth_local_min;

static const int INF = 2147483647;
groupshared int local_heap[512];

public struct DepthMin : IPrefixScanOp<int>
{
    public static int identity() { return INF; }
    public static int combine(int left, int right) { return min(left, right); }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = linear_group_id_2d(gid, 65535u);
    uint i = block * BLOCKED_SEARCH_ROWS + ltid.x;
    int depth = INF;
    if (i < token_count[0])
        depth = i == 0u ? 0 : int(depth_scan[i - 1u].x);

    blocked_local_heap_build<int, DepthMin>(ltid.x, depth, local_heap);
    depth_local_min[block * BLOCKED_SEARCH_ROWS + ltid.x] = local_heap[max(ltid.x, 1u)];
}
