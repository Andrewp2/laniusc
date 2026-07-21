// Backend-facing expression helpers over the dense compact HIR contract.
// This module deliberately exposes no raw parser-node columns.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint artifact_flags;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirPath { uint owner; uint segment_start; uint segment_count; uint kind; };
struct HirPathSegment { uint path; uint name_token; uint ordinal; uint file_id; };
struct HirString { uint node; uint data_offset; uint decoded_len; uint file_id; };
struct HirCallArg { uint call; uint value; uint ordinal; uint file_id; };

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_expr_parent;
StructuredBuffer<uint> compact_expr_root;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<HirPath> compact_paths;
StructuredBuffer<uint> compact_path_segment_count;
StructuredBuffer<HirPathSegment> compact_path_segments;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> compact_string_count;
StructuredBuffer<HirString> compact_strings;
StructuredBuffer<uint> compact_string_pool_len;

StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_decl;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint2> wasm_const_value_record;
StructuredBuffer<uint> body_let_init_hir_by_decl_token;
StructuredBuffer<uint> wasm_agg_local_width_by_token;
StructuredBuffer<uint> wasm_agg_local_base_by_token;
StructuredBuffer<uint> wasm_agg_local_block_prefix;
StructuredBuffer<uint> member_result_field_index;
StructuredBuffer<uint> wasm_func_flag;
StructuredBuffer<uint> wasm_func_slot_by_token;
StructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;
StructuredBuffer<uint> wasm_func_local_max_by_token;
StructuredBuffer<uint2> expr_subtree_total;
StructuredBuffer<uint2> expr_subtree_features;
StructuredBuffer<uint> compact_expr_scalar_type;

static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint HIR_EXPR = 14u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_CALL_CONTEXT_STMT_BIT = 0x80000000u;
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
static const uint HIR_EXPR_INDEX_FORM = 26u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_STRING = 28u;
static const uint HIR_EXPR_RANGE = 30u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint WASM_CONST_VALUE_LITERAL = 1u;
static const uint WASM_IMPORT_FUNCTION_COUNT = 42u;
static const uint LANGUAGE_SYMBOL_READ_I32 = 22u;
static const uint LANGUAGE_SYMBOL_WRITE_TEXT = 23u;
static const uint LANGUAGE_SYMBOL_WRITE_I32 = 24u;
static const uint LANGUAGE_SYMBOL_WRITE_BYTE = 25u;
static const uint LANGUAGE_SYMBOL_WRITE_NEWLINE = 26u;
static const uint WASM_STD_READ_I32_FUNC_INDEX = 24u;
static const uint WASM_STD_WRITE_I32_FUNC_INDEX = 25u;
static const uint WASM_STD_WRITE_BYTE_FUNC_INDEX = 26u;
static const uint WASM_STD_WRITE_NEWLINE_FUNC_INDEX = 27u;
static const uint WASM_STD_WRITE_TEXT_FUNC_INDEX = 30u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_I32_EQ = 0x46u;
static const uint WASM_I32_NE = 0x47u;
static const uint WASM_I32_LT_S = 0x48u;
static const uint WASM_I32_GT_S = 0x4au;
static const uint WASM_I32_LE_S = 0x4cu;
static const uint WASM_I32_GE_S = 0x4eu;
static const uint WASM_I32_LT_U = 0x49u;
static const uint WASM_I32_GT_U = 0x4bu;
static const uint WASM_I32_LE_U = 0x4du;
static const uint WASM_I32_GE_U = 0x4fu;
static const uint WASM_I32_ADD = 0x6au;
static const uint WASM_I32_SUB = 0x6bu;
static const uint WASM_I32_MUL = 0x6cu;
static const uint WASM_I32_DIV_S = 0x6du;
static const uint WASM_I32_DIV_U = 0x6eu;
static const uint WASM_I32_REM_S = 0x6fu;
static const uint WASM_I32_REM_U = 0x70u;
static const uint WASM_I32_AND = 0x71u;
static const uint WASM_I32_OR = 0x72u;
static const uint WASM_I32_XOR = 0x73u;
static const uint WASM_I32_SHL = 0x74u;
static const uint WASM_I32_SHR_S = 0x75u;
static const uint WASM_I32_SHR_U = 0x76u;
static const uint WASM_F32_EQ = 0x5bu;
static const uint WASM_F32_NE = 0x5cu;
static const uint WASM_F32_LT = 0x5du;
static const uint WASM_F32_GT = 0x5eu;
static const uint WASM_F32_LE = 0x5fu;
static const uint WASM_F32_GE = 0x60u;
static const uint WASM_F32_NEG = 0x8cu;
static const uint WASM_F32_ADD = 0x92u;
static const uint WASM_F32_SUB = 0x93u;
static const uint WASM_F32_MUL = 0x94u;
static const uint WASM_F32_DIV = 0x95u;
static const uint ASSIGN_OP_SET = 1u;
static const uint ASSIGN_OP_ADD = 2u;
static const uint ASSIGN_OP_SUB = 3u;
static const uint ASSIGN_OP_MUL = 4u;
static const uint ASSIGN_OP_DIV = 5u;
static const uint ASSIGN_OP_MOD = 6u;
static const uint MAX_PATH_SEGMENTS = 9u;

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint active_call_arg_count()
{
    return min(compact_call_arg_count[0u], gParams.n_hir_nodes);
}

