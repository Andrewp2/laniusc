import constant_value;
import type_checker.trait_solver.abi;
import type_checker.trait_solver.constant_atoms;
import type_checker.trait_solver.admitted_rows;
import type_checker.scoped_type_equality;
import type_checker.concrete_type_equality;

public bool ts_atom(uint atom, out uint4 low, out uint4 high)
{
    return ts_read8(1u, atom, low, high);
}
public bool ts_snapshot_is_valid(uint snapshot)
{
    uint4 row;
    return ts_read4(0u, snapshot, 0u, row) && row.x != TS_INVALID && row.y != TS_INVALID;
}
public bool ts_binder_is_valid(uint atom)
{
    uint4 low; uint4 high;
    if (!ts_atom(atom, low, high)) return false;
    if (low.x == 3u)
        return low.y != TS_INVALID && low.z != TS_INVALID && low.w != TS_INVALID &&
            high.x != TS_INVALID && all(high.yzw == uint3(0u, 0u, 0u));
    return low.x == 4u && ts_snapshot_is_valid(low.y) &&
        low.z != 0u && low.z != TS_INVALID && low.w != TS_INVALID &&
        all(high == uint4(0u, 0u, 0u, 0u));
}
public bool ts_parameter_is_valid(uint atom, bool constant)
{
    uint4 low; uint4 high;
    return ts_atom(atom, low, high) && low.x == 5u &&
        ts_binder_is_valid(low.y) && low.z == (constant ? 1u : 0u) &&
        low.w != TS_INVALID && all(high.yzw == uint3(0u, 0u, 0u)) &&
        (constant ? constant_scalar_is_supported(high.x) : high.x == 0u);
}
public bool ts_nominal_is_valid(uint atom)
{
    uint4 low; uint4 high;
    if (!ts_atom(atom, low, high) || any(high != uint4(0u, 0u, 0u, 0u))) return false;
    if (low.x == 1u)
        return low.y != TS_INVALID && low.z != TS_INVALID && low.w < 0x20000000u;
    return low.x == 2u && ts_snapshot_is_valid(low.y) &&
        low.z < 0x20000000u && low.w == 0u;
}
public bool ts_type_reference_shape(uint2 ref)
{
    if (ref.y == TS_INVALID) return false;
    if (ref.x == 1u) return ts_scalar_is_valid(ref.y);
    if (ref.x == 2u) return ts_parameter_is_valid(ref.y, false);
    uint4 low; uint4 high;
    return ref.x == 3u && ts_read8(5u, ref.y, low, high) && low.x >= 1u && low.x <= 4u;
}
public bool ts_constant_reference_shape(uint2 ref)
{
    if (ref.y == TS_INVALID) return false;
    uint3 value; uint target; uint2 child;
    return (ref.x == 0x80000001u && ts_constant_atom_value(ref.y, value)) ||
        (ref.x == 0x80000002u && ts_parameter_is_valid(ref.y, true)) ||
        (ref.x == 0x80000003u && ts_constant_projection(ref.y, target, child));
}
public bool ts_reference_shape(uint2 ref)
{ return ts_type_reference_shape(ref) || ts_constant_reference_shape(ref); }

// The nominal's accepted declaration/header relation comes from immutable
// CheckedUnitContracts. This validates its packed representation, not source
// name resolution. Child roots receive full independent traversal admission.
public bool ts_node_is_valid(uint node)
{
    uint4 low; uint4 high;
    if (!ts_read8(5u, node, low, high)) return false;
    if (low.x == 1u)
    {
        if (!ts_nominal_is_valid(low.y) || low.w > 32u ||
            (low.w == 0u && low.z != 0u) || !ts_row_span(6u, low.z, low.w) ||
            any(high != uint4(0u, 0u, 0u, 0u))) return false;
        [loop]
        for (uint i = 0u; i < low.w; i++)
        {
            uint2 child;
            if (!ts_read2(6u, low.z + i, 0u, child) || !ts_reference_shape(child)) return false;
        }
        return true;
    }
    if (low.x == 5u)
    {
        uint target; uint2 child;
        return ts_constant_projection(node, target, child) &&
            ts_constant_reference_shape(uint2(child.x | 0x80000000u, child.y));
    }
    if (low.x < 2u || low.x > 4u || any(low.yzw != uint3(0u, 0u, 0u)) ||
        !ts_type_reference_shape(high.xy)) return false;
    return low.x == 2u ? ts_constant_reference_shape(high.zw) :
        all(high.zw == uint2(0u, 0u));
}

