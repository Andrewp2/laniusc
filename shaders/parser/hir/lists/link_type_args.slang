// Seed generic type-argument links from grammar tree records.
//
// Type argument lists are right-recursive. First arguments seed the owning type
// expression and path segment, and later arguments point at their previous
// argument. Pointer jumping preserves the list identity and computes ordinals.
//
// Only argument value rows are written: types, literals, unary expressions,
// constant argument roots and positive magnitudes. The argument arrays are
// undefined on every other row, and readers test the row's kind first. The
// walk records go to both ping-pong buffers. An argument links only to another
// argument. The pass also marks the arguments
// with an owner or a link and counts them per block, in the layout of
// parser/hir/lists/mark_list_rows.slang, so the list compaction that
// follows lists them for the walk. One workgroup covers one block of 256 rows;
// the dispatch covers every block of the tree.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
    uint retain_debug_rows;
};

ConstantBuffer<Params> gHirType;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> prev_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_node_dense_id;
StructuredBuffer<uint> hir_semantic_parent;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<uint> hir_type_path_owner_by_leaf;
StructuredBuffer<uint> hir_bound_path_owner_by_leaf;

RWStructuredBuffer<uint> hir_type_arg_owner_a;
RWStructuredBuffer<uint> hir_type_arg_application_owner;
RWStructuredBuffer<uint> hir_type_arg_application_token;
RWStructuredBuffer<uint> hir_type_arg_link_a;
RWStructuredBuffer<uint> hir_type_arg_rank_a;
RWStructuredBuffer<uint> hir_type_arg_previous;
RWStructuredBuffer<uint> hir_type_arg_owner_b;
RWStructuredBuffer<uint> hir_type_arg_link_b;
RWStructuredBuffer<uint> hir_type_arg_rank_b;
RWStructuredBuffer<uint> hir_list_rank_flag;
RWStructuredBuffer<uint> hir_list_rank_block_sum;

static const uint FLAG_WORDS_PER_BLOCK = 8u;
groupshared uint g_flag_words[FLAG_WORDS_PER_BLOCK];
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_LITERAL_EXPR = 23u;

static const uint INVALID = 0xffffffffu;
static const uint OWNER_NODE_MASK = 0x7fffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_TYPE_FORM_PATH = 1u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_node_count()
{
    return gHirType.uses_status_count != 0u ? min(gHirType.n, tree_count_status[5u]) : gHirType.n;
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

uint next_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint sibling = next_sibling[node];
    return valid_node(sibling) && parent[sibling] == parent[node] ? sibling : INVALID;
}

uint previous_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint previous = prev_sibling[node];
    return valid_node(previous) && parent[previous] == parent[node] ? previous : INVALID;
}

bool is_type_arg_container(uint prod)
{
    return prod == PROD_TYPE_ARGS_SOME ||
           prod == PROD_TYPE_ARGS_AFTER_COMMA_MORE ||
           prod == PROD_BOUND_TYPE_ARGS_SOME ||
           prod == PROD_BOUND_TYPE_ARGS_AFTER_COMMA_MORE ||
           prod == PROD_PATH_IDENT_ARGS ||
           prod == PROD_MEMBER_TYPE_ARGS_SOME ||
           prod == PROD_PATH_TYPE_ARGS_AFTER_COMMA_MORE;
}

bool is_type_path_container(uint prod)
{
    return prod == PROD_TYPE_PATH || prod == PROD_TYPE_PATH_MORE ||
           prod == PROD_PATH_MORE;
}

bool is_type_path_segment(uint prod)
{
    return prod == PROD_TYPE_PATH_IDENT ||
           prod == PROD_PATH_IDENT ||
           prod == PROD_PATH_IDENT_ARGS ||
           prod == PROD_BOUND_TYPE_PATH_IDENT;
}

bool is_constant_operand_root(uint prod)
{
    return prod == PROD_GENERIC_ARGUMENT_INTEGER || prod == PROD_GENERIC_ARGUMENT_NEGATIVE ||
        prod == PROD_GENERIC_ARGUMENT_POSITIVE || prod == PROD_GENERIC_ARGUMENT_TRUE ||
        prod == PROD_GENERIC_ARGUMENT_FALSE || prod == PROD_GENERIC_ARGUMENT_CHAR ||
        prod == PROD_GENERIC_ARGUMENT_FLOAT;
}

// `+N` forwards to its magnitude and keeps no canonical row of its own, so
// the magnitude literal is that argument's row. `-N` keeps its unary row.
uint argument_row(uint root)
{
    return valid_node(root) && node_kind[root] == PROD_GENERIC_ARGUMENT_POSITIVE
        ? first_child_node(root) : root;
}

