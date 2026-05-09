use std::{collections::BTreeMap, fs, path::Path};

use laniusc::{
    hir::{
        HirAssignOp,
        HirBinaryOp,
        HirBlock,
        HirConst,
        HirError,
        HirExpr,
        HirExprKind,
        HirFile,
        HirFn,
        HirImportPath,
        HirItem,
        HirLiteralKind,
        HirPattern,
        HirPatternKind,
        HirStmt,
        HirStmtKind,
        HirType,
        HirTypeKind,
        Span,
        parse_source,
    },
    lexer::cpu::{CpuToken, lex_on_cpu},
    parser::cpu::{Ast, parse_from_token_kinds},
};

fn only_fn(src: &str) -> HirFn {
    let file = parse_source(src).expect("parse HIR");
    assert_eq!(file.items.len(), 1);
    match file.items.into_iter().next().unwrap() {
        HirItem::Fn(func) => func,
        HirItem::Import(_) => panic!("expected function item"),
        HirItem::Module(_) => panic!("expected function item"),
        HirItem::Const(_) => panic!("expected function item"),
        HirItem::Enum(_) => panic!("expected function item"),
        HirItem::Struct(_) => panic!("expected function item"),
        HirItem::Stmt(_) => panic!("expected function item"),
    }
}

fn fixture_sources(dir: &str) -> Vec<(String, String)> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join(dir);
    let mut paths = fs::read_dir(&root)
        .unwrap_or_else(|err| panic!("read fixture dir {}: {err}", root.display()))
        .map(|entry| {
            entry
                .unwrap_or_else(|err| panic!("read fixture entry in {}: {err}", root.display()))
                .path()
        })
        .filter(|path| path.extension().and_then(|ext| ext.to_str()) == Some("lani"))
        .collect::<Vec<_>>();
    paths.sort();

    paths
        .into_iter()
        .map(|path| {
            let file_name = path
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("<non-utf8>");
            let name = format!("{dir}/{file_name}");
            let src = fs::read_to_string(&path)
                .unwrap_or_else(|err| panic!("{name}: read {}: {err}", path.display()));
            (name, src)
        })
        .collect()
}

fn all_frontend_fixtures() -> Vec<(String, String)> {
    let mut fixtures = fixture_sources("parser_tests");
    fixtures.extend(fixture_sources("sample_programs"));
    fixtures
}

fn parse_cpu_ast(name: &str, src: &str) -> (Vec<CpuToken>, Ast) {
    let tokens = lex_on_cpu(src).unwrap_or_else(|err| panic!("{name}: CPU lex failed: {err}"));
    let kinds = tokens.iter().map(|token| token.kind).collect::<Vec<_>>();
    let ast = parse_from_token_kinds(&kinds)
        .unwrap_or_else(|err| panic!("{name}: CPU parser rejected fixture: {err}"));
    (tokens, ast)
}

fn ast_tag_counts(ast: &Ast) -> BTreeMap<&'static str, usize> {
    let mut counts = BTreeMap::new();
    for node in &ast.nodes {
        *counts.entry(node.tag).or_insert(0) += 1;
    }
    counts
}

fn ast_children<'a>(ast: &'a Ast, id: u32, expected_tag: &str) -> &'a [u32] {
    let node = &ast.nodes[id as usize];
    assert_eq!(node.tag, expected_tag, "AST node {id} tag");
    &node.children
}

fn assert_span_in_source(name: &str, label: &str, span: Span, src: &str) {
    assert!(
        span.start <= src.len(),
        "{name}: {label} span starts past source end: {:?}, source len {}",
        span,
        src.len()
    );
    assert!(
        span.end() <= src.len(),
        "{name}: {label} span ends past source end: {:?}, source len {}",
        span,
        src.len()
    );
    assert!(
        src.is_char_boundary(span.start) && src.is_char_boundary(span.end()),
        "{name}: {label} span is not on UTF-8 boundaries: {:?}",
        span
    );
}

fn assert_span_contains(name: &str, label: &str, parent: Span, child: Span) {
    assert!(
        parent.start <= child.start && child.end() <= parent.end(),
        "{name}: {label} child span {:?} is outside parent span {:?}",
        child,
        parent
    );
}

fn assert_hir_file_spans(name: &str, src: &str, tokens: &[CpuToken], file: &HirFile) {
    assert_span_in_source(name, "file", file.span, src);
    if let (Some(first), Some(last)) = (tokens.first(), tokens.last()) {
        assert_eq!(file.span.start, first.start, "{name}: file span start");
        assert_eq!(
            file.span.end(),
            last.start + last.len,
            "{name}: file span end"
        );
    } else {
        assert_eq!(file.span.len, 0, "{name}: empty token stream span len");
    }

    for (i, item) in file.items.iter().enumerate() {
        let span = match item {
            HirItem::Import(import) => {
                assert_span_in_source(name, "import", import.span, src);
                if let HirImportPath::Module(path) = &import.path {
                    assert_span_in_source(name, "import path", path.span, src);
                    assert_span_contains(name, "import path", import.span, path.span);
                }
                import.span
            }
            HirItem::Module(module) => {
                assert_span_in_source(name, "module", module.span, src);
                assert_span_in_source(name, "module path", module.path.span, src);
                assert_span_contains(name, "module path", module.span, module.path.span);
                module.span
            }
            HirItem::Fn(func) => {
                assert_fn_spans(name, src, func);
                func.span
            }
            HirItem::Const(konst) => {
                assert_const_spans(name, src, konst);
                konst.span
            }
            HirItem::Enum(enm) => {
                assert_enum_spans(name, src, enm);
                enm.span
            }
            HirItem::Struct(strukt) => {
                assert_struct_spans(name, src, strukt);
                strukt.span
            }
            HirItem::Stmt(stmt) => {
                assert_stmt_spans(name, src, stmt);
                stmt.span
            }
        };
        assert_span_contains(name, &format!("file item {i}"), file.span, span);
    }
}

