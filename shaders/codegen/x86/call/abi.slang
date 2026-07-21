// SysV x86_64 call ABI projection over backend call records.
//
// x86_call_records owns the parser/resolver/type boundary. Typechecking owns
// compact per-call/per-ordinal argument rows, and this pass records
// target/width ABI metadata without looking at argument expression forms.

import gpu_index;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct FeatureParams
{
    uint mask;
    uint enum_count;
    uint match_count;
    uint aggregate_count;
};

ConstantBuffer<FeatureParams> gX86Features;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_fn_return_type_node;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_len_value;
StructuredBuffer<uint> x86_decl_node_by_token;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> compact_hir_count;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> x86_compact_executable_raw;
StructuredBuffer<uint> x86_enclosing_let_node;
StructuredBuffer<uint> x86_decl_layout_record;
StructuredBuffer<uint4> x86_call_record;
StructuredBuffer<uint> x86_call_type_record;
StructuredBuffer<uint> call_record_status;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> x86_struct_type_record;
StructuredBuffer<uint> x86_struct_record_status;
StructuredBuffer<uint> x86_enum_type_record;
StructuredBuffer<uint2> x86_enum_value_record;
StructuredBuffer<uint> x86_enum_record_status;

RWStructuredBuffer<uint2> x86_call_abi_record;
RWStructuredBuffer<uint> call_abi_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint X86_CALL_ABI_OK = 1u;
static const uint X86_ENUM_RECORDS_OK = 1u;
static const uint X86_STRUCT_RECORDS_OK = 1u;
static const uint X86_ERR_CALL_ABI = 9u;
static const uint X86_ERR_ENUM_PAYLOAD_ARITY = 53u;
static const uint X86_ERR_CALL_ARG_COUNT = 56u;

