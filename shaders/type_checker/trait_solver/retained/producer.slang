// Program trait catalog and bound goals produced from the build's retention
// store (docs/compiler-retained-trait-catalog.md).
//
// The producer translates retained declarations, parameters, terms, trait
// facts and uses into the rows of the existing trait solver's catalog arena
// (tables 0-10) and batch input arena (tables 11-16). It selects no
// implementation and proves nothing: the solver's own admission, coherence
// and proof kernels consume these rows unchanged.
//
// Work is one lane per retained record in seven lane regions, in this order:
// declarations, parameters, terms, directory entries, trait records, uses
// and committed jobs. Each lane counts the rows it owns in 16 counters
// (RC_C_*), an exclusive scan ranks them, and the fill pass writes each row
// at its rank. Output order is the store's record order, never atomic order.
import primitive_types;
import constant_value;
import type_checker.retention.retention_store;
__exported import type_checker.trait_solver.retained.config_words;

// Configuration (rc_config words, config_words.slang). 00_configure writes
// the counts, lane regions, unit slots and sort width from the store's
// counters; the host writes the rest.
public StructuredBuffer<uint> rc_config;
public globallycoherent RWStructuredBuffer<uint> rc_state;
public RWStructuredBuffer<uint4> rc_flags;   // 4 uint4 (16 counters) per lane
public RWStructuredBuffer<uint4> rc_scan;    // exclusive prefix of rc_flags
public RWStructuredBuffer<uint4> rc_blocks;  // 4 uint4 per 256-lane block
public globallycoherent RWStructuredBuffer<uint> rc_entry;     // 2 words per directory entry
public globallycoherent RWStructuredBuffer<uint> rc_snapshot;  // 2 words per committed job
public globallycoherent RWStructuredBuffer<uint> rc_unit_slot; // (library, unit) -> job + 1
public RWStructuredBuffer<uint> rc_catalog;  // the solver's catalog arena
public RWStructuredBuffer<uint> rc_batch;    // the solver's batch input arena
// Binding order (see "Binding ranks"): sort keys, each binding record's
// sorted position (its method row) and each trait impl's first method row.
public RWStructuredBuffer<uint4> rc_sort;
public RWStructuredBuffer<uint> rc_bind_pos;
public RWStructuredBuffer<uint> rc_impl_first;
public StructuredBuffer<uint4> rc_stage;     // (k, j) of one bitonic step
// Term closure (see "Term closure"): a mark per stored term, the frontier
// list in discovery order and its cursor (wave first, wave end, appended).
public RWStructuredBuffer<uint> rc_reach;
public globallycoherent RWStructuredBuffer<uint> rc_front;
public globallycoherent RWStructuredBuffer<uint> rc_cursor;
// The route arena of the publication (docs/compiler-retained-trait-catalog.md,
// "Publication"); the producer writes its atom identity table.
public RWStructuredBuffer<uint> rc_routes;


public static const uint RC_R_DECL = 0u;
public static const uint RC_R_PARAM = 1u;
public static const uint RC_R_TERM = 2u;
public static const uint RC_R_DIR = 3u;
public static const uint RC_R_TRAIT = 4u;
public static const uint RC_R_USE = 5u;
public static const uint RC_R_JOB = 6u;
public static const uint RC_REGIONS = 7u;

// Counters, one per solver table the producer appends to.
public static const uint RC_C_ATOM = 0u;      // table 1
public static const uint RC_C_OWNER = 1u;     // table 2
public static const uint RC_C_PARAM = 2u;     // table 3
public static const uint RC_C_CALLABLE = 3u;  // table 4
public static const uint RC_C_NODE = 4u;      // table 5
public static const uint RC_C_EDGE = 5u;      // table 6
public static const uint RC_C_ROOT = 6u;      // table 7
public static const uint RC_C_PRED = 7u;      // table 8
public static const uint RC_C_IMPL = 8u;      // table 9
public static const uint RC_C_METHOD = 9u;    // table 10
public static const uint RC_C_CONTEXT = 10u;  // table 13
public static const uint RC_C_ASSUME = 11u;   // table 14
public static const uint RC_C_CALL = 12u;     // table 15
public static const uint RC_C_ENV = 13u;      // table 11
public static const uint RC_C_BIND = 14u;     // table 12
public static const uint RC_C_OBLIG = 15u;    // table 16
public static const uint RC_COUNTERS = 16u;

// rc_state words.
public static const uint RC_S_FAILURES = 0u;
public static const uint RC_S_FIRST = 1u;          // min (code << 24 | lane)
public static const uint RC_S_UNSUPPORTED_MEMBER_BOUNDS = 2u;
public static const uint RC_S_FILL_FAULTS = 3u;
public static const uint RC_S_UNIT_SLOTS_FULL = 4u; // the host grows rc_unit_slot and runs again
public static const uint RC_S_UNSUPPORTED_CALLEES = 5u;
public static const uint RC_S_PLAIN_CALLS = 6u;
public static const uint RC_S_TOTALS = 8u;         // + counter
public static const uint RC_S_CLOSURE_SHORT = 24u; // frontier not empty after the last wave: the host adds waves
public static const uint RC_S_CLOSURE_TERMS = 25u; // stored terms in the closure
public static const uint RC_S_CLOSURE_WAVES = 26u; // expansion waves that had work

// Failure codes (docs/compiler-retained-trait-catalog.md, "Failures").
public static const uint RC_E_NOT_READY = 1u;
public static const uint RC_E_SNAPSHOT = 2u;
public static const uint RC_E_UNIT = 3u;
public static const uint RC_E_PARAM_OWNER = 4u;
public static const uint RC_E_NOMINAL = 5u;
public static const uint RC_E_TRAIT_IDENTITY = 6u;
public static const uint RC_E_TRAIT_ARITY = 7u;
public static const uint RC_E_REQUIRED_MEMBER = 8u;
public static const uint RC_E_METHOD_OWNER = 9u;
public static const uint RC_E_BINDING_COVERAGE = 10u;
public static const uint RC_E_ENVIRONMENT = 11u;
public static const uint RC_E_SLOT = 12u;
public static const uint RC_E_TERM = 13u;
public static const uint RC_E_OWNER = 14u;
public static const uint RC_E_LIMIT = 15u;

public static const uint RC_INVALID = 0xffffffffu;

static const uint KIND_FREE_FN = 1u;
static const uint KIND_METHOD = 2u;
static const uint KIND_REQUIRED_MEMBER = 3u;
static const uint KIND_IMPL = 7u;
static const uint KIND_TRAIT = 8u;
static const uint FORM_DIRECT = 1u;
static const uint FORM_METHOD = 2u;

public uint cfg(uint word) { return rc_config[word]; }
public uint region_base(uint region) { return cfg(RC_CFG_BASE + region); }
public uint lanes() { return cfg(RC_CFG_LANES); }
public uint dispatch_lane(uint3 dtid) { return dtid.x + dtid.y * 16776960u; }

// Region of a lane and the record index inside it. Declarations and
// parameters start at handle 1, terms at RT_FIRST_TERM.
public uint2 lane_record(uint lane)
{
    uint region = 0u;
    for (uint r = 1u; r < RC_REGIONS; r++)
        if (lane >= region_base(r)) region = r;
    uint index = lane - region_base(region);
    if (region == RC_R_DECL || region == RC_R_PARAM) index += 1u;
    if (region == RC_R_TERM) index += RT_FIRST_TERM;
    return uint2(region, index);
}
uint lane_of(uint region, uint index)
{
    if (region == RC_R_DECL || region == RC_R_PARAM) index -= 1u;
    if (region == RC_R_TERM) index -= RT_FIRST_TERM;
    return region_base(region) + index;
}

