// Row facts of the execution rows (instance_exec.slang): one lane per
// instance table row, after selection and before the layout. A row whose
// environment realizes a nominal scalar gets that declaration's token, as
// 01_expression_refs derives it. A member row of
// a pending entry whose receiver the environment changes gets the field's
// word offset and width under the realized receiver, as 01d_member_layout
// derives them for the job's own rows (the field's type substituted under
// the receiver instance). An entry with a member whose layout does not
// derive here replays (EX_REJECT_FACT), and so does one with a struct
// literal whose realized struct has an application-typed field
// (literal_fields_resolve), or a raw view whose realized element has no
// native width (view_stride_resolves). A method call's callee member names
// no field and needs no layout. Every other row is marked INVALID: its copy
// keeps the template's member facts.
import hir_records;
import gpu_index;
import checked_semantic_artifact;
import type_checker.dependencies.record_fields;
import type_checker.checked_canonical;
import type_checker.checked_type_graph;
import type_checker.local_struct_layout;
import type_checker.native_nominal_identity;
import type_checker.closure.instance_table;
import type_checker.closure.instance_exec;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> type_native_word_count;
StructuredBuffer<uint> type_native_scalar_identity;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> semantic_member_field_ordinal_by_hir;
StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_CALL_EXPR = 19u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint INTRINSIC_I32_SLICE_FROM_RAW_PARTS = 4u;
static const uint INTRINSIC_TYPED_SLICE_FROM_RAW_PARTS = 7u;
static const uint INTRINSIC_SLICE_FROM_STORAGE = 16u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_STRUCT = 1u;
static const uint TYPE_INSTANCE_REFERENCE = 4u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

// The declaration token of the nominal scalar type id `payload`, as
// 01_expression_refs reads it; INVALID for a primitive.
uint scalar_nominal_decl_token(uint payload)
{
    uint tokens; uint stride;
    type_decl_hir_node_by_token.GetDimensions(tokens, stride);
    uint hir_rows; compact_hir_core.GetDimensions(hir_rows, stride);
    if (payload >= TY_ENUM_BASE && payload - TY_ENUM_BASE < tokens)
    {
        uint declaration = type_decl_hir_node_by_token[payload - TY_ENUM_BASE];
        if (declaration < hir_rows && compact_hir_core[declaration].kind == HIR_ENUM_ITEM)
            return payload - TY_ENUM_BASE;
    }
    if (payload >= TY_STRUCT_BASE && payload - TY_STRUCT_BASE < tokens)
    {
        uint declaration = type_decl_hir_node_by_token[payload - TY_STRUCT_BASE];
        if (declaration < hir_rows && compact_hir_core[declaration].kind == HIR_STRUCT_ITEM)
            return payload - TY_STRUCT_BASE;
    }
    return INVALID;
}

// As 01d_member_layout.
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

// The struct instance a member of a receiver of type (tag, payload) reads:
// the receiver's, or through one reference.
uint receiver_struct(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || payload >= checked_type_capacity()) return INVALID;
    uint kind = type_instance_kind[payload];
    if (kind == TYPE_INSTANCE_STRUCT) return payload;
    if (kind != TYPE_INSTANCE_REFERENCE || type_instance_elem_ref_tag[payload] != TYPE_REF_INSTANCE)
        return INVALID;
    uint element = type_instance_elem_ref_payload[payload];
    return element < checked_type_capacity() && type_instance_kind[element] == TYPE_INSTANCE_STRUCT
        ? element : INVALID;
}

void reject(uint entry)
{
    ex_set_quad(entry, EX_Q_HEAD, uint4(EX_REJECT_FACT, 0u, 0u, 0u));
}

// Whether lowering can lay out a literal of local struct instance
// `instance` that this environment realized. Lowering resolves each
// field's declared type under the instance to an existing type row
// (aggregate_elements.slang); a field whose declared type is an
// application, such as the `[T]` of `View<T>`, may substitute to one that
// no row of the job names (`[u32]`), so such a literal replays.
bool literal_fields_resolve(uint instance)
{
    if (instance >= checked_type_capacity() || type_instance_kind[instance] != TYPE_INSTANCE_STRUCT) return true;
    uint declaration = type_instance_decl_token[instance];
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint owner = declaration < gParams.n_tokens ? type_decl_hir_node_by_token[declaration] : INVALID;
    if (owner >= hir_count || compact_hir_core[owner].kind != HIR_STRUCT_ITEM) return true;
    uint count = min(compact_field_count[0u], gParams.n_hir_nodes);
    uint start = first_local_struct_field(compact_hir_core[owner].token_start, count, compact_fields);
    for (uint index = start; index < count && compact_fields[index].owner == owner; index++)
    {
        uint value = compact_fields[index].value;
        if (value >= hir_count || semantic_expr_ref_tag_by_hir[value] == TYPE_REF_INSTANCE) return false;
    }
    return true;
}

