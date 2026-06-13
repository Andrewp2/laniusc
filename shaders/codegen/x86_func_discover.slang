import gpu_index;
import atomics;

// Direct x86_64 function discovery.
//
// This pass maps GPU HIR function nodes and owning-function records for the
// native backend. x86_node_tree_info runs before this pass, so the function
// discovery status can still fail fast on invalid parser tree records.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
    uint virtual_next_call_step_count;
    uint regalloc_rows_per_chunk;
    uint regalloc_chunk_count;
    uint function_slot_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> x86_node_tree_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> hir_node_decl_token;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> fn_entrypoint_tag;

RWStructuredBuffer<uint> x86_func_meta;
RWStructuredBuffer<uint> x86_node_func;
RWStructuredBuffer<uint> x86_decl_node_by_token;

static const uint INVALID = 0xffffffffu;
static const uint HIR_FN = 3u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint ENTRYPOINT_MAIN = 1u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_NODE_TREE_OK = 1u;

static const uint FUNC_META_MAIN_COUNT = 1u;
static const uint FUNC_META_MAIN_MAX_NODE = 3u;
static const uint FUNC_META_MAIN_NODE = 4u;

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

bool valid_token(uint token_i)
{
    return token_i != INVALID && token_i < gParams.n_tokens;
}

bool is_main_function_node(uint node_i)
{
    return hir_kind[node_i] == HIR_FN &&
           hir_item_kind[node_i] == HIR_ITEM_KIND_FN &&
           fn_entrypoint_tag[node_i] == ENTRYPOINT_MAIN;
}

bool is_impl_method_function_node(uint node_i)
{
    uint fn_token = valid_node(node_i) ? hir_token_pos[node_i] : INVALID;
    return hir_kind[node_i] == HIR_FN &&
           valid_token(fn_token) &&
           valid_token(method_decl_param_offset[fn_token]);
}

bool is_function_record_node(uint node_i)
{
    return hir_kind[node_i] == HIR_FN &&
           (hir_item_kind[node_i] == HIR_ITEM_KIND_FN ||
            is_impl_method_function_node(node_i));
}

bool node_tree_ok()
{
    return x86_node_tree_status[0u] == X86_NODE_TREE_OK &&
           x86_node_tree_status[1u] == 0u;
}

void publish_function_lookup_key(uint key, uint node_i)
{
    if (key == INVALID || key >= gParams.n_tokens)
        return;

    atomic_u32_min(x86_decl_node_by_token, key, node_i);
}

void publish_function_lookup(uint node_i)
{
    if (!is_function_record_node(node_i))
        return;

    publish_function_lookup_key(hir_token_pos[node_i], node_i);
    publish_function_lookup_key(hir_node_decl_token[node_i], node_i);
    publish_function_lookup_key(hir_item_name_token[node_i], node_i);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (!node_tree_ok())
        return;

    if (node_i >= active_hir_node_count())
        return;

    if (!is_function_record_node(node_i))
        return;

    x86_node_func[node_i] = node_i;
    publish_function_lookup(node_i);

    if (!is_main_function_node(node_i))
        return;

    atomic_u32_add(x86_func_meta, FUNC_META_MAIN_COUNT, 1u);
    atomic_u32_max(x86_func_meta, FUNC_META_MAIN_MAX_NODE, node_i);
    atomic_u32_min(x86_func_meta, FUNC_META_MAIN_NODE, node_i);
}