static const uint X86_FEATURE_ENUM = 1u << 0u;
static const uint X86_ENUM_VALUE_KIND_BITS = 4u;
static const uint X86_ENUM_VALUE_KIND_MASK = 0xfu;
static const uint X86_ENUM_VALUE_CALL_CTOR = 1u;
static const uint X86_ENUM_VALUE_UNIT_CTOR = 2u;
static const uint X86_CALL_TYPE_STRIDE = 3u;
static const uint X86_DECL_LAYOUT_STRIDE = 4u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint X86_CALL_ABI_ARG_COUNT_BITS = 8u;
static const uint X86_CALL_ABI_ARG_COUNT_MASK = 0xffu;
static const uint X86_CALL_ABI_RETURN_WIDTH_MAX = 0x00ffffffu;
static const uint INTRINSIC_NONE = 0u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_FN = 3u;
static const uint X86_CALL_TARGET_HOST_TEXT_WRITE = 0xfffffffeu;
static const uint X86_CALL_TARGET_HOST_I32_TO_F32 = 0xfffffffdu;
static const uint X86_CALL_TARGET_HOST_OPEN_READ_PATH = 0xfffffffcu;
static const uint X86_CALL_TARGET_HOST_OPEN_WRITE_PATH = 0xfffffffbu;
static const uint X86_CALL_TARGET_HOST_READ_I32 = 0xfffffffau;
static const uint X86_CALL_TARGET_HOST_WRITE_I32 = 0xfffffff9u;
static const uint X86_CALL_TARGET_HOST_WRITE_BYTE = 0xfffffff8u;
static const uint X86_CALL_TARGET_HOST_WRITE_NEWLINE = 0xfffffff7u;
static const uint X86_CALL_TARGET_HOST_CLOSE_FILE = 0xfffffff6u;
static const uint X86_CALL_TARGET_HOST_PROCESS_EXIT = 0xfffffff5u;
static const uint X86_CALL_TARGET_HOST_SECURE_U32 = 0xfffffff4u;
static const uint X86_CALL_TARGET_HOST_ALLOC = 0xfffffff3u;
static const uint X86_CALL_TARGET_HOST_DEALLOC = 0xfffffff2u;
static const uint X86_CALL_TARGET_HOST_ARGC = 0xfffffff1u;
static const uint X86_CALL_TARGET_HOST_ARG_LEN = 0xfffffff0u;
static const uint X86_CALL_TARGET_HOST_ARG_READ = 0xffffffefu;
static const uint X86_CALL_TARGET_HOST_UNIX_SECONDS = 0xffffffeeu;
static const uint X86_CALL_TARGET_HOST_CURRENT_DIR_READ = 0xffffffedu;
static const uint X86_CALL_TARGET_HOST_VAR_COUNT = 0xffffffecu;
static const uint X86_CALL_TARGET_HOST_VAR_KEY_LEN = 0xffffffebu;
static const uint X86_CALL_TARGET_HOST_VAR_KEY_READ = 0xffffffeau;
static const uint X86_CALL_TARGET_HOST_VAR_LEN = 0xffffffe9u;
static const uint X86_CALL_TARGET_HOST_VAR_READ = 0xffffffe8u;
static const uint X86_CALL_TARGET_HOST_FS_READ = 0xffffffe7u;
static const uint X86_CALL_TARGET_HOST_FS_WRITE = 0xffffffe6u;
static const uint X86_CALL_TARGET_HOST_FS_OPEN_READ = 0xffffffe5u;
static const uint X86_CALL_TARGET_HOST_FS_OPEN_WRITE = 0xffffffe4u;
static const uint X86_CALL_TARGET_HOST_FS_OPEN_APPEND = 0xffffffe3u;
static const uint X86_CALL_TARGET_HOST_STDIN_READ = 0xffffffe2u;
static const uint X86_CALL_TARGET_HOST_STDOUT_WRITE = 0xffffffe1u;
static const uint X86_CALL_TARGET_HOST_STDERR_WRITE = 0xffffffe0u;
static const uint X86_CALL_TARGET_HOST_FILL_SECURE_BYTES = 0xffffffdfu;
static const uint X86_CALL_TARGET_HOST_FS_REMOVE_FILE = 0xffffffdeu;
static const uint X86_CALL_TARGET_HOST_FS_CREATE_DIR = 0xffffffddu;
static const uint X86_CALL_TARGET_HOST_FS_REMOVE_DIR = 0xffffffdcu;
static const uint X86_CALL_TARGET_HOST_FS_RENAME = 0xffffffdbu;
static const uint X86_CALL_TARGET_HOST_TIME_MONOTONIC_READ = 0xffffffdau;
static const uint X86_CALL_TARGET_HOST_TIME_SYSTEM_READ = 0xffffffd9u;
static const uint X86_CALL_TARGET_HOST_TIME_SLEEP_MS_I32 = 0xffffffd8u;
static const uint X86_CALL_TARGET_HOST_REALLOC = 0xffffffd7u;
static const uint X86_CALL_TARGET_HOST_ALLOC_FAILED = 0xffffffd6u;
static const uint X86_CALL_TARGET_DEPENDENCY_TAG = 0x80000000u;
static const uint CALL_PARAM_CACHE_STRIDE = 4u;
static const uint LANGUAGE_SYMBOL_OPEN_READ_PATH = 20u;
static const uint LANGUAGE_SYMBOL_OPEN_WRITE_PATH = 21u;
static const uint LANGUAGE_SYMBOL_READ_I32 = 22u;
static const uint LANGUAGE_SYMBOL_WRITE_TEXT = 23u;
static const uint LANGUAGE_SYMBOL_WRITE_I32 = 24u;
static const uint LANGUAGE_SYMBOL_WRITE_BYTE = 25u;
static const uint LANGUAGE_SYMBOL_WRITE_NEWLINE = 26u;
static const uint LANGUAGE_SYMBOL_CLOSE_FILE = 27u;
static const uint LANGUAGE_SYMBOL_I32_TO_F32 = 28u;
static const uint LANGUAGE_SYMBOL_EXIT = 29u;
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

static const uint X86_SYSV_MAX_INTEGER_ARGS = 6u;
static const uint X86_BACKEND_MAX_PACKED_CALL_ARGS = 6u;
static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_LEN_LITERAL = 1u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

bool valid_node(uint node)
{
    return valid_index_or_invalid(node, active_hir_node_count(), INVALID);
}

bool valid_token(uint token)
{
    return valid_index_or_invalid(token, gParams.n_tokens, INVALID);
}

uint function_item_kind(uint raw_node)
{
    if (!valid_node(raw_node))
        return 0u;
    uint dense = raw_to_compact_hir[raw_node];
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    return dense < count && compact_hir_core[dense].kind == HIR_FN
               ? compact_hir_payload[dense].a
               : 0u;
}

uint call_record_slot(uint call_node)
{
    if (!valid_node(call_node))
        return INVALID;
    uint token = x86_call_record[call_node].z;
    return valid_token(token) ? token : INVALID;
}

bool call_records_ok()
{
    return stage_status4_ok(call_record_status, X86_CALL_RECORDS_OK);
}

bool enum_records_ok()
{
    return stage_status4_ok(x86_enum_record_status, X86_ENUM_RECORDS_OK);
}

bool struct_records_ok()
{
    return stage_status4_ok(x86_struct_record_status, X86_STRUCT_RECORDS_OK);
}

bool has_enum_feature()
{
    return (gX86Features.mask & X86_FEATURE_ENUM) != 0u;
}

uint enum_value_kind(uint2 record)
{
    return record.x & X86_ENUM_VALUE_KIND_MASK;
}

