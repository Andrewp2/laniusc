use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    path::PathBuf,
    sync::Arc,
};

use anyhow::{Result, anyhow, ensure};

use super::{
    super::typecheck::{CompiledSourcePackUnit, OriginalUnitFacts},
    abi::*,
    catalog::*,
    dispatch::GpuProofReadback,
    proof_store::{OwnedProofRoot, PROOF_STORE_TABLES, ProofStoreSession},
};
use crate::type_checker::{CheckedGenericCall, CheckedGenericTarget};

#[cfg(test)]
#[path = "packet_tests.rs"]
mod tests;

/// Results may only be copied after the orchestrator has observed successful
/// GPU catalog, batch, context and call status for this exact Submission.
/// Its constructor is deliberately at this module boundary, not a public API.
#[derive(Clone, Debug)]
pub(in crate::compiler::gpu_compiler) struct ValidatedEvidence {
    epoch: u64,
    arena_id: u64,
    input_row: u32,
    pub predicate_identity: StableWitnessIdentity,
    /// The catalog predicate (table 8) this proof concludes.
    pub predicate_row: u32,
    /// The catalog implementation (table 9) the GPU selected for an
    /// implementation proof; None for an assumption proof. A copied GPU fact:
    /// the host never selects an implementation.
    pub implementation: Option<u32>,
    /// None: the GPU refuted this obligation under a soft context. It holds the
    /// obligation's place in the evidence order and proves nothing.
    proof: Option<OwnedProofRoot>,
}

impl ValidatedEvidence {
    pub fn is_concrete(&self) -> bool {
        self.proof.as_ref().is_some_and(|proof| proof.is_concrete())
    }
    /// The GPU refuted this obligation under a soft context: it has no proof.
    pub fn is_refuted(&self) -> bool {
        self.proof.is_none()
    }
}

/// Source identity is diagnostic data, never authority to replay a body.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::compiler::gpu_compiler) struct SourceCallIdentity {
    pub snapshot: FrozenSnapshotId,
    pub actual_function_hir: u32,
    pub call_hir: u32,
}

struct CallOccurrence {
    row: u32,
    facts: Arc<[CheckedGenericCall]>,
    fact_index: usize,
}

/// Minted only for a GPU-admitted occurrence in this exact retained arena.
#[derive(Clone)]
pub(in crate::compiler::gpu_compiler) struct AdmittedCall {
    catalog: Arc<FrozenCatalog>,
    arena_id: u64,
    row: u32,
    source: SourceCallIdentity,
    facts: Arc<[CheckedGenericCall]>,
    fact_index: usize,
    concrete: bool,
    refuted: bool,
}

impl AdmittedCall {
    pub fn source(&self) -> SourceCallIdentity {
        self.source
    }
    pub fn checked_call(&self) -> &CheckedGenericCall {
        &self.facts[self.fact_index]
    }
    pub fn is_concrete(&self) -> bool {
        self.concrete
    }
    /// The GPU refuted an obligation of this call's soft context (call status
    /// 8, or a sibling of one): the call is not admitted and is never concrete.
    pub fn is_refuted(&self) -> bool {
        self.refuted
    }
}

/// Owns diagnostic provenance even after a failed submission poisons its arena.
/// This error context cannot authorize a replay or admit a call.
#[derive(Clone)]
pub(in crate::compiler::gpu_compiler) struct RetainedCallSite {
    catalog: Arc<FrozenCatalog>,
    snapshot: u32,
    source: SourceCallIdentity,
    facts: Arc<[CheckedGenericCall]>,
    fact_index: usize,
}

impl RetainedCallSite {
    pub fn source(&self) -> SourceCallIdentity {
        self.source
    }
    pub fn source_unit(&self) -> [u32; 2] {
        self.catalog.snapshots[self.snapshot as usize].unit
    }
    pub fn source_texts(&self) -> &[String] {
        &self.catalog.snapshots[self.snapshot as usize].sources
    }
    pub fn source_paths(&self) -> &[Option<PathBuf>] {
        &self.catalog.snapshots[self.snapshot as usize].source_paths
    }
    pub fn checked_call(&self) -> &CheckedGenericCall {
        &self.facts[self.fact_index]
    }
}

impl std::fmt::Debug for RetainedCallSite {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        std::fmt::Debug::fmt(&self.source, f)
    }
}

impl std::fmt::Display for RetainedCallSite {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "retained call {} in source owner {} of snapshot {}",
            self.source.call_hir, self.source.actual_function_hir, self.source.snapshot.0
        )
    }
}

impl std::error::Error for RetainedCallSite {}

pub(in crate::compiler::gpu_compiler) struct ReplayContextInput<'a> {
    pub snapshot: u32,
    pub selected_owner_hir: u32,
    /// Definition predicate order, selected owner then lexical ancestors.
    pub evidence: &'a [ValidatedEvidence],
    pub origin_call: u32,
}

#[derive(Clone, Debug)]
pub(in crate::compiler::gpu_compiler) struct Submission {
    pub epoch: u64,
    pub arena_id: u64,
    pub serial: u32,
    pub call_span: Span,
    pub context_span: Span,
    pub obligation_span: Span,
    /// GPU insertion dispatch range. Growth changes bucket partitioning and
    /// requires all active assumption rows; otherwise only appended rows.
    pub assumption_index_span: Span,
    pub plan: UploadPlan,
}

pub(in crate::compiler::gpu_compiler) struct ProgramPacket {
    pub catalog: Arc<FrozenCatalog>,
    pub tables: Tables,
    /// The dispatcher retains the corresponding physical arena. This unique
    /// ledger keeps accepted closure bounds monotone through growth and replay.
    pub(super) proof_store: ProofStoreSession,
    atoms: Atoms,
    prefix: [u32; TABLE_COUNT],
    arena: AppendArena,
    outputs: OutputArena,
    submitted_counts: [u32; TABLE_COUNT],
    next_serial: u32,
    arena_id: u64,
    /// A packet is poisoned if a partially appended input fails validation.
    /// Callers must drop it; partial rows are never launchable.
    poisoned: bool,
    awaiting_result: Option<u32>,
    // Point lookups only (never iterated), so hashed.
    original_contexts: HashMap<(u32, u32), u32>,
    original_units: BTreeSet<u32>,
    call_occurrences: HashMap<(u32, u32), CallOccurrence>,
    admitted_calls: HashMap<u32, u32>,
    /// (replay context, call HIR) -> actual function HIR for the calls a
    /// replay context owns outside its template's frozen call inventory
    /// (`append_context_calls`).
    context_call_owners: BTreeMap<(u32, u32), u32>,
    /// Host encodings already written by this packet (`environment`,
    /// `call_predicates`); they change no row.
    encodings: EnvironmentEncodings,
}

