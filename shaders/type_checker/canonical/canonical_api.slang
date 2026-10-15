// Canonical type and constant identities (hash-consing). See
// docs/canonical-type-ids.md for the record layout, invariants and protocol.
//
// Every distinct type, constant and environment has exactly one canonical ID:
// a flat record whose children are canonical IDs, so identity is `==` on IDs
// and a key compares O(arity) words. This module is deliberately NOT generic
// over any graph adapter; every consumer shares one instantiation.
//
// Interning is single-dispatch and lock-free: a lane writes its complete
// record (key and facts), issues a device-scope release fence and CASes an
// empty hash slot from 0 to the record ID. A lane that meets an occupied slot
// fences (acquire) and compares the occupant's record, which was complete
// before its CAS. Nobody ever waits for another invocation.
import primitive_types;

// ---------------------------------------------------------------------------
// References. A canonical reference is a record ID in [1, CT_ID_LIMIT), a
// parameter leaf, or a sentinel. Scalar codes 1..SCALAR_USIZE are preseeded
// record IDs. Parameter leaves are not records: they carry their declaration
// token and domain, so `T` of two different binders never collides.
public static const uint CT_PENDING = 0xffffffffu;
public static const uint CT_UNKNOWN = 0xfffffffeu;
public static const uint CT_NONE = 0xfffffffdu;
public static const uint CT_PARAM_BIT = 0x80000000u;
public static const uint CT_CONST_PARAM_BIT = 0x40000000u;
public static const uint CT_PARAM_TOKEN_MASK = 0x1fffffffu;
// Parameters of a dependency signature (tag 5) are slot leaves: their binder
// is the dependency declaration or callee whose environment is applied.
public static const uint CT_DEP_PARAM_BIT = 0x20000000u;
public static const uint CT_DEP_PARAM_SLOTS = 32u;
public static const uint CT_ID_LIMIT = 0x40000000u;
// First record ID that is not a preseeded scalar.
public static const uint CT_FIRST_RECORD = 32u;
// Tag-3 rows at or above this payload are canonical IDs read through the
// checked type graph bridge (payload = CT_ROW_BASE + id).
public static const uint CT_ROW_BASE = 0x40000000u;
public static const uint CT_MAX_ARITY = 64u;

// Record kinds (low 8 bits of ct_head.x).
public static const uint CT_KIND_SCALAR = 1u;   // w0 scalar code
public static const uint CT_KIND_NAMED = 2u;    // w = (library, unit, local); args = ordered operands
public static const uint CT_KIND_ARRAY = 3u;    // args = (element, length count class)
public static const uint CT_KIND_SLICE = 4u;    // args = (element)
public static const uint CT_KIND_REF = 5u;      // args = (element)
public static const uint CC_KIND_VALUE = 8u;    // w = (scalar, lo, hi)
public static const uint CC_KIND_CAST = 9u;     // w0 target scalar; args = (symbolic child)
public static const uint CC_KIND_COUNT = 10u;   // w0 count; the count-identity domain
public static const uint CT_KIND_ENV = 16u;     // w = (owner, type mask, constant mask);
                                                // args = bound type slots, then bound constant slots

// Fact flags (ct_meta.y bits 16..31).
public static const uint CTF_TYPE_PARAM = 1u;   // some leaf is a type parameter
public static const uint CTF_CONST_PARAM = 2u;  // some leaf is a constant parameter

// Local declarations that are not exported use this bit in the `local`
// identity word; exported ones use their persisted interface index.
public static const uint CT_PRIVATE_LOCAL_BIT = 0x80000000u;

