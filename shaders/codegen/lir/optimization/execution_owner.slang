// CFG reachability is the authority for executable instruction ownership.
// Stable source rows and structured markers remain available as provenance;
// dead owners publish no canonical SSA values, operands, or uses.
import codegen.optimization_ir;

StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<OptIrNodeControl> opt_ir_control;
StructuredBuffer<uint> opt_ir_reachable;

bool opt_ir_node_has_cfg_owner(uint node, uint node_total)
{
    return node < node_total &&
        opt_ir_control[node].block_id < opt_ir_block_total[0u];
}

bool opt_ir_node_is_executable(uint node, uint node_total)
{
    return opt_ir_node_has_cfg_owner(node, node_total) &&
        opt_ir_reachable[opt_ir_control[node].block_id] != 0u;
}
