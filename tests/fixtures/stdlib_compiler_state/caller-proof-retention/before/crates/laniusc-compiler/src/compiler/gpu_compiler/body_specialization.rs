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
    typecheck::{CompiledSourcePackObject, CompiledSourcePackUnit},
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
        let mut contexts = units
            .iter()
            .map(|unit| {
                (
                    unit.interface.library_id,
                    unit.interface.unit_id,
                    unit.generic_calls.clone(),
                    unit.x86_call_hirs.clone(),
                )
            })
            .collect::<Vec<_>>();
        let mut unit_index = 0usize;
        while unit_index < contexts.len() {
            let (owner_library, owner_unit, generic_calls, call_hirs) =
                contexts[unit_index].clone();
            let calls_by_hir: BTreeMap<_, _> = generic_calls
                .iter()
                .map(|call| (call.call_hir, call))
                .collect();
            for (symbol_index, &call_hir) in call_hirs.iter().enumerate() {
                let Some(&call) = calls_by_hir.get(&call_hir) else {
                    continue;
                };
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
                // Unsupported environments keep their original identity and
                // reach the existing explicit missing-definition diagnostic.
                if !call.has_complete_arguments() {
                    continue;
                }
                let Ok((concrete_identity, concrete_layouts)) =
                    checked_specialization_identity(call, owner_library, owner_unit)
                else {
                    continue;
                };
                if let Some((_, layouts)) = specializations.get(&concrete_identity) {
                    if layouts != &concrete_layouts {
                        return Err(CompileError::GpuCodegen(
                            "the same checked specialization has inconsistent native layouts"
                                .into(),
                        ));
                    }
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
                    let replay = self.compile_body_specialization(template, call).await?;
                    let CompiledSourcePackObject::X86_64(mut concrete) = replay.object else {
                        unreachable!("body replay target is x86_64")
                    };
                    contexts.push((
                        library_id,
                        unit_id,
                        replay.generic_calls,
                        replay.x86_call_hirs,
                    ));
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
                        (native_identity, concrete_layouts),
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
    identity.extend_from_slice(b"LGS3");
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
