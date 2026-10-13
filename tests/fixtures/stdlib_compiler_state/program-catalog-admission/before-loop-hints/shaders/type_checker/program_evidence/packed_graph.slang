import type_checker.program_evidence.abi;
import type_checker.scoped_type_equality;
import type_checker.concrete_type_equality;

public bool pev_atom(uint atom, out uint4 low, out uint4 high)
{
    return pev_read8(1u, atom, low, high);
}
public bool pev_snapshot_is_valid(uint snapshot)
{
    uint4 row;
    return pev_read4(0u, snapshot, 0u, row) && row.x != PEV_INVALID && row.y != PEV_INVALID;
}
public bool pev_binder_is_valid(uint atom)
{
    uint4 low; uint4 high;
    if (!pev_atom(atom, low, high)) return false;
    if (low.x == 3u)
        return low.y != PEV_INVALID && low.z != PEV_INVALID && low.w != PEV_INVALID &&
            high.x != PEV_INVALID && all(high.yzw == uint3(0u, 0u, 0u));
    return low.x == 4u && pev_snapshot_is_valid(low.y) &&
        low.z != 0u && low.z != PEV_INVALID && low.w != PEV_INVALID &&
        all(high == uint4(0u, 0u, 0u, 0u));
}
public bool pev_parameter_is_valid(uint atom, bool constant)
{
    uint4 low; uint4 high;
    return pev_atom(atom, low, high) && low.x == 5u &&
        pev_binder_is_valid(low.y) && low.z == (constant ? 1u : 0u) &&
        low.w != PEV_INVALID && all(high == uint4(0u, 0u, 0u, 0u));
}
public bool pev_nominal_is_valid(uint atom)
{
    uint4 low; uint4 high;
    if (!pev_atom(atom, low, high) || any(high != uint4(0u, 0u, 0u, 0u))) return false;
    if (low.x == 1u)
        return low.y != PEV_INVALID && low.z != PEV_INVALID && low.w < 0x20000000u;
    return low.x == 2u && pev_snapshot_is_valid(low.y) &&
        low.z < 0x20000000u && low.w == 0u;
}
public bool pev_type_reference_shape(uint2 ref)
{
    if (ref.y == PEV_INVALID) return false;
    if (ref.x == 1u) return pev_scalar_is_valid(ref.y);
    if (ref.x == 2u) return pev_parameter_is_valid(ref.y, false);
    uint count;
    return ref.x == 3u && pev_table_count(5u, count) && ref.y < count;
}
public bool pev_constant_reference_shape(uint2 ref)
{
    return ref.y != PEV_INVALID && (ref.x == 0x80000001u ||
        (ref.x == 0x80000002u && pev_parameter_is_valid(ref.y, true)));
}
public bool pev_reference_shape(uint2 ref)
{ return pev_type_reference_shape(ref) || pev_constant_reference_shape(ref); }

// The nominal's accepted declaration/header relation comes from immutable
// CheckedUnitContracts. This validates its packed representation, not source
// name resolution. Child roots receive full independent traversal admission.
public bool pev_node_is_valid(uint node)
{
    uint4 low; uint4 high;
    if (!pev_read8(5u, node, low, high)) return false;
    if (low.x == 1u)
    {
        if (!pev_nominal_is_valid(low.y) || low.w > 32u ||
            (low.w == 0u && low.z != 0u) || !pev_row_span(6u, low.z, low.w) ||
            any(high != uint4(0u, 0u, 0u, 0u))) return false;
        for (uint i = 0u; i < low.w; i++)
        {
            uint2 child;
            if (!pev_read2(6u, low.z + i, 0u, child) || !pev_reference_shape(child)) return false;
        }
        return true;
    }
    if (low.x < 2u || low.x > 4u || any(low.yzw != uint3(0u, 0u, 0u)) ||
        !pev_type_reference_shape(high.xy)) return false;
    return low.x == 2u ? pev_constant_reference_shape(high.zw) :
        all(high.zw == uint2(0u, 0u));
}

