// One lexical selection rule for parameters and callable predicates.
bool body_specialization_selects_owner(uint owner)
{
    uint4 header = body_specialization_inputs[0u];
    bool selected_owner = false;
    bool local_replay = (header.y & 0xc0000000u) == 0x40000000u;
    if (local_replay)
        selected_owner = owner < active_hir_node_count() &&
            compact_hir_core[owner].kind == 3u &&
            compact_hir_core[owner].token_start == (header.y & 0x3fffffffu);
    else if ((header.y & 0x80000000u) == 0u)
        selected_owner = owner < active_hir_node_count() &&
            interface_public_decl_index_by_hir[owner] == header.y;
    else
    {
        uint method = header.y & 0x7fffffffu;
        // A method's environment contains both its own declaration and its
        // enclosing impl. Walk declaration owners, not coincident slot numbers.
        if (method >= active_hir_node_count() || compact_hir_core[method].kind != 3u)
            return false;
        // A headerless method can still own bounds on enclosing parameters.
        // Retain that callable before visiting its parameter-bearing ancestors.
        uint candidate = method;
        for (uint depth = 0u; depth < active_hir_node_count() &&
            candidate < active_hir_node_count(); depth++)
        {
            if (candidate == owner) { selected_owner = true; break; }
            uint parent = compact_hir_core[candidate].parent;
            uint next = parent < active_hir_node_count()
                ? generic_decl_owner_by_node_a[parent] : 0xffffffffu;
            if (next == candidate) break;
            candidate = next;
        }
    }
    return selected_owner;
}