uint enum_value_payload_count(uint2 record)
{
    return record.x >> X86_ENUM_VALUE_KIND_BITS;
}

bool enum_value_record_is_supported(uint2 record)
{
    if (record.x == INVALID || record.y == INVALID)
        return false;

    uint kind = enum_value_kind(record);
    uint payload_count = enum_value_payload_count(record);
    return (kind == X86_ENUM_VALUE_UNIT_CTOR && payload_count == 0u) ||
           (kind == X86_ENUM_VALUE_CALL_CTOR && payload_count == 1u);
}

bool has_enum_value_record(uint node)
{
    if (!has_enum_feature())
        return false;
    if (!valid_node(node))
        return false;
    return enum_value_record_is_supported(x86_enum_value_record[node]);
}

bool unsupported_multi_payload_enum_constructor(uint node)
{
    if (!has_enum_feature() || !valid_node(node))
        return false;

    uint2 record = x86_enum_value_record[node];
    if (record.x == INVALID || record.y == INVALID)
        return false;

    return enum_value_kind(record) == X86_ENUM_VALUE_CALL_CTOR &&
           enum_value_payload_count(record) > 1u;
}

bool token_has_language_name(uint name_token, uint language_symbol)
{
    if (!valid_token(name_token))
        return false;

    uint name_id = name_id_by_token[name_token];
    uint language_id = language_name_id[language_symbol];
    return name_id != INVALID && language_id != INVALID && name_id == language_id;
}

bool call_has_language_name(uint callee_token, uint resolver_fn_token, uint language_symbol)
{
    return token_has_language_name(callee_token, language_symbol) ||
           token_has_language_name(resolver_fn_token, language_symbol);
}

bool has_call_record(uint call_node)
{
    if (!valid_node(call_node))
        return false;

    uint4 record = x86_call_record[call_node];
    return uint4_any_not_equal(record, INVALID);
}

bool host_text_write_call(uint resolver_fn_token, uint callee_token, uint target_fn, uint arg_count, uint return_width)
{
    if (arg_count != 2u ||
        return_width != 1u ||
        !call_has_language_name(callee_token, resolver_fn_token, LANGUAGE_SYMBOL_WRITE_TEXT))
        return false;

    uint param0 = row_major_load<uint>(
        call_param_type,
        resolver_fn_token,
        CALL_PARAM_CACHE_STRIDE,
        0u,
        TY_UNKNOWN);
    uint param1 = row_major_load<uint>(
        call_param_type,
        resolver_fn_token,
        CALL_PARAM_CACHE_STRIDE,
        1u,
        TY_UNKNOWN);
    bool host_signature = param0 == TY_INT && param1 == TY_STRING;
    return host_signature &&
           ((!valid_node(target_fn)) ||
           function_item_kind(target_fn) == HIR_ITEM_KIND_EXTERN_FN);
}

bool host_i32_to_f32_call(uint call_node, uint resolver_fn_token, uint callee_token, uint target_fn, uint arg_count, uint return_width)
{
    if (arg_count != 1u ||
        return_width != 1u ||
        call_type_word(call_node, 0u) != TY_FLOAT ||
        !call_has_language_name(callee_token, resolver_fn_token, LANGUAGE_SYMBOL_I32_TO_F32))
        return false;

    uint param0 = row_major_load<uint>(
        call_param_type,
        resolver_fn_token,
        CALL_PARAM_CACHE_STRIDE,
        0u,
        TY_UNKNOWN);
    return param0 == TY_INT &&
           ((!valid_node(target_fn)) ||
            function_item_kind(target_fn) == HIR_ITEM_KIND_EXTERN_FN);
}

uint host_param(uint resolver_fn_token, uint ordinal)
{
    return row_major_load<uint>(
        call_param_type,
        resolver_fn_token,
        CALL_PARAM_CACHE_STRIDE,
        ordinal,
        TY_UNKNOWN);
}

bool extern_or_unlowered_target(uint target_fn)
{
    return (!valid_node(target_fn)) ||
           function_item_kind(target_fn) == HIR_ITEM_KIND_EXTERN_FN;
}

bool host_string_i32_return_call(uint resolver_fn_token, uint callee_token, uint target_fn, uint arg_count, uint return_width, uint language_symbol)
{
    return arg_count == 1u &&
           return_width == 1u &&
           call_has_language_name(callee_token, resolver_fn_token, language_symbol) &&
           host_param(resolver_fn_token, 0u) == TY_STRING &&
           extern_or_unlowered_target(target_fn);
}

