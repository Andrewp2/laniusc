// Target-independent optimizer IR storage contracts. Keep these records in
// lockstep with codegen/optimization_ir.rs.

import codegen.lowering_ir;

struct OptIrNodeCore
{
    uint type_id;
    uint type_ref_payload;
    uint flags;
    uint value_word_count;
};

struct OptIrNodeOperands
{
    uint result;
    uint a;
    uint b;
    uint c;
};

struct OptIrNodeControl
{
    uint block_id;
    uint region_id;
};

struct OptIrNodeResults
{
    uint value_out;
    uint effect_out;
};

struct OptIrValueDefinition
{
    uint source;
};

static const uint OPT_IR_VALUE_DEFINITION_INVALID = 0u;
static const uint OPT_IR_VALUE_DEFINITION_PARAMETER = 1u;
static const uint OPT_IR_VALUE_DEFINITION_NODE = 2u;
static const uint OPT_IR_VALUE_DEFINITION_BLOCK_ARGUMENT = 3u;
static const uint OPT_IR_VALUE_DEFINITION_KIND_SHIFT = 30u;
static const uint OPT_IR_VALUE_DEFINITION_PAYLOAD_MASK = 0x3fffffffu;

uint opt_ir_pack_value_definition(uint kind, uint payload)
{
    if (kind == OPT_IR_VALUE_DEFINITION_INVALID ||
        kind > OPT_IR_VALUE_DEFINITION_BLOCK_ARGUMENT ||
        payload > OPT_IR_VALUE_DEFINITION_PAYLOAD_MASK)
        return 0u;
    return kind << OPT_IR_VALUE_DEFINITION_KIND_SHIFT | payload;
}

uint opt_ir_value_definition_kind(OptIrValueDefinition definition)
{
    return definition.source >> OPT_IR_VALUE_DEFINITION_KIND_SHIFT;
}

uint opt_ir_value_definition_payload(OptIrValueDefinition definition)
{
    return opt_ir_value_definition_kind(definition) ==
        OPT_IR_VALUE_DEFINITION_INVALID
        ? 0xffffffffu
        : definition.source & OPT_IR_VALUE_DEFINITION_PAYLOAD_MASK;
}

struct OptIrBlock
{
    uint function_id;
    uint position_start;
    uint terminator;
    uint edge_range;
};

static const uint OPT_IR_BLOCK_EDGE_START_MASK = 0x3fffffffu;
static const uint OPT_IR_BLOCK_EDGE_COUNT_SHIFT = 30u;

uint opt_ir_pack_block_edges(uint start, uint count)
{
    return (start & OPT_IR_BLOCK_EDGE_START_MASK) |
        (min(count, 3u) << OPT_IR_BLOCK_EDGE_COUNT_SHIFT);
}

uint opt_ir_block_edge_start(OptIrBlock block)
{
    return block.edge_range & OPT_IR_BLOCK_EDGE_START_MASK;
}

uint opt_ir_block_edge_count(OptIrBlock block)
{
    return block.edge_range >> OPT_IR_BLOCK_EDGE_COUNT_SHIFT;
}

struct OptIrEdge
{
    uint from_block;
    uint packed_target;
};

struct OptIrFunction
{
    uint node_start;
    uint node_count;
    uint block_start;
    uint block_count;
    uint entry_block;
    uint flags;
    uint region_start;
    uint region_count;
};

struct OptIrRegion
{
    uint function_id;
    uint parent_region;
    uint position_start;
    uint position_end;
};

struct OptIrAccessCore
{
    uint subject;
    uint block_id;
};

struct OptIrAccessGroup
{
    uint subject;
    uint start;
    uint count;
    uint flags;
};

struct OptIrDeclarationBlock
{
    uint access_start;
};

struct OptIrReachingDefinitionState
{
    uint incoming_definition;
};

struct OptIrSsaDemand
{
    uint declaration;
    uint block;
};

struct OptIrSsaValueRef
{
    uint kind;
    uint payload;
};

struct OptIrBlockArgument
{
    uint block_id;
    uint declaration;
    uint incoming_start;
    uint incoming_count;
};

struct OptIrBlockArgumentIncoming
{
    uint predecessor;
    uint source;
};

struct OptIrIncomingValue
{
    uint predecessor;
    uint value;
};

struct OptIrUseGroup
{
    uint value;
    uint start;
    uint count;
};

static const uint OPT_IR_USE_FIXED = 0u;
static const uint OPT_IR_USE_CALL_ARGUMENT = 1u;
static const uint OPT_IR_USE_AGGREGATE_ELEMENT = 2u;
static const uint OPT_IR_USE_BLOCK_ARGUMENT_INCOMING = 3u;
static const uint OPT_IR_USE_KIND_SHIFT = 30u;
static const uint OPT_IR_USE_FIXED_ORDINAL_SHIFT = 28u;
static const uint OPT_IR_USE_FIXED_NODE_MASK = 0x0fffffffu;
static const uint OPT_IR_USE_ROW_MASK = 0x3fffffffu;

