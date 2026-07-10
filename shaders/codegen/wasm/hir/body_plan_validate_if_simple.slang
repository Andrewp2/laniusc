// Parallel validation and planning for simple scalar if statements.

import atomics;
import gpu_index;
import prefix_scan;

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
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_nearest_enclosing_control_node;
StructuredBuffer<uint> member_result_field_index;
StructuredBuffer<uint> member_result_field_node;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> wasm_agg_local_width_by_token;
StructuredBuffer<uint> wasm_agg_local_base_by_token;
StructuredBuffer<uint> wasm_agg_local_block_prefix;

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
static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint BODY_FEATURE_CONTROL_IF_SIMPLE = 1u << 23u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint HIR_STMT = 7u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_EXPR = 14u;
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
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint STMT_RECORD_KIND_FOR = 7u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint WASM_CONST_VALUE_LITERAL = 1u;
static const uint BODY_FRAGMENT_IF_OPEN_I32 = 16u;
static const uint BODY_FRAGMENT_IF_ELSE = 17u;
static const uint BODY_FRAGMENT_IF_END = 18u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint MAX_EXPR_EMIT_STACK = 16u;
static const uint MAX_EXPR_EMIT_STEPS = 48u;
static const uint MAX_CONTROL_BRANCH_DEPTH = 16u;
static const uint CONDITION_MEMBER_FORM_SHIFT = 24u;
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
    if (!valid_token(fn_token) || ordinal >= call_param_count[fn_token])
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
    if (ordinal == INVALID || ordinal >= call_param_count[fn_token])
        return false;

    local_index = function_param_abi_ordinal(fn_token, ordinal);
    return local_index != INVALID;
}

bool function_non_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token))
        return false;

    uint local_count = local_decl_count_for_function_token(fn_token);
    local_index = function_param_abi_count(fn_token) + decl_token;
    if (local_decl_type(decl_token) == TY_FLOAT)
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

uint align4(uint value)
{
    return (value + 3u) & ~3u;
}

uint aggregate_data_base()
{
    return align4((gParams.n_tokens + 1u) * 4u + gParams.source_len);
}

uint agg_local_base_slots(uint decl_token)
{
    return global_exclusive_prefix(
        decl_token,
        256u,
        wasm_agg_local_base_by_token,
        wasm_agg_local_block_prefix);
}

bool aggregate_address_expr_and_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token))
        return false;

    uint owner_fn = node_enclosing_fn_token(node);
    uint local_index = INVALID;
    if (function_param_local_index(decl_token, owner_fn, local_index))
    {
        len = local_get_len(local_index);
        return true;
    }
    if (function_non_param_local_index(decl_token, owner_fn, local_index))
    {
        len = local_get_len(local_index);
        return true;
    }
    if (wasm_agg_local_width_by_token[decl_token] != 0u)
    {
        uint address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
        len = 1u + i32_sleb_len(address);
        return true;
    }
    if (visible_type_for_token(decl_token) >= TY_ARRAY_BASE &&
        function_non_param_local_index(decl_token, owner_fn, local_index))
    {
        len = local_get_len(local_index);
        return true;
    }
    return false;
}

uint member_expr_node_from_expr(uint node)
{
    for (uint depth = 0u; depth < MAX_EXPR_EMIT_STACK; depth += 1u)
    {
        if (!valid_node(node))
            return INVALID;
        uint member_name = hir_member_name_token[node];
        if (hir_kind[node] == HIR_MEMBER_EXPR && valid_token(member_name))
            return node;
        uint root = hir_expr_result_root_node[node];
        if (valid_node(root) && root != node)
        {
            node = root;
            continue;
        }
        if (expr_form(node) == HIR_EXPR_FORWARD)
        {
            uint forwarded = expr_record_slot(node, EXPR_RECORD_LEFT);
            if (valid_node(forwarded) && forwarded != node)
            {
                node = forwarded;
                continue;
            }
        }
        return INVALID;
    }
    return INVALID;
}

bool expr_contains_call(uint node)
{
    uint nodes[MAX_EXPR_EMIT_STACK];
    uint sp = 1u;
    nodes[0u] = node;
    for (uint step = 0u; step < MAX_EXPR_EMIT_STEPS; step += 1u)
    {
        if (sp == 0u)
            return false;
        node = nodes[sp - 1u];
        sp -= 1u;
        if (!valid_node(node))
            continue;
        if (hir_kind[node] == HIR_CALL_EXPR)
            return true;
        if (valid_node(member_expr_node_from_expr(node)))
            continue;
        node = resolve_expr_node(node);
        if (!valid_node(node))
            continue;
        if (hir_kind[node] == HIR_CALL_EXPR)
            return true;
        uint form = expr_form(node);
        if (form == HIR_EXPR_NOT || form == HIR_EXPR_NEG)
        {
            if (sp >= MAX_EXPR_EMIT_STACK)
                return false;
            nodes[sp] = expr_record_slot(node, EXPR_RECORD_LEFT);
            sp += 1u;
            continue;
        }
        if (expr_binary_form(form))
        {
            if (sp + 2u > MAX_EXPR_EMIT_STACK)
                return false;
            nodes[sp] = expr_record_slot(node, EXPR_RECORD_LEFT);
            nodes[sp + 1u] = expr_record_slot(node, EXPR_RECORD_RIGHT);
            sp += 2u;
        }
    }
    return false;
}

