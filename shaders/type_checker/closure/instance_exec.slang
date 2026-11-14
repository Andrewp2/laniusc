// Execution rows of the instance table (instance_table.slang): the local
// instances an original job lowers itself instead of leaving them to a
// source-copy replay (docs/compiler-gpu-instantiation.md, milestones 2-3).
//
// Each selected table entry (F, count, E, base) gets an execution copy of
// its template subtree: virtual HIR rows [vrow, vrow + count) appended after
// the job's compact HIR, virtual tokens [vtok, vtok + span) appended after
// the job's token capacity, and a block in each side table (call arguments,
// fields, match arms, match payloads, array elements, strings, parameters)
// appended after that table's rows. A copied field that names a row, token
// or side-table index inside the template's subtree, span or block names the
// copy's instead; every other value (a declaration outside the body, a type
// row, a literal) is kept. Lowering reads the copies like any other rows:
// the virtual function has no generic parameters, its own source tokens and
// therefore its own function, local, place, temporary and schedule identity.
//
// Kernels: 08_exec_select (one lane per table entry: eligibility and block
// sizes), 08a_exec_members (one lane per table row: member layouts under a
// changed receiver and realized nominal declarations), 08b_exec_layout (one
// lane: bases and counts), 09_exec_rows (one lane per virtual row),
// 09b_exec_tables (one lane per virtual side-table slot), 09c_exec_counts
// (one lane, every job: the lowering's row counts).
import type_checker.closure.instance_table;

// Counters; see EX_COUNT_*.
public RWStructuredBuffer<uint> instance_exec_counts;
// EX_ENTRY_WORDS uint4 per table entry; see EX_Q*.
public RWStructuredBuffer<uint4> instance_exec_entries;
// Selected table entries in execution order (ascending virtual rows).
public RWStructuredBuffer<uint> instance_exec_list;
// Per instance table row (08a_exec_members): x and y are a member row's
// word offset and word count under its realized receiver when the
// environment changes the receiver, INVALID otherwise; z is the declaration
// token of a nominal scalar the environment realizes, INVALID otherwise.
// The row pass writes compact HIR tables, so it reads these facts here
// instead of binding the parser's declaration index beside them.
public RWStructuredBuffer<uint4> instance_exec_row_facts;

public static const uint EX_TABLES = 7u;
public static const uint EX_TABLE_CALL_ARGS = 0u;
public static const uint EX_TABLE_FIELDS = 1u;
public static const uint EX_TABLE_MATCH_ARMS = 2u;
public static const uint EX_TABLE_MATCH_PAYLOADS = 3u;
public static const uint EX_TABLE_ARRAY_ELEMENTS = 4u;
public static const uint EX_TABLE_STRINGS = 5u;
public static const uint EX_TABLE_PARAMS = 6u;

public static const uint EX_COUNT_ENTRIES = 0u;      // selected entries
public static const uint EX_COUNT_ROWS = 1u;         // virtual HIR rows
public static const uint EX_COUNT_TOKENS = 2u;       // virtual tokens
public static const uint EX_COUNT_FLAGS = 3u;        // EX_FLAG_* bits
public static const uint EX_COUNT_HIR = 4u;          // the job's own HIR rows (first virtual row)
public static const uint EX_COUNT_TOKEN_BASE = 5u;   // first virtual token
public static const uint EX_COUNT_TABLE = 6u;        // + k: virtual rows of side table k
public static const uint EX_COUNT_TABLE_BASE = 13u;  // + k: the job's own rows of side table k
public static const uint EX_COUNT_WORDS = 20u;

public static const uint EX_FLAG_CAPACITY = 1u;  // an entry did not fit; it and later ones replay

// Per table entry: 8 uint4.
public static const uint EX_ENTRY_WORDS = 8u;
public static const uint EX_Q_HEAD = 0u;      // (status, F, count, vrow)
public static const uint EX_Q_TOKENS = 1u;    // (template first token, span, vtok, table base)
public static const uint EX_Q_TSTART0 = 2u;   // template block starts, tables 0-3
public static const uint EX_Q_TSTART1 = 3u;   // tables 4-6
public static const uint EX_Q_TLEN0 = 4u;     // block lengths, tables 0-3
public static const uint EX_Q_TLEN1 = 5u;     // tables 4-6
public static const uint EX_Q_VSTART0 = 6u;   // virtual block starts, tables 0-3
public static const uint EX_Q_VSTART1 = 7u;   // tables 4-6

