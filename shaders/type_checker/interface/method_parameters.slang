import hir_records;

static const uint INTERFACE_METHOD_INVALID = 0xffffffffu;
static const uint INTERFACE_METHOD_SYMBOL = 0x80000000u;

// Canonical method rows are scattered in increasing compact HIR order.
uint interface_method_for_function(
    uint function_node, uint count, StructuredBuffer<HirMethodCore> methods)
{
    uint lo = 0u;
    uint hi = count;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (methods[mid].node < function_node) lo = mid + 1u;
        else hi = mid;
    }
    return lo < count && methods[lo].node == function_node
        ? lo : INTERFACE_METHOD_INVALID;
}

bool interface_public_inherent_method(HirMethodSignature signature)
{
    return ((signature.metadata >> 16u) & 4u) != 0u &&
        (signature.metadata & 0xffffu) == 1u;
}

// Every required method is part of a public trait's contract, including
// methods whose visibility prevents direct calls outside the defining module.
uint interface_trait_method_owner(
    HirMethodCore method, uint hir_count,
    StructuredBuffer<HirCore> cores, StructuredBuffer<HirPayload> payloads,
    StructuredBuffer<uint> public_decl_index_by_hir)
{
    uint owner = method.owner;
    return owner < hir_count && cores[owner].kind == 2u && payloads[owner].a == 10u
        ? public_decl_index_by_hir[owner] : INTERFACE_METHOD_INVALID;
}

uint interface_method_parameter_ordinal(
    HirMethodSignature signature, uint source_ordinal)
{
    // Mode 3 is a typed first-parameter candidate, including ordinary static
    // constructors. Preserve it. Only syntactic self / &self is implicit.
    bool implicit_self = signature.receiver_mode == 1u || signature.receiver_mode == 2u;
    return implicit_self && source_ordinal == 0u
        ? INTERFACE_METHOD_INVALID : source_ordinal;
}