public void fail(uint code, uint lane)
{
    InterlockedAdd(rc_state[RC_S_FAILURES], 1u);
    InterlockedMin(rc_state[RC_S_FIRST], (code << 24u) | min(lane, 0xffffffu));
}

// --------------------------------------------------------------------------
// Store records.
public bool valid_decl(uint decl) { return decl != 0u && decl < cfg(RC_CFG_DECLS); }
public bool valid_param(uint param) { return param != 0u && param < cfg(RC_CFG_PARAMS); }
public bool valid_term(uint term) { return term >= RT_FIRST_TERM && term < cfg(RC_CFG_TERMS); }

// The committed directory entry of a declaration, or RC_INVALID.
public uint entry_of(uint decl)
{
    if (!valid_decl(decl)) return RC_INVALID;
    uint def = rt_decl_def[decl];
    if (def == 0u || def - 1u >= cfg(RC_CFG_DIR)) return RC_INVALID;
    uint entry = def - 1u;
    uint4 d0 = rt_dir[entry * RT_DIR_WORDS];
    return d0.x == decl && d0.w == RT_DIR_COMMITTED ? entry : RC_INVALID;
}
public uint4 dir(uint entry, uint word) { return rt_dir[entry * RT_DIR_WORDS + word]; }
public uint entry_kind(uint entry) { return entry == RC_INVALID ? 0u : dir(entry, 0u).y; }
public bool committed_entry(uint entry)
{
    return entry < cfg(RC_CFG_DIR) && dir(entry, 0u).w == RT_DIR_COMMITTED &&
        entry_of(dir(entry, 0u).x) == entry;
}
public bool owner_kind(uint kind) { return kind == KIND_FREE_FN || kind == KIND_METHOD || kind == KIND_IMPL; }
public bool callable_kind(uint kind) { return kind == KIND_FREE_FN || kind == KIND_METHOD; }
// A trait impl: its signature block's second term is the trait term.
public uint impl_trait_term(uint entry)
{
    if (entry_kind(entry) != KIND_IMPL) return RT_NONE;
    return rt_sigs[dir(entry, 1u).z + 1u];
}
public bool trait_impl(uint entry) { return entry_kind(entry) == KIND_IMPL && impl_trait_term(entry) != RT_NONE; }
// Composed binder counts (type, constant) of an entry.
public uint2 binder_counts(uint entry) { uint y = dir(entry, 1u).y; return uint2(y & 0xffffu, y >> 16u); }
// The catalog owner entry of a declaration's parent, or RC_INVALID.
public uint parent_owner(uint entry)
{
    uint parent = dir(entry, 0u).z;
    if (parent == 0u) return RC_INVALID;
    uint p = entry_of(parent);
    return owner_kind(entry_kind(p)) ? p : RC_INVALID;
}
// Applicable predicates of an owner entry: its own block, then its parent's.
public uint applicable_count(uint entry)
{
    uint count = rt_dir_trait[entry].y;
    uint parent = parent_owner(entry);
    if (parent != RC_INVALID) count += rt_dir_trait[parent].y;
    return count;
}
public uint applicable_record(uint entry, uint ordinal)
{
    uint4 own = rt_dir_trait[entry];
    if (ordinal < own.y) return own.x + ordinal;
    return rt_dir_trait[parent_owner(entry)].x + ordinal - own.y;
}

// The snapshot (committed job ordinal) of a unit, or RC_INVALID.
public uint unit_hash(uint library, uint unit) { return (library * 0x9e3779b1u) ^ (unit * 0x85ebca77u + 0x165667b1u); }
public uint snapshot_of(uint library, uint unit)
{
    uint slots = cfg(RC_CFG_UNIT_SLOTS);
    uint slot = unit_hash(library, unit) & (slots - 1u);
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint value = rc_unit_slot[slot];
        if (value == 0u) return RC_INVALID;
        uint job = value - 1u;
        if (rc_snapshot[job * 2u] == library && rc_snapshot[job * 2u + 1u] == unit) return job;
        slot = (slot + 1u) & (slots - 1u);
    }
    return RC_INVALID;
}
public uint decl_snapshot(uint decl)
{
    uint4 key = rt_decl_key[decl];
    return snapshot_of(key.x, key.y);
}

// A CC_COUNT term of `count`, or 0. Exact comparison of the complete record.
public uint find_count_term(uint count)
{
    RtTermKey key = rt_key_begin(RT_KIND_CC_COUNT, 0u, 0u, uint3(count, 0u, 0u));
    uint slots; uint stride; rt_term_slot.GetDimensions(slots, stride);
    uint slot = rt_probe_start(key.hash.x, slots);
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint value = rt_term_slot[slot];
        if (value == 0u) return 0u;
        uint4 head = rt_term_head[value];
        if (head.x == key.head && all(head.yzw == key.words)) return value;
        slot = (slot + 1u) & (slots - 1u);
    }
    return 0u;
}

// --------------------------------------------------------------------------
// Atoms owned by each lane, in this order within the lane.
public bool decl_has_nominal(uint decl) { return rt_decl_key[decl].z == RT_NS_NOMINAL; }
public bool decl_has_binder(uint decl) { return entry_of(decl) != RC_INVALID; }
public bool decl_has_impl(uint decl) { return trait_impl(entry_of(decl)); }
public bool decl_has_callable(uint decl) { return callable_kind(entry_kind(entry_of(decl))); }
public uint decl_atom_count(uint decl)
{
    return (decl_has_nominal(decl) ? 1u : 0u) + (decl_has_binder(decl) ? 1u : 0u) +
        (decl_has_impl(decl) ? 1u : 0u) + (decl_has_callable(decl) ? 1u : 0u);
}
// A CC_VALUE of u32 whose count also has a CC_COUNT term shares that atom.
public bool term_owns_atom(uint term)
{
    uint4 head = rt_term_head[term];
    uint kind = head.x & 0xffu;
    if (kind == RT_KIND_CC_COUNT) return true;
    if (kind != RT_KIND_CC_VALUE) return false;
    return !(head.y == SCALAR_U32 && head.w == 0u && find_count_term(head.z) != 0u);
}
public bool term_has_node(uint term)
{
    uint kind = rt_term_head[term].x & 0xffu;
    bool shape = kind == RT_KIND_NAMED || kind == RT_KIND_ARRAY || kind == RT_KIND_SLICE ||
        kind == RT_KIND_REF || kind == RT_KIND_CC_CAST;
    return shape && (rt_term_flags(term) & RTF_SLOT) == 0u;
}

// Ranks from the scan.
public uint rank(uint lane, uint counter) { return rc_scan[lane * 4u + counter / 4u][counter & 3u]; }
public uint total(uint counter) { return rc_state[RC_S_TOTALS + counter]; }

public uint decl_atom(uint decl, uint which)
{
    // which: 0 nominal, 1 binder, 2 impl, 3 callable.
    uint at = rank(lane_of(RC_R_DECL, decl), RC_C_ATOM);
    if (which > 0u && decl_has_nominal(decl)) at++;
    if (which > 1u && decl_has_binder(decl)) at++;
    if (which > 2u && decl_has_impl(decl)) at++;
    return at;
}
public uint param_atom(uint param) { return rank(lane_of(RC_R_PARAM, param), RC_C_ATOM); }
public uint owner_row(uint entry) { return rank(lane_of(RC_R_DIR, entry), RC_C_OWNER); }
public uint callable_row(uint entry) { return rank(lane_of(RC_R_DIR, entry), RC_C_CALLABLE); }
public uint predicate_row(uint record) { return rank(lane_of(RC_R_TRAIT, record), RC_C_PRED); }