// ---------------------------------------------------------------------------
// Tables. Records are written once, before publication, and never change.
// ct_head  = (kind | arity << 8 | type_slots << 16, w0, w1, w2)
// ct_meta  = (arg_base, height | flags << 16, shash.lo, shash.hi)
// ct_extra = kind facts: NAMED (local decl token or INVALID, constant
//            operand mask); constants (count or INVALID, count class ID).
public globallycoherent RWStructuredBuffer<uint4> ct_head;
public globallycoherent RWStructuredBuffer<uint4> ct_meta;
public globallycoherent RWStructuredBuffer<uint2> ct_extra;
public globallycoherent RWStructuredBuffer<uint> ct_args;
// Open-addressing table of published IDs; 0 is empty. Power-of-two length.
public globallycoherent RWStructuredBuffer<uint> ct_slot;
// Counters and round state; see CT_COUNT_*. CT_COUNT_WORDS words.
public globallycoherent RWStructuredBuffer<uint> ct_counts;
// Canonical reference of every interning candidate: checked instance rows,
// constant atoms and constant projections. CT_PENDING until interned.
public globallycoherent RWStructuredBuffer<uint> canonical_row;
public globallycoherent RWStructuredBuffer<uint> canonical_atom;
public globallycoherent RWStructuredBuffer<uint> canonical_projection;
// Canonical reference of every dependency type node by its job-wide index:
// the page's span base (dependency_constant_type_span_base) plus the node.
// Written while the page is resident; CT_PENDING until interned.
public globallycoherent RWStructuredBuffer<uint> canonical_dependency_type;

public static const uint CT_COUNT_NEXT_RECORD = 0u;
public static const uint CT_COUNT_NEXT_ARG = 1u;
public static const uint CT_COUNT_PENDING = 2u;   // candidates left after the last round
public static const uint CT_COUNT_OVERFLOW = 3u;  // CT_OVERFLOW_* bits
public static const uint CT_COUNT_ROUND = 4u;
public static const uint CT_COUNT_FRONTIER = 5u;  // [5], [6]: ping-pong frontier lengths
public static const uint CT_COUNT_FINAL = 7u;     // nonzero: pending candidates become UNKNOWN
public static const uint CT_COUNT_LIBRARY = 8u;   // job identity of local declarations
public static const uint CT_COUNT_UNIT = 9u;
public static const uint CT_COUNT_WORDS = 16u;

// Interning rounds per job: a candidate still pending at the limit becomes
// UNKNOWN and sets CT_OVERFLOW_ROUNDS (the old walkers capped depth at 64).
public static const uint CT_MAX_ROUNDS = 64u;

public static const uint CT_OVERFLOW_TABLE = 1u;
public static const uint CT_OVERFLOW_RECORDS = 2u;
public static const uint CT_OVERFLOW_ARGS = 4u;
public static const uint CT_OVERFLOW_ROUNDS = 8u;
// 16 is CT_OVERFLOW_SUBST_MEMO (substitution/ct_subst.slang).
// A round appended more pending candidates or nodes than a frontier list holds.
public static const uint CT_OVERFLOW_FRONTIER = 32u;

public uint ct_record_capacity()
{
    uint count; uint stride;
    ct_head.GetDimensions(count, stride);
    return min(count, CT_ID_LIMIT);
}

public uint ct_slot_capacity()
{
    uint count; uint stride;
    ct_slot.GetDimensions(count, stride);
    return count;
}

public uint ct_arg_capacity()
{
    uint count; uint stride;
    ct_args.GetDimensions(count, stride);
    return count;
}

// ---------------------------------------------------------------------------
// Reference classification. Sentinels are the three largest values, so a
// resolved reference is nonzero and below CT_NONE.
public bool ct_is_resolved(uint ref)
{
    return ref - 1u < CT_NONE - 1u;
}

public bool ct_is_param(uint ref)
{
    return ref - CT_PARAM_BIT < CT_NONE - CT_PARAM_BIT;
}

public bool ct_is_type_param(uint ref)
{
    return ref - CT_PARAM_BIT < CT_CONST_PARAM_BIT;
}

public bool ct_is_const_param(uint ref)
{
    return ref - (CT_PARAM_BIT | CT_CONST_PARAM_BIT) < CT_NONE - (CT_PARAM_BIT | CT_CONST_PARAM_BIT);
}

public bool ct_is_record(uint ref)
{
    return ref - 1u < CT_ID_LIMIT - 1u;
}

// Dynamic records exclude the preseeded scalar IDs.
public bool ct_is_stored(uint ref)
{
    return ref - (SCALAR_USIZE + 1u) < CT_ID_LIMIT - (SCALAR_USIZE + 1u);
}

public uint ct_type_param(uint token)
{
    return token <= CT_PARAM_TOKEN_MASK ? CT_PARAM_BIT | token : CT_UNKNOWN;
}

