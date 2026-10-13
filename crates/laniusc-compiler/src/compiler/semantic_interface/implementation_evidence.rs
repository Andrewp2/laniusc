use std::collections::{BTreeMap, BTreeSet};

use super::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum ContractOwner {
    Declaration(u32),
    Implementation(u32),
}

pub(super) fn validate_contract_owner_capacity(domain: &str, count: usize) -> Result<(), String> {
    // Leave the all-ones owner reference reserved in both domains.
    if count >= IMPLEMENTATION_OWNER_TAG as usize {
        return Err(format!(
            "semantic-interface {domain} count exceeds contract owner domain"
        ));
    }
    Ok(())
}

pub(super) fn validate_contract_owner(
    owner_ref: u32,
    declarations: usize,
    implementations: usize,
) -> Result<ContractOwner, String> {
    if owner_ref == INVALID {
        return Err("semantic-interface contract owner is invalid".into());
    }
    let index = owner_ref & !IMPLEMENTATION_OWNER_TAG;
    if owner_ref & IMPLEMENTATION_OWNER_TAG == 0 {
        validate_index("contract declaration owner", 0, index, declarations)?;
        Ok(ContractOwner::Declaration(index))
    } else {
        validate_index("contract implementation owner", 0, index, implementations)?;
        Ok(ContractOwner::Implementation(index))
    }
}

pub(super) fn rebase_contract_owner(
    owner_ref: u32,
    declaration_base: u32,
    implementation_base: u32,
) -> Result<u32, String> {
    if owner_ref == INVALID {
        return Err("semantic-interface contract owner is invalid".into());
    }
    let tag = owner_ref & IMPLEMENTATION_OWNER_TAG;
    let base = if tag == 0 {
        declaration_base
    } else {
        implementation_base
    };
    let index = base
        .checked_add(owner_ref & !IMPLEMENTATION_OWNER_TAG)
        .filter(|&index| index < IMPLEMENTATION_OWNER_TAG - 1)
        .ok_or_else(|| {
            "semantic-interface rebased owner exceeds contract owner domain".to_string()
        })?;
    Ok(tag | index)
}

impl GpuSemanticInterfaceArtifact {
    /// Resolve an executable method through its explicit implementation owner.
    /// A public inherent scope is also its native symbol by the shared producer
    /// contract. Trait bodies always use their explicit binding target.
    pub fn implementation_method_target(&self, member_index: u32) -> Result<[u32; 3], String> {
        let member = self.members.get(member_index as usize)
            .ok_or_else(|| "semantic-interface callable member is out of range".to_string())?;
        let owner = validate_contract_owner(member.owner_ref, self.declarations.len(), self.implementations.len())?;
        let ContractOwner::Implementation(index) = owner else {
            return Err("semantic-interface callable has no implementation owner".into());
        };
        let implementation = self.implementations[index as usize];
        if member.kind != GpuSemanticInterfaceMemberKind::ImplementationMethod as u32
            || !self.contract_owner_member_range(owner)?.contains(&(member_index as usize))
            || member.value_hi & 0xc000_0000 != 0x8000_0000
            || member.value_lo & 0x8000_0000 != 0
            || [self.library_id, self.unit_id].contains(&INVALID)
        {
            return Err("semantic-interface callable has an invalid implementation member identity".into());
        }
        match GpuSemanticInterfaceImplementationKind::from_u32(implementation.kind) {
            Some(GpuSemanticInterfaceImplementationKind::Inherent) => {
                if implementation.visibility != 1 || !member.trait_method_is_public()
                    || [implementation.trait_library_id, implementation.trait_unit_id,
                        implementation.trait_declaration_index] != [INVALID; 3]
                    || implementation.argument_count != 0 || implementation.method_binding_count != 0
                {
                    return Err("semantic-interface inherent callable has an invalid public target contract".into());
                }
                Ok([self.library_id, self.unit_id, member.value_hi])
            }
            Some(GpuSemanticInterfaceImplementationKind::Trait) => {
                let range = checked_range("implementation method binding", index as usize,
                    implementation.first_method_binding, implementation.method_binding_count,
                    self.implementation_method_bindings.len())?;
                let mut targets = self.implementation_method_bindings[range].iter().filter(|binding|
                    binding.implementation_index == index && binding.implementation_method_member == member_index);
                let binding = targets.next().ok_or_else(|| "semantic-interface trait callable lacks a binding".to_string())?;
                if targets.next().is_some()
                    || binding.target_library_id != self.library_id || binding.target_unit_id != self.unit_id
                    || if member.trait_method_is_public() { binding.target_symbol != member.value_hi }
                        else { binding.target_symbol == INVALID || binding.target_symbol & 0xc000_0000 != 0x4000_0000 }
                {
                    return Err("semantic-interface trait callable has an invalid executable target".into());
                }
                Ok([binding.target_library_id, binding.target_unit_id, binding.target_symbol])
            }
            None => Err("semantic-interface callable has an unknown implementation kind".into()),
        }
    }

    /// The complete explicit owner inventory determines its enclosing header;
    /// signature graph reachability does not determine lexical ownership.
    pub fn inherent_implementation_scope(&self, implementation_index: u32) -> Result<Option<u32>, String> {
        let implementation = self.implementations.get(implementation_index as usize)
            .ok_or_else(|| "semantic-interface inherent implementation is out of range".to_string())?;
        if implementation.kind != GpuSemanticInterfaceImplementationKind::Inherent as u32 {
            return Err("semantic-interface owner is not an inherent implementation".into());
        }
        self.implementation_parameter_scope(implementation_index)
    }

    /// Exact lexical impl scope, shared by inherent and trait owners. Method
    /// scopes remain separate even when they use the same composed slot numbers.
    pub(super) fn implementation_parameter_scope(&self, implementation_index: u32) -> Result<Option<u32>, String> {
        let implementation = self.implementations.get(implementation_index as usize)
            .ok_or_else(|| "semantic-interface implementation is out of range".to_string())?;
        if GpuSemanticInterfaceImplementationKind::from_u32(implementation.kind).is_none() {
            return Err("semantic-interface implementation has an unknown kind".into());
        }
        let owner_ref = IMPLEMENTATION_OWNER_TAG | implementation_index;
        let members = self.contract_owner_member_range(ContractOwner::Implementation(implementation_index))?;
        let mut scopes = BTreeSet::new();
        for member in &self.members[members] {
            if member.owner_ref != owner_ref {
                return Err("semantic-interface implementation header has a foreign owner".into());
            }
            if matches!(GpuSemanticInterfaceMemberKind::from_u32(member.kind),
                Some(GpuSemanticInterfaceMemberKind::GenericTypeParameter | GpuSemanticInterfaceMemberKind::GenericConstParameter))
                && member.value_hi & 0xc000_0000 == 0xc000_0000
            {
                scopes.insert(member.value_hi);
            }
        }
        let prerequisites = checked_range("implementation prerequisite", implementation_index as usize,
            implementation.first_prerequisite, implementation.prerequisite_count, self.predicates.len())?;
        for predicate in &self.predicates[prerequisites] {
            if predicate.owner_ref != owner_ref || predicate.owner_scope_symbol == INVALID
                || predicate.owner_scope_symbol & 0xc000_0000 != 0xc000_0000
            {
                return Err("semantic-interface implementation prerequisite has a foreign lexical owner".into());
            }
            scopes.insert(predicate.owner_scope_symbol);
        }
        if scopes.len() > 1 || scopes.contains(&INVALID) {
            return Err("semantic-interface implementation mixes different impl parameter scopes".into());
        }
        Ok(scopes.into_iter().next())
    }

