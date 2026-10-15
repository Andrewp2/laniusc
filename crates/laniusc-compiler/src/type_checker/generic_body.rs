//! Closed semantic arguments for replaying one checked generic body.
//!
//! The host validates the retained declaration/argument identity. The GPU
//! substitutes type uses in that declaration's generic scope before normal
//! type-instance collection and native lowering. Optional retained native widths
//! are witnesses, not prerequisites for semantic seeding; GPU layout admission
//! must complete before a replayed native body can be published.

use std::collections::{BTreeMap, BTreeSet};

use anyhow::{Result, anyhow, ensure};

use super::{
    CheckedGenericApplicationArgument,
    CheckedGenericArgument,
    CheckedGenericConstant,
    CheckedGenericType,
};

pub(super) const MAX_BODY_TYPE_ARGUMENTS: usize = 32;
pub(super) const MAX_BODY_TYPE_NODES: usize = 64;
pub(super) const BODY_TYPE_GRAPH_START: usize = MAX_BODY_TYPE_ARGUMENTS * 2 + 1;
pub(super) const BODY_TYPE_EDGE_START: usize = BODY_TYPE_GRAPH_START + MAX_BODY_TYPE_NODES * 2;
pub(super) const MAX_BODY_TYPE_EDGES: usize = MAX_BODY_TYPE_NODES * MAX_BODY_TYPE_ARGUMENTS;
pub(super) const BODY_CONSTANT_START: usize = BODY_TYPE_EDGE_START * 4 + MAX_BODY_TYPE_EDGES;
pub(super) const BODY_SPECIALIZATION_WORDS: usize =
    BODY_CONSTANT_START + 4 + MAX_BODY_TYPE_ARGUMENTS * 4;
/// Bodies one replay can specialize together (see CheckedBodySpecializationBatch).
pub(crate) const MAX_BODY_ENTRIES: usize = 64;
pub(super) const BODY_ENTRY_TABLE_START: usize = BODY_SPECIALIZATION_WORDS / 4;
pub(super) const BODY_ENTRY_ROWS: usize = 1 + 2 * MAX_BODY_TYPE_ARGUMENTS;
pub(super) const BODY_BATCH_WORDS: usize =
    BODY_SPECIALIZATION_WORDS + (MAX_BODY_ENTRIES - 1) * BODY_ENTRY_ROWS * 4;

/// Selects an instance copy's declaration by the source byte of its `fn`
/// keyword (`COPY_TARGET | byte`); 00d2 resolves it to the copy's HIR row.
pub(crate) const BODY_COPY_TARGET: u32 = 0xc000_0000;

#[derive(Clone, Debug)]
pub(crate) struct CheckedBodySpecialization {
    /// Public declaration index, the existing high-bit associated-method
    /// symbol, or an instance copy (BODY_COPY_TARGET).
    pub target_symbol: u32,
    /// Unit whose immutable declarations are available during this replay.
    pub source_unit: [u32; 2],
    pub arguments: Vec<CheckedGenericArgument>,
    pub constants: Vec<CheckedGenericConstant>,
}

impl CheckedBodySpecialization {
    #[cfg(test)]
    pub(crate) fn scheduling_words(&self) -> Result<Vec<u32>> {
        Ok(self.scheduling_environment()?.0)
    }

    /// Scheduling identity contains semantic types and values. The caller
    /// supplies the native callee identity separately; a source-local replay
    /// selector must not split equivalent local and imported environments.
    /// Native widths and replay indexes are separately validated layout facts.
    pub(crate) fn scheduling_environment(&self) -> Result<(Vec<u32>, Vec<u32>)> {
        let packet = self.packet()?; // Validate closure and bounded replay capacity first.
        self.packet_scheduling_environment(&packet)
    }

    fn packet_scheduling_environment(&self, packet: &[u32; BODY_SPECIALIZATION_WORDS]) -> Result<(Vec<u32>, Vec<u32>)> {
        let mut canonical = std::collections::BTreeMap::<Vec<u32>, u32>::new();
        let mut nodes = Vec::new();
        let mut rebased = Vec::new();
        let mut layouts = Vec::new();
        for index in 0..packet[2] as usize {
            let start = (BODY_TYPE_GRAPH_START + index * 2) * 4;
            let node = &packet[start..start + 8];
            let mut key = vec![node[0]];
            match node[0] {
                1 => key.push(node[1]),
                10 => key.extend([node[1], node[2], node[4]]),
                2 => key.extend([rebased[node[1] as usize], node[2]]),
                3 | 4 => key.push(rebased[node[1] as usize]),
                9 => {
                    key.extend_from_slice(&node[4..7]);
                    key.push(node[2]);
                    let edge = BODY_TYPE_EDGE_START * 4 + node[1] as usize;
                    key.extend(
                        packet[edge..edge + node[2] as usize]
                            .iter()
                            .map(|&child| rebased[child as usize]),
                    );
                }
                _ => unreachable!("packet validated complete types"),
            }
            if let Some(&existing) = canonical.get(&key) {
                Self::merge_layout_witnesses(
                    &mut layouts[existing as usize..existing as usize + 1],
                    &node[3..4],
                )?;
                rebased.push(existing);
            } else {
                let new_index = nodes.len() as u32;
                canonical.insert(key.clone(), new_index);
                nodes.push(key);
                layouts.push(node[3]);
                rebased.push(new_index);
            }
        }
        let mut identity = vec![self.arguments.len() as u32, nodes.len() as u32];
        for slot in 0..self.arguments.len() {
            identity.push(rebased[packet[(slot * 2 + 1) * 4 + 2] as usize]);
        }
        for node in nodes {
            identity.push(node.len() as u32);
            identity.extend(node);
        }
        identity.push(self.constants.len() as u32);
        identity.extend(self.constants.iter().flat_map(|argument| {
            argument
                .value
                .literal()
                .expect("packet validated literal constants")
                .words()
        }));
        Ok((identity, layouts))
    }

    /// Canonicalize the GPU's completed seed-node layouts in the same order as
    /// the scheduling identity. This copies admitted results; it computes no
    /// native layout. Known input witnesses must survive unchanged.
    fn admitted_layouts(&self, native: &[u32]) -> Result<Vec<u32>> {
        let mut packet = self.packet()?;
        ensure!(native.len() == packet[2] as usize, "native seed layout count differs from its graph");
        for (index, &width) in native.iter().enumerate() {
            let start = (BODY_TYPE_GRAPH_START + index * 2) * 4;
            if matches!(packet[start], 1 | 10) { continue; }
            ensure!(packet[start + 3] == u32::MAX || packet[start + 3] == width,
                "GPU seed layout conflicts with its retained native witness");
            packet[start + 3] = width;
        }
        Ok(self.packet_scheduling_environment(&packet)?.1)
    }

    /// Unknown witnesses do not conflict with a known width. Two known widths
    /// for one exact semantic environment must agree. Validate before mutating
    /// the retained vector so a failed comparison cannot partially refine it.
    pub(crate) fn merge_layout_witnesses(retained: &mut [u32], incoming: &[u32]) -> Result<()> {
        ensure!(retained.len() == incoming.len(), "semantic layout witness counts differ");
        ensure!(retained.iter().zip(incoming).all(|(&left, &right)|
            left == u32::MAX || right == u32::MAX || left == right),
            "one checked type has inconsistent native layouts");
        for (left, &right) in retained.iter_mut().zip(incoming) {
            if *left == u32::MAX { *left = right; }
        }
        Ok(())
    }

    /// Serialize an exact closed graph. `u32::MAX` in a compound node's width
    /// column means that native layout remains to be computed by the GPU.
    pub(crate) fn packet(&self) -> Result<[u32; BODY_SPECIALIZATION_WORDS]> {
        let (nodes, edges, roots) = self.graph()?;
        let mut words = [0; BODY_SPECIALIZATION_WORDS];
        write_legacy_entry(&mut words, self, &roots);
        write_graph(&mut words, self.source_unit, &nodes, &edges);
        Ok(words)
    }

