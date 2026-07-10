// Scatter scalar let expressions containing the lanius_std i32_to_f32
// conversion. Output-byte lanes independently descend a bounded HIR tree.

import gpu_index;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<ScanParams> gScan;
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> status;
StructuredBuffer<uint> body_fragment_len;
StructuredBuffer<uint4> body_fragment_meta;
StructuredBuffer<uint4> body_fragment_aux;
StructuredBuffer<uint> body_scan_local_prefix;
StructuredBuffer<uint> body_scan_block_prefix;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_expr_float_bits;
StructuredBuffer<uint> hir_expr_string_start;
StructuredBuffer<uint> hir_expr_string_len;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint2> wasm_const_value_record;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> member_result_field_index;
StructuredBuffer<uint> wasm_agg_local_width_by_token;
StructuredBuffer<uint> wasm_agg_local_base_by_token;
StructuredBuffer<uint> wasm_agg_local_block_prefix;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;
StructuredBuffer<uint> wasm_func_local_max_by_token;
StructuredBuffer<uint> wasm_func_slot_by_token;

RWStructuredBuffer<uint> body_words;

static const uint INVALID = 0xffffffffu;
static const uint BODY_FRAGMENT_LET_EXPR_I32 = 9u;
static const uint BODY_FRAGMENT_ASSIGN_EXPR_I32 = 10u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32 = 11u;
static const uint BODY_FRAGMENT_LET_HOST_CALL_I32 = 37u;
static const uint BODY_FRAGMENT_IF_OPEN_CALL_EXPR_I32 = 51u;
static const uint BODY_FRAGMENT_LET_CONVERSION_EXPR_I32 = 50u;
static const uint LANGUAGE_SYMBOL_I32_TO_F32 = 28u;
static const uint LANGUAGE_SYMBOL_READ_I32 = 22u;
static const uint LANGUAGE_SYMBOL_WRITE_TEXT = 23u;
static const uint LANGUAGE_SYMBOL_WRITE_I32 = 24u;
static const uint LANGUAGE_SYMBOL_WRITE_BYTE = 25u;
static const uint LANGUAGE_SYMBOL_WRITE_NEWLINE = 26u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_INT = 3u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint HIR_EXPR = 14u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
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
static const uint HIR_EXPR_STRING = 28u;
static const uint WASM_CONST_VALUE_LITERAL = 1u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_F32_CONST = 0x43u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_LOCAL_SET = 0x21u;
static const uint WASM_CALL = 0x10u;
static const uint WASM_IF = 0x04u;
static const uint WASM_BLOCK_TYPE_EMPTY = 0x40u;
static const uint WASM_I32_LOAD = 0x28u;
static const uint WASM_F32_LOAD = 0x2au;
static const uint WASM_I32_EQZ = 0x45u;
static const uint WASM_I32_EQ = 0x46u;
static const uint WASM_I32_NE = 0x47u;
static const uint WASM_I32_LT_S = 0x48u;
static const uint WASM_I32_GT_S = 0x4au;
static const uint WASM_I32_LE_S = 0x4cu;
static const uint WASM_I32_GE_S = 0x4eu;
static const uint WASM_F32_EQ = 0x5bu;
static const uint WASM_F32_NE = 0x5cu;
static const uint WASM_F32_LT = 0x5du;
static const uint WASM_F32_GT = 0x5eu;
static const uint WASM_F32_LE = 0x5fu;
static const uint WASM_F32_GE = 0x60u;
static const uint WASM_I32_ADD = 0x6au;
static const uint WASM_I32_SUB = 0x6bu;
static const uint WASM_I32_MUL = 0x6cu;
static const uint WASM_I32_DIV_S = 0x6du;
static const uint WASM_I32_REM_S = 0x6fu;
static const uint WASM_I32_AND = 0x71u;
static const uint WASM_I32_OR = 0x72u;
static const uint WASM_I32_XOR = 0x73u;
static const uint WASM_I32_SHL = 0x74u;
static const uint WASM_I32_SHR_S = 0x75u;
static const uint WASM_F32_NEG = 0x8cu;
static const uint WASM_F32_ADD = 0x92u;
static const uint WASM_F32_SUB = 0x93u;
static const uint WASM_F32_MUL = 0x94u;
static const uint WASM_F32_DIV = 0x95u;
static const uint WASM_F32_CONVERT_I32_S = 0xb2u;
static const uint WASM_IMPORT_FUNCTION_COUNT = 31u;
static const uint WASM_STD_READ_I32_FUNC_INDEX = 24u;
static const uint WASM_STD_WRITE_I32_FUNC_INDEX = 25u;
static const uint WASM_STD_WRITE_BYTE_FUNC_INDEX = 26u;
static const uint WASM_STD_WRITE_NEWLINE_FUNC_INDEX = 27u;
static const uint WASM_STD_WRITE_TEXT_FUNC_INDEX = 30u;
static const uint MAX_EXPR_STACK = 16u;
static const uint MAX_EXPR_STEPS = 48u;
static const uint MAX_MEMBER_RESOLVE_STEPS = 16u;
static const uint WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint ASSIGN_OP_ADD = 2u;
static const uint ASSIGN_OP_SUB = 3u;
static const uint ASSIGN_OP_MUL = 4u;
static const uint ASSIGN_OP_DIV = 5u;
static const uint ASSIGN_OP_MOD = 6u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
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

