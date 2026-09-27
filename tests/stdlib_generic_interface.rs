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
