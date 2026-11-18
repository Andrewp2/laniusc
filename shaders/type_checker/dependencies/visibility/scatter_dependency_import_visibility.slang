// Scatter the import/declaration relation after its per-import count scan.
// An item import keeps only the rows of its named declarations, and its name
// takes precedence over module imports in the same module: their rows of that
// name get no owner, so lookups never see them.

import dependency_interface;
import gpu_index;
import status;
import byte_packing;

struct Params
{
    uint declaration_count;
    uint import_capacity;
    uint visible_capacity;
    uint lookup_capacity;
    uint source_len;
    uint path_capacity;
    uint namespace;
    uint hir_capacity;
};

struct NameSpan
{
    uint start;
    uint len;
    uint kind;
    uint token_index;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> import_count_out;
StructuredBuffer<uint> import_status;
StructuredBuffer<uint> import_item_name_id;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
StructuredBuffer<NameSpan> name_spans;
ByteAddressBuffer source_bytes;
ByteAddressBuffer language_symbol_bytes;
StructuredBuffer<uint> import_module_id;
StructuredBuffer<uint> import_target_dependency_module_id;
StructuredBuffer<uint> dependency_visible_count;
StructuredBuffer<uint> dependency_visible_prefix;
StructuredBuffer<uint> dependency_visible_total;
RWStructuredBuffer<uint> dependency_visible_owner_module;
RWStructuredBuffer<uint> dependency_visible_decl;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint IMPORT_IDENTITY_STRIDE = 4u;
static const uint IMPORT_STATUS_OK = 0u;
static const uint NAME_KIND_LANGUAGE_SYMBOL = 3u;
static const uint DECL_WORDS = 14u;
static const uint ERR_NAME_LIMIT = 11u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint active_import_count()
{
    return min(import_count_out[0u], gParams.import_capacity);
}

uint declaration_module(uint declaration_i)
{
    return dependency_declaration_word(declaration_i * DECL_WORDS);
}

uint dependency_name_byte(uint byte_i)
{
    uint word = dependency_name_byte_word(byte_i >> 2u);
    return (word >> ((byte_i & 3u) * 8u)) & 0xffu;
}

uint local_name_byte(NameSpan span, uint byte_i)
{
    return span.kind == NAME_KIND_LANGUAGE_SYMBOL
        ? byte_address_load_u8(language_symbol_bytes, span.start + byte_i)
        : byte_address_load_u8_bounded(source_bytes, span.start + byte_i, gParams.source_len);
}

bool declaration_name_equal(uint name_id, uint declaration_i)
{
    uint base = declaration_i * DECL_WORDS;
    if (dependency_declaration_word(base + 1u) != name_hash_lo[name_id] ||
        dependency_declaration_word(base + 2u) != name_hash_hi[name_id])
        return false;
    NameSpan span = name_spans[name_id];
    uint start = dependency_declaration_word(base + 3u);
    uint len = dependency_declaration_word(base + 4u);
    if (span.len != len || len > 64u)
        return false;
    for (uint byte_i = 0u; byte_i < 64u; byte_i += 1u)
    {
        if (byte_i >= len)
            break;
        if (local_name_byte(span, byte_i) != dependency_name_byte(start + byte_i))
            return false;
    }
    return true;
}

// Whether an item import in `module` names this declaration's name.
bool item_import_names(uint module, uint declaration_i)
{
    uint count = active_import_count();
    for (uint import_i = 0u; import_i < count; import_i += 1u)
    {
        uint item = import_item_name_id[import_i];
        if (item != INVALID && import_module_id[import_i] == module &&
            import_status[import_i] == IMPORT_STATUS_OK &&
            declaration_name_equal(item, declaration_i))
            return true;
    }
    return false;
}

uint import_for_visible_row(uint visible_i)
{
    uint first = 0u;
    uint count = active_import_count();
    while (count != 0u)
    {
        uint step = count >> 1u;
        uint probe = first + step;
        if (dependency_visible_prefix[probe] <= visible_i)
        {
            first = probe + 1u;
            count -= step + 1u;
        }
        else
            count = step;
    }
    return first == 0u ? INVALID : first - 1u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint visible_i = linear_thread_id(dtid);
    uint total = dependency_visible_total[0u];
    if (visible_i == 0u && total > gParams.visible_capacity)
        record_min_token_error(status, 0u, ERR_NAME_LIMIT, total);
    if (visible_i >= min(total, gParams.visible_capacity))
        return;
    uint import_i = import_for_visible_row(visible_i);
    if (import_i == INVALID)
        return;
    uint local_i = visible_i - dependency_visible_prefix[import_i];
    if (local_i >= dependency_visible_count[import_i])
        return;
    uint target = import_target_dependency_module_id[import_i * IMPORT_IDENTITY_STRIDE];
    if (target >= dependency_module_count())
        return;
    uint ordered_i = dependency_module_declaration_start(target) + local_i;
    uint declaration_i = dependency_module_declaration(ordered_i);
    if (declaration_i >= dependency_declaration_count() ||
        declaration_module(declaration_i) != target)
        return;
    uint module = import_module_id[import_i];
    uint item = import_item_name_id[import_i];
    if (item != INVALID ? !declaration_name_equal(item, declaration_i)
                        : item_import_names(module, declaration_i))
        module = INVALID;
    dependency_visible_owner_module[visible_i] = module;
    dependency_visible_decl[visible_i] = declaration_i;
}