uint compact_call_explicit_arg_count(uint call)
{
    return valid_node(call) && compact_hir_core[call].kind == HIR_CALL_EXPR
               ? compact_hir_payload[call].c
               : 0u;
}

uint compact_call_arg_node(uint call, uint ordinal)
{
    if (!valid_node(call) || compact_hir_core[call].kind != HIR_CALL_EXPR)
        return INVALID;
    HirPayload payload = compact_hir_payload[call];
    uint count = payload.c;
    uint start = payload.b;
    uint limit = active_call_arg_count();
    if (start == INVALID || ordinal >= count || start > limit || ordinal > limit - start)
        return INVALID;
    uint row = start + ordinal;
    if (row >= limit)
        return INVALID;
    HirCallArg arg = compact_call_args[row];
    return arg.call == call && arg.ordinal == ordinal && valid_node(arg.value)
               ? arg.value
               : INVALID;
}

uint compact_method_member_node_for_call(uint call)
{
    if (!valid_node(call) || compact_hir_core[call].kind != HIR_CALL_EXPR)
        return INVALID;
    uint callee = compact_hir_payload[call].a;
    return valid_node(callee) && compact_hir_core[callee].kind == HIR_MEMBER_EXPR
               ? callee
               : INVALID;
}

uint compact_method_receiver_node_for_call(uint call)
{
    uint member = compact_method_member_node_for_call(call);
    if (!valid_node(member))
        return INVALID;
    uint receiver = compact_hir_payload[member].b;
    return valid_node(receiver) ? receiver : INVALID;
}

bool compact_direct_call_has_receiver_arg(uint call, uint fn_token)
{
    if (!valid_token(fn_token) || !valid_node(compact_method_receiver_node_for_call(call)))
        return false;
    uint explicit_count = compact_call_explicit_arg_count(call);
    return call_param_count[fn_token] == explicit_count + 1u;
}

uint compact_direct_call_abi_arg_node(uint call, uint fn_token, uint ordinal)
{
    if (compact_direct_call_has_receiver_arg(call, fn_token))
    {
        if (ordinal == 0u)
            return compact_method_receiver_node_for_call(call);
        return compact_call_arg_node(call, ordinal - 1u);
    }
    return compact_call_arg_node(call, ordinal);
}

uint expr_record_slot(uint node, uint slot)
{
    if (!valid_node(node) || slot >= 4u)
        return INVALID;
    HirPayload payload = compact_hir_payload[node];
    if (slot == 0u) return payload.a;
    if (slot == 1u) return payload.b;
    if (slot == 2u) return payload.c;
    return payload.d;
}

uint expr_form(uint node)
{
    return valid_node(node) ? compact_hir_payload[node].a : HIR_EXPR_NONE;
}

uint resolve_expr_node(uint node)
{
    return valid_node(node) ? node : INVALID;
}

bool token_has_language_name(uint token, uint symbol)
{
    if (!valid_token(token) || symbol >= 64u)
        return false;
    uint language_id = language_name_id[symbol];
    return language_id != INVALID && name_id_by_token[token] == language_id;
}

uint active_path_count()
{
    return min(compact_path_count[0u], active_hir_node_count());
}

uint active_path_segment_count()
{
    return min(compact_path_segment_count[0u], gParams.n_tokens);
}

bool valid_path(uint path)
{
    return path != INVALID && path < active_path_count();
}

