// Parallel pre-validation collection for facts fragment validation must read.
//
// Function discovery owns function counting and reachability. This pass runs
// after that discovery and before fragment validation so statement lanes can
// read completed per-function local bounds when computing typed WASM locals.

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

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirCallArg { uint call; uint value; uint ordinal; uint file_id; };
struct HirPath { uint owner; uint segment_start; uint segment_count; uint kind; };
struct HirPathSegment { uint path; uint name_token; uint ordinal; uint file_id; };

StructuredBuffer<uint> status;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_expr_root;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<HirPath> compact_paths;
StructuredBuffer<uint> compact_path_segment_count;
StructuredBuffer<HirPathSegment> compact_path_segments;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> wasm_agg_local_width_by_token;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_decl;
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
RWStructuredBuffer<uint> wasm_func_flag;
RWStructuredBuffer<uint> wasm_func_slot_by_token;
RWStructuredBuffer<uint> wasm_func_local_max_by_token;
RWStructuredBuffer<uint> wasm_func_invalid_count_by_token;
RWStructuredBuffer<uint> wasm_func_detail_by_token;

static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint INVALID = 0xffffffffu;
static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;
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
static const uint BODY_FEATURE_EXPR_CONTROL = 1u << 0u;
static const uint BODY_FEATURE_DIRECT = 1u << 1u;
static const uint BODY_FEATURE_HOST = 1u << 2u;
static const uint BODY_FEATURE_ARRAYS = 1u << 3u;
static const uint BODY_FEATURE_MEMBER_EXPR = 1u << 4u;
static const uint BODY_FEATURE_BINARY_DIRECT = 1u << 5u;
static const uint BODY_FEATURE_LET_DIRECT = 1u << 6u;
static const uint BODY_FEATURE_RETURN_DIRECT = 1u << 8u;
static const uint BODY_FEATURE_LET_AGG_DIRECT = 1u << 9u;
static const uint BODY_FEATURE_RETURN_AGG_DIRECT = 1u << 10u;
static const uint BODY_FEATURE_AGG_COPY = 1u << 11u;
static const uint BODY_FEATURE_ARRAY_ALLOC = 1u << 12u;
static const uint BODY_FEATURE_ASSIGN = 1u << 13u;
static const uint BODY_FEATURE_CONTROL = 1u << 14u;
static const uint BODY_FEATURE_STMT_CALL = 1u << 15u;
static const uint BODY_FEATURE_HOST_BASIC = 1u << 16u;
static const uint BODY_FEATURE_HOST_ENV = 1u << 17u;
static const uint BODY_FEATURE_HOST_IO = 1u << 18u;
static const uint BODY_FEATURE_HOST_VOID = 1u << 19u;
static const uint BODY_FEATURE_STMT_PRINT = 1u << 20u;
static const uint BODY_FEATURE_STMT_HOST_VOID = 1u << 21u;
static const uint BODY_FEATURE_STMT_PRINT_DIRECT = 1u << 22u;
static const uint BODY_FEATURE_HOST_IO_I32 = 1u << 24u;
static const uint BODY_FEATURE_HOST_IO_STRING = 1u << 25u;
static const uint BODY_FEATURE_HOST_IO_RETURN = 1u << 26u;
static const uint BODY_FEATURE_RETURN_MEMBER_EXPR = 1u << 29u;
static const uint BODY_FEATURE_MEMBER_EXPR_SCATTER = 1u << 30u;
static const uint LANGUAGE_SYMBOL_READ_I32 = 22u;
static const uint LANGUAGE_SYMBOL_OPEN_READ_PATH = 20u;
static const uint LANGUAGE_SYMBOL_OPEN_WRITE_PATH = 21u;
static const uint LANGUAGE_SYMBOL_WRITE_TEXT = 23u;
static const uint LANGUAGE_SYMBOL_WRITE_I32 = 24u;
static const uint LANGUAGE_SYMBOL_WRITE_BYTE = 25u;
static const uint LANGUAGE_SYMBOL_WRITE_NEWLINE = 26u;
static const uint LANGUAGE_SYMBOL_CLOSE_FILE = 27u;
static const uint LANGUAGE_SYMBOL_EXIT = 29u;
static const uint LANGUAGE_SYMBOL_I32_TO_F32 = 28u;
static const uint LANGUAGE_SYMBOL_SECURE_U32 = 30u;
static const uint LANGUAGE_SYMBOL_ALLOC = 31u;
static const uint LANGUAGE_SYMBOL_DEALLOC = 32u;
static const uint LANGUAGE_SYMBOL_ARGC = 33u;
static const uint LANGUAGE_SYMBOL_ARG_LEN = 34u;
static const uint LANGUAGE_SYMBOL_ARG_READ = 35u;
static const uint LANGUAGE_SYMBOL_UNIX_SECONDS = 36u;
static const uint LANGUAGE_SYMBOL_CURRENT_DIR_READ = 37u;
static const uint LANGUAGE_SYMBOL_VAR_COUNT = 38u;
static const uint LANGUAGE_SYMBOL_VAR_KEY_LEN = 39u;
static const uint LANGUAGE_SYMBOL_VAR_KEY_READ = 40u;
static const uint LANGUAGE_SYMBOL_VAR_LEN = 41u;
static const uint LANGUAGE_SYMBOL_VAR_READ = 42u;
static const uint LANGUAGE_SYMBOL_CLOSE = 43u;
static const uint LANGUAGE_SYMBOL_READ = 44u;
static const uint LANGUAGE_SYMBOL_WRITE = 45u;
static const uint LANGUAGE_SYMBOL_OPEN_READ = 46u;
static const uint LANGUAGE_SYMBOL_OPEN_WRITE = 47u;
static const uint LANGUAGE_SYMBOL_OPEN_APPEND = 48u;
static const uint LANGUAGE_SYMBOL_WRITE_STDOUT = 49u;
static const uint LANGUAGE_SYMBOL_WRITE_STDERR = 50u;
static const uint LANGUAGE_SYMBOL_READ_STDIN = 51u;
static const uint LANGUAGE_SYMBOL_I32_ARRAY_DATA_PTR = 52u;
static const uint LANGUAGE_SYMBOL_FILL_SECURE_BYTES = 53u;
static const uint LANGUAGE_SYMBOL_REMOVE_FILE = 54u;
static const uint LANGUAGE_SYMBOL_CREATE_DIR = 55u;
static const uint LANGUAGE_SYMBOL_REMOVE_DIR = 56u;
static const uint LANGUAGE_SYMBOL_RENAME = 57u;
static const uint LANGUAGE_SYMBOL_MONOTONIC_READ = 58u;
static const uint LANGUAGE_SYMBOL_SYSTEM_READ = 59u;
static const uint LANGUAGE_SYMBOL_SLEEP_MS_I32 = 60u;
static const uint LANGUAGE_SYMBOL_REALLOC = 61u;
static const uint LANGUAGE_SYMBOL_ALLOC_FAILED = 62u;
static const uint INTRINSIC_TEXT_WRITE = 1u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_EXPR = 14u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_PATH_EXPR = 33u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_NONE = 0u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint STMT_RECORD_KIND_ASSIGN = 5u;
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
static const uint MAX_PATH_SEGMENTS = 9u;
static const uint HIR_CALL_CONTEXT_STMT_BIT = 0x80000000u;
static const uint HIR_CALL_CONTEXT_ID_MASK = 0x7fffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

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