    /// The closed checked graph in postorder and each type slot's root.
    fn graph(&self) -> Result<(Vec<[u32; 8]>, Vec<u32>, Vec<u32>)> {
        ensure!(
            self.target_symbol != u32::MAX,
            "body specialization target is invalid"
        );
        ensure!(
            (!self.arguments.is_empty() || !self.constants.is_empty())
                && self.arguments.len() <= MAX_BODY_TYPE_ARGUMENTS
                && self.constants.len() <= MAX_BODY_TYPE_ARGUMENTS,
            "body specialization requires a nonempty environment with at most {MAX_BODY_TYPE_ARGUMENTS} arguments in each parameter domain"
        );
        for (slot, argument) in self.constants.iter().enumerate() {
            ensure!(
                argument.slot == slot as u32 && argument.value.literal().is_some(),
                "body specialization has an incomplete constant environment"
            );
        }
        let mut nodes = Vec::new();
        let mut edges = Vec::new();
        let mut roots = Vec::with_capacity(self.arguments.len());
        for (slot, argument) in self.arguments.iter().enumerate() {
            ensure!(
                argument.slot == slot as u32,
                "body specialization has an incomplete slot sequence"
            );
            roots.push(append_checked_node(&argument.ty, &mut nodes, &mut edges)?);
        }
        Ok((nodes, edges, roots))
    }
}

/// Entry 0 of every packet: header, type-slot roots and constant rows.
fn write_legacy_entry(words: &mut [u32], entry: &CheckedBodySpecialization, roots: &[u32]) {
    words[0] = entry.arguments.len() as u32;
    words[1] = entry.target_symbol;
    words[BODY_CONSTANT_START] = entry.constants.len() as u32;
    for (slot, argument) in entry.constants.iter().enumerate() {
        let row = BODY_CONSTANT_START + 4 + slot * 4;
        words[row] = argument.slot;
        words[row + 1..row + 4].copy_from_slice(&argument.value.literal()
            .expect("validated literal constant").words());
    }
    for (slot, &root) in roots.iter().enumerate() {
        let row = (slot * 2 + 1) * 4;
        words[row] = slot as u32;
        words[row + 1] = 10; // private checked graph root
        words[row + 2] = root;
    }
}

fn write_graph(words: &mut [u32], source_unit: [u32; 2], nodes: &[[u32; 8]], edges: &[u32]) {
    words[2] = nodes.len() as u32;
    words[3] = edges.len() as u32;
    for (index, node) in nodes.iter().enumerate() {
        let start = (BODY_TYPE_GRAPH_START + index * 2) * 4;
        words[start..start + 8].copy_from_slice(node);
        // A declaration identity is stable within this exact source unit.
        // An instance row is not: replay may have rebound its arguments.
        // Preserve only the declaration, alongside all structural children.
        if node[0] == 9 && node[4..6] == source_unit {
            words[start + 7] = node[7];
        } else {
            words[start + 7] = u32::MAX;
        }
    }
    let edge_start = BODY_TYPE_EDGE_START * 4;
    words[edge_start..edge_start + edges.len()].copy_from_slice(edges);
}

/// Up to 64 bodies of one source unit replayed by one frontend run. Every
/// entry selects a different lexical scope; entries whose scopes share an
/// enclosing owner must bind that owner's parameters identically (the caller
/// checks this). The entries share one deduplicated seed graph, so seed rows,
/// native seed layouts and their validation are the same as for one entry.
///
/// Packet layout (uint4 rows): entry 0 keeps the single-entry layout. Row
/// 705.y counts the extra entries. Extra entry `e` (1-based) occupies the 65
/// rows from `738 + (e - 1) * 65`: a header (argument count, target symbol,
/// 0, constant count), one row per type slot (slot, 10, root, 0) and one row
/// per constant slot (slot, 10, constant node, 0). An extra entry's constant
/// value is a kind-10 node of the shared graph.
///
/// Instance copies: an entry whose target is `BODY_COPY_TARGET | byte` stores
/// `byte + 1` as its copy word (705.z for entry 0, header .z otherwise), and
/// 705.w holds the first copy row (`set_instance_copies`).
#[derive(Clone, Debug)]
pub(crate) struct CheckedBodySpecializationBatch {
    entries: Vec<CheckedBodySpecialization>,
    /// The first HIR row of the instance copies, 0 without copies.
    copy_first_row: u32,
    nodes: Vec<[u32; 8]>,
    edges: Vec<u32>,
    /// Per entry: the shared root of each type slot.
    roots: Vec<Vec<u32>>,
    /// Per entry: the shared kind-10 node of each constant slot (empty for
    /// entry 0, whose constants use the single-entry rows).
    constant_nodes: Vec<Vec<u32>>,
    /// Per entry: its single-entry graph node ordinal -> shared ordinal.
    shared_by_local: Vec<Vec<u32>>,
}

impl CheckedBodySpecializationBatch {
    pub(crate) fn single(entry: CheckedBodySpecialization) -> Result<Self> {
        let mut batch = Self {
            entries: Vec::new(),
            copy_first_row: 0,
            nodes: Vec::new(),
            edges: Vec::new(),
            roots: Vec::new(),
            constant_nodes: Vec::new(),
            shared_by_local: Vec::new(),
        };
        ensure!(batch.try_push(entry)?, "one body specialization exceeds the packet capacity");
        Ok(batch)
    }

    pub(crate) fn entries(&self) -> &[CheckedBodySpecialization] {
        &self.entries
    }

    /// An instance-copy batch: every entry selects a copy, by increasing
    /// copy byte, and every copy row is at or past `row`. `owners` holds,
    /// per entry, the template function HIR and the template impl HIR of a
    /// method copy.
    pub(crate) fn set_instance_copies(&mut self, row: u32, owners: Vec<(u32, Option<u32>)>) -> Result<()> {
        let bytes = self.entries.iter().map(|entry| {
            ensure!(entry.target_symbol & BODY_COPY_TARGET == BODY_COPY_TARGET,
                "an instance-copy batch entry selects an original declaration");
            Ok(entry.target_symbol & !BODY_COPY_TARGET)
        }).collect::<Result<Vec<_>>>()?;
        ensure!(bytes.windows(2).all(|pair| pair[0] < pair[1]),
            "instance copies are not in increasing source order");
        ensure!(row != 0, "an instance copy cannot be the first HIR row");
        self.copy_first_row = row;
        Ok(())
    }

    #[cfg(test)]
    pub(crate) fn copy_first_row(&self) -> Option<u32> {
        (self.copy_first_row != 0).then_some(self.copy_first_row)
    }

    /// Whether entries `a` and `b` bind one parameter slot to the same
    /// checked type (domain 0, compared as shared graph roots) or constant
    /// value (domain 1). A slot either entry lacks never binds identically.
    pub(crate) fn binds_identically(&self, a: usize, b: usize, slot: u32, domain: u32) -> bool {
        let slot = slot as usize;
        match domain {
            0 => matches!((self.roots[a].get(slot), self.roots[b].get(slot)),
                (Some(left), Some(right)) if left == right),
            1 => match (self.entries[a].constants.get(slot), self.entries[b].constants.get(slot)) {
    /// Per instance-copy entry: the template's function HIR and, for a
    /// method, the template's impl HIR.
    copy_owners: Vec<(u32, Option<u32>)>,
                (Some(left), Some(right)) => left.value.literal().map(|value| value.words())
                    == right.value.literal().map(|value| value.words()),
                _ => false,
            },
            _ => false,
        }
    }

