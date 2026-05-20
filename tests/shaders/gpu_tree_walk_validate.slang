import tree_walk;

static const uint TEST_COUNT = 16u;
static const uint INVALID = 0xffffffffu;
static const uint KIND_ROOT = 1u;
static const uint KIND_OWNER = 2u;

StructuredBuffer<uint> parent_in;
StructuredBuffer<uint> first_child_in;
StructuredBuffer<uint> next_sibling_in;
StructuredBuffer<uint> subtree_end_in;
StructuredBuffer<uint> kind;

RWStructuredBuffer<uint> owner_out;
RWStructuredBuffer<uint> ancestor_out;
RWStructuredBuffer<uint> keyed_ancestor_out;
RWStructuredBuffer<uint4> ancestor_edge_out;
RWStructuredBuffer<uint> has_owner_out;
RWStructuredBuffer<uint> has_owner_node_out;
RWStructuredBuffer<uint> has_strict_owner_node_out;
RWStructuredBuffer<uint> first_child_out;
RWStructuredBuffer<uint> next_sibling_out;
RWStructuredBuffer<uint> child_previous_out;
RWStructuredBuffer<uint> child_at_one_out;
RWStructuredBuffer<uint> owner_child_out;
RWStructuredBuffer<uint> subtree_end_out;
RWStructuredBuffer<uint> contains_root_out;
RWStructuredBuffer<uint> preorder_next_out;
RWStructuredBuffer<uint> preorder_first_owner_out;
RWStructuredBuffer<uint> preorder_descendant_owner_out;
RWStructuredBuffer<uint> preorder_owner_count_out;
RWStructuredBuffer<uint> preorder_second_owner_out;
RWStructuredBuffer<uint> preorder_owner_ordinal_before_out;
RWStructuredBuffer<uint> span_first_child_out;
RWStructuredBuffer<uint> span_next_sibling_out;
RWStructuredBuffer<uint> span_previous_sibling_out;
RWStructuredBuffer<uint> ancestor_before_root_out;
RWStructuredBuffer<uint> keyed_ancestor_before_root_out;
RWStructuredBuffer<uint> keyed_owner_child_out;
RWStructuredBuffer<uint4> ancestor_visit_out;

public struct TestGraph : ITreeWalkGraph
{
    public static bool valid(uint node)
    {
        return node != INVALID && node < TEST_COUNT;
    }

    public static uint parent(uint node)
    {
        return parent_in[node];
    }
}

public struct TestPreorderGraph : IPreorderTreeGraph
{
    public static bool valid(uint node)
    {
        return node != INVALID && node < TEST_COUNT;
    }

    public static uint parent(uint node)
    {
        return parent_in[node];
    }

    public static uint first_child(uint node)
    {
        return first_child_in[node];
    }

    public static uint next_sibling(uint node)
    {
        return next_sibling_in[node];
    }

    public static uint subtree_end(uint node)
    {
        return subtree_end_in[node];
    }
}

public struct TestChildGraph : ITreeChildGraph
{
    public static bool valid(uint node)
    {
        return node != INVALID && node < TEST_COUNT;
    }

    public static uint first_child(uint node)
    {
        return first_child_in[node];
    }

    public static uint next_sibling(uint node)
    {
        return next_sibling_in[node];
    }
}

public struct TestLinkedGraph : ITreeLinkedGraph
{
    public static bool valid(uint node)
    {
        return node != INVALID && node < TEST_COUNT;
    }

    public static uint parent(uint node)
    {
        return parent_in[node];
    }

    public static uint first_child(uint node)
    {
        return first_child_in[node];
    }

    public static uint next_sibling(uint node)
    {
        return next_sibling_in[node];
    }
}

public struct TestSpanGraph : IPreorderSpanGraph
{
    public static bool valid(uint node)
    {
        return node != INVALID && node < TEST_COUNT;
    }

    public static uint parent(uint node)
    {
        return parent_in[node];
    }

    public static uint subtree_end(uint node)
    {
        return subtree_end_in[node];
    }
}

public struct OwnerPredicate : ITreeWalkPredicate
{
    public static bool matches(uint node)
    {
        return kind[node] == KIND_OWNER;
    }
}

public struct RootPredicate : ITreeWalkPredicate
{
    public static bool matches(uint node)
    {
        return kind[node] == KIND_ROOT;
    }
}

public struct KindKeyPredicate : ITreeWalkKeyPredicate
{
    public static bool matches(uint node, uint key)
    {
        return kind[node] == key;
    }
}