bool token_has_language_name(uint token, uint symbol)
{
    if (!valid_token(token) || symbol >= 64u)
        return false;
    uint language_id = language_name_id[symbol];
    return language_id != INVALID && name_id_by_token[token] == language_id;
}

uint stmt_record_slot(uint node, uint slot)
{
    if (!valid_node(node) || slot >= 4u)
        return INVALID;
    HirPayload payload = compact_hir_payload[node];
    if (slot == 0u) return payload.a;
    if (slot == 1u) return payload.b;
    if (slot == 2u) return payload.c;
    return payload.d;
}

uint expr_record_slot(uint node, uint slot)
{
    return stmt_record_slot(node, slot);
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_FORM) : HIR_EXPR_NONE;
}

uint resolve_expr_node(uint node)
{
    return valid_node(node) ? node : INVALID;
}

uint active_path_count()
{
    return min(compact_path_count[0u], gParams.n_hir_nodes);
}

uint active_path_segment_count()
{
    return min(compact_path_segment_count[0u], gParams.n_tokens);
}

bool valid_path(uint path_i)
{
    return path_i != INVALID && path_i < active_path_count();
}

uint path_node_for_callee(uint callee_node)
{
    if (!valid_node(callee_node))
        return INVALID;
    if (compact_hir_core[callee_node].kind == HIR_PATH_EXPR)
        return callee_node;
    if (compact_hir_core[callee_node].kind != HIR_NAME_EXPR)
        return INVALID;
    uint child = compact_hir_links[callee_node].first_child;
    return valid_node(child) && compact_hir_core[child].kind == HIR_PATH_EXPR
        ? child
        : INVALID;
}

