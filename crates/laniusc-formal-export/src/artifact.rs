use serde::{Deserialize, Serialize};

use crate::{
    core::{CoreProgram, CoreTy},
    surface::SurfaceFile,
};

pub const SCHEMA_VERSION: u32 = 5;

pub type FileId = u32;
pub type TokenId = u32;
pub type ParseNodeId = u32;
pub type SurfaceNodeId = u32;
pub type CoreNodeId = u32;
pub type UnitId = u32;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Span {
    pub file: FileId,
    pub start: u32,
    pub finish: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourceFile {
    pub path: String,
    pub bytes: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Token {
    /// Stable raw/canonical token tag shared with the production compiler.
    pub kind: u32,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ParseChild {
    Token(TokenId),
    Node(ParseNodeId),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ParseNode {
    pub production: u32,
    pub nonterminal: u32,
    /// Half-open range in the parser's token lattice. Ordinary token
    /// boundaries are even; an odd boundary lies between the two virtual
    /// generic closes represented by one physical `>>` token.
    pub position_start: u32,
    pub position_end: u32,
    pub children: Vec<ParseChild>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Namespace {
    Value,
    Type,
    Module,
    Field,
    Variant,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LexicalScopeKind {
    FunctionBody,
    AfterLocal,
    ThenBody,
    ElseBody,
    LoopBody,
    BlockBody,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalScopeIdentity {
    pub kind: LexicalScopeKind,
    pub node: SurfaceNodeId,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResolutionEvidence {
    pub use_node: SurfaceNodeId,
    /// Pack unit whose local Surface identity space contains the declaration.
    pub declaration_unit: UnitId,
    pub declaration_node: SurfaceNodeId,
    pub namespace_tag: Namespace,
    /// Lexical scopes examined from the use site toward the function root.
    pub scope_path: Vec<LexicalScopeIdentity>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TypeRule {
    Literal,
    Local,
    Constant,
    Unary,
    Binary,
    Assignment,
    Call,
    Index,
    Field,
    StructValue,
    ReturnRule,
    Branch,
    Loop,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TypeEvidence {
    pub surface_node: SurfaceNodeId,
    pub ty: CoreTy,
    pub rule: TypeRule,
    pub premises: Vec<u32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LoweringRule {
    Declaration,
    Literal,
    Local,
    Unary,
    Binary,
    Assignment,
    Call,
    Index,
    Field,
    Aggregate,
    Statement,
    ControlFlow,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoweringEvidence {
    pub surface_node: SurfaceNodeId,
    pub core_node: CoreNodeId,
    pub rule: LoweringRule,
    pub premises: Vec<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExtractionArtifact {
    pub schema_version: u32,
    pub sources: Vec<SourceFile>,
    pub tokens: Vec<Token>,
    #[serde(default)]
    pub raw_tokens: Vec<Token>,
    pub semantic_token_kinds: Vec<u32>,
    pub parse_nodes: Vec<ParseNode>,
    pub parse_root: Option<ParseNodeId>,
    pub surface: Option<SurfaceFile>,
    pub resolutions: Vec<ResolutionEvidence>,
    pub types: Vec<TypeEvidence>,
    pub core_program: Option<CoreProgram>,
    pub lowering: Vec<LoweringEvidence>,
}

impl ExtractionArtifact {
    pub fn token_only(
        sources: Vec<SourceFile>,
        raw_tokens: Vec<Token>,
        tokens: Vec<Token>,
    ) -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            sources,
            tokens,
            raw_tokens,
            semantic_token_kinds: Vec::new(),
            parse_nodes: Vec::new(),
            parse_root: None,
            surface: None,
            resolutions: Vec::new(),
            types: Vec::new(),
            core_program: None,
            lowering: Vec::new(),
        }
    }
}

/// A dependency-ready source pack. Each unit retains its own source/token/
/// parse/Surface certificate, while Core declaration and node identities are
/// assigned globally across every unit.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExtractionArtifactPack {
    pub schema_version: u32,
    pub units: Vec<ExtractionArtifact>,
}
