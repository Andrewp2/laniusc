import atomics;
import body_common;

StructuredBuffer<uint> status;
RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;
RWStructuredBuffer<uint4> body_fragment_aux;

static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_MAIN_TOKEN_MIN = 9u;
static const uint BODY_PLAN_STMT_INVALID_COUNT = 11u;
static const uint BODY_PLAN_RETURN_COUNT = 12u;
static const uint BODY_PLAN_RETURN_TOKEN_MIN = 13u;
static const uint BODY_PLAN_LET_COUNT = 14u;
static const uint BODY_PLAN_LET_MAX_TOKEN = 15u;
static const uint BODY_PLAN_CALL_INVALID_COUNT = 16u;
static const uint BODY_PLAN_PRINT_COUNT_AGG = 17u;
static const uint BODY_PLAN_PRINT_LEN_AGG = 18u;
static const uint BODY_PLAN_PRINT_MAX_TOKEN = 19u;
static const uint BODY_PLAN_RETURN_VALUE_OK_COUNT = 20u;
static const uint BODY_PLAN_RETURN_VALUE_AGG = 21u;
static const uint BODY_PLAN_RETURN_VALUE_INVALID_COUNT = 22u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint BODY_PLAN_ASSIGN_COUNT = 24u;
static const uint BODY_PLAN_ASSIGN_MAX_TOKEN = 25u;
static const uint BODY_PLAN_ASSIGN_LEN_AGG = 26u;
static const uint BODY_PLAN_LET_LEN_AGG = 27u;
static const uint BODY_PLAN_RETURN_LEN_AGG = 28u;
static const uint BODY_PLAN_LOCAL_CONST_EXPR_COUNT = 29u;
static const uint BODY_PLAN_CONTROL_LEN_AGG = 30u;
static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint HIR_EXPR_INDEX = 26u;

static const uint BODY_FEATURE_EXPR_CONTROL = 1u << 0u;
static const uint BODY_FEATURE_DIRECT = 1u << 1u;
static const uint BODY_FEATURE_HOST = 1u << 2u;
static const uint BODY_FEATURE_ARRAYS = 1u << 3u;
static const uint BODY_FEATURE_MEMBER_EXPR = 1u << 4u;
static const uint BODY_FEATURE_BINARY_DIRECT = 1u << 5u;
static const uint BODY_FEATURE_LET_DIRECT = 1u << 6u;
static const uint BODY_FEATURE_RETURN_NESTED_DIRECT = 1u << 7u;
static const uint BODY_FEATURE_RETURN_DIRECT = 1u << 8u;
static const uint BODY_FEATURE_LET_AGG_DIRECT = 1u << 9u;
static const uint BODY_FEATURE_RETURN_AGG_DIRECT = 1u << 10u;
static const uint BODY_FEATURE_AGG_COPY = 1u << 11u;
static const uint BODY_FEATURE_ARRAY_ALLOC = 1u << 12u;
static const uint BODY_FRAGMENT_LET_ARRAY_I32 = 30u;
static const uint BODY_FRAGMENT_ARRAY_STORE_I32 = 31u;
static const uint BODY_FRAGMENT_AGG_FIELD_STORE_I32 = 40u;
static const uint BODY_FRAGMENT_AGG_DIRECT_COPY_I32 = 43u;
static const uint BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32 = 44u;
static const uint BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32 = 45u;

