// Trait-fact probe for program retention: reads only the build store.
//
// One lane per directory entry. The lane validates the entry's trait facts
// (rt_dir_trait, rt_traits) against the store's own identities:
//   predicates: exact owner, ordinal, subject owned by the entry's binder
//     map, trait term NAMED over the record's trait DeclId, that trait
//     committed as a TRAIT with as many explicit parameters as arguments,
//     every argument leaf inside the owner's chain;
//   bindings: exact impl owner, ordinal, the required member committed as a
//     REQUIRED_MEMBER of the impl's trait (the trait term's DeclId), the
//     method committed as a METHOD of this impl whose binder map starts with
//     the impl's, distinct required members, and one binding per required
//     member of the trait.
// It selects no implementation. Output: TRAIT_PROBE_WORDS words per entry.
import type_checker.retention.retention_store;

RWStructuredBuffer<uint> rt_test_out;

static const uint TRAIT_PROBE_WORDS = 16u;
static const uint DECL_TRAIT = 8u;
static const uint DECL_METHOD = 2u;
static const uint DECL_REQUIRED_MEMBER = 3u;
static const uint DECL_IMPL = 7u;

static const uint T_DECL = 0u;
static const uint T_KIND = 1u;
static const uint T_PREDICATES = 2u;
static const uint T_PREDICATES_BAD = 3u;
static const uint T_BINDINGS = 4u;
static const uint T_BINDINGS_BAD = 5u;
static const uint T_FAILED = 6u;        // bit per failed check
static const uint T_DIR_FLAGS = 7u;     // d3.w | committed state << 8
static const uint T_IMPL_TRAIT = 8u;    // a trait impl's trait DeclId
static const uint T_REQUIRED = 9u;      // required members of that trait (directory count)
static const uint T_RECEIVERS = 10u;    // bit per receiver mode bound
static const uint T_PARAM_SUBJECTS = 11u;
static const uint T_SCALAR_SUBJECTS = 12u;

uint dir_entry(uint decl)
{
    uint def = decl != 0u && decl < rt_counts[RT_A_DECLS] ? rt_decl_def[decl] : 0u;
    return def != 0u && def - 1u < rt_counts[RT_A_DIR] ? def - 1u : RT_INVALID;
}

uint4 dir_word(uint entry, uint word) { return rt_dir[entry * RT_DIR_WORDS + word]; }

bool committed(uint entry)
{
    return entry != RT_INVALID && dir_word(entry, 0u).w == RT_DIR_COMMITTED;
}

bool in_binders(uint entry, uint param)
{
    uint4 d1 = dir_word(entry, 1u);
    uint n = (d1.y & 0xffffu) + (d1.y >> 16u);
    for (uint i = 0u; i < n && i < 64u; i++)
        if (rt_binders[d1.x + i] == param) return true;
    return false;
}