uint aggregate_member_field_index(uint node)
{
    node = member_expr_node_from_expr(node);
    if (!valid_node(node))
        return INVALID;
    return member_result_field_index[hir_member_name_token[node]];
}

uint aggregate_member_field_type(uint node)
{
    node = member_expr_node_from_expr(node);
    if (!valid_node(node))
        return TY_UNKNOWN;
    uint member_name = hir_member_name_token[node];
    uint ty = visible_type_for_token(member_name);
    if (ty != TY_UNKNOWN)
        return ty;
    uint field_node = member_result_field_node[member_name];
    return valid_node(field_node) ? visible_type_for_token(hir_token_pos[field_node]) : TY_UNKNOWN;
}

bool aggregate_member_and_len(uint node, out uint len)
{
    len = 0u;
    node = member_expr_node_from_expr(node);
    if (!valid_node(node))
        return false;
    uint field_index = member_result_field_index[hir_member_name_token[node]];
    uint receiver_len = 0u;
    if (!aggregate_address_expr_and_len(hir_member_receiver_node[node], receiver_len))
        return false;
    len = receiver_len + 2u + u32_leb_len(field_index * 4u);
    return true;
}

uint member_expr_node(uint node)
{
    return member_expr_node_from_expr(node);
}

bool aggregate_name_local_index(uint node, out uint local_index)
{
    local_index = INVALID;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;
    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token))
        return false;
    uint owner_fn = node_enclosing_fn_token(node);
    return function_param_local_index(decl_token, owner_fn, local_index) ||
           function_non_param_local_index(decl_token, owner_fn, local_index);
}

bool condition_member_record(uint node, out uint local_index, out uint packed_field)
{
    local_index = INVALID;
    packed_field = INVALID;
    node = member_expr_node(node);
    if (!valid_node(node) ||
        !aggregate_name_local_index(hir_member_receiver_node[node], local_index))
    {
        return false;
    }
    uint field_index = aggregate_member_field_index(node);
    if (field_index == INVALID)
        return false;
    uint type_bit = aggregate_member_field_type(node) == TY_FLOAT ? 0x80000000u : 0u;
    packed_field = field_index | type_bit;
    return true;
}

uint4 condition_member_aux(uint condition_node)
{
    uint4 aux = uint4(INVALID, INVALID, INVALID, INVALID);
    condition_node = resolve_expr_node(condition_node);
    if (!valid_node(condition_node) || !expr_binary_form(expr_form(condition_node)))
        return aux;
    uint packed_form = expr_form(condition_node) << CONDITION_MEMBER_FORM_SHIFT;
    condition_member_record(
        expr_record_slot(condition_node, EXPR_RECORD_LEFT),
        aux.x,
        aux.y);
    if (aux.x != INVALID && aux.y != INVALID)
        aux.y |= packed_form;
    condition_member_record(
        expr_record_slot(condition_node, EXPR_RECORD_RIGHT),
        aux.z,
        aux.w);
    if (aux.z != INVALID && aux.w != INVALID)
        aux.w |= packed_form;
    return aux;
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
    if (aggregate_member_field_index(node) != INVALID)
        return aggregate_member_field_type(node) == TY_FLOAT;
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

bool expr_non_call_atom_and_len(uint node, out uint len)
{
    len = 0u;
    if (aggregate_member_and_len(node, len))
        return true;
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
    if (aggregate_member_field_index(node) == INVALID)
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

    uint raw_condition_node = stmt_record_slot(if_node, 1u);
    uint member_condition_node = member_expr_node_from_expr(raw_condition_node);
    condition_node = valid_node(member_condition_node)
                         ? member_condition_node
                         : resolve_expr_node(raw_condition_node);
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
}

uint fragment_pair_len(uint token_i)
{
    if (!valid_token(token_i))
        return 0u;
    uint slot = token_i * 2u;
    return body_fragment_len[slot] + body_fragment_len[slot + 1u];
}

void clear_fragment_pair_tail(uint token_i)
{
    if (!valid_token(token_i))
        return;
    uint slot = token_i * 2u + 1u;
    body_fragment_len[slot] = 0u;
    body_fragment_meta[slot] = uint4(0u, 0u, 0u, INVALID);
    body_fragment_aux[slot] = uint4(INVALID, 0u, 0u, 0u);
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

    if (expr_contains_call(stmt_record_slot(node, 1u)))
        return;

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

    uint replaced_len =
        fragment_pair_len(token) +
        fragment_pair_len(else_token) +
        fragment_pair_len(end_token);
    if (replaced_len != 0u && valid_token(owner_fn))
        atomic_u32_add(wasm_func_body_len_by_token, owner_fn, 0u - replaced_len);
    clear_fragment_pair_tail(token);
    clear_fragment_pair_tail(else_token);
    clear_fragment_pair_tail(end_token);
    add_func_body_len(owner_fn, open_len + else_len + end_len);
    publish_fragment(
        token,
        open_len,
        uint4(BODY_FRAGMENT_IF_OPEN_I32, condition_node, open_len, token),
        condition_member_aux(condition_node));
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
    atomic_u32_or(
        body_plan,
        BODY_PLAN_FEATURE_MASK,
        BODY_FEATURE_CONTROL_IF_SIMPLE);
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
    if (!valid_node(node) || hir_kind[node] != HIR_IF_STMT)
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_if_simple(node, hir_token_pos[node]);
}
