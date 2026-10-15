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
        gpu_compiler::instance_copies::InstanceSources,
    },
    type_checker::{
        BODY_COPY_TARGET,
        CheckedBodySpecialization,
        CheckedBodySpecializationBatch,
        CheckedGenericCall,
        CheckedGenericTarget,
    },
    codegen::{lowering::ReplaySelection, x86::GpuX86ObjectSection},
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
        self.prepare_batch(origins, false)
    }

    /// Whether an origin's body can replay as an instance copy: its template
    /// retained the byte span of the selected callable.
    pub fn instance_copy_available(&mut self, origin: &AdmittedCall) -> Result<bool> {
        self.ready()?;
        let (_, snapshot, selected_owner_hir, _) = self.packet.packet_mut()?.replay_origin(origin)?;
        Ok(self.catalog.snapshots[snapshot as usize].original_facts.owner_spans()
            .is_some_and(|spans| spans.get(selected_owner_hir).is_some()))
    }

    /// Like `prepare_replay_batch`, but every origin replays a renamed copy of
    /// its body appended after the template text, so origins may share one
    /// lexical scope. Each copy is checked under its origin's own context.
    pub fn prepare_instance_batch<'session>(
        &'session mut self,
        origins: &[&AdmittedCall],
    ) -> Result<ValidatedReplayRequest<'session>> {
        self.prepare_batch(origins, true)
    }

    fn prepare_batch<'session>(
        &'session mut self,
        origins: &[&AdmittedCall],
        copies: bool,
    ) -> Result<ValidatedReplayRequest<'session>> {
        self.ready()?;
        ensure!(!origins.is_empty(), "replay batch has no origin");
        let mut target_snapshot = None;
        let mut resolved = Vec::with_capacity(origins.len());
        for origin in origins {
            let (origin_call, snapshot, selected_owner_hir, obligations) =
                self.packet.packet_mut()?.replay_origin(origin)?;
            ensure!(*target_snapshot.get_or_insert(snapshot) == snapshot,
                "replay batch spans several template snapshots");
            ensure!(copies || resolved.iter().all(|&(_, _, hir, _)| hir != selected_owner_hir),
                "replay batch selects one lexical body twice");
            resolved.push((origin_call, snapshot, selected_owner_hir, obligations));
        }
        let target_snapshot = target_snapshot.expect("nonempty batch");
        let template = self.catalog.snapshots.get(target_snapshot as usize)
            .ok_or_else(|| anyhow!("replay target snapshot has no retained template"))?
            .original_facts.clone();
        // The copies come only from the frozen template text and the byte
        // spans its own check retained.
        let instance = if copies {
            let spans = template.owner_spans()
                .ok_or_else(|| anyhow!("template retained no owner spans for instance copies"))?;
            let selected = resolved.iter().map(|&(_, _, hir, _)| spans.get(hir).copied()
                .ok_or_else(|| anyhow!("selected body has no retained owner span")))
                .collect::<Result<Vec<_>>>()?;
            let sources = InstanceSources::build(template.template_sources(), &selected)?;
            let owners = selected.iter()
                .map(|span| (span.function_hir, span.inherent_impl.map(|(row, _, _)| row)))
                .collect();
            Some(InstanceRequest { sources: Arc::new(sources), first_copy_row: spans.hir_count, owners })
        } else {
            None
        };
        let mut batch: Option<CheckedBodySpecializationBatch> = None;
        let mut entries: Vec<(u32, u32)> = Vec::with_capacity(origins.len());
        for (index, (origin, &(origin_call, snapshot, selected_owner_hir, obligations))) in
            origins.iter().zip(&resolved).enumerate()
        {
            let call = origin.checked_call();
            let specialization = CheckedBodySpecialization {
                target_symbol: match (&instance, call.target) {
                    (Some(instance), _) => BODY_COPY_TARGET | instance.sources.copies[index].fn_byte,
                    (None, CheckedGenericTarget::Local {
                        specialization_symbol,
                        ..
                    }) => specialization_symbol,
                    (None, CheckedGenericTarget::Dependency {
                        declaration_index, ..
                    }) => declaration_index,
                    (None, CheckedGenericTarget::DependencyMethod { method_symbol, .. }) => method_symbol,
                },
                source_unit: self.catalog.snapshots[snapshot as usize].unit,
                arguments: call.arguments.clone(),
                constants: call.constants.clone(),
            };
            ensure!(specialization.target_symbol & BODY_COPY_TARGET != BODY_COPY_TARGET || instance.is_some(),
                "an original replay target uses the instance-copy selector");
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
        let mut specialization = batch.expect("nonempty batch");
        if let Some(instance) = &instance {
            specialization.set_instance_copies(instance.first_copy_row, instance.owners.clone())?;
        }
        // GPU checks each new context against the exact origin environment and
        // retained evidence before the frontend can defer a local-only lookup.
        self.check()?;
        Ok(ValidatedReplayRequest {
            session: self,
            template,
            target_snapshot,
            selected_hirs: entries.iter().map(|&(hir, _)| hir).collect(),
            entries,
            specialization,
            identity: Arc::new(()),
            instance,
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
    /// An instance-copy replay checks these copies instead of the template's
    /// own bodies.
    instance: Option<InstanceRequest>,
}

struct InstanceRequest {
    sources: Arc<InstanceSources>,
    /// The template's HIR row count: every copy row is at or past it.
    first_copy_row: u32,
    /// Per copy: the template function HIR and a method's template impl HIR.
    owners: Vec<(u32, Option<u32>)>,
}

/// The calls a replay admitted and where its published bodies are.
pub(in crate::compiler::gpu_compiler) struct CheckedReplayCalls {
    pub calls: Vec<AdmittedCall>,
    /// Per entry, the lexical callable HIR of its body in the replay unit:
    /// the selected template HIR, or the copy's row (u32::MAX for a copy
    /// with no generic call, which nothing looks up).
    pub entry_hirs: Vec<u32>,
    /// Per entry of an instance-copy replay, the native symbol of its copy's
    /// definition in the replay object.
    pub copy_symbols: Option<Vec<u32>>,
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
    /// The bodies the replay object may hold.
    pub fn replay_selection(&self) -> ReplaySelection<'_> {
        match &self.instance {
            Some(instance) => ReplaySelection::CopiesFrom(instance.first_copy_row),
            None => ReplaySelection::Functions(&self.selected_hirs),
        }
    }
    /// The source files the frontend checks: the template's, or the template's
    /// with the instance copies appended.
    pub fn frontend_sources(&self) -> &Arc<[String]> {
        match &self.instance {
            Some(instance) => &instance.sources.sources,
            None => self.template.template_sources(),
        }
    }
    pub fn instance_sources(&self) -> Option<&Arc<InstanceSources>> {
        self.instance.as_ref().map(|instance| &instance.sources)
    }
    pub fn identity(&self) -> Arc<()> {
        self.identity.clone()
    }

    pub fn finish(
        self,
        pending: PendingReplayUnit,
    ) -> Result<(CompiledSourcePackUnit, CheckedReplayCalls)> {
        pending.finish(self)
    }

    /// This method releases no object. Only typecheck's private PendingReplayUnit
    /// can publish its privately constructed compilation after this succeeds.
    pub fn check_replay_unit(
        self,
        unit: &mut CompiledSourcePackUnit,
        request_identity: &Arc<()>,
    ) -> Result<CheckedReplayCalls> {
        ensure!(
            Arc::ptr_eq(&self.identity, request_identity),
            "replay result belongs to another checked request"
        );
        self.session.ready()?;
        if self.instance.is_some() {
            return self.check_instance_unit(unit);
        }
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
        let calls = self.session.packet.packet_mut()?.admitted_batch_calls(self.target_snapshot, &selected)?;
        Ok(CheckedReplayCalls { calls, entry_hirs: self.selected_hirs, copy_symbols: None })
    }

    /// An instance-copy replay publishes exactly one definition per copy and
    /// only calls from the copies. Each copy's calls are checked under its
    /// entry's replay context; the template part of the unit is discarded.
    fn check_instance_unit(self, unit: &mut CompiledSourcePackUnit) -> Result<CheckedReplayCalls> {
        let instance = self.instance.as_ref().expect("instance replay");
        let first_row = instance.first_copy_row;
        let copies = &instance.sources;
        let catalog = &self.session.catalog;
        let frozen = &catalog.snapshots[self.target_snapshot as usize];
        ensure!(
            Arc::ptr_eq(&frozen.contracts, &unit.checked_contracts)
                && Arc::ptr_eq(&frozen.sources, &unit.template_sources)
                && frozen.source_paths.as_ref() == unit.template_source_paths.as_ref()
                && Arc::ptr_eq(&frozen.dependency_pages, &unit.template_dependency_pages),
            "instance replay does not retain frozen definition provenance"
        );
        let callable_symbols = frozen.contracts.binders.iter()
            .filter_map(|owner| owner.callable.map(|callable| callable.native_symbol))
            .collect::<BTreeSet<_>>();
        let CompiledSourcePackObject::X86_64(object) = &unit.object else {
            return Err(anyhow!("replay emission has the wrong target"));
        };
        object.validate().map_err(anyhow::Error::msg)?;
        ensure!([object.library_id, object.unit_id] == frozen.unit,
            "replay emission has the wrong source unit");
        let identity_of = |symbol: &crate::codegen::x86::GpuX86ObjectSymbolRecord| -> Option<[u32; 3]> {
            let start = symbol.identity_byte_start as usize;
            let bytes = object.identity_bytes.get(start..start + symbol.identity_byte_len as usize)?;
            (bytes.len() == 12).then(|| [
                u32::from_le_bytes(bytes[0..4].try_into().unwrap()),
                u32::from_le_bytes(bytes[4..8].try_into().unwrap()),
                u32::from_le_bytes(bytes[8..12].try_into().unwrap()),
            ])
        };
        let mut undefined_count = 0usize;
        let mut definitions_started = false;
        let mut copy_symbols = Vec::with_capacity(self.entries.len());
        for symbol in &object.symbols {
            let identity = identity_of(symbol);
            if symbol.section == GpuX86ObjectSection::Undefined {
                ensure!(!definitions_started, "native undefined symbols are not a prefix");
                undefined_count += 1;
                // A call into this unit links against the original object, so
                // it must name a callable of the frozen template.
                if let Some(identity) = identity.filter(|identity| identity[..2] == frozen.unit) {
                    ensure!(callable_symbols.contains(&identity[2]),
                        "instance copy calls a callable outside the template inventory");
                }
                continue;
            }
            definitions_started = true;
            if symbol.section != GpuX86ObjectSection::Text { continue; }
            let identity = identity.ok_or_else(|| anyhow!("native definition has no checked callable identity"))?;
            ensure!(identity[..2] == frozen.unit, "native definition belongs to another source unit");
            ensure!(identity[2] & 0xc000_0000 == 0x4000_0000 && !callable_symbols.contains(&identity[2]),
                "instance replay emitted a definition that is not a private copy");
            copy_symbols.push(identity[2]);
        }
        // Copies are private functions named by their first token, which
        // increases with the entry index.
        copy_symbols.sort_unstable();
        ensure!(copy_symbols.len() == self.entries.len()
            && copy_symbols.windows(2).all(|pair| pair[0] < pair[1]),
            "instance replay must define exactly one body per copy");
        ensure!(unit.x86_call_hirs.len() == undefined_count
            && unit.x86_call_function_hirs.len() == undefined_count,
            "replay native call inventory does not match undefined symbols");

        let owners = unit.checked_call_owners.iter()
            .map(|owner| (owner.call_hir, owner.function_hir)).collect::<BTreeMap<_, _>>();
        let mut facts = vec![Vec::<CheckedGenericCall>::new(); self.entries.len()];
        let mut entry_hirs = vec![u32::MAX; self.entries.len()];
        for call in unit.generic_calls.iter() {
            let owner = *owners.get(&call.call_hir)
                .ok_or_else(|| anyhow!("checked call missing actual owner"))?;
            let entry = copies.copy_at(call.source_span[0]);
            if owner == u32::MAX || owner < first_row {
                // Template facts are not published; the template's own
                // admission already covers them.
                ensure!(entry.is_none(), "a call inside a copy has a template owner");
                continue;
            }
            let entry = entry.ok_or_else(|| anyhow!("a copy-owned call lies outside every copy"))?;
            let span = copies.original_body_span(entry, call.source_span)
                .ok_or_else(|| anyhow!("a copy call span leaves its copied body"))?;
            ensure!(call.call_hir >= first_row, "a copy call precedes the copy rows");
            let slot = &mut entry_hirs[entry];
            if *slot == u32::MAX { *slot = owner; }
            ensure!(*slot == owner, "one copy's calls have several lexical owners");
            let mut translated = call.clone();
            translated.source_span = span;
            facts[entry].push(translated);
        }
        let rows = entry_hirs.iter().copied().filter(|&row| row != u32::MAX).collect::<BTreeSet<_>>();
        ensure!(rows.len() == entry_hirs.iter().filter(|&&row| row != u32::MAX).count(),
            "two copies share one lexical owner");
        let generic_owner = unit.generic_calls.iter()
            .map(|call| (call.call_hir, owners[&call.call_hir])).collect::<BTreeMap<_, _>>();
        for (&hir, &owner) in unit.x86_call_hirs.iter().zip(unit.x86_call_function_hirs.iter()) {
            ensure!(owner != u32::MAX && owner >= first_row,
                "instance replay emitted a call outside the copies");
            if let Some(&generic) = generic_owner.get(&hir) {
                ensure!(generic == owner, "native and generic call ownership disagree");
            }
        }
        let mut calls = Vec::new();
        let mut published = Vec::new();
        for (index, &(selected_hir, context)) in self.entries.iter().enumerate() {
            let entry_facts: Arc<[CheckedGenericCall]> = std::mem::take(&mut facts[index]).into();
            let call_hirs = entry_facts.iter().map(|call| call.call_hir).collect::<Vec<_>>();
            published.extend(entry_facts.iter().cloned());
            self.session.packet.packet_mut()?.append_instance_calls(
                self.target_snapshot, selected_hir, context, first_row, entry_facts)?;
            calls.push((selected_hir, context, call_hirs));
        }
        unit.generic_calls = published.into();
        self.session.check()?;
        let packet = self.session.packet.packet_mut()?;
        let mut admitted = Vec::new();
        for (selected_hir, context, call_hirs) in calls {
            admitted.extend(packet.admitted_instance_calls(
                self.target_snapshot, selected_hir, context, &call_hirs)?);
        }
        Ok(CheckedReplayCalls { calls: admitted, entry_hirs, copy_symbols: Some(copy_symbols) })
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
    ensure!(owners == frozen.call_owner_by_hir,
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
    let mut published = unit.generic_calls.to_vec();
    for call in &mut published {
        if omitted_hirs.contains(&owners[&call.call_hir]) {
            *call = (*originals.get(&call.call_hir).ok_or_else(||
                anyhow!("omitted template has no original checked call"))?).clone();
        }
    }
    // Selected body facts remain fresh. Ordinary helper facts still pass
    // the packet's exact comparison against their admitted originals.
    unit.generic_calls = published.into();
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
