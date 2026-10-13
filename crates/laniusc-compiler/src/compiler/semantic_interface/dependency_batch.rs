use super::*;

/// Contiguous, deterministic GPU-upload shape for a set of dependency
/// interfaces. Stable declaration identities remain
/// `(library_id, unit_id, local index)`; only references into flattened
/// storage are rebased.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct GpuSemanticInterfaceDependencyBatch {
    pub(crate) library_ids: Vec<u32>,
    pub(crate) unit_ids: Vec<u32>,
    pub(crate) module_library_id: Vec<u32>,
    pub(crate) module_unit_id: Vec<u32>,
    pub(crate) module_local_index: Vec<u32>,
    pub(crate) modules: Vec<GpuSemanticInterfaceModuleRecord>,
    pub(crate) module_segments: Vec<GpuSemanticInterfaceModuleSegmentRecord>,
    pub(crate) declaration_library_id: Vec<u32>,
    pub(crate) declaration_unit_id: Vec<u32>,
    pub(crate) declaration_local_index: Vec<u32>,
    pub(crate) declarations: Vec<GpuSemanticInterfaceDeclarationRecord>,
    pub(crate) type_library_id: Vec<u32>,
    pub(crate) type_unit_id: Vec<u32>,
    pub(crate) type_local_index: Vec<u32>,
    pub(crate) types: Vec<GpuSemanticInterfaceTypeRecord>,
    pub(crate) type_edges: Vec<GpuSemanticInterfaceTypeEdge>,
    pub(crate) members: Vec<GpuSemanticInterfaceMemberRecord>,
    pub(crate) predicate_library_id: Vec<u32>,
    pub(crate) predicate_unit_id: Vec<u32>,
    pub(crate) predicate_local_index: Vec<u32>,
    pub(crate) predicates: Vec<GpuSemanticInterfacePredicateRecord>,
    pub(crate) predicate_arguments: Vec<u32>,
    pub(crate) implementation_library_id: Vec<u32>,
    pub(crate) implementation_unit_id: Vec<u32>,
    pub(crate) implementation_local_index: Vec<u32>,
    pub(crate) implementations: Vec<GpuSemanticInterfaceImplementationRecord>,
    pub(crate) implementation_arguments: Vec<u32>,
    pub(crate) implementation_method_bindings: Vec<GpuSemanticInterfaceImplementationMethodBindingRecord>,
    pub(crate) name_bytes: Vec<u8>,
}

impl GpuSemanticInterfaceDependencyBatch {
    pub(crate) fn from_interfaces(
        current_library_id: u32,
        current_unit_id: u32,
        interfaces: &[GpuSemanticInterfaceArtifact],
    ) -> Result<Self, String> {
        let mut ordered = interfaces.iter().collect::<Vec<_>>();
        ordered.sort_unstable_by_key(|interface| (interface.library_id, interface.unit_id));
        for (index, interface) in ordered.iter().enumerate() {
            interface.validate().map_err(|reason| {
                format!(
                    "dependency semantic interface for library {} is invalid: {reason}",
                    interface.library_id
                )
            })?;
            if interface.library_id == current_library_id && interface.unit_id == current_unit_id {
                return Err(format!(
                    "library {current_library_id} unit {current_unit_id} cannot consume its own semantic interface as a dependency"
                ));
            }
            if index != 0
                && ordered[index - 1].library_id == interface.library_id
                && ordered[index - 1].unit_id == interface.unit_id
            {
                return Err(format!(
                    "dependency semantic interface ({}, {}) occurs more than once",
                    interface.library_id, interface.unit_id
                ));
            }
        }
        validate_batch_totals(&ordered)?;

        let mut batch = Self::default();
        for interface in ordered {
            batch.append(interface)?;
        }
        batch.validate_flattened_ranges()?;
        Ok(batch)
    }

