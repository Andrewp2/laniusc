// Coarse row keys for the debug cross-check against the previous graph
// equality. Rows that equality accepts always share a coarse key: kind,
// arity, declaration spelling and the canonical IDs of their type operands.
// Constant operands are left out, so the old walker itself compares typed
// and count constant identity. A pair whose type operands differ is caught
// at the deepest differing level, where all type operands agree.
import type_checker.canonical.canonical_api;
import type_checker.checked_type_graph;

// [0, buckets): chain heads (row + 1); [buckets, buckets + rows): next links.
public RWStructuredBuffer<uint> canonical_crosscheck_links;
// Per record: the smallest row interned to it (89_crosscheck_buckets), or
// 0xffffffff. Records are allocated per new key, so a record ID does not name
// the row that took it; this is the row the others of its ID are checked
// against.
public RWStructuredBuffer<uint> canonical_crosscheck_owner;

public uint crosscheck_owner_capacity()
{
    uint words; uint stride;
    canonical_crosscheck_owner.GetDimensions(words, stride);
    return words;
}

// The representative row of `id`, or 0xffffffff for a preseeded scalar or
// an ID no checked row holds.
public uint crosscheck_owner(uint id)
{
    if (id < CT_FIRST_RECORD || id >= crosscheck_owner_capacity()) return 0xffffffffu;
    return canonical_crosscheck_owner[id];
}

public uint crosscheck_rows()
{
    return min(ct_row_capacity(), checked_type_capacity());
}

public uint crosscheck_buckets()
{
    uint words; uint stride;
    canonical_crosscheck_links.GetDimensions(words, stride);
    return words > crosscheck_rows() ? words - crosscheck_rows() : 0u;
}

// Type operand `index` of a row, or CT_NONE for a constant operand.
uint coarse_operand(uint row, uint kind, uint index)
{
    if (kind == 1u)
    {
        uint tag; uint payload;
        if (!ScopedCheckedTypeGraph.argument(row, index, tag, payload)) return CT_UNKNOWN;
        return (tag & CT_CONSTANT_TAG_BIT) != 0u ? CT_NONE : ct_ref(tag, payload);
    }
    if (kind == 2u && index == 1u) return CT_NONE;
    return ct_ref(type_instance_elem_ref_tag[row], type_instance_elem_ref_payload[row]);
}

uint coarse_arity(uint row, uint kind)
{
    return kind == 1u ? min(type_instance_arg_count[row], CT_MAX_ARITY) : kind == 2u ? 2u : 1u;
}

// The previous equality's nominal spelling: a declaration token when the row
// has one, otherwise the imported (library, unit, local) triple.
uint4 coarse_spelling(uint row, uint kind)
{
    if (kind != 1u) return uint4(kind, 0u, 0u, 0u);
    uint token = type_instance_decl_token[row];
    if (token != 0xffffffffu) return uint4(1u, token, 0u, 0u);
    return uint4(2u, external_type_library_id[row], external_type_unit_id[row],
        external_type_local_index[row]);
}

public uint coarse_hash(uint row)
{
    uint kind = type_instance_kind[row];
    uint arity = coarse_arity(row, kind);
    uint4 spelling = coarse_spelling(row, kind);
    uint2 hash = ct_hash_word(CT_HASH_SEED, kind | (arity << 8u));
    hash = ct_hash_word(ct_hash_word(hash, spelling.x), spelling.y);
    hash = ct_hash_word(ct_hash_word(hash, spelling.z), spelling.w);
    for (uint index = 0u; index < arity; index++)
        hash = ct_hash_word(hash, coarse_operand(row, kind, index));
    return hash.x ^ hash.y;
}

public bool coarse_equal(uint left, uint right)
{
    uint kind = type_instance_kind[left];
    if (type_instance_kind[right] != kind) return false;
    uint arity = coarse_arity(left, kind);
    if (coarse_arity(right, kind) != arity) return false;
    if (any(coarse_spelling(left, kind) != coarse_spelling(right, kind))) return false;
    for (uint index = 0u; index < arity; index++)
        if (coarse_operand(left, kind, index) != coarse_operand(right, kind, index)) return false;
    return true;
}

// Rows that take part: interned to a canonical ID, of a supported kind.
public bool crosscheck_row(uint row)
{
    uint kind = type_instance_kind[row];
    return kind >= 1u && kind <= 4u && ct_is_resolved(canonical_row[row]);
}
