//! Untrusted Surface-to-Core proposal construction.
//!
//! This module is intentionally outside the trusted proof base.  It resolves
//! names and types and emits a Core proposal plus local evidence; Lean checks
//! the proposal independently before any proof consumes it.

use std::collections::HashMap;

use anyhow::{Context, Result, bail, ensure};

use crate::{
    artifact::{
        CoreNodeId,
        LexicalScopeIdentity,
        LexicalScopeKind,
        LoweringEvidence,
        LoweringRule,
        Namespace,
        ResolutionEvidence,
        TypeEvidence,
        TypeRule,
    },
    core::{
        CoreAssignOp,
        CoreBinaryOp,
        CoreConstant,
        CoreExpr,
        CoreExprValue,
        CoreFunction,
        CorePlace,
        CorePlaceValue,
        CorePointerWidth,
        CoreProgram,
        CoreScalarTy,
        CoreSignedIntTy,
        CoreStmt,
        CoreStmtValue,
        CoreStructDecl,
        CoreTarget,
        CoreTy,
        CoreUnaryOp,
        CoreValue,
        FunctionId,
        TypeId,
        VarId,
    },
    surface::{
        SpelledName,
        SurfaceArrayLength,
        SurfaceAssignOp,
        SurfaceBinaryOp,
        SurfaceExpr,
        SurfaceExprValue,
        SurfaceFile,
        SurfaceItem,
        SurfaceItemValue,
        SurfaceLiteral,
        SurfacePath,
        SurfaceStmt,
        SurfaceStmtValue,
        SurfaceTypeExpr,
        SurfaceTypeExprValue,
        SurfaceUnaryOp,
    },
};

#[derive(Debug)]
pub struct LoweredProgram {
    pub program: CoreProgram,
    pub resolutions: Vec<ResolutionEvidence>,
    pub types: Vec<TypeEvidence>,
    pub lowering: Vec<LoweringEvidence>,
}

#[derive(Debug, Clone)]
struct StructInfo {
    id: TypeId,
    declaration_unit: u32,
    declaration_node: u32,
    fields: Vec<(String, CoreTy)>,
}

#[derive(Debug, Clone)]
struct AliasInfo {
    module: String,
    declaration_unit: u32,
    declaration_node: u32,
    target: SurfaceTypeExpr,
}

#[derive(Debug, Clone)]
struct FunctionInfo {
    id: FunctionId,
    declaration_unit: u32,
    declaration_node: u32,
    parameters: Vec<CoreTy>,
    return_type: CoreTy,
}

#[derive(Debug, Clone)]
struct ConstantInfo {
    id: u32,
    declaration_unit: u32,
    declaration_node: u32,
    ty: CoreTy,
}

#[derive(Debug, Clone)]
struct LocalInfo {
    id: VarId,
    declaration_node: u32,
    declaration_scope: LexicalScopeIdentity,
    ty: CoreTy,
}

#[derive(Debug, Clone, Default)]
struct Locals {
    bindings: HashMap<String, LocalInfo>,
    scope_path: Vec<LexicalScopeIdentity>,
}

impl Locals {
    fn bind(&self, name: &SpelledName, info: LocalInfo) -> Self {
        let mut result = self.clone();
        result.bindings.insert(name.text.clone(), info);
        result
    }

    fn enter_scope(&self, kind: LexicalScopeKind, node: u32) -> Self {
        let mut result = self.clone();
        result
            .scope_path
            .insert(0, LexicalScopeIdentity { kind, node });
        result
    }

    fn path_to_declaration(&self, local: &LocalInfo) -> Result<Vec<LexicalScopeIdentity>> {
        let index = self
            .scope_path
            .iter()
            .position(|scope| *scope == local.declaration_scope)
            .context("local declaration scope is not an enclosing scope")?;
        Ok(self.scope_path[..=index].to_vec())
    }
}

#[derive(Debug)]
struct TypedExpr {
    core: CoreExpr,
    ty: CoreTy,
    type_evidence: u32,
    lowering_evidence: u32,
}

#[derive(Debug)]
struct TypedPlace {
    core: CorePlace,
    ty: CoreTy,
    type_evidence: u32,
    lowering_evidence: u32,
}

#[derive(Debug)]
struct LoweredStmt {
    core: CoreStmt,
    final_next_local: VarId,
    type_evidence: Option<u32>,
    lowering_evidence: u32,
}

struct Lowerer {
    unit_id: u32,
    module: String,
    aliases: HashMap<String, AliasInfo>,
    structs: HashMap<String, StructInfo>,
    functions: HashMap<String, FunctionInfo>,
    constants: HashMap<String, ConstantInfo>,
    next_core_node: CoreNodeId,
    resolutions: Vec<ResolutionEvidence>,
    types: Vec<TypeEvidence>,
    lowering: Vec<LoweringEvidence>,
}

impl Lowerer {
    fn builtin_type(name: &str) -> Option<CoreTy> {
        let signed = match name {
            "i8" => Some(CoreSignedIntTy::I8),
            "i16" => Some(CoreSignedIntTy::I16),
            "i32" => Some(CoreSignedIntTy::I32),
            "i64" => Some(CoreSignedIntTy::I64),
            "isize" => Some(CoreSignedIntTy::Isize),
            _ => None,
        };
        if let Some(ty) = signed {
            return Some(CoreTy::Scalar {
                ty: CoreScalarTy::Signed { ty },
            });
        }
        let unsigned = match name {
            "u8" => Some(crate::core::CoreUnsignedIntTy::U8),
            "u16" => Some(crate::core::CoreUnsignedIntTy::U16),
            "u32" => Some(crate::core::CoreUnsignedIntTy::U32),
            "u64" => Some(crate::core::CoreUnsignedIntTy::U64),
            "usize" => Some(crate::core::CoreUnsignedIntTy::Usize),
            _ => None,
        };
        if let Some(ty) = unsigned {
            return Some(CoreTy::Scalar {
                ty: CoreScalarTy::Unsigned { ty },
            });
        }
        let scalar = match name {
            "bool" => Some(CoreScalarTy::Bool),
            "f32" => Some(CoreScalarTy::F32),
            "f64" => Some(CoreScalarTy::F64),
            "char" => Some(CoreScalarTy::Char),
            "str" => Some(CoreScalarTy::String),
            "ptr" => Some(CoreScalarTy::RawPtr),
            _ => None,
        };
        scalar.map(|ty| CoreTy::Scalar { ty })
    }

    fn path_text(path: &SurfacePath) -> String {
        path.value
            .segments
            .iter()
            .map(|segment| segment.name.text.as_str())
            .collect::<Vec<_>>()
            .join("::")
    }

    fn qualify(module: &str, name: &str) -> String {
        if module.is_empty() {
            name.to_owned()
        } else {
            format!("{module}::{name}")
        }
    }

    fn qualified(&self, name: &str) -> String {
        Self::qualify(&self.module, name)
    }

