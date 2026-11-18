// Build-scoped program retention store (docs/compiler-program-retention.md).
//
// One store lives for one build. Every frontend job exports into it before
// its workspace is reused, and later GPU stages (discovery, projection) read
// only this store. Job-local canonical IDs, tokens and HIR rows never appear
// here: they are translated into the handles below.
//
// Handles are 1-based indexes into their arena; 0 is never a valid handle.
//
//   DeclId  rt_decl_key[id]  = (library, unit, namespace, local)
//   ParamId rt_param_key[id] = (owner DeclId, domain, ordinal, declared scalar)
//   TermId  rt_term_head[id] = (kind | arity << 8 | type_slots << 16, w0, w1, w2)
//
// A term reference is a TermId below RT_PARAM_BIT, a parameter leaf
// (RT_PARAM_BIT | [RT_CONST_BIT] | ParamId), a dependency-signature slot
// leaf (RT_PARAM_BIT | [RT_CONST_BIT] | RT_SLOT_BIT | scalar << 5 | slot,
// the canonical store's encoding), or a sentinel. Scalar terms 1..31 are
// preseeded and have no record, as in the canonical store.
//
// Interning is the canonical store's lock-free protocol: a lane writes its
// complete record, fences, and CASes an empty hash slot. A lane that loses an
// equal key keeps its record unpublished (a spare, counted in RT_C_SPARE).
// Equality is always a comparison of complete records; the hash only picks
// the first probe, and rt_config[RT_CFG_HASH_MASK] can force every key onto
// one probe chain to prove that collisions never merge distinct keys.
import shared.semantics.primitive_types;

public globallycoherent RWStructuredBuffer<uint> rt_counts;
public RWStructuredBuffer<uint> rt_config;
public globallycoherent RWStructuredBuffer<uint4> rt_decl_key;
public globallycoherent RWStructuredBuffer<uint> rt_decl_slot;
// Committed directory entry of a declaration, plus one; 0 when no committed
// job defines it. Written when the declaration's record is allocated (0)
// and at commit, so a new build needs no clear of this column.
public globallycoherent RWStructuredBuffer<uint> rt_decl_def;
public globallycoherent RWStructuredBuffer<uint4> rt_param_key;
public globallycoherent RWStructuredBuffer<uint> rt_param_slot;
public globallycoherent RWStructuredBuffer<uint4> rt_term_head;
// (arg base, flags | height << 16, hash lo, hash hi)
public globallycoherent RWStructuredBuffer<uint4> rt_term_meta;
// (owner a, owner b): the distinct owner DeclIds of the term's parameter
// leaves, at most two; RT_OWNERS_MANY in .y when there are more.
public globallycoherent RWStructuredBuffer<uint2> rt_term_owner;
public globallycoherent RWStructuredBuffer<uint> rt_term_args;
public globallycoherent RWStructuredBuffer<uint> rt_term_slot;

// Discovery records (resident for the whole build).
public globallycoherent RWStructuredBuffer<uint4> rt_dir;       // RT_DIR_WORDS per entry
public globallycoherent RWStructuredBuffer<uint> rt_binders;    // ParamIds in composed slot order
public globallycoherent RWStructuredBuffer<uint> rt_sigs;       // result term, then parameter terms
public globallycoherent RWStructuredBuffer<uint4> rt_schema;    // field and variant-payload records
public globallycoherent RWStructuredBuffer<uint4> rt_uses;      // RT_USE_WORDS per use
// Exact diagnostic provenance, including uses in nongeneric bodies whose
// body segment is not retained: job, file, file-relative byte, token length.
public globallycoherent RWStructuredBuffer<uint4> rt_use_spans;
// Trait facts. rt_dir_trait is a column of the directory (one uint4 per
// entry): (first predicate record, predicate count, first binding record,
// binding count). rt_traits holds RT_TRAIT_WORDS uint4 per record:
//   PREDICATE t0 (owner DeclId, PREDICATE | ordinal << 8, subject term, trait term)
//             t1 (trait DeclId, file id, file-relative byte start, byte length)
//   BINDING   t0 (impl DeclId, BINDING | receiver mode << 8 | ordinal << 16,
//                 required member DeclId, method DeclId)
//             t1 (trait DeclId, required member symbol, file id,
//                 file-relative byte start of the method's name)
// A trait term is NAMED (trait DeclId, constant-operand mask) over the
// argument terms, in the owner's scope.
public globallycoherent RWStructuredBuffer<uint4> rt_dir_trait;
public globallycoherent RWStructuredBuffer<uint4> rt_traits;
// One row per committed job ordinal, including jobs with no declarations:
// (library, unit, build generation, 0). Published only on transaction commit.
public globallycoherent RWStructuredBuffer<uint4> rt_jobs;
// Body payloads (streamable: nothing in the discovery records points into
// them except a segment index and arena ranges).
public globallycoherent RWStructuredBuffer<uint4> rt_segments;  // RT_SEG_WORDS per segment
public globallycoherent RWStructuredBuffer<uint4> rt_seg_rows;  // RT_ROW_WORDS per row
public globallycoherent RWStructuredBuffer<uint4> rt_seg_side;  // one record per side-table row
public globallycoherent RWStructuredBuffer<uint> rt_seg_bytes;  // string bytes and body source text, 4 per word
public globallycoherent RWStructuredBuffer<uint4> rt_seg_tokens; // body tokens: (kind, text byte start, length, name hash)

