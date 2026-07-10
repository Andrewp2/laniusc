// Cooperative pointer jumping for small semantic-HIR tables.
//
// A single 256-lane workgroup owns the table, so device-memory barriers can
// separate pointer-jump rounds without one dispatch per round. Larger tables
// retain the scalable multi-workgroup pass recorded by the host.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirContextRelations;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_count;

RWStructuredBuffer<uint> hir_stmt_context_link_a;
RWStructuredBuffer<uint> hir_contextual_stmt_value_a;
RWStructuredBuffer<uint> hir_nearest_stmt_value_a;
RWStructuredBuffer<uint> hir_nearest_block_value_a;
RWStructuredBuffer<uint> hir_nearest_enclosing_control_value_a;
RWStructuredBuffer<uint> hir_nearest_loop_value_a;
RWStructuredBuffer<uint> hir_nearest_fn_value_a;

RWStructuredBuffer<uint> hir_stmt_context_link_b;
RWStructuredBuffer<uint> hir_contextual_stmt_value_b;
RWStructuredBuffer<uint> hir_nearest_stmt_value_b;
RWStructuredBuffer<uint> hir_nearest_block_value_b;
RWStructuredBuffer<uint> hir_nearest_enclosing_control_value_b;
RWStructuredBuffer<uint> hir_nearest_loop_value_b;
RWStructuredBuffer<uint> hir_nearest_fn_value_b;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;

uint active_node_count()
{
    return gHirContextRelations.uses_status_count != 0u
               ? min(gHirContextRelations.n, tree_count_status[5u])
               : gHirContextRelations.n;
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

bool valid_semantic_row(uint row, uint semantic_count)
{
    return row != INVALID && row < semantic_count;
}

void propagate_a_to_b(uint row, uint semantic_count)
{
    uint link = hir_stmt_context_link_a[row];
    uint context_value = hir_contextual_stmt_value_a[row];
    uint nearest_value = hir_nearest_stmt_value_a[row];
    uint nearest_block = hir_nearest_block_value_a[row];
    uint nearest_control = hir_nearest_enclosing_control_value_a[row];
    uint nearest_loop = hir_nearest_loop_value_a[row];
    uint nearest_fn = hir_nearest_fn_value_a[row];
    if (valid_semantic_row(link, semantic_count))
    {
        if (context_value == INVALID)
            context_value = hir_contextual_stmt_value_a[link];
        if (nearest_value == INVALID)
            nearest_value = hir_nearest_stmt_value_a[link];
        if (nearest_block == INVALID)
            nearest_block = hir_nearest_block_value_a[link];
        if (nearest_control == INVALID)
            nearest_control = hir_nearest_enclosing_control_value_a[link];
        if (nearest_loop == INVALID)
            nearest_loop = hir_nearest_loop_value_a[link];
        if (nearest_fn == INVALID)
            nearest_fn = hir_nearest_fn_value_a[link];
        uint parent_link = hir_stmt_context_link_a[link];
        link = valid_semantic_row(parent_link, semantic_count) ? parent_link : INVALID;
    }

    hir_stmt_context_link_b[row] = link;
    hir_contextual_stmt_value_b[row] = context_value;
    hir_nearest_stmt_value_b[row] = nearest_value;
    hir_nearest_block_value_b[row] = nearest_block;
    hir_nearest_enclosing_control_value_b[row] = nearest_control;
    hir_nearest_loop_value_b[row] = nearest_loop;
    hir_nearest_fn_value_b[row] = nearest_fn;
}

void propagate_b_to_a(uint row, uint semantic_count)
{
    uint link = hir_stmt_context_link_b[row];
    uint context_value = hir_contextual_stmt_value_b[row];
    uint nearest_value = hir_nearest_stmt_value_b[row];
    uint nearest_block = hir_nearest_block_value_b[row];
    uint nearest_control = hir_nearest_enclosing_control_value_b[row];
    uint nearest_loop = hir_nearest_loop_value_b[row];
    uint nearest_fn = hir_nearest_fn_value_b[row];
    if (valid_semantic_row(link, semantic_count))
    {
        if (context_value == INVALID)
            context_value = hir_contextual_stmt_value_b[link];
        if (nearest_value == INVALID)
            nearest_value = hir_nearest_stmt_value_b[link];
        if (nearest_block == INVALID)
            nearest_block = hir_nearest_block_value_b[link];
        if (nearest_control == INVALID)
            nearest_control = hir_nearest_enclosing_control_value_b[link];
        if (nearest_loop == INVALID)
            nearest_loop = hir_nearest_loop_value_b[link];
        if (nearest_fn == INVALID)
            nearest_fn = hir_nearest_fn_value_b[link];
        uint parent_link = hir_stmt_context_link_b[link];
        link = valid_semantic_row(parent_link, semantic_count) ? parent_link : INVALID;
    }

    hir_stmt_context_link_a[row] = link;
    hir_contextual_stmt_value_a[row] = context_value;
    hir_nearest_stmt_value_a[row] = nearest_value;
    hir_nearest_block_value_a[row] = nearest_block;
    hir_nearest_enclosing_control_value_a[row] = nearest_control;
    hir_nearest_loop_value_a[row] = nearest_loop;
    hir_nearest_fn_value_a[row] = nearest_fn;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gtid: SV_GroupThreadID)
{
    uint semantic_count = active_semantic_count();
    bool read_a = true;
    for (uint span = 1u; span < gHirContextRelations.n; span <<= 1u)
    {
        for (uint row = gtid.x; row < semantic_count; row += WG_SIZE)
        {
            if (read_a)
                propagate_a_to_b(row, semantic_count);
            else
                propagate_b_to_a(row, semantic_count);
        }
        DeviceMemoryBarrierWithGroupSync();
        read_a = !read_a;
    }

    if (!read_a)
    {
        for (uint row = gtid.x; row < semantic_count; row += WG_SIZE)
        {
            hir_stmt_context_link_a[row] = hir_stmt_context_link_b[row];
            hir_contextual_stmt_value_a[row] = hir_contextual_stmt_value_b[row];
            hir_nearest_stmt_value_a[row] = hir_nearest_stmt_value_b[row];
            hir_nearest_block_value_a[row] = hir_nearest_block_value_b[row];
            hir_nearest_enclosing_control_value_a[row] =
                hir_nearest_enclosing_control_value_b[row];
            hir_nearest_loop_value_a[row] = hir_nearest_loop_value_b[row];
            hir_nearest_fn_value_a[row] = hir_nearest_fn_value_b[row];
        }
    }
}
