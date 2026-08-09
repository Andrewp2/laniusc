import hir_records;
import codegen.lir.semantic.common;
import codegen.lir.semantic.loop_recipe;
import codegen.lowering_ir;

struct Params { uint n_hir_nodes; uint lir_capacity; uint n_tokens; uint reserved1; };
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
StructuredBuffer<uint> semantic_array_length;
StructuredBuffer<uint> semantic_iterable_kind;
StructuredBuffer<uint> semantic_value_id;
StructuredBuffer<uint> semantic_value_type;
StructuredBuffer<uint> semantic_value_const_by_hir;
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
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_start;
StructuredBuffer<uint> compact_match_payload_count;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint> semantic_lir_count;
StructuredBuffer<uint> semantic_lir_offset;
StructuredBuffer<uint> semantic_execution_rank;

uint active_match_arm_count()
{
    return min(compact_match_arm_count[0u], gParams.n_hir_nodes);
}

uint active_match_payload_count()
{
    return min(compact_match_payload_row_count[0u], gParams.n_hir_nodes);
}

uint match_payload_for_pattern(uint node)
{
    uint lo = 0u;
    uint hi = active_match_payload_count();
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_match_payloads[mid].pattern < node) lo = mid + 1u;
        else hi = mid;
    }
    if (lo >= active_match_payload_count() ||
        compact_match_payloads[lo].pattern != node)
        return LIR_INVALID;
    uint declaration_token = semantic_value_id[node];
    uint variant_count = min(compact_variant_count[0u], gParams.n_hir_nodes);
    uint variant_lo = 0u;
    uint variant_hi = variant_count;
    while (variant_lo < variant_hi)
    {
        uint mid = variant_lo + (variant_hi - variant_lo) / 2u;
        if (compact_variants[mid].name_token < declaration_token)
            variant_lo = mid + 1u;
        else
            variant_hi = mid;
    }
    return variant_lo < variant_count &&
        compact_variants[variant_lo].name_token == declaration_token
            ? LIR_INVALID : lo;
}

uint match_arm_for_result_node(uint node, uint hir_count)
{
    uint token = compact_hir_core[node].token_start;
    uint lo = 0u;
    uint hi = active_match_arm_count();
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        uint result = compact_match_arms[mid].result;
        uint start = result < hir_count
            ? compact_hir_core[result].token_start : 0xffffffffu;
        if (start <= token) lo = mid + 1u;
        else hi = mid;
    }
    if (lo == 0u) return LIR_INVALID;
    uint arm_row = lo - 1u;
    uint result = compact_match_arms[arm_row].result;
    if (result >= hir_count) return LIR_INVALID;
    HirCore span = compact_hir_core[result];
    HirCore candidate = compact_hir_core[node];
    return candidate.token_start >= span.token_start &&
        candidate.token_end <= span.token_end ? arm_row : LIR_INVALID;
}

uint variant_ordinal_for_pattern(uint pattern, uint hir_count)
{
    if (pattern >= hir_count) return LIR_INVALID;
    uint declaration_token = semantic_value_id[pattern];
    uint count = min(compact_variant_count[0u], gParams.n_hir_nodes);
    uint lo = 0u;
    uint hi = count;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_variants[mid].name_token < declaration_token) lo = mid + 1u;
        else hi = mid;
    }
    return lo < count && compact_variants[lo].name_token == declaration_token
        ? compact_variants[lo].ordinal : LIR_INVALID;
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
    HirCore core = compact_hir_core[pattern];
    // The checker gives `_` a self-binding declaration identity. Do not
    // constrain this to one expression wrapper kind: compact HIR is allowed
    // to canonicalize a pattern name as either a name or a one-segment path.
    return semantic_value_id[pattern] == core.token_start;
}

uint scalar_match_pattern_value(uint pattern, uint hir_count)
{
    if (!scalar_match_pattern(pattern, hir_count)) return LIR_INVALID;
    HirPayload payload = compact_hir_payload[pattern];
    if (payload.a == HIR_EXPR_TRUE) return 1u;
    if (payload.a == HIR_EXPR_FALSE) return 0u;
    return payload.b;
}