uint body_fragment_feature_mask(uint kind)
{
    if (kind == BODY_FRAGMENT_LET_EXPR_I32 ||
        kind == BODY_FRAGMENT_ASSIGN_EXPR_I32 ||
        kind == BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32 ||
        kind == BODY_FRAGMENT_PRINT_EXPR_I64 ||
        kind == BODY_FRAGMENT_RETURN_EXPR_I32 ||
        kind == BODY_FRAGMENT_WHILE_OPEN_I32 ||
        kind == BODY_FRAGMENT_IF_OPEN_I32 ||
        kind == BODY_FRAGMENT_WHILE_OPEN_LOCAL_I32 ||
        kind == BODY_FRAGMENT_IF_OPEN_LOCAL_I32 ||
        kind == BODY_FRAGMENT_FOR_OPEN_RANGE_I32 ||
        kind == BODY_FRAGMENT_FOR_CLOSE_RANGE_I32)
        return BODY_FEATURE_EXPR_CONTROL;
    if (kind == BODY_FRAGMENT_LET_DIRECT_CALL_I32)
        return BODY_FEATURE_LET_DIRECT;
    if (kind == BODY_FRAGMENT_RETURN_DIRECT_CALL_I32)
        return BODY_FEATURE_RETURN_DIRECT;
    if (kind == BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 ||
        kind == BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32 ||
        kind == BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32)
        return BODY_FEATURE_DIRECT;
    if (kind == BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 ||
        kind == BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32)
        return BODY_FEATURE_BINARY_DIRECT;
    if (kind == BODY_FRAGMENT_LET_HOST_STDOUT_WRITE_I32 ||
        kind == BODY_FRAGMENT_LET_HOST_NO_ARG_I32 ||
        kind == BODY_FRAGMENT_LET_PROCESS_ARG_LEN_I32 ||
        kind == BODY_FRAGMENT_LET_PROCESS_ARG_READ_I32 ||
        kind == BODY_FRAGMENT_LET_HOST_CALL_I32 ||
        kind == BODY_FRAGMENT_HOST_CALL_VOID ||
        kind == BODY_FRAGMENT_LET_HOST_STR_CALL_I32)
        return BODY_FEATURE_HOST;
    if (kind == BODY_FRAGMENT_LET_I32_ARRAY_DATA_PTR ||
        kind == BODY_FRAGMENT_ARRAY_STORE_I32)
        return BODY_FEATURE_ARRAYS | BODY_FEATURE_MEMBER_EXPR;
    if (kind == BODY_FRAGMENT_LET_ARRAY_I32)
        return BODY_FEATURE_ARRAY_ALLOC;
    if (kind == BODY_FRAGMENT_AGG_FIELD_STORE_I32)
        return BODY_FEATURE_MEMBER_EXPR;
    if (kind == BODY_FRAGMENT_AGG_DIRECT_COPY_I32)
        return BODY_FEATURE_AGG_COPY;
    if (kind == BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32)
        return BODY_FEATURE_LET_AGG_DIRECT;
    if (kind == BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32)
        return BODY_FEATURE_RETURN_AGG_DIRECT;
    return 0u;
}

void publish_fragment_features(uint kind)
{
    uint mask = body_fragment_feature_mask(kind);
    if (mask != 0u)
        atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, mask);
}

void publish_fragment(uint token_i, uint len, uint4 meta, uint4 aux)
{
    uint slot = token_i * 2u;
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = meta;
    body_fragment_aux[slot] = aux;
    publish_fragment_features(meta.x);
}

void publish_fragment_slot(uint slot, uint len, uint4 meta, uint4 aux)
{
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = meta;
    body_fragment_aux[slot] = aux;
    publish_fragment_features(meta.x);
}

uint4 direct_call_aux(uint call_node)
{
    uint fn_token = INVALID;
    uint wasm_func_index = INVALID;
    uint arg_count = 0u;
    call_node = resolve_expr_node(call_node);
    if (!direct_user_call_node(call_node, fn_token, wasm_func_index, arg_count))
        return uint4(INVALID, 0u, 0u, 0u);
    return uint4(wasm_func_index, arg_count, fn_token, 0u);
}

void publish_detail(uint detail)
{
    atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, detail);
}

void publish_stmt_invalid(uint detail)
{
    atomic_u32_add(body_plan, BODY_PLAN_STMT_INVALID_COUNT, 1u);
    publish_detail(detail);
}

void publish_call_invalid(uint detail)
{
    atomic_u32_add(body_plan, BODY_PLAN_CALL_INVALID_COUNT, 1u);
    publish_detail(detail);
}

void publish_return_value(uint value)
{
    uint old_value = 0u;
    InterlockedExchange(body_plan[BODY_PLAN_RETURN_VALUE_AGG], value, old_value);
    atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
}

void publish_func_invalid(uint fn_token, uint detail)
{
    if (!valid_token(fn_token))
    {
        publish_stmt_invalid(detail);
        return;
    }
    atomic_u32_add(wasm_func_invalid_count_by_token, fn_token, 1u);
    atomic_u32_min(wasm_func_detail_by_token, fn_token, detail);
}

void add_func_body_len(uint fn_token, uint len)
{
    if (valid_token(fn_token))
        atomic_u32_add(wasm_func_body_len_by_token, fn_token, len);
}

void add_func_local_token(uint fn_token, uint decl_token)
{
    if (valid_token(fn_token) && valid_token(decl_token))
    {
        uint prior = atomic_u32_compare_exchange(
            wasm_func_local_max_by_token,
            fn_token,
            INVALID,
            decl_token);
        if (prior != INVALID)
            atomic_u32_max(wasm_func_local_max_by_token, fn_token, decl_token);
    }
}