public static const uint RT_DIR_WORDS = 4u;
public static const uint RT_USE_WORDS = 3u;
// Native call argument mode also records whether an i32 zero was a literal.
public static const uint RT_CALL_ARG_NULL_LITERAL = 1u << 8u;
public static const uint RT_SEG_WORDS = 6u;
public static const uint RT_ROW_WORDS = 7u;
public static const uint RT_DIR_STAGED = 1u;
public static const uint RT_DIR_COMMITTED = 2u;
public static const uint RT_DIR_INCOMPLETE = 1u;
// Schema record kinds (rt_schema .y low byte).
public static const uint RT_SCHEMA_FIELD = 1u;    // (struct, FIELD | ordinal << 8, 0, declared term)
public static const uint RT_SCHEMA_PAYLOAD = 2u;  // (enum, PAYLOAD | ordinal << 8, variant ordinal, declared term)
public static const uint RT_SCHEMA_VARIANT = 3u;  // (enum, VARIANT | ordinal << 8, payload count, first payload record)
public static const uint RT_SCHEMA_CONST = 4u;    // (constant, CONST | present << 8, value lo, value hi)
public static const uint RT_SCHEMA_NATIVE_ABI = 5u; // (extern, NATIVE_ABI, accepted ABI flags, 0)
public static const uint RT_TRAIT_WORDS = 2u;
// Trait fact kinds (rt_traits t0.y low byte).
public static const uint RT_TRAIT_PREDICATE = 1u;
public static const uint RT_TRAIT_BINDING = 2u;

public static const uint RT_INVALID = 0xffffffffu;
public static const uint RT_UNKNOWN = 0xfffffffeu;
public static const uint RT_NONE = 0xfffffffdu;
// A constant projection that did not fit its target (the canonical store's
// CT_FIT_FAILED, 0xfffffffc). Never a resolved term: it must propagate as a
// fit failure, not collapse into RT_UNKNOWN.
public static const uint RT_FIT_FAILED = 0xfffffffcu;
public static const uint RT_PARAM_BIT = 0x80000000u;
public static const uint RT_CONST_BIT = 0x40000000u;
public static const uint RT_SLOT_BIT = 0x20000000u;
public static const uint RT_ID_MASK = 0x1fffffffu;
public static const uint RT_FIRST_TERM = 32u;
public static const uint RT_OWNERS_MANY = 0xffffffffu;