fn assert_fn_spans(name: &str, src: &str, func: &HirFn) {
    assert_span_in_source(name, "function", func.span, src);
    for (i, param) in func.const_params.iter().enumerate() {
        assert_span_in_source(name, &format!("function const param {i}"), param.span, src);
        assert_span_contains(
            name,
            &format!("function const param {i}"),
            func.span,
            param.span,
        );
        assert_type_spans(name, src, &param.ty);
        assert_span_contains(
            name,
            &format!("function const param {i} type"),
            param.span,
            param.ty.span,
        );
    }
    for (i, param) in func.params.iter().enumerate() {
        assert_span_in_source(name, &format!("param {i}"), param.span, src);
        assert_span_contains(name, &format!("function param {i}"), func.span, param.span);
        assert_type_spans(name, src, &param.ty);
        assert_span_contains(name, &format!("param {i} type"), param.span, param.ty.span);
    }
    assert_type_spans(name, src, &func.ret);
    assert_span_contains(name, "function return type", func.span, func.ret.span);
    assert_block_spans(name, src, &func.body);
    assert_span_contains(name, "function body", func.span, func.body.span);
}

fn assert_const_spans(name: &str, src: &str, konst: &HirConst) {
    assert_span_in_source(name, "constant", konst.span, src);
    assert_type_spans(name, src, &konst.ty);
    assert_span_contains(name, "constant type", konst.span, konst.ty.span);
    assert_expr_spans(name, src, &konst.value);
    assert_span_contains(name, "constant value", konst.span, konst.value.span);
}

fn assert_enum_spans(name: &str, src: &str, enm: &laniusc::hir::HirEnum) {
    assert_span_in_source(name, "enum", enm.span, src);
    for (i, param) in enm.const_params.iter().enumerate() {
        assert_span_in_source(name, &format!("enum const param {i}"), param.span, src);
        assert_span_contains(name, &format!("enum const param {i}"), enm.span, param.span);
        assert_type_spans(name, src, &param.ty);
        assert_span_contains(
            name,
            &format!("enum const param {i} type"),
            param.span,
            param.ty.span,
        );
    }
    for (variant_i, variant) in enm.variants.iter().enumerate() {
        assert_span_in_source(
            name,
            &format!("enum variant {variant_i}"),
            variant.span,
            src,
        );
        assert_span_contains(
            name,
            &format!("enum variant {variant_i}"),
            enm.span,
            variant.span,
        );
        for (field_i, field) in variant.fields.iter().enumerate() {
            assert_type_spans(name, src, field);
            assert_span_contains(
                name,
                &format!("enum variant {variant_i} field {field_i}"),
                variant.span,
                field.span,
            );
        }
    }
}

fn assert_struct_spans(name: &str, src: &str, strukt: &laniusc::hir::HirStruct) {
    assert_span_in_source(name, "struct", strukt.span, src);
    for (i, param) in strukt.const_params.iter().enumerate() {
        assert_span_in_source(name, &format!("struct const param {i}"), param.span, src);
        assert_span_contains(
            name,
            &format!("struct const param {i}"),
            strukt.span,
            param.span,
        );
        assert_type_spans(name, src, &param.ty);
        assert_span_contains(
            name,
            &format!("struct const param {i} type"),
            param.span,
            param.ty.span,
        );
    }
    for (field_i, field) in strukt.fields.iter().enumerate() {
        assert_span_in_source(name, &format!("struct field {field_i}"), field.span, src);
        assert_span_contains(
            name,
            &format!("struct field {field_i}"),
            strukt.span,
            field.span,
        );
        assert_type_spans(name, src, &field.ty);
        assert_span_contains(
            name,
            &format!("struct field {field_i} type"),
            field.span,
            field.ty.span,
        );
    }
}

fn assert_type_spans(name: &str, src: &str, ty: &HirType) {
    assert_span_in_source(name, "type", ty.span, src);
    match &ty.kind {
        HirTypeKind::Array { elem, .. } => {
            assert_type_spans(name, src, elem);
            assert_span_contains(name, "array element type", ty.span, elem.span);
        }
        HirTypeKind::Ref { inner } => {
            assert_type_spans(name, src, inner);
            assert_span_contains(name, "reference inner type", ty.span, inner.span);
        }
        HirTypeKind::Slice { elem } => {
            assert_type_spans(name, src, elem);
            assert_span_contains(name, "slice element type", ty.span, elem.span);
        }
        HirTypeKind::Generic { args, .. } => {
            for (i, arg) in args.iter().enumerate() {
                assert_type_spans(name, src, arg);
                assert_span_contains(name, &format!("generic type arg {i}"), ty.span, arg.span);
            }
        }
        HirTypeKind::Void | HirTypeKind::Name(_) => {}
    }
}

fn assert_block_spans(name: &str, src: &str, block: &HirBlock) {
    assert_span_in_source(name, "block", block.span, src);
    for (i, stmt) in block.stmts.iter().enumerate() {
        assert_stmt_spans(name, src, stmt);
        assert_span_contains(name, &format!("block stmt {i}"), block.span, stmt.span);
    }
}

fn assert_stmt_spans(name: &str, src: &str, stmt: &HirStmt) {
    assert_span_in_source(name, "statement", stmt.span, src);
    match &stmt.kind {
        HirStmtKind::Let { ty, value, .. } => {
            if let Some(ty) = ty {
                assert_type_spans(name, src, ty);
                assert_span_contains(name, "let type", stmt.span, ty.span);
            }
            if let Some(value) = value {
                assert_expr_spans(name, src, value);
                assert_span_contains(name, "let value", stmt.span, value.span);
            }
        }
        HirStmtKind::Return(value) => {
            if let Some(value) = value {
                assert_expr_spans(name, src, value);
                assert_span_contains(name, "return value", stmt.span, value.span);
            }
        }
        HirStmtKind::If {
            cond,
            then_block,
            else_block,
        } => {
            assert_expr_spans(name, src, cond);
            assert_span_contains(name, "if condition", stmt.span, cond.span);
            assert_block_spans(name, src, then_block);
            assert_span_contains(name, "then block", stmt.span, then_block.span);
            if let Some(else_block) = else_block {
                assert_block_spans(name, src, else_block);
                assert_span_contains(name, "else block", stmt.span, else_block.span);
            }
        }
        HirStmtKind::While { cond, body } => {
            assert_expr_spans(name, src, cond);
            assert_span_contains(name, "while condition", stmt.span, cond.span);
            assert_block_spans(name, src, body);
            assert_span_contains(name, "while body", stmt.span, body.span);
        }
        HirStmtKind::Block(block) => {
            assert_block_spans(name, src, block);
            assert_span_contains(name, "nested block", stmt.span, block.span);
        }
        HirStmtKind::Expr(expr) => {
            assert_expr_spans(name, src, expr);
            assert_span_contains(name, "expression statement", stmt.span, expr.span);
        }
        HirStmtKind::Break | HirStmtKind::Continue => {}
    }
}

