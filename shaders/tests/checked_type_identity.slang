// Gate for checked_type_identity.slang, the canonical-ID replacement of the
// scoped and concrete equality walkers (the identity cases of the
// typed_constant_identity fixtures, on canonical IDs). One lane interns typed
// constants through the production key builders (canonical_constants.slang),
// count-class arrays and casts, publishes them as checked atoms, projections
// and rows, then compares checked operands with checked_types_equal and
// checked_types_equal_ids. Check i that fails sets bit i % 32 of word i / 32
// of identity_errors and stores its actual value at identity_errors[4 + i].
// Each builder and comparison has one call site.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_constants;
import type_checker.checked_type_identity;
import type_checker.substitution.ct_spare;
import primitive_types;

RWStructuredBuffer<uint> identity_errors;

static const uint INVALID = 0xffffffffu;
static const uint ATOM = 0x80000001u;
static const uint CONSTANT_PARAMETER = 0x80000002u;
static const uint PROJECTION = 0x80000003u;
static const uint VALUES = 10u;
static const uint PROJECTIONS = 5u;
static const uint ROWS = 6u;
static const uint COMPARISONS = 34u;
static const uint CLOSURE_CHECKS = 3u;

// Type parameter tokens 1 and 2 have slots 0 and 1; constant parameter
// token 3 has slot 0 and scalar u32. Every other token has no slot.
struct FixtureSlots : ICtSlots
{
    uint type_slot(uint token) { return token == 1u ? 0u : token == 2u ? 1u : CT_SLOT_NONE; }
    uint const_slot(uint token) { return token == 3u ? 0u : CT_SLOT_NONE; }
    uint const_scalar(uint token) { return token == 3u ? SCALAR_U32 : 0u; }
}

void check(uint index, uint actual, uint expected)
{
    if (actual == expected) return;
    InterlockedOr(identity_errors[index / 32u], 1u << (index % 32u));
    identity_errors[4u + index] = actual;
}

// Atom i's typed value.
uint3 atom_value(uint i)
{
    switch (i)
    {
    case 0u: return uint3(SCALAR_U32, 3u, 0u);
    case 1u: return uint3(SCALAR_U32, 3u, 0u);          // interned again: same ID as 0
    case 2u: return uint3(SCALAR_U64, 3u, 0u);          // same count, other type
    case 3u: return uint3(SCALAR_U64, 3u, 1u);          // different high limb
    case 4u: return uint3(SCALAR_I8, 0xffu, 0u);        // -1: not a count
    case 5u: return uint3(SCALAR_U8, 0xffu, 0u);
    case 6u: return uint3(SCALAR_BOOL, 1u, 0u);
    case 7u: return uint3(SCALAR_F32, 0u, 0u);          // +0.0
    case 8u: return uint3(SCALAR_F32, 0x80000000u, 0u); // -0.0: other bits
    default: return uint3(SCALAR_U32, 256u, 0u);
    }
}

// Projection i: (target scalar, child reference, child's declared scalar).
uint3 projection_case(uint i, uint u32_three, uint u32_256)
{
    switch (i)
    {
    case 0u: return uint3(SCALAR_U64, u32_three, 0u);              // folds to u64 3
    case 1u: return uint3(SCALAR_U8, u32_256, 0u);                 // does not fit u8
    case 2u: return uint3(SCALAR_U64, ct_const_param(3u), SCALAR_U32);
    case 3u: return uint3(SCALAR_U64, ct_const_param(3u), SCALAR_U32);
    default: return uint3(SCALAR_U8, ct_const_param(3u), SCALAR_U32);
    }
}

// Intern a typed value (cc_intern_count first, as every source does).
uint intern_value(uint3 value, inout uint spare)
{
    CtKey key;
    uint status = ct_build_value(value, key);
    return status == CT_KEY_BUILT ? ct_intern_spare(key, key.extra, spare) : status;
}

struct Comparison
{
    uint4 left;     // tag, payload, ID (only for `ids`), unused
    uint4 right;
    bool scoped;
    bool ids;       // checked_types_equal_ids with the given IDs
    bool expected;
}