bool host_i32_i32_i32_return_call(uint resolver_fn_token, uint callee_token, uint target_fn, uint arg_count, uint return_width, uint language_symbol)
{
    return arg_count == 2u &&
           return_width == 1u &&
           call_has_language_name(callee_token, resolver_fn_token, language_symbol) &&
           host_param(resolver_fn_token, 0u) == TY_INT &&
           host_param(resolver_fn_token, 1u) == TY_INT &&
           extern_or_unlowered_target(target_fn);
}

bool host_i32_i32_return_call(uint resolver_fn_token, uint callee_token, uint target_fn, uint arg_count, uint return_width, uint language_symbol)
{
    return arg_count == 1u &&
           return_width == 1u &&
           call_has_language_name(callee_token, resolver_fn_token, language_symbol) &&
           host_param(resolver_fn_token, 0u) == TY_INT &&
           extern_or_unlowered_target(target_fn);
}

bool host_i32_void_call(uint call_node, uint resolver_fn_token, uint callee_token, uint target_fn, uint arg_count, uint return_width, uint language_symbol)
{
    return arg_count == 1u &&
           return_width == 1u &&
           call_type_word(call_node, 0u) == TY_VOID &&
           call_has_language_name(callee_token, resolver_fn_token, language_symbol) &&
           host_param(resolver_fn_token, 0u) == TY_INT &&
           extern_or_unlowered_target(target_fn);
}

bool host_u32_no_arg_call(uint call_node, uint resolver_fn_token, uint callee_token, uint target_fn, uint arg_count, uint return_width, uint language_symbol)
{
    return arg_count == 0u &&
           return_width == 1u &&
           call_type_word(call_node, 0u) == TY_UINT &&
           call_has_language_name(callee_token, resolver_fn_token, language_symbol) &&
           extern_or_unlowered_target(target_fn);
}

bool host_i32_no_arg_call(uint call_node, uint resolver_fn_token, uint callee_token, uint target_fn, uint arg_count, uint return_width, uint language_symbol)
{
    return arg_count == 0u &&
           return_width == 1u &&
           call_type_word(call_node, 0u) == TY_INT &&
           call_has_language_name(callee_token, resolver_fn_token, language_symbol) &&
           extern_or_unlowered_target(target_fn);
}

bool host_i32_u32_u32_i32_return_call(uint call_node, uint resolver_fn_token, uint callee_token, uint target_fn, uint arg_count, uint return_width, uint language_symbol)
{
    return arg_count == 3u &&
           return_width == 1u &&
           call_type_word(call_node, 0u) == TY_INT &&
           call_has_language_name(callee_token, resolver_fn_token, language_symbol) &&
           host_param(resolver_fn_token, 0u) == TY_INT &&
           host_param(resolver_fn_token, 1u) == TY_UINT &&
           host_param(resolver_fn_token, 2u) == TY_UINT &&
           extern_or_unlowered_target(target_fn);
}

bool host_u32_u32_u32_return_call(uint call_node, uint resolver_fn_token, uint callee_token, uint target_fn, uint arg_count, uint return_width, uint language_symbol)
{
    return arg_count == 2u &&
           return_width == 1u &&
           call_type_word(call_node, 0u) == TY_UINT &&
           call_has_language_name(callee_token, resolver_fn_token, language_symbol) &&
           host_param(resolver_fn_token, 0u) == TY_UINT &&
           host_param(resolver_fn_token, 1u) == TY_UINT &&
           extern_or_unlowered_target(target_fn);
}

bool host_u32_u32_i32_return_call(uint call_node, uint resolver_fn_token, uint callee_token, uint target_fn, uint arg_count, uint return_width, uint language_symbol)
{
    return arg_count == 2u &&
           return_width == 1u &&
           call_type_word(call_node, 0u) == TY_INT &&
           call_has_language_name(callee_token, resolver_fn_token, language_symbol) &&
           host_param(resolver_fn_token, 0u) == TY_UINT &&
           host_param(resolver_fn_token, 1u) == TY_UINT &&
           extern_or_unlowered_target(target_fn);
}

bool host_u32_u32_u32_u32_i32_return_call(uint call_node, uint resolver_fn_token, uint callee_token, uint target_fn, uint arg_count, uint return_width, uint language_symbol)
{
    return arg_count == 4u &&
           return_width == 1u &&
           call_type_word(call_node, 0u) == TY_INT &&
           call_has_language_name(callee_token, resolver_fn_token, language_symbol) &&
           host_param(resolver_fn_token, 0u) == TY_UINT &&
           host_param(resolver_fn_token, 1u) == TY_UINT &&
           host_param(resolver_fn_token, 2u) == TY_UINT &&
           host_param(resolver_fn_token, 3u) == TY_UINT &&
           extern_or_unlowered_target(target_fn);
}