// A term's solver reference (tag, payload); payload RC_INVALID when the
// term has no translation.
public bool reference_ok(uint ref)
{
    if (ref >= 1u && ref < RT_FIRST_TERM) return true;
    if (rt_is_param_leaf(ref)) return valid_param(rt_leaf_param(ref)) && entry_of(rt_param_key[rt_leaf_param(ref)].x) != RC_INVALID;
    // A stored term outside the closure has no catalog row.
    if (!valid_term(ref) || rc_reach[ref] == 0u) return false;
    uint kind = rt_term_kind(ref);
    return term_has_node(ref) || kind == RT_KIND_CC_VALUE || kind == RT_KIND_CC_COUNT;
}
public uint reference_failure(uint ref)
{
    if (rt_is_slot_leaf(ref) || (valid_term(ref) && (rt_term_flags(ref) & RTF_SLOT) != 0u)) return RC_E_SLOT;
    return RC_E_TERM;
}
public uint2 reference(uint ref)
{
    if (!reference_ok(ref)) return uint2(RC_INVALID, RC_INVALID);
    if (ref < RT_FIRST_TERM) return uint2(1u, ref);
    if (rt_is_param_leaf(ref))
    {
        uint param = rt_leaf_param(ref);
        return uint2((ref & RT_CONST_BIT) != 0u ? 0x80000002u : 2u, param_atom(param));
    }
    uint kind = rt_term_kind(ref);
    if (kind == RT_KIND_CC_VALUE || kind == RT_KIND_CC_COUNT)
    {
        uint owner = ref;
        if (!term_owns_atom(ref)) owner = find_count_term(rt_term_head[ref].z);
        return uint2(0x80000001u, rank(lane_of(RC_R_TERM, owner), RC_C_ATOM));
    }
    uint node = rank(lane_of(RC_R_TERM, ref), RC_C_NODE);
    return uint2(kind == RT_KIND_CC_CAST ? 0x80000003u : 3u, node);
}

// --------------------------------------------------------------------------
// Uses that become solver calls: a direct or inherent-method call between
// catalog callables with a stored call environment.
public bool use_selected(uint use)
{
    uint4 u0 = rt_uses[use * RT_USE_WORDS];
    uint4 u1 = rt_uses[use * RT_USE_WORDS + 1u];
    uint form = u0.z & 0xffu;
    if (form != FORM_DIRECT && form != FORM_METHOD) return false;
    if (!callable_kind(entry_kind(entry_of(u0.x))) || !callable_kind(entry_kind(entry_of(u0.w)))) return false;
    // A goal needs an applicable predicate; other calls have no solver row.
    return valid_term(u1.x) && rt_term_kind(u1.x) == RT_KIND_ENV && applicable_count(entry_of(u0.w)) != 0u;
}
// Uses that are not goals, by reason (rc_state words 5 and 6): a direct or
// method use whose callee is not a committed store callable (extern, trait
// member, outside the store), and a call between store callables whose
// callee has no applicable predicate.
void count_skipped_use(uint use)
{
    uint4 u0 = rt_uses[use * RT_USE_WORDS];
    uint form = u0.z & 0xffu;
    if (form != FORM_DIRECT && form != FORM_METHOD) return;
    if (!callable_kind(entry_kind(entry_of(u0.w)))) InterlockedAdd(rc_state[RC_S_UNSUPPORTED_CALLEES], 1u);
    else if (callable_kind(entry_kind(entry_of(u0.x))) && applicable_count(entry_of(u0.w)) == 0u)
        InterlockedAdd(rc_state[RC_S_PLAIN_CALLS], 1u);
}

// --------------------------------------------------------------------------
// Term closure. The catalog holds only the stored terms that a solver row
// references, and their descendants. Roots are every reference a fill pass
// writes: an impl's self type and trait arguments, an owner predicate's
// subject and trait arguments, and a selected use's environment arguments.
// A node's arguments are its children. A u32 CC_VALUE that shares a
// CC_COUNT's atom also reaches that CC_COUNT. Pass 02d marks the roots from
// the directory, trait and use lanes. Pass 02e is one workgroup: each wave
// expands only the terms the previous wave discovered, with a workgroup
// barrier between waves; a term enters the frontier once. Pass 02 then
// counts only marked terms.
void reach(uint ref)
{
    if (!valid_term(ref)) return;
    uint previous;
    InterlockedCompareExchange(rc_reach[ref], 0u, 1u, previous);
    if (previous != 0u) return;
    uint slot;
    InterlockedAdd(rc_cursor[2], 1u, slot);
    rc_front[slot] = ref;
}
void reach_arguments(uint term, uint first)
{
    if (!valid_term(term)) return;
    uint arity = rt_term_arity(term);
    for (uint i = first; i < arity; i++) reach(rt_term_arg(term, i));
}
public void closure_roots(uint local)
{
    uint lane = region_base(RC_R_DIR) + local;
    if (lane >= region_base(RC_R_JOB)) return;
    uint2 record = lane_record(lane);
    if (record.x == RC_R_DIR)
    {
        uint entry = record.y;
        if (!committed_entry(entry) || !trait_impl(entry)) return;
        reach(rt_sigs[dir(entry, 1u).z]);
        reach_arguments(impl_trait_term(entry), 0u);
    }
    else if (record.x == RC_R_TRAIT)
    {
        uint4 t0 = rt_traits[record.y * RT_TRAIT_WORDS];
        if ((t0.y & 0xffu) != RT_TRAIT_PREDICATE || !owner_kind(entry_kind(entry_of(t0.x)))) return;
        reach(t0.z);
        reach_arguments(t0.w, 0u);
    }
    else if (record.x == RC_R_USE)
    {
        if (!use_selected(record.y)) return;
        reach_arguments(rt_uses[record.y * RT_USE_WORDS + 1u].x, 0u);
    }
}
void expand_term(uint term)
{
    uint4 head = rt_term_head[term];
    uint kind = head.x & 0xffu;
    if (term_has_node(term)) reach_arguments(term, 0u);
    else if (kind == RT_KIND_CC_VALUE && !term_owns_atom(term)) reach(find_count_term(head.z));
}
// Waves until one is empty or RC_CFG_CLOSURE_WAVES ran: each wave is the
// terms appended since the last one.
groupshared uint rc_wave[2];
public void closure_waves(uint lane)
{
    for (uint wave = 0u; wave < cfg(RC_CFG_CLOSURE_WAVES); wave++)
    {
        if (lane == 0u)
        {
            uint first = rc_cursor[1];
            uint end = rc_cursor[2];
            rc_cursor[0] = first;
            rc_cursor[1] = end;
            rc_wave[0] = first;
            rc_wave[1] = end;
            if (end != first) InterlockedAdd(rc_state[RC_S_CLOSURE_WAVES], 1u);
        }
        AllMemoryBarrierWithGroupSync();
        uint first = rc_wave[0];
        uint end = rc_wave[1];
        if (first == end) break;
        for (uint at = first + lane; at < end; at += 256u) expand_term(rc_front[at]);
        AllMemoryBarrierWithGroupSync();
    }
}

