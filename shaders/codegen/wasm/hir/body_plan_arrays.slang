// Array-specific body length and local accounting for the WASM HIR backend.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> status;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> hir_array_lit_context_stmt_node;
StructuredBuffer<uint> hir_array_element_parent_lit;
StructuredBuffer<uint> hir_array_element_ordinal;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> wasm_func_flag;
StructuredBuffer<uint> wasm_func_slot_by_token;

RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> wasm_func_body_len_by_token;
RWStructuredBuffer<uint> wasm_func_local_max_by_token;
RWStructuredBuffer<uint> wasm_func_invalid_count_by_token;
RWStructuredBuffer<uint> wasm_func_detail_by_token;
RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;

static const uint INVALID = 0xffffffffu;
static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint WASM_MAX_DIRECT_CALL_ARGS = 4u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_EXPR = 14u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_ASSIGN = 5u;
static const uint ASSIGN_OP_SET = 1u;
static const uint ASSIGN_OP_ADD = 2u;
static const uint ASSIGN_OP_SUB = 3u;
static const uint ASSIGN_OP_MUL = 4u;
static const uint ASSIGN_OP_DIV = 5u;
static const uint ASSIGN_OP_MOD = 6u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint HIR_EXPR_NONE = 0u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint HIR_EXPR_INDEX = 26u;
static const uint BODY_FRAGMENT_LET_ARRAY_I32 = 30u;
static const uint BODY_FRAGMENT_ARRAY_STORE_I32 = 31u;
static const uint BODY_FRAGMENT_ASSIGN_EXPR_I32 = 10u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32 = 11u;
static const uint DISPATCH_X_STRIDE = 16776960u;

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

uint stmt_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_FORM) : HIR_EXPR_NONE;
}

uint resolve_expr_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    if (valid_node(root))
        return root;
    return expr_form(node) == HIR_EXPR_FORWARD ? INVALID : node;
}

uint node_enclosing_fn_token(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint token = hir_token_pos[node];
    if (!valid_token(token))
        return INVALID;
    uint encoded_fn = enclosing_fn[token];
    return encoded_fn == 0u ? INVALID : encoded_fn - 1u;
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

uint i32_sleb_len(uint value)
{
    int current = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current = current >> 7;
        bool sign_bit_set = (byte_value & 0x40u) != 0u;
        bool done =
            (current == 0 && !sign_bit_set) ||
            (current == -1 && sign_bit_set) ||
            i == 4u;
        if (done)
            return i + 1u;
    }
    return 5u;
}

uint local_get_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
}

uint local_set_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
}

bool function_non_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;
    uint param_count = call_param_count[fn_token];
    if (param_count > WASM_MAX_DIRECT_CALL_ARGS)
        return false;
    local_index = param_count + decl_token;
    return true;
}

bool local_decl_token_for_name_expr(uint node, out uint local_index)
{
    local_index = INVALID;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token) ||
        body_let_init_expr_by_decl_token[decl_token] == INVALID)
    {
        return false;
    }
    return function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index);
}

bool assign_op_supported(uint op)
{
    return op == ASSIGN_OP_SET ||
           op == ASSIGN_OP_ADD ||
           op == ASSIGN_OP_SUB ||
           op == ASSIGN_OP_MUL ||
           op == ASSIGN_OP_DIV ||
           op == ASSIGN_OP_MOD;
}

uint array_lit_base_address(uint lit_node)
{
    if (!valid_node(lit_node) || !valid_token(hir_token_pos[lit_node]))
        return 0u;
    return hir_token_pos[lit_node] * 4u;
}

bool array_lit_for_decl_token(uint decl_token, out uint lit_node)
{
    lit_node = INVALID;
    if (!valid_token(decl_token))
        return false;

    uint init_expr = resolve_expr_node(body_let_init_expr_by_decl_token[decl_token]);
    if (!valid_node(init_expr) || hir_kind[init_expr] != HIR_ARRAY_EXPR)
        return false;

    uint context = hir_array_lit_context_stmt_node[init_expr];
    if (!valid_node(context) ||
        hir_kind[context] != HIR_LET_STMT ||
        stmt_record_slot(context, 0u) != STMT_RECORD_KIND_LET ||
        stmt_record_slot(context, 1u) != decl_token)
    {
        return false;
    }

    lit_node = init_expr;
    return true;
}

bool array_decl_for_name_expr(uint node, out uint decl_token, out uint local_index)
{
    decl_token = INVALID;
    local_index = INVALID;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    uint lit_node = INVALID;
    if (!array_lit_for_decl_token(decl_token, lit_node))
        return false;

    return function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index);
}

bool expr_atom_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    uint local_index = INVALID;
    if (form == HIR_EXPR_NAME && local_decl_token_for_name_expr(node, local_index))
    {
        len = local_get_len(local_index);
        return true;
    }
    if (form == HIR_EXPR_INT)
    {
        len = 1u + i32_sleb_len(hir_expr_int_value[node]);
        return true;
    }
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
    {
        len = 2u;
        return true;
    }
    return false;
}

bool expr_binary_op_supported(uint form)
{
    return form == HIR_EXPR_EQ ||
           form == HIR_EXPR_NE ||
           form == HIR_EXPR_LT ||
           form == HIR_EXPR_GT ||
           form == HIR_EXPR_LE ||
           form == HIR_EXPR_GE ||
           form == HIR_EXPR_ADD ||
           form == HIR_EXPR_SUB ||
           form == HIR_EXPR_MUL ||
           form == HIR_EXPR_DIV ||
           form == HIR_EXPR_MOD ||
           form == HIR_EXPR_AND ||
           form == HIR_EXPR_OR ||
           form == HIR_EXPR_BIT_OR ||
           form == HIR_EXPR_BIT_XOR ||
           form == HIR_EXPR_BIT_AND ||
           form == HIR_EXPR_SHL ||
           form == HIR_EXPR_SHR;
}

