// Execution rows (instance_exec.slang): one lane per virtual HIR row. The
// lane copies its template row's compact HIR, the row-keyed HIR relations
// lowering reads, and the row's checked semantic facts, remapping every row,
// token and side-table index of the template subtree to the copy's.
//
// The facts an environment changes come from the instance table: the row's
// realized expression reference, and, derived from it as the artifact
// projection derives them (00_project, 01_expression_refs), the aggregate
// declaration and width, the scalar machine type and the legacy value type.
// A call keeps the template's checked record with the realized result; its
// callee is the template's (08_exec_select admits no other call). The
// function row gets the realized return width and no interface index: its
// native symbol is private to this job (0x40000000 | its first token).
import primitive_types;
import hir_records;
import checked_semantic_artifact;
import type_checker.closure.instance_table;
import type_checker.closure.instance_exec;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<HirCore> compact_hir_core;
RWStructuredBuffer<HirLinks> compact_hir_links;
RWStructuredBuffer<HirPayload> compact_hir_payload;
RWStructuredBuffer<uint> compact_fn_return_type;
RWStructuredBuffer<uint> compact_const_value;
RWStructuredBuffer<uint> compact_hir_expr_parent;
RWStructuredBuffer<uint> compact_hir_expr_root;
RWStructuredBuffer<uint> compact_hir_nearest_loop;
RWStructuredBuffer<HirRange> compact_param_ranges;
RWStructuredBuffer<HirRange> compact_generic_param_ranges;
RWStructuredBuffer<uint> compact_array_element_start;
RWStructuredBuffer<uint> compact_array_element_count;
RWStructuredBuffer<uint> semantic_value_decl_by_hir;
RWStructuredBuffer<uint> semantic_value_type_by_hir;
RWStructuredBuffer<uint2> semantic_value_const_by_hir;
RWStructuredBuffer<uint> semantic_value_const_present_by_hir;
RWStructuredBuffer<uint> semantic_argument_mode_by_hir;
RWStructuredBuffer<uint> semantic_enclosing_fn_by_hir;
RWStructuredBuffer<uint> semantic_function_return_type_by_hir;
RWStructuredBuffer<uint> semantic_function_entrypoint_by_hir;
RWStructuredBuffer<uint> semantic_function_host_service_by_hir;
RWStructuredBuffer<uint> semantic_function_native_abi_by_hir;
RWStructuredBuffer<uint> semantic_control_depth_by_hir;
RWStructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
RWStructuredBuffer<uint> semantic_call_native_abi_by_hir;
RWStructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
RWStructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
RWStructuredBuffer<uint> semantic_aggregate_decl_token_by_hir;
RWStructuredBuffer<uint> semantic_aggregate_word_count_by_hir;
RWStructuredBuffer<uint> semantic_array_length_by_hir;
RWStructuredBuffer<uint> semantic_member_field_ordinal_by_hir;
RWStructuredBuffer<uint> semantic_member_field_word_offset_by_hir;
RWStructuredBuffer<uint> semantic_member_field_word_count_by_hir;
RWStructuredBuffer<uint> semantic_iterable_kind_by_hir;
RWStructuredBuffer<uint> semantic_function_result_word_count_by_hir;
RWStructuredBuffer<uint> semantic_expr_scalar_type_by_hir;
RWStructuredBuffer<uint> public_decl_index_by_hir;
StructuredBuffer<uint> type_native_word_count;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;
static const uint HIR_TYPE = 5u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint HIR_TRY_EXPR = 36u;
static const uint STMT_LET = 1u;
static const uint STMT_RETURN = 2u;
static const uint STMT_IF = 3u;
static const uint STMT_CONST = 4u;
static const uint STMT_ASSIGN = 5u;
static const uint STMT_WHILE = 6u;
static const uint STMT_FOR = 7u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_STRING = 28u;
static const uint HIR_EXPR_CHAR = 29u;
static const uint CONTEXT_STMT_BIT = 0x80000000u;
static const uint CONTEXT_ID_MASK = 0x7fffffffu;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

bool valid_instance(uint instance)
{
    uint rows; uint stride;
    type_instance_kind.GetDimensions(rows, stride);
    return instance < rows;
}

