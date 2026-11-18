// C-name resolution of the resident x86 link (codegen/x86/link/resident_linking.rs).
//
// The host lists the link's inputs in the GNU linker's order (shared
// objects, archives and the libraries that linker scripts name) and uploads
// each input's exported names, as system inputs. These kernels match the C
// names the program binds against those exports, as
// codegen/x86/native/resolve.rs does: the first shared object that exports
// a name defines it, and an archive whose index names it earlier sends the
// link to the C driver. They then write the dynamic writer's rows, string
// table and parameters, and size the emit dispatches.
//
// They read the plan's status and the referenced-name marks, so they run in
// the plan's submission, after resolve_resident_undefined_symbols.slang.

import shared.buffers.gpu_index;
__exported import shared.buffers.atomics;

public struct CNParams
{
    public uint candidate_count;
    public uint input_count;
    public uint row_count;
    public uint version_count;
    public uint name_mask;
    // The first archive without a symbol index, as a row, or INVALID.
    public uint wild_row;
    public uint gate;
    public uint output_capacity_words;
    public uint dyn_word_capacity;
    public uint string_capacity_bytes;
    public uint symbol_cap_total;
    public uint reloc_cap_total;
    public uint name_count;
    public uint main_bytes;
    public uint reserved_0;
    public uint reserved_1;
};

public ConstantBuffer<CNParams> gCN;

// Export and version names of every input, then this link's candidate names
// and sonames, as bytes.
public StructuredBuffer<uint> cn_bytes;
// Per row: byte offset in its input's block, length, code. A length of
// INVALID is an archive without an index, which may define any name.
public StructuredBuffer<uint> cn_rows;
// Per version: byte offset in its input's block, length. An input's
// versions are sorted by name.
public StructuredBuffer<uint> cn_versions;
// Per input: first row, row count, byte block start, first version, version
// count, soname byte offset, soname length, kind.
public StructuredBuffer<uint> cn_inputs;
// Per candidate: byte offset, length, name slot (INVALID for
// __libc_start_main when the program binds no such name). Candidate 0 is
// __libc_start_main; the others follow in byte order.
public StructuredBuffer<uint> cn_names;

public RWStructuredBuffer<uint> cn_name_hash;
// Per candidate: INVALID - first defining row (0: none), INVALID - first
// archive row (0: none), and whether an export of it has an unreadable
// version.
public RWStructuredBuffer<uint> cn_match;

public static const uint INVALID = 0xffffffffu;
public static const uint CODE_ERROR = 0xffffffffu;
public static const uint CODE_ARCHIVE = 0xfffffffeu;
public static const uint INPUT_WORDS = 8u;
public static const uint KIND_SHARED = 0u;
public static const uint GATE_ON = 1u;

// Result bits (cn_out[CN_BITS]); any bit sends the link to the host.
public static const uint BIT_GATE = 1u;
public static const uint BIT_UNRESOLVED = 2u;
public static const uint BIT_DRIVER = 4u;
public static const uint BIT_VERSION = 8u;
public static const uint BIT_CAPACITY = 16u;
public static const uint BIT_VERSIONS = 32u;
public static const uint BIT_HASH = 64u;

public uint cn_lane(uint3 tid) { return linear_dispatch_thread_id_2d(tid, 16776960u); }

public uint cn_byte(uint index)
{
    return (cn_bytes[index >> 2u] >> ((index & 3u) * 8u)) & 0xffu;
}

public uint name_hash(uint offset, uint len)
{
    uint h = 2166136261u;
    for (uint i = 0u; i < len; i += 1u)
        h = (h ^ cn_byte(offset + i)) * 16777619u;
    h ^= h >> 16u;
    return h;
}

public bool bytes_equal(uint a, uint b, uint len)
{
    for (uint i = 0u; i < len; i += 1u)
    {
        if (cn_byte(a + i) != cn_byte(b + i))
            return false;
    }
    return true;
}

public uint input_word(uint input, uint word) { return cn_inputs[input * INPUT_WORDS + word]; }

// The input that holds row `row` (inputs are in row order).
public uint input_of_row(uint row)
{
    uint found = 0u;
    for (uint k = 0u; k < gCN.input_count; k += 1u)
    {
        if (input_word(k, 0u) <= row)
            found = k;
    }
    return found;
}

public uint input_of_version(uint version)
{
    uint found = 0u;
    for (uint k = 0u; k < gCN.input_count; k += 1u)
    {
        if (input_word(k, 4u) != 0u && input_word(k, 3u) <= version)
            found = k;
    }
    return found;
}