/// The environment rows (tables 7, 12 and 11) a call's checked bindings
/// encode to are a function of the callee owner and the call's arguments,
/// constants and required parameter counts, given this packet's frozen
/// catalog and atoms (interning is idempotent). Thousands of call sites share
/// a few environments, so the first site of each is encoded in full and the
/// rest copy its rows; every call still gets its own environment, call and
/// obligation rows, so the GPU sees exactly the tables the full encoding
/// writes. Only environments whose graph copy writes no compound (table 5)
/// or edge (table 6) row are reused. Lives for one packet (one job).
///
/// `LANIUS_EVIDENCE_ENCODING_MEMO=0` encodes every call in full.
/// `LANIUS_CHECK_EVIDENCE_ENCODING_MEMO=1` encodes every call in full and
/// fails the append if a reusable encoding would have written other rows.
struct EnvironmentEncodings {
    enabled: bool,
    checked: bool,
    by_owner: HashMap<u32, Vec<EnvironmentEncoding>>,
    predicates: HashMap<u32, Arc<[u32]>>,
}

struct EnvironmentEncoding {
    facts: Arc<[CheckedGenericCall]>,
    fact_index: usize,
    /// Table-7 root rows, in the order the full encoding writes them.
    roots: Vec<[u32; 2]>,
    /// Table-12 rows as (parameter atom, index into `roots`), in row order.
    bindings: Vec<(u32, usize)>,
}

impl EnvironmentEncodings {
    fn new() -> Self {
        Self {
            enabled: crate::gpu::env::env_bool_truthy("LANIUS_EVIDENCE_ENCODING_MEMO", true),
            checked: crate::gpu::env::env_bool_truthy("LANIUS_CHECK_EVIDENCE_ENCODING_MEMO", false),
            by_owner: HashMap::new(),
            predicates: HashMap::new(),
        }
    }

    fn find(&self, owner: u32, call: &CheckedGenericCall) -> Option<usize> {
        if !self.enabled { return None; }
        self.by_owner.get(&owner)?.iter().position(|known| {
            let known = &known.facts[known.fact_index];
            known.required_generic_parameters == call.required_generic_parameters
                && known.required_constant_parameters == call.required_constant_parameters
                && known.arguments == call.arguments
                && known.constants == call.constants
        })
    }
}

impl ProgramPacket {
    /// Copy one exact retained identity tuple. This does not perform structural
    /// type comparison or confer admission on an unsubmitted atom.
    pub(super) fn retained_atom_key(&self, atom: u32) -> Result<[u32; 8]> {
        self.atoms.keys.get(atom as usize).copied()
            .ok_or_else(|| anyhow!("layout references an absent retained atom"))
    }

