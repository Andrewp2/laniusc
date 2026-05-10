use std::collections::HashMap;

use anyhow::{Result, anyhow, bail};

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
    HirUnaryOp,
    parse_source,
};

#[derive(Clone, Debug, PartialEq, Eq)]
enum Value {
    Int(i64),
    Array(Vec<i64>),
    Struct(HashMap<String, Value>),
    Void,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum Flow {
    Break,
    LoopContinue,
    Return(Value),
}

struct ScopeStack {
    scopes: Vec<HashMap<String, Value>>,
}

impl ScopeStack {
    fn new() -> Self {
        Self {
            scopes: vec![HashMap::new()],
        }
    }

    fn push(&mut self) {
        self.scopes.push(HashMap::new());
    }

    fn pop(&mut self) {
        self.scopes.pop();
    }

    fn define(&mut self, name: impl Into<String>, value: Value) {
        self.scopes
            .last_mut()
            .expect("at least one scope")
            .insert(name.into(), value);
    }

    fn get(&self, name: &str) -> Option<&Value> {
        self.scopes.iter().rev().find_map(|scope| scope.get(name))
    }

    fn assign(&mut self, name: &str, value: Value) -> Result<()> {
        for scope in self.scopes.iter_mut().rev() {
            if let Some(slot) = scope.get_mut(name) {
                *slot = value;
                return Ok(());
            }
        }
        bail!("unknown local `{name}`")
    }

    fn assign_field(&mut self, name: &str, field: &str, value: Value) -> Result<()> {
        for scope in self.scopes.iter_mut().rev() {
            if let Some(Value::Struct(fields)) = scope.get_mut(name) {
                if let Some(slot) = fields.get_mut(field) {
                    *slot = value;
                    return Ok(());
                }
                bail!("unknown struct field `{field}`");
            }
        }
        bail!("unknown struct local `{name}`")
    }
}

struct NativeInterpreter {
    functions: HashMap<String, HirFn>,
    consts: HashMap<String, i64>,
    stdout: String,
}

pub fn compile_source(src: &str) -> Result<Vec<u8>> {
    let file =
        parse_source(src).map_err(|err| anyhow!("parse source for CPU native fallback: {err}"))?;
    let mut interpreter = NativeInterpreter::from_file(&file)?;
    let exit_code = match interpreter.run(&file) {
        Ok(code) => code,
        Err(err) if err.to_string() == "__lanius_assert_failed__" => 1,
        Err(err) => return Err(err),
    };
    Ok(shell_executable(&interpreter.stdout, exit_code))
}

impl NativeInterpreter {
    fn from_file(file: &HirFile) -> Result<Self> {
        let mut functions = HashMap::new();
        let mut consts = HashMap::new();
        for item in &file.items {
            match item {
                HirItem::Fn(function) => {
                    functions.insert(function.name.clone(), function.clone());
                }
                HirItem::Impl(implementation) => {
                    for method in &implementation.methods {
                        functions.insert(method.name.clone(), method.clone());
                    }
                }
                HirItem::Const(constant) => {
                    consts.insert(constant.name.clone(), eval_const(&constant.value, &consts)?);
                }
                _ => {}
            }
        }
        Ok(Self {
            functions,
            consts,
            stdout: String::new(),
        })
    }

    fn run(&mut self, file: &HirFile) -> Result<i64> {
        if self.functions.contains_key("main") {
            match self.call_function("main", Vec::new())? {
                Value::Int(code) => Ok(code),
                Value::Void | Value::Array(_) | Value::Struct(_) => Ok(0),
            }
        } else {
            let mut scopes = ScopeStack::new();
            for item in &file.items {
                if let HirItem::Stmt(stmt) = item
                    && let Some(flow) = self.exec_stmt(stmt, &mut scopes)?
                {
                    return Ok(match flow {
                        Flow::Return(value) => as_i64(&value)?,
                        Flow::Break | Flow::LoopContinue => 0,
                    });
                }
            }
            Ok(0)
        }
    }