// Every parameter leaf of `ref` belongs to the binder chain (decl, parent).
bool chain_owned(uint ref, uint decl, uint parent)
{
    if (!rt_is_resolved(ref)) return false;
    if ((rt_term_flags(ref) & RTF_SLOT) != 0u) return false;
    uint2 owners = rt_term_owners(ref);
    if (owners.y == RT_OWNERS_MANY) return false;
    bool a = owners.x == 0u || owners.x == decl || (parent != 0u && owners.x == parent);
    bool b = owners.y == 0u || owners.y == decl || (parent != 0u && owners.y == parent);
    return a && b;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint entry = dtid.x;
    uint entries = rt_counts[RT_A_DIR];
    if (entry >= entries) return;
    uint base = entry * TRAIT_PROBE_WORDS;
    for (uint i = 0u; i < TRAIT_PROBE_WORDS; i++) rt_test_out[base + i] = 0u;
    uint4 d0 = dir_word(entry, 0u);
    uint4 d1 = dir_word(entry, 1u);
    uint4 d3 = dir_word(entry, 3u);
    uint decl = d0.x;
    uint parent = d0.z;
    uint4 facts = rt_dir_trait[entry];
    uint records = rt_counts[RT_A_TRAITS];
    uint failed = 0u;
    rt_test_out[base + T_DECL] = decl;
    rt_test_out[base + T_KIND] = d0.y;
    rt_test_out[base + T_DIR_FLAGS] = d3.w | (d0.w << 8u);
    if (facts.y > records || facts.x > records - facts.y) failed |= 1u << 15u;
    if (facts.w > records || facts.z > records - facts.w) failed |= 1u << 15u;
    if (failed != 0u) { rt_test_out[base + T_FAILED] = failed; return; }

    uint bad = 0u;
    uint params = 0u;
    uint scalars = 0u;
    for (uint p = 0u; p < facts.y; p++)
    {
        uint r = facts.x + p;
        uint4 t0 = rt_traits[r * RT_TRAIT_WORDS];
        uint4 t1 = rt_traits[r * RT_TRAIT_WORDS + 1u];
        uint f = 0u;
        if (t0.x != decl) f |= 1u << 0u;
        if ((t0.y & 0xffu) != RT_TRAIT_PREDICATE || (t0.y >> 8u) != p) f |= 1u << 1u;
        uint subject = t0.z;
        if (rt_is_param_leaf(subject))
        {
            uint param = rt_leaf_param(subject);
            uint owner = rt_param_key[param].x;
            if ((owner != decl && owner != parent) || rt_param_key[param].y != RT_DOMAIN_TYPE ||
                !in_binders(entry, param)) f |= 1u << 2u;
            params++;
        }
        else if (subject >= 1u && subject < RT_FIRST_TERM) scalars++;
        else f |= 1u << 2u;
        uint term = t0.w;
        if (!rt_is_stored_term(term) || rt_term_kind(term) != RT_KIND_NAMED || rt_term_head[term].y != t1.x)
            f |= 1u << 3u;
        uint trait_entry = dir_entry(t1.x);
        if (!committed(trait_entry) || dir_word(trait_entry, 0u).y != DECL_TRAIT) f |= 1u << 4u;
        else
        {
            uint4 td1 = dir_word(trait_entry, 1u);
            uint explicit = (td1.y & 0xffffu) - 1u + (td1.y >> 16u); // the type domain ends with Self
            if (rt_term_arity(term) != explicit) f |= 1u << 4u;
        }
        if (!chain_owned(term, decl, parent)) f |= 1u << 5u;
        if (t1.z == RT_INVALID || t1.w == 0u) f |= 1u << 6u;
        if (f != 0u) bad++;
        failed |= f;
    }

    uint bindings_bad = 0u;
    uint receivers = 0u;
    uint impl_trait = 0u;
    uint required_total = 0u;
    if (d0.y == DECL_IMPL && d1.z != RT_INVALID && rt_is_stored_term(rt_sigs[d1.z + 1u]))
    {
        impl_trait = rt_term_head[rt_sigs[d1.z + 1u]].y;
        for (uint other = 0u; other < entries; other++)
        {
            uint4 o0 = dir_word(other, 0u);
            if (o0.w == RT_DIR_COMMITTED && o0.y == DECL_REQUIRED_MEMBER && o0.z == impl_trait) required_total++;
        }
        if (required_total != facts.w) failed |= 1u << 13u;
    }
    else if (facts.w != 0u) failed |= 1u << 13u;
    for (uint b = 0u; b < facts.w; b++)
    {
        uint r = facts.z + b;
        uint4 t0 = rt_traits[r * RT_TRAIT_WORDS];
        uint4 t1 = rt_traits[r * RT_TRAIT_WORDS + 1u];
        uint f = 0u;
        if (t0.x != decl || (t0.y & 0xffu) != RT_TRAIT_BINDING || (t0.y >> 16u) != b) f |= 1u << 8u;
        uint required_entry = dir_entry(t0.z);
        if (!committed(required_entry) || dir_word(required_entry, 0u).y != DECL_REQUIRED_MEMBER ||
            dir_word(required_entry, 0u).z != impl_trait || t1.x != impl_trait) f |= 1u << 9u;
        uint method_entry = dir_entry(t0.w);
        if (!committed(method_entry) || dir_word(method_entry, 0u).y != DECL_METHOD ||
            dir_word(method_entry, 0u).z != decl) f |= 1u << 10u;
        else
        {
            // The method's binder map composes the impl's parameters first.
            uint4 m1 = dir_word(method_entry, 1u);
            uint types = d1.y & 0xffffu;
            uint consts = d1.y >> 16u;
            if ((m1.y & 0xffffu) < types || (m1.y >> 16u) < consts) f |= 1u << 14u;
            else
            {
                for (uint i = 0u; i < types; i++)
                    if (rt_binders[m1.x + i] != rt_binders[d1.x + i]) f |= 1u << 14u;
                for (uint i = 0u; i < consts; i++)
                    if (rt_binders[m1.x + (m1.y & 0xffffu) + i] != rt_binders[d1.x + types + i]) f |= 1u << 14u;
            }
        }
        uint receiver = (t0.y >> 8u) & 0xffu;
        if (receiver > 3u) f |= 1u << 11u;
        else receivers |= 1u << receiver;
        for (uint other = 0u; other < b; other++)
            if (rt_traits[(facts.z + other) * RT_TRAIT_WORDS].z == t0.z) f |= 1u << 12u;
        if (f != 0u) bindings_bad++;
        failed |= f;
    }
    rt_test_out[base + T_PREDICATES] = facts.y;
    rt_test_out[base + T_PREDICATES_BAD] = bad;
    rt_test_out[base + T_BINDINGS] = facts.w;
    rt_test_out[base + T_BINDINGS_BAD] = bindings_bad;
    rt_test_out[base + T_FAILED] = failed;
    rt_test_out[base + T_IMPL_TRAIT] = impl_trait;
    rt_test_out[base + T_REQUIRED] = required_total;
    rt_test_out[base + T_RECEIVERS] = receivers;
    rt_test_out[base + T_PARAM_SUBJECTS] = params;
    rt_test_out[base + T_SCALAR_SUBJECTS] = scalars;
}
