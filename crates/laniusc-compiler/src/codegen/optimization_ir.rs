//! Target-independent optimizer IR storage contracts.
//!
//! Phase 1 materializes these records one-for-one from semantic LIR. Later
//! phases may compact or rewrite them into SSA, but target lowering only sees
//! this boundary and never reaches back into mutable semantic instructions.

use encase::ShaderType;

/// Common operation data. Phase 1 keeps the opcode packed in `flags`, matching
/// semantic LIR's 16-byte stride. The generated semantic-property helpers make
/// the packed representation safe to query without widening every hot scan.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrNodeCore {
    pub type_id: u32,
    pub type_ref_payload: u32,
    pub flags: u32,
    pub value_word_count: u32,
}

/// Fixed-arity operation inputs. `result` preserves the pre-SSA declaration
/// identity during Phase 1; Phase 2 replaces it with dense SSA result IDs.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrNodeOperands {
    pub result: u32,
    pub a: u32,
    pub b: u32,
    pub c: u32,
}

/// Structured-control ownership. Effect dependencies are a separate compact
/// relation: reserving two empty effect words on every node would make pure
/// programs pay for state that only effectful nodes need.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrNodeControl {
    pub block_id: u32,
    pub region_id: u32,
}

/// Dense SSA outputs. Identity OptIR initializes both fields to INVALID; the
/// Phase 2 construction pass assigns them without changing target APIs.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrNodeResults {
    pub value_out: u32,
    pub effect_out: u32,
}

/// One canonical dense SSA value definition.
///
/// The high two bits encode whether the value is produced by a parameter,
/// ordinary OptIR node, or surviving block argument. The low 30 bits hold the
/// row in that source relation. Keeping this as one word gives optimizers a
/// dense value domain without duplicating type and ownership data already
/// available from the defining row.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrValueDefinition {
    pub source: u32,
}

/// Dense basic-block identity and its location in the scheduled OptIR stream.
///
/// Nodes retain stable OptIR IDs, while `position_start` indexes the
/// target-independent execution permutation. Keeping the two identities
/// separate lets dataflow use dense blocks without rewriting provenance or
/// variadic side tables merely to establish control flow.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrBlock {
    pub function_id: u32,
    pub position_start: u32,
    pub terminator: u32,
    /// Low 30 bits are the edge start; high two bits are the 0-2 successor
    /// count. Regions and block arguments are compact side relations.
    pub edge_range: u32,
}

/// One dense control-flow edge. Edges are stored in source-block order, so a
/// block's `edge_start/edge_count` range is sufficient for forward dataflow.
/// Reverse-edge indexing is built later from this canonical relation.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrEdge {
    pub from_block: u32,
    /// Low 28 bits contain the destination block; high four bits contain the
    /// complete optimizer edge-flag set.
    pub packed_target: u32,
}

/// Dense optimizer ownership for one semantic function. Region ranges remain
/// empty until the structured-region slice lands, but their permanent fields
/// are present now so target consumers do not face another representation
/// cutover after SSA construction begins.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrFunction {
    pub node_start: u32,
    pub node_count: u32,
    pub block_start: u32,
    pub block_count: u32,
    pub entry_block: u32,
    pub flags: u32,
    pub region_start: u32,
    pub region_count: u32,
}

/// One lexical structured-control region. Positions address the scheduled
/// OptIR stream and include the opening and closing control rows. Dense region
/// IDs follow opening position, so all regions owned by one function are
/// contiguous. `parent_region` is INVALID for a function-level root.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrRegion {
    pub function_id: u32,
    pub parent_region: u32,
    pub position_start: u32,
    pub position_end: u32,
}

/// The hot key for one row in the temporary declaration/memory-access
/// relation. Source identity and ordered position are construction and
/// validation metadata stored in parallel columns; late SSA construction
/// retains only the declaration/memory subject and owning block.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrAccessCore {
    pub subject: u32,
    pub block_id: u32,
}

