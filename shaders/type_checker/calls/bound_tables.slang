// Tables of bound-directed call inference (calls/03l*,
// docs/compiler-generic-types.md, "Bound-directed generic call inference").
// Every inference round rebuilds them before 03l3 reads them: 03l0 clears
// the counts, 03l1 appends the trait implementations and free-function
// bounds of each resident dependency page, 03l2 the trait implementations of
// this unit. Rows hold canonical IDs, which outlive the page they came from.
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