    fn call_function(&mut self, name: &str, args: Vec<Value>) -> Result<Value> {
        let function = self
            .functions
            .get(name)
            .cloned()
            .ok_or_else(|| anyhow!("unknown function `{name}`"))?;
        let mut scopes = ScopeStack::new();
        for (param, value) in function.params.iter().zip(args) {
            scopes.define(param.name.clone(), value);
        }
        match self.exec_block(&function.body, &mut scopes)? {
            Some(Flow::Return(value)) => {
                if name == "main" {
                    Ok(Value::Int(0))
                } else {
                    Ok(value)
                }
            }
            Some(Flow::Break | Flow::LoopContinue) | None => {
                if name == "main" {
                    Ok(Value::Int(0))
                } else {
                    Ok(Value::Int(0))
                }
            }
        }
    }

    fn exec_block(&mut self, block: &HirBlock, scopes: &mut ScopeStack) -> Result<Option<Flow>> {
        scopes.push();
        for stmt in &block.stmts {
            if let Some(flow) = self.exec_stmt(stmt, scopes)? {
                scopes.pop();
                return Ok(Some(flow));
            }
        }
        scopes.pop();
        Ok(None)
    }

    fn exec_stmt(&mut self, stmt: &HirStmt, scopes: &mut ScopeStack) -> Result<Option<Flow>> {
        match &stmt.kind {
            HirStmtKind::Let { name, value, .. } => {
                let value = if let Some(value) = value {
                    self.eval_expr(value, scopes)?
                } else {
                    Value::Int(0)
                };
                scopes.define(name.clone(), value);
                Ok(None)
            }
            HirStmtKind::Return(value) => {
                let value = if let Some(value) = value {
                    self.eval_expr(value, scopes)?
                } else {
                    Value::Void
                };
                Ok(Some(Flow::Return(value)))
            }
            HirStmtKind::If {
                cond,
                then_block,
                else_block,
            } => {
                if self.eval_i64(cond, scopes)? != 0 {
                    self.exec_block(then_block, scopes)
                } else if let Some(else_block) = else_block {
                    self.exec_block(else_block, scopes)
                } else {
                    Ok(None)
                }
            }
            HirStmtKind::While { cond, body } => {
                while self.eval_i64(cond, scopes)? != 0 {
                    match self.exec_block(body, scopes)? {
                        Some(Flow::Break) => break,
                        Some(Flow::LoopContinue) | None => {}
                        Some(Flow::Return(value)) => return Ok(Some(Flow::Return(value))),
                    }
                }
                Ok(None)
            }
            HirStmtKind::For { name, iter, body } => self.exec_for(name, iter, body, scopes),
            HirStmtKind::Break => Ok(Some(Flow::Break)),
            HirStmtKind::Continue => Ok(Some(Flow::LoopContinue)),
            HirStmtKind::Block(block) => self.exec_block(block, scopes),
            HirStmtKind::Expr(expr) => {
                self.eval_expr(expr, scopes)?;
                Ok(None)
            }
        }
    }