// Whether lowering can publish the stride of a raw view (slice_from_raw_parts,
// slice_from_storage) of realized type (tag, payload): it reads the element's
// native width (materialize.slang), which 01c derives only for a type whose
// field types are rows of the job. A realized element without one, such as
// `Node<i32, i32>` whose field `Entry<K, V>` substitutes to an instance no row
// names, replays.
bool view_stride_resolves(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || payload >= checked_type_capacity() ||
        type_instance_kind[payload] != TYPE_INSTANCE_SLICE)
        return true;
    uint element_tag = type_instance_elem_ref_tag[payload];
    uint element = type_instance_elem_ref_payload[payload];
    return element_tag != TYPE_REF_INSTANCE || checked_words(element_tag, element) != INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint rows = instance_table_counts[IT_COUNT_FLAGS] != 0u ? 0u
        : min(instance_table_counts[IT_COUNT_ROWS], it_row_capacity());
    if (row >= rows) return;
    instance_exec_row_facts[row] = uint4(INVALID, INVALID, INVALID, 0u);
    uint entries = min(min(instance_table_counts[IT_COUNT_ENTRIES], IT_RANK_LIMIT), ex_entry_capacity());
    uint entry = it_entry_of_row(row, entries);
    if (entry >= entries || ex_quad(entry, EX_Q_HEAD).x != EX_PENDING) return;
    uint4 key = instance_table[2u * entry];
    uint source = key.x + (row - key.w);
    uint2 own = instance_row_refs[row];
    uint nominal = own.x - 1u == TYPE_REF_SCALAR ? scalar_nominal_decl_token(own.y) : INVALID;
    instance_exec_row_facts[row] = uint4(INVALID, INVALID, nominal, 0u);
    if (compact_hir_core[source].kind == HIR_STRUCT_LITERAL_EXPR)
    {
        uint tag = own.x - 1u;
        bool changed = tag != semantic_expr_ref_tag_by_hir[source] || own.y != semantic_expr_ref_payload_by_hir[source];
        if (changed && tag == TYPE_REF_INSTANCE && !literal_fields_resolve(own.y)) reject(entry);
        return;
    }
    if (compact_hir_core[source].kind == HIR_CALL_EXPR)
    {
        uint intrinsic = semantic_calls_by_hir[source].intrinsic_tag;
        bool view = intrinsic == INTRINSIC_I32_SLICE_FROM_RAW_PARTS ||
            intrinsic == INTRINSIC_TYPED_SLICE_FROM_RAW_PARTS || intrinsic == INTRINSIC_SLICE_FROM_STORAGE;
        if (view && !view_stride_resolves(own.x - 1u, own.y)) reject(entry);
        return;
    }
    if (compact_hir_core[source].kind != HIR_MEMBER_EXPR) return;
    // A method call's callee names no field: the call's route and the
    // receiver's realized type are what lowering reads.
    uint name = compact_hir_payload[source].c;
    if (name < gParams.n_tokens && method_call_name_id[name] != INVALID) return;
    // Selection checked that the receiver is a row of the subtree.
    uint receiver = compact_hir_payload[source].b;
    uint2 realized = instance_row_refs[key.w + (receiver - key.x)];
    uint tag = realized.x - 1u;
    if (tag == semantic_expr_ref_tag_by_hir[receiver] && realized.y == semantic_expr_ref_payload_by_hir[receiver])
        return;
    uint instance = receiver_struct(tag, realized.y);
    uint ordinal = semantic_member_field_ordinal_by_hir[source];
    if (instance == INVALID || ordinal >= gParams.n_hir_nodes)
    {
        reject(entry);
        return;
    }
    uint offset = 0u;
    for (uint field = 0u; field <= ordinal; field++)
    {
        uint field_tag; uint field_payload;
        uint words = field_type(instance, field, field_tag, field_payload)
            ? checked_words(field_tag, field_payload) : INVALID;
        if (words == INVALID || offset >= INVALID - words)
        {
            reject(entry);
            return;
        }
        if (field == ordinal)
        {
            instance_exec_row_facts[row] = uint4(offset, words, nominal, 0u);
            return;
        }
        offset += words;
    }
}
