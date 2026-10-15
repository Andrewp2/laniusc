// Identity of checked type operands by canonical IDs
// (docs/canonical-type-ids.md). Two interned types are equal iff their IDs
// are equal, so nothing walks a type graph here.
//
// A checked operand reads its ID through ct_ref: a row its canonical_row
// entry, a constant its canonical_atom or canonical_projection entry. The
// operands must therefore be interned: the late canonical stage interns
// every row and constant, and inference-time readers intern theirs on demand
// (substitution/ct_checked.slang).
//
// checked_types_equal keeps the top-level admission of the walkers it
// replaces, scoped_type_refs_equal (`scoped`) and concrete_type_refs_equal
// with no environment:
// - both operands carry the same tag, except that constants of any kind
//   compare with each other (typed identity);
// - scalars and parameters compare by payload, so a legacy scalar-coded
//   nominal never equals an instance row;
// - scoped comparison admits only scalars, rows, constants and parameters
//   with a declared slot; concrete comparison compares other tags by payload.
// - parameter slots come from the kernel's ICtSlots adapter (CheckedSlots
//   or SourceSlots), so this module binds no graph table.
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_spare;

static const uint CHECKED_IDENTITY_INVALID = 0xffffffffu;

[ForceInline]
public bool checked_operand_is_constant(uint tag)
{
    return tag - (CT_CONSTANT_TAG_BIT | 1u) < 3u;
}

// Whether an operand passes the walkers' leaf admission: scoped comparison
// requires a declared slot for type and constant parameters.
bool checked_operand_admitted<S : ICtSlots>(S slots, uint tag, uint payload, bool scoped)
{
    if (payload == CHECKED_IDENTITY_INVALID) return false;
    if (!scoped) return true;
    if (tag == 2u) return slots.type_slot(payload) < 32u;
    if (tag != (CT_CONSTANT_TAG_BIT | 2u)) return true;
    return slots.const_slot(payload) < 32u;
}

// checked_types_equal with the operands' canonical IDs supplied by the
// caller (for example interned on demand); only rows and constants read them.
public bool checked_types_equal_ids<S : ICtSlots>(S slots, uint left_tag, uint left_payload, uint left,
    uint right_tag, uint right_payload, uint right, bool scoped)
{
    bool left_constant = checked_operand_is_constant(left_tag);
    bool right_constant = checked_operand_is_constant(right_tag);
    if (left_constant || right_constant)
        return left_constant && right_constant &&
            checked_operand_admitted(slots, left_tag, left_payload, scoped) &&
            checked_operand_admitted(slots, right_tag, right_payload, scoped) &&
            ct_is_resolved(left) && left == right;
    if (left_tag == 0u || left_tag != right_tag ||
        left_payload == CHECKED_IDENTITY_INVALID || right_payload == CHECKED_IDENTITY_INVALID) return false;
    if (left_tag == 3u) return ct_is_resolved(left) && left == right;
    if (left_payload != right_payload) return false;
    if (!scoped || left_tag == 1u) return true;
    return left_tag == 2u && slots.type_slot(left_payload) < 32u;
}

// Equality of two operands that are already interned.
public bool checked_types_equal<S : ICtSlots>(S slots, uint left_tag, uint left_payload,
    uint right_tag, uint right_payload, bool scoped)
{
    return checked_types_equal_ids(slots, left_tag, left_payload, ct_ref(left_tag, left_payload),
        right_tag, right_payload, ct_ref(right_tag, right_payload), scoped);
}

// Whether interned row `row` has no type or constant parameter leaf.
public bool checked_row_is_closed(uint row)
{
    return ct_closed(ct_row_ref(row));
}