uint opt_ir_pack_fixed_use(uint node, uint ordinal)
{
    return (min(ordinal, 3u) << OPT_IR_USE_FIXED_ORDINAL_SHIFT) |
        (node & OPT_IR_USE_FIXED_NODE_MASK);
}

uint opt_ir_pack_side_use(uint kind, uint row)
{
    return (min(kind, OPT_IR_USE_BLOCK_ARGUMENT_INCOMING) <<
        OPT_IR_USE_KIND_SHIFT) | (row & OPT_IR_USE_ROW_MASK);
}

uint opt_ir_use_kind(uint packed)
{
    return packed >> OPT_IR_USE_KIND_SHIFT;
}

uint opt_ir_use_row(uint packed)
{
    return opt_ir_use_kind(packed) == OPT_IR_USE_FIXED
        ? packed & OPT_IR_USE_FIXED_NODE_MASK
        : packed & OPT_IR_USE_ROW_MASK;
}

uint opt_ir_use_fixed_ordinal(uint packed)
{
    return (packed >> OPT_IR_USE_FIXED_ORDINAL_SHIFT) & 3u;
}

struct OptIrDominatorJump
{
    uint ancestor;
    uint distance;
};

struct OptIrDominatorTourLink
{
    uint previous;
    uint down_count;
};

static const uint OPT_IR_REACHING_DEFINITION_UNUSED = 0xffffffffu;
static const uint OPT_IR_REACHING_DEFINITION_UNRESOLVED = 0xfffffffeu;
static const uint OPT_IR_REACHING_DEFINITION_MERGE = 0xfffffffdu;

static const uint OPT_IR_SSA_SOURCE_INVALID = 0u;
static const uint OPT_IR_SSA_SOURCE_LOCAL_DEFINITION = 1u;
static const uint OPT_IR_SSA_SOURCE_DEMAND = 2u;
static const uint OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT = 3u;
static const uint OPT_IR_SSA_SOURCE_KIND_SHIFT = 30u;
static const uint OPT_IR_SSA_SOURCE_PAYLOAD_MASK = 0x3fffffffu;

uint opt_ir_pack_ssa_source(OptIrSsaValueRef source)
{
    if (source.kind == OPT_IR_SSA_SOURCE_INVALID) return 0u;
    if (source.kind > OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT ||
        source.payload > OPT_IR_SSA_SOURCE_PAYLOAD_MASK)
        return 0u;
    return source.kind << OPT_IR_SSA_SOURCE_KIND_SHIFT | source.payload;
}

OptIrSsaValueRef opt_ir_unpack_ssa_source(uint packed)
{
    OptIrSsaValueRef source;
    source.kind = packed >> OPT_IR_SSA_SOURCE_KIND_SHIFT;
    source.payload = source.kind == OPT_IR_SSA_SOURCE_INVALID
        ? 0xffffffffu
        : packed & OPT_IR_SSA_SOURCE_PAYLOAD_MASK;
    return source;
}

static const uint OPT_IR_DOMINATOR_INVALID = 0xffffffffu;
static const uint OPT_IR_DOMINATOR_UNRESOLVED = 0xfffffffeu;
static const uint OPT_IR_DOMINATOR_UNREACHABLE = 0xfffffffdu;

static const uint OPT_IR_ACCESS_INVALID = 0u;
static const uint OPT_IR_ACCESS_DECLARATION_READ = 1u;
static const uint OPT_IR_ACCESS_DECLARATION_WRITE = 2u;
static const uint OPT_IR_ACCESS_MEMORY_READ = 3u;
static const uint OPT_IR_ACCESS_MEMORY_WRITE = 4u;
static const uint OPT_IR_ACCESS_PARAMETER_DEFINITION = 5u;
static const uint OPT_IR_ACCESS_LOCAL_DECLARATION = 6u;
static const uint OPT_IR_ACCESS_KIND_COUNT = 7u;

static const uint OPT_IR_EDGE_FALLTHROUGH = 1u;
static const uint OPT_IR_EDGE_BRANCH = 2u;
static const uint OPT_IR_EDGE_CONDITIONAL = 4u;
static const uint OPT_IR_EDGE_BACK = 8u;
static const uint OPT_IR_EDGE_TARGET_MASK = 0x0fffffffu;

uint opt_ir_edge_target(uint to_block, uint flags)
{
    return (to_block & OPT_IR_EDGE_TARGET_MASK) |
        ((flags & 0x0fu) << 28u);
}

uint opt_ir_edge_to_block(uint packed_target)
{
    return packed_target & OPT_IR_EDGE_TARGET_MASK;
}

uint opt_ir_edge_flags(uint packed_target)
{
    return packed_target >> 28u;
}


uint opt_ir_op(OptIrNodeCore core)
{
    return (core.flags & SEMANTIC_LIR_OP_MASK) >> SEMANTIC_LIR_OP_SHIFT;
}