    fn validate_inherent_implementation(&self, index: usize) -> Result<(), String> {
        let implementation = self.implementations[index];
        if implementation.visibility != 1
            || [implementation.trait_library_id, implementation.trait_unit_id,
                implementation.trait_declaration_index] != [INVALID; 3]
            || implementation.argument_count != 0 || implementation.method_binding_count != 0
        {
            return Err(format!("semantic-interface inherent implementation {index} has invalid visibility or trait fields"));
        }
        self.validate_value_type_root("implementation subject", index, implementation.subject_type)?;
        let members = self.contract_owner_member_range(ContractOwner::Implementation(index as u32))?;
        let methods = self.members[members.clone()].iter().enumerate()
            .filter(|(_, member)| member.kind == GpuSemanticInterfaceMemberKind::ImplementationMethod as u32)
            .map(|(row, member)| (members.start + row, member)).collect::<Vec<_>>();
        if methods.is_empty() {
            return Err(format!("semantic-interface inherent implementation {index} has no public methods"));
        }
        let scope = self.inherent_implementation_scope(index as u32)?;
        let implementation_scopes = scope.into_iter().collect::<BTreeSet<_>>();
        self.validate_implementation_graph(index, vec![implementation.subject_type], &implementation_scopes)?;
        let mut counts = BTreeMap::<(u32, u32), Vec<u32>>::new();
        for member in &self.members[members.clone()] {
            if matches!(GpuSemanticInterfaceMemberKind::from_u32(member.kind),
                Some(GpuSemanticInterfaceMemberKind::GenericTypeParameter | GpuSemanticInterfaceMemberKind::GenericConstParameter))
            {
                if Some(member.value_hi) != scope && !methods.iter().any(|(_, method)| method.value_hi == member.value_hi) {
                    return Err(format!("semantic-interface inherent implementation {index} has a foreign header scope"));
                }
                counts.entry((member.value_hi, member.kind)).or_default().push(member.type_binding_slot());
            }
        }
        let mut inherited_counts = [0; 2];
        for (domain, kind) in [GpuSemanticInterfaceMemberKind::GenericTypeParameter,
            GpuSemanticInterfaceMemberKind::GenericConstParameter].into_iter().enumerate()
        {
            let mut slots = scope.and_then(|scope| counts.get(&(scope, kind as u32))).cloned().unwrap_or_default();
            slots.sort_unstable();
            if slots.len() > 32 || slots.iter().copied().ne(0..slots.len() as u32) {
                return Err(format!("semantic-interface inherent implementation {index} has an incomplete lexical binding scope"));
            }
            inherited_counts[domain] = slots.len() as u32;
        }
        for (row, method) in methods {
            self.implementation_method_target(row as u32)?;
            if !self.implementation_types_match(implementation.subject_type, method.receiver_type_index, &BTreeMap::new()) {
                return Err(format!("semantic-interface implementation method {row} receiver disagrees with its full subject"));
            }
            for (domain, kind, required) in [
                (0, GpuSemanticInterfaceMemberKind::GenericTypeParameter, method.method_type_parameter_count()),
                (1, GpuSemanticInterfaceMemberKind::GenericConstParameter, method.method_constant_parameter_count()),
            ] {
                let mut own_slots = counts.get(&(method.value_hi, kind as u32)).cloned().unwrap_or_default();
                own_slots.sort_unstable();
                let inherited = inherited_counts[domain];
                if required != inherited + own_slots.len() as u32
                    || own_slots.iter().copied().ne(inherited..required)
                {
                    return Err(format!("semantic-interface inherent method {row} has an incomplete composed header"));
                }
            }
            let mut scopes = implementation_scopes.clone();
            scopes.insert(method.value_hi);
            let roots = std::iter::once(method.type_index).chain(self.members[members.clone()].iter()
                .filter(|parameter| parameter.kind == GpuSemanticInterfaceMemberKind::Parameter as u32
                    && parameter.value_hi == method.value_hi).map(|parameter| parameter.type_index)).collect();
            self.validate_implementation_graph(index, roots, &scopes)?;
        }
        self.validate_implementation_prerequisites(index, scope)
    }

    fn validate_implementation_prerequisites(&self, index: usize, scope: Option<u32>) -> Result<(), String> {
        let implementation = self.implementations[index];
        let owner_ref = IMPLEMENTATION_OWNER_TAG | index as u32;
        let prerequisites = checked_range("implementation prerequisite", index,
            implementation.first_prerequisite, implementation.prerequisite_count, self.predicates.len())?;
        for (row, predicate) in self.predicates.iter().enumerate().filter(|(_, predicate)| predicate.owner_ref == owner_ref) {
            if predicate.owner_scope_symbol & 0xc000_0000 == 0xc000_0000
                && (!prerequisites.contains(&row) || Some(predicate.owner_scope_symbol) != scope)
            {
                return Err(format!("semantic-interface implementation prerequisite {row} is outside its implementation range"));
            }
        }
        Ok(())
    }

    fn validate_implementation_graph(&self, index: usize, roots: Vec<u32>, scopes: &BTreeSet<u32>) -> Result<(), String> {
        let owner_ref = IMPLEMENTATION_OWNER_TAG | index as u32;
        for root in self.predicate_graph_nodes(roots) {
            let ty = self.types[root as usize];
            if (ty.kind == GpuSemanticInterfaceTypeKind::Scalar as u32 && !crate::primitive_types::is_known(ty.payload_lo))
                || (ty.kind == GpuSemanticInterfaceTypeKind::Declaration as u32
                    && [ty.payload_lo, ty.nominal_unit_id, ty.payload_hi].contains(&INVALID))
            {
                return Err(format!("semantic-interface implementation {index} has an unresolved type identity"));
            }
            if let Some(parameter) = predicate_parameter_member(ty) {
                let member = self.members[parameter as usize];
                if member.owner_ref != owner_ref || !scopes.contains(&member.value_hi) {
                    return Err(format!("semantic-interface implementation {index} uses a foreign lexical parameter"));
                }
            }
        }
        Ok(())
    }

    pub(super) fn contract_owner_member_range(
        &self,
        owner: ContractOwner,
    ) -> Result<std::ops::Range<usize>, String> {
        let (first, count) = match owner {
            ContractOwner::Declaration(index) => {
                let row = self.declarations[index as usize];
                (row.first_member, row.member_count)
            }
            ContractOwner::Implementation(index) => {
                let row = self.implementations[index as usize];
                (row.first_member, row.member_count)
            }
        };
        checked_range("contract owner member", 0, first, count, self.members.len())
    }

    /// Run before any implementation-owned member or graph can be dereferenced.
    pub(super) fn validate_implementation_ranges(&self) -> Result<(), String> {
        for (index, implementation) in self.implementations.iter().enumerate() {
            validate_index(
                "implementation module",
                index,
                implementation.module,
                self.modules.len(),
            )?;
            validate_index(
                "implementation subject",
                index,
                implementation.subject_type,
                self.types.len(),
            )?;
            let members =
                self.contract_owner_member_range(ContractOwner::Implementation(index as u32))?;
            let owner_ref = IMPLEMENTATION_OWNER_TAG | index as u32;
            if self.members[members]
                .iter()
                .any(|member| member.owner_ref != owner_ref)
            {
                return Err(format!(
                    "semantic-interface implementation {index} contains a foreign member owner"
                ));
            }
            let arguments = checked_range(
                "implementation argument",
                index,
                implementation.first_argument,
                implementation.argument_count,
                self.implementation_arguments.len(),
            )?;
            for row in arguments {
                validate_index(
                    "implementation argument root",
                    row,
                    self.implementation_arguments[row],
                    self.types.len(),
                )?;
            }
            validate_range(
                "implementation prerequisite",
                index,
                implementation.first_prerequisite,
                implementation.prerequisite_count,
                self.predicates.len(),
            )?;
            validate_range(
                "implementation method binding",
                index,
                implementation.first_method_binding,
                implementation.method_binding_count,
                self.implementation_method_bindings.len(),
            )?;
        }
        for (row, binding) in self.implementation_method_bindings.iter().enumerate() {
            validate_index(
                "method binding implementation",
                row,
                binding.implementation_index,
                self.implementations.len(),
            )?;
            validate_index(
                "method binding callable member",
                row,
                binding.implementation_method_member,
                self.members.len(),
            )?;
        }
        Ok(())
    }

