// Shared bindings of the resident x86 link (codegen/x86/link/resident.rs).
//
// The objects a native build lowers are parked on the GPU when their
// projection is recorded: per slot, the metadata words, relocation rows,
// undefined-symbol rows, definition rows, text and rodata. These kernels
// plan the link, resolve symbols, write the dynamic symbol rows, gather the
// section bytes into the output image and apply the relocations. The host
// reads one status record (with the referenced C import names) and the
// finished image.

import gpu_index;
__exported import atomics;

public struct RLParams
{
    public uint object_count;
    public uint symbol_cap_total;
    public uint reloc_cap_total;
    public uint binding_count;
    public uint hash_mask;
    public uint small_mask;
    public uint route_capacity;
    public uint runtime_cap_max;
    public uint import_count;
    public uint text_len_total;
    public uint output_len;
    public uint dyn_symbol_rows;
    public uint name_count;
    public uint output_word_begin;
    public uint output_word_end;
    public uint reserved;
};

public ConstantBuffer<RLParams> gRL;

// Per slot: reloc base row, reloc cap, runtime reloc base row, runtime cap,
// undefined base row, undefined cap, definition base row, definition cap,
// text base byte, rodata base byte, symbol cap base, relocation cap base,
// text capacity bytes, rodata capacity bytes, then the host object's text
// length, rodata length, relocation count and symbol count, then the
// identity base word, whether the slot has rewritten identities, and the
// metadata base word. A slot's position in the store is not its object's
// link index: a lowering that is retried or discarded parks again.
public StructuredBuffer<uint> rl_slots;
public StructuredBuffer<uint> st_meta;
public StructuredBuffer<uint> st_reloc;
public StructuredBuffer<uint> st_undef;
public StructuredBuffer<uint> st_def;
public StructuredBuffer<uint> st_text;
public StructuredBuffer<uint> st_rodata;
// Undefined identities after the retained call rewrite, three words each.
public StructuredBuffer<uint> st_ident;
public StructuredBuffer<uint4> rl_routes;
// (identity, name slot)
public StructuredBuffer<uint4> rl_bindings;
// Import index of each name slot, written by the host after the plan.
public StructuredBuffer<uint> rl_import_of_name;

public RWStructuredBuffer<uint> rl_objects;
public RWStructuredBuffer<uint> rl_symbols;
public RWStructuredBuffer<uint> rl_sym_hash;
public RWStructuredBuffer<uint> rl_small_hash;
public RWStructuredBuffer<uint> rl_bind_hash;
public RWStructuredBuffer<uint> rl_status;
public RWStructuredBuffer<uint> rl_name_ref;
public RWStructuredBuffer<uint> rl_dyn_words;
public RWStructuredBuffer<uint> rl_out;

public static const uint SLOT_WORDS = 21u;
public static const uint META_WORDS = 32u;
public static const uint OBJECT_WORDS = 24u;
public static const uint SYMBOL_WORDS = 8u;
public static const uint RELOC_WORDS = 8u;
public static const uint INVALID = 0xffffffffu;
public static const uint BRIDGE_BYTES = 233u;
public static const uint TEXT_OFFSET = 0x78u;
public static const uint DYN_START_BYTES = 40u;
public static const uint DYN_STUB_BYTES = 8u;
public static const uint RESERVED_LIB = 0xfffffffeu;
public static const uint NS_USE = 0xffff0001u;

// Status words: totals the host reads after the plan, then error bits.
public static const uint ST_TEXT_LEN = 0u;
public static const uint ST_RODATA_LEN = 1u;
public static const uint ST_DEF_COUNT = 2u;
public static const uint ST_NAME_STRIDE = 3u;
public static const uint ST_ENTRY_OBJECT = 4u;
public static const uint ST_MAIN_OFFSET = 5u;
public static const uint ST_ERRORS = 16u;
public static const uint ST_EMIT_ERRORS = 17u;
public static const uint ST_WORDS = 64u;

// Object plan words.
public static const uint OB_TEXT_LEN = 0u;
public static const uint OB_RODATA_LEN = 1u;
public static const uint OB_ENTRY = 2u;
public static const uint OB_BODY_START = 3u;
public static const uint OB_BODY_END = 4u;
public static const uint OB_HAS_BODY = 5u;
public static const uint OB_RT_START = 6u;
public static const uint OB_RT_END = 7u;
public static const uint OB_HAS_RT = 8u;
public static const uint OB_COPY_START = 9u;
public static const uint OB_COPY_END = 10u;
public static const uint OB_SHARED = 11u;
public static const uint OB_TEXT_OUT = 12u;
public static const uint OB_RODATA_OUT = 13u;
public static const uint OB_DEF_PREFIX = 14u;
public static const uint OB_UNDEF_COUNT = 15u;
public static const uint OB_DEF_COUNT = 16u;
public static const uint OB_RELOC_COUNT = 17u;
public static const uint OB_RT_COUNT = 18u;
public static const uint OB_MISMATCH = 19u;
public static const uint OB_ENTRY_OBJECT = 20u;
public static const uint OB_ENTRY_RT_START = 21u;