    fn lookup_key_in<'b, T>(
        map: &'b HashMap<String, T>,
        module: &str,
        path: &SurfacePath,
    ) -> Option<&'b T> {
        let written = Self::path_text(path);
        if path.value.segments.len() == 1 {
            map.get(&Self::qualify(module, &written))
                .or_else(|| map.get(&written))
        } else {
            map.get(&written)
        }
    }

    fn lookup_key<'b, T>(&self, map: &'b HashMap<String, T>, path: &SurfacePath) -> Option<&'b T> {
        Self::lookup_key_in(map, &self.module, path)
    }

    fn resolve_type(&self, expression: &SurfaceTypeExpr) -> Result<CoreTy> {
        self.resolve_type_in(&self.module, expression)
    }

    fn resolve_type_in(&self, module: &str, expression: &SurfaceTypeExpr) -> Result<CoreTy> {
        match &expression.value {
            SurfaceTypeExprValue::Path { path } => {
                let text = Self::path_text(path);
                if path.value.segments.len() == 1 {
                    if let Some(ty) = Self::builtin_type(&text) {
                        return Ok(ty);
                    }
                }
                if let Some(alias) = Self::lookup_key_in(&self.aliases, module, path) {
                    ensure!(
                        alias.target.id != expression.id,
                        "recursive type alias {text:?} is not supported"
                    );
                    return self.resolve_type_in(&alias.module, &alias.target);
                }
                if let Some(declaration) = Self::lookup_key_in(&self.structs, module, path) {
                    return Ok(CoreTy::Structure { id: declaration.id });
                }
                bail!("unresolved type path {text:?}")
            }
            SurfaceTypeExprValue::Array { element, length } => {
                let length = match length {
                    SurfaceArrayLength::Literal { text, .. } => parse_nat(text)?,
                    SurfaceArrayLength::Parameter { name } => {
                        bail!(
                            "const-generic array length {:?} is not yet supported",
                            name.text
                        )
                    }
                };
                Ok(CoreTy::Array {
                    element: Box::new(self.resolve_type_in(module, element)?),
                    length,
                })
            }
            SurfaceTypeExprValue::Slice { element } => Ok(CoreTy::Slice {
                element: Box::new(self.resolve_type_in(module, element)?),
            }),
            SurfaceTypeExprValue::Reference { referent } => Ok(CoreTy::Reference {
                referent: Box::new(self.resolve_type_in(module, referent)?),
            }),
        }
    }

    fn record_type_resolutions_in(
        &mut self,
        module: &str,
        expression: &SurfaceTypeExpr,
        scope_path: &[LexicalScopeIdentity],
    ) -> Result<()> {
        match &expression.value {
            SurfaceTypeExprValue::Path { path } => {
                for segment in &path.value.segments {
                    for argument in &segment.arguments {
                        self.record_type_resolutions_in(module, argument, scope_path)?;
                    }
                }
                let text = Self::path_text(path);
                if path.value.segments.len() == 1 && Self::builtin_type(&text).is_some() {
                    return Ok(());
                }
                let (declaration_unit, declaration_node) = if let Some(alias) =
                    Self::lookup_key_in(&self.aliases, module, path)
                {
                    (alias.declaration_unit, alias.declaration_node)
                } else if let Some(declaration) = Self::lookup_key_in(&self.structs, module, path) {
                    (declaration.declaration_unit, declaration.declaration_node)
                } else {
                    bail!("unresolved type path {text:?}")
                };
                self.resolutions.push(ResolutionEvidence {
                    use_node: expression.id,
                    declaration_unit,
                    declaration_node,
                    namespace_tag: Namespace::Type,
                    scope_path: scope_path.to_vec(),
                });
            }
            SurfaceTypeExprValue::Array { element, .. }
            | SurfaceTypeExprValue::Slice { element }
            | SurfaceTypeExprValue::Reference { referent: element } => {
                self.record_type_resolutions_in(module, element, scope_path)?;
            }
        }
        Ok(())
    }

    fn record_type_resolutions(
        &mut self,
        expression: &SurfaceTypeExpr,
        scope_path: &[LexicalScopeIdentity],
    ) -> Result<()> {
        let module = self.module.clone();
        self.record_type_resolutions_in(&module, expression, scope_path)
    }

    fn new_node(&mut self) -> CoreNodeId {
        let id = self.next_core_node;
        self.next_core_node += 1;
        id
    }

    fn record_type(
        &mut self,
        surface_node: u32,
        ty: CoreTy,
        rule: TypeRule,
        premises: Vec<u32>,
    ) -> u32 {
        let id = self.types.len() as u32;
        self.types.push(TypeEvidence {
            surface_node,
            ty,
            rule,
            premises,
        });
        id
    }

    fn record_lowering(
        &mut self,
        surface_node: u32,
        core_node: CoreNodeId,
        rule: LoweringRule,
        premises: Vec<u32>,
    ) -> u32 {
        let id = self.lowering.len() as u32;
        self.lowering.push(LoweringEvidence {
            surface_node,
            core_node,
            rule,
            premises,
        });
        id
    }

    fn resolve_local(
        &mut self,
        expression: &SurfaceExpr,
        path: &SurfacePath,
        locals: &Locals,
    ) -> Result<TypedExpr> {
        ensure!(
            path.value.segments.len() == 1,
            "local path must have one segment"
        );
        let name = &path.value.segments[0].name.text;
        let local = locals
            .bindings
            .get(name)
            .with_context(|| format!("unresolved local {name:?}"))?
            .clone();
        self.resolutions.push(ResolutionEvidence {
            use_node: expression.id,
            declaration_unit: self.unit_id,
            declaration_node: local.declaration_node,
            namespace_tag: Namespace::Value,
            scope_path: locals.path_to_declaration(&local)?,
        });
        let core_node = self.new_node();
        let type_evidence =
            self.record_type(expression.id, local.ty.clone(), TypeRule::Local, vec![]);
        let lowering_evidence =
            self.record_lowering(expression.id, core_node, LoweringRule::Local, vec![]);
        Ok(TypedExpr {
            core: CoreExpr {
                id: core_node,
                value: CoreExprValue::Local { id: local.id },
            },
            ty: local.ty,
            type_evidence,
            lowering_evidence,
        })
    }

    fn literal(
        &mut self,
        expression: &SurfaceExpr,
        literal: &SurfaceLiteral,
        expected: Option<&CoreTy>,
    ) -> Result<TypedExpr> {
        let (value, ty) = match literal {
            SurfaceLiteral::Boolean { value } => (
                CoreValue::Boolean { value: *value },
                CoreTy::Scalar {
                    ty: CoreScalarTy::Bool,
                },
            ),
            SurfaceLiteral::Integer { text, .. } => {
                let ty = expected.cloned().unwrap_or(CoreTy::Scalar {
                    ty: CoreScalarTy::Signed {
                        ty: CoreSignedIntTy::I32,
                    },
                });
                let value = integer_value(text, &ty)?;
                (value, ty)
            }
            SurfaceLiteral::Float { text, .. } => {
                let ty = expected.cloned().unwrap_or(CoreTy::Scalar {
                    ty: CoreScalarTy::F32,
                });
                let value = match ty {
                    CoreTy::Scalar {
                        ty: CoreScalarTy::F32,
                    } => CoreValue::F32Bits {
                        bits: text
                            .parse::<f32>()
                            .with_context(|| format!("invalid f32 literal {text:?}"))?
                            .to_bits(),
                    },
                    CoreTy::Scalar {
                        ty: CoreScalarTy::F64,
                    } => CoreValue::F64Bits {
                        bits: text
                            .parse::<f64>()
                            .with_context(|| format!("invalid f64 literal {text:?}"))?
                            .to_bits(),
                    },
                    _ => bail!("float literal cannot have type {ty:?}"),
                };
                (value, ty)
            }
            SurfaceLiteral::String { text, .. } => (
                CoreValue::String {
                    value: decode_quoted(text, '"')?,
                },
                CoreTy::Scalar {
                    ty: CoreScalarTy::String,
                },
            ),
            SurfaceLiteral::Character { text, .. } => {
                let decoded = decode_quoted(text, '\'')?;
                let mut chars = decoded.chars();
                let value = chars.next().context("empty character literal")?;
                ensure!(
                    chars.next().is_none(),
                    "character literal has more than one scalar value"
                );
                (
                    CoreValue::Character {
                        value: value as u32,
                    },
                    CoreTy::Scalar {
                        ty: CoreScalarTy::Char,
                    },
                )
            }
        };
        if let Some(expected) = expected {
            ensure!(
                &ty == expected,
                "literal has type {ty:?}, expected {expected:?}"
            );
        }
        let core_node = self.new_node();
        let type_evidence = self.record_type(expression.id, ty.clone(), TypeRule::Literal, vec![]);
        let lowering_evidence =
            self.record_lowering(expression.id, core_node, LoweringRule::Literal, vec![]);
        Ok(TypedExpr {
            core: CoreExpr {
                id: core_node,
                value: CoreExprValue::Value { value },
            },
            ty,
            type_evidence,
            lowering_evidence,
        })
    }

    fn lower_expr(
        &mut self,
        expression: &SurfaceExpr,
        locals: &Locals,
        expected: Option<&CoreTy>,
    ) -> Result<TypedExpr> {
        let lowered = match &expression.value {
            SurfaceExprValue::Literal { literal } => {
                return self.literal(expression, literal, expected);
            }
            SurfaceExprValue::Path { path } => {
                if path.value.segments.len() == 1
                    && locals
                        .bindings
                        .contains_key(&path.value.segments[0].name.text)
                {
                    return self.resolve_local(expression, path, locals);
                }
                let declaration = self
                    .lookup_key(&self.constants, path)
                    .with_context(|| format!("unresolved value path {:?}", Self::path_text(path)))?
                    .clone();
                self.resolutions.push(ResolutionEvidence {
                    use_node: expression.id,
                    declaration_unit: declaration.declaration_unit,
                    declaration_node: declaration.declaration_node,
                    namespace_tag: Namespace::Value,
                    scope_path: locals.scope_path.clone(),
                });
                let node = self.new_node();
                let type_id = self.record_type(
                    expression.id,
                    declaration.ty.clone(),
                    TypeRule::Constant,
                    vec![],
                );
                let lower_id =
                    self.record_lowering(expression.id, node, LoweringRule::Local, vec![]);
                TypedExpr {
                    core: CoreExpr {
                        id: node,
                        value: CoreExprValue::Constant { id: declaration.id },
                    },
                    ty: declaration.ty,
                    type_evidence: type_id,
                    lowering_evidence: lower_id,
                }
            }
            SurfaceExprValue::Array { elements } => {
                let (element_type, expected_length) = match expected {
                    Some(CoreTy::Array { element, length }) => {
                        (Some((**element).clone()), Some(*length))
                    }
                    Some(CoreTy::Slice { element }) => (Some((**element).clone()), None),
                    _ => (None, None),
                };
                if let Some(length) = expected_length {
                    ensure!(length == elements.len() as u64, "array length mismatch");
                }
                let mut core_elements = Vec::with_capacity(elements.len());
                let mut type_premises = Vec::with_capacity(elements.len());
                let mut lower_premises = Vec::with_capacity(elements.len());
                let mut inferred_element = element_type;
                for element in elements {
                    let child = self.lower_expr(element, locals, inferred_element.as_ref())?;
                    if let Some(actual) = &inferred_element {
                        ensure!(&child.ty == actual, "array element type mismatch");
                    } else {
                        inferred_element = Some(child.ty.clone());
                    }
                    type_premises.push(child.type_evidence);
                    lower_premises.push(child.lowering_evidence);
                    core_elements.push(child.core);
                }
                let element_type = inferred_element
                    .context("empty array literal needs an expected element type")?;
                let array_type = CoreTy::Array {
                    element: Box::new(element_type.clone()),
                    length: core_elements.len() as u64,
                };
                let array_node = self.new_node();
                let array_type_id = self.record_type(
                    expression.id,
                    array_type.clone(),
                    TypeRule::Literal,
                    type_premises,
                );
                let array_lower_id = self.record_lowering(
                    expression.id,
                    array_node,
                    LoweringRule::Aggregate,
                    lower_premises,
                );
                let array = CoreExpr {
                    id: array_node,
                    value: CoreExprValue::Array {
                        element_type: element_type.clone(),
                        elements: core_elements,
                    },
                };
                if matches!(expected, Some(CoreTy::Slice { .. })) {
                    let slice_type = CoreTy::Slice {
                        element: Box::new(element_type.clone()),
                    };
                    let slice_node = self.new_node();
                    let type_id = self.record_type(
                        expression.id,
                        slice_type.clone(),
                        TypeRule::Literal,
                        vec![array_type_id],
                    );
                    let lower_id = self.record_lowering(
                        expression.id,
                        slice_node,
                        LoweringRule::Aggregate,
                        vec![array_lower_id],
                    );
                    TypedExpr {
                        core: CoreExpr {
                            id: slice_node,
                            value: CoreExprValue::ArrayToSlice {
                                element_type,
                                array: Box::new(array),
                            },
                        },
                        ty: slice_type,
                        type_evidence: type_id,
                        lowering_evidence: lower_id,
                    }
                } else {
                    TypedExpr {
                        core: array,
                        ty: array_type,
                        type_evidence: array_type_id,
                        lowering_evidence: array_lower_id,
                    }
                }
            }
            SurfaceExprValue::StructValue { path, fields } => {
                let declaration = self
                    .lookup_key(&self.structs, path)
                    .with_context(|| format!("unresolved struct path {:?}", Self::path_text(path)))?
                    .clone();
                self.resolutions.push(ResolutionEvidence {
                    use_node: expression.id,
                    declaration_unit: declaration.declaration_unit,
                    declaration_node: declaration.declaration_node,
                    namespace_tag: Namespace::Type,
                    scope_path: locals.scope_path.clone(),
                });
                ensure!(
                    fields.len() == declaration.fields.len(),
                    "struct literal field count mismatch"
                );
                let mut core_fields = Vec::with_capacity(fields.len());
                let mut type_premises = Vec::with_capacity(fields.len());
                let mut lower_premises = Vec::with_capacity(fields.len());
                for (name, field_type) in &declaration.fields {
                    let field = fields
                        .iter()
                        .find(|field| field.name.text == *name)
                        .with_context(|| format!("missing struct field {name:?}"))?;
                    let child = self.lower_expr(&field.value, locals, Some(field_type))?;
                    type_premises.push(child.type_evidence);
                    lower_premises.push(child.lowering_evidence);
                    core_fields.push(child.core);
                }
                let ty = CoreTy::Structure { id: declaration.id };
                let node = self.new_node();
                let type_id = self.record_type(
                    expression.id,
                    ty.clone(),
                    TypeRule::StructValue,
                    type_premises,
                );
                let lower_id = self.record_lowering(
                    expression.id,
                    node,
                    LoweringRule::Aggregate,
                    lower_premises,
                );
                TypedExpr {
                    core: CoreExpr {
                        id: node,
                        value: CoreExprValue::StructValue {
                            id: declaration.id,
                            fields: core_fields,
                        },
                    },
                    ty,
                    type_evidence: type_id,
                    lowering_evidence: lower_id,
                }
            }
            SurfaceExprValue::Unary { operator, operand } => {
                let input_expected = match operator {
                    SurfaceUnaryOp::LogicalNot => Some(CoreTy::Scalar {
                        ty: CoreScalarTy::Bool,
                    }),
                    _ => expected.cloned(),
                };
                let child = self.lower_expr(operand, locals, input_expected.as_ref())?;
                let ty = match operator {
                    SurfaceUnaryOp::LogicalNot => CoreTy::Scalar {
                        ty: CoreScalarTy::Bool,
                    },
                    SurfaceUnaryOp::Positive | SurfaceUnaryOp::Negative => {
                        ensure!(
                            is_arithmetic(&child.ty),
                            "arithmetic unary operand is not arithmetic"
                        );
                        child.ty.clone()
                    }
                };
                let op = match operator {
                    SurfaceUnaryOp::Positive => CoreUnaryOp::Positive,
                    SurfaceUnaryOp::Negative => CoreUnaryOp::Negate,
                    SurfaceUnaryOp::LogicalNot => CoreUnaryOp::LogicalNot,
                };
                let node = self.new_node();
                let type_id = self.record_type(
                    expression.id,
                    ty.clone(),
                    TypeRule::Unary,
                    vec![child.type_evidence],
                );
                let lower_id = self.record_lowering(
                    expression.id,
                    node,
                    LoweringRule::Unary,
                    vec![child.lowering_evidence],
                );
                TypedExpr {
                    core: CoreExpr {
                        id: node,
                        value: CoreExprValue::Unary {
                            op,
                            operand: Box::new(child.core),
                        },
                    },
                    ty,
                    type_evidence: type_id,
                    lowering_evidence: lower_id,
                }
            }
            SurfaceExprValue::Binary {
                operator,
                left,
                right,
            } => {
                let logical = matches!(
                    operator,
                    SurfaceBinaryOp::LogicalAnd | SurfaceBinaryOp::LogicalOr
                );
                let left_expected = logical.then_some(CoreTy::Scalar {
                    ty: CoreScalarTy::Bool,
                });
                let left = self.lower_expr(left, locals, left_expected.as_ref())?;
                let right = self.lower_expr(right, locals, Some(&left.ty))?;
                ensure!(left.ty == right.ty, "binary operand type mismatch");
                let ty = binary_result(*operator, &left.ty)?;
                let op = lower_binary(*operator);
                let node = self.new_node();
                let type_id = self.record_type(
                    expression.id,
                    ty.clone(),
                    TypeRule::Binary,
                    vec![left.type_evidence, right.type_evidence],
                );
                let lower_id = self.record_lowering(
                    expression.id,
                    node,
                    LoweringRule::Binary,
                    vec![left.lowering_evidence, right.lowering_evidence],
                );
                TypedExpr {
                    core: CoreExpr {
                        id: node,
                        value: CoreExprValue::Binary {
                            op,
                            left: Box::new(left.core),
                            right: Box::new(right.core),
                        },
                    },
                    ty,
                    type_evidence: type_id,
                    lowering_evidence: lower_id,
                }
            }
            SurfaceExprValue::Assign {
                operator,
                place,
                value,
            } => {
                let place = self.lower_place(place, locals)?;
                let value = self.lower_expr(value, locals, Some(&place.ty))?;
                let ty = CoreTy::Unit;
                let node = self.new_node();
                let type_id = self.record_type(
                    expression.id,
                    ty.clone(),
                    TypeRule::Assignment,
                    vec![place.type_evidence, value.type_evidence],
                );
                let lower_id = self.record_lowering(
                    expression.id,
                    node,
                    LoweringRule::Assignment,
                    vec![place.lowering_evidence, value.lowering_evidence],
                );
                TypedExpr {
                    core: CoreExpr {
                        id: node,
                        value: CoreExprValue::Assign {
                            op: lower_assign(*operator),
                            place: place.core,
                            value: Box::new(value.core),
                        },
                    },
                    ty,
                    type_evidence: type_id,
                    lowering_evidence: lower_id,
                }
            }
            SurfaceExprValue::Call { callee, arguments } => {
                let SurfaceExprValue::Path { path } = &callee.value else {
                    bail!("only direct path calls are currently supported")
                };
                let function = self
                    .lookup_key(&self.functions, path)
                    .with_context(|| {
                        format!("unresolved function path {:?}", Self::path_text(path))
                    })?
                    .clone();
                self.resolutions.push(ResolutionEvidence {
                    use_node: callee.id,
                    declaration_unit: function.declaration_unit,
                    declaration_node: function.declaration_node,
                    namespace_tag: Namespace::Value,
                    scope_path: locals.scope_path.clone(),
                });
                ensure!(
                    arguments.len() == function.parameters.len(),
                    "call argument count mismatch"
                );
                let mut core_arguments = Vec::with_capacity(arguments.len());
                let mut type_premises = Vec::with_capacity(arguments.len());
                let mut lower_premises = Vec::with_capacity(arguments.len());
                for (argument, parameter) in arguments.iter().zip(&function.parameters) {
                    let child = self.lower_expr(argument, locals, Some(parameter))?;
                    type_premises.push(child.type_evidence);
                    lower_premises.push(child.lowering_evidence);
                    core_arguments.push(child.core);
                }
                let node = self.new_node();
                let type_id = self.record_type(
                    expression.id,
                    function.return_type.clone(),
                    TypeRule::Call,
                    type_premises,
                );
                let lower_id =
                    self.record_lowering(expression.id, node, LoweringRule::Call, lower_premises);
                TypedExpr {
                    core: CoreExpr {
                        id: node,
                        value: CoreExprValue::Call {
                            function: function.id,
                            arguments: core_arguments,
                        },
                    },
                    ty: function.return_type,
                    type_evidence: type_id,
                    lowering_evidence: lower_id,
                }
            }
            SurfaceExprValue::Index { base, index } => {
                let base = self.lower_expr(base, locals, None)?;
                let element = match &base.ty {
                    CoreTy::Array { element, .. } | CoreTy::Slice { element } => {
                        (**element).clone()
                    }
                    _ => bail!("index base is not an array or slice"),
                };
                let index = self.lower_expr(index, locals, Some(&i32_type()))?;
                let node = self.new_node();
                let type_id = self.record_type(
                    expression.id,
                    element.clone(),
                    TypeRule::Index,
                    vec![base.type_evidence, index.type_evidence],
                );
                let lower_id = self.record_lowering(
                    expression.id,
                    node,
                    LoweringRule::Index,
                    vec![base.lowering_evidence, index.lowering_evidence],
                );
                TypedExpr {
                    core: CoreExpr {
                        id: node,
                        value: CoreExprValue::Index {
                            base: Box::new(base.core),
                            index: Box::new(index.core),
                        },
                    },
                    ty: element,
                    type_evidence: type_id,
                    lowering_evidence: lower_id,
                }
            }
            SurfaceExprValue::Member { base, name } => {
                let base = self.lower_expr(base, locals, None)?;
                let CoreTy::Structure { id } = base.ty else {
                    bail!("member base is not a structure")
                };
                let declaration = self
                    .structs
                    .values()
                    .find(|declaration| declaration.id == id)
                    .context("missing structure metadata")?
                    .clone();
                let (field, (_, ty)) = declaration
                    .fields
                    .iter()
                    .enumerate()
                    .find(|(_, (field, _))| field == &name.text)
                    .with_context(|| format!("unknown field {:?}", name.text))?;
                let ty = ty.clone();
                let node = self.new_node();
                let type_id = self.record_type(
                    expression.id,
                    ty.clone(),
                    TypeRule::Field,
                    vec![base.type_evidence],
                );
                let lower_id = self.record_lowering(
                    expression.id,
                    node,
                    LoweringRule::Field,
                    vec![base.lowering_evidence],
                );
                TypedExpr {
                    core: CoreExpr {
                        id: node,
                        value: CoreExprValue::Field {
                            base: Box::new(base.core),
                            field: field as u32,
                        },
                    },
                    ty,
                    type_evidence: type_id,
                    lowering_evidence: lower_id,
                }
            }
        };
        if let Some(expected) = expected {
            ensure!(
                &lowered.ty == expected,
                "expression has type {:?}, expected {expected:?}",
                lowered.ty
            );
        }
        Ok(lowered)
    }

    fn lower_place(&mut self, expression: &SurfaceExpr, locals: &Locals) -> Result<TypedPlace> {
        match &expression.value {
            SurfaceExprValue::Path { path } => {
                ensure!(
                    path.value.segments.len() == 1,
                    "place path must have one segment"
                );
                let name = &path.value.segments[0].name.text;
                let local = locals
                    .bindings
                    .get(name)
                    .with_context(|| format!("unresolved local place {name:?}"))?
                    .clone();
                self.resolutions.push(ResolutionEvidence {
                    use_node: expression.id,
                    declaration_unit: self.unit_id,
                    declaration_node: local.declaration_node,
                    namespace_tag: Namespace::Value,
                    scope_path: locals.path_to_declaration(&local)?,
                });
                let node = self.new_node();
                let type_id =
                    self.record_type(expression.id, local.ty.clone(), TypeRule::Local, vec![]);
                let lower_id =
                    self.record_lowering(expression.id, node, LoweringRule::Local, vec![]);
                Ok(TypedPlace {
                    core: CorePlace {
                        id: node,
                        value: CorePlaceValue::Local { id: local.id },
                    },
                    ty: local.ty,
                    type_evidence: type_id,
                    lowering_evidence: lower_id,
                })
            }
            SurfaceExprValue::Member { base, name } => {
                let base = self.lower_place(base, locals)?;
                let CoreTy::Structure { id } = base.ty else {
                    bail!("field place base is not a structure")
                };
                let declaration = self
                    .structs
                    .values()
                    .find(|declaration| declaration.id == id)
                    .context("missing structure metadata")?;
                let (field, (_, ty)) = declaration
                    .fields
                    .iter()
                    .enumerate()
                    .find(|(_, (field, _))| field == &name.text)
                    .with_context(|| format!("unknown field {:?}", name.text))?;
                let ty = ty.clone();
                let node = self.new_node();
                let type_id = self.record_type(
                    expression.id,
                    ty.clone(),
                    TypeRule::Field,
                    vec![base.type_evidence],
                );
                let lower_id = self.record_lowering(
                    expression.id,
                    node,
                    LoweringRule::Field,
                    vec![base.lowering_evidence],
                );
                Ok(TypedPlace {
                    core: CorePlace {
                        id: node,
                        value: CorePlaceValue::Field {
                            base: Box::new(base.core),
                            field: field as u32,
                        },
                    },
                    ty,
                    type_evidence: type_id,
                    lowering_evidence: lower_id,
                })
            }
            SurfaceExprValue::Index { base, index } => {
                let base = self.lower_place(base, locals)?;
                let element = match &base.ty {
                    CoreTy::Array { element, .. } | CoreTy::Slice { element } => {
                        (**element).clone()
                    }
                    _ => bail!("index place base is not an array or slice"),
                };
                let index = self.lower_expr(index, locals, Some(&i32_type()))?;
                let node = self.new_node();
                let type_id = self.record_type(
                    expression.id,
                    element.clone(),
                    TypeRule::Index,
                    vec![base.type_evidence, index.type_evidence],
                );
                let lower_id = self.record_lowering(
                    expression.id,
                    node,
                    LoweringRule::Index,
                    vec![base.lowering_evidence, index.lowering_evidence],
                );
                Ok(TypedPlace {
                    core: CorePlace {
                        id: node,
                        value: CorePlaceValue::Index {
                            base: Box::new(base.core),
                            index: Box::new(index.core),
                        },
                    },
                    ty: element,
                    type_evidence: type_id,
                    lowering_evidence: lower_id,
                })
            }
            _ => bail!("expression is not a mutable place"),
        }
    }

    fn skip(&mut self, anchor: u32) -> LoweredStmt {
        let node = self.new_node();
        let lowering_evidence = self.record_lowering(anchor, node, LoweringRule::Statement, vec![]);
        LoweredStmt {
            core: CoreStmt {
                id: node,
                value: CoreStmtValue::Skip,
            },
            final_next_local: 0,
            type_evidence: None,
            lowering_evidence,
        }
    }

    fn sequence(
        &mut self,
        anchor: u32,
        first: LoweredStmt,
        second: LoweredStmt,
        final_next_local: VarId,
    ) -> LoweredStmt {
        let node = self.new_node();
        let type_evidence = match (first.type_evidence, second.type_evidence) {
            (None, None) => None,
            (left, right) => Some(self.record_type(
                anchor,
                CoreTy::Unit,
                TypeRule::Branch,
                left.into_iter().chain(right).collect(),
            )),
        };
        let lowering_evidence = self.record_lowering(
            anchor,
            node,
            LoweringRule::ControlFlow,
            vec![first.lowering_evidence, second.lowering_evidence],
        );
        LoweredStmt {
            core: CoreStmt {
                id: node,
                value: CoreStmtValue::Sequence {
                    first: Box::new(first.core),
                    second: Box::new(second.core),
                },
            },
            final_next_local,
            type_evidence,
            lowering_evidence,
        }
    }

    fn lower_stmts(
        &mut self,
        statements: &[SurfaceStmt],
        locals: &Locals,
        return_type: &CoreTy,
        next_local: VarId,
        anchor: u32,
    ) -> Result<LoweredStmt> {
        let Some((head, tail)) = statements.split_first() else {
            let mut skip = self.skip(anchor);
            skip.final_next_local = next_local;
            return Ok(skip);
        };
        match &head.value {
            SurfaceStmtValue::LetLocal {
                name,
                type_annotation,
                initializer,
            } => {
                if let Some(ty) = type_annotation {
                    self.record_type_resolutions(ty, &locals.scope_path)?;
                }
                let annotated = type_annotation
                    .as_ref()
                    .map(|ty| self.resolve_type(ty))
                    .transpose()?;
                let (initializer, ty) = match initializer {
                    Some(initializer) => {
                        let lowered = self.lower_expr(initializer, locals, annotated.as_ref())?;
                        let ty = annotated.unwrap_or_else(|| lowered.ty.clone());
                        (Some(lowered), ty)
                    }
                    None => (
                        None,
                        annotated.context("uninitialized local requires a type annotation")?,
                    ),
                };
                let bound = locals
                    .enter_scope(LexicalScopeKind::AfterLocal, head.id)
                    .bind(
                        name,
                        LocalInfo {
                            id: next_local,
                            declaration_node: head.id,
                            declaration_scope: LexicalScopeIdentity {
                                kind: LexicalScopeKind::AfterLocal,
                                node: head.id,
                            },
                            ty: ty.clone(),
                        },
                    );
                let body = self.lower_stmts(tail, &bound, return_type, next_local + 1, anchor)?;
                let node = self.new_node();
                let mut type_premises = Vec::new();
                let mut lower_premises = Vec::new();
                if let Some(initializer) = &initializer {
                    type_premises.push(initializer.type_evidence);
                    lower_premises.push(initializer.lowering_evidence);
                }
                if let Some(body_type) = body.type_evidence {
                    type_premises.push(body_type);
                }
                lower_premises.push(body.lowering_evidence);
                let type_id =
                    self.record_type(head.id, CoreTy::Unit, TypeRule::Local, type_premises);
                let lower_id =
                    self.record_lowering(head.id, node, LoweringRule::Statement, lower_premises);
                let value = match initializer {
                    Some(initializer) => CoreStmtValue::LetLocal {
                        id: next_local,
                        ty,
                        initializer: initializer.core,
                        body: Box::new(body.core),
                    },
                    None => CoreStmtValue::LetUninitialized {
                        id: next_local,
                        ty,
                        body: Box::new(body.core),
                    },
                };
                Ok(LoweredStmt {
                    core: CoreStmt { id: node, value },
                    final_next_local: body.final_next_local,
                    type_evidence: Some(type_id),
                    lowering_evidence: lower_id,
                })
            }
            SurfaceStmtValue::ReturnValue { value } => {
                let value = value
                    .as_ref()
                    .map(|value| self.lower_expr(value, locals, Some(return_type)))
                    .transpose()?;
                let node = self.new_node();
                let type_id = self.record_type(
                    head.id,
                    CoreTy::Unit,
                    TypeRule::ReturnRule,
                    value
                        .as_ref()
                        .map(|value| vec![value.type_evidence])
                        .unwrap_or_default(),
                );
                let lower_id = self.record_lowering(
                    head.id,
                    node,
                    LoweringRule::Statement,
                    value
                        .as_ref()
                        .map(|value| vec![value.lowering_evidence])
                        .unwrap_or_default(),
                );
                let first = LoweredStmt {
                    core: CoreStmt {
                        id: node,
                        value: CoreStmtValue::ReturnValue {
                            value: value.map(|value| value.core),
                        },
                    },
                    final_next_local: next_local,
                    type_evidence: Some(type_id),
                    lowering_evidence: lower_id,
                };
                let rest = self.lower_stmts(tail, locals, return_type, next_local, anchor)?;
                let final_next = rest.final_next_local;
                Ok(self.sequence(head.id, first, rest, final_next))
            }
            SurfaceStmtValue::IfThenElse {
                condition,
                then_body,
                else_body,
            } => {
                let condition = self.lower_expr(
                    condition,
                    locals,
                    Some(&CoreTy::Scalar {
                        ty: CoreScalarTy::Bool,
                    }),
                )?;
                let then_body = self.lower_stmts(
                    then_body,
                    &locals.enter_scope(LexicalScopeKind::ThenBody, head.id),
                    return_type,
                    next_local,
                    head.id,
                )?;
                let else_body = self.lower_stmts(
                    else_body,
                    &locals.enter_scope(LexicalScopeKind::ElseBody, head.id),
                    return_type,
                    next_local,
                    head.id,
                )?;
                let branch_next = then_body.final_next_local.max(else_body.final_next_local);
                let node = self.new_node();
                let type_id = self.record_type(
                    head.id,
                    CoreTy::Unit,
                    TypeRule::Branch,
                    vec![condition.type_evidence],
                );
                let lower_id = self.record_lowering(
                    head.id,
                    node,
                    LoweringRule::ControlFlow,
                    vec![
                        condition.lowering_evidence,
                        then_body.lowering_evidence,
                        else_body.lowering_evidence,
                    ],
                );
                let first = LoweredStmt {
                    core: CoreStmt {
                        id: node,
                        value: CoreStmtValue::IfThenElse {
                            condition: condition.core,
                            then_branch: Box::new(then_body.core),
                            else_branch: Box::new(else_body.core),
                        },
                    },
                    final_next_local: branch_next,
                    type_evidence: Some(type_id),
                    lowering_evidence: lower_id,
                };
                let rest = self.lower_stmts(tail, locals, return_type, branch_next, anchor)?;
                let final_next = rest.final_next_local;
                Ok(self.sequence(head.id, first, rest, final_next))
            }
            SurfaceStmtValue::WhileLoop { condition, body } => {
                let condition = self.lower_expr(
                    condition,
                    locals,
                    Some(&CoreTy::Scalar {
                        ty: CoreScalarTy::Bool,
                    }),
                )?;
                let body = self.lower_stmts(
                    body,
                    &locals.enter_scope(LexicalScopeKind::LoopBody, head.id),
                    return_type,
                    next_local,
                    head.id,
                )?;
                let node = self.new_node();
                let type_id = self.record_type(
                    head.id,
                    CoreTy::Unit,
                    TypeRule::Loop,
                    vec![condition.type_evidence],
                );
                let lower_id = self.record_lowering(
                    head.id,
                    node,
                    LoweringRule::ControlFlow,
                    vec![condition.lowering_evidence, body.lowering_evidence],
                );
                let body_next = body.final_next_local;
                let first = LoweredStmt {
                    core: CoreStmt {
                        id: node,
                        value: CoreStmtValue::WhileLoop {
                            condition: condition.core,
                            body: Box::new(body.core),
                        },
                    },
                    final_next_local: body_next,
                    type_evidence: Some(type_id),
                    lowering_evidence: lower_id,
                };
                let rest = self.lower_stmts(tail, locals, return_type, body_next, anchor)?;
                let final_next = rest.final_next_local;
                Ok(self.sequence(head.id, first, rest, final_next))
            }
            SurfaceStmtValue::Block { body } => {
                let body = self.lower_stmts(
                    body,
                    &locals.enter_scope(LexicalScopeKind::BlockBody, head.id),
                    return_type,
                    next_local,
                    head.id,
                )?;
                let rest =
                    self.lower_stmts(tail, locals, return_type, body.final_next_local, anchor)?;
                let final_next = rest.final_next_local;
                Ok(self.sequence(head.id, body, rest, final_next))
            }
            SurfaceStmtValue::Expression { expression } => {
                let expression = self.lower_expr(expression, locals, None)?;
                let node = self.new_node();
                let lower_id = self.record_lowering(
                    head.id,
                    node,
                    LoweringRule::Statement,
                    vec![expression.lowering_evidence],
                );
                let first = LoweredStmt {
                    core: CoreStmt {
                        id: node,
                        value: CoreStmtValue::Expression {
                            expression: expression.core,
                        },
                    },
                    final_next_local: next_local,
                    type_evidence: Some(expression.type_evidence),
                    lowering_evidence: lower_id,
                };
                let rest = self.lower_stmts(tail, locals, return_type, next_local, anchor)?;
                let final_next = rest.final_next_local;
                Ok(self.sequence(head.id, first, rest, final_next))
            }
            SurfaceStmtValue::BreakLoop | SurfaceStmtValue::ContinueLoop => {
                let node = self.new_node();
                let lower_id = self.record_lowering(head.id, node, LoweringRule::Statement, vec![]);
                let value = if matches!(head.value, SurfaceStmtValue::BreakLoop) {
                    CoreStmtValue::BreakLoop
                } else {
                    CoreStmtValue::ContinueLoop
                };
                let first = LoweredStmt {
                    core: CoreStmt { id: node, value },
                    final_next_local: next_local,
                    type_evidence: None,
                    lowering_evidence: lower_id,
                };
                let rest = self.lower_stmts(tail, locals, return_type, next_local, anchor)?;
                let final_next = rest.final_next_local;
                Ok(self.sequence(head.id, first, rest, final_next))
            }
        }
    }

    fn lower_function(
        &mut self,
        item: &SurfaceItem,
        function: &crate::surface::SurfaceFunction,
    ) -> Result<CoreFunction> {
        let key = self.qualified(&function.name.text);
        let signature = self
            .functions
            .get(&key)
            .context("missing collected function signature")?
            .clone();
        let mut locals = Locals {
            scope_path: vec![LexicalScopeIdentity {
                kind: LexicalScopeKind::FunctionBody,
                node: item.id,
            }],
            ..Locals::default()
        };
        let mut parameters = Vec::with_capacity(function.parameters.len());
        for (index, (parameter, ty)) in function
            .parameters
            .iter()
            .zip(&signature.parameters)
            .enumerate()
        {
            let id = index as u32;
            locals = locals.bind(
                &parameter.name,
                LocalInfo {
                    id,
                    declaration_node: parameter.id,
                    declaration_scope: LexicalScopeIdentity {
                        kind: LexicalScopeKind::FunctionBody,
                        node: item.id,
                    },
                    ty: ty.clone(),
                },
            );
            parameters.push((id, ty.clone()));
        }
        let body = self.lower_stmts(
            &function.body,
            &locals,
            &signature.return_type,
            parameters.len() as u32,
            item.id,
        )?;
        Ok(CoreFunction {
            id: signature.id,
            parameters,
            return_type: signature.return_type,
            body: Some(body.core),
            external: None,
        })
    }
}

