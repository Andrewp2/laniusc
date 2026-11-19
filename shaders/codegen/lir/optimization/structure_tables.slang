import codegen.lir.lowering_ir;
import codegen.lir.optimization_ir;

public struct StructureParams
{
    public uint semantic_capacity;
    public uint hir_capacity;
    public uint block_capacity;
    public uint edge_capacity;
};

public ConstantBuffer<StructureParams> gParams;

public static const uint STRUCTURE_INVALID = 0xffffffffu;
public static const uint STRUCTURE_POINTER_JUMP_HOPS = 64u;

public StructuredBuffer<uint> semantic_lir_total;
public StructuredBuffer<uint> semantic_owner_by_instruction;
public StructuredBuffer<uint> semantic_schedule_order;
public StructuredBuffer<uint> semantic_function_id_by_hir;
public StructuredBuffer<OptIrNodeCore> opt_ir_core;
public StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
public RWStructuredBuffer<LoweringStatus> lowering_status;
public RWStructuredBuffer<uint> opt_ir_total;
public RWStructuredBuffer<OptIrNodeControl> opt_ir_control;
public RWStructuredBuffer<OptIrNodeResults> opt_ir_results;
public RWStructuredBuffer<uint> opt_ir_semantic_row;
public RWStructuredBuffer<uint> opt_ir_source_hir;
public RWStructuredBuffer<uint> opt_ir_position_by_node;
public RWStructuredBuffer<uint> opt_ir_block_start_flag;
public RWStructuredBuffer<uint> opt_ir_block_prefix;
public RWStructuredBuffer<uint> opt_ir_block_total;
public RWStructuredBuffer<OptIrBlock> opt_ir_blocks;
public RWStructuredBuffer<uint> opt_ir_edge_count_by_block;
public RWStructuredBuffer<uint> opt_ir_edge_prefix;
public RWStructuredBuffer<uint> opt_ir_edge_total;
public RWStructuredBuffer<OptIrEdge> opt_ir_edges;
public RWStructuredBuffer<uint> opt_ir_predecessor_total;
public RWStructuredBuffer<uint> opt_ir_predecessor_cursor;
public RWStructuredBuffer<uint> opt_ir_predecessor_edge_ids;
public RWStructuredBuffer<uint> scan_group_sums;
public StructuredBuffer<uint> semantic_function_total;
public StructuredBuffer<SemanticLirFunction> semantic_functions;
public RWStructuredBuffer<OptIrFunction> opt_ir_functions;
public RWStructuredBuffer<uint> opt_ir_reachable;
public RWStructuredBuffer<uint> opt_ir_dead_claim_by_block;
public RWStructuredBuffer<uint> opt_ir_immediate_dominator;
public RWStructuredBuffer<uint> opt_ir_dominator_children;
public RWStructuredBuffer<uint> opt_ir_dominator_child_row_by_block;
public RWStructuredBuffer<OptIrDominatorTourLink> opt_ir_dominator_tour_link_a;
public RWStructuredBuffer<OptIrDominatorTourLink> opt_ir_dominator_tour_link_b;
public RWStructuredBuffer<uint> opt_ir_dominator_preorder;
public RWStructuredBuffer<uint> opt_ir_dominator_subtree_end;
public RWStructuredBuffer<uint> opt_ir_block_by_dominator_preorder;
public RWStructuredBuffer<OptIrDominatorJump> opt_ir_dominator_depth_link_a;
public RWStructuredBuffer<OptIrDominatorJump> opt_ir_dominator_depth_link_b;
public RWStructuredBuffer<uint> opt_ir_dominator_depth;
public RWStructuredBuffer<uint> opt_ir_region_total;
public RWStructuredBuffer<OptIrRegion> opt_ir_regions;
public RWStructuredBuffer<uint> opt_ir_region_parent_link_a;
public RWStructuredBuffer<uint> opt_ir_region_parent_link_b;
public RWStructuredBuffer<uint> opt_ir_region_ownership_tree;
public RWStructuredBuffer<uint> opt_ir_block_region;
