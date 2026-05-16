// Paper-aligned name radix foundation.
//
// GPU-only scheduling contract:
// - Dispatch after a GPU exclusive prefix sum over run_head_mask.
// - name_count_in is the GPU-written compact name count from lexeme scatter.
// - run_head_prefix[i] is the number of unique sorted runs before i.
// - The final name id comes from the run_head/prefix pair and is scattered back
//   to the original NameSpan index.

struct Params
{
    uint name_count;
};

ConstantBuffer<Params> gParams;

struct NameSpan
{
    uint start;
    uint len;
    uint kind;
    uint token_index;
};

StructuredBuffer<NameSpan> name_spans;
StructuredBuffer<uint> name_count_in;
StructuredBuffer<uint> sorted_name_order;
StructuredBuffer<uint> run_head_mask;
StructuredBuffer<uint> run_head_prefix;
RWStructuredBuffer<uint> sorted_name_id;
RWStructuredBuffer<uint> name_id_by_input;
RWStructuredBuffer<uint> name_id_by_token;
RWStructuredBuffer<uint> language_name_id;
RWStructuredBuffer<uint> unique_name_count;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint NAME_KIND_LANGUAGE_SYMBOL = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint name_id_from_run_head(uint sorted_i)
{
    uint run_prefix = run_head_prefix[sorted_i];
    if (run_head_mask[sorted_i] != 0u)
        return run_prefix;
    if (run_prefix == 0u)
        return 0u;
    return run_prefix - 1u;
}

uint active_name_count()
{
    return min(name_count_in[0], gParams.name_count);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint name_count = active_name_count();
    if (i == 0u && name_count == 0u)
        unique_name_count[0] = 0u;
    if (i >= name_count)
        return;

    uint id = name_id_from_run_head(i);
    uint name_i = sorted_name_order[i];
    sorted_name_id[i] = id;
    name_id_by_input[name_i] = id;
    NameSpan span = name_spans[name_i];
    if (span.kind == NAME_KIND_LANGUAGE_SYMBOL)
        language_name_id[span.token_index] = id;
    else
        name_id_by_token[span.token_index] = id;

    if (i + 1u == name_count)
        unique_name_count[0] = id + 1u;
}