fn module_name(file: &SurfaceFile) -> Result<String> {
    file.value
        .items
        .iter()
        .find_map(|item| match &item.value {
            SurfaceItemValue::Module { path } => Some(Lowerer::path_text(path)),
            _ => None,
        })
        .context("source file has no module declaration")
}

#[derive(Debug, Clone, Default)]
struct LoweringCatalog {
    aliases: HashMap<String, AliasInfo>,
    structs: HashMap<String, StructInfo>,
    functions: HashMap<String, FunctionInfo>,
    constants: HashMap<String, ConstantInfo>,
}

impl LoweringCatalog {
    fn lowerer(&self, unit_id: u32, module: String, next_core_node: CoreNodeId) -> Lowerer {
        Lowerer {
            unit_id,
            module,
            aliases: self.aliases.clone(),
            structs: self.structs.clone(),
            functions: self.functions.clone(),
            constants: self.constants.clone(),
            next_core_node,
            resolutions: vec![],
            types: vec![],
            lowering: vec![],
        }
    }
}

fn collect_catalog(files: &[SurfaceFile]) -> Result<LoweringCatalog> {
    let mut catalog = LoweringCatalog::default();
    let mut next_struct = 0;

    for (unit_index, file) in files.iter().enumerate() {
        let unit_id = u32::try_from(unit_index).context("too many extraction units")?;
        let module = module_name(file)?;
        for item in &file.value.items {
            match &item.value {
                SurfaceItemValue::TypeAlias { name, target, .. } => {
                    let key = Lowerer::qualify(&module, &name.text);
                    ensure!(
                        catalog
                            .aliases
                            .insert(
                                key.clone(),
                                AliasInfo {
                                    module: module.clone(),
                                    declaration_unit: unit_id,
                                    declaration_node: item.id,
                                    target: target.clone(),
                                },
                            )
                            .is_none(),
                        "duplicate type alias {key:?}"
                    );
                }
                SurfaceItemValue::Structure { declaration } => {
                    let key = Lowerer::qualify(&module, &declaration.name.text);
                    ensure!(
                        catalog
                            .structs
                            .insert(
                                key.clone(),
                                StructInfo {
                                    id: next_struct,
                                    declaration_unit: unit_id,
                                    declaration_node: item.id,
                                    fields: vec![],
                                },
                            )
                            .is_none(),
                        "duplicate structure {key:?}"
                    );
                    next_struct += 1;
                }
                _ => {}
            }
        }
    }

    for (unit_index, file) in files.iter().enumerate() {
        let unit_id = u32::try_from(unit_index).context("too many extraction units")?;
        let module = module_name(file)?;
        let resolver = catalog.lowerer(unit_id, module.clone(), 0);
        for item in &file.value.items {
            if let SurfaceItemValue::Structure { declaration } = &item.value {
                let key = Lowerer::qualify(&module, &declaration.name.text);
                let fields = declaration
                    .fields
                    .iter()
                    .map(|field| {
                        Ok((
                            field.name.text.clone(),
                            resolver.resolve_type(&field.type_expression)?,
                        ))
                    })
                    .collect::<Result<Vec<_>>>()?;
                catalog
                    .structs
                    .get_mut(&key)
                    .context("missing collected structure")?
                    .fields = fields;
            }
        }
    }

    let mut next_function = 0;
    let mut next_constant = 0;
    for (unit_index, file) in files.iter().enumerate() {
        let unit_id = u32::try_from(unit_index).context("too many extraction units")?;
        let module = module_name(file)?;
        let resolver = catalog.lowerer(unit_id, module.clone(), 0);
        for item in &file.value.items {
            match &item.value {
                SurfaceItemValue::Function { function } => {
                    let key = Lowerer::qualify(&module, &function.name.text);
                    let parameters = function
                        .parameters
                        .iter()
                        .map(|parameter| resolver.resolve_type(&parameter.type_expression))
                        .collect::<Result<Vec<_>>>()?;
                    let return_type = function
                        .return_type
                        .as_ref()
                        .map(|ty| resolver.resolve_type(ty))
                        .transpose()?
                        .unwrap_or(CoreTy::Unit);
                    ensure!(
                        catalog
                            .functions
                            .insert(
                                key.clone(),
                                FunctionInfo {
                                    id: next_function,
                                    declaration_unit: unit_id,
                                    declaration_node: item.id,
                                    parameters,
                                    return_type,
                                },
                            )
                            .is_none(),
                        "duplicate function {key:?}"
                    );
                    next_function += 1;
                }
                SurfaceItemValue::Constant {
                    name,
                    type_expression,
                    ..
                } => {
                    let key = Lowerer::qualify(&module, &name.text);
                    let ty = resolver.resolve_type(type_expression)?;
                    ensure!(
                        catalog
                            .constants
                            .insert(
                                key.clone(),
                                ConstantInfo {
                                    id: next_constant,
                                    declaration_unit: unit_id,
                                    declaration_node: item.id,
                                    ty,
                                },
                            )
                            .is_none(),
                        "duplicate constant {key:?}"
                    );
                    next_constant += 1;
                }
                _ => {}
            }
        }
    }
    Ok(catalog)
}

