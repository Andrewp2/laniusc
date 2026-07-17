// GPU record-to-module-id attachment.
//
// Scheduling contract:
// - Dispatch after declaration/import/path records have been scattered and
//   module_id_by_file_id has been populated by GPU module records.
// - Each record fetches the module id for its parser-owned file id.
// - This pass writes owner module-id tables only. It does not resolve
//   declarations, make imports visible, inspect source bytes, use hashes,
//   perform CPU path lookup, or apply same-source shortcuts.

struct Params
{
    // Compact record buffers and dense path-owner ids have distinct domains.
    uint record_capacity;
    uint file_capacity;
    uint hir_node_capacity;
    uint reserved;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_module_file_id;
StructuredBuffer<uint> import_count_out;
StructuredBuffer<uint> import_module_file_id;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_owner_hir;
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> module_id_by_file_id;

RWStructuredBuffer<uint> decl_module_id;
RWStructuredBuffer<uint> import_module_id;
RWStructuredBuffer<uint> path_owner_module_id;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint record_capacity()
{
    return gParams.record_capacity;
}

uint file_capacity()
{
    return gParams.file_capacity == 0u ? gParams.record_capacity : gParams.file_capacity;
}

uint hir_node_capacity()
{
    return gParams.hir_node_capacity;
}

uint active_decl_count()
{
    return min(decl_count_out[0], record_capacity());
}

uint active_import_count()
{
    return min(import_count_out[0], record_capacity());
}

uint active_path_count()
{
    return min(path_count_out[0], record_capacity());
}

uint active_module_count()
{
    return min(module_count_out[0], file_capacity());
}

uint owner_module_from_file(uint file_id)
{
    uint module_id = file_id < file_capacity() ? module_id_by_file_id[file_id] : INVALID;
    if (module_id != INVALID)
        return module_id;
    return file_id == 0u && active_module_count() == 0u ? 0u : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= record_capacity())
        return;

    if (i < active_decl_count())
        decl_module_id[i] = owner_module_from_file(decl_module_file_id[i]);

    if (i < active_import_count())
        import_module_id[i] = owner_module_from_file(import_module_file_id[i]);

    if (i < active_path_count())
    {
        uint owner_hir = path_owner_hir[i];
        uint file_id = owner_hir < min(compact_hir_count[0u], hir_node_capacity())
            ? compact_hir_links[owner_hir].file_id
            : INVALID;
        path_owner_module_id[i] = owner_module_from_file(file_id);
    }
}
