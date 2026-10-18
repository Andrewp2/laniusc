//! Resident scheduling of concrete bodies from GPU-checked call environments.
//!
//! Allocate unused native unit identities for ordered checked type environments,
//! keeping durable object records and the native ABI unchanged. The GPU emitter
//! supplies the HIR-to-symbol relation; this controller does not inspect source
//! or infer types from target instructions.

use std::{
    borrow::Cow,
    collections::{BTreeMap, BTreeSet, HashMap, HashSet},
};

use super::{
    program_evidence::{AdmittedCall, NativeProgramSession, ReplayScope, native_program_error},
    typecheck::{CompiledSourcePackObject, CompiledSourcePackUnit, OriginalUnitFacts, PendingOriginalUnit},
    *,
};
use crate::type_checker::{CheckedBodySpecialization, CheckedGenericCall, CheckedGenericTarget};

/// A concrete body instantiated from another concrete body is one level
/// deeper. Finite programs stay far below this; reaching it means an
/// instantiation chain that keeps growing its type arguments (polymorphic
/// recursion), which has no finite monomorphization.
const MAX_INSTANTIATION_DEPTH: u32 = 64;

impl GpuCompiler<'_> {
    pub(super) async fn specialize_x86_source_pack_objects<'a>(
        &self,
        units: &[&'a CompiledSourcePackUnit],
    ) -> Result<Vec<Cow<'a, x86::GpuX86RelocatableObject>>, CompileError> {
        // Repeated references to one compiled object retain one exact fact
        // identity. Independent objects with equal numeric IDs stay distinct.
        let mut by_object = BTreeMap::<*const CompiledSourcePackUnit, OriginalUnitFacts>::new();
        let facts = units.iter().map(|unit| {
            let key = *unit as *const CompiledSourcePackUnit;
            if let Some(facts) = by_object.get(&key) { return Ok(facts.clone()); }
            let facts = unit.original_facts()?;
            by_object.insert(key, facts.clone());
            Ok(facts)
        }).collect::<anyhow::Result<Vec<_>>>().map_err(native_program_error)?;
        let mut program = NativeProgramSession::admit(
            &self.program_evidence_workspace, &facts).map_err(native_program_error)?;
        let calls = facts.iter().map(|facts|
            program.validated_original(facts)?.check_original_unit(facts))
            .collect::<anyhow::Result<Vec<_>>>().map_err(native_program_error)?;
        self.specialize_admitted_x86_source_pack_objects(units, program, calls).await
    }

    /// Pending originals expose only facts until this complete catalog and
    /// original-call batch pass. Released objects enter the shared scheduler.
    pub(super) async fn specialize_pending_x86_source_pack_objects(
        &self,
        pending: Vec<PendingOriginalUnit>,
    ) -> Result<Vec<x86::GpuX86RelocatableObject>, CompileError> {
        let facts = pending.iter().map(|unit| unit.facts().clone()).collect::<Vec<_>>();
        let mut program = NativeProgramSession::admit(
            &self.program_evidence_workspace, &facts).map_err(native_program_error)?;
        let released = pending.into_iter().zip(&facts).map(|(unit, facts)|
            unit.finish(program.validated_original(facts)?))
            .collect::<anyhow::Result<Vec<_>>>().map_err(native_program_error)?;
        let (units, calls): (Vec<_>, Vec<_>) = released.into_iter().unzip();
        let references = units.iter().collect::<Vec<_>>();
        let objects = self.specialize_admitted_x86_source_pack_objects(&references, program, calls).await?;
        Ok(objects.into_iter().map(Cow::into_owned).collect())
    }

    async fn specialize_admitted_x86_source_pack_objects<'a>(
        &self,
        units: &[&'a CompiledSourcePackUnit],
        mut program: NativeProgramSession,
        initial_calls: Vec<Vec<AdmittedCall>>,
    ) -> Result<Vec<Cow<'a, x86::GpuX86RelocatableObject>>, CompileError> {
        if units.len() != initial_calls.len() {
            return Err(CompileError::GpuCodegen("admitted source inventory is incomplete".into()));
        }
        let mut templates = BTreeMap::new();
        // The defined symbol identities of each template object, so the scan
        // finds a call's tag-only definition without walking every symbol.
        let mut defined_identities = BTreeMap::<(u32, u32), HashSet<&'a [u8]>>::new();
        let mut objects = Vec::with_capacity(units.len());
        let mut used_units = BTreeSet::new();
        for &unit in units {
            let CompiledSourcePackObject::X86_64(object) = &unit.object else {
                return Err(CompileError::GpuCodegen(
                    "resident x86 specialization received a different target".into(),
                ));
            };
            templates.insert((unit.interface.library_id, unit.interface.unit_id), unit);
            used_units.insert((object.library_id, object.unit_id));
            // Like `templates`, the last unit with a given identity wins.
            let mut defined = HashSet::new();
            for symbol in &object.symbols {
                let identity = symbol_identity(object, symbol);
                if symbol.section != x86::GpuX86ObjectSection::Undefined {
                    defined.insert(identity);
                }
                if identity.len() == 12 {
                    used_units.insert((
                        u32::from_le_bytes(identity[..4].try_into().unwrap()),
                        u32::from_le_bytes(identity[4..8].try_into().unwrap()),
                    ));
                }
            }
            defined_identities.insert((unit.interface.library_id, unit.interface.unit_id), defined);
            objects.push(Cow::Borrowed(object));
        }
        let mut specializations = BTreeMap::<Vec<u8>, (Vec<u8>, Vec<u32>)>::new();
        let mut next_unit_by_library = BTreeMap::<u32, u32>::new();
        let mut specialized_text_bytes = 0usize;
        let mut contexts = units.iter().zip(initial_calls).map(|(unit, calls)| ReplayContext {
            library_id: unit.interface.library_id,
            unit_id: unit.interface.unit_id,
            calls,
            call_hirs: unit.x86_call_hirs.clone(),
            call_owners: unit.x86_call_function_hirs.clone(),
            entries: BTreeMap::new(),
        }).collect::<Vec<_>>();
        let mut trace = SpecializationTrace::new();
        let batch_limit = replay_batch_limit();
        let instance_copies = instance_copies_enabled();
        // Breadth-first rounds: scan every context of the frontier, then
        // replay the round's new environments with compatible scopes of one
        // template unit sharing a frontend run, then patch the round's calls.
        let mut round_start = 0usize;
        while round_start < contexts.len() {
            let round_end = contexts.len();
            let scan_started = std::time::Instant::now();
            let mut pending = BTreeMap::<Vec<u8>, PendingBody>::new();
            let mut patches = Vec::<(usize, usize, Vec<u8>)>::new();
            for context_index in round_start..round_end {
                let context = &contexts[context_index];
                let (owner_library, owner_unit) = (context.library_id, context.unit_id);
                let calls_by_hir: BTreeMap<_, _> = context.calls
                    .iter()
                    .map(|call| (call.checked_call().call_hir, call))
                    .collect();
                for (symbol_index, &call_hir) in context.call_hirs.iter().enumerate() {
                    let Some(&admitted) = calls_by_hir.get(&call_hir) else {
                        if context_index >= units.len() {
                            trace.skipped(context_index, call_hir, "no admitted generic call", None);
                        }
                        continue;
                    };
                    let call = admitted.checked_call();
                    let Some((library_id, unit_id, declaration_index)) =
                        native_target(call.target, owner_library, owner_unit)
                    else {
                        if context_index >= units.len() {
                            trace.skipped(context_index, call_hir, "no native target", Some(call));
                        }
                        continue;
                    };
                    let Some(defined) = defined_identities.get(&(library_id, unit_id)) else {
                        if context_index >= units.len() {
                            trace.skipped(context_index, call_hir, "no template unit", Some(call));
                        }
                        continue;
                    };
                    let identity = declaration_identity(library_id, unit_id, declaration_index);
                    // A reusable native body does not waive the declaration's
                    // generic requirements. Validate unused parameters too, before
                    // accepting tag-only definitions or scheduling a replay.
                    if !call.has_all_parameter_slots() {
                        return Err(CompileError::Diagnostic(Diagnostic::error(
                            "LNC0017",
                            "generic call is missing declared type or constant bindings",
                        )));
                    }
                    if defined.contains(identity.as_slice()) {
                        // Tag-only generic functions already have a valid body.
                        if context_index >= units.len() {
                            trace.skipped(context_index, call_hir, "tag-only definition", Some(call));
                        }
                        continue;
                    }
                    let target = (library_id, unit_id, declaration_index);
                    let caller = context.call_owners.get(symbol_index).copied().unwrap_or(u32::MAX);
                    let environment = checked_replay_environment(call, owner_library, owner_unit)
                        .map_err(|error| {
                            // An environment that outgrows the checked type graph
                            // while a body instantiates its own declaration again is
                            // polymorphic recursion, not a capacity problem.
                            if instantiates_ancestor(&contexts, context_index, caller, target) {
                                instantiation_depth_error(
                                    call, templates.get(&(owner_library, owner_unit)).copied(), Some(error))
                            } else {
                                error
                            }
                        })?;
                    let Some((concrete_identity, concrete_layouts)) = environment else {
                        // A symbolic call belongs to an uninstantiated template.
                        // Its concrete replay will supply a new call environment.
                        if context_index >= units.len() {
                            trace.skipped(context_index, call_hir, "symbolic environment", Some(call));
                        }
                        continue;
                    };
                    let symbol = objects[context_index]
                        .symbols
                        .get(symbol_index)
                        .ok_or_else(|| {
                            CompileError::GpuCodegen("native call symbol is absent".into())
                        })?;
                    if symbol.section != x86::GpuX86ObjectSection::Undefined
                        || symbol_identity(&objects[context_index], symbol) != identity
                    {
                        return Err(CompileError::GpuCodegen(
                            "native call identity disagrees with its checked generic environment"
                                .into(),
                        ));
                    }
                    if let Some((_, layouts)) = specializations.get_mut(&concrete_identity) {
                        CheckedBodySpecialization::merge_layout_witnesses(layouts, &concrete_layouts)
                            .map_err(|error| CompileError::GpuCodegen(error.to_string()))?;
                        trace.reused += 1;
                    } else if let Some(body) = pending.get_mut(&concrete_identity) {
                        body.witnesses.push(concrete_layouts);
                        trace.reused += 1;
                    } else {
                        let depth = context.entry_depth(caller);
                        if depth >= MAX_INSTANTIATION_DEPTH {
                            return Err(instantiation_depth_error(
                                call, templates.get(&(owner_library, owner_unit)).copied(), None));
                        }
                        pending.insert(concrete_identity.clone(), PendingBody {
                            admitted: admitted.clone(),
                            target,
                            recursive: instantiates_ancestor(&contexts, context_index, caller, target),
                            origin: EntryOrigin {
                                depth: depth + 1,
                                parent: Some((context_index, caller)),
                                target,
                            },
                            witnesses: vec![concrete_layouts],
                        });
                    }
                    patches.push((context_index, symbol_index, concrete_identity));
                }
            }
            host_span("scan", scan_started);
            // Group by template unit, then pack compatible scopes greedily in
            // key order (deterministic: keys are canonical environments).
            let mut by_unit = BTreeMap::<(u32, u32), Vec<Vec<u8>>>::new();
            for (key, body) in &pending {
                by_unit.entry((body.target.0, body.target.1)).or_default().push(key.clone());
            }
            for keys in by_unit.into_values() {
                let plan_started = std::time::Instant::now();
                // A body with a retained declaration span replays as a
                // renamed copy, which shares a run with any other copy.
                // Polymorphic recursion replays alone, so a failure is its own.
                // A recursive body still replays as a copy when it can: an
                // original-scope replay rewrites the template method's own
                // rows, so a call in it that routes back to the same generic
                // impl (Twice<T>::area on a Twice<Rect> field) would find
                // only the rewritten, closed receiver pattern.
                // A copy run's entries are in copy rank order (the template's
                // last file, then continuation files by file), so keys are
                // sorted by rank, stably: within a rank they stay in key order.
                let mut ranked = Vec::with_capacity(keys.len());
                for key in keys {
                    let body = &pending[&key];
                    let rank = if instance_copies {
                        program.instance_copy_rank(&body.admitted).map_err(native_program_error)?
                    } else {
                        None
                    };
                    ranked.push((rank, key));
                }
                ranked.sort_by_key(|(rank, _)| rank.unwrap_or(0));
                let mut runs = Vec::<ReplayRun>::new();
                for (rank, key) in ranked {
                    let body = &pending[&key];
                    let scope = program.replay_scope(&body.admitted).map_err(native_program_error)?;
                    let entry = replay_entry(body.admitted.checked_call(), body.target);
                    let copies = rank.is_some();
                    // A run's impl bindings share one packet table, so a run
                    // closes before it would overflow it.
                    let bindings = program.instance_impl_bindings(&body.admitted)
                        .map_err(native_program_error)?.len();
                    if bindings > gpu_type_checker::MAX_BODY_IMPL_BINDINGS {
                        return Err(specialization_limit_error(&format!(
                            "one generic body needs {bindings} implementation bindings; a replay holds at most {}",
                            gpu_type_checker::MAX_BODY_IMPL_BINDINGS)));
                    }
                    let mut capped = false;
                    let placed = !body.recursive && runs.iter_mut().try_fold(false, |placed, run| {
                        // Original-scope runs stay small: their scopes are found by a linear search.
                        let limit = if run.copies {
                            batch_limit
                        } else {
                            batch_limit.min(gpu_type_checker::MAX_ORIGINAL_REPLAY_ENTRIES)
                        };
                        if placed || run.solo || run.copies != copies || run.keys.len() >= limit {
                            return Ok(placed);
                        }
                        if run.bindings + bindings > gpu_type_checker::MAX_BODY_IMPL_BINDINGS {
                            capped = true;
                            return Ok(false);
                        }
                        let added = run.try_add(&key, &scope, entry.clone())?;
                        if added { run.bindings += bindings; }
                        Ok(added)
                    }).map_err(|error: anyhow::Error| CompileError::GpuCodegen(error.to_string()))?;
                    if !placed {
                        let batch = gpu_type_checker::CheckedBodySpecializationBatch::single(entry)
                            .map_err(|error| CompileError::Diagnostic(
                                Diagnostic::error("LNC0017", "generic specialization cannot represent this environment")
                                    .with_note(error.to_string())))?;
                        runs.push(ReplayRun {
                            keys: vec![key], scopes: vec![scope], batch, solo: body.recursive, copies, bindings,
                            split: capped.then_some("impl-binding cap"),
                        });
                    }
                }
                host_span("plan", plan_started);
                for run in runs {
                    let started = std::time::Instant::now();
                    let origins = run.keys.iter().map(|key| &pending[key].admitted).collect::<Vec<_>>();
                    // A recursively growing environment fails wherever it first
                    // outgrows a limit; report it as the recursion it is.
                    let recursion = |error: CompileError| {
                        let body = &pending[&run.keys[0]];
                        if !run.solo || !is_capacity_failure(&error) { return error; }
                        let owner = body.origin.parent.map(|(context, _)|
                            (contexts[context].library_id, contexts[context].unit_id));
                        instantiation_depth_error(body.admitted.checked_call(),
                            owner.and_then(|owner| templates.get(&owner).copied()), Some(error))
                    };
                    let request = if run.copies {
                        program.prepare_instance_batch(&origins)
                    } else {
                        program.prepare_replay_batch(&origins)
                    }
                    .map_err(|error| recursion(native_program_error(error)))?;
                    let prepared = std::time::Instant::now();
                    let pending_unit = self
                        .compile_authorized_body_specialization(&request)
                        .await
                        .inspect_err(|_| trace.failed(&run.keys, &pending))
                        .map_err(&recursion)?;
                    let compiled = std::time::Instant::now();
                    let (replay, checked) = request.finish(pending_unit)
                        .inspect_err(|_| trace.failed(&run.keys, &pending))
                        .map_err(|error| recursion(native_program_error(error)))?;
                    let replay_calls = checked.calls;
                    let finished = std::time::Instant::now();
                    crate::gpu::trace::record_host_span("specialization", "prepare", started, prepared);
                    crate::gpu::trace::record_host_span("specialization", "compile", prepared, compiled);
                    crate::gpu::trace::record_host_span("specialization", "finish", compiled, finished);
                    let entry_layouts = replay.body_native_layouts.as_ref()
                        .filter(|layouts| layouts.len() == run.keys.len())
                        .ok_or_else(|| CompileError::GpuCodegen("concrete replay omitted admitted native layouts".into()))?
                        .clone();
                    let CompiledSourcePackObject::X86_64(mut concrete) = replay.object else {
                        unreachable!("body replay target is x86_64")
                    };
                    let (library_id, unit_id, _) = pending[&run.keys[0]].target;
                    let candidate = next_unit_by_library.entry(library_id).or_default();
                    while used_units.contains(&(library_id, *candidate)) {
                        *candidate = candidate.checked_add(1).ok_or_else(|| {
                            specialization_limit_error("no unused native unit identity")
                        })?;
                    }
                    let specialized_unit = *candidate;
                    used_units.insert((library_id, specialized_unit));
                    // A copy's definition is its own private callable; an
                    // original replay defines the declaration itself. The
                    // published identity keeps that symbol, so two copies of
                    // one declaration in a run stay distinct.
                    let definition_symbols = match &checked.copy_symbols {
                        Some(symbols) => symbols.clone(),
                        None => run.keys.iter().map(|key| pending[key].target.2).collect(),
                    };
                    let identities = definition_symbols.iter()
                        .map(|&symbol| declaration_identity(library_id, unit_id, symbol))
                        .collect::<Vec<_>>();
                    specialized_text_bytes = specialized_text_bytes
                        .checked_add(concrete.text.len())
                        .ok_or_else(|| specialization_limit_error("native text length overflow"))?;
                    // Undefined symbols precede definitions, so dropping other
                    // definitions preserves every relocation target index.
                    let published = identities.iter().map(Vec::as_slice).collect::<HashSet<_>>();
                    let keep: Vec<bool> = concrete
                        .symbols
                        .iter()
                        .map(|symbol| {
                            symbol.section == x86::GpuX86ObjectSection::Undefined
                                || published.contains(symbol_identity(&concrete, symbol))
                        })
                        .collect();
                    let mut index = 0;
                    concrete.symbols.retain(|_| {
                        let retain = keep[index];
                        index += 1;
                        retain
                    });
                    // Each key takes the first text definition still carrying
                    // its identity; a renamed definition no longer matches.
                    let mut definitions = HashMap::<Vec<u8>, Vec<usize>>::new();
                    for (index, symbol) in concrete.symbols.iter().enumerate().rev() {
                        if symbol.section == x86::GpuX86ObjectSection::Text {
                            definitions.entry(symbol_identity(&concrete, symbol).to_vec()).or_default().push(index);
                        }
                    }
                    let mut entries = BTreeMap::new();
                    for (position, key) in run.keys.iter().enumerate() {
                        let body = &pending[key];
                        let definition = definitions
                            .get_mut(&identities[position])
                            .and_then(Vec::pop)
                            .ok_or_else(|| {
                                let call = body.admitted.checked_call();
                                CompileError::GpuCodegen(format!(
                                    "concrete body replay produced no native definition for {:?} with {:?}",
                                    call.target, call.arguments
                                ))
                            })?;
                        let native_identity =
                            declaration_identity(library_id, specialized_unit, definition_symbols[position]);
                        replace_symbol_identity(&mut concrete, definition, &native_identity)?;
                        let mut admitted_layouts = entry_layouts[position].clone();
                        for witness in &body.witnesses {
                            CheckedBodySpecialization::merge_layout_witnesses(&mut admitted_layouts, witness)
                                .map_err(|error| CompileError::GpuCodegen(error.to_string()))?;
                        }
                        specializations.insert(key.clone(), (native_identity, admitted_layouts));
                        if checked.entry_hirs[position] != u32::MAX {
                            entries.insert(checked.entry_hirs[position], body.origin);
                        }
                    }
                    concrete.unit_id = specialized_unit;
                    concrete.entry_offset = None;
                    concrete
                        .validate()
                        .map_err(|error| CompileError::GpuCodegen(error))?;
                    host_span("publish", finished);
                    trace.replay(
                        &run.keys.iter().map(|key| (key.as_slice(), &pending[key])).collect::<Vec<_>>(),
                        specializations.len(), [started, prepared, compiled, finished],
                        concrete.text.len(), replay_calls.len(), run_kind(run.copies, run.solo),
                        run.bindings, run.split);
                    contexts.push(ReplayContext {
                        library_id,
                        unit_id,
                        calls: replay_calls,
                        call_hirs: replay.x86_call_hirs,
                        call_owners: replay.x86_call_function_hirs,
                        entries,
                    });
                    objects.push(Cow::Owned(concrete));
                }
            }
            let patch_started = std::time::Instant::now();
            for (context_index, symbol_index, key) in patches {
                replace_symbol_identity(
                    objects[context_index].to_mut(),
                    symbol_index,
                    &specializations[&key].0,
                )?;
            }
            host_span("patch", patch_started);
            round_start = round_end;
        }
        trace.finish(specializations.len(), specialized_text_bytes);
        Ok(objects)
    }
}

