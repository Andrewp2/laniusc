// Parallel validation and planning for simple scalar statement fragments:
// statement-position print calls and if statements with scalar conditions.

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
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint2> wasm_const_value_record;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_expr_float_bits;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_context_stmt_node;
StructuredBuffer<uint> hir_call_arg_start;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_call_arg_ordinal;
StructuredBuffer<uint> hir_nearest_enclosing_control_node;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> method_decl_receiver_mode;

RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;
RWStructuredBuffer<uint4> body_fragment_aux;
RWStructuredBuffer<uint> wasm_func_flag;
RWStructuredBuffer<uint> wasm_func_slot_by_token;
RWStructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;
RWStructuredBuffer<uint> wasm_func_body_len_by_token;
RWStructuredBuffer<uint> wasm_func_local_max_by_token;
RWStructuredBuffer<uint> wasm_func_invalid_count_by_token;
RWStructuredBuffer<uint> wasm_func_detail_by_token;

static const uint INVALID = 0xffffffffu;
static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;

static const uint HIR_STMT = 7u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_EXPR = 14u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint STMT_RECORD_KIND_FOR = 7u;

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
static const uint HIR_EXPR_FLOAT = 27u;

static const uint WASM_CONST_VALUE_LITERAL = 1u;
static const uint INTRINSIC_TEXT_WRITE = 1u;
static const uint BODY_FRAGMENT_PRINT_I64 = 2u;
static const uint BODY_FRAGMENT_PRINT_LOCAL_I64 = 7u;
static const uint BODY_FRAGMENT_PRINT_EXPR_I64 = 12u;
static const uint BODY_FRAGMENT_IF_OPEN_I32 = 16u;
static const uint BODY_FRAGMENT_IF_ELSE = 17u;
static const uint BODY_FRAGMENT_IF_END = 18u;
static const uint MAX_CONST_EVAL_STACK = 16u;
static const uint MAX_CONST_EVAL_STEPS = 48u;
static const uint MAX_EXPR_EMIT_STACK = 16u;
static const uint MAX_EXPR_EMIT_STEPS = 48u;
static const uint MAX_CONTROL_BRANCH_DEPTH = 16u;
static const uint MAX_PATH_SEGMENTS = 9u;
static const uint DISPATCH_X_STRIDE = 16776960u;

static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_PRINT_COUNT_AGG = 17u;
static const uint BODY_PLAN_PRINT_MAX_TOKEN = 19u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint BODY_PLAN_LOCAL_CONST_EXPR_COUNT = 29u;
static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint BODY_FEATURE_EXPR_CONTROL = 1u << 0u;

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

bool valid_token_end(uint token)
{
    return token != INVALID && token <= gParams.n_tokens;
}

uint stmt_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(hir_stmt_record, node, STMT_RECORD_STRIDE, slot, INVALID);
}

uint expr_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(hir_expr_record, node, EXPR_RECORD_STRIDE, slot, INVALID);
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

uint active_path_count()
{
    return min(path_count_out[0u], gParams.n_hir_nodes);
}

bool valid_path(uint path_i)
{
    return path_i != INVALID && path_i < active_path_count();
}

uint path_node_for_callee(uint callee_node)
{
    if (!valid_node(callee_node))
        return INVALID;
    if (hir_kind[callee_node] == HIR_PATH_EXPR)
        return callee_node;
    if (hir_kind[callee_node] == HIR_NAME_EXPR)
    {
        uint child = first_child[callee_node];
        if (valid_node(child) && hir_kind[child] == HIR_PATH_EXPR)
            return child;
    }
    return INVALID;
}

uint path_leaf_token_for_callee(uint callee_node)
{
    uint path_node = path_node_for_callee(callee_node);
    if (!valid_node(path_node))
        return INVALID;

    uint path_i = path_id_by_owner_hir[path_node];
    if (!valid_path(path_i))
        return INVALID;

    uint count = min(path_segment_count[path_i], MAX_PATH_SEGMENTS);
    if (count == 0u)
        return INVALID;

    uint slot = path_segment_base[path_i] + count - 1u;
    if (slot >= gParams.n_tokens * MAX_PATH_SEGMENTS)
        return INVALID;

    uint token = path_segment_token[slot];
    return valid_token(token) ? token : INVALID;
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

uint call_callee_token(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint raw_callee_node = hir_call_callee_node[call_node];
    uint path_leaf = path_leaf_token_for_callee(raw_callee_node);
    if (valid_token(path_leaf))
        return path_leaf;

    uint callee_node = resolve_expr_node(raw_callee_node);
    if (!valid_node(callee_node))
        return INVALID;
    uint callee_token = expr_record_slot(callee_node, EXPR_RECORD_VALUE_TOKEN);
    if (!valid_token(callee_token))
        callee_token = hir_token_pos[callee_node];
    return valid_token(callee_token) ? callee_token : INVALID;
}

bool statement_position_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;
    uint context = hir_call_context_stmt_node[call_node];
    return valid_node(context) && hir_kind[context] == HIR_STMT;
}

