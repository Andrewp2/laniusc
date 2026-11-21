// Check expressions and their containing statements over the same HIR rows.
#include "expression_condition_checks.slang"
#include "statement_type_checks.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node)) return;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    validate_expression_condition(node, core, payload);
    validate_statement_type(node, core, payload);
}