bool expr_simple_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    if (expr_atom_len(node, len))
        return true;

    uint form = expr_form(node);
    if (form == HIR_EXPR_NOT)
    {
        uint inner_len = 0u;
        if (!expr_atom_len(expr_record_slot(node, EXPR_RECORD_LEFT), inner_len))
            return false;
        len = inner_len + 2u;
        return true;
    }
    if (form == HIR_EXPR_NEG)
    {
        uint inner_len = 0u;
        if (!expr_atom_len(expr_record_slot(node, EXPR_RECORD_LEFT), inner_len))
            return false;
        len = 2u + inner_len + 1u;
        return true;
    }
    if (expr_binary_op_supported(form))
    {
        uint left_len = 0u;
        uint right_len = 0u;
        if (!expr_atom_len(expr_record_slot(node, EXPR_RECORD_LEFT), left_len) ||
            !expr_atom_len(expr_record_slot(node, EXPR_RECORD_RIGHT), right_len))
        {
            return false;
        }
        len = left_len + right_len + 1u;
        return true;
    }
    return false;
}

bool index_expr_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_INDEX)
        return false;

    uint decl_token = INVALID;
    uint local_index = INVALID;
    if (!array_decl_for_name_expr(
            expr_record_slot(node, EXPR_RECORD_LEFT),
            decl_token,
            local_index))
    {
        return false;
    }

    uint index_len = 0u;
    if (!expr_atom_len(expr_record_slot(node, EXPR_RECORD_RIGHT), index_len))
        return false;

    len = local_get_len(local_index) + index_len + 7u;
    return true;
}

void publish_func_invalid(uint fn_token, uint detail)
{
    if (!valid_token(fn_token))
        return;
    atomic_u32_add(wasm_func_invalid_count_by_token, fn_token, 1u);
    atomic_u32_min(wasm_func_detail_by_token, fn_token, detail);
    atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, detail);
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

void publish_fragment(uint token_i, uint len, uint4 meta)
{
    uint slot = token_i * 2u;
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = meta;
}

void account_let_array(uint node, uint owner_fn, uint token)
{
    if (hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return;
    }

    uint decl_token = stmt_record_slot(node, 1u);
    uint lit_node = INVALID;
    if (!array_lit_for_decl_token(decl_token, lit_node))
        return;

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, owner_fn, local_index))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint base_address = array_lit_base_address(lit_node);
    uint len = 1u + i32_sleb_len(base_address) + local_set_len(local_index);
    add_func_local_token(owner_fn, decl_token);
    add_func_body_len(owner_fn, len);
    publish_fragment(
        token,
        len,
        uint4(BODY_FRAGMENT_LET_ARRAY_I32, local_index, base_address, token));
}

void account_array_element(uint node, uint owner_fn, uint token)
{
    if (hir_kind[node] == HIR_ARRAY_EXPR)
        return;

    uint lit_node = hir_array_element_parent_lit[node];
    if (!valid_node(lit_node))
        return;
    if (lit_node == node)
        return;
    if (hir_kind[lit_node] != HIR_ARRAY_EXPR ||
        hir_array_element_ordinal[node] == INVALID)
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint context = hir_array_lit_context_stmt_node[lit_node];
    uint expr_len = 0u;
    if (!valid_node(context) ||
        hir_kind[context] != HIR_LET_STMT ||
        stmt_record_slot(context, 0u) != STMT_RECORD_KIND_LET ||
        resolve_expr_node(stmt_record_slot(context, 2u)) != lit_node ||
        !expr_simple_len(node, expr_len))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint address = array_lit_base_address(lit_node) +
                   hir_array_element_ordinal[node] * 4u;
    uint len = 1u + i32_sleb_len(address) + expr_len + 3u;
    add_func_body_len(owner_fn, len);
    publish_fragment(
        token,
        len,
        uint4(BODY_FRAGMENT_ARRAY_STORE_I32, address, node, token));
}

void account_assign_index(uint node, uint owner_fn, uint token)
{
    if (hir_kind[node] != HIR_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_ASSIGN)
    {
        return;
    }

    uint rhs_node = stmt_record_slot(node, 2u);
    rhs_node = resolve_expr_node(rhs_node);
    if (!valid_node(rhs_node) || expr_form(rhs_node) != HIR_EXPR_INDEX)
        return;

    uint target_len = 0u;
    uint rhs_len = 0u;
    uint target = stmt_record_slot(node, 1u);
    uint op = stmt_record_slot(node, 3u);
    if (!assign_op_supported(op) ||
        !local_decl_token_for_name_expr(target, target_len) ||
        !index_expr_len(rhs_node, rhs_len))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint len = op == ASSIGN_OP_SET
                   ? rhs_len + local_set_len(target_len)
                   : local_get_len(target_len) + rhs_len + 1u + local_set_len(target_len);
    add_func_body_len(owner_fn, len);
    publish_fragment(
        token,
        len,
        uint4(
            op == ASSIGN_OP_SET
                ? BODY_FRAGMENT_ASSIGN_EXPR_I32
                : BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32,
            target_len,
            rhs_node,
            op));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE)
        return;
    if (body_plan[BODY_PLAN_MAIN_COUNT] != 1u)
        return;

    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;

    uint token = hir_token_pos[node];
    account_let_array(node, owner_fn, token);
    account_array_element(node, owner_fn, token);
    account_assign_index(node, owner_fn, token);
}