uint opt_ir_access_kind(OptIrNodeCore core)
{
    uint op = opt_ir_op(core);
    if (semantic_lir_op_has_flag(op,
        SEMANTIC_LIR_OP_FLAG_DECLARATION_READ))
        return OPT_IR_ACCESS_DECLARATION_READ;
    if (semantic_lir_op_has_flag(op,
        SEMANTIC_LIR_OP_FLAG_DECLARATION_WRITE))
        return OPT_IR_ACCESS_DECLARATION_WRITE;
    if (semantic_lir_op_has_flag(op, SEMANTIC_LIR_OP_FLAG_MEMORY_READ))
        return OPT_IR_ACCESS_MEMORY_READ;
    if (semantic_lir_op_has_flag(op, SEMANTIC_LIR_OP_FLAG_MEMORY_WRITE))
    {
        // Compound assignment still uses STORE for its scalar declaration
        // update. Only field/index projections address memory here.
        bool projected = (core.flags &
            (SEMANTIC_LIR_FLAG_INDEXED | SEMANTIC_LIR_FLAG_FIELD)) != 0u;
        return op == SEMANTIC_LIR_OP_STORE && !projected
            ? OPT_IR_ACCESS_DECLARATION_WRITE
            : OPT_IR_ACCESS_MEMORY_WRITE;
    }
    return OPT_IR_ACCESS_INVALID;
}

uint opt_ir_access_domain(uint kind)
{
    return kind == OPT_IR_ACCESS_MEMORY_READ ||
        kind == OPT_IR_ACCESS_MEMORY_WRITE ? 1u : 0u;
}

uint opt_ir_type_ref_tag(OptIrNodeCore core)
{
    return (core.flags & SEMANTIC_LIR_TYPE_REF_TAG_MASK) >>
        SEMANTIC_LIR_TYPE_REF_TAG_SHIFT;
}

uint opt_ir_operand(OptIrNodeOperands operands, uint ordinal)
{
    return ordinal == 0u ? operands.a :
        ordinal == 1u ? operands.b :
        ordinal == 2u ? operands.c : 0xffffffffu;
}

// Resolves the executable operand-role table's DYNAMIC entries into the
// actual value edges represented by this row. Dynamic roles are deliberately
// centralized here so SSA construction, def-use construction, and both
// targets cannot grow separate opcode-shaped interpretations.
bool opt_ir_operand_is_value(OptIrNodeCore core, uint ordinal)
{
    if (ordinal >= 3u) return false;
    uint op = opt_ir_op(core);
    bool indexed = (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u;
    bool field = (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u;
    bool projected = indexed || field;

    // STORE's fixed property row describes the projected memory form. The
    // scalar declaration-update form instead stores `(declaration, value)` in
    // `(a, b)` and leaves `c` absent.
    if (op == SEMANTIC_LIR_OP_STORE)
    {
        if (!projected) return ordinal == 1u;
        return ordinal == 0u || ordinal == 2u ||
            (indexed && ordinal == 1u);
    }

    uint role = semantic_lir_operand_role(op, ordinal);
    if (role == SEMANTIC_LIR_OPERAND_VALUE) return true;
    if (role != SEMANTIC_LIR_OPERAND_DYNAMIC) return false;

    // An indexed load consumes `(aggregate, index)`; a field load consumes
    // only the aggregate while its other fields are layout metadata.
    return op == SEMANTIC_LIR_OP_LOAD && indexed && ordinal == 1u;
}

bool opt_ir_is_declaration_state_node(OptIrNodeCore core)
{
    uint op = opt_ir_op(core);
    if (op == SEMANTIC_LIR_OP_VALUE_GET ||
        op == SEMANTIC_LIR_OP_VALUE_SET)
        return true;
    bool projected = (core.flags &
        (SEMANTIC_LIR_FLAG_INDEXED | SEMANTIC_LIR_FLAG_FIELD)) != 0u;
    return op == SEMANTIC_LIR_OP_STORE && !projected;
}

static const uint OPT_IR_SSA_VALUE_LINK_INVALID = 0u;
static const uint OPT_IR_SSA_VALUE_LINK_NODE = 1u;
static const uint OPT_IR_SSA_VALUE_LINK_VALUE = 2u;
static const uint OPT_IR_SSA_VALUE_LINK_KIND_SHIFT = 30u;
static const uint OPT_IR_SSA_VALUE_LINK_PAYLOAD_MASK = 0x3fffffffu;

uint opt_ir_pack_ssa_value_link(uint kind, uint payload)
{
    if (kind == OPT_IR_SSA_VALUE_LINK_INVALID ||
        kind > OPT_IR_SSA_VALUE_LINK_VALUE ||
        payload > OPT_IR_SSA_VALUE_LINK_PAYLOAD_MASK)
        return 0u;
    return kind << OPT_IR_SSA_VALUE_LINK_KIND_SHIFT | payload;
}

uint opt_ir_ssa_value_link_kind(uint packed)
{
    return packed >> OPT_IR_SSA_VALUE_LINK_KIND_SHIFT;
}

uint opt_ir_ssa_value_link_payload(uint packed)
{
    return opt_ir_ssa_value_link_kind(packed) ==
        OPT_IR_SSA_VALUE_LINK_INVALID
        ? 0xffffffffu
        : packed & OPT_IR_SSA_VALUE_LINK_PAYLOAD_MASK;
}