fn assert_expr_spans(name: &str, src: &str, expr: &HirExpr) {
    assert_span_in_source(name, "expression", expr.span, src);
    match &expr.kind {
        HirExprKind::Array(elems) => {
            for (i, elem) in elems.iter().enumerate() {
                assert_expr_spans(name, src, elem);
                assert_span_contains(name, &format!("array element {i}"), expr.span, elem.span);
            }
        }
        HirExprKind::StructLiteral { fields, .. } => {
            for (i, field) in fields.iter().enumerate() {
                assert_span_in_source(name, &format!("struct literal field {i}"), field.span, src);
                assert_span_contains(
                    name,
                    &format!("struct literal field {i}"),
                    expr.span,
                    field.span,
                );
                assert_expr_spans(name, src, &field.value);
                assert_span_contains(
                    name,
                    &format!("struct literal field {i} value"),
                    field.span,
                    field.value.span,
                );
            }
        }
        HirExprKind::Match { expr: inner, arms } => {
            assert_expr_spans(name, src, inner);
            assert_span_contains(name, "match scrutinee", expr.span, inner.span);
            for (i, arm) in arms.iter().enumerate() {
                assert_span_in_source(name, &format!("match arm {i}"), arm.span, src);
                assert_span_contains(name, &format!("match arm {i}"), expr.span, arm.span);
                assert_pattern_spans(name, src, &arm.pattern);
                assert_span_contains(
                    name,
                    &format!("match arm {i} pattern"),
                    arm.span,
                    arm.pattern.span,
                );
                assert_expr_spans(name, src, &arm.value);
                assert_span_contains(
                    name,
                    &format!("match arm {i} value"),
                    arm.span,
                    arm.value.span,
                );
            }
        }
        HirExprKind::Call { callee, args } => {
            assert_expr_spans(name, src, callee);
            assert_span_contains(name, "call callee", expr.span, callee.span);
            for (i, arg) in args.iter().enumerate() {
                assert_expr_spans(name, src, arg);
                assert_span_contains(name, &format!("call arg {i}"), expr.span, arg.span);
            }
        }
        HirExprKind::Index { base, index } => {
            assert_expr_spans(name, src, base);
            assert_expr_spans(name, src, index);
            assert_span_contains(name, "index base", expr.span, base.span);
            assert_span_contains(name, "index expr", expr.span, index.span);
        }
        HirExprKind::Member { base, .. } => {
            assert_expr_spans(name, src, base);
            assert_span_contains(name, "member base", expr.span, base.span);
        }
        HirExprKind::Unary { expr: inner, .. } => {
            assert_expr_spans(name, src, inner);
            assert_span_contains(name, "unary expr", expr.span, inner.span);
        }
        HirExprKind::Binary { lhs, rhs, .. } => {
            assert_expr_spans(name, src, lhs);
            assert_expr_spans(name, src, rhs);
            assert_span_contains(name, "binary lhs", expr.span, lhs.span);
            assert_span_contains(name, "binary rhs", expr.span, rhs.span);
        }
        HirExprKind::Assign { target, value, .. } => {
            assert_expr_spans(name, src, target);
            assert_expr_spans(name, src, value);
            assert_span_contains(name, "assign target", expr.span, target.span);
            assert_span_contains(name, "assign value", expr.span, value.span);
        }
        HirExprKind::Name(_) | HirExprKind::Literal { .. } => {}
    }
}

fn assert_pattern_spans(name: &str, src: &str, pattern: &HirPattern) {
    assert_span_in_source(name, "pattern", pattern.span, src);
    if let HirPatternKind::Tuple { fields, .. } = &pattern.kind {
        for (i, field) in fields.iter().enumerate() {
            assert_pattern_spans(name, src, field);
            assert_span_contains(
                name,
                &format!("tuple pattern field {i}"),
                pattern.span,
                field.span,
            );
        }
    }
}

fn span_text<'a>(src: &'a str, span: Span) -> &'a str {
    &src[span.start..span.end()]
}

fn assert_span_text(src: &str, span: Span, expected: &str) {
    assert_eq!(span_text(src, span), expected);
}

fn let_value<'a>(stmt: &'a HirStmt, expected_name: &str) -> &'a HirExpr {
    let HirStmtKind::Let {
        name,
        value: Some(value),
        ..
    } = &stmt.kind
    else {
        panic!("expected initialized let statement");
    };
    assert_eq!(name, expected_name);
    value
}