    fn append(&mut self, interface: &GpuSemanticInterfaceArtifact) -> Result<(), String> {
        let module_base = checked_base("dependency module", self.modules.len())?;
        let segment_base = checked_base("dependency module segment", self.module_segments.len())?;
        let declaration_base = checked_base("dependency declaration", self.declarations.len())?;
        let type_base = checked_base("dependency type", self.types.len())?;
        let edge_base = checked_base("dependency type edge", self.type_edges.len())?;
        let member_base = checked_base("dependency member", self.members.len())?;
        let predicate_argument_base = checked_base("dependency predicate argument", self.predicate_arguments.len())?;
        let predicate_base = checked_base("dependency predicate", self.predicates.len())?;
        let implementation_base = checked_base("dependency implementation", self.implementations.len())?;
        let implementation_argument_base = checked_base("dependency implementation argument", self.implementation_arguments.len())?;
        let implementation_binding_base = checked_base("dependency implementation method binding", self.implementation_method_bindings.len())?;
        let name_base = checked_base("dependency name byte", self.name_bytes.len())?;

        self.library_ids.push(interface.library_id);
        self.unit_ids.push(interface.unit_id);
        for (local_index, module) in interface.modules.iter().enumerate() {
            self.module_library_id.push(interface.library_id);
            self.module_unit_id.push(interface.unit_id);
            self.module_local_index
                .push(u32::try_from(local_index).map_err(|_| {
                    "dependency module local index does not fit in u32".to_string()
                })?);
            self.modules.push(GpuSemanticInterfaceModuleRecord {
                first_segment: checked_add(
                    "dependency module segment base",
                    segment_base,
                    module.first_segment,
                )?,
                segment_count: module.segment_count,
            });
        }
        self.module_segments
            .extend(interface.module_segments.iter().map(|segment| {
                GpuSemanticInterfaceModuleSegmentRecord {
                    name_hash_lo: segment.name_hash_lo,
                    name_hash_hi: segment.name_hash_hi,
                    name_byte_start: name_base + segment.name_byte_start,
                    name_byte_len: segment.name_byte_len,
                }
            }));
        for (local_index, declaration) in interface.declarations.iter().enumerate() {
            self.declaration_library_id.push(interface.library_id);
            self.declaration_unit_id.push(interface.unit_id);
            self.declaration_local_index
                .push(u32::try_from(local_index).map_err(|_| {
                    "dependency declaration local index does not fit in u32".to_string()
                })?);
            self.declarations
                .push(GpuSemanticInterfaceDeclarationRecord {
                    module: checked_add(
                        "dependency declaration module",
                        module_base,
                        declaration.module,
                    )?,
                    name_hash_lo: declaration.name_hash_lo,
                    name_hash_hi: declaration.name_hash_hi,
                    name_byte_start: checked_add(
                        "dependency declaration name",
                        name_base,
                        declaration.name_byte_start,
                    )?,
                    name_byte_len: declaration.name_byte_len,
                    namespace: declaration.namespace,
                    kind: declaration.kind,
                    signature_type: rebase_optional(
                        "dependency declaration signature",
                        type_base,
                        declaration.signature_type,
                    )?,
                    first_member: checked_add(
                        "dependency declaration member base",
                        member_base,
                        declaration.first_member,
                    )?,
                    member_count: declaration.member_count,
                    owner_declaration: rebase_optional(
                        "dependency declaration owner",
                        declaration_base,
                        declaration.owner_declaration,
                    )?,
                    flags: declaration.flags,
                    value_lo: declaration.value_lo,
                    value_hi: declaration.value_hi,
                });
        }
        for (local_index, ty) in interface.types.iter().enumerate() {
            self.type_library_id.push(interface.library_id);
            self.type_unit_id.push(interface.unit_id);
            self.type_local_index.push(
                u32::try_from(local_index)
                    .map_err(|_| "dependency type local index does not fit in u32".to_string())?,
            );
            let payload_lo = if matches!(
                GpuSemanticInterfaceTypeKind::from_u32(ty.kind),
                Some(
                    GpuSemanticInterfaceTypeKind::GenericParameter
                        | GpuSemanticInterfaceTypeKind::ConstParameter
                )
            ) {
                member_base + ty.payload_lo
            } else {
                ty.payload_lo
            };
            self.types.push(GpuSemanticInterfaceTypeRecord {
                kind: ty.kind,
                payload_lo,
                payload_hi: ty.payload_hi,
                first_edge: if ty.edge_count == 0 { 0 } else { edge_base + ty.first_edge },
                edge_count: ty.edge_count,
                length_kind: ty.length_kind,
                // Typed scalar bits are values, never rebased identities.
                length_lo: ty.length_lo,
                length_hi: ty.length_hi,
                nominal_unit_id: ty.nominal_unit_id,
            });
        }
        self.type_edges
            .extend(
                interface
                    .type_edges
                    .iter()
                    .map(|edge| GpuSemanticInterfaceTypeEdge {
                        type_index: type_base + edge.type_index,
                    }),
            );
        self.members.extend(interface.members.iter().map(|member| {
            Ok(GpuSemanticInterfaceMemberRecord {
                owner_ref: rebase_contract_owner(member.owner_ref, declaration_base, implementation_base)?,
                kind: member.kind,
                ordinal: member.ordinal,
                name_hash_lo: member.name_hash_lo,
                name_hash_hi: member.name_hash_hi,
                name_byte_start: name_base + member.name_byte_start,
                name_byte_len: member.name_byte_len,
                type_index: if member.type_index == INVALID {
                    INVALID
                } else {
                    type_base + member.type_index
                },
                value_lo: member.value_lo,
                value_hi: member.value_hi,
                receiver_type_index: if member.receiver_type_index == INVALID {
                    INVALID
                } else {
                    type_base + member.receiver_type_index
                },
                generic_parameter_ordinal: member.generic_parameter_ordinal,
            })
        }).collect::<Result<Vec<_>, String>>()?);
        for (local_index, predicate) in interface.predicates.iter().enumerate() {
            self.predicate_library_id.push(interface.library_id);
            self.predicate_unit_id.push(interface.unit_id);
            self.predicate_local_index.push(checked_base("dependency predicate local index", local_index)?);
            self.predicates.push(GpuSemanticInterfacePredicateRecord {
                owner_ref: rebase_contract_owner(predicate.owner_ref, declaration_base, implementation_base)?,
                subject_type: checked_add("dependency predicate subject", type_base, predicate.subject_type)?,
                first_argument: checked_add("dependency predicate argument base", predicate_argument_base, predicate.first_argument)?,
                // Method symbols and the defining trait triple are portable
                // identities, never offsets in the flattened page tables.
                ..*predicate
            });
        }
        for &root in &interface.predicate_arguments {
            self.predicate_arguments.push(checked_add("dependency predicate argument root", type_base, root)?);
        }
        for (local_index, implementation) in interface.implementations.iter().enumerate() {
            self.implementation_library_id.push(interface.library_id);
            self.implementation_unit_id.push(interface.unit_id);
            self.implementation_local_index.push(checked_base("dependency implementation local index", local_index)?);
            self.implementations.push(GpuSemanticInterfaceImplementationRecord {
                module: checked_add("dependency implementation module", module_base, implementation.module)?,
                subject_type: checked_add("dependency implementation subject", type_base, implementation.subject_type)?,
                first_argument: checked_add("dependency implementation argument", implementation_argument_base, implementation.first_argument)?,
                first_member: checked_add("dependency implementation member", member_base, implementation.first_member)?,
                first_prerequisite: checked_add("dependency implementation prerequisite", predicate_base, implementation.first_prerequisite)?,
                first_method_binding: checked_add("dependency implementation method binding", implementation_binding_base, implementation.first_method_binding)?,
                ..*implementation
            });
        }
        for &root in &interface.implementation_arguments {
            self.implementation_arguments.push(checked_add("dependency implementation argument root", type_base, root)?);
        }
        for binding in &interface.implementation_method_bindings {
            self.implementation_method_bindings.push(GpuSemanticInterfaceImplementationMethodBindingRecord {
                implementation_index: checked_add("dependency method binding implementation", implementation_base, binding.implementation_index)?,
                implementation_method_member: checked_add("dependency method binding callable", member_base, binding.implementation_method_member)?,
                ..*binding
            });
        }
        self.name_bytes.extend_from_slice(&interface.name_bytes);
        Ok(())
    }

