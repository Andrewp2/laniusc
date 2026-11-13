//! Packing of dependency interfaces into GPU dependency pages
//! (`type_checker::dependency_pack`), checked on pages read back from the GPU.
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
        closure_summary: None,
        resident_bytes: Default::default(),
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
    let batch = crate::type_checker::gpu_packed_dependency_page(99, 99, &[second, first]).unwrap();
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
    }

#[test]
fn dependency_batch_is_library_ordered_and_rebases_only_flat_storage() {
    let library_9 = one_function_interface(9, 90, "nine", "run_nine");
    let library_7 = one_function_interface(7, 70, "seven", "run_seven");
    let batch =
        crate::type_checker::gpu_packed_dependency_page(11, 110, &[library_9, library_7])
            .expect("flatten valid dependency interfaces");

    assert_eq!(batch.library_ids, vec![7, 9]);
    assert_eq!(batch.unit_ids, vec![70, 90]);
    assert_eq!(batch.module_library_id, vec![7, 9]);
    assert_eq!(batch.module_unit_id, vec![70, 90]);
    assert_eq!(batch.module_local_index, vec![0, 0]);
    assert_eq!(batch.modules[1].first_segment, 1);
    assert_eq!(batch.module_segments[1].name_byte_start, "sevenrun_seven".len() as u32);
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
    let batch = crate::type_checker::gpu_packed_dependency_page(
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
        crate::type_checker::gpu_packed_dependency_page(
            7,
            70,
            std::slice::from_ref(&interface)
        )
        .unwrap_err()
        .contains("own semantic interface")
    );
    assert!(
        crate::type_checker::gpu_packed_dependency_page(
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
    let batch = crate::type_checker::gpu_packed_dependency_page(7, 72, &[second, first])
        .expect("distinct units in one library must have distinct identities");
    assert_eq!(batch.library_ids, vec![7, 7]);
    assert_eq!(batch.unit_ids, vec![70, 71]);
    assert_eq!(batch.declaration_unit_id, vec![70, 71]);
    assert_eq!(batch.type_unit_id, vec![70, 70, 71, 71]);
    assert_eq!(batch.type_local_index, vec![0, 1, 0, 1]);
}

#[test]
fn dependency_page_module_index_groups_declarations_in_any_module_order() {
    let first = one_function_interface(7, 70, "first", "run");
    let mut second = one_function_interface(7, 71, "m0", "a");
    for (module, name) in ["m1", "m2"].into_iter().enumerate() {
        let (name_hash_lo, name_hash_hi) = stable_name_hash(name.as_bytes());
        second.module_segments.push(GpuSemanticInterfaceModuleSegmentRecord {
            name_hash_lo,
            name_hash_hi,
            name_byte_start: second.name_bytes.len() as u32,
            name_byte_len: name.len() as u32,
        });
        second.name_bytes.extend_from_slice(name.as_bytes());
        second.modules.push(GpuSemanticInterfaceModuleRecord {
            first_segment: module as u32 + 1,
            segment_count: 1,
        });
    }
    let template = second.declarations[0];
    second.declarations[0].module = 2;
    for (name, module) in [("b", 0), ("c", 2), ("d", 1), ("e", 0)] {
        let (name_hash_lo, name_hash_hi) = stable_name_hash(name.as_bytes());
        second.declarations.push(GpuSemanticInterfaceDeclarationRecord {
            module,
            name_hash_lo,
            name_hash_hi,
            name_byte_start: second.name_bytes.len() as u32,
            name_byte_len: name.len() as u32,
            ..template
        });
        second.name_bytes.extend_from_slice(name.as_bytes());
    }
    second.validate().expect("valid multi-module interface");
    let page = crate::type_checker::gpu_packed_dependency_page(9, 90, &[second, first]).unwrap();
    // Page modules: first's one module, then m0, m1, m2; the second
    // interface's declarations are page rows 1..=5 in modules 3, 1, 3, 2, 1.
    assert_eq!(page.module_declaration_start, [0, 1, 3, 4]);
    assert_eq!(page.module_declaration_count, [1, 2, 1, 2]);
    assert_eq!(page.module_declaration_order, [0, 2, 5, 4, 1, 3]);
    assert_eq!(page.name_bytes, b"firstrunm0am1m2bcde");
}