uint u32_leb_len(uint value)
{
    if (value < (1u << 7u)) return 1u;
    if (value < (1u << 14u)) return 2u;
    if (value < (1u << 21u)) return 3u;
    if (value < (1u << 28u)) return 4u;
    return 5u;
}

uint u32_leb_byte(uint value, uint byte_i)
{
    uint shift = byte_i * 7u;
    uint byte_value = (value >> shift) & 0x7fu;
    return (value >> (shift + 7u)) == 0u ? byte_value : byte_value | 0x80u;
}

uint i32_sleb_len(uint value)
{
    int current = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current >>= 7;
        bool sign = (byte_value & 0x40u) != 0u;
        if ((current == 0 && !sign) || (current == -1 && sign) || i == 4u)
            return i + 1u;
    }
    return 5u;
}

uint i32_sleb_byte(uint value, uint byte_i)
{
    int current = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current >>= 7;
        bool sign = (byte_value & 0x40u) != 0u;
        bool done = (current == 0 && !sign) || (current == -1 && sign) || i == 4u;
        if (!done) byte_value |= 0x80u;
        if (i == byte_i) return byte_value;
        if (done) return 0u;
    }
    return 0u;
}

uint i32_const_byte(uint value, uint byte_i)
{
    return byte_i == 0u ? WASM_I32_CONST : i32_sleb_byte(value, byte_i - 1u);
}

uint f32_const_byte(uint bits, uint byte_i)
{
    return byte_i == 0u ? WASM_F32_CONST : (bits >> ((byte_i - 1u) * 8u)) & 0xffu;
}

uint local_get_len(uint local_index) { return 1u + u32_leb_len(local_index); }
uint local_get_byte(uint local_index, uint byte_i)
{
    return byte_i == 0u ? WASM_LOCAL_GET : u32_leb_byte(local_index, byte_i - 1u);
}
uint local_set_byte(uint local_index, uint byte_i)
{
    return byte_i == 0u ? WASM_LOCAL_SET : u32_leb_byte(local_index, byte_i - 1u);
}

uint visible_type_for_token(uint token)
{
    if (!valid_token(token)) return TY_UNKNOWN;
    uint ty = visible_type[token];
    if (ty != INVALID && ty != TY_UNKNOWN) return ty;
    uint decl = visible_decl[token];
    if (!valid_token(decl)) return TY_UNKNOWN;
    ty = visible_type[decl];
    return ty == INVALID ? TY_UNKNOWN : ty;
}

uint call_param_type_value(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token)) return TY_UNKNOWN;
    uint start = call_param_row_start[fn_token];
    uint count = call_param_row_count[fn_token];
    uint limit = call_param_row_count_out[0u];
    if (start == INVALID || ordinal >= count || start + ordinal >= limit) return TY_UNKNOWN;
    uint row = start + ordinal;
    if (call_param_row_fn_token[row] != fn_token || call_param_row_ordinal[row] != ordinal)
        return TY_UNKNOWN;
    return call_param_row_type[row];
}

uint function_param_abi_ordinal(uint fn_token, uint ordinal)
{
    uint local_index = 0u;
    for (uint i = 0u; i < ordinal; i += 1u)
        local_index += call_param_type_value(fn_token, i) == TY_STRING ? 2u : 1u;
    return local_index;
}

uint function_param_abi_count(uint fn_token)
{
    return function_param_abi_ordinal(fn_token, call_param_count[fn_token]);
}