    pub(super) fn validate_implementations(&self) -> Result<(), String> {
        let mut argument_owners = vec![None; self.implementation_arguments.len()];
        let mut binding_owners = vec![None; self.implementation_method_bindings.len()];
        if !self.implementations.is_empty() && [self.library_id, self.unit_id].contains(&INVALID) {
            return Err("semantic-interface implementation has an unresolved defining unit".into());
        }
        for (index, implementation) in self.implementations.iter().enumerate() {
            let owner_ref = IMPLEMENTATION_OWNER_TAG | index as u32;
            match GpuSemanticInterfaceImplementationKind::from_u32(implementation.kind) {
                Some(GpuSemanticInterfaceImplementationKind::Inherent) => {
                    self.validate_inherent_implementation(index)?;
                    continue;
                }
                Some(GpuSemanticInterfaceImplementationKind::Trait) => {}
                None => return Err(format!("semantic-interface implementation {index} has unknown kind {}", implementation.kind)),
            }
            if implementation.visibility > 1
                || [
                    implementation.trait_library_id,
                    implementation.trait_unit_id,
                    implementation.trait_declaration_index,
                ]
                .contains(&INVALID)
            {
                return Err(format!("semantic-interface implementation {index} has invalid visibility or trait identity"));
            }
            if implementation.argument_count > 32 {
                return Err(format!(
                    "semantic-interface implementation {index} exceeds 32 ordered operands"
                ));
            }
            self.validate_value_type_root(
                "implementation subject",
                index,
                implementation.subject_type,
            )?;
            let arguments = implementation.first_argument as usize
                ..(implementation.first_argument + implementation.argument_count) as usize;
            let roots = &self.implementation_arguments[arguments.clone()];
            for row in arguments {
                if argument_owners[row].replace(index).is_some() {
                    return Err(format!(
                        "semantic-interface implementation argument {row} has multiple owners"
                    ));
                }
            }
            let (implementation_scope, inherited_counts) = self.validate_trait_implementation_header(index,
                std::iter::once(implementation.subject_type)
                    .chain(roots.iter().copied()).collect())?;
            let implementation_scopes = implementation_scope.into_iter().collect::<BTreeSet<_>>();
            let members =
                self.contract_owner_member_range(ContractOwner::Implementation(index as u32))?;
            let methods = members
                .clone()
                .filter(|&row| {
                    self.members[row].kind
                        == GpuSemanticInterfaceMemberKind::ImplementationMethod as u32
                })
                .collect::<BTreeSet<_>>();
            for row in members.clone() {
                let member = self.members[row];
                if matches!(
                    GpuSemanticInterfaceMemberKind::from_u32(member.kind),
                    Some(
                        GpuSemanticInterfaceMemberKind::GenericTypeParameter
                            | GpuSemanticInterfaceMemberKind::GenericConstParameter
                    )
                ) {
                    // Owned header parameters were validated against the complete
                    // trait head above; they do not have value-type signatures.
                    continue;
                }
                if member.kind == GpuSemanticInterfaceMemberKind::Parameter as u32
                    && !methods
                        .iter()
                        .any(|&method| self.members[method].value_hi == member.value_hi)
                {
                    return Err(format!(
                        "semantic-interface implementation parameter {row} has no owning method"
                    ));
                }
                if member.kind == GpuSemanticInterfaceMemberKind::ImplementationMethod as u32 {
                    if [member.method_type_parameter_count(), member.method_constant_parameter_count()]
                        != inherited_counts
                    {
                        return Err(format!("semantic-interface implementation method {row} has an incomplete inherited header"));
                    }
                    if self.predicates.iter().any(|predicate|
                        predicate.owner_ref == owner_ref && predicate.owner_scope_symbol == member.value_hi)
                    {
                        return Err(format!("semantic-interface trait implementation method {row} own prerequisites are unsupported"));
                    }
                    if !self.implementation_types_match(
                        implementation.subject_type,
                        member.receiver_type_index,
                        &BTreeMap::new(),
                    ) {
                        return Err(format!("semantic-interface implementation method {row} receiver disagrees with its full subject"));
                    }
                }
                self.validate_implementation_graph(index, vec![member.type_index], &implementation_scopes)?;
            }
            let local_trait = if implementation.trait_library_id == self.library_id
                && implementation.trait_unit_id == self.unit_id
            {
                validate_index(
                    "implementation trait declaration",
                    index,
                    implementation.trait_declaration_index,
                    self.declarations.len(),
                )?;
                let declaration =
                    self.declarations[implementation.trait_declaration_index as usize];
                if declaration.kind != 10 || declaration.namespace != 3 {
                    return Err(format!(
                        "semantic-interface implementation {index} does not name a trait"
                    ));
                }
                let header = self.types[declaration.signature_type as usize];
                if header.edge_count != implementation.argument_count {
                    return Err(format!("semantic-interface implementation {index} trait arity disagrees with its operands"));
                }
                let mut substitutions = BTreeMap::new();
                for (ordinal, &root) in roots.iter().enumerate() {
                    let leaf = self.types
                        [self.type_edges[header.first_edge as usize + ordinal].type_index as usize];
                    if !self.parameter_operand_domain_matches(leaf.payload_lo, root) {
                        return Err(format!("semantic-interface implementation {index} operand {ordinal} has the wrong declared domain"));
                    }
                    substitutions.insert(leaf.payload_lo, root);
                }
                let required = self.members[declaration.first_member as usize
                    ..(declaration.first_member + declaration.member_count) as usize]
                    .iter()
                    .filter(|member| {
                        member.kind == GpuSemanticInterfaceMemberKind::TraitMethod as u32
                    })
                    .map(|member| (member.value_hi, member))
                    .collect::<BTreeMap<_, _>>();
                Some((required, substitutions))
            } else {
                None
            };
            let bindings = implementation.first_method_binding as usize
                ..(implementation.first_method_binding + implementation.method_binding_count)
                    as usize;
            let mut bound_methods = BTreeSet::new();
            let mut required_symbols = BTreeSet::new();
            for row in bindings {
                if binding_owners[row].replace(index).is_some() {
                    return Err(format!("semantic-interface implementation method binding {row} has multiple owners"));
                }
                let binding = self.implementation_method_bindings[row];
                let member_index = binding.implementation_method_member as usize;
                let member = self.members[member_index];
                if binding.implementation_index != index as u32
                    || member.owner_ref != owner_ref
                    || !methods.contains(&member_index)
                    || !bound_methods.insert(member_index)
                    || binding.required_method_symbol == INVALID
                    || binding.required_method_symbol & 0xc000_0000 != 0x8000_0000
                    || !required_symbols.insert(binding.required_method_symbol)
                {
                    return Err(format!("semantic-interface implementation method binding {row} has invalid or duplicate ownership"));
                }
                // Current exported evidence binds bodies in its defining unit.
                // Default/forwarded method bodies require a later contract.
                let target_matches = if member.trait_method_is_public() {
                    binding.target_symbol == member.value_hi
                } else {
                    binding.target_symbol != INVALID
                        && binding.target_symbol & 0xc000_0000 == 0x4000_0000
                };
                if binding.target_library_id != self.library_id
                    || binding.target_unit_id != self.unit_id
                    || !target_matches
                {
                    return Err(format!("semantic-interface implementation method binding {row} has an invalid executable target"));
                }
                if let Some((required, substitutions)) = &local_trait {
                    let expected = required.get(&binding.required_method_symbol)
                        .ok_or_else(|| format!("semantic-interface implementation method binding {row} names no required method"))?;
                    // Required methods have no own generic header in this
                    // capability. An implementation method additionally carries
                    // its enclosing impl's separately validated parameter counts.
                    let generic_count_bits = 0x0fff_0000;
                    if expected.method_type_parameter_count() != 0
                        || expected.method_constant_parameter_count() != 0
                        || (expected.value_lo & !generic_count_bits) != (member.value_lo & !generic_count_bits)
                        || !self.implementation_types_match(
                            expected.type_index,
                            member.type_index,
                            substitutions,
                        )
                    {
                        return Err(format!("semantic-interface implementation method binding {row} signature disagrees with its trait"));
                    }
                    let expected_parameters = self.members.iter().filter(|parameter| {
                        parameter.owner_ref == implementation.trait_declaration_index
                            && parameter.kind == GpuSemanticInterfaceMemberKind::Parameter as u32
                            && parameter.value_hi == expected.value_hi
                    });
                    for expected_parameter in expected_parameters {
                        let actual = self.members[members.clone()].iter().find(|parameter|
                            parameter.kind == GpuSemanticInterfaceMemberKind::Parameter as u32 &&
                            parameter.value_hi == member.value_hi && parameter.value_lo == expected_parameter.value_lo)
                            .ok_or_else(|| format!("semantic-interface implementation method binding {row} lacks a required parameter"))?;
                        if !self.implementation_types_match(
                            expected_parameter.type_index,
                            actual.type_index,
                            substitutions,
                        ) {
                            return Err(format!("semantic-interface implementation method binding {row} parameter disagrees with its trait"));
                        }
                    }
                }
            }
            if bound_methods != methods
                || local_trait
                    .as_ref()
                    .is_some_and(|(required, _)| required.len() != required_symbols.len())
            {
                return Err(format!("semantic-interface implementation {index} has an incomplete required-method binding set"));
            }
        }
        if argument_owners.iter().any(Option::is_none) || binding_owners.iter().any(Option::is_none)
        {
            return Err(
                "semantic-interface implementation arguments or method bindings have no owner"
                    .into(),
            );
        }
        Ok(())
    }

