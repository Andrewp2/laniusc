import semantic_interface_layout;
import type_checker.calls.explicit_constant_operand;
// Attach imported generic type instances to their canonical external nominal
// identity. Generic arguments remain in the ordinary local instance relation;
// only the declaration identity lives in the external side table.

import dependency_interface;
import hir_records;
import type_checker.local_struct_layout;
import type_checker.dependencies.enum_instance_layout;
import gpu_index;

struct Params
{
    uint type_count;
    uint declaration_count;
    uint member_count;
    uint path_capacity;
    uint token_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_dependency_library_id;
StructuredBuffer<uint> resolved_dependency_unit_id;
StructuredBuffer<uint> resolved_dependency_local_index;
StructuredBuffer<uint4> resolved_value_qualifier_binding;
StructuredBuffer<uint> canonical_type_roots;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<HirRange> compact_path_type_arg_ranges;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> declaration_generic_arity;
StructuredBuffer<uint> dependency_declaration_constant_arity;
StructuredBuffer<uint> declaration_field_count;
RWStructuredBuffer<uint> type_instance_kind;
RWStructuredBuffer<uint> type_instance_head_token;
RWStructuredBuffer<uint> type_instance_arg_count;
RWStructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
RWStructuredBuffer<uint> type_instance_decl_token;
RWStructuredBuffer<uint> type_instance_state;
RWStructuredBuffer<uint> type_instance_len_kind;
RWStructuredBuffer<uint> type_instance_len_payload;
RWStructuredBuffer<uint> call_explicit_arg_constant_kind;
RWStructuredBuffer<uint> call_explicit_arg_constant_payload;
RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;

// Constant operands read checked type references through this kernel's binding.
struct KernelTypeRefs : IExplicitOperandTypeRefs
{
    uint type_ref_tag(uint token) { return type_expr_ref_tag[token]; }
    uint type_ref_payload(uint token) { return type_expr_ref_payload[token]; }
}
RWStructuredBuffer<uint> external_type_library_id;
RWStructuredBuffer<uint> external_type_unit_id;
RWStructuredBuffer<uint> external_type_local_index;
RWStructuredBuffer<uint> type_instance_aggregate_word_count;

static const uint INVALID = 0xffffffffu;
static const uint DECL_WORDS = 14u;
static const uint TYPE_WORDS = 9u;
static const uint TYPE_KIND_DECLARATION = 3u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_RESOLVED = 1u;
static const uint TYPE_INSTANCE_UNSUPPORTED = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

public struct CheckedInstanceNativeWords : IInstanceNativeWords
{
    public static uint words(uint instance) { return type_instance_aggregate_word_count[instance]; }
}

public struct CheckedLocalStructTypeRefs : ILocalStructTypeRefs
{
    public static uint tag(uint token) { return type_expr_ref_tag[token]; }
    public static uint payload(uint token) { return type_expr_ref_payload[token]; }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (path_i >= min(path_count_out[0u], gParams.path_capacity))
        return;
    uint segment_count = path_segment_count[path_i];
    uint4 parent = resolved_value_qualifier_binding[path_i];
    bool qualified_value = path_kind[path_i] == 3u && segment_count >= 2u && parent.x == 2u;
    if (path_kind[path_i] != PATH_RECORD_KIND_HIR_TYPE_EXPR && !qualified_value) return;
    if (segment_count == 0u) return;
    uint leaf_token = path_segment_token[path_segment_base[path_i] + segment_count -
        (qualified_value ? 2u : 1u)];
    uint owner_token = path_owner_token[path_i];
    if (leaf_token >= gParams.token_capacity || owner_token >= gParams.token_capacity) return;
    // Type-qualified methods and variants consume the same per-use checked
    // parent application. Never install imported identity on a local template.
    uint declaration_i = qualified_value
        ? dependency_find_declaration(parent.y, parent.z, parent.w)
        : dependency_find_declaration(resolved_dependency_library_id[path_i],
            resolved_dependency_unit_id[path_i], resolved_dependency_local_index[path_i]);
    if (declaration_i == INVALID)
        return;
    // A bare imported nominal is the zero-operand form of the same checked
    // application. Its declaration is available on this page; source-side
    // collection cannot infer its arity from a page-local canonical index.
    uint declaration_kind = dependency_declaration_word(declaration_i * DECL_WORDS + 6u);
    if (type_instance_kind[leaf_token] != TYPE_INSTANCE_NAMED &&
        (declaration_kind == 6u || declaration_kind == 7u || declaration_kind == 8u) &&
        declaration_generic_arity[declaration_i] == 0u &&
        compact_path_type_arg_ranges[leaf_token].count == 0u)
    {
        type_instance_kind[leaf_token] = TYPE_INSTANCE_NAMED;
        type_instance_head_token[leaf_token] = leaf_token;
        type_instance_arg_start[leaf_token] = INVALID;
        type_instance_arg_count[leaf_token] = 0u;
    }
    if (type_instance_kind[leaf_token] != TYPE_INSTANCE_NAMED) return;
    if (type_instance_arg_count[leaf_token] != declaration_generic_arity[declaration_i])
    {
        type_instance_state[leaf_token] = TYPE_INSTANCE_UNSUPPORTED;
        return;
    }
    // Persisted member ordinals select independent domain slots; word 11
    // retains the source ordinal. Validate kinds before source rows are bound.
    uint arity = declaration_generic_arity[declaration_i];
    HirRange arguments = compact_path_type_arg_ranges[leaf_token];
    uint argument_count = min(compact_type_arg_count[0u], gParams.path_capacity);
    uint members = dependency_declaration_word(declaration_i * DECL_WORDS + 8u);
    uint member_count = dependency_declaration_word(declaration_i * DECL_WORDS + 9u);
    bool accepted = arity <= 32u && arguments.count == arity &&
        (arity == 0u || (arguments.start <= argument_count && arity <= argument_count - arguments.start)) &&
        members <= dependency_member_count() && member_count <= dependency_member_count() - members &&
        arity <= member_count;
    uint constant_positions = 0u; uint source_positions = 0u; uint type_parameters = 0u;
    uint hir_count = min(compact_hir_count[0u], gParams.path_capacity);
    for (uint slot = 0u; accepted && slot < arity; slot++)
    {
        uint member = (members + slot) * SEMANTIC_INTERFACE_MEMBER_WORDS;
        uint kind = dependency_member_word(member + 1u);
        uint ordinal = dependency_member_word(member + 11u);
        if ((kind != 2u && kind != 3u) || dependency_member_word(member + 9u) != 0u || ordinal >= arity)
        { accepted = false; break; }
        uint position = 1u << ordinal;
        if ((source_positions & position) != 0u) { accepted = false; break; }
        source_positions |= position;
        HirTypeArg argument = compact_type_args[arguments.start + ordinal];
        if (argument.application_token != leaf_token || argument.ordinal != ordinal ||
            argument.value >= hir_count)
        { accepted = false; break; }
        // The imported header owns each operand domain and declared scalar.
        // Parsing success must never select whether an operand is a type.
        if (kind == 3u)
        {
            uint scalar = dependency_const_member_scalar(members + slot);
            uint constant_kind; uint constant_value;
            if (scalar == 0u || !checked_explicit_constant_operand(KernelTypeRefs(), argument.value, scalar,
                constant_kind, constant_value))
            { accepted = false; break; }
            constant_positions |= position;
            // Preserve the first lexical binding across specialized replay.
            // The current nominal edge is republished by ordinary collection.
            if (call_explicit_arg_constant_kind[argument.value] == 0u)
            {
                call_explicit_arg_constant_kind[argument.value] = constant_kind;
                call_explicit_arg_constant_payload[argument.value] = constant_value;
            }
        }
        else
        {
            if (compact_hir_core[argument.value].kind != 5u)
            { accepted = false; break; }
            type_parameters++;
        }
    }
    if (!accepted)
    {
        type_instance_state[leaf_token] = TYPE_INSTANCE_UNSUPPORTED;
        return;
    }
    uint signature = dependency_declaration_word(declaration_i * DECL_WORDS + 7u);
    if (signature >= dependency_type_count())
        return;
    uint root = canonical_type_roots[signature];
    if (root >= dependency_type_count())
        return;
    uint type_base = root * TYPE_WORDS;
    uint kind = dependency_type_word(type_base);
    // Persist exact source-domain positions while this page owns the header.
    // Later source collection consumes these facts without portable row IDs.
    bool saw_constant = false; bool interleaved = false;
    for (uint ordinal = 0u; ordinal < arity; ordinal++)
    {
        bool constant = (constant_positions & (1u << ordinal)) != 0u;
        if (constant) saw_constant = true;
        else interleaved = interleaved || saw_constant;
    }
    type_instance_len_kind[leaf_token] = type_parameters | (interleaved ? 0x80000000u : 0u);
    type_instance_len_payload[leaf_token] = constant_positions;
    type_instance_decl_token[leaf_token] = INVALID;
    if (declaration_kind == 8u)
    {
        // This is the alias's application environment, not an application of
        // its target declaration. The target may reorder or inject operands,
        // or be a scalar, array, slice, reference, or parameter itself.
        external_type_library_id[leaf_token] = dependency_declaration_library_id(declaration_i);
        external_type_unit_id[leaf_token] = dependency_declaration_unit_id(declaration_i);
        external_type_local_index[leaf_token] = dependency_declaration_local_index(declaration_i);
        type_instance_aggregate_word_count[leaf_token] = 0u;
        type_instance_state[leaf_token] = TYPE_INSTANCE_RESOLVED;
        type_expr_ref_tag[owner_token] = TYPE_REF_INSTANCE;
        type_expr_ref_payload[owner_token] = leaf_token;
        type_expr_ref_tag[leaf_token] = TYPE_REF_INSTANCE;
        type_expr_ref_payload[leaf_token] = leaf_token;
        return;
    }
    external_type_library_id[leaf_token] = kind == TYPE_KIND_DECLARATION
        ? dependency_type_word(type_base + 1u)
        : dependency_type_library_id(root);
    external_type_unit_id[leaf_token] = kind == TYPE_KIND_DECLARATION
        ? dependency_type_word(type_base + 8u)
        : dependency_type_unit_id(root);
    external_type_local_index[leaf_token] = kind == TYPE_KIND_DECLARATION
        ? dependency_type_word(type_base + 2u)
        : dependency_type_local_index(root);
    uint enum_words = dependency_concrete_enum_instance_words<CheckedLocalStructTypeRefs, CheckedInstanceNativeWords>(
        declaration_i, leaf_token, canonical_type_roots, type_instance_kind,
        type_instance_arg_count, type_instance_arg_row_start,
        type_instance_arg_row_count_out, type_instance_arg_row_ref_tag,
        type_instance_arg_row_ref_payload, type_instance_arg_start,
        type_instance_arg_ref_tag, type_instance_arg_ref_payload,
        min(compact_hir_count[0u], gParams.path_capacity), gParams.token_capacity,
        min(compact_field_count[0u], gParams.path_capacity), compact_hir_core,
        compact_hir_payload, compact_fields, type_decl_hir_node_by_token);
    type_instance_aggregate_word_count[leaf_token] = enum_words != 0u
        ? enum_words : declaration_field_count[declaration_i];
    type_instance_state[leaf_token] = TYPE_INSTANCE_RESOLVED;
    type_expr_ref_tag[owner_token] = TYPE_REF_INSTANCE;
    type_expr_ref_payload[owner_token] = leaf_token;
    type_expr_ref_tag[leaf_token] = TYPE_REF_INSTANCE;
    type_expr_ref_payload[leaf_token] = leaf_token;
}
