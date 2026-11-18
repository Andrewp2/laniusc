// Seed struct declaration/literal field links from grammar tree records, and
// list the fields.
//
// Struct field lists have the same right-recursive shape as call arguments:
// first fields seed the owning struct/literal, and later fields point at their
// previous field. A separate pointer-jump pass computes ordinals and owners.
//
// Only the family's rows are written: struct declaration fields, struct
// literal fields, and the literal's head on struct literal rows. The field
// arrays are undefined on every other row, and readers test the row's
// production first. A field links only to another field. When debug rows are
// retained, every row's defaults are written, since debug readbacks read every
// row. The pass also marks the fields and counts them per block, in the layout
// of parser/hir/list/rank/prefix_00_local.slang, so the list compaction that
// follows lists them for the walk and the scatter. One workgroup covers one
// block of 256 rows; the dispatch covers every block of the tree.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
    uint retain_debug_rows;
};

ConstantBuffer<Params> gHirStruct;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> prev_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;

RWStructuredBuffer<uint> hir_struct_field_parent_struct;
RWStructuredBuffer<uint> hir_struct_field_ordinal;
RWStructuredBuffer<uint> hir_struct_field_type_node;
RWStructuredBuffer<uint> hir_struct_decl_field_start;
RWStructuredBuffer<uint> hir_struct_decl_field_count;
RWStructuredBuffer<uint> hir_struct_lit_head_node;
RWStructuredBuffer<uint> hir_struct_lit_field_start;
RWStructuredBuffer<uint> hir_struct_lit_field_count;
RWStructuredBuffer<uint> hir_struct_lit_field_parent_lit;
RWStructuredBuffer<uint> hir_struct_lit_field_value_node;
RWStructuredBuffer<uint> hir_struct_field_owner_a;
RWStructuredBuffer<uint> hir_struct_field_link_a;
RWStructuredBuffer<uint> hir_struct_field_rank_a;
RWStructuredBuffer<uint> hir_struct_lit_field_owner_a;
RWStructuredBuffer<uint> hir_struct_lit_field_link_a;
RWStructuredBuffer<uint> hir_struct_lit_field_rank_a;
RWStructuredBuffer<uint> hir_struct_lit_field_previous;
RWStructuredBuffer<uint> hir_struct_rank_flag;
RWStructuredBuffer<uint> hir_struct_rank_block_sum;

static const uint FLAG_WORDS_PER_BLOCK = 8u;
groupshared uint g_flag_words[FLAG_WORDS_PER_BLOCK];

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;
static const uint HIR_EXPR = 14u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_node_count()
{
    return gHirStruct.uses_status_count != 0u ? min(gHirStruct.n, tree_count_status[5u])
                                     : gHirStruct.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint parent_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint p = parent[node];
    return valid_node(p) ? p : INVALID;
}

uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = first_child[node];
    return valid_node(child) ? child : INVALID;
}

uint previous_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint previous = prev_sibling[node];
    return valid_node(previous) && parent[previous] == parent[node] ?
        previous :
        INVALID;
}

uint first_child_with_hir_kind(uint node, uint kind)
{
    uint child = first_child_node(node);
    return valid_node(child) && parent[child] == node && hir_kind[child] == kind
        ? child
        : INVALID;
}

uint field_from_struct_container(uint container)
{
    if (!valid_node(container))
        return INVALID;
    uint prod = node_kind[container];
    if (prod != PROD_STRUCT_FIELDS_SOME &&
        prod != PROD_STRUCT_FIELDS_AFTER_COMMA_MORE)
        return INVALID;
    uint field = first_child_node(container);
    return valid_node(field) && node_kind[field] == PROD_STRUCT_FIELD
        ? field
        : INVALID;
}

uint literal_field_from_container(uint container)
{
    if (!valid_node(container))
        return INVALID;
    uint prod = node_kind[container];
    if (prod != PROD_STRUCT_LIT_FIELDS_SOME &&
        prod != PROD_STRUCT_LIT_FIELDS_AFTER_COMMA_MORE)
        return INVALID;
    uint field = first_child_node(container);
    return valid_node(field) && node_kind[field] == PROD_STRUCT_LIT_FIELD
        ? field
        : INVALID;
}

uint previous_struct_field_for_after_comma(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_STRUCT_FIELDS_AFTER_COMMA_MORE)
        return INVALID;
    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    return field_from_struct_container(previous_container);
}

uint previous_literal_field_for_after_comma(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_STRUCT_LIT_FIELDS_AFTER_COMMA_MORE)
        return INVALID;
    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    return literal_field_from_container(previous_container);
}

uint owner_seed_for_struct_field_container(uint container)
{
    if (!valid_node(container) || node_kind[container] != PROD_STRUCT_FIELDS_SOME)
        return INVALID;
    uint owner = parent_node(container);
    return valid_node(owner) && node_kind[owner] == PROD_STRUCT ? owner : INVALID;
}

