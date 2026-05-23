use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct LoopCounts {
    long_guard: usize,
    dynamic_bound: usize,
    while_loop: usize,
}

struct ShaderTreeLoopBudget {
    label: &'static str,
    path: &'static str,
    recursive: bool,
    counts: LoopCounts,
    max_static_guard: usize,
}

const SHADER_TREE_LOOP_BUDGET: &[ShaderTreeLoopBudget] = &[
    ShaderTreeLoopBudget {
        label: "all shaders",
        path: "shaders",
        recursive: true,
        counts: LoopCounts {
            long_guard: 45,
            dynamic_bound: 343,
            while_loop: 16,
        },
        max_static_guard: 1024,
    },
    ShaderTreeLoopBudget {
        label: "shared shader helpers",
        path: "shaders",
        recursive: false,
        counts: LoopCounts {
            long_guard: 0,
            dynamic_bound: 45,
            while_loop: 7,
        },
        max_static_guard: 32,
    },
    ShaderTreeLoopBudget {
        label: "lexer shaders",
        path: "shaders/lexer",
        recursive: false,
        counts: LoopCounts {
            long_guard: 0,
            dynamic_bound: 8,
            while_loop: 0,
        },
        max_static_guard: 0,
    },
    ShaderTreeLoopBudget {
        label: "parser shaders",
        path: "shaders/parser",
        recursive: false,
        counts: LoopCounts {
            long_guard: 21,
            dynamic_bound: 24,
            while_loop: 5,
        },
        max_static_guard: 1024,
    },
    ShaderTreeLoopBudget {
        label: "type-check shaders",
        path: "shaders/type_checker",
        recursive: false,
        counts: LoopCounts {
            long_guard: 22,
            dynamic_bound: 136,
            while_loop: 4,
        },
        max_static_guard: 512,
    },
    ShaderTreeLoopBudget {
        label: "codegen shaders",
        path: "shaders/codegen",
        recursive: true,
        counts: LoopCounts {
            long_guard: 2,
            dynamic_bound: 130,
            while_loop: 0,
        },
        max_static_guard: 384,
    },
];

const TYPE_CHECK_LOOP_BUDGET: &[(&str, LoopCounts)] = &[
    (
        "type_check_calls_03_resolve.slang",
        LoopCounts {
            long_guard: 1,
            dynamic_bound: 6,
            while_loop: 0,
        },
    ),
    (
        "type_check_calls_03b_infer_array_generics.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 1,
            while_loop: 0,
        },
    ),
    (
        "type_check_calls_03c_validate_array_results.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 2,
            while_loop: 0,
        },
    ),
    (
        "type_check_conditions_hir.slang",
        LoopCounts {
            long_guard: 6,
            dynamic_bound: 1,
            while_loop: 0,
        },
    ),
    (
        "type_check_control.slang",
        LoopCounts {
            long_guard: 2,
            dynamic_bound: 1,
            while_loop: 0,
        },
    ),
    (
        "type_check_methods_03_resolve.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 1,
            while_loop: 0,
        },
    ),
    (
        "type_check_modules_01b_count_path_segments.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 1,
            while_loop: 0,
        },
    ),
    (
        "type_check_modules_01b_scatter_path_segments.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 1,
            while_loop: 0,
        },
    ),
    (
        "type_check_modules_09f_validate_import_visible_keys.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 2,
            while_loop: 0,
        },
    ),
    (
        "type_check_modules_10h_consume_value_calls.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 2,
            while_loop: 0,
        },
    ),
    (
        "type_check_modules_10l_consume_value_enum_calls.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 1,
            while_loop: 0,
        },
    ),
    (
        "type_check_modules_10m_bind_match_patterns.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 1,
            while_loop: 0,
        },
    ),
    (
        "type_check_modules_10n_type_match_exprs.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 1,
            while_loop: 0,
        },
    ),
    (
        "type_check_predicates_01_collect.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 21,
            while_loop: 1,
        },
    ),
    (
        "type_check_predicates_02_obligations.slang",
        LoopCounts {
            long_guard: 2,
            dynamic_bound: 5,
            while_loop: 0,
        },
    ),
    (
        "type_check_scope.slang",
        LoopCounts {
            long_guard: 4,
            dynamic_bound: 20,
            while_loop: 0,
        },
    ),
    (
        "type_check_tokens_min.slang",
        LoopCounts {
            long_guard: 3,
            dynamic_bound: 25,
            while_loop: 0,
        },
    ),
    (
        "type_check_type_instances_00b_decl_generic_params.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 2,
            while_loop: 0,
        },
    ),
    (
        "type_check_type_instances_00c_generic_param_use_slots.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 2,
            while_loop: 0,
        },
    ),
    (
        "type_check_type_instances_01f_decl_refs.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 2,
            while_loop: 0,
        },
    ),
    (
        "type_check_type_instances_03_member_results.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 2,
            while_loop: 0,
        },
    ),
    (
        "type_check_type_instances_04_struct_init_fields.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 6,
            while_loop: 0,
        },
    ),
    (
        "type_check_type_instances_05_array_return_refs.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 2,
            while_loop: 0,
        },
    ),
    (
        "type_check_type_instances_05b_array_literal_return_refs.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 1,
            while_loop: 0,
        },
    ),
    (
        "type_check_type_instances_08_validate_aggregate_access.slang",
        LoopCounts {
            long_guard: 2,
            dynamic_bound: 0,
            while_loop: 0,
        },
    ),
    (
        "type_check_visible_02_scatter.slang",
        LoopCounts {
            long_guard: 2,
            dynamic_bound: 6,
            while_loop: 2,
        },
    ),
    (
        "type_check_visible_02_scope_blocks.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 1,
            while_loop: 0,
        },
    ),
    (
        "type_check_visible_03g_build_hir_decl_scope_leaves.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 1,
            while_loop: 0,
        },
    ),
    (
        "type_check_visible_04_hir_names.slang",
        LoopCounts {
            long_guard: 0,
            dynamic_bound: 0,
            while_loop: 1,
        },
    ),
];

