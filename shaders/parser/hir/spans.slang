// Compute token spans for HIR-facing parse nodes.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
    uint token_capacity;
};

ConstantBuffer<Params> gHir;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_file_id;
StructuredBuffer<uint> source_file_token_end;
StructuredBuffer<uint> hir_type_path_leaf_node;

RWStructuredBuffer<uint> hir_token_end;

static const uint INVALID = 0xFFFFFFFFu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_FILE = 1u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHir.uses_status_count != 0u ? min(gHir.n, tree_count_status[5u]) : gHir.n;
}

uint clamped_end_after_token(uint token_pos)
{
    uint n_tokens = token_count[0];
    return token_pos >= n_tokens ? n_tokens : token_pos + 1u;
}

bool valid_node(uint node, uint n)
{
    return node != INVALID && node < n;
}

uint path_leaf_end(uint path_node, uint n)
{
    uint leaf = valid_node(path_node, n) ? hir_type_path_leaf_node[path_node] : INVALID;
    uint leaf_candidate = leaf < n ? hir_token_pos[leaf] : INVALID;
    uint leaf_pos = leaf_candidate == INVALID ? hir_token_pos[path_node] : leaf_candidate;
    return clamped_end_after_token(leaf_pos);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n = active_node_count();
    if (i >= n)
        return;

    uint start = hir_token_pos[i];
    if (start == INVALID)
    {
        hir_token_end[i] = INVALID;
        return;
    }

    if (hir_kind[i] == HIR_FILE)
    {
        uint file_id = hir_token_file_id[i];
        if (file_id != INVALID && file_id < gHir.token_capacity)
        {
            uint file_end = source_file_token_end[file_id];
            if (file_end > start)
            {
                hir_token_end[i] = file_end;
                return;
            }
        }
    }

    if (hir_kind[i] == HIR_PATH_EXPR)
    {
        hir_token_end[i] = path_leaf_end(i, n);
        return;
    }

    if (hir_kind[i] == HIR_NAME_EXPR)
    {
        if (node_kind[i] == PROD_PATTERN_IDENT)
        {
            uint end_node = min(subtree_end[i], n);
            uint max_pos = start;
            if (end_node > i + 1u)
            {
                uint last_pos = hir_token_pos[end_node - 1u];
                if (last_pos != INVALID)
                    max_pos = last_pos;
            }
            hir_token_end[i] = clamped_end_after_token(max_pos);
            return;
        }

        uint child = first_child[i];
        if (valid_node(child, n) && hir_kind[child] == HIR_PATH_EXPR)
        {
            hir_token_end[i] = path_leaf_end(child, n);
            return;
        }
        hir_token_end[i] = clamped_end_after_token(start);
        return;
    }

    uint end_node = min(subtree_end[i], n);
    uint max_pos = start;
    if (end_node > i + 1u)
    {
        uint last_pos = hir_token_pos[end_node - 1u];
        if (last_pos != INVALID)
            max_pos = last_pos;
    }

    hir_token_end[i] = clamped_end_after_token(max_pos);
}
