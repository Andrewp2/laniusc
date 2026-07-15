// GPU type-path resolver status validation.
//
// Scheduling contract:
// - Dispatch after local/imported/qualified type path resolution has populated
//   resolved_type_status and after type-path projection has copied multi-segment
//   statuses into token-indexed status tables.
// - This pass reduces HIR path-record resolver errors into the compiler-wide
//   status buffer. It does not inspect source bytes, token spelling, helper
//   names, or function-body shapes.

import generated_parse_production_ids;
import gpu_index;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_owner_hir;
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<uint> hir_bound_path_owner_by_leaf;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> resolved_type_status;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> module_value_path_status;
StructuredBuffer<uint> module_value_path_expr_head;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;
static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_INVALID = 0xffffffffu;

static const uint ERR_UNKNOWN_TYPE = 1u;
static const uint ERR_UNRESOLVED_IDENT = 2u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_tokens);
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

bool valid_hir_index(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

bool predicate_bound_type_path(uint path_i)
{
    uint owner = path_owner_hir[path_i];
    if (!valid_hir_index(owner))
        return false;

    uint leaf = hir_type_path_leaf_node[owner];
    if (!valid_hir_index(leaf))
        return false;

    return valid_hir_index(hir_bound_path_owner_by_leaf[leaf]);
}

bool metadata_path_record_step(inout uint node, out bool done)
{
    done = true;
    if (node == INVALID || node >= gParams.n_hir_nodes)
        return false;

    uint kind = node_kind[node];
    if (kind == PROD_MODULE ||
        kind == PROD_IMPORT ||
        kind == PROD_IMPORT_PATH ||
        kind == PROD_ITEM_MODULE ||
        kind == PROD_ITEM_IMPORT)
        return true;
    if (kind != PROD_PATH)
        return false;

    node = parent[node];
    done = false;
    return false;
}

bool metadata_path_record(uint path_i)
{
    uint node = path_owner_hir[path_i];
    bool done = false;

    bool found = metadata_path_record_step(node, done);
    if (found || done)
        return found;
    found = metadata_path_record_step(node, done);
    if (found || done)
        return found;
    found = metadata_path_record_step(node, done);
    if (found || done)
        return found;
    found = metadata_path_record_step(node, done);
    return found;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count())
        return;
    uint owner_token = path_owner_token[path_i];
    uint error_token = owner_token < gParams.n_tokens ? owner_token : gParams.n_tokens;

    if (predicate_bound_type_path(path_i))
        return;

    if (path_kind[path_i] == PATH_RECORD_KIND_HIR_TYPE_EXPR)
    {
        if (path_segment_count[path_i] <= 1u)
            return;

        uint resolved_status = resolved_type_status[path_i];
        if (resolved_status != PATH_RESOLVE_STATUS_OK)
        {
            record_error(error_token, ERR_UNKNOWN_TYPE, resolved_status);
        }
        return;
    }

    if (path_kind[path_i] != PATH_RECORD_KIND_HIR_PATH_EXPR)
        return;
    if (metadata_path_record(path_i))
        return;
    if (owner_token >= gParams.n_tokens || module_value_path_expr_head[owner_token] == 0u)
        return;

    uint value_status = resolved_value_status[path_i];
    if (value_status != PATH_RESOLVE_STATUS_OK)
    {
        // Qualified value-path status is carried in module_value_path_status so
        // later value consumers can clear it for non-value-path forms such as
        // type-qualified associated calls. conditions_hir reports any status
        // still left after those consumers run.
        return;
    }

    // Qualified value-path status is validated after value consumers and
    // associated-call resolution have had a chance to clear non-value forms.
}
