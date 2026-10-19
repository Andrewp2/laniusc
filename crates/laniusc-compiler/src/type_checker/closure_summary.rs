//! Closure summaries of library units (D1b, docs: D_PLAN D1b).
//!
//! D1's instance closure (shaders/type_checker/closure) follows only the
//! calls of the job's own unit. An application's call to a generic library
//! function reaches the library's generic calls only when that body's
//! replay is scanned, one replay round later. A library unit's summary is
//! the edge list of D1 for that unit, kept with its interface: per generic
//! function, each call to a generic function with the call's environment in
//! slot form, where every parameter of the caller is the dependency slot leaf
//! of its composed binding slot. A dependent job uploads the summaries of its
//! dependencies, interns their environment nodes, seeds closure roots from
//! its own closed calls into them and expands through their edges on the GPU
//! (closure/00b, 01b and 03b), so their instances join its first replay
//! round as kind-2 closure origins admitted in that job.
//!
//! The summary is built from the unit's already-decoded retained facts
//! (calls, call owners and the contract owner table) and carries no canonical
//! ID. Edges it cannot spell (private library types, unresolved identities,
//! nodes deeper than the import rounds) are left out: the closure only loses
//! instances, which the replays still find.

use std::{
    collections::{BTreeMap, HashMap},
    sync::Arc,
};

use super::{
    CheckedBinderIdentity,
    CheckedCallOwner,
    CheckedGenericApplicationArgument,
    CheckedGenericCall,
    CheckedGenericConstantValue,
    CheckedGenericTarget,
    CheckedGenericType,
    CheckedNominalIdentity,
    CheckedParameterDomain,
    CheckedUnitContracts,
};

const INVALID: u32 = u32::MAX;

/// The tag of a closure instance whose callee is a summary function: its
/// tagged environment's owner word and its instance row's callee are
/// `SUMMARY_TAG | job-wide function index` (a local instance uses its callee
/// HIR row + 1, which never has the high bit).
pub(crate) const SUMMARY_TAG: u32 = 0x8000_0000;

/// Node kinds (closure/summary.slang). They mirror the dependency page's
/// type node kinds where one exists, with the slot leaves immediate.
pub(crate) const NODE_SCALAR: u32 = 1; // w0 = scalar code
pub(crate) const NODE_TYPE_SLOT: u32 = 2; // w0 = composed type slot
pub(crate) const NODE_NAMED: u32 = 3; // w = (library, unit, persisted); children = operands
pub(crate) const NODE_ARRAY: u32 = 4; // children = (element, length)
pub(crate) const NODE_SLICE: u32 = 5; // children = (element)
pub(crate) const NODE_REF: u32 = 6; // children = (element)
pub(crate) const NODE_CONST_SLOT: u32 = 8; // w0 = composed constant slot, w1 = declared scalar
pub(crate) const NODE_LITERAL: u32 = 9; // w = (scalar, lo, hi)
pub(crate) const NODE_PROJECTION: u32 = 10; // w0 = target scalar, w1 = child parameter scalar; child

/// Function row flag: the function has a call the summary cannot spell.
pub(crate) const SUMMARY_FN_INCOMPLETE: u32 = 1;

/// A node interns in the round after its children (00b_import_summary): a
/// node deeper than this is left out with every edge that names it.
pub(crate) const SUMMARY_IMPORT_ROUNDS: u32 = 8;
/// Operands of one named node (canonical_dependency's NOMINAL_LIMIT).
const NAMED_OPERAND_LIMIT: usize = 32;

