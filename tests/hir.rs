use laniusc::hir::{
    HirAssignOp,
    HirBinaryOp,
    HirExprKind,
    HirItem,
    HirLiteralKind,
    HirStmtKind,
    HirTypeKind,
    parse_source,
};

fn only_fn(src: &str) -> laniusc::hir::HirFn {
    let file = parse_source(src).expect("parse HIR");
    assert_eq!(file.items.len(), 1);
    match file.items.into_iter().next().unwrap() {
        HirItem::Fn(func) => func,
        HirItem::Stmt(_) => panic!("expected function item"),
    }
}

#[test]
fn hir_preserves_names_and_literals_in_function_fixture() {
    let func = only_fn(include_str!("../parser_tests/function.lani"));

    assert!(!func.public);
    assert_eq!(func.name, "main");
    assert!(func.params.is_empty());
    assert_eq!(func.ret.kind, HirTypeKind::Void);
    assert_eq!(func.body.stmts.len(), 2);

    let HirStmtKind::Let {
        name,
        ty,
        value: Some(value),
    } = &func.body.stmts[0].kind
    else {
        panic!("expected let with initializer");
    };
    assert_eq!(name, "x");
    assert!(ty.is_none());

    let HirExprKind::Binary {
        op: HirBinaryOp::Add,
        lhs,
        rhs,
    } = &value.kind
    else {
        panic!("expected add expression, got {:?}", value.kind);
    };
    assert_eq!(
        lhs.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Int,
            text: "1".into()
        }
    );
    assert_eq!(
        rhs.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Int,
            text: "2".into()
        }
    );

    let HirStmtKind::Return(Some(ret)) = &func.body.stmts[1].kind else {
        panic!("expected return value");
    };
    assert_eq!(ret.kind, HirExprKind::Name("x".into()));
}

#[test]
fn hir_lowers_typed_function_control_flow_and_postfix_exprs() {
    let src = r#"
pub fn pick(a: i32, b: [i32; 4]) -> i32 {
    let i: i32 = 0;
    while (i < 4) {
        if (b[i] != 0) {
            return b[i];
        }
        i += 1;
    }
    return a;
}
"#;
    let func = only_fn(src);

    assert!(func.public);
    assert_eq!(func.name, "pick");
    assert_eq!(func.params.len(), 2);
    assert_eq!(func.params[0].name, "a");
    assert_eq!(func.params[0].ty.kind, HirTypeKind::Name("i32".into()));
    assert_eq!(func.params[1].name, "b");
    let HirTypeKind::Array { elem, len } = &func.params[1].ty.kind else {
        panic!("expected array parameter type");
    };
    assert_eq!(elem.kind, HirTypeKind::Name("i32".into()));
    assert_eq!(len, "4");
    assert_eq!(func.ret.kind, HirTypeKind::Name("i32".into()));
    assert_eq!(func.body.stmts.len(), 3);

    let HirStmtKind::While { cond, body } = &func.body.stmts[1].kind else {
        panic!("expected while statement");
    };
    assert!(matches!(
        cond.kind,
        HirExprKind::Binary {
            op: HirBinaryOp::Lt,
            ..
        }
    ));
    assert_eq!(body.stmts.len(), 2);

    let HirStmtKind::Expr(assign) = &body.stmts[1].kind else {
        panic!("expected assignment expression statement");
    };
    assert!(matches!(
        assign.kind,
        HirExprKind::Assign {
            op: HirAssignOp::Add,
            ..
        }
    ));
}

#[test]
fn hir_accepts_parser_fixtures() {
    for (name, src) in [
        ("control", include_str!("../parser_tests/control.lani")),
        ("file", include_str!("../parser_tests/file.lani")),
        ("function", include_str!("../parser_tests/function.lani")),
    ] {
        let file = parse_source(src).unwrap_or_else(|err| panic!("{name} HIR parse failed: {err}"));
        assert!(!file.items.is_empty(), "{name} should produce HIR items");
    }
}