#[test]
fn cpu_parser_and_hir_preserve_nested_if_else_structure_and_block_spans() {
    let src = "fn main() { if (outer) { if (inner) { return 1; } else { return 2; } } else { return 3; } }";
    let (_, ast) = parse_cpu_ast("nested if/else", src);
    let file_children = ast_children(&ast, ast.root, "file");
    assert_eq!(file_children.len(), 1);
    let fn_children = ast_children(&ast, file_children[0], "fn");
    let body_children = ast_children(&ast, fn_children[4], "block");
    assert_eq!(body_children.len(), 1);
    let outer_if_children = ast_children(&ast, body_children[0], "stmt_if");
    assert_eq!(outer_if_children.len(), 3);
    let outer_then_children = ast_children(&ast, outer_if_children[1], "block");
    assert_eq!(outer_then_children.len(), 1);
    let outer_else_children = ast_children(&ast, outer_if_children[2], "block");
    assert_eq!(outer_else_children.len(), 1);
    ast_children(&ast, outer_else_children[0], "stmt_return");
    let inner_if_children = ast_children(&ast, outer_then_children[0], "stmt_if");
    assert_eq!(inner_if_children.len(), 3);
    let inner_then_children = ast_children(&ast, inner_if_children[1], "block");
    assert_eq!(inner_then_children.len(), 1);
    ast_children(&ast, inner_then_children[0], "stmt_return");
    let inner_else_children = ast_children(&ast, inner_if_children[2], "block");
    assert_eq!(inner_else_children.len(), 1);
    ast_children(&ast, inner_else_children[0], "stmt_return");

    let func = only_fn(src);
    assert_eq!(func.body.stmts.len(), 1);
    let HirStmtKind::If {
        cond: outer_cond,
        then_block: outer_then,
        else_block: Some(outer_else),
    } = &func.body.stmts[0].kind
    else {
        panic!("expected outer if/else");
    };
    assert_eq!(outer_cond.kind, HirExprKind::Name("outer".into()));
    assert_span_text(
        src,
        func.body.stmts[0].span,
        "if (outer) { if (inner) { return 1; } else { return 2; } } else { return 3; }",
    );
    assert_span_text(
        src,
        outer_then.span,
        "{ if (inner) { return 1; } else { return 2; } }",
    );
    assert_span_text(src, outer_else.span, "{ return 3; }");
    assert_eq!(outer_then.stmts.len(), 1);
    assert_eq!(outer_else.stmts.len(), 1);

    let HirStmtKind::If {
        cond: inner_cond,
        then_block: inner_then,
        else_block: Some(inner_else),
    } = &outer_then.stmts[0].kind
    else {
        panic!("expected nested if/else");
    };
    assert_eq!(inner_cond.kind, HirExprKind::Name("inner".into()));
    assert_span_text(
        src,
        outer_then.stmts[0].span,
        "if (inner) { return 1; } else { return 2; }",
    );
    assert_span_text(src, inner_then.span, "{ return 1; }");
    assert_span_text(src, inner_else.span, "{ return 2; }");
}

#[test]
fn cpu_parser_and_hir_reject_else_if_without_else_block() {
    let src = "fn main() { if (a) { return 1; } else if (b) { return 2; } }";
    let tokens = lex_on_cpu(src).expect("lex else-if fixture");
    let kinds = tokens.iter().map(|token| token.kind).collect::<Vec<_>>();
    let cpu_err = parse_from_token_kinds(&kinds).expect_err("CPU parser should reject else-if");
    assert_eq!(cpu_err.expected, "LBrace");

    let hir_err = parse_source(src).expect_err("HIR parser should reject else-if");
    let HirError::Parse { expected, .. } = hir_err else {
        panic!("expected HIR parse error");
    };
    assert_eq!(expected, "LBrace");
}

#[test]
fn cpu_parser_and_hir_preserve_mixed_top_level_item_order_and_spans() {
    let src =
        "let before = 1;\nfn main() { return before; }\nprint(before);\nfn helper() { return 0; }";
    let (_, ast) = parse_cpu_ast("mixed top-level items", src);
    let file_children = ast_children(&ast, ast.root, "file");
    assert_eq!(file_children.len(), 4);
    ast_children(&ast, file_children[0], "stmt_let");
    ast_children(&ast, file_children[1], "fn");
    ast_children(&ast, file_children[2], "stmt_expr");
    ast_children(&ast, file_children[3], "fn");

    let file = parse_source(src).expect("parse mixed top-level HIR");
    assert_eq!(file.items.len(), 4);
    assert_span_text(src, file.span, src);

    let HirItem::Stmt(first) = &file.items[0] else {
        panic!("expected first item to be a statement");
    };
    assert_span_text(src, first.span, "let before = 1;");
    let before = let_value(first, "before");
    assert_eq!(
        before.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Int,
            text: "1".into()
        }
    );

    let HirItem::Fn(main) = &file.items[1] else {
        panic!("expected second item to be main function");
    };
    assert_eq!(main.name, "main");
    assert_span_text(src, main.span, "fn main() { return before; }");

    let HirItem::Stmt(third) = &file.items[2] else {
        panic!("expected third item to be a statement");
    };
    assert_span_text(src, third.span, "print(before);");
    let HirStmtKind::Expr(call) = &third.kind else {
        panic!("expected top-level call expression");
    };
    let HirExprKind::Call { callee, args } = &call.kind else {
        panic!("expected call expression");
    };
    assert_eq!(callee.kind, HirExprKind::Name("print".into()));
    assert_eq!(args.len(), 1);
    assert_eq!(args[0].kind, HirExprKind::Name("before".into()));

    let HirItem::Fn(helper) = &file.items[3] else {
        panic!("expected fourth item to be helper function");
    };
    assert_eq!(helper.name, "helper");
    assert_span_text(src, helper.span, "fn helper() { return 0; }");
}

#[test]
fn cpu_parser_and_hir_preserve_module_and_import_items() {
    let src = "module core::numbers;\nimport core::i32;\nimport \"stdlib/bool.lani\";\nfn main() { return; }";
    let (_, ast) = parse_cpu_ast("module/import items", src);
    let file_children = ast_children(&ast, ast.root, "file");
    assert_eq!(file_children.len(), 4);
    ast_children(&ast, file_children[0], "module");
    ast_children(&ast, file_children[1], "import_path");
    ast_children(&ast, file_children[2], "import_string");
    ast_children(&ast, file_children[3], "fn");

    let file = parse_source(src).expect("parse module/import HIR");
    assert_eq!(file.items.len(), 4);

    let HirItem::Module(module) = &file.items[0] else {
        panic!("expected first item to be module");
    };
    assert_eq!(module.path.segments, vec!["core", "numbers"]);
    assert_span_text(src, module.span, "module core::numbers;");
    assert_span_text(src, module.path.span, "core::numbers");

    let HirItem::Import(import) = &file.items[1] else {
        panic!("expected second item to be module import");
    };
    let HirImportPath::Module(path) = &import.path else {
        panic!("expected module import path");
    };
    assert_eq!(path.segments, vec!["core", "i32"]);
    assert_span_text(src, import.span, "import core::i32;");
    assert_span_text(src, path.span, "core::i32");

    let HirItem::Import(import) = &file.items[2] else {
        panic!("expected third item to be string import");
    };
    assert_eq!(
        import.path,
        HirImportPath::String("stdlib/bool.lani".into())
    );
    assert_span_text(src, import.span, "import \"stdlib/bool.lani\";");
}

