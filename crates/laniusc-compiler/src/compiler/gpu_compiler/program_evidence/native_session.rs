//! Native program checking owns its frozen catalog and every replay capability.
//! Neither source reparsing nor an existing native body can waive this gate.

use std::{collections::{BTreeMap, BTreeSet}, sync::Arc};

use anyhow::{Result, anyhow, ensure};

use super::{
    catalog::{CatalogInput, FrozenCatalog, accepted_call_owners},
    dispatch::{EvidenceDispatchFailure, EvidenceWorkspacePool, GpuPacket, GpuProgramEvidence},
    packet::{AdmittedCall, ReplayContextInput, RetainedCallSite, ValidatedEvidence},
};
use crate::{
    compiler::{
        CompileError,
        Diagnostic,
        diagnostic_label_from_source_span,
        gpu_compiler::typecheck::{
            CompiledSourcePackObject,
            CompiledSourcePackUnit,
            PendingReplayUnit,
            OriginalUnitFacts,
        },
        source_pack_diagnostic_files,
        source_pack_file_for_global_span,
    },
    type_checker::{CheckedBodySpecialization, CheckedBodySpecializationBatch, CheckedGenericTarget},
    codegen::x86::GpuX86ObjectSection,
};

pub(in crate::compiler::gpu_compiler) struct NativeProgramSession {
    catalog: Arc<FrozenCatalog>,
    gpu: GpuProgramEvidence,
    packet: GpuPacket,
    /// Global obligation order; hypotheses have no concrete replay capability.
    evidence: Vec<ValidatedEvidence>,
    poisoned: bool,
}

impl NativeProgramSession {
    pub fn admit(
        workspace: &EvidenceWorkspacePool,
        units: &[OriginalUnitFacts],
    ) -> Result<Self> {
        // Facts contain no object. Freeze the complete exact source inventory
        // before any pending unit can be released or native bodies reused.
        let inputs = units.iter().map(|facts| CatalogInput { facts }).collect::<Vec<_>>();
        let catalog = FrozenCatalog::freeze(&inputs)?;
        let gpu = GpuProgramEvidence::admit(workspace.checkout(), catalog.clone())?;
        let mut packet = gpu.new_packet()?;
        for snapshot in &catalog.snapshots {
            packet.packet_mut()?.append_original_unit_calls(&snapshot.original_facts)?;
        }
        let mut result = Self {
            catalog,
            gpu,
            packet,
            evidence: Vec::new(),
            poisoned: false,
        };
        // An empty call inventory still requires catalog and batch admission.
        result.check()?;
        Ok(result)
    }

    fn ready(&self) -> Result<()> {
        ensure!(
            !self.poisoned,
            "native program evidence session failed; discard it"
        );
        Ok(())
    }

    fn check(&mut self) -> Result<()> {
        self.ready()?;
        let obligation_count = self.packet.packet_mut()?.tables.count(16)? as usize;
        self.poisoned = true;
        let suffix = match self.gpu.check(&mut self.packet) {
            Ok(suffix) => suffix,
            Err(error) => {
                // Preserve the typed GPU failure and attach only descriptive
                // retained source data. A poisoned packet cannot issue proofs.
                let site = error
                    .downcast_ref::<EvidenceDispatchFailure>()
                    .and_then(|failure| self.packet.failure_call_site(failure));
                return Err(match site {
                    Some(site) => error.context(site),
                    None => error,
                });
            }
        };
        ensure!(
            self.evidence.len().checked_add(suffix.len()) == Some(obligation_count),
            "GPU evidence suffix does not cover the appended obligation inventory"
        );
        self.evidence.extend(suffix);
        self.poisoned = false;
        Ok(())
    }

    /// Only this fully admitted session can issue an original publication
    /// receipt. Even a unit with zero calls passed the unconditional batch gate.
    pub fn validated_original(&mut self, facts: &OriginalUnitFacts) -> Result<ValidatedOriginalUnit> {
        self.ready()?;
        let key = [facts.interface().library_id, facts.interface().unit_id];
        let snapshot = *self.catalog.snapshot_by_unit.get(&key)
            .ok_or_else(|| anyhow!("native source unit absent from frozen program"))?;
        let frozen = &self.catalog.snapshots[snapshot as usize];
        ensure!(frozen.original_facts.same_snapshot(facts),
            "native source unit does not own the admitted original snapshot");
        let calls = self.packet.packet_mut()?.admitted_unit_calls(snapshot, None)?;
        Ok(ValidatedOriginalUnit { facts: frozen.original_facts.clone(), calls })
    }