uint path_leaf_token_for_callee(uint callee_node)
{
    uint path_node = path_node_for_callee(callee_node);
    if (!valid_node(path_node))
        return INVALID;

    uint path_i = path_id_by_owner_hir[path_node];
    if (!valid_path(path_i))
        return INVALID;

    HirPath path = compact_paths[path_i];
    uint count = min(path.segment_count, MAX_PATH_SEGMENTS);
    if (path.owner != path_node || count == 0u || path.segment_start == INVALID)
        return INVALID;

    uint slot = path.segment_start + count - 1u;
    if (slot < path.segment_start || slot >= active_path_segment_count())
        return INVALID;

    HirPathSegment segment = compact_path_segments[slot];
    return segment.path == path_i && valid_token(segment.name_token)
        ? segment.name_token
        : INVALID;
}

uint node_enclosing_fn_token(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint token = compact_hir_core[node].token_start;
    if (!valid_token(token))
        return INVALID;
    uint encoded_fn = enclosing_fn[token];
    return encoded_fn == 0u ? INVALID : encoded_fn - 1u;
}

uint call_callee_token(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = compact_hir_payload[call_node].a;
    uint path_leaf = path_leaf_token_for_callee(callee_node);
    if (valid_token(path_leaf))
        return path_leaf;

    if (!valid_node(callee_node))
        return INVALID;
    if (compact_hir_core[callee_node].kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[callee_node].c;
        return valid_token(member_token) ? member_token : INVALID;
    }
    uint callee_token = expr_record_slot(callee_node, EXPR_RECORD_VALUE_TOKEN);
    if (!valid_token(callee_token))
        callee_token = compact_hir_core[callee_node].token_start;
    return valid_token(callee_token) ? callee_token : INVALID;
}

uint call_site_token(uint call_node)
{
    return valid_node(call_node) ? compact_hir_core[call_node].token_start : INVALID;
}

uint semantic_callee_token_for_call(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = call_site_token(call_node);
    uint callee_node = compact_hir_payload[call_node].a;
    if (!valid_node(callee_node))
        return valid_token(call_token) ? call_token : INVALID;

    if (compact_hir_core[callee_node].kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[callee_node].c;
        return valid_token(member_token) ? member_token : INVALID;
    }

    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    uint callee_token = expr_record_slot(callee_node, EXPR_RECORD_VALUE_TOKEN);
    if (!valid_token(callee_token))
        callee_token = compact_hir_core[callee_node].token_start;
    if (!valid_token(callee_token))
        callee_token = call_token;
    return valid_token(callee_token) ? callee_token : INVALID;
}

uint call_metadata_token(uint call_node, uint callee_token)
{
    uint site_token = call_site_token(call_node);
    uint semantic_token = semantic_callee_token_for_call(call_node);

    if (valid_token(site_token) && call_dependency_decl[site_token] != INVALID)
        return site_token;
    if (valid_token(semantic_token) && call_dependency_decl[semantic_token] != INVALID)
        return semantic_token;
    if (valid_token(callee_token) && call_dependency_decl[callee_token] != INVALID)
        return callee_token;

    if (valid_token(site_token) && valid_token(call_fn_index[site_token]))
        return site_token;

    if (valid_token(semantic_token) && valid_token(call_fn_index[semantic_token]))
        return semantic_token;

    if (valid_token(callee_token) && valid_token(call_fn_index[callee_token]))
        return callee_token;

    return callee_token;
}

