// One compact parameter relation for functions and enum constructors. A
// constructor's payload type is scoped by the enum, while its target is the
// variant. The two source families occupy disjoint rows before compaction.
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;

bool hir_callable_parameter(uint row, out uint target, out uint header,
    out uint type_node, out uint ordinal, out uint source_parameter)
{
    target = INVALID; header = INVALID; type_node = INVALID;
    ordinal = INVALID; source_parameter = INVALID;
    uint parameters = min(compact_param_count[0u], gParams.n_hir_nodes);
    if (row < parameters)
    {
        HirParam parameter = compact_params[row];
        header = parameter.owner;
        if (!valid_node(header)) return false;
        target = compact_hir_payload[header].b;
        type_node = parameter.type_node; ordinal = parameter.ordinal;
        source_parameter = row;
    }
    else
    {
        uint payload_row = row - parameters;
        if (payload_row >= min(compact_variant_payload_row_count[0u], gParams.n_hir_nodes)) return false;
        HirVariantPayload payload = compact_variant_payloads[payload_row];
        if (payload.variant >= min(compact_variant_count[0u], gParams.n_hir_nodes)) return false;
        HirVariant variant = compact_variants[payload.variant];
        header = variant.owner; target = variant.name_token;
        type_node = payload.type_node; ordinal = payload.ordinal;
    }
    // A source parameter owns a row even without a written type. In particular,
    // implicit self owns ordinal zero; omitting it would hide the whole callable
    // range from argument matching. Receiver checking owns its type separately.
    return valid_node(header) && valid_token(target) &&
        (source_parameter != INVALID || valid_node(type_node));
}
