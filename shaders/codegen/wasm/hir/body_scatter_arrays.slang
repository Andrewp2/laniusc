// Scatter WASM body bytes for array fragments and indexed-load assignments.

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

StructuredBuffer<uint> body_fragment_len;
StructuredBuffer<uint4> body_fragment_meta;
StructuredBuffer<uint> body_scan_local_prefix;
StructuredBuffer<uint> body_scan_block_prefix;
StructuredBuffer<uint> status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_array_lit_context_stmt_node;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> call_param_count;

RWStructuredBuffer<uint> body_words;

static const uint INVALID = 0xffffffffu;
static const uint BODY_FRAGMENT_LET_ARRAY_I32 = 30u;
static const uint BODY_FRAGMENT_ARRAY_STORE_I32 = 31u;
static const uint BODY_FRAGMENT_ASSIGN_EXPR_I32 = 10u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32 = 11u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint STMT_RECORD_KIND_LET = 1u;
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
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_LOCAL_SET = 0x21u;
static const uint WASM_I32_LOAD = 0x28u;
static const uint WASM_I32_STORE = 0x36u;
static const uint WASM_I32_EQZ = 0x45u;
static const uint WASM_I32_EQ = 0x46u;
static const uint WASM_I32_NE = 0x47u;
static const uint WASM_I32_LT_S = 0x48u;
static const uint WASM_I32_GT_S = 0x4au;
static const uint WASM_I32_LE_S = 0x4cu;
static const uint WASM_I32_GE_S = 0x4eu;
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
static const uint WASM_MAX_DIRECT_CALL_ARGS = 4u;
static const uint WG_SIZE = 256u;
static const uint BODY_FRAGMENT_MAX_BYTES = 32u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint body_prefix_for_token(uint token_i)
{
    return global_exclusive_prefix(
        token_i,
        WG_SIZE,
        body_scan_local_prefix,
        body_scan_block_prefix);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
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

uint u32_leb_byte(uint value, uint byte_i)
{
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = value & 0x7fu;
        value = value >> 7u;
        if (value != 0u)
            byte_value |= 0x80u;
        if (i == byte_i)
            return byte_value;
        if (value == 0u)
            return 0u;
    }
    return 0u;
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

uint i32_sleb_byte(uint value, uint byte_i)
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
        if (!done)
            byte_value |= 0x80u;
        if (i == byte_i)
            return byte_value;
        if (done)
            return 0u;
    }
    return 0u;
}

uint i32_const_byte(uint value, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_I32_CONST;
    return i32_sleb_byte(value, byte_i - 1u);
}

uint local_get_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_GET;
    return u32_leb_byte(local_index, byte_i - 1u);
}

uint local_set_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_SET;
    return u32_leb_byte(local_index, byte_i - 1u);
}

uint memarg_i32_byte(uint op, uint byte_i)
{
    if (byte_i == 0u)
        return op;
    if (byte_i == 1u)
        return 2u;
    return 0u;
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

bool array_lit_for_decl_token(uint decl_token, out uint lit_node)
{
    lit_node = INVALID;
    if (!valid_token(decl_token))
        return false;

    uint init_expr = resolve_expr_node(body_let_init_expr_by_decl_token[decl_token]);
    if (!valid_node(init_expr) || hir_kind[init_expr] != HIR_ARRAY_EXPR)
        return false;

    uint context = hir_array_lit_context_stmt_node[init_expr];
    if (!valid_node(context) || hir_kind[context] != HIR_LET_STMT)
        return false;

    lit_node = init_expr;
    return true;
}

bool array_local_for_expr(uint node, out uint local_index)
{
    local_index = INVALID;
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    uint lit_node = INVALID;
    if (!array_lit_for_decl_token(decl_token, lit_node))
        return false;

    return function_non_param_local_index(decl_token, node_enclosing_fn_token(node), local_index);
}

uint expr_binary_op_byte(uint form)
{
    if (form == HIR_EXPR_EQ) return WASM_I32_EQ;
    if (form == HIR_EXPR_NE) return WASM_I32_NE;
    if (form == HIR_EXPR_LT) return WASM_I32_LT_S;
    if (form == HIR_EXPR_GT) return WASM_I32_GT_S;
    if (form == HIR_EXPR_LE) return WASM_I32_LE_S;
    if (form == HIR_EXPR_GE) return WASM_I32_GE_S;
    if (form == HIR_EXPR_ADD) return WASM_I32_ADD;
    if (form == HIR_EXPR_SUB) return WASM_I32_SUB;
    if (form == HIR_EXPR_MUL) return WASM_I32_MUL;
    if (form == HIR_EXPR_AND || form == HIR_EXPR_BIT_AND) return WASM_I32_AND;
    if (form == HIR_EXPR_OR || form == HIR_EXPR_BIT_OR) return WASM_I32_OR;
    if (form == HIR_EXPR_BIT_XOR) return WASM_I32_XOR;
    if (form == HIR_EXPR_SHL) return WASM_I32_SHL;
    if (form == HIR_EXPR_SHR) return WASM_I32_SHR_S;
    if (form == HIR_EXPR_DIV) return WASM_I32_DIV_S;
    if (form == HIR_EXPR_MOD) return WASM_I32_REM_S;
    return 0u;
}

uint expr_atom_len(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return 0u;
    uint form = expr_form(node);
    uint local_index = INVALID;
    if (form == HIR_EXPR_NAME && local_decl_token_for_name_expr(node, local_index))
        return 1u + u32_leb_len(local_index);
    if (form == HIR_EXPR_INT)
        return 1u + i32_sleb_len(hir_expr_int_value[node]);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return 2u;
    return 0u;
}

uint expr_atom_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    uint form = expr_form(node);
    uint local_index = INVALID;
    if (form == HIR_EXPR_NAME && local_decl_token_for_name_expr(node, local_index))
        return local_get_byte(local_index, byte_i);
    if (form == HIR_EXPR_INT)
        return i32_const_byte(hir_expr_int_value[node], byte_i);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return i32_const_byte(form == HIR_EXPR_TRUE ? 1u : 0u, byte_i);
    return 0u;
}

