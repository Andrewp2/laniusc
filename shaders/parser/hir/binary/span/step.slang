// Pointer-jump binary expression left-span links.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirExpr;

StructuredBuffer<uint> hir_semantic_count;
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

uint active_row_count()
{
    return min(gHirExpr.n, hir_semantic_count[0u]);
}

bool valid_row(uint row)
{
    return row != INVALID && row < active_row_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= active_row_count())
        return;

    uint link = hir_binary_span_link_in[row];
    uint start = hir_binary_span_start_in[row];
    if (!valid_row(link) || link == row)
    {
        hir_binary_span_link_out[row] = INVALID;
        hir_binary_span_start_out[row] = start;
        return;
    }

    uint linked_start = hir_binary_span_start_in[link];
    uint linked_link = hir_binary_span_link_in[link];
    hir_binary_span_start_out[row] =
        linked_start != INVALID && (start == INVALID || linked_start < start)
            ? linked_start
            : start;
    hir_binary_span_link_out[row] =
        valid_row(linked_link) && linked_link != row ? linked_link : INVALID;
}