    /// Add one entry if the shared graph has room for it. Returns false and
    /// leaves the batch unchanged when it does not fit; an entry that is
    /// invalid on its own, or that belongs to another unit, is an error.
    pub(crate) fn try_push(&mut self, entry: CheckedBodySpecialization) -> Result<bool> {
        let (local_nodes, local_edges, local_roots) = entry.graph()?;
        if let Some(first) = self.entries.first() {
            ensure!(first.source_unit == entry.source_unit,
                "batched body specializations belong to different source units");
        }
        if self.entries.len() >= MAX_BODY_ENTRIES {
            copy_owners: Vec::new(),
            return Ok(false);
        }
        let mut nodes = self.nodes.clone();
        let mut edges = self.edges.clone();
        let mut shared = Vec::with_capacity(local_nodes.len());
        let rebased = local_nodes.iter().try_for_each(|node| {
            let mut copy = *node;
            let mut children = Vec::new();
            match node[0] {
                2 | 3 | 4 => copy[1] = shared[node[1] as usize],
                9 => children.extend(local_edges[node[1] as usize..(node[1] + node[2]) as usize]
                    .iter().map(|&child| shared[child as usize])),
                _ => {}
            }
            shared.push(intern_checked_node(copy, &children, &mut nodes, &mut edges)?);
            Ok::<(), anyhow::Error>(())
        });
        let mut constants = Vec::new();
        let rebased = rebased.and_then(|()| {
            if self.entries.is_empty() { return Ok(()); }
            for argument in &entry.constants {
                let [scalar, lo, hi] = argument.value.literal()
                    .expect("validated literal constant").words();
                constants.push(intern_checked_node(
                    [10, scalar, lo, 0, hi, 0, 0, 0], &[], &mut nodes, &mut edges)?);
            }
        ensure!(owners.len() == self.entries.len()
            && owners.iter().all(|&(function, implementation)| function < row
                && implementation.is_none_or(|implementation| implementation < row)),
            "instance copies need one template owner each");
            Ok(())
        self.copy_owners = owners;
        });
        if rebased.is_err() {
            return Ok(false);
    /// The template owner of each owner row of the instance copies, for a
    /// replay that checks this batch's copies.
    ///
    /// `callables` are the replay unit's function rows (free functions and
    /// methods), `method_impls` its (method, impl) rows. A copy is exactly
    /// one function (and one impl for a method), appended after the
    /// template in entry order, so the k-th callable row at or past the
    /// first copy row is entry k's copy. Template rows keep their own
    /// identity.
    pub(crate) fn instance_owner_aliases(
        &self,
        callables: &BTreeSet<u32>,
        method_impls: &[(u32, u32)],
    ) -> Result<BTreeMap<u32, u32>> {
        let mut aliases = BTreeMap::new();
        if self.copy_first_row == 0 {
            return Ok(aliases);
        }
        let copies = callables.range(self.copy_first_row..).copied().collect::<Vec<_>>();
        ensure!(copies.len() == self.copy_owners.len(),
            "replay checked {} instance-copy callables for {} copies", copies.len(), self.copy_owners.len());
        let impls = method_impls.iter().copied().collect::<BTreeMap<_, _>>();
        for (&copy, &(function, implementation)) in copies.iter().zip(&self.copy_owners) {
            aliases.insert(copy, function);
            match (impls.get(&copy), implementation) {
                (None, None) => {}
                (Some(&copy_impl), Some(implementation)) => {
                    ensure!(copy_impl >= self.copy_first_row && copy_impl < copy,
                        "instance-copy method {copy} is not inside its own copied impl");
                    ensure!(aliases.insert(copy_impl, implementation).is_none(),
                        "instance-copy impl {copy_impl} owns more than one copy");
                }
                _ => return Err(anyhow!("instance copy {copy} changed between a function and a method")),
            }
        }
        Ok(aliases)
    }

        }
        self.roots.push(local_roots.iter().map(|&root| shared[root as usize]).collect());
        self.nodes = nodes;
        self.edges = edges;
        self.constant_nodes.push(constants);
        self.shared_by_local.push(shared);
        self.entries.push(entry);
        Ok(true)
    }

    /// The uploaded words: exactly the single-entry packet for one entry.
    pub(crate) fn packet(&self) -> Result<Vec<u32>> {
        ensure!(!self.entries.is_empty(), "empty body specialization batch");
        let extra = self.entries.len() - 1;
        let mut words = vec![0; BODY_SPECIALIZATION_WORDS + extra * BODY_ENTRY_ROWS * 4];
        write_legacy_entry(&mut words, &self.entries[0], &self.roots[0]);
        write_graph(&mut words, self.entries[0].source_unit, &self.nodes, &self.edges);
        words[BODY_CONSTANT_START + 1] = extra as u32;
        let copy_word = |entry: &CheckedBodySpecialization| {
            if entry.target_symbol & BODY_COPY_TARGET == BODY_COPY_TARGET {
                (entry.target_symbol & !BODY_COPY_TARGET) + 1
            } else {
                0
            }
        };
        words[BODY_CONSTANT_START + 2] = copy_word(&self.entries[0]);
        words[BODY_CONSTANT_START + 3] = self.copy_first_row;
        for index in 1..self.entries.len() {
            let entry = &self.entries[index];
            let base = (BODY_ENTRY_TABLE_START + (index - 1) * BODY_ENTRY_ROWS) * 4;
            words[base] = entry.arguments.len() as u32;
            words[base + 1] = entry.target_symbol;
            words[base + 2] = copy_word(entry);
            words[base + 3] = entry.constants.len() as u32;
            for (slot, &root) in self.roots[index].iter().enumerate() {
                let row = base + (1 + slot) * 4;
                words[row..row + 3].copy_from_slice(&[slot as u32, 10, root]);
            }
            for (slot, &node) in self.constant_nodes[index].iter().enumerate() {
                let row = base + (1 + MAX_BODY_TYPE_ARGUMENTS + slot) * 4;
                words[row..row + 3].copy_from_slice(&[slot as u32, 10, node]);
            }
        }
        Ok(words)
    }

    /// Per entry, the admitted layouts of its scheduling environment from
    /// the GPU's completed shared seed-node widths.
    fn admitted_layouts(&self, native: &[u32]) -> Result<Vec<Vec<u32>>> {
        ensure!(native.len() == self.nodes.len(), "native seed layout count differs from its graph");
        self.entries.iter().zip(&self.shared_by_local).map(|(entry, shared)| {
            let local = shared.iter().map(|&ordinal| native[ordinal as usize]).collect::<Vec<_>>();
            entry.admitted_layouts(&local)
        }).collect()
    }
}

impl super::GpuTypeChecker {
    /// Called after this replay's successful status readback and before its
    /// retained workspace can be replaced. The seed and native row order are
    /// exact; no source token or host-computed layout is used as a substitute.
    pub(crate) fn retained_body_native_layouts(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        specialization: &CheckedBodySpecializationBatch,
    ) -> Result<Vec<Vec<u32>>> {
        use crate::gpu::readback::{PagedReadback, ReadbackRegion};
        let count = specialization.nodes.len();
        if count == 0 { return specialization.admitted_layouts(&[]); }
        let semantic = self.semantic_artifact()
            .ok_or_else(|| anyhow::anyhow!("body layout has no retained semantic artifact"))?;
        let source_bytes = semantic.type_generic_param_slot.byte_size as u64;
        let readback = PagedReadback::new(device, "body native layouts", count * 4);
        let regions = [ReadbackRegion::from_buffer(
            &semantic.type_instance_native_words, source_bytes, count * 4, "body native layouts",
        )?];
        let bytes = readback.read_regions(device, queue, &regions, "body native layouts")?;
        specialization.admitted_layouts(&super::generic_calls::words(&bytes[0]))
    }
}

/// Postorder graph of complete checked types. A nominal node keeps every
/// ordered child and the declaration's scoped identity independently of width.
fn append_checked_node(
    ty: &CheckedGenericType,
    nodes: &mut Vec<[u32; 8]>,
    edges: &mut Vec<u32>,
) -> Result<u32> {
    let mut node = [0; 8];
    let mut arguments = Vec::new();
    match ty {
        CheckedGenericType::Scalar(code) => {
            ensure!(
                crate::primitive_types::is_known(*code),
                "unsupported body scalar identity {code}"
            );
            node[0] = 1;
            node[1] = *code;
        }
        CheckedGenericType::Nominal {
            identity,
            arguments: children,
            words,
            local_replay,
        } => {
            ensure!(
                children.len() <= MAX_BODY_TYPE_ARGUMENTS,
                "nominal type exceeds {MAX_BODY_TYPE_ARGUMENTS} checked arguments"
            );
            ensure!(words.is_none_or(|width| width <= 0xffff), "invalid checked nominal layout");
            let words = words.unwrap_or(u32::MAX);
            let identity = identity.packet_identity()?;
            for child in children {
                arguments.push(match child {
                    CheckedGenericApplicationArgument::Type(ty) => {
                        append_checked_node(ty, nodes, edges)?
                    }
                    CheckedGenericApplicationArgument::Constant(value) => {
                        let value = value.literal().ok_or_else(|| {
                            anyhow::anyhow!(
                                "body specialization requires a complete nominal constant"
                            )
                        })?;
                        let [scalar, lo, hi] = value.words();
                        intern_checked_node([10, scalar, lo, 0, hi, 0, 0, 0], &[], nodes, edges)?
                    }
                });
            }
            node[0] = 9;
            node[2] = children.len() as u32;
            node[3] = words;
            node[4..7].copy_from_slice(&identity);
            node[7] = local_replay.unwrap_or(u32::MAX);
        }
        CheckedGenericType::Reference(referent) => {
            node[0] = 4;
            node[1] = append_checked_node(referent, nodes, edges)?;
            node[3] = 1;
        }
        CheckedGenericType::Slice(element) => {
            node[0] = 3;
            node[1] = append_checked_node(element, nodes, edges)?;
            node[3] = 3;
        }
        CheckedGenericType::Array {
            element,
            length,
            words,
        } => {
            let length = length.literal().and_then(|value| value.count()).ok_or_else(|| {
                anyhow::anyhow!("checked fixed-array length has no nonnegative u32 count")
            })?;
            ensure!(
                words.is_none_or(|width| width <= 0xffff && (length != 0 || width == 0)),
                "invalid checked fixed-array layout"
            );
            let words = words.unwrap_or(u32::MAX);
            node[0] = 2;
            node[1] = append_checked_node(element, nodes, edges)?;
            node[2] = length;
            node[3] = words;
        }
        _ => anyhow::bail!("body specialization requires a complete checked type; found {ty:?}"),
    }
    intern_checked_node(node, &arguments, nodes, edges)
}

