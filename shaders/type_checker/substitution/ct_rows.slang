// The checked row of each canonical ID (ct_realize.slang writes missing
// ones). ct_row_of[id] is a type row, or (kind << 30) | row for a constant
// (kind 1 atom, 3 projection); INVALID when there is none yet and CLAIMED
// while a lane writes one. Seeded rows only move to a smaller index, so the
// row of an ID is stable once every source spelling of it is seeded.
import type_checker.canonical.canonical_api;
import primitive_types;
#include "../type/instances/body_graph_layout.slang"

public globallycoherent RWStructuredBuffer<uint> ct_row_of;

public static const uint CT_ROW_INVALID = 0xffffffffu;
public static const uint CT_ROW_PENDING = 0xfffffffeu;
public static const uint CT_ROW_CLAIMED = 0xfffffffdu;
public static const uint CT_ROW_CONSTANT_TAG = 0x80000000u;
public static const uint CT_ROW_MASK = 0x3fffffffu;
// Rows at or above this are not published, so no word meets the sentinels.
public static const uint CT_ROW_LIMIT = 0x3ffffff0u;

public uint ct_row_of_capacity()
{
    uint count; uint stride;
    ct_row_of.GetDimensions(count, stride);
    return count;
}

// The published row word of a record, or CT_ROW_INVALID.
public uint ct_realized_word(uint id)
{
    return ct_is_record(id) && id < ct_row_of_capacity() ? ct_row_of[id] : CT_ROW_INVALID;
}

// The checked operand of `ref` (constants tagged CT_ROW_CONSTANT_TAG | kind),
// (0, CT_ROW_PENDING) when it still needs a row, or (0, CT_ROW_INVALID) when
// it has no checked spelling (a dependency slot parameter, an environment).
public uint2 ct_realized_ref(uint ref)
{
    if (ref - 1u < SCALAR_USIZE) return uint2(1u, ref);
    if (ct_is_param(ref))
    {
        if (ct_is_dep_param(ref)) return uint2(0u, CT_ROW_INVALID);
        return uint2(ct_is_const_param(ref) ? CT_ROW_CONSTANT_TAG | 2u : 2u, ct_param_token(ref));
    }
    if (!ct_is_record(ref)) return uint2(0u, CT_ROW_INVALID);
    uint kind = ct_kind(ref);
    bool type = kind >= CT_KIND_NAMED && kind <= CT_KIND_REF;
    bool constant = kind >= CC_KIND_VALUE && kind <= CC_KIND_COUNT;
    if (!type && !constant) return uint2(0u, CT_ROW_INVALID);
    uint word = ct_realized_word(ref);
    if (word == CT_ROW_INVALID || word == CT_ROW_CLAIMED) return uint2(0u, CT_ROW_PENDING);
    // Acquire: the row was complete before its publication.
    DeviceMemoryBarrier();
    return type ? uint2(3u, word) : uint2(CT_ROW_CONSTANT_TAG | (word >> 30u), word & CT_ROW_MASK);
}

// Offer checked row `row` (kind 1..4, declaration token `token`) of a job
// with `tokens` source rows as the row of its ID. A named row is offered only in the ID's own spelling (local
// token, or the external triple when the ID has none), since readers take
// the declaration from the row.
public void ct_seed_type_row(uint row, uint kind, uint token, uint id, uint tokens)
{
    // Body rows are rewritten by each body specialization; they are not
    // stable spellings. A replay offers its own after the body canonical
    // stage (01b_seed_body_rows).
    if (row - tokens < BODY_GRAPH_NODES) return;
    ct_offer_type_row(row, kind, token, id);
}

// ct_seed_type_row for any row, body rows included.
public void ct_offer_type_row(uint row, uint kind, uint token, uint id)
{
    if (kind == 0u || kind > 4u || row >= CT_ROW_LIMIT || !ct_is_record(id) || id >= ct_row_of_capacity()) return;
    if (ct_kind(id) != kind + (CT_KIND_NAMED - 1u)) return;
    if (kind == 1u && token != ct_named_decl_token(id)) return;
    InterlockedMin(ct_row_of[id], row);
}

// Offer a constant atom (kind 1) or projection (kind 3) row as the row of
// its ID.
public void ct_seed_constant_row(uint kind, uint row, uint id)
{
    if (row >= CT_ROW_LIMIT || !ct_is_record(id) || id >= ct_row_of_capacity() || !ct_is_constant(id)) return;
    InterlockedMin(ct_row_of[id], (kind << 30u) | row);
}