/// One object in the specialization worklist: an original unit's object or
/// a replay's. `entries` maps each body a replay published (its selected
/// callable HIR) to where that body was instantiated from.
struct ReplayContext {
    library_id: u32,
    unit_id: u32,
    calls: Vec<AdmittedCall>,
    call_hirs: std::sync::Arc<[u32]>,
    call_owners: std::sync::Arc<[u32]>,
    entries: BTreeMap<u32, EntryOrigin>,
}

impl ReplayContext {
    /// Instantiation depth of the body that owns a call: 0 in an original unit.
    fn entry_depth(&self, caller: u32) -> u32 {
        self.entries.get(&caller).map_or(0, |entry| entry.depth)
    }
}

#[derive(Clone, Copy)]
struct EntryOrigin {
    depth: u32,
    /// The context and calling body whose call instantiated this body.
    parent: Option<(usize, u32)>,
    /// This body's declaration (library, unit, declaration index).
    target: (u32, u32, u32),
}

/// A new environment found in the current round, replayed after the scan.
struct PendingBody {
    admitted: AdmittedCall,
    target: (u32, u32, u32),
    /// The body instantiates a declaration it was itself instantiated from
    /// (with another environment: equal environments reuse one body).
    recursive: bool,
    origin: EntryOrigin,
    /// Retained layout witnesses of every call site that needs this body.
    witnesses: Vec<Vec<u32>>,
}