// Ownership is retained binder identity, never a generic slot number.
public bool pev_owner_row_is_valid(uint owner)
{
    uint4 low; uint4 high; uint4 binder; uint4 extra; uint4 snapshot; uint callable;
    if (!pev_read8(2u, owner, low, high) ||
        !pev_binder_is_valid(low.x) || !pev_atom(low.x, binder, extra) ||
        !pev_read4(0u, low.y, 0u, snapshot) || !pev_snapshot_is_valid(low.y) ||
        low.z == PEV_INVALID || high.y > 64u ||
        (high.y == 0u && high.x != 0u) || (high.w == 0u && high.z != 0u) ||
        !pev_row_span(3u, high.x, high.y) || !pev_row_span(8u, high.z, high.w) ||
        !pev_word(2u, owner, 8u, callable)) return false;
    if (callable != PEV_INVALID)
    {
        uint callable_owner;
        if (!pev_word(4u, callable, 1u, callable_owner) || callable_owner != owner) return false;
    }
    if (binder.x == 3u && any(binder.yz != snapshot.xy)) return false;
    if (binder.x == 4u && binder.y != low.y) return false;
    uint owner_count;
    if (!pev_table_count(2u, owner_count)) return false;
    if (low.w == PEV_INVALID) return true;
    uint parent_snapshot;
    return low.w < owner_count && low.w != owner &&
        pev_word(2u, low.w, 1u, parent_snapshot) && parent_snapshot == low.y;
}
public bool pev_parameter_row_is_valid(uint row, uint expected_owner)
{
    uint4 param; uint binder; uint4 atom; uint4 extra;
    return pev_read4(3u, row, 0u, param) && param.x == expected_owner &&
        param.z < 32u && param.w <= 1u && pev_parameter_is_valid(param.y, param.w == 1u) &&
        pev_word(2u, expected_owner, 0u, binder) && pev_atom(param.y, atom, extra) && atom.y == binder;
}
public bool pev_parameter_visible(uint atom, uint owner)
{
    uint4 parameter; uint4 extra;
    if (!pev_atom(atom, parameter, extra) || parameter.x != 5u || parameter.z > 1u ||
        !pev_parameter_is_valid(atom, parameter.z == 1u)) return false;
    uint visited[64];
    for (uint depth = 0u; depth < 64u && owner != PEV_INVALID; depth++)
    {
        for (uint prior = 0u; prior < depth; prior++) if (visited[prior] == owner) return false;
        visited[depth] = owner;
        uint4 low; uint4 high;
        if (!pev_owner_row_is_valid(owner) || !pev_read8(2u, owner, low, high)) return false;
        if (low.x == parameter.y)
        {
            for (uint i = 0u; i < high.y; i++)
            {
                uint4 candidate;
                if (!pev_parameter_row_is_valid(high.x + i, owner) ||
                    !pev_read4(3u, high.x + i, 0u, candidate)) return false;
                if (candidate.y == atom) return true;
            }
            return false;
        }
        owner = low.w;
    }
    return false;
}