bool is_positive_magnitude(uint node)
{
    uint root = parent_node(node);
    return valid_node(root) && node_kind[root] == PROD_GENERIC_ARGUMENT_POSITIVE &&
        first_child_node(root) == node;
}

uint arg_from_container(uint container)
{
    if (!valid_node(container) || !is_type_arg_container(node_kind[container]))
        return INVALID;
    uint arg = first_child_node(container);
    if (valid_node(arg) && (node_kind[arg] == PROD_GENERIC_ARGUMENT_TYPE ||
        node_kind[arg] == PROD_GENERIC_ARGUMENT_CONSTANT))
        arg = first_child_node(arg);
    return valid_node(arg) && (hir_kind[arg] == HIR_TYPE ||
        is_constant_operand_root(node_kind[arg])) ? argument_row(arg) : INVALID;
}

uint previous_arg_for_after_comma(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_TYPE_ARGS_AFTER_COMMA_MORE &&
        node_kind[container] != PROD_BOUND_TYPE_ARGS_AFTER_COMMA_MORE &&
        node_kind[container] != PROD_PATH_TYPE_ARGS_AFTER_COMMA_MORE)
        return INVALID;
    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    uint previous = arg_from_container(previous_container);
    if (valid_node(previous))
        return previous;
    return valid_node(previous_container) && hir_kind[previous_container] == HIR_TYPE
        ? first_arg_for_type_owner(previous_container)
        : INVALID;
}

uint owner_seed_for_arg_container(uint container)
{
    if (!valid_node(container) ||
        (node_kind[container] != PROD_TYPE_ARGS_SOME &&
         node_kind[container] != PROD_BOUND_TYPE_ARGS_SOME))
        return INVALID;
    uint owner = parent_node(container);
    return valid_node(owner) && hir_kind[owner] == HIR_TYPE ? owner : INVALID;
}

bool valid_path_type_owner(uint owner, uint leaf)
{
    return valid_node(owner) &&
           hir_kind[owner] == HIR_TYPE &&
           hir_type_form[owner] == HIR_TYPE_FORM_PATH &&
           hir_type_path_leaf_node[owner] == leaf;
}

uint owner_seed_for_path_arg(uint node, uint container)
{
    if (!valid_node(container) ||
        (node_kind[container] != PROD_TYPE_ARGS_SOME &&
         node_kind[container] != PROD_BOUND_TYPE_ARGS_SOME &&
         node_kind[container] != PROD_PATH_IDENT_ARGS &&
         node_kind[container] != PROD_MEMBER_TYPE_ARGS_SOME))
        return INVALID;
    uint leaf = previous_sibling_node(node);
    uint owner = INVALID;
    if (valid_node(leaf) && is_type_path_segment(node_kind[leaf]))
    {
        uint encoded_owner = hir_type_path_owner_by_leaf[leaf];
        if (encoded_owner != 0u && encoded_owner <= OWNER_NODE_MASK)
            owner = OWNER_NODE_MASK - encoded_owner;
        else
        {
            uint bound_row = gHirType.retain_debug_rows != 0u
                ? leaf
                : hir_token_pos[leaf];
            uint bound_owner = hir_bound_path_owner_by_leaf[bound_row];
            owner = gHirType.retain_debug_rows != 0u
                ? bound_owner
                : (bound_owner != 0u && bound_owner <= OWNER_NODE_MASK
                    ? OWNER_NODE_MASK - bound_owner
                    : INVALID);
        }
        if (valid_path_type_owner(owner, leaf))
            return owner;
    }

    // Generic arguments in value paths, such as `Vec<T>::new`, have no
    // enclosing HIR_TYPE row. Their nearest semantic owner is the compact
    // HIR_PATH_EXPR that represents the whole callee path, or the member
    // expression for a receiver call. The applying segment owns the list.
    uint row = hir_node_dense_id[node];
    uint owner_row = row < active_node_count() ? hir_semantic_parent[row] : INVALID;
    owner = owner_row < active_node_count() ? hir_semantic_dense_node[owner_row] : INVALID;
    return valid_node(owner) &&
        (hir_kind[owner] == HIR_PATH_EXPR || hir_kind[owner] == HIR_MEMBER_EXPR)
        ? owner : INVALID;
}