uint call_fn_token_for_call(uint call_node, uint callee_token)
{
    uint metadata_token = call_metadata_token(call_node, callee_token);
    if (!valid_token(metadata_token))
        return INVALID;
    if (call_dependency_decl[metadata_token] != INVALID)
        return metadata_token;
    uint local_fn = call_fn_index[metadata_token];
    return valid_token(local_fn) ? local_fn : INVALID;
}

bool dependency_call_token(uint token)
{
    return valid_token(token) && call_dependency_decl[token] != INVALID;
}

bool statement_position_call(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return false;
    return (compact_hir_payload[call_node].d & HIR_CALL_CONTEXT_STMT_BIT) != 0u;
}

uint call_context_node(uint call_node)
{
    if (!valid_node(call_node))
        return INVALID;
    uint context = compact_hir_payload[call_node].d & HIR_CALL_CONTEXT_ID_MASK;
    return valid_node(context) ? context : INVALID;
}

bool print_call_node(uint call_node)
{
    uint callee_token = call_callee_token(call_node);
    return valid_token(callee_token) &&
           statement_position_call(call_node) &&
           call_intrinsic_tag[callee_token] == INTRINSIC_TEXT_WRITE &&
           compact_hir_payload[call_node].c == 1u;
}

uint call_arg0_node(uint call_node)
{
    if (!print_call_node(call_node))
        return INVALID;

    uint row = compact_hir_payload[call_node].b;
    uint count = min(compact_call_arg_count[0u], gParams.n_hir_nodes);
    if (row < count)
    {
        HirCallArg arg = compact_call_args[row];
        if (arg.call == call_node && arg.ordinal == 0u && valid_node(arg.value))
            return arg.value;
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

bool method_receiver_param(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token) || ordinal != 0u)
        return false;
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
    return type_is_i32_abi_value(ty) || (ty == TY_UNKNOWN && method_receiver_param(fn_token, ordinal));
}

bool supported_function_token(uint fn_token)
{
    return valid_token(fn_token) &&
           wasm_func_flag[fn_token] != 0u &&
           wasm_func_slot_by_token[fn_token] != INVALID;
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

bool expr_contains_member(uint node)
{
    return valid_node(node) &&
           compact_hir_core[node].kind == HIR_MEMBER_EXPR &&
           valid_token(compact_hir_payload[node].c);
}

bool token_has_host_language_name(uint token)
{
    if (!valid_token(token))
        return false;

    uint name_id = name_id_by_token[token];
    for (uint symbol = LANGUAGE_SYMBOL_OPEN_READ_PATH; symbol <= LANGUAGE_SYMBOL_ALLOC_FAILED; symbol += 1u)
    {
        if (symbol == 28u)
            continue;
        uint language_id = language_name_id[symbol];
        if (language_id != INVALID && language_id == name_id)
            return true;
    }
    return false;
}

uint host_token_feature_mask(uint token)
{
    if (!valid_token(token))
        return 0u;

    if (token_has_language_name(token, LANGUAGE_SYMBOL_OPEN_READ_PATH) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_OPEN_WRITE_PATH) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_WRITE_TEXT))
    {
        return BODY_FEATURE_HOST_IO | BODY_FEATURE_HOST_IO_STRING;
    }

    if (token_has_language_name(token, LANGUAGE_SYMBOL_READ_I32) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_WRITE_TEXT) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_WRITE_I32) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_WRITE_BYTE) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_WRITE_NEWLINE) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_CLOSE_FILE) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_CLOSE) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_READ) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_WRITE) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_OPEN_READ) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_OPEN_WRITE) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_OPEN_APPEND) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_WRITE_STDERR) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_READ_STDIN) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_FILL_SECURE_BYTES) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_REMOVE_FILE) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_CREATE_DIR) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_REMOVE_DIR) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_RENAME) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_MONOTONIC_READ) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_SYSTEM_READ) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_SLEEP_MS_I32) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_REALLOC) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_EXIT) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_ALLOC_FAILED))
    {
        return BODY_FEATURE_HOST_IO | BODY_FEATURE_HOST_IO_I32;
    }

    if (token_has_language_name(token, LANGUAGE_SYMBOL_ALLOC) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_CURRENT_DIR_READ) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_VAR_COUNT) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_VAR_KEY_LEN) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_VAR_KEY_READ) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_VAR_LEN) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_VAR_READ))
    {
        return BODY_FEATURE_HOST_ENV;
    }

    if (token_has_language_name(token, LANGUAGE_SYMBOL_WRITE_STDOUT) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_I32_ARRAY_DATA_PTR) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_ARGC) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_ARG_LEN) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_ARG_READ) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_SECURE_U32) ||
        token_has_language_name(token, LANGUAGE_SYMBOL_UNIX_SECONDS))
    {
        return BODY_FEATURE_HOST_BASIC;
    }

    return 0u;
}