bool host_u32_u32_u32_u32_u32_return_call(uint call_node, uint resolver_fn_token, uint callee_token, uint target_fn, uint arg_count, uint return_width, uint language_symbol)
{
    return arg_count == 4u &&
           return_width == 1u &&
           call_type_word(call_node, 0u) == TY_UINT &&
           call_has_language_name(callee_token, resolver_fn_token, language_symbol) &&
           host_param(resolver_fn_token, 0u) == TY_UINT &&
           host_param(resolver_fn_token, 1u) == TY_UINT &&
           host_param(resolver_fn_token, 2u) == TY_UINT &&
           host_param(resolver_fn_token, 3u) == TY_UINT &&
           extern_or_unlowered_target(target_fn);
}

bool host_u32_u32_u32_void_call(uint call_node, uint resolver_fn_token, uint callee_token, uint target_fn, uint arg_count, uint return_width, uint language_symbol)
{
    return arg_count == 3u &&
           return_width == 1u &&
           call_type_word(call_node, 0u) == TY_VOID &&
           call_has_language_name(callee_token, resolver_fn_token, language_symbol) &&
           host_param(resolver_fn_token, 0u) == TY_UINT &&
           host_param(resolver_fn_token, 1u) == TY_UINT &&
           host_param(resolver_fn_token, 2u) == TY_UINT &&
           extern_or_unlowered_target(target_fn);
}

bool host_u32_u32_void_call(uint call_node, uint resolver_fn_token, uint callee_token, uint target_fn, uint arg_count, uint return_width, uint language_symbol)
{
    return arg_count == 2u &&
           return_width == 1u &&
           call_type_word(call_node, 0u) == TY_VOID &&
           call_has_language_name(callee_token, resolver_fn_token, language_symbol) &&
           host_param(resolver_fn_token, 0u) == TY_UINT &&
           host_param(resolver_fn_token, 1u) == TY_UINT &&
           extern_or_unlowered_target(target_fn);
}

uint call_type_word(uint call_node, uint slot)
{
    return row_major_load<uint>(
        x86_call_type_record,
        call_node,
        X86_CALL_TYPE_STRIDE,
        slot,
        INVALID);
}

bool intrinsic_call(uint call_node)
{
    uint callee_token = call_type_word(call_node, 2u);
    return valid_token(callee_token) &&
           call_intrinsic_tag[callee_token] != INTRINSIC_NONE;
}

uint semantic_type_width(uint ty)
{
    if (ty == TY_STRING)
        return 2u;
    if (ty >= TY_ENUM_BASE && ty < TY_GENERIC_BASE)
        return 2u;
    if (ty >= TY_STRUCT_BASE && ty < TY_ENUM_BASE)
    {
        uint struct_token = ty - TY_STRUCT_BASE;
        if (valid_token(struct_token) && x86_struct_type_record[struct_token] != 0u)
            return x86_struct_type_record[struct_token];
    }
    return 1u;
}

uint named_type_instance_width(uint ty)
{
    if (!valid_token(ty))
        return 1u;
    uint enum_token = type_instance_decl_token[ty];
    if (valid_token(enum_token) && x86_enum_type_record[enum_token] > 1u)
        return x86_enum_type_record[enum_token];
    if (valid_token(enum_token) && x86_struct_type_record[enum_token] != 0u)
        return x86_struct_type_record[enum_token];
    return 1u;
}

uint type_ref_leaf_width(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return semantic_type_width(payload);
    if (tag == TYPE_REF_INSTANCE)
        return named_type_instance_width(payload);
    return 1u;
}

uint type_instance_width(uint ty)
{
    if (!valid_token(ty))
        return 1u;
    if (type_instance_kind[ty] == TYPE_INSTANCE_ARRAY &&
        type_instance_len_kind[ty] == TYPE_LEN_LITERAL &&
        type_instance_len_payload[ty] != 0u)
    {
        uint elem_width = type_ref_leaf_width(
            type_instance_elem_ref_tag[ty],
            type_instance_elem_ref_payload[ty]);
        return max(elem_width, 1u) * type_instance_len_payload[ty];
    }
    return named_type_instance_width(ty);
}

uint call_return_width(uint semantic_ty, uint type_token)
{
    return max(semantic_type_width(semantic_ty), type_instance_width(type_token));
}

bool array_type_width_for_type_node(uint type_node, out uint width)
{
    width = 0u;
    if (!valid_node(type_node) ||
        hir_kind[type_node] != HIR_TYPE ||
        hir_type_form[type_node] != HIR_TYPE_FORM_ARRAY)
        return false;
    uint len = hir_type_len_value[type_node];
    if (len == INVALID || len <= 1u)
        return false;
    width = len;
    return true;
}