bool print_call_node(uint call_node)
{
    uint callee_token = call_callee_token(call_node);
    return valid_token(callee_token) &&
           statement_position_call(call_node) &&
           call_intrinsic_tag[callee_token] == INTRINSIC_TEXT_WRITE &&
           hir_call_arg_count[call_node] == 1u;
}

uint call_arg0_node(uint call_node)
{
    if (!print_call_node(call_node))
        return INVALID;

    uint arg = hir_call_arg_start[call_node];
    if (valid_node(arg) &&
        hir_call_arg_parent_call[arg] == call_node &&
        hir_call_arg_ordinal[arg] == 0u)
    {
        return arg;
    }
    return INVALID;
}

uint visible_type_for_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;
    uint ty = visible_type[token];
    if (ty != INVALID && ty != TY_UNKNOWN)
        return ty;
    uint decl = visible_decl[token];
    if (!valid_token(decl))
        return TY_UNKNOWN;
    ty = visible_type[decl];
    return ty == INVALID ? TY_UNKNOWN : ty;
}

uint local_decl_initializer_type(uint decl_token)
{
    uint init_expr = valid_token(decl_token) ? body_let_init_expr_by_decl_token[decl_token] : INVALID;
    if (!valid_node(init_expr))
        return TY_UNKNOWN;
    uint root = hir_expr_result_root_node[init_expr];
    uint form = expr_form(valid_node(root) ? root : init_expr);
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    return form == HIR_EXPR_INT || form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE ? 3u : TY_UNKNOWN;
}

uint local_decl_type(uint decl_token)
{
    uint ty = local_decl_initializer_type(decl_token);
    if (ty == TY_UNKNOWN)
        ty = visible_type_for_token(decl_token);
    return ty == TY_UNKNOWN ? 3u : ty;
}

bool method_receiver_param(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token) || ordinal != 0u)
        return false;
    uint mode = method_decl_receiver_mode[fn_token];
    return mode == METHOD_RECEIVER_SELF || mode == METHOD_RECEIVER_REF_SELF;
}

uint call_param_type_value(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token))
        return TY_UNKNOWN;

    uint start = call_param_row_start[fn_token];
    uint count = call_param_row_count[fn_token];
    uint row_limit = call_param_row_count_out[0u];
    if (start == INVALID || ordinal >= count || start > row_limit || ordinal > row_limit - start)
        return method_receiver_param(fn_token, ordinal) ? 128u : TY_UNKNOWN;

    uint row = start + ordinal;
    if (row >= row_limit ||
        call_param_row_fn_token[row] != fn_token ||
        call_param_row_ordinal[row] != ordinal)
    {
        return method_receiver_param(fn_token, ordinal) ? 128u : TY_UNKNOWN;
    }

    uint ty = call_param_row_type[row];
    return ty == TY_UNKNOWN && method_receiver_param(fn_token, ordinal) ? 128u : ty;
}

uint wasm_value_abi_width(uint ty)
{
    return ty == TY_STRING ? 2u : 1u;
}

uint function_param_abi_count(uint fn_token)
{
    if (!valid_token(fn_token))
        return 0u;

    uint count = call_param_count[fn_token];
    uint total = 0u;
    for (uint ordinal = 0u; ordinal < count; ordinal += 1u)
        total += wasm_value_abi_width(call_param_type_value(fn_token, ordinal));
    return total;
}

uint function_param_abi_ordinal(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token))
        return INVALID;

    uint count = call_param_count[fn_token];
    if (ordinal >= count)
        return INVALID;

    uint local_index = 0u;
    for (uint i = 0u; i < ordinal; i += 1u)
        local_index += wasm_value_abi_width(call_param_type_value(fn_token, i));
    return local_index;
}

