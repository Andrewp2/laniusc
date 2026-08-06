import hir_records;
import codegen.lir.semantic.common;
import codegen.lowering_ir;

static const uint SEMANTIC_LOOP_RECIPE_NONE = 0u;
static const uint SEMANTIC_LOOP_RECIPE_DIRECT_RANGE = 1u;
static const uint SEMANTIC_LOOP_RECIPE_RANGE_VALUE = 2u;
static const uint SEMANTIC_LOOP_RECIPE_ARRAY = 3u;

struct SemanticLoopRecipe
{
    uint kind;
    uint row_count;
}

static const uint LOOP_OPERAND_NONE = 0u;
static const uint LOOP_OPERAND_ZERO = 1u;
static const uint LOOP_OPERAND_ONE = 2u;
static const uint LOOP_OPERAND_BINDING_DECL = 3u;
static const uint LOOP_OPERAND_ITERABLE_DECL = 4u;
static const uint LOOP_OPERAND_SYNTHETIC_DECL = 5u;
static const uint LOOP_OPERAND_RANGE_START = 6u;
static const uint LOOP_OPERAND_RANGE_END = 7u;
static const uint LOOP_OPERAND_ARRAY_LENGTH = 8u;
static const uint LOOP_OPERAND_ROW_BASE = 256u;

struct SemanticLoopOperandRecipe
{
    uint a;
    uint b;
    uint c;
}

bool semantic_lir_is_for(HirCore core, HirPayload payload)
{
    return core.kind == HIR_FOR_STMT ||
        (core.kind == HIR_STMT && payload.a == HIR_STMT_FOR);
}

SemanticLoopRecipe semantic_loop_recipe(HirCore core, HirPayload payload,
                                        uint iterable_form, uint iterable_kind,
                                        uint array_length)
{
    SemanticLoopRecipe recipe;
    recipe.kind = SEMANTIC_LOOP_RECIPE_NONE;
    recipe.row_count = semantic_lir_row_count(core, payload);
    if (!semantic_lir_is_for(core, payload)) return recipe;

    if (iterable_form == HIR_EXPR_RANGE ||
        iterable_form == HIR_EXPR_RANGE_INCLUSIVE)
        recipe.kind = SEMANTIC_LOOP_RECIPE_DIRECT_RANGE;
    else if (iterable_kind == 1u || iterable_kind == 2u)
        recipe.kind = SEMANTIC_LOOP_RECIPE_RANGE_VALUE;
    else if (iterable_kind == 3u || array_length != LIR_INVALID)
        recipe.kind = SEMANTIC_LOOP_RECIPE_ARRAY;
    else
        return recipe;

    recipe.row_count = recipe.kind == SEMANTIC_LOOP_RECIPE_DIRECT_RANGE
        ? 17u : 21u;
    return recipe;
}

