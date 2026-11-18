// Tables of bound-directed call inference (calls/03l*,
// docs/compiler-generic-types.md, "Bound-directed generic call inference").
// Before the inference rounds the counts are cleared and collect_local_implementations appends the
// trait implementations and bounds of this unit; a copy keeps those counts
// (bound_inference_local_counts). Each round restores them, and collect_dependency_bounds appends
// the trait implementations and free-function bounds of each resident
// dependency page before infer_bound_generics reads the tables
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
// One word per row: the next row of its chain plus one, or 0 at the chain's
// end (bound_link_implementation, bound_link_predicate).
public RWStructuredBuffer<uint> bound_implementation_next;
public RWStructuredBuffer<uint> bound_predicate_next;

public static const uint BOUND_ROW_WORDS = 16u;
public static const uint BOUND_IMPLEMENTATION_ARGUMENTS = 8u;
public static const uint BOUND_PREDICATE_ARGUMENTS = 7u;
public static const uint BOUND_COUNT_IMPLEMENTATIONS = 0u;
public static const uint BOUND_COUNT_PREDICATES = 1u;
// Nonzero when a row did not fit: the tables are incomplete and infer_bound_generics infers
// nothing, since a missing implementation could make a selection ambiguous.
public static const uint BOUND_COUNT_OVERFLOW = 2u;
public static const uint BOUND_LOCAL_IMPLEMENTATION = 0xfffffffdu;
// Words BOUND_IMPLEMENTATION_HEADS.. and BOUND_PREDICATE_HEADS.. of
// bound_inference_counts: the first row plus one (0: none) of each chain.
// An implementation row is linked into the chain of a hash of its trait and
// argument count, a predicate row into the chain of a hash of its owner.
// infer_bound_generics walks one chain instead of every row. The heads come before the owner
// filter, so the snapshot and restore of the counts (BOUND_LOCAL_WORDS) also
// return the heads to the local rows'. A local row's next word then names
// only local rows, and a dependency row's is written when it is linked again.
public static const uint BOUND_HEAD_COUNT = 256u;
public static const uint BOUND_IMPLEMENTATION_HEADS = 4u;
public static const uint BOUND_PREDICATE_HEADS = BOUND_IMPLEMENTATION_HEADS + BOUND_HEAD_COUNT;
public static const uint BOUND_LOCAL_WORDS = BOUND_PREDICATE_HEADS + BOUND_HEAD_COUNT;
// Words BOUND_OWNER_FILTER.. of bound_inference_counts: one bit per hash of
// the owner of every predicate row collected since the job's clear. infer_bound_generics
// skips a callee whose bit is clear, which then has no predicate row. A
// round's restore of the counts keeps the bits, so the rows of an earlier
// dependency page only leave bits that cost a chain walk.
public static const uint BOUND_OWNER_FILTER = BOUND_LOCAL_WORDS;
public static const uint BOUND_OWNER_FILTER_WORDS = 256u;
public static const uint BOUND_COUNT_WORDS = BOUND_OWNER_FILTER + BOUND_OWNER_FILTER_WORDS;

uint bound_hash(uint3 key)
{
    uint h = key.x * 0x9e3779b1u ^ key.y * 0x85ebca77u ^ key.z * 0xc2b2ae3du;
    h ^= h >> 15u; h *= 0x2c1b3c6du; h ^= h >> 12u;
    return h;
}

uint bound_owner_bit(uint3 owner)
{
    return bound_hash(owner) % (BOUND_OWNER_FILTER_WORDS * 32u);
}

uint bound_implementation_head(uint3 trait, uint arguments)
{
    return BOUND_IMPLEMENTATION_HEADS + bound_hash(trait ^ uint3(0u, 0u, arguments * 0x27d4eb2fu)) % BOUND_HEAD_COUNT;
}

uint bound_predicate_head(uint3 owner)
{
    return BOUND_PREDICATE_HEADS + bound_hash(owner) % BOUND_HEAD_COUNT;
}

// Pushes `row` onto the chain whose head is word `head` of the counts, with a
// compare-exchange: slangc 2026.2 segfaults on InterlockedExchange into a
// module's buffers (as type_checker/closure/instance_closure.slang). Each
// failed exchange means another lane linked a row, so a row capacity of
// attempts always suffices. No pass reads a chain in the dispatch that links
// it.
void bound_link(RWStructuredBuffer<uint> next, uint head, uint row)
{
    uint first = bound_inference_counts[head];
    uint words; uint stride;
    next.GetDimensions(words, stride);
    for (uint attempt = 0u; attempt < words; attempt++)
    {
        next[row] = first;
        uint previous = atomic_u32_compare_exchange(bound_inference_counts, head, first, row + 1u);
        if (previous == first) return;
        first = previous;
    }
}

// Links a row the collectors have reserved.
public void bound_link_implementation(uint row, uint3 trait, uint arguments)
{
    bound_link(bound_implementation_next, bound_implementation_head(trait, arguments), row);
}

public void bound_link_predicate(uint row, uint3 owner)
{
    bound_link(bound_predicate_next, bound_predicate_head(owner), row);
}

// The first row of a chain, or 0xffffffff.
public uint bound_first_implementation(uint3 trait, uint arguments)
{
    return bound_inference_counts[bound_implementation_head(trait, arguments)] - 1u;
}

public uint bound_next_implementation(uint row) { return bound_implementation_next[row] - 1u; }

public uint bound_first_predicate(uint3 owner)
{
    return bound_inference_counts[bound_predicate_head(owner)] - 1u;
}

public uint bound_next_predicate(uint row) { return bound_predicate_next[row] - 1u; }

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
