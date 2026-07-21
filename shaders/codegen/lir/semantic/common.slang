import codegen.lowering_ir;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirPayload { uint a; uint b; uint c; uint d; };

static const uint LIR_INVALID = 0xffffffffu;

static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;
static const uint HIR_EXPR = 14u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_POSTFIX_EXPR = 18u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_PATH_EXPR = 33u;

static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_RETURN = 2u;
static const uint HIR_STMT_IF = 3u;
static const uint HIR_STMT_CONST = 4u;
static const uint HIR_STMT_ASSIGN = 5u;
static const uint HIR_STMT_WHILE = 6u;
static const uint HIR_STMT_FOR = 7u;

static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_STRING = 28u;
static const uint HIR_EXPR_CHAR = 29u;
static const uint HIR_EXPR_RANGE = 30u;
static const uint HIR_EXPR_RANGE_INCLUSIVE = 34u;

bool semantic_lir_is_expression(HirCore core)
{
    return core.kind == HIR_EXPR || core.kind == HIR_ASSIGN_EXPR ||
        core.kind == HIR_BINARY_EXPR || core.kind == HIR_UNARY_EXPR ||
        core.kind == HIR_POSTFIX_EXPR || core.kind == HIR_CALL_EXPR ||
        core.kind == HIR_INDEX_EXPR || core.kind == HIR_MEMBER_EXPR ||
        core.kind == HIR_NAME_EXPR || core.kind == HIR_LITERAL_EXPR ||
        core.kind == HIR_PATH_EXPR ||
        core.kind == HIR_ARRAY_EXPR || core.kind == HIR_STRUCT_LITERAL_EXPR ||
        core.kind == HIR_MATCH_EXPR;
}

bool semantic_lir_is_if(HirCore core, HirPayload payload)
{
    return core.kind == HIR_IF_STMT ||
        (core.kind == HIR_STMT && payload.a == HIR_STMT_IF);
}

bool semantic_lir_is_loop(HirCore core, HirPayload payload)
{
    return core.kind == HIR_WHILE_STMT || core.kind == HIR_FOR_STMT ||
        (core.kind == HIR_STMT &&
         (payload.a == HIR_STMT_WHILE || payload.a == HIR_STMT_FOR));
}

bool semantic_lir_is_control(HirCore core, HirPayload payload)
{
    return semantic_lir_is_if(core, payload) || semantic_lir_is_loop(core, payload);
}

uint semantic_lir_row_count(HirCore core, HirPayload payload)
{
    if (semantic_lir_is_if(core, payload))
        return payload.d == LIR_INVALID ? 2u : 3u;
    if (semantic_lir_is_loop(core, payload))
        return 6u;
    if (semantic_lir_op(core, payload) != SEMANTIC_LIR_OP_INVALID) return 1u;

    // These are executable constructs. Until their full semantic contract is
    // implemented they retain a flagged row and must fail explicitly instead
    // of disappearing from the generated program.
    if (core.kind == HIR_BREAK_STMT || core.kind == HIR_CONTINUE_STMT ||
        core.kind == HIR_INDEX_EXPR || core.kind == HIR_MEMBER_EXPR ||
        core.kind == HIR_MATCH_EXPR)
        return 1u;
    if ((core.kind == HIR_EXPR || core.kind == HIR_ASSIGN_EXPR ||
         core.kind == HIR_BINARY_EXPR || core.kind == HIR_UNARY_EXPR ||
         core.kind == HIR_POSTFIX_EXPR || core.kind == HIR_LITERAL_EXPR) &&
        payload.a != HIR_EXPR_FORWARD)
        return 1u;
    return 0u;
}

uint semantic_lir_local_op(HirCore core, HirPayload payload, uint local_row,
                           uint row_count)
{
    if (semantic_lir_is_if(core, payload))
    {
        if (local_row == 0u) return SEMANTIC_LIR_OP_IF_BEGIN;
        if (row_count == 3u && local_row == 1u) return SEMANTIC_LIR_OP_ELSE;
        return SEMANTIC_LIR_OP_CONTROL_END;
    }
    if (semantic_lir_is_loop(core, payload))
    {
        if (local_row == 0u) return SEMANTIC_LIR_OP_BLOCK_BEGIN;
        if (local_row == 1u) return SEMANTIC_LIR_OP_LOOP_BEGIN;
        if (local_row == 2u) return SEMANTIC_LIR_OP_BRANCH_IF;
        if (local_row == 3u) return SEMANTIC_LIR_OP_BRANCH;
        return SEMANTIC_LIR_OP_CONTROL_END;
    }
    return semantic_lir_op(core, payload);
}

