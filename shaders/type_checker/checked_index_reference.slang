// Project an index argument from its checked named array/slice base. The
// start token of an index names its base and cannot provide the result type.
import hir_records;
import checked_semantic_artifact;
import type_checker.concrete_type_equality;

public bool checked_index_root(uint node, uint hir_count,
    StructuredBuffer<HirCore> cores, StructuredBuffer<HirPayload> payloads,
    out uint root, out uint indices)
{
    root = node; indices = 0u;
    for (uint depth = 0u; depth < 64u; depth++)
    {
        if (root >= hir_count) return false;
        HirCore core = cores[root];
        HirPayload value = payloads[root];
        if ((core.kind == 14u || core.kind == 16u || core.kind == 17u) && value.a == 1u)
            root = value.b;
        else if (core.kind == 20u)
        { indices++; root = value.b; }
        else return indices != 0u;
    }
    return false;
}

bool checked_named_index_base(uint node, uint hir_count, uint token_capacity,
    StructuredBuffer<HirCore> cores, StructuredBuffer<HirPayload> payloads,
    StructuredBuffer<uint> visible_declarations, out uint declaration, out uint indices)
{
    static const uint INVALID = 0xffffffffu;
    declaration = INVALID; indices = 0u;
    uint current = node;
    for (uint depth = 0u; depth < 64u; depth++)
    {
        if (current >= hir_count) return false;
        HirCore core = cores[current];
        HirPayload value = payloads[current];
        if ((core.kind == 14u || core.kind == 16u || core.kind == 17u) && value.a == 1u)
            current = value.b;
        else if (core.kind == 20u)
        {
            indices++;
            current = value.b;
        }
        else if (indices != 0u && (core.kind == 22u || core.kind == 33u))
        {
            uint token = value.d < token_capacity ? value.d : core.token_start;
            if (token >= token_capacity) return false;
            declaration = visible_declarations[token];
            if (declaration >= token_capacity) declaration = token;
            return true;
        }
        else return false;
    }
    return false;
}

// Indexing follows references only to find the container for this operation.
// The source graph and the projected element reference remain unchanged. The
// shared checked graph depth limit also makes cyclic/malformed chains fail.
public bool checked_index_container(uint source_tag, uint source_payload,
    StructuredBuffer<uint> instance_kinds, StructuredBuffer<uint> element_tags,
    StructuredBuffer<uint> element_payloads, out uint container)
{
    container = 0xffffffffu;
    uint instance_capacity; uint stride;
    instance_kinds.GetDimensions(instance_capacity, stride);
    uint tag = source_tag; uint payload = source_payload;
    for (uint depth = 0u; depth < 64u; depth++)
    {
        if (tag != 3u || payload >= instance_capacity) return false;
        uint kind = instance_kinds[payload];
        if (kind == 2u || kind == 3u) { container = payload; return true; }
        if (kind != 4u) return false;
        tag = element_tags[payload];
        payload = element_payloads[payload];
    }
    return false;
}

// Generic assignment-context readers keep their graph adapter authoritative.
// This overload needs structure only, not nominal identity or substitutions.
public bool checked_index_container<Graph : ITypeStructureGraph>(
    uint source_tag, uint source_payload, uint type_capacity, out uint container)
{
    container = 0xffffffffu;
    uint tag = source_tag; uint payload = source_payload;
    for (uint depth = 0u; depth < 64u; depth++)
    {
        if (tag != 3u || payload >= type_capacity) return false;
        uint kind = Graph.metadata(payload, 0u);
        if (kind == 2u || kind == 3u) { container = payload; return true; }
        if (kind != 4u) return false;
        tag = Graph.metadata(payload, 3u);
        payload = Graph.metadata(payload, 4u);
    }
    return false;
}

public bool checked_index_elements(uint indices, StructuredBuffer<uint> instance_kinds,
    StructuredBuffer<uint> element_tags, StructuredBuffer<uint> element_payloads,
    inout uint tag, inout uint payload)
{
    for (uint index = 0u; index < indices; index++)
    {
        uint container;
        if (!checked_index_container(tag, payload, instance_kinds, element_tags,
            element_payloads, container)) return false;
        tag = element_tags[container];
        payload = element_payloads[container];
    }
    return tag != 0u && payload != 0xffffffffu;
}

public bool checked_index_elements<Graph : ITypeStructureGraph>(uint indices,
    uint type_capacity, inout uint tag, inout uint payload)
{
    for (uint index = 0u; index < indices; index++)
    {
        uint container;
        if (!checked_index_container<Graph>(tag, payload, type_capacity, container)) return false;
        tag = Graph.metadata(container, 3u);
        payload = Graph.metadata(container, 4u);
    }
    return tag != 0u && payload != 0xffffffffu;
}

