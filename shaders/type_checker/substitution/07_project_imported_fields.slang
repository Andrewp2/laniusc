// The imported field projection (imported_fields.slang) over every live row
// (live_type_rows.slang). The inference rounds use
// 07b_project_listed_imported_fields.
#include "imported_fields.slang"
#include "../type/instances/live_type_rows.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    uint lanes = live_type_row_lanes(gParams.n_tokens, token_count[0u]);
    if (lane >= lanes) return;
    uint capacity; uint stride; uint group_capacity;
    imported_field_ref_tag.GetDimensions(capacity, stride);
    imported_layout_groups.GetDimensions(group_capacity, stride);
    uint row_spare = CT_NONE;
    CtSpare spare = ct_spare_none();
    bool busy = false;
    // The job's live rows (live_type_rows.slang). Rows realized while this
    // dispatch runs extend them; the count is read again for each row.
    uint source_rows;
    type_generic_param_slot_by_token.GetDimensions(source_rows, stride);
    for (uint index = lane; index < live_type_row_count(gParams.n_tokens, source_rows,
        mutable_type_capacity(), type_application_count[0u]); index += lanes)
    {
        uint instance = live_type_row(index, gParams.n_tokens, source_rows);
        if (!project_imported_row(instance, capacity, group_capacity, row_spare, spare, busy)) return;
    }
    // Another lane was writing a row a field needs: run another round.
    if (busy) { atomic_u32_add(call_inference_state, 1u, 1u); inference_note_item_change(); }
}
