// Hash-consed canonical type identities. See docs/canonical-type-ids.md.
//
// Every distinct checked type receives one canonical ID whose record stores
// canonical child IDs, so identity is integer equality and hashing reads
// O(arity) words. Candidates are checked instance rows [0, R) followed by
// constant atoms [R, R + A). Interning runs in rounds; each round proposes
// every ready candidate, claims hash slots, publishes new records and
// resolves duplicates, one dispatch each. No invocation ever waits on another.
import type_checker.checked_type_graph;
import type_checker.constant_atoms;
import type_checker.concrete_type_equality;
import constant_value;
import primitive_types;

// Canonical references are CT IDs, or parameter tokens tagged with the high
// bit. Scalar codes 1..17 are preseeded CT IDs.
public static const uint CANON_PARAM_BIT = 0x80000000u;
public static const uint CANON_PENDING = 0xffffffffu;
public static const uint CANON_UNKNOWN = 0xfffffffeu;
public static const uint CANON_NONE = 0xfffffffdu;
public static const uint CANON_FIRST_DYNAMIC = 32u;
public static const uint CANON_MAX_ARITY = 32u;

public static const uint CT_SCALAR = 1u;
public static const uint CT_NAMED = 2u;
public static const uint CT_ARRAY = 3u;
public static const uint CT_SLICE = 4u;
public static const uint CT_REF = 5u;
public static const uint CT_CONST = 6u;

// Array length forms stored in key aux1.
public static const uint CT_LENGTH_COUNT = 0u;
public static const uint CT_LENGTH_PARAM = 1u;

public static const uint CAND_IDLE = 0u;
public static const uint CAND_PROPOSED = 1u;
public static const uint CAND_OWNER = 2u;
public static const uint CAND_MATCHED = 3u;
public static const uint CAND_DONE = 4u;
public static const uint SLOT_CANDIDATE_BIT = 0x80000000u;

// Per-candidate state. Keys are (kind, head, aux0, aux1) and
// (aux2, arity, arg_base, hash); arguments live in canonical_cand_args.
public RWStructuredBuffer<uint> canonical_row;
public RWStructuredBuffer<uint> canonical_atom;
public RWStructuredBuffer<uint> canonical_cand_state;
public RWStructuredBuffer<uint4> canonical_cand_key_a;
public RWStructuredBuffer<uint4> canonical_cand_key_b;
public RWStructuredBuffer<uint> canonical_cand_args;
public RWStructuredBuffer<uint> canonical_cand_slot;
public RWStructuredBuffer<uint> canonical_cand_winner;
// Published records use the candidate key layout; arg_base indexes ct_args.
public RWStructuredBuffer<uint4> canonical_ct_key_a;
public RWStructuredBuffer<uint4> canonical_ct_key_b;
public RWStructuredBuffer<uint> canonical_ct_args;
public RWStructuredBuffer<uint> canonical_ct_rep;
public RWStructuredBuffer<uint> canonical_ct_slot;
// [0] next CT ID, [1] next ct arg word, [2] next candidate arg word,
// [3] overflow flags (1 table, 2 records, 4 args).
public RWStructuredBuffer<uint> canonical_counts;

public uint canonical_row_capacity()
{
    uint count; uint stride;
    canonical_row.GetDimensions(count, stride);
    return min(count, checked_type_capacity());
}

public uint canonical_atom_capacity()
{
    uint count; uint stride;
    canonical_atom.GetDimensions(count, stride);
    uint atoms; checked_constant_atoms.GetDimensions(atoms, stride);
    return min(count, atoms);
}

public uint canonical_candidate_capacity()
{
    return canonical_row_capacity() + canonical_atom_capacity();
}

public uint canonical_record_capacity()
{
    uint count; uint stride;
    canonical_ct_key_a.GetDimensions(count, stride);
    return count;
}

public uint canonical_slot_capacity()
{
    uint count; uint stride;
    canonical_ct_slot.GetDimensions(count, stride);
    return count;
}

public uint canonical_of_candidate(uint candidate)
{
    uint rows = canonical_row_capacity();
    if (candidate < rows) return canonical_row[candidate];
    return candidate - rows < canonical_atom_capacity()
        ? canonical_atom[candidate - rows] : CANON_UNKNOWN;
}

