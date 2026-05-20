public interface ITreeWalkGraph
{
    static bool valid(uint node);
    static uint parent(uint node);
}

public interface ITreeWalkPredicate
{
    static bool matches(uint node);
}

public interface ITreeWalkKeyPredicate
{
    static bool matches(uint node, uint key);
}

public interface ITreeWalkEdgeVisitor
{
    static void visit(uint ancestor, uint child, uint4 payload);
}

public interface ITreeChildGraph
{
    static bool valid(uint node);
    static uint first_child(uint node);
    static uint next_sibling(uint node);
}

public interface ITreeLinkedGraph
{
    static bool valid(uint node);
    static uint parent(uint node);
    static uint first_child(uint node);
    static uint next_sibling(uint node);
}

public interface IPreorderSpanGraph
{
    static bool valid(uint node);
    static uint parent(uint node);
    static uint subtree_end(uint node);
}

public interface IPreorderTreeGraph
{
    static bool valid(uint node);
    static uint parent(uint node);
    static uint first_child(uint node);
    static uint next_sibling(uint node);
    static uint subtree_end(uint node);
}

public bool find_self_or_ancestor<
    TGraph: ITreeWalkGraph,
    TPredicate: ITreeWalkPredicate>(
    uint node,
    uint max_steps,
    out uint found)
{
    found = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;

    uint cur = node;
    [loop]
    for (uint step = 0u; step < max_steps; step += 1u)
    {
        if (TPredicate.matches(cur))
        {
            found = cur;
            return true;
        }

        uint parent = TGraph.parent(cur);
        if (!TGraph.valid(parent) || parent == cur)
            return false;
        cur = parent;
    }
    return false;
}

public bool find_self_or_ancestor_matching_key<
    TGraph: ITreeWalkGraph,
    TPredicate: ITreeWalkKeyPredicate>(
    uint node,
    uint key,
    uint max_steps,
    out uint found)
{
    found = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;

    uint cur = node;
    [loop]
    for (uint step = 0u; step < max_steps; step += 1u)
    {
        if (TPredicate.matches(cur, key))
        {
            found = cur;
            return true;
        }

        uint parent = TGraph.parent(cur);
        if (!TGraph.valid(parent) || parent == cur)
            return false;
        cur = parent;
    }
    return false;
}

public bool find_ancestor_matching_key<
    TGraph: ITreeWalkGraph,
    TPredicate: ITreeWalkKeyPredicate>(
    uint node,
    uint key,
    uint max_steps,
    out uint found)
{
    found = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;
    uint parent = TGraph.parent(node);
    if (!TGraph.valid(parent) || parent == node)
        return false;
    return find_self_or_ancestor_matching_key<TGraph, TPredicate>(
        parent,
        key,
        max_steps,
        found);
}

public bool find_ancestor_edge<
    TGraph: ITreeWalkGraph,
    TPredicate: ITreeWalkPredicate>(
    uint node,
    uint max_steps,
    out uint ancestor,
    out uint child)
{
    ancestor = 0xffffffffu;
    child = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;

    uint cur = node;
    [loop]
    for (uint step = 0u; step < max_steps; step += 1u)
    {
        uint parent = TGraph.parent(cur);
        if (!TGraph.valid(parent) || parent == cur)
            return false;
        if (TPredicate.matches(parent))
        {
            ancestor = parent;
            child = cur;
            return true;
        }
        cur = parent;
    }
    return false;
}

public bool find_ancestor_edge_matching_key<
    TGraph: ITreeWalkGraph,
    TPredicate: ITreeWalkKeyPredicate>(
    uint node,
    uint key,
    uint max_steps,
    out uint ancestor,
    out uint child)
{
    ancestor = 0xffffffffu;
    child = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;

    uint cur = node;
    [loop]
    for (uint step = 0u; step < max_steps; step += 1u)
    {
        uint parent = TGraph.parent(cur);
        if (!TGraph.valid(parent) || parent == cur)
            return false;
        if (TPredicate.matches(parent, key))
        {
            ancestor = parent;
            child = cur;
            return true;
        }
        cur = parent;
    }
    return false;
}

