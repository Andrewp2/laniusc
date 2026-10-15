// Decode gate for the canonical bridge graph (canonical_bridge.slang). One
// lane interns a value, a count class, named types (type-first and
// interleaved, imported and local spellings), an array, a slice, references
// and a cast, then reads each back through CanonicalBridgeTypeGraph and the
// application environment reader. Check i that fails sets bit i % 32 of
// word i / 32 of bridge_errors and stores its actual value at
// bridge_errors[4 + i]. Each reader has one call site.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_bridge;
import type_checker.concrete_type_equality;
import primitive_types;

RWStructuredBuffer<uint> bridge_errors;

static const uint INVALID = 0xffffffffu;
static const uint CONSTANT_TAG = APPLICATION_CONSTANT_ARGUMENT;
static const uint METADATA_CHECKS = 33u;
static const uint ARGUMENT_CHECKS = 7u;

struct Ids
{
    uint count; uint value; uint named; uint local; uint array; uint slice; uint reference;
    uint slot_reference; uint cast;
};

void check(uint index, uint actual, uint expected)
{
    if (actual == expected) return;
    InterlockedOr(bridge_errors[index / 32u], 1u << (index % 32u));
    bridge_errors[4u + index] = actual;
}

// (ID, field, expected) of metadata check i.
uint3 metadata_case(uint i, Ids ids)
{
    switch (i)
    {
    // Named, imported spelling, type-first domains: N(i32; 4).
    case 0u: return uint3(ids.named, 0u, 1u);
    case 1u: return uint3(ids.named, 1u, INVALID);
    case 2u: return uint3(ids.named, 2u, 2u);
    case 3u: return uint3(ids.named, 5u, 1u);
    case 4u: return uint3(ids.named, 6u, 2u);
    case 5u: return uint3(ids.named, 7u, 1u);
    case 6u: return uint3(ids.named, 8u, 2u);
    case 7u: return uint3(ids.named, 9u, 3u);
    case 8u: return uint3(ids.named, 3u, 0u);
    // Named, local spelling (token 11), interleaved: M(4; bool).
    case 9u: return uint3(ids.local, 1u, 11u);
    case 10u: return uint3(ids.local, 5u, 1u | APPLICATION_INTERLEAVED_DOMAINS);
    case 11u: return uint3(ids.local, 6u, 1u);
    case 12u: return uint3(ids.local, 7u, INVALID);
    // [N; 4]: element and count-class length.
    case 13u: return uint3(ids.array, 0u, 2u);
    case 14u: return uint3(ids.array, 2u, 0u);
    case 15u: return uint3(ids.array, 3u, 3u);
    case 16u: return uint3(ids.array, 4u, CT_ROW_BASE + ids.named);
    case 17u: return uint3(ids.array, 5u, 1u);
    case 18u: return uint3(ids.array, 6u, CT_ROW_BASE + ids.count);
    case 19u: return uint3(ids.array, 1u, INVALID);
    // [u32], &T (token 7), and a reference to a dependency slot parameter.
    case 20u: return uint3(ids.slice, 0u, 3u);
    case 21u: return uint3(ids.slice, 3u, 1u);
    case 22u: return uint3(ids.slice, 4u, SCALAR_U32);
    case 23u: return uint3(ids.slice, 5u, 0u);
    case 24u: return uint3(ids.slice, 6u, INVALID);
    case 25u: return uint3(ids.reference, 0u, 4u);
    case 26u: return uint3(ids.reference, 3u, 2u);
    case 27u: return uint3(ids.reference, 4u, 7u);
    case 28u: return uint3(ids.slot_reference, 0u, 4u);
    case 29u: return uint3(ids.slot_reference, 3u, 0u);
    case 30u: return uint3(ids.slot_reference, 4u, INVALID);
    // A cast is a constant, not a type; an ID past the table is nothing.
    case 31u: return uint3(ids.cast, 0u, 0u);
    default: return uint3(CT_ID_LIMIT - 1u, 0u, 0u);
    }
}

// (instance, slot, constant domain) and the expected (tag, payload) of
// operand check i: direct operands, then the environment reader.
void argument_case(uint i, Ids ids, out uint3 query, out uint2 expected)
{
    uint named = CT_ROW_BASE + ids.named;
    uint local = CT_ROW_BASE + ids.local;
    uint value = CT_ROW_BASE + ids.value;
    switch (i)
    {
    case 0u: query = uint3(named, 0u, 0u); expected = uint2(1u, SCALAR_I32); break;
    case 1u: query = uint3(named, 1u, 0u); expected = uint2(CONSTANT_TAG | 1u, value); break;
    case 2u: query = uint3(named, 2u, 0u); expected = uint2(INVALID, INVALID); break;
    case 3u: query = uint3(named, 0u, 0u); expected = uint2(1u, SCALAR_I32); break;
    case 4u: query = uint3(named, 0u, 1u); expected = uint2(CONSTANT_TAG | 1u, value); break;
    case 5u: query = uint3(local, 0u, 0u); expected = uint2(1u, SCALAR_BOOL); break;
    default: query = uint3(local, 0u, 1u); expected = uint2(CONSTANT_TAG | 1u, value); break;
    }
}