Comparison comparison(uint tag_left, uint payload_left, uint tag_right, uint payload_right,
    bool scoped, bool expected)
{
    Comparison c;
    c.left = uint4(tag_left, payload_left, CT_NONE, 0u);
    c.right = uint4(tag_right, payload_right, CT_NONE, 0u);
    c.scoped = scoped;
    c.ids = false;
    c.expected = expected;
    return c;
}

Comparison comparison_case(uint i, uint2 row_ids)
{
    switch (i)
    {
    // Typed constant identity.
    case 0u: return comparison(ATOM, 0u, ATOM, 1u, true, true);
    case 1u: return comparison(ATOM, 0u, ATOM, 1u, false, true);
    case 2u: return comparison(ATOM, 0u, ATOM, 2u, false, false);       // u32 3 vs u64 3
    case 3u: return comparison(ATOM, 2u, ATOM, 3u, false, false);       // high limb
    case 4u: return comparison(ATOM, 4u, ATOM, 5u, false, false);       // i8 -1 vs u8 255
    case 5u: return comparison(ATOM, 7u, ATOM, 8u, false, false);       // +0.0 vs -0.0
    case 6u: return comparison(ATOM, 7u, ATOM, 7u, true, true);
    case 7u: return comparison(ATOM, 6u, ATOM, 0u, false, false);       // bool vs u32
    // Constants of any kind compare with each other.
    case 8u: return comparison(ATOM, 2u, PROJECTION, 0u, true, true);   // u64 3 == u64(u32 3)
    case 9u: return comparison(PROJECTION, 1u, PROJECTION, 1u, false, false); // unresolved
    case 10u: return comparison(PROJECTION, 2u, PROJECTION, 3u, true, true);  // equal casts
    case 11u: return comparison(PROJECTION, 2u, PROJECTION, 4u, true, false); // other target
    // Constant parameters: scoped needs a declared slot.
    case 12u: return comparison(CONSTANT_PARAMETER, 3u, CONSTANT_PARAMETER, 3u, true, true);
    case 13u: return comparison(CONSTANT_PARAMETER, 7u, CONSTANT_PARAMETER, 7u, true, false);
    case 14u: return comparison(CONSTANT_PARAMETER, 7u, CONSTANT_PARAMETER, 7u, false, true);
    case 15u: return comparison(CONSTANT_PARAMETER, 3u, ATOM, 0u, false, false);
    // A constant never equals a type.
    case 16u: return comparison(ATOM, 0u, 3u, 0u, false, false);
    case 17u: return comparison(1u, SCALAR_U32, ATOM, 0u, false, false);
    // Rows: array identity is element and length count class.
    case 18u: return comparison(3u, 0u, 3u, 1u, true, true);            // [i32; 3u32] == [i32; 3u64]
    case 19u: return comparison(3u, 0u, 3u, 2u, false, false);          // other count
    case 20u: return comparison(3u, 4u, 3u, 5u, false, false);          // both unresolved
    case 21u: return comparison(3u, 0u, 3u, 0u, true, true);
    case 22u: return comparison(3u, 3u, 3u, 3u, true, true);            // [T; 3]
    case 23u: return comparison(3u, INVALID, 3u, INVALID, false, false);
    // Scalars and legacy scalar-coded nominals compare by payload.
    case 24u: return comparison(1u, SCALAR_I32, 1u, SCALAR_I32, true, true);
    case 25u: return comparison(1u, SCALAR_I32, 1u, SCALAR_U32, true, false);
    case 26u: return comparison(1u, 5000u, 1u, 5000u, true, true);
    case 27u: return comparison(1u, SCALAR_I32, 3u, 0u, false, false);  // mixed tags
    // Type parameters: scoped needs a declared slot; concrete compares tokens.
    case 28u: return comparison(2u, 1u, 2u, 1u, true, true);
    case 29u: return comparison(2u, 9u, 2u, 9u, true, false);
    case 30u: return comparison(2u, 9u, 2u, 9u, false, true);
    case 31u: return comparison(2u, 1u, 2u, 2u, true, false);
    case 32u: return comparison(0u, 0u, 0u, 0u, false, false);
    default:
    {
        // Caller-supplied IDs: rows compare by ID, not by payload.
        Comparison c = comparison(3u, 100u, 3u, 200u, true, true);
        c.left.z = row_ids.x;
        c.right.z = row_ids.y;
        c.ids = true;
        return c;
    }
    }
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    for (uint i = 0u; i < CT_COUNT_WORDS; i++) ct_counts[i] = 0u;
    ct_counts[CT_COUNT_NEXT_RECORD] = ct_dynamic_base();
    uint spare = CT_NONE;

    // Atoms. The published tables hold every ID, so the lane keeps no
    // per-thread copies.
    [loop]
    for (uint i = 0u; i < VALUES; i++)
        canonical_atom[i] = intern_value(atom_value(i), spare);
    check(0u, canonical_atom[0] == canonical_atom[1] ? 1u : 0u, 1u);
    check(1u, ct_is_resolved(canonical_atom[0]) && canonical_atom[0] != canonical_atom[2] ? 1u : 0u, 1u);
    check(2u, cc_count_class(canonical_atom[0]) == cc_count_class(canonical_atom[2]) ? 1u : 0u, 1u);
    check(3u, cc_count(canonical_atom[2]), 3u);
    check(4u, cc_count(canonical_atom[4]), INVALID);
    check(5u, cc_count(canonical_atom[5]), 255u);

    // Projections: a concrete child folds to the target's value; a symbolic
    // child is a cast counted like the child.
    [loop]
    for (uint i = 0u; i < PROJECTIONS; i++)
    {
        uint3 projection = projection_case(i, canonical_atom[0], canonical_atom[9]);
        bool fold; uint3 value; CtKey key;
        uint status = ct_build_projection(projection.x, projection.y, projection.z, fold, value, key);
        uint id = status;
        if (fold) id = intern_value(value, spare);
        else if (status == CT_KEY_BUILT) id = ct_intern_spare(key, key.extra, spare);
        canonical_projection[i] = id;
    }
    check(6u, canonical_projection[0u] == canonical_atom[2] ? 1u : 0u, 1u);
    check(7u, canonical_projection[1u], CT_UNKNOWN);
    check(8u, ct_kind(canonical_projection[2u]), CC_KIND_CAST);
    check(9u, cc_count_class(canonical_projection[2u]) == ct_const_param(3u) ? 1u : 0u, 1u);

    // Rows: [i32; 3] by u32 3, [i32; 3] by u64 3, [i32; 256], [T; 3], and
    // two unresolved rows.
    [loop]
    for (uint row = 0u; row < ROWS; row++)
    {
        uint element = row == 3u ? ct_type_param(1u) : SCALAR_I32;
        uint length = row == 1u ? canonical_atom[2] : row == 2u ? canonical_atom[9] : canonical_atom[0];
        uint id = CT_UNKNOWN;
        if (row < 4u)
            id = ct_intern_small(CT_KIND_ARRAY, 2u, uint3(0u, 0u, 0u),
                uint2(element, cc_count_class(length)), uint2(INVALID, 0u), spare);
        canonical_row[row] = id;
    }
    check(10u, ct_is_resolved(canonical_row[0u]) ? 1u : 0u, 1u);

    // Closure.
    [loop]
    for (uint i = 0u; i < CLOSURE_CHECKS; i++)
    {
        uint row = i == 0u ? 0u : i == 1u ? 3u : 4u;
        check(11u + i, checked_row_is_closed(row) ? 1u : 0u, i == 0u ? 1u : 0u);
    }

    // Comparisons.
    [loop]
    for (uint i = 0u; i < COMPARISONS; i++)
    {
        Comparison c = comparison_case(i, uint2(canonical_row[0u], canonical_row[1u]));
        uint left = c.ids ? c.left.z : ct_ref(c.left.x, c.left.y);
        uint right = c.ids ? c.right.z : ct_ref(c.right.x, c.right.y);
        bool equal = checked_types_equal_ids(FixtureSlots(), c.left.x, c.left.y, left,
            c.right.x, c.right.y, right, c.scoped);
        check(16u + i, equal ? 1u : 0u, c.expected ? 1u : 0u);
    }
}