public bool find_ancestor<
    TGraph: ITreeWalkGraph,
    TPredicate: ITreeWalkPredicate>(
    uint node,
    uint max_steps,
    out uint found)
{
    found = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;
    uint parent = TGraph.parent(node);
    if (!TGraph.valid(parent) || parent == node)
        return false;
    return find_self_or_ancestor<TGraph, TPredicate>(parent, max_steps, found);
}

public bool visit_ancestors_until<
    TGraph: ITreeWalkGraph,
    TStopPredicate: ITreeWalkPredicate,
    TVisitor: ITreeWalkEdgeVisitor>(
    uint node,
    uint max_steps,
    uint4 payload,
    out uint stop_ancestor,
    out uint stop_child)
{
    stop_ancestor = 0xffffffffu;
    stop_child = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;

    uint cur = node;
    [loop]
    for (uint step = 0u; step < max_steps; step += 1u)
    {
        uint parent = TGraph.parent(cur);
        if (!TGraph.valid(parent) || parent == cur)
            return false;
        if (TStopPredicate.matches(parent))
        {
            stop_ancestor = parent;
            stop_child = cur;
            return true;
        }

        TVisitor.visit(parent, cur, payload);
        cur = parent;
    }
    return false;
}

public bool find_ancestor_before<
    TGraph: ITreeWalkGraph,
    TPredicate: ITreeWalkPredicate>(
    uint node,
    uint stop,
    uint max_steps,
    out uint found)
{
    found = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;
    uint cur = TGraph.parent(node);
    if (!TGraph.valid(cur) || cur == node)
        return false;

    [loop]
    for (uint step = 0u; step < max_steps; step += 1u)
    {
        if (!TGraph.valid(cur) || cur == stop)
            return false;
        if (TPredicate.matches(cur))
        {
            found = cur;
            return true;
        }

        uint parent = TGraph.parent(cur);
        if (!TGraph.valid(parent) || parent == cur)
            return false;
        cur = parent;
    }
    return false;
}

public bool find_ancestor_matching_key_before<
    TGraph: ITreeWalkGraph,
    TPredicate: ITreeWalkKeyPredicate>(
    uint node,
    uint stop,
    uint key,
    uint max_steps,
    out uint found)
{
    found = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;
    uint cur = TGraph.parent(node);
    if (!TGraph.valid(cur) || cur == node)
        return false;

    [loop]
    for (uint step = 0u; step < max_steps; step += 1u)
    {
        if (!TGraph.valid(cur) || cur == stop)
            return false;
        if (TPredicate.matches(cur, key))
        {
            found = cur;
            return true;
        }

        uint parent = TGraph.parent(cur);
        if (!TGraph.valid(parent) || parent == cur)
            return false;
        cur = parent;
    }
    return false;
}

public bool find_ancestor_matching_key_before_or_until<
    TGraph: ITreeWalkGraph,
    TPredicate: ITreeWalkKeyPredicate,
    TStopPredicate: ITreeWalkPredicate>(
    uint node,
    uint stop,
    uint key,
    uint max_steps,
    out uint found)
{
    found = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;
    uint cur = TGraph.parent(node);
    if (!TGraph.valid(cur) || cur == node)
        return false;

    [loop]
    for (uint step = 0u; step < max_steps; step += 1u)
    {
        if (!TGraph.valid(cur) || cur == stop || TStopPredicate.matches(cur))
            return false;
        if (TPredicate.matches(cur, key))
        {
            found = cur;
            return true;
        }

        uint parent = TGraph.parent(cur);
        if (!TGraph.valid(parent) || parent == cur)
            return false;
        cur = parent;
    }
    return false;
}

public bool has_self_or_ancestor<
    TGraph: ITreeWalkGraph,
    TPredicate: ITreeWalkPredicate>(
    uint node,
    uint max_steps)
{
    uint found;
    return find_self_or_ancestor<TGraph, TPredicate>(node, max_steps, found);
}