/// One contiguous declaration group in the stable access ordering. Memory
/// accesses use a separate domain and are not represented here. A declaration
/// therefore owns at most one group and group capacity follows declaration
/// capacity rather than instruction capacity.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrAccessGroup {
    pub subject: u32,
    pub start: u32,
    pub count: u32,
    pub flags: u32,
}

/// One declaration's accesses within one basic block. Rows are ordered first
/// by declaration and then by block. `access_start` addresses the stable
/// declaration-access ordering; the next row's start (or the declaration
/// access total) supplies the end. The declaration and block are deliberately
/// not repeated here: both are available from the first ordered access. This
/// keeps the required sparse SSA state to one word per populated pair.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrDeclarationBlock {
    pub access_start: u32,
}

/// Incoming reaching-definition state for one [`OptIrDeclarationBlock`].
/// Local and outgoing definitions are derived from the block's final ordered
/// access and `local_definition_by_access`; storing those values again would
/// double the mandatory SSA workspace. Reserved high values distinguish an
/// unused entry from an unresolved incoming value and, later, a merge value.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrReachingDefinitionState {
    pub incoming_definition: u32,
}

/// One memoized reaching-definition request used by demand-driven SSA
/// construction. Initial rows come from upward-exposed reads. Propagation can
/// add transparent predecessor blocks that have no declaration access row, so
/// the fixed-point relation owns both identities rather than indexing the
/// sparse [`OptIrDeclarationBlock`] seed table.
///
/// Rows use lexicographic `(declaration, block)` order. Sorting and
/// deduplication therefore provide the memoization boundary for parallel
/// propagation and break loop cycles after a join has published its merge
/// value.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrSsaDemand {
    pub declaration: u32,
    pub block: u32,
}

/// One pruned block argument created at a demanded CFG join.
///
/// Construction retains the source declaration so trivial-argument
/// propagation can prove that aliases stay in the same value domain. The
/// owning block and complete incoming range are canonical optimizer data:
/// consumers must not need the temporary demand relation or the following
/// argument row to recover either fact.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrBlockArgument {
    pub block_id: u32,
    pub declaration: u32,
    pub incoming_start: u32,
    pub incoming_count: u32,
}

/// One predecessor contribution to a block argument. Rows are stored in the
/// owning argument's contiguous incoming range and in canonical predecessor
/// order. Predecessor identity remains explicit so the final SSA relation is
/// independently checkable without retaining the reverse-CFG construction
/// index. During construction, `source` packs a two-bit source kind above a
/// 30-bit row payload; the final rewrite replaces it with a dense value.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrBlockArgumentIncoming {
    pub predecessor: u32,
    pub source: u32,
}

/// Final dense SSA contribution to a block argument. This replaces the
/// construction-only packed source while retaining the predecessor identity
/// required by optimizers and independent validation.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrIncomingValue {
    pub predecessor: u32,
    pub value: u32,
}

/// One compact group in the stable value-use ordering. `start/count` address
/// the canonical use columns; values with no users own no group row.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrUseGroup {
    pub value: u32,
    pub start: u32,
    pub count: u32,
}

/// One immediate-dominator identity per dense basic block. This is optimizer
/// workspace rather than a backend artifact: structured SSA consumes it to
/// place block arguments and validate rewritten uses.
///
/// Entry blocks dominate themselves. Blocks with no forward predecessor are
/// marked unreachable. Genuine forward joins remain unresolved until the
/// dominance-construction rounds establish their common ancestor.
pub type OptIrImmediateDominator = u32;

/// Binary-lifting workspace used while deriving a dominator range.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrDominatorJump {
    pub ancestor: u32,
    pub distance: u32,
}