uint function_return_hir_width(uint fn_node)
{
    uint width = 0u;
    uint type_node = valid_node(fn_node) ? hir_fn_return_type_node[fn_node] : INVALID;
    return array_type_width_for_type_node(type_node, width) ? width : 1u;
}

uint contextual_return_width(uint call_node)
{
    uint stmt_node = valid_node(call_node) ? x86_enclosing_let_node[call_node] : INVALID;
    if (!valid_node(stmt_node))
        return 0u;
    uint stmt_kind = row_major_load<uint>(
        hir_stmt_record,
        stmt_node,
        STMT_RECORD_STRIDE,
        0u,
        INVALID);
    if (stmt_kind != STMT_RECORD_KIND_LET)
        return 0u;
    uint decl_token = row_major_load<uint>(
        hir_stmt_record,
        stmt_node,
        STMT_RECORD_STRIDE,
        1u,
        INVALID);
    if (!valid_token(decl_token))
        return 0u;
    uint width = row_major_load<uint>(
        x86_decl_layout_record,
        decl_token,
        X86_DECL_LAYOUT_STRIDE,
        1u,
        0u);
    return width > 1u ? width : 0u;
}

uint function_node_for_resolver_target(uint resolver_fn_token)
{
    if (!valid_token(resolver_fn_token))
        return INVALID;

    uint node = x86_decl_node_by_token[resolver_fn_token];
    if (!valid_node(node))
        return INVALID;
    uint dense = raw_to_compact_hir[node];
    uint dense_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (dense == INVALID || dense >= dense_count)
        return node;
    uint executable_raw = x86_compact_executable_raw[dense];
    return valid_node(executable_raw) ? executable_raw : node;
}

void mark_call_abi_error(uint detail)
{
    publish_stage_error_min_detail4(call_abi_status, X86_ERR_CALL_ABI, detail);
}

void mark_call_arg_count_error(uint detail)
{
    publish_stage_error_min_detail4(
        call_abi_status,
        X86_ERR_CALL_ARG_COUNT,
        detail);
}

void mark_enum_payload_arity_error(uint call_node)
{
    publish_stage_error_min_detail4(
        call_abi_status,
        X86_ERR_ENUM_PAYLOAD_ARITY,
        call_node);
}

uint pack_call_abi_info(uint arg_count, uint return_width)
{
    if (return_width > X86_CALL_ABI_RETURN_WIDTH_MAX)
        return INVALID;
    return (return_width << X86_CALL_ABI_ARG_COUNT_BITS) |
           (arg_count & X86_CALL_ABI_ARG_COUNT_MASK);
}

