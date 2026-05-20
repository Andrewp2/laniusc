import sorted_runs;

static const uint SORTED_COUNT = 16u;
static const uint ITEM_CAPACITY = 12u;

StructuredBuffer<uint> sorted_order;
StructuredBuffer<uint> item_key;

RWStructuredBuffer<uint> item_out;
RWStructuredBuffer<uint> duplicate_prev_out;
RWStructuredBuffer<uint> identity_duplicate_prev_out;
RWStructuredBuffer<uint> run_head_out;
RWStructuredBuffer<uint> run_tail_out;
RWStructuredBuffer<uint> identity_run_head_out;
RWStructuredBuffer<uint> identity_run_tail_out;
RWStructuredBuffer<uint> run_head_flag_out;
RWStructuredBuffer<uint> run_id_from_prefix_out;

public struct ItemKeyEquality : ISortedRunEquality
{
    public static bool equal(uint left_item, uint right_item)
    {
        return item_key[left_item] == item_key[right_item];
    }
}

bool row_has_valid_item(uint row, out uint item)
{
    return sorted_order_item(row, SORTED_COUNT, ITEM_CAPACITY, sorted_order, item);
}

uint run_head_flag_for_row(uint row)
{
    uint item;
    if (!row_has_valid_item(row, item))
        return 0u;
    if (row == 0u)
        return sorted_run_head_flag(false);

    uint previous;
    if (!row_has_valid_item(row - 1u, previous))
        return sorted_run_head_flag(false);
    return sorted_run_head_flag(ItemKeyEquality.equal(previous, item));
}

uint run_head_prefix_for_row(uint row)
{
    uint prefix = 0u;
    [loop]
    for (uint i = 0u; i < row; i += 1u)
    {
        prefix += run_head_flag_for_row(i);
    }
    return prefix;
}

[shader("compute")]
[numthreads(16, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x;
    if (i >= SORTED_COUNT)
        return;

    uint item;
    item_out[i] = sorted_order_item(
        i,
        SORTED_COUNT,
        ITEM_CAPACITY,
        sorted_order,
        item) ? item : SORTED_RUN_INVALID;

    uint duplicate_item;
    uint prev_item;
    duplicate_prev_out[i] = sorted_adjacent_duplicate<ItemKeyEquality>(
        i,
        SORTED_COUNT,
        ITEM_CAPACITY,
        sorted_order,
        duplicate_item,
        prev_item) ? prev_item : SORTED_RUN_INVALID;

    uint identity_item;
    uint identity_prev_item;
    identity_duplicate_prev_out[i] =
        sorted_identity_adjacent_duplicate<ItemKeyEquality>(
            i,
            ITEM_CAPACITY,
            ITEM_CAPACITY,
            identity_item,
            identity_prev_item) ? identity_prev_item : SORTED_RUN_INVALID;

    uint head_item;
    run_head_out[i] = sorted_run_head<ItemKeyEquality>(
        i,
        SORTED_COUNT,
        ITEM_CAPACITY,
        sorted_order,
        head_item) ? head_item : SORTED_RUN_INVALID;

    uint tail_item;
    run_tail_out[i] = sorted_run_tail<ItemKeyEquality>(
        i,
        SORTED_COUNT,
        ITEM_CAPACITY,
        sorted_order,
        tail_item) ? tail_item : SORTED_RUN_INVALID;

    uint identity_head_item;
    identity_run_head_out[i] = sorted_identity_run_head<ItemKeyEquality>(
        i,
        ITEM_CAPACITY,
        ITEM_CAPACITY,
        identity_head_item) ? identity_head_item : SORTED_RUN_INVALID;

    uint identity_tail_item;
    identity_run_tail_out[i] = sorted_identity_run_tail<ItemKeyEquality>(
        i,
        ITEM_CAPACITY,
        ITEM_CAPACITY,
        identity_tail_item) ? identity_tail_item : SORTED_RUN_INVALID;

    uint head_flag = run_head_flag_for_row(i);
    run_head_flag_out[i] = head_flag;
    uint valid_item;
    run_id_from_prefix_out[i] = row_has_valid_item(i, valid_item)
        ? sorted_run_id_from_head_prefix(head_flag, run_head_prefix_for_row(i))
        : SORTED_RUN_INVALID;
}
