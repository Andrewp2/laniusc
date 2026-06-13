// Pointer-jump parser-owned context relations over semantic-HIR rows.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirContextRelations;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_stmt_context_link_in;
StructuredBuffer<uint> hir_contextual_stmt_value_in;
StructuredBuffer<uint> hir_nearest_stmt_value_in;
StructuredBuffer<uint> hir_nearest_block_value_in;
StructuredBuffer<uint> hir_nearest_enclosing_control_value_in;
StructuredBuffer<uint> hir_nearest_loop_value_in;
StructuredBuffer<uint> hir_nearest_fn_value_in;

RWStructuredBuffer<uint> hir_stmt_context_link_out;
RWStructuredBuffer<uint> hir_contextual_stmt_value_out;
RWStructuredBuffer<uint> hir_nearest_stmt_value_out;
RWStructuredBuffer<uint> hir_nearest_block_value_out;
RWStructuredBuffer<uint> hir_nearest_enclosing_control_value_out;
RWStructuredBuffer<uint> hir_nearest_loop_value_out;
RWStructuredBuffer<uint> hir_nearest_fn_value_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint semantic_count = active_semantic_count();
    if (row >= semantic_count)
        return;

    uint link = hir_stmt_context_link_in[row];
    uint context_value = hir_contextual_stmt_value_in[row];
    uint nearest_value = hir_nearest_stmt_value_in[row];
    uint nearest_block = hir_nearest_block_value_in[row];
    uint nearest_enclosing_control = hir_nearest_enclosing_control_value_in[row];
    uint nearest_loop = hir_nearest_loop_value_in[row];
    uint nearest_fn = hir_nearest_fn_value_in[row];
    if (valid_semantic_row(link, semantic_count))
    {
        if (context_value == INVALID)
        {
            uint parent_value = hir_contextual_stmt_value_in[link];
            if (parent_value != INVALID)
                context_value = parent_value;
        }

        if (nearest_value == INVALID)
        {
            uint parent_value = hir_nearest_stmt_value_in[link];
            if (parent_value != INVALID)
                nearest_value = parent_value;
        }

        if (nearest_block == INVALID)
        {
            uint parent_value = hir_nearest_block_value_in[link];
            if (parent_value != INVALID)
                nearest_block = parent_value;
        }

        if (nearest_enclosing_control == INVALID)
        {
            uint parent_value = hir_nearest_enclosing_control_value_in[link];
            if (parent_value != INVALID)
                nearest_enclosing_control = parent_value;
        }

        if (nearest_fn == INVALID)
        {
            uint parent_value = hir_nearest_fn_value_in[link];
            if (parent_value != INVALID)
                nearest_fn = parent_value;
        }

        if (nearest_loop == INVALID)
        {
            uint parent_value = hir_nearest_loop_value_in[link];
            if (parent_value != INVALID)
                nearest_loop = parent_value;
        }

        uint parent_link = hir_stmt_context_link_in[link];
        link = valid_semantic_row(parent_link, semantic_count) ? parent_link : INVALID;
    }

    hir_stmt_context_link_out[row] = link;
    hir_contextual_stmt_value_out[row] = context_value;
    hir_nearest_stmt_value_out[row] = nearest_value;
    hir_nearest_block_value_out[row] = nearest_block;
    hir_nearest_enclosing_control_value_out[row] = nearest_enclosing_control;
    hir_nearest_loop_value_out[row] = nearest_loop;
    hir_nearest_fn_value_out[row] = nearest_fn;
}