#[test]
fn hir_preserves_namespaced_paths_in_types_exprs_and_patterns() {
    let file = parse_source(
        "fn main(value: core::option::Option<i32>) { let out = core::math::add_one(1); let p = core::point::Point { x: out }; let y = match (out) { core::option::Some(inner) -> inner, _ -> out }; return; }",
    )
    .expect("parse namespaced paths");
    let HirItem::Fn(func) = &file.items[0] else {
        panic!("expected function item");
    };

    let HirTypeKind::Generic { name, args } = &func.params[0].ty.kind else {
        panic!("expected namespaced generic type");
    };
    assert_eq!(name, "core::option::Option");
    assert_eq!(args.len(), 1);
    assert_eq!(args[0].kind, HirTypeKind::Name("i32".into()));

    let call = let_value(&func.body.stmts[0], "out");
    let HirExprKind::Call { callee, args } = &call.kind else {
        panic!("expected namespaced call");
    };
    assert_eq!(callee.kind, HirExprKind::Name("core::math::add_one".into()));
    assert_eq!(args.len(), 1);

    let literal = let_value(&func.body.stmts[1], "p");
    let HirExprKind::StructLiteral { name, fields } = &literal.kind else {
        panic!("expected namespaced struct literal");
    };
    assert_eq!(name, "core::point::Point");
    assert_eq!(fields.len(), 1);

    let matched = let_value(&func.body.stmts[2], "y");
    let HirExprKind::Match { arms, .. } = &matched.kind else {
        panic!("expected match expression");
    };
    let HirPatternKind::Tuple { name, fields } = &arms[0].pattern.kind else {
        panic!("expected namespaced tuple pattern");
    };
    assert_eq!(name, "core::option::Some");
    assert_eq!(fields.len(), 1);
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
fn hir_preserves_bool_literals() {
    let func =
        only_fn("fn main() { let flag: bool = false; if (true) { return 1; } else { return 0; } }");

    let HirStmtKind::Let {
        value: Some(value), ..
    } = &func.body.stmts[0].kind
    else {
        panic!("expected let with initializer");
    };
    assert_eq!(
        value.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Bool,
            text: "false".to_string()
        }
    );

    let HirStmtKind::If { cond, .. } = &func.body.stmts[1].kind else {
        panic!("expected if statement");
    };
    assert_eq!(
        cond.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Bool,
            text: "true".to_string()
        }
    );
}

#[test]
fn hir_preserves_top_level_constants() {
    let file = parse_source(
        "const LIMIT: i32 = 7; pub const PUBLIC_LIMIT: i32 = 9; const ENABLED: bool = true; fn main() { return LIMIT; }",
    )
    .expect("parse constants");
    assert_eq!(file.items.len(), 4);

    let HirItem::Const(limit) = &file.items[0] else {
        panic!("expected first item to be const");
    };
    assert!(!limit.public);
    assert_eq!(limit.name, "LIMIT");
    assert_eq!(limit.ty.kind, HirTypeKind::Name("i32".into()));
    assert_eq!(
        limit.value.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Int,
            text: "7".into()
        }
    );

    let HirItem::Const(public_limit) = &file.items[1] else {
        panic!("expected second item to be public const");
    };
    assert!(public_limit.public);
    assert_eq!(public_limit.name, "PUBLIC_LIMIT");
    assert_eq!(public_limit.ty.kind, HirTypeKind::Name("i32".into()));
    assert_eq!(
        public_limit.value.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Int,
            text: "9".into()
        }
    );

    let HirItem::Const(enabled) = &file.items[2] else {
        panic!("expected second item to be const");
    };
    assert!(!enabled.public);
    assert_eq!(enabled.name, "ENABLED");
    assert_eq!(enabled.ty.kind, HirTypeKind::Name("bool".into()));
    assert_eq!(
        enabled.value.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Bool,
            text: "true".into()
        }
    );
}

#[test]
fn hir_preserves_enum_declarations() {
    let file = parse_source(
        "pub enum ResultI32 { Ok(i32), Err([i32; 4]), Empty } enum Ordering { Less, Equal, Greater }",
    )
    .expect("parse enum declarations");
    assert_eq!(file.items.len(), 2);

    let HirItem::Enum(result) = &file.items[0] else {
        panic!("expected first item to be enum");
    };
    assert!(result.public);
    assert_eq!(result.name, "ResultI32");
    assert!(result.type_params.is_empty());
    assert_eq!(result.variants.len(), 3);
    assert_eq!(result.variants[0].name, "Ok");
    assert_eq!(result.variants[0].fields.len(), 1);
    assert_eq!(
        result.variants[0].fields[0].kind,
        HirTypeKind::Name("i32".into())
    );
    assert_eq!(result.variants[1].name, "Err");
    assert_eq!(result.variants[1].fields.len(), 1);
    assert!(matches!(
        result.variants[1].fields[0].kind,
        HirTypeKind::Array { .. }
    ));
    assert_eq!(result.variants[2].name, "Empty");
    assert!(result.variants[2].fields.is_empty());

    let HirItem::Enum(ordering) = &file.items[1] else {
        panic!("expected second item to be enum");
    };
    assert!(!ordering.public);
    assert_eq!(ordering.name, "Ordering");
    assert_eq!(
        ordering
            .variants
            .iter()
            .map(|variant| variant.name.as_str())
            .collect::<Vec<_>>(),
        vec!["Less", "Equal", "Greater"]
    );
}