uint node_enclosing_fn_token(uint node)
{
    if (!valid_node(node)) return INVALID;
    uint token = hir_token_pos[node];
    if (!valid_token(token)) return INVALID;
    uint encoded = enclosing_fn[token];
    return encoded == 0u ? INVALID : encoded - 1u;
}

uint local_decl_type(uint decl_token)
{
    uint ty = visible_type_for_token(decl_token);
    if (ty != TY_UNKNOWN) return ty;
    uint init = valid_token(decl_token) ? body_let_init_expr_by_decl_token[decl_token] : INVALID;
    init = resolve_expr_node(init);
    if (!valid_node(init)) return TY_INT;
    uint form = expr_form(init);
    return form == HIR_EXPR_FLOAT ? TY_FLOAT : TY_INT;
}

bool local_index_for_decl(uint decl_token, uint owner_fn, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(owner_fn)) return false;
    uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
    if (ordinal != INVALID && ordinal < call_param_count[owner_fn])
    {
        local_index = function_param_abi_ordinal(owner_fn, ordinal);
        return true;
    }
    uint local_count = wasm_func_local_max_by_token[owner_fn];
    local_count = local_count == INVALID ? 0u : local_count + 1u;
    local_index = function_param_abi_count(owner_fn) + decl_token;
    if (local_decl_type(decl_token) == TY_FLOAT)
        local_index += local_count * 2u;
    return true;
}

bool local_name_index(uint node, out uint local_index)
{
    local_index = INVALID;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME) return false;
    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    return local_index_for_decl(decl_token, node_enclosing_fn_token(node), local_index);
}

bool name_const_value(uint node, out uint value)
{
    value = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME) return false;
    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token)) return false;
    uint2 record = wasm_const_value_record[decl_token];
    if (record.x != WASM_CONST_VALUE_LITERAL) return false;
    value = record.y;
    return true;
}

uint align4(uint value) { return (value + 3u) & ~3u; }
uint aggregate_data_base() { return align4((gParams.n_tokens + 1u) * 4u + gParams.source_len); }

uint agg_local_base_slots(uint decl_token)
{
    uint block_i = decl_token / WG_SIZE;
    uint prior = block_i == 0u ? 0u : wasm_agg_local_block_prefix[block_i - 1u];
    return prior + wasm_agg_local_base_by_token[decl_token];
}

bool aggregate_name_address(uint node, out uint value, out uint local_index, out bool is_local)
{
    value = 0u;
    local_index = INVALID;
    is_local = false;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME) return false;
    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    uint owner_fn = node_enclosing_fn_token(node);
    if (!valid_token(decl_token) || !valid_token(owner_fn)) return false;
    uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
    if (ordinal != INVALID && ordinal < call_param_count[owner_fn])
    {
        local_index = function_param_abi_ordinal(owner_fn, ordinal);
        is_local = true;
        return true;
    }
    if (wasm_agg_local_width_by_token[decl_token] != 0u)
    {
        value = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
        return true;
    }
    if (visible_type_for_token(decl_token) >= TY_ARRAY_BASE &&
        local_index_for_decl(decl_token, owner_fn, local_index))
    {
        is_local = true;
        return true;
    }
    return false;
}

uint member_expr_node_from_expr(uint node)
{
    for (uint step = 0u; step < MAX_MEMBER_RESOLVE_STEPS; step += 1u)
    {
        if (!valid_node(node)) return INVALID;
        if (hir_kind[node] == HIR_MEMBER_EXPR && valid_token(hir_member_name_token[node]))
            return node;
        if (expr_form(node) == HIR_EXPR_FORWARD)
        {
            uint forwarded = expr_record_slot(node, EXPR_RECORD_LEFT);
            if (valid_node(forwarded) && forwarded != node)
            {
                node = forwarded;
                continue;
            }
        }
        uint root = hir_expr_result_root_node[node];
        if (!valid_node(root) || root == node) return INVALID;
        node = root;
    }
    return INVALID;
}

bool member_atom(uint node, out uint receiver_node, out uint field_index, out uint ty)
{
    receiver_node = INVALID;
    field_index = INVALID;
    ty = TY_UNKNOWN;
    node = member_expr_node_from_expr(node);
    if (!valid_node(node) || hir_kind[node] != HIR_MEMBER_EXPR) return false;
    uint member_name = hir_member_name_token[node];
    if (!valid_token(member_name)) return false;
    field_index = member_result_field_index[member_name];
    receiver_node = hir_member_receiver_node[node];
    ty = visible_type_for_token(member_name);
    uint address = 0u;
    uint local_index = INVALID;
    bool is_local = false;
    return field_index != INVALID && aggregate_name_address(receiver_node, address, local_index, is_local);
}