    fn validate_trait_implementation_header(&self, index: usize, roots: Vec<u32>) -> Result<(Option<u32>, [u32; 2]), String> {
        let scope = self.implementation_parameter_scope(index as u32)?;
        let members = self.contract_owner_member_range(ContractOwner::Implementation(index as u32))?;
        let mut parameters = BTreeSet::new();
        let mut slots = [Vec::new(), Vec::new()];
        for row in members {
            let member = self.members[row];
            let domain = match GpuSemanticInterfaceMemberKind::from_u32(member.kind) {
                Some(GpuSemanticInterfaceMemberKind::GenericTypeParameter) => 0,
                Some(GpuSemanticInterfaceMemberKind::GenericConstParameter) => 1,
                _ => continue,
            };
            if Some(member.value_hi) != scope {
                return Err(format!("semantic-interface trait implementation {index} has a foreign header scope"));
            }
            parameters.insert(row as u32);
            slots[domain].push(member.type_binding_slot());
        }
        for domain in &mut slots {
            domain.sort_unstable();
            if domain.len() > 32 || domain.iter().copied().ne(0..domain.len() as u32) {
                return Err(format!("semantic-interface trait implementation {index} has an incomplete lexical binding scope"));
            }
        }
        let scopes = scope.into_iter().collect::<BTreeSet<_>>();
        self.validate_implementation_graph(index, roots.clone(), &scopes)?;
        let used = self.predicate_graph_nodes(roots).into_iter()
            .filter_map(|row| predicate_parameter_member(self.types[row as usize]))
            .collect::<BTreeSet<_>>();
        if used != parameters {
            return Err(format!("semantic-interface trait implementation {index} has an unconstrained implementation parameter"));
        }
        self.validate_implementation_prerequisites(index, scope)?;
        Ok((scope, [slots[0].len() as u32, slots[1].len() as u32]))
    }