// The scalar of a constant argument, or RC_INVALID for a type argument.
uint constant_scalar(uint arg)
{
    if (rt_is_param_leaf(arg))
        return (arg & RT_CONST_BIT) != 0u ? rt_param_key[rt_leaf_param(arg)].w : RC_INVALID;
    if (!valid_term(arg)) return RC_INVALID;
    uint kind = rt_term_kind(arg);
    if (kind == RT_KIND_CC_VALUE || kind == RT_KIND_CC_CAST) return rt_term_head[arg].y;
    if (kind == RT_KIND_CC_COUNT) return SCALAR_U32;
    return RC_INVALID;
}

// An application of `entry`'s binder: its type arguments fill the binder's
// type domain except `self_slots` Self slots (1 for a trait, whose Self is
// the last type parameter), its
// constant arguments fill the constant domain, each constant argument has
// the scalar of its parameter, and every argument has a translation.
// Returns 0 or a failure code.
uint check_application(uint term, uint entry, uint self_slots, uint arity_code)
{
    uint4 head = rt_term_head[term];
    uint arity = (head.x >> 8u) & 0xffu;
    uint constants = countbits(head.z);
    uint2 counts = binder_counts(entry);
    if (constants > arity || counts.x < self_slots || counts.x - self_slots != arity - constants ||
        counts.y != constants)
        return arity_code;
    uint binder = dir(entry, 1u).x;
    uint constant = 0u;
    for (uint i = 0u; i < arity; i++)
    {
        uint arg = rt_term_arg(term, i);
        if (!reference_ok(arg)) return reference_failure(arg);
        uint scalar = constant_scalar(arg);
        if (((head.z >> i) & 1u) == 0u)
        {
            if (scalar != RC_INVALID) return arity_code;
            continue;
        }
        uint param = rt_binders[binder + counts.x + constant];
        constant++;
        if (scalar == RC_INVALID || !valid_param(param) || rt_param_key[param].w != scalar)
            return arity_code;
    }
    return 0u;
}

// Trait identity and arity: a trait term is NAMED over a committed TRAIT
// whose binder has one more type parameter (Self) than the term has type
// arguments, and as many constant parameters as constant arguments.
public uint check_trait_term(uint term, uint trait_decl)
{
    if (!valid_term(term) || rt_term_kind(term) != RT_KIND_NAMED) return RC_E_TRAIT_IDENTITY;
    uint trait_entry = entry_of(rt_term_head[term].y);
    if (rt_term_head[term].y != trait_decl || entry_kind(trait_entry) != KIND_TRAIT) return RC_E_TRAIT_IDENTITY;
    return check_application(term, trait_entry, 1u, RC_E_TRAIT_ARITY);
}
public uint term_arity(uint term) { return valid_term(term) ? rt_term_arity(term) : 0u; }

// --------------------------------------------------------------------------
// Binding ranks. The solver admits an impl's methods in strictly increasing
// required symbol. Each binding record is keyed (impl entry, symbol, record)
// and the keys are sorted by a bitonic network over a power-of-two width P:
// log2(P) * (log2(P) + 1) / 2 steps, each one compare per lane. A binding's
// method row is its sorted position, so every impl's block is contiguous
// and ordered. Equal (impl, symbol) neighbours are a duplicate binding.
// Other records sort last. The sort runs before 02_count, which checks
// that each trait impl's segment holds exactly its recorded binding count.
// rc_impl_first stores first + 1, so a cleared word means no segment.
bool sort_greater(uint4 a, uint4 b)
{
    if (a.x != b.x) return a.x > b.x;
    if (a.y != b.y) return a.y > b.y;
    return a.z > b.z;
}
public void sort_init(uint i)
{
    if (i >= cfg(RC_CFG_SORT)) return;
    uint4 key = uint4(RC_INVALID, RC_INVALID, i, 0u);
    if (i < cfg(RC_CFG_TRAITS))
    {
        uint4 t0 = rt_traits[i * RT_TRAIT_WORDS];
        uint impl_entry = entry_of(t0.x);
        if ((t0.y & 0xffu) == RT_TRAIT_BINDING && trait_impl(impl_entry))
            key.xy = uint2(impl_entry, rt_traits[i * RT_TRAIT_WORDS + 1u].y);
    }
    rc_sort[i] = key;
}
public void sort_step(uint i)
{
    uint width = cfg(RC_CFG_SORT);
    uint2 step = rc_stage[0].xy;
    uint other = i ^ step.y;
    if (i >= width || other <= i || other >= width) return;
    uint4 a = rc_sort[i];
    uint4 b = rc_sort[other];
    bool ascending = (i & step.x) == 0u;
    if (ascending ? sort_greater(a, b) : sort_greater(b, a))
    {
        rc_sort[i] = b;
        rc_sort[other] = a;
    }
}
// The steps with j < RC_SORT_BLOCK / 2 stay inside one block, so one
// workgroup runs them in shared memory with the same compare-exchange
// network as sort_step. Stage (k, 0): k == 0 sorts each block completely
// (k = 2 .. min(block, width)); otherwise it finishes stage k with
// j = 256 .. 1.
public static const uint RC_SORT_BLOCK = 512u;
groupshared uint4 rc_sort_keys[RC_SORT_BLOCK];
public void sort_block(uint group, uint thread)
{
    uint width = cfg(RC_CFG_SORT);
    uint k = rc_stage[0].x;
    uint block = group * RC_SORT_BLOCK;
    for (uint e = thread; e < RC_SORT_BLOCK; e += 256u)
        if (block + e < width) rc_sort_keys[e] = rc_sort[block + e];
    GroupMemoryBarrierWithGroupSync();
    uint first = k == 0u ? 2u : k;
    uint last = k == 0u ? min(RC_SORT_BLOCK, width) : k;
    for (uint kk = first; kk <= last; kk <<= 1u)
    {
        for (uint j = (k == 0u ? kk : RC_SORT_BLOCK) >> 1u; j != 0u; j >>= 1u)
        {
            uint i = (thread / j) * 2u * j + thread % j;
            if (block + i < width)
            {
                uint4 a = rc_sort_keys[i];
                uint4 b = rc_sort_keys[i + j];
                bool ascending = ((block + i) & kk) == 0u;
                if (ascending ? sort_greater(a, b) : sort_greater(b, a))
                {
                    rc_sort_keys[i] = b;
                    rc_sort_keys[i + j] = a;
                }
            }
            GroupMemoryBarrierWithGroupSync();
        }
    }
    for (uint e = thread; e < RC_SORT_BLOCK; e += 256u)
        if (block + e < width) rc_sort[block + e] = rc_sort_keys[e];
}
public void sort_finish(uint p)
{
    if (p >= cfg(RC_CFG_SORT)) return;
    uint4 key = rc_sort[p];
    if (key.x == RC_INVALID) return;
    rc_bind_pos[key.z] = p;
    uint4 previous = p == 0u ? uint4(RC_INVALID, RC_INVALID, 0u, 0u) : rc_sort[p - 1u];
    if (previous.x != key.x) rc_impl_first[key.x] = p + 1u;
    else if (previous.y == key.y) fail(RC_E_BINDING_COVERAGE, lane_of(RC_R_TRAIT, key.z));
}

