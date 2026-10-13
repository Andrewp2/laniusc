import codegen.lowering_ir;

// Prefix: zero or more pointer loads, scrutinee store, enclosing block.
// Each arm retains its eight-row recipe. The final three rows trap on no
// match, close the block, and read the selected result. Argument capture is
// owned separately and always follows the complete recipe.
struct SemanticMatchRecipe
{
    uint address_load_count;
    uint arm_count;
    bool valid;
}

uint semantic_match_first_arm(SemanticMatchRecipe recipe)
{
    return recipe.address_load_count + 2u;
}

uint semantic_match_row_count(SemanticMatchRecipe recipe)
{
    return semantic_match_first_arm(recipe) + recipe.arm_count * 8u + 3u;
}

bool semantic_match_is_arm(SemanticMatchRecipe recipe, uint row)
{
    uint first = semantic_match_first_arm(recipe);
    return row >= first && row - first < recipe.arm_count * 8u;
}

uint semantic_match_arm_index(SemanticMatchRecipe recipe, uint row)
{
    return (row - semantic_match_first_arm(recipe)) / 8u;
}

uint semantic_match_phase(SemanticMatchRecipe recipe, uint row)
{
    return (row - semantic_match_first_arm(recipe)) % 8u;
}

uint semantic_match_arm_start(SemanticMatchRecipe recipe, uint arm)
{
    return semantic_match_first_arm(recipe) + arm * 8u;
}

SemanticMatchRecipe semantic_match_recipe_from_count(uint count, uint address_loads)
{
    SemanticMatchRecipe recipe;
    recipe.address_load_count = address_loads;
    uint prefix_and_tail = address_loads + 5u;
    recipe.valid = address_loads <= 63u && count >= prefix_and_tail &&
        (count - prefix_and_tail) % 8u == 0u;
    recipe.arm_count = recipe.valid ? (count - prefix_and_tail) / 8u : 0u;
    return recipe;
}

uint semantic_match_op(SemanticMatchRecipe recipe, uint row)
{
    if (!recipe.valid) return SEMANTIC_LIR_OP_INVALID;
    if (row < recipe.address_load_count) return SEMANTIC_LIR_OP_LOAD;
    if (row == recipe.address_load_count) return SEMANTIC_LIR_OP_VALUE_SET;
    if (row == recipe.address_load_count + 1u) return SEMANTIC_LIR_OP_BLOCK_BEGIN;
    uint count = semantic_match_row_count(recipe);
    if (row + 1u == count) return SEMANTIC_LIR_OP_VALUE_GET;
    if (row + 3u >= count)
        return row + 3u == count ? SEMANTIC_LIR_OP_TRAP : SEMANTIC_LIR_OP_CONTROL_END;
    uint phase = semantic_match_phase(recipe, row);
    if (phase == 0u) return SEMANTIC_LIR_OP_VALUE_GET;
    if (phase == 1u) return SEMANTIC_LIR_OP_LOAD;
    if (phase == 2u) return SEMANTIC_LIR_OP_CONST_I32;
    if (phase == 3u) return SEMANTIC_LIR_OP_COMPARE;
    if (phase == 4u) return SEMANTIC_LIR_OP_IF_BEGIN;
    if (phase == 5u) return SEMANTIC_LIR_OP_VALUE_SET;
    if (phase == 6u) return SEMANTIC_LIR_OP_BRANCH;
    return SEMANTIC_LIR_OP_CONTROL_END;
}