uint local_decl_count_for_function_token(uint fn_token)
{
    if (!valid_token(fn_token))
        return 0u;
    uint local_max = wasm_func_local_max_by_token[fn_token];
    return local_max == INVALID ? 0u : local_max + 1u;
}

bool function_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;

    uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
    uint param_count = call_param_count[fn_token];
    if (ordinal == INVALID || ordinal >= param_count)
        return false;

    local_index = function_param_abi_ordinal(fn_token, ordinal);
    return local_index != INVALID;
}

bool function_non_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;

    uint param_count = function_param_abi_count(fn_token);
    uint local_count = local_decl_count_for_function_token(fn_token);
    local_index = param_count + decl_token;
    if (local_decl_type(decl_token) == 5u)
        local_index += local_count * 2u;
    return true;
}

bool let_initializer_for_decl_token(uint decl_token, out uint init_expr)
{
    init_expr = INVALID;
    if (!valid_token(decl_token))
        return false;

    init_expr = body_let_init_expr_by_decl_token[decl_token];
    return valid_node(init_expr) && hir_kind[init_expr] == HIR_EXPR;
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

bool local_decl_token_for_name_expr(uint node, out uint decl_token)
{
    decl_token = INVALID;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token))
        return false;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return false;

    uint local_index = INVALID;
    if (function_param_local_index(decl_token, owner_fn, local_index))
    {
        decl_token = local_index;
        return true;
    }

    uint init_expr = INVALID;
    if (let_initializer_for_decl_token(decl_token, init_expr))
    {
        if (!function_non_param_local_index(decl_token, owner_fn, local_index))
            return false;
        decl_token = local_index;
        return true;
    }

    uint control = hir_nearest_enclosing_control_node[node];
    for (uint i = 0u; i < MAX_CONTROL_BRANCH_DEPTH; i += 1u)
    {
        if (!valid_node(control))
            return false;
        if ((hir_kind[control] == HIR_FOR_STMT || hir_kind[control] == HIR_STMT) &&
            stmt_record_slot(control, 0u) == STMT_RECORD_KIND_FOR &&
            stmt_record_slot(control, 1u) == decl_token)
        {
            if (!function_non_param_local_index(decl_token, owner_fn, local_index))
                return false;
            decl_token = local_index;
            return true;
        }
        control = hir_nearest_enclosing_control_node[control];
    }
    return false;
}

bool name_const_record_value(uint name_node, out uint value)
{
    value = 0u;
    uint name_token = expr_record_slot(name_node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token))
        return false;

    uint2 record = wasm_const_value_record[decl_token];
    if (record.x != WASM_CONST_VALUE_LITERAL)
        return false;
    value = record.y;
    return true;
}