// --------------------------------------------------------------------------
// Pass 00: snapshot identities per committed job, required-member counts per
// trait, and the callers that own selected uses.
public void mark_lane(uint lane)
{
    uint2 record = lane_record(lane);
    if (record.x == RC_R_DIR)
    {
        uint entry = record.y;
        if (!committed_entry(entry)) return;
        uint decl = dir(entry, 0u).x;
        uint job = dir(entry, 3u).z;
        uint4 key = rt_decl_key[decl];
        if (job >= cfg(RC_CFG_JOBS) || job >= rt_counts[RT_A_JOBS] || job >= rt_capacity(RT_A_JOBS))
        { fail(RC_E_SNAPSHOT, lane); return; }
        uint4 identity = rt_jobs[job];
        if (identity.x != key.x || identity.y != key.y || identity.z != cfg(RC_CFG_GENERATION))
            fail(RC_E_SNAPSHOT, lane);
        if (entry_kind(entry) == KIND_REQUIRED_MEMBER)
        {
            uint trait_entry = entry_of(dir(entry, 0u).z);
            if (entry_kind(trait_entry) != KIND_TRAIT) { fail(RC_E_REQUIRED_MEMBER, lane); return; }
            InterlockedAdd(rc_entry[trait_entry * 2u + 1u], 1u);
        }
    }
    else if (record.x == RC_R_JOB)
    {
        uint job = record.y;
        if (rt_counts[RT_A_JOBS] != cfg(RC_CFG_JOBS) || job >= rt_capacity(RT_A_JOBS))
        { fail(RC_E_SNAPSHOT, lane); return; }
        uint4 identity = rt_jobs[job];
        if (identity.z != cfg(RC_CFG_GENERATION) || identity.w != 0u)
        { fail(RC_E_SNAPSHOT, lane); return; }
        rc_snapshot[job * 2u] = identity.x;
        rc_snapshot[job * 2u + 1u] = identity.y;
    }
    else if (record.x == RC_R_USE)
    {
        if (!use_selected(record.y)) return;
        uint caller = entry_of(rt_uses[record.y * RT_USE_WORDS].x);
        rc_entry[caller * 2u] = 1u;
    }
}

// Pass 01: one lane per committed job indexes its (library, unit).
public void unit_lane(uint lane)
{
    uint2 record = lane_record(lane);
    if (record.x != RC_R_JOB) return;
    uint job = record.y;
    uint library = rc_snapshot[job * 2u];
    uint unit = rc_snapshot[job * 2u + 1u];
    // Pass 00 validates the job record. No library value is a sentinel.
    if (rc_state[RC_S_FAILURES] != 0u) return;
    uint slots = cfg(RC_CFG_UNIT_SLOTS);
    uint slot = unit_hash(library, unit) & (slots - 1u);
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint previous;
        InterlockedCompareExchange(rc_unit_slot[slot], 0u, job + 1u, previous);
        if (previous == 0u) return;
        uint other = previous - 1u;
        // Two committed jobs of one unit: its private identities are ambiguous.
        if (rc_snapshot[other * 2u] == library && rc_snapshot[other * 2u + 1u] == unit)
        { fail(RC_E_SNAPSHOT, lane); return; }
        slot = (slot + 1u) & (slots - 1u);
    }
    InterlockedAdd(rc_state[RC_S_UNIT_SLOTS_FULL], 1u);
}

// --------------------------------------------------------------------------
// Pass 02: per-lane row counts, with every producer check.
struct Counts
{
    uint4 g0; uint4 g1; uint4 g2; uint4 g3;
    [mutating] void set(uint counter, uint value)
    {
        uint lane = counter & 3u;
        if (counter < 4u) g0[lane] = value;
        else if (counter < 8u) g1[lane] = value;
        else if (counter < 12u) g2[lane] = value;
        else g3[lane] = value;
    }
}

