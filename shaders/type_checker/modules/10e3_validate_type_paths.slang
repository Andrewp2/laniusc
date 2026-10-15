// GPU type-path resolver status validation.
//
// Scheduling contract:
// - Dispatch after local/imported/qualified type path resolution has populated
//   resolved_type_status and after type-path projection has copied multi-segment
//   statuses into token-indexed status tables.
// - This pass reduces HIR path-record resolver errors into the compiler-wide
//   status buffer. It does not inspect source bytes, token spelling, helper
//   names, or function-body shapes.

import gpu_index;
import hir_records;
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
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_type_status;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_dependency_value_metadata;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> path_owner_hir;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<HirRange> compact_type_arg_ranges;
StructuredBuffer<uint> module_value_path_status;
StructuredBuffer<uint> module_value_path_expr_head;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<HirPath> compact_paths;
StructuredBuffer<HirPathSegment> compact_path_segments;
StructuredBuffer<HirRange> compact_path_type_arg_ranges;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;
static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RECORD_KIND_MODULE = 1u;
static const uint PATH_RECORD_KIND_IMPORT = 2u;
static const uint PATH_RECORD_KIND_HIR_BOUND_TYPE_EXPR = 5u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_AMBIGUOUS_IMPORT = 4u;
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

// Whether `node` is an argument in `arguments`.
bool range_has_argument(HirRange arguments, uint node, uint total)
{
    if (arguments.count > 64u || arguments.start > total || arguments.count > total - arguments.start)
        return false;
    bool found = false;
    for (uint i = 0u; i < arguments.count; i++)
        found = found || compact_type_args[arguments.start + i].value == node;
    return found;
}

// Whether `node` is an argument of an application at `token`: a value path
// segment (`f<N>`, `Type<N>::f`) or a member (`value.f<N>`).
bool token_applies_argument(uint token, uint node, uint total)
{
    return token < gParams.n_tokens &&
        range_has_argument(compact_path_type_arg_ranges[token], node, total);
}

// Whether `node` is an argument of a value path or member applying it.
// Their applications are token owned; only a type owns a node range.
bool value_application_argument(uint parent, uint node, uint count, uint total)
{
    uint kind = compact_hir_core[parent].kind;
    if (kind == 21u) return token_applies_argument(compact_hir_payload[parent].c, node, total);
    if (kind != 33u) return false;
    uint path = path_id_by_owner_hir[parent];
    if (path >= min(compact_path_count[0u], count)) return false;
    HirPath record = compact_paths[path];
    uint capacity; uint stride;
    compact_path_segments.GetDimensions(capacity, stride);
    if (record.owner != parent || record.segment_start > capacity ||
        record.segment_count > min(capacity - record.segment_start, 64u)) return false;
    bool found = false;
    for (uint segment = 0u; segment < record.segment_count; segment++)
        found = found || token_applies_argument(
            compact_path_segments[record.segment_start + segment].name_token, node, total);
    return found;
}

bool is_constant_operand_path(uint path)
{
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint node = path_owner_hir[path];
    if (node >= count) return false;
    uint parent = compact_hir_core[node].parent;
    if (parent >= count) return false;
    HirPayload owner = compact_hir_payload[parent];
    bool operand = compact_hir_core[parent].kind == 5u && owner.a == 2u && owner.d == node;
    uint total = min(compact_type_arg_count[0u], gParams.n_hir_nodes);
    operand = operand || range_has_argument(compact_type_arg_ranges[parent], node, total) ||
        value_application_argument(parent, node, count, total);
    if (!operand || resolved_value_status[path] != PATH_RESOLVE_STATUS_OK) return false;
    if (resolved_dependency_value_metadata[path * 4u] == 3u) return true;
    uint declaration = resolved_value_decl[path];
    return declaration < min(decl_count_out[0u], gParams.n_tokens) && decl_kind[declaration] == 3u;
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

    uint kind = path_kind[path_i];
    if (kind == PATH_RECORD_KIND_HIR_BOUND_TYPE_EXPR)
        return;

    if (kind == PATH_RECORD_KIND_HIR_TYPE_EXPR)
    {
        // The selected generic header (or array count consumer) decides the
        // operand domain. A value-name operand may have no type-namespace match.
        if (is_constant_operand_path(path_i)) return;
        uint resolved_status = resolved_type_status[path_i];
        if (resolved_status == PATH_RESOLVE_STATUS_AMBIGUOUS_IMPORT)
        {
            record_error(error_token, ERR_UNKNOWN_TYPE, resolved_status);
            return;
        }
        if (path_segment_count[path_i] <= 1u)
            return;

        if (resolved_status != PATH_RESOLVE_STATUS_OK)
        {
            record_error(error_token, ERR_UNKNOWN_TYPE, resolved_status);
        }
        return;
    }

    if (kind == PATH_RECORD_KIND_MODULE || kind == PATH_RECORD_KIND_IMPORT)
        return;
    if (kind != PATH_RECORD_KIND_HIR_PATH_EXPR)
        return;
    if (owner_token >= gParams.n_tokens || module_value_path_expr_head[owner_token] == 0u)
        return;

    uint value_status = resolved_value_status[path_i];
    if (value_status == PATH_RESOLVE_STATUS_AMBIGUOUS_IMPORT)
    {
        // A lexical local or parameter can shadow two imported declarations
        // with the same name. Defer one-segment value paths to lexical name
        // resolution and the final unresolved-name diagnostic. Qualified
        // paths cannot be disambiguated by a lexical declaration here.
        if (path_segment_count[path_i] > 1u)
            record_error(error_token, ERR_UNRESOLVED_IDENT, value_status);
        return;
    }
    if (value_status != PATH_RESOLVE_STATUS_OK)
    {
        // Qualified value-path status is carried in module_value_path_status so
        // later value consumers can clear it for non-value-path forms such as
        // type-qualified associated calls. The compact name-condition reducer
        // reports any status still left after those consumers run.
        return;
    }

    // Qualified value-path status is validated after value consumers and
    // associated-call resolution have had a chance to clear non-value forms.
}
