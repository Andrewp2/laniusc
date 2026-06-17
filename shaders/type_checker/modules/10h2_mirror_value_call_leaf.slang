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
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> call_generic_slot_type;
RWStructuredBuffer<uint> call_generic_slot_ordinal;

static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint MAX_PATH_SEGMENTS = 9u;
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
    uint leaf_token = leaf_i < gParams.n_tokens * MAX_PATH_SEGMENTS
        ? path_segment_token[leaf_i]
        : INVALID;
    return valid_token(leaf_token) ? leaf_token : owner_token;
}

bool concrete_return_type(uint ty)
{
    return ty != TY_UNKNOWN && ty < TY_GENERIC_BASE;
}

void mirror_call_fn_index(uint owner_token, uint leaf_token)
{
    uint owner_fn = call_fn_index[owner_token];
    uint leaf_fn = call_fn_index[leaf_token];
    if (valid_token(owner_fn))
        call_fn_index[leaf_token] = owner_fn;
    else if (valid_token(leaf_fn))
        call_fn_index[owner_token] = leaf_fn;
}

void mirror_call_return_type(uint owner_token, uint leaf_token)
{
    uint owner_ret_ty = call_return_type[owner_token];
    uint leaf_ret_ty = call_return_type[leaf_token];
    if (concrete_return_type(owner_ret_ty))
    {
        call_return_type[leaf_token] = owner_ret_ty;
    }
    else if (concrete_return_type(leaf_ret_ty))
    {
        call_return_type[owner_token] = leaf_ret_ty;
    }
    else if (owner_ret_ty != TY_UNKNOWN)
    {
        call_return_type[leaf_token] = owner_ret_ty;
    }
    else if (leaf_ret_ty != TY_UNKNOWN)
    {
        call_return_type[owner_token] = leaf_ret_ty;
    }
}

void mirror_call_return_type_token(uint owner_token, uint leaf_token)
{
    uint owner_ret_token = call_return_type_token[owner_token];
    uint leaf_ret_token = call_return_type_token[leaf_token];
    if (valid_token(owner_ret_token))
        call_return_type_token[leaf_token] = owner_ret_token;
    else if (valid_token(leaf_ret_token))
        call_return_type_token[owner_token] = leaf_ret_token;
}

void mirror_generic_slot(uint owner_token, uint leaf_token, uint slot)
{
    uint owner_i = owner_token * PARAM_CACHE_STRIDE + slot;
    uint leaf_i = leaf_token * PARAM_CACHE_STRIDE + slot;
    uint owner_ty = call_generic_slot_type[owner_i];
    uint leaf_ty = call_generic_slot_type[leaf_i];
    uint owner_ordinal = call_generic_slot_ordinal[owner_i];
    uint leaf_ordinal = call_generic_slot_ordinal[leaf_i];

    if (owner_ty != INVALID)
    {
        call_generic_slot_type[leaf_i] = owner_ty;
        call_generic_slot_ordinal[leaf_i] = owner_ordinal;
    }
    else if (leaf_ty != INVALID)
    {
        call_generic_slot_type[owner_i] = leaf_ty;
        call_generic_slot_ordinal[owner_i] = leaf_ordinal;
    }
    else if (owner_ordinal != INVALID)
    {
        call_generic_slot_ordinal[leaf_i] = owner_ordinal;
    }
    else if (leaf_ordinal != INVALID)
    {
        call_generic_slot_ordinal[owner_i] = leaf_ordinal;
    }
}

void mirror_generic_slots(uint owner_token, uint leaf_token)
{
    mirror_generic_slot(owner_token, leaf_token, 0u);
    mirror_generic_slot(owner_token, leaf_token, 1u);
    mirror_generic_slot(owner_token, leaf_token, 2u);
    mirror_generic_slot(owner_token, leaf_token, 3u);
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

    mirror_call_fn_index(owner_token, leaf_token);
    mirror_call_return_type(owner_token, leaf_token);
    mirror_call_return_type_token(owner_token, leaf_token);
    mirror_generic_slots(owner_token, leaf_token);
}