uint semantic_loop_recipe_op(uint recipe, uint row)
{
    static const uint direct_range_ops[17] = {
        SEMANTIC_LIR_OP_VALUE_SET,
        SEMANTIC_LIR_OP_VALUE_SET,
        SEMANTIC_LIR_OP_BLOCK_BEGIN,
        SEMANTIC_LIR_OP_LOOP_BEGIN,
        SEMANTIC_LIR_OP_VALUE_GET,
        SEMANTIC_LIR_OP_VALUE_GET,
        SEMANTIC_LIR_OP_COMPARE,
        SEMANTIC_LIR_OP_BRANCH_IF,
        SEMANTIC_LIR_OP_BLOCK_BEGIN,
        SEMANTIC_LIR_OP_CONTROL_END,
        SEMANTIC_LIR_OP_VALUE_GET,
        SEMANTIC_LIR_OP_CONST_I32,
        SEMANTIC_LIR_OP_ADD,
        SEMANTIC_LIR_OP_STORE,
        SEMANTIC_LIR_OP_BRANCH,
        SEMANTIC_LIR_OP_CONTROL_END,
        SEMANTIC_LIR_OP_CONTROL_END,
    };
    static const uint range_value_ops[21] = {
        SEMANTIC_LIR_OP_VALUE_GET,
        SEMANTIC_LIR_OP_LOAD,
        SEMANTIC_LIR_OP_VALUE_SET,
        SEMANTIC_LIR_OP_VALUE_GET,
        SEMANTIC_LIR_OP_LOAD,
        SEMANTIC_LIR_OP_VALUE_SET,
        SEMANTIC_LIR_OP_BLOCK_BEGIN,
        SEMANTIC_LIR_OP_LOOP_BEGIN,
        SEMANTIC_LIR_OP_VALUE_GET,
        SEMANTIC_LIR_OP_VALUE_GET,
        SEMANTIC_LIR_OP_COMPARE,
        SEMANTIC_LIR_OP_BRANCH_IF,
        SEMANTIC_LIR_OP_BLOCK_BEGIN,
        SEMANTIC_LIR_OP_CONTROL_END,
        SEMANTIC_LIR_OP_VALUE_GET,
        SEMANTIC_LIR_OP_CONST_I32,
        SEMANTIC_LIR_OP_ADD,
        SEMANTIC_LIR_OP_STORE,
        SEMANTIC_LIR_OP_BRANCH,
        SEMANTIC_LIR_OP_CONTROL_END,
        SEMANTIC_LIR_OP_CONTROL_END,
    };
    static const uint array_ops[21] = {
        SEMANTIC_LIR_OP_CONST_I32,
        SEMANTIC_LIR_OP_VALUE_SET,
        SEMANTIC_LIR_OP_BLOCK_BEGIN,
        SEMANTIC_LIR_OP_LOOP_BEGIN,
        SEMANTIC_LIR_OP_VALUE_GET,
        SEMANTIC_LIR_OP_CONST_I32,
        SEMANTIC_LIR_OP_COMPARE,
        SEMANTIC_LIR_OP_BRANCH_IF,
        SEMANTIC_LIR_OP_BLOCK_BEGIN,
        SEMANTIC_LIR_OP_VALUE_GET,
        SEMANTIC_LIR_OP_VALUE_GET,
        SEMANTIC_LIR_OP_LOAD,
        SEMANTIC_LIR_OP_VALUE_SET,
        SEMANTIC_LIR_OP_CONTROL_END,
        SEMANTIC_LIR_OP_VALUE_GET,
        SEMANTIC_LIR_OP_CONST_I32,
        SEMANTIC_LIR_OP_ADD,
        SEMANTIC_LIR_OP_STORE,
        SEMANTIC_LIR_OP_BRANCH,
        SEMANTIC_LIR_OP_CONTROL_END,
        SEMANTIC_LIR_OP_CONTROL_END,
    };

    if (recipe == SEMANTIC_LOOP_RECIPE_DIRECT_RANGE && row < 17u)
        return direct_range_ops[row];
    if (recipe == SEMANTIC_LOOP_RECIPE_RANGE_VALUE && row < 21u)
        return range_value_ops[row];
    if (recipe == SEMANTIC_LOOP_RECIPE_ARRAY && row < 21u)
        return array_ops[row];
    return SEMANTIC_LIR_OP_INVALID;
}