fn intern_checked_node(
    mut node: [u32; 8],
    arguments: &[u32],
    nodes: &mut Vec<[u32; 8]>,
    edges: &mut Vec<u32>,
) -> Result<u32> {
    if let Some(index) = nodes.iter().position(|existing| {
        if node[0] != 9 {
            return existing[..3] == node[..3] && existing[4..] == node[4..];
        }
        existing[0] == node[0] && existing[2] == node[2] && existing[4..] == node[4..] && {
            let start = existing[1] as usize;
            edges.get(start..start + arguments.len()) == Some(arguments)
        }
    }) {
        // Representation availability is not another graph node. Retain one
        // exact node and refine its optional witness without spending capacity.
        CheckedBodySpecialization::merge_layout_witnesses(&mut nodes[index][3..4], &node[3..4])?;
        return Ok(index as u32);
    }
    ensure!(
        nodes.len() < MAX_BODY_TYPE_NODES,
        "body specialization exceeds {MAX_BODY_TYPE_NODES} checked type nodes"
    );
    if node[0] == 9 {
        ensure!(
            arguments.len() <= MAX_BODY_TYPE_EDGES - edges.len(),
            "body specialization exceeds {MAX_BODY_TYPE_EDGES} checked type edges"
        );
        node[1] = edges.len() as u32;
        edges.extend_from_slice(arguments);
    }
    let index = nodes.len() as u32;
    nodes.push(node);
    Ok(index)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::type_checker::{
        CheckedBinderIdentity,
        CheckedGenericConstantValue,
        CheckedGenericParameter,
        CheckedNominalIdentity,
        CheckedParameterDomain,
        CheckedParameterIdentity,
    };

    fn symbolic_parameter(ordinal: u32) -> CheckedGenericParameter {
        CheckedGenericParameter {
            identity: CheckedParameterIdentity {
                unit: [7, 3],
                binder: CheckedBinderIdentity::SourceLocal {
                    owner_kind: 3,
                    declaration_start_token: 40,
                },
                domain: CheckedParameterDomain::Constant,
                source_ordinal: ordinal,
            },
            binding_slot: ordinal,
            constant_scalar: Some(crate::primitive_types::SCALAR_U32),
        }
    }

    #[test]
    fn specialization_identity_excludes_derived_layout_but_retains_full_types() {
        let environment = |ty| CheckedBodySpecialization {
            target_symbol: 7,
            source_unit: [7, 3],
            constants: Vec::new(),
            arguments: vec![CheckedGenericArgument { slot: 0, ty }],
        };
        let first = environment(nominal(vec![CheckedGenericType::Scalar(2)]));
        let different_type = environment(nominal(vec![CheckedGenericType::Scalar(3)]));
        let mut different_layout = first.clone();
        if let CheckedGenericType::Nominal { words, .. } = &mut different_layout.arguments[0].ty {
            *words = Some(3);
        }
        assert_ne!(
            first.scheduling_words().unwrap(),
            different_type.scheduling_words().unwrap()
        );
        assert_eq!(
            first.scheduling_words().unwrap(),
            different_layout.scheduling_words().unwrap()
        );
        assert_ne!(
            first.scheduling_environment().unwrap().1,
            different_layout.scheduling_environment().unwrap().1
        );
        let inconsistent = CheckedBodySpecialization {
            arguments: vec![
                first.arguments[0].clone(),
                CheckedGenericArgument {
                    slot: 1,
                    ty: different_layout.arguments[0].ty.clone(),
                },
            ],
            ..first.clone()
        };
        assert!(
            inconsistent.scheduling_environment().is_err(),
            "one semantic type cannot carry conflicting layouts in the same environment"
        );
        let short = environment(CheckedGenericType::Array {
            element: Box::new(CheckedGenericType::Scalar(2)),
            length: CheckedGenericConstantValue::count_literal(2),
            words: Some(2),
        });
        let long = environment(CheckedGenericType::Array {
            element: Box::new(CheckedGenericType::Scalar(2)),
            length: CheckedGenericConstantValue::count_literal(3),
            words: Some(3),
        });
        assert_ne!(
            short.scheduling_words().unwrap(),
            long.scheduling_words().unwrap()
        );
    }

    #[test]
    fn semantic_seed_preserves_missing_zero_and_known_width_witnesses() {
        let environment = |width| CheckedBodySpecialization {
            target_symbol: 7,
            source_unit: [7, 3],
            constants: Vec::new(),
            arguments: vec![CheckedGenericArgument {
                slot: 0,
                ty: CheckedGenericType::Nominal {
                    identity: CheckedNominalIdentity::SourceLocal {
                        unit: [7, 3], declaration_token: 12,
                    },
                    local_replay: Some(0x2000_000c),
                    arguments: vec![CheckedGenericApplicationArgument::Type(
                        CheckedGenericType::Array {
                            element: Box::new(CheckedGenericType::Scalar(3)),
                            length: CheckedGenericConstantValue::count_literal(0),
                            words: width,
                        },
                    )],
                    words: width,
                },
            }],
        };
        let missing = environment(None);
        let zero = environment(Some(0));
        assert_eq!(missing.scheduling_words().unwrap(), zero.scheduling_words().unwrap());
        for (seed, expected) in [(&missing, u32::MAX), (&zero, 0)] {
            let packet = seed.packet().expect("closed semantic graph");
            let root = (BODY_TYPE_GRAPH_START + packet[6] as usize * 2) * 4;
            assert_eq!(packet[root + 3], expected);
            assert_eq!(packet[root + 7], 0x2000_000c);
        }
        let mut retained = missing.scheduling_environment().unwrap().1;
        let known = zero.scheduling_environment().unwrap().1;
        CheckedBodySpecialization::merge_layout_witnesses(&mut retained, &known).unwrap();
        assert_eq!(retained, known, "zero is a complete native witness");
        let before = retained.clone();
        let mut conflict = known.clone();
        *conflict.last_mut().unwrap() = 1;
        assert!(CheckedBodySpecialization::merge_layout_witnesses(&mut retained, &conflict).is_err());
        assert_eq!(retained, before, "a conflict must not partially refine the cache");
    }

    #[test]
    fn completed_gpu_layouts_replace_unknown_cache_witnesses_before_reuse() {
        let seed = CheckedBodySpecialization {
            target_symbol: 7, source_unit: [7, 3], constants: vec![],
            arguments: vec![CheckedGenericArgument { slot: 0, ty: CheckedGenericType::Array {
                element: Box::new(CheckedGenericType::Scalar(3)),
                length: CheckedGenericConstantValue::count_literal(2), words: None,
            }}],
        };
        let mut admitted = seed.admitted_layouts(&[u32::MAX, 2]).unwrap();
        assert_eq!(admitted, vec![0, 2], "cache records the completed GPU width, not its absent input");
        assert!(CheckedBodySpecialization::merge_layout_witnesses(&mut admitted, &[0, 3]).is_err());
        assert_eq!(admitted, vec![0, 2]);
        let mut witnessed = seed.clone();
        if let CheckedGenericType::Array { words, .. } = &mut witnessed.arguments[0].ty { *words = Some(3); }
        assert!(witnessed.admitted_layouts(&[u32::MAX, 2]).is_err());
    }

    #[test]
    fn constant_environments_keep_values_in_specialization_identity() {
        let empty = CheckedBodySpecialization {
            target_symbol: 7,
            source_unit: [1, 2],
            arguments: Vec::new(),
            constants: vec![CheckedGenericConstant::literal(0, 0)],
        };
        let different = CheckedBodySpecialization {
            constants: vec![CheckedGenericConstant::literal(0, 3)],
            ..empty.clone()
        };
        assert_ne!(
            empty.scheduling_words().unwrap(),
            different.scheduling_words().unwrap()
        );
        let typed = CheckedBodySpecialization {
            arguments: vec![CheckedGenericArgument {
                slot: 0,
                ty: CheckedGenericType::Scalar(3),
            }],
            ..different.clone()
        };
        assert_ne!(
            typed.scheduling_words().unwrap(),
            different.scheduling_words().unwrap()
        );
        for constants in [
            vec![],
            vec![CheckedGenericConstant::literal(1, 3)],
            vec![CheckedGenericConstant { slot: 0,
                value: CheckedGenericConstantValue::Unresolved { kind: 1, payload: u32::MAX } }],
            vec![CheckedGenericConstant {
                slot: 0,
                value: super::super::generic_calls::CheckedGenericConstantValue::Parameter(
                    symbolic_parameter(3),
                ),
            }],
        ] {
            assert!(
                CheckedBodySpecialization {
                    constants,
                    ..empty.clone()
                }
                .packet()
                .is_err()
            );
        }
    }

    #[test]
    fn reference_specializations_keep_referent_identity_and_pointer_width() {
        let first = CheckedGenericType::Nominal {
            identity: CheckedNominalIdentity::Public([7, 2, 19]),
            local_replay: None,
            arguments: vec![CheckedGenericApplicationArgument::Type(
                CheckedGenericType::Scalar(3),
            )],
            words: Some(12),
        };
        let second = CheckedGenericType::Nominal {
            identity: CheckedNominalIdentity::Public([7, 2, 19]),
            local_replay: None,
            arguments: vec![CheckedGenericApplicationArgument::Type(
                CheckedGenericType::Scalar(2),
            )],
            words: Some(12),
        };
        let reference = CheckedGenericType::Reference(Box::new(first.clone()));
        assert_ne!(
            packet(vec![first]).unwrap(),
            packet(vec![reference.clone()]).unwrap()
        );
        assert_ne!(
            packet(vec![reference.clone()]).unwrap(),
            packet(vec![CheckedGenericType::Reference(Box::new(second))]).unwrap(),
        );
        let mut nodes = Vec::new();
        let mut edges = Vec::new();
        let root = append_checked_node(&reference, &mut nodes, &mut edges).unwrap();
        assert_eq!(
            nodes[root as usize][3], 1,
            "a reference stores one pointer regardless of referent size"
        );
        assert_eq!(
            root,
            append_checked_node(&reference, &mut nodes, &mut edges).unwrap()
        );
    }

    #[test]
    fn reference_specializations_reject_unresolved_referents() {
        assert!(
            packet(vec![CheckedGenericType::Reference(Box::new(
                CheckedGenericType::Unresolved {
                    reference_tag: 2,
                    instance_kind: 0
                },
            ))])
            .is_err()
        );
    }

    fn packet(types: Vec<CheckedGenericType>) -> Result<[u32; BODY_SPECIALIZATION_WORDS]> {
        CheckedBodySpecialization {
            target_symbol: 0,
            source_unit: [0, 0],
            constants: Vec::new(),
            arguments: types
                .into_iter()
                .enumerate()
                .map(|(slot, ty)| CheckedGenericArgument {
                    slot: slot as u32,
                    ty,
                })
                .collect(),
        }
        .packet()
    }

    fn nominal(arguments: Vec<CheckedGenericType>) -> CheckedGenericType {
        CheckedGenericType::Nominal {
            identity: CheckedNominalIdentity::Public([7, 3, 11]),
            local_replay: None,
            arguments: arguments
                .into_iter()
                .map(CheckedGenericApplicationArgument::Type)
                .collect(),
            words: Some(2),
        }
    }

    #[test]
    fn replay_keeps_complete_arguments_and_scopes_local_declarations() {
        let specialization = CheckedBodySpecialization {
            target_symbol: 0x4000_0040,
            source_unit: [7, 3],
            constants: Vec::new(),
            arguments: vec![CheckedGenericArgument {
                slot: 0,
                ty: CheckedGenericType::Nominal {
                    identity: CheckedNominalIdentity::SourceLocal {
                        unit: [7, 3],
                        declaration_token: 48,
                    },
                    local_replay: Some(0x2000_0030),
                    arguments: vec![CheckedGenericApplicationArgument::Type(
                        CheckedGenericType::Nominal {
                            arguments: Vec::new(),
                            identity: CheckedNominalIdentity::SourceLocal {
                                unit: [7, 3],
                                declaration_token: 2,
                            },
                            local_replay: Some(0x4000_1002),
                            words: Some(0),
                        },
                    )],
                    words: Some(2),
                },
            }],
        };
        let local = specialization.packet().expect("local structural replay");
        assert_eq!(local[5], 10, "local calls must replay the complete graph");
        let root = (BODY_TYPE_GRAPH_START + local[6] as usize * 2) * 4;
        assert_eq!(local[root + 7], 0x2000_0030);
        assert_eq!(local[root + 2], 1, "retain the nominal argument");
        let edge = BODY_TYPE_EDGE_START * 4 + local[root + 1] as usize;
        let child = (BODY_TYPE_GRAPH_START + local[edge] as usize * 2) * 4;
        assert_eq!(local[child + 7], 0x4000_1002);
        let imported = CheckedBodySpecialization {
            source_unit: [7, 4],
            ..specialization.clone()
        }
        .packet()
        .expect("imported structural replay");
        assert_eq!(
            imported[root + 7],
            u32::MAX,
            "foreign tokens are not local declarations"
        );
        assert_eq!(imported[child + 7], u32::MAX);
        assert_eq!(&local[root..root + 7], &imported[root..root + 7]);
        assert_eq!(&local[child..child + 7], &imported[child..child + 7]);
        let changed = CheckedBodySpecialization {
            arguments: vec![CheckedGenericArgument {
                slot: 0,
                ty: CheckedGenericType::Nominal {
                    identity: CheckedNominalIdentity::SourceLocal {
                        unit: [7, 3],
                        declaration_token: 48,
                    },
                    local_replay: Some(0x2000_0030),
                    arguments: vec![CheckedGenericApplicationArgument::Type(
                        CheckedGenericType::Scalar(3),
                    )],
                    words: Some(2),
                },
            }],
            ..specialization.clone()
        };
        assert_ne!(
            specialization.scheduling_words().unwrap(),
            changed.scheduling_words().unwrap(),
            "equal widths and declaration identity do not erase different arguments"
        );
    }

    #[test]
    fn checked_packets_keep_zero_layouts_distinct_from_missing_layouts() {
        let empty = CheckedGenericType::Nominal {
            arguments: Vec::new(),
            identity: CheckedNominalIdentity::Public([7, 3, 11]),
            local_replay: None,
            words: Some(0),
        };
        let empty_array = CheckedGenericType::Array {
            element: Box::new(CheckedGenericType::Scalar(7)),
            length: CheckedGenericConstantValue::count_literal(0),
            words: Some(0),
        };
        let zero_elements = CheckedGenericType::Array {
            element: Box::new(empty.clone()),
            length: CheckedGenericConstantValue::count_literal(3),
            words: Some(0),
        };
        let left = CheckedGenericType::Nominal {
            identity: CheckedNominalIdentity::Public([7, 3, 12]),
            local_replay: None,
            arguments: vec![CheckedGenericApplicationArgument::Type(
                CheckedGenericType::Scalar(2),
            )],
            words: Some(0),
        };
        let right = CheckedGenericType::Nominal {
            identity: CheckedNominalIdentity::Public([7, 3, 12]),
            local_replay: None,
            arguments: vec![CheckedGenericApplicationArgument::Type(
                CheckedGenericType::Scalar(3),
            )],
            words: Some(0),
        };
        let graph = packet(vec![empty, empty_array, zero_elements, left, right])
            .expect("complete zero layouts");
        assert_ne!(
            graph[30], graph[38],
            "zero width cannot erase type arguments"
        );
        for argument in 0..5 {
            let root = (BODY_TYPE_GRAPH_START + graph[6 + argument * 8] as usize * 2) * 4;
            assert_eq!(graph[root + 3], 0, "zero width survives checked replay");
        }
        for invalid in [
            CheckedGenericType::Nominal {
                arguments: Vec::new(),
                identity: CheckedNominalIdentity::Public([7, 3, 11]),
                local_replay: None,
                words: Some(u32::MAX),
            },
            CheckedGenericType::Array {
                element: Box::new(CheckedGenericType::Scalar(3)),
                length: CheckedGenericConstantValue::count_literal(0),
                words: Some(1),
            },
            CheckedGenericType::Unresolved {
                reference_tag: 3,
                instance_kind: 1,
            },
        ] {
            assert!(
                packet(vec![invalid]).is_err(),
                "an unresolved layout must not become empty"
            );
        }
    }

    #[test]
    fn nominal_packets_keep_ordered_children_and_distinct_equal_width_types() {
        let left = nominal(vec![
            CheckedGenericType::Scalar(3),
            CheckedGenericType::Scalar(2),
        ]);
        let right = nominal(vec![
            CheckedGenericType::Scalar(2),
            CheckedGenericType::Scalar(3),
        ]);
        let graph = packet(vec![left.clone(), right, left]).expect("checked graph");
        let roots = [graph[6], graph[14], graph[22]];
        assert_eq!(roots[0], roots[2], "identical applications reuse one node");
        assert_ne!(
            roots[0], roots[1],
            "equal layouts do not erase ordered arguments"
        );
        for (root, expected) in [(roots[0], [3, 2]), (roots[1], [2, 3])] {
            let node = (BODY_TYPE_GRAPH_START + root as usize * 2) * 4;
            assert_eq!(&graph[node + 4..node + 7], &[7, 3, 11]);
            assert_eq!(graph[node + 2], 2);
            let edge = BODY_TYPE_EDGE_START * 4 + graph[node + 1] as usize;
            for (slot, scalar) in expected.into_iter().enumerate() {
                let child = (BODY_TYPE_GRAPH_START + graph[edge + slot] as usize * 2) * 4;
                assert_eq!(&graph[child..child + 2], &[1, scalar]);
            }
        }
        assert_eq!(graph[3], 4, "repeated applications share their edge list");
    }

    #[test]
    fn nominal_packets_preserve_nested_structural_arguments_and_arity_limit() {
        let child = nominal(vec![CheckedGenericType::Array {
            element: Box::new(CheckedGenericType::Slice(Box::new(
                CheckedGenericType::Scalar(7),
            ))),
            length: CheckedGenericConstantValue::count_literal(2),
            words: Some(4),
        }]);
        let graph = packet(vec![nominal(vec![child; 32])]).expect("32 ordered arguments");
        let root = (BODY_TYPE_GRAPH_START + graph[6] as usize * 2) * 4;
        assert_eq!(graph[root + 2], 32);
        let start = BODY_TYPE_EDGE_START * 4 + graph[root + 1] as usize;
        assert!(
            graph[start..start + 32]
                .iter()
                .all(|child| *child == graph[start])
        );
        let error = packet(vec![nominal(vec![CheckedGenericType::Scalar(3); 33])]).unwrap_err();
        assert!(
            error.to_string().contains("exceeds 32 checked arguments"),
            "{error}"
        );
    }

    #[test]
    fn nominal_constants_keep_value_identity_and_require_closed_domains() {
        use CheckedGenericApplicationArgument as Argument;

        use super::super::generic_calls::CheckedGenericConstantValue as Constant;
        let environment = |arguments| CheckedBodySpecialization {
            target_symbol: 7,
            source_unit: [7, 3],
            constants: Vec::new(),
            arguments: vec![CheckedGenericArgument {
                slot: 0,
                ty: CheckedGenericType::Nominal {
                    identity: CheckedNominalIdentity::Public([7, 3, 11]),
                    local_replay: None,
                    arguments,
                    words: Some(1),
                },
            }],
        };
        let typed = Argument::Type(CheckedGenericType::Scalar(3));
        let zero = environment(vec![
            typed.clone(),
            Argument::Constant(Constant::count_literal(0)),
        ]);
        let three = environment(vec![
            typed.clone(),
            Argument::Constant(Constant::count_literal(3)),
        ]);
        assert_ne!(
            zero.scheduling_words().unwrap(),
            three.scheduling_words().unwrap(),
            "unused constants remain part of nominal identity even at equal widths"
        );
        assert_ne!(
            environment(vec![typed.clone(), typed.clone()])
                .scheduling_words()
                .unwrap(),
            three.scheduling_words().unwrap(),
            "a constant value is not a scalar type code"
        );
        for arguments in [
            vec![
                typed.clone(),
                Argument::Constant(Constant::Parameter(symbolic_parameter(9))),
            ],
            vec![
                typed.clone(),
                Argument::Constant(Constant::Unresolved { kind: 1, payload: u32::MAX }),
            ],
        ] {
            assert!(
                environment(arguments).packet().is_err(),
                "body replay requires complete nominal operands"
            );
        }
    }
    #[test]
    fn semantic_packets_reject_symbolic_graphs_but_preserve_missing_layouts() {
        let mut parameter = symbolic_parameter(0);
        parameter.identity.domain = CheckedParameterDomain::Type;
        parameter.constant_scalar = None;
        let symbolic = CheckedGenericType::Parameter(parameter);
        let no_layout = CheckedGenericType::Nominal {
            identity: CheckedNominalIdentity::Public([7, 3, 11]),
            arguments: vec![],
            words: None,
            local_replay: None,
        };
        for ty in [
            symbolic.clone(),
            CheckedGenericType::Reference(Box::new(symbolic.clone())),
            CheckedGenericType::Slice(Box::new(symbolic)),
            CheckedGenericType::Array {
                element: Box::new(CheckedGenericType::Scalar(3)),
                length: CheckedGenericConstantValue::Parameter(symbolic_parameter(1)),
                words: Some(4),
            },
        ] {
            assert!(
                ty.has_semantic_identity(),
                "a valid semantic graph survives: {ty:?}"
            );
            assert!(
                packet(vec![ty]).is_err(),
                "native replay cannot invent missing concrete facts"
            );
        }
        assert!(no_layout.is_closed());
        assert!(!no_layout.is_native_ready());
        assert!(packet(vec![no_layout, CheckedGenericType::Array {
            element: Box::new(CheckedGenericType::Scalar(3)),
            length: CheckedGenericConstantValue::count_literal(2),
            words: None,
        }]).is_ok(), "native layout admission follows semantic seeding");
    }

    #[test]
    fn public_nominal_identity_excludes_private_replay_anchor() {
        let nominal = |local_replay| CheckedGenericType::Nominal {
            identity: CheckedNominalIdentity::Public([7, 3, 11]),
            arguments: vec![],
            words: Some(2),
            local_replay,
        };
        let environment = |ty| CheckedBodySpecialization {
            target_symbol: 5,
            source_unit: [7, 3],
            constants: vec![],
            arguments: vec![CheckedGenericArgument { slot: 0, ty }],
        };
        let local = environment(nominal(Some(0x2000_0010)));
        let imported = environment(nominal(None));
        assert_eq!(
            local.scheduling_words().unwrap(),
            imported.scheduling_words().unwrap()
        );
        let local_packet = local.packet().unwrap();
        let root = (BODY_TYPE_GRAPH_START + local_packet[6] as usize * 2) * 4;
        assert_eq!(&local_packet[root + 4..root + 7], &[7, 3, 11]);
        assert_eq!(local_packet[root + 7], 0x2000_0010);
        let foreign_packet = CheckedBodySpecialization {
            source_unit: [9, 8],
            ..local
        }
        .packet()
        .unwrap();
        assert_eq!(
            foreign_packet[root + 7],
            u32::MAX,
            "a private replay anchor is activated only by the source unit that owns it"
        );
    }

    #[test]
    fn replay_constant_keys_keep_scalar_high_limb_and_all_value_patterns() {
        use crate::constant_value::CheckedConstantValue;
        use crate::primitive_types::*;
        let values = [
            [SCALAR_U32, u32::MAX, 0],
            [SCALAR_U64, u32::MAX, 0],
            [SCALAR_U64, u32::MAX, u32::MAX],
            [SCALAR_I64, u32::MAX, u32::MAX],
            [SCALAR_F64, 0, 0],
            [SCALAR_F64, 0, 0x8000_0000],
            [SCALAR_F64, 7, 0x7ff8_0000],
            [SCALAR_F64, 8, 0x7ff8_0000],
        ];
        let environment = |words: [u32; 3], nominal: bool| {
            let value = CheckedGenericConstantValue::Literal(
                CheckedConstantValue::from_words(words[0], [words[1], words[2]]).unwrap());
            CheckedBodySpecialization {
                target_symbol: 7, source_unit: [7, 3],
                constants: if nominal { vec![] } else { vec![CheckedGenericConstant { slot: 0, value: value.clone() }] },
                arguments: if nominal { vec![CheckedGenericArgument { slot: 0,
                    ty: CheckedGenericType::Nominal {
                        identity: CheckedNominalIdentity::Public([7, 3, 11]),
                        arguments: vec![CheckedGenericApplicationArgument::Constant(value)],
                        words: Some(0), local_replay: None,
                    },
                }] } else { vec![] },
            }
        };
        for nominal in [false, true] {
            let keys = values.iter().map(|&words| environment(words, nominal)
                .scheduling_words().unwrap()).collect::<std::collections::BTreeSet<_>>();
            assert_eq!(keys.len(), values.len(), "{nominal}: full typed identity");
            let packet = environment(values[2], nominal).packet().unwrap();
            if nominal {
                let start = BODY_TYPE_GRAPH_START * 4;
                assert_eq!([packet[start + 1], packet[start + 2], packet[start + 4]], values[2]);
                assert_eq!(packet[start + 3], 0, "constant bits never occupy native-width witness");
            } else {
                assert_eq!(&packet[BODY_CONSTANT_START + 5..BODY_CONSTANT_START + 8], &values[2]);
            }
        }
    }

    #[test]
    fn replay_array_counts_are_explicit_and_pending_projections_require_gpu_normalization() {
        use crate::constant_value::CheckedConstantValue;
        use crate::primitive_types::*;
        let count = |scalar, bits| CheckedGenericConstantValue::Literal(
            CheckedConstantValue::from_words(scalar, bits).unwrap());
        let array = |length| CheckedGenericType::Array {
            element: Box::new(CheckedGenericType::Nominal {
                identity: CheckedNominalIdentity::Public([7, 3, 11]),
                arguments: vec![], words: Some(0), local_replay: None,
            }), length, words: Some(0),
        };
        assert!(packet(vec![array(count(SCALAR_U32, [u32::MAX, 0]))]).is_ok(),
            "all-ones count is a value, with resource feasibility separate");
        for value in [count(SCALAR_U64, [0, 1]), count(SCALAR_I32, [u32::MAX, 0]),
            count(SCALAR_BOOL, [1, 0]), count(SCALAR_F64, [0, 0])] {
            assert!(packet(vec![array(value)]).is_err());
        }
        let projection = CheckedGenericConstantValue::CountProjection {
            target_scalar: SCALAR_U64,
            source: Box::new(count(SCALAR_U32, [3, 0])),
        };
        let environment = CheckedBodySpecialization {
            target_symbol: 7, source_unit: [7, 3], arguments: vec![],
            constants: vec![CheckedGenericConstant { slot: 0, value: projection.clone() }],
        };
        assert!(environment.packet().is_err(), "host must not evaluate concrete projection");
        assert!(packet(vec![array(projection)]).is_err());
    }

    fn entry(target: u32, types: Vec<CheckedGenericType>, constants: Vec<u32>) -> CheckedBodySpecialization {
        CheckedBodySpecialization {
            target_symbol: target,
            source_unit: [7, 3],
            arguments: types.into_iter().enumerate()
                .map(|(slot, ty)| CheckedGenericArgument { slot: slot as u32, ty }).collect(),
            constants: constants.into_iter().enumerate()
                .map(|(slot, value)| CheckedGenericConstant::literal(slot as u32, value)).collect(),
        }
    }

    fn array_of(element: CheckedGenericType, length: u32, words: Option<u32>) -> CheckedGenericType {
        CheckedGenericType::Array {
            element: Box::new(element),
            length: CheckedGenericConstantValue::count_literal(length),
            words,
        }
    }

    #[test]
    fn single_entry_batch_uploads_the_exact_single_entry_packet() {
        let local = CheckedGenericType::Nominal {
            identity: CheckedNominalIdentity::SourceLocal { unit: [7, 3], declaration_token: 12 },
            local_replay: Some(0x2000_000c),
            arguments: vec![CheckedGenericApplicationArgument::Constant(
                CheckedGenericConstantValue::count_literal(4))],
            words: None,
        };
        for specialization in [
            entry(5, vec![CheckedGenericType::Scalar(3)], vec![]),
            entry(0x8000_0021, vec![nominal(vec![CheckedGenericType::Scalar(2)]), local], vec![9, 0]),
            entry(5, vec![], vec![1]),
            entry(5, vec![array_of(CheckedGenericType::Scalar(3), 2, Some(2)),
                CheckedGenericType::Slice(Box::new(CheckedGenericType::Scalar(3)))], vec![]),
        ] {
            let batch = CheckedBodySpecializationBatch::single(specialization.clone()).unwrap();
            assert_eq!(batch.packet().unwrap(), specialization.packet().unwrap().to_vec());
            let words = specialization.packet().unwrap();
            let native = (0..words[2] as usize).map(|index| {
                let width = words[(BODY_TYPE_GRAPH_START + index * 2) * 4 + 3];
                if width == u32::MAX { 7 } else { width }
            }).collect::<Vec<_>>();
            assert_eq!(native.len(), batch.nodes.len());
            let layouts = batch.admitted_layouts(&native).unwrap();
            assert_eq!(layouts, vec![specialization.admitted_layouts(&native).unwrap()]);
        }
    }

    #[test]
    fn batched_entries_share_one_graph_and_keep_their_own_slots() {
        let scalar = CheckedGenericType::Scalar(3);
        let boxed = nominal(vec![scalar.clone()]);
        let mut batch = CheckedBodySpecializationBatch::single(
            entry(4, vec![boxed.clone(), scalar.clone()], vec![2])).unwrap();
        let before = batch.nodes.len();
        assert!(batch.try_push(entry(9, vec![scalar.clone(), array_of(boxed.clone(), 3, None)], vec![5, 2])).unwrap());
        let words = batch.packet().unwrap();
        assert_eq!(words.len(), BODY_SPECIALIZATION_WORDS + BODY_ENTRY_ROWS * 4);
        // Shared graph: scalar, Box<scalar>, then the new array node and the
        // two constants of the extra entry (2 and 5).
        assert_eq!(before, 2);
        assert_eq!(words[2] as usize, batch.nodes.len());
        assert_eq!(words[BODY_CONSTANT_START], 1, "entry 0 keeps its single-entry constant rows");
        assert_eq!(words[BODY_CONSTANT_START + 1], 1, "one extra entry");
        let base = BODY_ENTRY_TABLE_START * 4;
        assert_eq!(&words[base..base + 4], &[2, 9, 0, 2]);
        let root = |slot: usize| words[base + (1 + slot) * 4 + 2] as usize;
        assert_eq!(&words[base + 4..base + 6], &[0, 10]);
        assert_eq!(root(0), batch.roots[0][1] as usize, "the shared scalar node");
        let array = (BODY_TYPE_GRAPH_START + root(1) * 2) * 4;
        assert_eq!(words[array], 2);
        assert_eq!(words[array + 1], batch.roots[0][0], "array element is the shared Box node");
        assert_eq!(words[array + 2], 3);
        for (slot, value) in [(0usize, 5u32), (1, 2)] {
            let row = base + (1 + MAX_BODY_TYPE_ARGUMENTS + slot) * 4;
            assert_eq!(&words[row..row + 2], &[slot as u32, 10]);
            let node = (BODY_TYPE_GRAPH_START + words[row + 2] as usize * 2) * 4;
            assert_eq!(words[node], 10);
            assert_eq!(words[node + 2], value, "constant value lives in the kind-10 node");
        }
        // Per-entry layouts follow each entry's own single-entry graph order.
        let mut native = vec![1; batch.nodes.len()];
        native[root(1)] = 6;
        native[batch.roots[0][0] as usize] = 2;
        let layouts = batch.admitted_layouts(&native).unwrap();
        assert_eq!(layouts.len(), 2);
        let second = entry(9, vec![scalar.clone(), array_of(boxed.clone(), 3, None)], vec![5, 2]);
        let (_, edges, roots) = second.graph().unwrap();
        assert!(edges.len() <= batch.edges.len());
        let mut local = vec![0; batch.shared_by_local[1].len()];
        for (index, &shared) in batch.shared_by_local[1].iter().enumerate() { local[index] = native[shared as usize]; }
        assert_eq!(layouts[1], second.admitted_layouts(&local).unwrap());
        assert_eq!(roots.len(), 2);
        assert!(!batch.binds_identically(0, 1, 0, 0), "Box<T> and T differ in type slot 0");
        assert!(!batch.binds_identically(0, 1, 0, 1), "constants 2 and 5 differ in slot 0");
    }

    #[test]
    fn batched_bindings_compare_types_by_shared_root_and_constants_by_value() {
        let scalar = CheckedGenericType::Scalar(3);
        let mut batch = CheckedBodySpecializationBatch::single(
            entry(4, vec![array_of(scalar.clone(), 2, None), scalar.clone()], vec![2])).unwrap();
        // The same array with a known width witness is the same checked type.
        assert!(batch.try_push(entry(9, vec![array_of(scalar.clone(), 2, Some(2)), nominal(vec![])], vec![2, 5])).unwrap());
        assert!(batch.binds_identically(0, 1, 0, 0));
        assert!(!batch.binds_identically(0, 1, 1, 0));
        assert!(batch.binds_identically(0, 1, 0, 1));
        assert!(!batch.binds_identically(0, 1, 1, 1), "entry 0 has no constant slot 1");
        assert!(!batch.binds_identically(0, 1, 7, 0), "absent slots never match");
        // Entry 1's known width 2 for the shared array rejects a GPU width of 3.
        let mut native = vec![0; batch.nodes.len()];
        native[batch.roots[0][0] as usize] = 3;
        assert!(batch.admitted_layouts(&native).is_err());
    }

    #[test]
    fn a_full_batch_rejects_an_entry_without_changing() {
        let arrays = |lengths: std::ops::Range<u32>| lengths
            .map(|length| array_of(CheckedGenericType::Scalar(3), length, None)).collect::<Vec<_>>();
        let mut batch = CheckedBodySpecializationBatch::single(entry(1, arrays(1..31), vec![])).unwrap();
        assert!(batch.try_push(entry(2, arrays(31..61), vec![])).unwrap());
        assert_eq!(batch.nodes.len(), 61);
        let before = batch.packet().unwrap();
        assert!(!batch.try_push(entry(3, arrays(61..91), vec![])).unwrap(), "64 shared nodes");
        assert!(!batch.try_push(entry(3, vec![], vec![1, 2, 3, 4])).unwrap(), "constants are nodes too");
        assert_eq!(batch.packet().unwrap(), before);
        assert_eq!(batch.entries().len(), 2);
        assert!(batch.try_push(entry(3, arrays(1..3), vec![7, 8])).unwrap(), "reused nodes need no room");

        let mut many = CheckedBodySpecializationBatch::single(entry(0, vec![CheckedGenericType::Scalar(3)], vec![])).unwrap();
        for target in 1..MAX_BODY_ENTRIES as u32 {
            assert!(many.try_push(entry(target, vec![CheckedGenericType::Scalar(3)], vec![])).unwrap());
        }
        assert!(!many.try_push(entry(99, vec![CheckedGenericType::Scalar(3)], vec![])).unwrap());
        assert_eq!(many.packet().unwrap().len(), BODY_BATCH_WORDS);
        let mut foreign = entry(5, vec![CheckedGenericType::Scalar(3)], vec![]);
        foreign.source_unit = [7, 4];
        assert!(batch.try_push(foreign).is_err(), "one batch replays one source unit");
    }
    #[test]
    fn instance_copy_entries_store_their_copy_bytes_and_first_row() {
        let scalar = CheckedGenericType::Scalar(3);
        let mut batch = CheckedBodySpecializationBatch::single(
            entry(BODY_COPY_TARGET | 400, vec![scalar.clone()], vec![])).unwrap();
        assert!(batch.try_push(entry(BODY_COPY_TARGET | 520, vec![nominal(vec![scalar.clone()])], vec![])).unwrap());
        assert_eq!(batch.copy_first_row(), None);
        assert!(batch.set_instance_copies(77, vec![(3, None)]).is_err(), "one template owner per copy");
        batch.set_instance_copies(77, vec![(3, None), (9, Some(8))]).unwrap();
        assert_eq!(batch.copy_first_row(), Some(77));
        let words = batch.packet().unwrap();
        assert_eq!(words[1], BODY_COPY_TARGET | 400, "the target keeps the unresolved selector");
        assert_eq!(&words[BODY_CONSTANT_START + 1..BODY_CONSTANT_START + 4], &[1, 401, 77]);
        let base = BODY_ENTRY_TABLE_START * 4;
        assert_eq!(&words[base..base + 4], &[1, BODY_COPY_TARGET | 520, 521, 0]);

        // Ordinary entries have no copy word and no first copy row.
        let plain = CheckedBodySpecializationBatch::single(entry(5, vec![scalar.clone()], vec![])).unwrap();
        assert_eq!(&plain.packet().unwrap()[BODY_CONSTANT_START + 2..BODY_CONSTANT_START + 4], &[0, 0]);
        let mut mixed = plain.clone();
        assert!(mixed.try_push(entry(BODY_COPY_TARGET | 9, vec![scalar.clone()], vec![])).unwrap());
        assert!(mixed.set_instance_copies(4, vec![(1, None), (2, None)]).is_err(),
            "every entry of a copy batch is a copy");
        let mut unordered = CheckedBodySpecializationBatch::single(
            entry(BODY_COPY_TARGET | 600, vec![scalar.clone()], vec![])).unwrap();
        assert!(unordered.try_push(entry(BODY_COPY_TARGET | 500, vec![scalar], vec![])).unwrap());
        assert!(unordered.set_instance_copies(4, vec![(1, None), (2, None)]).is_err(),
            "copies follow source order");
    }
    #[test]
    fn instance_copy_owners_map_to_their_templates_in_entry_order() {
        let scalar = CheckedGenericType::Scalar(3);
        let mut batch = CheckedBodySpecializationBatch::single(
            entry(BODY_COPY_TARGET | 400, vec![scalar.clone()], vec![])).unwrap();
        assert!(batch.try_push(entry(BODY_COPY_TARGET | 520, vec![scalar.clone()], vec![])).unwrap());
        // Template: free function 3, method 9 of impl 8. Copies start at row 40:
        // free copy at 41, then impl copy 50 holding method copy 52.
        batch.set_instance_copies(40, vec![(3, None), (9, Some(8))]).unwrap();
        let callables = BTreeSet::from([3, 9, 12, 41, 52]);
        let methods = [(9, 8), (52, 50)];
        let aliases = batch.instance_owner_aliases(&callables, &methods).unwrap();
        assert_eq!(aliases, BTreeMap::from([(41, 3), (50, 8), (52, 9)]));
        // A missing copy, or a method copy checked as a free function, fails.
        assert!(batch.instance_owner_aliases(&BTreeSet::from([3, 41]), &methods).is_err());
        assert!(batch.instance_owner_aliases(&callables, &[(9, 8)]).is_err());
        // Batches without copies alias nothing.
        let plain = CheckedBodySpecializationBatch::single(entry(5, vec![scalar], vec![])).unwrap();
        assert!(plain.instance_owner_aliases(&callables, &methods).unwrap().is_empty());
    }
}