uint first_arg_for_type_owner(uint owner)
{
    if (!valid_node(owner) || hir_type_form[owner] != HIR_TYPE_FORM_PATH)
        return INVALID;

    uint leaf = hir_type_path_leaf_node[owner];
    uint first = next_sibling_node(leaf);
    if (valid_node(first) && (node_kind[first] == PROD_GENERIC_ARGUMENT_TYPE ||
        node_kind[first] == PROD_GENERIC_ARGUMENT_CONSTANT))
        first = first_child_node(first);
    return valid_node(first) && (hir_kind[first] == HIR_TYPE ||
        is_constant_operand_root(node_kind[first])) ? argument_row(first) : INVALID;
}

// Whether the row holds a type argument's value, or a constant argument's root:
// the rows whose argument arrays are defined.
bool argument_value_row(uint node)
{
    uint kind = hir_kind[node];
    return kind == HIR_TYPE || kind == HIR_LITERAL_EXPR || kind == HIR_UNARY_EXPR ||
        is_constant_operand_root(node_kind[node]) || is_positive_magnitude(node);
}

void seed_argument(uint node)
{
    hir_type_arg_owner_a[node] = INVALID;
    hir_type_arg_application_owner[node] = INVALID;
    hir_type_arg_application_token[node] = INVALID;
    hir_type_arg_link_a[node] = INVALID;
    hir_type_arg_rank_a[node] = 0u;
    hir_type_arg_previous[node] = INVALID;

    if (argument_row(node) != node)
        return;
    // A positive magnitude takes its wrapper's place in the argument list.
    bool positive = is_positive_magnitude(node);
    if (hir_kind[node] != HIR_TYPE && !is_constant_operand_root(node_kind[node]) && !positive)
        return;
    uint root = positive ? parent_node(node) : node;

    uint container = parent_node(root);
    if (valid_node(container) && (node_kind[container] == PROD_GENERIC_ARGUMENT_TYPE ||
        node_kind[container] == PROD_GENERIC_ARGUMENT_CONSTANT))
        container = parent_node(container);
    uint prod = valid_node(container) ? node_kind[container] : INVALID;
    uint path_owner = owner_seed_for_path_arg(root, container);
    uint owner = valid_node(path_owner) ? path_owner
        : owner_seed_for_arg_container(container);
    if (valid_node(owner))
    {
        uint leaf = hir_kind[owner] == HIR_TYPE ? hir_type_path_leaf_node[owner] : INVALID;
        uint token = prod == PROD_PATH_IDENT_ARGS ? hir_token_pos[container]
            : (prod == PROD_MEMBER_TYPE_ARGS_SOME ? hir_token_pos[container] - 1u
                : (valid_node(leaf) ? hir_token_pos[leaf] : INVALID));
        if (token == INVALID) return;
        // A path may have multiple applications. The first argument is the
        // list identity; its owner/token facts survive pointer-jump ranking.
        hir_type_arg_owner_a[node] = node;
        hir_type_arg_application_owner[node] = owner;
        hir_type_arg_application_token[node] = token;
        return;
    }

    if (prod == PROD_TYPE_ARGS_AFTER_COMMA_MORE ||
        prod == PROD_BOUND_TYPE_ARGS_AFTER_COMMA_MORE ||
        prod == PROD_PATH_TYPE_ARGS_AFTER_COMMA_MORE)
    {
        uint previous = previous_arg_for_after_comma(container);
        if (valid_node(previous))
        {
            hir_type_arg_link_a[node] = previous;
            hir_type_arg_rank_a[node] = 1u;
            hir_type_arg_previous[node] = previous;
        }
    }
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

    if (valid_node(node) && argument_value_row(node))
    {
        seed_argument(node);
        // Both ping-pong buffers: the walk reads a link's target from either.
        uint owner = hir_type_arg_owner_a[node];
        uint link = hir_type_arg_link_a[node];
        hir_type_arg_owner_b[node] = owner;
        hir_type_arg_link_b[node] = link;
        hir_type_arg_rank_b[node] = hir_type_arg_rank_a[node];
        if (owner != INVALID || link != INVALID)
            InterlockedOr(g_flag_words[lane >> 5u], 1u << (lane & 31u));
    }
    GroupMemoryBarrierWithGroupSync();

    uint word_i = block_i * FLAG_WORDS_PER_BLOCK + lane;
    if (lane < FLAG_WORDS_PER_BLOCK && word_i < (gHirType.n + 31u) / 32u)
        hir_list_rank_flag[word_i] = g_flag_words[lane];
    if (lane == 0u)
    {
        uint total = 0u;
        for (uint w = 0u; w < FLAG_WORDS_PER_BLOCK; ++w)
            total += countbits(g_flag_words[w]);
        hir_list_rank_block_sum[block_i] = total;
    }
}
