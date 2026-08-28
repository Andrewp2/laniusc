use anyhow::{Context, Result, bail, ensure};
use serde::{Deserialize, Serialize};

use crate::artifact::{
    ParseChild,
    ParseNode,
    ParseNodeId,
    SourceFile,
    SurfaceNodeId,
    Token,
    TokenId,
};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Located<T> {
    pub id: SurfaceNodeId,
    pub parse_node: ParseNodeId,
    pub value: T,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SpelledName {
    pub token: TokenId,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SurfacePathSegment {
    pub id: SurfaceNodeId,
    pub parse_node: ParseNodeId,
    pub name: SpelledName,
    pub arguments: Vec<SurfaceTypeExpr>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SurfacePathValue {
    pub segments: Vec<SurfacePathSegment>,
}

pub type SurfacePath = Located<SurfacePathValue>;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SurfaceArrayLength {
    Literal { token: TokenId, text: String },
    Parameter { name: SpelledName },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SurfaceTypeExprValue {
    Path {
        path: SurfacePath,
    },
    Array {
        element: Box<SurfaceTypeExpr>,
        length: SurfaceArrayLength,
    },
    Slice {
        element: Box<SurfaceTypeExpr>,
    },
    Reference {
        referent: Box<SurfaceTypeExpr>,
    },
}

pub type SurfaceTypeExpr = Located<SurfaceTypeExprValue>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SurfaceUnaryOp {
    Positive,
    Negative,
    LogicalNot,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SurfaceBinaryOp {
    LogicalOr,
    LogicalAnd,
    BitOr,
    BitXor,
    BitAnd,
    Equal,
    NotEqual,
    Less,
    Greater,
    LessEqual,
    GreaterEqual,
    ShiftLeft,
    ShiftRight,
    Add,
    Subtract,
    Multiply,
    Divide,
    Remainder,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SurfaceAssignOp {
    Set,
    Add,
    Subtract,
    Multiply,
    Divide,
    Remainder,
    BitXor,
    ShiftLeft,
    ShiftRight,
    BitAnd,
    BitOr,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SurfaceLiteral {
    Integer { token: TokenId, text: String },
    Float { token: TokenId, text: String },
    String { token: TokenId, text: String },
    Character { token: TokenId, text: String },
    Boolean { value: bool },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SurfaceStructFieldValue {
    pub id: SurfaceNodeId,
    pub parse_node: ParseNodeId,
    pub name: SpelledName,
    pub value: SurfaceExpr,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SurfaceExprValue {
    Literal {
        literal: SurfaceLiteral,
    },
    Path {
        path: SurfacePath,
    },
    Array {
        elements: Vec<SurfaceExpr>,
    },
    StructValue {
        path: SurfacePath,
        fields: Vec<SurfaceStructFieldValue>,
    },
    Unary {
        operator: SurfaceUnaryOp,
        operand: Box<SurfaceExpr>,
    },
    Binary {
        operator: SurfaceBinaryOp,
        left: Box<SurfaceExpr>,
        right: Box<SurfaceExpr>,
    },
    Assign {
        operator: SurfaceAssignOp,
        place: Box<SurfaceExpr>,
        value: Box<SurfaceExpr>,
    },
    Call {
        callee: Box<SurfaceExpr>,
        arguments: Vec<SurfaceExpr>,
    },
    Index {
        base: Box<SurfaceExpr>,
        index: Box<SurfaceExpr>,
    },
    Member {
        base: Box<SurfaceExpr>,
        name: SpelledName,
    },
}

pub type SurfaceExpr = Located<SurfaceExprValue>;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SurfaceStmtValue {
    LetLocal {
        name: SpelledName,
        type_annotation: Option<SurfaceTypeExpr>,
        initializer: Option<SurfaceExpr>,
    },
    ReturnValue {
        value: Option<SurfaceExpr>,
    },
    IfThenElse {
        condition: SurfaceExpr,
        then_body: Vec<SurfaceStmt>,
        else_body: Vec<SurfaceStmt>,
    },
    WhileLoop {
        condition: SurfaceExpr,
        body: Vec<SurfaceStmt>,
    },
    Block {
        body: Vec<SurfaceStmt>,
    },
    Expression {
        expression: SurfaceExpr,
    },
    BreakLoop,
    ContinueLoop,
}

pub type SurfaceStmt = Located<SurfaceStmtValue>;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SurfaceParameter {
    pub id: SurfaceNodeId,
    pub parse_node: ParseNodeId,
    pub name: SpelledName,
    pub type_expression: SurfaceTypeExpr,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SurfaceFunction {
    pub name: SpelledName,
    pub is_public: bool,
    pub parameters: Vec<SurfaceParameter>,
    pub return_type: Option<SurfaceTypeExpr>,
    pub body: Vec<SurfaceStmt>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SurfaceStructField {
    pub id: SurfaceNodeId,
    pub parse_node: ParseNodeId,
    pub name: SpelledName,
    pub type_expression: SurfaceTypeExpr,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SurfaceStruct {
    pub name: SpelledName,
    pub is_public: bool,
    pub fields: Vec<SurfaceStructField>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SurfaceItemValue {
    Module {
        path: SurfacePath,
    },
    ImportPath {
        path: SurfacePath,
    },
    Function {
        function: SurfaceFunction,
    },
    Constant {
        name: SpelledName,
        is_public: bool,
        type_expression: SurfaceTypeExpr,
        value: SurfaceExpr,
    },
    TypeAlias {
        name: SpelledName,
        is_public: bool,
        target: SurfaceTypeExpr,
    },
    Structure {
        declaration: SurfaceStruct,
    },
}

pub type SurfaceItem = Located<SurfaceItemValue>;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SurfaceFileValue {
    pub items: Vec<SurfaceItem>,
}

pub type SurfaceFile = Located<SurfaceFileValue>;

struct Tree<'a> {
    source: &'a SourceFile,
    tokens: &'a [Token],
    nodes: &'a [ParseNode],
    next_surface_id: SurfaceNodeId,
}

impl<'a> Tree<'a> {
    fn node(&self, id: ParseNodeId) -> Result<&'a ParseNode> {
        self.nodes
            .get(id as usize)
            .with_context(|| format!("surface extraction references missing parse node {id}"))
    }

    fn production(&self, id: ParseNodeId) -> Result<u32> {
        Ok(self.node(id)?.production)
    }

    fn child_node(&self, id: ParseNodeId, index: usize) -> Result<ParseNodeId> {
        match self.node(id)?.children.get(index) {
            Some(ParseChild::Node(child)) => Ok(*child),
            Some(ParseChild::Token(_)) => bail!("parse node {id} child {index} is a token"),
            None => bail!("parse node {id} has no child {index}"),
        }
    }

    fn child_token(&self, id: ParseNodeId, index: usize) -> Result<TokenId> {
        match self.node(id)?.children.get(index) {
            Some(ParseChild::Token(token)) => Ok(*token),
            Some(ParseChild::Node(_)) => bail!("parse node {id} child {index} is a node"),
            None => bail!("parse node {id} has no child {index}"),
        }
    }

    fn token_text(&self, token_id: TokenId) -> Result<String> {
        let token = self
            .tokens
            .get(token_id as usize)
            .with_context(|| format!("surface extraction references missing token {token_id}"))?;
        ensure!(
            token.span.file == 0,
            "only one-file extraction is currently supported"
        );
        let bytes = self
            .source
            .bytes
            .get(token.span.start as usize..token.span.finish as usize)
            .with_context(|| format!("token {token_id} span is outside its source"))?;
        String::from_utf8(bytes.to_vec())
            .with_context(|| format!("token {token_id} is not valid UTF-8"))
    }

    fn name(&self, node: ParseNodeId, child: usize) -> Result<SpelledName> {
        let token = self.child_token(node, child)?;
        Ok(SpelledName {
            token,
            text: self.token_text(token)?,
        })
    }

    fn locate<T>(&mut self, parse_node: ParseNodeId, value: T) -> Located<T> {
        let id = self.next_id();
        Located {
            id,
            parse_node,
            value,
        }
    }

    fn next_id(&mut self) -> SurfaceNodeId {
        let id = self.next_surface_id;
        self.next_surface_id += 1;
        id
    }

    fn expect(&self, node: ParseNodeId, production: u32) -> Result<()> {
        let actual = self.production(node)?;
        ensure!(
            actual == production,
            "expected production {production}, found {actual} at parse node {node}"
        );
        Ok(())
    }

    fn unsupported<T>(&self, node: ParseNodeId, context: &str) -> Result<T> {
        bail!(
            "surface extraction does not support production {} at parse node {node} while lowering {context}",
            self.production(node)?
        )
    }

    fn path(&mut self, node: ParseNodeId) -> Result<SurfacePath> {
        self.expect(node, 47)?;
        let mut segments = vec![self.path_segment(self.child_node(node, 0)?)?];
        self.path_tail(self.child_node(node, 1)?, &mut segments)?;
        Ok(self.locate(node, SurfacePathValue { segments }))
    }

    fn path_segment(&mut self, node: ParseNodeId) -> Result<SurfacePathSegment> {
        let (name, arguments) = match self.production(node)? {
            48 => (self.name(node, 0)?, vec![]),
            49 => {
                let mut arguments = vec![self.type_expr(self.child_node(node, 2)?)?];
                self.path_type_arg_tail(self.child_node(node, 3)?, &mut arguments)?;
                (self.name(node, 0)?, arguments)
            }
            _ => return self.unsupported(node, "path segment"),
        };
        Ok(SurfacePathSegment {
            id: self.next_id(),
            parse_node: node,
            name,
            arguments,
        })
    }

    fn path_tail(
        &mut self,
        node: ParseNodeId,
        segments: &mut Vec<SurfacePathSegment>,
    ) -> Result<()> {
        match self.production(node)? {
            50 => {
                segments.push(self.path_segment(self.child_node(node, 2)?)?);
                self.path_tail(self.child_node(node, 3)?, segments)
            }
            51 => Ok(()),
            _ => self.unsupported(node, "path tail"),
        }
    }

    fn path_type_arg_tail(
        &mut self,
        node: ParseNodeId,
        arguments: &mut Vec<SurfaceTypeExpr>,
    ) -> Result<()> {
        match self.production(node)? {
            52 => self.path_type_arg_tail_after_comma(self.child_node(node, 1)?, arguments),
            53 => Ok(()),
            _ => self.unsupported(node, "path type arguments"),
        }
    }

    fn path_type_arg_tail_after_comma(
        &mut self,
        node: ParseNodeId,
        arguments: &mut Vec<SurfaceTypeExpr>,
    ) -> Result<()> {
        match self.production(node)? {
            54 => {
                arguments.push(self.type_expr(self.child_node(node, 0)?)?);
                self.path_type_arg_tail(self.child_node(node, 1)?, arguments)
            }
            55 => Ok(()),
            _ => self.unsupported(node, "path type arguments after comma"),
        }
    }

    fn type_expr(&mut self, node: ParseNodeId) -> Result<SurfaceTypeExpr> {
        let value = match self.production(node)? {
            69 => {
                let mut segments = self.type_path(self.child_node(node, 0)?)?;
                let (last_parse_node, last_name) = segments
                    .pop()
                    .context("type path unexpectedly has no segments")?;
                let mut path_segments = segments
                    .into_iter()
                    .map(|(parse_node, name)| SurfacePathSegment {
                        id: self.next_id(),
                        parse_node,
                        name,
                        arguments: vec![],
                    })
                    .collect::<Vec<_>>();
                let arguments = self.type_args_opt(self.child_node(node, 1)?)?;
                path_segments.push(SurfacePathSegment {
                    id: self.next_id(),
                    parse_node: last_parse_node,
                    name: last_name,
                    arguments,
                });
                let path = self.locate(
                    node,
                    SurfacePathValue {
                        segments: path_segments,
                    },
                );
                SurfaceTypeExprValue::Path { path }
            }
            70 => {
                let element = Box::new(self.type_expr(self.child_node(node, 1)?)?);
                let tail = self.child_node(node, 2)?;
                match self.production(tail)? {
                    283 => SurfaceTypeExprValue::Array {
                        element,
                        length: self.array_length(self.child_node(tail, 1)?)?,
                    },
                    284 => SurfaceTypeExprValue::Slice { element },
                    _ => return self.unsupported(tail, "array/slice type tail"),
                }
            }
            285 => SurfaceTypeExprValue::Reference {
                referent: Box::new(self.type_expr(self.child_node(node, 1)?)?),
            },
            _ => return self.unsupported(node, "type expression"),
        };
        Ok(self.locate(node, value))
    }

    fn type_path(&self, node: ParseNodeId) -> Result<Vec<(ParseNodeId, SpelledName)>> {
        self.expect(node, 56)?;
        let first = self.child_node(node, 0)?;
        let mut names = vec![(first, self.type_path_segment(first)?)];
        self.type_path_tail(self.child_node(node, 1)?, &mut names)?;
        Ok(names)
    }

    fn type_path_segment(&self, node: ParseNodeId) -> Result<SpelledName> {
        self.expect(node, 57)?;
        self.name(node, 0)
    }

    fn type_path_tail(
        &self,
        node: ParseNodeId,
        names: &mut Vec<(ParseNodeId, SpelledName)>,
    ) -> Result<()> {
        match self.production(node)? {
            58 => {
                let segment = self.child_node(node, 2)?;
                names.push((segment, self.type_path_segment(segment)?));
                self.type_path_tail(self.child_node(node, 3)?, names)
            }
            59 => Ok(()),
            _ => self.unsupported(node, "type path tail"),
        }
    }

    fn type_args_opt(&mut self, node: ParseNodeId) -> Result<Vec<SurfaceTypeExpr>> {
        match self.production(node)? {
            226 => Ok(vec![]),
            227 => {
                let mut arguments = vec![self.type_expr(self.child_node(node, 1)?)?];
                self.type_arg_tail(self.child_node(node, 2)?, &mut arguments)?;
                Ok(arguments)
            }
            _ => self.unsupported(node, "type arguments"),
        }
    }

    fn type_arg_tail(
        &mut self,
        node: ParseNodeId,
        arguments: &mut Vec<SurfaceTypeExpr>,
    ) -> Result<()> {
        match self.production(node)? {
            228 => self.type_arg_tail_after_comma(self.child_node(node, 1)?, arguments),
            229 => Ok(()),
            _ => self.unsupported(node, "type argument tail"),
        }
    }

    fn type_arg_tail_after_comma(
        &mut self,
        node: ParseNodeId,
        arguments: &mut Vec<SurfaceTypeExpr>,
    ) -> Result<()> {
        match self.production(node)? {
            230 => {
                arguments.push(self.type_expr(self.child_node(node, 0)?)?);
                self.type_arg_tail(self.child_node(node, 1)?, arguments)
            }
            231 => Ok(()),
            _ => self.unsupported(node, "type arguments after comma"),
        }
    }

    fn array_length(&self, node: ParseNodeId) -> Result<SurfaceArrayLength> {
        match self.production(node)? {
            286 => {
                let token = self.child_token(node, 0)?;
                Ok(SurfaceArrayLength::Literal {
                    token,
                    text: self.token_text(token)?,
                })
            }
            287 => Ok(SurfaceArrayLength::Parameter {
                name: self.name(node, 0)?,
            }),
            _ => self.unsupported(node, "array length"),
        }
    }

    fn expr(&mut self, node: ParseNodeId) -> Result<SurfaceExpr> {
        self.expect(node, 104)?;
        self.assign(self.child_node(node, 0)?)
    }

    fn assign(&mut self, node: ParseNodeId) -> Result<SurfaceExpr> {
        self.expect(node, 105)?;
        let left = self.binary_layer(self.child_node(node, 0)?, BinaryLayer::LogicalOr)?;
        let tail = self.child_node(node, 1)?;
        let Some(operator) = assign_operator(self.production(tail)?) else {
            self.expect(tail, 117)?;
            return Ok(left);
        };
        let right = self.assign(self.child_node(tail, 1)?)?;
        Ok(self.locate(
            tail,
            SurfaceExprValue::Assign {
                operator,
                place: Box::new(left),
                value: Box::new(right),
            },
        ))
    }

    fn binary_layer(&mut self, node: ParseNodeId, layer: BinaryLayer) -> Result<SurfaceExpr> {
        self.expect(node, layer.head_production())?;
        let mut result = if let Some(next) = layer.next() {
            self.binary_layer(self.child_node(node, 0)?, next)?
        } else {
            self.unary(self.child_node(node, 0)?)?
        };
        let mut tail = self.child_node(node, 1)?;
        loop {
            let production = self.production(tail)?;
            if production == layer.end_production() {
                return Ok(result);
            }
            let operator = layer.operator(production).with_context(|| {
                format!("production {production} is not a {:?} operator", layer)
            })?;
            let right_node = self.child_node(tail, 1)?;
            let right = if let Some(next) = layer.next() {
                self.binary_layer(right_node, next)?
            } else {
                self.unary(right_node)?
            };
            result = self.locate(
                tail,
                SurfaceExprValue::Binary {
                    operator,
                    left: Box::new(result),
                    right: Box::new(right),
                },
            );
            tail = self.child_node(tail, 2)?;
        }
    }

    fn unary(&mut self, node: ParseNodeId) -> Result<SurfaceExpr> {
        match self.production(node)? {
            production @ (156 | 157 | 158) => {
                let operator = match production {
                    156 => SurfaceUnaryOp::Positive,
                    157 => SurfaceUnaryOp::Negative,
                    158 => SurfaceUnaryOp::LogicalNot,
                    _ => unreachable!(),
                };
                let operand = self.unary(self.child_node(node, 1)?)?;
                Ok(self.locate(
                    node,
                    SurfaceExprValue::Unary {
                        operator,
                        operand: Box::new(operand),
                    },
                ))
            }
            159 => self.postfix(self.child_node(node, 0)?),
            _ => self.unsupported(node, "unary expression"),
        }
    }

    fn postfix(&mut self, node: ParseNodeId) -> Result<SurfaceExpr> {
        self.expect(node, 160)?;
        let mut result = self.primary(self.child_node(node, 0)?)?;
        let mut tail = self.child_node(node, 1)?;
        loop {
            match self.production(tail)? {
                161 => {
                    let arguments = self.arguments(self.child_node(tail, 1)?)?;
                    result = self.locate(
                        tail,
                        SurfaceExprValue::Call {
                            callee: Box::new(result),
                            arguments,
                        },
                    );
                    tail = self.child_node(tail, 3)?;
                }
                162 => {
                    let index = self.expr(self.child_node(tail, 1)?)?;
                    result = self.locate(
                        tail,
                        SurfaceExprValue::Index {
                            base: Box::new(result),
                            index: Box::new(index),
                        },
                    );
                    tail = self.child_node(tail, 3)?;
                }
                163 => {
                    result = self.locate(
                        tail,
                        SurfaceExprValue::Member {
                            base: Box::new(result),
                            name: self.name(tail, 1)?,
                        },
                    );
                    tail = self.child_node(tail, 2)?;
                }
                164 => return Ok(result),
                _ => return self.unsupported(tail, "postfix expression"),
            }
        }
    }

    fn arguments(&mut self, node: ParseNodeId) -> Result<Vec<SurfaceExpr>> {
        match self.production(node)? {
            165 => Ok(vec![]),
            166 => {
                let mut arguments = vec![self.expr(self.child_node(node, 0)?)?];
                self.argument_tail(self.child_node(node, 1)?, &mut arguments)?;
                Ok(arguments)
            }
            _ => self.unsupported(node, "argument list"),
        }
    }

    fn argument_tail(&mut self, node: ParseNodeId, arguments: &mut Vec<SurfaceExpr>) -> Result<()> {
        match self.production(node)? {
            167 => self.argument_tail_after_comma(self.child_node(node, 1)?, arguments),
            168 => Ok(()),
            _ => self.unsupported(node, "argument tail"),
        }
    }

    fn argument_tail_after_comma(
        &mut self,
        node: ParseNodeId,
        arguments: &mut Vec<SurfaceExpr>,
    ) -> Result<()> {
        match self.production(node)? {
            169 => {
                arguments.push(self.expr(self.child_node(node, 0)?)?);
                self.argument_tail(self.child_node(node, 1)?, arguments)
            }
            170 => Ok(()),
            _ => self.unsupported(node, "arguments after comma"),
        }
    }

    fn primary(&mut self, node: ParseNodeId) -> Result<SurfaceExpr> {
        let value = match self.production(node)? {
            171 => SurfaceExprValue::Array {
                elements: self.array_elements(self.child_node(node, 1)?)?,
            },
            172 => return self.expr(self.child_node(node, 1)?),
            173 => {
                let path = self.path(self.child_node(node, 0)?)?;
                let tail = self.child_node(node, 1)?;
                match self.production(tail)? {
                    274 => SurfaceExprValue::Path { path },
                    275 => SurfaceExprValue::StructValue {
                        path,
                        fields: self.struct_literal_fields(self.child_node(tail, 1)?)?,
                    },
                    _ => return self.unsupported(tail, "identifier primary tail"),
                }
            }
            production @ (175 | 176 | 177 | 178) => {
                let token = self.child_token(node, 0)?;
                let text = self.token_text(token)?;
                SurfaceExprValue::Literal {
                    literal: match production {
                        175 => SurfaceLiteral::Integer { token, text },
                        176 => SurfaceLiteral::Float { token, text },
                        177 => SurfaceLiteral::String { token, text },
                        178 => SurfaceLiteral::Character { token, text },
                        _ => unreachable!(),
                    },
                }
            }
            185 => SurfaceExprValue::Literal {
                literal: SurfaceLiteral::Boolean { value: true },
            },
            186 => SurfaceExprValue::Literal {
                literal: SurfaceLiteral::Boolean { value: false },
            },
            _ => return self.unsupported(node, "primary expression"),
        };
        Ok(self.locate(node, value))
    }

    fn array_elements(&mut self, node: ParseNodeId) -> Result<Vec<SurfaceExpr>> {
        match self.production(node)? {
            179 => Ok(vec![]),
            180 => {
                let mut elements = vec![self.expr(self.child_node(node, 0)?)?];
                self.array_element_tail(self.child_node(node, 1)?, &mut elements)?;
                Ok(elements)
            }
            _ => self.unsupported(node, "array elements"),
        }
    }

    fn array_element_tail(
        &mut self,
        node: ParseNodeId,
        elements: &mut Vec<SurfaceExpr>,
    ) -> Result<()> {
        match self.production(node)? {
            181 => self.array_element_tail_after_comma(self.child_node(node, 1)?, elements),
            182 => Ok(()),
            _ => self.unsupported(node, "array element tail"),
        }
    }

    fn array_element_tail_after_comma(
        &mut self,
        node: ParseNodeId,
        elements: &mut Vec<SurfaceExpr>,
    ) -> Result<()> {
        match self.production(node)? {
            183 => {
                elements.push(self.expr(self.child_node(node, 0)?)?);
                self.array_element_tail(self.child_node(node, 1)?, elements)
            }
            184 => Ok(()),
            _ => self.unsupported(node, "array elements after comma"),
        }
    }

    fn struct_literal_fields(&mut self, node: ParseNodeId) -> Result<Vec<SurfaceStructFieldValue>> {
        match self.production(node)? {
            276 => Ok(vec![]),
            277 => {
                let mut fields = vec![self.struct_literal_field(self.child_node(node, 0)?)?];
                self.struct_literal_field_tail(self.child_node(node, 1)?, &mut fields)?;
                Ok(fields)
            }
            _ => self.unsupported(node, "struct literal fields"),
        }
    }

    fn struct_literal_field(&mut self, node: ParseNodeId) -> Result<SurfaceStructFieldValue> {
        self.expect(node, 278)?;
        let name = self.name(node, 0)?;
        let value = self.expr(self.child_node(node, 2)?)?;
        Ok(SurfaceStructFieldValue {
            id: self.next_id(),
            parse_node: node,
            name,
            value,
        })
    }

    fn struct_literal_field_tail(
        &mut self,
        node: ParseNodeId,
        fields: &mut Vec<SurfaceStructFieldValue>,
    ) -> Result<()> {
        match self.production(node)? {
            279 => self.struct_literal_field_tail_after_comma(self.child_node(node, 1)?, fields),
            280 => Ok(()),
            _ => self.unsupported(node, "struct literal field tail"),
        }
    }

    fn struct_literal_field_tail_after_comma(
        &mut self,
        node: ParseNodeId,
        fields: &mut Vec<SurfaceStructFieldValue>,
    ) -> Result<()> {
        match self.production(node)? {
            281 => {
                fields.push(self.struct_literal_field(self.child_node(node, 0)?)?);
                self.struct_literal_field_tail(self.child_node(node, 1)?, fields)
            }
            282 => Ok(()),
            _ => self.unsupported(node, "struct literal fields after comma"),
        }
    }

    fn statements(&mut self, node: ParseNodeId) -> Result<Vec<SurfaceStmt>> {
        match self.production(node)? {
            73 => {
                let statement = self.statement(self.child_node(node, 0)?)?;
                let mut rest = self.statements(self.child_node(node, 1)?)?;
                rest.insert(0, statement);
                Ok(rest)
            }
            74 => Ok(vec![]),
            _ => self.unsupported(node, "statement list"),
        }
    }

    fn statement(&mut self, node: ParseNodeId) -> Result<SurfaceStmt> {
        let value = match self.production(node)? {
            75 => SurfaceStmtValue::LetLocal {
                name: self.name(node, 1)?,
                type_annotation: self.optional_type(self.child_node(node, 2)?)?,
                initializer: self.optional_initializer(self.child_node(node, 3)?)?,
            },
            76 => SurfaceStmtValue::ReturnValue {
                value: self.optional_return(self.child_node(node, 1)?)?,
            },
            77 => SurfaceStmtValue::IfThenElse {
                condition: self.expr(self.child_node(node, 2)?)?,
                then_body: self.block(self.child_node(node, 4)?)?,
                else_body: self.else_tail(self.child_node(node, 5)?)?,
            },
            80 => SurfaceStmtValue::WhileLoop {
                condition: self.expr(self.child_node(node, 2)?)?,
                body: self.block(self.child_node(node, 4)?)?,
            },
            82 => SurfaceStmtValue::BreakLoop,
            83 => SurfaceStmtValue::ContinueLoop,
            84 => SurfaceStmtValue::Block {
                body: self.block(self.child_node(node, 0)?)?,
            },
            85 => SurfaceStmtValue::Expression {
                expression: self.expr(self.child_node(node, 0)?)?,
            },
            _ => return self.unsupported(node, "statement"),
        };
        Ok(self.locate(node, value))
    }

    fn optional_type(&mut self, node: ParseNodeId) -> Result<Option<SurfaceTypeExpr>> {
        match self.production(node)? {
            86 => Ok(Some(self.type_expr(self.child_node(node, 1)?)?)),
            87 => Ok(None),
            _ => self.unsupported(node, "optional local type"),
        }
    }

    fn optional_initializer(&mut self, node: ParseNodeId) -> Result<Option<SurfaceExpr>> {
        match self.production(node)? {
            88 => Ok(Some(self.expr(self.child_node(node, 1)?)?)),
            89 => Ok(None),
            _ => self.unsupported(node, "optional local initializer"),
        }
    }

    fn optional_return(&mut self, node: ParseNodeId) -> Result<Option<SurfaceExpr>> {
        match self.production(node)? {
            90 => Ok(Some(self.expr(self.child_node(node, 0)?)?)),
            91 => Ok(None),
            _ => self.unsupported(node, "optional return value"),
        }
    }

    fn else_tail(&mut self, node: ParseNodeId) -> Result<Vec<SurfaceStmt>> {
        match self.production(node)? {
            78 => self.block(self.child_node(node, 1)?),
            79 => Ok(vec![]),
            _ => self.unsupported(node, "else clause"),
        }
    }

    fn block(&mut self, node: ParseNodeId) -> Result<Vec<SurfaceStmt>> {
        match self.production(node)? {
            12 | 14 => self.statements(self.child_node(node, 1)?),
            71 | 72 => self.statements(self.child_node(node, 1)?),
            _ => self.unsupported(node, "block"),
        }
    }

    fn parameters(&mut self, node: ParseNodeId) -> Result<Vec<SurfaceParameter>> {
        match self.production(node)? {
            60 => Ok(vec![]),
            61 => {
                let mut parameters = vec![self.parameter(self.child_node(node, 0)?)?];
                self.parameter_tail(self.child_node(node, 1)?, &mut parameters)?;
                Ok(parameters)
            }
            _ => self.unsupported(node, "parameter list"),
        }
    }

    fn parameter(&mut self, node: ParseNodeId) -> Result<SurfaceParameter> {
        self.expect(node, 62)?;
        let name = self.name(node, 0)?;
        let type_expression = self.type_expr(self.child_node(node, 2)?)?;
        Ok(SurfaceParameter {
            id: self.next_id(),
            parse_node: node,
            name,
            type_expression,
        })
    }

    fn parameter_tail(
        &mut self,
        node: ParseNodeId,
        parameters: &mut Vec<SurfaceParameter>,
    ) -> Result<()> {
        match self.production(node)? {
            67 => self.parameter_tail_after_comma(self.child_node(node, 1)?, parameters),
            68 => Ok(()),
            _ => self.unsupported(node, "parameter tail"),
        }
    }

    fn parameter_tail_after_comma(
        &mut self,
        node: ParseNodeId,
        parameters: &mut Vec<SurfaceParameter>,
    ) -> Result<()> {
        match self.production(node)? {
            288 => {
                parameters.push(self.parameter(self.child_node(node, 0)?)?);
                self.parameter_tail(self.child_node(node, 1)?, parameters)
            }
            289 => Ok(()),
            _ => self.unsupported(node, "parameters after comma"),
        }
    }

    fn function(&mut self, node: ParseNodeId, is_public: bool) -> Result<SurfaceFunction> {
        self.expect(node, 11)?;
        self.expect(self.child_node(node, 2)?, 232)?;
        self.expect(self.child_node(node, 7)?, 36)?;
        let name = self.name(node, 1)?;
        let parameters = self.parameters(self.child_node(node, 4)?)?;
        let return_type_node = self.child_node(node, 6)?;
        let return_type = match self.production(return_type_node)? {
            34 => Some(self.type_expr(self.child_node(return_type_node, 1)?)?),
            35 => None,
            _ => return self.unsupported(return_type_node, "function return type"),
        };
        let body = self.block(self.child_node(node, 8)?)?;
        Ok(SurfaceFunction {
            name,
            is_public,
            parameters,
            return_type,
            body,
        })
    }

    fn struct_declaration(&mut self, node: ParseNodeId, is_public: bool) -> Result<SurfaceStruct> {
        self.expect(node, 258)?;
        self.expect(self.child_node(node, 2)?, 232)?;
        self.expect(self.child_node(node, 3)?, 36)?;
        Ok(SurfaceStruct {
            name: self.name(node, 1)?,
            is_public,
            fields: self.struct_fields(self.child_node(node, 5)?)?,
        })
    }

    fn struct_fields(&mut self, node: ParseNodeId) -> Result<Vec<SurfaceStructField>> {
        match self.production(node)? {
            259 => Ok(vec![]),
            260 => {
                let mut fields = vec![self.struct_field(self.child_node(node, 0)?)?];
                self.struct_field_tail(self.child_node(node, 1)?, &mut fields)?;
                Ok(fields)
            }
            _ => self.unsupported(node, "struct fields"),
        }
    }

    fn struct_field(&mut self, node: ParseNodeId) -> Result<SurfaceStructField> {
        self.expect(node, 261)?;
        let name = self.name(node, 0)?;
        let type_expression = self.type_expr(self.child_node(node, 2)?)?;
        Ok(SurfaceStructField {
            id: self.next_id(),
            parse_node: node,
            name,
            type_expression,
        })
    }

    fn struct_field_tail(
        &mut self,
        node: ParseNodeId,
        fields: &mut Vec<SurfaceStructField>,
    ) -> Result<()> {
        match self.production(node)? {
            262 => self.struct_field_tail_after_comma(self.child_node(node, 1)?, fields),
            263 => Ok(()),
            _ => self.unsupported(node, "struct field tail"),
        }
    }

    fn struct_field_tail_after_comma(
        &mut self,
        node: ParseNodeId,
        fields: &mut Vec<SurfaceStructField>,
    ) -> Result<()> {
        match self.production(node)? {
            264 => {
                fields.push(self.struct_field(self.child_node(node, 0)?)?);
                self.struct_field_tail(self.child_node(node, 1)?, fields)
            }
            265 => Ok(()),
            _ => self.unsupported(node, "struct fields after comma"),
        }
    }

    fn item(&mut self, node: ParseNodeId) -> Result<SurfaceItem> {
        let (is_public, production_node, production) = match self.production(node)? {
            3 => {
                let public_node = self.child_node(node, 1)?;
                let inner = self.child_node(public_node, 0)?;
                (true, inner, self.production(public_node)?)
            }
            production => (false, self.child_node(node, 0)?, production),
        };
        let value = match production {
            4 | 266 => SurfaceItemValue::Function {
                function: self.function(production_node, is_public)?,
            },
            6 => {
                self.expect(production_node, 43)?;
                let tail = self.child_node(production_node, 1)?;
                self.expect(tail, 44)?;
                SurfaceItemValue::ImportPath {
                    path: self.path(self.child_node(tail, 0)?)?,
                }
            }
            7 => {
                self.expect(production_node, 46)?;
                SurfaceItemValue::Module {
                    path: self.path(self.child_node(production_node, 1)?)?,
                }
            }
            8 | 269 => {
                self.expect(production_node, 16)?;
                self.expect(self.child_node(production_node, 2)?, 232)?;
                self.expect(self.child_node(production_node, 3)?, 36)?;
                SurfaceItemValue::TypeAlias {
                    name: self.name(production_node, 1)?,
                    is_public,
                    target: self.type_expr(self.child_node(production_node, 5)?)?,
                }
            }
            207 | 268 => {
                self.expect(production_node, 208)?;
                SurfaceItemValue::Constant {
                    name: self.name(production_node, 1)?,
                    is_public,
                    type_expression: self.type_expr(self.child_node(production_node, 3)?)?,
                    value: self.expr(self.child_node(production_node, 5)?)?,
                }
            }
            257 | 271 => SurfaceItemValue::Structure {
                declaration: self.struct_declaration(production_node, is_public)?,
            },
            _ => return self.unsupported(node, "top-level item"),
        };
        Ok(self.locate(node, value))
    }

    fn items(&mut self, node: ParseNodeId) -> Result<Vec<SurfaceItem>> {
        match self.production(node)? {
            1 => {
                let item = self.item(self.child_node(node, 0)?)?;
                let mut rest = self.items(self.child_node(node, 1)?)?;
                rest.insert(0, item);
                Ok(rest)
            }
            2 => Ok(vec![]),
            _ => self.unsupported(node, "item list"),
        }
    }

    fn file(&mut self, root: ParseNodeId) -> Result<SurfaceFile> {
        self.expect(root, 0)?;
        let items = self.items(self.child_node(root, 0)?)?;
        Ok(self.locate(root, SurfaceFileValue { items }))
    }
}

#[derive(Debug, Clone, Copy)]
enum BinaryLayer {
    LogicalOr,
    LogicalAnd,
    BitOr,
    BitXor,
    BitAnd,
    Equality,
    Comparison,
    Shift,
    Additive,
    Multiplicative,
}

impl BinaryLayer {
    fn head_production(self) -> u32 {
        match self {
            Self::LogicalOr => 118,
            Self::LogicalAnd => 121,
            Self::BitOr => 124,
            Self::BitXor => 127,
            Self::BitAnd => 130,
            Self::Equality => 133,
            Self::Comparison => 137,
            Self::Shift => 143,
            Self::Additive => 147,
            Self::Multiplicative => 151,
        }
    }

    fn end_production(self) -> u32 {
        match self {
            Self::LogicalOr => 120,
            Self::LogicalAnd => 123,
            Self::BitOr => 126,
            Self::BitXor => 129,
            Self::BitAnd => 132,
            Self::Equality => 136,
            Self::Comparison => 142,
            Self::Shift => 146,
            Self::Additive => 150,
            Self::Multiplicative => 155,
        }
    }

    fn next(self) -> Option<Self> {
        Some(match self {
            Self::LogicalOr => Self::LogicalAnd,
            Self::LogicalAnd => Self::BitOr,
            Self::BitOr => Self::BitXor,
            Self::BitXor => Self::BitAnd,
            Self::BitAnd => Self::Equality,
            Self::Equality => Self::Comparison,
            Self::Comparison => Self::Shift,
            Self::Shift => Self::Additive,
            Self::Additive => Self::Multiplicative,
            Self::Multiplicative => return None,
        })
    }

    fn operator(self, production: u32) -> Option<SurfaceBinaryOp> {
        Some(match (self, production) {
            (Self::LogicalOr, 119) => SurfaceBinaryOp::LogicalOr,
            (Self::LogicalAnd, 122) => SurfaceBinaryOp::LogicalAnd,
            (Self::BitOr, 125) => SurfaceBinaryOp::BitOr,
            (Self::BitXor, 128) => SurfaceBinaryOp::BitXor,
            (Self::BitAnd, 131) => SurfaceBinaryOp::BitAnd,
            (Self::Equality, 134) => SurfaceBinaryOp::Equal,
            (Self::Equality, 135) => SurfaceBinaryOp::NotEqual,
            (Self::Comparison, 138) => SurfaceBinaryOp::Less,
            (Self::Comparison, 139) => SurfaceBinaryOp::Greater,
            (Self::Comparison, 140) => SurfaceBinaryOp::LessEqual,
            (Self::Comparison, 141) => SurfaceBinaryOp::GreaterEqual,
            (Self::Shift, 144) => SurfaceBinaryOp::ShiftLeft,
            (Self::Shift, 145) => SurfaceBinaryOp::ShiftRight,
            (Self::Additive, 148) => SurfaceBinaryOp::Add,
            (Self::Additive, 149) => SurfaceBinaryOp::Subtract,
            (Self::Multiplicative, 152) => SurfaceBinaryOp::Multiply,
            (Self::Multiplicative, 153) => SurfaceBinaryOp::Divide,
            (Self::Multiplicative, 154) => SurfaceBinaryOp::Remainder,
            _ => return None,
        })
    }
}

fn assign_operator(production: u32) -> Option<SurfaceAssignOp> {
    Some(match production {
        106 => SurfaceAssignOp::Set,
        107 => SurfaceAssignOp::Add,
        108 => SurfaceAssignOp::Subtract,
        109 => SurfaceAssignOp::Multiply,
        110 => SurfaceAssignOp::Divide,
        111 => SurfaceAssignOp::Remainder,
        112 => SurfaceAssignOp::BitXor,
        113 => SurfaceAssignOp::ShiftLeft,
        114 => SurfaceAssignOp::ShiftRight,
        115 => SurfaceAssignOp::BitAnd,
        116 => SurfaceAssignOp::BitOr,
        _ => return None,
    })
}

pub fn extract_surface(
    source: &SourceFile,
    tokens: &[Token],
    nodes: &[ParseNode],
    root: ParseNodeId,
) -> Result<SurfaceFile> {
    Tree {
        source,
        tokens,
        nodes,
        next_surface_id: 0,
    }
    .file(root)
}
