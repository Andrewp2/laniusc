use crate::hir::{
    HirAssignOp,
    HirBinaryOp,
    HirBlock,
    HirExpr,
    HirExprKind,
    HirFile,
    HirFn,
    HirItem,
    HirLiteralKind,
    HirStmt,
    HirStmtKind,
    HirType,
    HirTypeKind,
    HirUnaryOp,
};

pub fn emit_c(file: &HirFile) -> String {
    CEmitter::new().emit_file(file)
}

struct CEmitter {
    out: String,
    indent: usize,
}

impl CEmitter {
    fn new() -> Self {
        Self {
            out: String::new(),
            indent: 0,
        }
    }

    fn emit_file(mut self, file: &HirFile) -> String {
        self.line("#include <stdbool.h>");
        self.line("#include <stdint.h>");
        self.line("#include <stdio.h>");
        self.line("");
        self.line("static inline void lanius_print_i64(int64_t value) {");
        self.indent += 1;
        self.line("printf(\"%lld\\n\", (long long)value);");
        self.indent -= 1;
        self.line("}");
        self.line("");

        let mut top_level_stmts = Vec::new();
        for item in &file.items {
            match item {
                HirItem::Fn(func) => {
                    self.emit_fn(func);
                    self.line("");
                }
                HirItem::Stmt(stmt) => top_level_stmts.push(stmt),
            }
        }

        if !top_level_stmts.is_empty() {
            self.line("int main(void) {");
            self.indent += 1;
            for stmt in top_level_stmts {
                self.emit_stmt(stmt, false);
            }
            self.line("return 0;");
            self.indent -= 1;
            self.line("}");
        }

        self.out
    }

    fn emit_fn(&mut self, func: &HirFn) {
        let ret = self.emit_return_type(func);
        let params = if func.params.is_empty() {
            "void".to_string()
        } else {
            func.params
                .iter()
                .map(|param| self.emit_decl(&param.ty, &sanitize_ident(&param.name)))
                .collect::<Vec<_>>()
                .join(", ")
        };
        self.line(&format!(
            "{} {}({}) {{",
            ret,
            sanitize_ident(&func.name),
            params
        ));
        self.indent += 1;
        let main_returns_int = func.name == "main" && matches!(func.ret.kind, HirTypeKind::Void);
        for stmt in &func.body.stmts {
            self.emit_stmt(stmt, main_returns_int);
        }
        if main_returns_int && !block_definitely_returns(&func.body) {
            self.line("return 0;");
        }
        self.indent -= 1;
        self.line("}");
    }

    fn emit_return_type(&self, func: &HirFn) -> String {
        if func.name == "main" {
            return "int".into();
        }
        self.emit_type_name(&func.ret)
    }

    fn emit_stmt(&mut self, stmt: &HirStmt, main_returns_int: bool) {
        match &stmt.kind {
            HirStmtKind::Let { name, ty, value } => {
                let c_name = sanitize_ident(name);
                match ty {
                    Some(ty) => {
                        let decl = self.emit_decl(ty, &c_name);
                        if let Some(value) = value {
                            self.line(&format!("{} = {};", decl, self.emit_expr(value)));
                        } else {
                            self.line(&format!("{};", decl));
                        }
                    }
                    None => {
                        let inferred = value
                            .as_ref()
                            .map(|expr| self.infer_expr_type(expr))
                            .unwrap_or_else(|| "int64_t".into());
                        if let Some(value) = value {
                            self.line(&format!(
                                "{} {} = {};",
                                inferred,
                                c_name,
                                self.emit_expr(value)
                            ));
                        } else {
                            self.line(&format!("{} {};", inferred, c_name));
                        }
                    }
                }
            }
            HirStmtKind::Return(value) => match value {
                Some(expr) => self.line(&format!("return {};", self.emit_expr(expr))),
                None if main_returns_int => self.line("return 0;"),
                None => self.line("return;"),
            },
            HirStmtKind::If {
                cond,
                then_block,
                else_block,
            } => {
                self.line(&format!("if ({}) {{", self.emit_expr(cond)));
                self.emit_block_contents(then_block, main_returns_int);
                if let Some(else_block) = else_block {
                    self.line("} else {");
                    self.emit_block_contents(else_block, main_returns_int);
                    self.line("}");
                } else {
                    self.line("}");
                }
            }
            HirStmtKind::While { cond, body } => {
                self.line(&format!("while ({}) {{", self.emit_expr(cond)));
                self.emit_block_contents(body, main_returns_int);
                self.line("}");
            }
            HirStmtKind::Break => self.line("break;"),
            HirStmtKind::Continue => self.line("continue;"),
            HirStmtKind::Block(block) => {
                self.line("{");
                self.emit_block_contents(block, main_returns_int);
                self.line("}");
            }
            HirStmtKind::Expr(expr) => self.line(&format!("{};", self.emit_expr(expr))),
        }
    }