// Term kinds: the canonical store's kinds, with the declaration word of a
// NAMED term and the owner word of an ENV term replaced by DeclIds.
//   SCALAR 1  w0 scalar (preseeded, no record)
//   NAMED  2  w0 DeclId, w1 constant-operand mask; args ordered operands
//   ARRAY  3  args (element, length count class)
//   SLICE  4, REF 5  args (element)
//   CC_VALUE 8  w = (scalar, lo, hi)
//   CC_CAST  9  w0 target scalar; args (symbolic child). Kept as a pending
//               fit obligation even though its count class equals the child's.
//   CC_COUNT 10 w0 count
//   ENV 16  w = (owner DeclId or 0, type mask, constant mask); args = bound
//           type slots then bound constant slots, in the receiving scope.
public static const uint RT_KIND_SCALAR = 1u;
public static const uint RT_KIND_NAMED = 2u;
public static const uint RT_KIND_ARRAY = 3u;
public static const uint RT_KIND_SLICE = 4u;
public static const uint RT_KIND_REF = 5u;
public static const uint RT_KIND_CC_VALUE = 8u;
public static const uint RT_KIND_CC_CAST = 9u;
public static const uint RT_KIND_CC_COUNT = 10u;
public static const uint RT_KIND_ENV = 16u;

// Term flags (rt_term_meta.y low 16 bits).
public static const uint RTF_TYPE_PARAM = 1u;
public static const uint RTF_CONST_PARAM = 2u;
public static const uint RTF_SLOT = 4u;

// Declaration namespaces (rt_decl_key.z).
public static const uint RT_NS_CALLABLE = 1u;  // local = native callable identity (callable_identity.slang)
public static const uint RT_NS_NOMINAL = 2u;   // local = interface index or CT_PRIVATE_LOCAL_BIT | decl id
// Namespace 3 is unused: traits are nominal identities.
public static const uint RT_NS_IMPL = 4u;      // local = impl HIR row of the declaring job (unit-qualified)
public static const uint RT_NS_VALUE = 5u;     // local = constant's interface index or 0x40000000 | first token

// Parameter domains (rt_param_key.y) and the synthetic ordinal of `Self`.
public static const uint RT_DOMAIN_TYPE = 1u;
public static const uint RT_DOMAIN_CONST = 2u;
public static const uint RT_SELF_ORDINAL = 0xffffu;

// Arenas: their allocation counter is rt_counts[arena].
public static const uint RT_A_DECLS = 0u;
public static const uint RT_A_PARAMS = 1u;
public static const uint RT_A_TERMS = 2u;
public static const uint RT_A_TERM_ARGS = 3u;
public static const uint RT_A_DIR = 4u;
public static const uint RT_A_BINDERS = 5u;
public static const uint RT_A_SIGS = 6u;
public static const uint RT_A_SCHEMA = 7u;
public static const uint RT_A_USES = 8u;
public static const uint RT_A_SEGMENTS = 9u;
public static const uint RT_A_SEG_ROWS = 10u;
public static const uint RT_A_SEG_SIDE = 11u;
public static const uint RT_A_SEG_BYTES = 12u;
public static const uint RT_A_SEG_TOKENS = 13u;
public static const uint RT_A_TRAITS = 14u;
public static const uint RT_A_JOBS = 15u;
public static const uint RT_ARENAS = 16u;