uint index_expr_len(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_INDEX)
        return 0u;
    uint local_index = INVALID;
    uint index_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_RIGHT));
    if (!array_local_for_expr(expr_record_slot(node, EXPR_RECORD_LEFT), local_index) ||
        index_len == 0u)
    {
        return 0u;
    }
    return 1u + u32_leb_len(local_index) + index_len + 7u;
}

uint index_expr_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    uint local_index = INVALID;
    if (!array_local_for_expr(expr_record_slot(node, EXPR_RECORD_LEFT), local_index))
        return 0u;

    uint base_len = 1u + u32_leb_len(local_index);
    if (byte_i < base_len)
        return local_get_byte(local_index, byte_i);

    uint index_node = expr_record_slot(node, EXPR_RECORD_RIGHT);
    uint index_len = expr_atom_len(index_node);
    uint index_start = base_len;
    if (byte_i < index_start + index_len)
        return expr_atom_byte(index_node, byte_i - index_start);

    uint scale_start = index_start + index_len;
    if (byte_i < scale_start + 2u)
        return i32_const_byte(4u, byte_i - scale_start);
    if (byte_i == scale_start + 2u)
        return WASM_I32_MUL;
    if (byte_i == scale_start + 3u)
        return WASM_I32_ADD;
    return memarg_i32_byte(WASM_I32_LOAD, byte_i - scale_start - 4u);
}

uint expr_simple_len(uint node)
{
    node = resolve_expr_node(node);
    uint atom_len = expr_atom_len(node);
    if (atom_len != 0u)
        return atom_len;
    uint form = expr_form(node);
    if (form == HIR_EXPR_INDEX)
        return index_expr_len(node);
    if (form == HIR_EXPR_NOT)
    {
        uint inner_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_LEFT));
        return inner_len == 0u ? 0u : inner_len + 1u;
    }
    if (form == HIR_EXPR_NEG)
    {
        uint inner_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_LEFT));
        return inner_len == 0u ? 0u : inner_len + 3u;
    }
    uint op = expr_binary_op_byte(form);
    uint left_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_LEFT));
    uint right_len = expr_atom_len(expr_record_slot(node, EXPR_RECORD_RIGHT));
    return op == 0u || left_len == 0u || right_len == 0u ? 0u : left_len + right_len + 1u;
}

uint expr_simple_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    uint atom_len = expr_atom_len(node);
    if (atom_len != 0u)
        return expr_atom_byte(node, byte_i);
    uint form = expr_form(node);
    if (form == HIR_EXPR_INDEX)
        return index_expr_byte(node, byte_i);
    if (form == HIR_EXPR_NOT)
    {
        uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
        uint inner_len = expr_atom_len(inner);
        if (byte_i < inner_len)
            return expr_atom_byte(inner, byte_i);
        return WASM_I32_EQZ;
    }
    if (form == HIR_EXPR_NEG)
    {
        if (byte_i < 2u)
            return i32_const_byte(0u, byte_i);
        uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
        uint inner_len = expr_atom_len(inner);
        if (byte_i < 2u + inner_len)
            return expr_atom_byte(inner, byte_i - 2u);
        return WASM_I32_SUB;
    }
    uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
    uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
    uint left_len = expr_atom_len(left);
    uint right_len = expr_atom_len(right);
    if (byte_i < left_len)
        return expr_atom_byte(left, byte_i);
    if (byte_i < left_len + right_len)
        return expr_atom_byte(right, byte_i - left_len);
    return expr_binary_op_byte(form);
}

