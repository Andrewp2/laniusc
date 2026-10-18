use std::{
    collections::{BTreeMap, BTreeSet},
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
};

use anyhow::{Result, anyhow, ensure};

use super::{super::typecheck::{CompiledSourcePackUnit, OriginalUnitFacts}, abi::*, native_layout::FrozenNativeLayout};
use crate::{
    compiler::{GpuSemanticInterfaceArtifact, GpuSemanticInterfaceImplementationKind, GpuSemanticInterfaceMemberKind},
    type_checker::{
        CheckedBinderIdentity,
        CheckedCallOwner,
        CheckedGenericApplicationArgument,
        CheckedGenericCall,
        CheckedGenericConstantValue,
        CheckedGenericParameter,
        CheckedGenericType,
        CheckedNominalIdentity,
        CheckedParameterDomain,
        CheckedUnitContracts,
    },
};

static NEXT_OWNED_ID: AtomicU64 = AtomicU64::new(1);
pub(super) fn owned_id() -> Result<u64> {
    NEXT_OWNED_ID
        .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |n| n.checked_add(1))
        .map_err(|_| anyhow!("immutable evidence identity space exhausted"))
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(in crate::compiler::gpu_compiler) struct FrozenSnapshotId(pub u64);

/// These IDs are native callable identities from accepted producers. A private
/// implementation method does not gain a public callable alias merely because
/// an exported implementation binding names its private native target.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct CallableInput {
    pub source_hir: u32,
    pub native_symbol: u32,
    pub public_alias: Option<[u32; 3]>,
}

/// One method of an evidence-selected implementation: the trait member it
/// implements (its interface symbol) and its native callable.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::compiler::gpu_compiler) struct ImplementationMethodTarget {
    /// Interface symbol of the trait member, scoped by the trait's unit.
    pub required_symbol: u32,
    pub trait_unit: [u32; 2],
    pub receiver_mode: u32,
    /// (library, unit, native symbol).
    pub target: [u32; 3],
}

pub(in crate::compiler::gpu_compiler) struct CatalogInput<'a> {
    pub facts: &'a OriginalUnitFacts,
}

pub(super) struct FrozenSnapshot {
    pub id: FrozenSnapshotId,
    pub unit: [u32; 2],
    pub original_facts: OriginalUnitFacts,
    pub contracts: Arc<CheckedUnitContracts>,
    pub sources: Arc<[String]>,
    pub source_paths: Arc<[Option<std::path::PathBuf>]>,
    pub dependency_pages: Arc<[Vec<GpuSemanticInterfaceArtifact>]>,
    pub interface_bytes: Arc<[u8]>,
    /// The complete original accepted inventory is authoritative even when a
    /// reparse produces fresh environments for the same source occurrences.
    pub original_calls: Arc<[CheckedGenericCall]>,
    pub original_call_owners: Arc<[CheckedCallOwner]>,
    pub call_owner_by_hir: BTreeMap<u32, u32>,
}

#[derive(Clone, Debug, Default)]
pub(super) struct Atoms {
    pub keys: Vec<[u32; 8]>,
    by_key: BTreeMap<[u32; 8], u32>,
}

