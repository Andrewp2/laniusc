//! Retained instance projection (docs/compiler-retained-projection.md).

use laniusc_compiler::{codegen::lowering_capture, compiler::compile_source_to_x86_64_with_gpu_codegen};

#[allow(unused_imports)]
use crate::common;

const ORACLE: &str = r#"struct Hidden { inner: i32 }
pub struct Pair { first: i32, second: u32 }
fn halve(value: i32) -> i32 {
    let cell: Hidden = Hidden { inner: value };
    return cell.inner / 2;
}
fn halveu(value: u32) -> u32 { return value / 2; }
fn mix(p: Pair) -> Pair {
    return Pair { first: halve(p.first), second: halveu(p.second) };
}
fn twice(v: f64) -> f64 { return v + v * 0.5; }
fn main() -> i32 {
    let p = mix(Pair { first: -8, second: 10 });
    if (twice(2.0) > 2.5) { return p.first + 10; }
    return 1;
}
"#;

fn dump(capture: &lowering_capture::Capture) {
    let n = capture["hir.count"][0] as usize;
    let word = |name: &str, i: usize, stride: usize| -> Vec<u32> {
        capture.get(name).map(|w| w[i * stride..(i * stride + stride).min(w.len())].to_vec()).unwrap_or_default()
    };
    let mut names: Vec<_> = capture.keys().cloned().collect();
    names.sort();
    eprintln!("columns: {names:?}");
    for row in 0..n {
        eprintln!(
            "row {row}: core {:?} links {:?} payload {:?} ret {:?} cv {:?} ep {:?} er {:?} nl {:?}",
            word("hir.core", row, 4), word("hir.links", row, 4), word("hir.payload", row, 4),
            word("hir.fn_return_type", row, 1), word("hir.const_value", row, 1),
            word("hir.expression_parents", row, 1), word("hir.expression_roots", row, 1),
            word("hir.nearest_loop", row, 1)
        );
        let mut sem = String::new();
        for name in &names {
            if name.starts_with("typecheck.semantic_") || name == "semantic.expression_types"
                || name == "typecheck.public_decl_index_by_hir"
            {
                let stride = if name.contains("calls_by_hir") { 22 } else if name.contains("value_consts_by_hir") { 2 } else { 1 };
                let w = word(name, row, stride);
                let short = name.trim_start_matches("typecheck.semantic_");
                if w.iter().any(|&x| x != u32::MAX && x != 0) { sem += &format!(" {short}={w:?}"); }
            }
        }
        eprintln!("      {sem}");
    }
    for (name, stride, count) in [("hir.call_args", 4, "hir.call_arg_count"), ("hir.fields", 4, "hir.field_count"),
        ("hir.params", 4, "hir.param_count"), ("typecheck.struct_init_field_ordinals", 1, "hir.field_count")] {
        let c = capture[count][0] as usize;
        for i in 0..c { eprintln!("{name}[{i}] = {:?}", word(name, i, stride)); }
    }
    for i in 0..n { let r = word("hir.param_ranges", i, 2); if r.len()==2 && r[1] != 0 { eprintln!("param_ranges[{i}]={r:?}"); } }
    for name in ["typecheck.type_instance_kind", "typecheck.type_instance_native_words", "typecheck.type_instance_decl_token",
        "typecheck.external_type_library_id", "typecheck.imported_layout_kind", "typecheck.type_instance_arg_count"] {
        let w = &capture[name];
        let live: Vec<_> = w.iter().enumerate().filter(|(_, x)| **x != u32::MAX && **x != 0).take(40).collect();
        eprintln!("{name}: {live:?}");
    }
}

#[test]
fn retained_projection_oracle_columns() {
    lowering_capture::arm(1 << 14);
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(ORACLE)).expect("oracle compiles");
    let captures = lowering_capture::take();
    eprintln!("{} lowering jobs, {} bytes", captures.len(), bytes.len());
    for c in &captures { dump(c); }
    if let Ok(path) = std::env::var("LANIUS_PROJECTION_ORACLE_DUMP") {
        let mut out = String::new();
        for (name, words) in &captures[0] {
            out += &format!("{name} {}\n", words.iter().map(|w| w.to_string()).collect::<Vec<_>>().join(" "));
        }
        std::fs::write(path, out).unwrap();
    }
    let out = common::run_x86_64_elf_output("oracle", "oracle", &bytes);
    assert_eq!(out.status.code(), Some(6));
}