uint member_atom_len(uint node)
{
    uint receiver = INVALID, field = INVALID, ty = TY_UNKNOWN;
    if (!member_atom(node, receiver, field, ty)) return 0u;
    uint address = 0u, local_index = INVALID;
    bool is_local = false;
    aggregate_name_address(receiver, address, local_index, is_local);
    uint receiver_len = is_local ? local_get_len(local_index) : 1u + i32_sleb_len(address);
    return receiver_len + 2u + u32_leb_len(field * 4u);
}

uint member_atom_byte(uint node, uint byte_i)
{
    uint receiver = INVALID, field = INVALID, ty = TY_UNKNOWN;
    if (!member_atom(node, receiver, field, ty)) return 0u;
    uint address = 0u, local_index = INVALID;
    bool is_local = false;
    aggregate_name_address(receiver, address, local_index, is_local);
    uint receiver_len = is_local ? local_get_len(local_index) : 1u + i32_sleb_len(address);
    if (byte_i < receiver_len)
        return is_local ? local_get_byte(local_index, byte_i) : i32_const_byte(address, byte_i);
    uint load_i = byte_i - receiver_len;
    if (load_i == 0u) return ty == TY_FLOAT ? WASM_F32_LOAD : WASM_I32_LOAD;
    if (load_i == 1u) return 2u;
    return u32_leb_byte(field * 4u, load_i - 2u);
}

uint atom_len(uint node)
{
    uint member_len = member_atom_len(node);
    if (member_len != 0u) return member_len;
    node = resolve_expr_node(node);
    if (!valid_node(node)) return 0u;
    uint form = expr_form(node);
    uint local_index = INVALID;
    if (form == HIR_EXPR_NAME && local_name_index(node, local_index)) return local_get_len(local_index);
    uint value = 0u;
    if (form == HIR_EXPR_NAME && name_const_value(node, value)) return 1u + i32_sleb_len(value);
    if (form == HIR_EXPR_INT) return 1u + i32_sleb_len(hir_expr_int_value[node]);
    if (form == HIR_EXPR_FLOAT) return 5u;
    if (form == HIR_EXPR_STRING)
    {
        uint start = hir_expr_string_start[node];
        uint len = hir_expr_string_len[node];
        if (start == INVALID || len == INVALID) return 0u;
        uint ptr = (gParams.n_tokens + 1u) * 4u + start;
        return 1u + i32_sleb_len(ptr) + 1u + i32_sleb_len(len);
    }
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE) return 2u;
    return 0u;
}

uint atom_byte(uint node, uint byte_i)
{
    if (member_atom_len(node) != 0u) return member_atom_byte(node, byte_i);
    node = resolve_expr_node(node);
    uint form = expr_form(node);
    uint local_index = INVALID;
    if (form == HIR_EXPR_NAME && local_name_index(node, local_index)) return local_get_byte(local_index, byte_i);
    uint value = 0u;
    if (form == HIR_EXPR_NAME && name_const_value(node, value)) return i32_const_byte(value, byte_i);
    if (form == HIR_EXPR_INT) return i32_const_byte(hir_expr_int_value[node], byte_i);
    if (form == HIR_EXPR_FLOAT) return f32_const_byte(hir_expr_float_bits[node], byte_i);
    if (form == HIR_EXPR_STRING)
    {
        uint start = hir_expr_string_start[node];
        uint len = hir_expr_string_len[node];
        uint ptr = (gParams.n_tokens + 1u) * 4u + start;
        uint ptr_len = 1u + i32_sleb_len(ptr);
        return byte_i < ptr_len
            ? i32_const_byte(ptr, byte_i)
            : i32_const_byte(len, byte_i - ptr_len);
    }
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return i32_const_byte(form == HIR_EXPR_TRUE ? 1u : 0u, byte_i);
    return 0u;
}

uint direct_call_arg_node(uint call_node, uint ordinal)
{
    uint start = valid_node(call_node) ? call_arg_row_start[call_node] : INVALID;
    uint count = valid_node(call_node) ? call_arg_row_count[call_node] : 0u;
    if (start == INVALID || ordinal >= count) return INVALID;
    uint row = start + ordinal;
    if (row >= gParams.n_hir_nodes) return INVALID;
    uint node = call_arg_row_node[row];
    return valid_node(node) ? node : INVALID;
}