    /// The lexical scope a concrete origin call would replay: its template
    /// snapshot, selected callable HIR and, for each enclosing owner (the
    /// callable first), that owner's parameter (binding slot, domain) pairs.
    /// Two replays of one snapshot can share a frontend run when they select
    /// different callables and every common owner binds identically.
    pub fn replay_scope(&mut self, origin: &AdmittedCall) -> Result<ReplayScope> {
        self.ready()?;
        let (_, snapshot, selected_owner_hir, _) = self.packet.packet_mut()?.replay_origin(origin)?;
        let owner = self.catalog.owner(snapshot, selected_owner_hir)?;
        let owners = self.catalog.owner_chain(owner)?.into_iter().map(|owner| {
            let row = self.catalog.tables.row(2, owner)?;
            let end = row[4].checked_add(row[5]).ok_or_else(|| anyhow!("parameter span overflow"))?;
            let parameters = (row[4]..end)
                .map(|index| {
                    let parameter = self.catalog.tables.row(3, index)?;
                    Ok((parameter[2], parameter[3]))
                })
                .collect::<Result<Vec<_>>>()?;
            Ok((owner, parameters))
        }).collect::<Result<Vec<_>>>()?;
        Ok(ReplayScope { snapshot, selected_owner_hir, owners })
    }

    /// Validate several concrete origins of one template snapshot for one
    /// frontend run. Each origin gets its own replay context; one GPU check
    /// covers them all. The caller groups compatible scopes (`replay_scope`).
    pub fn prepare_replay_batch<'session>(
        &'session mut self,
        origins: &[&AdmittedCall],
    ) -> Result<ValidatedReplayRequest<'session>> {
        self.ready()?;
        ensure!(!origins.is_empty(), "replay batch has no origin");
        let mut batch: Option<CheckedBodySpecializationBatch> = None;
        let mut target_snapshot = None;
        let mut entries: Vec<(u32, u32)> = Vec::with_capacity(origins.len());
        for origin in origins {
            let (origin_call, snapshot, selected_owner_hir, obligations) =
                self.packet.packet_mut()?.replay_origin(origin)?;
            ensure!(*target_snapshot.get_or_insert(snapshot) == snapshot,
                "replay batch spans several template snapshots");
            ensure!(entries.iter().all(|&(hir, _)| hir != selected_owner_hir),
                "replay batch selects one lexical body twice");
            let call = origin.checked_call();
            let specialization = CheckedBodySpecialization {
                target_symbol: match call.target {
                    CheckedGenericTarget::Local {
                        specialization_symbol,
                        ..
                    } => specialization_symbol,
                    CheckedGenericTarget::Dependency {
                        declaration_index, ..
                    } => declaration_index,
                    CheckedGenericTarget::DependencyMethod { method_symbol, .. } => method_symbol,
                },
                source_unit: self.catalog.snapshots[snapshot as usize].unit,
                arguments: call.arguments.clone(),
                constants: call.constants.clone(),
            };
            match batch.as_mut() {
                None => batch = Some(CheckedBodySpecializationBatch::single(specialization)
                    .map_err(|error| anyhow!("UNSUPPORTED: native replay environment: {error:#}"))?),
                Some(batch) => ensure!(
                    batch.try_push(specialization)
                        .map_err(|error| anyhow!("UNSUPPORTED: native replay environment: {error:#}"))?,
                    "replay batch exceeds the shared packet capacity"),
            }
            let end = obligations
                .first
                .checked_add(obligations.count)
                .ok_or_else(|| anyhow!("replay obligation span overflow"))?;
            let evidence = self
                .evidence
                .get(obligations.first as usize..end as usize)
                .ok_or_else(|| anyhow!("replay origin has no complete retained evidence span"))?
                .iter()
                .map(|proof| {
                    ensure!(proof.is_concrete(), "concrete replay origin retains symbolic evidence");
                    Ok(proof.clone())
                })
                .collect::<Result<Vec<_>>>()?;
            let context = self
                .packet
                .packet_mut()?
                .replay_context(ReplayContextInput {
                    snapshot,
                    selected_owner_hir,
                    evidence: &evidence,
                    origin_call,
                })?;
            entries.push((selected_owner_hir, context));
        }
        let target_snapshot = target_snapshot.expect("nonempty batch");
        let template = self.catalog.snapshots.get(target_snapshot as usize)
            .ok_or_else(|| anyhow!("replay target snapshot has no retained template"))?
            .original_facts.clone();
        // GPU checks each new context against the exact origin environment and
        // retained evidence before the frontend can defer a local-only lookup.
        self.check()?;
        Ok(ValidatedReplayRequest {
            session: self,
            template,
            target_snapshot,
            selected_hirs: entries.iter().map(|&(hir, _)| hir).collect(),
            entries,
            specialization: batch.expect("nonempty batch"),
            identity: Arc::new(()),
        })
    }
}

