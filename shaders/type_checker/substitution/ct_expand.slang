// Field closure over canonical IDs (docs/canonical-type-ids.md,
// "Substitution"). Every type that a complete application reaches through
// its arguments, element types, struct fields and enum payloads gets a
// checked row, so the application index, imported field projection and
// layout find them. The closure runs in level rounds over one job-wide
// queue instead of a per-lane stack: a root or a child enters the queue
// once per job (one mark bit per ID), and each round expands the IDs the
// previous round queued.
//
// A queue entry is (ID, word). The word holds the token errors are reported
// at, the entry's depth below its root, and two flags: LENIENT entries come
// from argument contexts and report only capacity and limit failures, and
// FIELDS_ONLY entries were deferred because their imported declaration was
// not on the resident dependency page; their arguments were already queued.
import type_checker.canonical.canonical_api;

public RWStructuredBuffer<uint> ct_expand_mark;
public RWStructuredBuffer<uint2> ct_expand_queue;
// Deferred imported IDs; an entry's ID is CT_NONE once it was re-queued.
public RWStructuredBuffer<uint2> ct_expand_deferred;
public RWStructuredBuffer<uint> ct_expand_counts;

public static const uint CT_EXPAND_LENGTH = 0u;    // entries appended
public static const uint CT_EXPAND_START = 1u;     // this round's first entry
public static const uint CT_EXPAND_END = 2u;       // this round's end
public static const uint CT_EXPAND_DEFERRED = 3u;  // deferred entries appended
public static const uint CT_EXPAND_ROUND = 4u;     // advances in this run
public static const uint CT_EXPAND_MODE = 5u;      // 1 inside the inference rounds
public static const uint CT_EXPAND_DONE = 6u;      // level workgroups finished
public static const uint CT_EXPAND_COUNT_WORDS = 8u;

// Level rounds per closure run; the host records one advance and this many
// level rounds, the last workgroup of each round advancing the run
// (substitution_passes.rs, EXPAND_LEVELS_PER_RUN).
// Inside the inference rounds a run that leaves queued IDs reports progress,
// so the next inference round continues it.
public static const uint CT_EXPAND_LEVELS_PER_RUN = 4u;

public static const uint CT_EXPAND_TOKEN_MASK = 0x007fffffu;
public static const uint CT_EXPAND_DEPTH_SHIFT = 23u;
public static const uint CT_EXPAND_DEPTH_LIMIT = 64u;
public static const uint CT_EXPAND_FIELDS_ONLY = 0x40000000u;
public static const uint CT_EXPAND_LENIENT = 0x80000000u;

public uint ct_expand_word(uint token, uint depth, bool lenient)
{
    return min(token, CT_EXPAND_TOKEN_MASK) | (depth << CT_EXPAND_DEPTH_SHIFT) |
        (lenient ? CT_EXPAND_LENIENT : 0u);
}

public uint ct_expand_token(uint word) { return word & CT_EXPAND_TOKEN_MASK; }
public uint ct_expand_depth(uint word) { return (word >> CT_EXPAND_DEPTH_SHIFT) & 0x7fu; }

// Types that have fields or type children: named, array, slice, reference.
public bool ct_expandable(uint id)
{
    uint kind = ct_kind(id);
    return kind >= CT_KIND_NAMED && kind <= CT_KIND_REF;
}

// Append an entry; false when the queue is full.
public bool ct_expand_append(uint id, uint word)
{
    uint capacity; uint stride;
    ct_expand_queue.GetDimensions(capacity, stride);
    uint slot;
    InterlockedAdd(ct_expand_counts[CT_EXPAND_LENGTH], 1u, slot);
    if (slot >= capacity) return false;
    ct_expand_queue[slot] = uint2(id, word);
    return true;
}

// Queue `id` once per job. True when it is queued (now or earlier) or needs
// no expansion; false when the queue is full.
public bool ct_expand_push(uint id, uint word)
{
    if (!ct_expandable(id)) return true;
    uint words; uint stride;
    ct_expand_mark.GetDimensions(words, stride);
    if ((id >> 5u) >= words) return false;
    uint bit = 1u << (id & 31u);
    uint prior;
    InterlockedOr(ct_expand_mark[id >> 5u], bit, prior);
    return (prior & bit) != 0u || ct_expand_append(id, word);
}

// Remember an imported ID whose declaration is on another page.
public bool ct_expand_defer(uint id, uint word)
{
    uint capacity; uint stride;
    ct_expand_deferred.GetDimensions(capacity, stride);
    uint slot;
    InterlockedAdd(ct_expand_counts[CT_EXPAND_DEFERRED], 1u, slot);
    if (slot >= capacity) return false;
    ct_expand_deferred[slot] = uint2(id, word | CT_EXPAND_FIELDS_ONLY);
    return true;
}

// Lane 0 of a root kernel starts a run: whether its leftovers count as
// inference progress. (The advances of a run count themselves modulo
// CT_EXPAND_LEVELS_PER_RUN + 1.)
public void ct_expand_begin_run(uint lane, uint mode)
{
    if (lane == 0u) ct_expand_counts[CT_EXPAND_MODE] = mode;
}

// Workgroups of the level round over [START, END): at least one, so the
// round's last workgroup always advances the run. A dispatch wider than
// 65535 groups is split over y, as ct_expand_advance writes it.
public uint3 ct_expand_level_args(uint groups)
{
    uint x = min(groups, 65535u);
    return uint3(x, x == 0u ? 0u : (groups + 65534u) / 65535u, 1u);
}

public uint ct_expand_level_groups()
{
    uint start = ct_expand_counts[CT_EXPAND_START];
    uint end = ct_expand_counts[CT_EXPAND_END];
    return max((end - start + 255u) / 256u, 1u);
}

// Close one level round of the run (one lane): the entries the previous
// round queued become this round's input. Returns the next level's
// dispatch arguments; the closing advance of a run dispatches no level and
// sets `progress` when, inside the inference rounds, queued leftovers must
// continue in the next inference round.
public uint3 ct_expand_advance(out bool progress)
{
    progress = false;
    uint capacity; uint stride;
    ct_expand_queue.GetDimensions(capacity, stride);
    uint appended;
    InterlockedAdd(ct_expand_counts[CT_EXPAND_LENGTH], 0u, appended);
    uint length = min(appended, capacity);
    uint round = ct_expand_counts[CT_EXPAND_ROUND] % (CT_EXPAND_LEVELS_PER_RUN + 1u);
    ct_expand_counts[CT_EXPAND_ROUND] = (round + 1u) % (CT_EXPAND_LEVELS_PER_RUN + 1u);
    if (round < CT_EXPAND_LEVELS_PER_RUN)
    {
        ct_expand_counts[CT_EXPAND_START] = ct_expand_counts[CT_EXPAND_END];
        ct_expand_counts[CT_EXPAND_END] = length;
        return ct_expand_level_args(ct_expand_level_groups());
    }
    progress = length > ct_expand_counts[CT_EXPAND_END] && ct_expand_counts[CT_EXPAND_MODE] != 0u;
    return ct_expand_level_args(0u);
}