    pub fn new(catalog: Arc<FrozenCatalog>) -> Result<Self> {
        let mut prefix = [0; TABLE_COUNT];
        for (table, count) in prefix.iter_mut().enumerate() {
            *count = catalog.tables.count(table)?;
        }
        let arena_id = owned_id()?;
        let (proof_store, _) =
            ProofStoreSession::allocate(catalog.epoch, arena_id, 1, [0; PROOF_STORE_TABLES])?;
        Ok(Self {
            atoms: catalog.atoms.clone(),
            catalog,
            tables: Tables::default(),
            prefix,
            arena: AppendArena::default(),
            outputs: OutputArena::default(),
            submitted_counts: [0; TABLE_COUNT],
            next_serial: 1,
            arena_id,
            proof_store,
            poisoned: false,
            awaiting_result: None,
            original_contexts: HashMap::new(),
            original_units: BTreeSet::new(),
            call_occurrences: HashMap::new(),
            admitted_calls: HashMap::new(),
            context_call_owners: BTreeMap::new(),
            encodings: EnvironmentEncodings::new(),
        })
    }
    fn ready(&self) -> Result<()> {
        ensure!(
            !self.poisoned,
            "evidence packet contains failed partial input"
        );
        ensure!(
            self.awaiting_result.is_none(),
            "prior evidence submission has no terminal result"
        );
        Ok(())
    }
    fn append_guard<T>(&mut self, f: impl FnOnce(&mut Self) -> Result<T>) -> Result<T> {
        self.ready()?;
        let result = f(self);
        if result.is_err() {
            self.poisoned = true;
        }
        result
    }
    fn combined_row(&self, table: usize, row: u32) -> Result<&[u32]> {
        if row < self.prefix[table] {
            self.catalog.tables.row(table, row)
        } else {
            self.tables.row(table, row - self.prefix[table])
        }
    }
    fn graph_copier(&mut self) -> GraphCopier<'_> {
        GraphCopier::new(
            &self.catalog.snapshot_by_unit,
            &mut self.atoms,
            &mut self.tables,
            self.prefix,
        )
    }

    pub fn original_context(&mut self, snapshot: u32, actual_function_hir: u32) -> Result<u32> {
        self.append_guard(|this| this.original_context_inner(snapshot, actual_function_hir))
    }
    fn original_context_inner(&mut self, snapshot: u32, actual_function_hir: u32) -> Result<u32> {
        ensure!(
            (snapshot as usize) < self.catalog.snapshots.len(),
            "context snapshot absent"
        );
        if let Some(&row) = self.original_contexts.get(&(snapshot, actual_function_hir)) {
            return Ok(row);
        }
        let owner = if actual_function_hir == INVALID {
            INVALID
        } else {
            self.catalog.owner(snapshot, actual_function_hir)?
        };
        if owner != INVALID {
            ensure!(
                self.catalog.callable_by_owner.contains_key(&owner),
                "actual caller is not a retained callable"
            );
        }
        let predicates = if owner == INVALID {
            Vec::new()
        } else {
            self.catalog.applicable_predicates(owner)?
        };
        let context = self.tables.count(13)?;
        let first = self.tables.count(14)?;
        for predicate in &predicates {
            self.tables
                .push(14, &[context, *predicate, INVALID, INVALID, 0, 0])?;
        }
        self.tables.push(
            13,
            &[
                snapshot,
                owner,
                INVALID,
                if predicates.is_empty() { 0 } else { first },
                u32_len(predicates.len(), "assumptions")?,
                if owner == INVALID { 2 } else { 0 },
                INVALID,
                0,
            ],
        )?;
        self.original_contexts
            .insert((snapshot, actual_function_hir), context);
        Ok(context)
    }
    /// Marks a pending context soft (row word 7), for tests of the soft
    /// obligation class. Production soft contexts are written as such when
    /// they are appended.
    #[cfg(test)]
    pub fn mark_context_soft(&mut self, context: u32) -> Result<()> {
        self.tables.row_mut(13, context)?[7] = 1;
        Ok(())
    }

    pub fn replay_context(&mut self, input: ReplayContextInput<'_>) -> Result<u32> {
        self.append_guard(|this| {
            let owner = this
                .catalog
                .owner(input.snapshot, input.selected_owner_hir)?;
            ensure!(
                this.catalog.callable_by_owner.contains_key(&owner),
                "selected body is not callable"
            );
            let origin = this.tables.row(15, input.origin_call)?;
            ensure!(
                this.admitted_calls.get(&input.origin_call) == Some(&1),
                "body replay requires a GPU-checked concrete origin call"
            );
            ensure!(
                this.catalog.tables.row(4, origin[3])?[1] == owner,
                "replay origin calls a different definition"
            );
            let origin_environment = origin[4];
            let predicates = this.catalog.applicable_predicates(owner)?;
            ensure!(
                predicates.len() == input.evidence.len(),
                "replay evidence count differs from selected owner requirements"
            );
            // The complete immutable origin environment is the only authority,
            // including unused/unconstrained parameters. An independent call
            // argument list could differ while satisfying the same predicates.
            let context = this.tables.count(13)?;
            let environment = this.body_environment(origin_environment, owner, context)?;
            let first = this.tables.count(14)?;
            for (predicate, evidence) in predicates.iter().zip(input.evidence) {
                ensure!(
                    evidence.epoch == this.catalog.epoch && evidence.arena_id == this.arena_id,
                    "replay evidence from a different catalog or row arena"
                );
                // The source evidence goal need not use this body's predicate ID:
                // the GPU compares it under its retained source environment.
                let proof = evidence
                    .proof
                    .as_ref()
                    .ok_or_else(|| anyhow!("refuted evidence cannot authorize a replay"))?;
                let row: [u32; 8] = this.tables.row(17, evidence.input_row)?.try_into()?;
                proof.require_concrete(&this.proof_store)?;
                ensure!(
                    proof.matches_evidence(row),
                    "retained evidence does not name its accepted proof and conclusion"
                );
                this.tables.push(
                    14,
                    &[context, *predicate, environment, evidence.input_row, 0, 0],
                )?;
            }
            this.tables.push(
                13,
                &[
                    input.snapshot,
                    owner,
                    environment,
                    if predicates.is_empty() { 0 } else { first },
                    u32_len(predicates.len(), "replay assumptions")?,
                    1,
                    input.origin_call,
                    0,
                ],
            )?;
            Ok(context)
        })
    }

    /// Original inputs carry no object or replay authority. Exact immutable
    /// snapshot identity covers the complete retained occurrence inventory,
    /// including the empty case, before any original call rows are appended.
    pub fn append_original_unit_calls(&mut self, facts: &OriginalUnitFacts) -> Result<Span> {
        self.append_guard(|this| {
            let interface = facts.interface();
            let key = [interface.library_id, interface.unit_id];
            let snapshot = *this
                .catalog
                .snapshot_by_unit
                .get(&key)
                .ok_or_else(|| anyhow!("original unit absent from frozen catalog"))?;
            let frozen = &this.catalog.snapshots[snapshot as usize];
            ensure!(
                frozen.original_facts.same_snapshot(facts),
                "original facts are not the frozen immutable source snapshot"
            );
            let owners = frozen.call_owner_by_hir.clone();
            ensure!(
                this.original_units.insert(snapshot),
                "original unit inventory was already appended"
            );
            this.append_call_inventory(
                snapshot, facts.generic_calls().clone(), owners, &BTreeMap::new(), &BTreeSet::new(),
            )
        })
    }

    /// A replay reparse is routed by its admitted selected owner. All other
    /// occurrences must equal already admitted original siblings byte for byte.
    #[cfg(test)]
    pub fn append_replay_unit_calls(
        &mut self,
        unit: &CompiledSourcePackUnit,
        selected_hir: u32,
        context: u32,
    ) -> Result<Span> {
        self.append_replay_batch_calls(unit, &BTreeMap::from([(selected_hir, context)]))
    }

    /// A batched replay reparse: each selected owner HIR routes its calls to
    /// its own replay context. A selected body may hold generic calls its
    /// template does not: a bound-member call whose concrete receiver selects
    /// a generic impl method (methods/09). They join that body's context
    /// (`append_context_calls`).
    pub fn append_replay_batch_calls(
        &mut self,
        unit: &CompiledSourcePackUnit,
        selected: &BTreeMap<u32, u32>,
    ) -> Result<Span> {
        self.append_guard(|this| {
            let unit_key = [unit.interface.library_id, unit.interface.unit_id];
            let snapshot = *this
                .catalog
                .snapshot_by_unit
                .get(&unit_key)
                .ok_or_else(|| anyhow!("call unit absent from frozen catalog"))?;
            let frozen = &this.catalog.snapshots[snapshot as usize];
            ensure!(
                Arc::ptr_eq(&frozen.contracts, &unit.checked_contracts)
                    && Arc::ptr_eq(&frozen.sources, &unit.template_sources)
                    && frozen.source_paths.as_ref() == unit.template_source_paths.as_ref()
                    && Arc::ptr_eq(&frozen.dependency_pages, &unit.template_dependency_pages),
                "call unit does not retain frozen definition provenance"
            );
            // No fresh public interface definitions are consumed here. The
            // frozen catalog alone supplies callable aliases and requirements.
            let owner_by_call = accepted_call_owners(unit)?;
            ensure!(
                frozen
                    .call_owner_by_hir
                    .iter()
                    .all(|(call, owner)| owner_by_call.get(call) == Some(owner)),
                "reparse changed the complete original call occurrence inventory"
            );
            ensure!(!selected.is_empty(), "replay reparse selects no body");
            // Calls the template lacks, grouped by their selected owner.
            let mut added = BTreeMap::<u32, Vec<usize>>::new();
            let mut added_hirs = BTreeSet::new();
            for (index, call) in unit.generic_calls.iter().enumerate() {
                if frozen.call_owner_by_hir.contains_key(&call.call_hir) { continue; }
                let owner = owner_by_call[&call.call_hir];
                ensure!(selected.contains_key(&owner),
                    "reparse added a generic call outside the selected body");
                added.entry(owner).or_default().push(index);
                added_hirs.insert(call.call_hir);
            }
            let first = this.tables.count(15)?;
            this.append_call_inventory(
                snapshot,
                unit.generic_calls.clone(),
                owner_by_call,
                selected,
                &added_hirs,
            )?;
            for (owner, indices) in &added {
                this.append_context_calls_inner(
                    snapshot,
                    selected[owner],
                    *owner,
                    unit.generic_calls.clone(),
                    indices,
                )?;
            }
            Span::new(first, this.tables.count(15)? - first)
        })
    }

    /// Append the instance closure's origin calls of `snapshot` (D1): each
    /// fact becomes the one call of a fresh no-owner context (kind 2, no
    /// assumptions), so its call HIR may repeat a frozen occurrence. A
    /// callee whose owner chain has requirements is left out: its origin
    /// needs evidence, which the closure cannot supply. Returns each appended
    /// fact's index and context.
    pub fn append_closure_calls(
        &mut self,
        snapshot: u32,
        facts: Arc<[CheckedGenericCall]>,
    ) -> Result<Vec<(usize, u32)>> {
        self.append_guard(|this| {
            ensure!(
                (snapshot as usize) < this.catalog.snapshots.len(),
                "closure call snapshot absent"
            );
            let mut appended = Vec::new();
            for (index, call) in facts.iter().enumerate() {
                let Ok(callable) = this.resolve_target(snapshot, call.target) else { continue };
                // A bounded callee's predicates join this batch as obligations
                // of a soft context (word 7 = 1): a refuted bound demotes only
                // this prediction to the replay rounds, never the batch.
                let callee_owner = this.catalog.tables.row(4, callable)?[1];
                let class = u32::from(!this.catalog.applicable_predicates(callee_owner)?.is_empty());
                let context = this.tables.count(13)?;
                this.tables.push(13, &[snapshot, INVALID, INVALID, 0, 0, 2, INVALID, class])?;
                ensure!(
                    this.context_call_owners.insert((context, call.call_hir), INVALID).is_none(),
                    "closure context already owns its call"
                );
                this.append_call(snapshot, context, INVALID, facts.clone(), index)?;
                appended.push((index, context));
            }
            Ok(appended)
        })
    }

    /// The admitted closure call of `context` (`append_closure_calls`).
    pub fn admitted_closure_call(&self, snapshot: u32, context: u32, call_hir: u32) -> Result<AdmittedCall> {
        self.ready()?;
        ensure!(
            self.context_call_owners.get(&(context, call_hir)) == Some(&INVALID),
            "context does not own a closure call"
        );
        self.admitted_occurrence(snapshot, context, call_hir, INVALID)
    }

    /// Append calls that replay context `context` owns outside its template's
    /// frozen call inventory: each fact at `fact_indices` becomes a call row
    /// of that context, owned by `owner_hir` (the context's selected body).
    /// `admitted_context_calls` returns them once the GPU admits them.
    /// Replay routes its added calls through `append_replay_batch_calls`;
    /// this entry point is for the calls of copied instance bodies.
    pub fn append_context_calls(
        &mut self,
        snapshot: u32,
        context: u32,
        owner_hir: u32,
        facts: Arc<[CheckedGenericCall]>,
        fact_indices: &[usize],
    ) -> Result<Span> {
        self.append_guard(|this| {
            this.append_context_calls_inner(snapshot, context, owner_hir, facts, fact_indices)
        })
    }

    fn append_context_calls_inner(
        &mut self,
        snapshot: u32,
        context: u32,
        owner_hir: u32,
        facts: Arc<[CheckedGenericCall]>,
        fact_indices: &[usize],
    ) -> Result<Span> {
        let catalog = self.catalog.clone();
        let frozen = catalog
            .snapshots
            .get(snapshot as usize)
            .ok_or_else(|| anyhow!("context call snapshot absent"))?;
        let owner = catalog.owner(snapshot, owner_hir)?;
        let row = self.tables.row(13, context)?;
        ensure!(
            catalog.callable_by_owner.contains_key(&owner)
                && row[0] == snapshot
                && row[1] == owner
                && row[5] == 1,
            "replay context does not own the selected lexical body"
        );
        let first = self.tables.count(15)?;
        for &index in fact_indices {
            let call_hir = facts
                .get(index)
                .ok_or_else(|| anyhow!("context call index absent"))?
                .call_hir;
            ensure!(
                !frozen.call_owner_by_hir.contains_key(&call_hir)
                    && self.context_call_owners.insert((context, call_hir), owner_hir).is_none(),
                "context call is already a retained occurrence"
            );
            self.append_call(snapshot, context, owner_hir, facts.clone(), index)?;
        }
        Span::new(first, self.tables.count(15)? - first)
    }

    fn append_call_inventory(
        &mut self,
        snapshot: u32,
        facts: Arc<[CheckedGenericCall]>,
        owner_by_call: BTreeMap<u32, u32>,
        selected_replay: &BTreeMap<u32, u32>,
        // Calls the caller appends as context calls instead.
        context_owned: &BTreeSet<u32>,
    ) -> Result<Span> {
        // Validate the routing authority before examining calls. An empty
        // body or a wrong selected HIR must not bypass this check merely
        // because every encountered call belongs to an original sibling.
        for (&selected_hir, &context) in selected_replay {
            let selected_owner = self.catalog.owner(snapshot, selected_hir)?;
            ensure!(
                self.catalog.callable_by_owner.contains_key(&selected_owner),
                "selected replay owner is not an accepted callable"
            );
            let row = self.tables.row(13, context)?;
            ensure!(
                row[0] == snapshot && row[1] == selected_owner && row[5] == 1,
                "replay context does not own the selected lexical body"
            );
        }
        let first = self.tables.count(15)?;
        for (fact_index, call) in facts.iter().enumerate() {
            if context_owned.contains(&call.call_hir) { continue; }
            let actual_hir = *owner_by_call
                .get(&call.call_hir)
                .ok_or_else(|| anyhow!("checked call missing actual owner"))?;
            let context = match selected_replay.get(&actual_hir) {
                Some(&context) => context,
                None => self.original_context_inner(snapshot, actual_hir)?,
            };
            // Only already GPU-admitted original sibling occurrences can be
            // reused during this exact immutable-source reparse.
            if let Some(prior) = self.call_occurrences.get(&(context, call.call_hir)) {
                ensure!(
                    !selected_replay.is_empty()
                        && self.tables.row(13, context)?[5] != 1
                        && matches!(self.admitted_calls.get(&prior.row), Some(1 | 2)),
                    "duplicate call occurrence is not an admitted original sibling"
                );
                ensure!(
                    prior.facts.get(prior.fact_index) == Some(call),
                    "UNSUPPORTED: body replay changed a non-selected callable's checked call facts"
                );
                continue;
            }
            self.append_call(snapshot, context, actual_hir, facts.clone(), fact_index)?;
        }
        // The full inventory is consumed before original or replay publication.
        Span::new(first, self.tables.count(15)? - first)
    }
    fn append_call(
        &mut self,
        snapshot: u32,
        context: u32,
        actual_hir: u32,
        facts: Arc<[CheckedGenericCall]>,
        fact_index: usize,
    ) -> Result<u32> {
        let call = facts
            .get(fact_index)
            .ok_or_else(|| anyhow!("checked call index absent"))?;
        let callable = self.resolve_target(snapshot, call.target)?;
        let callee_owner = self.catalog.tables.row(4, callable)?[1];
        let call_row = self.tables.count(15)?;
        let environment = self.environment(callee_owner, &facts, fact_index, call_row)?;
        let predicates = self.call_predicates(callee_owner)?;
        let first = self.tables.count(16)?;
        for predicate in predicates.iter() {
            self.tables
                .push(16, &[call_row, *predicate, environment, 0])?;
        }
        let actual_owner = if actual_hir == INVALID {
            INVALID
        } else {
            self.catalog.owner(snapshot, actual_hir)?
        };
        self.tables.push(
            15,
            &[
                context,
                call.call_hir,
                actual_owner,
                callable,
                environment,
                if predicates.is_empty() { 0 } else { first },
                u32_len(predicates.len(), "call obligations")?,
                0,
            ],
        )?;
        let key = (context, call.call_hir);
        ensure!(
            self.call_occurrences
                .insert(
                    key,
                    CallOccurrence {
                        row: call_row,
                        facts,
                        fact_index
                    }
                )
                .is_none(),
            "duplicate call occurrence"
        );
        Ok(call_row)
    }

    /// Resolves each original source occurrence to its admitted original or
    /// selected replay context, preserving the exact producer facts for it.
    pub fn admitted_unit_calls(
        &self,
        snapshot: u32,
        selected_replay: Option<(u32, u32)>,
    ) -> Result<Vec<AdmittedCall>> {
        self.admitted_batch_calls(snapshot, &selected_replay.into_iter().collect::<BTreeMap<_, _>>())
    }

    /// Every admitted call of the unit; calls in a selected owner HIR use
    /// that owner's replay context.
    pub fn admitted_batch_calls(
        &self,
        snapshot: u32,
        selected_replay: &BTreeMap<u32, u32>,
    ) -> Result<Vec<AdmittedCall>> {
        self.ready()?;
        let frozen = self
            .catalog
            .snapshots
            .get(snapshot as usize)
            .ok_or_else(|| anyhow!("call snapshot absent"))?;
        for (&selected_hir, &context) in selected_replay {
            let selected_owner = self.catalog.owner(snapshot, selected_hir)?;
            let row = self.tables.row(13, context)?;
            ensure!(
                self.catalog.callable_by_owner.contains_key(&selected_owner)
                    && row[0] == snapshot
                    && row[1] == selected_owner
                    && row[5] == 1,
                "replay context does not own the selected lexical body"
            );
        }
        frozen
            .original_calls
            .iter()
            .map(|call| {
                let actual_hir = *frozen
                    .call_owner_by_hir
                    .get(&call.call_hir)
                    .ok_or_else(|| anyhow!("original call has no accepted owner"))?;
                let context = match selected_replay.get(&actual_hir) {
                    Some(&context) => context,
                    None => *self
                        .original_contexts
                        .get(&(snapshot, actual_hir))
                        .ok_or_else(|| anyhow!("original call context absent"))?,
                };
                self.admitted_occurrence(snapshot, context, call.call_hir, actual_hir)
            })
            .collect()
    }

    /// The admitted calls that replay context `context` owns outside its
    /// template's inventory (`append_context_calls`), in call HIR order.
    pub fn admitted_context_calls(&self, snapshot: u32, context: u32) -> Result<Vec<AdmittedCall>> {
        self.ready()?;
        self.context_call_owners
            .range((context, 0)..=(context, u32::MAX))
            .map(|(&(_, call_hir), &actual_hir)| {
                self.admitted_occurrence(snapshot, context, call_hir, actual_hir)
            })
            .collect()
    }

    fn admitted_occurrence(
        &self,
        snapshot: u32,
        context: u32,
        call_hir: u32,
        actual_hir: u32,
    ) -> Result<AdmittedCall> {
        let frozen = self
            .catalog
            .snapshots
            .get(snapshot as usize)
            .ok_or_else(|| anyhow!("call snapshot absent"))?;
        let occurrence = self
            .call_occurrences
            .get(&(context, call_hir))
            .ok_or_else(|| anyhow!("call occurrence was not retained"))?;
        let state = *self
            .admitted_calls
            .get(&occurrence.row)
            .ok_or_else(|| anyhow!("call occurrence is not GPU-admitted"))?;
        ensure!(matches!(state, 1 | 2 | 8), "call has no successful GPU state");
        let site = self.retained_call_site(occurrence.row)?;
        ensure!(
            site.snapshot == snapshot
                && site.source
                    == SourceCallIdentity {
                        snapshot: frozen.id,
                        actual_function_hir: actual_hir,
                        call_hir,
                    },
            "call context belongs to another source occurrence"
        );
        Ok(AdmittedCall {
            catalog: self.catalog.clone(),
            arena_id: self.arena_id,
            row: occurrence.row,
            source: site.source,
            facts: site.facts,
            fact_index: site.fact_index,
            concrete: state == 1,
            refuted: state == 8,
        })
    }

    /// Diagnostic lookup deliberately works after poisoning. Exact integer and
    /// owned-fact joins locate the source; this does not assert GPU admission.
    pub fn retained_call_site(&self, call_row: u32) -> Result<RetainedCallSite> {
        let call = self.tables.row(15, call_row)?;
        let context = self.tables.row(13, call[0])?;
        let snapshot = context[0];
        let frozen = self
            .catalog
            .snapshots
            .get(snapshot as usize)
            .ok_or_else(|| anyhow!("call context source snapshot absent"))?;
        let actual_hir = match self.context_call_owners.get(&(call[0], call[1])) {
            Some(&owner) => owner,
            None => *frozen
                .call_owner_by_hir
                .get(&call[1])
                .ok_or_else(|| anyhow!("retained call has no accepted source owner"))?,
        };
        let actual_owner = if actual_hir == INVALID {
            INVALID
        } else {
            self.catalog.owner(snapshot, actual_hir)?
        };
        ensure!(
            call[2] == actual_owner
                && context[1] == actual_owner
                && if actual_hir == INVALID {
                    context[5] == 2
                } else {
                    matches!(context[5], 0 | 1)
                },
            "retained call context has another actual source owner"
        );
        let occurrence = self
            .call_occurrences
            .get(&(call[0], call[1]))
            .ok_or_else(|| anyhow!("retained source occurrence absent"))?;
        let fact = occurrence
            .facts
            .get(occurrence.fact_index)
            .ok_or_else(|| anyhow!("retained call producer fact absent"))?;
        ensure!(
            occurrence.row == call_row && fact.call_hir == call[1],
            "retained call row lost its exact source occurrence"
        );
        Ok(RetainedCallSite {
            catalog: self.catalog.clone(),
            snapshot,
            source: SourceCallIdentity {
                snapshot: frozen.id,
                actual_function_hir: actual_hir,
                call_hir: call[1],
            },
            facts: occurrence.facts.clone(),
            fact_index: occurrence.fact_index,
        })
    }

    /// Exact identity joins only. Goal equality and concrete selection have
    /// already run on the GPU; symbolic admission cannot authorize replay.
    pub fn replay_origin(&self, origin: &AdmittedCall) -> Result<(u32, u32, u32, Span)> {
        self.ready()?;
        ensure!(
            Arc::ptr_eq(&origin.catalog, &self.catalog) && origin.arena_id == self.arena_id,
            "call proof belongs to another catalog or arena"
        );
        ensure!(
            origin.concrete && self.admitted_calls.get(&origin.row) == Some(&1),
            "body replay requires a GPU-checked concrete origin"
        );
        let site = self.retained_call_site(origin.row)?;
        ensure!(
            site.source == origin.source
                && site.fact_index == origin.fact_index
                && Arc::ptr_eq(&site.facts, &origin.facts),
            "call proof lost its exact source identity or producer facts"
        );
        let call = self.tables.row(15, origin.row)?;
        let owner = self.catalog.tables.row(4, call[3])?[1];
        let definition = self.catalog.tables.row(2, owner)?;
        Ok((
            origin.row,
            definition[1],
            definition[2],
            Span::new(call[5], call[6])?,
        ))
    }

    fn resolve_target(&self, current_snapshot: u32, target: CheckedGenericTarget) -> Result<u32> {
        let (snapshot, symbol) = match target {
            CheckedGenericTarget::Local { native_symbol, .. } => (current_snapshot, native_symbol),
            CheckedGenericTarget::Dependency {
                library_id,
                unit_id,
                declaration_index,
            } => (
                *self
                    .catalog
                    .snapshot_by_unit
                    .get(&[library_id, unit_id])
                    .ok_or_else(|| anyhow!("callee unit outside frozen catalog"))?,
                declaration_index,
            ),
            CheckedGenericTarget::DependencyMethod {
                library_id,
                unit_id,
                method_symbol,
            } => (
                *self
                    .catalog
                    .snapshot_by_unit
                    .get(&[library_id, unit_id])
                    .ok_or_else(|| anyhow!("method unit outside frozen catalog"))?,
                method_symbol,
            ),
        };
        self.catalog
            .callable_by_native
            .get(&(snapshot, symbol))
            .copied()
            .ok_or_else(|| anyhow!("checked target has no exact callable owner"))
    }
    /// The callee owner's applicable predicates (a frozen-catalog function).
    fn call_predicates(&mut self, owner: u32) -> Result<Arc<[u32]>> {
        if !self.encodings.enabled {
            return Ok(self.catalog.applicable_predicates(owner)?.into());
        }
        if let Some(predicates) = self.encodings.predicates.get(&owner) {
            return Ok(predicates.clone());
        }
        let predicates: Arc<[u32]> = self.catalog.applicable_predicates(owner)?.into();
        self.encodings.predicates.insert(owner, predicates.clone());
        Ok(predicates)
    }

    /// One call's environment rows (see `EnvironmentEncodings`).
    fn environment(
        &mut self,
        owner: u32,
        facts: &Arc<[CheckedGenericCall]>,
        fact_index: usize,
        call_row: u32,
    ) -> Result<u32> {
        let call = facts.get(fact_index).ok_or_else(|| anyhow!("checked call index absent"))?;
        let known = self.encodings.find(owner, call);
        if let Some(index) = known && !self.encodings.checked {
            let Self { encodings, tables, prefix, .. } = self;
            let encoding = &encodings.by_owner[&owner][index];
            let base = add(prefix[7], tables.count(7)?, "environment roots")?;
            for root in &encoding.roots {
                tables.push(7, root)?;
            }
            let environment = tables.count(11)?;
            let first = tables.count(12)?;
            for &(atom, position) in &encoding.bindings {
                let root = add(base, u32_len(position, "environment root")?, "environment root")?;
                tables.push(12, &[environment, atom, root, 0])?;
            }
            tables.push(11, &[
                owner,
                if encoding.bindings.is_empty() { 0 } else { first },
                u32_len(encoding.bindings.len(), "bindings")?,
                1,
                call_row,
            ])?;
            return Ok(environment);
        }
        let before = [5, 6, 7, 12].map(|table| self.tables.count(table));
        let environment = self.encoded_environment(owner, call, call_row)?;
        if !self.encodings.enabled {
            return Ok(environment);
        }
        let [nodes, edges, roots, bindings] = before.map(|count| count.unwrap_or(u32::MAX));
        if self.tables.count(5)? != nodes || self.tables.count(6)? != edges {
            // A compound graph's rows are positional; it is encoded in full.
            return Ok(environment);
        }
        let base = add(self.prefix[7], roots, "environment roots")?;
        let written_roots = (roots..self.tables.count(7)?)
            .map(|row| Ok(self.tables.row(7, row)?.try_into().unwrap()))
            .collect::<Result<Vec<[u32; 2]>>>()?;
        let written_bindings = (bindings..self.tables.count(12)?)
            .map(|row| {
                let row = self.tables.row(12, row)?;
                let position = row[2].checked_sub(base)
                    .filter(|&position| (position as usize) < written_roots.len())
                    .ok_or_else(|| anyhow!("environment binding outside its own roots"))?;
                Ok((row[1], position as usize))
            })
            .collect::<Result<Vec<_>>>()?;
        match known {
            Some(index) => {
                let encoding = &self.encodings.by_owner[&owner][index];
                ensure!(
                    encoding.roots == written_roots && encoding.bindings == written_bindings,
                    "[evidence-encoding-memo] MISMATCH: call HIR {} encodes other environment rows than call HIR {}",
                    call.call_hir,
                    encoding.facts[encoding.fact_index].call_hir
                );
            }
            None => self.encodings.by_owner.entry(owner).or_default().push(EnvironmentEncoding {
                facts: facts.clone(),
                fact_index,
                roots: written_roots,
                bindings: written_bindings,
            }),
        }
        Ok(environment)
    }

    fn encoded_environment(&mut self, owner: u32, call: &CheckedGenericCall, call_row: u32) -> Result<u32> {
        ensure!(
            call.has_all_parameter_slots(),
            "checked call has incomplete generic parameter metadata"
        );
        let parameters = self.catalog.composed_parameters(owner)?;
        let mut type_args = BTreeMap::new();
        let mut constants = BTreeMap::new();
        for arg in &call.arguments {
            ensure!(
                arg.slot < 32 && type_args.insert(arg.slot, &arg.ty).is_none(),
                "duplicate/out-of-range checked type slot"
            );
        }
        for arg in &call.constants {
            ensure!(
                arg.slot < 32 && constants.insert(arg.slot, &arg.value).is_none(),
                "duplicate/out-of-range checked constant slot"
            );
        }
        let mut rows = Vec::with_capacity(parameters.len());
        let mut consumed_type = BTreeSet::new();
        let mut consumed_constant = BTreeSet::new();
        for p in parameters {
            let root = match p[3] {
                0 => {
                    ensure!(
                        consumed_type.insert(p[2]),
                        "two exact type parameters share a composed slot"
                    );
                    let value = type_args
                        .get(&p[2])
                        .ok_or_else(|| anyhow!("missing checked type binding"))?;
                    self.graph_copier().root(value)?
                }
                1 => {
                    ensure!(
                        consumed_constant.insert(p[2]),
                        "two exact constants share a composed slot"
                    );
                    let value = *constants
                        .get(&p[2])
                        .ok_or_else(|| anyhow!("missing checked constant binding"))?;
                    self.graph_copier().constant_root(value)?
                }
                _ => return Err(anyhow!("invalid parameter domain")),
            };
            rows.push((p[1], root));
        }
        ensure!(
            consumed_type.len() == type_args.len() && consumed_constant.len() == constants.len(),
            "extraneous checked environment binding"
        );
        rows.sort_by_key(|r| r.0);
        ensure!(
            rows.windows(2).all(|w| w[0].0 != w[1].0),
            "duplicate exact parameter key"
        );
        let environment = self.tables.count(11)?;
        let first = self.tables.count(12)?;
        for &(atom, root) in &rows {
            self.tables.push(12, &[environment, atom, root, 0])?;
        }
        self.tables.push(
            11,
            &[
                owner,
                if rows.is_empty() { 0 } else { first },
                u32_len(rows.len(), "bindings")?,
                1,
                call_row,
            ],
        )?;
        Ok(environment)
    }

    fn body_environment(&mut self, original: u32, owner: u32, context: u32) -> Result<u32> {
        let source: [u32; 5] = self.tables.row(11, original)?.try_into().unwrap();
        ensure!(
            source[0] == owner && source[3] == 1,
            "origin environment has a different owner/form"
        );
        let environment = self.tables.count(11)?;
        let first = self.tables.count(12)?;
        for index in source[1]..add(source[1], source[2], "origin bindings")? {
            let binding: [u32; 4] = self.tables.row(12, index)?.try_into().unwrap();
            ensure!(
                binding[0] == original,
                "origin binding has a different environment"
            );
            self.tables
                .push(12, &[environment, binding[1], binding[2], 0])?;
        }
        self.tables.push(
            11,
            &[
                owner,
                if source[2] == 0 { 0 } else { first },
                source[2],
                0,
                context,
            ],
        )?;
        Ok(environment)
    }

    /// Produces upload/copy plans only. The caller must finish GPU catalog
    /// admission/coherence before submitting a batch, then check all phase
    /// statuses. This method never declares a call valid.
    pub fn prepare_submission(&mut self) -> Result<Submission> {
        self.append_guard(|this| {
            ensure!(
                this.original_units.len() == this.catalog.snapshots.len(),
                "program packet is missing an original unit call inventory"
            );
            let atom_first = this.prefix[1] as usize + this.tables.count(1)? as usize;
            for key in &this.atoms.keys[atom_first..] {
                this.tables.push(1, key)?;
            }
            for table in CATALOG_ONLY {
                ensure!(
                    this.tables.count(table)? == 0,
                    "catalog-only table in batch suffix"
                );
            }
            let mut counts = [0; TABLE_COUNT];
            for (t, c) in counts.iter_mut().enumerate() {
                *c = this.tables.count(t)?;
            }
            let (copies, mut writes) = this.arena.prepare(&this.tables)?;
            let catalog_index_rows = this.prefix[1].max(this.prefix[9]);
            let output_counts = [
                1,
                this.prefix[9],
                counts[13],
                counts[16],
                counts[15],
                counts[16],
                catalog_index_rows,
                buckets(catalog_index_rows)?,
                counts[14],
                buckets(counts[14])?,
                1,
                this.prefix[9],
                buckets(catalog_index_rows)?,
            ];
            let (output_copies, mut initialize_outputs) = this.outputs.prepare(output_counts)?;
            // Assumption index is rebuilt for the full active assumption set
            // when bucket count changes; previous bucket hash partitioning is
            // not reusable after growth. No implementation index is rebuilt.
            let prior_assumptions = this.submitted_counts[14];
            let rebuild_assumptions = buckets(prior_assumptions)? != buckets(counts[14])?;
            if rebuild_assumptions {
                initialize_outputs.retain(|r| r.table != 8 && r.table != 9);
                initialize_outputs.push(OutputRange {
                    table: 8,
                    first_row: 0,
                    row_count: counts[14],
                });
                initialize_outputs.push(OutputRange {
                    table: 9,
                    first_row: 0,
                    row_count: output_counts[9],
                });
            }
            let serial = this.next_serial;
            this.next_serial = this
                .next_serial
                .checked_add(1)
                .ok_or_else(|| anyhow!("packet serial exhausted"))?;
            let mut header = vec![
                MAGIC,
                VERSION,
                this.catalog.epoch as u32,
                (this.catalog.epoch >> 32) as u32,
                serial,
                TABLE_COUNT as u32,
                DIRECTORY_WORD,
                OUTPUT_DIRECTORY_WORD,
            ];
            for table in 0..TABLE_COUNT {
                let c = this.catalog.slices[table];
                let b = this.arena.slices[table];
                header.extend([
                    c.offset,
                    c.count,
                    b.offset,
                    b.count,
                    b.capacity,
                    WIDTHS[table],
                ]);
            }
            for table in 0..OUTPUT_COUNT {
                let catalog = matches!(table, 0 | 1 | 6 | 7 | 11 | 12);
                let s = if catalog {
                    this.catalog.outputs[table]
                } else {
                    this.outputs.slices[table]
                };
                header.extend([
                    if catalog { 0 } else { 1 },
                    s.offset,
                    s.count,
                    s.capacity,
                    OUTPUT_WIDTHS[table],
                ]);
            }
            ensure!(
                header.len() == BATCH_FIXED_WORDS as usize,
                "wrong packet directory width"
            );
            writes.push(ArenaWrite {
                first_word: 0,
                words: header,
            });
            let result = Submission {
                epoch: this.catalog.epoch,
                arena_id: this.arena_id,
                serial,
                call_span: Span::new(
                    this.submitted_counts[15],
                    counts[15] - this.submitted_counts[15],
                )?,
                context_span: Span::new(
                    this.submitted_counts[13],
                    counts[13] - this.submitted_counts[13],
                )?,
                obligation_span: Span::new(
                    this.submitted_counts[16],
                    counts[16] - this.submitted_counts[16],
                )?,
                assumption_index_span: if rebuild_assumptions {
                    Span::new(0, counts[14])?
                } else {
                    Span::new(prior_assumptions, counts[14] - prior_assumptions)?
                },
                plan: UploadPlan {
                    copies,
                    writes,
                    output_copies,
                    initialize_outputs,
                    input_word_count: this.arena.next_word,
                    output_word_count: this.outputs.next_word,
                },
            };
            this.submitted_counts = counts;
            this.awaiting_result = Some(serial);
            Ok(result)
        })
    }

    /// The dispatch owner supplies complete status readbacks, never just an
    /// evidence slot. Failed or incomplete submissions poison this packet.
    /// Copying validated Evidence8 retains all referenced immutable row closures.
    pub fn accept_submission(
        &mut self,
        submission: &Submission,
        catalog_status: [u32; 8],
        batch_status: [u32; 8],
        context_statuses: &[[u32; 8]],
        call_statuses: &[[u32; 8]],
        obligation_results: &[[u32; 8]],
        evidence_rows: &[[u32; 8]],
        proof_readback: &GpuProofReadback,
    ) -> Result<Vec<ValidatedEvidence>> {
        let result = (|| {
            ensure!(
                !self.poisoned
                    && submission.epoch == self.catalog.epoch
                    && submission.arena_id == self.arena_id
                    && self.awaiting_result == Some(submission.serial),
                "evidence output belongs to another submission"
            );
            ensure!(
                catalog_status[0] == 1,
                "catalog has not passed GPU admission/coherence"
            );
            // Per-call success cannot admit an unused malformed row or an
            // empty batch. The final GPU reducer publishes this receipt only
            // after every admission/selection phase and required barrier.
            ensure!(
                batch_status[0] == 1
                    && batch_status[6] == submission.serial
                    && batch_status[7] == 0,
                "GPU batch admission failed, incomplete, or names another submission"
            );
            ensure!(
                context_statuses.len() == submission.context_span.count as usize
                    && context_statuses.iter().all(|s| s[0] == 1),
                "GPU context admission failed or incomplete"
            );
            ensure!(
                call_statuses.len() == submission.call_span.count as usize,
                "missing GPU call status"
            );
            // Status 8: the GPU refuted an obligation of the call's soft
            // context. That context's every call is demoted below.
            let mut demoted_contexts = BTreeSet::new();
            for (i, status) in call_statuses.iter().enumerate() {
                let call = submission.call_span.first + i as u32;
                ensure!(
                    matches!(status[0], 1 | 2 | 8) && status[2] == call,
                    "GPU call failed or status names another call"
                );
                if status[0] == 8 {
                    let context = self.tables.row(15, call)?[0];
                    ensure!(
                        self.tables.row(13, context)?[7] == 1,
                        "GPU refuted a call outside a soft context"
                    );
                    demoted_contexts.insert(context);
                }
            }
            ensure!(
                obligation_results.len() == submission.obligation_span.count as usize
                    && evidence_rows.len() == obligation_results.len(),
                "missing obligation results"
            );
            self.proof_store.check_submission(
                submission.epoch,
                submission.arena_id,
                submission.serial,
            )?;
            // The opaque readback owns the same GPU result rows supplied above;
            // its constructor is private to the dispatcher's physical arena.
            proof_readback.check_results(
                submission,
                batch_status,
                obligation_results,
                evidence_rows,
            )?;
            self.proof_store.accept_gpu_readback(proof_readback)?;
            let mut retained = Vec::with_capacity(evidence_rows.len());
            for (i, (status, evidence)) in obligation_results.iter().zip(evidence_rows).enumerate()
            {
                let obligation = submission.obligation_span.first + i as u32;
                let goal = self.tables.row(16, obligation)?;
                if status[0] == 3 {
                    // Only an obligation whose own call the GPU refuted may
                    // stay unproven; it holds its place without a proof.
                    let call = goal[0];
                    ensure!(
                        call >= submission.call_span.first
                            && call - submission.call_span.first < submission.call_span.count
                            && call_statuses[(call - submission.call_span.first) as usize][0] == 8,
                        "GPU obligation failed outside a refuted soft call"
                    );
                    let predicate_identity =
                        self.catalog.stable_witness(self.catalog.tables.row(8, goal[1])?[0])?;
                    retained.push(ValidatedEvidence {
                        epoch: self.catalog.epoch,
                        arena_id: self.arena_id,
                        input_row: INVALID,
                        predicate_identity,
                        predicate_row: goal[1],
                        implementation: None,
                        proof: None,
                    });
                    continue;
                }
                ensure!(
                    matches!(status[0], 1 | 2) && status[2] == obligation,
                    "GPU obligation failed or evidence slot is wrong"
                );
                ensure!(
                    evidence[1] == goal[1]
                        && evidence[2] == goal[2]
                        && evidence[5] == goal[0]
                        && evidence[6] == obligation
                        && evidence[7] == 0,
                    "GPU evidence output names a different obligation"
                );
                ensure!(
                    evidence[0] == if status[0] == 1 { 1 } else { 2 },
                    "evidence/result state mismatch"
                );
                let proof = self.proof_store.root_from_gpu_readback(
                    proof_readback,
                    [goal[1], goal[2], goal[0], obligation],
                )?;
                ensure!(
                    proof.matches_evidence(*evidence),
                    "proof readback differs from retained result"
                );
                let predicate_atom = self.catalog.tables.row(8, evidence[1])?[0];
                let predicate_identity = self.catalog.stable_witness(predicate_atom)?;
                // Result word 7 is the root proof's implementation plus one
                // (pps_publish_root); 0 for an assumption proof.
                let implementation = status[7].checked_sub(1);
                if let Some(row) = implementation {
                    ensure!(row < self.catalog.tables.count(9)?,
                        "GPU evidence names an implementation outside the catalog");
                }
                let input_row = self.tables.push(17, evidence)?;
                retained.push(ValidatedEvidence {
                    epoch: self.catalog.epoch,
                    arena_id: self.arena_id,
                    input_row,
                    predicate_identity,
                    predicate_row: evidence[1],
                    implementation,
                    proof: Some(proof),
                });
            }
            for call in submission.call_span.first
                ..add(
                    submission.call_span.first,
                    submission.call_span.count,
                    "admitted call span",
                )?
            {
                let context = self.tables.row(15, call)?[0];
                let state = if demoted_contexts.contains(&context) {
                    8
                } else {
                    call_statuses[(call - submission.call_span.first) as usize][0]
                };
                self.admitted_calls.insert(call, state);
            }
            Ok(retained)
        })();
        self.awaiting_result = None;
        if result.is_err() {
            self.poisoned = true;
        }
        result
    }
}