// Entry status (EX_Q_HEAD.x). Selected entries are EX_SELECTED; an entry
// that replays keeps the first reason it failed, for the trace.
public static const uint EX_PENDING = 0u;
public static const uint EX_SELECTED = 1u;
public static const uint EX_REJECT_TABLE = 0x100u;       // the table is flagged or not local
public static const uint EX_REJECT_OWNER = 0x101u;       // not a top-level function, or instantiated in place
public static const uint EX_REJECT_CONSTANTS = 0x102u;   // constant parameters
public static const uint EX_REJECT_SYNTAX = 0x103u;      // a nested item or function
public static const uint EX_REJECT_ROW = 0x104u;         // a row's type did not realize
public static const uint EX_REJECT_CALL = 0x105u;        // a call the table cannot route here
public static const uint EX_REJECT_FACT = 0x106u;        // a fact whose instance value is not derived here
public static const uint EX_REJECT_BLOCK = 0x107u;       // a side-table block is not contiguous
public static const uint EX_REJECT_CAPACITY = 0x108u;    // the rows, tokens or a table do not fit

public static const uint EX_INVALID = 0xffffffffu;

public uint4 ex_quad(uint entry, uint q)
{
    return instance_exec_entries[entry * EX_ENTRY_WORDS + q];
}

public void ex_set_quad(uint entry, uint q, uint4 value)
{
    instance_exec_entries[entry * EX_ENTRY_WORDS + q] = value;
}

public uint ex_component(uint4 value, uint index)
{
    return index == 0u ? value.x : index == 1u ? value.y : index == 2u ? value.z : value.w;
}

// Entries a job can address: the rank limit bounds the table.
public uint ex_entry_capacity()
{
    uint rows; uint stride;
    instance_exec_entries.GetDimensions(rows, stride);
    return rows / EX_ENTRY_WORDS;
}

// Component k of a pair of uint4 holding tables 0-3 and 4-6.
public uint ex_table_word(uint4 low, uint4 high, uint k)
{
    return k < 4u ? ex_component(low, k) : ex_component(high, k - 4u);
}

// The pair (low, high) with component k replaced by `value`.
public void ex_set_table_word(inout uint4 low, inout uint4 high, uint k, uint value)
{
    uint c = k & 3u;
    uint4 word = k < 4u ? low : high;
    if (c == 0u) word.x = value;
    else if (c == 1u) word.y = value;
    else if (c == 2u) word.z = value;
    else word.w = value;
    if (k < 4u) low = word;
    else high = word;
}

// The remapping of one selected entry.
public struct ExecMap
{
    public uint entry;      // table entry
    public uint function;   // template function row F
    public uint count;      // rows of F's subtree
    public uint vrow;       // virtual row of F
    public uint token;      // template first token
    public uint span;       // template tokens
    public uint vtok;       // virtual first token
    public uint base;       // the entry's first row in instance_row_refs
    public uint4 tstart0;   // template block starts (tables 0-3, 4-6)
    public uint4 tstart1;
    public uint4 tlen0;     // block lengths
    public uint4 tlen1;
    public uint4 vstart0;   // virtual block starts
    public uint4 vstart1;
}

public ExecMap ex_map(uint entry)
{
    ExecMap map;
    uint4 head = ex_quad(entry, EX_Q_HEAD);
    uint4 tokens = ex_quad(entry, EX_Q_TOKENS);
    map.entry = entry;
    map.function = head.y;
    map.count = head.z;
    map.vrow = head.w;
    map.token = tokens.x;
    map.span = tokens.y;
    map.vtok = tokens.z;
    map.base = tokens.w;
    map.tstart0 = ex_quad(entry, EX_Q_TSTART0);
    map.tstart1 = ex_quad(entry, EX_Q_TSTART1);
    map.tlen0 = ex_quad(entry, EX_Q_TLEN0);
    map.tlen1 = ex_quad(entry, EX_Q_TLEN1);
    map.vstart0 = ex_quad(entry, EX_Q_VSTART0);
    map.vstart1 = ex_quad(entry, EX_Q_VSTART1);
    return map;
}