uint semantic_materialized_op(uint node, uint local_row, uint local_count)
{
    if (match_payload_for_pattern(node) != LIR_INVALID)
        return local_row == 0u ? SEMANTIC_LIR_OP_VALUE_GET
            : local_row == 1u ? SEMANTIC_LIR_OP_LOAD : SEMANTIC_LIR_OP_VALUE_SET;
    if (compact_hir_core[node].kind == HIR_MATCH_EXPR &&
        local_row >= 3u && local_row + 1u < local_count)
    {
        uint phase = (local_row - 3u) % 12u;
        uint arm_row = compact_hir_payload[node].b + (local_row - 3u) / 12u;
        uint pattern = arm_row < active_match_arm_count()
            ? compact_match_arms[arm_row].pattern : LIR_INVALID;
        bool scalar = scalar_match_pattern(pattern, gParams.n_hir_nodes);
        bool wildcard = wildcard_match_pattern(pattern, gParams.n_hir_nodes);
        if (phase == 2u && (scalar || wildcard)) return SEMANTIC_LIR_OP_NOP;
        if (phase == 3u && scalar) return SEMANTIC_LIR_OP_VALUE_GET;
        if (phase == 3u && wildcard) return SEMANTIC_LIR_OP_CONST_I32;
        if (phase == 4u)
        {
            uint variant = variant_ordinal_for_pattern(pattern, gParams.n_hir_nodes);
            return variant != LIR_INVALID || scalar || wildcard
                ? SEMANTIC_LIR_OP_CONST_I32 : SEMANTIC_LIR_OP_INVALID;
        }
    }
    return semantic_lir_local_op(
        compact_hir_core[node], compact_hir_payload[node], local_row, local_count);
}

uint lir_for_hir(uint node, uint hir_count)
{
    if (node == LIR_INVALID || node >= hir_count || semantic_lir_count[node] == 0u)
        return LIR_INVALID;
    uint first = semantic_lir_offset[node];
    // Structured match control begins at `first`, but the expression's value
    // is materialized by the final synthetic VALUE_GET row. Consumers of the
    // HIR identity must observe that value-producing row, just as they observe
    // the sole row of an ordinary expression.
    return compact_hir_core[node].kind == HIR_MATCH_EXPR
        ? first + semantic_lir_count[node] - 1u : first;
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

uint semantic_type_for_hir(uint node, uint hir_count)
{
    if (node == LIR_INVALID || node >= hir_count) return 0u;
    uint call_result = semantic_call_result_type[node];
    return call_result != LIR_INVALID
        ? call_result
        : semantic_lir_type(semantic_expr_type[node]);
}

uint aggregate_word_count_for_type(uint type_id, uint hir_count)
{
    if (type_id < 4096u || type_id >= 8192u) return 0u;
    uint name_token = type_id >= 6144u
        ? type_id - 6144u : type_id - 4096u;
    if (name_token >= gParams.n_tokens) return 0u;
    uint struct_hir = semantic_aggregate_hir_by_name_token[name_token];
    return struct_hir < hir_count
        ? semantic_struct_word_count_by_hir[struct_hir] : 0u;
}

uint aggregate_word_count_for_hir(uint node, uint hir_count)
{
    if (node == LIR_INVALID || node >= hir_count) return 0u;
    uint array_length = semantic_array_length[node];
    if (array_length != LIR_INVALID) return array_length;
    uint projected_words = semantic_aggregate_word_count[node];
    if (projected_words != 0u) return projected_words;
    uint ref_tag = semantic_expr_ref_tag[node];
    uint ref_payload = semantic_expr_ref_payload[node];
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
    if (function != LIR_INVALID && function < hir_count)
    {
        uint words = semantic_lir_functions[function].result_word_count;
        if (words != 0u) return words;
    }
    return aggregate_word_count_for_type(
        semantic_type_for_hir(node, hir_count), hir_count);
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
        total += max(aggregate_word_count_for_hir(argument.value, hir_count), 1u);
    }
    return total;
}

