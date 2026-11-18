// Which local declarations mark_hidden_interface_declarations put in the hidden partition. Shared by
// count_hidden_interface_declarations and publish_hidden_interface_declarations; included after their buffers.
static const uint INVALID = 0xffffffffu;
static const uint MARK = 0x80000000u;
static const uint KIND_ENUM_VARIANT = 9u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LANES = 256u;

uint decl_capacity()
{
    uint count; uint stride;
    interface_public_decl_index_by_local.GetDimensions(count, stride);
    return count;
}

uint active_decls() { return min(decl_count_out[0u], decl_capacity()); }

// A hidden entry is still marked, or publish_hidden_interface_declarations has given it an index
// after the public partition, which stays below `public_count`.
bool hidden_entry(uint entry, uint public_count)
{
    return entry != INVALID && (entry >= MARK || entry >= public_count);
}

// The variants of a hidden enum are hidden with it.
bool hidden_flag(uint local, uint decls, uint public_count)
{
    if (local >= decls) return false;
    uint entry = interface_public_decl_index_by_local[local];
    if (hidden_entry(entry, public_count)) return true;
    uint parent = decl_parent_type_decl[local];
    return entry == INVALID && decl_kind[local] == KIND_ENUM_VARIANT && parent < decls &&
        hidden_entry(interface_public_decl_index_by_local[parent], public_count);
}
