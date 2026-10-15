// Seed the row of each ID from the interned source rows, atoms and
// projections (the smallest candidate in the ID's own spelling). Runs once
// per job, after the early canonical stage.
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_rows;
import type_checker.checked_type_graph;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint candidate = dtid.x + dtid.y * 16776960u;
    uint rows = ct_row_capacity();
    uint atoms = ct_atom_capacity();
    if (candidate < rows)
    {
        uint tokens; uint stride;
        type_generic_param_slot_by_token.GetDimensions(tokens, stride);
        if (candidate < checked_type_capacity())
            ct_seed_type_row(candidate, type_instance_kind[candidate], type_instance_decl_token[candidate],
                canonical_row[candidate], tokens);
    }
    else if (candidate - rows < atoms) ct_seed_constant_row(1u, candidate - rows, canonical_atom[candidate - rows]);
    else if (candidate - rows - atoms < ct_projection_capacity())
        ct_seed_constant_row(3u, candidate - rows - atoms, canonical_projection[candidate - rows - atoms]);
}