public bool has_ancestor_before<
    TGraph: ITreeWalkGraph,
    TPredicate: ITreeWalkPredicate>(
    uint node,
    uint stop,
    uint max_steps)
{
    uint found;
    return find_ancestor_before<TGraph, TPredicate>(node, stop, max_steps, found);
}

public bool has_self_or_ancestor_node<TGraph: ITreeWalkGraph>(
    uint node,
    uint ancestor,
    uint max_steps)
{
    if (!TGraph.valid(node) || !TGraph.valid(ancestor))
        return false;

    uint cur = node;
    [loop]
    for (uint step = 0u; step < max_steps; step += 1u)
    {
        if (cur == ancestor)
            return true;

        uint parent = TGraph.parent(cur);
        if (!TGraph.valid(parent) || parent == cur)
            return false;
        cur = parent;
    }
    return false;
}

public bool has_strict_ancestor_node<TGraph: ITreeWalkGraph>(
    uint node,
    uint ancestor,
    uint max_steps)
{
    if (!TGraph.valid(node) || !TGraph.valid(ancestor))
        return false;

    uint parent = TGraph.parent(node);
    if (!TGraph.valid(parent) || parent == node)
        return false;
    return has_self_or_ancestor_node<TGraph>(parent, ancestor, max_steps);
}

public bool has_self_or_ancestor_node_until<
    TGraph: ITreeWalkGraph,
    TStopPredicate: ITreeWalkPredicate>(
    uint node,
    uint ancestor,
    uint max_steps)
{
    if (!TGraph.valid(node) || !TGraph.valid(ancestor))
        return false;

    uint cur = node;
    [loop]
    for (uint step = 0u; step < max_steps; step += 1u)
    {
        if (cur == ancestor)
            return true;

        uint parent = TGraph.parent(cur);
        if (!TGraph.valid(parent) || parent == cur || TStopPredicate.matches(parent))
            return false;
        cur = parent;
    }
    return false;
}

public bool tree_child_first<TGraph: ITreeChildGraph>(
    uint node,
    out uint child)
{
    child = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;
    uint candidate = TGraph.first_child(node);
    if (!TGraph.valid(candidate))
        return false;
    child = candidate;
    return true;
}

public bool tree_child_next<TGraph: ITreeChildGraph>(
    uint node,
    out uint sibling)
{
    sibling = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;
    uint candidate = TGraph.next_sibling(node);
    if (!TGraph.valid(candidate))
        return false;
    sibling = candidate;
    return true;
}

public bool tree_child_previous<TGraph: ITreeChildGraph>(
    uint parent,
    uint node,
    uint max_siblings,
    out uint previous)
{
    previous = 0xffffffffu;
    if (!TGraph.valid(parent) || !TGraph.valid(node))
        return false;

    uint child;
    if (!tree_child_first<TGraph>(parent, child))
        return false;

    [loop]
    for (uint step = 0u; step < max_siblings; step += 1u)
    {
        if (!TGraph.valid(child))
            break;
        if (child == node)
            return previous != 0xffffffffu;

        previous = child;
        uint sibling;
        if (!tree_child_next<TGraph>(child, sibling))
            break;
        child = sibling;
    }

    previous = 0xffffffffu;
    return false;
}

public bool tree_child_at<TGraph: ITreeChildGraph>(
    uint node,
    uint ordinal,
    uint max_siblings,
    out uint child)
{
    child = 0xffffffffu;
    if (!tree_child_first<TGraph>(node, child))
        return false;
    for (uint step = 0u; step < max_siblings; step += 1u)
    {
        if (step == ordinal)
            return true;
        uint sibling;
        if (!tree_child_next<TGraph>(child, sibling))
            return false;
        child = sibling;
    }
    child = 0xffffffffu;
    return false;
}

