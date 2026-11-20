import shared.syntax.hir_records;
import type_checker.modules.record_candidates;
import shared.buffers.atomics;
import shared.buffers.status;
import type_checker.modules.path_prefix_common;

public struct Params
{
    public uint n_tokens;
    public uint source_len;
    public uint n_hir_nodes;
};
public ConstantBuffer<Params> gParams;

public StructuredBuffer<uint> compact_hir_count;
public StructuredBuffer<HirCore> compact_hir_core;
public StructuredBuffer<HirPayload> compact_hir_payload;
public RWStructuredBuffer<uint> module_record_family_bits;
public RWStructuredBuffer<uint> path_id_by_owner_hir;
public RWStructuredBuffer<uint> path_id_by_owner_token;
public RWStructuredBuffer<uint> path_max_segment_count;
public RWStructuredBuffer<uint> resolved_value_type_qualifier_token;
public RWStructuredBuffer<uint4> resolved_value_qualifier_binding;
public StructuredBuffer<uint> compact_hir_expr_parent;
public StructuredBuffer<uint> compact_path_count;
public StructuredBuffer<HirPath> compact_paths;
public StructuredBuffer<uint> compact_path_segment_count;
public StructuredBuffer<HirPathSegment> compact_path_segments;
public RWStructuredBuffer<uint> path_owner_hir;
public RWStructuredBuffer<uint> path_len;
public RWStructuredBuffer<uint> path_call_hir;
public RWStructuredBuffer<uint> path_owner_token;
public RWStructuredBuffer<uint> path_kind;
public RWStructuredBuffer<uint> path_count_out;
public RWStructuredBuffer<uint> path_segment_base;
public RWStructuredBuffer<uint> path_segment_count;
public RWStructuredBuffer<uint> path_segment_count_out;
public StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
public StructuredBuffer<uint> name_id_by_token;
public RWStructuredBuffer<uint> path_segment_name_id;
public RWStructuredBuffer<uint> path_segment_token;
public RWStructuredBuffer<uint> path_prefix_base;
public RWStructuredBuffer<uint> path_prefix_id_a;
public RWStructuredBuffer<uint> predicate_syntax_token;
public RWStructuredBuffer<uint> path_prefix_table_state;
public RWStructuredBuffer<uint> path_prefix_id_b;
public RWStructuredBuffer<uint> status;
public RWStructuredBuffer<uint> path_dispatch_args;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint PATH_KIND_BOUND_TYPE = 5u;
static const uint ERR_PATH_PREFIX_TABLE = 58u;
static const uint MAX_GROUPS_X = 65535u;

public void mark_module_record_candidates(uint i)
{
    ModuleRecordCandidate row;
    HirCore core = compact_hir_core[i];
    HirPayload payload = compact_hir_payload[i];
    row.hir_kind = core.kind;
    row.item_kind = payload.a;
    row.name_token = payload.b;
    row.namespace_kind = payload.c;
    module_record_family_bits[i] = module_record_candidate_bits(row, gParams.n_tokens);
}

public void clear_path_state(uint row, uint path_capacity)
{
    if (row < path_capacity)
    {
        resolved_value_type_qualifier_token[row] = INVALID;
        resolved_value_qualifier_binding[row] = uint4(0u, INVALID, INVALID, INVALID);
    }
    if (row < gParams.n_hir_nodes)
    {
        path_id_by_owner_hir[row] = INVALID;
    }
    if (row < gParams.n_tokens)
    {
        path_id_by_owner_token[row] = INVALID;
    }
    if (row == 0u)
        path_max_segment_count[0u] = 0u;
}

public void scatter_paths(uint row, uint hir_count, uint count)
{
    if (row == 0u)
        path_count_out[0u] = count;
    if (row >= count) return;

    HirPath path = compact_paths[row];
    if (path.owner >= hir_count || path.segment_count == 0u ||
        path.segment_start >= compact_path_segment_count[0u])
        return;
    HirPathSegment first = compact_path_segments[path.segment_start];
    uint owner_token = first.name_token;
    if (owner_token >= gParams.n_tokens)
        return;

    path_owner_hir[row] = path.owner;
    path_len[row] = path.segment_count;
    uint call = compact_hir_expr_parent[path.owner];
    if (call >= hir_count || compact_hir_core[call].kind != HIR_CALL_EXPR)
    {
        uint wrapper = compact_hir_core[path.owner].parent;
        call = wrapper < hir_count && compact_hir_core[wrapper].kind == HIR_NAME_EXPR
            ? compact_hir_expr_parent[wrapper]
            : INVALID;
    }
    path_call_hir[row] = call < hir_count && compact_hir_core[call].kind == HIR_CALL_EXPR
        ? call
        : INVALID;
    path_owner_token[row] = owner_token;
    path_id_by_owner_hir[path.owner] = row;
    path_id_by_owner_token[owner_token] = row;
    path_kind[row] = path.kind;
}