public EvidenceStatus pev_admit_owner_chain(uint owner, out uint type_count, out uint constant_count)
{
    type_count = 0u; constant_count = 0u;
    uint visited[64]; uint type_mask = 0u; uint constant_mask = 0u;
    uint chain_length = 0u;
    uint original = owner;
    for (uint depth = 0u; owner != PEV_INVALID; depth++)
    {
        if (depth == 64u) return pev_limit(6u, original, 65u, 64u);
        for (uint prior = 0u; prior < depth; prior++)
            if (visited[prior] == owner) return pev_invalid(5u, original, owner);
        visited[depth] = owner;
        chain_length = depth + 1u;
        uint4 low; uint4 high;
        uint declared_count;
        if (!pev_word(2u, owner, 5u, declared_count)) return pev_invalid(1u, original, owner);
        if (declared_count > 64u) return pev_limit(19u, owner, declared_count, 64u);
        if (!pev_owner_row_is_valid(owner) || !pev_read8(2u, owner, low, high)) return pev_invalid(3u, original, owner);
        uint prior_ordinal = PEV_INVALID;
        for (uint i = 0u; i < high.y; i++)
        {
            uint4 param; uint4 atom; uint4 extra;
            if (!pev_parameter_row_is_valid(high.x + i, owner) ||
                !pev_read4(3u, high.x + i, 0u, param) || !pev_atom(param.y, atom, extra))
                return pev_invalid(4u, owner, high.x + i);
            if (i != 0u && atom.w <= prior_ordinal) return pev_invalid(3u, owner, param.y);
            prior_ordinal = atom.w;
            uint bit = 1u << param.z;
            if (param.w == 0u)
            {
                if ((type_mask & bit) != 0u) return pev_invalid(3u, owner, param.y);
                type_mask |= bit; type_count++;
            }
            else
            {
                if ((constant_mask & bit) != 0u) return pev_invalid(3u, owner, param.y);
                constant_mask |= bit; constant_count++;
            }
        }
        owner = low.w;
    }
    uint expected_types = type_count == 32u ? PEV_INVALID : (1u << type_count) - 1u;
    uint expected_constants = constant_count == 32u ? PEV_INVALID : (1u << constant_count) - 1u;
    if (type_mask != expected_types || constant_mask != expected_constants)
        return pev_invalid(9u, original, PEV_INVALID);
    // A dense final union alone would permit child slot0 / ancestor slot1.
    // Verify the actual producer composition: ancestors precede own parameters
    // in each domain. Preserve these values; do not shift them a second time.
    uint composed_types = 0u; uint composed_constants = 0u;
    for (uint remaining = chain_length; remaining != 0u; remaining--)
    {
        uint current = visited[remaining - 1u]; uint4 span;
        if (!pev_read4(2u, current, 4u, span)) return pev_invalid(1u, original, current);
        for (uint i = 0u; i < span.y; i++)
        {
            uint4 param;
            if (!pev_read4(3u, span.x + i, 0u, param)) return pev_invalid(1u, current, span.x + i);
            uint expected;
            if (param.w == 0u) { expected = composed_types; composed_types++; }
            else { expected = composed_constants; composed_constants++; }
            if (param.z != expected) return pev_invalid(9u, current, param.y);
        }
    }
    return pev_ok();
}

public bool pev_environment_header(uint environment, out uint4 env)
{
    return pev_read4(11u, environment, 0u, env) && env.w <= 1u && env.z <= 64u &&
        (env.z != 0u || env.y == 0u) && pev_owner_row_is_valid(env.x) &&
        pev_row_span(12u, env.y, env.z);
}
public bool pev_environment_binding(uint environment, uint atom, out uint2 value)
{
    value = uint2(0u, PEV_INVALID);
    uint4 env; uint4 param; uint4 extra;
    if (!pev_environment_header(environment, env) || !pev_atom(atom, param, extra) ||
        param.x != 5u || param.z > 1u || !pev_parameter_visible(atom, env.x)) return false;
    // Bound by 64 entries, sorted by exact atom. No parameter-to-slot conversion.
    uint lo = 0u; uint hi = env.z;
    for (uint step = 0u; step < 7u && lo < hi; step++)
    {
        uint mid = lo + (hi - lo) / 2u;
        uint4 binding;
        if (!pev_read4(12u, env.y + mid, 0u, binding) ||
            binding.x != environment || binding.w != 0u) return false;
        if (binding.y == atom)
            return pev_read_root(binding.z, value) &&
                (param.z == 0u ? pev_type_reference_shape(value) : pev_constant_reference_shape(value));
        if (binding.y < atom) lo = mid + 1u;
        else hi = mid;
    }
    return false;
}