bool name_let_initializer_expr(uint name_node, out uint init_expr)
{
    init_expr = INVALID;
    uint name_token = expr_record_slot(name_node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    return let_initializer_for_decl_token(decl_token, init_expr);
}

bool const_atom_value(uint node, out uint value)
{
    value = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    if (form == HIR_EXPR_INT)
    {
        value = hir_expr_int_value[node];
        return true;
    }
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
    {
        value = form == HIR_EXPR_TRUE ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_NAME)
        return name_const_record_value(node, value);
    return false;
}

bool unary_const_value(uint form, uint inner, out uint value)
{
    if (form == HIR_EXPR_NEG)
    {
        value = 0u - inner;
        return true;
    }
    if (form == HIR_EXPR_NOT)
    {
        value = inner == 0u ? 1u : 0u;
        return true;
    }
    value = 0u;
    return false;
}

bool binary_const_value(uint form, uint left, uint right, out uint value)
{
    value = 0u;
    if (form == HIR_EXPR_EQ) { value = left == right ? 1u : 0u; return true; }
    if (form == HIR_EXPR_NE) { value = left != right ? 1u : 0u; return true; }
    if (form == HIR_EXPR_LT) { value = int(left) < int(right) ? 1u : 0u; return true; }
    if (form == HIR_EXPR_GT) { value = int(left) > int(right) ? 1u : 0u; return true; }
    if (form == HIR_EXPR_LE) { value = int(left) <= int(right) ? 1u : 0u; return true; }
    if (form == HIR_EXPR_GE) { value = int(left) >= int(right) ? 1u : 0u; return true; }
    if (form == HIR_EXPR_ADD) { value = left + right; return true; }
    if (form == HIR_EXPR_SUB) { value = left - right; return true; }
    if (form == HIR_EXPR_MUL) { value = left * right; return true; }
    if (form == HIR_EXPR_AND) { value = left != 0u && right != 0u ? 1u : 0u; return true; }
    if (form == HIR_EXPR_OR) { value = left != 0u || right != 0u ? 1u : 0u; return true; }
    if (form == HIR_EXPR_BIT_OR) { value = left | right; return true; }
    if (form == HIR_EXPR_BIT_XOR) { value = left ^ right; return true; }
    if (form == HIR_EXPR_BIT_AND) { value = left & right; return true; }
    if (form == HIR_EXPR_SHL) { value = left << min(right, 31u); return true; }
    if (form == HIR_EXPR_SHR) { value = uint(int(left) >> min(right, 31u)); return true; }
    if (right == 0u)
        return false;
    if (form == HIR_EXPR_DIV) { value = uint(int(left) / int(right)); return true; }
    if (form == HIR_EXPR_MOD) { value = uint(int(left) % int(right)); return true; }
    return false;
}

bool push_eval_node(
    inout uint nodes[MAX_CONST_EVAL_STACK],
    inout uint states[MAX_CONST_EVAL_STACK],
    inout uint sp,
    uint node)
{
    if (sp >= MAX_CONST_EVAL_STACK)
        return false;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    nodes[sp] = node;
    states[sp] = 0u;
    sp += 1u;
    return true;
}

bool expr_binary_form(uint form)
{
    return form == HIR_EXPR_EQ || form == HIR_EXPR_NE ||
           form == HIR_EXPR_LT || form == HIR_EXPR_GT ||
           form == HIR_EXPR_LE || form == HIR_EXPR_GE ||
           form == HIR_EXPR_ADD || form == HIR_EXPR_SUB ||
           form == HIR_EXPR_MUL || form == HIR_EXPR_AND ||
           form == HIR_EXPR_OR || form == HIR_EXPR_MOD ||
           form == HIR_EXPR_DIV || form == HIR_EXPR_BIT_OR ||
           form == HIR_EXPR_BIT_XOR || form == HIR_EXPR_BIT_AND ||
           form == HIR_EXPR_SHL || form == HIR_EXPR_SHR;
}

bool expr_atom_is_f32(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    if (form == HIR_EXPR_FLOAT)
        return true;
    if (form == HIR_EXPR_NAME)
    {
        uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
        return visible_type_for_token(name_token) == TY_FLOAT;
    }
    return false;
}

bool expr_neg_is_f32(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    return expr_form(node) == HIR_EXPR_NEG && expr_atom_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT));
}

bool const_expr_value(uint root_node, out uint value)
{
    value = 0u;
    uint nodes[MAX_CONST_EVAL_STACK];
    uint states[MAX_CONST_EVAL_STACK];
    uint values[MAX_CONST_EVAL_STACK];
    uint sp = 0u;
    uint vsp = 0u;
    if (!push_eval_node(nodes, states, sp, root_node))
        return false;

    for (uint step = 0u; step < MAX_CONST_EVAL_STEPS; step += 1u)
    {
        if (sp == 0u)
            break;

        uint node = nodes[sp - 1u];
        uint state = states[sp - 1u];
        uint form = expr_form(node);
        uint atom = 0u;
        if (state == 0u && const_atom_value(node, atom))
        {
            if (vsp >= MAX_CONST_EVAL_STACK)
                return false;
            values[vsp] = atom;
            vsp += 1u;
            sp -= 1u;
            continue;
        }
        if (state == 0u && form == HIR_EXPR_NAME)
        {
            uint init_expr = INVALID;
            if (!name_let_initializer_expr(node, init_expr))
                return false;
            nodes[sp - 1u] = resolve_expr_node(init_expr);
            states[sp - 1u] = 0u;
            continue;
        }
        if (form == HIR_EXPR_NEG || form == HIR_EXPR_NOT)
        {
            if (state == 0u)
            {
                states[sp - 1u] = 1u;
                if (!push_eval_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_LEFT)))
                    return false;
                continue;
            }
            if (vsp < 1u)
                return false;
            uint inner = values[vsp - 1u];
            vsp -= 1u;
            uint result = 0u;
            if (!unary_const_value(form, inner, result))
                return false;
            values[vsp] = result;
            vsp += 1u;
            sp -= 1u;
            continue;
        }
        if (!expr_binary_form(form))
            return false;

        if (state == 0u)
        {
            states[sp - 1u] = 1u;
            if (!push_eval_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_LEFT)))
                return false;
            continue;
        }
        if (state == 1u)
        {
            states[sp - 1u] = 2u;
            if (!push_eval_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_RIGHT)))
                return false;
            continue;
        }
        if (vsp < 2u)
            return false;
        uint right = values[vsp - 1u];
        uint left = values[vsp - 2u];
        vsp -= 2u;
        uint result = 0u;
        if (!binary_const_value(form, left, right, result))
            return false;
        values[vsp] = result;
        vsp += 1u;
        sp -= 1u;
    }

    if (sp != 0u || vsp != 1u)
        return false;
    value = values[0u];
    return true;
}

