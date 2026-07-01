import byte_packing;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> body_words;
StructuredBuffer<uint> body_status;
StructuredBuffer<uint> body_plan;
StructuredBuffer<uint> wasm_func_token_by_slot;
StructuredBuffer<uint> call_param_count;
RWStructuredBuffer<uint> out_words;
StructuredBuffer<uint> status;

static const uint WORKGROUP_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint TYPE_SECTION_LEN = 41u;
static const uint IMPORT_SECTION_LEN = 118u;
static const uint MEMORY_SECTION_LEN = 17u;
static const uint EXPORT_SECTION_LEN = 31u;
static const uint WASM_IMPORT_FUNCTION_COUNT = 7u;
static const uint BODY_PLAN_FUNCTION_COUNT = 31u;
static const uint BODY_PLAN_MAIN_SLOT = 34u;
static const uint INVALID = 0xffffffffu;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint body_byte(uint i)
{
    return body_words[i];
}

uint leb5_byte(uint value, uint i)
{
    uint byte_value = (value >> (i * 7u)) & 0x7fu;
    if (i < 4u)
        byte_value |= 0x80u;
    return byte_value;
}

uint type_payload_byte(uint pos)
{
    if (pos == 0u) return 6u;

    if (pos == 1u) return 0x60u;
    if (pos == 2u) return 1u;
    if (pos == 3u) return 0x7eu;
    if (pos == 4u) return 0u;

    if (pos == 5u) return 0x60u;
    if (pos == 6u) return 0u;
    if (pos == 7u) return 1u;
    if (pos == 8u) return 0x7fu;

    if (pos == 9u) return 0x60u;
    if (pos == 10u) return 1u;
    if (pos == 11u) return 0x7fu;
    if (pos == 12u) return 1u;
    if (pos == 13u) return 0x7fu;

    if (pos == 14u) return 0x60u;
    if (pos == 15u) return 2u;
    if (pos == 16u) return 0x7fu;
    if (pos == 17u) return 0x7fu;
    if (pos == 18u) return 1u;
    if (pos == 19u) return 0x7fu;

    if (pos == 20u) return 0x60u;
    if (pos == 21u) return 3u;
    if (pos == 22u) return 0x7fu;
    if (pos == 23u) return 0x7fu;
    if (pos == 24u) return 0x7fu;
    if (pos == 25u) return 1u;
    if (pos == 26u) return 0x7fu;

    if (pos == 27u) return 0x60u;
    if (pos == 28u) return 4u;
    if (pos == 29u) return 0x7fu;
    if (pos == 30u) return 0x7fu;
    if (pos == 31u) return 0x7fu;
    if (pos == 32u) return 0x7fu;
    if (pos == 33u) return 1u;
    if (pos == 34u) return 0x7fu;
    return 0u;
}

uint type_section_byte(uint pos)
{
    if (pos == 0u) return 1u;
    if (pos >= 1u && pos < 6u) return leb5_byte(35u, pos - 1u);
    return type_payload_byte(pos - 6u);
}