impl Atoms {
    pub fn intern(&mut self, key: [u32; 8]) -> Result<u32> {
        if let Some(&index) = self.by_key.get(&key) {
            return Ok(index);
        }
        let index = u32_len(self.keys.len(), "atoms")?;
        ensure!(index != INVALID, "atom identity capacity exhausted");
        self.keys.try_reserve(1)?;
        self.keys.push(key);
        self.by_key.insert(key, index);
        Ok(index)
    }
    pub fn find(&self, key: &[u32; 8]) -> Result<u32> {
        self.by_key
            .get(key)
            .copied()
            .ok_or_else(|| anyhow!("identity absent from frozen catalog"))
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(in crate::compiler::gpu_compiler) enum StableWitnessIdentity {
    Public {
        kind: u32,
        identity: [u32; 3],
    },
    Private {
        kind: u32,
        snapshot: FrozenSnapshotId,
        anchor: [u32; 2],
    },
}

pub(in crate::compiler::gpu_compiler) struct FrozenCatalog {
    pub epoch: u64,
    /// Definition recipes share this catalog's exact atom/root namespace and epoch.
    pub native_layout: FrozenNativeLayout,
    pub snapshots: Vec<FrozenSnapshot>,
    pub snapshot_by_unit: BTreeMap<[u32; 2], u32>,
    pub tables: Tables,
    pub atoms: Atoms,
    pub owner_by_hir: BTreeMap<(u32, u32), u32>,
    pub callable_by_native: BTreeMap<(u32, u32), u32>,
    pub callable_by_owner: BTreeMap<u32, u32>,
    pub predicate_by_owned_row: BTreeMap<(u32, u32), u32>,
    pub implementation_by_owned_row: BTreeMap<(u32, u32), u32>,
    /// Inverses of the two maps above: table-8 and table-9 row -> (snapshot,
    /// index into that snapshot's contract predicates or implementations).
    predicate_sources: Vec<(u32, u32)>,
    implementation_sources: Vec<(u32, u32)>,
    /// One upload, including catalog-owned output regions initialized by GPU.
    pub words: Arc<[u32]>,
    pub slices: [Slice; TABLE_COUNT],
    pub outputs: [Slice; OUTPUT_COUNT],
}

impl FrozenCatalog {
    pub fn freeze(inputs: &[CatalogInput<'_>]) -> Result<Arc<Self>> {
        let mut originals = BTreeMap::<[u32; 2], &CatalogInput<'_>>::new();
        for input in inputs {
            let unit = input.facts;
            let key = [unit.interface().library_id, unit.interface().unit_id];
            ensure!(
                key.iter().all(|&n| n != INVALID),
                "invalid source unit identity"
            );
            ensure!(
                unit.checked_contracts().source_unit == Some(key),
                "unscoped or foreign contract snapshot"
            );
            ensure!(unit.template_source_paths().len() == unit.template_sources().len(),
                "source paths do not match the immutable source-file ordinals");
            if let Some(prior) = originals.get(&key) {
                // Same numbers or source text do not establish private-object
                // provenance. This v1 admits actual retained-object duplicates.
                ensure!(
                    prior.facts.same_snapshot(unit),
                    "duplicate numeric unit identity has independent immutable snapshots"
                );
                ensure!(
                    prior.facts.interface().to_bytes().map_err(|e| anyhow!(e))?
                        == unit.interface().to_bytes().map_err(|e| anyhow!(e))?,
                    "conflicting public export for one snapshot"
                );
            } else {
                originals.insert(key, input);
            }
        }
        let epoch = owned_id()?;
        let mut result = Self {
            epoch,
            native_layout: FrozenNativeLayout::empty(epoch)?,
            snapshots: Vec::new(),
            snapshot_by_unit: BTreeMap::new(),
            tables: Tables::default(),
            atoms: Atoms::default(),
            owner_by_hir: BTreeMap::new(),
            callable_by_native: BTreeMap::new(),
            callable_by_owner: BTreeMap::new(),
            predicate_by_owned_row: BTreeMap::new(),
            implementation_by_owned_row: BTreeMap::new(),
            predicate_sources: Vec::new(),
            implementation_sources: Vec::new(),
            words: Arc::from([]),
            slices: [Slice::default(); TABLE_COUNT],
            outputs: [Slice::default(); OUTPUT_COUNT],
        };
        for (&key, input) in &originals {
            let index = u32_len(result.snapshots.len(), "snapshots")?;
            let id = FrozenSnapshotId(owned_id()?);
            let call_owner_by_hir = accepted_original_call_owners(input.facts)?;
            result
                .tables
                .push(0, &[key[0], key[1], id.0 as u32, (id.0 >> 32) as u32])?;
            result.snapshot_by_unit.insert(key, index);
            result.snapshots.push(FrozenSnapshot {
                id,
                unit: key,
                original_facts: input.facts.clone(),
                contracts: input.facts.checked_contracts().clone(),
                sources: input.facts.template_sources().clone(),
                source_paths: input.facts.template_source_paths().clone(),
                dependency_pages: input.facts.template_dependency_pages().clone(),
                interface_bytes: input
                    .facts
                    .interface()
                    .to_bytes()
                    .map_err(|e| anyhow!(e))?
                    .into(),
                original_calls: input.facts.generic_calls().clone(),
                original_call_owners: input.facts.checked_call_owners().clone(),
                call_owner_by_hir,
            });
        }
        // Page order and empty pages remain owned by the source snapshot. Flat
        // artifact byte equality verifies public provenance only. Pages never
        // add implementations or nominate a different private snapshot.
        for snapshot in &result.snapshots {
            for page in snapshot.dependency_pages.iter() {
                for artifact in page {
                    let key = [artifact.library_id, artifact.unit_id];
                    let index = *result.snapshot_by_unit.get(&key).ok_or_else(|| {
                        anyhow!("dependency unit {key:?} has no authoritative program snapshot")
                    })?;
                    ensure!(
                        artifact.to_bytes().map_err(|e| anyhow!(e))?.as_slice()
                            == result.snapshots[index as usize].interface_bytes.as_ref(),
                        "dependency page conflicts with authoritative unit {key:?}"
                    );
                }
            }
        }
        for snapshot in 0..result.snapshots.len() {
            let contracts = result.snapshots[snapshot].contracts.clone();
            let first = result.tables.count(2)?;
            for (local, owner) in contracts.binders.iter().enumerate() {
                let global = add(first, u32_len(local, "local owner")?, "owner")?;
                ensure!(
                    result
                        .owner_by_hir
                        .insert((snapshot as u32, owner.source_hir), global)
                        .is_none(),
                    "duplicate owner HIR"
                );
                let atom = binder_atom(
                    &mut result.atoms,
                    &result.snapshot_by_unit,
                    result.snapshots[snapshot].unit,
                    owner.binder,
                )?;
                result.tables.push(
                    2,
                    &[
                        atom,
                        snapshot as u32,
                        owner.source_hir,
                        INVALID,
                        0,
                        0,
                        0,
                        0,
                        INVALID,
                    ],
                )?;
            }
            for (local, owner) in contracts.binders.iter().enumerate() {
                let global = first + local as u32;
                let parameter_first = result.tables.count(3)?;
                for parameter in &owner.parameters {
                    ensure!(
                        parameter.identity.unit == result.snapshots[snapshot].unit,
                        "parameter belongs to another source unit"
                    );
                    ensure!(
                        parameter.identity.binder == owner.binder,
                        "parameter belongs to another binder"
                    );
                    ensure!(
                        parameter.binding_slot < 32,
                        "parameter slot exceeds domain capacity"
                    );
                    let atom =
                        parameter_atom(&mut result.atoms, &result.snapshot_by_unit, *parameter)?;
                    result.tables.push(
                        3,
                        &[
                            global,
                            atom,
                            parameter.binding_slot,
                            domain(parameter.identity.domain),
                        ],
                    )?;
                }
                let parent = owner
                    .enclosing_owner
                    .map(|p| {
                        ensure!(
                            (p as usize) < contracts.binders.len(),
                            "enclosing owner outside snapshot"
                        );
                        add(first, p, "enclosing owner")
                    })
                    .transpose()?
                    .unwrap_or(INVALID);
                let count = u32_len(owner.parameters.len(), "owner parameters")?;
                let row = result.tables.row_mut(2, global)?;
                row[3] = parent;
                row[4] = if count == 0 { 0 } else { parameter_first };
                row[5] = count;
            }
        }
        for (&unit_key, input) in &originals {
            let snapshot = result.snapshot_by_unit[&unit_key];
            let mut callables = input
                .facts
                .checked_contracts()
                .binders
                .iter()
                .filter_map(|owner| {
                    let callable = owner.callable.as_ref()?;
                    Some(CallableInput {
                        source_hir: owner.source_hir,
                        native_symbol: callable.native_symbol,
                        public_alias: public_callable_exists(
                            input.facts.interface(),
                            callable.native_symbol,
                        )
                        .then_some([
                            unit_key[0],
                            unit_key[1],
                            callable.native_symbol,
                        ]),
                    })
                })
                .collect::<Vec<_>>();
            callables.sort_by_key(|c| c.source_hir);
            for callable in callables {
                let owner = result.owner(snapshot, callable.source_hir)?;
                ensure!(
                    callable.native_symbol != INVALID,
                    "invalid callable native target"
                );
                ensure!(
                    callable.public_alias.is_some()
                        == public_callable_exists(input.facts.interface(), callable.native_symbol),
                    "callable public/private identity disagrees with accepted export"
                );
                if let Some(alias) = callable.public_alias {
                    ensure!(
                        alias == [unit_key[0], unit_key[1], callable.native_symbol],
                        "foreign callable export alias"
                    );
                    ensure!(
                        public_callable_exists(input.facts.interface(), callable.native_symbol),
                        "callable alias absent from accepted export"
                    );
                }
                let atom = result.atoms.intern(match callable.public_alias {
                    Some([lib, unit, symbol]) => [8, lib, unit, symbol, 0, 0, 0, 0],
                    None => [9, snapshot, callable.native_symbol, 0, 0, 0, 0, 0],
                })?;
                let parameters = result.composed_parameters(owner)?;
                let types = parameters.iter().filter(|p| p[3] == 0).count();
                let constants = parameters.len() - types;
                ensure!(
                    types <= 32 && constants <= 32,
                    "composed callable parameter capacity exceeded"
                );
                let row = result
                    .tables
                    .push(4, &[atom, owner, types as u32, constants as u32])?;
                ensure!(
                    result
                        .callable_by_native
                        .insert((snapshot, callable.native_symbol), row)
                        .is_none(),
                    "duplicate native callable in snapshot"
                );
                ensure!(
                    result.callable_by_owner.insert(owner, row).is_none(),
                    "duplicate callable owner"
                );
                result.tables.row_mut(2, owner)?[8] = row;
            }
        }
        // Group predicates by owner without changing order within that owner.
        // No graph equality, substitution or implementation matching happens here.
        for snapshot in 0..result.snapshots.len() {
            let contracts = result.snapshots[snapshot].contracts.clone();
            let unit = result.snapshots[snapshot].unit;
            let mut exported_predicates = BTreeSet::new();
            for local_owner in 0..contracts.binders.len() {
                let owner =
                    result.owner(snapshot as u32, contracts.binders[local_owner].source_hir)?;
                let first = result.tables.count(8)?;
                for (local_predicate, predicate) in contracts
                    .predicates
                    .iter()
                    .enumerate()
                    .filter(|(_, p)| p.owner as usize == local_owner)
                {
                    let atom = match predicate.public_index {
                        Some(index) => {
                            ensure!(
                                exported_predicates.insert(index),
                                "duplicate public predicate alias"
                            );
                            result
                                .atoms
                                .intern([10, unit[0], unit[1], index, 0, 0, 0, 0])?
                        }
                        None => result.atoms.intern([
                            11,
                            snapshot as u32,
                            predicate.source_row,
                            predicate.bound_hir,
                            0,
                            0,
                            0,
                            0,
                        ])?,
                    };
                    let trait_atom = nominal_atom(
                        &mut result.atoms,
                        &result.snapshot_by_unit,
                        predicate.trait_identity,
                    )?;
                    let (subject, arguments) = {
                        let mut copier = GraphCopier::new(
                            &result.snapshot_by_unit,
                            &mut result.atoms,
                            &mut result.tables,
                            [0; TABLE_COUNT],
                        );
                        (
                            copier.root(&predicate.subject)?,
                            copier.arguments(&predicate.arguments)?,
                        )
                    };
                    let row = result.tables.push(
                        8,
                        &[
                            atom,
                            owner,
                            trait_atom,
                            subject,
                            arguments.first,
                            arguments.count,
                            0,
                            0,
                        ],
                    )?;
                    result
                        .predicate_by_owned_row
                        .insert((snapshot as u32, local_predicate as u32), row);
                    ensure!(result.predicate_sources.len() == row as usize,
                        "predicate rows are not appended in order");
                    result.predicate_sources.push((snapshot as u32, local_predicate as u32));
                }
                let count = result.tables.count(8)? - first;
                let row = result.tables.row_mut(2, owner)?;
                row[6] = if count == 0 { 0 } else { first };
                row[7] = count;
            }
            ensure!(
                contracts
                    .predicates
                    .iter()
                    .all(|p| (p.owner as usize) < contracts.binders.len()),
                "predicate has missing owner"
            );
            let mut exported_impls = BTreeSet::new();
            for (local_impl, implementation) in contracts.implementations.iter().enumerate() {
                let owner_hir = contracts
                    .binders
                    .get(implementation.owner as usize)
                    .ok_or_else(|| anyhow!("implementation has missing owner"))?
                    .source_hir;
                let owner = result.owner(snapshot as u32, owner_hir)?;
                // Checked implementation rows are trait definitions. Their own
                // parameters and prerequisites stay on the exact impl binder;
                // the GPU admits the full head and proves these requirements.
                let prerequisites = result.implementation_prerequisite_span(owner)?;
                let atom = match implementation.public_index {
                    Some(index) => {
                        ensure!(
                            exported_impls.insert(index),
                            "duplicate public implementation alias"
                        );
                        result
                            .atoms
                            .intern([6, unit[0], unit[1], index, 0, 0, 0, 0])?
                    }
                    None => result
                        .atoms
                        .intern([7, snapshot as u32, owner_hir, 0, 0, 0, 0, 0])?,
                };
                let trait_atom = nominal_atom(
                    &mut result.atoms,
                    &result.snapshot_by_unit,
                    implementation.trait_identity,
                )?;
                let (subject, arguments) = {
                    let mut copier = GraphCopier::new(
                        &result.snapshot_by_unit,
                        &mut result.atoms,
                        &mut result.tables,
                        [0; TABLE_COUNT],
                    );
                    (
                        copier.root(&implementation.subject)?,
                        copier.arguments(&implementation.arguments)?,
                    )
                };
                let row = result.tables.count(9)?;
                let first_method = result.tables.count(10)?;
                let mut ordered_methods = implementation.method_bindings.iter().collect::<Vec<_>>();
                ordered_methods.sort_by_key(|method| method.required_symbol);
                ensure!(
                    ordered_methods
                        .windows(2)
                        .all(|rows| rows[0].required_symbol != rows[1].required_symbol),
                    "duplicate required method identity in implementation"
                );
                for method in ordered_methods {
                    let target_snapshot = *result
                        .snapshot_by_unit
                        .get(&[method.target[0], method.target[1]])
                        .ok_or_else(|| anyhow!("implementation target snapshot absent"))?;
                    let target = *result
                        .callable_by_native
                        .get(&(target_snapshot, method.target[2]))
                        .ok_or_else(|| {
                            anyhow!("accepted implementation target missing callable inventory")
                        })?;
                    let method_owner = result.owner(snapshot as u32, method.method_hir)?;
                    let target_row = result.tables.row(4, target)?;
                    ensure!(target_row[1] == method_owner,
                        "implementation target belongs to a different method owner");
                    let method_header = result.tables.row(2, method_owner)?;
                    ensure!(method_header[3] == owner,
                        "implementation method has a different lexical parent");
                    ensure!(method_header[5] == 0 && method_header[7] == 0,
                        "UNSUPPORTED: trait implementation method has own parameters or prerequisites");
                    // Callable counts were serialized from this exact lexical
                    // chain. The GPU separately validates complete inherited
                    // parameter identity and every call environment binding.
                    let target_atom = target_row[0];
                    result.tables.push(
                        10,
                        &[
                            row,
                            method.required_symbol,
                            target_atom,
                            method.receiver_mode,
                            method_owner,
                            0,
                        ],
                    )?;
                }
                let method_count = u32_len(
                    implementation.method_bindings.len(),
                    "implementation methods",
                )?;
                result.tables.push(
                    9,
                    &[
                        atom,
                        owner,
                        trait_atom,
                        subject,
                        arguments.first,
                        arguments.count,
                        if method_count == 0 { 0 } else { first_method },
                        method_count,
                        prerequisites.first,
                        prerequisites.count,
                        0,
                        0,
                    ],
                )?;
                result
                    .implementation_by_owned_row
                    .insert((snapshot as u32, local_impl as u32), row);
                ensure!(result.implementation_sources.len() == row as usize,
                    "implementation rows are not appended in order");
                result.implementation_sources.push((snapshot as u32, local_impl as u32));
            }
            let interface = originals[&unit].facts.interface();
            ensure!(
                exported_predicates.len() == interface.predicates.len()
                    && exported_predicates
                        .iter()
                        .all(|&p| (p as usize) < interface.predicates.len()),
                "public predicate export is not covered exactly by owned contracts"
            );
            ensure!(
                exported_impls == interface.implementations.iter().enumerate()
                    .filter(|(_, implementation)| implementation.kind == GpuSemanticInterfaceImplementationKind::Trait as u32)
                    .map(|(index, _)| index as u32).collect::<BTreeSet<_>>(),
                "public implementation export is not covered exactly by owned contracts"
            );
        }
        // Recipe roots may introduce parameter and nominal atoms. Copy them
        // before freezing Atom1; their identities remain owned by this catalog.
        result.native_layout = FrozenNativeLayout::capture(&mut result)?;
        for key in &result.atoms.keys {
            result.tables.push(1, key)?;
        }
        result.materialize()?;
        Ok(Arc::new(result))
    }

    pub fn owner(&self, snapshot: u32, hir: u32) -> Result<u32> {
        self.owner_by_hir
            .get(&(snapshot, hir))
            .copied()
            .ok_or_else(|| anyhow!("accepted callable owner {snapshot}:{hir} was not retained"))
    }
    pub fn owner_chain(&self, owner: u32) -> Result<Vec<u32>> {
        let mut chain = Vec::new();
        let mut current = owner;
        while current != INVALID {
            ensure!(
                chain.len() < 64 && !chain.contains(&current),
                "owner cycle or depth limit"
            );
            let row = self.tables.row(2, current)?;
            chain.push(current);
            current = row[3];
        }
        Ok(chain)
    }
    pub fn composed_parameters(&self, owner: u32) -> Result<Vec<[u32; 4]>> {
        let mut result = Vec::new();
        for owner in self.owner_chain(owner)? {
            let row = self.tables.row(2, owner)?;
            for index in row[4]..add(row[4], row[5], "parameter span")? {
                result.push(self.tables.row(3, index)?.try_into().unwrap());
            }
        }
        Ok(result)
    }
    /// The source unit that declares an implementation (table-9 row).
    pub fn implementation_unit(&self, row: u32) -> Result<[u32; 2]> {
        let &(snapshot, _) = self.implementation_sources.get(row as usize)
            .ok_or_else(|| anyhow!("implementation row outside the frozen catalog"))?;
        Ok(self.snapshots[snapshot as usize].unit)
    }

    /// The method targets of a nongeneric implementation (table-9 row), in
    /// required-symbol order: what a bound member call routes to once evidence
    /// has selected this implementation. None for an implementation with type
    /// or constant parameters, whose methods need an environment of their own.
    /// Copies accepted contract bindings; selects and compares nothing.
    pub fn implementation_method_targets(&self, row: u32) -> Result<Option<Vec<ImplementationMethodTarget>>> {
        let &(snapshot, local) = self.implementation_sources.get(row as usize)
            .ok_or_else(|| anyhow!("implementation row outside the frozen catalog"))?;
        let owner = self.tables.row(9, row)?[1];
        if !self.composed_parameters(owner)?.is_empty() {
            return Ok(None);
        }
        let implementation = self.snapshots[snapshot as usize].contracts.implementations
            .get(local as usize)
            .ok_or_else(|| anyhow!("implementation row has no retained contract"))?;
        let trait_unit = implementation.trait_identity.unit();
        ensure!(trait_unit.iter().all(|&word| word != INVALID),
            "implementation trait has an unscoped identity");
        let mut targets = implementation.method_bindings.iter().map(|binding| {
            ensure!(binding.target.iter().all(|&word| word != INVALID),
                "implementation method binding has an unscoped target");
            Ok(ImplementationMethodTarget {
                required_symbol: binding.required_symbol,
                trait_unit,
                receiver_mode: binding.receiver_mode,
                target: binding.target,
            })
        }).collect::<Result<Vec<_>>>()?;
        targets.sort_by_key(|target| target.required_symbol);
        Ok(Some(targets))
    }

    /// The binding slot of a predicate (table-8 row) whose subject is a type
    /// parameter of its owner chain, or None for another subject.
    pub fn predicate_subject_slot(&self, row: u32) -> Result<Option<u32>> {
        let &(snapshot, local) = self.predicate_sources.get(row as usize)
            .ok_or_else(|| anyhow!("predicate row outside the frozen catalog"))?;
        let predicate = self.snapshots[snapshot as usize].contracts.predicates
            .get(local as usize)
            .ok_or_else(|| anyhow!("predicate row has no retained contract"))?;
        Ok(match &predicate.subject {
            CheckedGenericType::Parameter(parameter)
                if parameter.identity.domain == CheckedParameterDomain::Type
                    && parameter.binding_slot < 32 => Some(parameter.binding_slot),
            _ => None,
        })
    }

    pub fn applicable_predicates(&self, owner: u32) -> Result<Vec<u32>> {
        let mut result = Vec::new();
        for owner in self.owner_chain(owner)? {
            let row = self.tables.row(2, owner)?;
            result.extend(row[6]..add(row[6], row[7], "predicate span")?);
        }
        Ok(result)
    }
    /// Impl12 has one exact own-binder prerequisite span. Source impls are
    /// currently top-level items; accepting inherited requirements here would
    /// flatten distinct owners into a span the GPU cannot interpret faithfully.
    /// Empty ancestor scopes are harmless, but nonempty inherited contracts
    /// need an explicit representation before they can be supported.
    fn implementation_prerequisite_span(&self, owner: u32) -> Result<Span> {
        for ancestor in self.owner_chain(owner)?.into_iter().skip(1) {
            let row = self.tables.row(2, ancestor)?;
            ensure!(row[5] == 0, "UNSUPPORTED: inherited implementation parameters");
            ensure!(row[7] == 0, "UNSUPPORTED: inherited implementation prerequisites");
        }
        let row = self.tables.row(2, owner)?;
        let prerequisites = Span::new(row[6], row[7])?;
        for predicate in prerequisites.first..add(prerequisites.first, prerequisites.count, "implementation prerequisites")? {
            ensure!(self.tables.row(8, predicate)?[1] == owner,
                "implementation prerequisite span contains a foreign owner");
        }
        Ok(prerequisites)
    }

    pub fn stable_witness(&self, atom: u32) -> Result<StableWitnessIdentity> {
        let key = *self
            .atoms
            .keys
            .get(atom as usize)
            .ok_or_else(|| anyhow!("witness atom outside frozen catalog"))?;
        match key[0] {
            6 | 10 => Ok(StableWitnessIdentity::Public {
                kind: key[0],
                identity: [key[1], key[2], key[3]],
            }),
            7 | 11 => Ok(StableWitnessIdentity::Private {
                kind: key[0],
                snapshot: self
                    .snapshots
                    .get(key[1] as usize)
                    .ok_or_else(|| anyhow!("private witness snapshot absent"))?
                    .id,
                anchor: [key[2], key[3]],
            }),
            _ => Err(anyhow!("atom is not an implementation/predicate witness")),
        }
    }
    fn materialize(&mut self) -> Result<()> {
        let mut words = vec![MAGIC, VERSION, self.epoch as u32, (self.epoch >> 32) as u32];
        for table in 0..TABLE_COUNT {
            let count = self.tables.count(table)?;
            ensure!(
                table < BATCH_ONLY_START || count == 0,
                "batch rows in frozen catalog"
            );
            if count != 0 {
                let offset = u32_len(words.len(), "catalog arena")?;
                add(
                    offset,
                    u32_len(self.tables.words[table].len(), "catalog table")?,
                    "catalog arena",
                )?;
                words.try_reserve(self.tables.words[table].len())?;
                words.extend_from_slice(&self.tables.words[table]);
                self.slices[table] = Slice {
                    offset,
                    count,
                    capacity: count,
                };
            }
        }
        let impls = self.tables.count(9)?;
        // The same scratch first indexes exact atom tuples for duplicate
        // admission, then is cleared and rebuilt for implementation keys.
        // Each phase still bounds row identities by its actual table count.
        let index_rows = self.tables.count(1)?.max(impls);
        for (table, count) in [
            (0, 1),
            (1, impls),
            (6, index_rows),
            (7, buckets(index_rows)?),
            (11, impls),
            (12, buckets(index_rows)?),
        ] {
            if count == 0 {
                continue;
            }
            let offset = u32_len(words.len(), "catalog output")?;
            let end = add(
                offset,
                mul(count, OUTPUT_WIDTHS[table], "catalog output")?,
                "catalog arena",
            )?;
            words.try_reserve((end - offset) as usize)?;
            words.resize(end as usize, if table == 7 || table == 12 { INVALID } else { 0 });
            self.outputs[table] = Slice {
                offset,
                count,
                capacity: count,
            };
        }
        self.words = words.into();
        Ok(())
    }
}

/// Integer occurrence coverage only: graphs are never compared here. A
/// caller-provided pair of truncated slices is not accepted as source authority.
pub(super) fn accepted_call_owners(unit: &CompiledSourcePackUnit) -> Result<BTreeMap<u32, u32>> {
    retained_call_owners(&unit.generic_calls, &unit.checked_call_owners)
}

fn accepted_original_call_owners(facts: &OriginalUnitFacts) -> Result<BTreeMap<u32, u32>> {
    retained_call_owners(facts.generic_calls(), facts.checked_call_owners())
}

fn retained_call_owners(calls: &[CheckedGenericCall], call_owners: &[CheckedCallOwner]) -> Result<BTreeMap<u32, u32>> {
    let mut owners = BTreeMap::new();
    for owner in call_owners.iter() {
        ensure!(
            owner.call_hir != INVALID
                && owners.insert(owner.call_hir, owner.function_hir).is_none(),
            "invalid or duplicate retained call ownership"
        );
    }
    let mut call_hirs = BTreeSet::new();
    for call in calls.iter() {
        ensure!(
            call.call_hir != INVALID && call_hirs.insert(call.call_hir),
            "invalid or duplicate checked generic call"
        );
    }
    ensure!(
        call_hirs == owners.keys().copied().collect::<BTreeSet<_>>(),
        "complete retained unit calls and owners are not bijective"
    );
    Ok(owners)
}

fn public_callable_exists(interface: &GpuSemanticInterfaceArtifact, symbol: u32) -> bool {
    if interface
        .declarations
        .get(symbol as usize)
        .is_some_and(|d| matches!(d.kind, 4 | 5))
    {
        return true;
    }
    interface.members.iter().enumerate().any(|(row, member)| {
        member.kind == GpuSemanticInterfaceMemberKind::ImplementationMethod as u32
            && member.trait_method_is_public()
            && interface.implementation_method_target(row as u32)
                .is_ok_and(|target| target == [interface.library_id, interface.unit_id, symbol])
    })
}

pub(super) fn domain(value: CheckedParameterDomain) -> u32 {
    match value {
        CheckedParameterDomain::Type => 0,
        CheckedParameterDomain::Constant => 1,
    }
}
pub(super) fn binder_atom(
    atoms: &mut Atoms,
    units: &BTreeMap<[u32; 2], u32>,
    unit: [u32; 2],
    binder: CheckedBinderIdentity,
) -> Result<u32> {
    let snapshot = *units
        .get(&unit)
        .ok_or_else(|| anyhow!("parameter unit outside frozen program"))?;
    atoms.intern(match binder {
        CheckedBinderIdentity::Public { owner, scope } => {
            [3, unit[0], unit[1], owner, scope, 0, 0, 0]
        }
        CheckedBinderIdentity::SourceLocal {
            owner_kind,
            declaration_start_token,
        } => [4, snapshot, owner_kind, declaration_start_token, 0, 0, 0, 0],
    })
}
pub(super) fn parameter_atom(
    atoms: &mut Atoms,
    units: &BTreeMap<[u32; 2], u32>,
    parameter: CheckedGenericParameter,
) -> Result<u32> {
    let identity = parameter.identity;
    let scalar = match (identity.domain, parameter.constant_scalar) {
        (CheckedParameterDomain::Type, None) => 0,
        (CheckedParameterDomain::Constant, Some(scalar))
            if crate::constant_value::constant_scalar_is_supported(scalar) => scalar,
        _ => anyhow::bail!("parameter scalar does not match its exact domain"),
    };
    let binder = binder_atom(atoms, units, identity.unit, identity.binder)?;
    atoms.intern([
        5,
        binder,
        domain(identity.domain),
        identity.source_ordinal,
        scalar,
        0,
        0,
        0,
    ])
}
pub(super) fn nominal_atom(
    atoms: &mut Atoms,
    units: &BTreeMap<[u32; 2], u32>,
    identity: CheckedNominalIdentity,
) -> Result<u32> {
    atoms.intern(match identity {
        CheckedNominalIdentity::Public([lib, unit, decl]) => {
            ensure!(
                units.contains_key(&[lib, unit]),
                "nominal unit outside frozen program"
            );
            [1, lib, unit, decl, 0, 0, 0, 0]
        }
        CheckedNominalIdentity::SourceLocal {
            unit,
            declaration_token,
        } => [
            2,
            *units
                .get(&unit)
                .ok_or_else(|| anyhow!("private nominal snapshot outside program"))?,
            declaration_token,
            0,
            0,
            0,
            0,
            0,
        ],
    })
}

/// Serialization only. No graph interning by structure, substitution, layout
/// queries, closedness tests, hashes, candidate lookup or trait matching.
pub(super) struct GraphCopier<'a> {
    units: &'a BTreeMap<[u32; 2], u32>,
    atoms: &'a mut Atoms,
    tables: &'a mut Tables,
    prefix: [u32; TABLE_COUNT],
    visits: usize,
}
impl<'a> GraphCopier<'a> {
    pub fn new(
        units: &'a BTreeMap<[u32; 2], u32>,
        atoms: &'a mut Atoms,
        tables: &'a mut Tables,
        prefix: [u32; TABLE_COUNT],
    ) -> Self {
        Self {
            units,
            atoms,
            tables,
            prefix,
            visits: 0,
        }
    }
    fn push(&mut self, table: usize, row: &[u32]) -> Result<u32> {
        add(
            self.prefix[table],
            self.tables.push(table, row)?,
            "combined graph index",
        )
    }
    pub fn root(&mut self, ty: &CheckedGenericType) -> Result<u32> {
        self.visits = 0;
        let r = self.ty(ty, 1)?;
        self.push(7, &r)
    }
    pub fn constant_root(&mut self, value: &CheckedGenericConstantValue) -> Result<u32> {
        self.visits = 0;
        let r = self.constant(value, 1)?;
        self.push(7, &r)
    }
    pub fn arguments(&mut self, arguments: &[CheckedGenericApplicationArgument]) -> Result<Span> {
        ensure!(arguments.len() <= 32, "operand arity exceeds packet limit");
        let first = add(self.prefix[7], self.tables.count(7)?, "operand roots")?;
        // Each operand receives an independent graph traversal budget.
        for argument in arguments {
            match argument {
                CheckedGenericApplicationArgument::Type(t) => {
                    self.root(t)?;
                }
                CheckedGenericApplicationArgument::Constant(c) => {
                    self.constant_root(c)?;
                }
            }
        }
        Span::new(first, u32_len(arguments.len(), "operand roots")?)
    }
    fn constant(&mut self, value: &CheckedGenericConstantValue, depth: usize) -> Result<[u32; 2]> {
        self.visits = self.visits.checked_add(1)
            .ok_or_else(|| anyhow!("constant graph visit overflow"))?;
        ensure!(depth <= ROOT_DEPTH && self.visits <= ROOT_VISITS,
            "constant graph copy exceeds explicit packet work limit");
        Ok(match value {
            CheckedGenericConstantValue::Literal(value) => {
                let [scalar, lo, hi] = value.words();
                let row = self.atoms.intern([12, scalar, lo, hi, 0, 0, 0, 0])?;
                [0x8000_0001, row]
            }
            CheckedGenericConstantValue::Parameter(parameter) => {
                ensure!(parameter.identity.domain == CheckedParameterDomain::Constant,
                    "type parameter used as constant");
                [0x8000_0002, parameter_atom(self.atoms, self.units, *parameter)?]
            }
            CheckedGenericConstantValue::CountProjection { target_scalar, source } => {
                ensure!(crate::primitive_types::integer_bits(*target_scalar) != 0,
                    "count projection has a noninteger target");
                // Copy the checked expression. The GPU owns fitting and
                // substitution; the host never evaluates a projection.
                let child = self.constant(source, depth + 1)?;
                let row = self.push(5, &[5, *target_scalar, 0, 0, child[0], child[1], 0, 0])?;
                [0x8000_0003, row]
            }
            CheckedGenericConstantValue::Unresolved { .. } => {
                return Err(anyhow!("unresolved constant in accepted graph"));
            }
        })
    }
    fn ty(&mut self, ty: &CheckedGenericType, depth: usize) -> Result<[u32; 2]> {
        self.visits = self
            .visits
            .checked_add(1)
            .ok_or_else(|| anyhow!("graph visit overflow"))?;
        ensure!(
            depth <= ROOT_DEPTH && self.visits <= ROOT_VISITS,
            "graph copy exceeds explicit packet work limit"
        );
        Ok(match ty {
            CheckedGenericType::Scalar(value) => {
                ensure!(crate::primitive_types::is_known(*value), "invalid scalar identity");
                [1, *value]
            }
            CheckedGenericType::Parameter(p) => {
                ensure!(
                    domain(p.identity.domain) == 0,
                    "constant parameter used as type"
                );
                [2, parameter_atom(self.atoms, self.units, *p)?]
            }
            CheckedGenericType::Slice(child) | CheckedGenericType::Reference(child) => {
                let value = self.ty(child, depth + 1)?;
                let kind = if matches!(ty, CheckedGenericType::Slice(_)) {
                    3
                } else {
                    4
                };
                [3, self.push(5, &[kind, 0, 0, 0, value[0], value[1], 0, 0])?]
            }
            CheckedGenericType::Array {
                element, length, ..
            } => {
                let value = self.ty(element, depth + 1)?;
                let length = self.constant(length, depth + 1)?;
                [
                    3,
                    self.push(5, &[2, 0, 0, 0, value[0], value[1], length[0], length[1]])?,
                ]
            }
            CheckedGenericType::Nominal {
                identity,
                arguments,
                ..
            } => {
                ensure!(arguments.len() <= 32, "nominal arity exceeds packet limit");
                let nominal = nominal_atom(self.atoms, self.units, *identity)?;
                let mut edges = Vec::with_capacity(arguments.len());
                for arg in arguments {
                    edges.push(match arg {
                        CheckedGenericApplicationArgument::Type(t) => self.ty(t, depth + 1)?,
                        CheckedGenericApplicationArgument::Constant(c) => {
                            self.visits += 1;
                            ensure!(
                                depth < ROOT_DEPTH && self.visits <= ROOT_VISITS,
                                "constant operand exceeds graph work limit"
                            );
                            self.constant(c, depth + 1)?
                        }
                    });
                }
                // Reserve the parent edge segment after recursively copying all
                // child graphs, so nested nominal edges cannot interleave it.
                let first = if edges.is_empty() {
                    0
                } else {
                    add(self.prefix[6], self.tables.count(6)?, "nominal edges")?
                };
                for edge in edges {
                    self.push(6, &edge)?;
                }
                [
                    3,
                    self.push(5, &[1, nominal, first, arguments.len() as u32, 0, 0, 0, 0])?,
                ]
            }
            CheckedGenericType::Unresolved { .. } => {
                return Err(anyhow!("unresolved type in accepted graph"));
            }
        })
    }
}

#[cfg(test)]
mod implementation_scope_tests {
    use super::*;

    fn catalog_with_owned_header_and_prerequisites() -> Arc<FrozenCatalog> {
        let mut catalog = FrozenCatalog::freeze(&[]).unwrap();
        let draft = Arc::get_mut(&mut catalog).unwrap();
        // An empty lexical ancestor does not alter the impl's exact contract.
        draft.tables.push(2, &[0, 0, 10, INVALID, 0, 0, 0, 0, INVALID]).unwrap();
        draft.tables.push(2, &[1, 0, 20, 0, 0, 2, 1, 2, INVALID]).unwrap();
        draft.tables.push(2, &[2, 0, 30, INVALID, 0, 0, 0, 1, INVALID]).unwrap();
        draft.tables.push(3, &[1, 3, 0, 0]).unwrap();
        draft.tables.push(3, &[1, 4, 0, 1]).unwrap();
        draft.tables.push(8, &[5, 2, 6, 0, 0, 0, 0, 0]).unwrap();
        draft.tables.push(8, &[7, 1, 6, 0, 0, 0, 0, 0]).unwrap();
        draft.tables.push(8, &[8, 1, 6, 0, 0, 0, 0, 0]).unwrap();
        catalog
    }

    #[test]
    fn implementation_span_keeps_own_parameters_and_exact_prerequisites() {
        let catalog = catalog_with_owned_header_and_prerequisites();
        let span = catalog.implementation_prerequisite_span(1).unwrap();
        assert_eq!((span.first, span.count), (1, 2));
        assert_eq!(catalog.composed_parameters(1).unwrap().len(), 2);
    }

    #[test]
    fn implementation_span_rejects_inherited_contracts_and_foreign_rows() {
        for case in 0..3 {
            let mut catalog = catalog_with_owned_header_and_prerequisites();
            let draft = Arc::get_mut(&mut catalog).unwrap();
            match case {
                0 => draft.tables.row_mut(2, 0).unwrap()[5] = 1,
                1 => draft.tables.row_mut(2, 0).unwrap()[7] = 1,
                2 => draft.tables.row_mut(8, 1).unwrap()[1] = 2,
                _ => unreachable!(),
            }
            let error = draft.implementation_prerequisite_span(1).unwrap_err().to_string();
            assert!(error.contains(match case {
                0 => "inherited implementation parameters",
                1 => "inherited implementation prerequisites",
                2 => "foreign owner",
                _ => unreachable!(),
            }), "{error}");
        }
    }
}