bool expr_mentions_local_let(uint root_node)
{
    uint nodes[MAX_CONST_EVAL_STACK];
    uint states[MAX_CONST_EVAL_STACK];
    uint sp = 0u;
    if (!push_eval_node(nodes, states, sp, root_node))
        return false;

    for (uint step = 0u; step < MAX_CONST_EVAL_STEPS; step += 1u)
    {
        if (sp == 0u)
            return false;

        uint node = resolve_expr_node(nodes[sp - 1u]);
        sp -= 1u;
        if (!valid_node(node))
            return false;

        uint decl_token = INVALID;
        if (local_decl_token_for_name_expr(node, decl_token))
            return true;

        uint form = expr_form(node);
        if (form == HIR_EXPR_NEG || form == HIR_EXPR_NOT)
        {
            if (!push_eval_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_LEFT)))
                return false;
            continue;
        }

        if (expr_binary_form(form))
        {
            if (!push_eval_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_LEFT)) ||
                !push_eval_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_RIGHT)))
            {
                return false;
            }
        }
    }
    return false;
}

bool expr_non_call_atom_and_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    uint decl_token = INVALID;
    if (form == HIR_EXPR_NAME && local_decl_token_for_name_expr(node, decl_token))
    {
        len = local_get_len(decl_token);
        return true;
    }

    uint value = 0u;
    if (form == HIR_EXPR_INT ||
        form == HIR_EXPR_TRUE ||
        form == HIR_EXPR_FALSE ||
        (form == HIR_EXPR_NAME && name_const_record_value(node, value)))
    {
        if (form == HIR_EXPR_INT)
            value = hir_expr_int_value[node];
        else if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
            value = form == HIR_EXPR_TRUE ? 1u : 0u;
        len = 1u + i32_sleb_len(value);
        return true;
    }
    if (form == HIR_EXPR_FLOAT)
    {
        len = 5u;
        return true;
    }
    return false;
}

bool push_expr_len_node(
    inout uint nodes[MAX_EXPR_EMIT_STACK],
    inout uint states[MAX_EXPR_EMIT_STACK],
    inout uint sp,
    uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node) || sp >= MAX_EXPR_EMIT_STACK)
        return false;
    nodes[sp] = node;
    states[sp] = 0u;
    sp += 1u;
    return true;
}