/// See `NativeProgramSession::replay_scope`.
#[derive(Clone)]
pub(in crate::compiler::gpu_compiler) struct ReplayScope {
    pub snapshot: u32,
    pub selected_owner_hir: u32,
    /// (catalog owner, [(binding slot, domain 0 = type / 1 = constant)]),
    /// innermost owner first.
    pub owners: Vec<(u32, Vec<(u32, u32)>)>,
}

/// Private constructor and immutable snapshot identity prevent source text,
/// numeric IDs, or arbitrary call vectors from authorizing native publication.
pub(in crate::compiler::gpu_compiler) struct ValidatedOriginalUnit {
    facts: OriginalUnitFacts,
    calls: Vec<AdmittedCall>,
}

impl ValidatedOriginalUnit {
    pub fn check_original_unit(self, facts: &OriginalUnitFacts) -> Result<Vec<AdmittedCall>> {
        ensure!(self.facts.same_snapshot(facts), "original publication receipt belongs to another snapshot");
        Ok(self.calls)
    }
}

/// Private construction ties every frontend input to one GPU-admitted origin.
/// The mutable session borrow remains held through compilation and fresh checks.
pub(in crate::compiler::gpu_compiler) struct ValidatedReplayRequest<'session> {
    session: &'session mut NativeProgramSession,
    template: OriginalUnitFacts,
    target_snapshot: u32,
    /// (selected owner HIR, replay context) per batch entry, in entry order.
    entries: Vec<(u32, u32)>,
    selected_hirs: Vec<u32>,
    specialization: CheckedBodySpecializationBatch,
    identity: Arc<()>,
}

impl<'session> ValidatedReplayRequest<'session> {
    pub fn template(&self) -> &OriginalUnitFacts {
        &self.template
    }
    pub fn specialization(&self) -> &CheckedBodySpecializationBatch {
        &self.specialization
    }
    /// The first entry's callable: frontend predicate checks use it only to
    /// know that an authorized replay is active.
    pub fn selected_function_hir(&self) -> u32 {
        self.selected_hirs[0]
    }
    pub fn selected_function_hirs(&self) -> &[u32] {
        &self.selected_hirs
    }
    pub fn identity(&self) -> Arc<()> {
        self.identity.clone()
    }

    pub fn finish(
        self,
        pending: PendingReplayUnit,
    ) -> Result<(CompiledSourcePackUnit, Vec<AdmittedCall>)> {
        pending.finish(self)
    }

    /// This method releases no object. Only typecheck's private PendingReplayUnit
    /// can publish its privately constructed compilation after this succeeds.
    pub fn check_replay_unit(
        self,
        unit: &mut CompiledSourcePackUnit,
        request_identity: &Arc<()>,
    ) -> Result<Vec<AdmittedCall>> {
        ensure!(
            Arc::ptr_eq(&self.identity, request_identity),
            "replay result belongs to another checked request"
        );
        self.session.ready()?;
        let selected: BTreeMap<u32, u32> = self.entries.iter().copied().collect();
        normalize_omitted_batch_template_calls(
            &self.session.catalog, self.target_snapshot,
            &selected.keys().copied().collect(), unit,
        )?;
        self.session
            .packet
            .packet_mut()?
            .append_replay_batch_calls(unit, &selected)?;
        self.session.check()?;
        let packet = self.session.packet.packet_mut()?;
        let mut calls = packet.admitted_batch_calls(self.target_snapshot, &selected)?;
        for &context in selected.values() {
            calls.extend(packet.admitted_context_calls(self.target_snapshot, context)?);
        }
        Ok(calls)
    }
}

