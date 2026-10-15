// Interning candidates of a type-check job: checked instance rows, constant
// atoms and constant projections, each with a fixed record slot. A candidate
// is interned once all of its children have canonical references; one
// candidate is a few dozen loads and one ct_intern, with no local arrays.
// A re-interned job (CT_COUNT_REINTERN) looks each key up first and moves a
// rewritten candidate whose fixed record is published to a dynamic record.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_constants;
import type_checker.checked_type_graph;
import type_checker.constant_atoms;
import type_checker.constant_parameter_slots;
import constant_value;
import primitive_types;

// Stable nominal identity: local declarations use the job's (library, unit)
// and their persisted interface index (or CT_PRIVATE_LOCAL_BIT | decl id), so
// a declaration reached locally and through an import shares one key.
public StructuredBuffer<uint> decl_id_by_name_token;
public StructuredBuffer<uint> decl_name_token;
public StructuredBuffer<uint> interface_public_decl_index_by_local;
public StructuredBuffer<uint> interface_public_decl_local_id;

static const uint INVALID = 0xffffffffu;
static const uint NOMINAL_LIMIT = 32u;

uint token_capacity()
{
    uint count; uint stride;
    type_generic_param_slot_by_token.GetDimensions(count, stride);
    return count;
}

uint declaration_capacity()
{
    uint count; uint stride;
    interface_public_decl_index_by_local.GetDimensions(count, stride);
    return count;
}

// Constant parameters must name a supported declared scalar in a valid slot,
// matching the scoped graph's parameter admission.
uint constant_parameter(uint token, bool count)
{
    if (token >= token_capacity() || type_const_param_slot_by_token[token] >= 32u) return CT_UNKNOWN;
    uint scalar = checked_constant_parameter_scalar(token);
    if (!constant_scalar_is_supported(scalar) || (count && !scalar_is_integer(scalar))) return CT_UNKNOWN;
    return ct_const_param(token);
}

// Canonical reference of one checked operand, with parameter admission. A
// `count` operand (an array length) must be an integer parameter.
uint operand(uint tag, uint payload, bool count)
{
    if (tag == 2u)
        return payload < token_capacity() && type_generic_param_slot_by_token[payload] != INVALID
            ? ct_type_param(payload) : CT_UNKNOWN;
    if (tag == (CT_CONSTANT_TAG_BIT | 2u)) return constant_parameter(payload, count);
    return ct_ref(tag, payload);
}

bool named_identity(uint row, out uint3 words, out uint token)
{
    uint declaration = type_instance_decl_token[row];
    uint library = ct_counts[CT_COUNT_LIBRARY];
    uint unit = ct_counts[CT_COUNT_UNIT];
    words = uint3(0u, 0u, 0u);
    token = INVALID;
    if (declaration != INVALID)
    {
        if (declaration >= token_capacity()) return false;
        uint local = decl_id_by_name_token[declaration];
        if (local >= declaration_capacity()) return false;
        uint persisted = interface_public_decl_index_by_local[local];
        words = uint3(library, unit, persisted != INVALID ? persisted : CT_PRIVATE_LOCAL_BIT | local);
        token = declaration;
        return true;
    }
    words = uint3(external_type_library_id[row], external_type_unit_id[row], external_type_local_index[row]);
    if (any(words == INVALID)) return false;
    // An imported reference to this job's own declaration keeps the same
    // bridge token as its local spelling, so the published facts do not
    // depend on which lane wins.
    if (words.x == library && words.y == unit && words.z < declaration_capacity())
    {
        uint local = interface_public_decl_local_id[words.z];
        if (local < declaration_capacity()) token = decl_name_token[local];
    }
    return true;
}

// Child `index` of a row before count-class mapping. Arrays: element, length.
// `constant` reports a constant-domain operand of a named application.
uint row_child(uint row, uint kind, uint index, out bool constant)
{
    uint tag = type_instance_elem_ref_tag[row];
    uint payload = type_instance_elem_ref_payload[row];
    bool length = kind == 2u && index == 1u;
    if (kind == 1u && !ScopedCheckedTypeGraph.argument(row, index, tag, payload)) tag = 0u;
    if (length)
    {
        tag = CT_CONSTANT_TAG_BIT | type_instance_len_kind[row];
        payload = type_instance_len_payload[row];
    }
    constant = kind == 1u && (tag & CT_CONSTANT_TAG_BIT) != 0u;
    return operand(tag, payload, length);
}