bool expr_tree_and_len(uint root_node, out uint len)
{
    len = 0u;
    uint nodes[MAX_EXPR_EMIT_STACK];
    uint states[MAX_EXPR_EMIT_STACK];
    uint lens[MAX_EXPR_EMIT_STACK];
    uint sp = 0u;
    uint lsp = 0u;
    if (!push_expr_len_node(nodes, states, sp, root_node))
        return false;

    for (uint step = 0u; step < MAX_EXPR_EMIT_STEPS; step += 1u)
    {
        if (sp == 0u)
            break;

        uint node = nodes[sp - 1u];
        uint state = states[sp - 1u];
        uint atom_len = 0u;
        if (state == 0u && expr_non_call_atom_and_len(node, atom_len))
        {
            if (lsp >= MAX_EXPR_EMIT_STACK)
                return false;
            lens[lsp] = atom_len;
            lsp += 1u;
            sp -= 1u;
            continue;
        }

        uint form = expr_form(node);
        if (form == HIR_EXPR_NOT || form == HIR_EXPR_NEG)
        {
            if (state == 0u)
            {
                states[sp - 1u] = 1u;
                if (!push_expr_len_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_LEFT)))
                    return false;
                continue;
            }
            if (lsp < 1u)
                return false;
            uint inner_len = lens[lsp - 1u];
            lens[lsp - 1u] = inner_len + (form == HIR_EXPR_NOT ? 1u : (expr_neg_is_f32(node) ? 1u : 3u));
            sp -= 1u;
            continue;
        }

        if (!expr_binary_form(form))
            return false;

        if (state == 0u)
        {
            states[sp - 1u] = 1u;
            if (!push_expr_len_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_LEFT)))
                return false;
            continue;
        }
        if (state == 1u)
        {
            states[sp - 1u] = 2u;
            if (!push_expr_len_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_RIGHT)))
                return false;
            continue;
        }
        if (lsp < 2u)
            return false;
        uint right_len = lens[lsp - 1u];
        uint left_len = lens[lsp - 2u];
        lsp -= 1u;
        lens[lsp - 1u] = left_len + right_len + 1u;
        sp -= 1u;
    }

    if (sp != 0u || lsp != 1u)
        return false;
    len = lens[0u];
    return len != 0u;
}

bool print_call_local_and_len(uint call_node, out uint decl_token, out uint len)
{
    decl_token = INVALID;
    len = 0u;
    uint arg_node = call_arg0_node(call_node);
    if (!valid_node(arg_node) || !local_decl_token_for_name_expr(arg_node, decl_token))
        return false;

    len = local_get_len(decl_token) + 1u + 2u;
    return true;
}

bool print_call_value_and_len(uint call_node, out uint value, out uint len)
{
    value = 0u;
    len = 0u;
    uint arg_node = call_arg0_node(call_node);
    if (!valid_node(arg_node) ||
        expr_mentions_local_let(arg_node) ||
        !const_expr_value(arg_node, value))
    {
        return false;
    }

    len = 1u + i32_sleb_len(value) + 2u;
    return true;
}

bool print_call_expr_and_len(uint call_node, out uint expr_node, out uint len)
{
    expr_node = INVALID;
    len = 0u;
    uint arg_node = resolve_expr_node(call_arg0_node(call_node));
    if (!valid_node(arg_node) || hir_kind[arg_node] == HIR_CALL_EXPR)
        return false;

    uint expr_len = 0u;
    if (!expr_tree_and_len(arg_node, expr_len))
        return false;

    expr_node = arg_node;
    len = expr_len + 1u + 2u;
    return true;
}

bool if_open_fragment_and_len(uint if_node, out uint condition_node, out uint len)
{
    condition_node = INVALID;
    len = 0u;
    if (!valid_node(if_node) ||
        hir_kind[if_node] != HIR_IF_STMT ||
        stmt_record_slot(if_node, 0u) != STMT_RECORD_KIND_IF)
    {
        return false;
    }

    condition_node = resolve_expr_node(stmt_record_slot(if_node, 1u));
    uint then_block = stmt_record_slot(if_node, 2u);
    uint condition_len = 0u;
    if (!valid_node(condition_node) ||
        !valid_node(then_block) ||
        !expr_tree_and_len(condition_node, condition_len))
    {
        return false;
    }

    len = condition_len + 2u;
    return true;
}

bool block_close_token(uint block_node, out uint close_token)
{
    close_token = INVALID;
    if (!valid_node(block_node))
        return false;

    uint end = hir_token_end[block_node];
    if (end == 0u || end == INVALID)
        return false;

    close_token = end - 1u;
    return valid_token(close_token);
}

bool if_else_token_and_len(uint if_node, out uint else_token, out uint len)
{
    else_token = INVALID;
    len = 0u;
    if (!valid_node(if_node) ||
        hir_kind[if_node] != HIR_IF_STMT ||
        stmt_record_slot(if_node, 0u) != STMT_RECORD_KIND_IF)
    {
        return false;
    }

    uint then_block = stmt_record_slot(if_node, 2u);
    uint else_block = stmt_record_slot(if_node, 3u);
    if (!valid_node(else_block) || !block_close_token(then_block, else_token))
        return false;

    len = 1u;
    return true;
}