// Ownership is retained binder identity, never a generic slot number.
public bool ts_owner_row_is_valid(uint owner)
{
    uint4 low; uint4 high; uint4 binder; uint4 extra; uint4 snapshot; uint callable;
    if (!ts_read8(2u, owner, low, high) ||
        !ts_binder_is_valid(low.x) || !ts_atom(low.x, binder, extra) ||
        !ts_read4(0u, low.y, 0u, snapshot) || !ts_snapshot_is_valid(low.y) ||
        low.z == TS_INVALID || high.y > 64u ||
        (high.y == 0u && high.x != 0u) || (high.w == 0u && high.z != 0u) ||
        !ts_row_span(3u, high.x, high.y) || !ts_row_span(8u, high.z, high.w) ||
        !ts_word(2u, owner, 8u, callable)) return false;
    if (callable != TS_INVALID)
    {
        uint callable_owner;
        if (!ts_word(4u, callable, 1u, callable_owner) || callable_owner != owner) return false;
    }
    if (binder.x == 3u && any(binder.yz != snapshot.xy)) return false;
    if (binder.x == 4u && binder.y != low.y) return false;
    uint owner_count;
    if (!ts_table_count(2u, owner_count)) return false;
    if (low.w == TS_INVALID) return true;
    uint parent_snapshot;
    return low.w < owner_count && low.w != owner &&
        ts_word(2u, low.w, 1u, parent_snapshot) && parent_snapshot == low.y;
}
public bool ts_parameter_row_is_valid(uint row, uint expected_owner)
{
    uint4 param; uint binder; uint4 atom; uint4 extra;
    return ts_read4(3u, row, 0u, param) && param.x == expected_owner &&
        param.z < 32u && param.w <= 1u && ts_parameter_is_valid(param.y, param.w == 1u) &&
        ts_word(2u, expected_owner, 0u, binder) && ts_atom(param.y, atom, extra) && atom.y == binder;
}
// The owner `steps` parent links (Owner word 3) above `owner`. Callers only
// re-walk a chain prefix they already read, so every read succeeds. Owner
// chains re-walk their prefix instead of keeping a per-thread visited list.
public uint ts_owner_ancestor(uint owner, uint steps)
{
    [loop]
    for (uint step = 0u; step < steps; step++)
    {
        uint parent;
        if (!ts_word(2u, owner, 3u, parent)) return TS_INVALID;
        owner = parent;
    }
    return owner;
}
// True when `owner` is one of the `count` owners from `first` up its chain.
public bool ts_owner_chain_contains(uint first, uint count, uint owner)
{
    [loop]
    for (uint prior = 0u; prior < count; prior++)
    {
        if (first == owner) return true;
        uint parent;
        if (!ts_word(2u, first, 3u, parent)) return false;
        first = parent;
    }
    return false;
}
public bool ts_parameter_visible(uint atom, uint owner)
{
    uint4 parameter; uint4 extra;
    if (!ts_atom(atom, parameter, extra) || parameter.x != 5u || parameter.z > 1u ||
        !ts_parameter_is_valid(atom, parameter.z == 1u)) return false;
    uint first = owner;
    [loop]
    for (uint depth = 0u; depth < 64u && owner != TS_INVALID; depth++)
    {
        if (ts_owner_chain_contains(first, depth, owner)) return false;
        uint4 low; uint4 high;
        if (!ts_owner_row_is_valid(owner) || !ts_read8(2u, owner, low, high)) return false;
        if (low.x == parameter.y)
        {
            [loop]
            for (uint i = 0u; i < high.y; i++)
            {
                uint4 candidate;
                if (!ts_parameter_row_is_valid(high.x + i, owner) ||
                    !ts_read4(3u, high.x + i, 0u, candidate)) return false;
                if (candidate.y == atom) return true;
            }
            return false;
        }
        owner = low.w;
    }
    return false;
}

