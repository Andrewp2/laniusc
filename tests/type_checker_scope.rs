mod common;

use laniusc::compiler::CompileError;

fn assert_unresolved_identifier_diagnostic(src: &str) {
    let err = common::type_check_source_with_timeout(src)
        .expect_err("source should fail GPU type checking");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0005");
            assert!(
                diagnostic.primary_label.is_some(),
                "unresolved identifier diagnostic should point at the rejected token"
            );
            let message = diagnostic.render();
            assert!(message.contains("error[LNC0005]"));
            assert!(message.contains("not found in this scope"));
        }
        other => panic!("expected unresolved identifier diagnostic, got {other:?}"),
    }
}

fn assert_gpu_compile_ok(src: &str) {
    common::type_check_source_with_timeout(src).expect("source should pass GPU type checking");
}

#[test]
fn type_checker_unresolved_identifier_diagnostic_uses_source_span_and_path() {
    let source = "fn main() {\n    print(later);\n    let later: i32 = 1;\n    return 0;\n}\n";
    let artifact = common::TempArtifact::new("laniusc_typecheck_diag", "unresolved", Some("lani"));
    artifact.write_str(source);

    let err = common::type_check_path_with_timeout(artifact.path())
        .expect_err("use before declaration should fail GPU type checking");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0005");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("unresolved identifier diagnostic should have a primary label");
            assert_eq!(label.path.as_path(), artifact.path());
            assert_eq!(label.line, 2);
            assert_eq!(label.column, 11);
            assert_eq!(label.length, "later".len());
            assert_eq!(label.source_line, Some("    print(later);".to_string()));
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0005]"));
            assert!(rendered.contains(&artifact.path().display().to_string()));
            assert!(rendered.contains("    print(later);"));
            assert!(rendered.contains("^".repeat("later".len()).as_str()));
        }
        other => panic!("expected unresolved identifier diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_assignment_mismatch_diagnostic_uses_source_span_and_path() {
    let source = "fn main() {\n    let value: i32 = false;\n    return 0;\n}\n";
    let artifact =
        common::TempArtifact::new("laniusc_typecheck_diag", "assign_mismatch", Some("lani"));
    artifact.write_str(source);

    let err = common::type_check_path_with_timeout(artifact.path())
        .expect_err("assignment type mismatch should fail GPU type checking");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0006");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("assignment mismatch diagnostic should have a primary label");
            assert_eq!(label.path.as_path(), artifact.path());
            assert_eq!(label.line, 2);
            assert_eq!(
                label.source_line,
                Some("    let value: i32 = false;".to_string())
            );
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0006]"));
            assert!(rendered.contains(&artifact.path().display().to_string()));
            assert!(rendered.contains("    let value: i32 = false;"));
            assert!(rendered.contains("expected a different type here"));
            assert!(!rendered.contains("GPU type check rejected"));
        }
        other => panic!("expected assignment mismatch diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_unknown_type_diagnostic_uses_source_span_and_path() {
    let source = "fn keep<T>(value: T) -> T where T: MissingTrait<T> {\n    return value;\n}\nfn main() {\n    let value: i32 = keep(1);\n    return value;\n}\n";
    let artifact =
        common::TempArtifact::new("laniusc_typecheck_diag", "unknown_type", Some("lani"));
    artifact.write_str(source);

    let err = common::type_check_path_with_timeout(artifact.path())
        .expect_err("unknown type should fail");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0007");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("unknown type diagnostic should have a primary label");
            assert_eq!(label.path.as_path(), artifact.path());
            assert_eq!(label.line, 1);
            assert_eq!(
                label.source_line,
                Some("fn keep<T>(value: T) -> T where T: MissingTrait<T> {".to_string())
            );
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0007]: unknown type"));
            assert!(rendered.contains(&artifact.path().display().to_string()));
            assert!(rendered.contains("type not found"));
            assert!(!rendered.contains("GPU type check rejected"));
        }
        other => panic!("expected unknown-type diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_rejects_let_initializer_self_reference() {
    let src = r#"
fn main() {
    let x = x;
    return 0;
}
"#;

    assert_unresolved_identifier_diagnostic(src);
}

#[test]
fn type_checker_rejects_typed_array_let_initializer_self_reference() {
    let src = r#"
fn main() {
    let values: [i32; 2] = values;
    return 0;
}
"#;

    assert_unresolved_identifier_diagnostic(src);
}

#[test]
fn type_checker_rejects_use_before_declaration() {
    let src = r#"
fn main() {
    print(later);
    let later: i32 = 1;
    return 0;
}
"#;

    assert_unresolved_identifier_diagnostic(src);
}

#[test]
fn type_checker_rejects_inner_block_declaration_leak() {
    let src = r#"
fn main() {
    if (1 == 1) {
        let hidden: i32 = 1;
        print(hidden);
    }
    print(hidden);
    return 0;
}
"#;

    assert_unresolved_identifier_diagnostic(src);
}

#[test]
fn type_checker_keeps_shadowing_block_local() {
    let src = r#"
fn main() {
    let x: i32 = 1;
    if (1 == 1) {
        print(x);
        let x: bool = 1 < 2;
        if (x) {
            print(2);
        }
    }
    print(x);
    return 0;
}
"#;

    assert_gpu_compile_ok(src);
}

#[test]
fn type_checker_keeps_parameters_visible_only_in_their_function() {
    let accepts = r#"
fn echo(value: i32) -> i32 {
    return value;
}

fn main() {
    print(echo(3));
    return 0;
}
"#;

    let rejects = r#"
fn helper(hidden: i32) -> i32 {
    let local: i32 = hidden;
    return local;
}

fn main() {
    print(hidden);
    return 0;
}
"#;

    assert_gpu_compile_ok(accepts);
    assert_unresolved_identifier_diagnostic(rejects);
}