uint semantic_lir_op(HirCore core, HirPayload payload)
{
    if (core.kind == HIR_ARRAY_EXPR || core.kind == HIR_STRUCT_LITERAL_EXPR)
        return SEMANTIC_LIR_OP_AGGREGATE_NEW;
    if (core.kind == HIR_INDEX_EXPR || core.kind == HIR_MEMBER_EXPR)
        return SEMANTIC_LIR_OP_LOAD;
    if (core.kind == HIR_CALL_EXPR) return SEMANTIC_LIR_OP_CALL;
    if (core.kind == HIR_BREAK_STMT || core.kind == HIR_CONTINUE_STMT)
        return SEMANTIC_LIR_OP_BRANCH;
    if (core.kind == HIR_LET_STMT ||
        (core.kind == HIR_STMT &&
         (payload.a == HIR_STMT_LET || payload.a == HIR_STMT_CONST)))
        return SEMANTIC_LIR_OP_VALUE_SET;
    if (core.kind == HIR_RETURN_STMT ||
        (core.kind == HIR_STMT && payload.a == HIR_STMT_RETURN))
        return SEMANTIC_LIR_OP_RETURN;
    if ((core.kind == HIR_STMT || core.kind == HIR_ASSIGN_EXPR) &&
        payload.a == HIR_STMT_ASSIGN)
        return SEMANTIC_LIR_OP_STORE;
    if (semantic_lir_is_if(core, payload)) return SEMANTIC_LIR_OP_IF_BEGIN;
    if (semantic_lir_is_loop(core, payload)) return SEMANTIC_LIR_OP_LOOP_BEGIN;

    if (core.kind != HIR_EXPR && core.kind != HIR_ASSIGN_EXPR &&
        core.kind != HIR_BINARY_EXPR && core.kind != HIR_UNARY_EXPR &&
        core.kind != HIR_POSTFIX_EXPR && core.kind != HIR_NAME_EXPR &&
        core.kind != HIR_LITERAL_EXPR && core.kind != HIR_PATH_EXPR)
        return SEMANTIC_LIR_OP_INVALID;

    uint form = payload.a;
    if (form == HIR_EXPR_FORWARD) return SEMANTIC_LIR_OP_INVALID;
    if (form == HIR_EXPR_NAME) return SEMANTIC_LIR_OP_VALUE_GET;
    if (form == HIR_EXPR_INT || form == HIR_EXPR_TRUE ||
        form == HIR_EXPR_FALSE)
        return SEMANTIC_LIR_OP_CONST_I32;
    if (form == HIR_EXPR_FLOAT) return SEMANTIC_LIR_OP_CONST_F32;
    if (form == HIR_EXPR_STRING) return SEMANTIC_LIR_OP_CONST_STRING;
    if (form == HIR_EXPR_NOT) return SEMANTIC_LIR_OP_LOGICAL_NOT;
    if (form == HIR_EXPR_NEG) return SEMANTIC_LIR_OP_NEGATE;
    if (form == HIR_EXPR_ADD) return SEMANTIC_LIR_OP_ADD;
    if (form == HIR_EXPR_SUB) return SEMANTIC_LIR_OP_SUB;
    if (form == HIR_EXPR_MUL) return SEMANTIC_LIR_OP_MUL;
    if (form == HIR_EXPR_DIV) return SEMANTIC_LIR_OP_DIV;
    if (form == HIR_EXPR_MOD) return SEMANTIC_LIR_OP_REM;
    if (form == HIR_EXPR_AND) return SEMANTIC_LIR_OP_LOGICAL_AND;
    if (form == HIR_EXPR_OR) return SEMANTIC_LIR_OP_LOGICAL_OR;
    if (form == HIR_EXPR_BIT_AND) return SEMANTIC_LIR_OP_BIT_AND;
    if (form == HIR_EXPR_BIT_OR) return SEMANTIC_LIR_OP_BIT_OR;
    if (form == HIR_EXPR_BIT_XOR) return SEMANTIC_LIR_OP_BIT_XOR;
    if (form == HIR_EXPR_SHL) return SEMANTIC_LIR_OP_SHIFT_LEFT;
    if (form == HIR_EXPR_SHR) return SEMANTIC_LIR_OP_SHIFT_RIGHT;
    if (form >= HIR_EXPR_EQ && form <= HIR_EXPR_GE)
        return SEMANTIC_LIR_OP_COMPARE;
    return SEMANTIC_LIR_OP_INVALID;
}

uint semantic_lir_type(uint packed_type)
{
    return packed_type >> 28u;
}

uint comparison_predicate(uint form)
{
    return form >= HIR_EXPR_EQ && form <= HIR_EXPR_GE
        ? form - HIR_EXPR_EQ
        : 0u;
}