uint owner_seed_for_literal_field_container(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_STRUCT_LIT_FIELDS_SOME)
        return INVALID;
    uint owner = parent_node(container);
    return valid_node(owner) && node_kind[owner] == PROD_STRUCT_LIT ? owner : INVALID;
}

void seed_struct_field(uint node)
{
    uint container = parent_node(node);
    uint prod = valid_node(container) ? node_kind[container] : INVALID;

    if (prod == PROD_STRUCT_FIELDS_SOME)
    {
        hir_struct_field_owner_a[node] =
            owner_seed_for_struct_field_container(container);
        return;
    }

    if (prod == PROD_STRUCT_FIELDS_AFTER_COMMA_MORE)
    {
        uint previous = previous_struct_field_for_after_comma(container);
        if (valid_node(previous))
        {
            hir_struct_field_link_a[node] = previous;
            hir_struct_field_rank_a[node] = 1u;
        }
    }
}

void seed_literal_field(uint node)
{
    uint container = parent_node(node);
    uint prod = valid_node(container) ? node_kind[container] : INVALID;

    if (prod == PROD_STRUCT_LIT_FIELDS_SOME)
    {
        hir_struct_lit_field_owner_a[node] =
            owner_seed_for_literal_field_container(container);
        return;
    }

    if (prod == PROD_STRUCT_LIT_FIELDS_AFTER_COMMA_MORE)
    {
        uint previous = previous_literal_field_for_after_comma(container);
        if (valid_node(previous))
        {
            hir_struct_lit_field_link_a[node] = previous;
            hir_struct_lit_field_rank_a[node] = 1u;
            hir_struct_lit_field_previous[node] = previous;
        }
    }
}

void clear_field_links(uint node)
{
    hir_struct_field_owner_a[node] = INVALID;
    hir_struct_field_link_a[node] = INVALID;
    hir_struct_field_rank_a[node] = 0u;
    hir_struct_lit_field_owner_a[node] = INVALID;
    hir_struct_lit_field_link_a[node] = INVALID;
    hir_struct_lit_field_rank_a[node] = 0u;
    hir_struct_lit_field_previous[node] = INVALID;
}

// Every row's defaults, for debug readbacks.
void clear_debug_row(uint node)
{
    clear_field_links(node);
    hir_struct_field_parent_struct[node] = INVALID;
    hir_struct_field_ordinal[node] = INVALID;
    hir_struct_field_type_node[node] = INVALID;
    hir_struct_decl_field_start[node] = INVALID;
    hir_struct_decl_field_count[node] = 0u;
    hir_struct_lit_head_node[node] = INVALID;
    hir_struct_lit_field_start[node] = INVALID;
    hir_struct_lit_field_count[node] = 0u;
    hir_struct_lit_field_parent_lit[node] = INVALID;
    hir_struct_lit_field_value_node[node] = INVALID;
}

// Writes a family row; returns whether the row is a field.
bool seed_row(uint node)
{
    uint prod = node_kind[node];
    if (prod == PROD_STRUCT_FIELD)
    {
        clear_field_links(node);
        hir_struct_field_parent_struct[node] = INVALID;
        hir_struct_field_ordinal[node] = INVALID;
        hir_struct_field_type_node[node] =
            first_child_with_hir_kind(node, HIR_TYPE);
        seed_struct_field(node);
        return true;
    }

    if (prod == PROD_STRUCT_LIT)
    {
        uint previous = previous_sibling_node(node);
        hir_struct_lit_head_node[node] =
            valid_node(previous) && node_kind[previous] == PROD_PATH
            ? previous
            : INVALID;
        return false;
    }

    if (prod == PROD_STRUCT_LIT_FIELD)
    {
        clear_field_links(node);
        uint output_row = gHirStruct.retain_debug_rows != 0u
            ? node
            : hir_token_pos[node];
        if (output_row != INVALID)
            hir_struct_lit_field_value_node[output_row] =
                first_child_with_hir_kind(node, HIR_EXPR);
        seed_literal_field(node);
        return true;
    }
    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_i = linear_group_id(gid);
    uint lane = ltid.x;
    uint node = block_i * WG_SIZE + lane;

    if (lane < FLAG_WORDS_PER_BLOCK)
        g_flag_words[lane] = 0u;
    GroupMemoryBarrierWithGroupSync();

    if (node < gHirStruct.n && gHirStruct.retain_debug_rows != 0u)
        clear_debug_row(node);
    if (valid_node(node) && seed_row(node))
        InterlockedOr(g_flag_words[lane >> 5u], 1u << (lane & 31u));
    GroupMemoryBarrierWithGroupSync();

    uint word_i = block_i * FLAG_WORDS_PER_BLOCK + lane;
    if (lane < FLAG_WORDS_PER_BLOCK && word_i < (gHirStruct.n + 31u) / 32u)
        hir_struct_rank_flag[word_i] = g_flag_words[lane];
    if (lane == 0u)
    {
        uint total = 0u;
        for (uint w = 0u; w < FLAG_WORDS_PER_BLOCK; ++w)
            total += countbits(g_flag_words[w]);
        hir_struct_rank_block_sum[block_i] = total;
    }
}