/// Bodies of one template unit that share one frontend run.
struct ReplayRun {
    keys: Vec<Vec<u8>>,
    scopes: Vec<ReplayScope>,
    batch: gpu_type_checker::CheckedBodySpecializationBatch,
    /// A polymorphically recursive body, which never shares its run.
    solo: bool,
    /// Every body replays as an instance copy, so scopes may repeat.
    copies: bool,
    /// The impl bindings of the run's bodies (at most MAX_BODY_IMPL_BINDINGS).
    bindings: usize,
    /// Why the run's first body opened a new run although an open run had
    /// room for it (trace only).
    split: Option<&'static str>,
}

impl ReplayRun {
    /// Add a body when its scope differs from every scope in the run, every
    /// enclosing owner it shares with one binds identically, and the shared
    /// graph has room. Leaves the run unchanged otherwise.
    fn try_add(
        &mut self,
        key: &[u8],
        scope: &ReplayScope,
        entry: CheckedBodySpecialization,
    ) -> anyhow::Result<bool> {
        if self.copies {
            // Copies own their enclosing impls too, so nothing is shared and
            // only the snapshot must agree (every scope has the first one's).
            // `try_push` leaves the batch unchanged when the entry does not
            // fit, so a run of thousands of copies never clones its batch.
            if self.scopes.first().is_some_and(|first| first.snapshot != scope.snapshot)
                || !self.batch.try_push(entry)?
            {
                return Ok(false);
            }
        } else {
            if self.scopes.iter().any(|other| other.snapshot != scope.snapshot
                || other.selected_owner_hir == scope.selected_owner_hir)
            {
                return Ok(false);
            }
            // An original-scope run is small (MAX_ORIGINAL_REPLAY_ENTRIES);
            // a trial copy undoes a push whose shared owners bind differently.
            let mut batch = self.batch.clone();
            if !batch.try_push(entry)? {
                return Ok(false);
            }
            let added = batch.entries().len() - 1;
            for (index, other) in self.scopes.iter().enumerate() {
                for (owner, parameters) in &scope.owners {
                    if !other.owners.iter().any(|(shared, _)| shared == owner) { continue; }
                    if !parameters.iter().all(|&(slot, domain)|
                        batch.binds_identically(index, added, slot, domain))
                    {
                        return Ok(false);
                    }
                }
            }
            self.batch = batch;
        }
        self.keys.push(key.to_vec());
        self.scopes.push(scope.clone());
        Ok(true)
    }
}