bool if_end_token_and_len(uint if_node, out uint end_token, out uint len)
{
    end_token = INVALID;
    len = 0u;
    if (!valid_node(if_node) ||
        hir_kind[if_node] != HIR_IF_STMT ||
        stmt_record_slot(if_node, 0u) != STMT_RECORD_KIND_IF)
    {
        return false;
    }

    uint then_block = stmt_record_slot(if_node, 2u);
    uint else_block = stmt_record_slot(if_node, 3u);
    uint close_block = valid_node(else_block) ? else_block : then_block;
    if (!block_close_token(close_block, end_token))
        return false;

    len = 1u;
    return true;
}

void add_func_body_len(uint fn_token, uint len)
{
    if (valid_token(fn_token) && len != 0u)
        atomic_u32_add(wasm_func_body_len_by_token, fn_token, len);
}

void publish_func_invalid(uint fn_token, uint detail)
{
    if (valid_token(fn_token))
        atomic_u32_add(wasm_func_invalid_count_by_token, fn_token, 1u);
    atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, detail);
    if (valid_token(fn_token))
        atomic_u32_min(wasm_func_detail_by_token, fn_token, detail);
}

void publish_fragment(uint token_i, uint len, uint4 meta, uint4 aux)
{
    uint slot = token_i * 2u;
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = meta;
    body_fragment_aux[slot] = aux;
    if (meta.x == BODY_FRAGMENT_PRINT_EXPR_I64)
        atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_EXPR_CONTROL);
}

void validate_main_print_simple(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (!print_call_node(node))
        return;

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }

    uint arg0 = resolve_expr_node(call_arg0_node(node));
    if (valid_node(arg0) && hir_kind[arg0] == HIR_CALL_EXPR)
        return;

    uint len = 0u;
    uint decl_token = INVALID;
    uint expr_node = INVALID;
    uint value = 0u;
    uint kind = BODY_FRAGMENT_PRINT_I64;
    if (print_call_local_and_len(node, decl_token, len))
    {
        kind = BODY_FRAGMENT_PRINT_LOCAL_I64;
        expr_node = decl_token;
    }
    else if (print_call_value_and_len(node, value, len))
    {
        kind = BODY_FRAGMENT_PRINT_I64;
        expr_node = value;
    }
    else if (print_call_expr_and_len(node, expr_node, len))
    {
        kind = BODY_FRAGMENT_PRINT_EXPR_I64;
    }
    else
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    if (expr_mentions_local_let(call_arg0_node(node)))
        atomic_u32_add(body_plan, BODY_PLAN_LOCAL_CONST_EXPR_COUNT, 1u);

    atomic_u32_add(body_plan, BODY_PLAN_PRINT_COUNT_AGG, 1u);
    add_func_body_len(owner_fn, len);
    atomic_u32_max(body_plan, BODY_PLAN_PRINT_MAX_TOKEN, token);
    publish_fragment(
        token,
        len,
        uint4(kind, expr_node, len, token),
        uint4(INVALID, 0u, 0u, 0u));
}

void validate_main_if_simple(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (hir_kind[node] != HIR_IF_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_IF)
    {
        return;
    }

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }

    uint condition_node = INVALID;
    uint open_len = 0u;
    uint else_token = INVALID;
    uint else_len = 0u;
    uint end_token = INVALID;
    uint end_len = 0u;
    if (!if_open_fragment_and_len(node, condition_node, open_len) ||
        !if_end_token_and_len(node, end_token, end_len))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    if (valid_node(stmt_record_slot(node, 3u)) &&
        !if_else_token_and_len(node, else_token, else_len))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    add_func_body_len(owner_fn, open_len + else_len + end_len);
    publish_fragment(
        token,
        open_len,
        uint4(BODY_FRAGMENT_IF_OPEN_I32, condition_node, open_len, token),
        uint4(INVALID, 0u, 0u, 0u));
    if (else_len != 0u)
    {
        publish_fragment(
            else_token,
            else_len,
            uint4(BODY_FRAGMENT_IF_ELSE, 0u, 0u, else_token),
            uint4(INVALID, 0u, 0u, 0u));
    }
    publish_fragment(
        end_token,
        end_len,
        uint4(BODY_FRAGMENT_IF_END, 0u, 0u, end_token),
        uint4(INVALID, 0u, 0u, 0u));
    atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, end_token);
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
    if (hir_kind[node] == HIR_CALL_EXPR)
        validate_main_print_simple(node, hir_token_pos[node]);
}
