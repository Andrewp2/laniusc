// Mirror module-qualified call metadata from the path owner to the callee leaf.
//
// Qualified value paths are keyed by their owner token, while chained method
// calls on a qualified call result use the leaf callee token as the receiver.
// This pass keeps the context-heavy call consumer under the storage-buffer
// limit and restores the small metadata projection needed by method resolution.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_owner_token;

RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint path_leaf_token(uint path_i, uint owner_token)
{
    uint count = path_i < active_path_count() ? path_segment_count[path_i] : 0u;
    if (count <= 1u)
        return owner_token;
    uint leaf_i = path_segment_base[path_i] + count - 1u;
    uint leaf_token = leaf_i < gParams.n_tokens * 4u ? path_segment_token[leaf_i] : INVALID;
    return valid_token(leaf_token) ? leaf_token : owner_token;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count())
        return;

    uint owner_token = path_owner_token[path_i];
    if (!valid_token(owner_token))
        return;

    uint leaf_token = path_leaf_token(path_i, owner_token);
    if (leaf_token == owner_token)
        return;

    uint fn_token = call_fn_index[owner_token];
    if (!valid_token(fn_token))
        return;

    call_fn_index[leaf_token] = fn_token;
    uint ret_ty = call_return_type[owner_token];
    if (ret_ty != TY_UNKNOWN)
        call_return_type[leaf_token] = ret_ty;
}
