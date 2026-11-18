import semantic_interface_layout;
// Publish checked field ranges for local and imported nominal applications.
// Imported ranges outlive their declaration page. Native lowering consumes
// these facts instead of substituting fields under the receiver again.
// This pass consumes widths after their producer finishes; it never evaluates
// layout from syntax or another lane's partially published type rows.
import hir_records;
import gpu_index;
import type_checker.dependencies.record_fields;
import type_checker.checked_canonical;
import type_checker.checked_type_graph;
import type_checker.local_struct_layout;
import type_checker.native_nominal_identity;

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
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> member_result_context_instance;
StructuredBuffer<uint> member_result_field_ordinal;
StructuredBuffer<uint> type_native_word_count;
StructuredBuffer<uint> type_native_scalar_identity;
RWStructuredBuffer<uint> semantic_member_field_word_offset_by_hir;
RWStructuredBuffer<uint> semantic_member_field_word_count_by_hir;

static const uint INVALID = 0xffffffffu;

uint type_head_token(uint node)
{
    uint path = path_id_by_owner_hir[node];
    if (path < min(path_count_out[0u], gParams.n_hir_nodes))
    {
        uint count = path_segment_count[path];
        uint row = count != 0u ? path_segment_base[path] + count - 1u : INVALID;
        if (row < gParams.n_tokens && path_segment_token[row] < gParams.n_tokens)
            return path_segment_token[row];
    }
    return compact_hir_core[node].token_start;
}

uint checked_words(uint tag, uint payload)
{
    if (tag == 3u && payload < checked_type_capacity()) return type_native_word_count[payload];
    if (tag != 1u) return INVALID;
    if (payload != 0u && payload < 128u) return payload == 7u ? 2u : 1u;
    uint token = native_nominal_token(payload, gParams.n_tokens, type_native_scalar_identity);
    return token != INVALID ? type_native_word_count[token] : INVALID;
}

bool field_type(uint instance, uint ordinal, out uint tag, out uint payload)
{
    tag = 0u; payload = INVALID;
    if (instance >= checked_type_capacity() || type_instance_kind[instance] != 1u) return false;
    uint declaration = type_instance_decl_token[instance];
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint owner = declaration < gParams.n_tokens ? type_decl_hir_node_by_token[declaration] : INVALID;
    if (owner < hir_count && compact_hir_core[owner].kind == 27u)
    {
        uint count = min(compact_field_count[0u], gParams.n_hir_nodes);
        uint start = first_local_struct_field(compact_hir_core[owner].token_start, count, compact_fields);
        if (start >= count || ordinal >= count - start) return false;
        HirField field = compact_fields[start + ordinal];
        if (field.owner != owner || field.ordinal != ordinal || field.value >= hir_count) return false;
        uint token = type_head_token(field.value);
        if (token >= gParams.n_tokens) return false;
        tag = type_expr_ref_tag[token]; payload = type_expr_ref_payload[token];
        return canonical_checked_scoped_reference<LateIds>(tag, payload, instance, gParams.n_tokens, tag, payload);
    }
    return imported_record_field_type(instance, ordinal, tag, payload);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, 16776960u);
    if (node >= gParams.n_hir_nodes) return;
    semantic_member_field_word_offset_by_hir[node] = INVALID;
    semantic_member_field_word_count_by_hir[node] = INVALID;
    if (node >= min(compact_hir_count[0u], gParams.n_hir_nodes) ||
        compact_hir_core[node].kind != 21u) return;
    uint token = compact_hir_payload[node].c;
    if (token >= gParams.n_tokens) return;
    uint instance = member_result_context_instance[token];
    uint ordinal = member_result_field_ordinal[token];
    if (ordinal == INVALID || ordinal >= gParams.n_hir_nodes) return;
    uint offset = 0u;
    for (uint field = 0u; field <= ordinal; field++)
    {
        uint tag; uint payload;
        if (!field_type(instance, field, tag, payload)) return;
        uint words = checked_words(tag, payload);
        if (words == INVALID || offset >= INVALID - words) return;
        if (field == ordinal)
        {
            semantic_member_field_word_offset_by_hir[node] = offset;
            semantic_member_field_word_count_by_hir[node] = words;
            return;
        }
        offset += words;
    }
}
