import codegen.lowering_ir;
import codegen.lir.wasm.host_abi;

static const uint WASM_MODULE_INVALID = 0xffffffffu;
static const uint WASM_MODULE_I32 = 0x7fu;
static const uint WASM_MODULE_F32 = 0x7du;
static const uint WASM_MODULE_TY_FLOAT = 5u;
static const uint WASM_MODULE_TY_STRING = 7u;
static const uint WASM_MODULE_FUNCTION_ENTRYPOINT = 1u;

uint wasm_module_leb5_byte(uint value, uint byte_i)
{
    uint part = (value >> (byte_i * 7u)) & 0x7fu;
    return byte_i < 4u ? part | 0x80u : part;
}

uint wasm_module_value_type(uint type_id)
{
    return type_id == WASM_MODULE_TY_FLOAT ? WASM_MODULE_F32 : WASM_MODULE_I32;
}

uint wasm_module_result_count(uint type_id)
{
    if (type_id == 0u || type_id == 1u) return 0u;
    return type_id == WASM_MODULE_TY_STRING ? 2u : 1u;
}

void wasm_module_store_byte(RWStructuredBuffer<uint> words, uint capacity,
                            uint pos, uint value)
{
    if (pos >= capacity) return;
    uint word_i = pos >> 2u;
    uint shift = (pos & 3u) * 8u;
    uint mask = 0xffu << shift;
    uint old_value = words[word_i];
    for (;;)
    {
        uint next = (old_value & ~mask) | ((value & 0xffu) << shift);
        uint prior;
        InterlockedCompareExchange(words[word_i], old_value, next, prior);
        if (prior == old_value) return;
        old_value = prior;
    }
}

uint wasm_module_load_byte(StructuredBuffer<uint> words, uint pos)
{
    return (words[pos >> 2u] >> ((pos & 3u) * 8u)) & 0xffu;
}
