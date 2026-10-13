// A call returning one of its generic parameter types has the checked type
// of the corresponding argument. Follow that accepted per-call relation;
// declaration-token caches cannot represent distinct compound instantiations.
import hir_records;

public uint generic_result_type_origin(uint node, uint hir_count,
    StructuredBuffer<HirCore> cores, StructuredBuffer<HirPayload> payloads,
    StructuredBuffer<uint> return_argument_nodes)
{
    for (uint depth = 0u; depth < hir_count && node < hir_count; depth++)
    {
        uint kind = cores[node].kind;
        HirPayload value = payloads[node];
        uint next = 0xffffffffu;
        if (kind == 19u) next = return_argument_nodes[node];
        else if ((kind == 14u || kind == 16u || kind == 17u) && value.a == 1u)
            next = value.b;
        if (next >= hir_count || next == node) return node;
        node = next;
    }
    return 0xffffffffu;
}