fn lower_file_with_catalog(
    file: &SurfaceFile,
    unit_id: u32,
    catalog: &LoweringCatalog,
    next_core_node: CoreNodeId,
) -> Result<(LoweredProgram, CoreNodeId)> {
    let module = module_name(file)?;
    let mut lowerer = catalog.lowerer(unit_id, module, next_core_node);

    // Type names in declarations are resolved at module scope. Recording them
    // here keeps catalog construction free of evidence side effects and emits
    // each source use exactly once in the artifact for its own unit.
    for item in &file.value.items {
        match &item.value {
            SurfaceItemValue::Function { function } => {
                for parameter in &function.parameters {
                    lowerer.record_type_resolutions(&parameter.type_expression, &[])?;
                }
                if let Some(return_type) = &function.return_type {
                    lowerer.record_type_resolutions(return_type, &[])?;
                }
            }
            SurfaceItemValue::Constant {
                type_expression, ..
            } => lowerer.record_type_resolutions(type_expression, &[])?,
            SurfaceItemValue::TypeAlias { target, .. } => {
                lowerer.record_type_resolutions(target, &[])?;
            }
            SurfaceItemValue::Structure { declaration } => {
                for field in &declaration.fields {
                    lowerer.record_type_resolutions(&field.type_expression, &[])?;
                }
            }
            SurfaceItemValue::Module { .. } | SurfaceItemValue::ImportPath { .. } => {}
        }
    }

    let mut structures = Vec::new();
    for item in &file.value.items {
        if let SurfaceItemValue::Structure { declaration } = &item.value {
            let info = lowerer
                .structs
                .get(&lowerer.qualified(&declaration.name.text))
                .context("missing collected structure")?;
            structures.push(CoreStructDecl {
                id: info.id,
                fields: info.fields.iter().map(|(_, ty)| ty.clone()).collect(),
            });
        }
    }
    structures.sort_by_key(|structure| structure.id);

    let mut constants = Vec::new();
    for item in &file.value.items {
        if let SurfaceItemValue::Constant { name, value, .. } = &item.value {
            let info = lowerer
                .constants
                .get(&lowerer.qualified(&name.text))
                .context("missing collected constant")?
                .clone();
            let SurfaceExprValue::Literal { literal } = &value.value else {
                bail!("constant initializer must currently be a literal")
            };
            let value = literal_core_value(literal, &info.ty)?;
            constants.push(CoreConstant {
                id: info.id,
                ty: info.ty,
                value,
            });
        }
    }
    constants.sort_by_key(|constant| constant.id);

    let mut functions = Vec::new();
    for item in &file.value.items {
        if let SurfaceItemValue::Function { function } = &item.value {
            functions.push(lowerer.lower_function(item, function)?);
        }
    }
    functions.sort_by_key(|function| function.id);

    let final_next_core_node = lowerer.next_core_node;
    Ok((
        LoweredProgram {
            program: CoreProgram {
                target: CoreTarget {
                    pointer_width: CorePointerWidth::Bits64,
                },
                structures,
                enumerations: vec![],
                constants,
                functions,
            },
            resolutions: lowerer.resolutions,
            types: lowerer.types,
            lowering: lowerer.lowering,
        },
        final_next_core_node,
    ))
}

