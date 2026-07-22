import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> fn_start_token_by_decl_token;
RWStructuredBuffer<uint> backend_call_fn_index;
RWStructuredBuffer<uint> call_intrinsic_tag;
RWStructuredBuffer<uint> fn_entrypoint_tag;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> call_param_count;
RWStructuredBuffer<uint> call_param_type;
RWStructuredBuffer<uint> call_param_ref_tag;
RWStructuredBuffer<uint> call_param_ref_payload;
RWStructuredBuffer<uint> call_param_row_start;
RWStructuredBuffer<uint> call_param_row_count;
RWStructuredBuffer<uint> call_generic_slot_type;
RWStructuredBuffer<uint> call_generic_slot_ordinal;
RWStructuredBuffer<uint> call_const_slot_len;
RWStructuredBuffer<uint> call_has_array_arg;
RWStructuredBuffer<uint> call_result_instance;
RWStructuredBuffer<uint> function_lookup_key;
RWStructuredBuffer<uint> function_lookup_fn;

static const uint INVALID = 0xffffffffu;

static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TYPE_REF_INVALID = 0u;
static const uint PARAM_CACHE_STRIDE = 4u;

static const uint TK_IDENT = 1u;
static const uint TK_LBRACKET = 20u;
static const uint TK_LBRACE = 22u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_ARROW = 75u;
static const uint TK_FN = 67u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_IF_LBRACE = 88u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint lookup_capacity()
{
    return max(gParams.n_tokens * 2u, 1u);
}

void clear_call_param_slot(uint token_i, uint param_i)
{
    row_major_store<uint>(
        call_param_type,
        token_i,
        PARAM_CACHE_STRIDE,
        param_i,
        TY_UNKNOWN);
    row_major_store<uint>(
        call_param_ref_tag,
        token_i,
        PARAM_CACHE_STRIDE,
        param_i,
        TYPE_REF_INVALID);
    row_major_store<uint>(
        call_param_ref_payload,
        token_i,
        PARAM_CACHE_STRIDE,
        param_i,
        INVALID);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i < gParams.n_tokens)
    {
        call_fn_index[i] = INVALID;
        fn_start_token_by_decl_token[i] = INVALID;
        backend_call_fn_index[i] = INVALID;
        call_intrinsic_tag[i] = 0u;
        call_return_type[i] = TY_UNKNOWN;
        call_return_type_token[i] = INVALID;
        call_param_count[i] = 0u;
        call_param_row_start[i] = INVALID;
        call_param_row_count[i] = 0u;
        clear_call_param_slot(i, 0u);
        clear_call_param_slot(i, 1u);
        clear_call_param_slot(i, 2u);
        clear_call_param_slot(i, 3u);
    }

    if (i < gParams.n_hir_nodes)
    {
        fn_entrypoint_tag[i] = 0u;
        call_has_array_arg[i] = 0u;
        call_result_instance[i] = INVALID;
    }

    if (i < gParams.n_tokens * PARAM_CACHE_STRIDE)
    {
        call_generic_slot_type[i] = INVALID;
        call_generic_slot_ordinal[i] = INVALID;
        call_const_slot_len[i] = INVALID;
    }

    if (i < lookup_capacity())
    {
        function_lookup_key[i] = INVALID;
        function_lookup_fn[i] = INVALID;
    }
}
