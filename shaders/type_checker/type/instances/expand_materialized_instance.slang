import semantic_interface_layout;
// Expand declaration fields and enum payloads of a materialized root.
#if !MATERIALIZE_ROOT_CANDIDATES
#error define MATERIALIZE_ROOT_CANDIDATES before including materialize_application.slang
#endif


bool child_reference(uint instance, uint ordinal, out uint3 reference)
{
    reference = uint3(0u, INVALID, INVALID);
    uint kind = type_instance_kind[instance];
    if (kind == 2u || kind == 3u || kind == 4u)
    {
        if (ordinal != 0u) return false;
        reference = uint3(type_instance_elem_ref_tag[instance], type_instance_elem_ref_payload[instance], INVALID);
        return true;
    }
    if (kind != 1u) return false;
    uint arguments = type_instance_arg_count[instance];
    if (ordinal < arguments)
    {
        uint tag; uint payload;
        MutableCheckedTypeGraph.argument(instance, ordinal, tag, payload);
        reference = uint3(tag, payload, INVALID); return true;
    }
    uint decl = type_instance_decl_token[instance];
    uint owner = decl < gParams.n_tokens ? type_decl_hir_node_by_token[decl] : INVALID;
    if (owner >= hir_count())
    {
        uint declaration = dependency_find_declaration(external_type_library_id[instance],
            external_type_unit_id[instance], external_type_local_index[instance]);
        if (declaration >= dependency_declaration_count()) return false;
        uint declaration_kind = dependency_declaration_word(declaration * 14u + 6u);
        if (declaration_kind != 6u && declaration_kind != 7u) return false;
        uint start = dependency_declaration_word(declaration * 14u + 8u);
        uint count = dependency_declaration_word(declaration * 14u + 9u);
        if (start > dependency_member_count() || count > dependency_member_count() - start) return false;
        uint field = ordinal - arguments;
        for (uint member = start; member < start + count; member++)
        {
            uint member_kind = dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 1u);
            uint type = dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 7u);
            if (declaration_kind == 6u && member_kind == 4u)
            {
                if (field != 0u) { field--; continue; }
                reference = uint3(5u, type, instance);
                return true;
            }
            if (declaration_kind == 7u && member_kind == 5u)
            {
                // Layout depends on every variant, including variants never
                // constructed or destructured in this unit. Expand their full
                // patterns under the enum's accepted argument environment.
                uint signature = canonical_field_root(type);
                if (signature == INVALID || dependency_type_word(signature * 9u) != 7u) return false;
                uint edge_start = dependency_type_word(signature * 9u + 3u);
                uint edge_count = dependency_type_word(signature * 9u + 4u);
                uint edges = dependency_count(5u);
                if (edge_count == 0u || edge_start > edges || edge_count > edges - edge_start) return false;
                uint payloads = edge_count - 1u;
                if (field >= payloads) { field -= payloads; continue; }
                reference = uint3(5u, dependency_type_edge_word(edge_start + field), instance);
                return true;
            }
        }
        return false;
    }
    uint type_node = INVALID;
    if (compact_hir_core[owner].kind == 27u)
    {
        uint total = min(compact_field_count[0u], gParams.n_hir_nodes);
        uint first = first_local_struct_field(compact_hir_core[owner].token_start, total, compact_fields);
        uint row = first + ordinal - arguments;
        if (row >= total || compact_fields[row].owner != owner) return false;
        type_node = compact_fields[row].value;
    }
    else if (compact_hir_core[owner].kind == 26u)
    {
        uint total = min(compact_variant_payload_row_count[0u], gParams.n_hir_nodes);
        uint variants = min(compact_variant_count[0u], gParams.n_hir_nodes);
        uint lo = 0u; uint hi = total;
        while (lo < hi)
        {
            uint mid = lo + (hi - lo) / 2u;
            uint variant = compact_variant_payloads[mid].variant;
            uint payload_owner = variant < variants ? compact_variants[variant].owner : INVALID;
            if (payload_owner < owner) lo = mid + 1u;
            else hi = mid;
        }
        uint row = lo + ordinal - arguments;
        if (row >= total) return false;
        HirVariantPayload field = compact_variant_payloads[row];
        if (field.variant >= variants || compact_variants[field.variant].owner != owner) return false;
        type_node = field.type_node;
    }
    else return false;
    uint token = type_token(type_node);
    if (token >= gParams.n_tokens) return false;
    reference = uint3(type_expr_ref_tag[token], type_expr_ref_payload[token], instance);
    return true;
}


bool expand_materialized_instance<Graph : IScopedTypeGraph>(uint root,
    inout uint created[DEPTH_LIMIT], inout uint created_count, out uint failure)
{
    failure = 0u;
    uint instances[DEPTH_LIMIT]; uint next[DEPTH_LIMIT]; uint depth = 0u;
    uint expanded[DEPTH_LIMIT]; uint expanded_count = 1u;
    expanded[0u] = root;
    instances[0u] = root; next[0u] = 0u;
    for (;;)
    {
        uint3 ref;
        uint ordinal = next[depth]; next[depth] = ordinal + 1u;
        if (!child_reference(instances[depth], ordinal, ref))
        {
            if (depth == 0u) return true;
            depth--; continue;
        }
        uint2 child;
        // A child structurally equal to an expanded row resolves to that row.
        if (!materialize<Graph>(ref, created, created_count, expanded, expanded_count, child, failure))
        {
            return false;
        }
        if (child.x != 3u) continue;
        bool visited = false;
        // A type can occur as an argument and again as a declaration field.
        // Expand the accepted DAG once, rather than revisiting every path.
        for (uint prior = 0u; prior < expanded_count; prior++)
            if (expanded[prior] == child.y) { visited = true; break; }
        if (visited) continue;
        if (depth + 1u == DEPTH_LIMIT || expanded_count == DEPTH_LIMIT)
        {
            failure = 2u; return false;
        }
        expanded[expanded_count++] = child.y;
        depth++; instances[depth] = child.y; next[depth] = 0u;
    }
}