/// One directed-arc link in the dominator-tree Euler tour. Parallel list
/// ranking replaces `previous` by progressively earlier predecessors while
/// accumulating the number of downward arcs. The final counts yield exact
/// preorder and subtree intervals without assuming source schedule order.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct OptIrDominatorTourLink {
    pub previous: u32,
    pub down_count: u32,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::codegen::lowering_ir::{SemanticLirCore, SemanticLirOperands};

    #[test]
    fn optimizer_records_match_shader_storage_layouts() {
        assert_eq!(std::mem::size_of::<OptIrNodeCore>(), 16);
        assert_eq!(std::mem::size_of::<OptIrNodeOperands>(), 16);
        assert_eq!(std::mem::size_of::<OptIrNodeControl>(), 8);
        assert_eq!(std::mem::size_of::<OptIrNodeResults>(), 8);
        assert_eq!(std::mem::size_of::<OptIrValueDefinition>(), 4);
        assert_eq!(std::mem::size_of::<OptIrBlock>(), 16);
        assert_eq!(std::mem::size_of::<OptIrEdge>(), 8);
        assert_eq!(std::mem::size_of::<OptIrFunction>(), 32);
        assert_eq!(std::mem::size_of::<OptIrRegion>(), 16);
        assert_eq!(std::mem::size_of::<OptIrAccessCore>(), 8);
        assert_eq!(std::mem::size_of::<OptIrAccessGroup>(), 16);
        assert_eq!(std::mem::size_of::<OptIrDeclarationBlock>(), 4);
        assert_eq!(std::mem::size_of::<OptIrReachingDefinitionState>(), 4);
        assert_eq!(std::mem::size_of::<OptIrSsaDemand>(), 8);
        assert_eq!(std::mem::size_of::<OptIrBlockArgument>(), 16);
        assert_eq!(std::mem::size_of::<OptIrBlockArgumentIncoming>(), 8);
        assert_eq!(std::mem::size_of::<OptIrIncomingValue>(), 8);
        assert_eq!(std::mem::size_of::<OptIrUseGroup>(), 12);
        assert_eq!(std::mem::size_of::<OptIrDominatorJump>(), 8);
        assert_eq!(std::mem::size_of::<OptIrDominatorTourLink>(), 8);
    }

    #[test]
    fn identity_opt_ir_columns_are_binary_compatible_with_semantic_lir() {
        assert_eq!(
            std::mem::size_of::<OptIrNodeCore>(),
            std::mem::size_of::<SemanticLirCore>()
        );
        assert_eq!(
            std::mem::align_of::<OptIrNodeCore>(),
            std::mem::align_of::<SemanticLirCore>()
        );
        assert_eq!(
            std::mem::offset_of!(OptIrNodeCore, type_id),
            std::mem::offset_of!(SemanticLirCore, type_id)
        );
        assert_eq!(
            std::mem::offset_of!(OptIrNodeCore, type_ref_payload),
            std::mem::offset_of!(SemanticLirCore, type_ref_payload)
        );
        assert_eq!(
            std::mem::offset_of!(OptIrNodeCore, flags),
            std::mem::offset_of!(SemanticLirCore, flags)
        );
        assert_eq!(
            std::mem::offset_of!(OptIrNodeCore, value_word_count),
            std::mem::offset_of!(SemanticLirCore, value_word_count)
        );

        assert_eq!(
            std::mem::size_of::<OptIrNodeOperands>(),
            std::mem::size_of::<SemanticLirOperands>()
        );
        assert_eq!(
            std::mem::align_of::<OptIrNodeOperands>(),
            std::mem::align_of::<SemanticLirOperands>()
        );
        assert_eq!(
            std::mem::offset_of!(OptIrNodeOperands, result),
            std::mem::offset_of!(SemanticLirOperands, result)
        );
        assert_eq!(
            std::mem::offset_of!(OptIrNodeOperands, a),
            std::mem::offset_of!(SemanticLirOperands, a)
        );
        assert_eq!(
            std::mem::offset_of!(OptIrNodeOperands, b),
            std::mem::offset_of!(SemanticLirOperands, b)
        );
        assert_eq!(
            std::mem::offset_of!(OptIrNodeOperands, c),
            std::mem::offset_of!(SemanticLirOperands, c)
        );
    }
}
