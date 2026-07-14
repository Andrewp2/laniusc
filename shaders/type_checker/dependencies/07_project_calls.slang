// Resolve unqualified call names through dependency visibility and project
// canonical function arity/return metadata into the existing call pipeline.
// Persisted declaration identity remains explicit in call_dependency_decl.

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
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> module_id_by_file_id;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
StructuredBuffer<NameSpan> name_spans;
ByteAddressBuffer source_bytes;
ByteAddressBuffer language_symbol_bytes;
StructuredBuffer<uint> dependency_declaration_words;
StructuredBuffer<uint> dependency_type_words;
StructuredBuffer<uint> dependency_type_edge_words;
StructuredBuffer<uint> canonical_type_roots;
StructuredBuffer<uint> dependency_name_byte_words;
StructuredBuffer<uint> dependency_visible_owner_module;
StructuredBuffer<uint> dependency_visible_decl;
StructuredBuffer<uint> dependency_visible_lookup;
RWStructuredBuffer<uint> call_dependency_decl;
RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_param_count;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint DECL_WORDS = 14u;
static const uint TYPE_WORDS = 9u;
static const uint NAME_KIND_LANGUAGE_SYMBOL = 3u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint INTERFACE_TYPE_SCALAR = 1u;
static const uint INTERFACE_TYPE_FUNCTION = 7u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint VALUE_NAMESPACE = 2u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_hir_count()
{
    return gParams.hir_capacity == 0u ? 0u : min(gParams.hir_capacity, hir_status[5u]);
}

uint mix(uint hash, uint value)
{
    hash ^= value;
    hash *= 16777619u;
    return hash;
}

uint key_hash(uint owner_module, uint lo, uint hi)
{
    uint hash = mix(2166136261u, owner_module);
    hash = mix(hash, VALUE_NAMESPACE);
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
    if (dependency_declaration_words[base + 5u] != VALUE_NAMESPACE ||
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

uint find_declaration(uint name_id, uint owner_module)
{
    uint mask = gParams.lookup_capacity - 1u;
    uint slot = key_hash(owner_module, name_hash_lo[name_id], name_hash_hi[name_id]) & mask;
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
                return INVALID;
            match = declaration_i;
        }
        slot = (slot + 1u) & mask;
    }
    return match;
}

uint scalar_type(uint type_i)
{
    type_i = canonical_type_roots[type_i];
    uint base = type_i * TYPE_WORDS;
    return dependency_type_words[base] == INTERFACE_TYPE_SCALAR
        ? dependency_type_words[base + 1u]
        : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call_node = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (call_node >= active_hir_count() || hir_kind[call_node] != HIR_CALL_EXPR)
        return;
    uint callee_node = hir_call_callee_node[call_node];
    if (callee_node >= active_hir_count() || hir_kind[callee_node] == HIR_MEMBER_EXPR)
        return;
    uint callee_token = hir_token_pos[callee_node];
    if (callee_token >= gParams.visible_capacity)
        return;
    call_dependency_decl[callee_token] = INVALID;
    uint file_i = token_file_id[callee_token];
    uint owner_module = module_id_by_file_id[file_i];
    uint name_id = name_id_by_token[callee_token];
    if (owner_module == INVALID || name_id == INVALID)
        return;
    uint declaration_i = find_declaration(name_id, owner_module);
    if (declaration_i == INVALID)
        return;
    uint declaration_base = declaration_i * DECL_WORDS;
    uint signature_i = dependency_declaration_words[declaration_base + 7u];
    uint signature_base = signature_i * TYPE_WORDS;
    if (dependency_type_words[signature_base] != INTERFACE_TYPE_FUNCTION)
        return;
    uint first_edge = dependency_type_words[signature_base + 3u];
    uint edge_count = dependency_type_words[signature_base + 4u];
    if (edge_count == 0u)
        return;
    uint return_type_i = dependency_type_edge_words[first_edge + edge_count - 1u];
    uint return_root = canonical_type_roots[return_type_i];
    uint return_type = scalar_type(return_type_i);
    call_dependency_decl[callee_token] = declaration_i;
    call_fn_index[callee_token] = callee_token;
    call_param_count[callee_token] = edge_count - 1u;
    call_return_type[callee_token] = return_type;
    if (return_type == 0u)
    {
        decl_type_ref_tag[callee_token] = TYPE_REF_EXTERNAL_CANONICAL;
        decl_type_ref_payload[callee_token] = return_root;
        call_return_type_token[callee_token] = callee_token;
    }
    else
    {
        call_return_type_token[callee_token] = INVALID;
    }
}
