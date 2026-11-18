import primitive_types;
// Direct probe of the production walkers. This adapter intentionally implements
// only the identity-aware capability, without the legacy slot/environment API.
import type_checker.scoped_type_equality;
import type_checker.scoped_type_hash;

struct Params
{
    uint node_count; uint argument_count; uint parameter_count; uint environment_count;
    uint binding_count; uint query_count; uint reserved0; uint reserved1;
};
ConstantBuffer<Params> gParams;
// Node rows: the ten IConcreteTypeGraph metadata columns, then first argument.
StructuredBuffer<uint> nodes;
StructuredBuffer<uint> arguments; // tag, payload
// Canonical parameter key: unit[2], binder kind/owner/scope, domain,
// source ordinal, binding slot. The last column is not part of identity.
StructuredBuffer<uint> parameters;
// Environment: unit[2], binder kind/owner/scope, type start/count, constant start/count.
StructuredBuffer<uint> environments;
StructuredBuffer<uint> bindings; // original canonical parameter, result tag/kind, payload
StructuredBuffer<uint> queries; // left[3], right[3], node capacity, parameter capacity
// admission status, equal, left/right hash success, left/right hash
RWStructuredBuffer<uint> results;
static const uint INVALID = 0xffffffffu;

bool parameter_valid(uint reference, bool constant)
{
    if (reference >= gParams.parameter_count) return false;
    uint base = reference * 8u;
    for (uint field = 0u; field < 8u; field++)
        if (parameters[base + field] == INVALID) return false;
    return parameters[base + 2u] <= 1u &&
        parameters[base + 5u] == (constant ? 1u : 0u) &&
        parameters[base + 7u] < 32u;
}

bool substitute(uint environment, uint original, bool constant, out uint tag, out uint payload)
{
    tag = 0u; payload = INVALID;
    if (environment >= gParams.environment_count || !parameter_valid(original, constant)) return false;
    uint parameter_base = original * 8u;
    uint environment_base = environment * 9u;
    // The original reference reaches this lookup intact. Equal slots belonging
    // to another unit or binder must not capture this environment's bindings.
    for (uint field = 0u; field < 5u; field++)
        if (parameters[parameter_base + field] != environments[environment_base + field]) return false;
    uint domain_start = constant ? 7u : 5u;
    uint start = environments[environment_base + domain_start];
    uint count = environments[environment_base + domain_start + 1u];
    uint slot = parameters[parameter_base + 7u];
    if (count > 32u || slot >= count || start > gParams.binding_count ||
        count > gParams.binding_count - start) return false;
    uint binding_base = (start + slot) * 3u;
    uint declared = bindings[binding_base];
    if (!parameter_valid(declared, constant)) return false;
    // Match full identity (including domain and source ordinal), then require
    // the binding coordinate to agree. Slot itself is not semantic identity.
    for (uint field = 0u; field < 8u; field++)
        if (parameters[parameter_base + field] != parameters[declared * 8u + field]) return false;
    tag = bindings[binding_base + 1u];
    payload = bindings[binding_base + 2u];
    // Output validation belongs to the production walkers, including domain.
    return true;
}

struct ProbeGraph : IParameterScopedTypeGraph
{
    // Legacy fixtures deliberately map each row to the same numbered u32
    // value. Separate typed-constant probes cover nonunique and colliding rows.
    static bool constant_value(uint row, out uint3 value)
    { value = uint3(SCALAR_U32, row, 0u); return row != INVALID; }
    static uint constant_parameter_scalar(uint reference)
    { return parameter_valid(reference, true) ? SCALAR_U32 : 0u; }
    static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { scalar = 0u; child = uint2(0u, INVALID); return false; }
    static uint metadata(uint instance, uint field)
    {
        if (instance >= gParams.node_count || field >= 10u) return INVALID;
        return nodes[instance * 11u + field];
    }
    static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    {
        tag = 0u; payload = INVALID;
        if (instance >= gParams.node_count) return false;
        uint base = instance * 11u;
        uint start = nodes[base + 10u];
        uint count = nodes[base + 2u];
        if (slot >= count || start > gParams.argument_count ||
            count > gParams.argument_count - start) return false;
        tag = arguments[(start + slot) * 2u];
        payload = arguments[(start + slot) * 2u + 1u];
        return true;
    }
    static bool parameter_is_valid(uint reference, bool constant)
    {
        return parameter_valid(reference, constant);
    }
    static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload)
    {
        return substitute(environment, reference, false, tag, payload);
    }
    static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value)
    {
        return substitute(environment, reference, true, kind, value);
    }
}

// Admission here checks transport bounds and primitive representation only.
// Unknown identities, wrong domains, unsupported arity, and traversal failure
// deliberately reach the real walkers rather than a second structural decoder.
bool root_admitted(uint tag, uint payload, uint context, uint capacity, uint parameter_capacity)
{
    if (context != INVALID && context >= gParams.environment_count) return false;
    if (tag == 1u) return payload >= 1u && payload <= 8u;
    if (tag == 2u || tag == 0x80000002u) return payload < parameter_capacity;
    if (tag == 3u) return payload < capacity;
    return tag == 0x80000001u && payload != INVALID;
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint row = dtid.x;
    if (row >= gParams.query_count) return;
    uint base = row * 8u;
    uint3 left = uint3(queries[base], queries[base + 1u], queries[base + 2u]);
    uint3 right = uint3(queries[base + 3u], queries[base + 4u], queries[base + 5u]);
    uint capacity = queries[base + 6u];
    uint parameter_capacity = queries[base + 7u];
    uint output = row * 6u;
    for (uint field = 0u; field < 6u; field++) results[output + field] = 0u;
    if (capacity > gParams.node_count || parameter_capacity > gParams.parameter_count)
    {
        results[output] = 1u;
        return;
    }
    if (!root_admitted(left.x, left.y, left.z, capacity, parameter_capacity) ||
        !root_admitted(right.x, right.y, right.z, capacity, parameter_capacity))
    {
        results[output] = 2u;
        return;
    }
    uint left_hash; uint right_hash;
    bool equal = scoped_type_refs_equal<ProbeGraph>(left.x, left.y, left.z,
        right.x, right.y, right.z, capacity, parameter_capacity);
    bool left_ok = scoped_type_ref_hash<ProbeGraph>(left.x, left.y, left.z,
        capacity, parameter_capacity, left_hash);
    bool right_ok = scoped_type_ref_hash<ProbeGraph>(right.x, right.y, right.z,
        capacity, parameter_capacity, right_hash);
    results[output + 1u] = equal ? 1u : 0u;
    results[output + 2u] = left_ok ? 1u : 0u;
    results[output + 3u] = right_ok ? 1u : 0u;
    results[output + 4u] = left_hash;
    results[output + 5u] = right_hash;
}
