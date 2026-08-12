// Exact balanced-prefix interning shared by the insert and lookup rounds.

static const uint PATH_PREFIX_INVALID = 0xffffffffu;
static const uint PATH_PREFIX_TABLE_EMPTY = 0u;
static const uint PATH_PREFIX_OWNER_MASK = 0x07ffffffu;
static const uint PATH_PREFIX_EPOCH_SHIFT = 27u;

uint path_prefix_table_owner(uint state)
{
    uint encoded = state & PATH_PREFIX_OWNER_MASK;
    return encoded == 0u ? PATH_PREFIX_INVALID : encoded - 1u;
}

uint path_prefix_table_epoch(uint state)
{
    return state >> PATH_PREFIX_EPOCH_SHIFT;
}

uint path_prefix_table_state_for_owner(uint owner, uint epoch)
{
    return (epoch << PATH_PREFIX_EPOCH_SHIFT) | (owner + 1u);
}

uint path_prefix_mix(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

uint path_prefix_first_slot(uint left, uint right, uint capacity)
{
    uint key = path_prefix_mix(left ^ 0x9e3779b9u);
    key ^= path_prefix_mix(right ^ 0x85ebca6bu);
    return capacity == 0u ? 0u : path_prefix_mix(key) % capacity;
}

uint2 path_prefix_pair(
    uint row,
    uint step,
    StructuredBuffer<uint> prefix_base,
    StructuredBuffer<uint> prefix_id)
{
    uint base = prefix_base[row];
    uint left = row >= base && row - base >= step
        ? prefix_id[row - step]
        : PATH_PREFIX_INVALID;
    return uint2(left, prefix_id[row]);
}