    /// Compare complete graphs, substituting only exact trait header members.
    fn implementation_types_match(
        &self,
        expected: u32,
        actual: u32,
        substitutions: &BTreeMap<u32, u32>,
    ) -> bool {
        let mut pending = vec![(expected, actual)];
        let mut seen = BTreeSet::new();
        while let Some((expected, actual)) = pending.pop() {
            if !seen.insert((expected, actual)) {
                continue;
            }
            let left = self.types[expected as usize];
            let right = self.types[actual as usize];
            if matches!(
                GpuSemanticInterfaceTypeKind::from_u32(left.kind),
                Some(
                    GpuSemanticInterfaceTypeKind::GenericParameter
                        | GpuSemanticInterfaceTypeKind::ConstParameter
                )
            ) {
                if let Some(&root) = substitutions.get(&left.payload_lo) {
                    pending.push((root, actual));
                    continue;
                }
            }
            if left.kind != right.kind || left.edge_count != right.edge_count {
                return false;
            }
            let equal = match GpuSemanticInterfaceTypeKind::from_u32(left.kind).unwrap() {
                GpuSemanticInterfaceTypeKind::Scalar
                | GpuSemanticInterfaceTypeKind::GenericParameter
                | GpuSemanticInterfaceTypeKind::ConstParameter
                | GpuSemanticInterfaceTypeKind::CountProjection
                | GpuSemanticInterfaceTypeKind::Reference => left.payload_lo == right.payload_lo,
                GpuSemanticInterfaceTypeKind::Declaration => {
                    (left.payload_lo, left.nominal_unit_id, left.payload_hi)
                        == (right.payload_lo, right.nominal_unit_id, right.payload_hi)
                }
                GpuSemanticInterfaceTypeKind::ConstValue => {
                    (left.payload_lo, left.length_lo, left.length_hi)
                        == (right.payload_lo, right.length_lo, right.length_hi)
                }
                GpuSemanticInterfaceTypeKind::Array
                | GpuSemanticInterfaceTypeKind::Slice | GpuSemanticInterfaceTypeKind::Function => {
                    true
                }
            };
            if !equal {
                return false;
            }
            for ordinal in 0..left.edge_count {
                pending.push((
                    self.type_edges[(left.first_edge + ordinal) as usize].type_index,
                    self.type_edges[(right.first_edge + ordinal) as usize].type_index,
                ));
            }
        }
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn inherent_interface() -> GpuSemanticInterfaceArtifact {
        let mut interface = super::super::tests::representative_interface();
        interface.members.push(GpuSemanticInterfaceMemberRecord {
            owner_ref: IMPLEMENTATION_OWNER_TAG,
            kind: GpuSemanticInterfaceMemberKind::ImplementationMethod as u32,
            ordinal: 0, value_lo: 1 << 30, value_hi: 0x8000_0003,
            receiver_type_index: 0, ..interface.members[0]
        });
        interface.implementations.push(GpuSemanticInterfaceImplementationRecord {
            module: 0, visibility: 1, trait_library_id: INVALID, trait_unit_id: INVALID,
            trait_declaration_index: INVALID, subject_type: 0, first_argument: 0, argument_count: 0,
            first_member: 1, member_count: 1, first_prerequisite: 0, prerequisite_count: 0,
            first_method_binding: 0, method_binding_count: 0,
            kind: GpuSemanticInterfaceImplementationKind::Inherent as u32,
        });
        interface
    }

    fn symbolic_inherent_interface() -> GpuSemanticInterfaceArtifact {
        let mut interface = inherent_interface();
        let prototype = interface.members[0];
        interface.members.truncate(1);
        for (ordinal, kind, scope, slot, source_ordinal) in [
            (0, 2, 0xc000_0007, 0, 0), (1, 3, 0xc000_0007, 0, 1),
            (2, 2, 0x8000_0003, 1, 0), (3, 3, 0x8000_0003, 1, 1),
        ] {
            interface.members.push(GpuSemanticInterfaceMemberRecord {
                owner_ref: IMPLEMENTATION_OWNER_TAG, kind, ordinal, type_index: if kind == 3 { 0 } else { INVALID },
                value_lo: slot, value_hi: scope, generic_parameter_ordinal: source_ordinal, ..prototype
            });
        }
        interface.members.push(GpuSemanticInterfaceMemberRecord {
            owner_ref: IMPLEMENTATION_OWNER_TAG, kind: 8, ordinal: 4, type_index: 2,
            value_lo: (2 << 16) | (2 << 22) | (1 << 30), value_hi: 0x8000_0003,
            receiver_type_index: 5, ..prototype
        });
        let leaf = interface.types[0];
        interface.types.extend([
            GpuSemanticInterfaceTypeRecord { kind: 2, payload_lo: 3, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 8, payload_lo: 2, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 2, payload_lo: 1, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 4, first_edge: 1, edge_count: 2, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 8, payload_lo: 4, ..leaf },
        ]);
        interface.type_edges.extend([4, 3].map(|type_index| GpuSemanticInterfaceTypeEdge { type_index }));
        interface.implementations[0].subject_type = 5;
        interface.implementations[0].member_count = 5;
        interface.implementations[0].prerequisite_count = 1;
        interface.predicates.extend([
            GpuSemanticInterfacePredicateRecord {
                owner_ref: IMPLEMENTATION_OWNER_TAG, owner_scope_symbol: 0xc000_0007,
                subject_type: 4, trait_library_id: 99, trait_unit_id: 100, trait_declaration_index: 0,
                first_argument: 0, argument_count: 0,
            },
            GpuSemanticInterfacePredicateRecord {
                owner_ref: IMPLEMENTATION_OWNER_TAG, owner_scope_symbol: 0x8000_0003,
                subject_type: 2, trait_library_id: 99, trait_unit_id: 100, trait_declaration_index: 1,
                first_argument: 0, argument_count: 1,
            },
        ]);
        interface.predicate_arguments.push(6);
        interface
    }

    fn symbolic_marker_interface() -> GpuSemanticInterfaceArtifact {
        let mut interface = inherent_interface();
        let prototype = interface.members[0];
        interface.members.truncate(1);
        for (ordinal, name, kind) in [(0, "T", 2), (1, "N", 3)] {
            let start = interface.name_bytes.len() as u32;
            interface.name_bytes.extend_from_slice(name.as_bytes());
            let hash = stable_name_hash(name.as_bytes());
            interface.members.push(GpuSemanticInterfaceMemberRecord {
                owner_ref: IMPLEMENTATION_OWNER_TAG, kind, ordinal,
                name_hash_lo: hash.0, name_hash_hi: hash.1,
                name_byte_start: start, name_byte_len: name.len() as u32,
                type_index: if kind == 3 { 0 } else { INVALID }, value_lo: 0, value_hi: 0xc000_0007,
                generic_parameter_ordinal: ordinal, ..prototype
            });
        }
        let leaf = interface.types[0];
        interface.types.extend([
            GpuSemanticInterfaceTypeRecord { kind: 8, payload_lo: 2, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 2, payload_lo: 1, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 4, first_edge: 1, edge_count: 2, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 6, payload_lo: 0, first_edge: 3, edge_count: 1, ..leaf },
        ]);
        interface.type_edges.extend([3, 2, 4].map(|type_index| GpuSemanticInterfaceTypeEdge { type_index }));
        let implementation = &mut interface.implementations[0];
        implementation.kind = GpuSemanticInterfaceImplementationKind::Trait as u32;
        implementation.trait_library_id = 99;
        implementation.trait_unit_id = 100;
        implementation.trait_declaration_index = 0;
        implementation.subject_type = 5;
        implementation.member_count = 2;
        implementation.prerequisite_count = 1;
        interface.predicates.push(GpuSemanticInterfacePredicateRecord {
            owner_ref: IMPLEMENTATION_OWNER_TAG, owner_scope_symbol: 0xc000_0007,
            subject_type: 3, trait_library_id: 99, trait_unit_id: 100,
            trait_declaration_index: 1, first_argument: 0, argument_count: 0,
        });
        interface
    }

    #[test]
    fn marker_headers_and_prerequisites_roundtrip_and_rebase_owned_graphs() {
        let first = symbolic_marker_interface();
        let bytes = first.to_bytes().expect("owned T,N in &[T;N] with a T prerequisite");
        assert_eq!(GpuSemanticInterfaceArtifact::from_bytes(&bytes).unwrap(), first);
        let mut second = first.clone();
        second.unit_id += 1;
        let batch = dependency_batch::GpuSemanticInterfaceDependencyBatch::from_interfaces(
            99, 999, &[first, second]).unwrap();
        assert_eq!(batch.members[4].owner_ref, IMPLEMENTATION_OWNER_TAG | 1);
        assert_eq!(batch.members[5].value_hi, 0xc000_0007);
        assert_eq!(batch.types[8].payload_lo, 5);
        assert_eq!(batch.predicates[1].owner_ref, IMPLEMENTATION_OWNER_TAG | 1);
        assert_eq!(batch.implementations[1].first_prerequisite, 1);
        assert_eq!(batch.implementations[1].prerequisite_count, 1);

        let mut operands = symbolic_marker_interface();
        operands.implementations[0].subject_type = 0;
        operands.implementations[0].argument_count = 1;
        operands.implementation_arguments.push(5);
        operands.validate().expect("ordered trait operands constrain both parameters");
    }

    #[test]
    fn marker_headers_require_every_parameter_in_the_head_and_exact_prerequisite_ownership() {
        let original = symbolic_marker_interface();
        for (subject, description) in [(0, "T only in a prerequisite"), (3, "N absent from the head")] {
            let mut unconstrained = original.clone();
            unconstrained.implementations[0].subject_type = subject;
            assert!(unconstrained.validate().unwrap_err().contains("unconstrained implementation parameter"),
                "{description}");
        }
        for case in 0..5 {
            let mut malformed = original.clone();
            match case {
                0 => malformed.implementations[0].prerequisite_count = 0,
                1 => malformed.predicates[0].owner_ref = 0,
                2 => malformed.predicates[0].owner_scope_symbol = 0xc000_0008,
                3 => malformed.members[2].value_lo = 1,
                4 => malformed.members[1].owner_ref = 0,
                _ => unreachable!(),
            }
            assert!(malformed.validate().is_err(), "malformed marker contract {case} accepted");
        }
        let mut inherent = symbolic_inherent_interface();
        inherent.implementations[0].subject_type = 0;
        inherent.members[5].receiver_type_index = 0;
        inherent.validate().expect("head inferability is a trait selection rule, not an inherent header rule");
    }

    #[test]
    fn trait_methods_retain_exact_inherited_headers_and_binding_targets() {
        let mut interface = symbolic_marker_interface();
        interface.members.push(GpuSemanticInterfaceMemberRecord {
            owner_ref: IMPLEMENTATION_OWNER_TAG, kind: 8, ordinal: 2,
            value_lo: (1 << 16) | (1 << 22) | (1 << 30), value_hi: 0x8000_0003,
            receiver_type_index: 5, ..interface.members[0]
        });
        interface.implementations[0].member_count += 1;
        interface.implementations[0].method_binding_count = 1;
        interface.implementation_method_bindings.push(GpuSemanticInterfaceImplementationMethodBindingRecord {
            implementation_index: 0, required_method_symbol: 0x8000_0011,
            implementation_method_member: 3, target_library_id: interface.library_id,
            target_unit_id: interface.unit_id, target_symbol: 0x8000_0003,
        });
        let bytes = interface.to_bytes().expect("method inherits exact T and N scopes");
        assert_eq!(GpuSemanticInterfaceArtifact::from_bytes(&bytes).unwrap(), interface);
        for case in 0..4 {
            let mut malformed = interface.clone();
            match case {
                0 => malformed.members[3].value_lo &= !(63 << 16),
                1 => malformed.members[3].value_lo += 1 << 22,
                2 => malformed.members[1].value_hi = 0x8000_0003,
                3 => {
                    let mut bound = malformed.predicates[0];
                    bound.owner_scope_symbol = 0x8000_0003;
                    malformed.predicates.push(bound);
                }
                _ => unreachable!(),
            }
            assert!(malformed.validate().is_err(), "incomplete/foreign inherited method environment {case}");
        }
    }

    #[test]
    fn inherent_owners_roundtrip_every_receiver_shape_and_exact_native_target() {
        for kind in [1, 3, 4, 5, 6] {
            let mut interface = inherent_interface();
            let leaf = interface.types[0];
            let subject = if kind == 1 { 0 } else if kind == 3 {
                interface.types.push(GpuSemanticInterfaceTypeRecord {
                    kind, payload_lo: 99, nominal_unit_id: 100, payload_hi: 7, ..leaf
                });
                2
            } else if kind == 4 {
                interface.types.extend([
                    GpuSemanticInterfaceTypeRecord { kind: 9, length_lo: 3, ..leaf },
                    leaf,
                    GpuSemanticInterfaceTypeRecord { kind: 4, first_edge: 1, edge_count: 2, ..leaf },
                ]);
                interface.type_edges.extend([3, 2].map(|type_index| GpuSemanticInterfaceTypeEdge { type_index }));
                4
            } else {
                interface.types.push(leaf);
                interface.types.push(GpuSemanticInterfaceTypeRecord {
                    kind, payload_lo: 0, first_edge: 1, edge_count: 1,
                    ..leaf
                });
                interface.type_edges.push(GpuSemanticInterfaceTypeEdge { type_index: 2 });
                if kind == 6 {
                    interface.types.push(GpuSemanticInterfaceTypeRecord {
                        kind, payload_lo: 0, first_edge: 2, edge_count: 1, ..leaf
                    });
                    interface.type_edges.push(GpuSemanticInterfaceTypeEdge { type_index: 3 });
                    4
                } else { 3 }
            };
            interface.implementations[0].subject_type = subject;
            interface.members[1].receiver_type_index = subject;
            let bytes = interface.to_bytes().expect("inherent receiver is a full graph");
            assert_eq!(GpuSemanticInterfaceArtifact::from_bytes(&bytes).unwrap(), interface);
            assert_eq!(interface.implementation_method_target(1).unwrap(), [7, 11, 0x8000_0003]);
            assert_eq!(interface.inherent_implementation_scope(0).unwrap(), None);
        }
    }

    #[test]
    fn inherent_headers_and_bounds_keep_exact_lexical_ownership_through_roundtrip_and_rebase() {
        let first = symbolic_inherent_interface();
        let bytes = first.to_bytes().expect("complete implementation and method headers");
        assert_eq!(GpuSemanticInterfaceArtifact::from_bytes(&bytes).unwrap(), first);
        assert_eq!(first.inherent_implementation_scope(0).unwrap(), Some(0xc000_0007));
        // The impl header remains complete even if its parameter is now used
        // only by a bound; subject graph reachability does not define ownership.
        let mut bounds_only = first.clone();
        bounds_only.implementations[0].subject_type = 0;
        bounds_only.members[5].receiver_type_index = 0;
        bounds_only.validate().expect("predicate-only inherited parameters retain their owner");
        let mut second = first.clone();
        second.unit_id += 1;
        let batch = dependency_batch::GpuSemanticInterfaceDependencyBatch::from_interfaces(99, 999, &[second, first]).unwrap();
        assert_eq!(batch.members[7].owner_ref, IMPLEMENTATION_OWNER_TAG | 1);
        assert_eq!(batch.members[7].value_hi, 0xc000_0007);
        assert_eq!(batch.members[11].value_hi, 0x8000_0003);
        assert_eq!(batch.types[10].payload_lo, 8);
        assert_eq!(batch.predicates[2].owner_ref, IMPLEMENTATION_OWNER_TAG | 1);
        assert_eq!(batch.implementations[1].first_prerequisite, 2);
        assert_eq!(batch.implementations[1].prerequisite_count, 1);
    }

    #[test]
    fn inherent_owners_reject_forged_kind_target_receiver_headers_and_dropped_prerequisites() {
        let original = symbolic_inherent_interface();
        for case in 0..12 {
            let mut interface = original.clone();
            match case {
                0 => interface.implementations[0].kind = 99,
                1 => interface.implementations[0].trait_library_id = 1,
                2 => interface.members[5].value_lo &= !(1 << 30),
                3 => interface.members[5].value_hi = 0x4000_0003,
                4 => interface.members[5].receiver_type_index = 0,
                5 => interface.members[5].value_lo -= 1 << 16,
                6 => interface.members[1].value_hi = 0xc000_0008,
                7 => interface.implementations[0].prerequisite_count = 0,
                8 => interface.predicates[1].owner_scope_symbol = 0x8000_0004,
                9 => interface.implementations[0].first_prerequisite = 1,
                10 => interface.members[1].value_lo = 1,
                11 => interface.implementations[0].visibility = 0,
                _ => unreachable!(),
            }
            assert!(interface.validate().is_err(), "malformed inherent contract {case} accepted");
        }
        let mut foreign_subject = original.clone();
        foreign_subject.types[4].payload_lo = 3; // method-owned T in the impl subject
        assert!(foreign_subject.validate().unwrap_err().contains("foreign lexical parameter"));
        let mut binding = original;
        binding.implementation_method_bindings.push(GpuSemanticInterfaceImplementationMethodBindingRecord {
            implementation_index: 0, required_method_symbol: 0x8000_0003,
            implementation_method_member: 5, target_library_id: 7, target_unit_id: 11, target_symbol: 0x8000_0003,
        });
        binding.implementations[0].method_binding_count = 1;
        assert!(binding.validate().is_err());
    }

    fn concrete_implementation_interface() -> GpuSemanticInterfaceArtifact {
        let mut interface = super::super::tests::representative_interface();
        let prototype = interface.members[0];
        let name_start = interface.name_bytes.len() as u32;
        interface.name_bytes.extend_from_slice(b"Shape");
        let name_hash = stable_name_hash(b"Shape");
        interface
            .declarations
            .push(GpuSemanticInterfaceDeclarationRecord {
                name_hash_lo: name_hash.0,
                name_hash_hi: name_hash.1,
                name_byte_start: name_start,
                name_byte_len: 5,
                namespace: 3,
                kind: 10,
                signature_type: 3,
                first_member: 1,
                member_count: 3,
                ..interface.declarations[0]
            });
        let requirements = 1 | (1 << 28) | (1 << 30);
        interface.members.extend([
            GpuSemanticInterfaceMemberRecord {
                owner_ref: 1,
                kind: 2,
                ordinal: 0,
                type_index: INVALID,
                generic_parameter_ordinal: 0,
                ..prototype
            },
            GpuSemanticInterfaceMemberRecord {
                owner_ref: 1,
                kind: 7,
                ordinal: 1,
                type_index: 7,
                value_lo: requirements,
                value_hi: 0x8000_0011,
                ..prototype
            },
            GpuSemanticInterfaceMemberRecord {
                owner_ref: 1,
                ordinal: 2,
                type_index: 7,
                value_lo: 1,
                value_hi: 0x8000_0011,
                ..prototype
            },
            GpuSemanticInterfaceMemberRecord {
                owner_ref: IMPLEMENTATION_OWNER_TAG,
                kind: 8,
                ordinal: 0,
                type_index: 11,
                value_lo: requirements,
                value_hi: 0x8000_0012,
                receiver_type_index: 11,
                ..prototype
            },
            GpuSemanticInterfaceMemberRecord {
                owner_ref: IMPLEMENTATION_OWNER_TAG,
                ordinal: 1,
                type_index: 11,
                value_lo: 1,
                value_hi: 0x8000_0012,
                ..prototype
            },
        ]);
        let leaf = interface.types[0];
        interface.types.extend([
            GpuSemanticInterfaceTypeRecord { kind: 2, payload_lo: 1, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 3, payload_lo: interface.library_id,
                nominal_unit_id: interface.unit_id, payload_hi: 1,
                first_edge: 1, edge_count: 1, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 9, length_lo: 2, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 2, payload_lo: 1, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 4, first_edge: 2, edge_count: 2, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 6, first_edge: 4, edge_count: 1, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 9, length_lo: 2, ..leaf },
            leaf,
            GpuSemanticInterfaceTypeRecord { kind: 4, first_edge: 5, edge_count: 2, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 6, first_edge: 7, edge_count: 1, ..leaf },
        ]);
        interface.type_edges.extend([2, 5, 4, 6, 9, 8, 10].map(|type_index|
            GpuSemanticInterfaceTypeEdge { type_index }));
        interface
            .implementations
            .push(GpuSemanticInterfaceImplementationRecord {
                module: 0,
                visibility: 1,
                trait_library_id: interface.library_id,
                trait_unit_id: interface.unit_id,
                trait_declaration_index: 1,
                subject_type: 11,
                first_argument: 0,
                argument_count: 1,
                first_member: 4,
                member_count: 2,
                first_prerequisite: 0,
                prerequisite_count: 0,
                first_method_binding: 0,
                method_binding_count: 1,
                kind: GpuSemanticInterfaceImplementationKind::Trait as u32,
            });
        interface.implementation_arguments.push(0);
        interface.implementation_method_bindings.push(
            GpuSemanticInterfaceImplementationMethodBindingRecord {
                implementation_index: 0,
                required_method_symbol: 0x8000_0011,
                implementation_method_member: 4,
                target_library_id: interface.library_id,
                target_unit_id: interface.unit_id,
                target_symbol: 0x8000_0012,
            },
        );
        interface
    }

    #[test]
    fn implementation_evidence_roundtrip_retains_compound_subject_and_private_callable() {
        for public in [false, true] {
            let mut interface = concrete_implementation_interface();
            if !public {
                interface.members[2].value_lo &= !(1 << 30);
                interface.members[4].value_lo &= !(1 << 30);
                interface.implementation_method_bindings[0].target_symbol = 0x4000_0021;
            }
            assert_eq!(interface.implementation_method_target(4).unwrap(),
                [interface.library_id, interface.unit_id, if public { 0x8000_0012 } else { 0x4000_0021 }]);
            let bytes = interface
                .to_bytes()
                .expect("validated full implementation contract");
            assert_eq!(
                GpuSemanticInterfaceArtifact::from_bytes(&bytes).unwrap(),
                interface
            );
            for offset in [56, 60, 64] {
                assert_eq!(
                    u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap()),
                    1
                );
            }
            let mut stale = bytes.clone();
            stale[8..12].copy_from_slice(&11u32.to_le_bytes());
            assert!(GpuSemanticInterfaceArtifact::from_bytes(&stale)
                .unwrap_err()
                .contains("version 11"));
            let mut malformed = bytes;
            malformed[68..72].copy_from_slice(&1u32.to_le_bytes());
            assert!(GpuSemanticInterfaceArtifact::from_bytes(&malformed)
                .unwrap_err()
                .contains("reserved"));
        }
    }

