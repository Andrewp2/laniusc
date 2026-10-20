// The instance table of an original job (docs: D_PLAN D2), built from the
// instance closure (instance_closure.slang) behind LANIUS_INSTANCE_TABLE.
// Every exported closure instance of a local function body becomes one entry
// (template function row F, row count, tagged environment E, virtual row
// base), in (F, ct_shash(E)) order, never by raw CT ID or discovery order.
// The entry's virtual rows [base, base + count) stand for the template rows
// [F, F + count): F's whole subtree. A virtual row's realized expression type
// is ct_realize(ct_subst(E, ct_ref(template row's expression reference))).
//
// Kernels: 05_table_keys (one lane per closure instance: eligibility, key,
// row count), 05b_table_rank (the same lanes: rank and base by counting),
// 05c_table_args (sizes the row dispatches), 06_table_rows / 06a (one lane
// per virtual row, retried while a realization is busy), 07_table_calls (one
// lane per virtual row: the callee instance of each call row, D3).
//
// The table is an observation for now: the host reads it only in validation
// mode (LANIUS_CHECK_INSTANCE_TABLE), against the copy run's own types.
import type_checker.canonical.canonical_api;
import type_checker.closure.instance_closure;

// Counters; see IT_COUNT_*.
public RWStructuredBuffer<uint> instance_table_counts;
// Per closure instance, in discovery order: (template function row or
// INVALID when not in the table, shash.x, shash.y, row count).
public RWStructuredBuffer<uint4> instance_table_keys;
// Two rows per entry, in table order:
//   2e:     (template function row, row count, tagged environment, base)
//   2e + 1: (closure instance index, depth, template source, 0); the
//           source is IT_SOURCE_LOCAL (this job's HIR) for now
public RWStructuredBuffer<uint4> instance_table;
// Per virtual row: (realized tag + 1, payload) of its expression type;
// (0, 0) while pending, (IT_ROW_FAILED, failure) when it could not realize.
public RWStructuredBuffer<uint2> instance_row_refs;
// Per virtual row: (IT_CALL_* kind, value) of the call it makes, for a call
// row (07_table_calls); (IT_CALL_NONE, 0) for every other row.
public RWStructuredBuffer<uint2> instance_row_calls;

// Call kinds of instance_row_calls.
public static const uint IT_CALL_NONE = 0u;        // no generic or bound call: the template's callee
public static const uint IT_CALL_ENTRY = 1u;       // a generic callee instance: value is its entry
public static const uint IT_CALL_METHOD = 2u;      // a bound call routed to a nongeneric method: its method row
public static const uint IT_CALL_UNRESOLVED = 3u;  // a local generic or bound call the table cannot name
public static const uint IT_CALL_DEPENDENCY = 4u;  // a generic call into a dependency (D7)

public static const uint IT_COUNT_ENTRIES = 0u;  // entries in the table
public static const uint IT_COUNT_ROWS = 1u;     // virtual rows of all entries
public static const uint IT_COUNT_FLAGS = 2u;    // IT_FLAG_* bits
public static const uint IT_COUNT_FAILED = 3u;   // rows that failed to realize
public static const uint IT_COUNT_WORDS = 4u;

public static const uint IT_FLAG_ROWS = 1u;       // the virtual rows exceed the row table
public static const uint IT_FLAG_COLLISION = 2u;  // two entries share a key
public static const uint IT_FLAG_ENTRIES = 4u;    // too many entries to rank

public static const uint IT_ROW_FAILED = 0xffffffffu;
public static const uint IT_NO_ENTRY = 0xffffffffu;  // it_find_entry: no such entry
public static const uint IT_SOURCE_LOCAL = 0u;  // the template rows are this job's HIR rows
// Ranking counts over every entry; past this many the table is skipped.
public static const uint IT_RANK_LIMIT = 16384u;

public void it_flag(uint bits)
{
    uint ignored;
    InterlockedOr(instance_table_counts[IT_COUNT_FLAGS], bits, ignored);
}

public uint it_row_capacity()
{
    uint rows; uint stride;
    instance_row_refs.GetDimensions(rows, stride);
    return rows;
}

// Closure instances the closure appended (and the key table holds).
public uint it_instances()
{
    uint rows; uint stride;
    instance_table_keys.GetDimensions(rows, stride);
    return min(min(instance_closure_counts[IC_COUNT_LENGTH], ic_instance_capacity()), rows);
}

// Whether key a orders before key b: function row, then structural hash.
public bool it_key_less(uint4 a, uint4 b)
{
    if (a.x != b.x) return a.x < b.x;
    if (a.y != b.y) return a.y < b.y;
    return a.z < b.z;
}

// The entry holding virtual row `row`: the last entry whose base is at or
// below it. Bases increase with the entry index.
public uint it_entry_of_row(uint row, uint entries)
{
    uint lo = 0u;
    uint hi = entries;
    while (hi - lo > 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (instance_table[2u * mid].w <= row) lo = mid;
        else hi = mid;
    }
    return lo;
}

// The entry of template function row `function` under tagged environment
// `env`, or IT_NO_ENTRY: entries are in key order, so a lower bound on the
// key (function, ct_shash(env)) finds it, and the entry must hold `env`
// itself.
public uint it_find_entry(uint function, uint env, uint entries)
{
    uint2 hash = ct_shash(env);
    uint4 key = uint4(function, hash.x, hash.y, 0u);
    uint lo = 0u;
    uint hi = entries;
    while (lo < hi)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        // The entry's own ranking key (05b), by its closure instance.
        uint4 other = instance_table_keys[instance_table[2u * mid + 1u].x];
        if (it_key_less(other, key)) lo = mid + 1u;
        else hi = mid;
    }
    if (lo >= entries) return IT_NO_ENTRY;
    uint4 found = instance_table[2u * lo];
    return found.x == function && found.z == env ? lo : IT_NO_ENTRY;
}
