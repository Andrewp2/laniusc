//! Stage timing for the existing CPU certificate producer, not GPU compilation.
use std::{env, path::PathBuf, time::Instant};

use anyhow::{Context, Result, ensure};
use laniusc_formal_export::{
    artifact::{ExtractionArtifact, ExtractionArtifactPack, SCHEMA_VERSION},
    extract_typed_artifact_pack,
    lexer,
    lowering,
    parser,
    surface,
};
use serde_json::json;

fn report(stage: &str, started: Instant, source: Option<&str>) {
    eprintln!(
        "{}",
        json!({"stage": stage, "seconds": started.elapsed().as_secs_f64(),
        "source": source})
    );
}

fn main() -> Result<()> {
    let args = env::args_os()
        .skip(1)
        .map(PathBuf::from)
        .collect::<Vec<_>>();
    ensure!(
        args.len() >= 2,
        "usage: profile-extraction <output.json> <source.lani>... (CPU producer only)"
    );
    let started = Instant::now();
    let mut units = Vec::new();
    for path in &args[1..] {
        let name = path.display().to_string();
        let timer = Instant::now();
        let bytes = std::fs::read(path).with_context(|| format!("read {name}"))?;
        report("read_source", timer, Some(&name));
        let timer = Instant::now();
        let (source, raw, tokens) = lexer::extract_tokens(name.clone(), bytes)?;
        report("lex_and_emit_tokens", timer, Some(&name));
        let timer = Instant::now();
        let parsed = parser::parse_tokens(&tokens)?;
        report("parse_and_emit_nodes", timer, Some(&name));
        let timer = Instant::now();
        let mut artifact = ExtractionArtifact::token_only(vec![source], raw, tokens);
        artifact.semantic_token_kinds = parsed.semantic_token_kinds;
        artifact.parse_nodes = parsed.nodes;
        artifact.parse_root = Some(parsed.root);
        artifact.surface = Some(surface::extract_surface(
            &artifact.sources[0],
            &artifact.tokens,
            &artifact.parse_nodes,
            parsed.root,
        )?);
        report("reconstruct_and_emit_surface", timer, Some(&name));
        units.push(artifact);
    }
    let timer = Instant::now();
    let surfaces = units
        .iter()
        .map(|u| u.surface.clone().expect("surface emitted"))
        .collect::<Vec<_>>();
    let lowered = lowering::lower_files(&surfaces)?;
    ensure!(lowered.len() == units.len(), "lowering changed unit count");
    for (unit, lowered) in units.iter_mut().zip(lowered) {
        unit.resolutions = lowered.resolutions;
        unit.types = lowered.types;
        unit.core_program = Some(lowered.program);
        unit.lowering = lowered.lowering;
    }
    report("lower_and_emit_core", timer, None);
    let pack = ExtractionArtifactPack {
        schema_version: SCHEMA_VERSION,
        units,
    };
    let timer = Instant::now();
    let encoded = serde_json::to_vec(&pack)?;
    report("serialize", timer, None);
    let timer = Instant::now();
    std::fs::write(&args[0], &encoded)?;
    report("write", timer, None);
    let total = started.elapsed().as_secs_f64();
    let source_bytes: usize = pack
        .units
        .iter()
        .flat_map(|u| &u.sources)
        .map(|s| s.bytes.len())
        .sum();
    eprintln!(
        "{}",
        json!({"stage": "producer_total", "seconds": total,
        "source_bytes": source_bytes, "certificate_bytes": encoded.len(),
        "parse_nodes": pack.units.iter().map(|u| u.parse_nodes.len()).sum::<usize>(),
        "units": pack.units.len(), "debug_assertions": cfg!(debug_assertions),
        "scope": "CPU extraction through Core, not GPU compile or Lean check"})
    );

    // Outside the measured path: reject a probe that drifts from production.
    let timer = Instant::now();
    let reference = extract_typed_artifact_pack(&args[1..])?;
    ensure!(
        encoded == serde_json::to_vec(&reference)?,
        "profiled producer differs from the production exporter"
    );
    report("reference_equality_audit_excluded", timer, None);
    eprintln!(
        "{}",
        json!({"complete": true, "exact_production_bytes": true})
    );
    Ok(())
}
