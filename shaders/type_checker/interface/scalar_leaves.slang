// Shared primitive leaves follow the HIR-backed type trees. Keep unit first:
// existing implicit-void signatures name the beginning of this interval.
import primitive_types;

public static const uint INTERFACE_SCALAR_LEAF_COUNT = SCALAR_NEVER - SCALAR_UNIT + 1u;

public uint interface_scalar_leaf_index(uint hir_type_count, uint scalar)
{
    return scalar_is_identity(scalar)
        ? hir_type_count + scalar - SCALAR_UNIT : 0xffffffffu;
}
