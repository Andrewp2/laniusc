import gpu_index;
import atomics;

// Direct x86_64 function discovery.
//
// This pass maps GPU HIR function lookup keys and discovers the entrypoint for
// the native backend. x86_node_tree_info runs before this pass, so function
// discovery can still fail fast on invalid parser tree records.

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
StructuredBuffer<uint> x86_node_tree_status;
StructuredBuffer<uint> hir_token_pos;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> hir_node_decl_token;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> method_decl_name_token;
StructuredBuffer<uint> fn_entrypoint_tag;
StructuredBuffer<uint> hir_nearest_fn_node;

RWStructuredBuffer<uint> x86_func_meta;
RWStructuredBuffer<uint> x86_node_func;
RWStructuredBuffer<uint> x86_decl_node_by_token;

static const uint INVALID = 0xffffffffu;
static const uint HIR_FN = 3u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
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

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

uint compact_function_for_raw(uint node_i)
{
    if (!valid_node(node_i))
        return INVALID;
    uint dense = raw_to_compact_hir[node_i];
    return dense < active_compact_hir_count() &&
           compact_hir_core[dense].kind == HIR_FN
               ? dense
               : INVALID;
}

uint canonical_function_token(uint node_i)
{
    uint dense = compact_function_for_raw(node_i);
    if (dense == INVALID)
        return INVALID;
    uint token = compact_hir_payload[dense].b;
    return valid_token(token) ? token : INVALID;
}

uint canonical_function_item_kind(uint node_i)
{
    uint dense = compact_function_for_raw(node_i);
    return dense == INVALID ? 0u : compact_hir_payload[dense].a;
}

bool is_main_function_node(uint node_i)
{
    uint fn_token = canonical_function_token(node_i);
    return hir_kind[node_i] == HIR_FN &&
           canonical_function_item_kind(node_i) == HIR_ITEM_KIND_FN &&
           valid_token(fn_token) &&
           fn_entrypoint_tag[fn_token] == ENTRYPOINT_MAIN;
}

bool is_impl_method_function_node(uint node_i)
{
    uint fn_token = canonical_function_token(node_i);
    return hir_kind[node_i] == HIR_FN &&
           valid_token(fn_token) &&
           valid_token(method_decl_param_offset[fn_token]);
}

bool is_function_record_node(uint node_i)
{
    return valid_node(node_i) &&
           hir_kind[node_i] == HIR_FN &&
           (canonical_function_item_kind(node_i) == HIR_ITEM_KIND_FN ||
            is_impl_method_function_node(node_i));
}

bool is_function_lookup_node(uint node_i)
{
    return hir_kind[node_i] == HIR_FN &&
           (canonical_function_item_kind(node_i) == HIR_ITEM_KIND_FN ||
            canonical_function_item_kind(node_i) == HIR_ITEM_KIND_EXTERN_FN ||
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
    if (!is_function_lookup_node(node_i))
        return;

    uint dense = compact_function_for_raw(node_i);
    if (dense == INVALID)
        return;

    // Function lookup is a compact-HIR projection. Raw declaration/context
    // columns can be repeated on grammar wrappers and are not stable semantic
    // keys; publishing them here made unrelated functions alias at scale.
    uint fn_token = compact_hir_payload[dense].b;
    publish_function_lookup_key(compact_hir_core[dense].token_start, node_i);
    publish_function_lookup_key(fn_token, node_i);
    publish_function_lookup_key(
        valid_token(fn_token) ? method_decl_name_token[fn_token] : INVALID,
        node_i);
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

    uint owner = hir_nearest_fn_node[node_i];
    x86_node_func[node_i] = is_function_record_node(owner) ? owner : INVALID;

    if (!is_function_lookup_node(node_i))
        return;

    publish_function_lookup(node_i);
    if (!is_main_function_node(node_i))
        return;

    atomic_u32_add(x86_func_meta, FUNC_META_MAIN_COUNT, 1u);
    atomic_u32_max(x86_func_meta, FUNC_META_MAIN_MAX_NODE, node_i);
    atomic_u32_min(x86_func_meta, FUNC_META_MAIN_NODE, node_i);
}