uint call_callee_token(uint call_node)
{
    uint callee = valid_node(call_node) ? resolve_expr_node(hir_call_callee_node[call_node]) : INVALID;
    if (!valid_node(callee)) return INVALID;
    uint token = expr_record_slot(callee, EXPR_RECORD_VALUE_TOKEN);
    if (!valid_token(token)) token = hir_token_pos[callee];
    return valid_token(token) ? token : INVALID;
}

bool conversion_call(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node) || hir_kind[node] != HIR_CALL_EXPR || hir_call_arg_count[node] != 1u)
        return false;
    uint token = call_callee_token(node);
    if (!valid_token(token)) return false;
    uint name_id = name_id_by_token[token];
    uint language_id = language_name_id[LANGUAGE_SYMBOL_I32_TO_F32];
    return name_id != INVALID && language_id != INVALID && name_id == language_id;
}

bool token_is_language_symbol(uint token, uint symbol)
{
    if (!valid_token(token)) return false;
    uint name_id = name_id_by_token[token];
    uint language_id = language_name_id[symbol];
    return name_id != INVALID && language_id != INVALID && name_id == language_id;
}

bool call_record(
    uint node,
    out uint wasm_func_index,
    out uint arg_count)
{
    wasm_func_index = INVALID;
    arg_count = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || hir_kind[node] != HIR_CALL_EXPR || conversion_call(node))
        return false;
    uint callee_token = call_callee_token(node);
    if (token_is_language_symbol(callee_token, LANGUAGE_SYMBOL_READ_I32))
        wasm_func_index = WASM_STD_READ_I32_FUNC_INDEX;
    else if (token_is_language_symbol(callee_token, LANGUAGE_SYMBOL_WRITE_TEXT))
        wasm_func_index = WASM_STD_WRITE_TEXT_FUNC_INDEX;
    else if (token_is_language_symbol(callee_token, LANGUAGE_SYMBOL_WRITE_I32))
        wasm_func_index = WASM_STD_WRITE_I32_FUNC_INDEX;
    else if (token_is_language_symbol(callee_token, LANGUAGE_SYMBOL_WRITE_BYTE))
        wasm_func_index = WASM_STD_WRITE_BYTE_FUNC_INDEX;
    else if (token_is_language_symbol(callee_token, LANGUAGE_SYMBOL_WRITE_NEWLINE))
        wasm_func_index = WASM_STD_WRITE_NEWLINE_FUNC_INDEX;
    else
    {
        uint site_token = hir_token_pos[node];
        uint fn_token = valid_token(site_token) ? call_fn_index[site_token] : INVALID;
        if (!valid_token(fn_token) && valid_token(callee_token))
            fn_token = call_fn_index[callee_token];
        if (!valid_token(fn_token) || wasm_func_slot_by_token[fn_token] == INVALID)
            return false;
        wasm_func_index = wasm_func_slot_by_token[fn_token] + WASM_IMPORT_FUNCTION_COUNT;
    }
    arg_count = hir_call_arg_count[node];
    return wasm_func_index != INVALID;
}

bool expr_value_is_f32(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node)) return false;
    if (conversion_call(node) || expr_form(node) == HIR_EXPR_FLOAT) return true;
    if (visible_type_for_token(hir_token_pos[node]) == TY_FLOAT) return true;
    uint form = expr_form(node);
    if (form == HIR_EXPR_NAME)
        return visible_type_for_token(expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN)) == TY_FLOAT;
    if (hir_kind[node] == HIR_MEMBER_EXPR)
        return visible_type_for_token(hir_member_name_token[node]) == TY_FLOAT;
    return false;
}

