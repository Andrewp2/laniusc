public interface IPrefixScanOp<T>
{
    static T identity();
    static T combine(T left, T right);
}

public struct PrefixScanI32Add : IPrefixScanOp<int>
{
    public static int identity()
    {
        return 0;
    }

    public static int combine(int left, int right)
    {
        return left + right;
    }
}

public struct PrefixScanU32Add : IPrefixScanOp<uint>
{
    public static uint identity()
    {
        return 0u;
    }

    public static uint combine(uint left, uint right)
    {
        return left + right;
    }
}

public struct PrefixScanU32Max : IPrefixScanOp<uint>
{
    public static uint identity()
    {
        return 0u;
    }

    public static uint combine(uint left, uint right)
    {
        return max(left, right);
    }
}

public struct PrefixScanU32x2Add : IPrefixScanOp<uint2>
{
    public static uint2 identity()
    {
        return uint2(0u, 0u);
    }

    public static uint2 combine(uint2 left, uint2 right)
    {
        return left + right;
    }
}

public struct PrefixScanU32x4Add : IPrefixScanOp<uint4>
{
    public static uint4 identity()
    {
        return uint4(0u, 0u, 0u, 0u);
    }

    public static uint4 combine(uint4 left, uint4 right)
    {
        return left + right;
    }
}

public struct PrefixScanU32x4SumSumMaxMin : IPrefixScanOp<uint4>
{
    public static uint4 identity()
    {
        return uint4(0u, 0u, 0u, 0xffffffffu);
    }

    public static uint4 combine(uint4 left, uint4 right)
    {
        return uint4(
            left.x + right.x,
            left.y + right.y,
            max(left.z, right.z),
            min(left.w, right.w));
    }
}

public struct PrefixScanI32x2SumMinPrefix : IPrefixScanOp<int2>
{
    public static int2 identity()
    {
        return int2(0, 0);
    }

    public static int2 combine(int2 left, int2 right)
    {
        return int2(left.x + right.x, min(left.y, left.x + right.y));
    }
}

groupshared int prefix_scan_i32_values[256];
groupshared uint prefix_scan_u32_values[256];
groupshared uint2 prefix_scan_u32x2_values[256];

public T prefix_scan_inclusive<T, TOp: IPrefixScanOp<T>, let GSIZE: int>(
    uint lane,
    T value,
    inout T scan_values[GSIZE])
{
    scan_values[lane] = value;
    GroupMemoryBarrierWithGroupSync();

    for (uint offs = 1u; offs < uint(GSIZE); offs <<= 1u)
    {
        T x = scan_values[lane];
        T left = TOp.identity();
        if (lane >= offs)
            left = scan_values[lane - offs];
        GroupMemoryBarrierWithGroupSync();
        x = TOp.combine(left, x);
        scan_values[lane] = x;
        GroupMemoryBarrierWithGroupSync();
    }

    return scan_values[lane];
}

public void prefix_scan_inclusive_2<
    T,
    TOp: IPrefixScanOp<T>,
    let WG_SIZE: int,
    let SCAN_SLOTS: int>(
    uint lane,
    T value0,
    T value1,
    inout T scan_values[SCAN_SLOTS],
    out T inclusive0,
    out T inclusive1)
{
    uint slot0 = lane;
    uint slot1 = lane + uint(WG_SIZE);

    scan_values[slot0] = value0;
    scan_values[slot1] = value1;
    GroupMemoryBarrierWithGroupSync();

    for (uint offs = 1u; offs < uint(SCAN_SLOTS); offs <<= 1u)
    {
        T x0 = scan_values[slot0];
        T x1 = scan_values[slot1];
        T left0 = TOp.identity();
        T left1 = TOp.identity();
        if (slot0 >= offs)
            left0 = scan_values[slot0 - offs];
        if (slot1 >= offs)
            left1 = scan_values[slot1 - offs];
        GroupMemoryBarrierWithGroupSync();
        scan_values[slot0] = TOp.combine(left0, x0);
        scan_values[slot1] = TOp.combine(left1, x1);
        GroupMemoryBarrierWithGroupSync();
    }

    inclusive0 = scan_values[slot0];
    inclusive1 = scan_values[slot1];
}