/// The single-entry packet a body's replay would use (see prepare_replay_batch).
fn replay_entry(call: &CheckedGenericCall, target: (u32, u32, u32)) -> CheckedBodySpecialization {
    CheckedBodySpecialization {
        target_symbol: match call.target {
            CheckedGenericTarget::Local {
                specialization_symbol,
                ..
            } => specialization_symbol,
            _ => target.2,
        },
        source_unit: [target.0, target.1],
        arguments: call.arguments.clone(),
        constants: call.constants.clone(),
    }
}

/// A host span on the specialization lane of LANIUS_PERFETTO_TRACE, from
/// `start` to now.
fn host_span(name: &str, start: std::time::Instant) {
    crate::gpu::trace::record_host_span("specialization", name, start, std::time::Instant::now());
}

/// `LANIUS_REPLAY_COPIES=0` replays every body in its original scope instead
/// of as an instance copy.
fn instance_copies_enabled() -> bool {
    crate::gpu::env::env_bool_truthy("LANIUS_REPLAY_COPIES", true)
}

/// `LANIUS_REPLAY_BATCH=N` caps the bodies per frontend run (1 replays each
/// body alone, as before batching).
fn replay_batch_limit() -> usize {
    std::env::var("LANIUS_REPLAY_BATCH").ok()
        .and_then(|value| value.trim().parse::<usize>().ok())
        .filter(|&limit| limit > 0)
        .map_or(gpu_type_checker::MAX_BODY_ENTRIES, |limit| limit.min(gpu_type_checker::MAX_BODY_ENTRIES))
}

