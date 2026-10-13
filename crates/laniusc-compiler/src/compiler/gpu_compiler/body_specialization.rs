//! Resident scheduling of concrete bodies from GPU-checked call environments.
//!
//! Allocate unused native unit identities for ordered checked type environments,
//! keeping durable object records and the native ABI unchanged. The GPU emitter
//! supplies the HIR-to-symbol relation; this controller does not inspect source
//! or infer types from target instructions.

use std::{
    borrow::Cow,
    collections::{BTreeMap, BTreeSet},
};

use super::{
    program_evidence::{AdmittedCall, NativeProgramSession, native_program_error},
    typecheck::{CompiledSourcePackObject, CompiledSourcePackUnit, OriginalUnitFacts, PendingOriginalUnit},
    *,
};
use crate::type_checker::{CheckedBodySpecialization, CheckedGenericCall, CheckedGenericTarget};

const MAX_RESIDENT_SPECIALIZATIONS: usize = 256;
const MAX_SPECIALIZED_TEXT_BYTES: usize = 64 << 20;

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
        let mut objects = Vec::with_capacity(units.len());
        let mut used_units = BTreeSet::new();
        for unit in units {
            let CompiledSourcePackObject::X86_64(object) = &unit.object else {
                return Err(CompileError::GpuCodegen(
                    "resident x86 specialization received a different target".into(),
                ));
            };
            templates.insert((unit.interface.library_id, unit.interface.unit_id), *unit);
            used_units.insert((object.library_id, object.unit_id));
            for symbol in &object.symbols {
                let identity = symbol_identity(object, symbol);
                if identity.len() == 12 {
                    used_units.insert((
                        u32::from_le_bytes(identity[..4].try_into().unwrap()),
                        u32::from_le_bytes(identity[4..8].try_into().unwrap()),
                    ));
                }
            }
            objects.push(Cow::Borrowed(object));
        }
        let mut specializations = BTreeMap::<Vec<u8>, (Vec<u8>, Vec<u32>)>::new();
        let mut next_unit_by_library = BTreeMap::<u32, u32>::new();
        let mut specialized_text_bytes = 0usize;
        let mut contexts = units.iter().zip(initial_calls).map(|(unit, calls)| (
            unit.interface.library_id, unit.interface.unit_id, calls, unit.x86_call_hirs.clone(),
        )).collect::<Vec<_>>();
        let mut unit_index = 0usize;
        while unit_index < contexts.len() {
            let (owner_library, owner_unit, generic_calls, call_hirs) =
                contexts[unit_index].clone();
            let calls_by_hir: BTreeMap<_, _> = generic_calls
                .iter()
                .map(|call| (call.checked_call().call_hir, call))
                .collect();
            for (symbol_index, &call_hir) in call_hirs.iter().enumerate() {
                let Some(&admitted) = calls_by_hir.get(&call_hir) else {
                    continue;
                };
                let call = admitted.checked_call();
                let Some((library_id, unit_id, declaration_index)) =
                    native_target(call.target, owner_library, owner_unit)
                else {
                    continue;
                };
                let Some(template) = templates.get(&(library_id, unit_id)) else {
                    continue;
                };
                let identity = declaration_identity(library_id, unit_id, declaration_index);
                let CompiledSourcePackObject::X86_64(original) = &template.object else {
                    unreachable!("templates were checked above")
                };
                // A reusable native body does not waive the declaration's
                // generic requirements. Validate unused parameters too, before
                // accepting tag-only definitions or scheduling a replay.
                if !call.has_all_parameter_slots() {
                    return Err(CompileError::Diagnostic(Diagnostic::error(
                        "LNC0017",
                        "generic call is missing declared type or constant bindings",
                    )));
                }
                if original.symbols.iter().any(|symbol| {
                    symbol.section != x86::GpuX86ObjectSection::Undefined
                        && symbol_identity(original, symbol) == identity
                }) {
                    // Tag-only generic functions already have a valid body.
                    continue;
                }
                let Some((concrete_identity, concrete_layouts)) =
                    checked_replay_environment(call, owner_library, owner_unit)?
                else {
                    // A symbolic call belongs to an uninstantiated template.
                    // Its concrete replay will supply a new call environment.
                    continue;
                };
                if let Some((_, layouts)) = specializations.get_mut(&concrete_identity) {
                    CheckedBodySpecialization::merge_layout_witnesses(layouts, &concrete_layouts)
                        .map_err(|error| CompileError::GpuCodegen(error.to_string()))?;
                }
                let symbol = objects[unit_index]
                    .symbols
                    .get(symbol_index)
                    .ok_or_else(|| {
                        CompileError::GpuCodegen("native call symbol is absent".into())
                    })?;
                if symbol.section != x86::GpuX86ObjectSection::Undefined
                    || symbol_identity(&objects[unit_index], symbol) != identity
                {
                    return Err(CompileError::GpuCodegen(
                        "native call identity disagrees with its checked generic environment"
                            .into(),
                    ));
                }
                if !specializations.contains_key(&concrete_identity) {
                    if specializations.len() == MAX_RESIDENT_SPECIALIZATIONS {
                        return Err(specialization_limit_error("more than 256 concrete bodies"));
                    }
                    let request = program
                        .prepare_replay(admitted)
                        .map_err(native_program_error)?;
                    let pending = self
                        .compile_authorized_body_specialization(&request)
                        .await?;
                    let (replay, replay_calls) =
                        request.finish(pending).map_err(native_program_error)?;
                    let mut admitted_layouts = replay.body_native_layouts.as_ref()
                        .ok_or_else(|| CompileError::GpuCodegen("concrete replay omitted admitted native layouts".into()))?
                        .to_vec();
                    CheckedBodySpecialization::merge_layout_witnesses(&mut admitted_layouts, &concrete_layouts)
                        .map_err(|error| CompileError::GpuCodegen(error.to_string()))?;
                    let CompiledSourcePackObject::X86_64(mut concrete) = replay.object else {
                        unreachable!("body replay target is x86_64")
                    };
                    contexts.push((library_id, unit_id, replay_calls, replay.x86_call_hirs));
                    let candidate = next_unit_by_library.entry(library_id).or_default();
                    while used_units.contains(&(library_id, *candidate)) {
                        *candidate = candidate.checked_add(1).ok_or_else(|| {
                            specialization_limit_error("no unused native unit identity")
                        })?;
                    }
                    let specialized_unit = *candidate;
                    used_units.insert((library_id, specialized_unit));
                    let native_identity =
                        declaration_identity(library_id, specialized_unit, declaration_index);
                    specialized_text_bytes = specialized_text_bytes
                        .checked_add(concrete.text.len())
                        .ok_or_else(|| specialization_limit_error("native text length overflow"))?;
                    if specialized_text_bytes > MAX_SPECIALIZED_TEXT_BYTES {
                        return Err(specialization_limit_error(
                            "more than 64 MiB of native text",
                        ));
                    }
                    // Undefined symbols precede definitions, so dropping other
                    // definitions preserves every relocation target index.
                    let keep: Vec<bool> = concrete
                        .symbols
                        .iter()
                        .map(|symbol| {
                            symbol.section == x86::GpuX86ObjectSection::Undefined
                                || symbol_identity(&concrete, symbol) == identity
                        })
                        .collect();
                    let mut index = 0;
                    concrete.symbols.retain(|_| {
                        let retain = keep[index];
                        index += 1;
                        retain
                    });
                    let definition = concrete
                        .symbols
                        .iter()
                        .position(|symbol| {
                            symbol.section == x86::GpuX86ObjectSection::Text
                                && symbol_identity(&concrete, symbol) == identity
                        })
                        .ok_or_else(|| {
                            CompileError::GpuCodegen(format!(
                                "concrete body replay produced no native definition for {:?} with {:?}",
                                call.target, call.arguments
                            ))
                        })?;
                    replace_symbol_identity(&mut concrete, definition, &native_identity)?;
                    concrete.unit_id = specialized_unit;
                    concrete.entry_offset = None;
                    concrete
                        .validate()
                        .map_err(|error| CompileError::GpuCodegen(error))?;
                    specializations.insert(
                        concrete_identity.clone(),
                        (native_identity, admitted_layouts),
                    );
                    objects.push(Cow::Owned(concrete));
                }
                replace_symbol_identity(
                    objects[unit_index].to_mut(),
                    symbol_index,
                    &specializations[&concrete_identity].0,
                )?;
            }
            unit_index += 1;
        }
        Ok(objects)
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
