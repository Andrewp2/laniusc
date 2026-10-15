import type_checker.dependencies.constant_view;
#include "../type/instances/materialize_application_inputs.slang"
StructuredBuffer<uint> compact_type_alias_target;
StructuredBuffer<uint2> imported_type_alias_target;
import type_checker.constant_materialization;
import type_checker.checked_array_counts;
#include "../type/instances/allocate_application.slang"

// Source rows and declaration targets are immutable for this dispatch. Each
// lane owns its generated nodes and publishes one complete reference. The next
// dispatch applies this relation to annotations and argument/element edges.
RWStructuredBuffer<uint2> type_alias_normalized_ref;

// Alias normalization is the source-normalization walk that
// type/instances/materialize_application.slang ran with
// MATERIALIZE_NORMALIZE_ALIASES: the same traversal, failures, row
// allocation and alias environments. Its frames live in workgroup memory,
// not in per-thread local arrays, so the kernel reserves no local frames: a
// workgroup of ALIAS_LANES lanes owns one DEPTH_LIMIT slice per lane and
// each lane normalizes ALIAS_ROOTS_PER_LANE of the workgroup's 256 roots in
// turn (the dispatch still counts 256 roots per workgroup). Frame kind and
// child count are read back from the frame's row. Every constant operand
// and array length is materialized at one site.
static const uint ALIAS_LANES = 8u;
static const uint ALIAS_ROOTS_PER_LANE = 32u;
static const uint ALIAS_FRAMES = ALIAS_LANES * DEPTH_LIMIT;
groupshared uint3 walk_ref[ALIAS_FRAMES];
groupshared uint walk_target[ALIAS_FRAMES];
groupshared uint walk_next[ALIAS_FRAMES];
groupshared uint walk_env_a[ALIAS_FRAMES];
groupshared uint walk_env_b[ALIAS_FRAMES];

bool materialize_source_constant<Graph : IScopedTypeGraph>(uint environment,
    inout uint kind, inout uint payload, out uint failure)
{
    uint2 result;
    if (!materialize_checked_constant<Graph, ScopedConstantEnvironment<Graph>>(
        uint3(kind, payload, environment), gParams.n_tokens, result, failure)) return false;
    kind = result.x; payload = result.y; return true;
}

// Aliases retain their immediate target and their own parameter environment.
// Expanding a flattened target under a different alias's slots captures the
// wrong parameters when headers reorder, omit, or inject arguments.
uint alias_target_node(uint instance)
{
    uint declaration = type_instance_decl_token[instance];
    uint owner = declaration < gParams.n_tokens ? type_decl_hir_node_by_token[declaration] : INVALID;
    return owner < hir_count() && compact_hir_payload[owner].a == 8u
        ? compact_type_alias_target[owner] : INVALID;
}

// A new row for the node `ref` whose children change. An array row takes
// `length`, already materialized under the node's environment.
uint allocate_normalized_application(uint3 ref, uint reuse, uint2 length, out uint failure)
{
    failure = 0u;
    uint source = ref.y;
    uint kind = type_instance_kind[source];
    uint length_kind = type_instance_len_kind[source];
    uint length_payload = type_instance_len_payload[source];
    if (kind == 2u)
    {
        length_kind = length.x; length_payload = length.y;
        if (!checked_source_array_length_valid(length_kind, length_payload, gParams.n_tokens))
            { failure = 3u; return INVALID; }
    }
    uint target = reuse;
    if (target == INVALID)
        target = allocate_application(type_instance_decl_token[source], type_instance_arg_count[source],
            length_kind, length_payload, external_type_library_id[source], external_type_unit_id[source],
            external_type_local_index[source]);
    else
    {
        // Tail expansion alternates private alias environments. All arguments
        // are caller-side checked references before this row becomes an
        // environment; the preceding environment stays immutable while its
        // reordered arguments are being evaluated.
        type_instance_kind[target] = 0u;
        type_instance_decl_token[target] = type_instance_decl_token[source];
        type_instance_arg_count[target] = type_instance_arg_count[source];
        type_instance_len_kind[target] = length_kind;
        type_instance_len_payload[target] = length_payload;
        external_type_library_id[target] = external_type_library_id[source];
        external_type_unit_id[target] = external_type_unit_id[source];
        external_type_local_index[target] = external_type_local_index[source];
    }
    if (target == INVALID) failure = 1u;
    return target;
}

// The kind of a frame's row and its number of children.
uint frame_kind(uint row) { return row < mutable_type_capacity() ? type_instance_kind[row] : 0u; }
uint frame_count(uint row) { return frame_kind(row) == 1u ? type_instance_arg_count[row] : 1u; }

