use std::{cell::RefCell, collections::HashMap};

use anyhow::{Result, anyhow, bail};

use crate::hir::{
    HirAssignOp,
    HirBinaryOp,
    HirBlock,
    HirExpr,
    HirExprKind,
    HirExternFn,
    HirFile,
    HirFn,
    HirItem,
    HirLiteralKind,
    HirStmt,
    HirStmtKind,
    HirStruct,
    HirType,
    HirTypeKind,
    HirUnaryOp,
    parse_source,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum WasmVal {
    I32,
    I64,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct FuncType {
    params: Vec<WasmVal>,
    results: Vec<WasmVal>,
}

#[derive(Clone, Debug)]
struct ImportFn {
    module: String,
    name: String,
    params: Vec<WasmVal>,
    ret: Option<WasmVal>,
    type_idx: u32,
    wasm_index: u32,
}

#[derive(Clone, Debug)]
struct DefinedFn {
    name: String,
    params: Vec<DefinedParam>,
    ret: ReturnLayout,
    body: HirBlock,
    type_idx: u32,
    wasm_index: u32,
}

#[derive(Clone, Debug)]
struct DefinedParam {
    name: String,
    layout: ParamLayout,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum ParamLayout {
    Scalar,
    Array(usize),
    Struct(Vec<String>),
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum ReturnLayout {
    Void,
    Scalar(WasmVal),
    Array(usize),
    Struct(Vec<String>),
}

#[derive(Clone, Debug)]
enum Binding {
    Scalar(u32),
    Array(Vec<u32>),
    Struct(Vec<StructLocal>),
}

#[derive(Clone, Debug)]
struct StructLocal {
    name: String,
    local: u32,
}

const DEFAULT_WASM_SLICE_PARAM_ELEMENTS: usize = 8;

#[derive(Clone, Copy, Debug)]
struct ForBinding {
    item: u32,
    index: u32,
}

#[derive(Default)]
struct FunctionLocals {
    let_bindings: HashMap<usize, Binding>,
    for_bindings: HashMap<usize, ForBinding>,
    next_local: u32,
    scratch: u32,
}

struct FunctionContext<'a> {
    module: &'a CpuWasmModule,
    locals: FunctionLocals,
    scopes: RefCell<Vec<HashMap<String, Binding>>>,
    return_layout: ReturnLayout,
}

#[derive(Clone, Copy, Debug, Default)]
struct ControlLabels {
    break_depth: Option<u32>,
    continue_depth: Option<u32>,
}

impl ControlLabels {
    fn nested_label(self) -> Self {
        Self {
            break_depth: self.break_depth.map(|depth| depth + 1),
            continue_depth: self.continue_depth.map(|depth| depth + 1),
        }
    }
}

impl FunctionContext<'_> {
    fn enter_scope(&self) {
        self.scopes.borrow_mut().push(HashMap::new());
    }

    fn exit_scope(&self) {
        self.scopes.borrow_mut().pop();
    }

    fn bind_let(&self, key: usize, name: &str) -> Result<Binding> {
        let binding = self
            .locals
            .let_bindings
            .get(&key)
            .cloned()
            .ok_or_else(|| anyhow!("missing local plan for `{name}`"))?;
        self.scopes
            .borrow_mut()
            .last_mut()
            .ok_or_else(|| anyhow!("no active local scope"))?
            .insert(name.to_string(), binding.clone());
        Ok(binding)
    }

    fn lookup_binding(&self, name: &str) -> Option<Binding> {
        self.scopes
            .borrow()
            .iter()
            .rev()
            .find_map(|scope| scope.get(name).cloned())
    }

    fn bind_for(&self, key: usize, name: &str) -> Result<ForBinding> {
        let binding = *self
            .locals
            .for_bindings
            .get(&key)
            .ok_or_else(|| anyhow!("missing for-loop local plan for `{name}`"))?;
        self.scopes
            .borrow_mut()
            .last_mut()
            .ok_or_else(|| anyhow!("no active local scope"))?
            .insert(name.to_string(), Binding::Scalar(binding.item));
        Ok(binding)
    }
}

struct CpuWasmModule {
    types: Vec<FuncType>,
    imports: Vec<ImportFn>,
    defined: Vec<DefinedFn>,
    consts: HashMap<String, i64>,
    structs: HashMap<String, StructLayout>,
}

#[derive(Clone, Debug)]
struct StructLayout {
    fields: Vec<String>,
}

pub fn compile_source(src: &str) -> Result<Vec<u8>> {
    let file =
        parse_source(src).map_err(|err| anyhow!("parse source for CPU WASM codegen: {err}"))?;
    CpuWasmModule::from_file(&file)?.emit()
}

impl CpuWasmModule {
    fn from_file(file: &HirFile) -> Result<Self> {
        let mut module = Self {
            types: Vec::new(),
            imports: Vec::new(),
            defined: Vec::new(),
            consts: collect_consts(file)?,
            structs: collect_structs(file),
        };

        module.add_import(
            "env".to_string(),
            "print_i64".to_string(),
            vec![WasmVal::I64],
            None,
        );

        for item in &file.items {
            if let HirItem::ExternFn(function) = item {
                module.add_extern(function)?;
            }
        }

        let mut saw_main = false;
        for item in &file.items {
            if let HirItem::Fn(function) = item {
                if function.name == "main" {
                    saw_main = true;
                }
                module.add_defined(function)?;
            }
            if let HirItem::Impl(implementation) = item {
                for method in &implementation.methods {
                    module.add_defined(method)?;
                }
            }
        }
        if !saw_main {
            module.add_synthetic_main(file);
        }

        Ok(module)
    }

    fn emit(&self) -> Result<Vec<u8>> {
        let mut wasm = Vec::new();
        wasm.extend_from_slice(b"\0asm");
        wasm.extend_from_slice(&[1, 0, 0, 0]);

        wasm_section(&mut wasm, 1, self.type_section());
        wasm_section(&mut wasm, 2, self.import_section());
        wasm_section(&mut wasm, 3, self.function_section());
        wasm_section(&mut wasm, 7, self.export_section()?);
        wasm_section(&mut wasm, 10, self.code_section()?);
        Ok(wasm)
    }

    fn add_import(
        &mut self,
        module: String,
        name: String,
        params: Vec<WasmVal>,
        ret: Option<WasmVal>,
    ) {
        let results = ret.into_iter().collect::<Vec<_>>();
        let type_idx = self.intern_type(params.clone(), results);
        let wasm_index = self.imports.len() as u32;
        self.imports.push(ImportFn {
            module,
            name,
            params,
            ret,
            type_idx,
            wasm_index,
        });
    }

    fn add_extern(&mut self, function: &HirExternFn) -> Result<()> {
        let params = function
            .params
            .iter()
            .map(|param| wasm_val_for_extern_type(&param.ty))
            .collect::<Result<Vec<_>>>()?;
        let ret = wasm_return_for_extern_type(&function.ret)?;
        self.add_import(
            function.abi.clone().unwrap_or_else(|| "env".to_string()),
            function.name.clone(),
            params,
            ret,
        );
        Ok(())
    }

    fn add_defined(&mut self, function: &HirFn) -> Result<()> {
        let is_main = function.name == "main";
        let defined_params = if is_main {
            Vec::new()
        } else {
            function
                .params
                .iter()
                .map(|param| DefinedParam {
                    name: param.name.clone(),
                    layout: param_layout_for_type(self, &param.ty),
                })
                .collect::<Vec<_>>()
        };
        let params = wasm_params_for_defined_params(&defined_params);
        let ret = if is_main {
            ReturnLayout::Scalar(WasmVal::I32)
        } else {
            return_layout_for_type(self, &function.ret)
        };
        let type_idx = self.intern_type(params, wasm_results_for_return(&ret));
        let wasm_index = self.imports.len() as u32 + self.defined.len() as u32;
        self.defined.push(DefinedFn {
            name: function.name.clone(),
            params: defined_params,
            ret,
            body: function.body.clone(),
            type_idx,
            wasm_index,
        });
        Ok(())
    }

    fn add_synthetic_main(&mut self, file: &HirFile) {
        let stmts = file
            .items
            .iter()
            .filter_map(|item| {
                if let HirItem::Stmt(stmt) = item {
                    Some(stmt.clone())
                } else {
                    None
                }
            })
            .collect::<Vec<_>>();
        let body = HirBlock {
            stmts,
            span: file.span,
        };
        let type_idx = self.intern_type(Vec::new(), vec![WasmVal::I32]);
        let wasm_index = self.imports.len() as u32 + self.defined.len() as u32;
        self.defined.push(DefinedFn {
            name: "main".to_string(),
            params: Vec::new(),
            ret: ReturnLayout::Scalar(WasmVal::I32),
            body,
            type_idx,
            wasm_index,
        });
    }

    fn intern_type(&mut self, params: Vec<WasmVal>, results: Vec<WasmVal>) -> u32 {
        let ty = FuncType { params, results };
        if let Some(idx) = self.types.iter().position(|existing| existing == &ty) {
            return idx as u32;
        }
        self.types.push(ty);
        (self.types.len() - 1) as u32
    }

    fn type_section(&self) -> Vec<u8> {
        let mut out = Vec::new();
        write_u32(&mut out, self.types.len() as u32);
        for ty in &self.types {
            out.push(0x60);
            write_u32(&mut out, ty.params.len() as u32);
            for &param in &ty.params {
                out.push(valtype_byte(param));
            }
            write_u32(&mut out, ty.results.len() as u32);
            for &result in &ty.results {
                out.push(valtype_byte(result));
            }
        }
        out
    }

    fn import_section(&self) -> Vec<u8> {
        let mut out = Vec::new();
        write_u32(&mut out, self.imports.len() as u32);
        for import in &self.imports {
            write_name(&mut out, &import.module);
            write_name(&mut out, &import.name);
            out.push(0x00);
            write_u32(&mut out, import.type_idx);
        }
        out
    }

    fn function_section(&self) -> Vec<u8> {
        let mut out = Vec::new();
        write_u32(&mut out, self.defined.len() as u32);
        for function in &self.defined {
            write_u32(&mut out, function.type_idx);
        }
        out
    }

    fn export_section(&self) -> Result<Vec<u8>> {
        let main = self
            .defined
            .iter()
            .find(|function| function.name == "main")
            .ok_or_else(|| anyhow!("CPU WASM codegen requires a main function"))?;
        let mut out = Vec::new();
        write_u32(&mut out, 1);
        write_name(&mut out, "main");
        out.push(0x00);
        write_u32(&mut out, main.wasm_index);
        Ok(out)
    }

    fn code_section(&self) -> Result<Vec<u8>> {
        let mut out = Vec::new();
        write_u32(&mut out, self.defined.len() as u32);
        for function in &self.defined {
            let body = self.function_body(function)?;
            write_u32(&mut out, body.len() as u32);
            out.extend(body);
        }
        Ok(out)
    }

    fn function_body(&self, function: &DefinedFn) -> Result<Vec<u8>> {
        let param_count =
            wasm_param_count(function.params.iter().map(|param| param.layout.clone()));
        let mut ctx = FunctionContext {
            module: self,
            locals: FunctionLocals {
                let_bindings: HashMap::new(),
                for_bindings: HashMap::new(),
                next_local: param_count,
                scratch: 0,
            },
            scopes: RefCell::new(Vec::new()),
            return_layout: function.ret.clone(),
        };
        let mut param_scope = HashMap::new();
        let mut next_param = 0;
        for param in &function.params {
            match &param.layout {
                ParamLayout::Scalar => {
                    param_scope.insert(param.name.clone(), Binding::Scalar(next_param));
                    next_param += 1;
                }
                ParamLayout::Array(width) => {
                    let elems = (next_param..next_param + *width as u32).collect::<Vec<_>>();
                    next_param += *width as u32;
                    param_scope.insert(param.name.clone(), Binding::Array(elems));
                }
                ParamLayout::Struct(fields) => {
                    let locals = fields
                        .iter()
                        .map(|name| {
                            let local = next_param;
                            next_param += 1;
                            StructLocal {
                                name: name.clone(),
                                local,
                            }
                        })
                        .collect::<Vec<_>>();
                    param_scope.insert(param.name.clone(), Binding::Struct(locals));
                }
            }
        }
        ctx.scopes.borrow_mut().push(param_scope);
        collect_block_locals(&function.body, &mut ctx.locals, self);
        ctx.locals.scratch = ctx.locals.next_local;
        ctx.locals.next_local += 1;

        let mut body = Vec::new();
        let declared_locals = ctx.locals.next_local - param_count;
        if declared_locals == 0 {
            write_u32(&mut body, 0);
        } else {
            write_u32(&mut body, 1);
            write_u32(&mut body, declared_locals);
            body.push(valtype_byte(WasmVal::I64));
        }

        emit_block(&mut body, &function.body, &ctx, ControlLabels::default())?;
        match &function.ret {
            ReturnLayout::Scalar(WasmVal::I32) => {
                body.push(0x41);
                write_i32(&mut body, 0);
            }
            ReturnLayout::Scalar(WasmVal::I64) => emit_i64_const(&mut body, 0),
            ReturnLayout::Array(width) => {
                for _ in 0..*width {
                    emit_i64_const(&mut body, 0);
                }
            }
            ReturnLayout::Struct(fields) => {
                for _ in fields {
                    emit_i64_const(&mut body, 0);
                }
            }
            ReturnLayout::Void => {}
        }
        body.push(0x0b);
        Ok(body)
    }

    fn import_by_name(&self, name: &str) -> Option<&ImportFn> {
        self.imports.iter().find(|import| import.name == name)
    }

    fn defined_by_name(&self, name: &str) -> Option<&DefinedFn> {
        self.defined.iter().find(|function| function.name == name)
    }
}

fn collect_consts(file: &HirFile) -> Result<HashMap<String, i64>> {
    let mut consts = HashMap::new();
    for item in &file.items {
        if let HirItem::Const(constant) = item {
            consts.insert(
                constant.name.clone(),
                eval_const_expr(&constant.value, &consts)?,
            );
        }
    }
    Ok(consts)
}

fn collect_structs(file: &HirFile) -> HashMap<String, StructLayout> {
    file.items
        .iter()
        .filter_map(|item| {
            let HirItem::Struct(structure) = item else {
                return None;
            };
            Some((structure.name.clone(), struct_layout(structure)))
        })
        .collect()
}

fn struct_layout(structure: &HirStruct) -> StructLayout {
    StructLayout {
        fields: structure
            .fields
            .iter()
            .map(|field| field.name.clone())
            .collect(),
    }
}

fn param_layout_for_type(module: &CpuWasmModule, ty: &HirType) -> ParamLayout {
    if let Some(layout) = struct_layout_for_type(module, Some(ty)) {
        return ParamLayout::Struct(layout.fields.clone());
    }
    match &ty.kind {
        HirTypeKind::Array { .. } => ParamLayout::Array(array_width_for_type(ty)),
        HirTypeKind::Slice { .. } => ParamLayout::Array(DEFAULT_WASM_SLICE_PARAM_ELEMENTS),
        _ => ParamLayout::Scalar,
    }
}

fn return_layout_for_type(module: &CpuWasmModule, ty: &HirType) -> ReturnLayout {
    if let Some(layout) = struct_layout_for_type(module, Some(ty)) {
        return ReturnLayout::Struct(layout.fields.clone());
    }
    match &ty.kind {
        HirTypeKind::Void => ReturnLayout::Void,
        HirTypeKind::Array { .. } => ReturnLayout::Array(array_width_for_type(ty)),
        _ => ReturnLayout::Scalar(WasmVal::I64),
    }
}

fn wasm_results_for_return(layout: &ReturnLayout) -> Vec<WasmVal> {
    match layout {
        ReturnLayout::Void => Vec::new(),
        ReturnLayout::Scalar(value) => vec![*value],
        ReturnLayout::Array(width) => std::iter::repeat(WasmVal::I64).take(*width).collect(),
        ReturnLayout::Struct(fields) => {
            std::iter::repeat(WasmVal::I64).take(fields.len()).collect()
        }
    }
}

fn array_width_for_type(ty: &HirType) -> usize {
    match &ty.kind {
        HirTypeKind::Array { len, .. } => len
            .parse::<usize>()
            .ok()
            .filter(|len| *len > 0)
            .unwrap_or(DEFAULT_WASM_SLICE_PARAM_ELEMENTS),
        _ => DEFAULT_WASM_SLICE_PARAM_ELEMENTS,
    }
}

fn struct_layout_for_type<'a>(
    module: &'a CpuWasmModule,
    ty: Option<&HirType>,
) -> Option<&'a StructLayout> {
    let Some(HirType {
        kind: HirTypeKind::Name(name),
        ..
    }) = ty
    else {
        return None;
    };
    module.structs.get(name)
}

