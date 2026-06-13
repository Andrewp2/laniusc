// Pointer-jump binary expression left-span links.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirExpr;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_binary_span_link_in;
StructuredBuffer<uint> hir_binary_span_start_in;

RWStructuredBuffer<uint> hir_binary_span_link_out;
RWStructuredBuffer<uint> hir_binary_span_start_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirExpr.uses_ll1 != 0u ? min(gHirExpr.n, ll1_status[5u]) : gHirExpr.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirExpr.n)
        return;

    if (!valid_node(node))
    {
        hir_binary_span_link_out[node] = INVALID;
        hir_binary_span_start_out[node] = INVALID;
        return;
    }

    uint link = hir_binary_span_link_in[node];
    uint start = hir_binary_span_start_in[node];
    if (!valid_node(link) || link == node)
    {
        hir_binary_span_link_out[node] = INVALID;
        hir_binary_span_start_out[node] = start;
        return;
    }

    uint linked_start = hir_binary_span_start_in[link];
    uint linked_link = hir_binary_span_link_in[link];
    hir_binary_span_start_out[node] =
        linked_start != INVALID && (start == INVALID || linked_start < start)
            ? linked_start
            : start;
    hir_binary_span_link_out[node] =
        valid_node(linked_link) && linked_link != node ? linked_link : INVALID;
}
