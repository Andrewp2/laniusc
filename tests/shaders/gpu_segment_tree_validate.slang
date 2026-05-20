import segment_tree;

static const uint BLOCK_COUNT = 13u;
static const uint LEAF_BASE = 16u;
static const uint QUERY_COUNT = 32u;
static const uint ROW_COUNT = 49u;
static const uint ROW_BLOCK_SIZE = 4u;

StructuredBuffer<int> row_value_in;
StructuredBuffer<int> leaf_value_in;
StructuredBuffer<int> tree_value_in;
StructuredBuffer<uint> mask_leaf_value_in;
StructuredBuffer<uint> mask_tree_value_in;
StructuredBuffer<uint> query_lo;
StructuredBuffer<uint> query_hi;
StructuredBuffer<uint> query_lo_index;
StructuredBuffer<uint> query_hi_index;
StructuredBuffer<int> query_target;
StructuredBuffer<uint> mask_query;

RWStructuredBuffer<uint> next_block_out;
RWStructuredBuffer<uint> previous_block_out;
RWStructuredBuffer<uint> next_index_out;
RWStructuredBuffer<uint> previous_index_out;
RWStructuredBuffer<uint> mask_next_block_out;
RWStructuredBuffer<uint> mask_previous_block_out;

public struct TestRangeMaxTree : IRangeSearchTree<int>
{
    public static uint n_blocks()
    {
        return BLOCK_COUNT;
    }

    public static uint leaf_base()
    {
        return LEAF_BASE;
    }

    public static int leaf_value(uint block)
    {
        return leaf_value_in[block];
    }

    public static int tree_value(uint node)
    {
        return tree_value_in[node];
    }
}

public struct TestRangeRows : IRangeSearchRows<int>
{
    public static uint item_count()
    {
        return ROW_COUNT;
    }

    public static uint block_size()
    {
        return ROW_BLOCK_SIZE;
    }

    public static int row_value(uint row)
    {
        return row_value_in[row];
    }
}

public struct TestMaskTree : IRangeSearchTree<uint>
{
    public static uint n_blocks()
    {
        return BLOCK_COUNT;
    }

    public static uint leaf_base()
    {
        return LEAF_BASE;
    }

    public static uint leaf_value(uint block)
    {
        return mask_leaf_value_in[block];
    }

    public static uint tree_value(uint node)
    {
        return mask_tree_value_in[node];
    }
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x;
    if (i >= QUERY_COUNT)
        return;

    uint next_block;
    next_block_out[i] = range_search_tree_first_block_at_or_after<int, int, TestRangeMaxTree, RangeSearchI32AtLeast>(
        query_lo[i],
        query_target[i],
        next_block) ? next_block : 0xffffffffu;

    uint previous_block;
    previous_block_out[i] = range_search_tree_last_block_before<int, int, TestRangeMaxTree, RangeSearchI32AtLeast>(
        query_hi[i],
        query_target[i],
        previous_block) ? previous_block : 0xffffffffu;

    uint next_index;
    next_index_out[i] = range_search_tree_first_index_at_or_after<int, int, TestRangeMaxTree, TestRangeRows, RangeSearchI32AtLeast>(
        query_lo_index[i],
        query_target[i],
        next_index) ? next_index : 0xffffffffu;

    uint previous_index;
    previous_index_out[i] = range_search_tree_last_index_before<int, int, TestRangeMaxTree, TestRangeRows, RangeSearchI32AtLeast>(
        query_hi_index[i],
        query_target[i],
        previous_index) ? previous_index : 0xffffffffu;

    uint mask_next_block;
    mask_next_block_out[i] = range_search_tree_first_block_at_or_after<uint, uint, TestMaskTree, RangeSearchU32BitsetIntersects>(
        query_lo[i],
        mask_query[i],
        mask_next_block) ? mask_next_block : 0xffffffffu;

    uint mask_previous_block;
    mask_previous_block_out[i] = range_search_tree_last_block_before<uint, uint, TestMaskTree, RangeSearchU32BitsetIntersects>(
        query_hi[i],
        mask_query[i],
        mask_previous_block) ? mask_previous_block : 0xffffffffu;
}