fn wasm_params_for_defined_params(params: &[DefinedParam]) -> Vec<WasmVal> {
    let mut wasm = Vec::new();
    for param in params {
        match &param.layout {
            ParamLayout::Scalar => wasm.push(WasmVal::I64),
            ParamLayout::Array(width) => {
                wasm.extend(std::iter::repeat(WasmVal::I64).take(*width));
            }
            ParamLayout::Struct(fields) => {
                wasm.extend(std::iter::repeat(WasmVal::I64).take(fields.len()));
            }
        }
    }
    wasm
}

fn wasm_param_count(layouts: impl IntoIterator<Item = ParamLayout>) -> u32 {
    layouts
        .into_iter()
        .map(|layout| match layout {
            ParamLayout::Scalar => 1,
            ParamLayout::Array(width) => width as u32,
            ParamLayout::Struct(fields) => fields.len() as u32,
        })
        .sum()
}

fn collect_block_locals(block: &HirBlock, locals: &mut FunctionLocals, module: &CpuWasmModule) {
    for stmt in &block.stmts {
        match &stmt.kind {
            HirStmtKind::Let { ty, value, .. } => {
                let binding = if let Some(layout) = struct_layout_for_type(module, ty.as_ref()) {
                    Binding::Struct(
                        layout
                            .fields
                            .iter()
                            .map(|field| StructLocal {
                                name: field.clone(),
                                local: alloc_local(locals),
                            })
                            .collect(),
                    )
                } else if let Some(HirType {
                    kind: HirTypeKind::Array { .. },
                    ..
                }) = ty
                {
                    Binding::Array(
                        (0..array_width_for_type(ty.as_ref().unwrap()))
                            .map(|_| alloc_local(locals))
                            .collect(),
                    )
                } else if let Some(HirExpr {
                    kind: HirExprKind::Array(elems),
                    ..
                }) = value
                {
                    let mut elem_locals = Vec::new();
                    for _ in elems {
                        elem_locals.push(alloc_local(locals));
                    }
                    Binding::Array(elem_locals)
                } else {
                    let idx = alloc_local(locals);
                    Binding::Scalar(idx)
                };
                locals.let_bindings.insert(stmt.span.start, binding);
            }
            HirStmtKind::If {
                then_block,
                else_block,
                ..
            } => {
                collect_block_locals(then_block, locals, module);
                if let Some(else_block) = else_block {
                    collect_block_locals(else_block, locals, module);
                }
            }
            HirStmtKind::While { body, .. } => {
                collect_block_locals(body, locals, module);
            }
            HirStmtKind::For { body, .. } => {
                let binding = ForBinding {
                    item: alloc_local(locals),
                    index: alloc_local(locals),
                };
                locals.for_bindings.insert(stmt.span.start, binding);
                collect_block_locals(body, locals, module);
            }
            HirStmtKind::Block(block) => collect_block_locals(block, locals, module),
            HirStmtKind::Return(_)
            | HirStmtKind::Break
            | HirStmtKind::Continue
            | HirStmtKind::Expr(_) => {}
        }
    }
}