uint path_node_for_callee(uint callee)
{
    if (!valid_node(callee))
        return INVALID;
    if (compact_hir_core[callee].kind == HIR_PATH_EXPR)
        return callee;
    if (compact_hir_core[callee].kind != HIR_NAME_EXPR)
        return INVALID;
    uint child = compact_hir_links[callee].first_child;
    return valid_node(child) && compact_hir_core[child].kind == HIR_PATH_EXPR
               ? child
               : INVALID;
}

uint path_leaf_token_for_callee(uint callee)
{
    uint owner = path_node_for_callee(callee);
    if (!valid_node(owner))
        return INVALID;
    uint path_i = path_id_by_owner_hir[owner];
    if (!valid_path(path_i))
        return INVALID;
    HirPath path = compact_paths[path_i];
    uint count = min(path.segment_count, MAX_PATH_SEGMENTS);
    if (path.owner != owner || count == 0u || path.segment_start == INVALID)
        return INVALID;
    uint row = path.segment_start + count - 1u;
    if (row < path.segment_start || row >= active_path_segment_count())
        return INVALID;
    HirPathSegment segment = compact_path_segments[row];
    return segment.path == path_i && valid_token(segment.name_token)
               ? segment.name_token
               : INVALID;
}

uint node_enclosing_fn_token(uint node)
{
    uint token = valid_node(node) ? compact_hir_core[node].token_start : INVALID;
    if (!valid_token(token))
        return INVALID;
    uint encoded = enclosing_fn[token];
    return encoded == 0u ? INVALID : encoded - 1u;
}

uint call_callee_token(uint call)
{
    if (!valid_node(call) || compact_hir_core[call].kind != HIR_CALL_EXPR)
        return INVALID;
    uint callee = compact_hir_payload[call].a;
    uint path_leaf = path_leaf_token_for_callee(callee);
    if (valid_token(path_leaf))
        return path_leaf;
    if (!valid_node(callee))
        return INVALID;
    if (compact_hir_core[callee].kind == HIR_MEMBER_EXPR)
        return compact_hir_payload[callee].c;
    uint token = compact_hir_payload[callee].d;
    if (!valid_token(token))
        token = compact_hir_core[callee].token_start;
    return valid_token(token) ? token : INVALID;
}

uint call_site_token(uint call)
{
    return valid_node(call) ? compact_hir_core[call].token_start : INVALID;
}

uint semantic_callee_token_for_call(uint call)
{
    if (!valid_node(call) || compact_hir_core[call].kind != HIR_CALL_EXPR)
        return INVALID;
    uint site = call_site_token(call);
    uint callee = compact_hir_payload[call].a;
    if (!valid_node(callee))
        return valid_token(site) ? site : INVALID;
    if (compact_hir_core[callee].kind == HIR_MEMBER_EXPR)
    {
        uint member = compact_hir_payload[callee].c;
        return valid_token(member) ? member : INVALID;
    }
    if (valid_token(site) && valid_token(call_fn_index[site]))
        return site;
    uint token = compact_hir_payload[callee].d;
    if (!valid_token(token)) token = compact_hir_core[callee].token_start;
    if (!valid_token(token)) token = site;
    return valid_token(token) ? token : INVALID;
}

uint call_metadata_token(uint call, uint callee_token)
{
    uint site = call_site_token(call);
    uint semantic = semantic_callee_token_for_call(call);
    if (valid_token(site) && call_dependency_decl[site] != INVALID) return site;
    if (valid_token(semantic) && call_dependency_decl[semantic] != INVALID) return semantic;
    if (valid_token(callee_token) && call_dependency_decl[callee_token] != INVALID) return callee_token;
    if (valid_token(site) && valid_token(call_fn_index[site])) return site;
    if (valid_token(semantic) && valid_token(call_fn_index[semantic])) return semantic;
    if (valid_token(callee_token) && valid_token(call_fn_index[callee_token])) return callee_token;
    return callee_token;
}

uint call_fn_token_for_call(uint call, uint callee_token)
{
    uint metadata = call_metadata_token(call, callee_token);
    if (!valid_token(metadata)) return INVALID;
    if (call_dependency_decl[metadata] != INVALID) return metadata;
    uint local = call_fn_index[metadata];
    return valid_token(local) ? local : INVALID;
}

bool supported_function_token(uint token)
{
    return valid_token(token) && wasm_func_flag[token] != 0u &&
           wasm_func_slot_by_token[token] != INVALID;
}