pub fn lower_files(files: &[SurfaceFile]) -> Result<Vec<LoweredProgram>> {
    let catalog = collect_catalog(files)?;
    let mut next_core_node = 0;
    let mut programs = Vec::with_capacity(files.len());
    for (unit_index, file) in files.iter().enumerate() {
        let unit_id = u32::try_from(unit_index).context("too many extraction units")?;
        let (program, final_next_core_node) =
            lower_file_with_catalog(file, unit_id, &catalog, next_core_node)?;
        programs.push(program);
        next_core_node = final_next_core_node;
    }
    Ok(programs)
}

pub fn lower_file(file: &SurfaceFile) -> Result<LoweredProgram> {
    lower_files(std::slice::from_ref(file))?
        .into_iter()
        .next()
        .context("one-file lowering produced no program")
}

fn i32_type() -> CoreTy {
    CoreTy::Scalar {
        ty: CoreScalarTy::Signed {
            ty: CoreSignedIntTy::I32,
        },
    }
}

fn parse_nat(text: &str) -> Result<u64> {
    text.replace('_', "")
        .parse()
        .with_context(|| format!("invalid natural number {text:?}"))
}

fn parse_int(text: &str) -> Result<i64> {
    text.replace('_', "")
        .parse()
        .with_context(|| format!("invalid integer {text:?}"))
}