fn alloc_local(locals: &mut FunctionLocals) -> u32 {
    let idx = locals.next_local;
    locals.next_local += 1;
    idx
}

fn emit_block(
    out: &mut Vec<u8>,
    block: &HirBlock,
    ctx: &FunctionContext<'_>,
    control: ControlLabels,
) -> Result<()> {
    ctx.enter_scope();
    for stmt in &block.stmts {
        emit_stmt(out, stmt, ctx, control)?;
    }
    ctx.exit_scope();
    Ok(())
}

fn emit_stmt(
    out: &mut Vec<u8>,
    stmt: &HirStmt,
    ctx: &FunctionContext<'_>,
    control: ControlLabels,
) -> Result<()> {
    match &stmt.kind {
        HirStmtKind::Let { name, value, .. } => {
            emit_let(out, stmt.span.start, name, value.as_ref(), ctx)
        }
        HirStmtKind::Return(value) => {
            match &ctx.return_layout {
                ReturnLayout::Scalar(WasmVal::I32) => {
                    out.push(0x41);
                    write_i32(out, 0);
                }
                ReturnLayout::Scalar(WasmVal::I64) => {
                    if let Some(value) = value {
                        emit_expr_i64(out, value, ctx)?;
                    } else {
                        emit_i64_const(out, 0);
                    }
                }
                ReturnLayout::Array(width) => {
                    if let Some(value) = value {
                        emit_array_values(out, value, *width, ctx)?;
                    } else {
                        for _ in 0..*width {
                            emit_i64_const(out, 0);
                        }
                    }
                }
                ReturnLayout::Struct(fields) => {
                    if let Some(value) = value {
                        emit_struct_values(out, value, fields, ctx)?;
                    } else {
                        for _ in fields {
                            emit_i64_const(out, 0);
                        }
                    }
                }
                ReturnLayout::Void => {}
            }
            out.push(0x0f);
            Ok(())
        }
        HirStmtKind::If {
            cond,
            then_block,
            else_block,
        } => {
            emit_condition(out, cond, ctx)?;
            out.push(0x04);
            out.push(0x40);
            let nested_control = control.nested_label();
            emit_block(out, then_block, ctx, nested_control)?;
            if let Some(else_block) = else_block {
                out.push(0x05);
                emit_block(out, else_block, ctx, nested_control)?;
            }
            out.push(0x0b);
            Ok(())
        }
        HirStmtKind::While { cond, body } => {
            out.push(0x02);
            out.push(0x40);
            out.push(0x03);
            out.push(0x40);
            emit_condition(out, cond, ctx)?;
            out.push(0x45);
            out.push(0x0d);
            write_u32(out, 1);
            emit_block(
                out,
                body,
                ctx,
                ControlLabels {
                    break_depth: Some(1),
                    continue_depth: Some(0),
                },
            )?;
            out.push(0x0c);
            write_u32(out, 0);
            out.push(0x0b);
            out.push(0x0b);
            Ok(())
        }
        HirStmtKind::Break => {
            let depth = control
                .break_depth
                .ok_or_else(|| anyhow!("break used outside of a loop"))?;
            out.push(0x0c);
            write_u32(out, depth);
            Ok(())
        }
        HirStmtKind::Continue => {
            let depth = control
                .continue_depth
                .ok_or_else(|| anyhow!("continue used outside of a loop"))?;
            out.push(0x0c);
            write_u32(out, depth);
            Ok(())
        }
        HirStmtKind::Block(block) => emit_block(out, block, ctx, control),
        HirStmtKind::Expr(expr) => emit_expr_stmt(out, expr, ctx),
        HirStmtKind::For { name, iter, body } => {
            emit_for(out, stmt.span.start, name, iter, body, ctx)
        }
    }
}