void member_word_layout(uint receiver, uint ordinal, uint hir_count,
                        out uint word_offset, out uint word_count)
{
    word_offset = ordinal;
    word_count = 1u;
    if (receiver >= hir_count) return;
    uint decl_token = semantic_aggregate_decl_token[receiver];
    if (decl_token >= gParams.n_tokens) return;
    uint struct_hir = semantic_aggregate_hir_by_name_token[decl_token];
    if (struct_hir >= hir_count) return;
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

// A path expression can name either a callable or a constant. Callable paths
// are syntax owned by their call expression, while constant paths are actual
// value-producing rows and must be materialized as literal instructions.
uint constant_reference_for_hir(uint node, uint hir_count)
{
    if (node == LIR_INVALID || node >= hir_count ||
        compact_hir_core[node].kind != HIR_PATH_EXPR ||
        semantic_value_id[node] >= gParams.n_tokens)
        return LIR_INVALID;
    uint function_id = semantic_function_id_by_token[semantic_value_id[node]];
    if (function_id >= gParams.n_hir_nodes) return LIR_INVALID;
    uint target_hir = semantic_lir_functions[function_id].hir_function;
    return target_hir < hir_count &&
        compact_hir_core[target_hir].kind == HIR_CONST_ITEM
        ? target_hir : LIR_INVALID;
}

bool imported_constant_for_hir(uint node, uint hir_count)
{
    return node < hir_count && semantic_value_const_present_by_hir[node] != 0u;
}

uint materialize_loop_operand(uint source, uint node, uint first_row,
                              uint hir_count, HirPayload payload,
                              HirPayload range_payload)
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
    if (source >= LOOP_OPERAND_ROW_BASE)
        return first_row + source - LOOP_OPERAND_ROW_BASE;
    return LIR_INVALID;
}