// A builder builds a candidate's complete key and returns CT_KEY_BUILT, or
// returns the candidate's final reference (a sentinel) without a key. One
// ct_intern call then publishes whichever key was built.
uint build_row(uint row, bool final, out CtKey key)
{
    key = ct_empty_key();
    uint kind = type_instance_kind[row];
    if (kind == 0u) return CT_NONE;
    if (kind > 4u) return CT_UNKNOWN;
    uint arity = kind == 1u ? type_instance_arg_count[row] : kind == 2u ? 2u : 1u;
    if (arity > NOMINAL_LIMIT) return CT_UNKNOWN;
    uint3 words = uint3(0u, 0u, 0u);
    uint token = INVALID;
    if (kind == 1u && !named_identity(row, words, token)) return CT_UNKNOWN;
    // Pass 0 checks readiness, so nothing is reserved for a row that must
    // wait; pass 1 writes the key. Published references never change, so
    // both passes read the same children (at one call site).
    uint mask = 0u;
    uint ct = kind == 1u ? CT_KIND_NAMED : kind == 2u ? CT_KIND_ARRAY : kind == 3u ? CT_KIND_SLICE : CT_KIND_REF;
    for (uint pass = 0u; pass < 2u; pass++)
    {
        if (pass == 1u)
        {
            // Acquire: children's records were published before their references.
            DeviceMemoryBarrier();
            key = ct_key_begin(ct, arity, kind == 1u ? arity - countbits(mask) : 0u, words);
            if (!ct_key_reserve_args(key)) return CT_UNKNOWN;
        }
        for (uint index = 0u; index < arity; index++)
        {
            bool constant;
            uint child = row_child(row, kind, index, constant);
            if (pass == 0u)
            {
                if (child == CT_PENDING) return final ? CT_UNKNOWN : CT_PENDING;
                if (!ct_is_resolved(child)) return CT_UNKNOWN;
                if (constant) mask |= 1u << index;
                continue;
            }
            // Array identity uses the length's count class, not its typed value.
            if (kind == 2u && index == 1u) child = cc_count_class(child);
            ct_key_arg(key, index, child);
        }
    }
    key.extra = uint2(token, mask);
    return key.ok ? CT_KEY_BUILT : CT_UNKNOWN;
}

// Atoms intern their typed value; projections fold or cast
// (canonical_constants.slang). Both end at the one value-key site.
uint build_constant(uint candidate, bool final, out CtKey key)
{
    key = ct_empty_key();
    uint atom = candidate - ct_row_capacity();
    uint3 value;
    if (atom < ct_atom_capacity())
    {
        if (!checked_constant_atom_value(atom, value)) return CT_NONE;
    }
    else
    {
        uint target; uint2 child_ref;
        if (!checked_constant_projection(atom - ct_atom_capacity(), target, child_ref)) return CT_NONE;
        uint child = operand(CT_CONSTANT_TAG_BIT | child_ref.x, child_ref.y, false);
        if (child == CT_PENDING) return final ? CT_UNKNOWN : CT_PENDING;
        if (!ct_is_resolved(child)) return CT_UNKNOWN;
        uint param_scalar = ct_is_const_param(child)
            ? checked_constant_parameter_scalar(ct_param_token(child)) : 0u;
        bool fold;
        uint status = ct_build_projection(target, child, param_scalar, fold, value, key);
        if (!fold) return status;
    }
    return ct_build_value(value, key);
}

// Intern one candidate; CT_PENDING means a child is not interned yet.
public uint canonical_intern_candidate(uint candidate, bool final)
{
    CtKey key;
    uint status;
    if (candidate < ct_row_capacity()) status = build_row(candidate, final, key);
    else status = build_constant(candidate, final, key);
    if (status != CT_KEY_BUILT) return status;
    uint record = ct_candidate_record(candidate);
    if (ct_counts[CT_COUNT_REINTERN] != 0u)
    {
        // The fixed record may hold this candidate's earlier key, which
        // other references still name.
        uint found = ct_lookup(key);
        if (found != CT_NONE) return found;
        if (ct_is_published(record)) record = ct_alloc_record();
        if (record == CT_UNKNOWN) return CT_UNKNOWN;
    }
    ct_key_store(key, record, key.extra);
    return ct_intern(record, key);
}