/// Scratch replay substitutes the selected enclosing impl environment in
/// the whole source unit. Only the selected generic body may be published;
/// other generic bodies remain templates. Ordinary local helpers remain in
/// text because direct calls use already emitted relative displacements.
/// Check that native publication boundary before discarding scratch facts.
#[cfg(test)]
pub(super) fn normalize_omitted_template_calls(
    catalog: &FrozenCatalog,
    target_snapshot: u32,
    selected_owner_hir: u32,
    unit: &mut CompiledSourcePackUnit,
) -> Result<()> {
    normalize_omitted_batch_template_calls(
        catalog, target_snapshot, &BTreeSet::from([selected_owner_hir]), unit)
}

/// The same boundary for a batched replay: every selected body may be published.
///
/// Every template call keeps its owner. The replay may add generic calls: a
/// bound-member call whose now-concrete receiver selects a generic impl
/// method (methods/09). A selected body keeps them; in another generic body
/// they are dropped with that body's other scratch facts.
pub(super) fn normalize_omitted_batch_template_calls(
    catalog: &FrozenCatalog,
    target_snapshot: u32,
    selected_owner_hirs: &BTreeSet<u32>,
    unit: &mut CompiledSourcePackUnit,
) -> Result<()> {
    let frozen = &catalog.snapshots[target_snapshot as usize];
    ensure!(
        Arc::ptr_eq(&frozen.contracts, &unit.checked_contracts)
            && Arc::ptr_eq(&frozen.sources, &unit.template_sources)
            && frozen.source_paths.as_ref() == unit.template_source_paths.as_ref()
            && Arc::ptr_eq(&frozen.dependency_pages, &unit.template_dependency_pages),
        "replay emission does not retain frozen definition provenance"
    );
    let owners = accepted_call_owners(unit)?;
    ensure!(frozen.call_owner_by_hir.iter().all(|(call, owner)| owners.get(call) == Some(owner)),
        "replay emission changed the complete source occurrence inventory");
    let mut omitted_hirs = BTreeSet::new();
    let mut omitted_symbols = BTreeSet::new();
    let mut callable_symbols = BTreeSet::new();
    for owner in &frozen.contracts.binders {
        let Some(callable) = owner.callable else { continue };
        ensure!(callable_symbols.insert(callable.native_symbol),
            "frozen callable identities are not unique");
        if selected_owner_hirs.contains(&owner.source_hir) { continue; }
        let catalog_owner = catalog.owner(target_snapshot, owner.source_hir)?;
        if !catalog.composed_parameters(catalog_owner)?.is_empty() {
            omitted_hirs.insert(owner.source_hir);
            omitted_symbols.insert(callable.native_symbol);
        }
    }
    let CompiledSourcePackObject::X86_64(object) = &unit.object else {
        return Err(anyhow!("replay emission has the wrong target"));
    };
    object.validate().map_err(anyhow::Error::msg)?;
    ensure!([object.library_id, object.unit_id] == frozen.unit,
        "replay emission has the wrong source unit");
    let mut undefined_count = 0usize;
    let mut definitions_started = false;
    for symbol in &object.symbols {
        if symbol.section == GpuX86ObjectSection::Undefined {
            ensure!(!definitions_started, "native undefined symbols are not a prefix");
            undefined_count += 1;
            continue;
        }
        definitions_started = true;
        let start = symbol.identity_byte_start as usize;
        let bytes = &object.identity_bytes[start..start + symbol.identity_byte_len as usize];
        ensure!(bytes.len() == 12, "native definition has no checked callable identity");
        let identity = [
            u32::from_le_bytes(bytes[0..4].try_into().unwrap()),
            u32::from_le_bytes(bytes[4..8].try_into().unwrap()),
            u32::from_le_bytes(bytes[8..12].try_into().unwrap()),
        ];
        ensure!(identity[..2] == frozen.unit,
            "native definition belongs to another source unit");
        ensure!(callable_symbols.contains(&identity[2]),
            "replay producer emitted a definition outside the frozen callable inventory");
        ensure!(!omitted_symbols.contains(&identity[2]),
            "replay producer emitted a non-selected generic body");
    }
    ensure!(unit.x86_call_hirs.len() == undefined_count,
        "replay native call inventory does not match undefined symbols");
    ensure!(unit.x86_call_function_hirs.len() == undefined_count,
        "replay native owner inventory does not match undefined symbols");
    for (&hir, &owner) in unit.x86_call_hirs.iter().zip(unit.x86_call_function_hirs.iter()) {
        if owner != u32::MAX {
            let accepted_owner = catalog.owner(target_snapshot, owner)?;
            ensure!(catalog.callable_by_owner.contains_key(&accepted_owner),
                "replay native call has no accepted lexical callable");
        }
        if let Some(&generic_owner) = owners.get(&hir) {
            ensure!(generic_owner == owner,
                "native and generic call ownership disagree");
        }
        ensure!(!omitted_hirs.contains(&owner),
            "replay producer retained a call from a non-selected generic body");
    }
    let originals: BTreeMap<_, _> = frozen.original_calls.iter()
        .map(|call| (call.call_hir, call)).collect();
    let mut published = Vec::with_capacity(unit.generic_calls.len());
    let mut dropped = BTreeSet::new();
    for call in unit.generic_calls.iter() {
        let owner = owners[&call.call_hir];
        if !frozen.call_owner_by_hir.contains_key(&call.call_hir) {
            if selected_owner_hirs.contains(&owner) {
                published.push(call.clone());
            } else {
                ensure!(omitted_hirs.contains(&owner),
                    "replay added a generic call outside the selected body");
                dropped.insert(call.call_hir);
            }
        } else if omitted_hirs.contains(&owner) {
            published.push((*originals.get(&call.call_hir).ok_or_else(||
                anyhow!("omitted template has no original checked call"))?).clone());
        } else {
            published.push(call.clone());
        }
    }
    // Selected body facts remain fresh. Ordinary helper facts still pass
    // the packet's exact comparison against their admitted originals.
    unit.generic_calls = published.into();
    if !dropped.is_empty() {
        unit.checked_call_owners = unit.checked_call_owners.iter()
            .filter(|owner| !dropped.contains(&owner.call_hir)).copied().collect();
    }
    Ok(())
}