uint import_section_byte(uint pos)
{
    if (pos == 0u) return 2u;
    if (pos >= 1u && pos < 6u) return leb5_byte(112u, pos - 1u);
    if (pos == 6u) return 7u;
    if (pos == 7u) return 3u;
    if (pos == 8u) return 101u;
    if (pos == 9u) return 110u;
    if (pos == 10u) return 118u;
    if (pos == 11u) return 9u;
    if (pos == 12u) return 112u;
    if (pos == 13u) return 114u;
    if (pos == 14u) return 105u;
    if (pos == 15u) return 110u;
    if (pos == 16u) return 116u;
    if (pos == 17u) return 95u;
    if (pos == 18u) return 105u;
    if (pos == 19u) return 54u;
    if (pos == 20u) return 52u;
    if (pos == 21u) return 0u;
    if (pos == 23u) return 3u;
    if (pos == 24u) return 101u;
    if (pos == 25u) return 110u;
    if (pos == 26u) return 118u;
    if (pos == 27u) return 12u;
    if (pos == 28u) return 119u;
    if (pos == 29u) return 114u;
    if (pos == 30u) return 105u;
    if (pos == 31u) return 116u;
    if (pos == 32u) return 101u;
    if (pos == 33u) return 95u;
    if (pos == 34u) return 115u;
    if (pos == 35u) return 116u;
    if (pos == 36u) return 100u;
    if (pos == 37u) return 111u;
    if (pos == 38u) return 117u;
    if (pos == 39u) return 116u;
    if (pos == 40u) return 0u;
    if (pos == 41u) return 3u;
    if (pos == 42u) return 3u;
    if (pos == 43u) return 101u;
    if (pos == 44u) return 110u;
    if (pos == 45u) return 118u;
    if (pos == 46u) return 4u;
    if (pos == 47u) return 97u;
    if (pos == 48u) return 114u;
    if (pos == 49u) return 103u;
    if (pos == 50u) return 99u;
    if (pos == 51u) return 0u;
    if (pos == 52u) return 1u;
    if (pos == 53u) return 3u;
    if (pos == 54u) return 101u;
    if (pos == 55u) return 110u;
    if (pos == 56u) return 118u;
    if (pos == 57u) return 7u;
    if (pos == 58u) return 97u;
    if (pos == 59u) return 114u;
    if (pos == 60u) return 103u;
    if (pos == 61u) return 95u;
    if (pos == 62u) return 108u;
    if (pos == 63u) return 101u;
    if (pos == 64u) return 110u;
    if (pos == 65u) return 0u;
    if (pos == 66u) return 2u;
    if (pos == 67u) return 3u;
    if (pos == 68u) return 101u;
    if (pos == 69u) return 110u;
    if (pos == 70u) return 118u;
    if (pos == 71u) return 8u;
    if (pos == 72u) return 97u;
    if (pos == 73u) return 114u;
    if (pos == 74u) return 103u;
    if (pos == 75u) return 95u;
    if (pos == 76u) return 114u;
    if (pos == 77u) return 101u;
    if (pos == 78u) return 97u;
    if (pos == 79u) return 100u;
    if (pos == 80u) return 0u;
    if (pos == 81u) return 4u;
    if (pos == 82u) return 3u;
    if (pos == 83u) return 101u;
    if (pos == 84u) return 110u;
    if (pos == 85u) return 118u;
    if (pos == 86u) return 10u;
    if (pos == 87u) return 115u;
    if (pos == 88u) return 101u;
    if (pos == 89u) return 99u;
    if (pos == 90u) return 117u;
    if (pos == 91u) return 114u;
    if (pos == 92u) return 101u;
    if (pos == 93u) return 95u;
    if (pos == 94u) return 117u;
    if (pos == 95u) return 51u;
    if (pos == 96u) return 50u;
    if (pos == 97u) return 0u;
    if (pos == 98u) return 1u;
    if (pos == 99u) return 3u;
    if (pos == 100u) return 101u;
    if (pos == 101u) return 110u;
    if (pos == 102u) return 118u;
    if (pos == 103u) return 12u;
    if (pos == 104u) return 117u;
    if (pos == 105u) return 110u;
    if (pos == 106u) return 105u;
    if (pos == 107u) return 120u;
    if (pos == 108u) return 95u;
    if (pos == 109u) return 115u;
    if (pos == 110u) return 101u;
    if (pos == 111u) return 99u;
    if (pos == 112u) return 111u;
    if (pos == 113u) return 110u;
    if (pos == 114u) return 100u;
    if (pos == 115u) return 115u;
    if (pos == 116u) return 0u;
    if (pos == 117u) return 1u;
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

    uint fn_token = wasm_func_token_by_slot[slot];
    uint param_count = fn_token == INVALID ? 0u : min(call_param_count[fn_token], 4u);
    return leb5_byte(1u + param_count, byte_i);
}

uint memory_page_count()
{
    uint bytes = (gParams.n_tokens + 1u) * 4u;
    return max(1u, (bytes + 65535u) / 65536u);
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

uint module_body_start(uint function_count)
{
    return 8u +
           TYPE_SECTION_LEN +
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
    uint import_start = type_start + TYPE_SECTION_LEN;
    uint func_start = import_start + IMPORT_SECTION_LEN;
    uint func_len = function_section_len(function_count);
    uint memory_start = func_start + func_len;
    uint export_start = memory_start + MEMORY_SECTION_LEN;
    uint code_start = export_start + EXPORT_SECTION_LEN;
    uint body_start = code_start + code_header_len();

    if (pos < import_start)
        return type_section_byte(pos - type_start);
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
    return body_byte(pos - body_start);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[1u] == 1u || status[1u] == 2u || status[1u] == 5u || status[2u] != 0u)
        return;

    uint body_len = body_status[0u];
    bool body_ok = body_status[1u] != 0u;
    uint module_len = module_body_start(body_plan[BODY_PLAN_FUNCTION_COUNT]) + body_len;
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