public void prefix_scan_inclusive_4<
    T,
    TOp: IPrefixScanOp<T>,
    let WG_SIZE: int,
    let SCAN_SLOTS: int>(
    uint lane,
    T value0,
    T value1,
    T value2,
    T value3,
    inout T scan_values[SCAN_SLOTS],
    out T inclusive0,
    out T inclusive1,
    out T inclusive2,
    out T inclusive3)
{
    uint slot0 = lane;
    uint slot1 = lane + uint(WG_SIZE);
    uint slot2 = lane + uint(WG_SIZE) * 2u;
    uint slot3 = lane + uint(WG_SIZE) * 3u;

    scan_values[slot0] = value0;
    scan_values[slot1] = value1;
    scan_values[slot2] = value2;
    scan_values[slot3] = value3;
    GroupMemoryBarrierWithGroupSync();

    for (uint offs = 1u; offs < uint(SCAN_SLOTS); offs <<= 1u)
    {
        T x0 = scan_values[slot0];
        T x1 = scan_values[slot1];
        T x2 = scan_values[slot2];
        T x3 = scan_values[slot3];
        T left0 = TOp.identity();
        T left1 = TOp.identity();
        T left2 = TOp.identity();
        T left3 = TOp.identity();
        if (slot0 >= offs)
            left0 = scan_values[slot0 - offs];
        if (slot1 >= offs)
            left1 = scan_values[slot1 - offs];
        if (slot2 >= offs)
            left2 = scan_values[slot2 - offs];
        if (slot3 >= offs)
            left3 = scan_values[slot3 - offs];
        GroupMemoryBarrierWithGroupSync();
        scan_values[slot0] = TOp.combine(left0, x0);
        scan_values[slot1] = TOp.combine(left1, x1);
        scan_values[slot2] = TOp.combine(left2, x2);
        scan_values[slot3] = TOp.combine(left3, x3);
        GroupMemoryBarrierWithGroupSync();
    }

    inclusive0 = scan_values[slot0];
    inclusive1 = scan_values[slot1];
    inclusive2 = scan_values[slot2];
    inclusive3 = scan_values[slot3];
}

public void prefix_scan_inclusive_8<
    T,
    TOp: IPrefixScanOp<T>,
    let WG_SIZE: int,
    let SCAN_SLOTS: int>(
    uint lane,
    T value0,
    T value1,
    T value2,
    T value3,
    T value4,
    T value5,
    T value6,
    T value7,
    inout T scan_values[SCAN_SLOTS],
    out T inclusive0,
    out T inclusive1,
    out T inclusive2,
    out T inclusive3,
    out T inclusive4,
    out T inclusive5,
    out T inclusive6,
    out T inclusive7)
{
    uint slot0 = lane;
    uint slot1 = lane + uint(WG_SIZE);
    uint slot2 = lane + uint(WG_SIZE) * 2u;
    uint slot3 = lane + uint(WG_SIZE) * 3u;
    uint slot4 = lane + uint(WG_SIZE) * 4u;
    uint slot5 = lane + uint(WG_SIZE) * 5u;
    uint slot6 = lane + uint(WG_SIZE) * 6u;
    uint slot7 = lane + uint(WG_SIZE) * 7u;

    scan_values[slot0] = value0;
    scan_values[slot1] = value1;
    scan_values[slot2] = value2;
    scan_values[slot3] = value3;
    scan_values[slot4] = value4;
    scan_values[slot5] = value5;
    scan_values[slot6] = value6;
    scan_values[slot7] = value7;
    GroupMemoryBarrierWithGroupSync();

    for (uint offs = 1u; offs < uint(SCAN_SLOTS); offs <<= 1u)
    {
        T x0 = scan_values[slot0];
        T x1 = scan_values[slot1];
        T x2 = scan_values[slot2];
        T x3 = scan_values[slot3];
        T x4 = scan_values[slot4];
        T x5 = scan_values[slot5];
        T x6 = scan_values[slot6];
        T x7 = scan_values[slot7];
        T left0 = TOp.identity();
        T left1 = TOp.identity();
        T left2 = TOp.identity();
        T left3 = TOp.identity();
        T left4 = TOp.identity();
        T left5 = TOp.identity();
        T left6 = TOp.identity();
        T left7 = TOp.identity();
        if (slot0 >= offs)
            left0 = scan_values[slot0 - offs];
        if (slot1 >= offs)
            left1 = scan_values[slot1 - offs];
        if (slot2 >= offs)
            left2 = scan_values[slot2 - offs];
        if (slot3 >= offs)
            left3 = scan_values[slot3 - offs];
        if (slot4 >= offs)
            left4 = scan_values[slot4 - offs];
        if (slot5 >= offs)
            left5 = scan_values[slot5 - offs];
        if (slot6 >= offs)
            left6 = scan_values[slot6 - offs];
        if (slot7 >= offs)
            left7 = scan_values[slot7 - offs];
        GroupMemoryBarrierWithGroupSync();
        scan_values[slot0] = TOp.combine(left0, x0);
        scan_values[slot1] = TOp.combine(left1, x1);
        scan_values[slot2] = TOp.combine(left2, x2);
        scan_values[slot3] = TOp.combine(left3, x3);
        scan_values[slot4] = TOp.combine(left4, x4);
        scan_values[slot5] = TOp.combine(left5, x5);
        scan_values[slot6] = TOp.combine(left6, x6);
        scan_values[slot7] = TOp.combine(left7, x7);
        GroupMemoryBarrierWithGroupSync();
    }

    inclusive0 = scan_values[slot0];
    inclusive1 = scan_values[slot1];
    inclusive2 = scan_values[slot2];
    inclusive3 = scan_values[slot3];
    inclusive4 = scan_values[slot4];
    inclusive5 = scan_values[slot5];
    inclusive6 = scan_values[slot6];
    inclusive7 = scan_values[slot7];
}