bool supported_call_target_token(uint token)
{
    return supported_function_token(token) ||
           (valid_token(token) && call_dependency_decl[token] != INVALID);
}

uint wasm_call_target_for_call(uint call, uint fn_token)
{
    uint metadata = call_metadata_token(call, call_callee_token(call));
    if (valid_token(metadata) && call_dependency_decl[metadata] != INVALID)
        return 0x80000000u | (call_dependency_decl[metadata] & 0x7fffffffu);
    return valid_token(fn_token) && wasm_func_slot_by_token[fn_token] != INVALID
               ? wasm_func_slot_by_token[fn_token] + WASM_IMPORT_FUNCTION_COUNT
               : INVALID;
}

uint call_return_type_for_call(uint call, uint callee_token, uint fn_token)
{
    uint metadata = call_metadata_token(call, callee_token);
    uint ty = valid_token(metadata) ? call_return_type[metadata] : TY_UNKNOWN;
    return ty != TY_UNKNOWN && ty != INVALID
               ? ty
               : (valid_token(fn_token) ? call_return_type[fn_token] : TY_UNKNOWN);
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

bool method_receiver_param(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token) || ordinal != 0u) return false;
    uint mode = method_decl_receiver_mode[fn_token];
    return mode == METHOD_RECEIVER_SELF || mode == METHOD_RECEIVER_REF_SELF;
}

bool type_is_i32_value(uint ty)
{
    return ty == TY_BOOL || ty == TY_INT || ty == TY_UINT;
}

bool type_is_i32_abi_value(uint ty)
{
    return type_is_i32_value(ty) || ty == TY_STRING || ty >= TY_ARRAY_BASE;
}

bool type_is_i32_abi_param(uint fn_token, uint ordinal, uint ty)
{
    return type_is_i32_abi_value(ty) ||
           (ty == TY_UNKNOWN && method_receiver_param(fn_token, ordinal));
}

uint call_param_type_value(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token)) return TY_UNKNOWN;
    uint start = call_param_row_start[fn_token];
    uint count = call_param_row_count[fn_token];
    uint limit = call_param_row_count_out[0u];
    if (start == INVALID || ordinal >= count || start > limit || ordinal > limit - start)
        return method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : TY_UNKNOWN;
    uint row = start + ordinal;
    if (row >= limit || call_param_row_fn_token[row] != fn_token ||
        call_param_row_ordinal[row] != ordinal)
    {
        return method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : TY_UNKNOWN;
    }
    uint ty = call_param_row_type[row];
    return ty == TY_UNKNOWN && method_receiver_param(fn_token, ordinal)
               ? TY_ARRAY_BASE
               : ty;
}

uint u32_leb_len(uint value)
{
    for (uint i = 0u; i < 5u; i += 1u)
    {
        value >>= 7u;
        if (value == 0u) return i + 1u;
    }
    return 5u;
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

uint u32_leb_byte(uint value, uint byte_i)
{
    uint byte_value = (value >> (byte_i * 7u)) & 0x7fu;
    return byte_i == 4u || (value >> ((byte_i + 1u) * 7u)) == 0u
               ? byte_value
               : byte_value | 0x80u;
}

uint i32_const_byte(uint value, uint byte_i)
{
    return byte_i == 0u ? WASM_I32_CONST : i32_sleb_byte(value, byte_i - 1u);
}

uint f32_const_byte(uint bits, uint byte_i)
{
    return byte_i == 0u ? 0x43u : (bits >> ((byte_i - 1u) * 8u)) & 0xffu;
}

uint local_get_byte(uint local_index, uint byte_i)
{
    return byte_i == 0u ? WASM_LOCAL_GET : u32_leb_byte(local_index, byte_i - 1u);
}

uint local_get_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
}

uint local_set_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
}

uint local_set_byte(uint local_index, uint byte_i)
{
    return byte_i == 0u ? 0x21u : u32_leb_byte(local_index, byte_i - 1u);
}

bool compact_direct_call_header(uint call, out uint4 aux)
{
    aux = uint4(INVALID, 0u, INVALID, 0u);
    if (!valid_node(call) || compact_hir_core[call].kind != HIR_CALL_EXPR)
        return false;
    uint callee = call_callee_token(call);
    if (!valid_token(callee) || call_intrinsic_tag[callee] != 0u)
        return false;
    uint fn_token = call_fn_token_for_call(call, callee);
    if (!supported_call_target_token(fn_token))
        return false;
    uint arg_count = compact_call_explicit_arg_count(call) +
                     (compact_direct_call_has_receiver_arg(call, fn_token) ? 1u : 0u);
    if (call_param_count[fn_token] != arg_count)
        return false;
    uint return_ty = call_return_type_for_call(call, callee, fn_token);
    if (!type_is_i32_value(return_ty) && return_ty != TY_FLOAT)
        return false;
    uint target = wasm_call_target_for_call(call, fn_token);
    if (target == INVALID)
        return false;
    aux = uint4(target, arg_count, fn_token, return_ty);
    return true;
}