uint let_array_i32_fragment_byte(uint local_index, uint base_address, uint byte_i)
{
    uint const_len = 1u + i32_sleb_len(base_address);
    if (byte_i < const_len)
        return i32_const_byte(base_address, byte_i);
    return local_set_byte(local_index, byte_i - const_len);
}

uint array_store_i32_fragment_byte(uint address, uint expr_node, uint byte_i)
{
    uint address_len = 1u + i32_sleb_len(address);
    if (byte_i < address_len)
        return i32_const_byte(address, byte_i);
    uint expr_start = address_len;
    uint expr_len = expr_simple_len(expr_node);
    if (byte_i < expr_start + expr_len)
        return expr_simple_byte(expr_node, byte_i - expr_start);
    return memarg_i32_byte(WASM_I32_STORE, byte_i - expr_start - expr_len);
}

uint assign_index_i32_fragment_byte(uint local_index, uint expr_node, uint op, uint byte_i)
{
    uint expr_len = index_expr_len(expr_node);
    if (byte_i < expr_len)
        return index_expr_byte(expr_node, byte_i);
    return local_set_byte(local_index, byte_i - expr_len);
}

uint assign_compound_index_i32_fragment_byte(uint local_index, uint expr_node, uint op, uint byte_i)
{
    uint get_len = 1u + u32_leb_len(local_index);
    if (byte_i < get_len)
        return local_get_byte(local_index, byte_i);
    uint expr_start = get_len;
    uint expr_len = index_expr_len(expr_node);
    if (byte_i < expr_start + expr_len)
        return index_expr_byte(expr_node, byte_i - expr_start);
    uint op_i = expr_start + expr_len;
    if (byte_i == op_i)
        return expr_binary_op_byte(op == 2u ? HIR_EXPR_ADD :
                                   op == 3u ? HIR_EXPR_SUB :
                                   op == 4u ? HIR_EXPR_MUL :
                                   op == 5u ? HIR_EXPR_DIV :
                                   HIR_EXPR_MOD);
    return local_set_byte(local_index, byte_i - op_i - 1u);
}

bool fragment_needs_array_scatter(uint4 meta)
{
    if (meta.x == BODY_FRAGMENT_LET_ARRAY_I32 ||
        meta.x == BODY_FRAGMENT_ARRAY_STORE_I32)
    {
        return true;
    }
    if (meta.x == BODY_FRAGMENT_ASSIGN_EXPR_I32 ||
        meta.x == BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32)
    {
        uint expr_node = resolve_expr_node(meta.z);
        return valid_node(expr_node) && expr_form(expr_node) == HIR_EXPR_INDEX;
    }
    return false;
}

uint array_fragment_byte(uint4 meta, uint byte_i)
{
    if (meta.x == BODY_FRAGMENT_LET_ARRAY_I32)
        return let_array_i32_fragment_byte(meta.y, meta.z, byte_i);
    if (meta.x == BODY_FRAGMENT_ARRAY_STORE_I32)
        return array_store_i32_fragment_byte(meta.y, meta.z, byte_i);
    if (meta.x == BODY_FRAGMENT_ASSIGN_EXPR_I32)
        return assign_index_i32_fragment_byte(meta.y, meta.z, meta.w, byte_i);
    if (meta.x == BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32)
        return assign_compound_index_i32_fragment_byte(meta.y, meta.z, meta.w, byte_i);
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint slot_i = linear_dispatch_id(tid);
    uint token_i = slot_i / BODY_FRAGMENT_MAX_BYTES;
    uint byte_i = slot_i - token_i * BODY_FRAGMENT_MAX_BYTES;
    if (token_i >= gScan.n_items || status[2u] != 0u)
        return;

    uint len = body_fragment_len[token_i];
    if (byte_i >= len)
        return;

    uint4 meta = body_fragment_meta[token_i];
    if (!fragment_needs_array_scatter(meta))
        return;

    uint offset = body_prefix_for_token(token_i);
    body_words[offset + byte_i] = array_fragment_byte(meta, byte_i);
}