SemanticLoopOperandRecipe semantic_loop_operand_recipe(uint recipe, uint row)
{
    static const uint direct_a[17] = {
        LOOP_OPERAND_BINDING_DECL, LOOP_OPERAND_SYNTHETIC_DECL,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_BINDING_DECL,
        LOOP_OPERAND_SYNTHETIC_DECL, LOOP_OPERAND_ROW_BASE + 4u,
        LOOP_OPERAND_ROW_BASE + 6u, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_BINDING_DECL, LOOP_OPERAND_ONE,
        LOOP_OPERAND_ROW_BASE + 10u, LOOP_OPERAND_BINDING_DECL,
        LOOP_OPERAND_ROW_BASE + 3u, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
    };
    static const uint direct_b[17] = {
        LOOP_OPERAND_RANGE_START, LOOP_OPERAND_RANGE_END,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_ROW_BASE + 5u, LOOP_OPERAND_ONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_ROW_BASE + 11u,
        LOOP_OPERAND_ROW_BASE + 12u, LOOP_OPERAND_ZERO,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
    };
    static const uint direct_c[17] = {
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_ROW_BASE + 16u,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
    };
    static const uint range_value_a[21] = {
        LOOP_OPERAND_ITERABLE_DECL, LOOP_OPERAND_ROW_BASE + 0u,
        LOOP_OPERAND_BINDING_DECL, LOOP_OPERAND_ITERABLE_DECL,
        LOOP_OPERAND_ROW_BASE + 3u, LOOP_OPERAND_SYNTHETIC_DECL,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_BINDING_DECL,
        LOOP_OPERAND_SYNTHETIC_DECL, LOOP_OPERAND_ROW_BASE + 8u,
        LOOP_OPERAND_ROW_BASE + 10u, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_BINDING_DECL, LOOP_OPERAND_ONE,
        LOOP_OPERAND_ROW_BASE + 14u, LOOP_OPERAND_BINDING_DECL,
        LOOP_OPERAND_ROW_BASE + 7u, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
    };
    static const uint range_value_b[21] = {
        LOOP_OPERAND_NONE, LOOP_OPERAND_ZERO, LOOP_OPERAND_ROW_BASE + 1u,
        LOOP_OPERAND_NONE, LOOP_OPERAND_ONE, LOOP_OPERAND_ROW_BASE + 4u,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_ROW_BASE + 9u, LOOP_OPERAND_ONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_ROW_BASE + 15u,
        LOOP_OPERAND_ROW_BASE + 16u, LOOP_OPERAND_ZERO,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
    };
    static const uint range_value_c[21] = {
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_ROW_BASE + 20u,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
    };
    static const uint array_a[21] = {
        LOOP_OPERAND_ZERO, LOOP_OPERAND_SYNTHETIC_DECL,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_SYNTHETIC_DECL,
        LOOP_OPERAND_ARRAY_LENGTH, LOOP_OPERAND_ROW_BASE + 4u,
        LOOP_OPERAND_ROW_BASE + 6u, LOOP_OPERAND_NONE,
        LOOP_OPERAND_ITERABLE_DECL, LOOP_OPERAND_SYNTHETIC_DECL,
        LOOP_OPERAND_ROW_BASE + 9u, LOOP_OPERAND_BINDING_DECL,
        LOOP_OPERAND_NONE, LOOP_OPERAND_SYNTHETIC_DECL, LOOP_OPERAND_ONE,
        LOOP_OPERAND_ROW_BASE + 14u, LOOP_OPERAND_SYNTHETIC_DECL,
        LOOP_OPERAND_ROW_BASE + 3u, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
    };
    static const uint array_b[21] = {
        LOOP_OPERAND_NONE, LOOP_OPERAND_ROW_BASE + 0u, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_ROW_BASE + 5u, LOOP_OPERAND_ONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_ROW_BASE + 10u,
        LOOP_OPERAND_ROW_BASE + 11u, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_ROW_BASE + 15u,
        LOOP_OPERAND_ROW_BASE + 16u, LOOP_OPERAND_ZERO,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
    };
    static const uint array_c[21] = {
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_ROW_BASE + 20u,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE, LOOP_OPERAND_NONE, LOOP_OPERAND_NONE,
        LOOP_OPERAND_NONE,
    };

    SemanticLoopOperandRecipe result;
    result.a = LOOP_OPERAND_NONE;
    result.b = LOOP_OPERAND_NONE;
    result.c = LOOP_OPERAND_NONE;
    if (recipe == SEMANTIC_LOOP_RECIPE_DIRECT_RANGE && row < 17u)
    {
        result.a = direct_a[row]; result.b = direct_b[row]; result.c = direct_c[row];
    }
    else if (recipe == SEMANTIC_LOOP_RECIPE_RANGE_VALUE && row < 21u)
    {
        result.a = range_value_a[row];
        result.b = range_value_b[row];
        result.c = range_value_c[row];
    }
    else if (recipe == SEMANTIC_LOOP_RECIPE_ARRAY && row < 21u)
    {
        result.a = array_a[row]; result.b = array_b[row]; result.c = array_c[row];
    }
    return result;
}

uint semantic_loop_recipe_flags(uint recipe, uint row)
{
    uint flags = SEMANTIC_LIR_FLAG_SYNTHETIC_CONTROL;
    if (recipe == SEMANTIC_LOOP_RECIPE_RANGE_VALUE && (row == 1u || row == 4u))
        flags |= SEMANTIC_LIR_FLAG_FIELD;
    if (recipe == SEMANTIC_LOOP_RECIPE_ARRAY && row == 11u)
        flags |= SEMANTIC_LIR_FLAG_INDEXED;

    bool conditional_branch =
        (recipe == SEMANTIC_LOOP_RECIPE_DIRECT_RANGE && row == 7u) ||
        (recipe == SEMANTIC_LOOP_RECIPE_RANGE_VALUE && row == 11u) ||
        (recipe == SEMANTIC_LOOP_RECIPE_ARRAY && row == 7u);
    bool back_edge =
        (recipe == SEMANTIC_LOOP_RECIPE_DIRECT_RANGE && row == 14u) ||
        (recipe == SEMANTIC_LOOP_RECIPE_RANGE_VALUE && row == 18u) ||
        (recipe == SEMANTIC_LOOP_RECIPE_ARRAY && row == 18u);
    if (conditional_branch || back_edge)
        flags |= SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID;
    if (conditional_branch)
        flags |= SEMANTIC_LIR_FLAG_BRANCH_FALSE;
    return flags;
}
