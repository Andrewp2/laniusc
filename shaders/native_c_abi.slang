// Explicit source ABI classification shared by checked semantic projection and
// hidden declaration retention. The parser owns declaration/name token spans;
// this reads only that declaration's optional ABI literal on the GPU.
import hir_records;
import primitive_types;

public struct NativeAbiToken { public uint kind; public uint start; public uint len; };
public static const uint NATIVE_ABI_NONE = 0u;
public static const uint NATIVE_ABI_C = 1u;
public static const uint SOURCE_ABI_LANIUS_STD = 2u;
public static const uint SOURCE_ABI_LANIUS_ALLOC = 3u;
public static const uint SOURCE_ABI_LANIUS_LINUX = 4u;
public static const uint SOURCE_ABI_OTHER = 5u;
public static const uint NATIVE_C_MAX_PARAMETERS = 32u;

uint abi_byte(ByteAddressBuffer bytes, uint offset)
{
    return (bytes.Load(offset & ~3u) >> ((offset & 3u) * 8u)) & 255u;
}

public uint native_extern_source_abi(HirCore core, HirPayload payload,
    StructuredBuffer<NativeAbiToken> tokens, ByteAddressBuffer bytes,
    uint token_capacity, uint source_len)
{
    // An extern with an ABI has `extern STRING fn NAME`; the optional-ABI
    // parser production determines the published NAME token.
    if (core.kind != 3u || payload.a != 5u ||
        core.token_start >= token_capacity || payload.b != core.token_start + 3u)
        return NATIVE_ABI_NONE;
    uint token = core.token_start + 1u;
    if (token >= token_capacity) return SOURCE_ABI_OTHER;
    NativeAbiToken word = tokens[token];
    if (word.start > source_len || word.len > source_len - word.start || word.len < 2u ||
        abi_byte(bytes, word.start) != 34u || abi_byte(bytes, word.start + word.len - 1u) != 34u)
        return SOURCE_ABI_OTHER;
    uint start = word.start + 1u;
    if (word.len == 3u && abi_byte(bytes, start) == 67u) return NATIVE_ABI_C;
    static const uint runtime_prefix[7] = {108u, 97u, 110u, 105u, 117u, 115u, 95u};
    if (word.len != 12u && word.len != 14u) return SOURCE_ABI_OTHER;
    for (uint i = 0u; i < 7u; i++)
        if (abi_byte(bytes, start + i) != runtime_prefix[i]) return SOURCE_ABI_OTHER;
    if (word.len == 12u && abi_byte(bytes, start + 7u) == 115u &&
        abi_byte(bytes, start + 8u) == 116u && abi_byte(bytes, start + 9u) == 100u)
        return SOURCE_ABI_LANIUS_STD;
    static const uint allocation_suffix[5] = {97u, 108u, 108u, 111u, 99u};
    static const uint linux_suffix[5] = {108u, 105u, 110u, 117u, 120u};
    if (word.len == 14u)
    {
        bool allocation = true;
        bool linux = true;
        for (uint i = 0u; i < 5u; i++)
        {
            uint byte = abi_byte(bytes, start + 7u + i);
            allocation = allocation && byte == allocation_suffix[i];
            linux = linux && byte == linux_suffix[i];
        }
        if (allocation) return SOURCE_ABI_LANIUS_ALLOC;
        if (linux) return SOURCE_ABI_LANIUS_LINUX;
    }
    return SOURCE_ABI_OTHER;
}

public bool native_c_scalar(uint scalar, bool result)
{
    return scalar == SCALAR_I32 || scalar == SCALAR_U32 || scalar == SCALAR_I64 ||
        scalar == SCALAR_U64 || scalar == SCALAR_ISIZE || scalar == SCALAR_USIZE ||
        scalar == SCALAR_PTR || (result && scalar == SCALAR_UNIT);
}
