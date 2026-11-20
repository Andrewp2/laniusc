// Parallel pointer-jump step for compact expression ancestors: each round
// follows up to POINTER_JUMP_HOPS input links, so the reach of a link grows
// by that factor per round (`pointer_jump_hop_pairs` in lowering_ir.rs).

import codegen.lir.semantics.instructions.semantic_instruction_recipes;
import shared.collectives.step_program;

struct Params { uint n_hir_nodes; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
RWStructuredBuffer<uint> execution_rank_link_a;
RWStructuredBuffer<uint> execution_rank_a;
RWStructuredBuffer<uint> execution_rank_link_b;
RWStructuredBuffer<uint> execution_rank_b;
struct Launch { uint groups; uint slot; uint pairs; uint reserved; };
ConstantBuffer<Launch> program_launch;

static const uint POINTER_JUMP_HOPS = 64u;

void propagate_rank(
    uint node,
    uint hir_count,
    RWStructuredBuffer<uint> execution_rank_link_in,
    RWStructuredBuffer<uint> execution_rank_in,
    RWStructuredBuffer<uint> execution_rank_link_out,
    RWStructuredBuffer<uint> execution_rank_out)
{
    uint link = execution_rank_link_in[node];
    uint rank = execution_rank_in[node];
    for (uint hop = 1u; hop < POINTER_JUMP_HOPS; ++hop)
    {
        if (link == LIR_INVALID || link >= hir_count)
            break;
        rank += execution_rank_in[link];
        link = execution_rank_link_in[link];
    }
    bool linked = link != LIR_INVALID && link < hir_count;
    execution_rank_link_out[node] = linked ? execution_rank_link_in[link] : LIR_INVALID;
    execution_rank_out[node] = rank + (linked ? execution_rank_in[link] : 0u);
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint rows = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    for (uint pair = 0u; pair < program_launch.pairs; ++pair)
    {
        for (uint row = program.lane; row < rows; row += program.lanes)
            propagate_rank(row, rows, execution_rank_link_a, execution_rank_a,
                execution_rank_link_b, execution_rank_b);
        if (!step_barrier(program)) return;
        for (uint row = program.lane; row < rows; row += program.lanes)
            propagate_rank(row, rows, execution_rank_link_b, execution_rank_b,
                execution_rank_link_a, execution_rank_a);
        if (pair + 1u < program_launch.pairs && !step_barrier(program)) return;
    }
    step_program_end(program);
}