public bool tree_child_first_matching<
    TGraph: ITreeChildGraph,
    TPredicate: ITreeWalkPredicate>(
    uint node,
    uint max_siblings,
    out uint child)
{
    child = 0xffffffffu;
    if (!tree_child_first<TGraph>(node, child))
        return false;
    for (uint step = 0u; step < max_siblings; step += 1u)
    {
        if (TPredicate.matches(child))
            return true;
        uint sibling;
        if (!tree_child_next<TGraph>(child, sibling))
            break;
        child = sibling;
    }
    child = 0xffffffffu;
    return false;
}

public bool tree_child_first_matching_key<
    TGraph: ITreeChildGraph,
    TPredicate: ITreeWalkKeyPredicate>(
    uint node,
    uint key,
    uint max_siblings,
    out uint child)
{
    child = 0xffffffffu;
    if (!tree_child_first<TGraph>(node, child))
        return false;
    for (uint step = 0u; step < max_siblings; step += 1u)
    {
        if (TPredicate.matches(child, key))
            return true;
        uint sibling;
        if (!tree_child_next<TGraph>(child, sibling))
            break;
        child = sibling;
    }
    child = 0xffffffffu;
    return false;
}

public bool tree_next_preorder_within<TGraph: ITreeLinkedGraph>(
    uint root,
    uint node,
    uint max_ascend_steps,
    out uint next)
{
    next = 0xffffffffu;
    if (!TGraph.valid(root) || !TGraph.valid(node))
        return false;

    uint child = TGraph.first_child(node);
    if (TGraph.valid(child))
    {
        next = child;
        return true;
    }

    uint cur = node;
    [loop]
    for (uint step = 0u; step < max_ascend_steps; step += 1u)
    {
        if (cur == root)
            return false;
        uint sibling = TGraph.next_sibling(cur);
        if (TGraph.valid(sibling))
        {
            next = sibling;
            return true;
        }
        uint parent = TGraph.parent(cur);
        if (!TGraph.valid(parent) || parent == cur)
            return false;
        cur = parent;
    }
    return false;
}

public bool tree_first_preorder_matching_key<
    TGraph: ITreeLinkedGraph,
    TPredicate: ITreeWalkKeyPredicate>(
    uint root,
    uint key,
    uint max_steps,
    out uint found)
{
    found = 0xffffffffu;
    if (!TGraph.valid(root))
        return false;

    uint cur = root;
    [loop]
    for (uint step = 0u; step < max_steps; step += 1u)
    {
        if (TPredicate.matches(cur, key))
        {
            found = cur;
            return true;
        }

        uint next;
        if (!tree_next_preorder_within<TGraph>(root, cur, max_steps, next))
            break;
        cur = next;
    }
    return false;
}

public bool tree_first_descendant_matching_key<
    TGraph: ITreeLinkedGraph,
    TPredicate: ITreeWalkKeyPredicate>(
    uint root,
    uint key,
    uint max_steps,
    out uint found)
{
    found = 0xffffffffu;
    if (!TGraph.valid(root))
        return false;

    uint cur = TGraph.first_child(root);
    if (!TGraph.valid(cur))
        return false;

    [loop]
    for (uint step = 0u; step < max_steps; step += 1u)
    {
        if (TPredicate.matches(cur, key))
        {
            found = cur;
            return true;
        }

        uint next;
        if (!tree_next_preorder_within<TGraph>(root, cur, max_steps, next))
            break;
        cur = next;
    }
    return false;
}

public uint tree_count_preorder_matching_key<
    TGraph: ITreeLinkedGraph,
    TPredicate: ITreeWalkKeyPredicate>(
    uint root,
    uint key,
    uint max_steps)
{
    if (!TGraph.valid(root))
        return 0u;

    uint count = 0u;
    uint cur = root;
    [loop]
    for (uint step = 0u; step < max_steps; step += 1u)
    {
        if (TPredicate.matches(cur, key))
            count += 1u;

        uint next;
        if (!tree_next_preorder_within<TGraph>(root, cur, max_steps, next))
            break;
        cur = next;
    }
    return count;
}