// Read complete accepted roots. These tables are immutable during projection;
// nested indexes never depend on another lane's partially published result.
public bool checked_value_index_reference(uint node, uint hir_count, uint token_capacity,
    StructuredBuffer<HirCore> cores, StructuredBuffer<HirPayload> payloads,
    StructuredBuffer<uint> visible_declarations, StructuredBuffer<uint> declaration_tags,
    StructuredBuffer<uint> declaration_payloads, StructuredBuffer<uint> member_tags,
    StructuredBuffer<uint> member_payloads, StructuredBuffer<CheckedCallArtifact> calls,
    StructuredBuffer<uint> instance_kinds, StructuredBuffer<uint> element_tags,
    StructuredBuffer<uint> element_payloads, out uint tag, out uint payload)
{
    tag = 0u; payload = 0xffffffffu;
    uint root; uint indices;
    if (!checked_index_root(node, hir_count, cores, payloads, root, indices)) return false;
    HirCore core = cores[root];
    HirPayload value = payloads[root];
    if (core.kind == 22u || core.kind == 33u)
    {
        uint token = value.d < token_capacity ? value.d : core.token_start;
        if (token >= token_capacity) return false;
        uint declaration = visible_declarations[token];
        if (declaration >= token_capacity) declaration = token;
        tag = declaration_tags[declaration]; payload = declaration_payloads[declaration];
    }
    else if (core.kind == 21u)
    {
        if (value.c >= token_capacity) return false;
        tag = member_tags[value.c]; payload = member_payloads[value.c];
    }
    else if (core.kind == 19u)
    {
        tag = calls[root].return_ref_tag; payload = calls[root].return_ref_payload;
    }
    else return false;
    return checked_index_elements(indices, instance_kinds, element_tags, element_payloads,
        tag, payload);
}

public bool checked_member_index_reference(uint node, uint hir_count, uint token_capacity,
    StructuredBuffer<HirCore> cores, StructuredBuffer<HirPayload> payloads,
    StructuredBuffer<uint> member_tags, StructuredBuffer<uint> member_payloads,
    StructuredBuffer<uint> instance_kinds, StructuredBuffer<uint> element_tags,
    StructuredBuffer<uint> element_payloads, out uint tag, out uint payload)
{
    tag = 0u; payload = 0xffffffffu;
    uint root; uint indices;
    if (!checked_index_root(node, hir_count, cores, payloads, root, indices) ||
        cores[root].kind != 21u) return false;
    uint token = payloads[root].c;
    if (token >= token_capacity) return false;
    tag = member_tags[token]; payload = member_payloads[token];
    return checked_index_elements(indices, instance_kinds, element_tags, element_payloads,
        tag, payload);
}

public bool checked_named_index_reference(uint node, uint hir_count, uint token_capacity,
    StructuredBuffer<HirCore> cores, StructuredBuffer<HirPayload> payloads,
    StructuredBuffer<uint> visible_declarations, StructuredBuffer<uint> declaration_tags,
    StructuredBuffer<uint> declaration_payloads, StructuredBuffer<uint> instance_kinds,
    StructuredBuffer<uint> element_tags, StructuredBuffer<uint> element_payloads,
    out uint tag, out uint payload)
{
    tag = 0u; payload = 0xffffffffu;
    uint declaration; uint indices;
    if (!checked_named_index_base(node, hir_count, token_capacity, cores, payloads,
        visible_declarations, declaration, indices)) return false;
    tag = declaration_tags[declaration];
    payload = declaration_payloads[declaration];
    return checked_index_elements(indices, instance_kinds, element_tags, element_payloads,
        tag, payload);
}

// Match typing publishes declaration references in the same pass. Share the
// traversal and projection with readers while preserving the buffer's access mode.
public bool checked_named_index_reference(uint node, uint hir_count, uint token_capacity,
    StructuredBuffer<HirCore> cores, StructuredBuffer<HirPayload> payloads,
    StructuredBuffer<uint> visible_declarations, RWStructuredBuffer<uint> declaration_tags,
    RWStructuredBuffer<uint> declaration_payloads, StructuredBuffer<uint> instance_kinds,
    StructuredBuffer<uint> element_tags, StructuredBuffer<uint> element_payloads,
    out uint tag, out uint payload)
{
    tag = 0u; payload = 0xffffffffu;
    uint declaration; uint indices;
    if (!checked_named_index_base(node, hir_count, token_capacity, cores, payloads,
        visible_declarations, declaration, indices)) return false;
    tag = declaration_tags[declaration];
    payload = declaration_payloads[declaration];
    return checked_index_elements(indices, instance_kinds, element_tags, element_payloads,
        tag, payload);
}
