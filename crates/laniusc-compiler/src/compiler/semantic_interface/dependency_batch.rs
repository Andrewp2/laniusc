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
    pub(crate) types: Vec<GpuSemanticInterfaceTypeRecord>,
    pub(crate) type_edges: Vec<GpuSemanticInterfaceTypeEdge>,
    pub(crate) members: Vec<GpuSemanticInterfaceMemberRecord>,
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
        self.types.extend(interface.types.iter().map(|ty| {
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
            GpuSemanticInterfaceTypeRecord {
                kind: ty.kind,
                payload_lo,
                payload_hi: ty.payload_hi,
                first_edge: edge_base + ty.first_edge,
                edge_count: ty.edge_count,
                length_kind: ty.length_kind,
                length_lo: ty.length_lo,
                length_hi: ty.length_hi,
                nominal_unit_id: ty.nominal_unit_id,
            }
        }));
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
            GpuSemanticInterfaceMemberRecord {
                owner_declaration: declaration_base + member.owner_declaration,
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
            }
        }));
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
        checked_u32_len("dependency name byte", self.name_bytes.len())?;
        if self.module_library_id.len() != self.modules.len()
            || self.module_unit_id.len() != self.modules.len()
            || self.module_local_index.len() != self.modules.len()
            || self.declaration_library_id.len() != self.declarations.len()
            || self.declaration_unit_id.len() != self.declarations.len()
            || self.declaration_local_index.len() != self.declarations.len()
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
            validate_index(
                "dependency member owner",
                index,
                member.owner_declaration,
                self.declarations.len(),
            )?;
            validate_optional_index(
                "dependency member type",
                index,
                member.type_index,
                self.types.len(),
            )?;
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
            name_bytes,
        }
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
        assert_eq!(batch.declarations[1].module, 1);
        assert_eq!(batch.declarations[1].signature_type, 3);
        assert_eq!(batch.types[3].first_edge, 1);
        assert_eq!(batch.type_edges[1].type_index, 2);
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
    }
}