    fn validate_flattened_ranges(&self) -> Result<(), String> {
        checked_u32_len("dependency library", self.library_ids.len())?;
        checked_u32_len("dependency module", self.modules.len())?;
        checked_u32_len("dependency module segment", self.module_segments.len())?;
        checked_u32_len("dependency declaration", self.declarations.len())?;
        checked_u32_len("dependency type", self.types.len())?;
        checked_u32_len("dependency type edge", self.type_edges.len())?;
        checked_u32_len("dependency member", self.members.len())?;
        checked_u32_len("dependency predicate", self.predicates.len())?;
        checked_u32_len("dependency predicate argument", self.predicate_arguments.len())?;
        checked_u32_len("dependency implementation", self.implementations.len())?;
        checked_u32_len("dependency implementation argument", self.implementation_arguments.len())?;
        checked_u32_len("dependency implementation method binding", self.implementation_method_bindings.len())?;
        validate_contract_owner_capacity("dependency declaration", self.declarations.len())?;
        validate_contract_owner_capacity("dependency implementation", self.implementations.len())?;
        checked_u32_len("dependency name byte", self.name_bytes.len())?;
        if self.module_library_id.len() != self.modules.len()
            || self.module_unit_id.len() != self.modules.len()
            || self.module_local_index.len() != self.modules.len()
            || self.declaration_library_id.len() != self.declarations.len()
            || self.declaration_unit_id.len() != self.declarations.len()
            || self.declaration_local_index.len() != self.declarations.len()
            || self.type_library_id.len() != self.types.len()
            || self.type_unit_id.len() != self.types.len()
            || self.type_local_index.len() != self.types.len()
            || self.predicate_library_id.len() != self.predicates.len()
            || self.predicate_unit_id.len() != self.predicates.len()
            || self.predicate_local_index.len() != self.predicates.len()
            || self.implementation_library_id.len() != self.implementations.len()
            || self.implementation_unit_id.len() != self.implementations.len()
            || self.implementation_local_index.len() != self.implementations.len()
        {
            return Err(
                "dependency semantic-interface identity side tables have different lengths"
                    .to_string(),
            );
        }
        for (index, module) in self.modules.iter().enumerate() {
            validate_range(
                "dependency module segment",
                index,
                module.first_segment,
                module.segment_count,
                self.module_segments.len(),
            )?;
        }
        for (index, declaration) in self.declarations.iter().enumerate() {
            validate_index(
                "dependency declaration module",
                index,
                declaration.module,
                self.modules.len(),
            )?;
            validate_index(
                "dependency declaration signature",
                index,
                declaration.signature_type,
                self.types.len(),
            )?;
            validate_range(
                "dependency declaration member",
                index,
                declaration.first_member,
                declaration.member_count,
                self.members.len(),
            )?;
            validate_optional_index(
                "dependency declaration owner",
                index,
                declaration.owner_declaration,
                self.declarations.len(),
            )?;
        }
        for (index, ty) in self.types.iter().enumerate() {
            validate_range(
                "dependency type edge",
                index,
                ty.first_edge,
                ty.edge_count,
                self.type_edges.len(),
            )?;
        }
        for (index, edge) in self.type_edges.iter().enumerate() {
            validate_index(
                "dependency type edge target",
                index,
                edge.type_index,
                self.types.len(),
            )?;
        }
        for (index, member) in self.members.iter().enumerate() {
            validate_contract_owner(member.owner_ref, self.declarations.len(), self.implementations.len())?;
            validate_optional_index(
                "dependency member type",
                index,
                member.type_index,
                self.types.len(),
            )?;
            validate_optional_index(
                "dependency associated method receiver type",
                index,
                member.receiver_type_index,
                self.types.len(),
            )?;
        }
        for (index, predicate) in self.predicates.iter().enumerate() {
            validate_contract_owner(predicate.owner_ref, self.declarations.len(), self.implementations.len())?;
            validate_index("dependency predicate subject", index, predicate.subject_type, self.types.len())?;
            validate_range("dependency predicate argument", index, predicate.first_argument,
                predicate.argument_count, self.predicate_arguments.len())?;
        }
        for (row, &root) in self.predicate_arguments.iter().enumerate() {
            validate_index("dependency predicate argument root", row, root, self.types.len())?;
        }
        for (index, implementation) in self.implementations.iter().enumerate() {
            if GpuSemanticInterfaceImplementationKind::from_u32(implementation.kind).is_none() {
                return Err(format!("dependency implementation {index} has an unknown kind"));
            }
            validate_index("dependency implementation module", index, implementation.module, self.modules.len())?;
            validate_index("dependency implementation subject", index, implementation.subject_type, self.types.len())?;
            validate_range("dependency implementation argument", index, implementation.first_argument, implementation.argument_count, self.implementation_arguments.len())?;
            validate_range("dependency implementation member", index, implementation.first_member, implementation.member_count, self.members.len())?;
            validate_range("dependency implementation prerequisite", index, implementation.first_prerequisite, implementation.prerequisite_count, self.predicates.len())?;
            validate_range("dependency implementation method binding", index, implementation.first_method_binding, implementation.method_binding_count, self.implementation_method_bindings.len())?;
        }
        for (row, &root) in self.implementation_arguments.iter().enumerate() {
            validate_index("dependency implementation argument root", row, root, self.types.len())?;
        }
        for (row, binding) in self.implementation_method_bindings.iter().enumerate() {
            validate_index("dependency method binding implementation", row, binding.implementation_index, self.implementations.len())?;
            validate_index("dependency method binding callable", row, binding.implementation_method_member, self.members.len())?;
        }
        Ok(())
    }
}