/// Upload capacities of one job (`closure_summary_inputs`). A dependency
/// summary that does not fit is left out whole.
pub(crate) const SUMMARY_MAX_FNS: usize = 4096;
pub(crate) const SUMMARY_MAX_EDGES: usize = 16384;
pub(crate) const SUMMARY_MAX_NODES: usize = 16384;
pub(crate) const SUMMARY_MAX_ARGS: usize = 65536;
/// Words: header, function rows (two uint4 each: library, unit, symbol,
/// first edge; end edge, type mask, constant mask, 0), edge rows (one uint4:
/// callee function or INVALID, type mask, constant mask, first argument),
/// node rows (two uint4: kind | arity << 8, w0, w1, w2; first child,
/// constant mask, 0, 0) and argument words.
pub(crate) const SUMMARY_HEADER_WORDS: usize = 16;
pub(crate) const SUMMARY_FN_BASE: usize = SUMMARY_HEADER_WORDS;
pub(crate) const SUMMARY_EDGE_BASE: usize = SUMMARY_FN_BASE + SUMMARY_MAX_FNS * 8;
pub(crate) const SUMMARY_NODE_BASE: usize = SUMMARY_EDGE_BASE + SUMMARY_MAX_EDGES * 4;
pub(crate) const SUMMARY_ARG_BASE: usize = SUMMARY_NODE_BASE + SUMMARY_MAX_NODES * 8;
pub(crate) const SUMMARY_INPUT_WORDS: usize = SUMMARY_ARG_BASE + SUMMARY_MAX_ARGS;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct SummaryNode {
    kind: u32,
    words: [u32; 3],
    /// Operands that are constants (named nodes and array lengths).
    constant_mask: u32,
    children: Vec<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct SummaryFn {
    symbol: u32,
    type_mask: u32,
    constant_mask: u32,
    /// Every generic call of the function is an edge.
    complete: bool,
    /// This function's edges in `ClosureSummary::edges`.
    edges: std::ops::Range<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct SummaryEdge {
    /// (library, unit, native symbol) of the callee, as `native_target`.
    callee: [u32; 3],
    /// The retained call: the template a decoded instance copies.
    template: CheckedGenericCall,
    type_mask: u32,
    constant_mask: u32,
    /// Node of each binding: type slots, then constant slots.
    arguments: Vec<u32>,
}

/// The closure edges of one library unit.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ClosureSummary {
    unit: [u32; 2],
    /// Sorted by symbol.
    fns: Vec<SummaryFn>,
    edges: Vec<SummaryEdge>,
    nodes: Vec<SummaryNode>,
    heights: Vec<u32>,
    argument_words: usize,
    /// The content digest dependents' cache keys use (`hash_into`).
    digest: [u8; 32],
}

fn low_bits(count: u32) -> u32 {
    if count == 0 { 0 } else { u32::MAX >> (32 - count.min(32)) }
}

#[derive(Default)]
struct NodeTable {
    nodes: Vec<SummaryNode>,
    heights: Vec<u32>,
    index: HashMap<SummaryNode, u32>,
}

impl NodeTable {
    fn intern(&mut self, node: SummaryNode) -> Option<u32> {
        if let Some(&index) = self.index.get(&node) {
            return Some(index);
        }
        let height = 1 + node.children.iter()
            .map(|&child| self.heights[child as usize])
            .max()
            .unwrap_or(0);
        if height > SUMMARY_IMPORT_ROUNDS {
            return None;
        }
        let index = u32::try_from(self.nodes.len()).ok()?;
        self.heights.push(height);
        self.index.insert(node.clone(), index);
        self.nodes.push(node);
        Some(index)
    }

    fn leaf(&mut self, kind: u32, words: [u32; 3]) -> Option<u32> {
        self.intern(SummaryNode { kind, words, constant_mask: 0, children: Vec::new() })
    }

    fn ty(&mut self, ty: &CheckedGenericType) -> Option<u32> {
        match ty {
            CheckedGenericType::Scalar(scalar) => self.leaf(NODE_SCALAR, [*scalar, 0, 0]),
            CheckedGenericType::Parameter(parameter) => {
                (parameter.identity.domain == CheckedParameterDomain::Type
                    && parameter.binding_slot < 32)
                    .then_some(())?;
                self.leaf(NODE_TYPE_SLOT, [parameter.binding_slot, 0, 0])
            }
            CheckedGenericType::Slice(element) | CheckedGenericType::Reference(element) => {
                let child = self.ty(element)?;
                let kind = if matches!(ty, CheckedGenericType::Slice(_)) { NODE_SLICE } else { NODE_REF };
                self.intern(SummaryNode { kind, words: [0; 3], constant_mask: 0, children: vec![child] })
            }
            CheckedGenericType::Array { element, length, .. } => {
                let element = self.ty(element)?;
                let length = self.constant(length)?;
                self.intern(SummaryNode {
                    kind: NODE_ARRAY,
                    words: [0; 3],
                    constant_mask: 2,
                    children: vec![element, length],
                })
            }
            CheckedGenericType::Nominal { identity, arguments, .. } => {
                // A private library type has no identity a dependent can
                // spell; neither has an unscoped one.
                let CheckedNominalIdentity::Public([library, unit, index]) = *identity else {
                    return None;
                };
                (library != INVALID && unit != INVALID && arguments.len() <= NAMED_OPERAND_LIMIT)
                    .then_some(())?;
                let mut constant_mask = 0;
                let mut children = Vec::with_capacity(arguments.len());
                for (operand, argument) in arguments.iter().enumerate() {
                    children.push(match argument {
                        CheckedGenericApplicationArgument::Type(ty) => self.ty(ty)?,
                        CheckedGenericApplicationArgument::Constant(value) => {
                            constant_mask |= 1 << operand;
                            self.constant(value)?
                        }
                    });
                }
                self.intern(SummaryNode {
                    kind: NODE_NAMED,
                    words: [library, unit, index],
                    constant_mask,
                    children,
                })
            }
            CheckedGenericType::Unresolved { .. } => None,
        }
    }

    fn constant(&mut self, value: &CheckedGenericConstantValue) -> Option<u32> {
        match value {
            CheckedGenericConstantValue::Literal(literal) => self.leaf(NODE_LITERAL, literal.words()),
            CheckedGenericConstantValue::Parameter(parameter) => {
                let scalar = parameter.constant_scalar?;
                (parameter.identity.domain == CheckedParameterDomain::Constant
                    && parameter.binding_slot < 32)
                    .then_some(())?;
                self.leaf(NODE_CONST_SLOT, [parameter.binding_slot, scalar, 0])
            }
            CheckedGenericConstantValue::CountProjection { target_scalar, source } => {
                let parameter_scalar = match source.as_ref() {
                    CheckedGenericConstantValue::Parameter(parameter) => parameter.constant_scalar?,
                    _ => 0,
                };
                let child = self.constant(source)?;
                self.intern(SummaryNode {
                    kind: NODE_PROJECTION,
                    words: [*target_scalar, parameter_scalar, 0],
                    constant_mask: 0,
                    children: vec![child],
                })
            }
            CheckedGenericConstantValue::Unresolved { .. } => None,
        }
    }
}

/// (library, unit, symbol) of a retained call's callee, as the dependent
/// spells its own calls into this unit (`native_target`).
fn callee_key(target: CheckedGenericTarget, unit: [u32; 2]) -> [u32; 3] {
    match target {
        CheckedGenericTarget::Dependency { library_id, unit_id, declaration_index } =>
            [library_id, unit_id, declaration_index],
        CheckedGenericTarget::DependencyMethod { library_id, unit_id, method_symbol } =>
            [library_id, unit_id, method_symbol],
        CheckedGenericTarget::Local { native_symbol, .. } => [unit[0], unit[1], native_symbol],
    }
}

impl ClosureSummary {
    /// The summary of one scoped library unit (without functions when it
    /// has no generic caller: an interface without any summary is one built
    /// before this unit's check, and says so). `calls` are its retained
    /// generic calls, `owners` their checked lexical functions and
    /// `contracts` its owner table.
    pub(crate) fn build(
        unit: [u32; 2],
        calls: &[CheckedGenericCall],
        owners: &[CheckedCallOwner],
        contracts: &CheckedUnitContracts,
    ) -> Result<Self, String> {
        // A top-level function's native symbol is the declaration index its
        // dependents call it by (call_dependency_local_index). The summary
        // keys its functions by native symbol, so that is checked, never
        // assumed: a unit where it does not hold has no summary.
        for binder in &contracts.binders {
            if let (None, Some(callable), CheckedBinderIdentity::Public { owner, scope: 0 }) =
                (binder.enclosing_owner, binder.callable, binder.binder)
            {
                if owner != callable.native_symbol {
                    return Err(format!(
                        "public function {owner} has native symbol {}", callable.native_symbol));
                }
            }
        }
        let owner_of = owners.iter()
            .map(|owner| (owner.call_hir, owner.function_hir))
            .collect::<HashMap<_, _>>();
        let binder_of = contracts.binders.iter().enumerate()
            .map(|(index, binder)| (binder.source_hir, index))
            .collect::<HashMap<_, _>>();
        // (native symbol, type mask, constant mask) of each callable owner
        // with a generic environment: its own parameters and every enclosing
        // owner's (an impl method's composed slots).
        let caller = |function_hir: u32| -> Option<(u32, u32, u32)> {
            let index = *binder_of.get(&function_hir)?;
            let symbol = contracts.binders[index].callable?.native_symbol;
            let (mut types, mut constants) = (0u32, 0u32);
            let mut next = Some(index as u32);
            for _ in 0..contracts.binders.len() {
                let Some(owner) = next else { break };
                let binder = contracts.binders.get(owner as usize)?;
                for parameter in &binder.parameters {
                    if parameter.binding_slot >= 32 { return None; }
                    match parameter.identity.domain {
                        CheckedParameterDomain::Type => types |= 1 << parameter.binding_slot,
                        CheckedParameterDomain::Constant => constants |= 1 << parameter.binding_slot,
                    }
                }
                next = binder.enclosing_owner;
            }
            ((types | constants) != 0).then_some((symbol, types, constants))
        };
        let mut table = NodeTable::default();
        // Owner symbol -> (masks, complete, edges in call order). An owner
        // with a call the summary cannot spell is incomplete: dependents
        // neither root nor expand it.
        let mut by_owner = BTreeMap::<u32, (u32, u32, bool, Vec<SummaryEdge>)>::new();
        let mut ordered = calls.iter().collect::<Vec<_>>();
        ordered.sort_by_key(|call| call.call_hir);
        for call in ordered {
            let Some(&function_hir) = owner_of.get(&call.call_hir) else { continue };
            let Some((symbol, owner_types, owner_constants)) = caller(function_hir) else { continue };
            let entry = by_owner.entry(symbol).or_insert((owner_types, owner_constants, true, Vec::new()));
            let (types, constants) = (call.required_generic_parameters, call.required_constant_parameters);
            if (types, constants) == (Some(0), Some(0)) {
                continue;
            }
            let (Some(types), Some(constants)) = (types, constants) else {
                entry.2 = false;
                continue;
            };
            let mut arguments = Vec::with_capacity((types + constants) as usize);
            let spelled = (types <= 32 && constants <= 32 && call.has_all_parameter_slots())
                .then_some(())
                .and_then(|()| call.arguments.iter().try_for_each(|argument| {
                    arguments.push(table.ty(&argument.ty)?);
                    Some(())
                }))
                .and_then(|()| call.constants.iter().try_for_each(|constant| {
                    arguments.push(table.constant(&constant.value)?);
                    Some(())
                }));
            if spelled.is_none() {
                entry.2 = false;
                continue;
            }
            entry.3.push(SummaryEdge {
                callee: callee_key(call.target, unit),
                template: call.clone(),
                type_mask: low_bits(types),
                constant_mask: low_bits(constants),
                arguments,
            });
        }
        let mut fns = Vec::with_capacity(by_owner.len());
        let mut edges = Vec::new();
        for (symbol, (type_mask, constant_mask, complete, owner_edges)) in by_owner {
            let start = edges.len() as u32;
            edges.extend(owner_edges);
            fns.push(SummaryFn { symbol, type_mask, constant_mask, complete, edges: start..edges.len() as u32 });
        }
        let argument_words = edges.iter().map(|edge| edge.arguments.len()).sum::<usize>()
            + table.nodes.iter().map(|node| node.children.len()).sum::<usize>();
        let mut summary = Self {
            unit,
            fns,
            edges,
            nodes: table.nodes,
            heights: table.heights,
            argument_words,
            digest: [0; 32],
        };
        summary.digest = summary.content_digest();
        Ok(summary)
    }

    /// Feed the summary's content into a cache key: a dependent's cached
    /// closure is only as current as the summaries it read, which the
    /// encoded interface does not carry.
    pub(crate) fn hash_into(&self, hasher: &mut blake3::Hasher) {
        hasher.update(&self.digest);
    }

    fn content_digest(&self) -> [u8; 32] {
        let mut hasher = blake3::Hasher::new();
        hasher.update(b"laniusc-closure-summary-v1");
        let words = |hasher: &mut blake3::Hasher, values: &[u32]| {
            hasher.update(&(values.len() as u64).to_le_bytes());
            for value in values {
                hasher.update(&value.to_le_bytes());
            }
        };
        words(&mut hasher, &self.unit);
        for function in &self.fns {
            words(&mut hasher, &[function.symbol, function.type_mask, function.constant_mask,
                u32::from(function.complete), function.edges.start, function.edges.end]);
        }
        for edge in &self.edges {
            words(&mut hasher, &edge.callee);
            words(&mut hasher, &[edge.type_mask, edge.constant_mask]);
            words(&mut hasher, &edge.arguments);
            hasher.update(format!("{:?}", edge.template).as_bytes());
        }
        for node in &self.nodes {
            words(&mut hasher, &[node.kind, node.words[0], node.words[1], node.words[2], node.constant_mask]);
            words(&mut hasher, &node.children);
        }
        *hasher.finalize().as_bytes()
    }

    /// Counts for LANIUS_DEBUG_INSTANCE_CLOSURE.
    pub(crate) fn describe(&self) -> String {
        let incomplete = self.fns.iter().filter(|function| !function.complete).count();
        format!("fns={} incomplete={incomplete} edges={} nodes={}",
            self.fns.len(), self.edges.len(), self.nodes.len())
    }

    /// Heap and inline bytes, for the unit caches' budgets.
    pub(crate) fn resident_bytes(&self) -> usize {
        std::mem::size_of::<Self>()
            + self.fns.capacity() * std::mem::size_of::<SummaryFn>()
            + self.edges.iter().map(|edge| std::mem::size_of::<SummaryEdge>()
                + edge.arguments.capacity() * 4
                + edge.template.resident_argument_bytes()).sum::<usize>()
            + self.nodes.iter().map(|node| std::mem::size_of::<SummaryNode>()
                + node.children.capacity() * 4).sum::<usize>()
            + self.heights.capacity() * 4
    }
}

/// The dependency summaries of one job, merged into the upload
/// (`closure_summary_inputs`): functions sorted by (library, unit, symbol),
/// edge callees resolved to job-wide function indices, node and argument
/// indices made job-wide.
pub(crate) struct JobClosureSummaries {
    /// The dependent job's own (library, unit).
    current_unit: [u32; 2],
    summaries: Vec<Arc<ClosureSummary>>,
    /// (summary, first edge) of each summary, in job edge order.
    edge_starts: Vec<(usize, u32)>,
    header: Vec<u32>,
    fn_words: Vec<u32>,
    edge_words: Vec<u32>,
    node_words: Vec<u32>,
    argument_words: Vec<u32>,
    rounds: u32,
}

impl JobClosureSummaries {
    /// None when no dependency has a summary with a function. A summary of
    /// the job's own unit (`current_unit`) is never its dependency's.
    pub(crate) fn new(
        current_unit: [u32; 2],
        summaries: impl IntoIterator<Item = Arc<ClosureSummary>>,
    ) -> Option<Self> {
        let mut summaries = summaries.into_iter()
            .filter(|summary| !summary.fns.is_empty() && summary.unit != current_unit)
            .collect::<Vec<_>>();
        summaries.sort_by_key(|summary| summary.unit);
        summaries.dedup_by_key(|summary| summary.unit);
        // Whole summaries, in unit order, while every section fits.
        let (mut fns, mut edges, mut nodes, mut arguments) = (0usize, 0usize, 0usize, 0usize);
        summaries.retain(|summary| {
            let fits = fns + summary.fns.len() <= SUMMARY_MAX_FNS
                && edges + summary.edges.len() <= SUMMARY_MAX_EDGES
                && nodes + summary.nodes.len() <= SUMMARY_MAX_NODES
                && arguments + summary.argument_words <= SUMMARY_MAX_ARGS;
            if fits {
                fns += summary.fns.len();
                edges += summary.edges.len();
                nodes += summary.nodes.len();
                arguments += summary.argument_words;
            }
            fits
        });
        if summaries.is_empty() {
            return None;
        }
        // Function rows: every owner and every callee (a leaf callee has
        // no edges of its own, but its instances are what the closure
        // finds), sorted by (library, unit, symbol). An owner row keeps its
        // own masks; a leaf takes its first caller's.
        let mut rows = BTreeMap::<[u32; 3], (u32, u32, u32, Option<(usize, std::ops::Range<u32>)>)>::new();
        for (index, summary) in summaries.iter().enumerate() {
            for function in &summary.fns {
                rows.insert([summary.unit[0], summary.unit[1], function.symbol],
                    (function.type_mask, function.constant_mask,
                        if function.complete { 0 } else { SUMMARY_FN_INCOMPLETE },
                        Some((index, function.edges.clone()))));
            }
        }
        for summary in &summaries {
            for edge in &summary.edges {
                rows.entry(edge.callee).or_insert((edge.type_mask, edge.constant_mask, 0, None));
            }
        }
        if rows.len() > SUMMARY_MAX_FNS {
            return None;
        }
        let keys = rows.keys().copied().collect::<Vec<_>>();
        let mut job = Self {
            current_unit,
            summaries: Vec::new(),
            edge_starts: Vec::new(),
            header: vec![0; SUMMARY_HEADER_WORDS],
            fn_words: Vec::with_capacity((keys.len() + 1) * 8),
            edge_words: Vec::with_capacity(edges * 4),
            node_words: Vec::with_capacity(nodes * 8),
            argument_words: Vec::with_capacity(arguments),
            rounds: 0,
        };
        // Job edges are each summary's edges in unit order; a function's
        // edges stay contiguous, so its row holds (first, end).
        let mut edge_bases = Vec::with_capacity(summaries.len());
        let (mut edge_base, mut node_base) = (0u32, 0u32);
        for (index, summary) in summaries.iter().enumerate() {
            job.edge_starts.push((index, edge_base));
            edge_bases.push(edge_base);
            for edge in &summary.edges {
                let callee = keys.binary_search(&edge.callee).map_or(INVALID, |index| index as u32);
                job.edge_words.extend([callee, edge.type_mask, edge.constant_mask,
                    job.argument_words.len() as u32]);
                job.argument_words.extend(edge.arguments.iter().map(|&node| node_base + node));
            }
            for (node, height) in summary.nodes.iter().zip(&summary.heights) {
                job.node_words.extend([node.kind | ((node.children.len() as u32) << 8),
                    node.words[0], node.words[1], node.words[2],
                    job.argument_words.len() as u32, node.constant_mask, 0, 0]);
                job.argument_words.extend(node.children.iter().map(|&child| node_base + child));
                job.rounds = job.rounds.max(*height);
            }
            edge_base += summary.edges.len() as u32;
            node_base += summary.nodes.len() as u32;
        }
        for (key, (type_mask, constant_mask, flags, owned)) in &rows {
            let (first, end) = owned.as_ref().map_or((0, 0), |(summary, range)|
                (edge_bases[*summary] + range.start, edge_bases[*summary] + range.end));
            job.fn_words.extend([key[0], key[1], key[2], first, end, *type_mask, *constant_mask, *flags]);
        }
        job.header[..9].copy_from_slice(&[
            keys.len() as u32,
            edge_base,
            node_base,
            job.argument_words.len() as u32,
            SUMMARY_FN_BASE as u32,
            SUMMARY_EDGE_BASE as u32,
            SUMMARY_NODE_BASE as u32,
            SUMMARY_ARG_BASE as u32,
            job.rounds,
        ]);
        job.summaries = summaries;
        Some(job)
    }

    /// (word offset, words) of each section to write to the upload buffer.
    pub(crate) fn sections(&self) -> [(usize, &[u32]); 5] {
        [
            (0, &self.header),
            (SUMMARY_FN_BASE, &self.fn_words),
            (SUMMARY_EDGE_BASE, &self.edge_words),
            (SUMMARY_NODE_BASE, &self.node_words),
            (SUMMARY_ARG_BASE, &self.argument_words),
        ]
    }

    /// Import rounds: the deepest node's height.
    pub(crate) fn rounds(&self) -> u32 {
        self.rounds
    }

    pub(crate) fn current_unit(&self) -> [u32; 2] {
        self.current_unit
    }

    /// The library unit and retained template call of job edge `edge`.
    pub(crate) fn edge_template(&self, edge: u32) -> Option<([u32; 2], &CheckedGenericCall)> {
        let position = self.edge_starts.partition_point(|&(_, start)| start <= edge).checked_sub(1)?;
        let (summary, start) = self.edge_starts[position];
        let summary = &self.summaries[summary];
        let edge = summary.edges.get((edge - start) as usize)?;
        Some((summary.unit, &edge.template))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::type_checker::{
        CheckedCallableOwner,
        CheckedContractOwner,
        CheckedGenericArgument,
        CheckedGenericConstant,
        CheckedGenericParameter,
        CheckedParameterIdentity,
    };

    const UNIT: [u32; 2] = [0, 0];

    fn parameter(slot: u32, constant: bool) -> CheckedGenericParameter {
        CheckedGenericParameter {
            identity: CheckedParameterIdentity {
                unit: UNIT,
                binder: CheckedBinderIdentity::SourceLocal { owner_kind: 3, declaration_start_token: 1 },
                domain: if constant { CheckedParameterDomain::Constant } else { CheckedParameterDomain::Type },
                source_ordinal: slot,
            },
            binding_slot: slot,
            constant_scalar: constant.then_some(17),
        }
    }

    fn owner(source_hir: u32, symbol: u32, parameters: Vec<CheckedGenericParameter>) -> CheckedContractOwner {
        CheckedContractOwner {
            source_hir,
            binder: CheckedBinderIdentity::SourceLocal { owner_kind: 3, declaration_start_token: source_hir },
            callable: Some(CheckedCallableOwner { native_symbol: symbol }),
            enclosing_owner: None,
            parameters,
        }
    }

    fn call(call_hir: u32, symbol: u32, argument: CheckedGenericType, length: Option<CheckedGenericConstantValue>)
        -> CheckedGenericCall
    {
        CheckedGenericCall {
            call_hir,
            source_span: [0, 0],
            target: CheckedGenericTarget::Local {
                function_start_token: symbol,
                generic_parameter_count: 1,
                native_symbol: symbol,
                specialization_symbol: symbol,
            },
            arguments: vec![CheckedGenericArgument { slot: 0, ty: argument }],
            constants: length.into_iter().map(|value| CheckedGenericConstant { slot: 0, value }).collect(),
            required_generic_parameters: Some(1),
            required_constant_parameters: Some(0),
        }
    }

    fn summary() -> ClosureSummary {
        // outer<T> (symbol 10, HIR 100) calls mid<T> (symbol 11); mid (HIR
        // 110) calls inner<[T]> (symbol 12) and leaf<Private> (left out).
        let contracts = CheckedUnitContracts {
            binders: vec![
                owner(100, 10, vec![parameter(0, false)]),
                owner(110, 11, vec![parameter(0, false)]),
                owner(120, 12, vec![parameter(0, false)]),
            ],
            ..Default::default()
        };
        let slot = CheckedGenericType::Parameter(parameter(0, false));
        let private = CheckedGenericType::Nominal {
            identity: CheckedNominalIdentity::SourceLocal { unit: UNIT, declaration_token: 5 },
            arguments: Vec::new(),
            words: None,
            local_replay: None,
        };
        let calls = vec![
            call(111, 12, CheckedGenericType::Slice(Box::new(slot.clone())), None),
            call(101, 11, slot.clone(), None),
            call(112, 13, private, None),
        ];
        let owners = [(101, 100), (111, 110), (112, 110)]
            .map(|(call_hir, function_hir)| CheckedCallOwner { call_hir, function_hir });
        ClosureSummary::build(UNIT, &calls, &owners, &contracts).expect("symbols")
    }

    #[test]
    fn summary_keeps_slot_form_edges_by_owner_and_leaves_out_private_types() {
        let summary = summary();
        assert_eq!(summary.fns.iter().map(|function| (function.symbol, function.complete)).collect::<Vec<_>>(),
            [(10, true), (11, false)]);
        assert_eq!(summary.edges.len(), 2);
        assert_eq!(summary.edges[0].callee, [0, 0, 11]);
        assert_eq!(summary.edges[1].callee, [0, 0, 12]);
        // The slot leaf is shared; the slice is one level above it.
        assert_eq!(summary.nodes.len(), 2);
        assert_eq!(summary.nodes[0].kind, NODE_TYPE_SLOT);
        assert_eq!(summary.nodes[1].kind, NODE_SLICE);
        assert_eq!(summary.heights, [1, 2]);
    }

    #[test]
    fn job_upload_resolves_callees_and_maps_edges_back_to_templates() {
        let job = JobClosureSummaries::new([9, 9], [Arc::new(summary())]).expect("job");
        let [header, functions, edges, nodes, arguments] = job.sections().map(|(_, words)| words.to_vec());
        // Rows: outer (10) and mid (11) own an edge each; inner (12) is a
        // leaf callee with none.
        assert_eq!(&header[..4], &[3, 2, 2, 3]);
        assert_eq!(job.rounds(), 2);
        assert_eq!(functions.chunks(8).map(|row| (row[2], row[3], row[4])).collect::<Vec<_>>(),
            [(10, 0, 1), (11, 1, 2), (12, 0, 0)]);
        assert_eq!((edges[0], edges[4]), (1, 2));
        assert_eq!(arguments[edges[3] as usize], 0);
        assert_eq!(arguments[edges[7] as usize], 1);
        assert_eq!(nodes[8] & 0xff, NODE_SLICE);
        assert_eq!(arguments[nodes[8 + 4] as usize], 0);
        assert_eq!(job.edge_template(1).map(|(unit, call)| (unit, call.call_hir)), Some((UNIT, 111)));
        assert!(job.edge_template(2).is_none());
    }
}