/// `LANIUS_DEBUG_SPECIALIZATION=1` prints one line per frontend replay run
/// (its bodies' key hashes and depths, phase times) and a summary per program.
struct SpecializationTrace {
    enabled: bool,
    start: std::time::Instant,
    reused: usize,
    runs: usize,
    /// Runs by kind: instance copies, original scope, polymorphic recursion.
    kinds: [usize; 3],
    phases_ms: [f64; 3],
}

/// Trace index of a run's kind: 0 copies, 1 original scope, 2 solo
/// (polymorphic recursion, in its original scope).
fn run_kind(copies: bool, solo: bool) -> usize {
    if solo { 2 } else if copies { 0 } else { 1 }
}

const RUN_KINDS: [&str; 3] = ["copies", "original", "solo"];

impl SpecializationTrace {
    fn new() -> Self {
        Self {
            enabled: crate::gpu::env::env_bool_truthy("LANIUS_DEBUG_SPECIALIZATION", false),
            start: std::time::Instant::now(),
            reused: 0,
            runs: 0,
            kinds: [0; 3],
            phases_ms: [0.0; 3],
        }
    }

    fn replay(
        &mut self,
        bodies: &[(&[u8], &PendingBody)],
        total: usize,
        times: [std::time::Instant; 4],
        text_bytes: usize,
        replay_calls: usize,
        kind: usize,
        bindings: usize,
        split: Option<&str>,
    ) {
        self.runs += 1;
        self.kinds[kind] += 1;
        if !self.enabled { return; }
        let ms = |a: std::time::Instant, b: std::time::Instant| b.duration_since(a).as_secs_f64() * 1000.0;
        let phases = [ms(times[0], times[1]), ms(times[1], times[2]), ms(times[2], times[3])];
        for (total, phase) in self.phases_ms.iter_mut().zip(phases) { *total += phase; }
        let (library, unit, _) = bodies[0].1.target;
        eprintln!(
            "[specialization] run={} kind={} unit={library}:{unit} bodies={} total={total} prepare={:.1}ms compile={:.1}ms finish={:.1}ms text={text_bytes} calls={replay_calls} impl_bindings={bindings}{}",
            self.runs, RUN_KINDS[kind], bodies.len(), phases[0], phases[1], phases[2],
            split.map(|why| format!(" split={why}")).unwrap_or_default(),
        );
        for (key, body) in bodies {
            let call = body.admitted.checked_call();
            eprintln!(
                "[specialization]   depth={} decl={} key={} args={:?} consts={:?}",
                body.origin.depth, body.target.2, &blake3::hash(key).to_hex()[..12],
                call.arguments, call.constants,
            );
        }
    }