uint host_call_feature_mask(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return 0u;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return 0u;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    uint mask = host_token_feature_mask(callee_token);
    if (valid_token(fn_token))
        mask |= host_token_feature_mask(fn_token);
    return mask;
}

bool known_host_call_node(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!valid_token(fn_token))
        fn_token = callee_token;

    return token_has_host_language_name(callee_token) ||
           token_has_host_language_name(fn_token);
}

bool host_void_call_node_for_symbol(uint call_node, uint language_symbol)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    return token_has_language_name(callee_token, language_symbol) ||
           token_has_language_name(fn_token, language_symbol);
}

bool i32_to_f32_call_node(uint call_node)
{
    if (!valid_node(call_node) ||
        compact_hir_core[call_node].kind != HIR_CALL_EXPR ||
        compact_hir_payload[call_node].c != 1u)
    {
        return false;
    }

    uint callee_token = call_callee_token(call_node);
    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    return token_has_language_name(callee_token, LANGUAGE_SYMBOL_I32_TO_F32) ||
           token_has_language_name(fn_token, LANGUAGE_SYMBOL_I32_TO_F32);
}

bool print_call_requires_expr_control(uint call_node)
{
    uint arg0 = resolve_expr_node(call_arg0_node(call_node));
    if (!valid_node(arg0) || compact_hir_core[arg0].kind == HIR_CALL_EXPR)
        return false;

    uint form = expr_form(arg0);
    if (form == HIR_EXPR_INT ||
        form == HIR_EXPR_TRUE ||
        form == HIR_EXPR_FALSE ||
        form == HIR_EXPR_NAME)
    {
        return false;
    }

    return form == HIR_EXPR_NOT ||
           form == HIR_EXPR_NEG ||
           expr_binary_form(form);
}

bool potential_user_call_node(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token) || call_intrinsic_tag[callee_token] != 0u)
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    return supported_function_token(fn_token) || dependency_call_token(fn_token);
}