void count_decl(uint lane, uint decl, inout Counts n)
{
    uint4 key = rt_decl_key[decl];
    if (all(key == uint4(0u, 0u, 0u, 0u))) return; // an unpublished spare
    n.set(RC_C_ATOM, decl_atom_count(decl));
    if (decl_has_nominal(decl))
    {
        bool private_local = (key.w & 0x80000000u) != 0u;
        if ((key.w & 0x7fffffffu) >= 0x20000000u) fail(RC_E_NOMINAL, lane);
        if (private_local && decl_snapshot(decl) == RC_INVALID) fail(RC_E_UNIT, lane);
    }
}
void count_param(uint lane, uint param, inout Counts n)
{
    uint4 key = rt_param_key[param];
    if (all(key == uint4(0u, 0u, 0u, 0u))) return;
    if (entry_of(key.x) == RC_INVALID) { fail(RC_E_PARAM_OWNER, lane); return; }
    n.set(RC_C_ATOM, 1u);
}
void count_term(uint lane, uint term, inout Counts n)
{
    uint kind = rt_term_head[term].x & 0xffu;
    if (kind == 0u || rc_reach[term] == 0u) return;
    if (term_owns_atom(term)) n.set(RC_C_ATOM, 1u);
    if (!term_has_node(term)) return;
    n.set(RC_C_NODE, 1u);
    uint arity = rt_term_arity(term);
    if (kind == RT_KIND_NAMED)
    {
        n.set(RC_C_EDGE, arity);
        // A nominal application is checked against its defining binder.
        uint decl = rt_term_head[term].y;
        uint entry = entry_of(decl);
        uint code = 0u;
        if (!valid_decl(decl) || rt_decl_key[decl].z != RT_NS_NOMINAL || entry == RC_INVALID) code = RC_E_NOMINAL;
        // A trait term (a bound or impl header) has one Self slot first.
        else if (entry_kind(entry) == KIND_TRAIT) code = check_application(term, entry, 1u, RC_E_TRAIT_ARITY);
        else code = check_application(term, entry, 0u, RC_E_NOMINAL);
        if (code != 0u) fail(code, lane);
        return;
    }
    for (uint i = 0u; i < arity; i++)
        if (!reference_ok(rt_term_arg(term, i))) fail(reference_failure(rt_term_arg(term, i)), lane);
}
void count_dir(uint lane, uint entry, inout Counts n)
{
    if (!committed_entry(entry)) return;
    uint kind = entry_kind(entry);
    if (!owner_kind(kind)) return;
    uint decl = dir(entry, 0u).x;
    if (dir(entry, 0u).z != 0u && parent_owner(entry) == RC_INVALID) fail(RC_E_OWNER, lane);
    n.set(RC_C_OWNER, 1u);
    uint2 counts = binder_counts(entry);
    // The composed binder: in each domain the parent owner's slots, in its
    // order, then this entry's own parameters.
    uint parent = parent_owner(entry);
    uint2 inherited = parent == RC_INVALID ? uint2(0u, 0u) : binder_counts(parent);
    if (inherited.x > counts.x || inherited.y > counts.y) fail(RC_E_PARAM_OWNER, lane);
    uint own = 0u;
    for (uint i = 0u; i < counts.x + counts.y && i < 128u; i++)
    {
        uint param = rt_binders[dir(entry, 1u).x + i];
        if (!valid_param(param)) { fail(RC_E_PARAM_OWNER, lane); continue; }
        bool constant = i >= counts.x;
        uint slot = constant ? i - counts.x : i;
        if (slot < (constant ? inherited.y : inherited.x))
        {
            uint expected = rt_binders[dir(parent, 1u).x + (constant ? inherited.x + slot : slot)];
            if (param != expected) fail(RC_E_PARAM_OWNER, lane);
        }
        else if (rt_param_key[param].x != decl) fail(RC_E_PARAM_OWNER, lane);
        if (rt_param_key[param].x == decl) own++;
    }
    n.set(RC_C_PARAM, own);
    if (callable_kind(kind))
    {
        n.set(RC_C_CALLABLE, 1u);
        if (rc_entry[entry * 2u] != 0u)
        {
            n.set(RC_C_CONTEXT, 1u);
            n.set(RC_C_ASSUME, applicable_count(entry));
        }
    }
    if (trait_impl(entry))
    {
        uint term = impl_trait_term(entry);
        uint self_term = rt_sigs[dir(entry, 1u).z];
        uint code = valid_term(term) ? check_trait_term(term, rt_term_head[term].y) : RC_E_TRAIT_IDENTITY;
        if (code != 0u) { fail(code, lane); return; }
        if (!reference_ok(self_term)) { fail(reference_failure(self_term), lane); return; }
        uint trait_entry = entry_of(rt_term_head[term].y);
        uint bound = rt_dir_trait[entry].w;
        if (bound != rc_entry[trait_entry * 2u + 1u] || !segment_exact(entry, bound)) fail(RC_E_BINDING_COVERAGE, lane);
        n.set(RC_C_IMPL, 1u);
        n.set(RC_C_ROOT, 1u + term_arity(term));
    }
}
// The impl's sorted binding segment has exactly `bound` records.
bool segment_exact(uint entry, uint bound)
{
    uint first = rc_impl_first[entry];
    if (bound == 0u) return first == 0u;
    if (first == 0u) return false;
    uint last = first - 1u + bound - 1u;
    uint width = cfg(RC_CFG_SORT);
    if (last >= width || rc_sort[last].x != entry) return false;
    return last + 1u == width || rc_sort[last + 1u].x != entry;
}
void count_trait(uint lane, uint record, inout Counts n)
{
    uint4 t0 = rt_traits[record * RT_TRAIT_WORDS];
    uint4 t1 = rt_traits[record * RT_TRAIT_WORDS + 1u];
    uint kind = t0.y & 0xffu;
    if (kind == RT_TRAIT_PREDICATE)
    {
        uint owner = entry_of(t0.x);
        uint owner_entry_kind = entry_kind(owner);
        if (owner_entry_kind == KIND_REQUIRED_MEMBER)
        {
            // A required member's own bound needs required-member
            // substitution, which the solver does not admit. Counted;
            // no catalog row.
            InterlockedAdd(rc_state[RC_S_UNSUPPORTED_MEMBER_BOUNDS], 1u);
            return;
        }
        if (!owner_kind(owner_entry_kind)) { fail(RC_E_OWNER, lane); return; }
        uint code = check_trait_term(t0.w, t1.x);
        if (code != 0u) { fail(code, lane); return; }
        // A scalar, a type parameter or a structural type term.
        bool subject = (t0.z >= 1u && t0.z < RT_FIRST_TERM) ||
            (rt_is_param_leaf(t0.z) && (t0.z & RT_CONST_BIT) == 0u && reference_ok(t0.z)) ||
            (valid_term(t0.z) && term_has_node(t0.z) && rt_term_kind(t0.z) != RT_KIND_CC_CAST && reference_ok(t0.z));
        if (!subject) { fail(reference_failure(t0.z), lane); return; }
        n.set(RC_C_PRED, 1u);
        n.set(RC_C_ATOM, 1u);
        n.set(RC_C_ROOT, 1u + term_arity(t0.w));
    }
    else if (kind == RT_TRAIT_BINDING)
    {
        uint impl_entry = entry_of(t0.x);
        if (!trait_impl(impl_entry)) { fail(RC_E_METHOD_OWNER, lane); return; }
        uint trait_term = impl_trait_term(impl_entry);
        uint required = entry_of(t0.z);
        uint4 required_key = valid_decl(t0.z) ? rt_decl_key[t0.z] : uint4(0u, 0u, 0u, 0u);
        if (!valid_term(trait_term) || rt_term_head[trait_term].y != t1.x ||
            entry_kind(required) != KIND_REQUIRED_MEMBER || dir(required, 0u).z != t1.x ||
            required_key.z != RT_NS_CALLABLE || required_key.w != t1.y ||
            (t1.y & 0xc0000000u) != 0x80000000u)
        { fail(RC_E_REQUIRED_MEMBER, lane); return; }
        uint method = entry_of(t0.w);
        if (entry_kind(method) != KIND_METHOD || dir(method, 0u).z != t0.x)
        { fail(RC_E_METHOD_OWNER, lane); return; }
        n.set(RC_C_METHOD, 1u);
    }
    else fail(RC_E_TERM, lane);
}
void count_use(uint lane, uint use, inout Counts n)
{
    if (!use_selected(use)) { count_skipped_use(use); return; }
    uint4 u0 = rt_uses[use * RT_USE_WORDS];
    uint4 u1 = rt_uses[use * RT_USE_WORDS + 1u];
    uint callee = entry_of(u0.w);
    uint2 counts = binder_counts(callee);
    uint k = counts.x + counts.y;
    uint4 head = rt_term_head[u1.x];
    uint type_mask = counts.x >= 32u ? 0xffffffffu : (1u << counts.x) - 1u;
    uint const_mask = counts.y >= 32u ? 0xffffffffu : (1u << counts.y) - 1u;
    if (counts.x > 32u || counts.y > 32u) { fail(RC_E_LIMIT, lane); return; }
    // The environment is the callee's, complete in both domains.
    if (head.y != u0.w || head.z != type_mask || head.w != const_mask || rt_term_arity(u1.x) != k)
    { fail(RC_E_ENVIRONMENT, lane); return; }
    for (uint i = 0u; i < k; i++)
    {
        uint arg = rt_term_arg(u1.x, i);
        if (!reference_ok(arg)) { fail(reference_failure(arg), lane); return; }
    }
    n.set(RC_C_CALL, 1u);
    n.set(RC_C_ENV, 1u);
    n.set(RC_C_BIND, k);
    n.set(RC_C_ROOT, k);
    n.set(RC_C_OBLIG, applicable_count(callee));
}
public void count_lane(uint lane)
{
    Counts n;
    n.g0 = uint4(0u, 0u, 0u, 0u); n.g1 = n.g0; n.g2 = n.g0; n.g3 = n.g0;
    // The store must be READY and of the build the host configured.
    if (lane == 0u && (rt_counts[RT_C_READY] != 1u || rt_counts[RT_C_GENERATION] != cfg(RC_CFG_GENERATION)))
        fail(RC_E_NOT_READY, lane);
    if (lane == 0u)
    {
        // Terms discovered by the last wave were never expanded.
        if (rc_cursor[1] != rc_cursor[2]) rc_state[RC_S_CLOSURE_SHORT] = 1u;
        rc_state[RC_S_CLOSURE_TERMS] = rc_cursor[2];
    }
    uint2 record = lane_record(lane);
    if (record.x == RC_R_DECL) count_decl(lane, record.y, n);
    else if (record.x == RC_R_PARAM) count_param(lane, record.y, n);
    else if (record.x == RC_R_TERM) count_term(lane, record.y, n);
    else if (record.x == RC_R_DIR) count_dir(lane, record.y, n);
    else if (record.x == RC_R_TRAIT) count_trait(lane, record.y, n);
    else if (record.x == RC_R_USE) count_use(lane, record.y, n);
    rc_flags[lane * 4u] = n.g0;
    rc_flags[lane * 4u + 1u] = n.g1;
    rc_flags[lane * 4u + 2u] = n.g2;
    rc_flags[lane * 4u + 3u] = n.g3;
}