#[test]
fn hir_preserves_generic_enum_declarations_and_type_uses() {
    let file = parse_source(
        "pub enum Option<T> { Some(T), None } enum Result<T, E> { Ok(T), Err(E) } fn unwrap_or(value: Option<i32>, fallback: i32) -> i32 { return fallback; }",
    )
    .expect("parse generic enum declarations");
    assert_eq!(file.items.len(), 3);

    let HirItem::Enum(option) = &file.items[0] else {
        panic!("expected first item to be enum");
    };
    assert_eq!(option.name, "Option");
    assert_eq!(option.type_params, vec!["T"]);
    assert_eq!(option.variants[0].name, "Some");
    assert_eq!(
        option.variants[0].fields[0].kind,
        HirTypeKind::Name("T".into())
    );

    let HirItem::Enum(result) = &file.items[1] else {
        panic!("expected second item to be enum");
    };
    assert_eq!(result.name, "Result");
    assert_eq!(result.type_params, vec!["T", "E"]);
    assert_eq!(
        result.variants[0].fields[0].kind,
        HirTypeKind::Name("T".into())
    );
    assert_eq!(
        result.variants[1].fields[0].kind,
        HirTypeKind::Name("E".into())
    );

    let HirItem::Fn(func) = &file.items[2] else {
        panic!("expected third item to be function");
    };
    let HirTypeKind::Generic { name, args } = &func.params[0].ty.kind else {
        panic!("expected generic parameter type");
    };
    assert_eq!(name, "Option");
    assert_eq!(args.len(), 1);
    assert_eq!(args[0].kind, HirTypeKind::Name("i32".into()));
}

#[test]
fn hir_preserves_match_expressions_and_patterns() {
    let func = only_fn(
        "fn choose(value: i32, fallback: i32) -> i32 { let out = match (value) { 0 -> fallback, Some(inner) -> inner, _ -> value }; return out; }",
    );
    assert_eq!(func.body.stmts.len(), 2);

    let out = let_value(&func.body.stmts[0], "out");
    let HirExprKind::Match { expr, arms } = &out.kind else {
        panic!("expected match expression");
    };
    assert_eq!(expr.kind, HirExprKind::Name("value".into()));
    assert_eq!(arms.len(), 3);
    assert_eq!(
        arms[0].pattern.kind,
        HirPatternKind::Literal {
            kind: HirLiteralKind::Int,
            text: "0".into()
        }
    );
    assert_eq!(arms[0].value.kind, HirExprKind::Name("fallback".into()));
    let HirPatternKind::Tuple { name, fields } = &arms[1].pattern.kind else {
        panic!("expected tuple variant-style pattern");
    };
    assert_eq!(name, "Some");
    assert_eq!(fields.len(), 1);
    assert_eq!(fields[0].kind, HirPatternKind::Name("inner".into()));
    assert_eq!(arms[1].value.kind, HirExprKind::Name("inner".into()));
    assert_eq!(arms[2].pattern.kind, HirPatternKind::Wildcard);
    assert_eq!(arms[2].value.kind, HirExprKind::Name("value".into()));
}

#[test]
fn hir_preserves_struct_declarations() {
    let file = parse_source(
        "pub struct VecHeader<T> { ptr: i32, len: i32, cap: i32, value: Option<T> } struct Empty { }",
    )
    .expect("parse struct declarations");
    assert_eq!(file.items.len(), 2);

    let HirItem::Struct(header) = &file.items[0] else {
        panic!("expected first item to be struct");
    };
    assert!(header.public);
    assert_eq!(header.name, "VecHeader");
    assert_eq!(header.type_params, vec!["T"]);
    assert_eq!(
        header
            .fields
            .iter()
            .map(|field| field.name.as_str())
            .collect::<Vec<_>>(),
        vec!["ptr", "len", "cap", "value"]
    );
    assert_eq!(header.fields[0].ty.kind, HirTypeKind::Name("i32".into()));
    let HirTypeKind::Generic { name, args } = &header.fields[3].ty.kind else {
        panic!("expected generic field type");
    };
    assert_eq!(name, "Option");
    assert_eq!(args.len(), 1);
    assert_eq!(args[0].kind, HirTypeKind::Name("T".into()));

    let HirItem::Struct(empty) = &file.items[1] else {
        panic!("expected second item to be struct");
    };
    assert!(!empty.public);
    assert_eq!(empty.name, "Empty");
    assert!(empty.fields.is_empty());
}

#[test]
fn hir_preserves_struct_literal_expressions() {
    let file = parse_source(
        "struct Point { x: i32, y: i32 } fn make() { let p = Point { x: 1, y: 2 }; let empty = Point { }; }",
    )
    .expect("parse struct literal expressions");
    assert_eq!(file.items.len(), 2);

    let HirItem::Fn(func) = &file.items[1] else {
        panic!("expected second item to be function");
    };
    assert_eq!(func.body.stmts.len(), 2);

    let first = let_value(&func.body.stmts[0], "p");
    let HirExprKind::StructLiteral { name, fields } = &first.kind else {
        panic!("expected named struct literal");
    };
    assert_eq!(name, "Point");
    assert_eq!(
        fields
            .iter()
            .map(|field| field.name.as_str())
            .collect::<Vec<_>>(),
        vec!["x", "y"]
    );
    assert_eq!(
        fields[0].value.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Int,
            text: "1".into()
        }
    );
    assert_eq!(
        fields[1].value.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Int,
            text: "2".into()
        }
    );

    let second = let_value(&func.body.stmts[1], "empty");
    let HirExprKind::StructLiteral { name, fields } = &second.kind else {
        panic!("expected empty named struct literal");
    };
    assert_eq!(name, "Point");
    assert!(fields.is_empty());
}

