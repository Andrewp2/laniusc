//! Native program checking owns its frozen catalog and every replay capability.
//! Neither source reparsing nor an existing native body can waive this gate.

use std::{collections::{BTreeMap, BTreeSet}, sync::Arc};

use anyhow::{Result, anyhow, ensure};

use super::{
    catalog::{CatalogInput, FrozenCatalog, FrozenSnapshot, accepted_call_owners},
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
        BodyImplBinding,
        CheckedBodySpecialization,
        CheckedBodySpecializationBatch,
        CheckedGenericCall,
        CheckedGenericTarget,
        CheckedUnitContracts,
        BlankingDirection,
        TemplateBlanking,
    },
    codegen::{lowering::ReplaySelection, x86::{GpuX86ObjectSection, GpuX86RelocatableObject}},
};

pub(in crate::compiler::gpu_compiler) struct NativeProgramSession {
    catalog: Arc<FrozenCatalog>,
    gpu: GpuProgramEvidence,
    packet: GpuPacket,
    /// Global obligation order; hypotheses have no concrete replay capability.
    evidence: Vec<ValidatedEvidence>,
    poisoned: bool,
    /// Admitted origins of each unit's instance closure (D1), by unit:
    /// (instantiation depth, origin call).
    closure_origins: BTreeMap<[u32; 2], Vec<(u32, AdmittedCall)>>,
    /// Closure instances decoded, closed, appended as calls, and admitted
    /// concrete, summed over units (trace only).
    closure_stats: [usize; 4],
}

impl NativeProgramSession {
    pub fn admit(
        workspace: &EvidenceWorkspacePool,
        units: &[OriginalUnitFacts],
    ) -> Result<Self> {
        // Facts contain no object. Freeze the complete exact source inventory
        // before any pending unit can be released or native bodies reused.
        let inputs = units.iter().map(|facts| CatalogInput { facts }).collect::<Vec<_>>();
        let start = std::time::Instant::now();
        let catalog = FrozenCatalog::freeze(&inputs)?;
        let frozen = std::time::Instant::now();
        crate::gpu::trace::record_host_span("host.compiler", "program_evidence.catalog_freeze", start, frozen);
        let gpu = GpuProgramEvidence::admit(workspace.checkout(), catalog.clone())?;
        crate::gpu::trace::record_host_span("host.compiler", "program_evidence.admit", frozen, std::time::Instant::now());
        let mut packet = gpu.new_packet()?;
        for snapshot in &catalog.snapshots {
            packet.packet_mut()?.append_original_unit_calls(&snapshot.original_facts)?;
        }
        // The instance closure's origins join the same check: each closed
        // instance is one call of its own; a bounded callee's predicates
        // are soft obligations, so a refuted bound demotes only that call.
        let mut closure_calls = Vec::new();
        let mut closure_stats = [0usize; 4];
        if instance_closure_enabled() {
            // A dependent's instances of a library body (D1b) are that
            // library snapshot's closure calls, after its own, merged over
            // the dependents in snapshot order without repeats.
            let mut dependency_calls = BTreeMap::<[u32; 2], Vec<(CheckedGenericCall, u32)>>::new();
            let mut dependency_seen = BTreeSet::<([u32; 2], u32, String)>::new();
            for snapshot in &catalog.snapshots {
                let Some(closure) = snapshot.original_facts.instance_closure() else { continue };
                closure_stats[0] += closure.dependency_instances.len();
                for instance in &closure.dependency_instances {
                    if instance.unit == snapshot.unit
                        || !dependency_seen.insert((instance.unit, instance.call.call_hir,
                            format!("{:?}{:?}", instance.call.arguments, instance.call.constants)))
                    {
                        continue;
                    }
                    dependency_calls.entry(instance.unit).or_default()
                        .push((instance.call.clone(), instance.depth));
                }
            }
            for (index, snapshot) in catalog.snapshots.iter().enumerate() {
                let local = snapshot.original_facts.instance_closure()
                    .map_or(&[][..], |closure| closure.instances.as_slice());
                closure_stats[0] += local.len();
                let (calls, depths): (Vec<_>, Vec<_>) = local.iter()
                    .map(|instance| (&instance.call, instance.depth))
                    .chain(dependency_calls.get(&snapshot.unit).into_iter().flatten()
                        .map(|(call, depth)| (call, *depth)))
                    .filter(|(call, _)| call.has_closed_arguments())
                    .map(|(call, depth)| (call.clone(), depth))
                    .unzip();
                if calls.is_empty() { continue; }
                closure_stats[1] += calls.len();
                let calls: Arc<[CheckedGenericCall]> = calls.into();
                let snapshot_index = u32::try_from(index)?;
                let appended = packet.packet_mut()?.append_closure_calls(snapshot_index, calls.clone())?;
                closure_stats[2] += appended.len();
                closure_calls.push((snapshot_index, snapshot.unit, calls, depths, appended));
            }
        }
        let mut result = Self {
            catalog,
            gpu,
            packet,
            evidence: Vec::new(),
            poisoned: false,
            closure_origins: BTreeMap::new(),
            closure_stats,
        };
        // An empty call inventory still requires catalog and batch admission.
        result.check()?;
        for (snapshot, unit, calls, depths, appended) in closure_calls {
            let packet = result.packet.packet_mut()?;
            let origins = appended.into_iter()
                .map(|(index, context)| Ok((depths[index],
                    packet.admitted_closure_call(snapshot, context, calls[index].call_hir)?)))
                .collect::<Result<Vec<_>>>()?;
            let origins = origins.into_iter().filter(|(_, call)| call.is_concrete()).collect::<Vec<_>>();
            result.closure_stats[3] += origins.len();
            result.closure_origins.insert(unit, origins);
        }
        Ok(result)
    }