public EvidenceStatus pev_admit_environment_header(uint environment, uint expected_owner, uint form)
{
    uint4 env;
    if (!pev_read4(11u, environment, 0u, env)) return pev_invalid(1u, environment, PEV_INVALID);
    if (env.z > 64u) return pev_limit(19u, environment, env.z, 64u);
    if (env.x != expected_owner || env.w != form) return pev_invalid(3u, environment, expected_owner);
    uint types; uint constants;
    EvidenceStatus status = pev_admit_owner_chain(env.x, types, constants);
    if (status.state != PEV_VALID) return status;
    if (!pev_environment_header(environment, env)) return pev_invalid(1u, environment, PEV_INVALID);
    if (env.z != types + constants) return pev_invalid(9u, environment, expected_owner);
    uint previous = PEV_INVALID; uint actual_types = 0u; uint actual_constants = 0u;
    for (uint i = 0u; i < env.z; i++)
    {
        uint4 binding; uint4 parameter; uint4 extra; uint2 value;
        if (!pev_read4(12u, env.y + i, 0u, binding) || binding.x != environment || binding.w != 0u ||
            (i != 0u && binding.y <= previous) || !pev_atom(binding.y, parameter, extra) ||
            parameter.x != 5u || parameter.z > 1u || !pev_parameter_visible(binding.y, env.x) ||
            !pev_read_root(binding.z, value)) return pev_invalid(3u, environment, env.y + i);
        previous = binding.y;
        if (parameter.z == 0u)
        {
            if (!pev_type_reference_shape(value)) return pev_invalid(4u, environment, binding.z);
            actual_types++;
        }
        else
        {
            if (!pev_constant_reference_shape(value)) return pev_invalid(4u, environment, binding.z);
            actual_constants++;
        }
    }
    if (actual_types != types || actual_constants != constants)
        return pev_invalid(9u, environment, expected_owner);
    return pev_ok();
}

public struct ProgramEvidenceTypeGraph : IParameterScopedTypeGraph
{
    public static bool parameter_is_valid(uint reference, bool constant)
    { return pev_parameter_is_valid(reference, constant); }
    public static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload)
    {
        tag = 0u; payload = PEV_INVALID; uint2 value;
        if (!pev_parameter_is_valid(reference, false) ||
            !pev_environment_binding(environment, reference, value) || !pev_type_reference_shape(value)) return false;
        tag = value.x; payload = value.y; return true;
    }
    public static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value)
    {
        kind = 0u; value = PEV_INVALID; uint2 ref;
        if (!pev_parameter_is_valid(reference, true) ||
            !pev_environment_binding(environment, reference, ref) || !pev_constant_reference_shape(ref)) return false;
        kind = ref.x & 0x7fffffffu; value = ref.y; return true;
    }
    public static uint metadata(uint instance, uint field)
    {
        uint4 low; uint4 high;
        if (!pev_read8(5u, instance, low, high)) return PEV_INVALID;
        if (field == 0u) return low.x;
        // Existing walker calls this declaration identity. Here it is an exact
        // interned nominal atom; its identity capacity is the atom table count.
        // It is neither a HIR/token row nor a forged public nominal triple.
        if (field == 1u) return low.x == 1u ? low.y : PEV_INVALID;
        if (field == 2u) return low.x == 1u ? low.w : 0u;
        if (field == 3u) return high.x;
        if (field == 4u) return high.y;
        if (low.x == 1u && (field == 5u || field == 6u))
        {
            if (low.w > 32u || !pev_row_span(6u, low.z, low.w)) return PEV_INVALID;
            uint constants = 0u; uint types = 0u;
            for (uint slot = 0u; slot < low.w; slot++)
            {
                uint2 ref;
                if (!pev_read2(6u, low.z + slot, 0u, ref) || !pev_reference_shape(ref)) return PEV_INVALID;
                if (application_argument_is_constant(ref.x)) constants |= 1u << slot;
                else types++;
            }
            // The general IConcreteTypeGraph contract also exposes ordered
            // mixed domains. Always using the explicit mask is exact.
            return field == 5u ? types | APPLICATION_INTERLEAVED_DOMAINS : constants;
        }
        if (field == 5u) return low.x == 2u ? high.z & 0x7fffffffu : 0u;
        if (field == 6u) return low.x == 2u ? high.w : 0u;
        return PEV_INVALID;
    }
    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    {
        tag = 0u; payload = PEV_INVALID; uint4 low; uint2 ref;
        if (!pev_read4(5u, instance, 0u, low) || low.x != 1u || low.w > 32u ||
            slot >= low.w || !pev_row_span(6u, low.z, low.w) ||
            !pev_read2(6u, low.z + slot, 0u, ref) || !pev_reference_shape(ref)) return false;
        tag = ref.x; payload = ref.y; return true;
    }
}
