// Dependency signature types (checked tag 5) interned while their page is
// resident (docs/canonical-type-ids.md, "Dependency pages"). Node t of the
// page owns the job-wide index span + t (dependency_constant_type_span_base)
// and, like a candidate, no record (ct_intern_key). Nodes mirror checked
// rows (the interface exports rows node by node, in the rows' operand
// order), so an imported row and the signature node it was exported from
// share one key: kinds 3..6 are named, array, slice and reference; 9 and 10
// are constant values and count projections; 2 and 8 are the declaration's
// parameter slots (ct_dep_type_param, ct_dep_const_param).
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_constants;
import dependency_interface;
import constant_value;
import primitive_types;

// Alias roots of the resident page (dependencies/09, 10): a type alias node
// points at its signature node, every other node at itself.
public StructuredBuffer<uint> canonical_type_roots;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_WORDS = 9u;
static const uint NOMINAL_LIMIT = 32u;

// Job-wide index of node `t` of the resident page, or INVALID.
public uint ct_dependency_index(uint t)
{
    uint base = dependency_constant_type_span_base();
    uint capacity = ct_dependency_capacity();
    return t < dependency_type_count() && base <= capacity && t < capacity - base ? base + t : INVALID;
}

public uint ct_dependency_state(uint t)
{
    uint index = ct_dependency_index(t);
    return index != INVALID ? canonical_dependency_type[index] : CT_UNKNOWN;
}

uint alias_root(uint t)
{
    uint roots; uint stride;
    canonical_type_roots.GetDimensions(roots, stride);
    return t < roots ? canonical_type_roots[t] : INVALID;
}

// The reference a parent reads for child node `t`: an alias is its signature.
uint node_ref(uint t)
{
    return ct_dependency_state(alias_root(t));
}

// Named, array, slice and reference nodes. Pass 0 checks readiness, pass 1
// writes the key, both reading the children at one call site.
uint build_composite(uint t, uint kind, bool final, out CtKey key)
{
    key = ct_empty_key();
    // Function types (7) have no checked row form, hence no identity.
    if (kind < 3u || kind > 6u) return CT_UNKNOWN;
    uint base = t * TYPE_WORDS;
    uint arity = dependency_type_word(base + 4u);
    uint edge = dependency_type_word(base + 3u);
    uint edges = dependency_count(5u);
    if (kind == 3u ? arity > NOMINAL_LIMIT : arity != (kind == 4u ? 2u : 1u)) return CT_UNKNOWN;
    if (arity != 0u && (edge > edges || arity > edges - edge)) return CT_UNKNOWN;
    // An array's length is its explicit integer length node.
    if (kind == 4u && dependency_array_length_type(t) == INVALID) return CT_UNKNOWN;
    uint3 words = uint3(0u, 0u, 0u);
    if (kind == 3u)
    {
        // (library, unit, persisted declaration index), the imported rows'
        // triple. The job's own declarations are spelled with their tokens
        // (canonical_candidates.slang), and no interface names them.
        words = uint3(dependency_type_word(base + 1u), dependency_type_word(base + 8u),
            dependency_type_word(base + 2u));
        if (words.x == ct_counts[CT_COUNT_LIBRARY] && words.y == ct_counts[CT_COUNT_UNIT])
            return CT_UNKNOWN;
    }
    uint ct = kind == 3u ? CT_KIND_NAMED : kind == 4u ? CT_KIND_ARRAY : kind == 5u ? CT_KIND_SLICE : CT_KIND_REF;
    uint mask = 0u;
    for (uint pass = 0u; pass < 2u; pass++)
    {
        if (pass == 1u)
        {
            // Acquire: children's records were published before their references.
            DeviceMemoryBarrier();
            key = ct_key_begin(ct, arity, kind == 3u ? arity - countbits(mask) : 0u, words);
            if (!ct_key_reserve_args(key)) return CT_UNKNOWN;
        }
        for (uint index = 0u; index < arity; index++)
        {
            uint child_node = dependency_type_edge_word(edge + index);
            bool below = child_node < t;
            uint child_kind = below ? dependency_type_word(child_node * TYPE_WORDS) : 0u;
            uint child = below ? node_ref(child_node) : CT_UNKNOWN;
            if (pass == 0u)
            {
                if (child == CT_PENDING) return final ? CT_UNKNOWN : CT_PENDING;
                if (!ct_is_resolved(child)) return CT_UNKNOWN;
                // Constants are named operands and array lengths only.
                bool constant = child_kind >= 8u && child_kind <= 10u;
                if (kind != 3u && constant != (kind == 4u && index == 1u)) return CT_UNKNOWN;
                if (constant) mask |= 1u << index;
                continue;
            }
            // Array identity uses the length's count class, not its typed value.
            if (kind == 4u && index == 1u) child = cc_count_class(child);
            ct_key_arg(key, index, child);
        }
    }
    if (!key.ok) return CT_UNKNOWN;
    key.extra = uint2(INVALID, mask);
    return CT_KEY_BUILT;
}

uint build_dependency(uint t, bool final, out CtKey key)
{
    key = ct_empty_key();
    uint root = alias_root(t);
    if (root != t)
    {
        // A type alias is its signature's node.
        uint state = ct_dependency_state(root);
        return state == CT_PENDING && final ? CT_UNKNOWN : state;
    }
    uint kind = dependency_type_word(t * TYPE_WORDS);
    if (kind == 1u)
    {
        uint scalar = dependency_type_word(t * TYPE_WORDS + 1u);
        return scalar >= 1u && scalar <= SCALAR_USIZE ? scalar : CT_UNKNOWN;
    }
    if (kind == 2u) return ct_dep_type_param(dependency_generic_type_slot(t));
    if (kind == 8u)
        return constant_scalar_is_supported(dependency_const_parameter_scalar(t))
            ? ct_dep_const_param(dependency_generic_const_slot(t), dependency_const_parameter_scalar(t))
            : CT_UNKNOWN;
    bool fold = false;
    uint3 value = uint3(0u, 0u, 0u);
    if (kind == 9u)
    {
        if (!dependency_literal_constant_value(t, value)) return CT_UNKNOWN;
        fold = true;
    }
    else if (kind == 10u)
    {
        uint target; uint child_node;
        if (!dependency_count_projection_child(t, target, child_node)) return CT_UNKNOWN;
        uint child = node_ref(child_node);
        if (child == CT_PENDING) return final ? CT_UNKNOWN : CT_PENDING;
        if (!ct_is_resolved(child)) return CT_UNKNOWN;
        uint status = ct_build_projection(target, child, dependency_constant_scalar(child_node),
            fold, value, key);
        if (!fold) return status;
    }
    if (fold) return ct_build_value(value, key);
    return build_composite(t, kind, final, key);
}

// Intern node `t` of the resident page; CT_PENDING means a child is not
// interned yet.
public uint canonical_intern_dependency(uint t, bool final)
{
    uint index = ct_dependency_index(t);
    if (index == INVALID) return CT_UNKNOWN;
    CtKey key;
    uint status = build_dependency(t, final, key);
    if (status != CT_KEY_BUILT) return status;
    return ct_intern_key(key);
}
