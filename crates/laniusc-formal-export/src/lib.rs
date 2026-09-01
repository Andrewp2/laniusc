//! Untrusted CPU producer for formal-extraction certificates.
//!
//! Nothing in this crate is part of the trusted proof base. It emits data that
//! the Lean checker must validate against the original source bytes.

pub mod artifact;
pub mod core;
pub mod lexer;
pub mod lowering;
pub mod parser;
pub mod surface;

use std::path::Path;

use anyhow::{Context, Result};
use artifact::{ExtractionArtifact, ExtractionArtifactPack, SCHEMA_VERSION};

fn extract_bytes(path: String, bytes: Vec<u8>) -> Result<ExtractionArtifact> {
    let (source, raw_tokens, tokens) = lexer::extract_tokens(path, bytes)?;
    let parsed = parser::parse_tokens(&tokens)?;
    let mut artifact = ExtractionArtifact::token_only(vec![source], raw_tokens, tokens);
    artifact.semantic_token_kinds = parsed.semantic_token_kinds;
    artifact.parse_nodes = parsed.nodes;
    artifact.parse_root = Some(parsed.root);
    artifact.surface = Some(surface::extract_surface(
        &artifact.sources[0],
        &artifact.tokens,
        &artifact.parse_nodes,
        parsed.root,
    )?);
    Ok(artifact)
}

fn attach_lowered(
    mut artifact: ExtractionArtifact,
    lowered: lowering::LoweredProgram,
) -> ExtractionArtifact {
    artifact.resolutions = lowered.resolutions;
    artifact.types = lowered.types;
    artifact.core_program = Some(lowered.program);
    artifact.lowering = lowered.lowering;
    artifact
}

fn attach_core(artifact: ExtractionArtifact) -> Result<ExtractionArtifact> {
    let surface = artifact
        .surface
        .as_ref()
        .context("cannot lower an extraction artifact without Surface syntax")?;
    let lowered = lowering::lower_file(surface)?;
    Ok(attach_lowered(artifact, lowered))
}

pub fn extract_artifact(path: &Path) -> Result<ExtractionArtifact> {
    let bytes = std::fs::read(path)
        .with_context(|| format!("read extraction source {}", path.display()))?;
    extract_bytes(path.display().to_string(), bytes)
}

pub fn extract_typed_artifact(path: &Path) -> Result<ExtractionArtifact> {
    attach_core(extract_artifact(path)?)
}