// rt_counts layout.
public static const uint RT_C_JOB_BASE = 16u;   // + arena: counter at the job's start
public static const uint RT_C_DEMAND = 32u;     // + arena: largest end a failed allocation needed
public static const uint RT_C_SPARE = 48u;      // + arena: unpublished spare records (decls, params, terms, term args)
public static const uint RT_C_OVERFLOW = 64u;   // bits 1 << arena; RT_OVERFLOW_* table bits
public static const uint RT_C_INVARIANTS = 65u; // invariant failures of the current job
public static const uint RT_C_FIRST_INVARIANT = 66u; // smallest invariant code of the current job
public static const uint RT_C_JOBS = 67u;       // committed jobs of the build
public static const uint RT_C_JOB_STATE = 68u;  // RT_JOB_*
public static const uint RT_C_ROLLBACKS = 69u;  // jobs rolled back in this build
public static const uint RT_C_LIBRARY = 70u;    // current job (library, unit)
public static const uint RT_C_UNIT = 71u;
public static const uint RT_C_CONFLICTS = 72u;  // declarations defined by two committed entries
public static const uint RT_C_STAGED_DIR = 73u; // first staged directory entry of the job
public static const uint RT_C_INVARIANT_TOTAL = 74u; // invariant failures over the build
public static const uint RT_C_INCOMPLETE = 75u; // incomplete entries of the current committed job
public static const uint RT_C_INCOMPLETE_TOTAL = 76u; // incomplete entries over the build
public static const uint RT_C_READY = 77u; // exported records complete so far; not codegen admission
// Build generation: nonzero and unique per begin_build over every store of
// the process. A GPU consumer of a derived publication compares it with the
// generation the publication recorded.
public static const uint RT_C_GENERATION = 78u;
// The current job's smallest fault key, (row << 8) | reason: the row of a
// failure that makes an entry incomplete or breaks an invariant.
public static const uint RT_C_FAULT_KEY = 79u;
// The build's first fault, written when a committed job clears READY:
// RT_C_FAULT is the reason (RT_INV_* code, or RT_FAULT_STAT + RT_STAT_*)
// with RT_FAULT_LOCATED when the job, file, byte and length words name the
// row's first token. The trait catalog copies these words to its count
// readback, so an unready store reports where it failed.
public static const uint RT_C_FAULT = 89u;
public static const uint RT_C_FAULT_JOB = 90u;
public static const uint RT_C_FAULT_FILE = 91u;
public static const uint RT_C_FAULT_BYTE = 92u;
public static const uint RT_C_FAULT_LEN = 93u;
public static const uint RT_FAULT_STAT = 16u;
public static const uint RT_FAULT_UNKNOWN = 0xffu;
public static const uint RT_FAULT_LOCATED = 0x100u;
public static const uint RT_FAULT_NO_ROW = 0xffffffu;
public static const uint RT_C_JOB_SPARE = 80u; // + arena (decls..term args): spares at the job's start
// Build totals at the job's start, which an uncommit restores
// (export/19_uncommit.slang).
public static const uint RT_C_SAVED_JOBS = 84u;
public static const uint RT_C_SAVED_INVARIANT_TOTAL = 85u;
public static const uint RT_C_SAVED_INCOMPLETE_TOTAL = 86u;
public static const uint RT_C_SAVED_READY = 87u;
public static const uint RT_C_SAVED_CONFLICTS = 88u;
public static const uint RT_C_WORDS = 96u;

public static const uint RT_OVERFLOW_DECL_TABLE = 1u << 16u;
public static const uint RT_OVERFLOW_PARAM_TABLE = 1u << 17u;
public static const uint RT_OVERFLOW_TERM_TABLE = 1u << 18u;

public static const uint RT_JOB_OPEN = 1u;
public static const uint RT_JOB_COMMITTED = 2u;
public static const uint RT_JOB_ROLLED_BACK = 3u;

public static const uint RT_CFG_HASH_MASK = 0u;

// Records an arena holds. Handle arenas reserve index 0 (handles are 1-based).
// (Buffer dimensions are read in place: a helper taking the buffer would drop
// its globallycoherent qualifier.)
public uint rt_capacity(uint arena)
{
    uint n = 0u; uint m = 0u; uint k = 0u; uint s;
    if (arena == RT_A_DECLS) { rt_decl_key.GetDimensions(n, s); rt_decl_def.GetDimensions(m, s); return min(n, m); }
    if (arena == RT_A_PARAMS) { rt_param_key.GetDimensions(n, s); return n; }
    if (arena == RT_A_TERMS)
    {
        rt_term_head.GetDimensions(n, s); rt_term_meta.GetDimensions(m, s); rt_term_owner.GetDimensions(k, s);
        return min(min(n, m), k);
    }
    if (arena == RT_A_TERM_ARGS) { rt_term_args.GetDimensions(n, s); return n; }
    if (arena == RT_A_DIR) { rt_dir.GetDimensions(n, s); rt_dir_trait.GetDimensions(m, s); return min(n / RT_DIR_WORDS, m); }
    if (arena == RT_A_BINDERS) { rt_binders.GetDimensions(n, s); return n; }
    if (arena == RT_A_SIGS) { rt_sigs.GetDimensions(n, s); return n; }
    if (arena == RT_A_SCHEMA) { rt_schema.GetDimensions(n, s); return n; }
    if (arena == RT_A_USES) { rt_uses.GetDimensions(n, s); rt_use_spans.GetDimensions(m, s); return min(n / RT_USE_WORDS, m); }
    if (arena == RT_A_SEGMENTS) { rt_segments.GetDimensions(n, s); return n / RT_SEG_WORDS; }
    if (arena == RT_A_SEG_ROWS) { rt_seg_rows.GetDimensions(n, s); return n / RT_ROW_WORDS; }
    if (arena == RT_A_SEG_SIDE) { rt_seg_side.GetDimensions(n, s); return n; }
    if (arena == RT_A_SEG_BYTES) { rt_seg_bytes.GetDimensions(n, s); return n; }
    if (arena == RT_A_SEG_TOKENS) { rt_seg_tokens.GetDimensions(n, s); return n; }
    if (arena == RT_A_TRAITS) { rt_traits.GetDimensions(n, s); return n / RT_TRAIT_WORDS; }
    if (arena == RT_A_JOBS) { rt_jobs.GetDimensions(n, s); return n; }
    return 0u;
}

