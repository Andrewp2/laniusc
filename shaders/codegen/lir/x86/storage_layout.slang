// Storage capabilities of the current native ABI. A checked value width does
// not establish an address layout: packed i32 places, native aggregate words,
// and pointer/length descriptors are distinct. Borrowing cannot convert them.
import codegen.lowering_ir;
import codegen.optimization_ir;

static const uint X86_STORAGE_NATIVE_WORDS = 1u;
static const uint X86_STORAGE_PACKED_I32 = 2u;
static const uint X86_STORAGE_DIRECT_DESCRIPTOR = 3u;
static const uint X86_STORAGE_INDIRECT_DESCRIPTOR = 4u;
static const uint X86_NATIVE_WORD_BYTES = 8u;
static const uint X86_PACKED_I32_BYTES = 4u;

uint x86_array_storage_kind(OptIrNodeCore value, bool packed_literal)
{
    uint op = opt_ir_op(value);
    if ((value.flags & SEMANTIC_LIR_FLAG_NATIVE_PLACE) != 0u &&
        (value.flags & SEMANTIC_LIR_FLAG_ARRAY_PAIR) == 0u) return X86_STORAGE_NATIVE_WORDS;
    if (packed_literal) return X86_STORAGE_PACKED_I32;
    if ((value.flags & SEMANTIC_LIR_FLAG_ARRAY_PAIR) != 0u)
        return (op == SEMANTIC_LIR_OP_VALUE_GET || op == SEMANTIC_LIR_OP_PLACE_LOAD) ? X86_STORAGE_DIRECT_DESCRIPTOR
            : X86_STORAGE_INDIRECT_DESCRIPTOR;
    if (value.type_id == 131u && op != SEMANTIC_LIR_OP_CALL &&
        op != SEMANTIC_LIR_OP_CALL_SYMBOL && op != SEMANTIC_LIR_OP_LOAD)
        return X86_STORAGE_PACKED_I32;
    return X86_STORAGE_NATIVE_WORDS;
}

// A view construction publishes the backing convention once. Consumers use
// this signed byte stride without changing its type or specialization identity.
bool x86_fixed_array_stride(uint storage, uint words, uint length, out uint stride)
{
    stride = 0u;
    if (storage == X86_STORAGE_PACKED_I32) { stride = 4u; return true; }
    if (storage != X86_STORAGE_NATIVE_WORDS) return false;
    if (length == 0u) return words == 0u;
    if (words == 0xffffffffu || words % length != 0u || words / length > 0x0fffffffu)
        return false;
    stride = 0u - (words / length) * X86_NATIVE_WORD_BYTES;
    return true;
}

uint x86_native_word_displacement(uint ordinal)
{ return 0u - ordinal * X86_NATIVE_WORD_BYTES; }

uint x86_packed_i32_element_offset(uint ordinal)
{ return ordinal * X86_PACKED_I32_BYTES; }
