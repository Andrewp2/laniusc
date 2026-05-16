// GPU HIR-qualified value call consumer.
//
// This pass consumes resolver rows, HIR call records, and function return
// metadata. It does not inspect token kinds or source bytes to decide whether
// a resolved declaration is callable.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_token_start;
StructuredBuffer<uint4> call_arg_record;
StructuredBuffer<uint> module_value_path_call_open;

RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED_DECL = 6u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint PARAM_CACHE_STRIDE = 16u;

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

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

bool is_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE;
}

uint call_node_for_callee_token(uint callee_i)
{
    if (!valid_token(callee_i))
        return INVALID;
    return call_arg_record[callee_i * PARAM_CACHE_STRIDE].z;
}

bool valid_function_decl(uint decl_i, out uint fn_token)
{
    fn_token = INVALID;
    if (decl_i >= gParams.n_hir_nodes)
        return false;

    uint token_i = decl_token_start[decl_i];
    if (!valid_token(token_i) || call_fn_index[token_i] != token_i)
        return false;

    fn_token = token_i;
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count())
        return;

    uint owner_token = path_owner_token[path_i];
    if (!valid_token(owner_token) || module_value_path_call_open[owner_token] == INVALID)
        return;

    if (!valid_node(call_node_for_callee_token(owner_token)))
        return;
    if (resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return;

    uint fn_token;
    if (!valid_function_decl(resolved_value_decl[path_i], fn_token))
        return;

    uint ret_ty = call_return_type[owner_token];
    if (ret_ty == TY_UNKNOWN)
    {
        uint decl_ret_ty = call_return_type[fn_token];
        if (!is_generic_type(decl_ret_ty))
            ret_ty = decl_ret_ty;
    }

    call_fn_index[owner_token] = fn_token;
    if (ret_ty != TY_UNKNOWN)
        call_return_type[owner_token] = ret_ty;
    module_value_path_status[owner_token] = INVALID;
}