public void rt_overflow(uint arena, uint end)
{
    InterlockedOr(rt_counts[RT_C_OVERFLOW], 1u << arena);
    InterlockedMax(rt_counts[RT_C_DEMAND + arena], end);
}

// Reserve `n` consecutive slots of `arena`, or RT_INVALID after recording the
// overflow and the demand. The counter keeps the requested end either way, so
// its final value after a failed job is the job's whole demand.
public uint rt_alloc(uint arena, uint n)
{
    uint base;
    InterlockedAdd(rt_counts[arena], n, base);
    uint capacity = rt_capacity(arena);
    if (base > capacity || n > capacity - base)
    {
        rt_overflow(arena, base + n);
        return RT_INVALID;
    }
    return base;
}

public void rt_invariant(uint code)
{
    InterlockedAdd(rt_counts[RT_C_INVARIANTS], 1u);
    InterlockedMin(rt_counts[RT_C_FIRST_INVARIANT], code);
    rt_fault(RT_FAULT_NO_ROW, code);
}

// Records a fault of `row` (a HIR row of the job); the smallest row wins.
public void rt_fault(uint row, uint reason)
{
    InterlockedMin(rt_counts[RT_C_FAULT_KEY], (min(row, RT_FAULT_NO_ROW) << 8u) | (reason & 0xffu));
}

public uint rt_mix(uint h, uint v)
{
    h ^= v + 0x9e3779b9u + (h << 6u) + (h >> 2u);
    h ^= h >> 16u;
    h *= 0x7feb352du;
    h ^= h >> 15u;
    h *= 0x846ca68bu;
    return h ^ (h >> 16u);
}

public uint2 rt_mix2(uint2 h, uint v)
{
    return uint2(rt_mix(h.x, v), rt_mix(h.y ^ 0x5bd1e995u, v * 0x01000193u));
}

public uint rt_probe_start(uint hash, uint slots)
{
    return (hash & rt_config[RT_CFG_HASH_MASK]) & (slots - 1u);
}

// ---------------------------------------------------------------------------
// Declarations.
public uint2 rt_decl_hash(uint4 key)
{
    uint2 h = uint2(0x243f6a88u, 0x85a308d3u);
    h = rt_mix2(h, key.x);
    h = rt_mix2(h, key.y);
    h = rt_mix2(h, key.z);
    return rt_mix2(h, key.w);
}

// An unpublished record is a tombstone (namespace 0), so a rehash after
// growth never publishes a second record for one key.
void rt_decl_spare(uint record)
{
    rt_decl_key[record] = uint4(0u, 0u, 0u, 0u);
    InterlockedAdd(rt_counts[RT_C_SPARE + RT_A_DECLS], 1u);
}

void rt_param_spare(uint record)
{
    rt_param_key[record] = uint4(0u, 0u, 0u, 0u);
    InterlockedAdd(rt_counts[RT_C_SPARE + RT_A_PARAMS], 1u);
}

void rt_term_spare(uint record, uint arity)
{
    rt_term_head[record] = uint4(0u, 0u, 0u, 0u);
    InterlockedAdd(rt_counts[RT_C_SPARE + RT_A_TERMS], 1u);
    InterlockedAdd(rt_counts[RT_C_SPARE + RT_A_TERM_ARGS], arity);
}

