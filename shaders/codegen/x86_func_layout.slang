// x86_64 function layout projection.
//
// Instruction counts and prefix/range assignment are owned by earlier GPU
// passes. This pass scatters the resulting per-function ranges into the stable
// x86_func_layout_record buffer consumed by instruction and relocation planning.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint4> x86_func_inst_count_record;
StructuredBuffer<uint> x86_func_inst_count_status;
StructuredBuffer<uint4> x86_func_inst_range_record;
StructuredBuffer<uint> x86_func_inst_range_status;

RWStructuredBuffer<uint4> x86_func_layout_record;
RWStructuredBuffer<uint> x86_func_layout_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_FUNC_INST_COUNT_OK = 1u;
static const uint X86_FUNC_INST_RANGE_OK = 1u;
static const uint X86_FUNC_LAYOUT_OK = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool upstream_ok()
{
    return x86_func_inst_count_status[0u] == X86_FUNC_INST_COUNT_OK &&
           x86_func_inst_count_status[1u] == 0u &&
           x86_func_inst_range_status[0u] == X86_FUNC_INST_RANGE_OK &&
           x86_func_inst_range_status[1u] == 0u;
}

bool valid_count_record(uint node)
{
    if (node >= active_hir_node_count())
        return false;
    uint4 count_record = x86_func_inst_count_record[node];
    return count_record.x == node && count_record.y != 0u && count_record.y != INVALID;
}

bool valid_range_record(uint node)
{
    if (!valid_count_record(node))
        return false;
    uint4 range = x86_func_inst_range_record[node];
    uint4 count = x86_func_inst_count_record[node];
    return range.y == count.y &&
           range.z == count.z &&
           range.w == count.w &&
           range.x != INVALID;
}

void publish_layout_status(bool ok)
{
    x86_func_layout_status[0u] = ok ? X86_FUNC_LAYOUT_OK : 0u;
    x86_func_layout_status[1u] = ok ? 0u :
                                 (x86_func_inst_range_status[1u] != 0u ?
                                  x86_func_inst_range_status[1u] :
                                  x86_func_inst_count_status[1u]);
    x86_func_layout_status[2u] = ok ? INVALID :
                                 (x86_func_inst_range_status[1u] != 0u ?
                                  x86_func_inst_range_status[2u] :
                                  x86_func_inst_count_status[2u]);
    x86_func_layout_status[3u] = ok ? x86_func_inst_range_status[3u] : 0u;
    x86_func_layout_status[4u] = ok ? x86_func_inst_range_status[4u] : INVALID;
    x86_func_layout_status[5u] = ok ? x86_func_inst_range_status[5u] : INVALID;
    x86_func_layout_status[6u] = ok ? x86_func_inst_range_status[6u] : 0u;
    x86_func_layout_status[7u] = ok ? x86_func_inst_range_status[7u] : INVALID;
    x86_func_layout_status[8u] = ok ? x86_func_inst_range_status[8u] : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    bool ok = upstream_ok();
    if (node_i == 0u)
        publish_layout_status(ok);

    if (!ok || node_i >= active_hir_node_count() || !valid_range_record(node_i))
        return;

    x86_func_layout_record[node_i] = x86_func_inst_range_record[node_i];
}