pub fn extract_typed_artifact_pack(paths: &[impl AsRef<Path>]) -> Result<ExtractionArtifactPack> {
    let mut units = paths
        .iter()
        .map(|path| extract_artifact(path.as_ref()))
        .collect::<Result<Vec<_>>>()?;
    let surfaces = units
        .iter()
        .map(|unit| {
            unit.surface
                .clone()
                .context("cannot lower an extraction unit without Surface syntax")
        })
        .collect::<Result<Vec<_>>>()?;
    let lowered = lowering::lower_files(&surfaces)?;
    units = units
        .into_iter()
        .zip(lowered)
        .map(|(unit, lowered)| attach_lowered(unit, lowered))
        .collect();
    Ok(ExtractionArtifactPack {
        schema_version: SCHEMA_VERSION,
        units,
    })
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    use serde_json::Value;

    use super::*;

    const VERIFIED_SOURCES: &[(&str, &[u8])] = &[
        (
            "canonical_tokens.lani",
            include_bytes!("../../../verified_compiler/src/verified/canonical_tokens.lani"),
        ),
        (
            "decimal.lani",
            include_bytes!("../../../verified_compiler/src/verified/decimal.lani"),
        ),
        (
            "digits.lani",
            include_bytes!("../../../verified_compiler/src/verified/digits.lani"),
        ),
        (
            "lexer.lani",
            include_bytes!("../../../verified_compiler/src/verified/lexer.lani"),
        ),
        (
            "number.lani",
            include_bytes!("../../../verified_compiler/src/verified/number.lani"),
        ),
        (
            "raw_lexer.lani",
            include_bytes!("../../../verified_compiler/src/verified/raw_lexer.lani"),
        ),
        (
            "symbol.lani",
            include_bytes!("../../../verified_compiler/src/verified/symbol.lani"),
        ),
        (
            "token.lani",
            include_bytes!("../../../verified_compiler/src/verified/token.lani"),
        ),
        (
            "token_scan.lani",
            include_bytes!("../../../verified_compiler/src/verified/token_scan.lani"),
        ),
    ];

    fn collect_located_ids(value: &Value, output: &mut Vec<u64>) {
        match value {
            Value::Array(values) => {
                for value in values {
                    collect_located_ids(value, output);
                }
            }
            Value::Object(fields) => {
                if fields.contains_key("parse_node") {
                    output.push(
                        fields
                            .get("id")
                            .and_then(Value::as_u64)
                            .expect("every parse-node origin belongs to a located Surface node"),
                    );
                }
                for value in fields.values() {
                    collect_located_ids(value, output);
                }
            }
            _ => {}
        }
    }

    #[test]
    fn every_verified_frontend_source_has_a_dense_located_surface_tree() {
        for &(name, source) in VERIFIED_SOURCES {
            let artifact = extract_bytes(name.into(), source.to_vec()).unwrap();
            let surface = artifact.surface.as_ref().expect("surface extraction");
            assert_eq!(surface.parse_node, artifact.parse_root.unwrap(), "{name}");

            let encoded = serde_json::to_value(surface).unwrap();
            let mut ids = Vec::new();
            collect_located_ids(&encoded, &mut ids);
            let unique = ids.iter().copied().collect::<BTreeSet<_>>();
            let expected = (0..ids.len() as u64).collect::<BTreeSet<_>>();
            assert_eq!(unique, expected, "{name} has non-dense Surface IDs");
            assert_eq!(ids.len(), unique.len(), "{name} reuses a Surface ID");
            assert_eq!(surface.id as usize + 1, ids.len(), "{name}");
        }
    }

    #[test]
    fn digits_source_lowers_without_a_handwritten_core_tree() {
        let artifact = extract_bytes(
            "digits.lani".into(),
            include_bytes!("../../../verified_compiler/src/verified/digits.lani").to_vec(),
        )
        .unwrap();
        let artifact = attach_core(artifact).unwrap();
        let core = artifact.core_program.as_ref().unwrap();

        assert_eq!(core.structures.len(), 1);
        assert_eq!(core.functions.len(), 7);
        assert!(!artifact.resolutions.is_empty());
        assert!(!artifact.types.is_empty());
        assert!(!artifact.lowering.is_empty());
    }

    #[test]
    fn verified_frontend_pack_uses_global_core_identities() {
        let root =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../verified_compiler/src/verified");
        let paths = VERIFIED_SOURCES
            .iter()
            .map(|(name, _)| root.join(name))
            .collect::<Vec<_>>();
        let pack = extract_typed_artifact_pack(&paths).unwrap();

        assert_eq!(pack.units.len(), VERIFIED_SOURCES.len());

        let mut saw_cross_unit_resolution = false;
        let mut saw_type_resolution = false;
        let mut saw_module_scope_type_resolution = false;
        let mut saw_cross_unit_type_resolution = false;
        for (unit_index, unit) in pack.units.iter().enumerate() {
            let use_node_count = unit.surface.as_ref().unwrap().id + 1;
            for resolution in &unit.resolutions {
                assert!(resolution.use_node < use_node_count);
                let declaration_unit = usize::try_from(resolution.declaration_unit).unwrap();
                let declaration_artifact = pack
                    .units
                    .get(declaration_unit)
                    .expect("resolution declaration unit belongs to this pack");
                let declaration_node_count = declaration_artifact.surface.as_ref().unwrap().id + 1;
                assert!(resolution.declaration_node < declaration_node_count);
                saw_cross_unit_resolution |= declaration_unit != unit_index;
                if resolution.namespace_tag == artifact::Namespace::Type {
                    saw_type_resolution = true;
                    saw_module_scope_type_resolution |= resolution.scope_path.is_empty();
                    saw_cross_unit_type_resolution |= declaration_unit != unit_index;
                }
            }
        }
        assert!(
            saw_cross_unit_resolution,
            "the frontend pack should exercise cross-unit resolution evidence"
        );
        assert!(
            saw_type_resolution,
            "the frontend pack should exercise type-namespace resolution evidence"
        );
        assert!(
            saw_module_scope_type_resolution,
            "declaration signatures should record module-scope type evidence"
        );
        assert!(
            saw_cross_unit_type_resolution,
            "qualified imported types should retain cross-unit declaration identity"
        );
        let structure_ids = pack
            .units
            .iter()
            .flat_map(|unit| &unit.core_program.as_ref().unwrap().structures)
            .map(|declaration| declaration.id)
            .collect::<Vec<_>>();
        let constant_ids = pack
            .units
            .iter()
            .flat_map(|unit| &unit.core_program.as_ref().unwrap().constants)
            .map(|declaration| declaration.id)
            .collect::<Vec<_>>();
        let function_ids = pack
            .units
            .iter()
            .flat_map(|unit| &unit.core_program.as_ref().unwrap().functions)
            .map(|declaration| declaration.id)
            .collect::<Vec<_>>();
        let core_node_ids = pack
            .units
            .iter()
            .flat_map(|unit| &unit.lowering)
            .map(|row| row.core_node)
            .collect::<Vec<_>>();

        for (label, ids) in [
            ("structure", structure_ids),
            ("constant", constant_ids),
            ("function", function_ids),
            ("Core node", core_node_ids),
        ] {
            let unique = ids.iter().copied().collect::<BTreeSet<_>>();
            assert_eq!(ids.len(), unique.len(), "duplicate {label} identity");
        }
    }
}
