// Reject a match that leaves a value of its scrutinee without an arm.
//
// The rule. A pattern is a name or `_` (it matches every value), a variant,
// or an integer literal. `true` and `false` are the two variants of bool. A
// variant pattern is simple when every payload pattern below it is a name or
// `_`, and single when exactly one payload pattern is not. A group is the
// set of patterns at one position: the arm patterns of the match, or the
// payload patterns in one column below the single patterns of one variant in
// a parent group. A group is covered when it has a `_` arm, or when each
// variant of its enum has a simple member, or has single members whose
// payload group is covered. For one variant only the column of its first
// single member counts. The match is exhaustive when its arm group is
// covered. A pattern with two payload patterns that can fail, an integer
// literal, and a pattern nested deeper than MAX_DEPTH cover nothing.
//
// The rule accepts no match that misses a value. It rejects some exhaustive
// matches, for example one that splits two payload columns at once; such a
// match needs a `_` arm.
//
// The check. One thread owns one pattern: an arm row or a payload row. A
// group fails at a leaf when a variant of its enum has no simple and no
// single member. The thread finds that for its own group from the variant
// after its own, so the members of a group together visit every variant.
// The thread then walks to the arm group. At each level the walk stops when
// another member covers the variant that the failing group sits below. A
// walk that reaches the arm group reports the `match` token. Every report
// for one match carries the same token and detail, so the result does not
// depend on thread order.
//
// This pass also owns the arm pattern that is none of `_`, a literal or an
// enum variant. No earlier pass reports a path that names another kind of
// declaration there.

import hir_records;
import type_checker.checked_pattern_path;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_start;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> resolved_dependency_value_metadata;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_DEPTH = 6u;
static const uint LANGUAGE_SYMBOL_WILDCARD = 19u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint ERR_MATCH_NOT_EXHAUSTIVE = 30u;
static const uint DETAIL_MISSING_VARIANT = 0u;
static const uint DETAIL_NEEDS_WILDCARD = 1u;
static const uint DETAIL_NOT_A_PATTERN = 2u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint IMPORTED_PAYLOAD_VARIANT = 10u;
static const uint IMPORTED_GENERIC_UNIT_VARIANT = 11u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;

// What a pattern is. OTHER is an arm pattern that is no pattern at all.
static const uint PATTERN_OTHER = 0u;
static const uint PATTERN_IRREFUTABLE = 1u;
static const uint PATTERN_LITERAL = 2u;
static const uint PATTERN_VARIANT = 3u;

// A variant family. A local enum is the run of variant rows that starts at
// `first` and shares `owner`. Bool and an imported enum give `count` and
// leave `owner` INVALID.
struct Family
{
    uint owner;
    uint first;
    uint count;
};

struct Shape
{
    uint kind;
    uint ordinal;
    Family family;
};