bool compact_binary_direct_call_header(
    uint expr,
    out uint call,
    out uint other,
    out uint call_side,
    out uint4 aux)
{
    call = INVALID;
    other = INVALID;
    call_side = 0u;
    aux = uint4(INVALID, 0u, INVALID, TY_UNKNOWN);
    if (!valid_node(expr) || !expr_binary_op_supported(expr_form(expr))) return false;
    HirPayload payload = compact_hir_payload[expr];
    uint4 left_aux = uint4(INVALID, 0u, INVALID, TY_UNKNOWN);
    uint4 right_aux = uint4(INVALID, 0u, INVALID, TY_UNKNOWN);
    bool left_call = compact_direct_call_header(payload.b, left_aux);
    bool right_call = compact_direct_call_header(payload.c, right_aux);
    if (left_call == right_call) return false;
    call = left_call ? payload.b : payload.c;
    other = left_call ? payload.c : payload.b;
    call_side = right_call ? 1u : 0u;
    aux = left_call ? left_aux : right_aux;
    return valid_node(other);
}

bool compact_assign_op_supported(uint op, uint value_ty)
{
    if (op == ASSIGN_OP_SET) return true;
    if (value_ty == TY_FLOAT)
        return op == ASSIGN_OP_ADD || op == ASSIGN_OP_SUB ||
               op == ASSIGN_OP_MUL || op == ASSIGN_OP_DIV;
    return type_is_i32_value(value_ty) &&
           (op == ASSIGN_OP_ADD || op == ASSIGN_OP_SUB ||
            op == ASSIGN_OP_MUL || op == ASSIGN_OP_DIV ||
            op == ASSIGN_OP_MOD);
}

uint compact_assign_op_byte(uint op, uint value_ty)
{
    if (value_ty == TY_FLOAT)
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

uint local_decl_count_for_function_token(uint fn_token)
{
    if (!valid_token(fn_token)) return 0u;
    uint max_token = wasm_func_local_max_by_token[fn_token];
    return max_token == INVALID ? 0u : max_token + 1u;
}

uint wasm_value_abi_width(uint ty)
{
    return ty == TY_STRING ? 2u : 1u;
}

uint function_param_abi_count(uint fn_token)
{
    if (!valid_token(fn_token)) return 0u;
    uint total = 0u;
    for (uint ordinal = 0u; ordinal < call_param_count[fn_token]; ordinal += 1u)
        total += wasm_value_abi_width(call_param_type_value(fn_token, ordinal));
    return total;
}

uint function_param_abi_ordinal(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token) || ordinal >= call_param_count[fn_token]) return INVALID;
    uint local = 0u;
    for (uint i = 0u; i < ordinal; i += 1u)
        local += wasm_value_abi_width(call_param_type_value(fn_token, i));
    return local;
}

uint expr_literal_scalar_type(uint node)
{
    uint form = expr_form(node);
    if (form == HIR_EXPR_FLOAT) return TY_FLOAT;
    if (form == HIR_EXPR_INT || form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_INT;
    return TY_UNKNOWN;
}

uint local_decl_type(uint decl_token)
{
    uint ty = visible_type_for_token(decl_token);
    if (ty != TY_UNKNOWN) return ty;
    uint init = valid_token(decl_token) ? body_let_init_hir_by_decl_token[decl_token] : INVALID;
    uint root = valid_node(init) ? compact_expr_root[init] : INVALID;
    ty = expr_literal_scalar_type(valid_node(root) ? root : init);
    return ty == TY_UNKNOWN ? TY_INT : ty;
}

bool function_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token)) return false;
    uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
    if (ordinal == INVALID || ordinal >= call_param_count[fn_token]) return false;
    local_index = function_param_abi_ordinal(fn_token, ordinal);
    return local_index != INVALID;
}