uint binary_op_byte(uint node)
{
    node = resolve_expr_node(node);
    uint form = expr_form(node);
    bool f32 = expr_value_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT)) ||
               expr_value_is_f32(expr_record_slot(node, EXPR_RECORD_RIGHT));
    if (f32)
    {
        if (form == HIR_EXPR_EQ) return WASM_F32_EQ;
        if (form == HIR_EXPR_NE) return WASM_F32_NE;
        if (form == HIR_EXPR_LT) return WASM_F32_LT;
        if (form == HIR_EXPR_GT) return WASM_F32_GT;
        if (form == HIR_EXPR_LE) return WASM_F32_LE;
        if (form == HIR_EXPR_GE) return WASM_F32_GE;
        if (form == HIR_EXPR_ADD) return WASM_F32_ADD;
        if (form == HIR_EXPR_SUB) return WASM_F32_SUB;
        if (form == HIR_EXPR_MUL) return WASM_F32_MUL;
        if (form == HIR_EXPR_DIV) return WASM_F32_DIV;
        return 0u;
    }
    if (form == HIR_EXPR_EQ) return WASM_I32_EQ;
    if (form == HIR_EXPR_NE) return WASM_I32_NE;
    if (form == HIR_EXPR_LT) return WASM_I32_LT_S;
    if (form == HIR_EXPR_GT) return WASM_I32_GT_S;
    if (form == HIR_EXPR_LE) return WASM_I32_LE_S;
    if (form == HIR_EXPR_GE) return WASM_I32_GE_S;
    if (form == HIR_EXPR_ADD) return WASM_I32_ADD;
    if (form == HIR_EXPR_SUB) return WASM_I32_SUB;
    if (form == HIR_EXPR_MUL) return WASM_I32_MUL;
    if (form == HIR_EXPR_DIV) return WASM_I32_DIV_S;
    if (form == HIR_EXPR_MOD) return WASM_I32_REM_S;
    if (form == HIR_EXPR_AND || form == HIR_EXPR_BIT_AND) return WASM_I32_AND;
    if (form == HIR_EXPR_OR || form == HIR_EXPR_BIT_OR) return WASM_I32_OR;
    if (form == HIR_EXPR_BIT_XOR) return WASM_I32_XOR;
    if (form == HIR_EXPR_SHL) return WASM_I32_SHL;
    if (form == HIR_EXPR_SHR) return WASM_I32_SHR_S;
    return 0u;
}

uint expr_len(uint root)
{
    root = resolve_expr_node(root);
    if (!valid_node(root)) return 0u;
    uint nodes[MAX_EXPR_STACK];
    uint states[MAX_EXPR_STACK];
    uint lens[MAX_EXPR_STACK];
    uint sp = 1u, lsp = 0u;
    nodes[0u] = root;
    states[0u] = 0u;
    for (uint step = 0u; step < MAX_EXPR_STEPS; step += 1u)
    {
        if (sp == 0u) break;
        uint node = resolve_expr_node(nodes[sp - 1u]);
        if (!valid_node(node)) return 0u;
        nodes[sp - 1u] = node;
        uint state = states[sp - 1u];
        uint len = atom_len(node);
        if (state == 0u && len != 0u)
        {
            if (lsp >= MAX_EXPR_STACK) return 0u;
            lens[lsp++] = len;
            sp--;
            continue;
        }
        if (conversion_call(node))
        {
            if (state == 0u)
            {
                if (sp >= MAX_EXPR_STACK) return 0u;
                states[sp - 1u] = 1u;
                nodes[sp] = direct_call_arg_node(node, 0u);
                states[sp++] = 0u;
                continue;
            }
            if (lsp < 1u) return 0u;
            lens[lsp - 1u] += 1u;
            sp--;
            continue;
        }
        uint call_index = INVALID;
        uint call_arg_count = 0u;
        if (call_record(node, call_index, call_arg_count))
        {
            if (state < call_arg_count)
            {
                if (sp >= MAX_EXPR_STACK) return 0u;
                states[sp - 1u] = state + 1u;
                nodes[sp] = direct_call_arg_node(node, state);
                states[sp++] = 0u;
                continue;
            }
            if (lsp < call_arg_count || lsp - call_arg_count >= MAX_EXPR_STACK)
                return 0u;
            uint call_len = 1u + u32_leb_len(call_index);
            for (uint i = 0u; i < call_arg_count; i += 1u)
                call_len += lens[lsp - call_arg_count + i];
            lsp -= call_arg_count;
            lens[lsp++] = call_len;
            sp--;
            continue;
        }
        uint form = expr_form(node);
        if (form == HIR_EXPR_NOT || form == HIR_EXPR_NEG)
        {
            if (state == 0u)
            {
                if (sp >= MAX_EXPR_STACK) return 0u;
                states[sp - 1u] = 1u;
                nodes[sp] = expr_record_slot(node, EXPR_RECORD_LEFT);
                states[sp++] = 0u;
                continue;
            }
            if (lsp < 1u) return 0u;
            lens[lsp - 1u] += form == HIR_EXPR_NOT ? 1u : (expr_value_is_f32(node) ? 1u : 3u);
            sp--;
            continue;
        }
        if (binary_op_byte(node) == 0u) return 0u;
        if (state < 2u)
        {
            if (sp >= MAX_EXPR_STACK) return 0u;
            states[sp - 1u] = state + 1u;
            nodes[sp] = expr_record_slot(node, state == 0u ? EXPR_RECORD_LEFT : EXPR_RECORD_RIGHT);
            states[sp++] = 0u;
            continue;
        }
        if (lsp < 2u) return 0u;
        lens[lsp - 2u] += lens[lsp - 1u] + 1u;
        lsp--;
        sp--;
    }
    return sp == 0u && lsp == 1u ? lens[0u] : 0u;
}