public EvidenceStatus ts_admit_owner_chain(uint owner, out uint type_count, out uint constant_count)
{
    type_count = 0u; constant_count = 0u;
    uint type_mask = 0u; uint constant_mask = 0u;
    uint chain_length = 0u;
    uint original = owner;
    [loop]
    for (uint depth = 0u; owner != TS_INVALID; depth++)
    {
        if (depth == 64u) return ts_limit(6u, original, 65u, 64u);
        if (ts_owner_chain_contains(original, depth, owner)) return ts_invalid(5u, original, owner);
        chain_length = depth + 1u;
        uint4 low; uint4 high;
        uint declared_count;
        if (!ts_word(2u, owner, 5u, declared_count)) return ts_invalid(1u, original, owner);
        if (declared_count > 64u) return ts_limit(19u, owner, declared_count, 64u);
        if (!ts_owner_row_is_valid(owner) || !ts_read8(2u, owner, low, high)) return ts_invalid(3u, original, owner);
        uint prior_ordinal = TS_INVALID;
        [loop]
        for (uint i = 0u; i < high.y; i++)
        {
            uint4 param; uint4 atom; uint4 extra;
            if (!ts_parameter_row_is_valid(high.x + i, owner) ||
                !ts_read4(3u, high.x + i, 0u, param) || !ts_atom(param.y, atom, extra))
                return ts_invalid(4u, owner, high.x + i);
            if (i != 0u && atom.w <= prior_ordinal) return ts_invalid(3u, owner, param.y);
            prior_ordinal = atom.w;
            uint bit = 1u << param.z;
            if (param.w == 0u)
            {
                if ((type_mask & bit) != 0u) return ts_invalid(3u, owner, param.y);
                type_mask |= bit; type_count++;
            }
            else
            {
                if ((constant_mask & bit) != 0u) return ts_invalid(3u, owner, param.y);
                constant_mask |= bit; constant_count++;
            }
        }
        owner = low.w;
    }
    uint expected_types = type_count == 32u ? TS_INVALID : (1u << type_count) - 1u;
    uint expected_constants = constant_count == 32u ? TS_INVALID : (1u << constant_count) - 1u;
    if (type_mask != expected_types || constant_mask != expected_constants)
        return ts_invalid(9u, original, TS_INVALID);
    // A dense final union alone would permit child slot0 / ancestor slot1.
    // Verify the actual producer composition: ancestors precede own parameters
    // in each domain. Preserve these values; do not shift them a second time.
    uint composed_types = 0u; uint composed_constants = 0u;
    [loop]
    for (uint remaining = chain_length; remaining != 0u; remaining--)
    {
        uint current = ts_owner_ancestor(original, remaining - 1u); uint4 span;
        if (!ts_read4(2u, current, 4u, span)) return ts_invalid(1u, original, current);
        [loop]
        for (uint i = 0u; i < span.y; i++)
        {
            uint4 param;
            if (!ts_read4(3u, span.x + i, 0u, param)) return ts_invalid(1u, current, span.x + i);
            uint expected;
            if (param.w == 0u) { expected = composed_types; composed_types++; }
            else { expected = composed_constants; composed_constants++; }
            if (param.z != expected) return ts_invalid(9u, current, param.y);
        }
    }
    return ts_ok();
}