public uint rt_intern_decl(uint4 key)
{
    uint slots; uint slot_stride; rt_decl_slot.GetDimensions(slots, slot_stride);
    uint slot = rt_probe_start(rt_decl_hash(key).x, slots);
    uint record = 0u;
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint value = rt_decl_slot[slot];
        if (value == 0u)
        {
            if (record == 0u)
            {
                record = rt_alloc(RT_A_DECLS, 1u);
                if (record == RT_INVALID) return RT_INVALID;
                rt_decl_key[record] = key;
                rt_decl_def[record] = 0u;
            }
            DeviceMemoryBarrier();
            InterlockedCompareExchange(rt_decl_slot[slot], 0u, record, value);
            if (value == 0u) return record;
        }
        DeviceMemoryBarrier();
        if (all(rt_decl_key[value] == key))
        {
            if (record != 0u) rt_decl_spare(record);
            return value;
        }
        slot = (slot + 1u) & (slots - 1u);
    }
    InterlockedOr(rt_counts[RT_C_OVERFLOW], RT_OVERFLOW_DECL_TABLE);
    if (record != 0u) rt_decl_spare(record);
    return RT_INVALID;
}

// Lookup without insertion: 0 when the key is absent.
public uint rt_find_decl(uint4 key)
{
    uint slots; uint slot_stride; rt_decl_slot.GetDimensions(slots, slot_stride);
    uint slot = rt_probe_start(rt_decl_hash(key).x, slots);
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint value = rt_decl_slot[slot];
        if (value == 0u) return 0u;
        DeviceMemoryBarrier();
        if (all(rt_decl_key[value] == key)) return value;
        slot = (slot + 1u) & (slots - 1u);
    }
    return 0u;
}

// ---------------------------------------------------------------------------
// Parameters. Identity is (owner, domain, ordinal); the declared scalar is
// immutable declaration metadata, not part of the key.
public uint2 rt_param_hash(uint3 key)
{
    uint2 h = rt_decl_hash(rt_decl_key[key.x]);
    h = rt_mix2(h, 0x70617261u ^ key.y);
    return rt_mix2(h, key.z);
}

public uint rt_intern_param(uint owner, uint domain, uint ordinal, uint scalar)
{
    uint3 key = uint3(owner, domain, ordinal);
    uint slots; uint slot_stride; rt_param_slot.GetDimensions(slots, slot_stride);
    uint slot = rt_probe_start(rt_param_hash(key).x, slots);
    uint record = 0u;
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint value = rt_param_slot[slot];
        if (value == 0u)
        {
            if (record == 0u)
            {
                record = rt_alloc(RT_A_PARAMS, 1u);
                if (record == RT_INVALID) return RT_INVALID;
                rt_param_key[record] = uint4(key, scalar);
            }
            DeviceMemoryBarrier();
            InterlockedCompareExchange(rt_param_slot[slot], 0u, record, value);
            if (value == 0u) return record;
        }
        DeviceMemoryBarrier();
        if (all(rt_param_key[value].xyz == key))
        {
            if (record != 0u) rt_param_spare(record);
            return value;
        }
        slot = (slot + 1u) & (slots - 1u);
    }
    InterlockedOr(rt_counts[RT_C_OVERFLOW], RT_OVERFLOW_PARAM_TABLE);
    if (record != 0u) rt_param_spare(record);
    return RT_INVALID;
}

// ---------------------------------------------------------------------------
// Term references.
public bool rt_is_term(uint ref) { return ref - 1u < RT_PARAM_BIT - 1u; }
public bool rt_is_stored_term(uint ref) { return ref >= RT_FIRST_TERM && ref < RT_PARAM_BIT; }
public bool rt_is_leaf(uint ref) { return ref - RT_PARAM_BIT < RT_FIT_FAILED - RT_PARAM_BIT; }
public bool rt_is_param_leaf(uint ref) { return rt_is_leaf(ref) && (ref & RT_SLOT_BIT) == 0u; }
public bool rt_is_slot_leaf(uint ref) { return rt_is_leaf(ref) && (ref & RT_SLOT_BIT) != 0u; }
public bool rt_is_resolved(uint ref) { return ref - 1u < RT_FIT_FAILED - 1u; }
public uint rt_leaf_param(uint ref) { return ref & RT_ID_MASK; }