fn validate_batch_totals(interfaces: &[&GpuSemanticInterfaceArtifact]) -> Result<(), String> {
    checked_u32_len("dependency library", interfaces.len())?;
    checked_total(
        "dependency module",
        interfaces.iter().map(|interface| interface.modules.len()),
    )?;
    checked_total(
        "dependency module segment",
        interfaces
            .iter()
            .map(|interface| interface.module_segments.len()),
    )?;
    checked_total(
        "dependency declaration",
        interfaces
            .iter()
            .map(|interface| interface.declarations.len()),
    )?;
    checked_total(
        "dependency type",
        interfaces.iter().map(|interface| interface.types.len()),
    )?;
    checked_total(
        "dependency type edge",
        interfaces
            .iter()
            .map(|interface| interface.type_edges.len()),
    )?;
    checked_total(
        "dependency member",
        interfaces.iter().map(|interface| interface.members.len()),
    )?;
    checked_total("dependency predicate", interfaces.iter().map(|interface| interface.predicates.len()))?;
    checked_total("dependency predicate argument", interfaces.iter().map(|interface| interface.predicate_arguments.len()))?;
    checked_total("dependency implementation", interfaces.iter().map(|interface| interface.implementations.len()))?;
    checked_total("dependency implementation argument", interfaces.iter().map(|interface| interface.implementation_arguments.len()))?;
    checked_total("dependency implementation method binding", interfaces.iter().map(|interface| interface.implementation_method_bindings.len()))?;
    checked_total(
        "dependency name byte",
        interfaces
            .iter()
            .map(|interface| interface.name_bytes.len()),
    )?;
    Ok(())
}