    /// The bodies of a run whose replay failed. A run that succeeds prints
    /// them in `replay`, after its compile.
    fn failed(&self, keys: &[Vec<u8>], pending: &BTreeMap<Vec<u8>, PendingBody>) {
        if !self.enabled { return; }
        for key in keys {
            let body = &pending[key];
            let call = body.admitted.checked_call();
            eprintln!(
                "[specialization] failed depth={} target={:?} key={} args={:?} consts={:?} witnesses={:?}",
                body.origin.depth, body.target, &blake3::hash(key).to_hex()[..12],
                call.arguments, call.constants, body.witnesses,
            );
        }
    }

    /// A replay's native call that the scan leaves for the linker.
    fn skipped(&self, context: usize, call_hir: u32, why: &str, call: Option<&CheckedGenericCall>) {
        if !self.enabled { return; }
        match call {
            Some(call) => eprintln!(
                "[specialization]   skip context={context} call_hir={call_hir}: {why} target={:?} args={:?} consts={:?}",
                call.target, call.arguments, call.constants,
            ),
            None => eprintln!("[specialization]   skip context={context} call_hir={call_hir}: {why}"),
        }
    }

    fn finish(&self, bodies: usize, text_bytes: usize) {
        if !self.enabled { return; }
        eprintln!(
            "[specialization] summary bodies={bodies} runs={} copy_runs={} original_runs={} solo_runs={} reused_sites={} text={text_bytes} prepare={:.1}ms compile={:.1}ms finish={:.1}ms total={:.1}ms",
            self.runs, self.kinds[0], self.kinds[1], self.kinds[2], self.reused,
            self.phases_ms[0], self.phases_ms[1], self.phases_ms[2],
            self.start.elapsed().as_secs_f64() * 1000.0,
        );
    }
}

fn declaration_identity(library_id: u32, unit_id: u32, declaration_index: u32) -> Vec<u8> {
    [library_id, unit_id, declaration_index]
        .into_iter()
        .flat_map(u32::to_le_bytes)
        .collect()
}

/// Symbolic calls wait for their enclosing body to be instantiated. A closed
/// environment must either produce a checked replay packet or explain its
/// native boundary; silently falling through would misreport a missing symbol.
fn checked_replay_environment(
    call: &CheckedGenericCall,
    owner_library: u32,
    owner_unit: u32,
) -> Result<Option<(Vec<u8>, Vec<u32>)>, CompileError> {
    if !call.has_closed_arguments() {
        return Ok(None);
    }
    checked_specialization_identity(call, owner_library, owner_unit)
        .map(Some)
        .map_err(|error| {
            CompileError::Diagnostic(
                Diagnostic::error(
                    "LNC0017",
                    "generic specialization cannot represent this environment",
                )
                .with_note(error.to_string()),
            )
        })
}

fn checked_specialization_identity(
    call: &CheckedGenericCall,
    owner_library: u32,
    owner_unit: u32,
) -> anyhow::Result<(Vec<u8>, Vec<u32>)> {
    let Some((library_id, unit_id, declaration_index)) =
        native_target(call.target, owner_library, owner_unit)
    else {
        anyhow::bail!("body specialization requires a resolved native target")
    };
    let (types, layouts) = CheckedBodySpecialization {
        target_symbol: match call.target {
            CheckedGenericTarget::Local {
                specialization_symbol,
                ..
            } => specialization_symbol,
            _ => declaration_index,
        },
        source_unit: [library_id, unit_id],
        arguments: call.arguments.clone(),
        constants: call.constants.clone(),
    }
    .scheduling_environment()?;
    let mut identity = declaration_identity(library_id, unit_id, declaration_index);
    // A private scheduling key only. Native symbols keep the existing
    // three-word identity and receive an unused unit ID for each unique key.
    identity.extend_from_slice(b"LGS4");
    // The complete private graph is part of the key: equal descriptor widths
    // do not establish equal element types or nested array lengths.
    for word in types {
        identity.extend_from_slice(&word.to_le_bytes());
    }
    Ok((identity, layouts))
}

fn native_target(
    target: CheckedGenericTarget,
    owner_library: u32,
    owner_unit: u32,
) -> Option<(u32, u32, u32)> {
    match target {
        CheckedGenericTarget::Dependency {
            library_id,
            unit_id,
            declaration_index,
        } => Some((library_id, unit_id, declaration_index)),
        CheckedGenericTarget::DependencyMethod {
            library_id,
            unit_id,
            method_symbol,
        } => Some((library_id, unit_id, method_symbol)),
        CheckedGenericTarget::Local { native_symbol, .. } => {
            Some((owner_library, owner_unit, native_symbol))
        }
    }
}