uint expr_byte(uint node, uint byte_i)
{
    for (uint step = 0u; step < MAX_EXPR_STEPS; step += 1u)
    {
        node = resolve_expr_node(node);
        if (!valid_node(node)) return 0u;
        uint len = atom_len(node);
        if (len != 0u) return atom_byte(node, byte_i);
        if (conversion_call(node))
        {
            uint arg = direct_call_arg_node(node, 0u);
            uint arg_len = expr_len(arg);
            if (byte_i < arg_len)
            {
                node = arg;
                continue;
            }
            return byte_i == arg_len ? WASM_F32_CONVERT_I32_S : 0u;
        }
        uint call_index = INVALID;
        uint call_arg_count = 0u;
        if (call_record(node, call_index, call_arg_count))
        {
            uint offset = 0u;
            bool descended = false;
            for (uint i = 0u; i < call_arg_count; i += 1u)
            {
                uint arg = direct_call_arg_node(node, i);
                uint arg_len = expr_len(arg);
                if (byte_i < offset + arg_len)
                {
                    node = arg;
                    byte_i -= offset;
                    descended = true;
                    break;
                }
                offset += arg_len;
            }
            if (descended) continue;
            if (byte_i == offset) return WASM_CALL;
            return u32_leb_byte(call_index, byte_i - offset - 1u);
        }
        uint form = expr_form(node);
        if (form == HIR_EXPR_NOT || form == HIR_EXPR_NEG)
        {
            uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
            uint inner_len = expr_len(inner);
            if (form == HIR_EXPR_NEG && !expr_value_is_f32(node) && byte_i < 2u)
                return i32_const_byte(0u, byte_i);
            uint prefix = form == HIR_EXPR_NEG && !expr_value_is_f32(node) ? 2u : 0u;
            if (byte_i < prefix + inner_len)
            {
                node = inner;
                byte_i -= prefix;
                continue;
            }
            if (byte_i != prefix + inner_len) return 0u;
            return form == HIR_EXPR_NOT ? WASM_I32_EQZ
                 : expr_value_is_f32(node) ? WASM_F32_NEG
                 : WASM_I32_SUB;
        }
        uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
        uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
        uint left_len = expr_len(left);
        uint right_len = expr_len(right);
        if (byte_i < left_len) { node = left; continue; }
        if (byte_i < left_len + right_len)
        {
            node = right;
            byte_i -= left_len;
            continue;
        }
        return byte_i == left_len + right_len ? binary_op_byte(node) : 0u;
    }
    return 0u;
}

uint body_prefix_for_item(uint item_i)
{
    return global_exclusive_prefix(item_i, WG_SIZE, body_scan_local_prefix, body_scan_block_prefix);
}

uint host_call_expr_len(uint call_node, uint wasm_func_index, uint arg_count)
{
    uint len = 1u + u32_leb_len(wasm_func_index);
    for (uint i = 0u; i < arg_count; i += 1u)
    {
        uint arg_len = expr_len(direct_call_arg_node(resolve_expr_node(call_node), i));
        if (arg_len == 0u) return 0u;
        len += arg_len;
    }
    return len;
}

uint host_call_expr_byte(
    uint call_node,
    uint wasm_func_index,
    uint arg_count,
    uint byte_i)
{
    call_node = resolve_expr_node(call_node);
    uint offset = 0u;
    for (uint i = 0u; i < arg_count; i += 1u)
    {
        uint arg_node = direct_call_arg_node(call_node, i);
        uint arg_len = expr_len(arg_node);
        if (byte_i < offset + arg_len)
            return expr_byte(arg_node, byte_i - offset);
        offset += arg_len;
    }
    if (byte_i == offset) return WASM_CALL;
    return u32_leb_byte(wasm_func_index, byte_i - offset - 1u);
}