// --------------------------------------------------------------------------
// Pass 06: rows at their ranks.
static const uint TS_MAGIC_WORD = 0x50455631u;
static const uint TS_VERSION_WORD = 3u;

uint width(uint table)
{
    uint packed = table < 8u ? 0x22844984u : (table < 16u ? 0x868456C8u : 0x00000084u);
    return (packed >> ((table & 7u) * 4u)) & 15u;
}
// A fill pass runs once per arena: the catalog before its admission, the
// batch after its arena is placed. Each writes only its own arena's tables.
void put(uint table, uint row, uint field, uint value)
{
    uint at = cfg(RC_CFG_TABLE + table) + row * width(table) + field;
    bool batch = table > 10u;
    if (batch != (cfg(RC_CFG_PHASE) == 1u)) return;
    if (batch) rc_batch[at] = value;
    else rc_catalog[at] = value;
}
void put4(uint table, uint row, uint first, uint4 v)
{
    put(table, row, first, v.x); put(table, row, first + 1u, v.y);
    put(table, row, first + 2u, v.z); put(table, row, first + 3u, v.w);
}
void put_atom(uint row, uint4 low)
{
    put4(1u, row, 0u, low);
    put4(1u, row, 4u, uint4(0u, 0u, 0u, 0u));
}
// The retained identity of a catalog atom: 1 DeclId, 2 ParamId, 3 TermId,
// 0 none. Written with the catalog.
static const uint ID_DECL = 1u;
static const uint ID_PARAM = 2u;
static const uint ID_TERM = 3u;
void put_id(uint atom, uint kind, uint id)
{
    if (cfg(RC_CFG_PHASE) != 0u) return;
    uint at = cfg(RC_CFG_ATOM_IDS) + atom * 2u;
    rc_routes[at] = kind;
    rc_routes[at + 1u] = id;
}
void put_root(uint row, uint ref)
{
    uint2 r = reference(ref);
    if (r.y == RC_INVALID && cfg(RC_CFG_PHASE) == 0u) InterlockedAdd(rc_state[RC_S_FILL_FAULTS], 1u);
    put(7u, row, 0u, r.x); put(7u, row, 1u, r.y);
}
uint first_or_zero(uint first, uint count) { return count == 0u ? 0u : first; }