fn symbol_identity<'a>(
    object: &'a x86::GpuX86RelocatableObject,
    symbol: &x86::GpuX86ObjectSymbolRecord,
) -> &'a [u8] {
    let start = symbol.identity_byte_start as usize;
    &object.identity_bytes[start..start + symbol.identity_byte_len as usize]
}

fn replace_symbol_identity(
    object: &mut x86::GpuX86RelocatableObject,
    index: usize,
    identity: &[u8],
) -> Result<(), CompileError> {
    let start = u32::try_from(object.identity_bytes.len())
        .map_err(|_| specialization_limit_error("symbol identity storage exceeds u32"))?;
    let len = u32::try_from(identity.len())
        .map_err(|_| specialization_limit_error("symbol identity length exceeds u32"))?;
    start
        .checked_add(len)
        .ok_or_else(|| specialization_limit_error("symbol identity range exceeds u32"))?;
    let symbol = object
        .symbols
        .get_mut(index)
        .ok_or_else(|| CompileError::GpuCodegen("specialization symbol is absent".into()))?;
    let (lo, hi) = crate::compiler::stable_name_hash(identity);
    symbol.identity_hash_lo = lo;
    symbol.identity_hash_hi = hi;
    symbol.identity_byte_start = start;
    symbol.identity_byte_len = len;
    object.identity_bytes.extend_from_slice(identity);
    Ok(())
}

/// Whether the body owning a call (`caller` in `context`), or a body it was
/// instantiated from, is a body of `target`.
fn instantiates_ancestor(
    contexts: &[ReplayContext],
    mut context: usize,
    mut caller: u32,
    target: (u32, u32, u32),
) -> bool {
    while let Some(entry) = contexts[context].entries.get(&caller) {
        if entry.target == target {
            return true;
        }
        let Some((parent, parent_caller)) = entry.parent else { return false };
        context = parent;
        caller = parent_caller;
    }
    false
}

/// Reported at the call that would instantiate one level past the limit, or
/// whose recursively grown environment no longer fits a checked type graph
/// (`capacity` holds that error).
fn instantiation_depth_error(
    call: &CheckedGenericCall,
    owner: Option<&CompiledSourcePackUnit>,
    capacity: Option<CompileError>,
) -> CompileError {
    let note = match &capacity {
        None => format!(
            "concrete generic bodies instantiate each other more than {MAX_INSTANTIATION_DEPTH} levels deep"
        ),
        Some(_) => "a generic body instantiates its own declaration with type arguments that keep growing".to_owned(),
    };
    let mut diagnostic = Diagnostic::error("LNC0073", "generic instantiation depth exceeded")
        .with_note(note);
    match &capacity {
        Some(CompileError::Diagnostic(inner)) => {
            for note in &inner.notes {
                diagnostic = diagnostic.with_note(note.clone());
            }
        }
        Some(CompileError::GpuFrontend(detail) | CompileError::GpuSyntax(detail)
            | CompileError::GpuTypeCheck(detail) | CompileError::GpuCodegen(detail)) => {
            diagnostic = diagnostic.with_note(detail.clone());
        }
        None => {}
    }
    diagnostic = diagnostic
        .with_help(
            "a generic function that calls itself with a larger type argument (polymorphic recursion) has no finite set of concrete bodies",
        );
    if let Some(unit) = owner {
        let [start, len] = call.source_span;
        let files = crate::compiler::source_pack_diagnostic_files(
            unit.template_sources.as_ref(), Some(unit.template_source_paths.as_ref()));
        if let Some(file) = crate::compiler::source_pack_file_for_global_span(&files, start as usize) {
            if (start as usize).checked_add(len as usize).is_some_and(|end| end <= file.global_end) {
                diagnostic = diagnostic.with_primary_label(crate::compiler::diagnostic_label_from_source_span(
                    &file.path,
                    &file.source,
                    start as usize - file.global_start,
                    len as usize,
                    "this call needs another level of concrete bodies",
                ));
            }
        }
    }
    CompileError::Diagnostic(diagnostic)
}

/// Whether a replay failed on a limit (an internal LNC0017 or an unmapped
/// stage error) rather than on a language diagnostic such as a missing impl.
fn is_capacity_failure(error: &CompileError) -> bool {
    match error {
        CompileError::Diagnostic(diagnostic) => diagnostic.code == "LNC0017",
        _ => true,
    }
}

