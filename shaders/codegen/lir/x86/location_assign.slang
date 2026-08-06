import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
StructuredBuffer<uint> x86_position_by_semantic;
StructuredBuffer<uint> x86_last_use_by_semantic;
StructuredBuffer<uint> x86_clobber_by_position;
RWStructuredBuffer<uint> x86_location_by_semantic;

static const uint DISPATCH_X_STRIDE = 16776960u;

bool scalar_gpr_type(uint type_id)
{
    return type_id == 1u || type_id == 2u || type_id == 3u ||
        type_id == 4u || type_id == 6u || type_id == 8u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    if (row >= total) return;
    uint first = x86_position_by_semantic[row];
    uint last = x86_last_use_by_semantic[row];
    if (first >= total || last <= first || last - first >= X86_TEMP_REGISTER_COUNT ||
        !scalar_gpr_type(semantic_lir_core[row].type_id)) return;
    // Keep the stack-home path as the correctness baseline while the
    // interference graph is assembled. A value may be consumed by a later
    // target expansion row than the semantic row that names it, so a local
    // row-order comparison cannot prove non-overlap. Stack homes are already
    // part of the ABI and preserve every value without aliasing.
    return;
    // Register assignment is only valid when this interval does not overlap
    // another value assigned to the same lane. The previous first-position
    // modulo heuristic ignored interference between adjacent field loads, so
    // expressions such as `oc.y * ray.direction.y` silently overwrote one
    // operand. Keep the decision deterministic and parallel: a row claims a
    // lane only when no earlier value with the same lane has an overlapping
    // lifetime. Values that cannot claim a lane remain in their stack homes.
    uint candidate = first % X86_TEMP_REGISTER_COUNT;
    for (uint other = 0u; other < row; ++other)
    {
        uint other_first = x86_position_by_semantic[other];
        uint other_last = x86_last_use_by_semantic[other];
        if (other_first >= total || other_last <= other_first ||
            other_first % X86_TEMP_REGISTER_COUNT != candidate)
            continue;
        if (other_first <= last && first <= other_last)
            return;
    }
    for (uint position = first + 1u; position <= last; ++position)
        if (x86_clobber_by_position[position] != 0u) return;
    uint physical = X86_TEMP_REGISTER_FIRST + candidate;
    x86_location_by_semantic[row] = X86_LOCATION_REGISTER | physical;
}