// Batch graph rows and frozen catalog ownership are admitted first. Env11
// still validates its own binding records before the later Binding12 stage.
public bool ts_environment_header(uint environment, out uint4 env)
{
    uint4 owner; uint4 span;
    return ts_read4(11u, environment, 0u, env) && env.w <= 1u && env.z <= 64u &&
        (env.z != 0u || env.y == 0u) && ts_read_admitted_owner(env.x, owner, span) &&
        ts_row_span(12u, env.y, env.z);
}
// Post-admission substitution only: every Env11 row and its complete binding
// set passed ordered suffix admission before phases14-17 consume environments.
// Older rows are immutable and covered by a successful retained receipt. Env11
// itself preflights values with INVALID environment, so it never uses lookup.
// Exact membership, sorted uniqueness, completeness, and value scope were
// proved there. The typed adapters below still check requested/returned domains.
public bool ts_admitted_environment_binding(uint environment, uint atom, out uint2 value)
{
    value = uint2(0u, TS_INVALID);
    uint4 env;
    if (atom == TS_INVALID || !ts_read4(11u, environment, 0u, env) ||
        env.w > 1u || env.z > 64u || (env.z == 0u && env.y != 0u) ||
        !ts_row_span(12u, env.y, env.z)) return false;
    // Bound by 64 entries, sorted by exact atom. No parameter-to-slot conversion.
    uint lo = 0u; uint hi = env.z;
    [loop]
    for (uint step = 0u; step < 7u && lo < hi; step++)
    {
        uint mid = lo + (hi - lo) / 2u;
        uint4 binding;
        if (!ts_read4(12u, env.y + mid, 0u, binding) ||
            binding.x != environment || binding.w != 0u) return false;
        if (binding.y == atom) return ts_read_root(binding.z, value);
        if (binding.y < atom) lo = mid + 1u;
        else hi = mid;
    }
    return false;
}

public EvidenceStatus ts_admit_environment_header(uint environment, uint expected_owner, uint form)
{
    uint4 env;
    if (!ts_read4(11u, environment, 0u, env)) return ts_invalid(1u, environment, TS_INVALID);
    if (env.z > 64u) return ts_limit(19u, environment, env.z, 64u);
    if (env.x != expected_owner || env.w != form) return ts_invalid(3u, environment, expected_owner);
    uint types; uint constants;
    EvidenceStatus status = ts_admitted_owner_parameter_counts(env.x, types, constants);
    if (status.state != TS_VALID) return status;
    if (!ts_environment_header(environment, env)) return ts_invalid(1u, environment, TS_INVALID);
    if (env.z != types + constants) return ts_invalid(9u, environment, expected_owner);
    uint previous = TS_INVALID; uint actual_types = 0u; uint actual_constants = 0u;
    for (uint i = 0u; i < env.z; i++)
    {
        uint4 binding; uint4 parameter; uint2 value;
        if (!ts_read4(12u, env.y + i, 0u, binding) || binding.x != environment || binding.w != 0u ||
            (i != 0u && binding.y <= previous) || !ts_read_admitted_parameter(binding.y, parameter) ||
            !ts_admitted_parameter_visible(binding.y, env.x) ||
            !ts_read_root(binding.z, value)) return ts_invalid(3u, environment, env.y + i);
        previous = binding.y;
        if (parameter.z == 0u)
        {
            if (!ts_admitted_type_reference_shape(value)) return ts_invalid(4u, environment, binding.z);
            actual_types++;
        }
        else
        {
            if (!ts_admitted_constant_reference_shape(value) ||
                ts_constant_reference_scalar(value) != ts_constant_parameter_scalar(binding.y))
                return ts_invalid(4u, environment, binding.z);
            actual_constants++;
        }
    }
    if (actual_types != types || actual_constants != constants)
        return ts_invalid(9u, environment, expected_owner);
    return ts_ok();
}

// Both policies consume admitted node/edge/atom rows through checked readers.
// Root preflight separately proves contextual graph invariants before hashing
// or equality. Only owned-parameter substitution differs between the policies.
public uint ts_graph_metadata(uint instance, uint field)
{
    uint4 low; uint4 high;
    bool admitted = ts_read_admitted_node(instance, low, high);
    return select(admitted, ts_node_row_field(low, high, field), TS_INVALID);
}
public bool ts_graph_argument(uint instance, uint slot, out uint tag, out uint payload)
{
    tag = 0u; payload = TS_INVALID; uint4 low; uint2 ref;
    bool read = ts_read4(5u, instance, 0u, low);
    if (!(read & (low.x == 1u) & (low.w <= 32u) & (slot < low.w))) return false;
    if (!ts_row_span(6u, low.z, low.w) || !ts_read2(6u, low.z + slot, 0u, ref)) return false;
    tag = ref.x; payload = ref.y; return true;
}