void project_call_record(uint call_node)
{
    uint slot = call_record_slot(call_node);
    if (slot != INVALID)
        x86_call_abi_record[slot] = uint2(INVALID, INVALID);

    if (unsupported_multi_payload_enum_constructor(call_node))
    {
        mark_enum_payload_arity_error(call_node);
        return;
    }

    uint4 call_record = x86_call_record[call_node];
    uint owner_fn = call_record.x;
    bool dependency_call = (call_record.y & X86_CALL_TARGET_DEPENDENCY_TAG) != 0u &&
                           call_record.y < X86_CALL_TARGET_HOST_ALLOC_FAILED;
    uint target_fn = function_node_for_resolver_target(call_record.y);
    uint callee_token = call_type_word(call_node, 2u);
    uint arg_count = call_record.w;
    uint return_ty = call_type_word(call_node, 0u);
    uint return_ty_token = call_type_word(call_node, 1u);

    uint context_width = contextual_return_width(call_node);
    uint return_width = context_width > 1u
                            ? context_width
                            : max(
                                  call_return_width(return_ty, return_ty_token),
                                  function_return_hir_width(target_fn));
    uint abi_register_count = arg_count + (return_width > 1u ? 1u : 0u);
    bool supported = true;
    bool host_text_write = host_text_write_call(call_record.y, callee_token, target_fn, arg_count, return_width);
    bool host_i32_to_f32 = host_i32_to_f32_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width);
    bool host_open_read_path = host_string_i32_return_call(call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_OPEN_READ_PATH);
    bool host_open_write_path = host_string_i32_return_call(call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_OPEN_WRITE_PATH);
    bool host_read_i32 = host_i32_i32_i32_return_call(call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_READ_I32);
    bool host_write_i32 = host_i32_i32_i32_return_call(call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_WRITE_I32);
    bool host_write_byte = host_i32_i32_i32_return_call(call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_WRITE_BYTE);
    bool host_write_newline = host_i32_i32_return_call(call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_WRITE_NEWLINE);
    bool host_close_file = host_i32_i32_return_call(call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_CLOSE_FILE);
    bool host_process_exit = host_i32_void_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_EXIT);
    bool host_secure_u32 = host_u32_no_arg_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_SECURE_U32);
    bool host_alloc = host_u32_u32_u32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_ALLOC);
    bool host_dealloc = host_u32_u32_u32_void_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_DEALLOC);
    bool host_argc = host_i32_no_arg_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_ARGC);
    bool host_arg_len = host_i32_i32_return_call(call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_ARG_LEN);
    bool host_arg_read = host_i32_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_ARG_READ);
    bool host_unix_seconds = host_i32_no_arg_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_UNIX_SECONDS);
    bool host_current_dir_read = host_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_CURRENT_DIR_READ);
    bool host_var_count = host_i32_no_arg_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_VAR_COUNT);
    bool host_var_key_len = host_i32_i32_return_call(call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_VAR_KEY_LEN);
    bool host_var_key_read = host_i32_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_VAR_KEY_READ);
    bool host_var_len = host_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_VAR_LEN);
    bool host_var_read = host_u32_u32_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_VAR_READ);
    bool host_close = host_i32_i32_return_call(call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_CLOSE);
    bool host_fs_read = host_i32_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_READ);
    bool host_fs_write = host_i32_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_WRITE);
    bool host_fs_open_read = host_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_OPEN_READ);
    bool host_fs_open_write = host_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_OPEN_WRITE);
    bool host_fs_open_append = host_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_OPEN_APPEND);
    bool host_stdin_read = host_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_READ_STDIN);
    bool host_stdout_write = host_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_WRITE_STDOUT);
    bool host_stderr_write = host_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_WRITE_STDERR);
    bool host_fill_secure_bytes = host_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_FILL_SECURE_BYTES);
    bool host_fs_remove_file = host_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_REMOVE_FILE);
    bool host_fs_create_dir = host_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_CREATE_DIR);
    bool host_fs_remove_dir = host_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_REMOVE_DIR);
    bool host_fs_rename = host_u32_u32_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_RENAME);
    bool host_time_monotonic_read = host_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_MONOTONIC_READ);
    bool host_time_system_read = host_u32_u32_i32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_SYSTEM_READ);
    bool host_time_sleep_ms_i32 = host_i32_i32_return_call(call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_SLEEP_MS_I32);
    bool host_realloc = host_u32_u32_u32_u32_u32_return_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_REALLOC);
    bool host_alloc_failed = host_u32_u32_void_call(call_node, call_record.y, callee_token, target_fn, arg_count, return_width, LANGUAGE_SYMBOL_ALLOC_FAILED);
    bool host_call = !dependency_call && (host_text_write || host_i32_to_f32 ||
                     host_open_read_path || host_open_write_path ||
                     host_read_i32 || host_write_i32 || host_write_byte ||
                     host_write_newline || host_close_file || host_close ||
                     host_process_exit || host_secure_u32 || host_alloc ||
                     host_dealloc || host_argc || host_arg_len || host_arg_read ||
                     host_unix_seconds || host_current_dir_read ||
                     host_var_count || host_var_key_len || host_var_key_read ||
                     host_var_len || host_var_read ||
                     host_fs_read || host_fs_write ||
                     host_fs_open_read || host_fs_open_write || host_fs_open_append ||
                     host_stdin_read || host_stdout_write || host_stderr_write ||
                     host_fill_secure_bytes || host_fs_remove_file ||
                     host_fs_create_dir || host_fs_remove_dir || host_fs_rename ||
                     host_time_monotonic_read || host_time_system_read || host_time_sleep_ms_i32 ||
                     host_realloc || host_alloc_failed);
    if (!host_call && !dependency_call && !valid_node(target_fn))
    {
        mark_call_abi_error(slot != INVALID ? slot : call_node);
        supported = false;
    }
    if (!valid_node(owner_fn))
    {
        mark_call_abi_error(slot != INVALID ? slot : call_node);
        supported = false;
    }
    if (arg_count > X86_BACKEND_MAX_PACKED_CALL_ARGS)
    {
        mark_call_arg_count_error(slot != INVALID ? slot : call_node);
        supported = false;
    }
    else if (abi_register_count > X86_SYSV_MAX_INTEGER_ARGS)
    {
        mark_call_abi_error(slot != INVALID ? slot : call_node);
        supported = false;
    }

    uint abi_info = pack_call_abi_info(arg_count, return_width);
    if (abi_info == INVALID || slot == INVALID)
    {
        mark_call_abi_error(slot != INVALID ? slot : call_node);
        supported = false;
    }

    if (supported)
        x86_call_abi_record[slot] = uint2(
            host_text_write ? X86_CALL_TARGET_HOST_TEXT_WRITE
          : host_i32_to_f32 ? X86_CALL_TARGET_HOST_I32_TO_F32
          : host_open_read_path ? X86_CALL_TARGET_HOST_OPEN_READ_PATH
          : host_open_write_path ? X86_CALL_TARGET_HOST_OPEN_WRITE_PATH
          : host_read_i32 ? X86_CALL_TARGET_HOST_READ_I32
          : host_write_i32 ? X86_CALL_TARGET_HOST_WRITE_I32
          : host_write_byte ? X86_CALL_TARGET_HOST_WRITE_BYTE
          : host_write_newline ? X86_CALL_TARGET_HOST_WRITE_NEWLINE
          : (host_close_file || host_close) ? X86_CALL_TARGET_HOST_CLOSE_FILE
          : host_process_exit ? X86_CALL_TARGET_HOST_PROCESS_EXIT
          : host_secure_u32 ? X86_CALL_TARGET_HOST_SECURE_U32
          : host_alloc ? X86_CALL_TARGET_HOST_ALLOC
          : host_dealloc ? X86_CALL_TARGET_HOST_DEALLOC
          : host_argc ? X86_CALL_TARGET_HOST_ARGC
          : host_arg_len ? X86_CALL_TARGET_HOST_ARG_LEN
          : host_arg_read ? X86_CALL_TARGET_HOST_ARG_READ
          : host_unix_seconds ? X86_CALL_TARGET_HOST_UNIX_SECONDS
          : host_current_dir_read ? X86_CALL_TARGET_HOST_CURRENT_DIR_READ
          : host_var_count ? X86_CALL_TARGET_HOST_VAR_COUNT
          : host_var_key_len ? X86_CALL_TARGET_HOST_VAR_KEY_LEN
          : host_var_key_read ? X86_CALL_TARGET_HOST_VAR_KEY_READ
          : host_var_len ? X86_CALL_TARGET_HOST_VAR_LEN
          : host_var_read ? X86_CALL_TARGET_HOST_VAR_READ
          : host_fs_read ? X86_CALL_TARGET_HOST_FS_READ
          : host_fs_write ? X86_CALL_TARGET_HOST_FS_WRITE
          : host_fs_open_read ? X86_CALL_TARGET_HOST_FS_OPEN_READ
          : host_fs_open_write ? X86_CALL_TARGET_HOST_FS_OPEN_WRITE
          : host_fs_open_append ? X86_CALL_TARGET_HOST_FS_OPEN_APPEND
          : host_stdin_read ? X86_CALL_TARGET_HOST_STDIN_READ
          : host_stdout_write ? X86_CALL_TARGET_HOST_STDOUT_WRITE
          : host_stderr_write ? X86_CALL_TARGET_HOST_STDERR_WRITE
          : host_fill_secure_bytes ? X86_CALL_TARGET_HOST_FILL_SECURE_BYTES
          : host_fs_remove_file ? X86_CALL_TARGET_HOST_FS_REMOVE_FILE
          : host_fs_create_dir ? X86_CALL_TARGET_HOST_FS_CREATE_DIR
          : host_fs_remove_dir ? X86_CALL_TARGET_HOST_FS_REMOVE_DIR
          : host_fs_rename ? X86_CALL_TARGET_HOST_FS_RENAME
          : host_time_monotonic_read ? X86_CALL_TARGET_HOST_TIME_MONOTONIC_READ
          : host_time_system_read ? X86_CALL_TARGET_HOST_TIME_SYSTEM_READ
          : host_time_sleep_ms_i32 ? X86_CALL_TARGET_HOST_TIME_SLEEP_MS_I32
          : host_realloc ? X86_CALL_TARGET_HOST_REALLOC
          : host_alloc_failed ? X86_CALL_TARGET_HOST_ALLOC_FAILED
          : dependency_call ? call_record.y
          : target_fn,
            abi_info);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i == 0u && (!call_records_ok() || !enum_records_ok() || !struct_records_ok()))
    {
        call_abi_status[0u] = 0u;
        if (!call_records_ok())
        {
            call_abi_status[1u] = call_record_status[1u];
            call_abi_status[2u] = call_record_status[2u];
        }
        else if (!enum_records_ok())
        {
            call_abi_status[1u] = x86_enum_record_status[1u];
            call_abi_status[2u] = x86_enum_record_status[2u];
        }
        else
        {
            call_abi_status[1u] = x86_struct_record_status[1u];
            call_abi_status[2u] = x86_struct_record_status[2u];
        }
        call_abi_status[3u] = 0u;
    }

    if (!call_records_ok() || !enum_records_ok() || !struct_records_ok() ||
        node_i >= active_hir_node_count())
        return;

    if (has_call_record(node_i) && !has_enum_value_record(node_i))
    {
        if (intrinsic_call(node_i))
            return;
        project_call_record(node_i);
    }
}