bool function_non_param_local_index_for_type(
    uint decl_token, uint fn_token, uint local_ty, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token)) return false;
    local_index = function_param_abi_count(fn_token) + decl_token;
    if (local_ty == TY_FLOAT)
        local_index += local_decl_count_for_function_token(fn_token) * 2u;
    return true;
}

bool function_non_param_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    return function_non_param_local_index_for_type(
        decl_token, fn_token, local_decl_type(decl_token), local_index);
}

bool function_decl_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    return function_param_local_index(decl_token, fn_token, local_index) ||
           function_non_param_local_index(decl_token, fn_token, local_index);
}

bool function_string_len_local_index(uint decl_token, uint fn_token, out uint local_index)
{
    local_index = INVALID;
    if (!valid_token(decl_token) || !valid_token(fn_token)) return false;
    uint ordinal = wasm_func_param_ordinal_by_decl_token[decl_token];
    if (ordinal != INVALID && ordinal < call_param_count[fn_token])
    {
        if (call_param_type_value(fn_token, ordinal) != TY_STRING) return false;
        uint ptr = function_param_abi_ordinal(fn_token, ordinal);
        if (ptr == INVALID) return false;
        local_index = ptr + 1u;
        return true;
    }
    if (local_decl_type(decl_token) != TY_STRING) return false;
    local_index = function_param_abi_count(fn_token) +
                  local_decl_count_for_function_token(fn_token) + decl_token;
    return true;
}

bool let_initializer_for_decl_token(uint decl_token, out uint init)
{
    init = valid_token(decl_token) ? body_let_init_hir_by_decl_token[decl_token] : INVALID;
    return valid_node(init);
}

bool local_decl_token_for_name_expr(uint node, out uint local_index)
{
    local_index = INVALID;
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME) return false;
    uint name = compact_hir_payload[node].d;
    uint decl = valid_token(name) ? visible_decl[name] : INVALID;
    if (!valid_token(decl)) return false;
    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn)) return false;
    if (function_param_local_index(decl, owner_fn, local_index)) return true;
    uint init = INVALID;
    if (let_initializer_for_decl_token(decl, init))
        return function_non_param_local_index(decl, owner_fn, local_index);
    uint encoded_fn = enclosing_fn[decl];
    return encoded_fn != 0u && encoded_fn - 1u == owner_fn &&
           function_non_param_local_index(decl, owner_fn, local_index);
}

bool name_const_record_value(uint node, out uint value)
{
    value = 0u;
    uint name = valid_node(node) ? compact_hir_payload[node].d : INVALID;
    uint decl = valid_token(name) ? visible_decl[name] : INVALID;
    if (!valid_token(decl)) return false;
    uint2 record = wasm_const_value_record[decl];
    if (record.x != WASM_CONST_VALUE_LITERAL) return false;
    value = record.y;
    return true;
}