// Normalize `input`. This lane's frames are walk_*[base + depth]. Rows are
// immutable inputs except the private rows this lane allocates.
bool normalize<Graph : IScopedTypeGraph>(uint3 input, uint base, out uint2 result, out uint failure)
{
    for (uint i = 0u; i < DEPTH_LIMIT; i++)
        { walk_env_a[base + i] = INVALID; walk_env_b[base + i] = INVALID; }
    uint alias_expansions = 0u;
    uint created_count = 0u;
    uint depth = 0u;
    walk_ref[base] = input; walk_next[base] = INVALID;
    result = uint2(0u, INVALID); failure = 0u;
    for (;;)
    {
        uint frame = base + depth;
        uint3 ref = walk_ref[frame];
        bool complete = false;
        uint2 value = uint2(0u, INVALID);
        if (walk_next[frame] == INVALID)
        {
            uint alias_capacity; uint alias_stride;
            imported_type_alias_target.GetDimensions(alias_capacity, alias_stride);
            if (ref.x == 3u && ref.y < alias_capacity)
            {
                uint2 expanded = imported_type_alias_target[ref.y];
                if (expanded.x != 0u && expanded.y != INVALID)
                {
                    if (alias_expansions++ >= gParams.n_hir_nodes) { failure = 5u; return false; }
                    // The retained target is expressed in the caller's lexical
                    // parameters. Keep the surrounding substitution environment
                    // when expanding it inside another local/imported alias.
                    walk_ref[frame] = uint3(expanded, ref.z);
                    continue;
                }
            }
            if (ref.x == 2u && ref.z != INVALID)
            {
                uint slot = ref.y < gParams.n_tokens ? type_generic_param_slot_by_token[ref.y] : INVALID;
                uint tag; uint payload;
                if (slot == INVALID || !Graph.environment_argument(ref.z, slot, tag, payload))
                    { failure = 3u; return false; }
                ref = uint3(tag, payload, INVALID);
            }
            // Classify the node: a constant operand, a scalar or parameter
            // leaf, or a row whose children are walked next.
            bool constant = application_argument_is_constant(ref.x);
            bool row = !constant && ref.x == 3u && ref.y < mutable_type_capacity();
            uint kind = 0u;
            if (row)
            {
                kind = type_instance_kind[ref.y];
                uint arguments = kind == 1u ? type_instance_arg_count[ref.y] : 1u;
                if (kind < 1u || kind > 4u || arguments > ARG_LIMIT) { failure = 2u; return false; }
            }
            else if (!constant && !(ref.x == 1u && ref.y != 0u && ref.y != INVALID) &&
                !(ref.x == 2u && ref.y < gParams.n_tokens &&
                  type_generic_param_slot_by_token[ref.y] != INVALID))
                { failure = 3u; return false; }
            // A constant operand and an array row's length share this
            // materialization site.
            uint length_kind = 0u; uint length = INVALID;
            if (constant || kind == 2u)
            {
                length_kind = constant ? ref.x & ~APPLICATION_CONSTANT_ARGUMENT : type_instance_len_kind[ref.y];
                length = constant ? ref.y : type_instance_len_payload[ref.y];
                if (!materialize_source_constant<Graph>(ref.z, length_kind, length, failure))
                    return false;
                if (constant) ref = uint3(APPLICATION_CONSTANT_ARGUMENT | length_kind, length, INVALID);
            }
            walk_ref[frame] = ref;
            if (!row) { value = ref.xy; complete = true; }
            else
            {
                walk_target[frame] = INVALID; walk_next[frame] = 0u;
                if (kind == 2u && (length_kind != type_instance_len_kind[ref.y] ||
                    length != type_instance_len_payload[ref.y]))
                {
                    uint target = allocate_normalized_application(ref, INVALID, uint2(length_kind, length), failure);
                    if (target == INVALID) return false;
                    walk_target[frame] = target;
                }
            }
        }
        if (!complete && walk_next[frame] == frame_count(ref.y))
        {
            uint kind = frame_kind(ref.y);
            uint target = walk_target[frame];
            if (target != INVALID) type_instance_kind[target] = kind;
            value = uint2(3u, target == INVALID ? ref.y : target);
            uint alias_target = kind == 1u ? alias_target_node(value.y) : INVALID;
            if (alias_target < hir_count())
            {
                // Acyclic declaration chains have at most one expansion per
                // declaration along this path. The input-sized bound also
                // terminates recursive aliases without a fixed alias-hop cap.
                if (alias_expansions++ >= gParams.n_hir_nodes) { failure = 5u; return false; }
                uint token = type_token(alias_target);
                if (token >= gParams.n_tokens) { failure = 3u; return false; }
                walk_ref[frame] = uint3(type_expr_ref_tag[token], type_expr_ref_payload[token], value.y);
                walk_next[frame] = INVALID;
                continue;
            }
            if (target != INVALID)
            {
                if (created_count == DEPTH_LIMIT) { failure = 2u; return false; }
                created_count++;
            }
            complete = true;
        }
        if (complete)
        {
            if (depth == 0u)
            {
                for (uint i = 0u; i < DEPTH_LIMIT; i++)
                {
                    if (walk_env_a[base + i] != INVALID) type_instance_kind[walk_env_a[base + i]] = 0u;
                    if (walk_env_b[base + i] != INVALID) type_instance_kind[walk_env_b[base + i]] = 0u;
                }
                result = value; return true;
            }
            depth--;
            frame = base + depth;
            uint3 owner = walk_ref[frame];
            uint parent = walk_target[frame];
            uint slot = walk_next[frame] - 1u;
            uint kind = frame_kind(owner.y);
            if (owner.x == 3u && parent == INVALID)
            {
                uint source = owner.y;
                uint old_tag; uint old_payload;
                if (kind == 1u)
                {
                    if (!Graph.argument(source, slot, old_tag, old_payload)) { failure = 3u; return false; }
                }
                else { old_tag = type_instance_elem_ref_tag[source]; old_payload = type_instance_elem_ref_payload[source]; }
                if (all(value == uint2(old_tag, old_payload))) continue;
                bool alias = kind == 1u && alias_target_node(source) < hir_count();
                bool use_a = owner.z != walk_env_a[frame];
                uint reuse = alias ? (use_a ? walk_env_a[frame] : walk_env_b[frame]) : INVALID;
                // The length was materialized when the node was classified
                // and left the source's unchanged.
                parent = allocate_normalized_application(owner, reuse,
                    uint2(type_instance_len_kind[source], type_instance_len_payload[source]), failure);
                if (parent == INVALID) return false;
                walk_target[frame] = parent;
                if (alias)
                {
                    if (use_a) walk_env_a[frame] = parent;
                    else walk_env_b[frame] = parent;
                }
                // Earlier children are unchanged. Copy them once when the
                // first changed edge makes a new complete node necessary.
                if (kind == 1u)
                    for (uint i = 0u; i < slot; i++)
                    {
                        uint tag; uint payload;
                        if (!Graph.argument(source, i, tag, payload)) { failure = 3u; return false; }
                        uint edge = type_instance_arg_start[parent] + i;
                        type_instance_arg_ref_tag[edge] = tag; type_instance_arg_ref_payload[edge] = payload;
                    }
            }
            if (kind == 1u)
            {
                uint start = type_instance_arg_start[parent];
                type_instance_arg_ref_tag[start + slot] = value.x;
                type_instance_arg_ref_payload[start + slot] = value.y;
            }
            else
            {
                type_instance_elem_ref_tag[parent] = value.x;
                type_instance_elem_ref_payload[parent] = value.y;
            }
            continue;
        }
        uint slot = walk_next[frame]; walk_next[frame] = slot + 1u;
        uint tag; uint payload;
        if (frame_kind(ref.y) == 1u)
        {
            if (!Graph.argument(ref.y, slot, tag, payload))
                { failure = 3u; return false; }
        }
        else { tag = type_instance_elem_ref_tag[ref.y]; payload = type_instance_elem_ref_payload[ref.y]; }
        if (depth + 1u == DEPTH_LIMIT) { failure = 2u; return false; }
        depth++;
        walk_ref[base + depth] = uint3(tag, payload, ref.z); walk_next[base + depth] = INVALID;
    }
}

void normalize_root(uint root, uint base)
{
    if (root >= gParams.n_tokens) return;
    type_alias_normalized_ref[root] = uint2(0u, INVALID);
    if (type_instance_kind[root] == 0u || type_instance_state[root] != 1u) return;
    if (type_instance_kind[root] == 1u && type_instance_decl_token[root] == INVALID &&
        external_type_library_id[root] == INVALID) return;
    uint2 result; uint failure;
    if (!normalize<MutableCheckedTypeGraph>(uint3(3u, root, INVALID), base, result, failure))
    {
        record_min_token_error(status, root, 6u, 0x414c0000u | failure);
        return;
    }
    type_alias_normalized_ref[root] = result;
}

[shader("compute")]
[numthreads(8, 1, 1)]
void main(uint3 group: SV_GroupID, uint3 lane: SV_GroupThreadID)
{
    // The dispatch counts 256-root workgroups (the token-domain arguments).
    uint first = (group.x + group.y * 65535u) * 256u + lane.x;
    for (uint step = 0u; step < ALIAS_ROOTS_PER_LANE; step++)
        normalize_root(first + step * ALIAS_LANES, lane.x * DEPTH_LIMIT);
}