public void prefix_scan_inclusive_16<
    T,
    TOp: IPrefixScanOp<T>,
    let WG_SIZE: int,
    let SCAN_SLOTS: int>(
    uint lane,
    T value0,
    T value1,
    T value2,
    T value3,
    T value4,
    T value5,
    T value6,
    T value7,
    T value8,
    T value9,
    T value10,
    T value11,
    T value12,
    T value13,
    T value14,
    T value15,
    inout T scan_values[SCAN_SLOTS],
    out T inclusive0,
    out T inclusive1,
    out T inclusive2,
    out T inclusive3,
    out T inclusive4,
    out T inclusive5,
    out T inclusive6,
    out T inclusive7,
    out T inclusive8,
    out T inclusive9,
    out T inclusive10,
    out T inclusive11,
    out T inclusive12,
    out T inclusive13,
    out T inclusive14,
    out T inclusive15)
{
    uint slot0 = lane;
    uint slot1 = lane + uint(WG_SIZE);
    uint slot2 = lane + uint(WG_SIZE) * 2u;
    uint slot3 = lane + uint(WG_SIZE) * 3u;
    uint slot4 = lane + uint(WG_SIZE) * 4u;
    uint slot5 = lane + uint(WG_SIZE) * 5u;
    uint slot6 = lane + uint(WG_SIZE) * 6u;
    uint slot7 = lane + uint(WG_SIZE) * 7u;
    uint slot8 = lane + uint(WG_SIZE) * 8u;
    uint slot9 = lane + uint(WG_SIZE) * 9u;
    uint slot10 = lane + uint(WG_SIZE) * 10u;
    uint slot11 = lane + uint(WG_SIZE) * 11u;
    uint slot12 = lane + uint(WG_SIZE) * 12u;
    uint slot13 = lane + uint(WG_SIZE) * 13u;
    uint slot14 = lane + uint(WG_SIZE) * 14u;
    uint slot15 = lane + uint(WG_SIZE) * 15u;

    scan_values[slot0] = value0;
    scan_values[slot1] = value1;
    scan_values[slot2] = value2;
    scan_values[slot3] = value3;
    scan_values[slot4] = value4;
    scan_values[slot5] = value5;
    scan_values[slot6] = value6;
    scan_values[slot7] = value7;
    scan_values[slot8] = value8;
    scan_values[slot9] = value9;
    scan_values[slot10] = value10;
    scan_values[slot11] = value11;
    scan_values[slot12] = value12;
    scan_values[slot13] = value13;
    scan_values[slot14] = value14;
    scan_values[slot15] = value15;
    GroupMemoryBarrierWithGroupSync();

    for (uint offs = 1u; offs < uint(SCAN_SLOTS); offs <<= 1u)
    {
        T x0 = scan_values[slot0];
        T x1 = scan_values[slot1];
        T x2 = scan_values[slot2];
        T x3 = scan_values[slot3];
        T x4 = scan_values[slot4];
        T x5 = scan_values[slot5];
        T x6 = scan_values[slot6];
        T x7 = scan_values[slot7];
        T x8 = scan_values[slot8];
        T x9 = scan_values[slot9];
        T x10 = scan_values[slot10];
        T x11 = scan_values[slot11];
        T x12 = scan_values[slot12];
        T x13 = scan_values[slot13];
        T x14 = scan_values[slot14];
        T x15 = scan_values[slot15];
        T left0 = TOp.identity();
        T left1 = TOp.identity();
        T left2 = TOp.identity();
        T left3 = TOp.identity();
        T left4 = TOp.identity();
        T left5 = TOp.identity();
        T left6 = TOp.identity();
        T left7 = TOp.identity();
        T left8 = TOp.identity();
        T left9 = TOp.identity();
        T left10 = TOp.identity();
        T left11 = TOp.identity();
        T left12 = TOp.identity();
        T left13 = TOp.identity();
        T left14 = TOp.identity();
        T left15 = TOp.identity();
        if (slot0 >= offs)
            left0 = scan_values[slot0 - offs];
        if (slot1 >= offs)
            left1 = scan_values[slot1 - offs];
        if (slot2 >= offs)
            left2 = scan_values[slot2 - offs];
        if (slot3 >= offs)
            left3 = scan_values[slot3 - offs];
        if (slot4 >= offs)
            left4 = scan_values[slot4 - offs];
        if (slot5 >= offs)
            left5 = scan_values[slot5 - offs];
        if (slot6 >= offs)
            left6 = scan_values[slot6 - offs];
        if (slot7 >= offs)
            left7 = scan_values[slot7 - offs];
        if (slot8 >= offs)
            left8 = scan_values[slot8 - offs];
        if (slot9 >= offs)
            left9 = scan_values[slot9 - offs];
        if (slot10 >= offs)
            left10 = scan_values[slot10 - offs];
        if (slot11 >= offs)
            left11 = scan_values[slot11 - offs];
        if (slot12 >= offs)
            left12 = scan_values[slot12 - offs];
        if (slot13 >= offs)
            left13 = scan_values[slot13 - offs];
        if (slot14 >= offs)
            left14 = scan_values[slot14 - offs];
        if (slot15 >= offs)
            left15 = scan_values[slot15 - offs];
        GroupMemoryBarrierWithGroupSync();
        scan_values[slot0] = TOp.combine(left0, x0);
        scan_values[slot1] = TOp.combine(left1, x1);
        scan_values[slot2] = TOp.combine(left2, x2);
        scan_values[slot3] = TOp.combine(left3, x3);
        scan_values[slot4] = TOp.combine(left4, x4);
        scan_values[slot5] = TOp.combine(left5, x5);
        scan_values[slot6] = TOp.combine(left6, x6);
        scan_values[slot7] = TOp.combine(left7, x7);
        scan_values[slot8] = TOp.combine(left8, x8);
        scan_values[slot9] = TOp.combine(left9, x9);
        scan_values[slot10] = TOp.combine(left10, x10);
        scan_values[slot11] = TOp.combine(left11, x11);
        scan_values[slot12] = TOp.combine(left12, x12);
        scan_values[slot13] = TOp.combine(left13, x13);
        scan_values[slot14] = TOp.combine(left14, x14);
        scan_values[slot15] = TOp.combine(left15, x15);
        GroupMemoryBarrierWithGroupSync();
    }

    inclusive0 = scan_values[slot0];
    inclusive1 = scan_values[slot1];
    inclusive2 = scan_values[slot2];
    inclusive3 = scan_values[slot3];
    inclusive4 = scan_values[slot4];
    inclusive5 = scan_values[slot5];
    inclusive6 = scan_values[slot6];
    inclusive7 = scan_values[slot7];
    inclusive8 = scan_values[slot8];
    inclusive9 = scan_values[slot9];
    inclusive10 = scan_values[slot10];
    inclusive11 = scan_values[slot11];
    inclusive12 = scan_values[slot12];
    inclusive13 = scan_values[slot13];
    inclusive14 = scan_values[slot14];
    inclusive15 = scan_values[slot15];
}