public uint rl_lane(uint3 tid) { return linear_dispatch_thread_id_2d(tid, 16776960u); }

public uint slot_word(uint object, uint word) { return rl_slots[object * SLOT_WORDS + word]; }
public uint meta_word(uint object, uint word) { return st_meta[slot_word(object, 20u) + word]; }
public uint object_word(uint object, uint word) { return rl_objects[object * OBJECT_WORDS + word]; }

public void fail(uint bit) { atomic_u32_or(rl_status, ST_ERRORS, bit); }
public void fail_emit(uint bit) { atomic_u32_or(rl_status, ST_EMIT_ERRORS, bit); }

public uint word_byte(StructuredBuffer<uint> words, uint byte_index)
{
    return (words[byte_index >> 2u] >> ((byte_index & 3u) * 8u)) & 0xffu;
}

// Byte `offset` of object `object`'s whole text section.
public uint object_text_byte(uint object, uint offset)
{
    return word_byte(st_text, slot_word(object, 8u) + offset);
}

public uint object_rodata_byte(uint object, uint offset)
{
    return word_byte(st_rodata, slot_word(object, 9u) + offset);
}

// The object geometry the projection's layout words describe:
// (text length, rodata length, entry, body start, body end, has body).
public void object_geometry(uint object, out uint text_len, out uint rodata_len,
    out uint entry, out uint body_start, out uint body_end)
{
    uint body_len = meta_word(object, 4u);
    uint wrapper_len = meta_word(object, 10u) - meta_word(object, 9u);
    uint runtime_len = meta_word(object, 13u);
    text_len = wrapper_len + body_len + runtime_len;
    rodata_len = meta_word(object, 15u);
    entry = meta_word(object, 6u) == 1u ? 1u : 0u;
    body_start = wrapper_len;
    body_end = wrapper_len + body_len;
}

public uint identity_hash(uint3 value)
{
    uint h = 2166136261u;
    h = (h ^ value.x) * 16777619u;
    h = (h ^ value.y) * 16777619u;
    h = (h ^ value.z) * 16777619u;
    h ^= h >> 16u;
    return h;
}

public uint3 symbol_identity(uint symbol) { return uint3(rl_symbols[symbol * SYMBOL_WORDS + 1u], rl_symbols[symbol * SYMBOL_WORDS + 2u], rl_symbols[symbol * SYMBOL_WORDS + 3u]); }

// Definition symbol (capacity index) with this identity, or INVALID.
public uint lookup_definition(uint3 identity)
{
    uint slot = identity_hash(identity) & gRL.hash_mask;
    for (uint probe = 0u; probe <= gRL.hash_mask; probe += 1u)
    {
        uint value = rl_sym_hash[slot];
        if (value == 0u)
            return INVALID;
        if (all(symbol_identity(value - 1u) == identity))
            return value - 1u;
        slot = (slot + 1u) & gRL.hash_mask;
    }
    return INVALID;
}

// Name slot of the foreign binding with this identity, or INVALID.
public uint lookup_binding(uint3 identity)
{
    uint slot = identity_hash(identity) & gRL.hash_mask;
    for (uint probe = 0u; probe <= gRL.hash_mask; probe += 1u)
    {
        uint value = rl_bind_hash[slot];
        if (value == 0u)
            return INVALID;
        if (all(rl_bindings[value - 1u].xyz == identity))
            return rl_bindings[value - 1u].w;
        slot = (slot + 1u) & gRL.hash_mask;
    }
    return INVALID;
}

public uint small_key_hash(uint object, uint offset)
{
    return identity_hash(uint3(object, offset, 0x5a5au)) & gRL.small_mask;
}

public uint small_key(uint object, uint offset)
{
    return ((object + 1u) << 24u) | offset;
}

// Size of the last defined text symbol at (object, copied offset) whose
// size is 2..10, or 0.
public uint small_symbol_size(uint object, uint offset)
{
    if (object >= 255u || offset >= 0x1000000u)
        return 0u;
    uint key = small_key(object, offset);
    uint slot = small_key_hash(object, offset);
    for (uint probe = 0u; probe <= gRL.small_mask; probe += 1u)
    {
        uint stored = rl_small_hash[slot * 2u];
        if (stored == 0u)
            return 0u;
        if (stored == key)
        {
            uint definition = rl_small_hash[slot * 2u + 1u] - 1u;
            uint symbol = slot_word(object, 10u) + slot_word(object, 5u) + definition;
            return rl_symbols[symbol * SYMBOL_WORDS + 6u];
        }
        slot = (slot + 1u) & gRL.small_mask;
    }
    return 0u;
}

// Capacity index of symbol `local` of `object` (undefined rows first).
public uint symbol_cap_index(uint object, uint local)
{
    uint undef_count = object_word(object, OB_UNDEF_COUNT);
    uint base = slot_word(object, 10u);
    return local < undef_count ? base + local : base + slot_word(object, 5u) + (local - undef_count);
}