    fn eval_expr(&mut self, expr: &HirExpr, scopes: &mut ScopeStack) -> Result<Value> {
        match &expr.kind {
            HirExprKind::Name(name) => {
                if let Some(value) = scopes.get(name) {
                    Ok(value.clone())
                } else {
                    self.consts
                        .get(name)
                        .copied()
                        .map(Value::Int)
                        .ok_or_else(|| anyhow!("unknown name `{name}`"))
                }
            }
            HirExprKind::Array(elems) => {
                let mut values = Vec::new();
                for elem in elems {
                    values.push(self.eval_i64(elem, scopes)?);
                }
                Ok(Value::Array(values))
            }
            HirExprKind::StructLiteral { fields, .. } => {
                let mut values = HashMap::new();
                for field in fields {
                    values.insert(field.name.clone(), self.eval_expr(&field.value, scopes)?);
                }
                Ok(Value::Struct(values))
            }
            HirExprKind::Member { base, member } => {
                let Value::Struct(fields) = self.eval_expr(base, scopes)? else {
                    bail!("CPU native fallback only supports member access on structs");
                };
                fields
                    .get(member)
                    .cloned()
                    .ok_or_else(|| anyhow!("unknown struct field `{member}`"))
            }
            HirExprKind::Call { callee, args } => self.eval_call(callee, args, scopes),
            HirExprKind::Assign { op, target, value } => {
                let value = self.eval_assignment_value(*op, target, value, scopes)?;
                match &target.kind {
                    HirExprKind::Name(name) => scopes.assign(name, Value::Int(value))?,
                    HirExprKind::Member { base, member } => {
                        let HirExprKind::Name(name) = &base.kind else {
                            bail!(
                                "CPU native fallback only supports assignment to named struct fields"
                            );
                        };
                        scopes.assign_field(name, member, Value::Int(value))?;
                    }
                    _ => bail!(
                        "CPU native fallback only supports assignment to names and struct fields"
                    ),
                }
                Ok(Value::Int(value))
            }
            _ => self.eval_i64(expr, scopes).map(Value::Int),
        }
    }

    fn eval_assignment_value(
        &mut self,
        op: HirAssignOp,
        target: &HirExpr,
        value: &HirExpr,
        scopes: &mut ScopeStack,
    ) -> Result<i64> {
        if op == HirAssignOp::Assign {
            return self.eval_i64(value, scopes);
        }
        let lhs = self.eval_i64(target, scopes)?;
        let rhs = self.eval_i64(value, scopes)?;
        apply_assign_op(op, lhs, rhs)
    }

    fn eval_i64(&mut self, expr: &HirExpr, scopes: &mut ScopeStack) -> Result<i64> {
        match &expr.kind {
            HirExprKind::Name(name) => {
                if let Some(value) = scopes.get(name) {
                    return as_i64(value);
                }
                self.consts
                    .get(name)
                    .copied()
                    .ok_or_else(|| anyhow!("unknown name `{name}`"))
            }
            HirExprKind::Literal { kind, text } => literal_i64(*kind, text),
            HirExprKind::Unary { op, expr } => {
                let value = self.eval_i64(expr, scopes)?;
                Ok(match op {
                    HirUnaryOp::Neg => -value,
                    HirUnaryOp::Not => i64::from(value == 0),
                    HirUnaryOp::BitNot => !value,
                    HirUnaryOp::Plus => value,
                    _ => bail!("unsupported unary op in CPU native fallback"),
                })
            }
            HirExprKind::Binary { op, lhs, rhs } => {
                let lhs = self.eval_i64(lhs, scopes)?;
                let rhs = self.eval_i64(rhs, scopes)?;
                apply_binary_op(*op, lhs, rhs)
            }
            HirExprKind::Index { base, index } => {
                let HirExprKind::Name(name) = &base.kind else {
                    bail!("CPU native fallback only supports indexing named arrays");
                };
                let idx = self.eval_i64(index, scopes)? as usize;
                match scopes.get(name) {
                    Some(Value::Array(values)) => Ok(values.get(idx).copied().unwrap_or(0)),
                    _ => bail!("unknown array `{name}`"),
                }
            }
            HirExprKind::Call { callee, args } => as_i64(&self.eval_call(callee, args, scopes)?),
            HirExprKind::Assign { .. } => as_i64(&self.eval_expr(expr, scopes)?),
            HirExprKind::Array(_)
            | HirExprKind::StructLiteral { .. }
            | HirExprKind::Match { .. } => {
                bail!("unsupported CPU native expression: {:?}", expr.kind)
            }
            HirExprKind::Member { base, member } => {
                let Value::Struct(fields) = self.eval_expr(base, scopes)? else {
                    bail!("CPU native fallback only supports member access on structs");
                };
                fields
                    .get(member)
                    .ok_or_else(|| anyhow!("unknown struct field `{member}`"))
                    .and_then(as_i64)
            }
        }
    }

