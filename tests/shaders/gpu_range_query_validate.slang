import gpu_index;
import range_query;

static const uint SORTED_COUNT = 64u;
static const uint QUERY_COUNT = 32u;

StructuredBuffer<uint> sorted2_a;
StructuredBuffer<uint> sorted2_b;
StructuredBuffer<uint> query2_a;
StructuredBuffer<uint> query2_b;
StructuredBuffer<uint> sorted4_a;
StructuredBuffer<uint> sorted4_b;
StructuredBuffer<uint> sorted4_c;
StructuredBuffer<uint> sorted4_d;
StructuredBuffer<uint> query4_a;
StructuredBuffer<uint> query4_b;
StructuredBuffer<uint> query4_c;
StructuredBuffer<uint> query4_d;

RWStructuredBuffer<uint> query2_begin_out;
RWStructuredBuffer<uint> query2_end_out;
RWStructuredBuffer<uint> query2_row_out;
RWStructuredBuffer<uint> query4_begin_out;
RWStructuredBuffer<uint> query4_end_out;
RWStructuredBuffer<uint> query4_row_out;

public struct Query2Key
{
    uint a;
    uint b;
}

public struct Query2Compare : IRowQueryCompare<Query2Key>
{
    public static int compare(uint row, Query2Key key)
    {
        int cmp = compare_u32(sorted2_a[row], key.a);
        if (cmp != 0)
            return cmp;
        return compare_u32(sorted2_b[row], key.b);
    }
}

public struct Query4Key
{
    uint a;
    uint b;
    uint c;
    uint d;
}

public struct Query4Compare : IRowQueryCompare<Query4Key>
{
    public static int compare(uint row, Query4Key key)
    {
        int cmp = compare_u32(sorted4_a[row], key.a);
        if (cmp != 0)
            return cmp;
        cmp = compare_u32(sorted4_b[row], key.b);
        if (cmp != 0)
            return cmp;
        cmp = compare_u32(sorted4_c[row], key.c);
        if (cmp != 0)
            return cmp;
        return compare_u32(sorted4_d[row], key.d);
    }
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x;
    if (i >= QUERY_COUNT)
        return;

    Query2Key key2;
    key2.a = query2_a[i];
    key2.b = query2_b[i];
    QueryRange range2 = equal_range_query<Query2Key, Query2Compare>(
        SORTED_COUNT,
        key2);
    query2_begin_out[i] = range2.begin;
    query2_end_out[i] = range2.end;
    query2_row_out[i] = find_equal_query<Query2Key, Query2Compare>(
        SORTED_COUNT,
        key2);

    Query4Key key4;
    key4.a = query4_a[i];
    key4.b = query4_b[i];
    key4.c = query4_c[i];
    key4.d = query4_d[i];
    QueryRange range4 = equal_range_query<Query4Key, Query4Compare>(
        SORTED_COUNT,
        key4);
    query4_begin_out[i] = range4.begin;
    query4_end_out[i] = range4.end;
    query4_row_out[i] = find_equal_query<Query4Key, Query4Compare>(
        SORTED_COUNT,
        key4);
}
