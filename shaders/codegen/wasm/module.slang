import byte_packing;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

ByteAddressBuffer source_bytes;
StructuredBuffer<uint> body_words;
StructuredBuffer<uint> body_status;
StructuredBuffer<uint> body_plan;
StructuredBuffer<uint> wasm_func_token_by_slot;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> method_decl_receiver_mode;
RWStructuredBuffer<uint> out_words;
StructuredBuffer<uint> status;

static const uint WORKGROUP_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint TYPE_SECTION_PAYLOAD_LEN = 756u;
static const uint TYPE_SECTION_LEN = 762u;
static const uint TYPE_COUNT = 114u;
static const uint TYPE_ENTRIES_LEN = TYPE_SECTION_PAYLOAD_LEN - 1u;
static const uint FIXED_TYPE_COUNT = 21u;
static const uint MIXED_TYPE_BASE = FIXED_TYPE_COUNT;
static const uint MIXED_TYPES_PER_RETURN = 31u;
static const uint IMPORT_SECTION_PAYLOAD_LEN = 515u;
static const uint IMPORT_SECTION_LEN = 521u;
static const uint MEMORY_SECTION_LEN = 17u;
static const uint EXPORT_SECTION_LEN = 31u;
static const uint WASM_IMPORT_FUNCTION_COUNT = 31u;
static const uint BODY_PLAN_FUNCTION_COUNT = 31u;
static const uint BODY_PLAN_MAIN_SLOT = 34u;
static const uint INVALID = 0xffffffffu;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_ARRAY_BASE = 128u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint WASM_VALTYPE_I32 = 0x7fu;
static const uint WASM_VALTYPE_I64 = 0x7eu;
static const uint WASM_VALTYPE_F32 = 0x7du;
static const uint WASM_MAX_DIRECT_CALL_ARGS = 4u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint body_byte(uint i)
{
    return body_words[i];
}

uint source_byte(uint pos)
{
    if (pos >= gParams.source_len)
        return 0u;
    return byte_address_load_u8(source_bytes, pos);
}

