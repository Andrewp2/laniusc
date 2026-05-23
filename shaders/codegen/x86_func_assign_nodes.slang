// x86_64 owning-function assignment seed.
//
// This pass consumes the backend HIR tree projection plus the HIR-order
// function-owner prefix scan. The scan provides a candidate function owner, and
// the subtree span validates that the node is actually inside that function.
// The parent link then pointer-jumps any remaining unresolved nodes from the
// tree relation. It works from HIR records only; it does not inspect token
// spelling or source text.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> x86_tree_parent;
StructuredBuffer<uint> x86_tree_subtree_end;
StructuredBuffer<uint> x86_node_tree_status;
StructuredBuffer<uint> x86_func_owner_scan_local_prefix;
StructuredBuffer<uint> x86_func_owner_scan_block_prefix;

RWStructuredBuffer<uint> x86_node_func;
RWStructuredBuffer<uint> x86_func_owner_link;

static const uint INVALID = 0xffffffffu;
static const uint HIR_FN = 3u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WG_SIZE = 256u;
static const uint X86_NODE_TREE_OK = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node_i)
{
    return node_i != INVALID && node_i < active_hir_node_count();
}

bool node_tree_ok()
{
    return x86_node_tree_status[0u] == X86_NODE_TREE_OK &&
           x86_node_tree_status[1u] == 0u;
}

bool is_owning_function_node(uint node_i)
{
    if (!valid_node(node_i))
        return false;
    return hir_kind[node_i] == HIR_FN;
}

uint owner_from_hir_order_scan(uint node_i)
{
    if (!valid_node(node_i))
        return INVALID;

    uint block_i = node_i / WG_SIZE;
    uint prior_blocks = block_i == 0u ? 0u : x86_func_owner_scan_block_prefix[block_i - 1u];
    uint encoded_owner = max(x86_func_owner_scan_local_prefix[node_i], prior_blocks);
    return encoded_owner == 0u ? INVALID : encoded_owner - 1u;
}

bool owner_subtree_contains_node(uint owner, uint node_i)
{
    if (!valid_node(owner) || !valid_node(node_i))
        return false;

    uint end = x86_tree_subtree_end[owner];
    return end != INVALID && owner <= node_i && node_i < end;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i >= active_hir_node_count())
    {
        if (node_i < gParams.n_hir_nodes)
        {
            x86_node_func[node_i] = INVALID;
            x86_func_owner_link[node_i] = INVALID;
        }
        return;
    }

    uint parent = node_tree_ok() ? x86_tree_parent[node_i] : INVALID;
    uint scanned_owner = owner_from_hir_order_scan(node_i);
    uint owner = owner_subtree_contains_node(scanned_owner, node_i)
                     ? scanned_owner
                     : INVALID;
    x86_node_func[node_i] = is_owning_function_node(node_i) ? node_i : owner;
    x86_func_owner_link[node_i] = valid_node(parent) ? parent : INVALID;
}
