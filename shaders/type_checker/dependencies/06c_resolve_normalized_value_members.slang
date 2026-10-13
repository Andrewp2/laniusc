#include "normalized_member_lookup.slang"
import byte_packing;
struct NameSpan { uint start; uint len; uint kind; uint token_index; };
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_segment_name_id;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint4> resolved_value_qualifier_binding;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_state;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> external_type_library_id;
StructuredBuffer<uint> external_type_unit_id;
StructuredBuffer<uint> external_type_local_index;
StructuredBuffer<uint> dependency_visible_lookup;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
StructuredBuffer<NameSpan> name_spans;
ByteAddressBuffer source_bytes;
ByteAddressBuffer language_symbol_bytes;
RWStructuredBuffer<uint> resolved_value_status;
RWStructuredBuffer<uint> resolved_value_type_qualifier_token;
RWStructuredBuffer<uint> resolved_dependency_value_library_id;
RWStructuredBuffer<uint> resolved_dependency_value_unit_id;
RWStructuredBuffer<uint> resolved_dependency_value_local_index;
RWStructuredBuffer<uint> module_value_path_status;

bool same_name(uint name, uint declaration)
{
    uint base = declaration * 14u;
    NameSpan span = name_spans[name];
    uint len = dependency_declaration_word(base + 4u);
    if (span.len != len || len > 64u || name_hash_lo[name] != dependency_declaration_word(base + 1u) ||
        name_hash_hi[name] != dependency_declaration_word(base + 2u)) return false;
    uint start = dependency_declaration_word(base + 3u);
    for (uint i = 0u; i < len; i++)
    {
        uint local = span.kind == 3u ? byte_address_load_u8(language_symbol_bytes, span.start + i)
            : byte_address_load_u8_bounded(source_bytes, span.start + i, gParams.source_len);
        uint byte = start + i;
        if (local != ((dependency_name_byte_word(byte >> 2u) >> ((byte & 3u) * 8u)) & 255u)) return false;
    }
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path = dtid.x + dtid.y * 16776960u;
    if (path >= min(path_count_out[0u], gParams.path_capacity) || path_kind[path] != 3u ||
        path_segment_count[path] < 2u || resolved_value_status[path] == 0u || resolved_value_status[path] == 4u) return;
    uint binding = resolved_value_qualifier_binding[path].x;
    if (binding != 1u && binding != 2u) return;
    uint last = path_segment_base[path] + path_segment_count[path] - 1u;
    uint token = path_segment_token[last - 1u];
    uint tokens; uint stride;
    type_expr_ref_tag.GetDimensions(tokens, stride);
    if (token >= tokens || type_expr_ref_tag[token] != 3u) return;
    uint instance = type_expr_ref_payload[token];
    uint capacity;
    type_instance_kind.GetDimensions(capacity, stride);
    if (instance >= capacity || type_instance_kind[instance] != 1u ||
        type_instance_state[instance] != 1u || type_instance_decl_token[instance] != INVALID) return;
    uint parent = dependency_find_declaration(external_type_library_id[instance],
        external_type_unit_id[instance], external_type_local_index[instance]);
    if (parent >= dependency_declaration_count() || dependency_declaration_word(parent * 14u + 6u) != 7u) return;
    uint name = path_segment_name_id[last];
    name_hash_lo.GetDimensions(capacity, stride);
    if (name >= capacity) return;
    uint mask = gParams.lookup_capacity - 1u;
    uint slot = normalized_member_hash(parent, name_hash_lo[name], name_hash_hi[name]) & mask;
    uint match = INVALID;
    for (uint probe = 0u; probe < gParams.lookup_capacity; probe++)
    {
        uint declaration = dependency_visible_lookup[slot];
        if (declaration == INVALID) break;
        if (declaration < dependency_declaration_count() &&
            dependency_declaration_word(declaration * 14u + 10u) == parent && same_name(name, declaration))
        {
            if (match != INVALID && match != declaration)
            {
                resolved_value_status[path] = 4u;
                uint owner = path_owner_token[path];
                if (owner < tokens) module_value_path_status[owner] = 4u;
                return;
            }
            match = declaration;
        }
        slot = (slot + 1u) & mask;
    }
    if (match == INVALID) return;
    resolved_dependency_value_library_id[path] = dependency_declaration_library_id(match);
    resolved_dependency_value_unit_id[path] = dependency_declaration_unit_id(match);
    resolved_dependency_value_local_index[path] = dependency_declaration_local_index(match);
    resolved_value_type_qualifier_token[path] = token;
    resolved_value_status[path] = 0u;
    uint owner = path_owner_token[path];
    if (owner < tokens) module_value_path_status[owner] = 0u;
}
