import codegen.lir.lowering_ir;
import codegen.lir.optimization_ir;

public struct AccessParams
{
    public uint semantic_capacity;
    public uint hir_capacity;
    public uint block_capacity;
    public uint access_capacity;
    public uint declaration_capacity;
    public uint parameter_capacity;
    public uint local_capacity;
    public uint reserved;
};

public ConstantBuffer<AccessParams> access_params;

public struct DemandParams
{
    public uint block_capacity;
    public uint edge_capacity;
    public uint access_capacity;
    public uint declaration_capacity;
    public uint declaration_block_capacity;
    public uint demand_capacity;
    public uint alias_hops;
    public uint reserved;
    public uint incoming_capacity;
};

public ConstantBuffer<DemandParams> demand_params;

public StructuredBuffer<uint> opt_ir_block_total;
public StructuredBuffer<OptIrNodeControl> opt_ir_control;
public StructuredBuffer<uint> opt_ir_reachable;
public StructuredBuffer<uint> opt_ir_total;
public StructuredBuffer<OptIrNodeCore> opt_ir_core;
public StructuredBuffer<uint> semantic_schedule_order;
public RWStructuredBuffer<uint> opt_ir_access_flag;
public StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
public RWStructuredBuffer<uint> opt_ir_access_prefix;
public RWStructuredBuffer<uint> opt_ir_instruction_access_total;
public RWStructuredBuffer<uint> opt_ir_metadata_access_total;
public RWStructuredBuffer<OptIrAccessCore> opt_ir_accesses;
public RWStructuredBuffer<uint> opt_ir_access_source_rows;
public RWStructuredBuffer<uint> opt_ir_access_positions;
public RWStructuredBuffer<uint> opt_ir_access_kinds;
public RWStructuredBuffer<LoweringStatus> lowering_status;
public StructuredBuffer<uint> semantic_function_total;
public StructuredBuffer<uint> semantic_param_total;
public StructuredBuffer<SemanticLirParam> semantic_params;
public StructuredBuffer<uint> semantic_local_total;
public StructuredBuffer<SemanticLirLocal> semantic_locals;
public StructuredBuffer<OptIrFunction> opt_ir_functions;
public RWStructuredBuffer<uint> opt_ir_access_total;
public RWStructuredBuffer<uint> opt_ir_declaration_access_total;
public StructuredBuffer<uint> opt_ir_position_by_node;
public StructuredBuffer<OptIrBlock> opt_ir_blocks;
public RWStructuredBuffer<uint> opt_ir_access_order;
public RWStructuredBuffer<uint> opt_ir_access_group_start_flag;
public RWStructuredBuffer<uint> opt_ir_local_definition_by_access;
public RWStructuredBuffer<uint> opt_ir_access_group_prefix;
public RWStructuredBuffer<OptIrAccessGroup> opt_ir_access_groups;
public RWStructuredBuffer<OptIrDeclarationBlock> opt_ir_declaration_blocks;
public RWStructuredBuffer<uint> opt_ir_access_group_total;
public RWStructuredBuffer<uint> opt_ir_declaration_block_total;
public RWStructuredBuffer<OptIrReachingDefinitionState> opt_ir_reaching_definition_states;
public RWStructuredBuffer<uint> access_order_temporary;
public RWStructuredBuffer<uint> access_histogram;
public RWStructuredBuffer<uint> access_bucket_total;
public RWStructuredBuffer<uint> opt_ir_ssa_demand_total;
public RWStructuredBuffer<OptIrSsaDemand> opt_ir_ssa_demands;
public RWStructuredBuffer<uint> opt_ir_ssa_block_argument_total;
public RWStructuredBuffer<OptIrBlockArgument> opt_ir_ssa_block_arguments;
public RWStructuredBuffer<uint> opt_ir_ssa_demand_seed_flag;
public RWStructuredBuffer<uint> opt_ir_ssa_demand_seed_prefix;
public RWStructuredBuffer<uint> opt_ir_ssa_sparse_declaration;
public RWStructuredBuffer<uint> opt_ir_ssa_sparse_block;
public StructuredBuffer<uint> opt_ir_edge_total;
public StructuredBuffer<OptIrEdge> opt_ir_edges;
public StructuredBuffer<uint> opt_ir_predecessor_prefix;
public StructuredBuffer<uint> opt_ir_predecessor_edge_ids;
public RWStructuredBuffer<uint> opt_ir_ssa_walk;
public RWStructuredBuffer<uint> opt_ir_ssa_demand_order;
public RWStructuredBuffer<OptIrSsaDemand> opt_ir_ssa_canonical_demands_tmp;
public RWStructuredBuffer<uint> opt_ir_ssa_block_argument_flag;
public RWStructuredBuffer<uint> opt_ir_ssa_block_argument_incoming_count;
public RWStructuredBuffer<uint> opt_ir_ssa_block_argument_incoming_total;
public RWStructuredBuffer<OptIrBlockArgumentIncoming> opt_ir_ssa_block_argument_incoming;
public RWStructuredBuffer<uint> opt_ir_ssa_block_argument_user_count;
public RWStructuredBuffer<uint> opt_ir_ssa_block_argument_user_prefix;
public RWStructuredBuffer<uint> opt_ir_ssa_block_argument_user_total;
public RWStructuredBuffer<uint> opt_ir_ssa_block_argument_user_arguments;
public RWStructuredBuffer<uint> opt_ir_ssa_block_argument_summary;
public RWStructuredBuffer<uint> opt_ir_ssa_block_argument_replacement;
public RWStructuredBuffer<uint> demand_order_temporary;
public RWStructuredBuffer<uint> demand_histogram;
public RWStructuredBuffer<uint> demand_bucket_total;
public RWStructuredBuffer<uint> opt_ir_ssa_demand_resolution_tmp;
