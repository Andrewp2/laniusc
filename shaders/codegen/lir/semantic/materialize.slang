import integer_words;
import primitive_types;
import native_value_layout;
import checked_semantic_artifact;
import type_checker.checked_type_graph;
import hir_records;
import codegen.lir.semantic.common;
import codegen.lir.semantic.match_recipe;
import codegen.lir.semantic.loop_recipe;
import codegen.lowering_ir;

static const uint HIR_STRUCT_ITEM = 27u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_INSTANCE_NAMED = 1u;

struct Params
{
    uint n_hir_nodes;
    uint lir_capacity;
    uint n_tokens;
    uint resident_rows;
    uint schedule_packed_bits;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_const_value;
StructuredBuffer<uint> semantic_expr_type;
StructuredBuffer<uint> semantic_expr_ref_tag;
StructuredBuffer<uint> semantic_expr_ref_payload;
StructuredBuffer<uint> semantic_aggregate_decl_token;
StructuredBuffer<uint> semantic_aggregate_word_count;
StructuredBuffer<uint> type_instance_native_words;
// An imported nominal's declaration kind: 6 struct, 7 enum (low 31 bits).
StructuredBuffer<uint> imported_layout_kind;
StructuredBuffer<uint> semantic_array_length;
StructuredBuffer<uint> semantic_iterable_kind;
StructuredBuffer<uint> semantic_value_id;
StructuredBuffer<uint> semantic_value_type;
StructuredBuffer<uint2> semantic_value_const_by_hir;
StructuredBuffer<uint> semantic_value_const_present_by_hir;
StructuredBuffer<uint> semantic_call_target;
StructuredBuffer<uint> semantic_call_kind;
StructuredBuffer<uint> semantic_call_result_type;
StructuredBuffer<uint> semantic_call_symbol_library_id;
StructuredBuffer<uint> semantic_call_symbol_unit_id;
StructuredBuffer<uint> semantic_call_symbol_local_index;
StructuredBuffer<uint> semantic_function_id;
StructuredBuffer<uint> semantic_function_id_by_token;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> semantic_control_depth_by_hir;
StructuredBuffer<uint> semantic_member_field_ordinal;
StructuredBuffer<uint> semantic_member_field_word_offset;
StructuredBuffer<uint> semantic_member_field_word_count;
StructuredBuffer<uint> semantic_aggregate_hir_by_name_token;
StructuredBuffer<uint> semantic_struct_word_count_by_hir;
StructuredBuffer<uint> semantic_struct_field_start_by_hir;
StructuredBuffer<uint> semantic_struct_field_word_offset_by_row;
StructuredBuffer<uint> semantic_struct_field_word_count_by_row;
StructuredBuffer<uint> compact_expr_root;
StructuredBuffer<uint> compact_nearest_loop;
StructuredBuffer<uint> compact_array_element_start;
StructuredBuffer<uint> compact_array_element_owner_count;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_variant_payload_start;
StructuredBuffer<uint> compact_variant_payload_count;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_start;
StructuredBuffer<uint> compact_match_payload_count;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint2> semantic_argument_value_layout;
StructuredBuffer<uint> semantic_argument_mode_by_hir;
StructuredBuffer<uint> semantic_lir_count;
StructuredBuffer<uint> semantic_lir_offset;
StructuredBuffer<uint> semantic_lir_value_row_by_hir;
StructuredBuffer<uint> semantic_execution_rank;
StructuredBuffer<uint> compact_expr_parent;
StructuredBuffer<uint> semantic_place_original_count;
StructuredBuffer<uint> semantic_place_function_flags;
StructuredBuffer<uint4> semantic_place_storage_by_token;
StructuredBuffer<uint> semantic_place_address_by_token;
StructuredBuffer<uint> semantic_receiver_call_by_hir;
StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
StructuredBuffer<SemanticLirLocal> semantic_lir_locals;

uint active_match_arm_count()
{
    return min(compact_match_arm_count[0u], gParams.n_hir_nodes);
}

uint active_match_payload_count()
{
    return min(compact_match_payload_row_count[0u], gParams.n_hir_nodes);
}

#include "match_reference.slang"
#include "receiver_layout.slang"

// A payload binder's row. Variant sub-patterns are checks, not binders.
uint match_payload_for_pattern(uint node)
{
    uint row = semantic_match_payload_row(node);
    return row != LIR_INVALID &&
        semantic_match_variant_ordinal(node, gParams.n_hir_nodes) == LIR_INVALID
        ? row : LIR_INVALID;
}

bool scalar_match_pattern(uint pattern, uint hir_count)
{
    if (pattern >= hir_count) return false;
    HirCore core = compact_hir_core[pattern];
    HirPayload payload = compact_hir_payload[pattern];
    return core.kind == HIR_LITERAL_EXPR &&
        (payload.a == HIR_EXPR_INT || payload.a == HIR_EXPR_TRUE ||
         payload.a == HIR_EXPR_FALSE);
}

bool wildcard_match_pattern(uint pattern, uint hir_count)
{
    if (pattern >= hir_count) return false;
    if (semantic_value_const_present_by_hir[pattern] == 0x40000000u)
        return false;
    HirCore core = compact_hir_core[pattern];
    // The checker gives `_` a self-binding declaration identity. Do not
    // constrain this to one expression wrapper kind: compact HIR is allowed
    // to canonicalize a pattern name as either a name or a one-segment path.
    return semantic_value_id[pattern] == core.token_start;
}

uint2 scalar_match_pattern_value(uint pattern, uint hir_count)
{
    if (!scalar_match_pattern(pattern, hir_count)) return uint2(LIR_INVALID, LIR_INVALID);
    HirPayload payload = compact_hir_payload[pattern];
    if (payload.a == HIR_EXPR_TRUE) return uint2(1u, 0u);
    if (payload.a == HIR_EXPR_FALSE) return uint2(0u, 0u);
    return uint2(payload.b, payload.c);
}

uint semantic_materialized_op(uint node, uint local_row, uint local_count)
{
    if (semantic_match_payload_row(node) != LIR_INVALID)
    {
        bool check = semantic_match_variant_ordinal(node, gParams.n_hir_nodes) != LIR_INVALID;
        return local_row == 0u ? SEMANTIC_LIR_OP_VALUE_GET
            : local_row == 1u ? SEMANTIC_LIR_OP_LOAD
            : !check ? SEMANTIC_LIR_OP_VALUE_SET
            : local_row == 2u ? SEMANTIC_LIR_OP_CONST_I32
            : local_row == 3u ? SEMANTIC_LIR_OP_COMPARE
            : local_row == 4u ? SEMANTIC_LIR_OP_IF_BEGIN : SEMANTIC_LIR_OP_CONTROL_END;
    }
    if (compact_hir_core[node].kind == HIR_MATCH_EXPR)
    {
        SemanticMatchRecipe recipe = semantic_match_retained_recipe_for_hir(
            node, min(gParams.n_hir_nodes, compact_hir_count[0u]));
        if (!recipe.valid) return SEMANTIC_LIR_OP_INVALID;
        if (semantic_match_is_arm(recipe, local_row))
        {
            uint phase = semantic_match_phase(recipe, local_row);
            uint arm_row = compact_hir_payload[node].b + semantic_match_arm_index(recipe, local_row);
            uint pattern = arm_row < active_match_arm_count()
                ? compact_match_arms[arm_row].pattern : LIR_INVALID;
            bool scalar = scalar_match_pattern(pattern, gParams.n_hir_nodes);
            bool wildcard = wildcard_match_pattern(pattern, gParams.n_hir_nodes);
            if (phase == 0u && wildcard) return SEMANTIC_LIR_OP_NOP;
            if (phase == 1u && (scalar || wildcard)) return SEMANTIC_LIR_OP_NOP;
            if (phase == 3u && wildcard) return SEMANTIC_LIR_OP_NOP;
            if (phase == 2u)
            {
                uint variant = semantic_match_variant_ordinal(pattern, gParams.n_hir_nodes);
                return variant != LIR_INVALID || scalar || wildcard
                    ? SEMANTIC_LIR_OP_CONST_I32 : SEMANTIC_LIR_OP_INVALID;
            }
        }
        return semantic_match_op(recipe, local_row);
    }
    return semantic_lir_local_op(
        compact_hir_core[node], compact_hir_payload[node], local_row, local_count);
}

uint lir_for_hir_original(uint node, uint hir_count)
{
    if (node == LIR_INVALID || node >= hir_count || semantic_place_original_count[node] == 0u)
        return LIR_INVALID;
    uint first = semantic_lir_offset[node];
    // Structured match control begins at `first`, but the expression's value
    // is materialized by the final synthetic VALUE_GET row. Consumers of the
    // HIR identity must observe that value-producing row, just as they observe
    // the sole row of an ordinary expression.
    // ((kind - 34) & ~2) == 0 is a match (34) or `value?` (36).
    return (semantic_argument_value_layout[node].x != 0u ||
        ((compact_hir_core[node].kind - HIR_MATCH_EXPR) & ~2u) == 0u ||
        semantic_lir_is_short_circuit(compact_hir_core[node], compact_hir_payload[node]))
        ? first + semantic_place_original_count[node] - 1u : first;
}

// The row carrying a HIR node's value: lir.semantic.count publishes its
// position within the node's rows (semantic_lir_value_row_by_hir).
uint lir_for_hir(uint node, uint hir_count)
{
    if (node == LIR_INVALID || node >= hir_count) return LIR_INVALID;
    uint value_row = semantic_lir_value_row_by_hir[node];
    return value_row != LIR_INVALID ? semantic_lir_offset[node] + value_row : LIR_INVALID;
}

uint lir_for_value_hir(uint node, uint hir_count)
{
    if (node == LIR_INVALID || node >= hir_count) return LIR_INVALID;
    uint root = compact_expr_root[node];
    if (root != LIR_INVALID && root < hir_count) node = root;
    return lir_for_hir(node, hir_count);
}


uint bounded_token(uint node, uint hir_count, uint fallback)
{
    return node != LIR_INVALID && node < hir_count
        ? compact_hir_core[node].token_start : fallback;
}

uint completed_token(uint node, uint hir_count, uint fallback)
{
    if (node == LIR_INVALID || node >= hir_count) return fallback;
    HirCore core = compact_hir_core[node];
    return core.token_end > core.token_start
        ? core.token_end - 1u : core.token_end;
}

uint completion_rank(HirCore core)
{
    // At a shared closing token, an inner expression (later opening token)
    // completes before its consumer. Equal spans retain expression-depth ties.
    return 0xffffffffu - core.token_start;
}

uint semantic_type_for_hir(uint node, uint hir_count)
{
    if (node == LIR_INVALID || node >= hir_count) return 0u;
    uint reference = semantic_expr_ref_payload[node];
    if (semantic_expr_ref_tag[node] == TYPE_REF_INSTANCE &&
        reference < checked_type_capacity() && type_instance_kind[reference] == 4u)
        return SEMANTIC_LIR_TY_POINTER;
    uint call_result = semantic_call_result_type[node];
    return call_result != LIR_INVALID
        ? call_result
        : semantic_lir_type(semantic_expr_type[node]);
}

uint aggregate_word_count_for_type(uint type_id, uint hir_count)
{
    if (type_id < TY_STRUCT_BASE) return 0u;
    // Validate overlapping legacy nominal encodings against the declaration
    // HIR.  A large source pack can encode a struct token above 2047 into the
    // old enum numeric window, but the token-to-HIR relation remains exact.
    uint struct_token = type_id - TY_STRUCT_BASE;
    if (struct_token < gParams.n_tokens)
    {
        uint struct_hir = semantic_aggregate_hir_by_name_token[struct_token];
        if (struct_hir < hir_count &&
            compact_hir_core[struct_hir].kind == HIR_STRUCT_ITEM)
            return semantic_struct_word_count_by_hir[struct_hir];
    }
    if (type_id >= 6144u)
    {
        uint enum_token = type_id - 6144u;
        if (enum_token < gParams.n_tokens)
        {
            uint enum_hir = semantic_aggregate_hir_by_name_token[enum_token];
            if (enum_hir < hir_count &&
                compact_hir_core[enum_hir].kind == 26u)
                return semantic_struct_word_count_by_hir[enum_hir];
        }
    }
    return 0u;
}

bool concrete_type_argument(uint instance, uint slot, out uint tag, out uint payload)
{
    return ScopedCheckedTypeGraph.argument(instance, slot, tag, payload);
}

uint concrete_type_ref_words(uint tag, uint payload, uint hir_count)
{
    if (tag == 1u)
    {
        if (payload == SEMANTIC_LIR_TY_STRING) return 2u;
        if (payload != 0u && payload < 128u) return 1u;
        if (payload < TY_STRUCT_BASE) return LIR_INVALID;
        return aggregate_word_count_for_type(payload, hir_count);
    }
    if (tag != TYPE_REF_INSTANCE || payload >= checked_type_capacity())
        return LIR_INVALID;
    if (type_instance_kind[payload] == 3u)
        return NATIVE_SLICE_WORDS;
    uint checked_words = type_instance_native_words[payload];
    if (checked_words != LIR_INVALID) return checked_words;
    uint decl_token = type_instance_decl_token[payload];
    if (decl_token >= gParams.n_tokens) return LIR_INVALID;
    uint declaration = semantic_aggregate_hir_by_name_token[decl_token];
    if (declaration >= hir_count) return LIR_INVALID;
    uint words = semantic_struct_word_count_by_hir[declaration];
    return words;
}

bool opaque_generic_enum_reference(uint node, uint hir_count)
{
    uint tag;
    uint instance;
    semantic_type_ref_for_hir(node, hir_count, tag, instance);
    if (tag != TYPE_REF_INSTANCE || instance >= checked_type_capacity()) return false;
    uint declaration_token = type_instance_decl_token[instance];
    if (declaration_token >= gParams.n_tokens) return false;
    uint declaration = semantic_aggregate_hir_by_name_token[declaration_token];
    if (declaration >= hir_count || compact_hir_core[declaration].kind != 26u)
        return false;
    // Unknown width is acceptable only for the address of an enum whose
    // instance actually depends on a generic parameter. Cyclic concrete
    // declarations and unsupported nested layouts remain errors.
    for (uint slot = 0u; slot < type_instance_arg_count[instance]; slot++)
    {
        uint argument_tag;
        uint argument_payload;
        if (concrete_type_argument(instance, slot, argument_tag, argument_payload) &&
            argument_tag == 2u)
            return true;
    }
    return false;
}

uint concrete_enum_instance_words(uint instance, uint hir_count)
{
    if (instance >= checked_type_capacity() ||
        type_instance_kind[instance] != TYPE_INSTANCE_NAMED)
        return 0u;
    if (type_instance_arg_count[instance] == 0u) return 0u;
    uint decl_token = type_instance_decl_token[instance];
    if (decl_token >= gParams.n_tokens) return 0u;
    uint owner = semantic_aggregate_hir_by_name_token[decl_token];
    if (owner >= hir_count || compact_hir_core[owner].kind != 26u)
        return 0u;
    uint checked_words = type_instance_native_words[instance];
    if (checked_words != 0u && checked_words != LIR_INVALID) return checked_words;
    // The semantic layout producer owns substitution and complete variant
    // traversal. An unavailable width must remain unavailable here.
    return 0u;
}

uint enum_constructor_owner(uint node, uint hir_count)
{
    if (node >= hir_count || semantic_call_kind[node] != 5u)
        return LIR_INVALID;
    // The call target is a discriminant ordinal within its enum, not a row
    // in compact_variants. Resolve the checked result declaration instead.
    uint token = semantic_aggregate_decl_token[node];
    uint owner = token < gParams.n_tokens
        ? semantic_aggregate_hir_by_name_token[token] : LIR_INVALID;
    if (owner < hir_count && compact_hir_core[owner].kind == 26u)
        return owner;
    uint result_type = semantic_call_result_type[node];
    if (result_type < 6144u) return LIR_INVALID;
    token = result_type - 6144u;
    owner = token < gParams.n_tokens
        ? semantic_aggregate_hir_by_name_token[token] : LIR_INVALID;
    return owner < hir_count && compact_hir_core[owner].kind == 26u
        ? owner : LIR_INVALID;
}

uint contextual_enum_instance(uint node, uint hir_count)
{
    if (node >= hir_count) return LIR_INVALID;
    if (semantic_expr_ref_tag[node] == TYPE_REF_INSTANCE)
        return semantic_expr_ref_payload[node];
    if (semantic_call_kind[node] != 5u) return LIR_INVALID;
    uint owner = enum_constructor_owner(node, hir_count);
    if (owner >= hir_count) return LIR_INVALID;
    uint root = compact_expr_root[node];
    if (root >= hir_count) root = node;
    uint parent = compact_hir_core[root].parent;
    if (parent >= hir_count) return LIR_INVALID;
    HirCore parent_core = compact_hir_core[parent];
    HirPayload parent_payload = compact_hir_payload[parent];
    if ((parent_core.kind != HIR_STMT && parent_core.kind != HIR_LET_STMT) ||
        parent_payload.a != HIR_STMT_LET || parent_payload.c != root ||
        semantic_expr_ref_tag[parent] != TYPE_REF_INSTANCE)
        return LIR_INVALID;
    uint instance = semantic_expr_ref_payload[parent];
    uint owner_token = compact_hir_payload[owner].b;
    return instance < checked_type_capacity() && owner_token < gParams.n_tokens &&
        type_instance_decl_token[instance] == owner_token
        ? instance : LIR_INVALID;
}

uint aggregate_word_count_for_hir(uint node, uint hir_count)
{
    if (node == LIR_INVALID || node >= hir_count) return 0u;
    uint ref_tag = semantic_expr_ref_tag[node];
    uint ref_payload = semantic_expr_ref_payload[node];
    if (ref_tag == TYPE_REF_INSTANCE && ref_payload < checked_type_capacity())
        return type_instance_kind[ref_payload] == 4u ? 0u
            : type_instance_native_words[ref_payload];
    // The checked layout is in native words; a fixed array's logical length
    // counts elements. Multiword elements (e.g. str) must copy every word.
    uint projected_words = semantic_aggregate_word_count[node];
    if (projected_words != 0u) return projected_words;
    uint array_length = semantic_array_length[node];
    if (array_length != LIR_INVALID &&
        array_length != SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME)
        return array_length;
    if (ref_tag == TYPE_REF_INSTANCE || semantic_call_kind[node] == 5u)
    {
        uint enum_words = concrete_enum_instance_words(
            contextual_enum_instance(node, hir_count), hir_count);
        if (enum_words != 0u) return enum_words;
    }
    // A borrowed slice has data, length, and stride even when its element type
    // was instantiated from an imported generic function at this call site.
    if (ref_tag == TYPE_REF_INSTANCE &&
        array_length == SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME)
        return NATIVE_SLICE_WORDS;
    if (ref_tag == 1u)
    {
        uint words = aggregate_word_count_for_type(ref_payload, hir_count);
        if (words != 0u) return words;
    }
    uint name_token = semantic_aggregate_decl_token[node];
    if (name_token < gParams.n_tokens)
    {
        uint struct_hir = semantic_aggregate_hir_by_name_token[name_token];
        if (struct_hir < hir_count)
            return semantic_struct_word_count_by_hir[struct_hir];
    }
    // Instantiated aggregate calls carry their concrete ABI width on the
    // resolved function record. Numeric scalar type codes intentionally do
    // not encode generic arguments, so this is the canonical source for a
    // call such as `Range<i32>`.
    uint function = semantic_call_target[node];
    // Only ordinary function targets index this table. Host services and
    // intrinsics share the target field but use independent numeric IDs;
    // interpreting one as a function can turn an integer result (e.g. a file
    // handle) into an unrelated function's aggregate pointer.
    if (semantic_call_kind[node] == 1u &&
        function != LIR_INVALID && function < hir_count)
    {
        uint words = semantic_lir_functions[function].result_word_count;
        if (words != 0u) return words;
    }
    return aggregate_word_count_for_type(
        semantic_type_for_hir(node, hir_count), hir_count);
}

uint native_value_words_for_hir(uint node, uint hir_count)
{
    uint tag; uint payload;
    semantic_type_ref_for_hir(node, hir_count, tag, payload);
    if (tag == 1u && payload != 0u && payload < 128u)
        return payload == SEMANTIC_LIR_TY_STRING ? 2u : 1u;
    // A reference has one native value word even though it needs no
    // aggregate copy storage. Constructor totals and payload prefix offsets
    // count the pointer itself, not the size of its referent.
    if (tag == TYPE_REF_INSTANCE && payload < checked_type_capacity() &&
        type_instance_kind[payload] == 4u) return 1u;
    if (tag == TYPE_REF_INSTANCE || (tag == 1u && payload >= 128u))
        return aggregate_word_count_for_hir(node, hir_count);
    return LIR_INVALID;
}

// A payload's word in the scrutinee. Every pattern level adds its
// discriminant and the payloads before this one; an arm's payload rows,
// nested ones included, are contiguous from its first direct payload.
uint match_binding_word_offset(HirMatchPayload binding, uint hir_count)
{
    if (binding.arm >= active_match_arm_count()) return LIR_INVALID;
    uint arm = binding.arm;
    uint arm_pattern = compact_match_arms[arm].pattern;
    uint start = compact_match_payload_start[arm];
    uint total = active_match_payload_count();
    if (start >= total) return LIR_INVALID;
    uint offset = 0u;
    for (uint depth = 0u; depth < 8u; depth += 1u)
    {
        offset += 1u; // discriminant
        uint prior_count = 0u;
        for (uint row = start; row < total && compact_match_payloads[row].arm == arm; row += 1u)
        {
            HirMatchPayload prior = compact_match_payloads[row];
            if (prior.parent_pattern != binding.parent_pattern ||
                prior.ordinal >= binding.ordinal)
                continue;
            if (prior.pattern >= hir_count ||
                semantic_expr_ref_tag[prior.pattern] == TYPE_REF_GENERIC_PARAM)
                return LIR_INVALID;
            uint words = native_value_words_for_hir(prior.pattern, hir_count);
            if (words == LIR_INVALID || offset > LIR_INVALID - words)
                return LIR_INVALID;
            offset += words;
            prior_count += 1u;
        }
        if (prior_count != binding.ordinal) return LIR_INVALID;
        if (binding.parent_pattern == arm_pattern) return offset;
        uint parent = semantic_match_payload_row(binding.parent_pattern);
        if (parent == LIR_INVALID || compact_match_payloads[parent].arm != arm)
            return LIR_INVALID;
        binding = compact_match_payloads[parent];
    }
    return LIR_INVALID;
}

// The arm's nested variant checks; its branch leaves their IFs too.
uint match_arm_check_count(uint arm, uint hir_count)
{
    uint start = arm < active_match_arm_count() ? compact_match_payload_start[arm] : LIR_INVALID;
    uint total = active_match_payload_count();
    uint checks = 0u;
    for (uint row = start; row < total && compact_match_payloads[row].arm == arm; row += 1u)
        if (semantic_match_variant_ordinal(compact_match_payloads[row].pattern, hir_count) != LIR_INVALID)
            checks += 1u;
    return checks;
}

uint enum_constructor_word_count(uint node, HirPayload payload, uint hir_count)
{
    uint total = 1u; // discriminant
    uint call_arg_total = min(compact_call_arg_count[0u], gParams.n_hir_nodes);
    for (uint ordinal = 0u; ordinal < payload.c; ordinal += 1u)
    {
        uint row = payload.b + ordinal;
        if (row < payload.b || row >= call_arg_total) return 0u;
        HirCallArg argument = compact_call_args[row];
        if (argument.call != node || argument.ordinal != ordinal) return 0u;
        uint words = native_value_words_for_hir(argument.value, hir_count);
        if (words == LIR_INVALID || total >= LIR_INVALID - words) return LIR_INVALID;
        total += words;
    }
    return total;
}

void member_word_layout(uint member, uint ordinal, uint hir_count,
                        out uint word_offset, out uint word_count)
{
    word_offset = ordinal;
    word_count = 1u;
    if (member >= hir_count) return;
    uint receiver = compact_hir_payload[member].b;
    if (receiver >= hir_count) return;
    uint receiver_tag = semantic_expr_ref_tag[receiver];
    uint receiver_instance = semantic_expr_ref_payload[receiver];
    // The value remains a pointer, but field offsets belong to its complete
    // referent. Using the wrapper loses generic multiword prefix fields.
    for (uint depth = 0u; depth < 64u && receiver_tag == TYPE_REF_INSTANCE &&
         receiver_instance < checked_type_capacity() && type_instance_kind[receiver_instance] == 4u; depth++)
    {
        uint reference = receiver_instance;
        receiver_tag = type_instance_elem_ref_tag[reference];
        receiver_instance = type_instance_elem_ref_payload[reference];
    }
    if (receiver_tag == TYPE_REF_INSTANCE && receiver_instance < checked_type_capacity() &&
        type_instance_kind[receiver_instance] == 4u)
    { word_offset = LIR_INVALID; word_count = LIR_INVALID; return; }
    if (receiver_tag == TYPE_REF_INSTANCE &&
        receiver_instance < checked_type_capacity() &&
        type_instance_kind[receiver_instance] == TYPE_INSTANCE_NAMED &&
        (type_instance_arg_count[receiver_instance] != 0u ||
         (type_instance_decl_token[receiver_instance] == LIR_INVALID &&
          external_type_library_id[receiver_instance] != LIR_INVALID)))
    {
        // Consume the complete receiver's checked range. Missing facts reject
        // later; lowering never reconstructs a field's type or native width.
        word_offset = semantic_member_field_word_offset[member];
        word_count = semantic_member_field_word_count[member];
        return;
    }
    uint decl_token = receiver_tag == TYPE_REF_INSTANCE && receiver_instance < checked_type_capacity() &&
        type_instance_kind[receiver_instance] == TYPE_INSTANCE_NAMED
        ? type_instance_decl_token[receiver_instance] : semantic_aggregate_decl_token[receiver];
    // An indexed struct can have its element declaration on the slice base
    // even when the index expression has no cached declaration token. Field
    // ordinals are not ABI offsets when earlier fields occupy multiple words.
    if (decl_token >= gParams.n_tokens &&
        compact_hir_core[receiver].kind == HIR_INDEX_EXPR)
    {
        uint base = compact_hir_payload[receiver].b;
        if (base < hir_count)
            decl_token = semantic_aggregate_decl_token[base];
    }
    if (decl_token >= gParams.n_tokens &&
        receiver_tag == SEMANTIC_TYPE_REF_SCALAR)
    {
        uint type_id = receiver_instance;
        if (type_id >= TY_STRUCT_BASE)
            decl_token = type_id - TY_STRUCT_BASE;
    }
    if (decl_token >= gParams.n_tokens) return;
    uint struct_hir = semantic_aggregate_hir_by_name_token[decl_token];
    if (struct_hir >= hir_count ||
        compact_hir_core[struct_hir].kind != HIR_STRUCT_ITEM)
        return;
    uint start = semantic_struct_field_start_by_hir[struct_hir];
    uint field_row = start != LIR_INVALID ? start + ordinal : LIR_INVALID;
    if (field_row >= gParams.n_hir_nodes) return;
    word_offset = semantic_struct_field_word_offset_by_row[field_row];
    word_count = semantic_struct_field_word_count_by_row[field_row];
}

void semantic_type_ref_for_hir(uint node, uint hir_count,
                               out uint tag, out uint payload)
{
    tag = 0u;
    payload = LIR_INVALID;
    if (node == LIR_INVALID || node >= hir_count) return;
    tag = semantic_expr_ref_tag[node];
    payload = semantic_expr_ref_payload[node];
}

static const uint IMPORTED_LAYOUT_STRUCT = 6u;

// An imported struct instance whose checked native layout is known.
bool imported_struct_instance(uint instance)
{
    if (type_instance_decl_token[instance] != LIR_INVALID ||
        external_type_library_id[instance] == LIR_INVALID)
        return false;
    uint capacity; uint stride;
    imported_layout_kind.GetDimensions(capacity, stride);
    uint words = type_instance_native_words[instance];
    return instance < capacity &&
        (imported_layout_kind[instance] & 0x7fffffffu) == IMPORTED_LAYOUT_STRUCT &&
        words != 0u && words != LIR_INVALID;
}

// The opcode of the zero value that `let x: T;` stores, from the checked
// declaration type: a zero constant for numbers, bool, char and ptr, and a
// zero-filled aggregate for fixed arrays, slices, local structs and imported
// structs. A slice's zero is (null, 0, 0), a valid empty view: its length
// is 0, so every index fails the bounds check. An imported struct is filled
// from its imported layout. Other types are unsupported: the zero bits of
// str and references are not values, and an enum's would silently pick its
// first variant.
uint zero_initializer_op(uint node, uint hir_count)
{
    uint tag;
    uint payload;
    semantic_type_ref_for_hir(node, hir_count, tag, payload);
    uint declaration_token = LIR_INVALID;
    if (tag == 1u)
    {
        if (scalar_is_float(payload)) return SEMANTIC_LIR_OP_CONST_F32;
        if (scalar_is_integer(payload) || payload == SCALAR_BOOL ||
            payload == SCALAR_CHAR || payload == SCALAR_PTR)
            return SEMANTIC_LIR_OP_CONST_I32;
        // Legacy codes: 128 + element is a fixed array of that scalar.
        if (payload >= 128u && payload < TY_STRUCT_BASE)
        {
            uint element = payload - 128u;
            return scalar_is_float(element) || scalar_is_integer(element) ||
                element == SCALAR_BOOL || element == SCALAR_CHAR || element == SCALAR_PTR
                ? SEMANTIC_LIR_OP_AGGREGATE_NEW : SEMANTIC_LIR_OP_INVALID;
        }
        if (payload >= TY_STRUCT_BASE) declaration_token = payload - TY_STRUCT_BASE;
    }
    else if (tag == TYPE_REF_INSTANCE && payload < checked_type_capacity())
    {
        uint kind = type_instance_kind[payload];
        if (kind == 2u || kind == 3u) return SEMANTIC_LIR_OP_AGGREGATE_NEW;
        if (kind == TYPE_INSTANCE_NAMED)
        {
            if (imported_struct_instance(payload)) return SEMANTIC_LIR_OP_AGGREGATE_NEW;
            declaration_token = type_instance_decl_token[payload];
        }
    }
    uint declaration = declaration_token < gParams.n_tokens
        ? semantic_aggregate_hir_by_name_token[declaration_token] : LIR_INVALID;
    return declaration < hir_count && compact_hir_core[declaration].kind == HIR_STRUCT_ITEM
        ? SEMANTIC_LIR_OP_AGGREGATE_NEW : SEMANTIC_LIR_OP_INVALID;
}

bool imported_constant_for_hir(uint node, uint hir_count)
{
    return node < hir_count &&
           semantic_value_const_present_by_hir[node] == 0x80000000u;
}

uint materialize_loop_operand(uint source, uint node, uint first_row,
                              uint hir_count, HirPayload payload,
                              HirPayload range_payload, uint scalar)
{
    if (source == LOOP_OPERAND_NONE) return LIR_INVALID;
    if (source == LOOP_OPERAND_ZERO) return 0u;
    if (source == LOOP_OPERAND_ONE) return 1u;
    if (source == LOOP_OPERAND_BINDING_DECL) return payload.b;
    if (source == LOOP_OPERAND_ITERABLE_DECL)
        return payload.c < hir_count ? semantic_value_id[payload.c] : LIR_INVALID;
    if (source == LOOP_OPERAND_SYNTHETIC_DECL) return gParams.n_tokens + node;
    if (source == LOOP_OPERAND_RANGE_START)
        return lir_for_value_hir(range_payload.b, hir_count);
    if (source == LOOP_OPERAND_RANGE_END)
        return lir_for_value_hir(range_payload.c, hir_count);
    if (source == LOOP_OPERAND_ARRAY_LENGTH)
        return payload.c < hir_count ? semantic_array_length[payload.c] : LIR_INVALID;
    if (source == LOOP_OPERAND_INTEGER_MAX_LO || source == LOOP_OPERAND_INTEGER_MAX_HI)
    {
        uint bits = scalar_integer_bits(scalar);
        uint2 maximum = integer_words_mask(bits - (scalar_is_signed_integer(scalar) ? 1u : 0u));
        return source == LOOP_OPERAND_INTEGER_MAX_LO ? maximum.x : maximum.y;
    }
    if (source >= LOOP_OPERAND_ROW_BASE)
        return first_row + source - LOOP_OPERAND_ROW_BASE;
    return LIR_INVALID;
}

SemanticLirSchedule semantic_schedule(uint node, uint local_row, uint local_count,
                                      uint hir_count, HirCore hir, HirLinks links,
                                      HirPayload payload)
{
    SemanticLirSchedule schedule;
    bool expression_row = semantic_lir_is_expression(hir);
    uint root = expression_row ? compact_expr_root[node] : LIR_INVALID;
    SemanticMatchRecipe match_recipe;
    match_recipe.address_load_count = 0u;
    match_recipe.arm_count = 0u;
    match_recipe.valid = true;
    if (hir.kind == HIR_MATCH_EXPR)
        match_recipe = semantic_match_retained_recipe_for_hir(node, hir_count);
    uint local_op = semantic_lir_local_op(hir, payload, local_row, local_count,
        match_recipe.address_load_count);
    uint iterable_kind = semantic_iterable_kind[node];
    uint iterable_form = payload.c < hir_count ? compact_hir_payload[payload.c].a : 0u;
    uint array_length = payload.c < hir_count
        ? semantic_array_length[payload.c] : LIR_INVALID;
    uint iterable_type_kind = payload.c < hir_count
        ? receiver_kind(semantic_expr_ref_tag[payload.c], semantic_expr_ref_payload[payload.c]) : 0u;
    SemanticLoopRecipe loop_recipe = semantic_loop_recipe(
        hir, payload, iterable_form, iterable_kind, array_length, iterable_type_kind);
    bool direct_range_for = loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_RANGE ||
        loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_RANGE_FROM_ZERO ||
        loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_UNBOUNDED_RANGE ||
        loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_UNBOUNDED_RANGE_FROM_ZERO;
    bool range_value_for = loop_recipe.kind == SEMANTIC_LOOP_RECIPE_RANGE_VALUE;
    bool range_for = direct_range_for || range_value_for;
    bool slice_for = loop_recipe.kind == SEMANTIC_LOOP_RECIPE_SLICE;
    bool array_for = loop_recipe.kind == SEMANTIC_LOOP_RECIPE_ARRAY || slice_for;
    uint check_row = semantic_match_check_row(node, hir_count);
    if (check_row != LIR_INVALID)
    {
        uint arm_row = compact_match_payloads[check_row].arm;
        HirMatchArm arm = compact_match_arms[arm_row];
        HirCore result = compact_hir_core[arm.result];
        SemanticMatchRecipe owner_recipe = semantic_match_retained_recipe_for_hir(arm.owner, hir_count);
        bool close = local_row + 1u == SEMANTIC_MATCH_CHECK_ROWS;
        // Payload rows follow source order, so an outer check opens first;
        // each owns eight ties. Every check closes after the arm's branch
        // and before its IF_END, inner checks first.
        uint ordinal = check_row - min(compact_match_payload_start[arm_row], check_row);
        schedule.execution_region = close
            ? result.token_end > result.token_start ? result.token_end - 1u : result.token_end
            : result.token_start;
        schedule.execution_rank = close ? completion_rank(compact_hir_core[arm.owner]) : 0u;
        schedule.execution_tie = close ? 2u + 0xffu - min(ordinal, 0xffu)
            : semantic_match_first_arm(owner_recipe) + 5u + ordinal * 8u + local_row;
        return schedule;
    }
    uint payload_row = match_payload_for_pattern(node);
    if (payload_row != LIR_INVALID)
    {
        HirMatchPayload binding = compact_match_payloads[payload_row];
        HirMatchArm arm = compact_match_arms[binding.arm];
        HirCore result = compact_hir_core[arm.result];
        schedule.execution_region = result.token_start;
        schedule.execution_rank = 0u;
        // Payload extraction belongs inside the selected arm, after its
        // IF_BEGIN and before the result expression.
        SemanticMatchRecipe owner_recipe = semantic_match_retained_recipe_for_hir(arm.owner, hir_count);
        schedule.execution_tie = semantic_match_first_arm(owner_recipe) + 5u +
            binding.ordinal * 3u + local_row;
        return schedule;
    }
    if (hir.kind == HIR_MATCH_EXPR)
    {
        if (!match_recipe.valid)
        {
            schedule.execution_region = hir.token_start;
            schedule.execution_rank = 0u;
            schedule.execution_tie = local_row;
            return schedule;
        }
        if (local_row + 3u >= local_count)
        {
            schedule.execution_region = hir.token_end > hir.token_start
                ? hir.token_end - 1u : hir.token_end;
            // A compound final arm may share this closing boundary. Its
            // result store, branch, nested check ends, and IF_END use the
            // final rank with ties 0..0x102. Close the match after that arm.
            schedule.execution_rank = completion_rank(hir);
            schedule.execution_tie = 0x103u + local_row - (local_count - 3u);
            return schedule;
        }
        if (local_row < semantic_match_first_arm(match_recipe))
        {
            uint first_arm = payload.b;
            HirCore first_result = first_arm < active_match_arm_count()
                ? compact_hir_core[compact_match_arms[first_arm].result] : hir;
            schedule.execution_region = first_result.token_start;
            schedule.execution_rank = 0u;
            schedule.execution_tie = local_row;
            return schedule;
        }
        uint arm_row = payload.b + semantic_match_arm_index(match_recipe, local_row);
        HirMatchArm arm = compact_match_arms[arm_row];
        HirCore result = compact_hir_core[arm.result];
        uint phase = semantic_match_phase(match_recipe, local_row);
        schedule.execution_region = phase <= 4u
            ? result.token_start
            : result.token_end > result.token_start
                ? result.token_end - 1u : result.token_end;
        schedule.execution_rank = phase <= 4u ? 0u : completion_rank(hir);
        schedule.execution_tie = phase <= 4u
            ? semantic_match_first_arm(match_recipe) + phase
            : phase == 7u ? 0x102u : phase - 5u;
        return schedule;
    }
    if (range_for || array_for)
    {
        HirPayload range;
        range.a = 0u;
        range.b = payload.c;
        range.c = payload.c;
        range.d = LIR_INVALID;
        if (direct_range_for) range = compact_hir_payload[payload.c];
        uint start_node = range.b;
        uint end_node = range.c;
        uint start_token = completed_token(start_node, hir_count, hir.token_start);
        uint end_token = completed_token(end_node, hir_count, start_token);
        bool starts_from_zero =
            loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_RANGE_FROM_ZERO ||
            loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_UNBOUNDED_RANGE_FROM_ZERO;
        bool unbounded =
            loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_UNBOUNDED_RANGE ||
            loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_UNBOUNDED_RANGE_FROM_ZERO;
        uint header_last_row = unbounded ? (starts_from_zero ? 3u : 2u)
            : starts_from_zero || slice_for ? 8u : 7u;
        uint body_begin_row = header_last_row + 1u;
        if (local_row <= (starts_from_zero ? 1u : 0u))
            schedule.execution_region = start_token;
        else if (local_row <= header_last_row)
            schedule.execution_region = end_token;
        else if (local_row == body_begin_row ||
                 ((array_for || range_value_for) && local_row <= 12u))
        {
            schedule.execution_region = bounded_token(payload.d, hir_count, hir.token_start);
            schedule.execution_rank = 0u;
            schedule.execution_tie = local_row - body_begin_row;
            return schedule;
        }
        else
            // Loop-body rows must sort strictly before a statement beginning
            // at the loop's half-open end token. Keeping the closing region
            // on the final token inside the loop prevents a following call
            // such as `print(total)` from being emitted in the loop body.
            schedule.execution_region = hir.token_end > hir.token_start
                ? hir.token_end - 1u : hir.token_end;
        schedule.execution_rank = 0xffffffffu;
        schedule.execution_tie = local_row;
        return schedule;
    }
    if (semantic_lir_is_assignment(hir, payload))
    {
        uint rhs = payload.c;
        uint rhs_root = rhs < hir_count ? compact_expr_root[rhs] : LIR_INVALID;
        if (rhs_root == LIR_INVALID || rhs_root >= hir_count) rhs_root = rhs;
        bool compound_lhs_read = payload.d != HIR_ASSIGN_OP_SET && local_row == 0u;
        schedule.execution_region = compound_lhs_read
            ? bounded_token(rhs_root, hir_count, hir.token_start)
            : completed_token(rhs_root, hir_count, hir.token_start);
        // A compound assignment reads its old lhs before evaluating the RHS,
        // then applies the binary operation and store after the RHS completes.
        // This is observable for side effects and is also the stack contract
        // required by Wasm's non-commutative binary instructions.
        schedule.execution_rank = compound_lhs_read ? 0u : 0xffffffffu;
        schedule.execution_tie = !compound_lhs_read && rhs_root < hir_count &&
            compact_hir_core[rhs_root].kind == HIR_MATCH_EXPR
            ? 0xffffffffu : local_row;
        return schedule;
    }
    if (semantic_lir_is_zero_let(hir, payload))
    {
        // No initializer completes first: the zero value, then its store,
        // run at the statement itself.
        schedule.execution_region = hir.token_start;
        schedule.execution_rank = 0xffffffffu;
        schedule.execution_tie = 0xfffffffeu + min(local_row, 1u);
        return schedule;
    }
    if (root == LIR_INVALID || root >= hir_count)
    {
        uint operand = LIR_INVALID;
        if (local_op == SEMANTIC_LIR_OP_RETURN)
            operand = hir.kind == HIR_CONST_ITEM
                ? compact_const_value[node] : payload.b;
        else if (local_op == SEMANTIC_LIR_OP_IF_BEGIN ||
            local_op == SEMANTIC_LIR_OP_LOOP_BEGIN)
            operand = payload.b;
        else if (local_op == SEMANTIC_LIR_OP_VALUE_SET ||
                 local_op == SEMANTIC_LIR_OP_STORE)
            operand = payload.c;
        if (operand != LIR_INVALID && operand < hir_count)
        {
            uint operand_root = compact_expr_root[operand];
            root = operand_root != LIR_INVALID && operand_root < hir_count
                ? operand_root : operand;
        }
    }
    // Every ordinary producer runs at its own completion boundary. Grouping
    // a whole tree at its root's opening token places consuming calls before
    // structured children such as match arguments have closed. Closing-token
    // postorder also preserves left-to-right effects across sibling arguments.
    schedule.execution_region = expression_row
        ? completed_token(node, hir_count, hir.token_start)
        : completed_token(root, hir_count, hir.token_start);
    schedule.execution_rank = expression_row
        ? completion_rank(hir) : 0xffffffffu;
    schedule.execution_tie = expression_row
        ? (0x00ffffffu - min(semantic_execution_rank[node], 0x00ffffffu)) * 128u
        : 0xffffffffu;

    if (semantic_lir_is_short_circuit(hir, payload))
    {
        // Open the conditional after the LHS, before evaluating any RHS row.
        // Each expression depth owns 128 ties for control/capture rows and
        // up to 64 receiver dereferences. A child's complete adjustment
        // precedes its parent's opening rows at equal token boundaries.
        schedule.execution_region = completed_token(
            local_row < 3u ? payload.b : payload.c, hir_count, hir.token_start);
        schedule.execution_tie += local_row;
    }

    if (semantic_lir_is_control(hir, payload))
    {
        bool loop = semantic_lir_is_loop(hir, payload);
        if (!loop && local_row == 0u)
        {
            uint condition = payload.b;
            uint condition_root = condition < hir_count
                ? compact_expr_root[condition] : LIR_INVALID;
            schedule.execution_region = completed_token(
                condition_root, hir_count, completed_token(condition, hir_count, hir.token_start));
            // The marker consumes the completed condition expression. Keep it
            // in the statement-effect rank band so every expression depth in
            // this region precedes the branch.
            schedule.execution_rank = 0xffffffffu;
            schedule.execution_tie = 0xffffffffu;
        }
        else if (!loop && semantic_lir_is_contract(hir, payload))
        {
            // ELSE, TRAP and CONTROL_END run together at the clause's end.
            // The condition's span includes the parentheses, so IF_BEGIN
            // already owns the last tie on `)`; the next token (the next
            // clause or the body's `{`) opens no rows of its own.
            schedule.execution_region = hir.token_end;
            schedule.execution_rank = 0u;
            schedule.execution_tie = local_row;
        }
        else if (!loop && local_count == 3u && local_row == 1u)
        {
            schedule.execution_region = bounded_token(payload.d, hir_count, hir.token_end);
            schedule.execution_rank = 0xffffffffu;
            schedule.execution_tie = 0u;
        }
        else if (!loop)
        {
            uint closing_arm = payload.d < hir_count ? payload.d : payload.c;
            uint closing_end = closing_arm < hir_count
                ? compact_hir_core[closing_arm].token_end : hir.token_end;
            // Source spans are half-open. Put the synthetic closing marker on
            // the final token inside the arm so an expression beginning at the
            // arm's token_end cannot sort into the controlled region.
            schedule.execution_region = closing_end > hir.token_start
                ? closing_end - 1u : closing_end;
            schedule.execution_rank = 0xffffffffu;
            schedule.execution_tie = 0xffffffffu;
            if (links.subtree_end <= node)
                schedule.execution_region = hir.token_start;
        }
        else
        {
            uint condition = payload.b;
            uint condition_root = condition < hir_count
                ? compact_expr_root[condition] : LIR_INVALID;
            if (local_row <= 1u)
            {
                schedule.execution_region = hir.token_start;
                schedule.execution_rank = hir.token_start;
                schedule.execution_tie = local_row;
            }
            else if (local_row == 2u)
            {
                schedule.execution_region = completed_token(
                    condition_root, hir_count, completed_token(condition, hir_count, hir.token_start));
                schedule.execution_rank = 0xffffffffu;
                schedule.execution_tie = 0xffffffffu;
            }
            else
            {
                schedule.execution_region = hir.token_end > hir.token_start
                    ? hir.token_end - 1u : hir.token_end;
                schedule.execution_rank = schedule.execution_region;
                schedule.execution_tie = local_row - 3u;
            }
        }
    }
    return schedule;
}

struct SemanticLirRow
{
    SemanticLirCore core;
    SemanticLirOperands operands;
    uint layout_word_offset;
};

SemanticLirRow materialize_original_semantic_lir_row(uint node, uint local_row, uint hir_count)
{
    uint first_row = semantic_lir_offset[node];

    HirCore hir = compact_hir_core[node];
    HirLinks links = compact_hir_links[node];
    HirPayload payload = compact_hir_payload[node];
    uint2 capture = semantic_argument_value_layout[node];
    uint local_count = semantic_place_original_count[node] - (capture.x != 0u ? 1u : 0u);
    if (capture.x != 0u && local_row == local_count)
    {
        // Capture at the source expression's completion point, before the
        // next argument runs. The original expression still owns calls,
        // constructor elements, and structured-control recipe rows.
        bool final_value = ((hir.kind - HIR_MATCH_EXPR) & ~2u) == 0u ||
            semantic_lir_is_short_circuit(hir, payload);
        uint source_row = final_value ? local_count - 1u : 0u;
        SemanticLirRow snapshot;
        snapshot.core.type_id = capture.y == 2u ? 131u
            : semantic_type_for_hir(node, hir_count);
        uint tag;
        semantic_type_ref_for_hir(node, hir_count, tag,
            snapshot.core.type_ref_payload);
        snapshot.core.flags = ((tag & 3u) << SEMANTIC_LIR_TYPE_REF_TAG_SHIFT) |
            (SEMANTIC_LIR_OP_AGGREGATE_COPY << SEMANTIC_LIR_OP_SHIFT) |
            (capture.y == 3u ? SEMANTIC_LIR_FLAG_ARRAY_PAIR : 0u);
        snapshot.core.value_word_count = capture.x;
        snapshot.operands.a = first_row + source_row;
        snapshot.operands.b = LIR_INVALID;
        snapshot.operands.c = 0u;
        snapshot.layout_word_offset = LIR_INVALID;
        if (capture.y == 4u)
        {
            // Array-to-slice view: a slice descriptor whose words are the
            // array's address and static length; the length rides in the
            // layout offset column for the target's immediate.
            snapshot.core.type_id = 128u;
            snapshot.core.flags |= SEMANTIC_LIR_FLAG_ARRAY_PAIR | SEMANTIC_LIR_FLAG_PLACE_VIEW;
            snapshot.layout_word_offset = semantic_array_length[node];
        }
        return snapshot;
    }
    bool compound_assignment = semantic_lir_is_assignment(hir, payload) &&
        payload.d != HIR_ASSIGN_OP_SET && local_count == 3u;
    uint assignment_lhs = semantic_lir_is_assignment(hir, payload)
        ? payload.b : LIR_INVALID;
    HirCore assignment_lhs_core = hir;
    HirPayload assignment_lhs_payload = payload;
    if (assignment_lhs < hir_count)
    {
        assignment_lhs_core = compact_hir_core[assignment_lhs];
        assignment_lhs_payload = compact_hir_payload[assignment_lhs];
    }
    bool assignment_field = assignment_lhs < hir_count &&
        assignment_lhs_core.kind == HIR_MEMBER_EXPR;
    bool assignment_indexed = assignment_lhs < hir_count &&
        assignment_lhs_core.kind == HIR_INDEX_EXPR;
    // A break or continue branches by its loop's recipe and follows none
    // itself, so the one recipe lookup serves both kinds of row.
    bool loop_exit = (hir.kind == HIR_BREAK_STMT || hir.kind == HIR_CONTINUE_STMT) &&
        compact_nearest_loop[node] < hir_count;
    uint recipe_node = loop_exit ? compact_nearest_loop[node] : node;
    HirPayload recipe_payload = loop_exit ? compact_hir_payload[recipe_node] : payload;
    uint iterable = recipe_payload.c;
    uint iterable_kind = semantic_iterable_kind[recipe_node];
    uint iterable_form = iterable < hir_count ? compact_hir_payload[iterable].a : 0u;
    uint array_length = iterable < hir_count
        ? semantic_array_length[iterable] : LIR_INVALID;
    uint iterable_type_kind = iterable < hir_count
        ? receiver_kind(semantic_expr_ref_tag[iterable], semantic_expr_ref_payload[iterable]) : 0u;
    SemanticLoopRecipe owner_recipe = semantic_loop_recipe(
        loop_exit ? compact_hir_core[recipe_node] : hir, recipe_payload,
        iterable_form, iterable_kind, array_length, iterable_type_kind);
    SemanticLoopRecipe loop_recipe = owner_recipe;
    if (loop_exit)
    {
        loop_recipe.kind = SEMANTIC_LOOP_RECIPE_NONE;
        loop_recipe.exhaustion_row = LIR_INVALID;
    }
    bool direct_range_for = loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_RANGE ||
        loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_RANGE_FROM_ZERO ||
        loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_UNBOUNDED_RANGE ||
        loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_UNBOUNDED_RANGE_FROM_ZERO;
    bool range_value_for = loop_recipe.kind == SEMANTIC_LOOP_RECIPE_RANGE_VALUE;
    bool range_for = direct_range_for || range_value_for;
    bool slice_for = loop_recipe.kind == SEMANTIC_LOOP_RECIPE_SLICE;
    bool array_for = loop_recipe.kind == SEMANTIC_LOOP_RECIPE_ARRAY || slice_for;
    HirPayload range_payload;
    range_payload.a = 0u;
    range_payload.b = LIR_INVALID;
    range_payload.c = LIR_INVALID;
    range_payload.d = LIR_INVALID;
    if (direct_range_for && payload.c < hir_count)
        range_payload = compact_hir_payload[payload.c];

    uint row = first_row + local_row;
    uint op = semantic_materialized_op(node, local_row, local_count);
    // A payload sub-pattern binds a name or, naming a variant, checks it.
    // Both read one payload word: one offset walk serves both.
    uint pattern_payload_row = semantic_match_payload_row(node);
    uint pattern_variant = pattern_payload_row != LIR_INVALID
        ? semantic_match_variant_ordinal(node, hir_count) : LIR_INVALID;
    bool match_check = pattern_variant != LIR_INVALID;
    uint match_check_row = match_check ? pattern_payload_row : LIR_INVALID;
    uint match_payload_row = match_check ? LIR_INVALID : pattern_payload_row;
    bool match_binding = match_payload_row != LIR_INVALID;
    uint pattern_word_offset = pattern_payload_row != LIR_INVALID
        ? match_binding_word_offset(compact_match_payloads[pattern_payload_row], hir_count)
        : LIR_INVALID;
    bool imported_constant = imported_constant_for_hir(node, hir_count);
    if (imported_constant)
    {
        uint constant_type = semantic_value_type[node];
        op = scalar_is_float(constant_type)
            ? SEMANTIC_LIR_OP_CONST_F32 : SEMANTIC_LIR_OP_CONST_I32;
    }
    // Compound assignment reads an addressable lhs through the same semantic
    // LOAD contract as an ordinary member/index expression. It is not a
    // declaration lookup: fields and elements have no declaration value ID.
    if (compound_assignment && local_row == 0u &&
        (assignment_field || assignment_indexed))
        op = SEMANTIC_LIR_OP_LOAD;
    // Local constants are represented as zero-argument semantic functions;
    // their name rows therefore lower through the same call instruction as
    // explicit call expressions. Imported constants are projected directly
    // from interface metadata and never receive this call kind.
    // A pattern's scrutinee read is not its variant's constructor call.
    if (op == SEMANTIC_LIR_OP_VALUE_GET && semantic_call_kind[node] == 1u &&
        pattern_payload_row == LIR_INVALID)
        op = SEMANTIC_LIR_OP_CALL;
    if (op == SEMANTIC_LIR_OP_VALUE_GET && semantic_call_kind[node] == 5u &&
        pattern_payload_row == LIR_INVALID)
        op = SEMANTIC_LIR_OP_AGGREGATE_NEW;
    if (loop_recipe.kind != SEMANTIC_LOOP_RECIPE_NONE)
        op = semantic_loop_recipe_op(loop_recipe, local_row);
    if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 2u)
        op = SEMANTIC_LIR_OP_CALL_INTRINSIC;
    else if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 3u)
        op = SEMANTIC_LIR_OP_CALL_HOST;
    else if (op == SEMANTIC_LIR_OP_CALL &&
        (semantic_call_kind[node] == 4u || semantic_call_kind[node] == 6u))
        op = SEMANTIC_LIR_OP_CALL_SYMBOL;
    else if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 5u)
        op = SEMANTIC_LIR_OP_AGGREGATE_NEW;
    bool zero_let = semantic_lir_is_zero_let(hir, payload);
    // A type with no zero value still gets a constant producer, so the store
    // keeps a value edge; both rows carry UNSUPPORTED and the targets reject
    // the declaration at its source.
    uint zero_op = zero_let ? zero_initializer_op(node, hir_count)
                            : SEMANTIC_LIR_OP_INVALID;
    bool zero_unsupported = zero_let && zero_op == SEMANTIC_LIR_OP_INVALID;
    if (zero_let)
        op = local_row != 0u ? SEMANTIC_LIR_OP_VALUE_SET
            : zero_unsupported ? SEMANTIC_LIR_OP_CONST_I32 : zero_op;

    bool match_expression = hir.kind == HIR_MATCH_EXPR;
    bool short_circuit = semantic_lir_is_short_circuit(hir, payload);
    SemanticMatchRecipe match_recipe;
    match_recipe.address_load_count = 0u;
    match_recipe.arm_count = 0u;
    match_recipe.valid = true;
    if (match_expression)
        match_recipe = semantic_match_retained_recipe_for_hir(node, hir_count);
    bool match_result_get = match_expression && local_row + 1u == local_count;
    bool match_address_load = match_expression && local_row < match_recipe.address_load_count;
    bool match_scrutinee_set = match_expression && local_row == match_recipe.address_load_count;
    bool match_arm_instruction = match_expression && semantic_match_is_arm(match_recipe, local_row);
    uint match_phase = match_arm_instruction
        ? semantic_match_phase(match_recipe, local_row) : LIR_INVALID;

    SemanticLirCore core;
    core.type_id = semantic_type_for_hir(node, hir_count);
    uint type_ref_tag;
    semantic_type_ref_for_hir(node, hir_count,
        type_ref_tag, core.type_ref_payload);
    if (type_ref_tag == 1u &&
        scalar_is_known(core.type_ref_payload))
    {
        // Member and call slice bases are projected through their checked
        // element reference after the older scalar cache was populated.
        // Machine selection must use that checked element type, not the
        // still-unclassified cache entry.
        core.type_id = core.type_ref_payload;
    }
    uint match_scalar = match_expression && payload.a < hir_count &&
        semantic_expr_ref_tag[payload.a] == 1u &&
        scalar_is_known(semantic_expr_ref_payload[payload.a])
        ? semantic_expr_ref_payload[payload.a] : 0u;
    if (match_scrutinee_set || match_address_load)
    {
        core.type_id = match_scrutinee_set && match_scalar != 0u
            ? match_scalar : SEMANTIC_LIR_TY_POINTER;
        type_ref_tag = 1u;
        core.type_ref_payload = core.type_id;
    }
    else if (match_check)
    {
        // The scrutinee address, then the arm recipe's scalar tag rows.
        core.type_id = local_row == 0u ? SEMANTIC_LIR_TY_POINTER : 3u;
        type_ref_tag = 1u;
        core.type_ref_payload = core.type_id;
    }
    else if (match_expression && !match_result_get && match_phase != 5u)
    {
        uint arm_row = match_arm_instruction
            ? payload.b + semantic_match_arm_index(match_recipe, local_row) : LIR_INVALID;
        uint pattern = arm_row < active_match_arm_count()
            ? compact_match_arms[arm_row].pattern : LIR_INVALID;
        core.type_id = match_phase == 0u &&
            !scalar_match_pattern(pattern, hir_count) &&
            !wildcard_match_pattern(pattern, hir_count)
            ? SEMANTIC_LIR_TY_POINTER
            : match_scalar != 0u && scalar_match_pattern(pattern, hir_count) &&
                (match_phase == 0u || match_phase == 2u || match_phase == 3u)
            ? match_scalar : 3u;
        type_ref_tag = 1u;
        core.type_ref_payload = core.type_id;
    }
    else if (match_expression)
    {
        // The scalar expression cache cannot encode a checked array result.
        // Both the arm store and final read must keep the projected value
        // type so an i32 array copied into a local uses packed storage at
        // its return boundary as well.
        core.type_id = semantic_value_type[node];
    }
    else if (match_binding)
    {
        HirMatchPayload binding = compact_match_payloads[match_payload_row];
        HirMatchArm arm = compact_match_arms[binding.arm];
        uint match_node = arm.owner;
        if (local_row == 0u)
        {
            core.type_id = SEMANTIC_LIR_TY_POINTER;
            type_ref_tag = 1u;
            core.type_ref_payload = SEMANTIC_LIR_TY_POINTER;
        }
        else
        {
            core.type_id = semantic_value_type[node];
            semantic_type_ref_for_hir(node, hir_count,
                type_ref_tag, core.type_ref_payload);
        }
    }
    if ((op == SEMANTIC_LIR_OP_VALUE_GET || op == SEMANTIC_LIR_OP_VALUE_SET ||
         op == SEMANTIC_LIR_OP_STORE || zero_let) && !match_expression &&
        !match_binding && !match_check && !short_circuit)
        core.type_id = semantic_value_type[node];
    // The six synthetic rows of &&/|| carry the boolean result, even when
    // the RHS compares an aggregate. Its operand's ABI width is not the
    // width of the short-circuit temporary.
    if (short_circuit)
    {
        core.type_id = 2u;
        type_ref_tag = 1u;
        core.type_ref_payload = 2u;
    }
    // A declaration-setting row represents the value being stored, while the
    // statement node itself need not carry an expression type. Preserve the
    // checked RHS reference here so target ABIs can distinguish instantiated
    // aggregates from scalar values without reconstructing declaration syntax.
    if (op == SEMANTIC_LIR_OP_VALUE_SET && !match_expression && !short_circuit && payload.c < hir_count)
        semantic_type_ref_for_hir(payload.c, hir_count,
            type_ref_tag, core.type_ref_payload);
    if (semantic_lir_is_assignment(hir, payload) && payload.b < hir_count)
    {
        // The lvalue's declaration type is not necessarily the type of the
        // value being updated: indexing an array and selecting a struct field
        // produce their element/field type. Preserve the checked expression
        // result so target selection can distinguish signed and unsigned
        // compound operations.
        core.type_id = semantic_type_for_hir(payload.b, hir_count);
        semantic_type_ref_for_hir(payload.b, hir_count,
            type_ref_tag, core.type_ref_payload);
        // The checked lvalue reference also owns machine selection. Generic
        // record members can acquire their slice element type after the old
        // scalar expression cache was computed; an i32 store still needs its
        // four-byte element stride.
        if (type_ref_tag == 1u && scalar_is_known(core.type_ref_payload))
            core.type_id = core.type_ref_payload;
    }
    if (op == SEMANTIC_LIR_OP_RETURN &&
        semantic_function_id[node] != LIR_INVALID)
    {
        core.type_id = semantic_lir_functions[semantic_function_id[node]].result_type;
        semantic_type_ref_for_hir(payload.b, hir_count,
            type_ref_tag, core.type_ref_payload);
        // A bare `return;` carries no value even in `fn main()`, whose
        // entry ABI result is i32: the target clears the exit register.
        // Typing it as the function's result would make SSA read its
        // absent operand.
        if (hir.kind != HIR_CONST_ITEM && payload.b >= hir_count)
            core.type_id = 1u;
    }
    if (range_for)
    {
        // The checked loop binder owns induction and bound identity. A named
        // range's two address reads instead retain its full value graph.
        semantic_type_ref_for_hir(node, hir_count, type_ref_tag, core.type_ref_payload);
        core.type_id = type_ref_tag == 1u && scalar_is_integer(core.type_ref_payload)
            ? core.type_ref_payload : 0u;
        if (range_value_for && (local_row == 0u || local_row == 3u))
        {
            semantic_type_ref_for_hir(payload.c, hir_count, type_ref_tag, core.type_ref_payload);
            core.type_id = semantic_type_for_hir(payload.c, hir_count);
        }
    }
    if (array_for)
    {
        core.type_id = 3u;
        type_ref_tag = 1u;
        core.type_ref_payload = 3u;
        if (local_row == (slice_for ? 2u : 9u))
        {
            // This synthetic read carries the entire iterable. The scalar
            // expression cache omits fixed arrays; preserve the checked
            // value projection so indexing selects the array's real storage.
            core.type_id = semantic_value_type[payload.c];
            semantic_type_ref_for_hir(payload.c, hir_count,
                type_ref_tag, core.type_ref_payload);
        }
        else if (local_row == 11u || local_row == 12u)
        {
            // The checked array-index projection stores the for binding's
            // element type on the loop HIR row. The token-value table has no
            // declaration row for this synthetic load/store pair.
            core.type_id = semantic_type_for_hir(node, hir_count);
            semantic_type_ref_for_hir(node, hir_count,
                type_ref_tag, core.type_ref_payload);
            if (type_ref_tag == 1u && scalar_is_known(core.type_ref_payload))
                core.type_id = core.type_ref_payload;
        }
    }
    // Comparisons produce bool but machine selection depends on the operand
    // representation. The semantic instruction type therefore records the
    // compared value type for this opcode.
    // Loop-recipe comparisons operate on the synthetic integer induction
    // value and bound produced by the recipe. `payload.b` belongs to the
    // source `for` statement (the binding token), not to this synthetic
    // comparison; interpreting it as an operand HIR can borrow an unrelated
    // scalar type from another packed module and select an f32 comparison.
    if (op == SEMANTIC_LIR_OP_COMPARE && !match_expression &&
        !range_for && !array_for && payload.b < hir_count)
    {
        uint compared_type_node = payload.b;
        // An unsuffixed literal on the left takes the checked type of its
        // right operand for machine comparison. Otherwise char and high-bit
        // u32 comparisons incorrectly select signed i32 condition codes.
        if (payload.c < hir_count &&
            compact_hir_core[payload.b].kind == HIR_LITERAL_EXPR)
        {
            uint literal_form = compact_hir_payload[payload.b].a;
            uint right_type = semantic_type_for_hir(payload.c, hir_count);
            if ((literal_form == HIR_EXPR_CHAR && right_type == 6u) ||
                (literal_form == HIR_EXPR_INT && right_type == 4u))
                compared_type_node = payload.c;
        }
        core.type_id = semantic_type_for_hir(compared_type_node, hir_count);
        semantic_type_ref_for_hir(compared_type_node, hir_count,
            type_ref_tag, core.type_ref_payload);
    }
    if (type_ref_tag == TYPE_REF_INSTANCE &&
        core.type_ref_payload < checked_type_capacity() &&
        type_instance_kind[core.type_ref_payload] == 4u)
        core.type_id = SEMANTIC_LIR_TY_POINTER;
    if (op == SEMANTIC_LIR_OP_CONST_I32 && scalar_is_wide_integer(core.type_id))
        op = SEMANTIC_LIR_OP_CONST_I64;
    if (op == SEMANTIC_LIR_OP_CONST_F32 && core.type_id == SCALAR_F64)
        op = SEMANTIC_LIR_OP_CONST_F64;
    core.flags = ((type_ref_tag & 3u) << SEMANTIC_LIR_TYPE_REF_TAG_SHIFT) |
        ((op & 0x3fu) << SEMANTIC_LIR_OP_SHIFT);
    if (op == SEMANTIC_LIR_OP_CALL_SYMBOL && semantic_call_kind[node] == 6u)
        core.flags |= SEMANTIC_LIR_FLAG_NATIVE_C_CALL;
    // Field word offsets and indexed-array lengths are mutually exclusive
    // projection metadata. They share the existing per-row side table instead
    // of widening every semantic instruction.
    uint projection_metadata = LIR_INVALID;
    uint value_node = (match_scrutinee_set || match_address_load) ? payload.a
        : op == SEMANTIC_LIR_OP_VALUE_SET && payload.c < hir_count
        ? payload.c : node;
    if (op == SEMANTIC_LIR_OP_STORE && assignment_lhs < hir_count)
        value_node = assignment_lhs;
    // A loop's binding-value rows take the iterable's width instead; every
    // loop row overrides the width below, so one lookup serves both.
    bool loop_value_row = (range_value_for && (local_row == 0u || local_row == 3u)) ||
        (array_for && local_row == (slice_for ? 2u : 9u));
    // A checked instance owns its layout even when it occupies zero words.
    // Falling back to its generic declaration would turn a concrete empty
    // value into an unresolved layout (or an unrelated provisional width).
    // An unlaid-out stored value falls back to the setting row's own width;
    // the loop keeps one copy of the width walk.
    bool checked_value_layout = value_node < hir_count &&
        semantic_expr_ref_tag[value_node] == TYPE_REF_INSTANCE &&
        semantic_expr_ref_payload[value_node] < checked_type_capacity();
    uint value_words = 0u;
    [loop]
    for (uint attempt = 0u; attempt < 2u; attempt++)
    {
        core.value_word_count = aggregate_word_count_for_hir(
            attempt != 0u ? node : loop_value_row ? payload.c : value_node, hir_count);
        if (attempt == 0u) value_words = core.value_word_count;
        if (checked_value_layout || core.value_word_count != 0u ||
            op != SEMANTIC_LIR_OP_VALUE_SET)
            break;
    }
    if (!checked_value_layout && core.value_word_count == 0u)
        core.value_word_count = aggregate_word_count_for_type(core.type_id, hir_count);
    // A return statement has no independent instance reference. Its nominal
    // type can name an unresolved generic declaration even when the checked
    // function signature has a concrete layout. Use that signature's width.
    if (op == SEMANTIC_LIR_OP_RETURN && semantic_function_id[node] != LIR_INVALID)
    {
        uint return_words = semantic_lir_functions[semantic_function_id[node]].result_word_count;
        core.value_word_count = return_words;
    }
    // Comparison retains its operand type for machine selection, but its
    // produced value is one scalar bool. Inheriting an enum operand's word
    // count makes a subsequent &&/|| store dereference that bool as a pointer.
    if (op == SEMANTIC_LIR_OP_COMPARE || short_circuit)
        core.value_word_count = 0u;
    // A match retains the terminal enum address. Pointer normalization and
    // the synthetic store never copy the enum or inherit the result width.
    if (match_scrutinee_set || match_address_load || match_check)
        core.value_word_count = 0u;
    // Aggregate parameters already use the native pointer representation.
    // Reading that address does not need a specialization of its payload.
    if (op == SEMANTIC_LIR_OP_VALUE_GET &&
        core.value_word_count == LIR_INVALID &&
        opaque_generic_enum_reference(node, hir_count))
        core.value_word_count = 0u;
    if (range_for)
        core.value_word_count = loop_value_row ? value_words : 0u;
    if (array_for && (local_row == 11u || local_row == 12u))
    {
        // semantic_array_length[node] describes the iterable, not one loop
        // binding value. Prefer the projected element ABI width here.
        uint element_words = semantic_aggregate_word_count[node];
        uint element_decl_token = semantic_aggregate_decl_token[node];
        if (element_decl_token < gParams.n_tokens)
        {
            uint element_hir = semantic_aggregate_hir_by_name_token[element_decl_token];
            if (element_hir < hir_count)
                element_words = semantic_struct_word_count_by_hir[element_hir];
        }
        if (element_words == 0u)
            element_words = aggregate_word_count_for_type(core.type_id, hir_count);
        core.value_word_count = element_words;
    }
    else if (array_for && loop_value_row)
        core.value_word_count = value_words;
    else if (array_for)
    {
        // Induction values, bounds, and control rows are scalar recipe
        // temporaries. The loop statement's iterable layout must not turn
        // `index = 0` into an aggregate copy through the null address.
        core.value_word_count = 0u;
    }
    // Literal arrays own a compact, dense element range even when type
    // projection has not published semantic_array_length for the expression.
    // Allocate ABI words rather than element rows: an array of three two-word
    // structs occupies six words even though it has only three HIR elements.
    // The checked array artifact carries the element declaration identity;
    // semantic struct layout turns that identity into the ABI element width.
    if (op == SEMANTIC_LIR_OP_AGGREGATE_NEW && hir.kind == HIR_ARRAY_EXPR)
    {
        uint element_count = compact_array_element_owner_count[node];
        uint element_words = 1u;
        uint decl_token = semantic_aggregate_decl_token[node];
        if (decl_token < gParams.n_tokens)
        {
            uint struct_hir = semantic_aggregate_hir_by_name_token[decl_token];
            if (struct_hir < hir_count)
                element_words = max(
                    semantic_struct_word_count_by_hir[struct_hir], 1u);
        }
        uint projected_words = semantic_aggregate_word_count[node];
        bool checked_array = type_ref_tag == TYPE_REF_INSTANCE &&
            core.type_ref_payload < checked_type_capacity() &&
            type_instance_kind[core.type_ref_payload] == 2u;
        core.value_word_count = checked_array ? type_instance_native_words[core.type_ref_payload]
            : projected_words != 0u && projected_words != LIR_INVALID
            ? projected_words : element_count * element_words;
    }
    if (op == SEMANTIC_LIR_OP_AGGREGATE_NEW && semantic_call_kind[node] == 5u)
    {
        uint concrete_words = concrete_enum_instance_words(
            contextual_enum_instance(node, hir_count), hir_count);
        uint projected_words = semantic_aggregate_word_count[node];
        core.value_word_count = concrete_words != 0u ? concrete_words
            : projected_words != 0u && projected_words != LIR_INVALID
                ? projected_words
            : hir.kind == HIR_CALL_EXPR
                ? enum_constructor_word_count(node, payload, hir_count) : 1u;
        uint owner = enum_constructor_owner(node, hir_count);
        if (owner < hir_count &&
            semantic_struct_word_count_by_hir[owner] == LIR_INVALID &&
            concrete_words == 0u)
            core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
    }
    if ((op == SEMANTIC_LIR_OP_LOAD || op == SEMANTIC_LIR_OP_STORE) &&
        (hir.kind == HIR_INDEX_EXPR || assignment_indexed))
    {
        core.flags |= SEMANTIC_LIR_FLAG_INDEXED;
        uint indexed_base = assignment_indexed
            ? assignment_lhs_payload.b : payload.b;
        if (indexed_base < hir_count)
        {
            projection_metadata = semantic_array_length[indexed_base];
            if (projection_metadata == LIR_INVALID)
            {
                uint projected_words = aggregate_word_count_for_hir(
                    indexed_base, hir_count);
                if (projected_words != 0u)
                    projection_metadata = projected_words;
            }
        }
    }
    // Bounds describe the terminal indexed container, even when the actual
    // value is &slice or &&slice. Only the checked value root owns descriptor
    // shape; reference reads/calls must remain one pointer.
    bool slice_value = receiver_kind(type_ref_tag, core.type_ref_payload) == 3u;
    bool slice_result_call = hir.kind == HIR_CALL_EXPR && semantic_lir_is_call(op);
    if (slice_value &&
        ((op == SEMANTIC_LIR_OP_VALUE_GET &&
          (!match_binding || local_row != 0u) &&
          (!match_expression || match_result_get)) ||
         (op == SEMANTIC_LIR_OP_LOAD &&
          (hir.kind == HIR_MEMBER_EXPR || hir.kind == HIR_INDEX_EXPR || match_binding)) ||
         slice_result_call))
        core.flags |= SEMANTIC_LIR_FLAG_ARRAY_PAIR;
    if ((op == SEMANTIC_LIR_OP_LOAD || op == SEMANTIC_LIR_OP_STORE) &&
        (hir.kind == HIR_MEMBER_EXPR || assignment_field))
        core.flags |= SEMANTIC_LIR_FLAG_FIELD;
    if ((match_expression && op == SEMANTIC_LIR_OP_LOAD) ||
        ((match_binding || match_check) && local_row == 1u))
        core.flags |= SEMANTIC_LIR_FLAG_FIELD;
    // The layout passes mark by-value cycles and unsupported nested payloads
    // with LIR_INVALID. Never let that sentinel become an x86 copy width or
    // silently skip the initialization of a match scrutinee.
    if (op == SEMANTIC_LIR_OP_INVALID || zero_unsupported ||
        core.value_word_count == LIR_INVALID ||
        (match_binding && local_row != 0u && type_ref_tag == 2u))
        core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
    if (match_expression && match_phase == 6u)
        core.flags |= SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID;
    if (range_for && (semantic_expr_ref_tag[node] != 1u ||
        !scalar_is_integer(semantic_expr_ref_payload[node])))
        core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED_FOR_ITERABLE;
    if (semantic_lir_is_for(hir, payload) &&
        loop_recipe.kind == SEMANTIC_LOOP_RECIPE_NONE)
        core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED_FOR_ITERABLE;
    if (compound_assignment && !assignment_field && !assignment_indexed &&
        (payload.b >= hir_count || semantic_value_id[payload.b] == LIR_INVALID))
        core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
    if (semantic_lir_is_control(hir, payload) || short_circuit)
        core.flags |= SEMANTIC_LIR_FLAG_SYNTHETIC_CONTROL;
    if (hir.kind == HIR_CONTINUE_STMT)
        core.flags |= SEMANTIC_LIR_FLAG_BRANCH_CONTINUE;
    uint enclosing_loop = compact_nearest_loop[node];
    bool explicit_loop_branch =
        (hir.kind == HIR_BREAK_STMT || hir.kind == HIR_CONTINUE_STMT) &&
        enclosing_loop < hir_count;
    uint explicit_branch_depth = 0u;
    if (explicit_loop_branch)
    {
        HirCore loop_core = compact_hir_core[enclosing_loop];
        uint branch_depth = semantic_control_depth_by_hir[node];
        uint loop_depth = semantic_control_depth_by_hir[enclosing_loop];
        if (branch_depth < loop_depth)
            explicit_loop_branch = false;
        else
        {
            explicit_branch_depth = uint(branch_depth - loop_depth);
            if (hir.kind == HIR_BREAK_STMT)
                explicit_branch_depth += loop_core.kind == HIR_FOR_STMT ? 2u : 1u;
            core.flags |= SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID;
        }
    }
    bool structured_loop = semantic_lir_is_loop(hir, payload);
    if (loop_recipe.kind == SEMANTIC_LOOP_RECIPE_NONE &&
        structured_loop && (local_row == 2u || local_row == 3u))
        core.flags |= SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID;
    if (loop_recipe.kind == SEMANTIC_LOOP_RECIPE_NONE &&
        structured_loop && local_row == 2u)
        core.flags |= SEMANTIC_LIR_FLAG_BRANCH_FALSE;
    if (loop_recipe.kind != SEMANTIC_LOOP_RECIPE_NONE)
        core.flags |= semantic_loop_recipe_flags(loop_recipe, local_row);
    if (slice_for && local_row == 2u)
        core.flags |= SEMANTIC_LIR_FLAG_ARRAY_PAIR;
    if (slice_for && (payload.c >= hir_count ||
        (compact_hir_core[payload.c].kind != HIR_NAME_EXPR &&
         compact_hir_core[payload.c].kind != HIR_PATH_EXPR) ||
        semantic_value_id[payload.c] == LIR_INVALID))
        core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED_FOR_ITERABLE;
    if (array_for && (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
        projection_metadata = array_length;
    SemanticLirOperands operands;
    operands.result = row;
    operands.a = LIR_INVALID;
    operands.b = LIR_INVALID;
    operands.c = LIR_INVALID;
    uint layout_word_offset = projection_metadata;

    if (short_circuit)
    {
        uint declaration = gParams.n_tokens + node;
        if (local_row == 0u || local_row == 3u)
        {
            operands.a = declaration;
            operands.b = lir_for_hir(local_row == 0u ? payload.b : payload.c, hir_count);
        }
        else if (local_row == 1u)
            operands.a = payload.a == HIR_EXPR_OR
                ? lir_for_hir(payload.b, hir_count) : declaration;
        else if (local_row == 2u)
        {
            operands.a = first_row + 1u;
            operands.b = first_row + 4u;
            operands.c = 0u;
        }
        else if (local_row == 5u)
            operands.a = declaration;
    }
    else if (match_expression)
    {
        uint result_declaration = gParams.n_tokens + node;
        uint scrutinee_declaration = gParams.n_tokens + hir_count + node;
        if (match_result_get)
            operands.a = result_declaration;
        else if (match_address_load)
        {
            operands.a = local_row == 0u ? lir_for_value_hir(payload.a, hir_count)
                : first_row + local_row - 1u;
            operands.b = 0u;
            operands.c = 1u;
            layout_word_offset = 0u;
        }
        else if (match_scrutinee_set)
        {
            operands.a = scrutinee_declaration;
            operands.b = match_recipe.address_load_count == 0u
                ? lir_for_value_hir(payload.a, hir_count)
                : first_row + match_recipe.address_load_count - 1u;
        }
        else if (match_arm_instruction)
        {
            uint arm_index = semantic_match_arm_index(match_recipe, local_row);
            uint arm_row = payload.b + arm_index;
            HirMatchArm arm = compact_match_arms[arm_row];
            uint arm_first = first_row + semantic_match_arm_start(match_recipe, arm_index);
            uint variant = semantic_match_variant_ordinal(arm.pattern, hir_count);
            bool scalar_pattern = scalar_match_pattern(arm.pattern, hir_count);
            bool wildcard_pattern = wildcard_match_pattern(arm.pattern, hir_count);
            if (match_phase == 0u)
                operands.a = scrutinee_declaration;
            else if (match_phase == 1u)
            {
                if (!scalar_pattern && !wildcard_pattern)
                {
                    operands.a = arm_first;
                    operands.b = 0u;
                    layout_word_offset = 0u;
                }
            }
            else if (match_phase == 2u)
            {
                uint2 constant = wildcard_pattern ? uint2(1u, 0u) : scalar_pattern
                    ? scalar_match_pattern_value(arm.pattern, hir_count) : uint2(variant, 0u);
                operands.a = constant.x;
                if (op == SEMANTIC_LIR_OP_CONST_I64) operands.b = constant.y;
            }
            else if (match_phase == 3u)
            {
                if (!wildcard_pattern)
                {
                    operands.a = scalar_pattern ? arm_first : arm_first + 1u;
                    operands.b = arm_first + 2u;
                    operands.c = 0u;
                }
            }
            else if (match_phase == 4u)
            {
                operands.a = wildcard_pattern ? arm_first + 2u
                    : arm_first + 3u;
                operands.b = arm_first + 7u;
                operands.c = 0u;
            }
            else if (match_phase == 5u)
            {
                operands.a = result_declaration;
                operands.b = lir_for_value_hir(arm.result, hir_count);
            }
            else if (match_phase == 6u)
            {
                operands.a = first_row + local_count - 2u;
                // The arm is nested in its IF, its nested checks' IFs, and
                // the enclosing match BLOCK.
                operands.b = 1u + match_arm_check_count(arm_row, hir_count);
            }
        }
    }
    else if (match_check)
    {
        HirMatchPayload check = compact_match_payloads[match_check_row];
        uint scrutinee_declaration = gParams.n_tokens + hir_count + compact_match_arms[check.arm].owner;
        uint word_offset = pattern_word_offset;
        if (word_offset == LIR_INVALID)
            core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
        if (local_row == 0u)
            operands.a = scrutinee_declaration;
        else if (local_row == 1u)
        {
            operands.a = first_row;
            operands.b = word_offset;
            layout_word_offset = word_offset;
        }
        else if (local_row == 2u)
            operands.a = pattern_variant;
        else if (local_row == 3u)
        {
            operands.a = first_row + 1u;
            operands.b = first_row + 2u;
            operands.c = 0u;
        }
        else if (local_row == 4u)
        {
            operands.a = first_row + 3u;
            operands.b = first_row + 5u;
            operands.c = 0u;
        }
    }
    else if (match_binding)
    {
        HirMatchPayload binding = compact_match_payloads[match_payload_row];
        HirMatchArm arm = compact_match_arms[binding.arm];
        uint match_node = arm.owner;
        uint scrutinee_declaration = gParams.n_tokens + hir_count + match_node;
        uint word_offset = pattern_word_offset;
        if (word_offset == LIR_INVALID)
            core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
        if (local_row == 0u)
            operands.a = scrutinee_declaration;
        else if (local_row == 1u)
        {
            operands.a = first_row;
            operands.b = word_offset;
            operands.c = 1u;
            layout_word_offset = word_offset;
        }
        else
        {
            operands.a = semantic_value_id[node];
            operands.b = first_row + 1u;
        }
    }
    else if (loop_recipe.kind != SEMANTIC_LOOP_RECIPE_NONE)
    {
        SemanticLoopOperandRecipe recipe =
            semantic_loop_operand_recipe(loop_recipe, local_row);
        operands.a = materialize_loop_operand(
            recipe.a, node, first_row, hir_count, payload, range_payload, core.type_id);
        operands.b = materialize_loop_operand(
            recipe.b, node, first_row, hir_count, payload, range_payload, core.type_id);
        operands.c = materialize_loop_operand(
            recipe.c, node, first_row, hir_count, payload, range_payload, core.type_id);
        // Synthetic zero/one rows have no high operand in the base recipe.
        if (op == SEMANTIC_LIR_OP_CONST_I64 && recipe.b == LOOP_OPERAND_NONE) operands.b = 0u;
    }
    else if (op == SEMANTIC_LIR_OP_CONST_I32 || op == SEMANTIC_LIR_OP_CONST_I64 || op == SEMANTIC_LIR_OP_CONST_F32 ||
        op == SEMANTIC_LIR_OP_CONST_F64 || op == SEMANTIC_LIR_OP_CONST_STRING)
    {
        operands.a = imported_constant
            ? semantic_value_const_by_hir[node].x
            : payload.b;
        if (op == SEMANTIC_LIR_OP_CONST_I64)
            operands.b = imported_constant ? semantic_value_const_by_hir[node].y : payload.c;
        if (op == SEMANTIC_LIR_OP_CONST_F64)
        {
            // HIR owns independently rounded f32/f64 candidates. The checked
            // scalar chooses a lane; no target-side reparse or conversion.
            operands.a = imported_constant ? semantic_value_const_by_hir[node].x : payload.c;
            operands.b = imported_constant ? semantic_value_const_by_hir[node].y : payload.d;
        }
        if (op == SEMANTIC_LIR_OP_CONST_I32 && payload.a == HIR_EXPR_TRUE)
            operands.a = 1u;
        else if (op == SEMANTIC_LIR_OP_CONST_I32 && payload.a == HIR_EXPR_FALSE)
            operands.a = 0u;

    }
    else if (op == SEMANTIC_LIR_OP_VALUE_GET)
        operands.a = compound_assignment && payload.b < hir_count
            ? semantic_value_id[payload.b] : semantic_value_id[node];
    else if (op == SEMANTIC_LIR_OP_CALL ||
             op == SEMANTIC_LIR_OP_CALL_INTRINSIC ||
             op == SEMANTIC_LIR_OP_CALL_HOST)
    {
        operands.a = semantic_call_target[node];
        operands.b = payload.b;
        operands.c = payload.c;
    }
    else if (op == SEMANTIC_LIR_OP_CALL_SYMBOL)
    {
        operands.a = semantic_call_symbol_library_id[node];
        operands.b = semantic_call_symbol_unit_id[node];
        operands.c = semantic_call_symbol_local_index[node];
    }
    else if (op == SEMANTIC_LIR_OP_VALUE_SET)
    {
        operands.a = semantic_value_id[node];
        operands.b = lir_for_value_hir(payload.c, hir_count);
    }
    else if (op == SEMANTIC_LIR_OP_RETURN)
        operands.a = lir_for_value_hir(hir.kind == HIR_CONST_ITEM
            ? compact_const_value[node] : payload.b, hir_count);
    else if (op == SEMANTIC_LIR_OP_STORE)
    {
        uint stored_value = compound_assignment ? first_row + 1u
            : lir_for_value_hir(payload.c, hir_count);
        if (assignment_field)
        {
            operands.a = lir_for_hir(assignment_lhs_payload.b, hir_count);
            uint field_words;
            member_word_layout(assignment_lhs,
                semantic_member_field_ordinal[assignment_lhs], hir_count,
                layout_word_offset, field_words);
            if (layout_word_offset == LIR_INVALID || field_words == LIR_INVALID)
                core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
            operands.b = semantic_member_field_ordinal[assignment_lhs];
            operands.c = stored_value;
        }
        else if (assignment_indexed)
        {
            operands.a = lir_for_hir(assignment_lhs_payload.b, hir_count);
            operands.b = lir_for_hir(assignment_lhs_payload.c, hir_count);
            operands.c = stored_value;
        }
        else
        {
            operands.a = payload.b < hir_count
                ? semantic_value_id[payload.b] : LIR_INVALID;
            operands.b = stored_value;
        }
    }
    else if (compound_assignment && local_row == 1u)
    {
        operands.a = first_row;
        operands.b = lir_for_value_hir(payload.c, hir_count);
    }
    else if (structured_loop && op == SEMANTIC_LIR_OP_BRANCH_IF)
    {
        operands.a = lir_for_value_hir(payload.b, hir_count);
        operands.b = 1u;
        operands.c = first_row + 5u;
    }
    else if (structured_loop && op == SEMANTIC_LIR_OP_BRANCH)
    {
        operands.a = first_row + 1u;
        operands.b = 0u;
    }
    else if (op == SEMANTIC_LIR_OP_IF_BEGIN)
    {
        operands.a = lir_for_value_hir(payload.b, hir_count);
        // With an else arm, false control skips the synthetic ELSE branch and
        // enters the following body. Without one it targets CONTROL_END. A
        // contract (4 rows) has an else arm: its TRAP.
        bool else_arm = local_count >= 3u;
        operands.b = else_arm ? first_row + 1u : first_row + local_count - 1u;
        operands.c = else_arm ? 1u : 0u;
    }
    else if (op == SEMANTIC_LIR_OP_ELSE)
        operands.a = first_row + local_count - 1u;
    else if (op == SEMANTIC_LIR_OP_LOOP_BEGIN)
    {
        operands.a = lir_for_value_hir(payload.b, hir_count);
        // Control regions are semantic HIR identities rather than values.
        operands.b = payload.c;
        operands.c = payload.d;
    }
    else if (op == SEMANTIC_LIR_OP_AGGREGATE_NEW)
    {
        bool array = hir.kind == HIR_ARRAY_EXPR;
        // `[value; count]` keeps its one element row; a zero value needs no
        // element at all, so it lowers as the zero aggregate of its type.
        bool zero_repeat = array && payload.a == HIR_ARRAY_REPEAT_ZERO;
        bool repeat = array && hir_array_is_repeat(hir, payload);
        bool enum_constructor = semantic_call_kind[node] == 5u;
        operands.a = array ? compact_array_element_start[node]
            : enum_constructor
                ? compact_array_element_row_count[0u] + compact_field_count[0u] +
                    (hir.kind == HIR_CALL_EXPR ? payload.b : 0u)
                : compact_array_element_row_count[0u] + payload.b;
        operands.b = zero_repeat ? 0u
            : array ? compact_array_element_owner_count[node]
            : enum_constructor && hir.kind != HIR_CALL_EXPR ? 0u : payload.c;
        // High bit distinguishes a tagged enum aggregate; low bits contain
        // the checked declaration ordinal. Struct literals retain their
        // existing nonzero marker and arrays retain zero.
        operands.c = enum_constructor
            ? SEMANTIC_LIR_AGGREGATE_ENUM | semantic_call_target[node]
            : zero_repeat ? SEMANTIC_LIR_AGGREGATE_ZERO
            : repeat ? SEMANTIC_LIR_AGGREGATE_REPEAT
            : array ? 0u : 1u;
    }
    else if (op == SEMANTIC_LIR_OP_LOAD && (hir.kind == HIR_MEMBER_EXPR || assignment_field))
    {
        // The compact member payload already names the canonical receiver
        // expression. Following its enclosing expression root here can turn
        // `pair` in `pair.left + pair.right` into the binary result and create
        // a target-level use-before-definition cycle.
        uint member = assignment_field ? assignment_lhs : node;
        HirPayload member_payload = assignment_field ? assignment_lhs_payload : payload;
        operands.a = lir_for_hir(member_payload.b, hir_count);
        member_word_layout(member, semantic_member_field_ordinal[member],
            hir_count, layout_word_offset, operands.c);
        if (layout_word_offset == LIR_INVALID || operands.c == LIR_INVALID)
            core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
        operands.b = semantic_member_field_ordinal[member];
    }
    else if (op == SEMANTIC_LIR_OP_LOAD && assignment_indexed)
    {
        operands.a = lir_for_hir(assignment_lhs_payload.b, hir_count);
        operands.b = lir_for_hir(assignment_lhs_payload.c, hir_count);
    }
    else if (op == SEMANTIC_LIR_OP_LOAD && hir.kind == HIR_INDEX_EXPR)
    {
        operands.a = lir_for_hir(payload.b, hir_count);
        operands.b = lir_for_hir(payload.c, hir_count);
    }
    else if (op == SEMANTIC_LIR_OP_BRANCH)
    {
        operands.a = lir_for_hir(compact_nearest_loop[node], hir_count);
        if (operands.a != LIR_INVALID)
        {
            bool recipe_loop = owner_recipe.kind != SEMANTIC_LOOP_RECIPE_NONE;
            operands.a += recipe_loop
                ? (hir.kind == HIR_CONTINUE_STMT ? semantic_loop_continue_row(owner_recipe) : owner_recipe.row_count - 1u)
                : (hir.kind == HIR_CONTINUE_STMT ? 1u : 5u);
        }
        operands.b = explicit_loop_branch ? explicit_branch_depth : LIR_INVALID;
    }
    else
    {
        // Operator payloads are immediate child identities. The expression
        // root is a scheduling relation, not a value alias: following it here
        // would replace both children with the operator itself. Statement
        // payloads above may still refer to forwarding wrappers and therefore
        // deliberately resolve their complete expression result.
        operands.a = lir_for_hir(payload.b, hir_count);
        // A conversion's payload.c is its target type row, which has no
        // value. Its metadata operand is the source's checked scalar type.
        operands.b = op == SEMANTIC_LIR_OP_CONVERT
            ? semantic_type_for_hir(payload.b, hir_count)
            : lir_for_hir(payload.c, hir_count);
    }
    if (zero_let)
    {
        // A zero constant (both literal words zero) or a zero-filled
        // aggregate with no elements, then the store of that row.
        operands.a = local_row == 0u ? 0u : semantic_value_id[node];
        operands.b = local_row == 0u ? 0u : first_row;
        operands.c = op == SEMANTIC_LIR_OP_AGGREGATE_NEW
            ? SEMANTIC_LIR_AGGREGATE_ZERO : LIR_INVALID;
    }
    if (op == SEMANTIC_LIR_OP_CALL_INTRINSIC && intrinsic_slice_from_raw_parts(operands.a))
    {
        // Raw views publish the documented convention: packed i32 (+4),
        // packed bytes for u8 (+1), and descending native words otherwise.
        // The checked graph owns the compound width.
        layout_word_offset = LIR_INVALID;
        if (operands.a == INTRINSIC_I32_SLICE_FROM_RAW_PARTS)
            layout_word_offset = 4u;
        else if (type_ref_tag == TYPE_REF_INSTANCE && core.type_ref_payload < checked_type_capacity() &&
            type_instance_kind[core.type_ref_payload] == 3u)
        {
            uint element_tag = type_instance_elem_ref_tag[core.type_ref_payload];
            uint element_payload = type_instance_elem_ref_payload[core.type_ref_payload];
            uint words = concrete_type_ref_words(element_tag, element_payload, hir_count);
            if (element_tag == 1u && element_payload == 3u) layout_word_offset = 4u;
            else if (element_tag == 1u && element_payload == 13u) layout_word_offset = 1u;
            else if (words != LIR_INVALID && words <= 0x0fffffffu)
                layout_word_offset = 0u - words * 8u;
        }
    }
    // Field operands are target-independent ordinals. Explicit member HIR
    // above computes a potentially wider flattened x86 layout offset; field
    // operations synthesized by a lowering recipe have no member node and
    // therefore use their ordinal as the offset for the flat scalar record
    // described by that recipe.
    if (layout_word_offset == LIR_INVALID &&
        (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u)
        layout_word_offset = operands.b;
    // Operation payload belongs in operands, never in the semantic flag
    // namespace. Comparison predicates range from 0..5 and previously
    // collided with UNSUPPORTED/SYNTHETIC_CONTROL/BRANCH_CONTINUE.
    if (op == SEMANTIC_LIR_OP_COMPARE && !match_expression)
        operands.c = range_for || array_for
            ? ((range_payload.a == HIR_EXPR_RANGE_INCLUSIVE ||
                range_payload.a == HIR_EXPR_RANGE_TO_INCLUSIVE || iterable_kind == 2u)
                ? 4u : 2u)
            : comparison_predicate(payload.a);

    if (range_for && loop_recipe.exhaustion_row != LIR_INVALID &&
        local_row == loop_recipe.exhaustion_row + 1u)
        operands.c = 1u; // current != terminal bound

    // Native signed8/16 values use canonical sign-extended32, while the
    // portable constant pair stores only declared-width bits. Normalize
    // before known-value analysis or immediate ABI expansion can see it.
    if (op == SEMANTIC_LIR_OP_CONST_I32 && scalar_is_narrow_integer(core.type_id))
    {
        uint bits = scalar_integer_bits(core.type_id);
        operands.a = scalar_is_signed_integer(core.type_id)
            ? uint(int(operands.a << (32u - bits)) >> (32u - bits))
            : operands.a & ((1u << bits) - 1u);
    }
    SemanticLirRow result;
    result.core = core;
    result.operands = operands;
    result.layout_word_offset = layout_word_offset;
    return result;
}

// Place lowering owns the distinction between a declaration's stable cell,
// a projection of that cell, and a value captured from it. Receiver lookup
// supplies only the checked type adjustment. The one temporary cell is the
// call-owned local of a borrowed receiver that is not a place.
uint place_original_recipe_count(uint node)
{
    return semantic_place_original_count[node] -
        (semantic_argument_value_layout[node].x != 0u ? 1u : 0u);
}

SemanticLirSchedule place_semantic_schedule(uint node, uint local_row, uint hir_count)
{
    HirCore hir = compact_hir_core[node];
    if (hir.kind == 3u && semantic_place_function_flags[node] != 0u)
    {
        SemanticLirSchedule schedule;
        schedule.execution_region = hir.token_start;
        schedule.execution_rank = 0u;
        schedule.execution_tie = local_row;
        return schedule;
    }
    uint original = semantic_place_original_count[node];
    uint recipe = place_original_recipe_count(node);
    bool appended = local_row >= original;
    bool snapshot = local_row == recipe && local_row < original;
    bool final_value = ((hir.kind - HIR_MATCH_EXPR) & ~2u) == 0u ||
        semantic_lir_is_short_circuit(hir, compact_hir_payload[node]);
    uint source = snapshot || appended ? (final_value ? recipe - 1u : 0u) : local_row;
    SemanticLirSchedule schedule = semantic_schedule(node, source, recipe,
        hir_count, hir, compact_hir_links[node], compact_hir_payload[node]);
    if (snapshot) schedule.execution_tie += 1u;
    if (appended) schedule.execution_tie += 1u + local_row - original;
    return schedule;
}

void place_set_op(inout SemanticLirCore core, uint op)
{
    core.flags = (core.flags & ~SEMANTIC_LIR_OP_MASK) |
        (op << SEMANTIC_LIR_OP_SHIFT);
}

void place_set_type(inout SemanticLirCore core, uint tag, uint payload, uint hir_count)
{
    core.type_id = receiver_machine_type(tag, payload);
    core.type_ref_payload = payload;
    core.flags = (core.flags & ~(SEMANTIC_LIR_TYPE_REF_TAG_MASK |
        SEMANTIC_LIR_FLAG_ARRAY_PAIR)) |
        ((tag & 3u) << SEMANTIC_LIR_TYPE_REF_TAG_SHIFT);
    uint kind = receiver_kind(tag, payload);
    core.value_word_count = receiver_aggregate(tag, payload)
        ? receiver_native_words(tag, payload, hir_count) : 0u;
    if (kind == 3u) core.flags |= SEMANTIC_LIR_FLAG_ARRAY_PAIR;
    if (core.type_id == 0u || core.value_word_count == LIR_INVALID)
        core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
}

// A base is consumed as a place only by a field/index operation. The checked
// source identity remains unchanged, so ordinary argument/value reads still
// snapshot at their own evaluation point.
SemanticLirRow place_empty_row(uint node, uint local_row, uint hir_count)
{
    SemanticLirRow result;
    result.core.type_id = SEMANTIC_LIR_TY_POINTER;
    result.core.type_ref_payload = SEMANTIC_LIR_TY_POINTER;
    result.core.value_word_count = 0u;
    result.core.flags = (1u << SEMANTIC_LIR_TYPE_REF_TAG_SHIFT) |
        (SEMANTIC_LIR_OP_NOP << SEMANTIC_LIR_OP_SHIFT);
    result.operands.result = semantic_lir_offset[node] + local_row;
    result.operands.a = LIR_INVALID;
    result.operands.b = LIR_INVALID;
    result.operands.c = LIR_INVALID;
    result.layout_word_offset = LIR_INVALID;
    return result;
}

// place_mark gives the call's local storage only when the receiver is not a
// place (receiver_temporary.slang); the method name token keys it. Only the
// node marked as its holder gets the rows: the receiver, or the aggregate
// under a borrowed field projection (receiver_words.slang).
uint receiver_temporary_place(uint encoded, uint hir_count)
{
    uint call = (encoded & RECEIVER_CALL_MASK) - 1u;
    uint member = (encoded & RECEIVER_TEMPORARY_HOLDER) != 0u && call < hir_count
        ? compact_hir_payload[call].a : LIR_INVALID;
    uint token = member < hir_count && compact_hir_core[member].kind == HIR_MEMBER_EXPR
        ? compact_hir_payload[member].c : LIR_INVALID;
    return token < gParams.n_tokens && semantic_place_storage_by_token[token].x != 0u
        ? token : LIR_INVALID;
}

SemanticLirRow materialize_semantic_lir_row(uint node, uint local_row, uint hir_count)
{
    HirCore hir = compact_hir_core[node];
    if (hir.kind == 3u && semantic_place_function_flags[node] != 0u)
    {
        SemanticLirRow result = place_empty_row(node, local_row, hir_count);
        SemanticLirFunction function = semantic_lir_functions[semantic_function_id[node]];
        uint declaration = local_row < function.param_count
            ? semantic_lir_params[function.param_start + local_row].declaration_id
            : semantic_lir_locals[function.local_start + local_row - function.param_count].declaration_id;
        if (declaration < gParams.n_tokens && semantic_place_storage_by_token[declaration].x != 0u)
        {
            place_set_op(result.core, SEMANTIC_LIR_OP_ADDRESS);
            result.operands.a = declaration;
        }
        return result;
    }

    uint original = semantic_place_original_count[node];
    uint encoded = semantic_receiver_call_by_hir[node];
    bool projected = (encoded & RECEIVER_TEMPORARY_PROJECTED) != 0u;
    uint encoded_call = encoded & RECEIVER_CALL_MASK;
    uint temporary = receiver_temporary_place(encoded, hir_count);
    if (local_row >= original)
    {
        SemanticLirRow result = place_empty_row(node, local_row, hir_count);
        // The first appended row adjusts the node's original value row.
        uint adjusted = local_row == original
            ? lir_for_hir_original(node, hir_count) : result.operands.result - 1u;
        if (encoded_call == 0u)
        {
            uint extra = projection_adjustment_rows(node, hir_count);
            uint load = local_row - original;
            place_set_op(result.core, SEMANTIC_LIR_OP_PLACE_LOAD);
            result.operands.a = adjusted;
            uint tag; uint payload;
            projection_adjusted_ref(node, load + 1u, tag, payload);
            place_set_type(result.core, tag, payload, hir_count);
            result.core.flags |= SEMANTIC_LIR_FLAG_NATIVE_PLACE;
            if (extra == LIR_INVALID || load >= extra || result.operands.a == LIR_INVALID)
                result.core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
            return result;
        }
        CheckedCallArtifact call = semantic_calls_by_hir[encoded_call - 1u];
        if (temporary != LIR_INVALID)
        {
            // Store the receiver value as a `let` initializer would, then
            // borrow the stored copy. The aggregate under borrowed fields
            // is instead read back as a view of its copy, as a `let` local
            // would be: the fields take their addresses from the view.
            bool store = local_row == original;
            bool place = store || projected;
            place_set_op(result.core, store ? SEMANTIC_LIR_OP_PLACE_STORE
                : projected ? SEMANTIC_LIR_OP_PLACE_LOAD : SEMANTIC_LIR_OP_ADDRESS);
            result.operands.a = place ? semantic_place_address_by_token[temporary] : temporary;
            result.operands.b = store ? adjusted : LIR_INVALID;
            place_set_type(result.core,
                projected ? semantic_expr_ref_tag[node]
                    : store ? call.receiver_matched_ref_tag : call.receiver_parameter_ref_tag,
                projected ? semantic_expr_ref_payload[node]
                    : store ? call.receiver_matched_ref_payload : call.receiver_parameter_ref_payload,
                hir_count);
            uint4 storage = semantic_place_storage_by_token[temporary];
            if (place) result.core.flags |= SEMANTIC_LIR_FLAG_NATIVE_PLACE;
            if (projected && !store) result.core.flags |= SEMANTIC_LIR_FLAG_PLACE_VIEW;
            result.core.value_word_count = place
                ? (storage.x != 1u ? storage.y : result.core.value_word_count)
                : receiver_native_words(call.receiver_matched_ref_tag,
                    call.receiver_matched_ref_payload, hir_count);
            if (result.operands.a == LIR_INVALID || local_row > original + 1u)
                result.core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
            return result;
        }
        if (projected) { result.core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED; return result; }
        uint adjustment_row = local_row - original;
        bool value = call.receiver_adjustment_kind == 1u;
        bool final_load = value && adjustment_row + 1u == call.receiver_deref_count;
        bool final_copy = value && adjustment_row == call.receiver_deref_count;
        place_set_op(result.core, final_copy ? SEMANTIC_LIR_OP_AGGREGATE_COPY : SEMANTIC_LIR_OP_PLACE_LOAD);
        result.operands.a = adjusted;
        if (final_load || final_copy)
        {
            place_set_type(result.core, call.receiver_matched_ref_tag,
                call.receiver_matched_ref_payload, hir_count);
            if (final_load) result.core.flags |= SEMANTIC_LIR_FLAG_NATIVE_PLACE;
        }
        else if (!value && adjustment_row + 2u == call.receiver_deref_count)
            place_set_type(result.core, call.receiver_parameter_ref_tag,
                call.receiver_parameter_ref_payload, hir_count);
        if (result.operands.a == LIR_INVALID || call.receiver_deref_count == 0u)
            result.core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
        return result;
    }

    SemanticLirRow result = materialize_original_semantic_lir_row(node, local_row, hir_count);
    result.operands.result = semantic_lir_offset[node] + local_row;
    uint op = semantic_lir_op(result.core);
    if (encoded_call != 0u)
    {
        CheckedCallArtifact call = semantic_calls_by_hir[encoded_call - 1u];
        if (call.receiver_adjustment_kind == 2u && call.receiver_deref_count == 0u &&
            temporary == LIR_INVALID && !projected)
        {
            // Count disables receiver copies for borrowing. These operations
            // publish the real declaration/field/index cell, never a spill of
            // its current pointer or scalar value.
            if (op == SEMANTIC_LIR_OP_VALUE_GET)
            {
                place_set_op(result.core, SEMANTIC_LIR_OP_ADDRESS);
                if (result.operands.a >= gParams.n_tokens ||
                    semantic_place_storage_by_token[result.operands.a].x == 0u)
                    result.core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
            }
            else if (op == SEMANTIC_LIR_OP_LOAD && hir.kind == HIR_MEMBER_EXPR)
                place_set_op(result.core, SEMANTIC_LIR_OP_FIELD_ADDRESS);
            else if (op == SEMANTIC_LIR_OP_LOAD && hir.kind == HIR_INDEX_EXPR)
                place_set_op(result.core, SEMANTIC_LIR_OP_INDEX_ADDRESS);
            else result.core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
            uint width = receiver_native_words(call.receiver_matched_ref_tag,
                call.receiver_matched_ref_payload, hir_count);
            place_set_type(result.core, call.receiver_parameter_ref_tag,
                call.receiver_parameter_ref_payload, hir_count);
            // Address projections consume this exact pointee width for
            // indexing; an empty aggregate has width zero, not one.
            result.core.value_word_count = width;
            if (width == LIR_INVALID) result.core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
            return result;
        }
    }

    bool declaration_store = op == SEMANTIC_LIR_OP_VALUE_SET ||
        (op == SEMANTIC_LIR_OP_STORE &&
         (result.core.flags & (SEMANTIC_LIR_FLAG_FIELD | SEMANTIC_LIR_FLAG_INDEXED)) == 0u);
    if ((op == SEMANTIC_LIR_OP_VALUE_GET || declaration_store) &&
        result.operands.a < gParams.n_tokens)
    {
        uint declaration = result.operands.a;
        uint4 storage = semantic_place_storage_by_token[declaration];
        if (storage.x != 0u)
        {
            result.operands.a = semantic_place_address_by_token[declaration];
            place_set_op(result.core, declaration_store
                ? SEMANTIC_LIR_OP_PLACE_STORE : SEMANTIC_LIR_OP_PLACE_LOAD);
            result.core.flags |= SEMANTIC_LIR_FLAG_NATIVE_PLACE;
            if (storage.x == 2u)
            {
                // Assignment/declaration rows did not previously own their
                // descriptor ABI: the native STORE recipe inferred it from
                // the RHS. A true place operation owns the destination shape.
                result.core.value_word_count = storage.y;
                if (storage.y == NATIVE_SLICE_WORDS)
                {
                    result.core.type_id = 128u;
                    result.core.flags |= SEMANTIC_LIR_FLAG_ARRAY_PAIR;
                }
                else
                {
                    result.core.type_id = SEMANTIC_LIR_TY_STRING;
                    result.core.flags &= ~SEMANTIC_LIR_FLAG_ARRAY_PAIR;
                }
            }
            if (storage.x == 3u)
            {
                // Fixed-array parameters arrive using the view call ABI;
                // their promoted homes contain canonical owned native words.
                result.core.flags &= ~SEMANTIC_LIR_FLAG_ARRAY_PAIR;
                result.core.value_word_count = storage.y;
                // A checked slice argument borrows this backing array. A
                // snapshot would change the alias observed by the callee.
                // Owned arguments keep the ordinary value-copy behavior.
                bool borrowed_array_argument = semantic_argument_mode_by_hir[node] == 2u &&
                    receiver_kind(semantic_expr_ref_tag[node],
                        semantic_expr_ref_payload[node]) == 2u;
                if (!declaration_store && (receiver_is_projection_base(node, hir_count) ||
                    borrowed_array_argument))
                    result.core.flags |= SEMANTIC_LIR_FLAG_PLACE_VIEW;
            }
            if (result.operands.a == LIR_INVALID)
                result.core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
        }
    }
    return result;
}