#[test]
fn type_checker_shader_loop_budget_does_not_grow() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("shaders/type_checker");
    let mut actual = BTreeMap::new();
    let mut max_static_guard = 0usize;

    for entry in fs::read_dir(&root).expect("read shaders/type_checker") {
        let path = entry.expect("shader entry").path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("slang") {
            continue;
        }

        let (counts, largest) = count_shader_loops(&path, has_token_or_hir_sized_loop_bound);
        max_static_guard = max_static_guard.max(largest);

        if counts != LoopCounts::default() {
            let file = path
                .file_name()
                .and_then(|name| name.to_str())
                .expect("shader filename")
                .to_owned();
            actual.insert(file, counts);
        }
    }

    assert!(
        max_static_guard <= 512,
        "type-check shaders should not add static loop guards above 512 iterations"
    );

    let expected: BTreeMap<_, _> = TYPE_CHECK_LOOP_BUDGET.iter().copied().collect();
    let mut failures = Vec::new();
    for (file, counts) in &actual {
        let Some(budget) = expected.get(file.as_str()) else {
            failures.push(format!(
                "{file} added loop debt {counts:?} without a budget entry"
            ));
            continue;
        };
        if counts.long_guard > budget.long_guard {
            failures.push(format!(
                "{file} long guarded loops grew from {} to {}",
                budget.long_guard, counts.long_guard
            ));
        }
        if counts.dynamic_bound > budget.dynamic_bound {
            failures.push(format!(
                "{file} dynamic-bound loops grew from {} to {}",
                budget.dynamic_bound, counts.dynamic_bound
            ));
        }
        if counts.while_loop > budget.while_loop {
            failures.push(format!(
                "{file} while loops grew from {} to {}",
                budget.while_loop, counts.while_loop
            ));
        }
    }

    assert!(
        failures.is_empty(),
        "type-check shader loop budget grew:\n{}",
        failures.join("\n")
    );
}

