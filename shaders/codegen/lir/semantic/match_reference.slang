// Included by count and materialization after their checked/HIR inputs.
#include "../../../type_checker/checked_referent.slang"

uint semantic_match_variant_ordinal(uint pattern, uint hir_count)
{
    if (pattern >= hir_count) return LIR_INVALID;
    // Imported variant identity/ordinal survives dependency-page eviction.
    if (semantic_value_const_present_by_hir[pattern] == 0x40000000u)
        return semantic_value_const_by_hir[pattern].x;
    uint declaration = semantic_value_id[pattern];
    uint count = min(compact_variant_count[0u], gParams.n_hir_nodes);
    uint lo = 0u; uint hi = count;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_variants[mid].name_token < declaration) lo = mid + 1u;
        else hi = mid;
    }
    return lo < count && compact_variants[lo].name_token == declaration
        ? compact_variants[lo].ordinal : LIR_INVALID;
}

// A payload sub-pattern that names a variant binds nothing. It checks that
// payload's own discriminant: VALUE_GET, LOAD, CONST, COMPARE and IF_BEGIN
// open inside its arm, and CONTROL_END closes after the arm's branch, so a
// failed check falls through to the next arm.
static const uint SEMANTIC_MATCH_CHECK_ROWS = 6u;

uint semantic_match_payload_row(uint node)
{
    uint total = active_match_payload_count();
    uint lo = 0u; uint hi = total;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_match_payloads[mid].pattern < node) lo = mid + 1u;
        else hi = mid;
    }
    return lo < total && compact_match_payloads[lo].pattern == node ? lo : LIR_INVALID;
}

uint semantic_match_check_row(uint node, uint hir_count)
{
    uint row = semantic_match_payload_row(node);
    return row != LIR_INVALID &&
        semantic_match_variant_ordinal(node, hir_count) != LIR_INVALID
        ? row : LIR_INVALID;
}

bool semantic_match_pattern_accepts_enum(uint pattern, uint tag, uint payload, uint hir_count)
{
    if (pattern >= hir_count) return false;
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    bool nominal = tag == 3u && payload < capacity && type_instance_kind[payload] == 1u;
    if (semantic_value_const_present_by_hir[pattern] == 0x40000000u)
    {
        // The checker retained the enum parent's identity on the pattern's
        // token; these are stable identity columns, never resident page rows.
        uint token = compact_hir_core[pattern].token_start;
        return nominal && token < gParams.n_tokens && token < capacity &&
            external_type_library_id[token] != LIR_INVALID &&
            external_type_unit_id[token] != LIR_INVALID &&
            external_type_local_index[token] != LIR_INVALID &&
            external_type_library_id[token] == external_type_library_id[payload] &&
            external_type_unit_id[token] == external_type_unit_id[payload] &&
            external_type_local_index[token] == external_type_local_index[payload];
    }
    uint declaration = semantic_value_id[pattern];
    uint count = min(compact_variant_count[0u], gParams.n_hir_nodes);
    uint lo = 0u; uint hi = count;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_variants[mid].name_token < declaration) lo = mid + 1u;
        else hi = mid;
    }
    if (lo >= count || compact_variants[lo].name_token != declaration) return false;
    uint owner = compact_variants[lo].owner;
    if (owner >= hir_count || compact_hir_core[owner].kind != 26u) return false;
    uint enum_token = compact_hir_payload[owner].b;
    return enum_token < gParams.n_tokens && (nominal
        ? type_instance_decl_token[payload] == enum_token
        : tag == 1u && payload == 6144u + enum_token);
}

SemanticMatchRecipe semantic_match_recipe_for_hir(uint node, uint hir_count)
{
    SemanticMatchRecipe recipe;
    recipe.address_load_count = 0u;
    recipe.arm_count = 0u;
    recipe.valid = node < hir_count;
    if (!recipe.valid) return recipe;
    HirPayload match_value = compact_hir_payload[node];
    recipe.arm_count = match_value.b < active_match_arm_count()
        ? min(match_value.c, active_match_arm_count() - match_value.b) : 0u;
    if (match_value.a >= hir_count) { recipe.valid = false; return recipe; }
    uint tag = semantic_expr_ref_tag[match_value.a];
    uint payload = semantic_expr_ref_payload[match_value.a];
    // Owned enum addresses and ordinary scalar matches keep their old recipe.
    if (tag != 3u) return recipe;
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    if (payload >= capacity) { recipe.valid = false; return recipe; }
    if (type_instance_kind[payload] != 4u) return recipe;
    uint depth;
    if (!checked_referent_reference(tag, payload, depth))
    { recipe.valid = false; return recipe; }
    // Every observed variant must belong to the terminal enum. A wildcard
    // observes no tag or payload, so wildcard-only matches keep the original
    // value without dereferencing it. Scalar-reference matches require a
    // distinct value recipe and cannot use enum-address normalization.
    bool enum_pattern = false;
    for (uint ordinal = 0u; ordinal < recipe.arm_count; ordinal++)
    {
        uint pattern = compact_match_arms[match_value.b + ordinal].pattern;
        if (pattern >= hir_count) { recipe.valid = false; return recipe; }
        uint pattern_token = compact_hir_core[pattern].token_start;
        bool imported = semantic_value_const_present_by_hir[pattern] == 0x40000000u;
        if (!imported && semantic_value_id[pattern] == pattern_token) continue;
        if (!semantic_match_pattern_accepts_enum(pattern, tag, payload, hir_count))
        { recipe.valid = false; return recipe; }
        enum_pattern = true;
    }
    if (enum_pattern) recipe.address_load_count = depth - 1u;
    return recipe;
}

// Count owns referent validation. All later consumers reconstruct only the
// private row recipe that that dispatch published for this exact HIR owner.
// Rewalking arm identities per instruction would make large matches quadratic.
SemanticMatchRecipe semantic_match_retained_recipe_for_hir(uint node, uint hir_count)
{
    SemanticMatchRecipe recipe;
    recipe.address_load_count = 0u;
    recipe.arm_count = 0u;
    recipe.valid = node < hir_count;
    if (!recipe.valid) return recipe;
    HirPayload match_value = compact_hir_payload[node];
    recipe.arm_count = match_value.b < active_match_arm_count()
        ? min(match_value.c, active_match_arm_count() - match_value.b) : 0u;
    uint capture_rows = semantic_argument_value_layout[node].x != 0u ? 1u : 0u;
    uint stored_count = semantic_place_original_count[node];
    uint base_count = semantic_match_row_count(recipe);
    recipe.valid = stored_count >= capture_rows &&
        stored_count - capture_rows >= base_count &&
        stored_count - capture_rows - base_count <= 63u;
    if (recipe.valid)
        recipe.address_load_count = stored_count - capture_rows - base_count;
    return recipe;
}