fn specialization_limit_error(detail: &str) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0017", "generic specialization limit exceeded")
            .with_note(detail.to_owned()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::type_checker::{
        CheckedBinderIdentity,
        CheckedGenericArgument,
        CheckedGenericConstantValue,
        CheckedGenericParameter,
        CheckedGenericType,
        CheckedParameterDomain,
        CheckedParameterIdentity,
    };

    fn call(types: Vec<CheckedGenericType>) -> CheckedGenericCall {
        CheckedGenericCall {
            call_hir: 3,
            source_span: [0, 1],
            target: CheckedGenericTarget::Dependency {
                library_id: 1,
                unit_id: 2,
                declaration_index: 7,
            },
            required_generic_parameters: Some(types.len() as u32),
            required_constant_parameters: Some(0),
            arguments: types
                .into_iter()
                .enumerate()
                .map(|(slot, ty)| CheckedGenericArgument {
                    slot: slot as u32,
                    ty,
                })
                .collect(),
            constants: Vec::new(),
        }
    }

    #[test]
    fn a_copy_run_takes_every_copy_of_one_body_in_place() {
        let entry = |byte: u32, scalar: u32| CheckedBodySpecialization {
            target_symbol: crate::type_checker::BODY_COPY_TARGET | byte,
            source_unit: [0, 0],
            arguments: vec![CheckedGenericArgument { slot: 0, ty: CheckedGenericType::Scalar(scalar) }],
            constants: Vec::new(),
        };
        let scope = |snapshot: u32| ReplayScope { snapshot, selected_owner_hir: 9, owners: vec![(4, vec![(0, 0)])] };
        let run = |copies: bool| ReplayRun {
            keys: vec![vec![0]],
            scopes: vec![scope(1)],
            batch: gpu_type_checker::CheckedBodySpecializationBatch::single(entry(100, 3)).unwrap(),
            solo: false,
            copies,
            bindings: 0,
            split: None,
        };
        let mut copies = run(true);
        // Other environments of the same lexical body join a copy run.
        for (index, scalar) in [4u32, 5, 6].into_iter().enumerate() {
            assert!(copies.try_add(&[index as u8 + 1], &scope(1), entry(200 + index as u32, scalar)).unwrap());
        }
        assert_eq!((copies.batch.entries().len(), copies.keys.len(), copies.scopes.len()), (4, 4, 4));
        // Another template snapshot does not, and leaves the run unchanged.
        assert!(!copies.try_add(&[9], &scope(2), entry(300, 7)).unwrap());
        assert_eq!((copies.batch.entries().len(), copies.keys.len(), copies.scopes.len()), (4, 4, 4));
        // An original-scope run never selects one lexical body twice.
        let mut original = run(false);
        assert!(!original.try_add(&[1], &scope(1), entry(200, 4)).unwrap());
        assert_eq!(original.batch.entries().len(), 1);
    }

    #[test]
    fn specialization_identity_unifies_local_and_imported_references_to_one_body() {
        let imported = call(vec![CheckedGenericType::Scalar(3)]);
        let mut local = imported.clone();
        local.target = CheckedGenericTarget::Local {
            function_start_token: 17,
            generic_parameter_count: 1,
            native_symbol: 7,
            specialization_symbol: 0x4000_0011,
        };
        let imported_key = checked_specialization_identity(&imported, 9, 10).unwrap();
        assert_eq!(
            imported_key,
            checked_specialization_identity(&local, 1, 2).unwrap(),
            "replay selectors do not change the native callee or its environment"
        );
        assert_ne!(
            imported_key.0,
            checked_specialization_identity(&local, 1, 3).unwrap().0,
            "another defining unit remains a different callee"
        );
        local.target = CheckedGenericTarget::Local {
            function_start_token: 17,
            generic_parameter_count: 1,
            native_symbol: 8,
            specialization_symbol: 0x4000_0011,
        };
        assert_ne!(
            imported_key.0,
            checked_specialization_identity(&local, 1, 2).unwrap().0,
            "another native declaration remains a different callee"
        );
    }

    #[test]
    fn replay_waits_for_symbolic_arguments_but_accepts_concrete_arguments() {
        let symbolic = call(vec![CheckedGenericType::Parameter(
            CheckedGenericParameter {
                identity: CheckedParameterIdentity {
                    unit: [5, 6],
                    binder: CheckedBinderIdentity::Public {
                        owner: 8,
                        scope: u32::MAX,
                    },
                    domain: CheckedParameterDomain::Type,
                    source_ordinal: 0,
                },
                binding_slot: 0,
                constant_scalar: None,
            },
        )]);
        assert!(
            checked_replay_environment(&symbolic, 5, 6)
                .unwrap()
                .is_none()
        );
        let concrete = call(vec![CheckedGenericType::Scalar(3)]);
        assert!(
            checked_replay_environment(&concrete, 5, 6)
                .unwrap()
                .is_some()
        );
    }

    #[test]
    fn closed_replay_defers_missing_native_layout_to_gpu_materialization() {
        let without_layout = call(vec![CheckedGenericType::Array {
            element: Box::new(CheckedGenericType::Scalar(3)),
            length: CheckedGenericConstantValue::count_literal(2),
            words: None,
        }]);
        let (_, layouts) = checked_replay_environment(&without_layout, 5, 6)
            .expect("closed semantic seed").expect("concrete environment");
        assert!(layouts.contains(&u32::MAX), "missing width remains explicit");
    }

    #[test]
    fn closed_replay_reports_graph_capacity_instead_of_missing_definition() {
        // The current packet permits 64 distinct nodes. These 32 independent
        // reference/array types plus their shared scalar require 65 nodes.
        let mut at_capacity = call(
            (0..31)
                .map(|length| {
                    CheckedGenericType::Reference(Box::new(CheckedGenericType::Array {
                        element: Box::new(CheckedGenericType::Scalar(3)),
                        length: CheckedGenericConstantValue::count_literal(length),
                        words: Some(length),
                    }))
                })
                .collect(),
        );
        at_capacity.required_generic_parameters = Some(32);
        at_capacity.arguments.push(CheckedGenericArgument {
            slot: 31,
            ty: CheckedGenericType::Scalar(4),
        });
        assert!(
            checked_replay_environment(&at_capacity, 5, 6)
                .unwrap()
                .is_some()
        );
        let mut over_capacity = at_capacity;
        over_capacity.arguments[31] = CheckedGenericArgument {
            slot: 31,
            ty: CheckedGenericType::Reference(Box::new(CheckedGenericType::Array {
                element: Box::new(CheckedGenericType::Scalar(3)),
                length: CheckedGenericConstantValue::count_literal(31),
                words: Some(31),
            })),
        };
        let error = checked_replay_environment(&over_capacity, 5, 6).unwrap_err();
        let CompileError::Diagnostic(diagnostic) = error else {
            panic!("expected replay capacity diagnostic");
        };
        assert_eq!(diagnostic.code, "LNC0017");
        assert!(
            diagnostic.notes.iter().any(|note| note.contains("64")),
            "{diagnostic:?}"
        );
    }
}