public void count_path_segments(uint row, uint count, uint segments)
{
    if (row == 0u)
        path_segment_count_out[0u] = segments;
    if (row >= count)
        return;
    HirPath path = compact_paths[row];
    path_segment_base[row] = path.segment_start;
    path_segment_count[row] = path.segment_count;
    atomic_u32_max(path_max_segment_count, 0u, path.segment_count);
}

// Whether `node` is the trait type of a trait implementation's header.
bool impl_trait_type(uint node, uint count)
{
    uint owner = node < count ? compact_hir_core[node].parent : INVALID;
    return owner < count && compact_hir_semantic_facts[owner].semantic_kind == HIR_SEMANTIC_IMPL_TRAIT &&
        compact_hir_payload[owner].b == node;
}

public void scatter_path_segments(uint row, uint hir_count, uint paths)
{
    HirPathSegment segment = compact_path_segments[row];
    if (segment.path >= paths)
        return;
    HirPath path = compact_paths[segment.path];
    if (segment.ordinal >= path.segment_count || path.segment_start + segment.ordinal != row)
        return;
    uint token = segment.name_token;
    if (token >= gParams.n_tokens || name_id_by_token[token] == INVALID)
        return;
    path_segment_name_id[row] = name_id_by_token[token];
    path_segment_token[row] = token;
    path_prefix_base[row] = path.segment_start;
    path_prefix_id_a[row] = name_id_by_token[token];
    // Every segment of a bound path, and of the trait path of an impl header
    // (`impl gen::lib::Score for Rec`), belongs to the compact predicate
    // family. Marking by compact segment row keeps this parallel and removes
    // the old first/second-argument width limit from diagnostic ownership.
    if (path.kind == PATH_KIND_BOUND_TYPE || impl_trait_type(path.owner, hir_count))
        predicate_syntax_token[token] = 1u;
}

public void clear_path_prefix_table(uint row, uint rows)
{
    path_prefix_table_state[row] = 0u;
    path_prefix_table_state[row + rows] = 0u;
}

public void intern_path_prefix_pairs(uint row, uint rows, uint step, uint epoch,
    RWStructuredBuffer<uint> input_ids, RWStructuredBuffer<uint> output_ids)
{
    uint capacity = rows * 2u;
    uint2 key = path_prefix_pair(row, step, path_prefix_base, input_ids);
    uint first = path_prefix_first_slot(key.x, key.y, capacity);
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint slot = (first + probe) % capacity;
        uint state = path_prefix_table_state[slot];
        if (state != PATH_PREFIX_TABLE_EMPTY && path_prefix_table_epoch(state) == epoch)
        {
            uint owner = path_prefix_table_owner(state);
            uint2 occupied_key = path_prefix_pair(
                owner,
                step,
                path_prefix_base,
                input_ids);
            if (occupied_key.x == key.x && occupied_key.y == key.y)
            {
                output_ids[row] = slot;
                return;
            }
            continue;
        }

        uint replacement = path_prefix_table_state_for_owner(row, epoch);
        uint prior = atomic_u32_compare_exchange(
            path_prefix_table_state,
            slot,
            state,
            replacement);
        if (prior == state)
        {
            output_ids[row] = slot;
            return;
        }

        if (path_prefix_table_epoch(prior) != epoch)
            continue;

        uint prior_owner = path_prefix_table_owner(prior);
        uint2 prior_key = path_prefix_pair(
            prior_owner,
            step,
            path_prefix_base,
            input_ids);
        if (prior_key.x == key.x && prior_key.y == key.y)
        {
            output_ids[row] = slot;
            return;
        }
    }

    output_ids[row] = PATH_PREFIX_INVALID;
    record_min_token_error(status, row, ERR_PATH_PREFIX_TABLE, step);
}

// The dependency and type-instance passes use this grid after the program.
public void publish_path_dispatch(uint paths)
{
    uint groups = max(1u, (paths + 255u) / 256u);
    path_dispatch_args[0u] = min(groups, MAX_GROUPS_X);
    path_dispatch_args[1u] = max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    path_dispatch_args[2u] = 1u;
}
