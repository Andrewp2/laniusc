// Queue the complete source applications as field-closure roots
// (ct_expand.slang). Their arguments, fields and payloads get rows in the
// following level rounds. Open applications are roots too: an unbound
// parameter leaf keeps its declaration identity, as in the application
// index.
import status;
import type_checker.canonical.canonical_api;
import type_checker.checked_type_graph;
import type_checker.substitution.ct_expand;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> type_decl_generic_param_count_by_owner_token;
StructuredBuffer<uint> type_decl_const_param_count_by_owner_token;
RWStructuredBuffer<uint> status;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint root = dtid.x + dtid.y * 16776960u;
    ct_expand_begin_run(root, 0u);
    if (root >= gParams.n_tokens || type_instance_kind[root] != 1u) return;
    uint declaration = type_instance_decl_token[root];
    if (declaration < gParams.n_tokens && type_instance_arg_count[root] !=
        (type_decl_generic_param_count_by_owner_token[declaration] +
         type_decl_const_param_count_by_owner_token[declaration])) return;
    uint id = ct_ref(3u, root);
    if (ct_kind(id) != CT_KIND_NAMED) return;
    if (!ct_expand_push(id, ct_expand_word(root, 0u, false)))
        record_min_token_error(status, root, 6u, 0x474e0001u);
}