fn integer_value(text: &str, ty: &CoreTy) -> Result<CoreValue> {
    match ty {
        CoreTy::Scalar {
            ty: CoreScalarTy::Signed { ty },
        } => Ok(CoreValue::Signed {
            ty: *ty,
            value: parse_int(text)?,
        }),
        CoreTy::Scalar {
            ty: CoreScalarTy::Unsigned { ty },
        } => Ok(CoreValue::Unsigned {
            ty: *ty,
            value: parse_nat(text)?,
        }),
        CoreTy::Scalar {
            ty: CoreScalarTy::RawPtr,
        } if parse_nat(text)? == 0 => Ok(CoreValue::Pointer { address: 0 }),
        _ => bail!("integer literal cannot have type {ty:?}"),
    }
}

fn literal_core_value(literal: &SurfaceLiteral, ty: &CoreTy) -> Result<CoreValue> {
    match literal {
        SurfaceLiteral::Boolean { value }
            if *ty
                == CoreTy::Scalar {
                    ty: CoreScalarTy::Bool,
                } =>
        {
            Ok(CoreValue::Boolean { value: *value })
        }
        SurfaceLiteral::Integer { text, .. } => integer_value(text, ty),
        SurfaceLiteral::Float { text, .. } => match ty {
            CoreTy::Scalar {
                ty: CoreScalarTy::F32,
            } => Ok(CoreValue::F32Bits {
                bits: text.parse::<f32>()?.to_bits(),
            }),
            CoreTy::Scalar {
                ty: CoreScalarTy::F64,
            } => Ok(CoreValue::F64Bits {
                bits: text.parse::<f64>()?.to_bits(),
            }),
            _ => bail!("float constant has non-float type"),
        },
        SurfaceLiteral::String { text, .. }
            if *ty
                == CoreTy::Scalar {
                    ty: CoreScalarTy::String,
                } =>
        {
            Ok(CoreValue::String {
                value: decode_quoted(text, '"')?,
            })
        }
        SurfaceLiteral::Character { text, .. }
            if *ty
                == CoreTy::Scalar {
                    ty: CoreScalarTy::Char,
                } =>
        {
            let value = decode_quoted(text, '\'')?;
            let mut chars = value.chars();
            let character = chars.next().context("empty character literal")?;
            ensure!(
                chars.next().is_none(),
                "character constant has multiple scalar values"
            );
            Ok(CoreValue::Character {
                value: character as u32,
            })
        }
        _ => bail!("literal does not match declared constant type"),
    }
}