fn emit_for(
    out: &mut Vec<u8>,
    key: usize,
    name: &str,
    iter: &HirExpr,
    body: &HirBlock,
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    let binding = ctx
        .locals
        .for_bindings
        .get(&key)
        .copied()
        .ok_or_else(|| anyhow!("missing for-loop local plan for `{name}`"))?;
    match &iter.kind {
        HirExprKind::Name(iter_name) => match ctx.lookup_binding(iter_name) {
            Some(Binding::Array(elems)) => emit_array_for(out, key, name, &elems, body, ctx),
            Some(Binding::Scalar(range)) => emit_range_for(out, name, range, binding, body, ctx),
            Some(Binding::Struct(_)) => bail!("struct `{iter_name}` is not iterable"),
            None => bail!("unknown for-loop iterable `{iter_name}`"),
        },
        _ => bail!("CPU WASM codegen only supports for loops over named arrays and ranges"),
    }
}

fn emit_array_for(
    out: &mut Vec<u8>,
    key: usize,
    name: &str,
    elems: &[u32],
    body: &HirBlock,
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    ctx.enter_scope();
    let binding = ctx.bind_for(key, name)?;
    emit_i64_const(out, 0);
    emit_local_set(out, binding.index);

    emit_counted_for_loop(
        out,
        binding,
        |out| {
            emit_i64_const(out, elems.len() as i64);
            Ok(())
        },
        |out| {
            emit_array_index_from_locals(
                out,
                elems,
                |out| {
                    emit_local_get(out, binding.index);
                    Ok(())
                },
                ctx.locals.scratch,
            )?;
            emit_local_set(out, binding.item);
            Ok(())
        },
        body,
        ctx,
    )?;
    ctx.exit_scope();
    Ok(())
}

fn emit_range_for(
    out: &mut Vec<u8>,
    name: &str,
    range: u32,
    binding: ForBinding,
    body: &HirBlock,
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    ctx.enter_scope();
    ctx.scopes
        .borrow_mut()
        .last_mut()
        .ok_or_else(|| anyhow!("no active local scope"))?
        .insert(name.to_string(), Binding::Scalar(binding.item));
    emit_local_get(out, range);
    emit_pair_start_from_stack(out);
    emit_local_set(out, binding.index);

    emit_counted_for_loop(
        out,
        binding,
        |out| {
            emit_local_get(out, range);
            emit_pair_end_from_stack(out);
            Ok(())
        },
        |out| {
            emit_local_get(out, binding.index);
            emit_local_set(out, binding.item);
            Ok(())
        },
        body,
        ctx,
    )?;
    ctx.exit_scope();
    Ok(())
}

fn emit_counted_for_loop<End, Bind>(
    out: &mut Vec<u8>,
    binding: ForBinding,
    mut emit_end: End,
    mut emit_item: Bind,
    body: &HirBlock,
    ctx: &FunctionContext<'_>,
) -> Result<()>
where
    End: FnMut(&mut Vec<u8>) -> Result<()>,
    Bind: FnMut(&mut Vec<u8>) -> Result<()>,
{
    out.push(0x02);
    out.push(0x40);
    out.push(0x03);
    out.push(0x40);
    emit_local_get(out, binding.index);
    emit_end(out)?;
    out.push(0x59);
    out.push(0x0d);
    write_u32(out, 1);

    emit_item(out)?;

    out.push(0x02);
    out.push(0x40);
    emit_block(
        out,
        body,
        ctx,
        ControlLabels {
            break_depth: Some(2),
            continue_depth: Some(0),
        },
    )?;
    out.push(0x0b);

    emit_local_get(out, binding.index);
    emit_i64_const(out, 1);
    out.push(0x7c);
    emit_local_set(out, binding.index);
    out.push(0x0c);
    write_u32(out, 0);
    out.push(0x0b);
    out.push(0x0b);
    Ok(())
}

fn emit_pair_start_from_stack(out: &mut Vec<u8>) {
    out.push(0xa7);
    out.push(0xac);
}

fn emit_pair_end_from_stack(out: &mut Vec<u8>) {
    emit_i64_const(out, 32);
    out.push(0x87);
}

fn emit_u32_mask(out: &mut Vec<u8>) {
    emit_i64_const(out, 0xffff_ffff);
}

fn emit_i32_pair(
    out: &mut Vec<u8>,
    start: &HirExpr,
    end: &HirExpr,
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    emit_expr_i64(out, end, ctx)?;
    emit_u32_mask(out);
    out.push(0x83);
    emit_i64_const(out, 32);
    out.push(0x86);
    emit_expr_i64(out, start, ctx)?;
    emit_u32_mask(out);
    out.push(0x83);
    out.push(0x84);
    Ok(())
}

fn emit_struct_literal_i64(
    out: &mut Vec<u8>,
    fields: &[crate::hir::HirStructLiteralField],
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    let start = fields
        .iter()
        .find(|field| field.name == "start")
        .ok_or_else(|| anyhow!("CPU WASM codegen only supports start/end struct literals"))?;
    let end = fields
        .iter()
        .find(|field| field.name == "end")
        .ok_or_else(|| anyhow!("CPU WASM codegen only supports start/end struct literals"))?;
    emit_i32_pair(out, &start.value, &end.value, ctx)
}