/// Missing implementations remain a source diagnostic. Invalid input, resource
/// exhaustion, unsupported graphs and ambiguity keep their distinct GPU cause.
pub(in crate::compiler::gpu_compiler) fn native_program_error(
    error: anyhow::Error,
) -> CompileError {
    let missing = error
        .downcast_ref::<EvidenceDispatchFailure>()
        .and_then(|failure| failure.obligation)
        .is_some_and(|(_, status)| status[0] == 3);
    if missing {
        if let Some(site) = error.downcast_ref::<RetainedCallSite>() {
            let [start, len] = site.checked_call().source_span;
            let files =
                source_pack_diagnostic_files(site.source_texts(), Some(site.source_paths()));
            if let Some(file) = source_pack_file_for_global_span(&files, start as usize) {
                if len != 0
                    && (start as usize)
                        .checked_add(len as usize)
                        .is_some_and(|end| end <= file.global_end)
                {
                    return CompileError::Diagnostic(
                        Diagnostic::error("LNC0008", "unsatisfied trait bound").with_primary_label(
                            diagnostic_label_from_source_span(
                                &file.path,
                                &file.source,
                                start as usize - file.global_start,
                                len as usize,
                                "no matching impl satisfies this call",
                            ),
                        ),
                    );
                }
            }
        }
        return CompileError::Diagnostic(
            Diagnostic::error(
                "LNC0017",
                "program trait failure has no valid retained call source span",
            )
            .with_note(format!("{error:#}")),
        );
    }
    CompileError::Diagnostic(
        Diagnostic::error("LNC0017", "program trait evidence checking failed")
            .with_note(format!("{error:#}")),
    )
}
