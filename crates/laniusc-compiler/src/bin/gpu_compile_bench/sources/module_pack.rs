use laniusc_compiler::codegen::unit::SourcePackLibraryDependency;

use super::{DeterministicRng, SourceArtifact, append_expected_print, varied_short_ident};

pub(super) fn make_module_pack_source_artifact(
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> SourceArtifact {
    let mut rng = DeterministicRng::new(seed ^ 0x9e37_79b9);
    let root = varied_short_ident("pkg", 0, &mut rng);
    let math_segment = varied_short_ident("math", 1, &mut rng);
    let bridge_segment = varied_short_ident("bridge", 2, &mut rng);
    let math_module = format!("{root}::{math_segment}");
    let bridge_module = format!("{root}::{bridge_segment}");
    let mut math_src = format!("module {math_module};\n");
    let mut bridge_src = format!("module {bridge_module};\nimport {math_module};\n");
    let mut main_src = format!("module app::main;\nimport {bridge_module};\nfn main() {{\n");
    let mut expected_stdout = String::new();
    let mut line_count = 5usize;
    let mut chunk = 0usize;

    loop {
        let projected_len = math_src
            .len()
            .saturating_add(bridge_src.len())
            .saturating_add(main_src.len())
            .saturating_add(32);
        if target_bytes.is_some_and(|target| projected_len >= target)
            || target_bytes.is_none() && line_count >= lines
        {
            break;
        }

        let math_fn = varied_short_ident("mf", chunk, &mut rng);
        let bridge_fn = varied_short_ident("bf", chunk, &mut rng);
        let extra = (rng.small_int() % 23) as i32;
        let threshold = (rng.small_int() % 31 + 8) as i32;
        let bias = (rng.small_int() % 11 + 1) as i32;
        let tail = (rng.small_int() % 17) as i32;
        let arg = (rng.small_int() % 37) as i32;
        let total = arg + extra;
        let math_value = if total > threshold {
            total - bias
        } else {
            total + bias
        };
        append_expected_print(&mut expected_stdout, math_value + tail);

        math_src.push_str("pub fn ");
        math_src.push_str(&math_fn);
        math_src.push_str("(left: i32, right: i32) -> i32 {\n");
        math_src.push_str("    let total: i32 = left + right;\n");
        math_src.push_str("    if (total > ");
        math_src.push_str(&threshold.to_string());
        math_src.push_str(") {\n        return total - ");
        math_src.push_str(&bias.to_string());
        math_src.push_str(";\n    } else {\n        return total + ");
        math_src.push_str(&bias.to_string());
        math_src.push_str(";\n    }\n}\n");

        bridge_src.push_str("pub fn ");
        bridge_src.push_str(&bridge_fn);
        bridge_src.push_str("(value: i32) -> i32 {\n    return ");
        bridge_src.push_str(&math_module);
        bridge_src.push_str("::");
        bridge_src.push_str(&math_fn);
        bridge_src.push_str("(value, ");
        bridge_src.push_str(&extra.to_string());
        bridge_src.push_str(") + ");
        bridge_src.push_str(&tail.to_string());
        bridge_src.push_str(";\n}\n");

        main_src.push_str("    print(");
        main_src.push_str(&bridge_module);
        main_src.push_str("::");
        main_src.push_str(&bridge_fn);
        main_src.push('(');
        main_src.push_str(&arg.to_string());
        main_src.push_str("));\n");

        line_count += 13;
        chunk += 1;
    }

    main_src.push_str("    return 0;\n}\n");
    SourceArtifact::source_pack_with_libraries(
        vec![math_src, bridge_src, main_src],
        vec![0, 1, 2],
        vec![
            SourcePackLibraryDependency {
                library_id: 1,
                depends_on_library_id: 0,
            },
            SourcePackLibraryDependency {
                library_id: 2,
                depends_on_library_id: 1,
            },
        ],
        Some(expected_stdout),
    )
}