public uint rt_param_leaf(uint param)
{
    if (param == RT_INVALID || param > RT_ID_MASK) return RT_UNKNOWN;
    return RT_PARAM_BIT | (rt_param_key[param].y == RT_DOMAIN_CONST ? RT_CONST_BIT : 0u) | param;
}

public uint rt_term_kind(uint ref)
{
    if (!rt_is_term(ref)) return 0u;
    return ref < RT_FIRST_TERM ? RT_KIND_SCALAR : rt_term_head[ref].x & 0xffu;
}

public uint rt_term_arity(uint ref)
{
    return rt_is_stored_term(ref) ? (rt_term_head[ref].x >> 8u) & 0xffu : 0u;
}

public uint3 rt_term_words(uint ref)
{
    if (!rt_is_term(ref)) return uint3(0u, 0u, 0u);
    return ref < RT_FIRST_TERM ? uint3(ref, 0u, 0u) : rt_term_head[ref].yzw;
}

public uint rt_term_arg(uint ref, uint index)
{
    if (!rt_is_stored_term(ref) || index >= rt_term_arity(ref)) return RT_NONE;
    return rt_term_args[rt_term_meta[ref].x + index];
}

public uint rt_term_flags(uint ref)
{
    if (rt_is_stored_term(ref)) return rt_term_meta[ref].y & 0xffffu;
    if (rt_is_slot_leaf(ref)) return RTF_SLOT;
    if (rt_is_leaf(ref)) return (ref & RT_CONST_BIT) != 0u ? RTF_CONST_PARAM : RTF_TYPE_PARAM;
    return 0u;
}

public bool rt_term_closed(uint ref)
{
    return rt_is_term(ref) && (rt_term_flags(ref) & (RTF_TYPE_PARAM | RTF_CONST_PARAM | RTF_SLOT)) == 0u;
}

public uint rt_term_height(uint ref)
{
    if (rt_is_stored_term(ref)) return rt_term_meta[ref].y >> 16u;
    return rt_is_term(ref) ? 1u : 0u;
}

public uint2 rt_term_owners(uint ref)
{
    if (rt_is_stored_term(ref)) return rt_term_owner[ref];
    if (rt_is_param_leaf(ref)) return uint2(rt_param_key[rt_leaf_param(ref)].x, 0u);
    return uint2(0u, 0u);
}

// Union of two owner summaries, keeping at most two distinct owners.
public uint2 rt_owner_union(uint2 a, uint2 b)
{
    if (a.y == RT_OWNERS_MANY || b.y == RT_OWNERS_MANY) return uint2(a.x, RT_OWNERS_MANY);
    uint2 out = a;
    for (uint i = 0u; i < 2u; i++)
    {
        uint owner = i == 0u ? b.x : b.y;
        if (owner == 0u || owner == out.x || owner == out.y) continue;
        if (out.x == 0u) out.x = owner;
        else if (out.y == 0u) out.y = owner;
        else return uint2(out.x, RT_OWNERS_MANY);
    }
    return out;
}

// Structural hash of a reference: never an ID, so it is stable across jobs.
public uint2 rt_ref_hash(uint ref)
{
    if (rt_is_stored_term(ref)) return rt_term_meta[ref].zw;
    if (rt_is_param_leaf(ref))
    {
        uint4 param = rt_param_key[rt_leaf_param(ref)];
        return rt_param_hash(param.xyz);
    }
    return rt_mix2(uint2(0x13198a2eu, 0x03707344u), ref);
}

// The arguments of a term key being interned. Implementations read them
// from wherever the producer staged them; rt_intern_term copies them into
// rt_term_args only when the key is new.
public interface IRtArgs
{
    uint arg(uint index);
}

public struct RtStoredArgs : IRtArgs
{
    public uint base;
    public uint arg(uint index) { return rt_term_args[base + index]; }
}

public struct RtTermKey
{
    public uint head;      // kind | arity << 8 | type_slots << 16
    public uint3 words;
    public uint flags;
    public uint height;
    public uint2 hash;
    public uint2 owners;
    public bool ok;
}