// A statement's payload (core.slang: stmt_kind branch).
HirPayload stmt_payload(ExecMap map, HirPayload p)
{
    if (p.a == STMT_LET || p.a == STMT_CONST || p.a == STMT_FOR)
    {
        p.b = ex_token(map, p.b);
        p.c = ex_row(map, p.c);
        p.d = ex_row(map, p.d);
    }
    else if (p.a == STMT_RETURN)
    {
        p.b = ex_row(map, p.b);
        p.d = ex_token(map, p.d);
    }
    else if (p.a == STMT_ASSIGN)
    {
        p.b = ex_row(map, p.b);
        p.c = ex_row(map, p.c);
    }
    else if (p.a == STMT_IF || p.a == STMT_WHILE)
    {
        p.b = ex_row(map, p.b);
        p.c = ex_row(map, p.c);
        p.d = ex_row(map, p.d);
    }
    return p;
}

uint context(ExecMap map, uint encoded)
{
    uint id = encoded & CONTEXT_ID_MASK;
    if (id == CONTEXT_ID_MASK) return encoded;
    return (encoded & CONTEXT_STMT_BIT) | (ex_row(map, id) & CONTEXT_ID_MASK);
}

// The remapped payload of template row `row` (core.slang: the branches
// that wrote it, then the side-table scatters that filled b/c).
HirPayload payload_of(ExecMap map, uint row, HirCore core, HirPayload p)
{
    if (row == map.function)
    {
        // A function's payload: item kind, name token, namespace, visibility.
        p.b = ex_token(map, p.b);
        return p;
    }
    if (core.kind == HIR_PARAM)
    {
        p.a = ex_row(map, p.a);
        p.c = ex_token(map, p.c);
        p.d = ex_row(map, p.d);
        return p;
    }
    if (core.kind == HIR_TYPE)
    {
        p.b = ex_row(map, p.b);
        p.c = ex_token(map, p.c);
        p.d = ex_row(map, p.d);
        return p;
    }
    if (core.kind == HIR_STMT || core.kind == HIR_LET_STMT || core.kind == HIR_RETURN_STMT ||
        core.kind == HIR_IF_STMT || core.kind == HIR_WHILE_STMT || core.kind == HIR_BREAK_STMT ||
        core.kind == HIR_CONTINUE_STMT || core.kind == HIR_FOR_STMT)
        return stmt_payload(map, p);
    if (core.kind == HIR_CALL_EXPR)
    {
        p.a = ex_row(map, p.a);
        p.b = ex_index(map, EX_TABLE_CALL_ARGS, p.b);
        p.d = context(map, p.d);
        return p;
    }
    if (core.kind == HIR_INDEX_EXPR || core.kind == HIR_TRY_EXPR)
    {
        p.b = ex_row(map, p.b);
        p.c = ex_row(map, p.c);
        p.d = ex_token(map, p.d);
        return p;
    }
    if (core.kind == HIR_MEMBER_EXPR)
    {
        p.b = ex_row(map, p.b);
        p.c = ex_token(map, p.c);
        p.d = ex_token(map, p.d);
        return p;
    }
    if (core.kind == HIR_ARRAY_EXPR)
    {
        p.b = ex_row(map, p.b);
        p.c = ex_token(map, p.c);
        p.d = context(map, p.d);
        return p;
    }
    if (core.kind == HIR_STRUCT_LITERAL_EXPR)
    {
        p.b = ex_index(map, EX_TABLE_FIELDS, p.b);
        p.d = context(map, p.d);
        return p;
    }
    if (core.kind == HIR_MATCH_EXPR)
    {
        p.a = ex_row(map, p.a);
        p.b = ex_index(map, EX_TABLE_MATCH_ARMS, p.b);
        return p;
    }
    if (p.a == 0u) return p;
    // Every other expression: (form, operand rows, value token), with
    // literal words in place of operands.
    if (p.a == HIR_EXPR_INT || p.a == HIR_EXPR_CHAR)
    {
        p.d = ex_token(map, p.d);
        return p;
    }
    if (p.a == HIR_EXPR_FLOAT) return p;
    if (p.a == HIR_EXPR_STRING && core.kind == HIR_LITERAL_EXPR)
    {
        p.b = ex_index(map, EX_TABLE_STRINGS, p.b);
        p.c = ex_row(map, p.c);
        p.d = ex_token(map, p.d);
        return p;
    }
    if (core.kind != 22u) p.b = ex_row(map, p.b);
    p.c = ex_row(map, p.c);
    p.d = ex_token(map, p.d);
    return p;
}