fn decode_quoted(text: &str, delimiter: char) -> Result<String> {
    let content = text
        .strip_prefix(delimiter)
        .and_then(|text| text.strip_suffix(delimiter))
        .context("malformed quoted literal")?;
    let mut result = String::new();
    let mut chars = content.chars();
    while let Some(character) = chars.next() {
        if character != '\\' {
            result.push(character);
            continue;
        }
        let escaped = chars.next().context("unterminated escape")?;
        result.push(match escaped {
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            '\\' => '\\',
            '\'' => '\'',
            '"' => '"',
            '0' => '\0',
            _ => bail!("unsupported escape \\{escaped}"),
        });
    }
    Ok(result)
}

fn is_integer(ty: &CoreTy) -> bool {
    matches!(
        ty,
        CoreTy::Scalar {
            ty: CoreScalarTy::Signed { .. } | CoreScalarTy::Unsigned { .. } | CoreScalarTy::Char
        }
    )
}

fn is_arithmetic(ty: &CoreTy) -> bool {
    is_integer(ty)
        || matches!(
            ty,
            CoreTy::Scalar {
                ty: CoreScalarTy::F32 | CoreScalarTy::F64
            }
        )
}

fn binary_result(operator: SurfaceBinaryOp, operand: &CoreTy) -> Result<CoreTy> {
    use SurfaceBinaryOp::*;
    match operator {
        LogicalOr | LogicalAnd => {
            ensure!(
                *operand
                    == CoreTy::Scalar {
                        ty: CoreScalarTy::Bool
                    },
                "logical operand is not bool"
            );
            Ok(CoreTy::Scalar {
                ty: CoreScalarTy::Bool,
            })
        }
        Equal | NotEqual => {
            ensure!(
                matches!(operand, CoreTy::Scalar { .. }),
                "equality operand is not scalar"
            );
            Ok(CoreTy::Scalar {
                ty: CoreScalarTy::Bool,
            })
        }
        Less | Greater | LessEqual | GreaterEqual => {
            ensure!(is_arithmetic(operand), "ordered operand is not arithmetic");
            Ok(CoreTy::Scalar {
                ty: CoreScalarTy::Bool,
            })
        }
        Add | Subtract | Multiply | Divide => {
            ensure!(
                is_arithmetic(operand),
                "arithmetic operand has non-arithmetic type"
            );
            Ok(operand.clone())
        }
        Remainder | BitOr | BitXor | BitAnd | ShiftLeft | ShiftRight => {
            ensure!(is_integer(operand), "integer operator has non-integer type");
            Ok(operand.clone())
        }
    }
}

