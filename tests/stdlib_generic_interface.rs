mod common;

use laniusc_compiler::compiler::{
    GpuSemanticInterfaceArtifact,
    GpuSemanticInterfaceMemberKind,
    GpuSemanticInterfaceTypeKind,
};

fn declaration<'a>(
    artifact: &'a GpuSemanticInterfaceArtifact,
    name: &str,
) -> &'a laniusc_compiler::compiler::GpuSemanticInterfaceDeclarationRecord {
    artifact
        .declarations
        .iter()
        .find(|declaration| {
            let start = declaration.name_byte_start as usize;
            let end = start + declaration.name_byte_len as usize;
            &artifact.name_bytes[start..end] == name.as_bytes()
        })
        .unwrap_or_else(|| panic!("missing exported declaration {name}"))
}

#[test]
fn generic_option_and_result_variant_payloads_refer_to_their_enum_parameters() {
    let artifact = common::semantic_interface_with_timeout(
        0,
        &[
            include_str!("../stdlib/core/result.lani"),
            include_str!("../stdlib/core/option.lani"),
        ],
    )
    .expect("export real generic Option and Result interfaces");

    for (enum_name, variant_name, parameter_ordinal) in [
        ("Option", "Some", 0),
        ("Result", "Ok", 0),
        ("Result", "Err", 1),
    ] {
        let parent = declaration(&artifact, enum_name);
        let generic_member = artifact.members[(parent.first_member + parameter_ordinal) as usize];
        assert_eq!(
            generic_member.kind,
            GpuSemanticInterfaceMemberKind::GenericTypeParameter as u32,
            "{enum_name} parameter {parameter_ordinal}"
        );

        let variant = declaration(&artifact, variant_name);
        let signature = artifact.types[variant.signature_type as usize];
        assert_eq!(signature.edge_count, 2, "{variant_name} signature");
        let payload_edge = artifact.type_edges[signature.first_edge as usize];
        let payload = artifact.types[payload_edge.type_index as usize];
        assert_eq!(
            payload.kind,
            GpuSemanticInterfaceTypeKind::GenericParameter as u32,
            "{variant_name} payload"
        );
        assert_eq!(
            payload.payload_lo,
            parent.first_member + parameter_ordinal,
            "{variant_name} must refer to {enum_name}'s generic member"
        );
    }
}

#[test]
fn non_generic_public_methods_are_exported_as_associated_members() {
    let artifact = common::semantic_interface_with_timeout(
        0,
        &[include_str!(
            "fixtures/stdlib_foundation/repro_imported_associated_new_root/core/thing.lani"
        )],
    )
    .expect("export Thing interface");
    let thing = declaration(&artifact, "Thing");
    let thing_index = artifact
        .declarations
        .iter()
        .position(|candidate| std::ptr::eq(candidate, thing))
        .expect("Thing declaration index") as u32;
    let methods: Vec<_> = artifact.members
        [thing.first_member as usize..(thing.first_member + thing.member_count) as usize]
        .iter()
        .filter(|member| member.kind == GpuSemanticInterfaceMemberKind::AssociatedMethod as u32)
        .collect();
    for method in &methods {
        let receiver = &artifact.types[method.receiver_type_index as usize];
        assert_eq!(receiver.kind, GpuSemanticInterfaceTypeKind::Declaration as u32);
        assert_eq!(receiver.payload_lo, artifact.library_id);
        assert_eq!(receiver.nominal_unit_id, artifact.unit_id);
        assert_eq!(receiver.payload_hi, thing_index);
    }
    let names: Vec<_> = methods
        .iter()
        .map(|member| {
            let start = member.name_byte_start as usize;
            let end = start + member.name_byte_len as usize;
            String::from_utf8_lossy(&artifact.name_bytes[start..end]).into_owned()
        })
        .collect();
    assert_eq!(names.len(), 2, "both public Thing methods must be exported");
    assert!(names.contains(&"new".to_string()));
    assert!(names.contains(&"get".to_string()));
}

#[test]
fn generic_vec_public_methods_remain_exported_as_associated_members() {
    let artifact =
        common::semantic_interface_with_timeout(0, &[include_str!("../stdlib/std/vec.lani")])
            .expect("export Vec interface");
    let vector = declaration(&artifact, "Vec");
    let names: Vec<_> = artifact.members
        [vector.first_member as usize..(vector.first_member + vector.member_count) as usize]
        .iter()
        .filter(|member| member.kind == GpuSemanticInterfaceMemberKind::AssociatedMethod as u32)
        .map(|member| {
            let start = member.name_byte_start as usize;
            let end = start + member.name_byte_len as usize;
            String::from_utf8_lossy(&artifact.name_bytes[start..end]).into_owned()
        })
        .collect();
    assert_eq!(names.len(), 3);
    for name in ["new", "len", "is_empty"] {
        assert!(names.contains(&name.to_string()), "missing Vec::{name}");
    }
}