uint intern_named(uint3 words, uint2 args, uint2 extra, inout uint spare)
{
    CtKey key = ct_key_begin(CT_KIND_NAMED, 2u, 1u, words);
    if (!ct_key_reserve_args(key)) return CT_UNKNOWN;
    ct_key_arg(key, 0u, args.x);
    ct_key_arg(key, 1u, args.y);
    return ct_intern_spare(key, extra, spare);
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint spare = CT_NONE;
    uint3 none = uint3(0u, 0u, 0u);
    uint2 empty = uint2(0u, 0u);
    Ids ids;
    ids.count = cc_intern_count(4u, spare);
    ids.value = ct_intern_small(CC_KIND_VALUE, 0u, uint3(SCALAR_U32, 4u, 0u), empty, uint2(4u, ids.count), spare);
    ids.named = intern_named(uint3(1u, 2u, 3u), uint2(SCALAR_I32, ids.value), uint2(INVALID, 2u), spare);
    ids.local = intern_named(uint3(5u, 6u, 7u), uint2(ids.value, SCALAR_BOOL), uint2(11u, 1u), spare);
    ids.array = ct_intern_small(CT_KIND_ARRAY, 2u, none, uint2(ids.named, ids.count), empty, spare);
    ids.slice = ct_intern_small(CT_KIND_SLICE, 1u, none, uint2(SCALAR_U32, 0u), empty, spare);
    ids.reference = ct_intern_small(CT_KIND_REF, 1u, none, uint2(ct_type_param(7u), 0u), empty, spare);
    ids.slot_reference = ct_intern_small(CT_KIND_REF, 1u, none, uint2(ct_dep_type_param(2u), 0u), empty, spare);
    ids.cast = ct_intern_small(CC_KIND_CAST, 1u, uint3(SCALAR_USIZE, 0u, 0u), uint2(ct_const_param(9u), 0u),
        uint2(INVALID, ct_const_param(9u)), spare);
    uint stored = 0u;
    stored += uint(ct_is_stored(ids.count)) + uint(ct_is_stored(ids.value)) + uint(ct_is_stored(ids.named));
    stored += uint(ct_is_stored(ids.local)) + uint(ct_is_stored(ids.array)) + uint(ct_is_stored(ids.slice));
    stored += uint(ct_is_stored(ids.reference)) + uint(ct_is_stored(ids.slot_reference));
    stored += uint(ct_is_stored(ids.cast));
    check(0u, stored, 9u);

    [loop]
    for (uint i = 0u; i < METADATA_CHECKS; i++)
    {
        uint3 query = metadata_case(i, ids);
        check(1u + i, CanonicalBridgeTypeGraph.metadata(CT_ROW_BASE + query.x, query.y), query.z);
    }
    [loop]
    for (uint i = 0u; i < ARGUMENT_CHECKS; i++)
    {
        uint3 query; uint2 expected;
        argument_case(i, ids, query, expected);
        uint tag; uint payload;
        bool found = i < 3u ? CanonicalBridgeTypeGraph.argument(query.x, query.y, tag, payload)
            : application_environment_argument<CanonicalBridgeTypeGraph>(
                query.x, query.y, query.z != 0u, tag, payload);
        check(34u + i, found ? tag : INVALID, expected.x);
        check(41u + i, found ? payload : INVALID, expected.y);
    }

    // Constants: a count class and a value read as u32 4; a cast is a
    // projection of its parameter child; neither is the other.
    uint3 decoded; uint scalar; uint2 child;
    check(48u, uint(CanonicalBridgeTypeGraph.constant_value(CT_ROW_BASE + ids.count, decoded) &&
        all(decoded == uint3(SCALAR_U32, 4u, 0u))), 1u);
    check(49u, uint(CanonicalBridgeTypeGraph.constant_value(CT_ROW_BASE + ids.value, decoded) &&
        all(decoded == uint3(SCALAR_U32, 4u, 0u))), 1u);
    check(50u, uint(CanonicalBridgeTypeGraph.constant_value(CT_ROW_BASE + ids.cast, decoded)), 0u);
    check(51u, uint(CanonicalBridgeTypeGraph.constant_projection(CT_ROW_BASE + ids.cast, scalar, child) &&
        scalar == SCALAR_USIZE && all(child == uint2(2u, 9u))), 1u);
    check(52u, uint(CanonicalBridgeTypeGraph.constant_projection(CT_ROW_BASE + ids.value, scalar, child)), 0u);

    // Operands of sentinels and parameters, and the round trip back to IDs.
    check(53u, ct_bridge_operand(CT_UNKNOWN).y, INVALID);
    check(54u, ct_bridge_operand(CT_PENDING).y, INVALID);
    check(55u, ct_bridge_operand(0u).y, INVALID);
    check(56u, ct_bridge_operand(ct_dep_const_param(1u, SCALAR_USIZE)).y, INVALID);
    uint2 operand = ct_bridge_operand(ct_const_param(9u));
    check(57u, operand.x, CONSTANT_TAG | 2u);
    check(58u, operand.y, 9u);
    check(59u, ct_ref(3u, CT_ROW_BASE + ids.array), ids.array);
    check(60u, ct_ref(CONSTANT_TAG | 1u, CT_ROW_BASE + ids.value), ids.value);
    check(61u, ct_ref(CONSTANT_TAG | 3u, CT_ROW_BASE + ids.cast), ids.cast);
    // Rows below the base belong to the checked graph (empty here).
    check(62u, CanonicalBridgeTypeGraph.metadata(CT_ROW_BASE - 1u, 0u), 0u);
}