public struct VisitUntilRootVisitor : ITreeWalkEdgeVisitor
{
    public static void visit(uint ancestor, uint child, uint4 payload)
    {
        uint source = payload.x;
        uint4 row = ancestor_visit_out[source];
        row.x += 1u;
        ancestor_visit_out[source] = row;
    }
}

uint pack_test_node(uint node)
{
    return node == INVALID ? 255u : node;
}

uint pack_three_test_nodes(uint a, uint b, uint c)
{
    return pack_test_node(a) |
           (pack_test_node(b) << 8u) |
           (pack_test_node(c) << 16u);
}

[shader("compute")]
[numthreads(16, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x;
    if (node >= TEST_COUNT)
        return;

    uint owner;
    bool found_owner = find_self_or_ancestor<TestGraph, OwnerPredicate>(
        node,
        8u,
        owner);
    owner_out[node] = found_owner ? owner : INVALID;
    has_owner_out[node] = has_self_or_ancestor<TestGraph, OwnerPredicate>(
        node,
        8u) ? 1u : 0u;
    has_owner_node_out[node] = has_self_or_ancestor_node<TestGraph>(
        node,
        2u,
        8u) ? 1u : 0u;
    has_strict_owner_node_out[node] = has_strict_ancestor_node<TestGraph>(
        node,
        2u,
        8u) ? 1u : 0u;

    uint root;
    bool found_root = find_ancestor<TestGraph, RootPredicate>(
        node,
        8u,
        root);
    ancestor_out[node] = found_root ? root : INVALID;

    uint keyed_root;
    bool found_keyed_root = find_ancestor_matching_key<TestGraph, KindKeyPredicate>(
        node,
        KIND_ROOT,
        8u,
        keyed_root);
    keyed_ancestor_out[node] = found_keyed_root ? keyed_root : INVALID;

    uint edge_ancestor;
    uint edge_child;
    bool found_edge = find_ancestor_edge<TestGraph, OwnerPredicate>(
        node,
        8u,
        edge_ancestor,
        edge_child);

    uint keyed_edge_ancestor;
    uint keyed_edge_child;
    bool found_keyed_edge =
        find_ancestor_edge_matching_key<TestGraph, KindKeyPredicate>(
            node,
            KIND_OWNER,
            8u,
            keyed_edge_ancestor,
            keyed_edge_child);
    ancestor_edge_out[node] = uint4(
        found_edge ? edge_ancestor : INVALID,
        found_edge ? edge_child : INVALID,
        found_keyed_edge ? keyed_edge_ancestor : INVALID,
        found_keyed_edge ? keyed_edge_child : INVALID);

    uint owner_before_root;
    ancestor_before_root_out[node] = find_ancestor_before<TestGraph, OwnerPredicate>(
        node,
        0u,
        8u,
        owner_before_root) ? owner_before_root : INVALID;
    uint keyed_owner_before_root;
    keyed_ancestor_before_root_out[node] =
        find_ancestor_matching_key_before<TestGraph, KindKeyPredicate>(
            node,
            0u,
            KIND_OWNER,
            8u,
            keyed_owner_before_root) ? keyed_owner_before_root : INVALID;

    ancestor_visit_out[node] = uint4(0u, INVALID, INVALID, INVALID);
    uint visit_stop_ancestor;
    uint visit_stop_child;
    bool visited_until_root = visit_ancestors_until<
        TestGraph,
        RootPredicate,
        VisitUntilRootVisitor>(
        node,
        8u,
        uint4(node, 0u, 0u, 0u),
        visit_stop_ancestor,
        visit_stop_child);

    uint keyed_owner_before_or_until_root;
    bool found_owner_before_or_until_root =
        find_ancestor_matching_key_before_or_until<
            TestGraph,
            KindKeyPredicate,
            RootPredicate>(
            node,
            INVALID,
            KIND_OWNER,
            8u,
            keyed_owner_before_or_until_root);
    uint span_first_owner;
    bool found_span_first_owner = tree_span_first_matching_key<
        TestSpanGraph,
        KindKeyPredicate>(
        node,
        KIND_OWNER,
        8u,
        span_first_owner);
    uint span_descendant_owner;
    bool found_span_descendant_owner = tree_span_first_descendant_matching<
        TestSpanGraph,
        OwnerPredicate>(
        node,
        8u,
        span_descendant_owner);
    uint4 visit_result = ancestor_visit_out[node];
    visit_result.y = visited_until_root ? visit_stop_ancestor : INVALID;
    visit_result.z = pack_three_test_nodes(
        visited_until_root ? visit_stop_child : INVALID,
        found_owner_before_or_until_root ? keyed_owner_before_or_until_root : INVALID,
        found_span_first_owner ? span_first_owner : INVALID);
    visit_result.w = found_span_descendant_owner ? span_descendant_owner : INVALID;
    ancestor_visit_out[node] = visit_result;

    uint first_child;
    first_child_out[node] = tree_first_child<TestPreorderGraph>(
        node,
        first_child) ? first_child : INVALID;

    uint next_sibling;
    next_sibling_out[node] = tree_next_sibling<TestPreorderGraph>(
        node,
        next_sibling) ? next_sibling : INVALID;

    uint previous_child;
    uint parent = parent_in[node];
    child_previous_out[node] = tree_child_previous<TestChildGraph>(
        parent,
        node,
        8u,
        previous_child) ? previous_child : INVALID;

    uint child_at_one;
    child_at_one_out[node] = tree_child_at<TestPreorderGraph>(
        node,
        1u,
        8u,
        child_at_one) ? child_at_one : INVALID;

    uint owner_child;
    owner_child_out[node] = tree_first_child_matching<
        TestPreorderGraph,
        OwnerPredicate>(
        node,
        8u,
        owner_child) ? owner_child : INVALID;

    uint child_graph_child;
    bool child_graph_ok = tree_child_first_matching<
        TestChildGraph,
        OwnerPredicate>(
        node,
        8u,
        child_graph_child);
    if (child_graph_ok && owner_child_out[node] != child_graph_child)
        owner_child_out[node] = INVALID;

    uint keyed_owner_child;
    keyed_owner_child_out[node] = tree_child_first_matching_key<
        TestChildGraph,
        KindKeyPredicate>(
        node,
        KIND_OWNER,
        8u,
        keyed_owner_child) ? keyed_owner_child : INVALID;

    uint end;
    subtree_end_out[node] = tree_subtree_end<TestPreorderGraph>(
        node,
        TEST_COUNT,
        end) ? end : INVALID;
    contains_root_out[node] = tree_contains<TestPreorderGraph>(
        0u,
        node,
        TEST_COUNT) ? 1u : 0u;

    uint preorder_root = node < 12u ? 0u : (node < 15u ? 12u : 15u);
    uint preorder_next;
    preorder_next_out[node] = tree_next_preorder_within<TestLinkedGraph>(
        preorder_root,
        node,
        8u,
        preorder_next) ? preorder_next : INVALID;
    uint preorder_owner;
    preorder_first_owner_out[node] =
        tree_first_preorder_matching_key<TestLinkedGraph, KindKeyPredicate>(
            preorder_root,
            KIND_OWNER,
            8u,
            preorder_owner) ? preorder_owner : INVALID;
    uint preorder_descendant_owner;
    preorder_descendant_owner_out[node] =
        tree_first_descendant_matching_key<TestLinkedGraph, KindKeyPredicate>(
            preorder_root,
            KIND_OWNER,
            8u,
            preorder_descendant_owner) ? preorder_descendant_owner : INVALID;
    preorder_owner_count_out[node] =
        tree_count_preorder_matching_key<TestLinkedGraph, KindKeyPredicate>(
            preorder_root,
            KIND_OWNER,
            8u);
    uint preorder_second_owner;
    preorder_second_owner_out[node] =
        tree_nth_preorder_matching_key<TestLinkedGraph, KindKeyPredicate>(
            preorder_root,
            KIND_OWNER,
            1u,
            8u,
            preorder_second_owner) ? preorder_second_owner : INVALID;
    uint owner_ordinal_before;
    preorder_owner_ordinal_before_out[node] =
        tree_matching_key_ordinal_before<TestLinkedGraph, KindKeyPredicate>(
            preorder_root,
            KIND_OWNER,
            node,
            8u,
            owner_ordinal_before) ? owner_ordinal_before : INVALID;

    uint span_first_child;
    span_first_child_out[node] = tree_span_first_child<TestSpanGraph>(
        node,
        span_first_child) ? span_first_child : INVALID;

    uint span_next_sibling;
    span_next_sibling_out[node] = tree_span_next_sibling<TestSpanGraph>(
        node,
        span_next_sibling) ? span_next_sibling : INVALID;

    uint span_previous_sibling;
    span_previous_sibling_out[node] = tree_span_previous_sibling<TestSpanGraph>(
        node,
        8u,
        span_previous_sibling) ? span_previous_sibling : INVALID;
}
