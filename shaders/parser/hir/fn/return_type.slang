// Publish each function or impl-method parser-owned return type node.
//
// Only canonical type rows can contribute an output. Starting from those rows,
// walk grammar forwarding parents until reaching either the return-type wrapper
// or another canonical type. The latter means this is a nested type rather than
// the return root. Once the return wrapper is found, the remaining path to the
// function declaration is fixed signature grammar, independent of user type
// nesting. This avoids propagating owner columns through every raw parse row.

import generated_parse_production_ids;
struct Params
{
    uint n;
    uint uses_status_count;
    uint semantic_parent_local_ancestor_span;
    uint retain_debug_rows;
};

ConstantBuffer<Params> gHirFnReturnType;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> raw_to_hir;

RWStructuredBuffer<uint> hir_fn_return_type_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_FN = 3u;
static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_NONE = 0u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirFnReturnType.uses_status_count != 0u
               ? min(gHirFnReturnType.n, tree_count_status[5u])
               : gHirFnReturnType.n;
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

bool valid_original_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

bool valid_semantic_row(uint row)
{
    return row != INVALID && row < active_semantic_count();
}

bool function_decl_node(uint node)
{
    if (!valid_original_node(node) || hir_kind[node] != HIR_FN)
        return false;
    uint production = node_kind[node];
    return production == PROD_FN || production == PROD_EXTERN_FN ||
           production == PROD_IMPL_FN || production == PROD_TRAIT_METHOD ||
           production == PROD_TRAIT_METHOD_PUB;
}

uint next_parent(uint node)
{
    uint next = valid_original_node(node) ? parent[node] : INVALID;
    return next != node && valid_original_node(next) ? next : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (!valid_semantic_row(row))
        return;

    uint node = hir_semantic_dense_node[row];
    if (!valid_original_node(node) || hir_kind[node] != HIR_TYPE ||
        hir_type_form[node] == HIR_TYPE_FORM_NONE)
        return;

    uint cursor = next_parent(node);
    bool inside_return_type = false;
    while (valid_original_node(cursor))
    {
        if (node_kind[cursor] == PROD_RET_TYPE)
        {
            inside_return_type = true;
            cursor = next_parent(cursor);
            break;
        }
        // A different canonical type between this row and the return wrapper
        // owns this nested type. Only that outer type may become the function's
        // published return root.
        if (hir_kind[cursor] == HIR_TYPE && raw_to_hir[cursor] != INVALID)
            return;
        if (function_decl_node(cursor))
            return;
        cursor = next_parent(cursor);
    }
    if (!inside_return_type)
        return;

    while (valid_original_node(cursor) && !function_decl_node(cursor))
        cursor = next_parent(cursor);
    uint function_owner = cursor;
    if (!function_decl_node(function_owner)) return;

    uint output_row = gHirFnReturnType.retain_debug_rows != 0u
        ? function_owner
        : raw_to_hir[function_owner];
    if (output_row != INVALID)
        InterlockedMin(hir_fn_return_type_node[output_row], node);
}