    #[test]
    fn implementation_evidence_constant_operand_substitutes_array_length() {
        let mut interface = concrete_implementation_interface();
        interface.members[1].kind = GpuSemanticInterfaceMemberKind::GenericConstParameter as u32;
        interface.types[2].kind = GpuSemanticInterfaceTypeKind::ConstParameter as u32;
        interface.members[1].type_index = 0;
        interface.types[5] = interface.types[0];
        interface.types[4] = GpuSemanticInterfaceTypeRecord {
            kind: GpuSemanticInterfaceTypeKind::ConstParameter as u32,
            payload_lo: 1, ..interface.types[0]
        };
        interface.types.push(GpuSemanticInterfaceTypeRecord {
            kind: GpuSemanticInterfaceTypeKind::ConstValue as u32,
            length_lo: 2,
            ..interface.types[0]
        });
        interface.implementation_arguments[0] = 12;
        interface
            .validate()
            .expect("complete constant operand graph");
        interface.types[12].length_lo = 3;
        assert!(interface
            .validate()
            .unwrap_err()
            .contains("signature disagrees"));
    }

    #[test]
    fn implementation_evidence_matching_preserves_scalar_bits_and_projection_structure() {
        use crate::primitive_types::*;
        let mut interface = inherent_interface();
        let leaf = interface.types[0];
        for (scalar, bits) in [
            (SCALAR_U64, [7, 1]), (SCALAR_U64, [7, 1]),
            (SCALAR_U64, [7, 2]), (SCALAR_I64, [7, 1]),
            (SCALAR_F32, [0, 0]), (SCALAR_F32, [0x80000000, 0]),
            (SCALAR_F64, [0x1234, 0x7ff80000]), (SCALAR_F64, [0x1235, 0x7ff80000]),
        ] {
            interface.types.push(GpuSemanticInterfaceTypeRecord {
                kind: 9, payload_lo: scalar, length_lo: bits[0], length_hi: bits[1], ..leaf
            });
        }
        interface.types.extend([
            GpuSemanticInterfaceTypeRecord { kind: 9, payload_lo: SCALAR_U64, length_lo: 7, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 10, payload_lo: SCALAR_U8, first_edge: 1, edge_count: 1, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 9, payload_lo: SCALAR_U64, length_lo: 7, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 10, payload_lo: SCALAR_U8, first_edge: 2, edge_count: 1, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 9, payload_lo: SCALAR_U64, length_lo: 7, ..leaf },
            GpuSemanticInterfaceTypeRecord { kind: 10, payload_lo: SCALAR_U16, first_edge: 3, edge_count: 1, ..leaf },
        ]);
        interface.type_edges.extend([10, 12, 14].map(|type_index| GpuSemanticInterfaceTypeEdge { type_index }));
        interface.validate().unwrap();
        let empty = BTreeMap::new();
        assert!(interface.implementation_types_match(2, 3, &empty));
        for (left, right) in [(2, 4), (2, 5), (6, 7), (8, 9), (11, 15), (11, 10)] {
            assert!(!interface.implementation_types_match(left, right, &empty),
                "distinct typed constant graphs {left}, {right} must not match");
        }
        assert!(interface.implementation_types_match(11, 13, &empty));
    }