bool expr_binary_op_supported(uint form)
{
    return (form >= HIR_EXPR_EQ && form <= HIR_EXPR_GE) ||
           (form >= HIR_EXPR_ADD && form <= HIR_EXPR_SHR);
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

uint expr_binary_op_byte_for_node(uint node)
{
    if (!valid_node(node)) return 0u;
    HirPayload payload = compact_hir_payload[node];
    uint form = payload.a;
    uint numeric_ty = compact_expr_numeric_operand_type(node);
    if (numeric_ty == TY_FLOAT)
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
    if (numeric_ty == TY_UINT)
    {
        if (form == HIR_EXPR_LT) return WASM_I32_LT_U;
        if (form == HIR_EXPR_GT) return WASM_I32_GT_U;
        if (form == HIR_EXPR_LE) return WASM_I32_LE_U;
        if (form == HIR_EXPR_GE) return WASM_I32_GE_U;
        if (form == HIR_EXPR_DIV) return WASM_I32_DIV_U;
        if (form == HIR_EXPR_MOD) return WASM_I32_REM_U;
        if (form == HIR_EXPR_SHR) return WASM_I32_SHR_U;
    }
    return expr_binary_op_byte(form);
}

uint compact_expr_scalar_type_for_node(uint node)
{
    if (!valid_node(node)) return TY_UNKNOWN;
    return compact_expr_scalar_type[node] >> 28u;
}

uint compact_expr_numeric_operand_type(uint node)
{
    if (!valid_node(node)) return TY_UNKNOWN;
    uint form = expr_form(node);
    if (form >= HIR_EXPR_EQ && form <= HIR_EXPR_GE)
        return compact_expr_scalar_type_for_node(compact_hir_payload[node].b);
    return compact_expr_scalar_type_for_node(node);
}

bool expr_atom_is_f32(uint node)
{
    if (!valid_node(node)) return false;
    uint form = expr_form(node);
    if (form == HIR_EXPR_FLOAT) return true;
    if (form == HIR_EXPR_NAME)
        return visible_type_for_token(compact_hir_payload[node].d) == TY_FLOAT;
    if (compact_hir_core[node].kind == HIR_MEMBER_EXPR)
        return visible_type_for_token(compact_hir_payload[node].c) == TY_FLOAT;
    return false;
}

bool expr_neg_is_f32(uint node)
{
    return valid_node(node) && expr_form(node) == HIR_EXPR_NEG &&
           compact_expr_scalar_type_for_node(node) == TY_FLOAT;
}

uint align4(uint value)
{
    return (value + 3u) & ~3u;
}

uint aggregate_data_base()
{
    // This is a module-memory layout address, not a compact-HIR storage
    // offset. Until the Wasm data section itself moves to the compact string
    // pool, aggregate storage follows the shared backend contract and begins
    // after the source-sized data region.
    return align4((gParams.n_tokens + 1u) * 4u + gParams.source_len);
}

uint agg_local_base_slots(uint decl_token)
{
    uint block = decl_token / 256u;
    uint prior = block == 0u ? 0u : wasm_agg_local_block_prefix[block - 1u];
    return prior + wasm_agg_local_base_by_token[decl_token];
}

bool aggregate_name_address_expr_plan(
    uint node, out uint opcode, out uint operand, out uint len)
{
    opcode = 0u; operand = 0u; len = 0u;
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME) return false;
    uint name = compact_hir_payload[node].d;
    uint decl = valid_token(name) ? visible_decl[name] : INVALID;
    if (!valid_token(decl)) return false;
    uint owner_fn = node_enclosing_fn_token(node);
    uint local = INVALID;
    bool is_param = function_param_local_index(decl, owner_fn, local);
    if (!is_param && valid_token(owner_fn))
    {
        uint ordinal = wasm_func_param_ordinal_by_decl_token[decl];
        if (ordinal != INVALID)
        {
            local = function_param_abi_ordinal(owner_fn, ordinal);
            is_param = local != INVALID;
        }
    }
    if (is_param)
    {
        uint decl_ty = visible_type_for_token(decl);
        uint ordinal = wasm_func_param_ordinal_by_decl_token[decl];
        uint param_ty = call_param_type_value(owner_fn, ordinal);
        if (decl_ty != TY_UNKNOWN && decl_ty < TY_ARRAY_BASE &&
            param_ty < TY_ARRAY_BASE && method_decl_param_offset[owner_fn] != decl)
            return false;
        opcode = WASM_LOCAL_GET; operand = local; len = local_get_len(local);
        return true;
    }
    if (wasm_agg_local_width_by_token[decl] != 0u)
    {
        operand = aggregate_data_base() + agg_local_base_slots(decl) * 4u;
        opcode = WASM_I32_CONST; len = 1u + i32_sleb_len(operand);
        return true;
    }
    if (visible_type_for_token(decl) >= TY_ARRAY_BASE &&
        function_non_param_local_index_for_type(decl, owner_fn, TY_INT, local))
    {
        opcode = WASM_LOCAL_GET; operand = local; len = local_get_len(local);
        return true;
    }
    return false;
}

uint aggregate_name_address_expr_byte(uint node, uint byte_i)
{
    uint opcode = 0u;
    uint operand = 0u;
    uint len = 0u;
    if (!aggregate_name_address_expr_plan(node, opcode, operand, len) || byte_i >= len)
        return 0u;
    return opcode == WASM_LOCAL_GET
               ? local_get_byte(operand, byte_i)
               : i32_const_byte(operand, byte_i);
}

bool aggregate_member_address_and_len(uint node, out uint address, out uint len)
{
    address = 0u; len = 0u;
    if (!valid_node(node) || compact_hir_core[node].kind != HIR_MEMBER_EXPR) return false;
    uint member = compact_hir_payload[node].c;
    if (!valid_token(member) || member_result_field_index[member] == INVALID) return false;
    uint2 total = expr_subtree_total[node];
    if (total.y != 0u || total.x == 0u) return false;
    len = total.x;
    return true;
}

