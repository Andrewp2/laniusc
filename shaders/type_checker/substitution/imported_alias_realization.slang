// Realize the imported alias targets of materialize_dependency_alias_targets as checked rows,
// after the last dependency page. A target published as (pending, ID)
// becomes the checked reference of its row (ct_realize). A lane that meets
// a row another lane is writing leaves its target for the next dispatch
// (08); the final dispatch (finalize_imported_alias_realization) reports it instead. Included by both
// entry files: the shader build compiles only files with an entry point.
import shared.buffers.status;
import type_checker.mutable_checked_type_graph;
import type_checker.canonicalization.canonical_api;
import type_checker.substitution.canonical_substitution;
import type_checker.substitution.canonical_checked_type_rows;
import type_checker.substitution.checked_row_realization;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint2> imported_type_alias_target;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
// materialize_dependency_alias_targets: the tag of a target that is not realized yet.
static const uint ALIAS_TARGET_PENDING = 0xfffffffeu;
// Failure detail: 0x41490020 | ct_realize failure bits.
static const uint FAILURE_REALIZE = 0x41490020u;

void realize_alias_target(uint leaf, bool final_dispatch)
{
    uint capacity; uint stride;
    imported_type_alias_target.GetDimensions(capacity, stride);
    if (leaf >= min(gParams.n_tokens, capacity)) return;
    uint2 target = imported_type_alias_target[leaf];
    if (target.x != ALIAS_TARGET_PENDING) return;
    uint failure;
    uint2 reference = ct_realize(target.y, failure);
    if (!final_dispatch && failure == CT_REALIZE_BUSY) return;
    if (failure != 0u || (reference.x != 1u && reference.x != 2u && reference.x != 3u))
    {
        record_min_token_error(status, leaf, 6u, FAILURE_REALIZE | failure);
        reference = uint2(0u, INVALID);
    }
    imported_type_alias_target[leaf] = reference;
}