    fn emit_block_contents(&mut self, block: &HirBlock, main_returns_int: bool) {
        self.indent += 1;
        for stmt in &block.stmts {
            self.emit_stmt(stmt, main_returns_int);
        }
        self.indent -= 1;
    }

    fn emit_expr(&self, expr: &HirExpr) -> String {
        match &expr.kind {
            HirExprKind::Name(name) => sanitize_ident(name),
            HirExprKind::Literal { kind: _, text } => text.clone(),
            HirExprKind::Array(elems) => {
                let elems = elems
                    .iter()
                    .map(|elem| self.emit_expr(elem))
                    .collect::<Vec<_>>()
                    .join(", ");
                format!("{{{}}}", elems)
            }
            HirExprKind::Call { callee, args } => {
                if matches!(&callee.kind, HirExprKind::Name(name) if name == "print")
                    && args.len() == 1
                {
                    return format!("lanius_print_i64({})", self.emit_expr(&args[0]));
                }
                let args = args
                    .iter()
                    .map(|arg| self.emit_expr(arg))
                    .collect::<Vec<_>>()
                    .join(", ");
                format!("{}({})", self.emit_expr(callee), args)
            }
            HirExprKind::Index { base, index } => {
                format!("{}[{}]", self.emit_expr(base), self.emit_expr(index))
            }
            HirExprKind::Member { base, member } => {
                format!("{}.{}", self.emit_expr(base), sanitize_ident(member))
            }
            HirExprKind::Unary { op, expr } => match op {
                HirUnaryOp::PreInc => format!("(++{})", self.emit_expr(expr)),
                HirUnaryOp::PreDec => format!("(--{})", self.emit_expr(expr)),
                HirUnaryOp::Plus => format!("(+{})", self.emit_expr(expr)),
                HirUnaryOp::Neg => format!("(-{})", self.emit_expr(expr)),
                HirUnaryOp::Not => format!("(!{})", self.emit_expr(expr)),
                HirUnaryOp::BitNot => format!("(~{})", self.emit_expr(expr)),
                HirUnaryOp::PostInc => format!("({}++)", self.emit_expr(expr)),
                HirUnaryOp::PostDec => format!("({}--)", self.emit_expr(expr)),
            },
            HirExprKind::Binary { op, lhs, rhs } => format!(
                "({} {} {})",
                self.emit_expr(lhs),
                binary_op(*op),
                self.emit_expr(rhs)
            ),
            HirExprKind::Assign { op, target, value } => format!(
                "({} {} {})",
                self.emit_expr(target),
                assign_op(*op),
                self.emit_expr(value)
            ),
        }
    }

    fn infer_expr_type(&self, expr: &HirExpr) -> String {
        match &expr.kind {
            HirExprKind::Literal { kind, .. } => match kind {
                HirLiteralKind::Int => "int64_t".into(),
                HirLiteralKind::Float => "double".into(),
                HirLiteralKind::String => "const char *".into(),
                HirLiteralKind::Char => "char".into(),
            },
            HirExprKind::Binary { op, lhs, rhs } => match op {
                HirBinaryOp::Lt
                | HirBinaryOp::Gt
                | HirBinaryOp::Le
                | HirBinaryOp::Ge
                | HirBinaryOp::Eq
                | HirBinaryOp::Ne
                | HirBinaryOp::And
                | HirBinaryOp::Or => "bool".into(),
                _ => {
                    let lhs = self.infer_expr_type(lhs);
                    let rhs = self.infer_expr_type(rhs);
                    if lhs == "double" || rhs == "double" {
                        "double".into()
                    } else {
                        "int64_t".into()
                    }
                }
            },
            HirExprKind::Array(_) => "int64_t".into(),
            HirExprKind::Call { .. }
            | HirExprKind::Index { .. }
            | HirExprKind::Member { .. }
            | HirExprKind::Name(_)
            | HirExprKind::Unary { .. }
            | HirExprKind::Assign { .. } => "int64_t".into(),
        }
    }

    fn emit_decl(&self, ty: &HirType, name: &str) -> String {
        match &ty.kind {
            HirTypeKind::Array { elem, len } => self.emit_decl(elem, &format!("{}[{}]", name, len)),
            HirTypeKind::Void | HirTypeKind::Name(_) => {
                format!("{} {}", self.emit_type_name(ty), name)
            }
        }
    }