public void fill_decl(uint lane, uint decl)
{
    uint4 key = rt_decl_key[decl];
    if (all(key == uint4(0u, 0u, 0u, 0u))) return;
    uint entry = entry_of(decl);
    uint job = entry == RC_INVALID ? RC_INVALID : dir(entry, 3u).z;
    for (uint which = 0u; which < 4u; which++)
    {
        bool has = which == 0u ? decl_has_nominal(decl) : (which == 1u ? decl_has_binder(decl) :
            (which == 2u ? decl_has_impl(decl) : decl_has_callable(decl)));
        if (has) put_id(decl_atom(decl, which), ID_DECL, decl);
    }
    if (decl_has_nominal(decl))
    {
        bool private_local = (key.w & 0x80000000u) != 0u;
        put_atom(decl_atom(decl, 0u), private_local ?
            uint4(2u, decl_snapshot(decl), key.w & 0x7fffffffu, 0u) : uint4(1u, key.x, key.y, key.w));
    }
    if (decl_has_binder(decl)) put_atom(decl_atom(decl, 1u), uint4(4u, job, key.z, key.w));
    if (decl_has_impl(decl))
    {
        put_atom(decl_atom(decl, 2u), uint4(7u, job, key.w, 0u));
    }
    if (decl_has_callable(decl)) put_atom(decl_atom(decl, 3u), uint4(8u, key.x, key.y, key.w));
}
public void fill_param(uint lane, uint param)
{
    uint4 key = rt_param_key[param];
    if (all(key == uint4(0u, 0u, 0u, 0u)) || entry_of(key.x) == RC_INVALID) return;
    uint domain = key.y == RT_DOMAIN_CONST ? 1u : 0u;
    put_atom(param_atom(param), uint4(5u, decl_atom(key.x, 1u), domain, key.z | (domain << 16u)));
    put_id(param_atom(param), ID_PARAM, param);
    put(1u, param_atom(param), 4u, domain == 1u ? key.w : 0u);
}
public void fill_term(uint lane, uint term)
{
    uint4 head = rt_term_head[term];
    uint kind = head.x & 0xffu;
    if (kind == 0u || rc_reach[term] == 0u) return;
    if (term_owns_atom(term))
    {
        uint row = rank(lane, RC_C_ATOM);
        put_id(row, ID_TERM, term);
        if (kind == RT_KIND_CC_COUNT) put_atom(row, uint4(12u, SCALAR_U32, head.y, 0u));
        else put_atom(row, uint4(12u, head.y, head.z, head.w));
    }
    if (!term_has_node(term)) return;
    uint node = rank(lane, RC_C_NODE);
    uint4 low = uint4(0u, 0u, 0u, 0u); uint4 high = uint4(0u, 0u, 0u, 0u);
    if (kind == RT_KIND_NAMED)
    {
        uint arity = rt_term_arity(term);
        uint edge = rank(lane, RC_C_EDGE);
        low = uint4(1u, decl_atom(head.y, 0u), first_or_zero(edge, arity), arity);
        for (uint i = 0u; i < arity; i++)
        {
            uint2 r = reference(rt_term_arg(term, i));
            put(6u, edge + i, 0u, r.x); put(6u, edge + i, 1u, r.y);
        }
    }
    else if (kind == RT_KIND_ARRAY)
    {
        low = uint4(2u, 0u, 0u, 0u);
        high = uint4(reference(rt_term_arg(term, 0u)), reference(rt_term_arg(term, 1u)));
    }
    else if (kind == RT_KIND_SLICE || kind == RT_KIND_REF)
    {
        low = uint4(kind == RT_KIND_SLICE ? 3u : 4u, 0u, 0u, 0u);
        high = uint4(reference(rt_term_arg(term, 0u)), 0u, 0u);
    }
    else // CC_CAST
    {
        low = uint4(5u, head.y, 0u, 0u);
        high = uint4(reference(rt_term_arg(term, 0u)), 0u, 0u);
    }
    put4(5u, node, 0u, low);
    put4(5u, node, 4u, high);
}
public void fill_dir(uint lane, uint entry)
{
    if (!committed_entry(entry)) return;
    uint kind = entry_kind(entry);
    if (!owner_kind(kind)) return;
    uint decl = dir(entry, 0u).x;
    uint4 key = rt_decl_key[decl];
    uint job = dir(entry, 3u).z;
    uint owner = rank(lane, RC_C_OWNER);
    uint parent = parent_owner(entry);
    uint4 own_facts = rt_dir_trait[entry];
    uint params = rank(lane, RC_C_PARAM);
    uint2 counts = binder_counts(entry);
    uint own = 0u;
    for (uint i = 0u; i < counts.x + counts.y && i < 128u; i++)
    {
        uint param = rt_binders[dir(entry, 1u).x + i];
        if (!valid_param(param) || rt_param_key[param].x != decl) continue;
        bool constant = i >= counts.x;
        put4(3u, params + own, 0u, uint4(owner, param_atom(param), constant ? i - counts.x : i, constant ? 1u : 0u));
        own++;
    }
    uint predicates = own_facts.y == 0u ? 0u : predicate_row(own_facts.x);
    uint callable = callable_kind(kind) ? rank(lane, RC_C_CALLABLE) : RC_INVALID;
    put4(2u, owner, 0u, uint4(decl_atom(decl, 1u), job, key.w, parent == RC_INVALID ? RC_INVALID : owner_row(parent)));
    put4(2u, owner, 4u, uint4(first_or_zero(params, own), own, predicates, own_facts.y));
    put(2u, owner, 8u, callable);
    if (callable != RC_INVALID)
        put4(4u, callable, 0u, uint4(decl_atom(decl, 3u), owner, counts.x, counts.y));
    if (trait_impl(entry))
    {
        uint term = impl_trait_term(entry);
        uint arity = term_arity(term);
        uint roots = rank(lane, RC_C_ROOT);
        put_root(roots, rt_sigs[dir(entry, 1u).z]);
        for (uint i = 0u; i < arity; i++) put_root(roots + 1u + i, rt_term_arg(term, i));
        uint methods = own_facts.w == 0u ? 0u : rc_impl_first[entry] - 1u;
        uint row = rank(lane, RC_C_IMPL);
        put4(9u, row, 0u, uint4(decl_atom(decl, 2u), owner, decl_atom(rt_term_head[term].y, 0u), roots));
        put4(9u, row, 4u, uint4(first_or_zero(roots + 1u, arity), arity, methods, own_facts.w));
        put4(9u, row, 8u, uint4(predicates, own_facts.y, 0u, 0u));
    }
    if (callable != RC_INVALID && rc_entry[entry * 2u] != 0u)
    {
        uint context = rank(lane, RC_C_CONTEXT);
        uint assumptions = rank(lane, RC_C_ASSUME);
        uint count = applicable_count(entry);
        put4(13u, context, 0u, uint4(job, owner, RC_INVALID, first_or_zero(assumptions, count)));
        put4(13u, context, 4u, uint4(count, 0u, RC_INVALID, 0u));
        for (uint i = 0u; i < count; i++)
        {
            put4(14u, assumptions + i, 0u, uint4(context, predicate_row(applicable_record(entry, i)), RC_INVALID, RC_INVALID));
            put(14u, assumptions + i, 4u, 0u); put(14u, assumptions + i, 5u, 0u);
        }
    }
}
public void fill_trait(uint lane, uint record)
{
    uint4 t0 = rt_traits[record * RT_TRAIT_WORDS];
    uint4 t1 = rt_traits[record * RT_TRAIT_WORDS + 1u];
    uint kind = t0.y & 0xffu;
    if (kind == RT_TRAIT_PREDICATE)
    {
        uint owner = entry_of(t0.x);
        if (!owner_kind(entry_kind(owner))) return;
        uint4 key = rt_decl_key[t0.x];
        uint atom = rank(lane, RC_C_ATOM);
        put_atom(atom, uint4(11u, dir(owner, 3u).z, key.w, (key.z << 24u) | (t0.y >> 8u)));
        put_id(atom, 0u, 0u);
        uint arity = term_arity(t0.w);
        uint roots = rank(lane, RC_C_ROOT);
        put_root(roots, t0.z);
        for (uint i = 0u; i < arity; i++) put_root(roots + 1u + i, rt_term_arg(t0.w, i));
        uint row = rank(lane, RC_C_PRED);
        put4(8u, row, 0u, uint4(atom, owner_row(owner), decl_atom(t1.x, 0u), roots));
        put4(8u, row, 4u, uint4(first_or_zero(roots + 1u, arity), arity, 0u, 0u));
    }
    else if (kind == RT_TRAIT_BINDING)
    {
        uint impl_entry = entry_of(t0.x);
        if (!trait_impl(impl_entry)) return;
        uint row = rc_bind_pos[record];
        uint impl_row = rank(lane_of(RC_R_DIR, impl_entry), RC_C_IMPL);
        put4(10u, row, 0u, uint4(impl_row, t1.y, decl_atom(t0.w, 3u), (t0.y >> 8u) & 0xffu));
        put(10u, row, 4u, owner_row(entry_of(t0.w)));
        put(10u, row, 5u, 0u);
    }
}
public void fill_use(uint lane, uint use)
{
    if (!use_selected(use)) return;
    uint4 u0 = rt_uses[use * RT_USE_WORDS];
    uint4 u1 = rt_uses[use * RT_USE_WORDS + 1u];
    uint caller = entry_of(u0.x);
    uint callee = entry_of(u0.w);
    uint2 counts = binder_counts(callee);
    uint k = counts.x + counts.y;
    uint call = rank(lane, RC_C_CALL);
    uint env = rank(lane, RC_C_ENV);
    uint bindings = rank(lane, RC_C_BIND);
    uint roots = rank(lane, RC_C_ROOT);
    uint obligations = rank(lane, RC_C_OBLIG);
    uint count = applicable_count(callee);
    uint context = rank(lane_of(RC_R_DIR, caller), RC_C_CONTEXT);
    put4(15u, call, 0u, uint4(context, use, owner_row(caller), callable_row(callee)));
    put4(15u, call, 4u, uint4(env, first_or_zero(obligations, count), count, 0u));
    put4(11u, env, 0u, uint4(owner_row(callee), first_or_zero(bindings, k), k, 1u));
    put(11u, env, 4u, call);
    uint binder = dir(callee, 1u).x;
    for (uint i = 0u; i < k; i++)
    {
        put_root(roots + i, rt_term_arg(u1.x, i));
        // Bindings are sorted by parameter atom, which follows ParamId: a
        // rank by counting, k * k reads for k <= 64 parameters (LIMIT).
        uint param = rt_binders[binder + i];
        uint position = 0u;
        for (uint j = 0u; j < k; j++) if (rt_binders[binder + j] < param) position++;
        put4(12u, bindings + position, 0u, uint4(env, param_atom(param), roots + i, 0u));
    }
    for (uint o = 0u; o < count; o++)
        put4(16u, obligations + o, 0u, uint4(call, predicate_row(applicable_record(callee, o)), env, 0u));
    if (cfg(RC_CFG_PHASE) == 1u)
    {
        // The publication's use map (route_abi.slang); pass 07 adds the call status.
        uint at = cfg(RC_CFG_ROUTE_USES) + use * 4u;
        rc_routes[at] = call + 1u;
        rc_routes[at + 1u] = obligations;
        rc_routes[at + 2u] = count;
    }
}
public void fill_job(uint lane, uint job)
{
    put4(0u, job, 0u, uint4(rc_snapshot[job * 2u], rc_snapshot[job * 2u + 1u], job, cfg(RC_CFG_GENERATION)));
}
public uint region_end(uint region)
{
    return region + 1u < RC_REGIONS ? region_base(region + 1u) : lanes();
}
public void write_catalog_header()
{
    if (cfg(RC_CFG_PHASE) != 0u) return;
    rc_catalog[0u] = TS_MAGIC_WORD; rc_catalog[1u] = TS_VERSION_WORD;
    rc_catalog[2u] = cfg(RC_CFG_EPOCH); rc_catalog[3u] = cfg(RC_CFG_EPOCH + 1u);
}
// One fill kernel per region (entries/06_fill_*): its lane, or RC_INVALID.
public uint region_lane(uint region, uint local)
{
    uint lane = region_base(region) + local;
    return lane < region_end(region) ? lane : RC_INVALID;
}