#[test]
fn shader_tree_loop_budget_does_not_grow() {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut failures = Vec::new();

    for budget in SHADER_TREE_LOOP_BUDGET {
        let root = manifest_dir.join(budget.path);
        let mut paths = Vec::new();
        collect_shader_paths(&root, budget.recursive, &mut paths);

        let mut actual = LoopCounts::default();
        let mut max_static_guard = 0usize;
        for path in paths {
            let (counts, largest) = count_shader_loops(&path, has_nonconstant_loop_bound);
            actual.long_guard += counts.long_guard;
            actual.dynamic_bound += counts.dynamic_bound;
            actual.while_loop += counts.while_loop;
            max_static_guard = max_static_guard.max(largest);
        }

        if actual.long_guard > budget.counts.long_guard {
            failures.push(format!(
                "{} long guarded loops grew from {} to {}",
                budget.label, budget.counts.long_guard, actual.long_guard
            ));
        }
        if actual.dynamic_bound > budget.counts.dynamic_bound {
            failures.push(format!(
                "{} nonconstant-bound loops grew from {} to {}",
                budget.label, budget.counts.dynamic_bound, actual.dynamic_bound
            ));
        }
        if actual.while_loop > budget.counts.while_loop {
            failures.push(format!(
                "{} while loops grew from {} to {}",
                budget.label, budget.counts.while_loop, actual.while_loop
            ));
        }
        if max_static_guard > budget.max_static_guard {
            failures.push(format!(
                "{} max static loop guard grew from {} to {}",
                budget.label, budget.max_static_guard, max_static_guard
            ));
        }
    }

    assert!(
        failures.is_empty(),
        "shader tree loop budget grew:\n{}",
        failures.join("\n")
    );
}

fn collect_shader_paths(root: &Path, recursive: bool, out: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(root).unwrap_or_else(|err| panic!("read {}: {err}", root.display())) {
        let path = entry.expect("shader entry").path();
        if recursive && path.is_dir() {
            collect_shader_paths(&path, recursive, out);
        } else if path.extension().and_then(|ext| ext.to_str()) == Some("slang") {
            out.push(path);
        }
    }
}

fn count_shader_loops(path: &Path, dynamic_bound: fn(&str) -> bool) -> (LoopCounts, usize) {
    let source = fs::read_to_string(path)
        .unwrap_or_else(|err| panic!("read shader {}: {err}", path.display()));
    let mut counts = LoopCounts::default();
    let mut max_static_guard = 0usize;
    for line in source.lines().map(str::trim) {
        if line.contains("for (") {
            let largest = largest_static_less_than_bound(line);
            max_static_guard = max_static_guard.max(largest);
            if largest >= 256 {
                counts.long_guard += 1;
            }
            if dynamic_bound(line) {
                counts.dynamic_bound += 1;
            }
        }
        if line.contains("while (") {
            counts.while_loop += 1;
        }
    }
    (counts, max_static_guard)
}

fn largest_static_less_than_bound(line: &str) -> usize {
    let mut largest = 0usize;
    for rhs in line.split('<').skip(1) {
        let rhs = rhs.trim_start();
        let mut digits = String::new();
        for ch in rhs.chars() {
            if ch.is_ascii_digit() {
                digits.push(ch);
            } else {
                break;
            }
        }
        if let Ok(value) = digits.parse::<usize>() {
            largest = largest.max(value);
        }
    }
    largest
}

fn has_token_or_hir_sized_loop_bound(line: &str) -> bool {
    line.split('<').skip(1).any(|rhs| {
        let rhs = rhs.trim_start();
        rhs.starts_with("n;")
            || rhs.starts_with("n ")
            || rhs.starts_with("n)")
            || rhs.starts_with("n_active")
            || rhs.starts_with("count")
            || rhs.starts_with("end")
            || rhs.starts_with("close_i")
            || rhs.starts_with("active_")
            || rhs.starts_with("gParams.n_")
    })
}

fn has_nonconstant_loop_bound(line: &str) -> bool {
    line.split('<').skip(1).any(|rhs| {
        let rhs = rhs.trim_start();
        if rhs.is_empty()
            || rhs.starts_with(|ch: char| ch.is_ascii_digit())
            || rhs.starts_with("uint(")
            || rhs.starts_with("int(")
        {
            return false;
        }
        !rhs.chars()
            .take_while(|ch| ch.is_ascii_alphanumeric() || *ch == '_')
            .all(|ch| ch.is_ascii_uppercase() || ch.is_ascii_digit() || ch == '_')
    })
}