fn emit_member_i64(
    out: &mut Vec<u8>,
    base: &HirExpr,
    member: &str,
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    if let HirExprKind::Name(name) = &base.kind
        && let Some(Binding::Struct(fields)) = ctx.lookup_binding(name)
    {
        let local = struct_field_local(&fields, member)
            .ok_or_else(|| anyhow!("unknown struct field `{member}`"))?;
        emit_local_get(out, local);
        return Ok(());
    }

    emit_expr_i64(out, base, ctx)?;
    match member {
        "start" => emit_pair_start_from_stack(out),
        "end" => emit_pair_end_from_stack(out),
        _ => bail!("CPU WASM codegen only supports start/end member access"),
    };
    Ok(())
}

fn emit_let(
    out: &mut Vec<u8>,
    key: usize,
    name: &str,
    value: Option<&HirExpr>,
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    match ctx.bind_let(key, name)? {
        Binding::Scalar(local) => {
            if let Some(value) = value {
                emit_expr_i64(out, value, ctx)?;
            } else {
                emit_i64_const(out, 0);
            }
            emit_local_set(out, local);
        }
        Binding::Array(locals) => {
            if let Some(value) = value {
                emit_array_to_locals(out, value, &locals, ctx)?;
            } else {
                for local in locals {
                    emit_i64_const(out, 0);
                    emit_local_set(out, local);
                }
            }
        }
        Binding::Struct(fields) => {
            if let Some(value) = value {
                emit_struct_to_locals(out, value, &fields, ctx)?;
            } else {
                for field in fields {
                    emit_i64_const(out, 0);
                    emit_local_set(out, field.local);
                }
            }
        }
    }
    Ok(())
}

fn emit_array_to_locals(
    out: &mut Vec<u8>,
    value: &HirExpr,
    locals: &[u32],
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    emit_array_values(out, value, locals.len(), ctx)?;
    for local in locals.iter().rev() {
        emit_local_set(out, *local);
    }
    Ok(())
}

fn emit_array_values(
    out: &mut Vec<u8>,
    value: &HirExpr,
    width: usize,
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    match &value.kind {
        HirExprKind::Name(name) => {
            let locals = match ctx.lookup_binding(name) {
                Some(Binding::Array(locals)) => locals,
                _ => bail!("array value `{name}` is not bound to an array"),
            };
            for idx in 0..width {
                if let Some(local) = locals.get(idx) {
                    emit_local_get(out, *local);
                } else {
                    emit_i64_const(out, 0);
                }
            }
            Ok(())
        }
        HirExprKind::Array(elems) => {
            for idx in 0..width {
                if let Some(elem) = elems.get(idx) {
                    emit_expr_i64(out, elem, ctx)?;
                } else {
                    emit_i64_const(out, 0);
                }
            }
            Ok(())
        }
        HirExprKind::Call { callee, args } => emit_call_array_values(out, callee, args, width, ctx),
        _ => bail!(
            "CPU WASM codegen only supports named arrays, literals, and array-return calls as array values"
        ),
    }
}

fn emit_struct_to_locals(
    out: &mut Vec<u8>,
    value: &HirExpr,
    locals: &[StructLocal],
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    match &value.kind {
        HirExprKind::StructLiteral { fields, .. } => {
            for target in locals {
                if let Some(field) = fields.iter().find(|field| field.name == target.name) {
                    emit_expr_i64(out, &field.value, ctx)?;
                } else {
                    emit_i64_const(out, 0);
                }
                emit_local_set(out, target.local);
            }
            Ok(())
        }
        HirExprKind::Name(name) => {
            let Some(Binding::Struct(source_fields)) = ctx.lookup_binding(name) else {
                bail!("struct value `{name}` is not bound to a struct");
            };
            for target in locals {
                let source = struct_field_local(&source_fields, &target.name)
                    .ok_or_else(|| anyhow!("unknown struct field `{}`", target.name))?;
                emit_local_get(out, source);
                emit_local_set(out, target.local);
            }
            Ok(())
        }
        HirExprKind::Call { callee, args } => {
            emit_call_struct_to_locals(out, callee, args, locals, ctx)
        }
        _ => bail!(
            "CPU WASM codegen only supports struct literals, named structs, and struct-return calls as struct values"
        ),
    }
}

fn emit_struct_values(
    out: &mut Vec<u8>,
    value: &HirExpr,
    fields: &[String],
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    match &value.kind {
        HirExprKind::StructLiteral {
            fields: literal_fields,
            ..
        } => {
            for name in fields {
                if let Some(field) = literal_fields.iter().find(|field| field.name == *name) {
                    emit_expr_i64(out, &field.value, ctx)?;
                } else {
                    emit_i64_const(out, 0);
                }
            }
            Ok(())
        }
        HirExprKind::Name(name) => {
            let Some(Binding::Struct(locals)) = ctx.lookup_binding(name) else {
                bail!("struct value `{name}` is not bound to a struct");
            };
            for field in fields {
                let local = struct_field_local(&locals, field)
                    .ok_or_else(|| anyhow!("unknown struct field `{field}`"))?;
                emit_local_get(out, local);
            }
            Ok(())
        }
        HirExprKind::Call { callee, args } => {
            emit_call_struct_values(out, callee, args, fields, ctx)
        }
        _ => bail!(
            "CPU WASM codegen only supports struct literals, named structs, and struct-return calls as struct values"
        ),
    }
}

fn emit_call_struct_to_locals(
    out: &mut Vec<u8>,
    callee: &HirExpr,
    args: &[HirExpr],
    locals: &[StructLocal],
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    let fields = locals
        .iter()
        .map(|field| field.name.clone())
        .collect::<Vec<_>>();
    emit_call_struct_values(out, callee, args, &fields, ctx)?;
    for field in fields.iter().rev() {
        let local = struct_field_local(locals, field)
            .ok_or_else(|| anyhow!("unknown struct field `{field}`"))?;
        emit_local_set(out, local);
    }
    Ok(())
}

fn emit_call_struct_values(
    out: &mut Vec<u8>,
    callee: &HirExpr,
    args: &[HirExpr],
    fields: &[String],
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    if let HirExprKind::Member { base, member } = &callee.kind
        && let Some(function) = ctx.module.defined_by_name(member)
    {
        let mut call_args = Vec::with_capacity(args.len() + 1);
        call_args.push(base.as_ref());
        call_args.extend(args.iter());
        emit_defined_call_struct_values(out, function, &call_args, fields, ctx)?;
        return Ok(());
    }

    let name = callee_name(callee).ok_or_else(|| anyhow!("unsupported call target"))?;
    if let Some(function) = ctx.module.defined_by_name(&name) {
        let call_args = args.iter().collect::<Vec<_>>();
        emit_defined_call_struct_values(out, function, &call_args, fields, ctx)?;
        return Ok(());
    }
    bail!("unknown struct-returning function `{name}`")
}

fn struct_field_local(fields: &[StructLocal], member: &str) -> Option<u32> {
    fields
        .iter()
        .find(|field| field.name == member)
        .map(|field| field.local)
}

