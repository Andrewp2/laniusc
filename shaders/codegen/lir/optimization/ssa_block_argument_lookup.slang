// Shared accessors over compact pruned block arguments.

import codegen.optimization_ir;

StructuredBuffer<uint> opt_ir_ssa_block_argument_total;
StructuredBuffer<OptIrBlockArgument> opt_ir_ssa_block_arguments;

public uint opt_ir_active_ssa_block_argument_total(uint capacity)
{
    return min(opt_ir_ssa_block_argument_total[0u], capacity);
}

public OptIrBlockArgument opt_ir_ssa_block_argument(uint row)
{
    return opt_ir_ssa_block_arguments[row];
}

// Incoming rows are compacted in block-argument order, but each argument owns
// its complete range. Consumers therefore do not depend on a neighboring row
// or on the construction-time global total to recover the range end.
public uint opt_ir_ssa_block_argument_incoming_end(
    uint row,
    uint argument_total,
    uint incoming_total)
{
    if (row >= argument_total) return incoming_total;
    OptIrBlockArgument argument = opt_ir_ssa_block_arguments[row];
    uint end = argument.incoming_start + argument.incoming_count;
    return end < argument.incoming_start ? 0xffffffffu : end;
}