public bool tree_nth_preorder_matching_key<
    TGraph: ITreeLinkedGraph,
    TPredicate: ITreeWalkKeyPredicate>(
    uint root,
    uint key,
    uint ordinal,
    uint max_steps,
    out uint found)
{
    found = 0xffffffffu;
    if (!TGraph.valid(root))
        return false;

    uint seen = 0u;
    uint cur = root;
    [loop]
    for (uint step = 0u; step < max_steps; step += 1u)
    {
        if (TPredicate.matches(cur, key))
        {
            if (seen == ordinal)
            {
                found = cur;
                return true;
            }
            seen += 1u;
        }

        uint next;
        if (!tree_next_preorder_within<TGraph>(root, cur, max_steps, next))
            break;
        cur = next;
    }
    return false;
}

public bool tree_matching_key_ordinal_before<
    TGraph: ITreeLinkedGraph,
    TPredicate: ITreeWalkKeyPredicate>(
    uint root,
    uint key,
    uint target,
    uint max_steps,
    out uint ordinal)
{
    ordinal = 0u;
    if (!TGraph.valid(root) || !TGraph.valid(target))
        return false;

    uint cur = root;
    [loop]
    for (uint step = 0u; step < max_steps; step += 1u)
    {
        if (cur == target)
            return true;
        if (TPredicate.matches(cur, key))
            ordinal += 1u;

        uint next;
        if (!tree_next_preorder_within<TGraph>(root, cur, max_steps, next))
            break;
        cur = next;
    }
    ordinal = 0xffffffffu;
    return false;
}

public bool tree_span_first_child<TGraph: IPreorderSpanGraph>(
    uint node,
    out uint child)
{
    child = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;
    uint candidate = node + 1u;
    if (!TGraph.valid(candidate) || TGraph.parent(candidate) != node)
        return false;
    child = candidate;
    return true;
}

public bool tree_span_next_sibling<TGraph: IPreorderSpanGraph>(
    uint node,
    out uint sibling)
{
    sibling = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;
    uint parent = TGraph.parent(node);
    uint candidate = TGraph.subtree_end(node);
    if (!TGraph.valid(parent) ||
        !TGraph.valid(candidate) ||
        TGraph.parent(candidate) != parent)
        return false;
    sibling = candidate;
    return true;
}

public bool tree_span_previous_sibling<TGraph: IPreorderSpanGraph>(
    uint node,
    uint max_siblings,
    out uint previous)
{
    previous = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;

    uint parent = TGraph.parent(node);
    if (!TGraph.valid(parent))
        return false;

    uint child;
    if (!tree_span_first_child<TGraph>(parent, child))
        return false;

    [loop]
    for (uint guard = 0u; guard < max_siblings && TGraph.valid(child) &&
                          TGraph.parent(child) == parent && child < node;
         guard += 1u)
    {
        previous = child;
        uint sibling;
        if (!tree_span_next_sibling<TGraph>(child, sibling))
            break;
        child = sibling;
    }
    return previous != 0xffffffffu;
}

public bool tree_span_first_matching<
    TGraph: IPreorderSpanGraph,
    TPredicate: ITreeWalkPredicate>(
    uint root,
    uint max_steps,
    out uint found)
{
    found = 0xffffffffu;
    if (!TGraph.valid(root))
        return false;

    uint end = TGraph.subtree_end(root);
    if (end <= root)
        return false;

    uint cur = root;
    [loop]
    for (uint step = 0u; step < max_steps && cur < end; step += 1u)
    {
        if (!TGraph.valid(cur))
            return false;
        if (TPredicate.matches(cur))
        {
            found = cur;
            return true;
        }
        cur += 1u;
    }
    return false;
}

public bool tree_span_first_descendant_matching<
    TGraph: IPreorderSpanGraph,
    TPredicate: ITreeWalkPredicate>(
    uint root,
    uint max_steps,
    out uint found)
{
    found = 0xffffffffu;
    if (!TGraph.valid(root))
        return false;
    uint child = root + 1u;
    if (!TGraph.valid(child) || TGraph.parent(child) != root)
        return false;
    return tree_span_first_matching<TGraph, TPredicate>(child, max_steps, found);
}