uint compound_assign_op_byte(uint op, bool f32)
{
    if (f32)
    {
        if (op == ASSIGN_OP_ADD) return WASM_F32_ADD;
        if (op == ASSIGN_OP_SUB) return WASM_F32_SUB;
        if (op == ASSIGN_OP_MUL) return WASM_F32_MUL;
        if (op == ASSIGN_OP_DIV) return WASM_F32_DIV;
        return 0u;
    }
    if (op == ASSIGN_OP_ADD) return WASM_I32_ADD;
    if (op == ASSIGN_OP_SUB) return WASM_I32_SUB;
    if (op == ASSIGN_OP_MUL) return WASM_I32_MUL;
    if (op == ASSIGN_OP_DIV) return WASM_I32_DIV_S;
    if (op == ASSIGN_OP_MOD) return WASM_I32_REM_S;
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint body_byte_i = linear_dispatch_id(tid);
    if (body_byte_i >= gScan.out_capacity || status[2u] != 0u) return;
    uint lo = 0u, hi = gScan.n_items;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint start = body_prefix_for_item(mid);
        uint end = start + body_fragment_len[mid];
        if (end <= body_byte_i) lo = mid + 1u; else hi = mid;
    }
    uint item = lo;
    if (item >= gScan.n_items) return;
    uint len = body_fragment_len[item];
    uint offset = body_prefix_for_item(item);
    if (body_byte_i < offset || body_byte_i >= offset + len) return;
    uint4 meta = body_fragment_meta[item];
    uint4 aux = body_fragment_aux[item];
    uint byte_i = body_byte_i - offset;
    if (meta.x == BODY_FRAGMENT_LET_HOST_CALL_I32)
    {
        uint call_len = host_call_expr_len(meta.z, meta.w, aux.y);
        uint store_len = 1u + u32_leb_len(meta.y);
        if (call_len == 0u || call_len + store_len != len) return;
        body_words[offset + byte_i] = byte_i < call_len
            ? host_call_expr_byte(meta.z, meta.w, aux.y, byte_i)
            : local_set_byte(meta.y, byte_i - call_len);
        return;
    }
    if (meta.x == BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32)
    {
        uint rhs_len = expr_len(meta.z);
        uint get_len = local_get_len(meta.y);
        uint store_len = 1u + u32_leb_len(meta.y);
        uint op_byte = compound_assign_op_byte(meta.w, expr_value_is_f32(meta.z));
        if (rhs_len == 0u || op_byte == 0u || get_len + rhs_len + 1u + store_len != len)
            return;
        if (byte_i < get_len)
            body_words[offset + byte_i] = local_get_byte(meta.y, byte_i);
        else if (byte_i < get_len + rhs_len)
            body_words[offset + byte_i] = expr_byte(meta.z, byte_i - get_len);
        else if (byte_i == get_len + rhs_len)
            body_words[offset + byte_i] = op_byte;
        else
            body_words[offset + byte_i] =
                local_set_byte(meta.y, byte_i - get_len - rhs_len - 1u);
        return;
    }
    if (meta.x == BODY_FRAGMENT_IF_OPEN_CALL_EXPR_I32)
    {
        uint condition_len = expr_len(meta.y);
        if (condition_len == 0u || condition_len + 2u != len) return;
        if (byte_i < condition_len)
            body_words[offset + byte_i] = expr_byte(meta.y, byte_i);
        else
            body_words[offset + byte_i] =
                byte_i == condition_len ? WASM_IF : WASM_BLOCK_TYPE_EMPTY;
        return;
    }
    if (meta.x != BODY_FRAGMENT_LET_EXPR_I32 &&
        meta.x != BODY_FRAGMENT_ASSIGN_EXPR_I32 &&
        meta.x != BODY_FRAGMENT_LET_CONVERSION_EXPR_I32)
        return;
    uint value_len = expr_len(meta.z);
    uint store_len = 1u + u32_leb_len(meta.y);
    if (value_len == 0u || value_len + store_len != len) return;
    body_words[offset + byte_i] = byte_i < value_len
        ? expr_byte(meta.z, byte_i)
        : local_set_byte(meta.y, byte_i - value_len);
}
