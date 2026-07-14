// Resolve still-unmatched one-segment paths to canonical dependency identities.

import byte_packing;
import gpu_index;

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
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_name_id;
StructuredBuffer<uint> path_owner_module_id;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
StructuredBuffer<NameSpan> name_spans;
ByteAddressBuffer source_bytes;
ByteAddressBuffer language_symbol_bytes;
StructuredBuffer<uint> dependency_declaration_words;
StructuredBuffer<uint> dependency_name_byte_words;
StructuredBuffer<uint> dependency_visible_owner_module;
StructuredBuffer<uint> dependency_visible_decl;
StructuredBuffer<uint> dependency_visible_lookup;
RWStructuredBuffer<uint> resolved_dependency_decl;
RWStructuredBuffer<uint> resolved_status;

static const uint INVALID = 0xffffffffu;
static const uint DECL_WORDS = 14u;
static const uint NAME_KIND_LANGUAGE_SYMBOL = 3u;
static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED = 2u;
static const uint PATH_RESOLVE_STATUS_AMBIGUOUS_IMPORT = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint mix(uint hash, uint value)
{
    hash ^= value;
    hash *= 16777619u;
    return hash;
}

uint key_hash(uint owner_module, uint namespace_value, uint lo, uint hi)
{
    uint hash = mix(2166136261u, owner_module);
    hash = mix(hash, namespace_value);
    hash = mix(hash, lo);
    return mix(hash, hi);
}

uint dependency_name_byte(uint byte_i)
{
    uint word = dependency_name_byte_words[byte_i >> 2u];
    return (word >> ((byte_i & 3u) * 8u)) & 0xffu;
}

uint local_name_byte(NameSpan span, uint byte_i)
{
    return span.kind == NAME_KIND_LANGUAGE_SYMBOL
        ? byte_address_load_u8(language_symbol_bytes, span.start + byte_i)
        : byte_address_load_u8_bounded(source_bytes, span.start + byte_i, gParams.source_len);
}

bool exact_match(uint name_id, uint owner_module, uint visible_i)
{
    if (dependency_visible_owner_module[visible_i] != owner_module)
        return false;
    uint declaration_i = dependency_visible_decl[visible_i];
    if (declaration_i >= gParams.declaration_count)
        return false;
    uint base = declaration_i * DECL_WORDS;
    if (dependency_declaration_words[base + 5u] != gParams.namespace ||
        dependency_declaration_words[base + 1u] != name_hash_lo[name_id] ||
        dependency_declaration_words[base + 2u] != name_hash_hi[name_id])
        return false;
    NameSpan span = name_spans[name_id];
    uint start = dependency_declaration_words[base + 3u];
    uint len = dependency_declaration_words[base + 4u];
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (path_i >= gParams.path_capacity)
        return;
    resolved_dependency_decl[path_i] = INVALID;
    if (path_i >= min(path_count_out[0u], gParams.path_capacity) ||
        path_segment_count[path_i] != 1u)
        return;
    uint expected_kind = gParams.namespace == 3u
        ? PATH_RECORD_KIND_HIR_TYPE_EXPR
        : PATH_RECORD_KIND_HIR_PATH_EXPR;
    if (path_kind[path_i] != expected_kind ||
        resolved_status[path_i] == PATH_RESOLVE_STATUS_OK)
        return;
    uint owner_module = path_owner_module_id[path_i];
    if (owner_module == INVALID)
        return;
    uint name_id = path_segment_name_id[path_segment_base[path_i]];
    uint mask = gParams.lookup_capacity - 1u;
    uint slot = key_hash(
        owner_module, gParams.namespace, name_hash_lo[name_id], name_hash_hi[name_id]) & mask;
    uint match = INVALID;
    for (uint probe = 0u; probe < gParams.lookup_capacity; probe += 1u)
    {
        uint visible_i = dependency_visible_lookup[slot];
        if (visible_i == INVALID)
            break;
        if (visible_i < gParams.visible_capacity && exact_match(name_id, owner_module, visible_i))
        {
            uint declaration_i = dependency_visible_decl[visible_i];
            if (match != INVALID && match != declaration_i)
            {
                resolved_status[path_i] = PATH_RESOLVE_STATUS_AMBIGUOUS_IMPORT;
                return;
            }
            match = declaration_i;
        }
        slot = (slot + 1u) & mask;
    }
    if (match == INVALID)
    {
        if (resolved_status[path_i] != PATH_RESOLVE_STATUS_OK)
            resolved_status[path_i] = PATH_RESOLVE_STATUS_UNRESOLVED;
        return;
    }
    resolved_dependency_decl[path_i] = match;
    resolved_status[path_i] = PATH_RESOLVE_STATUS_OK;
}