public int prefix_scan_i32_256(uint lane, int value)
{
    return prefix_scan_inclusive<int, PrefixScanI32Add, 256>(
        lane,
        value,
        prefix_scan_i32_values);
}

public uint prefix_scan_u32_256(uint lane, uint value)
{
    return prefix_scan_inclusive<uint, PrefixScanU32Add, 256>(
        lane,
        value,
        prefix_scan_u32_values);
}

public uint prefix_scan_u32_max_256(uint lane, uint value)
{
    return prefix_scan_inclusive<uint, PrefixScanU32Max, 256>(
        lane,
        value,
        prefix_scan_u32_values);
}

public uint2 prefix_scan_u32x2_256(uint lane, uint2 value)
{
    return prefix_scan_inclusive<uint2, PrefixScanU32x2Add, 256>(
        lane,
        value,
        prefix_scan_u32x2_values);
}

public uint global_exclusive_prefix(
    uint item_i,
    uint workgroup_size,
    StructuredBuffer<uint> local_prefix,
    StructuredBuffer<uint> block_prefix)
{
    uint block_i = item_i / workgroup_size;
    uint prior_blocks = block_i == 0u ? 0u : block_prefix[block_i - 1u];
    return prior_blocks + local_prefix[item_i];
}

public uint inclusive_scan_total(uint n_blocks, StructuredBuffer<uint> block_prefix)
{
    return n_blocks == 0u ? 0u : block_prefix[n_blocks - 1u];
}