#[test]
fn hir_preserves_slice_type_syntax() {
    let func = only_fn("fn first(values: [i32], nested: [[bool]]) -> i32 { return 0; }");
    assert_eq!(func.params.len(), 2);

    let HirTypeKind::Slice { elem } = &func.params[0].ty.kind else {
        panic!("expected first parameter to be a slice");
    };
    assert_eq!(elem.kind, HirTypeKind::Name("i32".into()));

    let HirTypeKind::Slice { elem } = &func.params[1].ty.kind else {
        panic!("expected second parameter to be a slice");
    };
    let HirTypeKind::Slice { elem } = &elem.kind else {
        panic!("expected nested slice element");
    };
    assert_eq!(elem.kind, HirTypeKind::Name("bool".into()));
}

#[test]
fn hir_preserves_reference_type_syntax() {
    let func = only_fn("fn borrow(value: &i32, values: &[i32], nested: & &bool) { return; }");
    assert_eq!(func.params.len(), 3);

    let HirTypeKind::Ref { inner } = &func.params[0].ty.kind else {
        panic!("expected first parameter to be a reference");
    };
    assert_eq!(inner.kind, HirTypeKind::Name("i32".into()));

    let HirTypeKind::Ref { inner } = &func.params[1].ty.kind else {
        panic!("expected second parameter to be a reference");
    };
    let HirTypeKind::Slice { elem } = &inner.kind else {
        panic!("expected referenced slice");
    };
    assert_eq!(elem.kind, HirTypeKind::Name("i32".into()));

    let HirTypeKind::Ref { inner } = &func.params[2].ty.kind else {
        panic!("expected nested reference");
    };
    let HirTypeKind::Ref { inner } = &inner.kind else {
        panic!("expected inner reference");
    };
    assert_eq!(inner.kind, HirTypeKind::Name("bool".into()));
}

#[test]
fn hir_preserves_generic_function_declarations() {
    let func = only_fn("pub fn unwrap_or<T>(value: T, fallback: T) -> T { return fallback; }");

    assert!(func.public);
    assert_eq!(func.name, "unwrap_or");
    assert_eq!(func.type_params, vec!["T"]);
    assert_eq!(func.params.len(), 2);
    assert_eq!(func.params[0].name, "value");
    assert_eq!(func.params[0].ty.kind, HirTypeKind::Name("T".into()));
    assert_eq!(func.params[1].name, "fallback");
    assert_eq!(func.params[1].ty.kind, HirTypeKind::Name("T".into()));
    assert_eq!(func.ret.kind, HirTypeKind::Name("T".into()));
}

#[test]
fn hir_preserves_const_generic_params_and_named_array_lengths() {
    let file = parse_source(
        "pub struct ArrayVec<T, const N: usize> { values: [T; N], len: usize } fn first<T, const N: usize>(values: [T; N]) -> T { return values[0]; }",
    )
    .expect("parse const generic declarations");
    assert_eq!(file.items.len(), 2);

    let HirItem::Struct(array_vec) = &file.items[0] else {
        panic!("expected first item to be struct");
    };
    assert_eq!(array_vec.name, "ArrayVec");
    assert_eq!(array_vec.type_params, vec!["T"]);
    assert_eq!(array_vec.const_params.len(), 1);
    assert_eq!(array_vec.const_params[0].name, "N");
    assert_eq!(
        array_vec.const_params[0].ty.kind,
        HirTypeKind::Name("usize".into())
    );
    let HirTypeKind::Array { elem, len } = &array_vec.fields[0].ty.kind else {
        panic!("expected array field");
    };
    assert_eq!(elem.kind, HirTypeKind::Name("T".into()));
    assert_eq!(len, "N");

    let HirItem::Fn(first) = &file.items[1] else {
        panic!("expected second item to be function");
    };
    assert_eq!(first.name, "first");
    assert_eq!(first.type_params, vec!["T"]);
    assert_eq!(first.const_params.len(), 1);
    assert_eq!(first.const_params[0].name, "N");
    let HirTypeKind::Array { elem, len } = &first.params[0].ty.kind else {
        panic!("expected array parameter");
    };
    assert_eq!(elem.kind, HirTypeKind::Name("T".into()));
    assert_eq!(len, "N");
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

#[test]
fn frontend_fixtures_parse_through_cpu_and_hir_with_consistent_roots_and_spans() {
    let fixtures = all_frontend_fixtures();
    assert!(
        fixtures.len() > 3,
        "expected parser fixtures plus sample programs"
    );

    for (name, src) in fixtures {
        let (tokens, ast) = parse_cpu_ast(&name, &src);
        let root = &ast.nodes[ast.root as usize];
        assert_eq!(root.tag, "file", "{name}: CPU root tag");

        let file =
            parse_source(&src).unwrap_or_else(|err| panic!("{name}: HIR parse failed: {err}"));
        assert_eq!(
            file.items.len(),
            root.children.len(),
            "{name}: CPU/HIR top-level item count"
        );
        assert_hir_file_spans(&name, &src, &tokens, &file);
    }
}

#[test]
fn cpu_parser_builds_expected_syntax_tags_for_real_fixtures() {
    for (name, src, expected_tags) in [
        (
            "sample arithmetic precedence",
            include_str!("../sample_programs/arithmetic_precedence.lani"),
            &["fn", "stmt_let", "group", "add", "mul", "call"][..],
        ),
        (
            "sample array sum",
            include_str!("../sample_programs/array_sum.lani"),
            &["type_array", "array_lit", "stmt_while", "add_set", "index"][..],
        ),
        (
            "sample loop control",
            include_str!("../sample_programs/loop_control.lani"),
            &["stmt_while", "stmt_if", "stmt_continue", "stmt_break"][..],
        ),
        (
            "top-level script sample",
            include_str!("../sample_programs/top_level_script.lani"),
            &["file", "stmt_let", "stmt_expr", "call", "mul", "add"][..],
        ),
    ] {
        let (_, ast) = parse_cpu_ast(name, src);
        let counts = ast_tag_counts(&ast);
        for tag in expected_tags {
            assert!(
                counts.get(tag).copied().unwrap_or(0) > 0,
                "{name}: expected CPU AST tag {tag}, counts: {counts:?}"
            );
        }
    }
}

#[test]
fn hir_preserves_sample_arithmetic_precedence_and_group_spans() {
    let src = include_str!("../sample_programs/arithmetic_precedence.lani");
    let func = only_fn(src);

    let a = let_value(&func.body.stmts[0], "a");
    assert_eq!(span_text(src, a.span), "1 + 2 * 3");
    let HirExprKind::Binary {
        op: HirBinaryOp::Add,
        lhs: a_lhs,
        rhs: a_rhs,
    } = &a.kind
    else {
        panic!("expected a initializer to be addition, got {:?}", a.kind);
    };
    assert_eq!(
        a_lhs.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Int,
            text: "1".into()
        }
    );
    let HirExprKind::Binary {
        op: HirBinaryOp::Mul,
        lhs: mul_lhs,
        rhs: mul_rhs,
    } = &a_rhs.kind
    else {
        panic!("expected multiplication on right side of a initializer");
    };
    assert_eq!(
        mul_lhs.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Int,
            text: "2".into()
        }
    );
    assert_eq!(
        mul_rhs.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Int,
            text: "3".into()
        }
    );

    let b = let_value(&func.body.stmts[1], "b");
    assert_eq!(span_text(src, b.span), "(1 + 2) * 3");
    let HirExprKind::Binary {
        op: HirBinaryOp::Mul,
        lhs: grouped_add,
        rhs: b_rhs,
    } = &b.kind
    else {
        panic!(
            "expected b initializer to be multiplication, got {:?}",
            b.kind
        );
    };
    assert_eq!(span_text(src, grouped_add.span), "(1 + 2)");
    assert!(matches!(
        grouped_add.kind,
        HirExprKind::Binary {
            op: HirBinaryOp::Add,
            ..
        }
    ));
    assert_eq!(
        b_rhs.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Int,
            text: "3".into()
        }
    );
}