fn checked_total(label: &str, mut counts: impl Iterator<Item = usize>) -> Result<(), String> {
    let total = counts
        .try_fold(0usize, |total, count| total.checked_add(count))
        .ok_or_else(|| format!("{label} count overflows usize"))?;
    checked_u32_len(label, total).map(|_| ())
}

fn checked_base(label: &str, len: usize) -> Result<u32, String> {
    u32::try_from(len).map_err(|_| format!("{label} count {len} does not fit in u32"))
}

fn checked_add(label: &str, base: u32, local: u32) -> Result<u32, String> {
    base.checked_add(local)
        .ok_or_else(|| format!("{label} index {base}+{local} overflows u32"))
}

fn rebase_optional(label: &str, base: u32, local: u32) -> Result<u32, String> {
    if local == INVALID {
        Ok(INVALID)
    } else {
        checked_add(label, base, local)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn one_function_interface(
        library_id: u32,
        unit_id: u32,
        module_name: &str,
        fn_name: &str,
    ) -> GpuSemanticInterfaceArtifact {
        let mut name_bytes = module_name.as_bytes().to_vec();
        let fn_start = name_bytes.len() as u32;
        name_bytes.extend_from_slice(fn_name.as_bytes());
        let (module_hash_lo, module_hash_hi) = stable_name_hash(module_name.as_bytes());
        let (fn_hash_lo, fn_hash_hi) = stable_name_hash(fn_name.as_bytes());
        GpuSemanticInterfaceArtifact {
            version: GPU_SEMANTIC_INTERFACE_VERSION,
            library_id,
            unit_id,
            modules: vec![GpuSemanticInterfaceModuleRecord {
                first_segment: 0,
                segment_count: 1,
            }],
            module_segments: vec![GpuSemanticInterfaceModuleSegmentRecord {
                name_hash_lo: module_hash_lo,
                name_hash_hi: module_hash_hi,
                name_byte_start: 0,
                name_byte_len: module_name.len() as u32,
            }],
            declarations: vec![GpuSemanticInterfaceDeclarationRecord {
                module: 0,
                name_hash_lo: fn_hash_lo,
                name_hash_hi: fn_hash_hi,
                name_byte_start: fn_start,
                name_byte_len: fn_name.len() as u32,
                namespace: 2,
                kind: 4,
                signature_type: 1,
                first_member: 0,
                member_count: 0,
                owner_declaration: INVALID,
                flags: 0,
                value_lo: 0,
                value_hi: 0,
            }],
            types: vec![
                GpuSemanticInterfaceTypeRecord {
                    kind: GpuSemanticInterfaceTypeKind::Scalar as u32,
                    payload_lo: 3,
                    payload_hi: 0,
                    first_edge: 0,
                    edge_count: 0,
                    length_kind: 0,
                    length_lo: 0,
                    length_hi: 0,
                    nominal_unit_id: 0,
                },
                GpuSemanticInterfaceTypeRecord {
                    kind: GpuSemanticInterfaceTypeKind::Function as u32,
                    payload_lo: 0,
                    payload_hi: 0,
                    first_edge: 0,
                    edge_count: 1,
                    length_kind: 0,
                    length_lo: 0,
                    length_hi: 0,
                    nominal_unit_id: 0,
                },
            ],
            type_edges: vec![GpuSemanticInterfaceTypeEdge { type_index: 0 }],
            members: Vec::new(),
            predicates: Vec::new(),
            predicate_arguments: Vec::new(),
            implementations: Vec::new(),
            implementation_arguments: Vec::new(),
            implementation_method_bindings: Vec::new(),
            name_bytes,
        }
    }

    #[test]
    fn dependency_batch_predicates_keep_method_symbols_and_portable_identity() {
        let mut first = one_function_interface(7, 70, "first", "Carrier");
        let declaration = first.declarations[0];
        first.types.push(GpuSemanticInterfaceTypeRecord {
            kind: GpuSemanticInterfaceTypeKind::Declaration as u32,
            payload_lo: first.library_id, nominal_unit_id: first.unit_id,
            payload_hi: 0, ..first.types[0]
        });
        first.declarations[0].kind = 6;
        first.declarations[0].namespace = 1;
        first.declarations[0].signature_type = 2;
        first.declarations[0].member_count = 0;
        first.members.push(GpuSemanticInterfaceMemberRecord {
            owner_ref: IMPLEMENTATION_OWNER_TAG, kind: GpuSemanticInterfaceMemberKind::ImplementationMethod as u32,
            ordinal: 0, name_hash_lo: declaration.name_hash_lo, name_hash_hi: declaration.name_hash_hi,
            name_byte_start: declaration.name_byte_start, name_byte_len: declaration.name_byte_len,
            type_index: 0, value_lo: 1 << 30, value_hi: 0x8000_0034, receiver_type_index: 2,
            generic_parameter_ordinal: INVALID,
        });
        first.implementations.push(GpuSemanticInterfaceImplementationRecord {
            module: 0, visibility: 1, trait_library_id: INVALID, trait_unit_id: INVALID,
            trait_declaration_index: INVALID, subject_type: 2, first_argument: 0, argument_count: 0,
            first_member: 0, member_count: 1, first_prerequisite: 0, prerequisite_count: 0,
            first_method_binding: 0, method_binding_count: 0,
            kind: GpuSemanticInterfaceImplementationKind::Inherent as u32,
        });
        first.predicates.push(GpuSemanticInterfacePredicateRecord {
            owner_ref: IMPLEMENTATION_OWNER_TAG, owner_scope_symbol: 0x8000_0034, subject_type: 0,
            trait_library_id: 90, trait_unit_id: 110, trait_declaration_index: 5,
            first_argument: 0, argument_count: 1,
        });
        first.predicate_arguments.push(0);
        let mut second = first.clone();
        second.unit_id += 1;
        second.types[2].nominal_unit_id = second.unit_id;
        let batch = GpuSemanticInterfaceDependencyBatch::from_interfaces(99, 99, &[second, first]).unwrap();
        assert_eq!(batch.predicate_library_id, [7, 7]);
        assert_eq!(batch.predicate_unit_id, [70, 71]);
        assert_eq!(batch.predicate_local_index, [0, 0]);
        assert_eq!(batch.predicates[1], GpuSemanticInterfacePredicateRecord {
            owner_ref: IMPLEMENTATION_OWNER_TAG | 1, subject_type: 3, first_argument: 1, ..batch.predicates[0]
        });
        assert_eq!(batch.predicate_arguments, [0, 3]);
        assert_eq!(batch.members[1].value_hi, 0x8000_0034);
        assert_eq!(batch.members[1].owner_ref, IMPLEMENTATION_OWNER_TAG | 1);
        assert_eq!(batch.implementations[1].kind, GpuSemanticInterfaceImplementationKind::Inherent as u32);
        assert_eq!(batch.implementations[1].subject_type, 5);
        let mut malformed = batch.clone();
        malformed.predicate_unit_id.pop();
        assert!(malformed.validate_flattened_ranges().unwrap_err().contains("different lengths"));
        let mut malformed = batch;
        malformed.predicate_arguments[1] = INVALID;
        assert!(malformed.validate_flattened_ranges().unwrap_err().contains("predicate argument root"));
    }

    #[test]
    fn dependency_batch_is_library_ordered_and_rebases_only_flat_storage() {
        let library_9 = one_function_interface(9, 90, "nine", "run_nine");
        let library_7 = one_function_interface(7, 70, "seven", "run_seven");
        let batch =
            GpuSemanticInterfaceDependencyBatch::from_interfaces(11, 110, &[library_9, library_7])
                .expect("flatten valid dependency interfaces");

        assert_eq!(batch.library_ids, vec![7, 9]);
        assert_eq!(batch.unit_ids, vec![70, 90]);
        assert_eq!(batch.module_library_id, vec![7, 9]);
        assert_eq!(batch.module_unit_id, vec![70, 90]);
        assert_eq!(batch.module_local_index, vec![0, 0]);
        assert_eq!(batch.modules[1].first_segment, 1);
        assert_eq!(batch.declaration_library_id, vec![7, 9]);
        assert_eq!(batch.declaration_unit_id, vec![70, 90]);
        assert_eq!(batch.declaration_local_index, vec![0, 0]);
        assert_eq!(batch.type_library_id, vec![7, 7, 9, 9]);
        assert_eq!(batch.type_unit_id, vec![70, 70, 90, 90]);
        assert_eq!(batch.type_local_index, vec![0, 1, 0, 1]);
        assert_eq!(batch.declarations[1].module, 1);
        assert_eq!(batch.declarations[1].signature_type, 3);
        assert_eq!(batch.types[3].first_edge, 1);
        assert_eq!(batch.type_edges[1].type_index, 2);
    }

    #[test]
    fn dependency_batch_keeps_constant_array_lengths_with_their_declarations() {
        let make = |unit, name| {
            let mut interface = one_function_interface(7, unit, name, "keep");
            let declaration = &mut interface.declarations[0];
            declaration.member_count = 1;
            interface.members.push(GpuSemanticInterfaceMemberRecord {
                owner_ref: 0,
                kind: GpuSemanticInterfaceMemberKind::GenericConstParameter as u32,
                ordinal: 0,
                name_hash_lo: declaration.name_hash_lo,
                name_hash_hi: declaration.name_hash_hi,
                name_byte_start: declaration.name_byte_start,
                name_byte_len: declaration.name_byte_len,
                type_index: 0,
                value_lo: 0,
                value_hi: 0,
                receiver_type_index: INVALID,
                generic_parameter_ordinal: 0,
            });
            let scalar = interface.types[0];
            let mut function = interface.types[1];
            let parameter = GpuSemanticInterfaceTypeRecord {
                kind: GpuSemanticInterfaceTypeKind::ConstParameter as u32,
                payload_lo: 0, ..scalar
            };
            let array = GpuSemanticInterfaceTypeRecord {
                kind: GpuSemanticInterfaceTypeKind::Array as u32,
                edge_count: 2, ..scalar
            };
            let literal = GpuSemanticInterfaceTypeRecord {
                kind: GpuSemanticInterfaceTypeKind::ConstValue as u32, ..scalar
            };
            function.first_edge = 4;
            interface.types = vec![scalar, parameter, scalar, array, literal, scalar,
                GpuSemanticInterfaceTypeRecord { first_edge: 2, ..array }, function];
            interface.type_edges = [2, 1, 5, 4, 6].map(|type_index|
                GpuSemanticInterfaceTypeEdge { type_index }).to_vec();
            interface.declarations[0].signature_type = 7;
            interface
        };
        let batch = GpuSemanticInterfaceDependencyBatch::from_interfaces(
            9,
            0,
            &[make(2, "second"), make(1, "first")],
        )
        .expect("constant length interfaces");
        assert_eq!(batch.members[1].type_index, 8, "declared scalar leaf is rebased");
        assert_eq!(batch.types[12].first_edge, 0, "literal has no rebased edge pointer");
        for (type_row, owner) in [(1, 0), (9, 1)] {
            let length = &batch.types[type_row];
            let member = &batch.members[length.payload_lo as usize];
            assert_eq!(member.owner_ref, owner);
            assert_eq!(
                member.kind,
                GpuSemanticInterfaceMemberKind::GenericConstParameter as u32
            );
            assert_eq!(
                batch.types[type_row + 3].length_lo,
                0,
                "a literal zero is not a member identity"
            );
        }
    }

    #[test]
    fn dependency_batch_rejects_self_and_duplicate_units() {
        let interface = one_function_interface(7, 70, "seven", "run");
        assert!(
            GpuSemanticInterfaceDependencyBatch::from_interfaces(
                7,
                70,
                std::slice::from_ref(&interface)
            )
            .unwrap_err()
            .contains("own semantic interface")
        );
        assert!(
            GpuSemanticInterfaceDependencyBatch::from_interfaces(
                9,
                90,
                &[interface.clone(), interface]
            )
            .unwrap_err()
            .contains("occurs more than once")
        );
    }

    #[test]
    fn dependency_batch_distinguishes_units_of_one_library() {
        let first = one_function_interface(7, 70, "first", "run");
        let second = one_function_interface(7, 71, "second", "run");
        let batch = GpuSemanticInterfaceDependencyBatch::from_interfaces(7, 72, &[second, first])
            .expect("distinct units in one library must have distinct identities");
        assert_eq!(batch.library_ids, vec![7, 7]);
        assert_eq!(batch.unit_ids, vec![70, 71]);
        assert_eq!(batch.declaration_unit_id, vec![70, 71]);
        assert_eq!(batch.type_unit_id, vec![70, 70, 71, 71]);
        assert_eq!(batch.type_local_index, vec![0, 1, 0, 1]);
    }
}