fn lower_binary(operator: SurfaceBinaryOp) -> CoreBinaryOp {
    match operator {
        SurfaceBinaryOp::LogicalOr => CoreBinaryOp::LogicalOr,
        SurfaceBinaryOp::LogicalAnd => CoreBinaryOp::LogicalAnd,
        SurfaceBinaryOp::BitOr => CoreBinaryOp::BitOr,
        SurfaceBinaryOp::BitXor => CoreBinaryOp::BitXor,
        SurfaceBinaryOp::BitAnd => CoreBinaryOp::BitAnd,
        SurfaceBinaryOp::Equal => CoreBinaryOp::Equal,
        SurfaceBinaryOp::NotEqual => CoreBinaryOp::NotEqual,
        SurfaceBinaryOp::Less => CoreBinaryOp::Less,
        SurfaceBinaryOp::Greater => CoreBinaryOp::Greater,
        SurfaceBinaryOp::LessEqual => CoreBinaryOp::LessEqual,
        SurfaceBinaryOp::GreaterEqual => CoreBinaryOp::GreaterEqual,
        SurfaceBinaryOp::ShiftLeft => CoreBinaryOp::ShiftLeft,
        SurfaceBinaryOp::ShiftRight => CoreBinaryOp::ShiftRight,
        SurfaceBinaryOp::Add => CoreBinaryOp::Add,
        SurfaceBinaryOp::Subtract => CoreBinaryOp::Subtract,
        SurfaceBinaryOp::Multiply => CoreBinaryOp::Multiply,
        SurfaceBinaryOp::Divide => CoreBinaryOp::Divide,
        SurfaceBinaryOp::Remainder => CoreBinaryOp::Remainder,
    }
}

fn lower_assign(operator: SurfaceAssignOp) -> CoreAssignOp {
    match operator {
        SurfaceAssignOp::Set => CoreAssignOp::Set,
        SurfaceAssignOp::Add => CoreAssignOp::Add,
        SurfaceAssignOp::Subtract => CoreAssignOp::Subtract,
        SurfaceAssignOp::Multiply => CoreAssignOp::Multiply,
        SurfaceAssignOp::Divide => CoreAssignOp::Divide,
        SurfaceAssignOp::Remainder => CoreAssignOp::Remainder,
        SurfaceAssignOp::BitXor => CoreAssignOp::BitXor,
        SurfaceAssignOp::ShiftLeft => CoreAssignOp::ShiftLeft,
        SurfaceAssignOp::ShiftRight => CoreAssignOp::ShiftRight,
        SurfaceAssignOp::BitAnd => CoreAssignOp::BitAnd,
        SurfaceAssignOp::BitOr => CoreAssignOp::BitOr,
    }
}