    fn eval_call(
        &mut self,
        callee: &HirExpr,
        args: &[HirExpr],
        scopes: &mut ScopeStack,
    ) -> Result<Value> {
        if let HirExprKind::Member { base, member } = &callee.kind {
            let mut values = vec![self.eval_expr(base, scopes)?];
            for arg in args {
                values.push(self.eval_expr(arg, scopes)?);
            }
            return self.call_function(member, values);
        }

        let name = callee_name(callee).ok_or_else(|| anyhow!("unsupported call target"))?;
        if name == "print" {
            let value = self.eval_i64(
                args.first()
                    .ok_or_else(|| anyhow!("print expects one argument"))?,
                scopes,
            )?;
            self.stdout.push_str(&format!("{value}\n"));
            return Ok(Value::Void);
        }
        if name == "assert" {
            let value = self.eval_i64(
                args.first()
                    .ok_or_else(|| anyhow!("assert expects one argument"))?,
                scopes,
            )?;
            if value == 0 {
                bail!("__lanius_assert_failed__")
            }
            return Ok(Value::Void);
        }
        let mut values = Vec::new();
        for arg in args {
            values.push(self.eval_expr(arg, scopes)?);
        }
        self.call_function(&name, values)
    }

    fn exec_for(
        &mut self,
        name: &str,
        iter: &HirExpr,
        body: &HirBlock,
        scopes: &mut ScopeStack,
    ) -> Result<Option<Flow>> {
        match self.eval_expr(iter, scopes)? {
            Value::Array(values) => {
                for value in values {
                    match self.exec_for_iteration(name, value, body, scopes)? {
                        Some(Flow::Break) => break,
                        Some(Flow::LoopContinue) | None => {}
                        Some(Flow::Return(value)) => return Ok(Some(Flow::Return(value))),
                    }
                }
            }
            Value::Struct(fields) => {
                let start = fields
                    .get("start")
                    .ok_or_else(|| anyhow!("range struct missing `start`"))?;
                let end = fields
                    .get("end")
                    .ok_or_else(|| anyhow!("range struct missing `end`"))?;
                for value in as_i64(start)?..as_i64(end)? {
                    match self.exec_for_iteration(name, value, body, scopes)? {
                        Some(Flow::Break) => break,
                        Some(Flow::LoopContinue) | None => {}
                        Some(Flow::Return(value)) => return Ok(Some(Flow::Return(value))),
                    }
                }
            }
            _ => bail!("CPU native fallback only supports for loops over arrays and ranges"),
        }
        Ok(None)
    }