    #[test]
    fn implementation_evidence_local_constant_operands_require_exact_declared_scalar() {
        let mut interface = concrete_implementation_interface();
        interface.members[1].kind = GpuSemanticInterfaceMemberKind::GenericConstParameter as u32;
        interface.members[1].type_index = 0;
        interface.types[2].kind = GpuSemanticInterfaceTypeKind::ConstParameter as u32;
        interface.types[5] = interface.types[0];
        interface.types[4] = GpuSemanticInterfaceTypeRecord {
            kind: GpuSemanticInterfaceTypeKind::ConstParameter as u32,
            payload_lo: 1, ..interface.types[0]
        };
        interface.implementation_arguments[0] = 8;
        interface.validate().expect("i32 header and i32 operand");
        interface.types[8].payload_lo = crate::primitive_types::SCALAR_U32;
        assert!(interface.validate().unwrap_err().contains("wrong declared domain"));
    }

    #[test]
    fn implementation_evidence_rejects_corrupt_ownership_identity_and_bindings() {
        let original = concrete_implementation_interface();
        original.validate().unwrap();
        for change in 0..24 {
            let mut interface = original.clone();
            match change {
                0 => interface.members[4].owner_ref = 0,
                1 => interface.members[0].owner_ref = IMPLEMENTATION_OWNER_TAG,
                2 => interface.members[4].owner_ref = INVALID,
                3 => interface.implementations[0].subject_type = INVALID,
                4 => interface.implementations[0].trait_unit_id = INVALID,
                5 => interface.implementations[0].trait_declaration_index = 0,
                6 => interface.implementations[0].argument_count = 0,
                7 => interface.implementation_arguments[0] = INVALID,
                8 => interface.implementation_arguments.push(0),
                9 => interface.implementation_method_bindings[0].implementation_index = 1,
                10 => interface.implementation_method_bindings[0].implementation_method_member = 2,
                11 => {
                    interface.implementation_method_bindings[0].required_method_symbol = 0x8000_0099
                }
                12 => interface.implementation_method_bindings[0].target_unit_id += 1,
                13 => interface.implementation_method_bindings[0].target_symbol += 1,
                14 => interface
                    .implementation_method_bindings
                    .push(interface.implementation_method_bindings[0]),
                15 => interface.implementations[0].method_binding_count = 0,
                16 => interface.members[4].receiver_type_index = 10,
                17 => interface.members[5].type_index = 0,
                18 => interface.members[5].value_hi = 0,
                19 => interface.implementations[0].subject_type = 2,
                20 => interface.implementations[0].first_argument = INVALID,
                21 => interface.implementations[0].visibility = 2,
                22 => interface.implementations[0].member_count = INVALID,
                23 => interface.members[4].value_lo |= 1 << 16,
                _ => unreachable!(),
            }
            assert!(
                interface.validate().is_err(),
                "corrupt implementation contract {change}"
            );
        }
        let mut duplicate = original.clone();
        duplicate
            .implementation_method_bindings
            .push(duplicate.implementation_method_bindings[0]);
        duplicate.implementations[0].method_binding_count = 2;
        assert!(duplicate
            .validate()
            .unwrap_err()
            .contains("duplicate ownership"));
        let mut malformed = original;
        malformed.types[9].payload_lo = 0;
        assert!(malformed
            .validate()
            .unwrap_err()
            .contains("unknown scalar identity"));
    }