public uint ct_const_param(uint token)
{
    return token <= CT_PARAM_TOKEN_MASK ? CT_PARAM_BIT | CT_CONST_PARAM_BIT | token : CT_UNKNOWN;
}

public uint ct_param_token(uint ref)
{
    return ref & CT_PARAM_TOKEN_MASK;
}

public uint ct_dep_type_param(uint slot)
{
    return slot < CT_DEP_PARAM_SLOTS ? CT_PARAM_BIT | CT_DEP_PARAM_BIT | slot : CT_UNKNOWN;
}

// A dependency constant parameter also carries its declared scalar, so a
// substitution is checked without its signature node.
public uint ct_dep_const_param(uint slot, uint scalar)
{
    return slot < CT_DEP_PARAM_SLOTS && scalar < 32u
        ? CT_PARAM_BIT | CT_CONST_PARAM_BIT | CT_DEP_PARAM_BIT | (scalar << 5u) | slot : CT_UNKNOWN;
}

public uint ct_dep_param_slot(uint ref)
{
    return ref & (CT_DEP_PARAM_SLOTS - 1u);
}

public uint ct_dep_param_scalar(uint ref)
{
    return (ref >> 5u) & 31u;
}

public bool ct_is_dep_param(uint ref)
{
    return ct_is_param(ref) && (ref & CT_DEP_PARAM_BIT) != 0u;
}

// ---------------------------------------------------------------------------
// Fact accessors. Valid for any resolved reference.
public uint ct_kind(uint ref)
{
    if (!ct_is_record(ref)) return 0u;
    return ref <= SCALAR_USIZE ? CT_KIND_SCALAR : ct_head[ref].x & 0xffu;
}

public uint ct_arity(uint ref)
{
    return ct_is_stored(ref) ? (ct_head[ref].x >> 8u) & 0xffu : 0u;
}

// Type-slot count of an environment, type-operand count of a named type.
public uint ct_type_slots(uint ref)
{
    return ct_is_stored(ref) ? ct_head[ref].x >> 16u : 0u;
}

public uint3 ct_words(uint ref)
{
    if (!ct_is_record(ref)) return uint3(0u, 0u, 0u);
    return ref <= SCALAR_USIZE ? uint3(ref, 0u, 0u) : ct_head[ref].yzw;
}

public uint ct_arg(uint ref, uint index)
{
    if (!ct_is_stored(ref)) return CT_NONE;
    uint4 head = ct_head[ref];
    return index < ((head.x >> 8u) & 0xffu) ? ct_args[ct_meta[ref].x + index] : CT_NONE;
}

public bool ct_is_constant(uint ref)
{
    if (ct_is_param(ref)) return ct_is_const_param(ref);
    return ct_kind(ref) - CC_KIND_VALUE < CT_KIND_ENV - CC_KIND_VALUE;
}

// Deterministic structural hash: built from kinds, raw key words and child
// hashes only, never from IDs. It is the only identity that may leave the GPU
// or decide an ordering.
public uint2 ct_hash_mix(uint2 hash, uint2 value)
{
    hash.x = (hash.x ^ value.x) * 0x01000193u;
    hash.x ^= hash.x >> 15u;
    hash.y = (hash.y ^ value.y) * 0x9e3779b1u + hash.x;
    hash.y ^= hash.y >> 13u;
    return hash;
}

public uint2 ct_hash_word(uint2 hash, uint value)
{
    return ct_hash_mix(hash, uint2(value, value * 0x85ebca6bu + 0x165667b1u));
}

public static const uint2 CT_HASH_SEED = uint2(0x811c9dc5u, 0x3c6ef372u);

// (height, flags, shash) of a resolved reference, from one read. Parameter
// leaves have height 0 and preseeded scalars height 1.
public uint4 ct_facts(uint ref)
{
    if (ct_is_stored(ref))
    {
        uint4 meta = ct_meta[ref];
        return uint4(meta.y & 0xffffu, meta.y >> 16u, meta.zw);
    }
    bool param = ct_is_param(ref);
    uint flags = !param ? 0u : ct_is_const_param(ref) ? CTF_CONST_PARAM : CTF_TYPE_PARAM;
    uint2 hash = ct_hash_word(ct_hash_word(CT_HASH_SEED, param ? 0xabcd0000u : CT_KIND_SCALAR), ref);
    return uint4(param ? 0u : 1u, flags, hash);
}