fn emit_expr_stmt(out: &mut Vec<u8>, expr: &HirExpr, ctx: &FunctionContext<'_>) -> Result<()> {
    match &expr.kind {
        HirExprKind::Call { callee, args } if callee_name(callee).as_deref() == Some("print") => {
            let arg = args
                .first()
                .ok_or_else(|| anyhow!("print expects one argument"))?;
            emit_expr_i64(out, arg, ctx)?;
            out.push(0x10);
            write_u32(out, 0);
            Ok(())
        }
        HirExprKind::Call { callee, args } if callee_name(callee).as_deref() == Some("assert") => {
            let arg = args
                .first()
                .ok_or_else(|| anyhow!("assert expects one argument"))?;
            emit_assert(out, arg, ctx)
        }
        HirExprKind::Assign { .. } => emit_assignment(out, expr, ctx),
        HirExprKind::Call { .. } => {
            emit_expr_i64(out, expr, ctx)?;
            out.push(0x1a);
            Ok(())
        }
        _ => {
            emit_expr_i64(out, expr, ctx)?;
            out.push(0x1a);
            Ok(())
        }
    }
}

fn emit_assert(out: &mut Vec<u8>, expr: &HirExpr, ctx: &FunctionContext<'_>) -> Result<()> {
    emit_condition(out, expr, ctx)?;
    out.push(0x45);
    out.push(0x04);
    out.push(0x40);
    out.push(0x00);
    out.push(0x0b);
    Ok(())
}

fn emit_assignment(out: &mut Vec<u8>, expr: &HirExpr, ctx: &FunctionContext<'_>) -> Result<()> {
    let HirExprKind::Assign { op, target, value } = &expr.kind else {
        return Ok(());
    };
    let local = match &target.kind {
        HirExprKind::Name(name) => match ctx.lookup_binding(name) {
            Some(Binding::Scalar(local)) => local,
            _ => bail!("unknown scalar local `{name}`"),
        },
        HirExprKind::Member { base, member } => {
            let HirExprKind::Name(name) = &base.kind else {
                bail!("CPU WASM codegen only supports assignment to named struct fields");
            };
            let Some(Binding::Struct(fields)) = ctx.lookup_binding(name) else {
                bail!("unknown struct local `{name}`");
            };
            struct_field_local(&fields, member)
                .ok_or_else(|| anyhow!("unknown struct field `{member}`"))?
        }
        _ => bail!("CPU WASM codegen only supports assignment to locals and struct fields"),
    };
    if *op == HirAssignOp::Assign {
        emit_expr_i64(out, value, ctx)?;
    } else {
        emit_local_get(out, local);
        emit_expr_i64(out, value, ctx)?;
        emit_assign_op(out, *op)?;
    }
    emit_local_set(out, local);
    Ok(())
}

fn emit_expr_i64(out: &mut Vec<u8>, expr: &HirExpr, ctx: &FunctionContext<'_>) -> Result<()> {
    match &expr.kind {
        HirExprKind::Name(name) => {
            if let Some(value) = ctx.module.consts.get(name) {
                emit_i64_const(out, *value);
                return Ok(());
            }
            match ctx.lookup_binding(name) {
                Some(Binding::Scalar(local)) => emit_local_get(out, local),
                Some(Binding::Array(_)) => bail!("array `{name}` cannot be used as a scalar"),
                Some(Binding::Struct(_)) => bail!("struct `{name}` cannot be used as a scalar"),
                None => bail!("unknown name `{name}`"),
            }
            Ok(())
        }
        HirExprKind::Literal { kind, text } => {
            let value = literal_i64(*kind, text)?;
            emit_i64_const(out, value);
            Ok(())
        }
        HirExprKind::Unary { op, expr } => emit_unary_i64(out, *op, expr, ctx),
        HirExprKind::Binary { op, lhs, rhs } => emit_binary_i64(out, *op, lhs, rhs, ctx),
        HirExprKind::Assign { .. } => {
            emit_assignment(out, expr, ctx)?;
            emit_i64_const(out, 0);
            Ok(())
        }
        HirExprKind::Call { callee, args } => emit_call_i64(out, callee, args, ctx),
        HirExprKind::Index { base, index } => emit_index_i64(out, base, index, ctx),
        HirExprKind::StructLiteral { fields, .. } => emit_struct_literal_i64(out, fields, ctx),
        HirExprKind::Member { base, member } => emit_member_i64(out, base, member, ctx),
        HirExprKind::Array(_) | HirExprKind::Match { .. } => {
            bail!("unsupported CPU WASM expression: {:?}", expr.kind)
        }
    }
}

fn emit_unary_i64(
    out: &mut Vec<u8>,
    op: HirUnaryOp,
    expr: &HirExpr,
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    match op {
        HirUnaryOp::Neg => {
            emit_i64_const(out, 0);
            emit_expr_i64(out, expr, ctx)?;
            out.push(0x7d);
        }
        HirUnaryOp::Not => {
            emit_condition(out, expr, ctx)?;
            out.push(0x45);
            out.push(0xac);
        }
        HirUnaryOp::BitNot => {
            emit_expr_i64(out, expr, ctx)?;
            emit_i64_const(out, -1);
            out.push(0x85);
        }
        HirUnaryOp::Plus => emit_expr_i64(out, expr, ctx)?,
        HirUnaryOp::PreInc | HirUnaryOp::PreDec | HirUnaryOp::PostInc | HirUnaryOp::PostDec => {
            bail!("CPU WASM codegen does not support increment/decrement yet")
        }
    }
    Ok(())
}

fn emit_binary_i64(
    out: &mut Vec<u8>,
    op: HirBinaryOp,
    lhs: &HirExpr,
    rhs: &HirExpr,
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    match op {
        HirBinaryOp::And | HirBinaryOp::Or => {
            emit_condition(out, lhs, ctx)?;
            emit_condition(out, rhs, ctx)?;
            out.push(if op == HirBinaryOp::And { 0x71 } else { 0x72 });
            out.push(0xac);
        }
        HirBinaryOp::Lt
        | HirBinaryOp::Gt
        | HirBinaryOp::Le
        | HirBinaryOp::Ge
        | HirBinaryOp::Eq
        | HirBinaryOp::Ne => {
            emit_compare_i32(out, op, lhs, rhs, ctx)?;
            out.push(0xac);
        }
        _ => {
            emit_expr_i64(out, lhs, ctx)?;
            emit_expr_i64(out, rhs, ctx)?;
            emit_binary_op(out, op)?;
        }
    }
    Ok(())
}

fn emit_condition(out: &mut Vec<u8>, expr: &HirExpr, ctx: &FunctionContext<'_>) -> Result<()> {
    match &expr.kind {
        HirExprKind::Unary {
            op: HirUnaryOp::Not,
            expr,
        } => {
            emit_condition(out, expr, ctx)?;
            out.push(0x45);
        }
        HirExprKind::Binary { op, lhs, rhs }
            if matches!(
                op,
                HirBinaryOp::Lt
                    | HirBinaryOp::Gt
                    | HirBinaryOp::Le
                    | HirBinaryOp::Ge
                    | HirBinaryOp::Eq
                    | HirBinaryOp::Ne
            ) =>
        {
            emit_compare_i32(out, *op, lhs, rhs, ctx)?;
        }
        HirExprKind::Binary {
            op: HirBinaryOp::And,
            lhs,
            rhs,
        } => {
            emit_condition(out, lhs, ctx)?;
            emit_condition(out, rhs, ctx)?;
            out.push(0x71);
        }
        HirExprKind::Binary {
            op: HirBinaryOp::Or,
            lhs,
            rhs,
        } => {
            emit_condition(out, lhs, ctx)?;
            emit_condition(out, rhs, ctx)?;
            out.push(0x72);
        }
        _ => {
            emit_expr_i64(out, expr, ctx)?;
            emit_i64_const(out, 0);
            out.push(0x52);
        }
    }
    Ok(())
}

