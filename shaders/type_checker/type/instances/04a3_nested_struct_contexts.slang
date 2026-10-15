import semantic_interface_layout;
// One lane owns each contextualized literal tree. Child literals receive the
// checked field type under the parent's environment before field validation.
// No lane consumes another lane's mutable literal-context output.
//
// The walk keeps no stack: a child literal's parent is its nearest literal
// ancestor in the HIR, and the walk resumes the parent after the field row
// whose value is the child. A field type is substituted under the parent's
// application over canonical IDs (ct_scoped_reference).
import hir_records;
import type_checker.mutable_checked_type_graph;
import type_checker.substitution.ct_scoped;
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
static const uint HIR_STRUCT_LITERAL = 28u;
static const uint DEPTH_LIMIT = 64u;

// The nearest struct-literal ancestor of `node` (INVALID: none).
uint literal_parent(uint node, uint count)
{
    uint ancestor = compact_hir_core[node].parent;
    for (uint steps = 0u; ancestor < count && steps < count; steps++)
    {
        if (compact_hir_core[ancestor].kind == HIR_STRUCT_LITERAL) return ancestor;
        ancestor = compact_hir_core[ancestor].parent;
    }
    return INVALID;
}

// The ordinal of the field of `literal` whose value is `child` (INVALID: none).
uint field_ordinal_of(uint literal, uint child, uint fields)
{
    HirPayload payload = compact_hir_payload[literal];
    if (payload.b >= fields) return INVALID;
    uint end = min(payload.c, fields - payload.b);
    for (uint ordinal = 0u; ordinal < end; ordinal++)
    {
        HirField value = compact_fields[payload.b + ordinal];
        if (value.value == child && value.owner == literal) return ordinal;
    }
    return INVALID;
}

// The context a child literal gets from field `value` of `node`; false when
// the parent gives it none (the child keeps its own context and its fields
// are not visited).
bool child_context(uint node, HirField value, uint child, uint count, uint fields)
{
    uint decl = struct_lit_context_decl_token[node];
    uint owner = decl < gParams.n_tokens ? type_decl_hir_node_by_token[decl] : INVALID;
    uint tag; uint payload;
    if (owner < count)
    {
        // An unbound parent header cannot give a child an actual type.
        // Its fields infer independently until the parent has an application.
        if (type_instance_arg_count[decl] != 0u &&
            struct_lit_context_instance[node] >= mutable_type_capacity()) return false;
        uint row = struct_field_lookup_find(owner, name_id_by_token[value.name_token],
            fields, gParams.n_tokens, compact_fields, name_id_by_token, struct_field_lookup_state);
        if (row >= fields || compact_fields[row].value >= count) return false;
        uint token = compact_hir_core[compact_fields[row].value].token_start;
        if (token >= gParams.n_tokens) return false;
        uint failure;
        if (!ct_scoped_reference(type_expr_ref_tag[token], type_expr_ref_payload[token],
            struct_lit_context_instance[node], gParams.n_tokens, tag, payload, failure)) return false;
    }
    else
    {
        uint name = name_id_by_token[value.name_token];
        if (name >= gParams.n_tokens) return false;
        uint field_ordinal = imported_record_field_ordinal(struct_lit_context_instance[node],
            name_hash_lo[name], name_hash_hi[name]);
        if (field_ordinal == INVALID || !imported_record_field_type(struct_lit_context_instance[node],
            field_ordinal, tag, payload)) return false;
    }
    // Explicit constructor arguments are actual evidence, including a
    // different application of the same declaration. Preserve that type
    // for its own fields; parent field validation checks compatibility.
    uint capacity = mutable_type_capacity();
    uint constructor_token = compact_hir_core[child].token_start;
    if (constructor_token < gParams.n_tokens && type_expr_ref_tag[constructor_token] == 3u &&
        type_expr_ref_payload[constructor_token] < capacity)
    {
        tag = 3u;
        payload = type_expr_ref_payload[constructor_token];
    }
    uint child_decl = tag == 3u && payload < capacity
        ? type_instance_decl_token[payload] : tag == 1u && payload >= 4096u ? payload - 4096u : INVALID;
    if (child_decl >= gParams.n_tokens)
    {
        uint constructor = compact_hir_core[child].token_start;
        if (tag != 3u || constructor >= gParams.n_tokens ||
            external_type_library_id[payload] == INVALID) return false;
        if (external_type_library_id[payload] != external_type_library_id[constructor] ||
            external_type_unit_id[payload] != external_type_unit_id[constructor] ||
            external_type_local_index[payload] != external_type_local_index[constructor])
        { record_min_token_error(status, value.name_token, 3u, 0u); return false; }
        // Imported declarations retain stable identities and checked field
        // references independently of their original dependency page.
        struct_lit_context_instance[child] = payload;
    }
    else
    {
        struct_lit_context_decl_token[child] = child_decl;
        struct_lit_context_instance[child] = tag == 3u ? payload : INVALID;
    }
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint root = dtid.x + dtid.y * 16776960u;
    uint count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (root >= count || compact_hir_core[root].kind != HIR_STRUCT_LITERAL) return;
    if (literal_parent(root, count) != INVALID) return;
    if (struct_lit_context_decl_token[root] >= gParams.n_tokens &&
        !imported_record_fields_available(struct_lit_context_instance[root])) return;
    uint fields = min(compact_field_count[0u], gParams.n_hir_nodes);
    uint node = root; uint next = 0u; uint depth = 0u;
    // Each field row is visited once, plus one return per visited child.
    for (uint steps = 0u; steps < 2u * fields + 1u; steps++)
    {
        HirPayload literal = compact_hir_payload[node];
        uint ordinal = next; next = ordinal + 1u;
        if (ordinal >= literal.c || literal.b >= fields || ordinal >= fields - literal.b)
        {
            if (depth == 0u) return;
            // Resume the parent after the field whose value this literal is.
            uint parent = literal_parent(node, count);
            if (parent >= count) return;
            uint resumed = field_ordinal_of(parent, node, fields);
            if (resumed == INVALID) return;
            node = parent; next = resumed + 1u; depth--;
            continue;
        }
        HirField value = compact_fields[literal.b + ordinal];
        uint child = value.value;
        if (child >= count || compact_hir_core[child].kind != HIR_STRUCT_LITERAL || value.owner != node ||
            value.name_token >= gParams.n_tokens) continue;
        if (!child_context(node, value, child, count, fields)) continue;
        // The walk returns through the child's literal ancestor, so it only
        // enters a child whose nearest literal ancestor is this literal.
        if (literal_parent(child, count) != node) continue;
        if (depth + 1u == DEPTH_LIMIT)
        { record_min_token_error(status, value.name_token, 6u, 0x474e0002u); return; }
        depth++; node = child; next = 0u;
    }
}