public uint ct_height(uint ref) { return ct_is_resolved(ref) ? ct_facts(ref).x : 0u; }
public uint ct_flags(uint ref) { return ct_is_resolved(ref) ? ct_facts(ref).y : 0u; }
public uint2 ct_shash(uint ref) { return ct_is_resolved(ref) ? ct_facts(ref).zw : uint2(0u, 0u); }

public bool ct_closed(uint ref)
{
    return ct_is_resolved(ref) && (ct_facts(ref).y & (CTF_TYPE_PARAM | CTF_CONST_PARAM)) == 0u;
}

// Constant facts: the u32 count of a concrete count-valid value, and the
// count-identity class (CC_COUNT record or parameter leaf) of any constant.
public uint cc_count(uint ref)
{
    uint kind = ct_kind(ref);
    return kind == CC_KIND_VALUE || kind == CC_KIND_COUNT ? ct_extra[ref].x : 0xffffffffu;
}

public uint cc_count_class(uint ref)
{
    if (ct_is_const_param(ref)) return ref;
    uint kind = ct_kind(ref);
    if (kind == CC_KIND_COUNT) return ref;
    return kind == CC_KIND_VALUE || kind == CC_KIND_CAST ? ct_extra[ref].y : CT_NONE;
}

// Named-type facts for the checked-graph bridge.
public uint ct_named_decl_token(uint ref)
{
    return ct_kind(ref) == CT_KIND_NAMED ? ct_extra[ref].x : 0xffffffffu;
}

public uint ct_named_constant_mask(uint ref)
{
    return ct_kind(ref) == CT_KIND_NAMED ? ct_extra[ref].y : 0u;
}

// ---------------------------------------------------------------------------
// Checked operands. Maps a checked (tag, payload) operand to its canonical
// reference: 1 scalar (and legacy scalar-coded nominal rows 4096..8191),
// 2 type parameter token, 3 instance row (or a bridged CT ID at CT_ROW_BASE),
// and the constant argument tags (atom, constant parameter, projection; atom
// and projection payloads at CT_ROW_BASE are bridged constant IDs).
// Parameter validity is the producer's concern; this is a pure mapping.
public static const uint CT_CONSTANT_TAG_BIT = 0x80000000u;

public uint ct_row_capacity() { uint n; uint s; canonical_row.GetDimensions(n, s); return n; }
public uint ct_atom_capacity() { uint n; uint s; canonical_atom.GetDimensions(n, s); return n; }
public uint ct_projection_capacity() { uint n; uint s; canonical_projection.GetDimensions(n, s); return n; }
public uint ct_dependency_capacity() { uint n; uint s; canonical_dependency_type.GetDimensions(n, s); return n; }

public uint ct_row_ref(uint row)
{
    return row < ct_row_capacity() ? canonical_row[row] : CT_UNKNOWN;
}

public uint ct_constant_ref(uint kind, uint payload)
{
    // A bridged value, count class or cast (canonical_bridge.slang).
    if ((kind == 1u || kind == 3u) && payload >= CT_ROW_BASE) return payload - CT_ROW_BASE;
    if (kind == 1u) return payload < ct_atom_capacity() ? canonical_atom[payload] : CT_UNKNOWN;
    if (kind == 2u) return ct_const_param(payload);
    if (kind == 3u) return payload < ct_projection_capacity() ? canonical_projection[payload] : CT_UNKNOWN;
    return CT_UNKNOWN;
}

// Interning candidates: rows [0, R), atoms [R, R + A), projections
// [R + A, R + A + P). No candidate or dependency node owns a record: a key
// takes one from ct_alloc_record only when the table lacks it (ct_intern_key).
public uint ct_candidate_count()
{
    return ct_row_capacity() + ct_atom_capacity() + ct_projection_capacity();
}