fn emit_compare_i32(
    out: &mut Vec<u8>,
    op: HirBinaryOp,
    lhs: &HirExpr,
    rhs: &HirExpr,
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    emit_expr_i64(out, lhs, ctx)?;
    emit_expr_i64(out, rhs, ctx)?;
    out.push(match op {
        HirBinaryOp::Eq => 0x51,
        HirBinaryOp::Ne => 0x52,
        HirBinaryOp::Lt => 0x53,
        HirBinaryOp::Gt => 0x55,
        HirBinaryOp::Le => 0x57,
        HirBinaryOp::Ge => 0x59,
        _ => bail!("not a comparison op"),
    });
    Ok(())
}

fn emit_call_i64(
    out: &mut Vec<u8>,
    callee: &HirExpr,
    args: &[HirExpr],
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    if let HirExprKind::Member { base, member } = &callee.kind
        && let Some(function) = ctx.module.defined_by_name(member)
    {
        let mut call_args = Vec::with_capacity(args.len() + 1);
        call_args.push(base.as_ref());
        call_args.extend(args.iter());
        emit_defined_call_i64(out, function, &call_args, ctx)?;
        return Ok(());
    }

    let name = callee_name(callee).ok_or_else(|| anyhow!("unsupported call target"))?;
    if name == "print" {
        let arg = args
            .first()
            .ok_or_else(|| anyhow!("print expects one argument"))?;
        emit_expr_i64(out, arg, ctx)?;
        out.push(0x10);
        write_u32(out, 0);
        emit_i64_const(out, 0);
        return Ok(());
    }
    if name == "assert" {
        let arg = args
            .first()
            .ok_or_else(|| anyhow!("assert expects one argument"))?;
        emit_assert(out, arg, ctx)?;
        emit_i64_const(out, 0);
        return Ok(());
    }
    if let Some(import) = ctx.module.import_by_name(&name) {
        for (idx, arg) in args.iter().enumerate() {
            emit_expr_i64(out, arg, ctx)?;
            if import.params.get(idx) == Some(&WasmVal::I32) {
                out.push(0xa7);
            }
        }
        out.push(0x10);
        write_u32(out, import.wasm_index);
        match import.ret {
            Some(WasmVal::I32) => out.push(0xac),
            Some(WasmVal::I64) => {}
            None => emit_i64_const(out, 0),
        }
        return Ok(());
    }
    if let Some(function) = ctx.module.defined_by_name(&name) {
        let call_args = args.iter().collect::<Vec<_>>();
        emit_defined_call_i64(out, function, &call_args, ctx)?;
        return Ok(());
    }
    bail!("unknown function `{name}`")
}

fn emit_call_array_values(
    out: &mut Vec<u8>,
    callee: &HirExpr,
    args: &[HirExpr],
    width: usize,
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    if let HirExprKind::Member { base, member } = &callee.kind
        && let Some(function) = ctx.module.defined_by_name(member)
    {
        let mut call_args = Vec::with_capacity(args.len() + 1);
        call_args.push(base.as_ref());
        call_args.extend(args.iter());
        emit_defined_call_array_values(out, function, &call_args, width, ctx)?;
        return Ok(());
    }

    let name = callee_name(callee).ok_or_else(|| anyhow!("unsupported call target"))?;
    if let Some(function) = ctx.module.defined_by_name(&name) {
        let call_args = args.iter().collect::<Vec<_>>();
        emit_defined_call_array_values(out, function, &call_args, width, ctx)?;
        return Ok(());
    }
    bail!("unknown array-returning function `{name}`")
}

fn emit_defined_call_i64(
    out: &mut Vec<u8>,
    function: &DefinedFn,
    args: &[&HirExpr],
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    emit_defined_call(out, function, args, ctx)?;
    match &function.ret {
        ReturnLayout::Void => emit_i64_const(out, 0),
        ReturnLayout::Scalar(WasmVal::I32) => out.push(0xac),
        ReturnLayout::Scalar(WasmVal::I64) => {}
        ReturnLayout::Array(_) => bail!(
            "array-returning function `{}` used as scalar",
            function.name
        ),
        ReturnLayout::Struct(_) => bail!(
            "struct-returning function `{}` used as scalar",
            function.name
        ),
    }
    Ok(())
}

fn emit_defined_call_array_values(
    out: &mut Vec<u8>,
    function: &DefinedFn,
    args: &[&HirExpr],
    width: usize,
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    let ReturnLayout::Array(actual_width) = &function.ret else {
        bail!("function `{}` does not return an array", function.name);
    };
    if *actual_width != width {
        bail!(
            "function `{}` returns array width {}, expected {}",
            function.name,
            actual_width,
            width
        );
    }
    emit_defined_call(out, function, args, ctx)
}

fn emit_defined_call_struct_values(
    out: &mut Vec<u8>,
    function: &DefinedFn,
    args: &[&HirExpr],
    fields: &[String],
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    let ReturnLayout::Struct(actual_fields) = &function.ret else {
        bail!("function `{}` does not return a struct", function.name);
    };
    if actual_fields != fields {
        bail!(
            "function `{}` returns struct fields {:?}, expected {:?}",
            function.name,
            actual_fields,
            fields
        );
    }
    emit_defined_call(out, function, args, ctx)
}

fn emit_defined_call(
    out: &mut Vec<u8>,
    function: &DefinedFn,
    args: &[&HirExpr],
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    if args.len() != function.params.len() {
        bail!(
            "function `{}` expects {} arguments, got {}",
            function.name,
            function.params.len(),
            args.len()
        );
    }
    for (param, arg) in function.params.iter().zip(args.iter()) {
        match &param.layout {
            ParamLayout::Scalar => emit_expr_i64(out, arg, ctx)?,
            ParamLayout::Array(width) => emit_array_argument(out, arg, *width, ctx)?,
            ParamLayout::Struct(fields) => emit_struct_argument(out, arg, fields, ctx)?,
        }
    }
    out.push(0x10);
    write_u32(out, function.wasm_index);
    Ok(())
}

fn emit_array_argument(
    out: &mut Vec<u8>,
    arg: &HirExpr,
    width: usize,
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    emit_array_values(out, arg, width, ctx)
}

fn emit_struct_argument(
    out: &mut Vec<u8>,
    arg: &HirExpr,
    fields: &[String],
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    emit_struct_values(out, arg, fields, ctx)
}

fn emit_index_i64(
    out: &mut Vec<u8>,
    base: &HirExpr,
    index: &HirExpr,
    ctx: &FunctionContext<'_>,
) -> Result<()> {
    let HirExprKind::Name(name) = &base.kind else {
        bail!("CPU WASM codegen only supports indexing named arrays");
    };
    let elems = match ctx.lookup_binding(name) {
        Some(Binding::Array(elems)) => elems,
        _ => bail!("unknown array `{name}`"),
    };
    emit_array_index_from_locals(
        out,
        &elems,
        |out| emit_expr_i64(out, index, ctx),
        ctx.locals.scratch,
    )?;
    Ok(())
}

