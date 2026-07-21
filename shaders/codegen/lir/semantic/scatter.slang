import codegen.lir.semantic.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint n_hir_nodes; uint lir_capacity; uint n_tokens; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> semantic_expr_type;
StructuredBuffer<uint> semantic_value_id;
StructuredBuffer<uint> semantic_value_type;
StructuredBuffer<uint> semantic_call_target;
StructuredBuffer<uint> semantic_call_kind;
StructuredBuffer<uint> semantic_call_result_type;
StructuredBuffer<uint> semantic_function_id;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<int> semantic_if_depth;
StructuredBuffer<uint> member_result_field_ordinal;
StructuredBuffer<uint> compact_expr_root;
StructuredBuffer<uint> compact_nearest_loop;
StructuredBuffer<uint> compact_array_element_start;
StructuredBuffer<uint> compact_array_element_owner_count;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<uint> semantic_lir_count;
StructuredBuffer<uint> semantic_lir_offset;
StructuredBuffer<uint> semantic_execution_rank;
ByteAddressBuffer semantic_page;
RWStructuredBuffer<SemanticLirCore> semantic_lir_core;
RWStructuredBuffer<SemanticLirOperands> semantic_lir_operands;
RWStructuredBuffer<SemanticLirSchedule> semantic_lir_schedule;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint lir_for_hir(uint node, uint hir_count)
{
    return node != LIR_INVALID && node < hir_count && semantic_lir_count[node] != 0u
        ? semantic_lir_offset[node]
        : LIR_INVALID;
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

void write_schedule(uint row, uint node, uint local_row, uint local_count,
                    uint hir_count, HirCore hir, HirLinks links,
                    HirPayload payload)
{
    SemanticLirSchedule schedule;
    schedule.function_id = semantic_function_id[node];
    bool expression_row = semantic_lir_is_expression(hir);
    uint root = expression_row ? compact_expr_root[node] : LIR_INVALID;
    uint local_op = semantic_lir_local_op(hir, payload, local_row, local_count);
    bool range_for = local_count == 17u && semantic_lir_is_loop(hir, payload);
    if (range_for)
    {
        HirPayload range = compact_hir_payload[payload.c];
        uint start_node = range.b;
        uint end_node = range.c;
        uint start_token = bounded_token(start_node, hir_count, hir.token_start);
        uint end_token = bounded_token(end_node, hir_count, start_token);
        if (local_row == 0u)
            schedule.execution_region = start_token;
        else if (local_row <= 7u)
            schedule.execution_region = end_token;
        else if (local_row == 8u)
        {
            schedule.execution_region = bounded_token(payload.d, hir_count, hir.token_start);
            schedule.execution_rank = 0u;
            schedule.execution_tie = 0u;
            semantic_lir_schedule[row] = schedule;
            return;
        }
        else
            schedule.execution_region = hir.token_end;
        schedule.execution_rank = 0xffffffffu;
        schedule.execution_tie = local_row;
        semantic_lir_schedule[row] = schedule;
        return;
    }
    if (root == LIR_INVALID || root >= hir_count)
    {
        uint operand = LIR_INVALID;
        if (local_op == SEMANTIC_LIR_OP_RETURN ||
            local_op == SEMANTIC_LIR_OP_IF_BEGIN ||
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
    // Aggregate elements are independent expression roots in compact HIR.
    // Their owner becomes executable only at the closing boundary, after all
    // element regions. Statements consuming the aggregate share that same
    // completion region and follow it through the ordinary expression/effect
    // tie ordering.
    schedule.execution_region = root != LIR_INVALID && root < hir_count
        ? (aggregate_root ? root_core.token_end : root_core.token_start)
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
            schedule.execution_region = hir.token_end;
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
                schedule.execution_region = hir.token_end;
                schedule.execution_rank = hir.token_end;
                schedule.execution_tie = local_row - 3u;
            }
        }
    }
    semantic_lir_schedule[row] = schedule;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint4 page = semantic_page.Load4(0u);
    uint semantic_start = page.x;
    uint semantic_count = page.y;
    uint hir_start = page.z;
    uint hir_page_count = page.w;
    uint local_node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (local_node >= hir_page_count) return;
    uint node = hir_start + local_node;
    uint hir_count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (node >= hir_count || semantic_lir_count[node] == 0u) return;
    uint first_row = semantic_lir_offset[node];

    HirCore hir = compact_hir_core[node];
    HirLinks links = compact_hir_links[node];
    HirPayload payload = compact_hir_payload[node];
    uint local_count = semantic_lir_count[node];
    bool range_for = local_count == 17u && semantic_lir_is_loop(hir, payload);
    HirPayload range_payload;
    range_payload.a = 0u;
    range_payload.b = LIR_INVALID;
    range_payload.c = LIR_INVALID;
    range_payload.d = LIR_INVALID;
    if (range_for && payload.c < hir_count)
        range_payload = compact_hir_payload[payload.c];

    for (uint local_row = 0u; local_row < local_count; ++local_row)
    {
    uint row = first_row + local_row;
    if (row < semantic_start || row >= semantic_start + semantic_count ||
        row >= gParams.lir_capacity) continue;
    uint page_row = row - semantic_start;
    uint op = semantic_lir_local_op(hir, payload, local_row, local_count);
    if (range_for)
    {
        if (local_row <= 1u) op = SEMANTIC_LIR_OP_VALUE_SET;
        else if (local_row == 2u) op = SEMANTIC_LIR_OP_BLOCK_BEGIN;
        else if (local_row == 3u) op = SEMANTIC_LIR_OP_LOOP_BEGIN;
        else if (local_row == 4u || local_row == 5u || local_row == 10u)
            op = SEMANTIC_LIR_OP_VALUE_GET;
        else if (local_row == 6u) op = SEMANTIC_LIR_OP_COMPARE;
        else if (local_row == 7u) op = SEMANTIC_LIR_OP_BRANCH_IF;
        else if (local_row == 8u) op = SEMANTIC_LIR_OP_BLOCK_BEGIN;
        else if (local_row == 10u) op = SEMANTIC_LIR_OP_VALUE_GET;
        else if (local_row == 11u) op = SEMANTIC_LIR_OP_CONST_I32;
        else if (local_row == 12u) op = SEMANTIC_LIR_OP_ADD;
        else if (local_row == 13u) op = SEMANTIC_LIR_OP_STORE;
        else if (local_row == 14u) op = SEMANTIC_LIR_OP_BRANCH;
        else op = SEMANTIC_LIR_OP_CONTROL_END;
    }
    if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 2u)
        op = SEMANTIC_LIR_OP_CALL_INTRINSIC;
    else if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 3u)
        op = SEMANTIC_LIR_OP_CALL_HOST;

    SemanticLirCore core;
    core.op = op;
    core.type_id = semantic_type_for_hir(node, hir_count);
    if (op == SEMANTIC_LIR_OP_VALUE_GET || op == SEMANTIC_LIR_OP_VALUE_SET ||
        op == SEMANTIC_LIR_OP_STORE)
        core.type_id = semantic_value_type[node];
    if (op == SEMANTIC_LIR_OP_RETURN &&
        semantic_function_id[node] != LIR_INVALID)
        core.type_id = semantic_lir_functions[semantic_function_id[node]].result_type;
    if (range_for) core.type_id = 3u;
    // Comparisons produce bool but machine selection depends on the operand
    // representation. The semantic instruction type therefore records the
    // compared value type for this opcode.
    if (op == SEMANTIC_LIR_OP_COMPARE && payload.b < hir_count)
        core.type_id = semantic_type_for_hir(payload.b, hir_count);
    core.source_hir = node;
    core.flags = op == SEMANTIC_LIR_OP_COMPARE ? comparison_predicate(payload.a) : 0u;
    if (op == SEMANTIC_LIR_OP_LOAD && hir.kind == HIR_INDEX_EXPR)
        core.flags |= SEMANTIC_LIR_FLAG_INDEXED;
    if (op == SEMANTIC_LIR_OP_LOAD && hir.kind == HIR_MEMBER_EXPR)
        core.flags |= SEMANTIC_LIR_FLAG_FIELD;
    if (range_for && op == SEMANTIC_LIR_OP_COMPARE)
        core.flags = range_payload.a == HIR_EXPR_RANGE_INCLUSIVE ? 4u : 2u;
    if (op == SEMANTIC_LIR_OP_INVALID) core.flags |= SEMANTIC_LIR_FLAG_UNSUPPORTED;
    if (local_count > 1u) core.flags |= SEMANTIC_LIR_FLAG_SYNTHETIC_CONTROL;
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
        int branch_depth = semantic_if_depth[hir.token_start];
        int loop_depth = semantic_if_depth[loop_core.token_start];
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
    if (structured_loop && (local_row == 2u || local_row == 3u))
        core.flags |= SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID;
    if (structured_loop && local_row == 2u)
        core.flags |= SEMANTIC_LIR_FLAG_BRANCH_FALSE;
    if (range_for && (local_row == 7u || local_row == 14u))
        core.flags |= SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID;
    if (range_for && local_row == 7u)
        core.flags |= SEMANTIC_LIR_FLAG_BRANCH_FALSE;

    SemanticLirOperands operands;
    operands.result = row;
    operands.a = LIR_INVALID;
    operands.b = LIR_INVALID;
    operands.c = LIR_INVALID;

    if (range_for)
    {
        uint end_value_id = gParams.n_tokens + node;
        if (local_row == 0u)
        {
            operands.a = payload.b;
            operands.b = lir_for_value_hir(range_payload.b, hir_count);
        }
        else if (local_row == 1u)
        {
            operands.a = end_value_id;
            operands.b = lir_for_value_hir(range_payload.c, hir_count);
        }
        else if (local_row == 4u || local_row == 10u)
            operands.a = payload.b;
        else if (local_row == 5u)
            operands.a = end_value_id;
        else if (local_row == 6u)
        {
            operands.a = first_row + 4u;
            operands.b = first_row + 5u;
        }
        else if (local_row == 7u)
        {
            operands.a = first_row + 6u;
            operands.b = 1u;
            operands.c = first_row + 16u;
        }
        else if (local_row == 11u)
            operands.a = 1u;
        else if (local_row == 12u)
        {
            operands.a = first_row + 10u;
            operands.b = first_row + 11u;
        }
        else if (local_row == 13u)
        {
            operands.a = payload.b;
            operands.b = first_row + 12u;
        }
        else if (local_row == 14u)
        {
            operands.a = first_row + 3u;
            operands.b = 0u;
        }
    }
    else if (op == SEMANTIC_LIR_OP_CONST_I32 || op == SEMANTIC_LIR_OP_CONST_F32 ||
        op == SEMANTIC_LIR_OP_CONST_STRING)
    {
        operands.a = payload.b;
        if (op == SEMANTIC_LIR_OP_CONST_I32 && payload.a == HIR_EXPR_TRUE)
            operands.a = 1u;
        else if (op == SEMANTIC_LIR_OP_CONST_I32 && payload.a == HIR_EXPR_FALSE)
            operands.a = 0u;
    }
    else if (op == SEMANTIC_LIR_OP_VALUE_GET)
        operands.a = semantic_value_id[node];
    else if (op == SEMANTIC_LIR_OP_CALL ||
             op == SEMANTIC_LIR_OP_CALL_INTRINSIC ||
             op == SEMANTIC_LIR_OP_CALL_HOST)
    {
        operands.a = semantic_call_target[node];
        operands.b = payload.b;
        operands.c = payload.c;
    }
    else if (op == SEMANTIC_LIR_OP_VALUE_SET)
    {
        operands.a = semantic_value_id[node];
        operands.b = lir_for_value_hir(payload.c, hir_count);
    }
    else if (op == SEMANTIC_LIR_OP_RETURN)
        operands.a = lir_for_value_hir(payload.b, hir_count);
    else if (op == SEMANTIC_LIR_OP_STORE)
    {
        operands.a = payload.b < hir_count ? semantic_value_id[payload.b] : LIR_INVALID;
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
        operands.a = array ? compact_array_element_start[node]
                           : compact_array_element_row_count[0u] + payload.b;
        operands.b = array ? compact_array_element_owner_count[node] : payload.c;
        operands.c = array ? 0u : 1u;
    }
    else if (op == SEMANTIC_LIR_OP_LOAD && hir.kind == HIR_MEMBER_EXPR)
    {
        // The compact member payload already names the canonical receiver
        // expression. Following its enclosing expression root here can turn
        // `pair` in `pair.left + pair.right` into the binary result and create
        // a target-level use-before-definition cycle.
        operands.a = lir_for_hir(payload.b, hir_count);
        operands.b = payload.c < gParams.n_tokens
            ? member_result_field_ordinal[payload.c] : LIR_INVALID;
    }
    else if (op == SEMANTIC_LIR_OP_BRANCH)
    {
        operands.a = lir_for_hir(compact_nearest_loop[node], hir_count);
        if (operands.a != LIR_INVALID)
        {
            HirCore loop_core = compact_hir_core[compact_nearest_loop[node]];
            bool range_loop = semantic_lir_count[compact_nearest_loop[node]] == 17u &&
                semantic_lir_is_loop(loop_core,
                    compact_hir_payload[compact_nearest_loop[node]]);
            operands.a += range_loop
                ? (hir.kind == HIR_CONTINUE_STMT ? 9u : 16u)
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

    semantic_lir_core[page_row] = core;
    semantic_lir_operands[page_row] = operands;
    write_schedule(page_row, node, local_row, local_count, hir_count, hir, links, payload);
    }
}