bool expr_non_call_atom_and_len(uint node, out uint len)
{
    len = 0u;
    if (!valid_node(node)) return false;
    uint form = expr_form(node);
    uint local = INVALID;
    uint name_token = form == HIR_EXPR_NAME ? compact_hir_payload[node].d : INVALID;
    if (form == HIR_EXPR_NAME && visible_type_for_token(name_token) != TY_STRING &&
        local_decl_token_for_name_expr(node, local))
    {
        len = local_get_len(local);
        return true;
    }
    uint address = 0u;
    if (aggregate_member_address_and_len(node, address, len)) return true;
    uint value = 0u;
    if (form == HIR_EXPR_INT || form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE ||
        (form == HIR_EXPR_NAME && name_const_record_value(node, value)))
    {
        if (form == HIR_EXPR_INT) value = compact_hir_payload[node].b;
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

uint expr_non_call_atom_byte(uint node, uint byte_i)
{
    if (!valid_node(node)) return 0u;
    uint form = expr_form(node);
    uint local = INVALID;
    uint name_token = form == HIR_EXPR_NAME ? compact_hir_payload[node].d : INVALID;
    if (form == HIR_EXPR_NAME && visible_type_for_token(name_token) != TY_STRING &&
        local_decl_token_for_name_expr(node, local))
        return local_get_byte(local, byte_i);
    uint value = 0u;
    if (form == HIR_EXPR_NAME && name_const_record_value(node, value))
        return i32_const_byte(value, byte_i);
    if (form == HIR_EXPR_INT)
        return i32_const_byte(compact_hir_payload[node].b, byte_i);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return i32_const_byte(form == HIR_EXPR_TRUE ? 1u : 0u, byte_i);
    if (form == HIR_EXPR_FLOAT)
        return f32_const_byte(compact_hir_payload[node].b, byte_i);
    return 0u;
}

bool string_literal_ptr_len(uint node, out uint ptr, out uint len)
{
    ptr = 0u; len = 0u;
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_STRING) return false;
    uint row = compact_hir_payload[node].b;
    uint count = min(compact_string_count[0u], active_hir_node_count());
    if (row >= count) return false;
    HirString string_row = compact_strings[row];
    uint pool_len = compact_string_pool_len[0u];
    if (string_row.node != node || string_row.data_offset > pool_len ||
        string_row.decoded_len > pool_len - string_row.data_offset)
        return false;
    ptr = (gParams.n_tokens + 1u) * 4u + string_row.data_offset;
    len = string_row.decoded_len;
    return true;
}

bool string_value_expr_and_len(uint node, out uint len)
{
    len = 0u;
    uint ptr = 0u; uint string_len = 0u;
    if (string_literal_ptr_len(node, ptr, string_len))
    {
        len = 1u + i32_sleb_len(ptr) + 1u + i32_sleb_len(string_len);
        return true;
    }
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME) return false;
    uint name = compact_hir_payload[node].d;
    uint decl = valid_token(name) ? visible_decl[name] : INVALID;
    uint owner_fn = node_enclosing_fn_token(node);
    uint ptr_local = INVALID; uint len_local = INVALID;
    if (!valid_token(decl) || visible_type_for_token(decl) != TY_STRING ||
        !function_decl_local_index(decl, owner_fn, ptr_local) ||
        !function_string_len_local_index(decl, owner_fn, len_local))
        return false;
    len = local_get_len(ptr_local) + local_get_len(len_local);
    return true;
}

uint string_value_expr_byte(uint node, uint byte_i)
{
    uint ptr = 0u; uint string_len = 0u;
    if (string_literal_ptr_len(node, ptr, string_len))
    {
        uint ptr_len = 1u + i32_sleb_len(ptr);
        return byte_i < ptr_len
                   ? i32_const_byte(ptr, byte_i)
                   : i32_const_byte(string_len, byte_i - ptr_len);
    }
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME) return 0u;
    uint name = compact_hir_payload[node].d;
    uint decl = valid_token(name) ? visible_decl[name] : INVALID;
    uint owner_fn = node_enclosing_fn_token(node);
    uint ptr_local = INVALID; uint len_local = INVALID;
    if (!function_decl_local_index(decl, owner_fn, ptr_local) ||
        !function_string_len_local_index(decl, owner_fn, len_local))
        return 0u;
    uint ptr_len = local_get_len(ptr_local);
    return byte_i < ptr_len
               ? local_get_byte(ptr_local, byte_i)
               : local_get_byte(len_local, byte_i - ptr_len);
}
