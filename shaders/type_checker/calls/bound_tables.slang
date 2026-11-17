// Tables of bound-directed call inference (calls/03l*,
// docs/compiler-generic-types.md, "Bound-directed generic call inference").
// Before the inference rounds the counts are cleared and 03l2 appends the
// trait implementations and bounds of this unit; a copy keeps those counts
// (bound_inference_local_counts). Each round restores them, and 03l1 appends
// the trait implementations and free-function bounds of each resident
// dependency page before 03l3 reads the tables
// (docs/compiler-call-inference-rounds.md). Rows hold canonical IDs, which
// outlive the page they came from.
//
// An implementation row (BOUND_ROW_WORDS words):
//   0..2  the trait's stable identity (library, unit, declaration)
//   3..5  the implementation's identity: a dependency's (library, unit,
//         local index), or (BOUND_LOCAL_IMPLEMENTATION, 0, HIR node) here
//   6     the subject pattern, or CT_UNKNOWN when some part of the header has
//         no canonical ID (such a row matches every subject, so it can only
//         make a selection ambiguous)
//   7     the trait argument count, at most BOUND_IMPLEMENTATION_ARGUMENTS
//   8..15 the trait argument patterns
// A predicate row:
//   0..2  the owning free function's identity (library, unit, declaration)
//   3     the predicate's local index in its interface (its source order)
//   4     the type slot of the subject parameter
//   5..7  the trait's stable identity
//   8     the trait argument count, at most BOUND_PREDICATE_ARGUMENTS
//   9..15 the trait argument patterns, over the function's parameters
import atomics;

public RWStructuredBuffer<uint> bound_inference_counts;
public RWStructuredBuffer<uint> bound_implementation_rows;
public RWStructuredBuffer<uint> bound_predicate_rows;

public static const uint BOUND_ROW_WORDS = 16u;
public static const uint BOUND_IMPLEMENTATION_ARGUMENTS = 8u;
public static const uint BOUND_PREDICATE_ARGUMENTS = 7u;
public static const uint BOUND_COUNT_IMPLEMENTATIONS = 0u;
public static const uint BOUND_COUNT_PREDICATES = 1u;
// Nonzero when a row did not fit: the tables are incomplete and 03l3 infers
// nothing, since a missing implementation could make a selection ambiguous.
public static const uint BOUND_COUNT_OVERFLOW = 2u;
public static const uint BOUND_LOCAL_IMPLEMENTATION = 0xfffffffdu;
// Words BOUND_OWNER_FILTER.. of bound_inference_counts: one bit per hash of
// the owner of every predicate row collected since the job's clear. 03l3
// skips a callee whose bit is clear, which then has no predicate row. A
// round's restore of the counts keeps the bits, so the rows of an earlier
// dependency page only leave bits that cost a scan.
public static const uint BOUND_OWNER_FILTER = 4u;
public static const uint BOUND_OWNER_FILTER_WORDS = 256u;
public static const uint BOUND_COUNT_WORDS = BOUND_OWNER_FILTER + BOUND_OWNER_FILTER_WORDS;

uint bound_owner_bit(uint3 owner)
{
    uint h = owner.x * 0x9e3779b1u ^ owner.y * 0x85ebca77u ^ owner.z * 0xc2b2ae3du;
    h ^= h >> 15u; h *= 0x2c1b3c6du; h ^= h >> 12u;
    return h % (BOUND_OWNER_FILTER_WORDS * 32u);
}

// Records that `owner` has a predicate row (the collectors, after writing it).
public void bound_mark_owner(uint3 owner)
{
    uint bit = bound_owner_bit(owner);
    uint ignored;
    InterlockedOr(bound_inference_counts[BOUND_OWNER_FILTER + (bit >> 5u)], 1u << (bit & 31u), ignored);
}

// False only when no predicate row of `owner` was collected.
public bool bound_owner_may_have_predicates(uint3 owner)
{
    uint bit = bound_owner_bit(owner);
    return (bound_inference_counts[BOUND_OWNER_FILTER + (bit >> 5u)] & (1u << (bit & 31u))) != 0u;
}

public uint bound_row_capacity(uint table)
{
    uint words; uint stride;
    if (table == BOUND_COUNT_IMPLEMENTATIONS) bound_implementation_rows.GetDimensions(words, stride);
    else bound_predicate_rows.GetDimensions(words, stride);
    return words / BOUND_ROW_WORDS;
}

// A new row of `table`, or 0xffffffff after recording the overflow.
public uint bound_reserve_row(uint table)
{
    uint row = atomic_u32_add(bound_inference_counts, table, 1u);
    if (row < bound_row_capacity(table)) return row;
    atomic_u32_max(bound_inference_counts, BOUND_COUNT_OVERFLOW, 1u);
    return 0xffffffffu;
}

public uint bound_row_count(uint table)
{
    return min(bound_inference_counts[table], bound_row_capacity(table));
}
