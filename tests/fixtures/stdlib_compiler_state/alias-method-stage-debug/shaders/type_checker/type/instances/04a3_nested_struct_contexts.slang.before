import semantic_interface_layout;
// One lane owns each contextualized literal tree. Child literals receive the
// checked field type under the parent's environment before field validation.
// No lane consumes another lane's mutable literal-context output.
import hir_records;
import type_checker.checked_scoped_types;
import type_checker.checked_type_graph;
import type_checker.type.instances.struct_field_lookup;
import status;
import type_checker.dependencies.record_fields;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> struct_field_lookup_state;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
RWStructuredBuffer<uint> struct_lit_context_decl_token;
RWStructuredBuffer<uint> struct_lit_context_instance;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint DEPTH_LIMIT = 64u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint root = dtid.x + dtid.y * 16776960u;
    uint count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (root >= count || compact_hir_core[root].kind != 28u) return;
    uint ancestor = compact_hir_core[root].parent;
    for (uint steps = 0u; ancestor < count && steps < count; steps++)
    {
        if (compact_hir_core[ancestor].kind == 28u) return;
        ancestor = compact_hir_core[ancestor].parent;
    }
    if (struct_lit_context_decl_token[root] >= gParams.n_tokens &&
        !imported_record_fields_available(struct_lit_context_instance[root])) return;
    uint nodes[DEPTH_LIMIT]; uint next[DEPTH_LIMIT]; uint depth = 0u;
    nodes[0u] = root; next[0u] = 0u;
    uint fields = min(compact_field_count[0u], gParams.n_hir_nodes);
    for (;;)
    {
        uint node = nodes[depth];
        HirPayload literal = compact_hir_payload[node];
        uint ordinal = next[depth]; next[depth] = ordinal + 1u;
        if (ordinal >= literal.c || literal.b >= fields || ordinal >= fields - literal.b)
        {
            if (depth == 0u) return;
            depth--; continue;
        }
        HirField value = compact_fields[literal.b + ordinal];
        uint child = value.value;
        if (child >= count || compact_hir_core[child].kind != 28u || value.owner != node ||
            value.name_token >= gParams.n_tokens) continue;
        uint decl = struct_lit_context_decl_token[node];
        uint owner = decl < gParams.n_tokens ? type_decl_hir_node_by_token[decl] : INVALID;
        uint tag; uint payload;
        if (owner < count)
        {
            // An unbound parent header cannot give a child an actual type.
            // Its fields infer independently until the parent has an application.
            if (type_instance_arg_count[decl] != 0u &&
                struct_lit_context_instance[node] >= checked_type_capacity()) continue;
            uint row = struct_field_lookup_find(owner, name_id_by_token[value.name_token],
                fields, gParams.n_tokens, compact_fields, name_id_by_token, struct_field_lookup_state);
            if (row >= fields || compact_fields[row].value >= count) continue;
            uint token = compact_hir_core[compact_fields[row].value].token_start;
            if (token >= gParams.n_tokens) continue;
            if (!checked_scoped_reference(type_expr_ref_tag[token], type_expr_ref_payload[token],
                struct_lit_context_instance[node], gParams.n_tokens, tag, payload)) continue;
        }
        else
        {
            uint name = name_id_by_token[value.name_token];
            if (name >= gParams.n_tokens) continue;
            uint field_ordinal = imported_record_field_ordinal(struct_lit_context_instance[node],
                name_hash_lo[name], name_hash_hi[name]);
            if (field_ordinal == INVALID || !imported_record_field_type(struct_lit_context_instance[node],
                field_ordinal, tag, payload)) continue;
        }
        // Explicit constructor arguments are actual evidence, including a
        // different application of the same declaration. Preserve that type
        // for its own fields; parent field validation checks compatibility.
        uint constructor_token = compact_hir_core[child].token_start;
        if (constructor_token < gParams.n_tokens && type_expr_ref_tag[constructor_token] == 3u &&
            type_expr_ref_payload[constructor_token] < checked_type_capacity())
        {
            tag = 3u;
            payload = type_expr_ref_payload[constructor_token];
        }
        uint child_decl = tag == 3u && payload < checked_type_capacity()
            ? type_instance_decl_token[payload] : tag == 1u && payload >= 4096u ? payload - 4096u : INVALID;
        if (child_decl >= gParams.n_tokens)
        {
            uint constructor = compact_hir_core[child].token_start;
            if (tag != 3u || constructor >= gParams.n_tokens ||
                external_type_library_id[payload] == INVALID) continue;
            if (external_type_library_id[payload] != external_type_library_id[constructor] ||
                external_type_unit_id[payload] != external_type_unit_id[constructor] ||
                external_type_local_index[payload] != external_type_local_index[constructor])
            { record_min_token_error(status, value.name_token, 3u, 0u); continue; }
            // Imported declarations retain stable identities and checked field
            // references independently of their original dependency page.
            struct_lit_context_instance[child] = payload;
        }
        else
        {
            struct_lit_context_decl_token[child] = child_decl;
            struct_lit_context_instance[child] = tag == 3u ? payload : INVALID;
        }
        if (depth + 1u == DEPTH_LIMIT)
        { record_min_token_error(status, value.name_token, 6u, 0x474e0002u); return; }
        depth++; nodes[depth] = child; next[depth] = 0u;
    }
}