    /// The admitted instance-closure origins of an original unit:
    /// (instantiation depth, origin call), in closure order.
    pub fn instance_closure_origins(&self, unit: [u32; 2]) -> &[(u32, AdmittedCall)] {
        self.closure_origins.get(&unit).map_or(&[], Vec::as_slice)
    }

    /// Closure instances decoded, closed, appended and admitted concrete.
    pub fn instance_closure_stats(&self) -> [usize; 4] {
        self.closure_stats
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

    /// The impl bindings of the body an origin call instantiates, as instance
    /// 0 (see `BodyImplBinding`). Each bound of the body's owner chain on a
    /// type slot that evidence proved with a nongeneric implementation outside
    /// the template unit gives one binding per implementation method. Bounds
    /// proved by an implementation of the template unit give none: 09 finds
    /// those in the replayed unit itself.
    pub fn instance_impl_bindings(&mut self, origin: &AdmittedCall) -> Result<Vec<BodyImplBinding>> {
        self.ready()?;
        let (_, snapshot, _, obligations) = self.packet.packet_mut()?.replay_origin(origin)?;
        let end = obligations.first.checked_add(obligations.count)
            .ok_or_else(|| anyhow!("replay obligation span overflow"))?;
        let evidence = self.evidence.get(obligations.first as usize..end as usize)
            .ok_or_else(|| anyhow!("replay origin has no complete retained evidence span"))?;
        impl_bindings(&self.catalog, self.catalog.snapshots[snapshot as usize].unit, evidence, 0)
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

    /// Where an origin's copy goes (`InstanceSources::copy_rank`), or None
    /// when its body replays in its original scope. A body can replay as a
    /// copy when its template retained the byte span of the selected
    /// callable and the copy, appended to the body's own file or to a
    /// continuation of it, resolves names in the body's module. A copy
    /// run's entries are in rank order.
    pub fn instance_copy_rank(&mut self, origin: &AdmittedCall) -> Result<Option<u32>> {
        self.ready()?;
        let (_, snapshot, selected_owner_hir, _) = self.packet.packet_mut()?.replay_origin(origin)?;
        let facts = &self.catalog.snapshots[snapshot as usize].original_facts;
        Ok(facts.owner_spans()
            .and_then(|spans| spans.get(selected_owner_hir))
            .and_then(|span| InstanceSources::copy_rank(facts.template_sources(), span)))
    }

    /// Why `instance_copy_rank` is None for an origin, for the
    /// specialization trace. A body without a retained span is a trait
    /// member or a trait-impl method with no inherent rendering, named by
    /// its implementation's self type when it has one.
    pub fn instance_copy_miss(&mut self, origin: &AdmittedCall) -> Result<String> {
        use crate::type_checker::CheckedGenericType as Type;
        self.ready()?;
        let (_, snapshot, owner_hir, _) = self.packet.packet_mut()?.replay_origin(origin)?;
        let facts = &self.catalog.snapshots[snapshot as usize].original_facts;
        let Some(spans) = facts.owner_spans() else {
            return Ok("the unit kept no owner spans".into());
        };
        if let Some(span) = spans.get(owner_hir) {
            return Ok(InstanceSources::copy_miss(facts.template_sources(), span).unwrap_or("copyable").into());
        }
        let unit = [facts.interface().library_id, facts.interface().unit_id];
        let subject = facts.checked_contracts().implementations.iter()
            .find(|implementation| implementation.method_bindings.iter().any(|binding| binding.method_hir == owner_hir))
            .map(|implementation| match &implementation.subject {
                Type::Scalar(_) => "scalar",
                Type::Parameter(_) => "type parameter",
                Type::Slice(_) => "slice",
                Type::Reference(_) => "reference",
                Type::Array { .. } => "array",
                Type::Nominal { identity, .. } if identity.unit() == unit => "local nominal",
                Type::Nominal { .. } => "foreign nominal",
                Type::Unresolved { .. } => "unresolved",
            });
        Ok(match subject {
            Some(kind) => format!("no span: trait-impl method, {kind} self type"),
            None => "no span: not a trait-impl method".into(),
        })
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

    /// A library instance-cache hit (D7b): the bodies of an earlier job's copy
    /// run, published again without a frontend run. Each origin must be a
    /// GPU-admitted concrete call of this job and gets its own replay context,
    /// exactly as `prepare_instance_batch` gives it; each cached copy's calls
    /// (`entry_facts`, in entry order) are appended under that context and this
    /// job's evidence must admit them again before anything patches them.
    /// The cached object may call outside its template only where this job's
    /// impl bindings name the callee. Returns the admitted calls in the order
    /// `check_instance_unit` returns them.
    pub fn admit_cached_instances(
        &mut self,
        origins: &[&AdmittedCall],
        template_unit: [u32; 2],
        entry_facts: &[Arc<[CheckedGenericCall]>],
        object: &GpuX86RelocatableObject,
    ) -> Result<Vec<AdmittedCall>> {
        self.ready()?;
        ensure!(!origins.is_empty() && origins.len() == entry_facts.len(),
            "cached instance run does not match its origins");
        let mut target_snapshot = None;
        let mut bindings = Vec::new();
        let mut contexts = Vec::with_capacity(origins.len());
        for (index, origin) in origins.iter().enumerate() {
            let (origin_call, snapshot, selected_owner_hir, obligations) =
                self.packet.packet_mut()?.replay_origin(origin)?;
            ensure!(*target_snapshot.get_or_insert(snapshot) == snapshot,
                "cached instance run spans several template snapshots");
            ensure!(self.catalog.snapshots[snapshot as usize].unit == template_unit,
                "cached instance run belongs to another template unit");
            let end = obligations.first.checked_add(obligations.count)
                .ok_or_else(|| anyhow!("replay obligation span overflow"))?;
            let evidence = self.evidence.get(obligations.first as usize..end as usize)
                .ok_or_else(|| anyhow!("replay origin has no complete retained evidence span"))?
                .iter()
                .map(|proof| {
                    ensure!(proof.is_concrete(), "concrete replay origin retains symbolic evidence");
                    Ok(proof.clone())
                })
                .collect::<Result<Vec<_>>>()?;
            bindings.extend(impl_bindings(&self.catalog, template_unit, &evidence, index as u32)?);
            let context = self.packet.packet_mut()?.replay_context(ReplayContextInput {
                snapshot,
                selected_owner_hir,
                evidence: &evidence,
                origin_call,
            })?;
            contexts.push((selected_owner_hir, context));
        }
        let snapshot = target_snapshot.expect("nonempty run");
        check_external_callees(&self.catalog.snapshots[snapshot as usize], object, &bindings)?;
        let mut call_hirs = Vec::with_capacity(contexts.len());
        for (&(selected_hir, context), facts) in contexts.iter().zip(entry_facts) {
            let indices = (0..facts.len()).collect::<Vec<_>>();
            self.packet.packet_mut()?.append_context_calls(
                snapshot, context, selected_hir, facts.clone(), &indices)?;
            call_hirs.push(facts.iter().map(|call| call.call_hir).collect::<Vec<_>>());
        }
        // One check covers the new contexts and their calls.
        self.check()?;
        let packet = self.packet.packet_mut()?;
        let mut admitted = Vec::new();
        for (&(_, context), call_hirs) in contexts.iter().zip(&call_hirs) {
            let context_calls = packet.admitted_context_calls(snapshot, context)?;
            ensure!(context_calls.len() == call_hirs.len()
                && context_calls.iter().zip(call_hirs).all(|(call, &hir)| call.source().call_hir == hir),
                "a cached instance copy's admitted calls differ from its appended calls");
            admitted.extend(context_calls);
        }
        Ok(admitted)
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
        let mut instance = if copies {
            let spans = template.owner_spans()
                .ok_or_else(|| anyhow!("template retained no owner spans for instance copies"))?;
            let selected = resolved.iter().map(|&(_, _, hir, _)| spans.get(hir).copied()
                .ok_or_else(|| anyhow!("selected body has no retained owner span")))
                .collect::<Result<Vec<_>>>()?;
            let sources = InstanceSources::build(template.template_sources(), &selected)?;
            let owners = selected.iter()
                .map(|span| (span.function_hir, span.enclosing_impl.map(|header| header.hir)))
                .collect();
            Some(InstanceRequest {
                sources: Arc::new(sources),
                first_copy_row: spans.hir_count,
                owners,
                declarations_only: None,
            })
        } else {
            None
        };
        let mut batch: Option<CheckedBodySpecializationBatch> = None;
        let mut entries: Vec<(u32, u32)> = Vec::with_capacity(origins.len());
        let mut bindings = Vec::new();
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
            bindings.extend(impl_bindings(&self.catalog, self.catalog.snapshots[snapshot as usize].unit,
                &evidence, index as u32)?);
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
            let template_files = u32::try_from(template.template_sources().len())
                .map_err(|_| anyhow!("template has too many source files"))?;
            specialization.set_continuation_files(template_files, instance.sources.continuations.clone())?;
        }
        specialization.set_impl_bindings(bindings)?;
        if let Some(instance) = instance.as_mut()
            && (declarations_only_templates_enabled() || declarations_only_templates_checked())
        {
            let unit = self.catalog.snapshots[target_snapshot as usize].unit;
            match DeclarationsOnlyTemplate::build(&template, unit, instance, &specialization, resolved[0].2) {
                Ok(template) => instance.declarations_only = template.map(Arc::new),
                Err(error) => if crate::gpu::env::env_bool_truthy("LANIUS_DEBUG_DECL_ONLY_TEMPLATES", false) {
                    eprintln!("[decl-only] unit {}:{} keeps its full template: {error:#}", unit[0], unit[1]);
                },
            }
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
    /// The same replay against the template with its function bodies left
    /// out, when that template could be built.
    declarations_only: Option<Arc<DeclarationsOnlyTemplate>>,
}

/// An instance-copy replay's frontend inputs in the copy space of a
/// declarations-only template (`TemplateBlanking`). The frontend checks
/// these; its results are converted back to the template's full space
/// before the request checks them, so everything after the frontend sees
/// the same identities as a replay against the full template.
pub(in crate::compiler::gpu_compiler) struct DeclarationsOnlyTemplate {
    pub blanking: TemplateBlanking,
    /// The instance sources with every blanked body's interior spaces.
    pub sources: Arc<[String]>,
    pub specialization: CheckedBodySpecializationBatch,
    pub contracts: Arc<CheckedUnitContracts>,
    /// The first copy row in copy space.
    pub first_copy_row: u32,
    pub selected_function_hir: u32,
}

impl DeclarationsOnlyTemplate {
    /// None when the template retained no body spans or has nothing to
    /// blank; an error when an input identity has no copy-space image.
    fn build(
        template: &OriginalUnitFacts,
        unit: [u32; 2],
        instance: &InstanceRequest,
        specialization: &CheckedBodySpecializationBatch,
        selected_function_hir: u32,
    ) -> Result<Option<Self>> {
        let Some(bodies) = template.owner_spans().and_then(|spans| spans.bodies.as_ref()) else {
            return Ok(None);
        };
        let full_contracts = template.checked_contracts();
        let Some(blanking) = TemplateBlanking::new(unit, bodies, full_contracts)? else {
            return Ok(None);
        };
        let map = blanking.map(BlankingDirection::ToCopy);
        let (removed_tokens, removed_rows) = blanking.removed();
        let first_copy_row = instance.first_copy_row.checked_sub(removed_rows)
            .ok_or_else(|| anyhow!("blanked rows exceed the template's rows"))?;
        let specialization = specialization.declarations_only(&map, first_copy_row, removed_tokens)?;
        let mut contracts = CheckedUnitContracts::clone(full_contracts);
        map.contracts(&mut contracts)?;
        let selected_function_hir = map.row(selected_function_hir)?;
        let sources = blanking.blank_sources(&instance.sources.sources)?.into();
        Ok(Some(Self { blanking, sources, specialization, contracts: Arc::new(contracts), first_copy_row,
            selected_function_hir }))
    }
}

/// `LANIUS_DECL_ONLY_TEMPLATES=0` replays instance copies against the full
/// template text (the kill switch).
pub(in crate::compiler::gpu_compiler) fn declarations_only_templates_enabled() -> bool {
    crate::gpu::env::env_bool_truthy("LANIUS_DECL_ONLY_TEMPLATES", true)
}

/// `LANIUS_CHECK_DECL_ONLY_TEMPLATES=1` compiles every copy replay against
/// both templates and fails on any difference, then keeps the full one.
pub(in crate::compiler::gpu_compiler) fn declarations_only_templates_checked() -> bool {
    crate::gpu::env::env_bool_truthy("LANIUS_CHECK_DECL_ONLY_TEMPLATES", false)
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
    /// Per entry of an instance-copy replay, the checked calls of its copy
    /// as appended under its replay context (the library instance cache
    /// keeps them so a later job can admit them again).
    pub entry_facts: Option<Vec<Arc<[CheckedGenericCall]>>>,
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
    /// The declarations-only template of an instance-copy replay.
    pub fn declarations_only(&self) -> Option<&DeclarationsOnlyTemplate> {
        self.instance.as_ref().and_then(|instance| instance.declarations_only.as_deref())
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
        check_external_callees(&self.session.catalog.snapshots[self.target_snapshot as usize],
            unit_object(unit)?, self.specialization.impl_bindings())?;
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
        Ok(CheckedReplayCalls { calls, entry_hirs: self.selected_hirs, copy_symbols: None, entry_facts: None })
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
        if crate::type_checker::instance_table_checked() {
            report_instance_table(frozen.unit, self.template.instance_closure(),
                unit.instance_closure.as_deref(), &self.specialization, &instance.owners);
        }
        let callable_symbols = frozen.contracts.binders.iter()
            .filter_map(|owner| owner.callable.map(|callable| callable.native_symbol))
            .collect::<BTreeSet<_>>();
        check_external_callees(frozen, unit_object(unit)?, self.specialization.impl_bindings())?;
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
        let mut kept_facts = Vec::with_capacity(self.entries.len());
        for (index, &(selected_hir, context)) in self.entries.iter().enumerate() {
            let entry_facts: Arc<[CheckedGenericCall]> = std::mem::take(&mut facts[index]).into();
            kept_facts.push(entry_facts.clone());
            let call_hirs = entry_facts.iter().map(|call| call.call_hir).collect::<Vec<_>>();
            published.extend(entry_facts.iter().cloned());
            // A copy's calls are context calls of its entry, owned by the
            // template body the copy reproduces.
            let indices = (0..entry_facts.len()).collect::<Vec<_>>();
            self.session.packet.packet_mut()?.append_context_calls(
                self.target_snapshot, context, selected_hir, entry_facts, &indices)?;
            calls.push((context, call_hirs));
        }
        unit.generic_calls = published.into();
        self.session.check()?;
        let packet = self.session.packet.packet_mut()?;
        let mut admitted = Vec::new();
        for (context, call_hirs) in calls {
            let context_calls = packet.admitted_context_calls(self.target_snapshot, context)?;
            ensure!(context_calls.len() == call_hirs.len()
                && context_calls.iter().zip(&call_hirs).all(|(call, &hir)| call.source().call_hir == hir),
                "an instance copy's admitted calls differ from its appended calls");
            admitted.extend(context_calls);
        }
        Ok(CheckedReplayCalls { calls: admitted, entry_hirs, copy_symbols: Some(copy_symbols),
            entry_facts: Some(kept_facts) })
    }
}


/// `ty` with every array length that is a count written as a u32 count.
fn lengths_as_counts(ty: crate::type_checker::CheckedGenericType) -> crate::type_checker::CheckedGenericType {
    use crate::type_checker::{CheckedGenericApplicationArgument as Argument, CheckedGenericType as Type};
    use crate::type_checker::CheckedGenericConstantValue as Value;
    match ty {
        Type::Array { element, length, words } => {
            let length = match length {
                Value::Literal(value) => value.count()
                    .and_then(|count| crate::constant_value::CheckedConstantValue::from_words(
                        crate::primitive_types::SCALAR_U32, [count, 0]))
                    .map_or(Value::Literal(value), Value::Literal),
                other => other,
            };
            Type::Array { element: Box::new(lengths_as_counts(*element)), length, words }
        }
        Type::Slice(element) => Type::Slice(Box::new(lengths_as_counts(*element))),
        Type::Reference(target) => Type::Reference(Box::new(lengths_as_counts(*target))),
        Type::Nominal { identity, arguments, words, local_replay } => Type::Nominal {
            identity,
            arguments: arguments.into_iter().map(|argument| match argument {
                Argument::Type(ty) => Argument::Type(lengths_as_counts(ty)),
                other => other,
            }).collect(),
            words,
            local_replay,
        },
        other => other,
    }
}

/// The instance table's validation (D2, `LANIUS_CHECK_INSTANCE_TABLE=1`):
/// each copy of this run against the original job's table entry for the
/// same template function and arguments, row by row, as decoded types.
/// It only reports, on stderr; nothing depends on the table yet.
///
/// Array lengths compare as counts, as canonical array identity does (a
/// realized length is a u32 count; a copy keeps its constant's scalar):
/// rows equal that way are counted apart too.
///
/// Parameter rows (HIR kind 4) are counted apart: their expression slot
/// holds the row's scalar cache, which differs between jobs for the same
/// copy. Lowering takes a parameter's type from its type row; whether any
/// reader uses the parameter row's slot is for D5's accessor audit.
///
/// Return statement rows (HIR kind 9) are counted apart as well. A copy's
/// slot is its scalar cache, which expression_types/00_init fills by reading
/// the statement's payload as an expression form (HIR_STMT_RETURN and
/// HIR_EXPR_NAME are both 2). Readers checked (10-19): lowering's
/// materialize types a return from its function's result and its value row
/// (payload.b) and sizes it from the function's result words, overriding
/// what the row's own slot gave; 00_project's value type of the row is read
/// only for value, store and match operations; the checker's return
/// validation reads payload.b; the other expression-ref readers
/// (call_args, aggregate_elements, place_mark, receiver_*, count,
/// local_mark, local_scatter, match_reference, function_layout_*,
/// function_templates, compact_expr, compact_aggregate_requests,
/// inference_expression_reference, 08_validate_call_args, 01a/01b) index
/// expression, type, pattern or declaration rows.
///
/// Calls (D3, instance_row_calls): a row naming a callee entry must be a
/// retained generic call of the copy whose target is that entry's function
/// and whose arguments are the entry's; a row the table leaves to the
/// template's callee, or routes to a nongeneric method, must have no
/// retained generic call; a dependency call must be one into a dependency.
/// Unresolved rows (today: calls on a type parameter that a replay routes
/// to an implementation outside this unit, such as an imported trait's)
/// are counted.
fn report_instance_table(
    unit: [u32; 2],
    template: Option<&crate::type_checker::CheckedInstanceClosure>,
    copies: Option<&crate::type_checker::CheckedInstanceClosure>,
    specialization: &CheckedBodySpecializationBatch,
    owners: &[(u32, Option<u32>)],
) {
    use crate::type_checker::{CheckedGenericTarget, CheckedRowFact};
    // instance_row_calls kinds (closure/instance_table.slang, IT_CALL_*).
    const IT_CALL_NONE: u32 = 0;
    const IT_CALL_ENTRY: u32 = 1;
    const IT_CALL_METHOD: u32 = 2;
    const IT_CALL_UNRESOLVED: u32 = 3;
    const IT_CALL_DEPENDENCY: u32 = 4;
    const HIR_PARAM: u32 = 4;
    const HIR_RETURN_STMT: u32 = 9;
    let label = format!("[instance-table] unit {}:{}", unit[0], unit[1]);
    let Some(table) = template.and_then(|closure| closure.table.as_ref()) else {
        eprintln!("{label} no table: template closure {}, found {}, flags {:#x}, error {:?}, {} copies",
            if template.is_some() { "present" } else { "absent" },
            template.map_or(0, |closure| closure.found), template.map_or(0, |closure| closure.flags),
            template.and_then(|closure| closure.error.as_ref()), specialization.entries().len());
        return;
    };
    if let Some(error) = copies.and_then(|closure| closure.error.as_ref()) {
        eprintln!("{label} copy rows failed: {error}");
    }
    let mut entries = table.entries.clone();
    for entry in &mut entries {
        entry.scope(unit);
    }
    let copy_rows = copies.map_or(&[][..], |closure| closure.copy_rows.as_slice());
    let [mut matched, mut unmatched, mut missing, mut lengths] = [0usize; 4];
    let [mut rows, mut equal, mut differ, mut undecoded, mut params, mut counts, mut returns] = [0usize; 7];
    // Calls: equal (entry, method, none, dependency), differ, unresolved.
    let [mut call_entries, mut call_methods, mut call_dependencies, mut call_differ, mut unresolved] = [0usize; 5];
    for (index, (entry, &(function, _))) in specialization.entries().iter().zip(owners).enumerate() {
        let Some(found) = entries.iter()
            .find(|candidate| candidate.is_instance(function, &entry.arguments, &entry.constants, unit))
        else {
            unmatched += 1;
            if unmatched <= 3 {
                let same = entries.iter().filter(|candidate| candidate.function_row == function)
                    .map(|candidate| format!("{:?}", candidate.arguments)).collect::<Vec<_>>();
                eprintln!("{label} copy {index} (function {function}) has no table entry: {:?}; \
                    entries of that function: {same:?}", entry.arguments);
            }
            continue;
        };
        matched += 1;
        let Some(copy) = copy_rows.get(index) else {
            missing += 1;
            continue;
        };
        if copy.len() != found.rows.len() {
            lengths += 1;
            eprintln!("{label} copy {index} (function {function}) has {} rows, its entry {}",
                copy.len(), found.rows.len());
            continue;
        }
        let copy_calls = copies.and_then(|closure| closure.copy_calls.get(index))
            .map_or(&[][..], Vec::as_slice);
        for (row, &[kind, value]) in found.calls.iter().enumerate() {
            let retained = copy_calls.iter().find(|(offset, _)| *offset == row).map(|(_, call)| call);
            let agrees = match (kind, retained) {
                (IT_CALL_NONE, None) => true,
                (IT_CALL_METHOD, None) => { call_methods += 1; true }
                (IT_CALL_ENTRY, Some(call)) => entries.get(value as usize).is_some_and(|callee| {
                    matches!(call.target, CheckedGenericTarget::Local { function_start_token, .. }
                        if function_start_token == callee.function_token)
                        && callee.is_instance(callee.function_row, &call.arguments, &call.constants, unit)
                }) && { call_entries += 1; true },
                (IT_CALL_DEPENDENCY, Some(call)) => matches!(call.target,
                    CheckedGenericTarget::Dependency { .. } | CheckedGenericTarget::DependencyMethod { .. })
                    && { call_dependencies += 1; true },
                (IT_CALL_UNRESOLVED, _) => { unresolved += 1; true }
                _ => false,
            };
            if !agrees {
                call_differ += 1;
                if call_differ <= 4 {
                    let callee = (kind == IT_CALL_ENTRY).then(|| entries.get(value as usize)).flatten()
                        .map(|callee| (callee.function_row, callee.function_token, &callee.arguments, &callee.constants));
                    eprintln!("{label} copy {index} function {function} call row +{row}: table ({kind}, {value}) \
                        callee {callee:?}; copy {:?}", retained.map(|call| (&call.target, &call.arguments, &call.constants)));
                }
            }
        }
        let kinds = copies.and_then(|closure| closure.copy_row_kinds.get(index));
        for (row, (expected, actual)) in found.rows.iter().zip(copy).enumerate() {
            let mut actual = actual.clone();
            actual.scope(unit);
            let kind = kinds.and_then(|kinds| kinds.get(row)).copied();
            rows += 1;
            match (expected, &actual) {
                _ if *expected == actual => equal += 1,
                _ if kind == Some(HIR_PARAM) => params += 1,
                _ if kind == Some(HIR_RETURN_STMT) => returns += 1,
                (CheckedRowFact::Type(left), CheckedRowFact::Type(right))
                    if lengths_as_counts(left.clone()) == lengths_as_counts(right.clone()) => counts += 1,
                (CheckedRowFact::Undecoded(_), CheckedRowFact::Undecoded(_)) => undecoded += 1,
                _ => {
                    differ += 1;
                    if differ <= 8 {
                        eprintln!("{label} copy {index} function {function} row +{row} kind {kind:?}: \
                            table {expected:?}; copy {actual:?}");
                        if crate::gpu::env::env_bool_truthy("LANIUS_DEBUG_INSTANCE_TABLE", false) {
                            eprintln!("{label} copy {index} constants: table {:?}; copy {:?}",
                                found.constants, entry.constants);
                        }
                    }
                }
            }
        }
    }
    eprintln!(
        "{label} entries={} flags={} failed={} copies={} matched={matched} unmatched={unmatched} \
         missing_rows={missing} length_mismatch={lengths} rows={rows} equal={equal} differ={differ} \
         param_rows_differ={params} return_rows_differ={returns} array_count_equal={counts} \
         both_undecoded={undecoded} call_entries={call_entries} call_methods={call_methods} \
         call_dependencies={call_dependencies} call_unresolved={unresolved} call_differ={call_differ}",
        table.entries.len(), table.flags, table.failed, specialization.entries().len(),
    );
}

/// See `NativeProgramSession::instance_impl_bindings`; `instance` numbers the
/// rows. Copies GPU-selected implementations and their accepted method
/// bindings; selects and compares nothing. Proportional to the origin's
/// evidence: an implementation of the template unit costs one lookup.
fn impl_bindings(
    catalog: &FrozenCatalog,
    template_unit: [u32; 2],
    evidence: &[ValidatedEvidence],
    instance: u32,
) -> Result<Vec<BodyImplBinding>> {
    let mut bindings = Vec::new();
    for proof in evidence {
        let Some(implementation) = proof.implementation else { continue };
        if catalog.implementation_unit(implementation)? == template_unit { continue; }
        let Some(slot) = catalog.predicate_subject_slot(proof.predicate_row)? else { continue };
        let Some(methods) = catalog.implementation_method_targets(implementation)? else { continue };
        for method in methods {
            if method.target[..2] == template_unit { continue; }
            bindings.push(BodyImplBinding {
                instance,
                slot,
                required_symbol: method.required_symbol,
                trait_unit: if method.trait_unit == template_unit { [u32::MAX; 2] } else { method.trait_unit },
                target: method.target,
            });
        }
    }
    Ok(bindings)
}

/// A replay object may call outside its template unit only into the units the
/// template imports, or into an implementation method that one of the
/// replay's impl bindings names (methods/09 routes bound members there).
fn check_external_callees(
    frozen: &FrozenSnapshot,
    object: &GpuX86RelocatableObject,
    bindings: &[BodyImplBinding],
) -> Result<()> {
    let imports = frozen.dependency_pages.iter().flatten()
        .map(|artifact| [artifact.library_id, artifact.unit_id])
        .collect::<BTreeSet<_>>();
    let targets = bindings.iter().map(|binding| binding.target).collect::<BTreeSet<_>>();
    for symbol in object.symbols.iter().filter(|symbol| symbol.section == GpuX86ObjectSection::Undefined) {
        let start = symbol.identity_byte_start as usize;
        let Some(bytes) = object.identity_bytes.get(start..start + symbol.identity_byte_len as usize)
            .filter(|bytes| bytes.len() == 12) else { continue };
        let identity = [
            u32::from_le_bytes(bytes[0..4].try_into().unwrap()),
            u32::from_le_bytes(bytes[4..8].try_into().unwrap()),
            u32::from_le_bytes(bytes[8..12].try_into().unwrap()),
        ];
        let unit = [identity[0], identity[1]];
        ensure!(unit == frozen.unit || imports.contains(&unit) || targets.contains(&identity),
            "replay calls {identity:?} outside its template's imports, and no implementation binding names it");
    }
    Ok(())
}

fn unit_object(unit: &CompiledSourcePackUnit) -> Result<&GpuX86RelocatableObject> {
    match &unit.object {
        CompiledSourcePackObject::X86_64(object) => Ok(object),
        _ => Err(anyhow!("replay emission has the wrong target")),
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
/// `LANIUS_INSTANCE_CLOSURE=0` leaves the instance closure's origins out of
/// program admission, so every deeper body waits for a later replay round.
pub(in crate::compiler::gpu_compiler) fn instance_closure_enabled() -> bool {
    crate::gpu::env::env_bool_truthy("LANIUS_INSTANCE_CLOSURE", true)
}

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