public void set_canonical_of_candidate(uint candidate, uint id)
{
    uint rows = canonical_row_capacity();
    if (candidate < rows) canonical_row[candidate] = id;
    else if (candidate - rows < canonical_atom_capacity()) canonical_atom[candidate - rows] = id;
}

public bool canonical_is_resolved(uint id)
{
    return id != CANON_PENDING && id != CANON_UNKNOWN && id != CANON_NONE;
}

// Canonical reference of one checked (tag, payload) operand. PENDING means a
// child is not interned yet; UNKNOWN marks shapes this layer does not cover,
// whose consumers keep the previous graph comparison.
public uint canonical_ref(uint tag, uint payload)
{
    static const uint INVALID = 0xffffffffu;
    if (payload == INVALID) return CANON_UNKNOWN;
    uint rows = canonical_row_capacity();
    if (tag == 1u)
    {
        if (payload >= 1u && payload <= SCALAR_USIZE) return payload;
        // Monomorphic nominal values keep legacy scalar-coded references;
        // they name the declaration's own zero-argument application row.
        if (payload >= 4096u && payload < 6144u)
            return payload - 4096u < rows ? canonical_row[payload - 4096u] : CANON_UNKNOWN;
        if (payload >= 6144u && payload < 8192u)
            return payload - 6144u < rows ? canonical_row[payload - 6144u] : CANON_UNKNOWN;
        return CANON_UNKNOWN;
    }
    if (tag == 2u) return payload < CANON_PARAM_BIT ? (CANON_PARAM_BIT | payload) : CANON_UNKNOWN;
    if (tag == 3u) return payload < rows ? canonical_row[payload] : CANON_UNKNOWN;
    if (tag == (APPLICATION_CONSTANT_ARGUMENT | 1u))
        return payload < canonical_atom_capacity() ? canonical_atom[payload] : CANON_UNKNOWN;
    if (tag == (APPLICATION_CONSTANT_ARGUMENT | 2u))
        return payload < CANON_PARAM_BIT ? (CANON_PARAM_BIT | payload) : CANON_UNKNOWN;
    return CANON_UNKNOWN;
}

public uint canonical_hash_mix(uint hash, uint value)
{
    hash = (hash ^ value) * 16777619u;
    return hash ^ (hash >> 15u);
}

public uint canonical_key_hash(uint4 a, uint aux2, uint arity)
{
    uint hash = 2166136261u;
    hash = canonical_hash_mix(hash, a.x);
    hash = canonical_hash_mix(hash, a.y);
    hash = canonical_hash_mix(hash, a.z);
    hash = canonical_hash_mix(hash, a.w);
    hash = canonical_hash_mix(hash, aux2);
    return canonical_hash_mix(hash, arity);
}

// Keys compare by every word; arguments are already canonical.
public bool canonical_candidate_matches_candidate(uint left, uint right)
{
    uint4 la = canonical_cand_key_a[left]; uint4 lb = canonical_cand_key_b[left];
    uint4 ra = canonical_cand_key_a[right]; uint4 rb = canonical_cand_key_b[right];
    if (any(la != ra) || lb.x != rb.x || lb.y != rb.y || lb.w != rb.w) return false;
    for (uint i = 0u; i < lb.y; i++)
        if (canonical_cand_args[lb.z + i] != canonical_cand_args[rb.z + i]) return false;
    return true;
}

public bool canonical_candidate_matches_record(uint candidate, uint id)
{
    if (id >= canonical_record_capacity()) return false;
    uint4 la = canonical_cand_key_a[candidate]; uint4 lb = canonical_cand_key_b[candidate];
    uint4 ra = canonical_ct_key_a[id]; uint4 rb = canonical_ct_key_b[id];
    if (any(la != ra) || lb.x != rb.x || lb.y != rb.y || lb.w != rb.w) return false;
    for (uint i = 0u; i < lb.y; i++)
        if (canonical_cand_args[lb.z + i] != canonical_ct_args[rb.z + i]) return false;
    return true;
}