public bool tree_span_first_matching_key<
    TGraph: IPreorderSpanGraph,
    TPredicate: ITreeWalkKeyPredicate>(
    uint root,
    uint key,
    uint max_steps,
    out uint found)
{
    found = 0xffffffffu;
    if (!TGraph.valid(root))
        return false;

    uint end = TGraph.subtree_end(root);
    if (end <= root)
        return false;

    uint cur = root;
    [loop]
    for (uint step = 0u; step < max_steps && cur < end; step += 1u)
    {
        if (!TGraph.valid(cur))
            return false;
        if (TPredicate.matches(cur, key))
        {
            found = cur;
            return true;
        }
        cur += 1u;
    }
    return false;
}

public bool tree_span_first_descendant_matching_key<
    TGraph: IPreorderSpanGraph,
    TPredicate: ITreeWalkKeyPredicate>(
    uint root,
    uint key,
    uint max_steps,
    out uint found)
{
    found = 0xffffffffu;
    if (!TGraph.valid(root))
        return false;
    uint child = root + 1u;
    if (!TGraph.valid(child) || TGraph.parent(child) != root)
        return false;
    return tree_span_first_matching_key<TGraph, TPredicate>(
        child,
        key,
        max_steps,
        found);
}

public bool tree_subtree_end<TGraph: IPreorderTreeGraph>(
    uint node,
    uint node_count,
    out uint end)
{
    end = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;
    uint candidate = TGraph.subtree_end(node);
    if (candidate <= node || candidate > node_count)
        return false;
    end = candidate;
    return true;
}

public bool tree_contains<TGraph: IPreorderTreeGraph>(
    uint ancestor,
    uint node,
    uint node_count)
{
    uint end;
    return TGraph.valid(node) &&
           tree_subtree_end<TGraph>(ancestor, node_count, end) &&
           node >= ancestor &&
           node < end;
}

public bool tree_strictly_contains<TGraph: IPreorderTreeGraph>(
    uint ancestor,
    uint node,
    uint node_count)
{
    return node != ancestor && tree_contains<TGraph>(ancestor, node, node_count);
}

public bool tree_first_child<TGraph: IPreorderTreeGraph>(
    uint node,
    out uint child)
{
    child = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;
    uint candidate = TGraph.first_child(node);
    if (!TGraph.valid(candidate) || TGraph.parent(candidate) != node)
        return false;
    child = candidate;
    return true;
}

public bool tree_next_sibling<TGraph: IPreorderTreeGraph>(
    uint node,
    out uint sibling)
{
    sibling = 0xffffffffu;
    if (!TGraph.valid(node))
        return false;
    uint parent = TGraph.parent(node);
    uint candidate = TGraph.next_sibling(node);
    if (!TGraph.valid(parent) ||
        !TGraph.valid(candidate) ||
        TGraph.parent(candidate) != parent)
        return false;
    sibling = candidate;
    return true;
}

public bool tree_child_at<TGraph: IPreorderTreeGraph>(
    uint node,
    uint ordinal,
    uint max_siblings,
    out uint child)
{
    child = 0xffffffffu;
    if (!tree_first_child<TGraph>(node, child))
        return false;
    for (uint step = 0u; step < max_siblings; step += 1u)
    {
        if (step == ordinal)
            return true;
        uint sibling;
        if (!tree_next_sibling<TGraph>(child, sibling))
            return false;
        child = sibling;
    }
    child = 0xffffffffu;
    return false;
}

public bool tree_first_child_matching<
    TGraph: IPreorderTreeGraph,
    TPredicate: ITreeWalkPredicate>(
    uint node,
    uint max_siblings,
    out uint child)
{
    child = 0xffffffffu;
    if (!tree_first_child<TGraph>(node, child))
        return false;
    for (uint step = 0u; step < max_siblings; step += 1u)
    {
        if (TPredicate.matches(child))
            return true;
        uint sibling;
        if (!tree_next_sibling<TGraph>(child, sibling))
            break;
        child = sibling;
    }
    child = 0xffffffffu;
    return false;
}