public uint ex_tstart(ExecMap map, uint k) { return ex_table_word(map.tstart0, map.tstart1, k); }
public uint ex_tlen(ExecMap map, uint k) { return ex_table_word(map.tlen0, map.tlen1, k); }
public uint ex_vstart(ExecMap map, uint k) { return ex_table_word(map.vstart0, map.vstart1, k); }

// A row inside the template subtree names the copy's row.
public uint ex_row(ExecMap map, uint row)
{
    return row != EX_INVALID && row >= map.function && row - map.function < map.count
        ? map.vrow + (row - map.function) : row;
}

// A subtree boundary may be one past the last row.
public uint ex_boundary(ExecMap map, uint row)
{
    return row != EX_INVALID && row >= map.function && row - map.function <= map.count
        ? map.vrow + (row - map.function) : row;
}

// A token inside the template's span names the copy's token.
public uint ex_token(ExecMap map, uint token)
{
    return token != EX_INVALID && token >= map.token && token - map.token < map.span
        ? map.vtok + (token - map.token) : token;
}

// An index into side table k inside the template's block names the copy's.
public uint ex_index(ExecMap map, uint k, uint index)
{
    uint start = ex_tstart(map, k);
    return index != EX_INVALID && index >= start && index - start < ex_tlen(map, k)
        ? ex_vstart(map, k) + (index - start) : index;
}

// The template row of virtual row `row` of `map`.
public uint ex_template_row(ExecMap map, uint row)
{
    return map.function + (row - map.vrow);
}

// The realized expression reference of template row `row` under the
// entry: (tag, payload), or (EX_INVALID, 0) when it did not realize.
public uint2 ex_row_ref(ExecMap map, uint row)
{
    if (row == EX_INVALID || row < map.function || row - map.function >= map.count)
        return uint2(EX_INVALID, 0u);
    uint2 reference = instance_row_refs[map.base + (row - map.function)];
    if (reference.x == 0u || reference.x == IT_ROW_FAILED) return uint2(EX_INVALID, 0u);
    return uint2(reference.x - 1u, reference.y);
}

// The selected entry whose virtual rows hold `row`, or EX_INVALID.
public uint ex_entry_of_row(uint row)
{
    uint entries = instance_exec_counts[EX_COUNT_ENTRIES];
    uint first = instance_exec_counts[EX_COUNT_HIR];
    if (entries == 0u || row < first || row - first >= instance_exec_counts[EX_COUNT_ROWS])
        return EX_INVALID;
    uint lo = 0u;
    uint hi = entries;
    while (hi - lo > 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (ex_quad(instance_exec_list[mid], EX_Q_HEAD).w <= row) lo = mid;
        else hi = mid;
    }
    return instance_exec_list[lo];
}

// The selected entry whose block of side table k holds virtual index
// `index`, or EX_INVALID.
public uint ex_entry_of_index(uint k, uint index)
{
    uint entries = instance_exec_counts[EX_COUNT_ENTRIES];
    uint first = instance_exec_counts[EX_COUNT_TABLE_BASE + k];
    if (entries == 0u || index < first || index - first >= instance_exec_counts[EX_COUNT_TABLE + k])
        return EX_INVALID;
    uint q = k < 4u ? EX_Q_VSTART0 : EX_Q_VSTART1;
    uint c = k < 4u ? k : k - 4u;
    uint lo = 0u;
    uint hi = entries;
    while (hi - lo > 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (ex_component(ex_quad(instance_exec_list[mid], q), c) <= index) lo = mid;
        else hi = mid;
    }
    // An entry without a block in this table shares its start with the next
    // entry's block; take the last entry whose block holds the index.
    uint entry = instance_exec_list[lo];
    uint4 lengths = ex_quad(entry, k < 4u ? EX_Q_TLEN0 : EX_Q_TLEN1);
    uint start = ex_component(ex_quad(entry, q), c);
    return index - start < ex_component(lengths, c) ? entry : EX_INVALID;
}