uint leb5_byte(uint value, uint i)
{
    uint byte_value = (value >> (i * 7u)) & 0x7fu;
    if (i < 4u)
        byte_value |= 0x80u;
    return byte_value;
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

uint type_param_count(uint type_i)
{
    if (type_i >= MIXED_TYPE_BASE)
    {
        uint rel = (type_i - MIXED_TYPE_BASE) % MIXED_TYPES_PER_RETURN;
        uint offset = 0u;
        for (uint n = 0u; n <= WASM_MAX_DIRECT_CALL_ARGS; n += 1u)
        {
            uint count = 1u << n;
            if (rel < offset + count)
                return n;
            offset += count;
        }
        return 0u;
    }

    if (type_i == 0u) return 1u;
    if (type_i == 1u || type_i == 7u || type_i == 11u) return 0u;
    if (type_i >= 2u && type_i <= 5u) return type_i - 1u;
    if (type_i == 6u) return 3u;
    if (type_i == 8u) return 1u;
    if (type_i == 9u) return 2u;
    if (type_i == 10u) return 4u;
    if (type_i >= 12u && type_i <= 15u) return type_i - 11u;
    if (type_i >= 16u && type_i <= 19u) return type_i - 15u;
    if (type_i == 20u) return 1u;
    return 0u;
}

uint type_return_type(uint type_i)
{
    if (type_i >= MIXED_TYPE_BASE)
    {
        uint category = (type_i - MIXED_TYPE_BASE) / MIXED_TYPES_PER_RETURN;
        if (category == 1u)
            return WASM_VALTYPE_I32;
        if (category == 2u)
            return WASM_VALTYPE_F32;
        return 0u;
    }

    if ((type_i >= 1u && type_i <= 5u) || (type_i >= 16u && type_i <= 19u))
        return WASM_VALTYPE_I32;
    if ((type_i >= 11u && type_i <= 15u) || type_i == 20u)
        return WASM_VALTYPE_F32;
    return 0u;
}

uint type_param_type(uint type_i, uint ordinal)
{
    if (ordinal >= type_param_count(type_i))
        return 0u;
    if (type_i >= MIXED_TYPE_BASE)
    {
        uint rel = (type_i - MIXED_TYPE_BASE) % MIXED_TYPES_PER_RETURN;
        uint offset = 0u;
        for (uint n = 0u; n <= WASM_MAX_DIRECT_CALL_ARGS; n += 1u)
        {
            uint count = 1u << n;
            if (rel < offset + count)
            {
                uint mask = rel - offset;
                return ((mask >> ordinal) & 1u) != 0u ? WASM_VALTYPE_F32 : WASM_VALTYPE_I32;
            }
            offset += count;
        }
        return 0u;
    }

    if (type_i == 0u)
        return WASM_VALTYPE_I64;
    if ((type_i >= 12u && type_i <= 19u))
        return WASM_VALTYPE_F32;
    return WASM_VALTYPE_I32;
}

uint type_entry_len(uint type_i)
{
    uint result_count = type_return_type(type_i) == 0u ? 0u : 1u;
    return 3u + type_param_count(type_i) + result_count;
}

uint type_entry_byte(uint type_i, uint byte_i)
{
    uint param_count = type_param_count(type_i);
    if (byte_i == 0u) return 0x60u;
    if (byte_i == 1u) return param_count;
    if (byte_i < 2u + param_count)
        return type_param_type(type_i, byte_i - 2u);
    uint result_count_i = 2u + param_count;
    uint result_type = type_return_type(type_i);
    if (byte_i == result_count_i)
        return result_type == 0u ? 0u : 1u;
    if (byte_i == result_count_i + 1u && result_type != 0u)
        return result_type;
    return 0u;
}

uint static_type_entries_byte(uint rel)
{
    uint offset = 0u;
    for (uint type_i = 0u; type_i < TYPE_COUNT; type_i += 1u)
    {
        uint len = type_entry_len(type_i);
        if (rel < offset + len)
            return type_entry_byte(type_i, rel - offset);
        offset += len;
    }
    return 0u;
}

bool method_receiver_param(uint fn_token, uint ordinal)
{
    if (fn_token == INVALID || ordinal != 0u)
        return false;
    uint mode = method_decl_receiver_mode[fn_token];
    return mode == METHOD_RECEIVER_SELF || mode == METHOD_RECEIVER_REF_SELF;
}

uint call_param_type_value(uint fn_token, uint ordinal)
{
    if (fn_token == INVALID)
        return 0u;

    uint start = call_param_row_start[fn_token];
    uint count = call_param_row_count[fn_token];
    uint row_limit = call_param_row_count_out[0u];
    if (start == INVALID || ordinal >= count || start > row_limit || ordinal > row_limit - start)
        return method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : 0u;

    uint row = start + ordinal;
    if (row >= row_limit ||
        call_param_row_fn_token[row] != fn_token ||
        call_param_row_ordinal[row] != ordinal)
    {
        return method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : 0u;
    }

    uint ty = call_param_row_type[row];
    return ty == 0u && method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : ty;
}

uint function_signature_result_type(uint fn_token)
{
    uint ret = fn_token == INVALID ? 0u : call_return_type[fn_token];
    if (ret == TY_BOOL || ret == TY_INT || ret == TY_UINT || ret >= TY_ARRAY_BASE)
        return WASM_VALTYPE_I32;
    if (ret == TY_FLOAT)
        return WASM_VALTYPE_F32;
    return 0u;
}

uint function_signature_param_type(uint fn_token, uint ordinal)
{
    uint ty = call_param_type_value(fn_token, ordinal);
    return ty == TY_FLOAT ? WASM_VALTYPE_F32 : WASM_VALTYPE_I32;
}

uint function_signature_type_entry_len(uint fn_token)
{
    uint param_count = fn_token == INVALID ? 0u : call_param_count[fn_token];
    uint result_count = function_signature_result_type(fn_token) == 0u ? 0u : 1u;
    return 1u + 5u + param_count + 1u + result_count;
}

uint function_signature_type_entry_byte(uint fn_token, uint byte_i)
{
    uint param_count = fn_token == INVALID ? 0u : call_param_count[fn_token];
    if (byte_i == 0u)
        return 0x60u;
    if (byte_i >= 1u && byte_i < 6u)
        return leb5_byte(param_count, byte_i - 1u);
    uint params_start = 6u;
    if (byte_i >= params_start && byte_i < params_start + param_count)
        return function_signature_param_type(fn_token, byte_i - params_start);
    uint result_count_i = params_start + param_count;
    uint result_type = function_signature_result_type(fn_token);
    if (byte_i == result_count_i)
        return result_type == 0u ? 0u : 1u;
    if (byte_i == result_count_i + 1u && result_type != 0u)
        return result_type;
    return 0u;
}

uint dynamic_type_entries_len(uint function_count)
{
    uint total = 0u;
    for (uint slot = 0u; slot < function_count; slot += 1u)
    {
        uint fn_token = wasm_func_token_by_slot[slot];
        total += function_signature_type_entry_len(fn_token);
    }
    return total;
}

uint dynamic_type_entries_byte(uint rel, uint function_count)
{
    uint offset = 0u;
    for (uint slot = 0u; slot < function_count; slot += 1u)
    {
        uint fn_token = wasm_func_token_by_slot[slot];
        uint len = function_signature_type_entry_len(fn_token);
        if (rel < offset + len)
            return function_signature_type_entry_byte(fn_token, rel - offset);
        offset += len;
    }
    return 0u;
}

uint type_section_payload_len(uint function_count)
{
    return 5u + TYPE_ENTRIES_LEN + dynamic_type_entries_len(function_count);
}

uint type_section_len(uint function_count)
{
    return 6u + type_section_payload_len(function_count);
}

uint type_payload_byte(uint pos, uint function_count)
{
    if (pos < 5u)
        return leb5_byte(TYPE_COUNT + function_count, pos);

    uint rel = pos - 5u;
    if (rel < TYPE_ENTRIES_LEN)
        return static_type_entries_byte(rel);
    return dynamic_type_entries_byte(rel - TYPE_ENTRIES_LEN, function_count);
}

uint type_section_byte(uint pos, uint function_count)
{
    if (pos == 0u) return 1u;
    if (pos >= 1u && pos < 6u) return leb5_byte(type_section_payload_len(function_count), pos - 1u);
    return type_payload_byte(pos - 6u, function_count);
}

uint import_name_len(uint import_i)
{
    if (import_i == 0u) return 9u;
    if (import_i == 1u) return 12u;
    if (import_i == 2u) return 4u;
    if (import_i == 3u) return 7u;
    if (import_i == 4u) return 8u;
    if (import_i == 5u) return 10u;
    if (import_i == 6u) return 12u;
    if (import_i == 7u) return 16u;
    if (import_i == 8u) return 15u;
    if (import_i == 9u) return 9u;
    if (import_i == 10u) return 11u;
    if (import_i == 11u) return 12u;
    if (import_i == 12u) return 7u;
    if (import_i == 13u) return 8u;
    if (import_i == 14u) return 5u;
    if (import_i == 15u) return 4u;
    if (import_i == 16u) return 5u;
    if (import_i == 17u) return 9u;
    if (import_i == 18u) return 10u;
    if (import_i == 19u) return 11u;
    if (import_i == 20u) return 12u;
    if (import_i == 21u) return 10u;
    if (import_i == 22u) return 5u;
    if (import_i == 23u) return 7u;
    if (import_i == 24u) return 8u;
    if (import_i == 25u) return 9u;
    if (import_i == 26u) return 10u;
    if (import_i == 27u) return 13u;
    if (import_i == 28u) return 14u;
    if (import_i == 29u) return 15u;
    if (import_i == 30u) return 10u;
    return 0u;
}

uint import_type_index(uint import_i)
{
    if (import_i == 0u) return 0u;
    if (import_i == 1u) return 3u;
    if (import_i == 2u) return 1u;
    if (import_i == 3u) return 2u;
    if (import_i == 4u) return 4u;
    if (import_i == 5u) return 1u;
    if (import_i == 6u) return 1u;
    if (import_i == 7u) return 3u;
    if (import_i == 8u) return 1u;
    if (import_i == 9u) return 1u;
    if (import_i == 10u) return 2u;
    if (import_i == 11u) return 4u;
    if (import_i == 12u) return 3u;
    if (import_i == 13u) return 5u;
    if (import_i == 14u) return 2u;
    if (import_i == 15u) return 4u;
    if (import_i == 16u) return 4u;
    if (import_i == 17u) return 3u;
    if (import_i == 18u) return 3u;
    if (import_i == 19u) return 3u;
    if (import_i == 20u) return 3u;
    if (import_i == 21u) return 3u;
    if (import_i == 22u) return 3u;
    if (import_i == 23u) return 6u;
    if (import_i == 24u) return 3u;
    if (import_i == 25u) return 3u;
    if (import_i == 26u) return 3u;
    if (import_i == 27u) return 2u;
    if (import_i == 28u) return 3u;
    if (import_i == 29u) return 3u;
    if (import_i == 30u) return 4u;
    return 0u;
}

uint import_name_byte(uint import_i, uint byte_i)
{
    if (import_i == 0u && byte_i == 0u) return 112u;
    if (import_i == 0u && byte_i == 1u) return 114u;
    if (import_i == 0u && byte_i == 2u) return 105u;
    if (import_i == 0u && byte_i == 3u) return 110u;
    if (import_i == 0u && byte_i == 4u) return 116u;
    if (import_i == 0u && byte_i == 5u) return 95u;
    if (import_i == 0u && byte_i == 6u) return 105u;
    if (import_i == 0u && byte_i == 7u) return 54u;
    if (import_i == 0u && byte_i == 8u) return 52u;
    if (import_i == 1u && byte_i == 0u) return 119u;
    if (import_i == 1u && byte_i == 1u) return 114u;
    if (import_i == 1u && byte_i == 2u) return 105u;
    if (import_i == 1u && byte_i == 3u) return 116u;
    if (import_i == 1u && byte_i == 4u) return 101u;
    if (import_i == 1u && byte_i == 5u) return 95u;
    if (import_i == 1u && byte_i == 6u) return 115u;
    if (import_i == 1u && byte_i == 7u) return 116u;
    if (import_i == 1u && byte_i == 8u) return 100u;
    if (import_i == 1u && byte_i == 9u) return 111u;
    if (import_i == 1u && byte_i == 10u) return 117u;
    if (import_i == 1u && byte_i == 11u) return 116u;
    if (import_i == 2u && byte_i == 0u) return 97u;
    if (import_i == 2u && byte_i == 1u) return 114u;
    if (import_i == 2u && byte_i == 2u) return 103u;
    if (import_i == 2u && byte_i == 3u) return 99u;
    if (import_i == 3u && byte_i == 0u) return 97u;
    if (import_i == 3u && byte_i == 1u) return 114u;
    if (import_i == 3u && byte_i == 2u) return 103u;
    if (import_i == 3u && byte_i == 3u) return 95u;
    if (import_i == 3u && byte_i == 4u) return 108u;
    if (import_i == 3u && byte_i == 5u) return 101u;
    if (import_i == 3u && byte_i == 6u) return 110u;
    if (import_i == 4u && byte_i == 0u) return 97u;
    if (import_i == 4u && byte_i == 1u) return 114u;
    if (import_i == 4u && byte_i == 2u) return 103u;
    if (import_i == 4u && byte_i == 3u) return 95u;
    if (import_i == 4u && byte_i == 4u) return 114u;
    if (import_i == 4u && byte_i == 5u) return 101u;
    if (import_i == 4u && byte_i == 6u) return 97u;
    if (import_i == 4u && byte_i == 7u) return 100u;
    if (import_i == 5u && byte_i == 0u) return 115u;
    if (import_i == 5u && byte_i == 1u) return 101u;
    if (import_i == 5u && byte_i == 2u) return 99u;
    if (import_i == 5u && byte_i == 3u) return 117u;
    if (import_i == 5u && byte_i == 4u) return 114u;
    if (import_i == 5u && byte_i == 5u) return 101u;
    if (import_i == 5u && byte_i == 6u) return 95u;
    if (import_i == 5u && byte_i == 7u) return 117u;
    if (import_i == 5u && byte_i == 8u) return 51u;
    if (import_i == 5u && byte_i == 9u) return 50u;
    if (import_i == 6u && byte_i == 0u) return 117u;
    if (import_i == 6u && byte_i == 1u) return 110u;
    if (import_i == 6u && byte_i == 2u) return 105u;
    if (import_i == 6u && byte_i == 3u) return 120u;
    if (import_i == 6u && byte_i == 4u) return 95u;
    if (import_i == 6u && byte_i == 5u) return 115u;
    if (import_i == 6u && byte_i == 6u) return 101u;
    if (import_i == 6u && byte_i == 7u) return 99u;
    if (import_i == 6u && byte_i == 8u) return 111u;
    if (import_i == 6u && byte_i == 9u) return 110u;
    if (import_i == 6u && byte_i == 10u) return 100u;
    if (import_i == 6u && byte_i == 11u) return 115u;
    if (import_i == 7u && byte_i == 0u) return 99u;
    if (import_i == 7u && byte_i == 1u) return 117u;
    if (import_i == 7u && byte_i == 2u) return 114u;
    if (import_i == 7u && byte_i == 3u) return 114u;
    if (import_i == 7u && byte_i == 4u) return 101u;
    if (import_i == 7u && byte_i == 5u) return 110u;
    if (import_i == 7u && byte_i == 6u) return 116u;
    if (import_i == 7u && byte_i == 7u) return 95u;
    if (import_i == 7u && byte_i == 8u) return 100u;
    if (import_i == 7u && byte_i == 9u) return 105u;
    if (import_i == 7u && byte_i == 10u) return 114u;
    if (import_i == 7u && byte_i == 11u) return 95u;
    if (import_i == 7u && byte_i == 12u) return 114u;
    if (import_i == 7u && byte_i == 13u) return 101u;
    if (import_i == 7u && byte_i == 14u) return 97u;
    if (import_i == 7u && byte_i == 15u) return 100u;
    if (import_i == 8u && byte_i == 0u) return 99u;
    if (import_i == 8u && byte_i == 1u) return 117u;
    if (import_i == 8u && byte_i == 2u) return 114u;
    if (import_i == 8u && byte_i == 3u) return 114u;
    if (import_i == 8u && byte_i == 4u) return 101u;
    if (import_i == 8u && byte_i == 5u) return 110u;
    if (import_i == 8u && byte_i == 6u) return 116u;
    if (import_i == 8u && byte_i == 7u) return 95u;
    if (import_i == 8u && byte_i == 8u) return 100u;
    if (import_i == 8u && byte_i == 9u) return 105u;
    if (import_i == 8u && byte_i == 10u) return 114u;
    if (import_i == 8u && byte_i == 11u) return 95u;
    if (import_i == 8u && byte_i == 12u) return 108u;
    if (import_i == 8u && byte_i == 13u) return 101u;
    if (import_i == 8u && byte_i == 14u) return 110u;
    if (import_i == 9u && byte_i == 0u) return 118u;
    if (import_i == 9u && byte_i == 1u) return 97u;
    if (import_i == 9u && byte_i == 2u) return 114u;
    if (import_i == 9u && byte_i == 3u) return 95u;
    if (import_i == 9u && byte_i == 4u) return 99u;
    if (import_i == 9u && byte_i == 5u) return 111u;
    if (import_i == 9u && byte_i == 6u) return 117u;
    if (import_i == 9u && byte_i == 7u) return 110u;
    if (import_i == 9u && byte_i == 8u) return 116u;
    if (import_i == 10u && byte_i == 0u) return 118u;
    if (import_i == 10u && byte_i == 1u) return 97u;
    if (import_i == 10u && byte_i == 2u) return 114u;
    if (import_i == 10u && byte_i == 3u) return 95u;
    if (import_i == 10u && byte_i == 4u) return 107u;
    if (import_i == 10u && byte_i == 5u) return 101u;
    if (import_i == 10u && byte_i == 6u) return 121u;
    if (import_i == 10u && byte_i == 7u) return 95u;
    if (import_i == 10u && byte_i == 8u) return 108u;
    if (import_i == 10u && byte_i == 9u) return 101u;
    if (import_i == 10u && byte_i == 10u) return 110u;
    if (import_i == 11u && byte_i == 0u) return 118u;
    if (import_i == 11u && byte_i == 1u) return 97u;
    if (import_i == 11u && byte_i == 2u) return 114u;
    if (import_i == 11u && byte_i == 3u) return 95u;
    if (import_i == 11u && byte_i == 4u) return 107u;
    if (import_i == 11u && byte_i == 5u) return 101u;
    if (import_i == 11u && byte_i == 6u) return 121u;
    if (import_i == 11u && byte_i == 7u) return 95u;
    if (import_i == 11u && byte_i == 8u) return 114u;
    if (import_i == 11u && byte_i == 9u) return 101u;
    if (import_i == 11u && byte_i == 10u) return 97u;
    if (import_i == 11u && byte_i == 11u) return 100u;
    if (import_i == 12u && byte_i == 0u) return 118u;
    if (import_i == 12u && byte_i == 1u) return 97u;
    if (import_i == 12u && byte_i == 2u) return 114u;
    if (import_i == 12u && byte_i == 3u) return 95u;
    if (import_i == 12u && byte_i == 4u) return 108u;
    if (import_i == 12u && byte_i == 5u) return 101u;
    if (import_i == 12u && byte_i == 6u) return 110u;
    if (import_i == 13u && byte_i == 0u) return 118u;
    if (import_i == 13u && byte_i == 1u) return 97u;
    if (import_i == 13u && byte_i == 2u) return 114u;
    if (import_i == 13u && byte_i == 3u) return 95u;
    if (import_i == 13u && byte_i == 4u) return 114u;
    if (import_i == 13u && byte_i == 5u) return 101u;
    if (import_i == 13u && byte_i == 6u) return 97u;
    if (import_i == 13u && byte_i == 7u) return 100u;
    if (import_i == 14u && byte_i == 0u) return 99u;
    if (import_i == 14u && byte_i == 1u) return 108u;
    if (import_i == 14u && byte_i == 2u) return 111u;
    if (import_i == 14u && byte_i == 3u) return 115u;
    if (import_i == 14u && byte_i == 4u) return 101u;
    if (import_i == 15u && byte_i == 0u) return 114u;
    if (import_i == 15u && byte_i == 1u) return 101u;
    if (import_i == 15u && byte_i == 2u) return 97u;
    if (import_i == 15u && byte_i == 3u) return 100u;
    if (import_i == 16u && byte_i == 0u) return 119u;
    if (import_i == 16u && byte_i == 1u) return 114u;
    if (import_i == 16u && byte_i == 2u) return 105u;
    if (import_i == 16u && byte_i == 3u) return 116u;
    if (import_i == 16u && byte_i == 4u) return 101u;
    if (import_i == 17u && byte_i == 0u) return 111u;
    if (import_i == 17u && byte_i == 1u) return 112u;
    if (import_i == 17u && byte_i == 2u) return 101u;
    if (import_i == 17u && byte_i == 3u) return 110u;
    if (import_i == 17u && byte_i == 4u) return 95u;
    if (import_i == 17u && byte_i == 5u) return 114u;
    if (import_i == 17u && byte_i == 6u) return 101u;
    if (import_i == 17u && byte_i == 7u) return 97u;
    if (import_i == 17u && byte_i == 8u) return 100u;
    if (import_i == 18u && byte_i == 0u) return 111u;
    if (import_i == 18u && byte_i == 1u) return 112u;
    if (import_i == 18u && byte_i == 2u) return 101u;
    if (import_i == 18u && byte_i == 3u) return 110u;
    if (import_i == 18u && byte_i == 4u) return 95u;
    if (import_i == 18u && byte_i == 5u) return 119u;
    if (import_i == 18u && byte_i == 6u) return 114u;
    if (import_i == 18u && byte_i == 7u) return 105u;
    if (import_i == 18u && byte_i == 8u) return 116u;
    if (import_i == 18u && byte_i == 9u) return 101u;
    if (import_i == 19u && byte_i == 0u) return 111u;
    if (import_i == 19u && byte_i == 1u) return 112u;
    if (import_i == 19u && byte_i == 2u) return 101u;
    if (import_i == 19u && byte_i == 3u) return 110u;
    if (import_i == 19u && byte_i == 4u) return 95u;
    if (import_i == 19u && byte_i == 5u) return 97u;
    if (import_i == 19u && byte_i == 6u) return 112u;
    if (import_i == 19u && byte_i == 7u) return 112u;
    if (import_i == 19u && byte_i == 8u) return 101u;
    if (import_i == 19u && byte_i == 9u) return 110u;
    if (import_i == 19u && byte_i == 10u) return 100u;
    if (import_i == 20u && byte_i == 0u) return 119u;
    if (import_i == 20u && byte_i == 1u) return 114u;
    if (import_i == 20u && byte_i == 2u) return 105u;
    if (import_i == 20u && byte_i == 3u) return 116u;
    if (import_i == 20u && byte_i == 4u) return 101u;
    if (import_i == 20u && byte_i == 5u) return 95u;
    if (import_i == 20u && byte_i == 6u) return 115u;
    if (import_i == 20u && byte_i == 7u) return 116u;
    if (import_i == 20u && byte_i == 8u) return 100u;
    if (import_i == 20u && byte_i == 9u) return 101u;
    if (import_i == 20u && byte_i == 10u) return 114u;
    if (import_i == 20u && byte_i == 11u) return 114u;
    if (import_i == 21u && byte_i == 0u) return 114u;
    if (import_i == 21u && byte_i == 1u) return 101u;
    if (import_i == 21u && byte_i == 2u) return 97u;
    if (import_i == 21u && byte_i == 3u) return 100u;
    if (import_i == 21u && byte_i == 4u) return 95u;
    if (import_i == 21u && byte_i == 5u) return 115u;
    if (import_i == 21u && byte_i == 6u) return 116u;
    if (import_i == 21u && byte_i == 7u) return 100u;
    if (import_i == 21u && byte_i == 8u) return 105u;
    if (import_i == 21u && byte_i == 9u) return 110u;
    if (import_i == 22u && byte_i == 0u) return 97u;
    if (import_i == 22u && byte_i == 1u) return 108u;
    if (import_i == 22u && byte_i == 2u) return 108u;
    if (import_i == 22u && byte_i == 3u) return 111u;
    if (import_i == 22u && byte_i == 4u) return 99u;
    if (import_i == 23u && byte_i == 0u) return 100u;
    if (import_i == 23u && byte_i == 1u) return 101u;
    if (import_i == 23u && byte_i == 2u) return 97u;
    if (import_i == 23u && byte_i == 3u) return 108u;
    if (import_i == 23u && byte_i == 4u) return 108u;
    if (import_i == 23u && byte_i == 5u) return 111u;
    if (import_i == 23u && byte_i == 6u) return 99u;
    if (import_i == 24u && byte_i == 0u) return 114u;
    if (import_i == 24u && byte_i == 1u) return 101u;
    if (import_i == 24u && byte_i == 2u) return 97u;
    if (import_i == 24u && byte_i == 3u) return 100u;
    if (import_i == 24u && byte_i == 4u) return 95u;
    if (import_i == 24u && byte_i == 5u) return 105u;
    if (import_i == 24u && byte_i == 6u) return 51u;
    if (import_i == 24u && byte_i == 7u) return 50u;
    if (import_i == 25u && byte_i == 0u) return 119u;
    if (import_i == 25u && byte_i == 1u) return 114u;
    if (import_i == 25u && byte_i == 2u) return 105u;
    if (import_i == 25u && byte_i == 3u) return 116u;
    if (import_i == 25u && byte_i == 4u) return 101u;
    if (import_i == 25u && byte_i == 5u) return 95u;
    if (import_i == 25u && byte_i == 6u) return 105u;
    if (import_i == 25u && byte_i == 7u) return 51u;
    if (import_i == 25u && byte_i == 8u) return 50u;
    if (import_i == 26u && byte_i == 0u) return 119u;
    if (import_i == 26u && byte_i == 1u) return 114u;
    if (import_i == 26u && byte_i == 2u) return 105u;
    if (import_i == 26u && byte_i == 3u) return 116u;
    if (import_i == 26u && byte_i == 4u) return 101u;
    if (import_i == 26u && byte_i == 5u) return 95u;
    if (import_i == 26u && byte_i == 6u) return 98u;
    if (import_i == 26u && byte_i == 7u) return 121u;
    if (import_i == 26u && byte_i == 8u) return 116u;
    if (import_i == 26u && byte_i == 9u) return 101u;
    if (import_i == 27u && byte_i == 0u) return 119u;
    if (import_i == 27u && byte_i == 1u) return 114u;
    if (import_i == 27u && byte_i == 2u) return 105u;
    if (import_i == 27u && byte_i == 3u) return 116u;
    if (import_i == 27u && byte_i == 4u) return 101u;
    if (import_i == 27u && byte_i == 5u) return 95u;
    if (import_i == 27u && byte_i == 6u) return 110u;
    if (import_i == 27u && byte_i == 7u) return 101u;
    if (import_i == 27u && byte_i == 8u) return 119u;
    if (import_i == 27u && byte_i == 9u) return 108u;
    if (import_i == 27u && byte_i == 10u) return 105u;
    if (import_i == 27u && byte_i == 11u) return 110u;
    if (import_i == 27u && byte_i == 12u) return 101u;
    if (import_i == 28u && byte_i == 0u) return 111u;
    if (import_i == 28u && byte_i == 1u) return 112u;
    if (import_i == 28u && byte_i == 2u) return 101u;
    if (import_i == 28u && byte_i == 3u) return 110u;
    if (import_i == 28u && byte_i == 4u) return 95u;
    if (import_i == 28u && byte_i == 5u) return 114u;
    if (import_i == 28u && byte_i == 6u) return 101u;
    if (import_i == 28u && byte_i == 7u) return 97u;
    if (import_i == 28u && byte_i == 8u) return 100u;
    if (import_i == 28u && byte_i == 9u) return 95u;
    if (import_i == 28u && byte_i == 10u) return 112u;
    if (import_i == 28u && byte_i == 11u) return 97u;
    if (import_i == 28u && byte_i == 12u) return 116u;
    if (import_i == 28u && byte_i == 13u) return 104u;
    if (import_i == 29u && byte_i == 0u) return 111u;
    if (import_i == 29u && byte_i == 1u) return 112u;
    if (import_i == 29u && byte_i == 2u) return 101u;
    if (import_i == 29u && byte_i == 3u) return 110u;
    if (import_i == 29u && byte_i == 4u) return 95u;
    if (import_i == 29u && byte_i == 5u) return 119u;
    if (import_i == 29u && byte_i == 6u) return 114u;
    if (import_i == 29u && byte_i == 7u) return 105u;
    if (import_i == 29u && byte_i == 8u) return 116u;
    if (import_i == 29u && byte_i == 9u) return 101u;
    if (import_i == 29u && byte_i == 10u) return 95u;
    if (import_i == 29u && byte_i == 11u) return 112u;
    if (import_i == 29u && byte_i == 12u) return 97u;
    if (import_i == 29u && byte_i == 13u) return 116u;
    if (import_i == 29u && byte_i == 14u) return 104u;
    if (import_i == 30u && byte_i == 0u) return 119u;
    if (import_i == 30u && byte_i == 1u) return 114u;
    if (import_i == 30u && byte_i == 2u) return 105u;
    if (import_i == 30u && byte_i == 3u) return 116u;
    if (import_i == 30u && byte_i == 4u) return 101u;
    if (import_i == 30u && byte_i == 5u) return 95u;
    if (import_i == 30u && byte_i == 6u) return 116u;
    if (import_i == 30u && byte_i == 7u) return 101u;
    if (import_i == 30u && byte_i == 8u) return 120u;
    if (import_i == 30u && byte_i == 9u) return 116u;
    return 0u;
}

uint import_entry_len(uint import_i)
{
    return 7u + import_name_len(import_i);
}

uint import_entry_byte(uint import_i, uint pos)
{
    uint name_len = import_name_len(import_i);
    if (pos == 0u) return 3u;
    if (pos == 1u) return 101u;
    if (pos == 2u) return 110u;
    if (pos == 3u) return 118u;
    if (pos == 4u) return name_len;
    if (pos >= 5u && pos < 5u + name_len)
        return import_name_byte(import_i, pos - 5u);
    if (pos == 5u + name_len) return 0u;
    if (pos == 6u + name_len) return import_type_index(import_i);
    return 0u;
}

uint import_section_byte(uint pos)
{
    if (pos == 0u) return 2u;
    if (pos >= 1u && pos < 6u) return leb5_byte(IMPORT_SECTION_PAYLOAD_LEN, pos - 1u);
    if (pos == 6u) return WASM_IMPORT_FUNCTION_COUNT;

    uint entry_pos = pos - 7u;
    uint offset = 0u;
    for (uint import_i = 0u; import_i < WASM_IMPORT_FUNCTION_COUNT; import_i += 1u)
    {
        uint len = import_entry_len(import_i);
        if (entry_pos < offset + len)
            return import_entry_byte(import_i, entry_pos - offset);
        offset += len;
    }
    return 0u;
}

uint function_section_len(uint function_count)
{
    return 11u + function_count * 5u;
}

uint function_section_byte(uint pos, uint function_count)
{
    if (pos == 0u) return 3u;
    uint payload_len = 5u + function_count * 5u;
    if (pos >= 1u && pos < 6u) return leb5_byte(payload_len, pos - 1u);
    if (pos >= 6u && pos < 11u) return leb5_byte(function_count, pos - 6u);

    uint rel = pos - 11u;
    uint slot = rel / 5u;
    uint byte_i = rel - slot * 5u;
    if (slot >= function_count)
        return 0u;

    return leb5_byte(TYPE_COUNT + slot, byte_i);
}

uint memory_page_count()
{
    uint source_end = (gParams.n_tokens + 1u) * 4u + gParams.source_len;
    uint bytes = ((source_end + 3u) & ~3u) + gParams.n_tokens * 4u;
    return max(1u, (bytes + 65535u) / 65536u);
}

uint source_data_base()
{
    return (gParams.n_tokens + 1u) * 4u;
}

uint memory_section_byte(uint pos)
{
    if (pos == 0u) return 5u;
    if (pos >= 1u && pos < 6u) return leb5_byte(11u, pos - 1u);
    if (pos >= 6u && pos < 11u) return leb5_byte(1u, pos - 6u);
    if (pos == 11u) return 0u;
    if (pos >= 12u && pos < 17u) return leb5_byte(memory_page_count(), pos - 12u);
    return 0u;
}

uint export_section_byte(uint pos, uint main_slot)
{
    if (pos == 0u) return 7u;
    if (pos >= 1u && pos < 6u) return leb5_byte(25u, pos - 1u);
    if (pos == 6u) return 2u;
    if (pos == 7u) return 4u;
    if (pos == 8u) return 109u;
    if (pos == 9u) return 97u;
    if (pos == 10u) return 105u;
    if (pos == 11u) return 110u;
    if (pos == 12u) return 0u;
    if (pos >= 13u && pos < 18u) return leb5_byte(WASM_IMPORT_FUNCTION_COUNT + main_slot, pos - 13u);
    if (pos == 18u) return 6u;
    if (pos == 19u) return 109u;
    if (pos == 20u) return 101u;
    if (pos == 21u) return 109u;
    if (pos == 22u) return 111u;
    if (pos == 23u) return 114u;
    if (pos == 24u) return 121u;
    if (pos == 25u) return 2u;
    if (pos >= 26u && pos < 31u) return leb5_byte(0u, pos - 26u);
    return 0u;
}

uint code_header_len()
{
    return 11u;
}

uint code_section_byte(uint pos, uint function_count, uint body_len)
{
    if (pos == 0u) return 10u;
    if (pos >= 1u && pos < 6u) return leb5_byte(5u + body_len, pos - 1u);
    if (pos >= 6u && pos < 11u) return leb5_byte(function_count, pos - 6u);
    return 0u;
}

uint data_section_len()
{
    return 24u + gParams.source_len;
}

uint data_section_byte(uint pos)
{
    if (pos == 0u) return 11u;
    if (pos >= 1u && pos < 6u) return leb5_byte(18u + gParams.source_len, pos - 1u);
    if (pos >= 6u && pos < 11u) return leb5_byte(1u, pos - 6u);
    if (pos == 11u) return 0u;
    if (pos == 12u) return 0x41u;
    if (pos >= 13u && pos < 18u) return leb5_byte(source_data_base(), pos - 13u);
    if (pos == 18u) return 0x0bu;
    if (pos >= 19u && pos < 24u) return leb5_byte(gParams.source_len, pos - 19u);
    return source_byte(pos - 24u);
}

uint module_body_start(uint function_count)
{
    return 8u +
           type_section_len(function_count) +
           IMPORT_SECTION_LEN +
           function_section_len(function_count) +
           MEMORY_SECTION_LEN +
           EXPORT_SECTION_LEN +
           code_header_len();
}

uint module_byte(uint pos, uint body_len, uint module_len)
{
    if (pos >= module_len)
        return 0u;
    if (pos == 0u) return 0x00u;
    if (pos == 1u) return 0x61u;
    if (pos == 2u) return 0x73u;
    if (pos == 3u) return 0x6du;
    if (pos == 4u) return 0x01u;
    if (pos == 5u) return 0x00u;
    if (pos == 6u) return 0x00u;
    if (pos == 7u) return 0x00u;

    uint function_count = body_plan[BODY_PLAN_FUNCTION_COUNT];
    uint main_slot = body_plan[BODY_PLAN_MAIN_SLOT];
    uint type_start = 8u;
    uint import_start = type_start + type_section_len(function_count);
    uint func_start = import_start + IMPORT_SECTION_LEN;
    uint func_len = function_section_len(function_count);
    uint memory_start = func_start + func_len;
    uint export_start = memory_start + MEMORY_SECTION_LEN;
    uint code_start = export_start + EXPORT_SECTION_LEN;
    uint body_start = code_start + code_header_len();
    uint data_start = body_start + body_len;

    if (pos < import_start)
        return type_section_byte(pos - type_start, function_count);
    if (pos < func_start)
        return import_section_byte(pos - import_start);
    if (pos < memory_start)
        return function_section_byte(pos - func_start, function_count);
    if (pos < export_start)
        return memory_section_byte(pos - memory_start);
    if (pos < code_start)
        return export_section_byte(pos - export_start, main_slot);
    if (pos < body_start)
        return code_section_byte(pos - code_start, function_count, body_len);
    if (pos < data_start)
        return body_byte(pos - body_start);
    return data_section_byte(pos - data_start);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[1u] == 1u || status[1u] == 2u || status[1u] == 5u || status[2u] != 0u)
        return;

    uint body_len = body_status[0u];
    bool body_ok = body_status[1u] != 0u;
    uint module_len =
        module_body_start(body_plan[BODY_PLAN_FUNCTION_COUNT]) + body_len + data_section_len();
    bool ok = body_ok && module_len <= gParams.out_capacity;

    if (!ok)
        return;

    uint word_i = linear_dispatch_id(tid);
    uint word_count = (module_len + 3u) / 4u;
    if (word_i >= word_count)
        return;

    uint pos = word_i * 4u;
    out_words[word_i] = pack_u8x4(
        module_byte(pos + 0u, body_len, module_len),
        module_byte(pos + 1u, body_len, module_len),
        module_byte(pos + 2u, body_len, module_len),
        module_byte(pos + 3u, body_len, module_len));
}