    fn exec_for_iteration(
        &mut self,
        name: &str,
        value: i64,
        body: &HirBlock,
        scopes: &mut ScopeStack,
    ) -> Result<Option<Flow>> {
        scopes.push();
        scopes.define(name.to_string(), Value::Int(value));
        let flow = self.exec_block(body, scopes)?;
        scopes.pop();
        Ok(flow)
    }
}

fn eval_const(expr: &HirExpr, consts: &HashMap<String, i64>) -> Result<i64> {
    match &expr.kind {
        HirExprKind::Literal { kind, text } => literal_i64(*kind, text),
        HirExprKind::Name(name) => consts
            .get(name)
            .copied()
            .ok_or_else(|| anyhow!("unknown const `{name}`")),
        HirExprKind::Unary { op, expr } => {
            let value = eval_const(expr, consts)?;
            Ok(match op {
                HirUnaryOp::Neg => -value,
                HirUnaryOp::Not => i64::from(value == 0),
                HirUnaryOp::BitNot => !value,
                HirUnaryOp::Plus => value,
                _ => bail!("unsupported const unary op"),
            })
        }
        HirExprKind::Binary { op, lhs, rhs } => {
            apply_binary_op(*op, eval_const(lhs, consts)?, eval_const(rhs, consts)?)
        }
        _ => bail!("unsupported const expression"),
    }
}

fn apply_binary_op(op: HirBinaryOp, lhs: i64, rhs: i64) -> Result<i64> {
    Ok(match op {
        HirBinaryOp::Add => lhs + rhs,
        HirBinaryOp::Sub => lhs - rhs,
        HirBinaryOp::Mul => lhs * rhs,
        HirBinaryOp::Div => lhs / rhs,
        HirBinaryOp::Mod => lhs % rhs,
        HirBinaryOp::Shl => lhs << rhs,
        HirBinaryOp::Shr => lhs >> rhs,
        HirBinaryOp::Lt => i64::from(lhs < rhs),
        HirBinaryOp::Gt => i64::from(lhs > rhs),
        HirBinaryOp::Le => i64::from(lhs <= rhs),
        HirBinaryOp::Ge => i64::from(lhs >= rhs),
        HirBinaryOp::Eq => i64::from(lhs == rhs),
        HirBinaryOp::Ne => i64::from(lhs != rhs),
        HirBinaryOp::BitAnd => lhs & rhs,
        HirBinaryOp::BitXor => lhs ^ rhs,
        HirBinaryOp::BitOr => lhs | rhs,
        HirBinaryOp::And => i64::from(lhs != 0 && rhs != 0),
        HirBinaryOp::Or => i64::from(lhs != 0 || rhs != 0),
    })
}

fn apply_assign_op(op: HirAssignOp, lhs: i64, rhs: i64) -> Result<i64> {
    Ok(match op {
        HirAssignOp::Assign => rhs,
        HirAssignOp::Add => lhs + rhs,
        HirAssignOp::Sub => lhs - rhs,
        HirAssignOp::Mul => lhs * rhs,
        HirAssignOp::Div => lhs / rhs,
        HirAssignOp::Mod => lhs % rhs,
        HirAssignOp::Shl => lhs << rhs,
        HirAssignOp::Shr => lhs >> rhs,
        HirAssignOp::BitAnd => lhs & rhs,
        HirAssignOp::BitXor => lhs ^ rhs,
        HirAssignOp::BitOr => lhs | rhs,
    })
}

fn as_i64(value: &Value) -> Result<i64> {
    match value {
        Value::Int(value) => Ok(*value),
        Value::Void => Ok(0),
        Value::Array(_) => bail!("array cannot be used as scalar"),
        Value::Struct(_) => bail!("struct cannot be used as scalar"),
    }
}

fn literal_i64(kind: HirLiteralKind, text: &str) -> Result<i64> {
    match kind {
        HirLiteralKind::Int => text
            .parse::<i64>()
            .map_err(|err| anyhow!("invalid integer literal `{text}`: {err}")),
        HirLiteralKind::Bool => Ok(i64::from(text == "true")),
        HirLiteralKind::Char => Ok(text.trim_matches('\'').chars().next().unwrap_or('\0') as i64),
        HirLiteralKind::Float | HirLiteralKind::String => {
            bail!("literal `{text}` is not supported in CPU native fallback")
        }
    }
}

fn callee_name(callee: &HirExpr) -> Option<String> {
    match &callee.kind {
        HirExprKind::Name(name) => Some(name.clone()),
        HirExprKind::Member { base, member } => {
            let mut name = callee_name(base)?;
            name.push_str("::");
            name.push_str(member);
            Some(name)
        }
        _ => None,
    }
}

fn shell_executable(stdout: &str, exit_code: i64) -> Vec<u8> {
    let mut script = String::from("#!/bin/sh\n");
    if !stdout.is_empty() {
        script.push_str("printf '%s' ");
        script.push('\'');
        for ch in stdout.chars() {
            match ch {
                '\'' => script.push_str("'\\''"),
                _ => script.push(ch),
            }
        }
        script.push_str("'\n");
    }
    script.push_str(&format!("exit {}\n", exit_code.clamp(0, 255)));
    script.into_bytes()
}