// The words a value of checked type (tag, payload) occupies, as the
// return-width projection reads them; INVALID when unknown.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = instance_exec_counts[EX_COUNT_HIR] + dtid.x + dtid.y * 16776960u;
    uint entry = ex_entry_of_row(row);
    if (entry == EX_INVALID) return;
    ExecMap map = ex_map(entry);
    uint source = ex_template_row(map, row);

    HirCore core = compact_hir_core[source];
    HirLinks links = compact_hir_links[source];
    HirPayload payload = compact_hir_payload[source];
    HirCore copy_core = core;
    copy_core.parent = row == map.vrow ? core.parent : ex_row(map, core.parent);
    copy_core.token_start = ex_token(map, core.token_start);
    copy_core.token_end = ex_token_end(map, core.token_end);
    HirLinks copy_links = links;
    copy_links.first_child = ex_row(map, links.first_child);
    copy_links.next_sibling = row == map.vrow ? INVALID : ex_row(map, links.next_sibling);
    copy_links.subtree_end = ex_boundary(map, links.subtree_end);
    compact_hir_core[row] = copy_core;
    compact_hir_links[row] = copy_links;
    compact_hir_payload[row] = payload_of(map, source, core, payload);

    compact_fn_return_type[row] = ex_row(map, compact_fn_return_type[source]);
    compact_const_value[row] = ex_row(map, compact_const_value[source]);
    compact_hir_expr_parent[row] = ex_row(map, compact_hir_expr_parent[source]);
    compact_hir_expr_root[row] = ex_row(map, compact_hir_expr_root[source]);
    compact_hir_nearest_loop[row] = ex_row(map, compact_hir_nearest_loop[source]);
    HirRange params = compact_param_ranges[source];
    if (params.count != 0u) params.start = ex_index(map, EX_TABLE_PARAMS, params.start);
    compact_param_ranges[row] = params;
    HirRange generics = compact_generic_param_ranges[source];
    generics.count = 0u;
    compact_generic_param_ranges[row] = generics;
    uint elements = compact_array_element_count[source];
    compact_array_element_start[row] = elements != 0u
        ? ex_index(map, EX_TABLE_ARRAY_ELEMENTS, compact_array_element_start[source])
        : compact_array_element_start[source];
    compact_array_element_count[row] = elements;

    uint2 template_ref = uint2(semantic_expr_ref_tag_by_hir[source], semantic_expr_ref_payload_by_hir[source]);
    uint4 facts = instance_exec_row_facts[map.base + (source - map.function)];
    uint2 reference = ex_row_ref(map, source);
    if (reference.x == EX_INVALID) reference = template_ref;
    bool changed = any(reference != template_ref);

    semantic_value_decl_by_hir[row] = ex_token(map, semantic_value_decl_by_hir[source]);
    uint value_type = semantic_value_type_by_hir[source];
    uint scalar_type = semantic_expr_scalar_type_by_hir[source];
    uint aggregate_decl = ex_token(map, semantic_aggregate_decl_token_by_hir[source]);
    uint aggregate_words = semantic_aggregate_word_count_by_hir[source];
    if (changed)
    {
        // 00_project: a checked scalar, an array of scalars and a reference
        // override the legacy value type.
        if (reference.x == TYPE_REF_SCALAR) value_type = reference.y;
        else if (reference.x == TYPE_REF_INSTANCE && valid_instance(reference.y))
        {
            uint kind = type_instance_kind[reference.y];
            if (kind == 2u && type_instance_elem_ref_tag[reference.y] == TYPE_REF_SCALAR)
                value_type = 128u + type_instance_elem_ref_payload[reference.y];
            else if (kind == 4u) value_type = SCALAR_PTR;
            else value_type = 0u;
        }
        else value_type = 0u;
        // The scalar machine type: the realized scalar, or none for an
        // aggregate (lowering reads its layout from the reference), above
        // the template's inference link (remapped below).
        scalar_type = ((reference.x == TYPE_REF_SCALAR ? reference.y : 0u) << SCALAR_TYPE_SHIFT) |
            (scalar_type & SCALAR_TYPE_LINK_MASK);
        // 01_expression_refs: an instance's declaration and its complete
        // native width; a nominal scalar's declaration.
        if (reference.x == TYPE_REF_INSTANCE && valid_instance(reference.y))
        {
            aggregate_decl = type_instance_decl_token[reference.y];
            aggregate_words = type_native_word_count[reference.y];
        }
        else
        {
            aggregate_decl = reference.x == TYPE_REF_SCALAR ? facts.z : INVALID;
            aggregate_words = 0u;
        }
    }
    semantic_value_type_by_hir[row] = value_type;
    // A link names a row of the subtree, or none (all link bits set).
    uint link = scalar_type & SCALAR_TYPE_LINK_MASK;
    if (link != SCALAR_TYPE_LINK_MASK)
    {
        uint copy = ex_row(map, link);
        link = copy < SCALAR_TYPE_LINK_MASK ? copy : SCALAR_TYPE_LINK_MASK;
    }
    semantic_expr_scalar_type_by_hir[row] = (scalar_type & ~SCALAR_TYPE_LINK_MASK) | link;
    semantic_aggregate_decl_token_by_hir[row] = aggregate_decl;
    semantic_aggregate_word_count_by_hir[row] = aggregate_words;
    semantic_expr_ref_tag_by_hir[row] = reference.x;
    semantic_expr_ref_payload_by_hir[row] = reference.y;
    semantic_value_const_by_hir[row] = semantic_value_const_by_hir[source];
    semantic_value_const_present_by_hir[row] = semantic_value_const_present_by_hir[source];
    semantic_argument_mode_by_hir[row] = semantic_argument_mode_by_hir[source];
    uint enclosing = semantic_enclosing_fn_by_hir[source];
    semantic_enclosing_fn_by_hir[row] = enclosing == 0u ? 0u : ex_row(map, enclosing - 1u) + 1u;
    semantic_function_entrypoint_by_hir[row] = semantic_function_entrypoint_by_hir[source];
    semantic_function_host_service_by_hir[row] = semantic_function_host_service_by_hir[source];
    semantic_function_native_abi_by_hir[row] = semantic_function_native_abi_by_hir[source];
    semantic_control_depth_by_hir[row] = semantic_control_depth_by_hir[source];
    semantic_call_native_abi_by_hir[row] = semantic_call_native_abi_by_hir[source];
    semantic_array_length_by_hir[row] = semantic_array_length_by_hir[source];
    semantic_member_field_ordinal_by_hir[row] = semantic_member_field_ordinal_by_hir[source];
    // A member under a changed receiver has its own layout (08a_exec_members).
    semantic_member_field_word_offset_by_hir[row] = facts.x != INVALID
        ? facts.x : semantic_member_field_word_offset_by_hir[source];
    semantic_member_field_word_count_by_hir[row] = facts.x != INVALID
        ? facts.y : semantic_member_field_word_count_by_hir[source];
    semantic_iterable_kind_by_hir[row] = semantic_iterable_kind_by_hir[source];
    public_decl_index_by_hir[row] = INVALID;

    uint return_type = semantic_function_return_type_by_hir[source];
    uint result_words = semantic_function_result_word_count_by_hir[source];
    if (row == map.vrow)
    {
        // The function's result: its return type row's realized reference.
        // Only a native array result has words (01b_array_index_refs), and
        // selection leaves an entry whose result becomes an array to replay.
        uint return_row = compact_fn_return_type[source];
        uint2 result = ex_row_ref(map, return_row);
        if (result.x != EX_INVALID &&
            (result.x != semantic_expr_ref_tag_by_hir[return_row] ||
             result.y != semantic_expr_ref_payload_by_hir[return_row]))
        {
            return_type = result.x == TYPE_REF_SCALAR ? result.y : 0u;
            result_words = 0u;
        }
    }
    semantic_function_return_type_by_hir[row] = return_type;
    semantic_function_result_word_count_by_hir[row] = result_words;

    CheckedCallArtifact call = semantic_calls_by_hir[source];
    if (core.kind == HIR_CALL_EXPR)
    {
        call.target_token = ex_token(map, call.target_token);
        call.receiver_hir = ex_row(map, call.receiver_hir);
        call.callable_hir = ex_row(map, call.callable_hir);
        if (changed)
        {
            call.return_ref_tag = reference.x;
            call.return_ref_payload = reference.y;
            call.return_type = reference.x == TYPE_REF_SCALAR ? reference.y : 0u;
        }
        call.symbolic_type_environment = 0u;
    }
    semantic_calls_by_hir[row] = call;
}
