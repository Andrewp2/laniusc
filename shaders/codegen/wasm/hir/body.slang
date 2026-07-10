// Publish function wrapper fragments after per-function body sizes are known.

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
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> wasm_func_flag;
StructuredBuffer<uint> wasm_func_slot_by_token;
StructuredBuffer<uint> wasm_func_body_len_by_token;
StructuredBuffer<uint> wasm_func_local_max_by_token;
StructuredBuffer<uint> call_return_type;

RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;
RWStructuredBuffer<uint4> body_fragment_aux;

static const uint INVALID = 0xffffffffu;
static const uint HIR_FN = 3u;
static const uint HIR_BLOCK = 6u;
static const uint BODY_FRAGMENT_FUNCTION_HEADER = 22u;
static const uint BODY_FRAGMENT_FUNCTION_END = 28u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint TY_VOID = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool supported_function_token(uint fn_token)
{
    return valid_token(fn_token) &&
           wasm_func_flag[fn_token] != 0u &&
           wasm_func_slot_by_token[fn_token] != INVALID;
}

uint u32_leb_len(uint value)
{
    for (uint i = 0u; i < 5u; i += 1u)
    {
        value = value >> 7u;
        if (value == 0u)
            return i + 1u;
    }
    return 5u;
}

uint local_decl_fragment_len_from_count(uint local_count)
{
    if (local_count == 0u)
        return 1u;
    uint i32_count = local_count * 2u;
    return 1u + u32_leb_len(i32_count) + 1u + u32_leb_len(local_count) + 1u;
}

uint local_decl_count_for_function_token(uint fn_token)
{
    if (!valid_token(fn_token))
        return 0u;
    uint local_max = wasm_func_local_max_by_token[fn_token];
    return local_max == INVALID ? 0u : local_max + 1u;
}

bool function_end_token(uint fn_node, out uint end_token)
{
    end_token = INVALID;
    uint fn_end = hir_token_end[fn_node];
    if (fn_end != 0u && fn_end != INVALID)
    {
        end_token = fn_end - 1u;
        return valid_token(end_token);
    }

    uint child = first_child[fn_node];
    if (!valid_node(child) || hir_kind[child] != HIR_BLOCK)
        return false;

    uint child_end = hir_token_end[child];
    if (child_end == 0u || child_end == INVALID)
        return false;
    end_token = child_end - 1u;
    return valid_token(end_token);
}

void publish_fragment_slot(uint slot, uint len, uint4 meta)
{
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = meta;
    body_fragment_aux[slot] = uint4(INVALID, 0u, 0u, 0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node) || hir_kind[node] != HIR_FN)
        return;

    uint fn_token = hir_token_pos[node];
    if (!supported_function_token(fn_token))
        return;

    uint local_count = local_decl_count_for_function_token(fn_token);
    uint body_size = wasm_func_body_len_by_token[fn_token];
    uint header_len = 5u + local_decl_fragment_len_from_count(local_count);
    publish_fragment_slot(
        fn_token * 2u,
        header_len,
        uint4(BODY_FRAGMENT_FUNCTION_HEADER, body_size, local_count, fn_token));

    uint end_token = INVALID;
    if (!function_end_token(node, end_token))
        return;

    publish_fragment_slot(
        end_token * 2u + 1u,
        call_return_type[fn_token] == TY_VOID ? 1u : 2u,
        uint4(BODY_FRAGMENT_FUNCTION_END, 0u, 0u, end_token));
}