public uint ct_candidate_state(uint candidate)
{
    uint rows = ct_row_capacity();
    if (candidate < rows) return canonical_row[candidate];
    uint atoms = ct_atom_capacity();
    if (candidate - rows < atoms) return canonical_atom[candidate - rows];
    uint projection = candidate - rows - atoms;
    return projection < ct_projection_capacity() ? canonical_projection[projection] : CT_UNKNOWN;
}

// Release fence first: a lane that reads this reference and then the
// record's facts must observe the record, even when this lane adopted a
// record that another lane published.
public void ct_publish_candidate(uint candidate, uint id)
{
    DeviceMemoryBarrier();
    uint rows = ct_row_capacity();
    uint atoms = ct_atom_capacity();
    if (candidate < rows) canonical_row[candidate] = id;
    else if (candidate - rows < atoms) canonical_atom[candidate - rows] = id;
    else if (candidate - rows - atoms < ct_projection_capacity())
        canonical_projection[candidate - rows - atoms] = id;
}

public uint ct_ref(uint tag, uint payload)
{
    if (payload == 0xffffffffu) return CT_UNKNOWN;
    if ((tag & CT_CONSTANT_TAG_BIT) != 0u) return ct_constant_ref(tag & ~CT_CONSTANT_TAG_BIT, payload);
    if (tag == 1u)
    {
        if (payload >= 1u && payload <= SCALAR_USIZE) return payload;
        // Monomorphic nominal values keep legacy scalar-coded references to
        // the declaration's own zero-argument application row.
        if (payload >= 4096u && payload < 8192u)
            return ct_row_ref(payload - (payload < 6144u ? 4096u : 6144u));
        return CT_UNKNOWN;
    }
    if (tag == 2u) return ct_type_param(payload);
    if (tag == 3u) return payload >= CT_ROW_BASE ? payload - CT_ROW_BASE : ct_row_ref(payload);
    return CT_UNKNOWN;
}

// ---------------------------------------------------------------------------
// Key construction. A builder accumulates the key's facts while its
// arguments are written straight into ct_args.
public struct CtKey
{
    public uint4 head;
    public uint arg_base;
    public uint height;
    public uint flags;
    public uint2 shash;
    // The record's ct_extra facts, stored with the key (ct_key_store).
    public uint2 extra;
    public bool ok;
}

public CtKey ct_key_begin(uint kind, uint arity, uint type_slots, uint3 words)
{
    CtKey key;
    key.head = uint4(kind | (arity << 8u) | (type_slots << 16u), words);
    key.arg_base = 0u;
    key.height = 0u;
    key.flags = 0u;
    key.extra = uint2(0xffffffffu, 0u);
    key.ok = arity <= CT_MAX_ARITY;
    uint2 hash = ct_hash_word(CT_HASH_SEED, key.head.x);
    hash = ct_hash_word(hash, words.x);
    hash = ct_hash_word(hash, words.y);
    key.shash = ct_hash_word(hash, words.z);
    return key;
}

// Allocate argument words for a key (dynamic records and candidates alike).
public bool ct_key_reserve_args(inout CtKey key)
{
    uint arity = (key.head.x >> 8u) & 0xffu;
    if (arity == 0u || !key.ok) return key.ok;
    uint base; InterlockedAdd(ct_counts[1u], arity, base);
    uint capacity = ct_arg_capacity();
    if (base > capacity || arity > capacity - base)
    {
        InterlockedOr(ct_counts[3u], CT_OVERFLOW_ARGS);
        key.ok = false;
        return false;
    }
    key.arg_base = base;
    return true;
}

// Fold one child's facts into the key. Does not write the argument word.
public void ct_key_fold(inout CtKey key, uint child)
{
    if (!ct_is_resolved(child)) { key.ok = false; return; }
    uint4 facts = ct_facts(child);
    key.height = max(key.height, facts.x);
    key.flags |= facts.y;
    key.shash = ct_hash_mix(key.shash, facts.zw);
}

// Append argument `index` (requires ct_key_reserve_args).
public void ct_key_arg(inout CtKey key, uint index, uint child)
{
    ct_key_fold(key, child);
    if (key.ok) ct_args[key.arg_base + index] = child;
}