public RtTermKey rt_key_begin(uint kind, uint arity, uint type_slots, uint3 words)
{
    RtTermKey key;
    key.head = kind | (arity << 8u) | (type_slots << 16u);
    key.words = words;
    key.flags = 0u;
    key.height = 1u;
    key.hash = rt_mix2(uint2(0xa4093822u, 0x299f31d0u), key.head);
    // A NAMED term hashes its declaration's key and an ENV term its owner's,
    // never their IDs.
    if (kind == RT_KIND_NAMED || (kind == RT_KIND_ENV && words.x != 0u))
    {
        uint2 decl = rt_decl_hash(rt_decl_key[words.x]);
        key.hash = rt_mix2(rt_mix2(key.hash, decl.x), decl.y);
        key.hash = rt_mix2(rt_mix2(key.hash, words.y), words.z);
    }
    else
    {
        key.hash = rt_mix2(rt_mix2(rt_mix2(key.hash, words.x), words.y), words.z);
    }
    key.owners = uint2(0u, 0u);
    key.ok = arity <= 64u;
    return key;
}

public void rt_key_fold(inout RtTermKey key, uint child)
{
    if (!rt_is_resolved(child)) { key.ok = false; return; }
    key.flags |= rt_term_flags(child);
    key.height = max(key.height, rt_term_height(child) + 1u);
    uint2 h = rt_ref_hash(child);
    key.hash = rt_mix2(rt_mix2(key.hash, h.x), h.y);
    key.owners = rt_owner_union(key.owners, rt_term_owners(child));
}

bool rt_term_matches<A : IRtArgs>(uint id, RtTermKey key, A args)
{
    uint4 head = rt_term_head[id];
    if (head.x != key.head || any(head.yzw != key.words)) return false;
    uint arity = (key.head >> 8u) & 0xffu;
    uint base = rt_term_meta[id].x;
    for (uint i = 0u; i < arity; i++)
        if (rt_term_args[base + i] != args.arg(i)) return false;
    return true;
}

// Intern a complete key. Only a key the table lacks takes a record and
// argument words; a lane that loses the slot to an equal key keeps them as
// a counted spare.
public uint rt_intern_term<A : IRtArgs>(RtTermKey key, A args)
{
    if (!key.ok) return RT_UNKNOWN;
    uint kind = key.head & 0xffu;
    if (kind == RT_KIND_SCALAR) return key.words.x >= 1u && key.words.x < RT_FIRST_TERM ? key.words.x : RT_UNKNOWN;
    uint arity = (key.head >> 8u) & 0xffu;
    uint slots; uint slot_stride; rt_term_slot.GetDimensions(slots, slot_stride);
    uint slot = rt_probe_start(key.hash.x, slots);
    uint record = 0u;
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint value = rt_term_slot[slot];
        if (value == 0u)
        {
            if (record == 0u)
            {
                uint base = arity == 0u ? 0u : rt_alloc(RT_A_TERM_ARGS, arity);
                if (base == RT_INVALID) return RT_UNKNOWN;
                record = rt_alloc(RT_A_TERMS, 1u);
                if (record == RT_INVALID)
                {
                    InterlockedAdd(rt_counts[RT_C_SPARE + RT_A_TERM_ARGS], arity);
                    return RT_UNKNOWN;
                }
                if (record > RT_ID_MASK)
                {
                    rt_overflow(RT_A_TERMS, record + 1u);
                    InterlockedAdd(rt_counts[RT_C_SPARE + RT_A_TERM_ARGS], arity);
                    return RT_UNKNOWN;
                }
                for (uint i = 0u; i < arity; i++) rt_term_args[base + i] = args.arg(i);
                rt_term_head[record] = uint4(key.head, key.words);
                rt_term_meta[record] = uint4(base, key.flags | (min(key.height, 0xffffu) << 16u), key.hash);
                rt_term_owner[record] = key.owners;
            }
            DeviceMemoryBarrier();
            InterlockedCompareExchange(rt_term_slot[slot], 0u, record, value);
            if (value == 0u) return record;
        }
        DeviceMemoryBarrier();
        if (rt_term_matches(value, key, args))
        {
            if (record != 0u) rt_term_spare(record, arity);
            return value;
        }
        slot = (slot + 1u) & (slots - 1u);
    }
    InterlockedOr(rt_counts[RT_C_OVERFLOW], RT_OVERFLOW_TERM_TABLE);
    if (record != 0u) rt_term_spare(record, arity);
    return RT_UNKNOWN;
}