bool call_is_left_operand_of_let_binary_expr(uint call_node, uint context)
{
    if (!valid_node(call_node) ||
        !valid_node(context) ||
        stmt_record_slot(context, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    uint init_expr = resolve_expr_node(stmt_record_slot(context, 2u));
    if (!valid_node(init_expr) || !expr_binary_form(expr_form(init_expr)))
        return false;

    uint left = resolve_expr_node(expr_record_slot(init_expr, EXPR_RECORD_LEFT));
    return left == call_node;
}

uint collect_feature_mask(uint node)
{
    if (!valid_node(node))
        return 0u;

    uint kind = compact_hir_core[node].kind;
    if (kind == HIR_ARRAY_EXPR)
        return BODY_FEATURE_ARRAY_ALLOC | BODY_FEATURE_MEMBER_EXPR;
    if (kind == HIR_STRUCT_LITERAL_EXPR)
        return BODY_FEATURE_ARRAY_ALLOC | BODY_FEATURE_MEMBER_EXPR;
    if (kind == HIR_MEMBER_EXPR)
    {
        uint mask = BODY_FEATURE_MEMBER_EXPR;
        uint root = compact_expr_root[node];
        uint owner = valid_node(root) ? compact_hir_core[root].parent : INVALID;
        uint owner_stmt = valid_node(owner) ? stmt_record_slot(owner, 0u) : STMT_RECORD_KIND_NONE;
        if (owner_stmt == STMT_RECORD_KIND_LET)
            mask |= BODY_FEATURE_MEMBER_EXPR_SCATTER;
        else if (owner_stmt == STMT_RECORD_KIND_RETURN && root == node)
            mask |= BODY_FEATURE_RETURN_MEMBER_EXPR;
        return mask;
    }
    if (kind == HIR_IF_STMT)
        // The always-dispatched scalar validator sizes every IF condition from
        // the parallel expression forest. It publishes the expression-scatter
        // feature after validation, so feature collection does not need to
        // walk the condition or classify it as simple/call-containing here.
        return 0u;
    if (kind == HIR_WHILE_STMT || kind == HIR_FOR_STMT)
        return BODY_FEATURE_EXPR_CONTROL | BODY_FEATURE_CONTROL;
    if (kind == HIR_STMT && stmt_record_slot(node, 0u) == STMT_RECORD_KIND_ASSIGN)
        return BODY_FEATURE_EXPR_CONTROL | BODY_FEATURE_ASSIGN;

    if (kind == HIR_CALL_EXPR)
    {
        uint mask = 0u;
        if (i32_to_f32_call_node(node))
            mask |= BODY_FEATURE_EXPR_CONTROL | BODY_FEATURE_MEMBER_EXPR_SCATTER;
        if (statement_position_call(node))
        {
            if (print_call_node(node))
            {
                uint arg0 = resolve_expr_node(call_arg0_node(node));
                if (valid_node(arg0) && compact_hir_core[arg0].kind == HIR_CALL_EXPR)
                    mask |= BODY_FEATURE_STMT_PRINT_DIRECT;
                else
                {
                    mask |= BODY_FEATURE_STMT_PRINT;
                    if (print_call_requires_expr_control(node))
                        mask |= BODY_FEATURE_EXPR_CONTROL;
                }
            }
            if (host_void_call_node_for_symbol(node, LANGUAGE_SYMBOL_DEALLOC) ||
                host_void_call_node_for_symbol(node, LANGUAGE_SYMBOL_EXIT) ||
                host_void_call_node_for_symbol(node, LANGUAGE_SYMBOL_ALLOC_FAILED))
                mask |= BODY_FEATURE_STMT_HOST_VOID | BODY_FEATURE_HOST_VOID;
            if ((mask & (BODY_FEATURE_STMT_PRINT | BODY_FEATURE_STMT_PRINT_DIRECT | BODY_FEATURE_STMT_HOST_VOID)) != 0u)
                mask |= BODY_FEATURE_STMT_CALL;
        }
        if (print_call_node(node) && print_call_requires_expr_control(node))
            mask |= BODY_FEATURE_EXPR_CONTROL;
        if (potential_user_call_node(node))
        {
            uint context = call_context_node(node);
            uint context_stmt_kind = valid_node(context) ? stmt_record_slot(context, 0u) : STMT_RECORD_KIND_NONE;
            if (context_stmt_kind == STMT_RECORD_KIND_LET)
            {
                uint decl_token = stmt_record_slot(context, 1u);
                bool aggregate_target =
                    valid_token(decl_token) &&
                    (visible_type_for_token(decl_token) >= TY_ARRAY_BASE ||
                     wasm_agg_local_width_by_token[decl_token] != 0u);
                if (!aggregate_target && call_is_left_operand_of_let_binary_expr(node, context))
                    mask |= BODY_FEATURE_EXPR_CONTROL | BODY_FEATURE_BINARY_DIRECT;
                mask |= aggregate_target
                            ? (BODY_FEATURE_LET_AGG_DIRECT |
                               BODY_FEATURE_AGG_COPY |
                               BODY_FEATURE_ARRAY_ALLOC)
                            : BODY_FEATURE_LET_DIRECT;
            }
            else if (context_stmt_kind == STMT_RECORD_KIND_RETURN)
                mask |= BODY_FEATURE_RETURN_DIRECT | BODY_FEATURE_RETURN_AGG_DIRECT;
            else
                mask |= BODY_FEATURE_DIRECT;
        }
        mask |= host_call_feature_mask(node);
        return mask;
    }

    uint stmt_kind = stmt_record_slot(node, 0u);
    bool is_let_stmt = kind == HIR_LET_STMT || stmt_kind == STMT_RECORD_KIND_LET;
    bool is_return_stmt = kind == HIR_RETURN_STMT || stmt_kind == STMT_RECORD_KIND_RETURN;
    if (is_let_stmt || is_return_stmt)
    {
        uint mask = 0u;
        uint decl_token_for_let = INVALID;
        bool let_target_is_aggregate = false;
        if (is_let_stmt)
        {
            decl_token_for_let = stmt_record_slot(node, 1u);
            let_target_is_aggregate =
                valid_token(decl_token_for_let) &&
                (visible_type_for_token(decl_token_for_let) >= TY_ARRAY_BASE ||
                 wasm_agg_local_width_by_token[decl_token_for_let] != 0u);
            if (let_target_is_aggregate)
            {
                mask |= BODY_FEATURE_ARRAY_ALLOC | BODY_FEATURE_MEMBER_EXPR;
            }
        }
        uint expr_node = resolve_expr_node(stmt_record_slot(node, is_let_stmt ? 2u : 1u));
        if (valid_node(expr_node) && compact_hir_core[expr_node].kind == HIR_CALL_EXPR)
        {
            if (potential_user_call_node(expr_node))
            {
                if (is_let_stmt)
                    mask |= let_target_is_aggregate
                                ? (BODY_FEATURE_LET_AGG_DIRECT |
                                   BODY_FEATURE_AGG_COPY |
                                   BODY_FEATURE_ARRAY_ALLOC)
                                : BODY_FEATURE_LET_DIRECT;
                else
                    mask |= BODY_FEATURE_RETURN_DIRECT | BODY_FEATURE_RETURN_AGG_DIRECT;
            }
            uint host_mask = host_call_feature_mask(expr_node);
            if (is_return_stmt && (host_mask & BODY_FEATURE_HOST_IO) != 0u)
                host_mask |= BODY_FEATURE_HOST_IO_RETURN;
            mask |= host_mask;
        }
        if (valid_node(expr_node) && compact_hir_core[expr_node].kind == HIR_ARRAY_EXPR)
            mask |= BODY_FEATURE_ARRAY_ALLOC | BODY_FEATURE_MEMBER_EXPR;
        if (valid_node(expr_node) && expr_contains_member(expr_node))
        {
            mask |= BODY_FEATURE_MEMBER_EXPR;
            if (is_return_stmt && compact_hir_core[expr_node].kind == HIR_MEMBER_EXPR)
                mask |= BODY_FEATURE_RETURN_MEMBER_EXPR;
            else if (!is_return_stmt)
                mask |= BODY_FEATURE_MEMBER_EXPR_SCATTER;
        }
        if (valid_node(expr_node) && compact_hir_core[expr_node].kind == HIR_EXPR)
            mask |= BODY_FEATURE_EXPR_CONTROL | BODY_FEATURE_BINARY_DIRECT;
        return mask;
    }

    return 0u;
}

void collect_body_features(uint node)
{
    uint mask = collect_feature_mask(node);
    if (mask != 0u)
        atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, mask);
}

void collect_function_param_row(uint row)
{
    uint row_limit = call_param_row_count_out[0u];
    if (row >= row_limit)
        return;

    uint fn_token = call_param_row_fn_token[row];
    uint ordinal = call_param_row_ordinal[row];
    if (!supported_function_token(fn_token) || ordinal == INVALID)
        return;

    uint ty = call_param_row_type[row];
    if (!type_is_i32_abi_param(fn_token, ordinal, ty) && ty != TY_FLOAT)
    {
        atomic_u32_add(wasm_func_invalid_count_by_token, fn_token, 1u);
        atomic_u32_min(wasm_func_detail_by_token, fn_token, fn_token);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE)
        return;

    if (row < active_hir_node_count())
        collect_body_features(row);
    collect_function_param_row(row);
}