// A pattern of one arm. `row` is its payload row, or INVALID for the arm
// pattern itself.
struct Node
{
    uint arm;
    uint row;
};

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
uint active_arm_count() { return min(compact_match_arm_count[0u], gParams.n_hir_nodes); }
uint active_payload_count() { return min(compact_match_payload_row_count[0u], gParams.n_hir_nodes); }
uint active_variant_count() { return min(compact_variant_count[0u], gParams.n_hir_nodes); }
uint active_path_count() { return min(path_count_out[0u], gParams.n_hir_nodes); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

bool token_is_wildcard(uint token)
{
    return valid_token(token) && name_id_by_token[token] != INVALID &&
           name_id_by_token[token] == language_name_id[LANGUAGE_SYMBOL_WILDCARD];
}

// The variant a pattern names, as match binding resolves it.
bool pattern_variant(uint pattern, uint token, out uint ordinal, out Family family)
{
    ordinal = INVALID;
    family.owner = INVALID;
    family.first = 0u;
    family.count = 0u;
    uint path = checked_pattern_path(pattern, active_hir_count(), active_path_count(),
        compact_hir_links, path_id_by_owner_hir);
    if (path == INVALID || path_owner_token[path] != token)
        return false;
    uint imported = resolved_dependency_value_metadata[path * 4u];
    if (imported == HIR_ITEM_KIND_ENUM_VARIANT || imported == IMPORTED_PAYLOAD_VARIANT ||
        imported == IMPORTED_GENERIC_UNIT_VARIANT)
    {
        ordinal = resolved_dependency_value_metadata[path * 4u + 2u];
        family.count = resolved_dependency_value_metadata[path * 4u + 3u];
        return true;
    }
    if (resolved_value_status[path] != PATH_RESOLVE_STATUS_OK)
        return false;
    uint decl = resolved_value_decl[path];
    if (decl >= gParams.n_hir_nodes || decl_kind[decl] != HIR_ITEM_KIND_ENUM_VARIANT)
        return false;
    uint enum_decl = decl_parent_type_decl[decl];
    if (enum_decl >= gParams.n_hir_nodes || decl_kind[enum_decl] != HIR_ITEM_KIND_ENUM)
        return false;
    uint row = decl_hir_node[decl];
    if (row >= active_variant_count())
        return false;
    HirVariant variant = compact_variants[row];
    if (variant.ordinal > row)
        return false;
    ordinal = variant.ordinal;
    family.owner = variant.owner;
    family.first = row - variant.ordinal;
    return true;
}

bool family_has_ordinal(Family family, uint ordinal)
{
    if (family.owner == INVALID)
        return ordinal < family.count;
    uint row = family.first + ordinal;
    return row >= family.first && row < active_variant_count() &&
        compact_variants[row].owner == family.owner;
}

Shape node_shape(Node node)
{
    bool is_arm = node.row == INVALID;
    Shape shape;
    // A payload pattern that cannot be read is treated as one that can fail.
    shape.kind = is_arm ? PATTERN_OTHER : PATTERN_LITERAL;
    shape.ordinal = INVALID;
    shape.family.owner = INVALID;
    shape.family.first = 0u;
    shape.family.count = 0u;
    uint pattern = is_arm
        ? compact_match_arms[node.arm].pattern
        : compact_match_payloads[node.row].pattern;
    if (!valid_hir(pattern))
        return shape;
    HirCore core = compact_hir_core[pattern];
    if (token_is_wildcard(core.token_start))
    {
        shape.kind = PATTERN_IRREFUTABLE;
        return shape;
    }
    if (core.kind == HIR_LITERAL_EXPR)
    {
        uint form = compact_hir_payload[pattern].a;
        shape.kind = PATTERN_LITERAL;
        if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        {
            shape.kind = PATTERN_VARIANT;
            shape.ordinal = form == HIR_EXPR_TRUE ? 1u : 0u;
            shape.family.count = 2u;
        }
        return shape;
    }
    if (pattern_variant(pattern, core.token_start, shape.ordinal, shape.family))
        shape.kind = PATTERN_VARIANT;
    else if (!is_arm)
        shape.kind = PATTERN_IRREFUTABLE;
    return shape;
}

// Payload rows are in token order, so the rows of one arm are one run and a
// pattern comes before the patterns below it. The parent of a payload row is
// the nearest earlier row of its arm that owns its parent pattern. A row
// with no such row sits directly below the arm pattern.
Node parent_of(Node node)
{
    Node parent;
    parent.arm = node.arm;
    parent.row = INVALID;
    uint target = compact_match_payloads[node.row].parent_pattern;
    for (uint row = node.row; row > 0u;)
    {
        row -= 1u;
        HirMatchPayload earlier = compact_match_payloads[row];
        if (earlier.arm != node.arm)
            break;
        if (earlier.pattern == target)
        {
            parent.row = row;
            break;
        }
    }
    return parent;
}

// The payload patterns directly below `node` that can fail: their count,
// and the row of the last one.
uint refutable_children(Node node, out uint child_row)
{
    child_row = INVALID;
    uint count = 0u;
    uint rows = active_payload_count();
    uint row = node.row == INVALID ? compact_match_payload_start[node.arm] : node.row + 1u;
    for (; row < rows; row += 1u)
    {
        HirMatchPayload payload = compact_match_payloads[row];
        if (payload.arm != node.arm)
            break;
        Node child;
        child.arm = node.arm;
        child.row = row;
        bool direct = node.row == INVALID
            ? parent_of(child).row == INVALID
            : payload.parent_pattern == compact_match_payloads[node.row].pattern;
        if (!direct)
            continue;
        uint kind = node_shape(child).kind;
        if (kind == PATTERN_LITERAL || kind == PATTERN_VARIANT)
        {
            count += 1u;
            child_row = row;
        }
    }
    return count;
}

// Whether `candidate` is in the group of `member`: it sits in the same
// payload column below the same variants, and every pattern above it is
// single. `depth` is the depth of `member`. The patterns above `member` are
// checked by the walk in `main`.
bool in_group_of(Node candidate, Node member, uint depth)
{
    for (uint level = 0u; level < depth; level += 1u)
    {
        if (candidate.row == INVALID)
            return false;
        if (compact_match_payloads[candidate.row].ordinal !=
            compact_match_payloads[member.row].ordinal)
            return false;
        candidate = parent_of(candidate);
        member = parent_of(member);
        Shape above = node_shape(candidate);
        if (above.kind != PATTERN_VARIANT || above.ordinal != node_shape(member).ordinal)
            return false;
        uint ignored;
        if (refutable_children(candidate, ignored) != 1u)
            return false;
    }
    return candidate.row == INVALID;
}

// The work of one pattern. `first` and `arm_count` are the arm rows of the
// match and `match_token` is its `match` keyword.
void check_pattern(Node self, uint first, uint arm_count, uint match_token)
{
    uint depth = 0u;
    Node top = self;
    for (; depth <= MAX_DEPTH && top.row != INVALID; depth += 1u)
        top = parent_of(top);
    if (top.row != INVALID || depth > MAX_DEPTH)
        return;

    Shape own = node_shape(self);
    if (own.kind == PATTERN_OTHER)
    {
        // An unresolved name here already has its own report at this token.
        uint pattern = compact_match_arms[self.arm].pattern;
        uint pattern_token = valid_hir(pattern) ? compact_hir_core[pattern].token_start : INVALID;
        if (valid_token(pattern_token) && status[STATUS_TOKEN_SLOT] != pattern_token)
            record_min_token_error(status, pattern_token, ERR_MATCH_NOT_EXHAUSTIVE,
                DETAIL_NOT_A_PATTERN);
        return;
    }
    if (own.kind == PATTERN_IRREFUTABLE)
        return;

    // `current` starts as this pattern and moves to the pattern above it
    // each time its group is found to fail.
    Node current = self;
    uint level = depth;
    uint rows = active_payload_count();
    uint failed_column = INVALID;
    Shape named = own;
    for (uint step = 0u; step <= MAX_DEPTH; step += 1u)
    {
        if (step != 0u && named.kind != PATTERN_VARIANT)
            return;
        uint next = INVALID;
        if (step == 0u && named.kind == PATTERN_VARIANT)
            next = family_has_ordinal(named.family, named.ordinal + 1u) ? named.ordinal + 1u : 0u;

        bool catch_all_or_other = false;
        bool arm_group_has_variant = false;
        bool any_cover = false;
        bool next_covered = false;
        bool named_simple = false;
        uint named_single_column = INVALID;
        uint current_refutable = 0u;
        for (uint offset = 0u; offset < arm_count && !catch_all_or_other; offset += 1u)
        {
            Node candidate;
            candidate.arm = first + offset;
            candidate.row = level == 0u ? INVALID : compact_match_payload_start[candidate.arm];
            // The arm group has one candidate in each arm: the arm pattern.
            // A deeper group can have any payload row of the arm.
            for (uint visit = 0u; visit <= rows; visit += 1u)
            {
                if (level != 0u)
                {
                    if (candidate.row >= rows)
                        break;
                    if (compact_match_payloads[candidate.row].arm != candidate.arm)
                        break;
                }
                if (level == 0u || in_group_of(candidate, current, level))
                {
                    Shape shape = node_shape(candidate);
                    if (level == 0u &&
                        (shape.kind == PATTERN_IRREFUTABLE || shape.kind == PATTERN_OTHER))
                        catch_all_or_other = true;
                    if (shape.kind == PATTERN_VARIANT)
                    {
                        uint child_row;
                        uint refutable = refutable_children(candidate, child_row);
                        bool simple = refutable == 0u;
                        bool single = refutable == 1u && level < MAX_DEPTH;
                        arm_group_has_variant = arm_group_has_variant || level == 0u;
                        any_cover = any_cover || simple || single;
                        if (shape.ordinal == next)
                            next_covered = next_covered || simple || single;
                        if (shape.ordinal == named.ordinal)
                        {
                            named_simple = named_simple || simple;
                            if (single && named_single_column == INVALID)
                                named_single_column = compact_match_payloads[child_row].ordinal;
                        }
                        if (candidate.arm == current.arm && candidate.row == current.row)
                            current_refutable = refutable;
                    }
                }
                if (level == 0u)
                    break;
                candidate.row += 1u;
            }
        }

        if (level == 0u && catch_all_or_other)
            return;
        if (step == 0u)
        {
            // A leaf failure: no member covers anything, or the variant
            // after this one has no member that covers it.
            bool named_covered = named_simple || named_single_column != INVALID;
            bool leaf = !any_cover ||
                (named.kind == PATTERN_VARIANT && named_covered && !next_covered);
            if (!leaf)
                return;
        }
        else
        {
            // The group below `current` fails. The variant of `current` is
            // still covered when another member is simple, and the failing
            // group counts only when it is the column of the first single
            // member.
            if (named_simple || current_refutable != 1u ||
                named_single_column != failed_column)
                return;
        }
        if (level == 0u)
        {
            if (valid_token(match_token))
                record_min_token_error(status, match_token, ERR_MATCH_NOT_EXHAUSTIVE,
                    arm_group_has_variant ? DETAIL_MISSING_VARIANT : DETAIL_NEEDS_WILDCARD);
            return;
        }
        failed_column = compact_match_payloads[current.row].ordinal;
        current = parent_of(current);
        named = node_shape(current);
        level -= 1u;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    // A thread index names an arm row and a payload row.
    for (uint family_i = 0u; family_i < 2u; family_i += 1u)
    {
        Node self;
        if (family_i == 0u)
        {
            if (row >= active_arm_count()) continue;
            self.arm = row;
            self.row = INVALID;
        }
        else
        {
            if (row >= active_payload_count()) continue;
            self.arm = compact_match_payloads[row].arm;
            self.row = row;
            if (self.arm >= active_arm_count()) continue;
        }
        HirMatchArm arm = compact_match_arms[self.arm];
        if (!valid_hir(arm.owner) || arm.ordinal > self.arm) continue;
        if (compact_hir_core[arm.owner].kind != HIR_MATCH_EXPR) continue;
        uint first = self.arm - arm.ordinal;
        uint arm_count = compact_hir_payload[arm.owner].c;
        if (compact_hir_payload[arm.owner].b != first ||
            arm_count > active_arm_count() - first)
            continue;
        check_pattern(self, first, arm_count, compact_hir_core[arm.owner].token_start);
    }
}