// Root admission substitutes a type or a constant parameter at one call site
// per visited leaf: substitute_parameter(constant) is exactly
// substitute_constant_parameter (constant) or substitute_type_parameter.
public interface ITsAdmissionGraph : IParameterScopedTypeGraph
{
    static bool substitute_parameter(uint environment, uint reference, bool constant,
        out uint tag, out uint payload);
}

public struct TraitSolverTypeGraph : ITsAdmissionGraph
{
    public static bool constant_value(uint atom, out uint3 value)
    { return ts_constant_atom_value(atom, value); }
    public static uint constant_parameter_scalar(uint parameter)
    { return ts_constant_parameter_scalar(parameter); }
    public static bool constant_projection(uint node, out uint target, out uint2 child)
    { return ts_constant_projection(node, target, child); }
    public static bool parameter_is_valid(uint reference, bool constant)
    { return ts_admitted_parameter_has_domain(reference, constant); }
    public static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload)
    {
        tag = 0u; payload = TS_INVALID; uint2 value;
        if (!ts_admitted_parameter_has_domain(reference, false) ||
            !ts_admitted_environment_binding(environment, reference, value) || !ts_admitted_type_reference_shape(value)) return false;
        tag = value.x; payload = value.y; return true;
    }
    public static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value)
    {
        kind = 0u; value = TS_INVALID; uint2 ref;
        if (!ts_admitted_parameter_has_domain(reference, true) ||
            !ts_admitted_environment_binding(environment, reference, ref) || !ts_admitted_constant_reference_shape(ref)) return false;
        kind = ref.x & 0x7fffffffu; value = ref.y; return true;
    }
    // A type binding's tag is 1..3, so the constant mask leaves it unchanged.
    public static bool substitute_parameter(uint environment, uint reference, bool constant,
        out uint tag, out uint payload)
    {
        tag = 0u; payload = TS_INVALID; uint2 value;
        if (!ts_admitted_parameter_has_domain(reference, constant) ||
            !ts_admitted_environment_binding(environment, reference, value)) return false;
        bool shape;
        if (constant) shape = ts_admitted_constant_reference_shape(value);
        else shape = ts_admitted_type_reference_shape(value);
        if (!shape) return false;
        tag = value.x & 0x7fffffffu; payload = value.y; return true;
    }
    public static uint metadata(uint instance, uint field)
    { return ts_graph_metadata(instance, field); }
    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    { return ts_graph_argument(instance, slot, tag, payload); }
}

// Definition-side catalog roots have no substitution environment. This policy
// makes that capability boundary explicit even when a walk stores contexts in
// a dynamically indexed stack. Unexpected substitution requests fail closed.
public struct CatalogTraitSolverTypeGraph : ITsAdmissionGraph
{
    public static bool constant_value(uint atom, out uint3 value)
    { return ts_constant_atom_value(atom, value); }
    public static uint constant_parameter_scalar(uint parameter)
    { return ts_constant_parameter_scalar(parameter); }
    public static bool constant_projection(uint node, out uint target, out uint2 child)
    { return ts_constant_projection(node, target, child); }
    public static bool parameter_is_valid(uint reference, bool constant)
    { return ts_admitted_parameter_has_domain(reference, constant); }
    public static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload)
    {
        tag = 0u; payload = TS_INVALID;
        return false;
    }
    public static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value)
    {
        kind = 0u; value = TS_INVALID;
        return false;
    }
    public static bool substitute_parameter(uint environment, uint reference, bool constant,
        out uint tag, out uint payload)
    {
        tag = 0u; payload = TS_INVALID;
        return false;
    }
    public static uint metadata(uint instance, uint field)
    { return ts_graph_metadata(instance, field); }
    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    { return ts_graph_argument(instance, slot, tag, payload); }
}