#[test]
fn hir_lowers_sample_array_sum_assignments_and_indexing() {
    let func = only_fn(include_str!("../sample_programs/array_sum.lani"));
    assert_eq!(func.body.stmts.len(), 6);

    let HirStmtKind::Let {
        name,
        ty: Some(values_ty),
        value: Some(values),
    } = &func.body.stmts[0].kind
    else {
        panic!("expected typed values array binding");
    };
    assert_eq!(name, "values");
    let HirTypeKind::Array { elem, len } = &values_ty.kind else {
        panic!("expected values to have an array type");
    };
    assert_eq!(elem.kind, HirTypeKind::Name("i32".into()));
    assert_eq!(len, "5");
    let HirExprKind::Array(elems) = &values.kind else {
        panic!("expected values initializer to be an array literal");
    };
    assert_eq!(elems.len(), 5);

    let HirStmtKind::While { body, .. } = &func.body.stmts[3].kind else {
        panic!("expected while loop");
    };
    assert_eq!(body.stmts.len(), 2);

    let HirStmtKind::Expr(total_assign) = &body.stmts[0].kind else {
        panic!("expected total assignment expression statement");
    };
    let HirExprKind::Assign {
        op: HirAssignOp::Add,
        target,
        value,
    } = &total_assign.kind
    else {
        panic!("expected total += values[i]");
    };
    assert_eq!(target.kind, HirExprKind::Name("total".into()));
    let HirExprKind::Index { base, index } = &value.kind else {
        panic!("expected values[i] index expression");
    };
    assert_eq!(base.kind, HirExprKind::Name("values".into()));
    assert_eq!(index.kind, HirExprKind::Name("i".into()));

    let HirStmtKind::Expr(i_assign) = &body.stmts[1].kind else {
        panic!("expected i assignment expression statement");
    };
    assert!(matches!(
        i_assign.kind,
        HirExprKind::Assign {
            op: HirAssignOp::Add,
            ..
        }
    ));
}

#[test]
fn hir_lowers_top_level_script_sample_as_statement_items() {
    let src = include_str!("../sample_programs/top_level_script.lani");
    let file = parse_source(src).expect("parse top-level script HIR");
    assert_eq!(file.items.len(), 3);

    let HirItem::Stmt(first) = &file.items[0] else {
        panic!("expected first top-level item to be a statement");
    };
    let x = let_value(first, "x");
    assert_eq!(
        x.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Int,
            text: "3".into()
        }
    );

    let HirItem::Stmt(second) = &file.items[1] else {
        panic!("expected second top-level item to be a statement");
    };
    let y = let_value(second, "y");
    assert_eq!(
        y.kind,
        HirExprKind::Literal {
            kind: HirLiteralKind::Int,
            text: "4".into()
        }
    );

    let HirItem::Stmt(third) = &file.items[2] else {
        panic!("expected third top-level item to be a statement");
    };
    let HirStmtKind::Expr(call) = &third.kind else {
        panic!("expected top-level print call expression");
    };
    let HirExprKind::Call { callee, args } = &call.kind else {
        panic!("expected call expression");
    };
    assert_eq!(callee.kind, HirExprKind::Name("print".into()));
    assert_eq!(args.len(), 1);
    let HirExprKind::Binary {
        op: HirBinaryOp::Add,
        lhs,
        rhs,
    } = &args[0].kind
    else {
        panic!("expected print argument to be x*x + y*y");
    };
    assert!(matches!(
        lhs.kind,
        HirExprKind::Binary {
            op: HirBinaryOp::Mul,
            ..
        }
    ));
    assert!(matches!(
        rhs.kind,
        HirExprKind::Binary {
            op: HirBinaryOp::Mul,
            ..
        }
    ));
}

#[test]
fn cpu_parser_and_hir_reject_missing_initializer_expression() {
    let src = "fn main() { let x = ; }\n";
    let tokens = lex_on_cpu(src).expect("lex invalid fixture");
    let kinds = tokens.iter().map(|token| token.kind).collect::<Vec<_>>();
    let cpu_err =
        parse_from_token_kinds(&kinds).expect_err("CPU parser should reject missing initializer");
    assert_eq!(cpu_err.expected, "primary");

    let hir_err = parse_source(src).expect_err("HIR parser should reject missing initializer");
    let HirError::Parse { expected, .. } = hir_err else {
        panic!("expected HIR parse error");
    };
    assert_eq!(expected, "primary");
}
