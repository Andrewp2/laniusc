// The method index of the resident dependency page: two open-address tables
// in one buffer, built on the GPU when the page is loaded
// (type_checker/dependencies/00b and 00c). The first half holds every public
// implementation method and trait requirement by (library, unit, symbol); the
// second half holds every public implementation method by name hash. A call
// probes its own slot run and not every member of the page.
import dependency_interface;
import semantic_interface_layout;

StructuredBuffer<uint> dependency_method_lookup;

// Slots of one table: a power of two, at least twice the page's members.
uint dependency_method_lookup_capacity()
{
    uint length; uint stride;
    dependency_method_lookup.GetDimensions(length, stride);
    return dependency_member_count() == 0u ? 0u : length >> 1u;
}

// The member in probe `probe` of the name table run that starts at `hash`;
// 0xffffffff ends the run. Rows of other names share runs: the caller
// compares the name.
uint dependency_method_named(uint hash, uint probe)
{
    uint capacity = dependency_method_lookup_capacity();
    if (probe >= capacity) return 0xffffffffu;
    return dependency_method_lookup[capacity + ((hash + probe) & (capacity - 1u))];
}

// Only public implementation methods use their lexical interface symbol as
// their native target. Private trait methods require their explicit binding;
// this direct-call lookup must not create a public alias for that symbol.
// A trait's required member is found by the same identity; its signature
// serves calls through a bound, never a native call.
uint dependency_find_method(uint library_id, uint unit_id, uint method_symbol)
{
    if (method_symbol == 0xffffffffu || (method_symbol & 0xc0000000u) != 0x80000000u)
        return 0xffffffffu;
    uint capacity = dependency_method_lookup_capacity();
    uint hash = dependency_method_identity_hash(library_id, unit_id, method_symbol);
    uint found = 0xffffffffu;
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint row = dependency_method_lookup[(hash + probe) & (capacity - 1u)];
        if (row == 0xffffffffu) break;
        uint base = row * SEMANTIC_INTERFACE_MEMBER_WORDS;
        if (dependency_member_word(base + 9u) != method_symbol ||
            (!dependency_public_implementation_method(row) &&
             !dependency_trait_requirement(row))) continue;
        uint library; uint unit; uint local;
        if (!dependency_contract_owner_identity(dependency_member_word(base), library, unit, local) ||
            library != library_id || unit != unit_id) continue;
        if (found != 0xffffffffu) return 0xffffffffu;
        found = row;
    }
    return found;
}

uint dependency_callable_return_type(uint library, uint unit, uint symbol)
{
    uint declaration = dependency_find_declaration(library, unit, symbol);
    if (declaration != 0xffffffffu)
    {
        uint signature = dependency_declaration_word(declaration * 14u + 7u);
        if (signature >= dependency_type_count()) return 0xffffffffu;
        uint base = signature * 9u;
        uint count = dependency_type_word(base + 4u);
        uint start = dependency_type_word(base + 3u);
        uint edges = dependency_count(5u);
        if (dependency_type_word(base) != 7u || count == 0u || start > edges || count > edges - start)
            return 0xffffffffu;
        return dependency_type_edge_word(start + count - 1u);
    }
    uint method = dependency_find_method(library, unit, symbol);
    return method == 0xffffffffu ? 0xffffffffu : dependency_member_word(method * SEMANTIC_INTERFACE_MEMBER_WORDS + 7u);
}