SemanticLirSchedule semantic_schedule(uint node, uint local_row, uint local_count,
                                      uint hir_count, HirCore hir, HirLinks links,
                                      HirPayload payload)
{
    SemanticLirSchedule schedule;
    schedule.function_id = semantic_function_id[node];
    bool expression_row = semantic_lir_is_expression(hir);
    uint root = expression_row ? compact_expr_root[node] : LIR_INVALID;
    uint local_op = semantic_lir_local_op(hir, payload, local_row, local_count);
    uint iterable_kind = semantic_iterable_kind[node];
    uint iterable_form = payload.c < hir_count ? compact_hir_payload[payload.c].a : 0u;
    uint array_length = payload.c < hir_count
        ? semantic_array_length[payload.c] : LIR_INVALID;
    SemanticLoopRecipe loop_recipe = semantic_loop_recipe(
        hir, payload, iterable_form, iterable_kind, array_length);
    bool direct_range_for = loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_RANGE ||
        loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_RANGE_FROM_ZERO ||
        loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_UNBOUNDED_RANGE ||
        loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_UNBOUNDED_RANGE_FROM_ZERO;
    bool range_value_for = loop_recipe.kind == SEMANTIC_LOOP_RECIPE_RANGE_VALUE;
    bool range_for = direct_range_for || range_value_for;
    bool array_for = loop_recipe.kind == SEMANTIC_LOOP_RECIPE_ARRAY;
    uint payload_row = match_payload_for_pattern(node);
    if (payload_row != LIR_INVALID)
    {
        HirMatchPayload binding = compact_match_payloads[payload_row];
        HirMatchArm arm = compact_match_arms[binding.arm];
        HirCore result = compact_hir_core[arm.result];
        schedule.execution_region = result.token_start;
        schedule.execution_rank = 0u;
        // Payload extraction belongs inside the selected arm. Match phases
        // occupy ties 3..10 at the result start, with IF_BEGIN at tie 10;
        // binding rows follow it and precede the result expression.
        schedule.execution_tie = 11u + binding.ordinal * 3u + local_row;
        return schedule;
    }
    if (hir.kind == HIR_MATCH_EXPR)
    {
        if (local_row + 1u == local_count)
        {
            schedule.execution_region = hir.token_end > hir.token_start
                ? hir.token_end - 1u : hir.token_end;
            // The match closing token is after every arm region. At that
            // boundary, rank the result read before the enclosing statement
            // effect, whose rank is derived from the completed expression.
            schedule.execution_rank = 0u;
            schedule.execution_tie = 0u;
            return schedule;
        }
        if (local_row <= 2u)
        {
            uint first_arm = payload.b;
            HirCore first_result = first_arm < active_match_arm_count()
                ? compact_hir_core[compact_match_arms[first_arm].result] : hir;
            schedule.execution_region = first_result.token_start;
            schedule.execution_rank = 0u;
            schedule.execution_tie = local_row;
            return schedule;
        }
        uint arm_row = payload.b + (local_row - 3u) / 12u;
        HirMatchArm arm = compact_match_arms[arm_row];
        HirCore result = compact_hir_core[arm.result];
        uint phase = (local_row - 3u) % 12u;
        schedule.execution_region = phase <= 7u
            ? result.token_start
            : result.token_end > result.token_start
                ? result.token_end - 1u : result.token_end;
        schedule.execution_rank = phase <= 7u ? 0u : 0xffffffffu;
        schedule.execution_tie = phase <= 7u ? phase + 3u : phase - 8u;
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
        uint start_token = bounded_token(start_node, hir_count, hir.token_start);
        uint end_token = bounded_token(end_node, hir_count, start_token);
        bool starts_from_zero =
            loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_RANGE_FROM_ZERO ||
            loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_UNBOUNDED_RANGE_FROM_ZERO;
        bool unbounded =
            loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_UNBOUNDED_RANGE ||
            loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_UNBOUNDED_RANGE_FROM_ZERO;
        uint header_last_row = unbounded ? (starts_from_zero ? 3u : 2u)
            : starts_from_zero ? 8u : 7u;
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
        schedule.execution_region = bounded_token(rhs_root, hir_count, hir.token_start);
        bool compound_lhs_read = payload.d != HIR_ASSIGN_OP_SET && local_row == 0u;
        // A compound assignment reads its old lhs before evaluating the RHS,
        // then applies the binary operation and store after the RHS completes.
        // This is observable for side effects and is also the stack contract
        // required by Wasm's non-commutative binary instructions.
        schedule.execution_rank = compound_lhs_read ? 0u : 0xffffffffu;
        schedule.execution_tie = local_row;
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
    HirCore root_core = hir;
    if (root != LIR_INVALID && root < hir_count)
        root_core = compact_hir_core[root];
    bool aggregate_root = root != LIR_INVALID && root < hir_count &&
        (root_core.kind == HIR_ARRAY_EXPR ||
         root_core.kind == HIR_STRUCT_LITERAL_EXPR);
    bool completed_match_root = root != LIR_INVALID && root < hir_count &&
        root_core.kind == HIR_MATCH_EXPR && (!expression_row || node == root);
    // Aggregate elements are independent expression roots in compact HIR.
    // Their owner becomes executable only at the closing boundary, after all
    // element regions. Statements consuming the aggregate share that same
    // completion region and follow it through the ordinary expression/effect
    // tie ordering.
    schedule.execution_region = root != LIR_INVALID && root < hir_count
        ? ((aggregate_root || completed_match_root)
            ? (root_core.token_end > root_core.token_start
                ? root_core.token_end - 1u : root_core.token_end)
            : root_core.token_start)
        : hir.token_start;
    // Source-ordered tree postorder is the common schedule contract for both
    // register targets and Wasm's operand stack. A child finishes no later
    // than its parent; equal right boundaries are broken child-before-parent
    // by reversed expression depth. Statement effects share the result root's
    // end boundary and occupy the final tie value.
    schedule.execution_rank = expression_row
        ? hir.token_end
        : root != LIR_INVALID && root < hir_count
            ? compact_hir_core[root].token_end : hir.token_end;
    schedule.execution_tie = expression_row
        ? 0x7fffffffu - min(semantic_execution_rank[node], 0x7fffffffu)
        : 0xffffffffu;

    uint result_arm = match_arm_for_result_node(node, hir_count);
    if (result_arm != LIR_INVALID)
    {
        HirCore result = compact_hir_core[compact_match_arms[result_arm].result];
        schedule.execution_region = result.token_start;
    }

    if (semantic_lir_is_control(hir, payload))
    {
        bool loop = semantic_lir_is_loop(hir, payload);
        if (!loop && local_row == 0u)
        {
            uint condition = payload.b;
            uint condition_root = condition < hir_count
                ? compact_expr_root[condition] : LIR_INVALID;
            schedule.execution_region = bounded_token(
                condition_root, hir_count, bounded_token(condition, hir_count, hir.token_start));
            // The marker consumes the completed condition expression. Keep it
            // in the statement-effect rank band so every expression depth in
            // this region precedes the branch.
            schedule.execution_rank = 0xffffffffu;
            schedule.execution_tie = 0xffffffffu;
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
                schedule.execution_region = bounded_token(
                    condition_root, hir_count, bounded_token(condition, hir_count, hir.token_start));
                schedule.execution_rank = condition < hir_count
                    ? compact_hir_core[condition].token_end : hir.token_start;
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
    SemanticLirSchedule schedule;
    uint layout_word_offset;
};

SemanticLirRow materialize_semantic_lir_row(uint node, uint local_row, uint hir_count)
{
    uint first_row = semantic_lir_offset[node];

    HirCore hir = compact_hir_core[node];
    HirLinks links = compact_hir_links[node];
    HirPayload payload = compact_hir_payload[node];
    uint local_count = semantic_lir_count[node];
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
    uint iterable_kind = semantic_iterable_kind[node];
    uint iterable_form = payload.c < hir_count ? compact_hir_payload[payload.c].a : 0u;
    uint array_length = payload.c < hir_count
        ? semantic_array_length[payload.c] : LIR_INVALID;
    SemanticLoopRecipe loop_recipe = semantic_loop_recipe(
        hir, payload, iterable_form, iterable_kind, array_length);
    bool direct_range_for = loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_RANGE ||
        loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_RANGE_FROM_ZERO ||
        loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_UNBOUNDED_RANGE ||
        loop_recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_UNBOUNDED_RANGE_FROM_ZERO;
    bool range_value_for = loop_recipe.kind == SEMANTIC_LOOP_RECIPE_RANGE_VALUE;
    bool range_for = direct_range_for || range_value_for;
    bool array_for = loop_recipe.kind == SEMANTIC_LOOP_RECIPE_ARRAY;
    HirPayload range_payload;
    range_payload.a = 0u;
    range_payload.b = LIR_INVALID;
    range_payload.c = LIR_INVALID;
    range_payload.d = LIR_INVALID;
    if (direct_range_for && payload.c < hir_count)
        range_payload = compact_hir_payload[payload.c];

    uint row = first_row + local_row;
    uint op = semantic_materialized_op(node, local_row, local_count);
    uint constant_reference_hir = constant_reference_for_hir(node, hir_count);
    bool imported_constant = imported_constant_for_hir(node, hir_count);
    if (constant_reference_hir != LIR_INVALID || imported_constant)
    {
        uint constant_type = semantic_value_type[node];
        op = constant_type == 5u
            ? SEMANTIC_LIR_OP_CONST_F32 : SEMANTIC_LIR_OP_CONST_I32;
    }
    // Compound assignment reads an addressable lhs through the same semantic
    // LOAD contract as an ordinary member/index expression. It is not a
    // declaration lookup: fields and elements have no declaration value ID.
    if (compound_assignment && local_row == 0u &&
        (assignment_field || assignment_indexed))
        op = SEMANTIC_LIR_OP_LOAD;
    if (op == SEMANTIC_LIR_OP_VALUE_GET && hir.kind == HIR_CALL_EXPR &&
        semantic_call_kind[node] == 1u)
        op = SEMANTIC_LIR_OP_CALL;
    if (op == SEMANTIC_LIR_OP_VALUE_GET && semantic_call_kind[node] == 5u)
        op = SEMANTIC_LIR_OP_AGGREGATE_NEW;
    if (loop_recipe.kind != SEMANTIC_LOOP_RECIPE_NONE)
        op = semantic_loop_recipe_op(loop_recipe.kind, local_row);
    if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 2u)
        op = SEMANTIC_LIR_OP_CALL_INTRINSIC;
    else if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 3u)
        op = SEMANTIC_LIR_OP_CALL_HOST;
    else if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 4u)
        op = SEMANTIC_LIR_OP_CALL_SYMBOL;
    else if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 5u)
        op = SEMANTIC_LIR_OP_AGGREGATE_NEW;

    uint match_payload_row = match_payload_for_pattern(node);
    bool match_binding = match_payload_row != LIR_INVALID;
    bool match_expression = hir.kind == HIR_MATCH_EXPR;
    bool match_result_get = match_expression && local_row + 1u == local_count;
    bool match_scrutinee_set = match_expression && local_row == 0u;
    bool match_arm_instruction = match_expression && local_row >= 3u &&
        !match_result_get;
    uint match_phase = match_arm_instruction
        ? (local_row - 3u) % 12u : LIR_INVALID;

    SemanticLirCore core;
    core.op = op;
    core.type_id = semantic_type_for_hir(node, hir_count);
    semantic_type_ref_for_hir(node, hir_count,
        core.type_ref_tag, core.type_ref_payload);
    if (match_scrutinee_set)
    {
        core.type_id = SEMANTIC_LIR_TY_POINTER;
        core.type_ref_tag = 1u;
        core.type_ref_payload = SEMANTIC_LIR_TY_POINTER;
    }
    else if (match_expression && !match_result_get)
    {
        core.type_id = match_phase == 2u ? SEMANTIC_LIR_TY_POINTER : 3u;
        core.type_ref_tag = 1u;
        core.type_ref_payload = core.type_id;
    }
    else if (match_binding)
    {
        HirMatchPayload binding = compact_match_payloads[match_payload_row];
        HirMatchArm arm = compact_match_arms[binding.arm];
        uint match_node = arm.owner;
        if (local_row == 0u)
        {
            core.type_id = SEMANTIC_LIR_TY_POINTER;
            core.type_ref_tag = 1u;
            core.type_ref_payload = SEMANTIC_LIR_TY_POINTER;
        }
        else
        {
            core.type_id = semantic_value_type[node];
            semantic_type_ref_for_hir(node, hir_count,
                core.type_ref_tag, core.type_ref_payload);
        }
    }
    if ((op == SEMANTIC_LIR_OP_VALUE_GET || op == SEMANTIC_LIR_OP_VALUE_SET ||
         op == SEMANTIC_LIR_OP_STORE) && !match_expression)
        core.type_id = semantic_value_type[node];
    // A declaration-setting row represents the value being stored, while the
    // statement node itself need not carry an expression type. Preserve the
    // checked RHS reference here so target ABIs can distinguish instantiated
    // aggregates from scalar values without reconstructing declaration syntax.
    if (op == SEMANTIC_LIR_OP_VALUE_SET && !match_expression && payload.c < hir_count)
        semantic_type_ref_for_hir(payload.c, hir_count,
            core.type_ref_tag, core.type_ref_payload);
    if (semantic_lir_is_assignment(hir, payload) && payload.b < hir_count)
    {
        core.type_id = semantic_value_type[payload.b];
        semantic_type_ref_for_hir(payload.b, hir_count,
            core.type_ref_tag, core.type_ref_payload);
    }
    if (op == SEMANTIC_LIR_OP_RETURN &&
        semantic_function_id[node] != LIR_INVALID)
    {
        core.type_id = semantic_lir_functions[semantic_function_id[node]].result_type;
        semantic_type_ref_for_hir(payload.b, hir_count,
            core.type_ref_tag, core.type_ref_payload);
    }
    if (range_for)
    {
        core.type_id = 3u;
        core.type_ref_tag = 1u;
        core.type_ref_payload = 3u;
    }
    if (array_for)
    {
        core.type_id = 3u;
        core.type_ref_tag = 1u;
        core.type_ref_payload = 3u;
        if (local_row == 9u)
        {
            core.type_id = semantic_type_for_hir(payload.c, hir_count);
            semantic_type_ref_for_hir(payload.c, hir_count,
                core.type_ref_tag, core.type_ref_payload);
        }
        else if (local_row == 11u || local_row == 12u)
        {
            core.type_id = semantic_value_type[node];
            semantic_type_ref_for_hir(node, hir_count,
                core.type_ref_tag, core.type_ref_payload);
        }
    }
    // Comparisons produce bool but machine selection depends on the operand
    // representation. The semantic instruction type therefore records the
    // compared value type for this opcode.
    if (op == SEMANTIC_LIR_OP_COMPARE && !match_expression && payload.b < hir_count)
    {
        core.type_id = semantic_type_for_hir(payload.b, hir_count);
        semantic_type_ref_for_hir(payload.b, hir_count,
            core.type_ref_tag, core.type_ref_payload);
    }
    core.source_hir = node;
    core.flags = 0u;
    uint value_node = match_scrutinee_set ? payload.a
        : op == SEMANTIC_LIR_OP_VALUE_SET && payload.c < hir_count
        ? payload.c : node;
    if (op == SEMANTIC_LIR_OP_STORE && assignment_lhs < hir_count)
        value_node = assignment_lhs;
    core.value_word_count = aggregate_word_count_for_hir(value_node, hir_count);
    if (core.value_word_count == 0u && op == SEMANTIC_LIR_OP_VALUE_SET)
        core.value_word_count = aggregate_word_count_for_hir(node, hir_count);
    if (core.value_word_count == 0u)
        core.value_word_count = aggregate_word_count_for_type(core.type_id, hir_count);
    if (op == SEMANTIC_LIR_OP_AGGREGATE_NEW && semantic_call_kind[node] == 5u)
        core.value_word_count = hir.kind == HIR_CALL_EXPR
            ? enum_constructor_word_count(node, payload, hir_count) : 1u;
    if ((op == SEMANTIC_LIR_OP_LOAD || op == SEMANTIC_LIR_OP_STORE) &&
        (hir.kind == HIR_INDEX_EXPR || assignment_indexed))
        core.flags |= SEMANTIC_LIR_FLAG_INDEXED;
    if ((op == SEMANTIC_LIR_OP_LOAD || op == SEMANTIC_LIR_OP_STORE) &&
        (hir.kind == HIR_MEMBER_EXPR || assignment_field))
        core.flags |= SEMANTIC_LIR_FLAG_FIELD;
    if ((match_expression && !match_result_get && op == SEMANTIC_LIR_OP_LOAD) ||
        (match_binding && local_row == 1u))
        core.flags |= SEMANTIC_LIR_FLAG_FIELD;
    if (op == SEMANTIC_LIR_OP_INVALID) core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
    if (compound_assignment && !assignment_field && !assignment_indexed &&
        (payload.b >= hir_count || semantic_value_id[payload.b] == LIR_INVALID))
        core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
    if (semantic_lir_is_control(hir, payload))
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
        core.flags |= semantic_loop_recipe_flags(loop_recipe.kind, local_row);

    SemanticLirOperands operands;
    operands.result = row;
    operands.a = LIR_INVALID;
    operands.b = LIR_INVALID;
    operands.c = LIR_INVALID;
    uint layout_word_offset = LIR_INVALID;

    if (match_expression)
    {
        uint result_declaration = gParams.n_tokens + node;
        uint scrutinee_declaration = gParams.n_tokens + hir_count + node;
        uint matched_declaration = gParams.n_tokens + hir_count * 2u + node;
        if (match_result_get)
            operands.a = result_declaration;
        else if (match_scrutinee_set)
        {
            operands.a = scrutinee_declaration;
            operands.b = lir_for_value_hir(payload.a, hir_count);
        }
        else if (local_row == 1u)
            operands.a = 0u;
        else if (local_row == 2u)
        {
            operands.a = matched_declaration;
            operands.b = first_row + 1u;
        }
        else
        {
            uint arm_row = payload.b + (local_row - 3u) / 12u;
            HirMatchArm arm = compact_match_arms[arm_row];
            uint arm_first = first_row + 3u + (arm_row - payload.b) * 12u;
            uint variant = variant_ordinal_for_pattern(arm.pattern, hir_count);
            bool scalar_pattern = scalar_match_pattern(arm.pattern, hir_count);
            bool wildcard_pattern = wildcard_match_pattern(arm.pattern, hir_count);
            if (match_phase == 0u)
                operands.a = matched_declaration;
            else if (match_phase == 1u)
                operands.a = arm_first;
            else if (match_phase == 2u)
                operands.a = scrutinee_declaration;
            else if (match_phase == 3u)
            {
                if (scalar_pattern)
                    operands.a = scrutinee_declaration;
                else if (wildcard_pattern)
                    operands.a = 1u;
                else
                {
                    operands.a = arm_first + 2u;
                    operands.b = 0u;
                    layout_word_offset = 0u;
                }
            }
            else if (match_phase == 4u)
                operands.a = wildcard_pattern ? 1u : scalar_pattern
                    ? scalar_match_pattern_value(arm.pattern, hir_count)
                    : variant;
            else if (match_phase == 5u)
            {
                operands.a = arm_first + 3u;
                operands.b = arm_first + 4u;
                operands.c = 0u;
            }
            else if (match_phase == 6u)
            {
                operands.a = arm_first + 1u;
                operands.b = arm_first + 5u;
            }
            else if (match_phase == 7u)
            {
                operands.a = arm_first + 6u;
                operands.b = arm_first + 11u;
                operands.c = 0u;
            }
            else if (match_phase == 8u)
            {
                operands.a = result_declaration;
                operands.b = lir_for_value_hir(arm.result, hir_count);
            }
            else if (match_phase == 9u)
                operands.a = 1u;
            else if (match_phase == 10u)
            {
                operands.a = matched_declaration;
                operands.b = arm_first + 9u;
            }
        }
    }
    else if (match_binding)
    {
        HirMatchPayload binding = compact_match_payloads[match_payload_row];
        HirMatchArm arm = compact_match_arms[binding.arm];
        uint match_node = arm.owner;
        uint scrutinee_declaration = gParams.n_tokens + hir_count + match_node;
        uint word_offset = 1u + binding.ordinal;
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
            semantic_loop_operand_recipe(loop_recipe.kind, local_row);
        operands.a = materialize_loop_operand(
            recipe.a, node, first_row, hir_count, payload, range_payload);
        operands.b = materialize_loop_operand(
            recipe.b, node, first_row, hir_count, payload, range_payload);
        operands.c = materialize_loop_operand(
            recipe.c, node, first_row, hir_count, payload, range_payload);
    }
    else if (op == SEMANTIC_LIR_OP_CONST_I32 || op == SEMANTIC_LIR_OP_CONST_F32 ||
        op == SEMANTIC_LIR_OP_CONST_STRING)
    {
        uint local_constant_value = payload.b;
        if (constant_reference_hir != LIR_INVALID)
        {
            uint initializer = compact_const_value[constant_reference_hir];
            if (initializer < hir_count)
                local_constant_value = compact_hir_payload[initializer].b;
        }
        operands.a = imported_constant
            ? semantic_value_const_by_hir[node]
            : constant_reference_hir != LIR_INVALID
                ? local_constant_value : payload.b;
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
            member_word_layout(assignment_lhs_payload.b,
                semantic_member_field_ordinal[assignment_lhs], hir_count,
                layout_word_offset, field_words);
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
        // enters the following body. Without one it targets CONTROL_END.
        operands.b = local_count == 3u ? first_row + 1u
                                       : first_row + local_count - 1u;
        operands.c = local_count == 3u ? 1u : 0u;
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
        bool enum_constructor = semantic_call_kind[node] == 5u;
        operands.a = array ? compact_array_element_start[node]
            : enum_constructor
                ? compact_array_element_row_count[0u] + compact_field_count[0u] +
                    (hir.kind == HIR_CALL_EXPR ? payload.b : 0u)
                : compact_array_element_row_count[0u] + payload.b;
        operands.b = array ? compact_array_element_owner_count[node]
            : enum_constructor && hir.kind != HIR_CALL_EXPR ? 0u : payload.c;
        // High bit distinguishes a tagged enum aggregate; low bits contain
        // the checked declaration ordinal. Struct literals retain their
        // existing nonzero marker and arrays retain zero.
        operands.c = enum_constructor
            ? SEMANTIC_LIR_AGGREGATE_ENUM | semantic_call_target[node]
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
        member_word_layout(member_payload.b, semantic_member_field_ordinal[member],
            hir_count, layout_word_offset, operands.c);
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
            HirCore loop_core = compact_hir_core[compact_nearest_loop[node]];
            bool expanded_loop = semantic_lir_is_loop(loop_core,
                compact_hir_payload[compact_nearest_loop[node]]);
            uint loop_rows = semantic_lir_count[compact_nearest_loop[node]];
            uint continue_offset = loop_rows == 17u ? 9u
                : loop_rows == 18u ? 10u
                : loop_rows == 12u ? 4u
                : loop_rows == 13u ? 5u
                : loop_rows == 21u ? 14u : 1u;
            uint break_offset = loop_rows == 17u ? 16u
                : loop_rows == 18u ? 17u
                : loop_rows == 12u ? 11u
                : loop_rows == 13u ? 12u
                : loop_rows == 21u ? 20u : 5u;
            operands.a += expanded_loop
                ? (hir.kind == HIR_CONTINUE_STMT ? continue_offset : break_offset)
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
        operands.b = lir_for_hir(payload.c, hir_count);
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

    SemanticLirRow result;
    result.core = core;
    result.operands = operands;
    result.schedule = semantic_schedule(
        node, local_row, local_count, hir_count, hir, links, payload);
    result.layout_word_offset = layout_word_offset;
    return result;
}
