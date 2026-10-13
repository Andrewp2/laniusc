// Checked references are scoped to one frontend job. A dependency reference
// points at a resolved path, whose portable identity survives page replacement.
// A local reference names a local declaration; it is never a dependency row.
// Persisted interfaces translate local references at their export boundary.

public StructuredBuffer<uint> resolved_dependency_library_id;
public StructuredBuffer<uint> resolved_dependency_unit_id;
public StructuredBuffer<uint> resolved_dependency_local_index;
// Four words per path: declaration kind, type arity, constant arity, methods.
public StructuredBuffer<uint> resolved_dependency_trait_header;

static const uint TRAIT_REFERENCE_INVALID = 0xffffffffu;
static const uint TRAIT_REFERENCE_DEPENDENCY = 0x80000000u;

public bool trait_reference_is_dependency(uint reference)
{
    return reference != TRAIT_REFERENCE_INVALID &&
        (reference & TRAIT_REFERENCE_DEPENDENCY) != 0u;
}

public uint trait_reference_path(uint reference)
{
    return reference & ~TRAIT_REFERENCE_DEPENDENCY;
}

public uint trait_reference_for_dependency_path(uint path)
{
    uint words; uint stride;
    resolved_dependency_trait_header.GetDimensions(words, stride);
    if (path >= words / 4u || path >= TRAIT_REFERENCE_DEPENDENCY ||
        resolved_dependency_trait_header[path * 4u] != 10u)
        return TRAIT_REFERENCE_INVALID;
    return TRAIT_REFERENCE_DEPENDENCY | path;
}

public uint4 trait_reference_identity(uint reference)
{
    if (reference == TRAIT_REFERENCE_INVALID) return uint4(0u, 0u, 0u, 0u);
    if (!trait_reference_is_dependency(reference)) return uint4(1u, reference, 0u, 0u);
    uint path = trait_reference_path(reference);
    return uint4(2u, resolved_dependency_library_id[path],
        resolved_dependency_unit_id[path], resolved_dependency_local_index[path]);
}

public bool trait_references_equal(uint left, uint right)
{
    return left != TRAIT_REFERENCE_INVALID && right != TRAIT_REFERENCE_INVALID &&
        all(trait_reference_identity(left) == trait_reference_identity(right));
}

public uint trait_reference_header(uint reference, uint field)
{
    return resolved_dependency_trait_header[trait_reference_path(reference) * 4u + field];
}