    #[test]
    fn implementation_evidence_rebases_tagged_owners_without_rebasing_symbols() {
        let first = concrete_implementation_interface();
        let mut second = first.clone();
        second.unit_id += 1;
        second.types[3].nominal_unit_id = second.unit_id;
        second.implementations[0].trait_unit_id = second.unit_id;
        second.implementation_method_bindings[0].target_unit_id = second.unit_id;
        let member_base = first.members.len() as u32;
        let type_base = first.types.len() as u32;
        let batch = dependency_batch::GpuSemanticInterfaceDependencyBatch::from_interfaces(
            99,
            99,
            &[second.clone(), first.clone()],
        )
        .unwrap();
        assert_eq!(batch.implementation_library_id, [7, 7]);
        assert_eq!(batch.implementation_unit_id, [11, 12]);
        assert_eq!(batch.implementation_local_index, [0, 0]);
        assert_eq!(
            batch.members[member_base as usize + 4].owner_ref,
            IMPLEMENTATION_OWNER_TAG | 1
        );
        assert_eq!(batch.members[member_base as usize + 1].owner_ref, 3);
        assert_eq!(batch.implementation_arguments, [0, type_base]);
        assert_eq!(
            batch.implementations[1],
            GpuSemanticInterfaceImplementationRecord {
                module: 1,
                subject_type: type_base + 11,
                first_argument: 1,
                first_member: member_base + 4,
                first_method_binding: 1,
                ..second.implementations[0]
            }
        );
        assert_eq!(
            batch.implementation_method_bindings[1],
            GpuSemanticInterfaceImplementationMethodBindingRecord {
                implementation_index: 1,
                implementation_method_member: member_base + 4,
                ..second.implementation_method_bindings[0]
            }
        );
        assert_eq!(
            rebase_contract_owner(IMPLEMENTATION_OWNER_TAG, 17, 3).unwrap(),
            IMPLEMENTATION_OWNER_TAG | 3
        );
        assert!(rebase_contract_owner(INVALID, 0, 0).is_err());
        assert!(rebase_contract_owner(1, IMPLEMENTATION_OWNER_TAG - 1, 0).is_err());
    }

    #[test]
    fn implementation_evidence_keeps_imported_nominal_subject_identity() {
        let mut interface = concrete_implementation_interface();
        interface.types[9] = GpuSemanticInterfaceTypeRecord {
            kind: GpuSemanticInterfaceTypeKind::Declaration as u32,
            payload_lo: 99,
            nominal_unit_id: 42,
            payload_hi: 17,
            ..interface.types[9]
        };
        interface.implementation_arguments[0] = 9;
        let bytes = interface
            .to_bytes()
            .expect("reference to array of imported nominal elements");
        assert_eq!(
            GpuSemanticInterfaceArtifact::from_bytes(&bytes).unwrap(),
            interface
        );
    }

    #[test]
    fn implementation_evidence_rejects_unowned_headers_and_prerequisites() {
        let original = concrete_implementation_interface();
        let mut generic = original.clone();
        generic.members.push(GpuSemanticInterfaceMemberRecord {
            kind: GpuSemanticInterfaceMemberKind::GenericTypeParameter as u32,
            ordinal: 2,
            value_lo: 0,
            value_hi: 0,
            type_index: INVALID,
            receiver_type_index: INVALID,
            generic_parameter_ordinal: 0,
            ..generic.members[4]
        });
        generic.implementations[0].member_count += 1;
        assert!(generic
            .validate()
            .unwrap_err()
            .contains("foreign header scope"));
        let mut prerequisites = original;
        prerequisites
            .predicates
            .push(GpuSemanticInterfacePredicateRecord {
                owner_ref: IMPLEMENTATION_OWNER_TAG,
                owner_scope_symbol: 0,
                subject_type: 11,
                trait_library_id: 99,
                trait_unit_id: 42,
                trait_declaration_index: 0,
                first_argument: 0,
                argument_count: 0,
            });
        prerequisites.implementations[0].prerequisite_count = 1;
        assert!(prerequisites
            .validate()
            .unwrap_err()
            .contains("foreign lexical owner"));
    }

    #[test]
    fn implementation_evidence_marker_trait_requires_no_callable_binding() {
        let mut interface = concrete_implementation_interface();
        interface.members.truncate(2);
        interface.declarations[1].member_count = 1;
        interface.implementations[0].first_member = 2;
        interface.implementations[0].member_count = 0;
        interface.implementations[0].method_binding_count = 0;
        interface.implementation_method_bindings.clear();
        interface
            .validate()
            .expect("complete marker implementation");
    }
}