// Write the complete record at `record`. It is not yet visible to lookups.
public void ct_key_store(CtKey key, uint record, uint2 extra)
{
    ct_head[record] = key.head;
    ct_meta[record] = uint4(key.arg_base, min(key.height + 1u, 0xffffu) | (key.flags << 16u),
        key.shash);
    ct_extra[record] = extra;
}

public uint ct_probe_start(uint2 shash)
{
    return (shash.x ^ (shash.y * 0x27d4eb2du)) & (ct_slot_capacity() - 1u);
}

// Key equality against a published record, given the candidate's key.
public bool ct_record_matches(uint record, CtKey key)
{
    if (record == 0u || record >= ct_record_capacity()) return false;
    if (any(ct_head[record] != key.head)) return false;
    uint4 meta = ct_meta[record];
    if (any(meta.zw != key.shash)) return false;
    uint arity = (key.head.x >> 8u) & 0xffu;
    for (uint i = 0u; i < arity; i++)
        if (ct_args[meta.x + i] != ct_args[key.arg_base + i]) return false;
    return true;
}

// Small keys (arity <= 2) compare against register arguments.
public bool ct_record_matches_small(uint record, uint4 head, uint2 shash, uint2 args)
{
    if (record == 0u || record >= ct_record_capacity()) return false;
    if (any(ct_head[record] != head)) return false;
    uint4 meta = ct_meta[record];
    if (any(meta.zw != shash)) return false;
    uint arity = (head.x >> 8u) & 0xffu;
    if (arity >= 1u && ct_args[meta.x] != args.x) return false;
    if (arity >= 2u && ct_args[meta.x + 1u] != args.y) return false;
    return true;
}

// Publish the stored record `record`, or return the equal record that is
// already published. When the result differs from `record`, the caller still
// owns `record` and may reuse it for another key.
public uint ct_intern(uint record, CtKey key)
{
    if (!key.ok) return CT_UNKNOWN;
    uint slots = ct_slot_capacity();
    uint slot = ct_probe_start(key.shash);
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint value = ct_slot[slot];
        if (value == 0u)
        {
            // Release: the complete record precedes its publication.
            DeviceMemoryBarrier();
            InterlockedCompareExchange(ct_slot[slot], 0u, record, value);
            if (value == 0u) return record;
        }
        // Acquire: the occupant's record was complete before its CAS.
        DeviceMemoryBarrier();
        if (value == record || ct_record_matches(value, key)) return value;
        slot = (slot + 1u) & (slots - 1u);
    }
    InterlockedOr(ct_counts[3u], CT_OVERFLOW_TABLE);
    return CT_UNKNOWN;
}

// Intern a built key (arguments already written) that owns no record. The
// probe adopts an equal published record; only a key the table lacks takes a
// record, allocated and stored once, at the first empty slot. A lane that
// then loses that slot to an equal key keeps its record unpublished, and
// nothing references it.
public uint ct_intern_key(CtKey key)
{
    if (!key.ok) return CT_UNKNOWN;
    uint slots = ct_slot_capacity();
    uint slot = ct_probe_start(key.shash);
    uint record = CT_NONE;
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint value = ct_slot[slot];
        if (value == 0u)
        {
            if (record == CT_NONE)
            {
                record = ct_alloc_record();
                if (record == CT_UNKNOWN) return CT_UNKNOWN;
                ct_key_store(key, record, key.extra);
            }
            // Release: the complete record precedes its publication.
            DeviceMemoryBarrier();
            InterlockedCompareExchange(ct_slot[slot], 0u, record, value);
            if (value == 0u) return record;
        }
        // Acquire: the occupant's record was complete before its CAS.
        DeviceMemoryBarrier();
        if (ct_record_matches(value, key)) return value;
        slot = (slot + 1u) & (slots - 1u);
    }
    InterlockedOr(ct_counts[3u], CT_OVERFLOW_TABLE);
    return CT_UNKNOWN;
}

// Find a published record equal to a stored key without publishing it.
public uint ct_lookup(CtKey key)
{
    if (!key.ok) return CT_UNKNOWN;
    uint slots = ct_slot_capacity();
    uint slot = ct_probe_start(key.shash);
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint value = ct_slot[slot];
        if (value == 0u) return CT_NONE;
        DeviceMemoryBarrier();
        if (ct_record_matches(value, key)) return value;
        slot = (slot + 1u) & (slots - 1u);
    }
    return CT_NONE;
}