public T block_prefix_scan_step<T, TOp: IPrefixScanOp<T>>(
    uint item_i,
    uint scan_step,
    StructuredBuffer<T> block_sum,
    StructuredBuffer<T> prefix_in)
{
    return parallel_scan_step_value<T, TOp>(
        item_i,
        scan_step,
        block_sum[item_i],
        prefix_in);
}

public T parallel_scan_step_value<T, TOp: IPrefixScanOp<T>>(
    uint item_i,
    uint scan_step,
    T seed_value,
    StructuredBuffer<T> prefix_in)
{
    if (scan_step == 0u)
        return seed_value;
    T value = prefix_in[item_i];
    if (item_i >= scan_step)
        value = TOp.combine(prefix_in[item_i - scan_step], value);
    return value;
}

public T exclusive_block_prefix<T, TOp: IPrefixScanOp<T>>(
    uint block_i,
    StructuredBuffer<T> inclusive_prefix)
{
    return block_i == 0u ? TOp.identity() : inclusive_prefix[block_i - 1u];
}

public int2 block_prefix_scan_step_i32_sum_min_prefix(
    uint item_i,
    uint scan_step,
    StructuredBuffer<int> block_sum,
    StructuredBuffer<int> block_min_prefix,
    StructuredBuffer<int> prefix_sum_in,
    StructuredBuffer<int> prefix_min_in)
{
    int2 summary = scan_step == 0u
        ? int2(block_sum[item_i], block_min_prefix[item_i])
        : int2(prefix_sum_in[item_i], prefix_min_in[item_i]);
    if (scan_step != 0u && item_i >= scan_step)
    {
        int2 left = int2(prefix_sum_in[item_i - scan_step],
                        prefix_min_in[item_i - scan_step]);
        summary = PrefixScanI32x2SumMinPrefix.combine(left, summary);
    }
    return summary;
}

public uint4 load_u32x4_flat(StructuredBuffer<uint> values, uint base)
{
    return uint4(
        values[base + 0u],
        values[base + 1u],
        values[base + 2u],
        values[base + 3u]);
}

public void store_u32x4_flat(RWStructuredBuffer<uint> values, uint base, uint4 value)
{
    values[base + 0u] = value.x;
    values[base + 1u] = value.y;
    values[base + 2u] = value.z;
    values[base + 3u] = value.w;
}

public uint4 parallel_scan_step_u32x4_flat<TOp: IPrefixScanOp<uint4>>(
    uint item_i,
    uint scan_step,
    uint4 seed_value,
    StructuredBuffer<uint> prefix_in,
    uint stride)
{
    if (scan_step == 0u)
        return seed_value;

    uint base = item_i * stride;
    uint4 value = load_u32x4_flat(prefix_in, base);
    if (item_i >= scan_step)
    {
        uint left_base = (item_i - scan_step) * stride;
        value = TOp.combine(load_u32x4_flat(prefix_in, left_base), value);
    }
    return value;
}
