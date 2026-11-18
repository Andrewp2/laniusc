// 07_project_imported_fields over the listed live rows
// (live_type_row_list.slang), for the inference rounds.
#include "imported_fields.slang"
#include "../types/instances/live_type_row_list.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    ListedTypeRows rows = listed_type_rows();
    if (lane >= rows.lanes) return;
    uint capacity; uint stride; uint group_capacity;
    imported_field_ref_tag.GetDimensions(capacity, stride);
    imported_layout_groups.GetDimensions(group_capacity, stride);
    uint row_spare = CT_NONE;
    CtSpare spare = ct_spare_none();
    bool busy = false;
    // Rows realized while this dispatch runs extend the generated range; the
    // count is read again for each row.
    uint source_rows;
    type_generic_param_slot_by_token.GetDimensions(source_rows, stride);
    for (uint index = lane; index < listed_type_row_count(rows, source_rows,
        mutable_type_capacity(), type_application_count[0u]); index += rows.lanes)
    {
        uint instance = listed_type_row(rows, index, source_rows);
        if (!project_imported_row(instance, capacity, group_capacity, row_spare, spare, busy)) return;
    }
    // Another lane was writing a row a field needs: run another round.
    if (busy) { atomic_u32_add(call_inference_state, 1u, 1u); inference_note_item_change(); }
}