    fn emit_type_name(&self, ty: &HirType) -> String {
        match &ty.kind {
            HirTypeKind::Void => "void".into(),
            HirTypeKind::Name(name) => map_type_name(name),
            HirTypeKind::Array { elem, len } => {
                format!("{}[{}]", self.emit_type_name(elem), len)
            }
        }
    }

    fn line(&mut self, s: &str) {
        for _ in 0..self.indent {
            self.out.push_str("    ");
        }
        self.out.push_str(s);
        self.out.push('\n');
    }
}

fn map_type_name(name: &str) -> String {
    match name {
        "i8" => "int8_t".into(),
        "i16" => "int16_t".into(),
        "i32" => "int32_t".into(),
        "i64" => "int64_t".into(),
        "isize" => "intptr_t".into(),
        "u8" => "uint8_t".into(),
        "u16" => "uint16_t".into(),
        "u32" => "uint32_t".into(),
        "u64" => "uint64_t".into(),
        "usize" => "uintptr_t".into(),
        "f32" => "float".into(),
        "f64" => "double".into(),
        "bool" => "bool".into(),
        "char" => "char".into(),
        other => sanitize_ident(other),
    }
}

fn binary_op(op: HirBinaryOp) -> &'static str {
    match op {
        HirBinaryOp::Add => "+",
        HirBinaryOp::Sub => "-",
        HirBinaryOp::Mul => "*",
        HirBinaryOp::Div => "/",
        HirBinaryOp::Mod => "%",
        HirBinaryOp::Shl => "<<",
        HirBinaryOp::Shr => ">>",
        HirBinaryOp::Lt => "<",
        HirBinaryOp::Gt => ">",
        HirBinaryOp::Le => "<=",
        HirBinaryOp::Ge => ">=",
        HirBinaryOp::Eq => "==",
        HirBinaryOp::Ne => "!=",
        HirBinaryOp::BitAnd => "&",
        HirBinaryOp::BitXor => "^",
        HirBinaryOp::BitOr => "|",
        HirBinaryOp::And => "&&",
        HirBinaryOp::Or => "||",
    }
}

fn assign_op(op: HirAssignOp) -> &'static str {
    match op {
        HirAssignOp::Assign => "=",
        HirAssignOp::Add => "+=",
        HirAssignOp::Sub => "-=",
        HirAssignOp::Mul => "*=",
        HirAssignOp::Div => "/=",
        HirAssignOp::Mod => "%=",
        HirAssignOp::Shl => "<<=",
        HirAssignOp::Shr => ">>=",
        HirAssignOp::BitAnd => "&=",
        HirAssignOp::BitXor => "^=",
        HirAssignOp::BitOr => "|=",
    }
}

fn block_definitely_returns(block: &HirBlock) -> bool {
    block
        .stmts
        .last()
        .is_some_and(|stmt| stmt_definitely_returns(stmt))
}

fn stmt_definitely_returns(stmt: &HirStmt) -> bool {
    match &stmt.kind {
        HirStmtKind::Return(_) => true,
        HirStmtKind::Block(block) => block_definitely_returns(block),
        HirStmtKind::If {
            then_block,
            else_block: Some(else_block),
            ..
        } => block_definitely_returns(then_block) && block_definitely_returns(else_block),
        _ => false,
    }
}

fn sanitize_ident(name: &str) -> String {
    let mut out = String::with_capacity(name.len().max(1));
    for (i, ch) in name.chars().enumerate() {
        let valid = ch == '_' || ch.is_ascii_alphanumeric();
        if i == 0 && ch.is_ascii_digit() {
            out.push('_');
        }
        out.push(if valid { ch } else { '_' });
    }
    if out.is_empty() {
        out.push('_');
    }
    if is_c_keyword(&out) {
        format!("l_{}", out)
    } else {
        out
    }
}

fn is_c_keyword(name: &str) -> bool {
    matches!(
        name,
        "auto"
            | "break"
            | "case"
            | "char"
            | "const"
            | "continue"
            | "default"
            | "do"
            | "double"
            | "else"
            | "enum"
            | "extern"
            | "float"
            | "for"
            | "goto"
            | "if"
            | "inline"
            | "int"
            | "long"
            | "register"
            | "restrict"
            | "return"
            | "short"
            | "signed"
            | "sizeof"
            | "static"
            | "struct"
            | "switch"
            | "typedef"
            | "union"
            | "unsigned"
            | "void"
            | "volatile"
            | "while"
            | "_Alignas"
            | "_Alignof"
            | "_Atomic"
            | "_Bool"
            | "_Complex"
            | "_Generic"
            | "_Imaginary"
            | "_Noreturn"
            | "_Static_assert"
            | "_Thread_local"
    )
}