fn emit_array_index_from_locals<F>(
    out: &mut Vec<u8>,
    elems: &[u32],
    mut emit_index: F,
    scratch: u32,
) -> Result<()>
where
    F: FnMut(&mut Vec<u8>) -> Result<()>,
{
    emit_i64_const(out, 0);
    emit_local_set(out, scratch);
    for (idx, local) in elems.iter().enumerate() {
        emit_index(out)?;
        emit_i64_const(out, idx as i64);
        out.push(0x51);
        out.push(0x04);
        out.push(0x40);
        emit_local_get(out, *local);
        emit_local_set(out, scratch);
        out.push(0x0b);
    }
    emit_local_get(out, scratch);
    Ok(())
}

fn emit_binary_op(out: &mut Vec<u8>, op: HirBinaryOp) -> Result<()> {
    out.push(match op {
        HirBinaryOp::Add => 0x7c,
        HirBinaryOp::Sub => 0x7d,
        HirBinaryOp::Mul => 0x7e,
        HirBinaryOp::Div => 0x7f,
        HirBinaryOp::Mod => 0x81,
        HirBinaryOp::BitAnd => 0x83,
        HirBinaryOp::BitOr => 0x84,
        HirBinaryOp::BitXor => 0x85,
        HirBinaryOp::Shl => 0x86,
        HirBinaryOp::Shr => 0x87,
        _ => bail!("unsupported arithmetic op"),
    });
    Ok(())
}

fn emit_assign_op(out: &mut Vec<u8>, op: HirAssignOp) -> Result<()> {
    out.push(match op {
        HirAssignOp::Add => 0x7c,
        HirAssignOp::Sub => 0x7d,
        HirAssignOp::Mul => 0x7e,
        HirAssignOp::Div => 0x7f,
        HirAssignOp::Mod => 0x81,
        HirAssignOp::BitAnd => 0x83,
        HirAssignOp::BitOr => 0x84,
        HirAssignOp::BitXor => 0x85,
        HirAssignOp::Shl => 0x86,
        HirAssignOp::Shr => 0x87,
        HirAssignOp::Assign => bail!("plain assignment handled separately"),
    });
    Ok(())
}

fn emit_local_get(out: &mut Vec<u8>, local: u32) {
    out.push(0x20);
    write_u32(out, local);
}

fn emit_local_set(out: &mut Vec<u8>, local: u32) {
    out.push(0x21);
    write_u32(out, local);
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

fn eval_const_expr(expr: &HirExpr, consts: &HashMap<String, i64>) -> Result<i64> {
    match &expr.kind {
        HirExprKind::Literal { kind, text } => literal_i64(*kind, text),
        HirExprKind::Name(name) => consts
            .get(name)
            .copied()
            .ok_or_else(|| anyhow!("unknown const `{name}`")),
        HirExprKind::Unary { op, expr } => {
            let value = eval_const_expr(expr, consts)?;
            Ok(match op {
                HirUnaryOp::Neg => -value,
                HirUnaryOp::Not => i64::from(value == 0),
                HirUnaryOp::BitNot => !value,
                HirUnaryOp::Plus => value,
                _ => bail!("unsupported const unary op"),
            })
        }
        HirExprKind::Binary { op, lhs, rhs } => {
            let lhs = eval_const_expr(lhs, consts)?;
            let rhs = eval_const_expr(rhs, consts)?;
            Ok(match op {
                HirBinaryOp::Add => lhs + rhs,
                HirBinaryOp::Sub => lhs - rhs,
                HirBinaryOp::Mul => lhs * rhs,
                HirBinaryOp::Div => lhs / rhs,
                HirBinaryOp::Mod => lhs % rhs,
                HirBinaryOp::Eq => i64::from(lhs == rhs),
                HirBinaryOp::Ne => i64::from(lhs != rhs),
                HirBinaryOp::Lt => i64::from(lhs < rhs),
                HirBinaryOp::Gt => i64::from(lhs > rhs),
                HirBinaryOp::Le => i64::from(lhs <= rhs),
                HirBinaryOp::Ge => i64::from(lhs >= rhs),
                HirBinaryOp::And => i64::from(lhs != 0 && rhs != 0),
                HirBinaryOp::Or => i64::from(lhs != 0 || rhs != 0),
                HirBinaryOp::BitAnd => lhs & rhs,
                HirBinaryOp::BitOr => lhs | rhs,
                HirBinaryOp::BitXor => lhs ^ rhs,
                HirBinaryOp::Shl => lhs << rhs,
                HirBinaryOp::Shr => lhs >> rhs,
            })
        }
        _ => bail!("unsupported const expression"),
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
            bail!("literal `{text}` is not supported in CPU WASM scalar codegen")
        }
    }
}

fn wasm_val_for_extern_type(ty: &HirType) -> Result<WasmVal> {
    Ok(match type_name(ty).as_deref() {
        Some("i64") => WasmVal::I64,
        Some("i32" | "u32" | "u8" | "bool") => WasmVal::I32,
        Some(other) => bail!("unsupported extern parameter type `{other}`"),
        None => bail!("unsupported extern parameter type"),
    })
}

fn wasm_return_for_extern_type(ty: &HirType) -> Result<Option<WasmVal>> {
    if matches!(ty.kind, HirTypeKind::Void) {
        return Ok(None);
    }
    wasm_val_for_extern_type(ty).map(Some)
}

fn type_name(ty: &HirType) -> Option<String> {
    match &ty.kind {
        HirTypeKind::Name(name) => Some(name.clone()),
        HirTypeKind::Generic { name, .. } => Some(name.clone()),
        _ => None,
    }
}

fn wasm_section(wasm: &mut Vec<u8>, id: u8, payload: Vec<u8>) {
    wasm.push(id);
    write_u32(wasm, payload.len() as u32);
    wasm.extend(payload);
}

fn write_name(out: &mut Vec<u8>, name: &str) {
    write_u32(out, name.len() as u32);
    out.extend_from_slice(name.as_bytes());
}

fn valtype_byte(ty: WasmVal) -> u8 {
    match ty {
        WasmVal::I32 => 0x7f,
        WasmVal::I64 => 0x7e,
    }
}

fn emit_i64_const(out: &mut Vec<u8>, value: i64) {
    out.push(0x42);
    write_i64(out, value);
}

fn write_u32(out: &mut Vec<u8>, mut value: u32) {
    loop {
        let mut byte = (value & 0x7f) as u8;
        value >>= 7;
        if value != 0 {
            byte |= 0x80;
        }
        out.push(byte);
        if value == 0 {
            break;
        }
    }
}

fn write_i32(out: &mut Vec<u8>, value: i32) {
    write_i64(out, value as i64);
}

fn write_i64(out: &mut Vec<u8>, mut value: i64) {
    loop {
        let byte = (value as u8) & 0x7f;
        value >>= 7;
        let done = (value == 0 && (byte & 0x40) == 0) || (value == -1 && (byte & 0x40) != 0);
        out.push(if done { byte } else { byte | 0x80 });
        if done {
            break;
        }
    }
}