// Whether `record` is in the table. A published record is never rewritten,
// so its stored hash leads to its slot.
public bool ct_is_published(uint record)
{
    uint slots = ct_slot_capacity();
    uint probe = ct_probe_start(ct_meta[record].zw);
    for (uint step = 0u; step < slots; step++)
    {
        uint other = ct_slot[probe];
        if (other == record) return true;
        if (other == 0u) return false;
        probe = (probe + 1u) & (slots - 1u);
    }
    return false;
}

public uint ct_alloc_record()
{
    uint record; InterlockedAdd(ct_counts[0u], 1u, record);
    if (record >= ct_record_capacity())
    {
        InterlockedOr(ct_counts[3u], CT_OVERFLOW_RECORDS);
        return CT_UNKNOWN;
    }
    return record;
}

// Intern a key of arity <= 2 whose arguments live in registers. The lookup
// runs first; a record is stored only for a key not yet present. `spare` is a
// lane-owned unpublished record (CT_NONE when the lane has none): it is used
// before allocating, and a lane that loses the publication race to an equal
// key keeps its record in `spare` for its next key. A spare is never
// referenced by anyone else, so rewriting it is safe.
public uint ct_intern_small(uint kind, uint arity, uint3 words, uint2 args, uint2 extra,
    inout uint spare)
{
    CtKey key = ct_key_begin(kind, arity, 0u, words);
    if (arity > 2u) return CT_UNKNOWN;
    if (arity >= 1u) ct_key_fold(key, args.x);
    if (arity >= 2u) ct_key_fold(key, args.y);
    if (!key.ok) return CT_UNKNOWN;
    if (kind == CT_KIND_SCALAR && words.x >= 1u && words.x <= SCALAR_USIZE && arity == 0u &&
        words.y == 0u && words.z == 0u) return words.x;
    uint slots = ct_slot_capacity();
    uint slot = ct_probe_start(key.shash);
    bool stored = false;
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint value = ct_slot[slot];
        if (value == 0u)
        {
            if (!stored)
            {
                if (spare == CT_NONE) spare = ct_alloc_record();
                if (spare == CT_UNKNOWN) { spare = CT_NONE; return CT_UNKNOWN; }
                if (!ct_key_reserve_args(key)) return CT_UNKNOWN;
                if (arity >= 1u) ct_args[key.arg_base] = args.x;
                if (arity >= 2u) ct_args[key.arg_base + 1u] = args.y;
                ct_key_store(key, spare, extra);
                stored = true;
            }
            DeviceMemoryBarrier();
            InterlockedCompareExchange(ct_slot[slot], 0u, spare, value);
            if (value == 0u)
            {
                uint id = spare;
                spare = CT_NONE;
                return id;
            }
        }
        DeviceMemoryBarrier();
        if (ct_record_matches_small(value, key.head, key.shash, args)) return value;
        slot = (slot + 1u) & (slots - 1u);
    }
    InterlockedOr(ct_counts[3u], CT_OVERFLOW_TABLE);
    return CT_UNKNOWN;
}

// Intern a built key (arguments already written) through a lane-owned spare
// record, looking it up first. Same `spare` contract as ct_intern_small.
public uint ct_intern_spare(CtKey key, uint2 extra, inout uint spare)
{
    uint found = ct_lookup(key);
    if (found != CT_NONE) return found;
    if (spare == CT_NONE) spare = ct_alloc_record();
    if (spare == CT_UNKNOWN) { spare = CT_NONE; return CT_UNKNOWN; }
    ct_key_store(key, spare, extra);
    uint id = ct_intern(spare, key);
    if (id == spare) spare = CT_NONE;
    return id;
}

// The count-identity record of `count`. Every count record is built here so
// its stored facts do not depend on which caller publishes it.
public uint cc_intern_count(uint count, inout uint spare)
{
    return ct_intern_small(CC_KIND_COUNT, 0u, uint3(count, 0u, 0u), uint2(0u, 0u),
        uint2(count, CT_NONE), spare);
}
