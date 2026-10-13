// Shared structural evidence for type arguments in a value path. Including
// passes supply raw delimiter search relations and read-only token views.
// Raw angles include comparison/shift operators. A candidate pair must stay
// inside the same statement and structural containers before its tail can
// establish a value-path application.
// Search the three existing delimiter hierarchies together. A block can
// contain an owning-container exit when any one of its minima crosses the
// corresponding depth. This needs one traversal and no new relation.
public struct ValuePathDelimiterTree : IRangeSearchTree<int3>
{
    public static uint n_blocks() { return AngleDepthTree.n_blocks(); }
    public static uint leaf_base() { return AngleDepthTree.leaf_base(); }
    public static int3 leaf_value(uint block) {
        return int3(ParenDepthTree.leaf_value(block), BracketDepthTree.leaf_value(block), BraceDepthTree.leaf_value(block));
    }
    public static int3 tree_value(uint node) {
        return int3(ParenDepthTree.tree_value(node), BracketDepthTree.tree_value(node), BraceDepthTree.tree_value(node));
    }
}
public struct ValuePathDelimiterRows : IRangeSearchRows<int3>
{
    public static uint item_count() { return AngleDepthRows.item_count(); }
    public static uint block_size() { return WG_SIZE; }
    public static int3 row_value(uint row) {
        return int3(paren_match_depth[row], bracket_match_depth[row], brace_match_depth[row]);
    }
}
public struct ValuePathContainerExit : IRangeSearchPredicate<int3, int3>
{
    public static bool aggregate_may_match(int3 value, int3 depth) { return any(value <= depth); }
    public static bool leaf_matches(int3 value, int3 depth) { return any(value <= depth); }
}

bool value_path_arguments_share_container(uint open_i, uint close_i)
{
    if (statement_context_kind[open_i] != statement_context_kind[close_i]) return false;
    int paren = block_prefix_paren[open_i / WG_SIZE] + depth_paren_inblock[open_i];
    int bracket = block_prefix_bracket[open_i / WG_SIZE] + depth_bracket_inblock[open_i];
    int brace = block_prefix_brace[open_i / WG_SIZE] + depth_brace_inblock[open_i];
    if (paren != block_prefix_paren[close_i / WG_SIZE] + depth_paren_inblock[close_i] ||
        bracket != block_prefix_bracket[close_i / WG_SIZE] + depth_bracket_inblock[close_i] ||
        brace != block_prefix_brace[close_i / WG_SIZE] + depth_brace_inblock[close_i]) return false;
    // Equal depths alone would accept separate sibling groups. The first
    // closing boundary of each owning container must follow the angle pair.
    uint boundary;
    if (range_search_tree_first_index_at_or_after<int3, int3,
        ValuePathDelimiterTree, ValuePathDelimiterRows, ValuePathContainerExit>(
            open_i + 1u, int3(paren, bracket, brace) - 1, boundary) &&
        boundary < close_i) return false;
    return true;
}

bool value_path_type_arguments_have_tail(uint open_i, uint count)
{
    if (open_i == 0u || open_i >= count || token_words[open_i].kind != TK_LT ||
        token_words[open_i - 1u].kind != TK_IDENT) return false;
    int depth = angle_match_depth[open_i];
    uint close_i;
    if (depth == 2147483647 ||
        !range_search_tree_first_index_at_or_after<int, int,
            AngleDepthTree, AngleDepthRows, DepthAtMost>(open_i + 1u, depth, close_i) ||
        close_i >= count || angle_match_depth[close_i] != depth) return false;
    uint close = token_words[close_i].kind;
    if (close != TK_GT && close != 44u) return false;
    uint next_i = close_i + 1u;
    if (next_i >= count) return false;
    uint next = token_words[next_i].kind;
    bool tail = next == TK_LPAREN ||
        (next == TK_COLON && next_i + 1u < count && token_words[next_i + 1u].kind == TK_COLON) ||
        (next == TK_LBRACE && brace_semantic_kind[next_i] == TK_STRUCT_LIT_LBRACE);
    return tail && value_path_arguments_share_container(open_i, close_i);
}
