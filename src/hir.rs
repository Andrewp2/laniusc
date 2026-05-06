//! High-level AST/HIR for the current Lanius frontend surface.
//!
//! The parser's CPU AST is intentionally grammar-shaped and compact. This
//! module preserves source names/literals and lowers away grammar helper nodes
//! so name resolution and type checking have a stable input.

use serde::Serialize;

use crate::lexer::{
    cpu::{CpuToken, lex_on_cpu},
    tables::tokens::TokenKind,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HirToken {
    pub kind: TokenKind,
    pub start: usize,
    pub len: usize,
}

impl From<CpuToken> for HirToken {
    fn from(token: CpuToken) -> Self {
        Self {
            kind: token.kind,
            start: token.start,
            len: token.len,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Span {
    pub start: usize,
    pub len: usize,
}

impl Span {
    pub fn end(self) -> usize {
        self.start.saturating_add(self.len)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct HirFile {
    pub items: Vec<HirItem>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub enum HirItem {
    Fn(HirFn),
    Stmt(HirStmt),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct HirFn {
    pub public: bool,
    pub name: String,
    pub params: Vec<HirParam>,
    pub ret: HirType,
    pub body: HirBlock,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct HirParam {
    pub name: String,
    pub ty: HirType,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct HirBlock {
    pub stmts: Vec<HirStmt>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct HirType {
    pub kind: HirTypeKind,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub enum HirTypeKind {
    Void,
    Name(String),
    Array { elem: Box<HirType>, len: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct HirStmt {
    pub kind: HirStmtKind,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub enum HirStmtKind {
    Let {
        name: String,
        ty: Option<HirType>,
        value: Option<HirExpr>,
    },
    Return(Option<HirExpr>),
    If {
        cond: HirExpr,
        then_block: HirBlock,
        else_block: Option<HirBlock>,
    },
    While {
        cond: HirExpr,
        body: HirBlock,
    },
    Break,
    Continue,
    Block(HirBlock),
    Expr(HirExpr),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct HirExpr {
    pub kind: HirExprKind,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub enum HirExprKind {
    Name(String),
    Literal {
        kind: HirLiteralKind,
        text: String,
    },
    Array(Vec<HirExpr>),
    Call {
        callee: Box<HirExpr>,
        args: Vec<HirExpr>,
    },
    Index {
        base: Box<HirExpr>,
        index: Box<HirExpr>,
    },
    Member {
        base: Box<HirExpr>,
        member: String,
    },
    Unary {
        op: HirUnaryOp,
        expr: Box<HirExpr>,
    },
    Binary {
        op: HirBinaryOp,
        lhs: Box<HirExpr>,
        rhs: Box<HirExpr>,
    },
    Assign {
        op: HirAssignOp,
        target: Box<HirExpr>,
        value: Box<HirExpr>,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum HirLiteralKind {
    Int,
    Float,
    String,
    Char,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum HirUnaryOp {
    PreInc,
    PreDec,
    Plus,
    Neg,
    Not,
    BitNot,
    PostInc,
    PostDec,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum HirBinaryOp {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Shl,
    Shr,
    Lt,
    Gt,
    Le,
    Ge,
    Eq,
    Ne,
    BitAnd,
    BitXor,
    BitOr,
    And,
    Or,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum HirAssignOp {
    Assign,
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Shl,
    Shr,
    BitAnd,
    BitXor,
    BitOr,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HirError {
    Lex(String),
    Parse {
        pos: usize,
        expected: &'static str,
        found: Option<TokenKind>,
    },
}

impl std::fmt::Display for HirError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            HirError::Lex(err) => write!(f, "lex error: {err}"),
            HirError::Parse {
                pos,
                expected,
                found,
            } => match found {
                Some(kind) => write!(
                    f,
                    "HIR parse error at token #{pos}, expected {expected}, found {kind:?}"
                ),
                None => write!(
                    f,
                    "HIR parse error at token #{pos}, expected {expected}, found <eof>"
                ),
            },
        }
    }
}

impl std::error::Error for HirError {}

pub fn parse_source(src: &str) -> Result<HirFile, HirError> {
    let tokens = lex_on_cpu(src)
        .map_err(HirError::Lex)?
        .into_iter()
        .map(HirToken::from)
        .collect::<Vec<_>>();
    parse_tokens(src, &tokens)
}

pub fn parse_tokens(src: &str, tokens: &[HirToken]) -> Result<HirFile, HirError> {
    HirParser { src, tokens, i: 0 }.parse_file()
}

struct HirParser<'a> {
    src: &'a str,
    tokens: &'a [HirToken],
    i: usize,
}

impl<'a> HirParser<'a> {
    fn parse_file(&mut self) -> Result<HirFile, HirError> {
        let start = self.peek_start();
        let mut items = Vec::new();
        while self.peek().is_some() {
            items.push(self.parse_item()?);
        }
        Ok(HirFile {
            items,
            span: self.span_since(start),
        })
    }

    fn parse_item(&mut self) -> Result<HirItem, HirError> {
        let public = self.eat(TokenKind::Pub).is_some();
        if public || self.peek() == Some(TokenKind::Fn) {
            Ok(HirItem::Fn(self.parse_fn(public)?))
        } else {
            Ok(HirItem::Stmt(self.parse_stmt()?))
        }
    }

    fn parse_fn(&mut self, public: bool) -> Result<HirFn, HirError> {
        let start = if public {
            self.prev_start()
        } else {
            self.peek_start()
        };
        self.expect(TokenKind::Fn, "Fn")?;
        let name = self.expect_name(&[TokenKind::Ident], "function name")?;
        self.expect_any(
            &[
                TokenKind::ParamLParen,
                TokenKind::CallLParen,
                TokenKind::LParen,
            ],
            "function parameter list",
        )?;
        let params = self.parse_params()?;
        self.expect_any(
            &[
                TokenKind::ParamRParen,
                TokenKind::CallRParen,
                TokenKind::RParen,
            ],
            "RParen",
        )?;

        let ret = if self.eat(TokenKind::Arrow).is_some() {
            self.parse_type_expr()?
        } else {
            HirType {
                kind: HirTypeKind::Void,
                span: self.empty_span(),
            }
        };
        let body = self.parse_block()?;

        Ok(HirFn {
            public,
            name,
            params,
            ret,
            body,
            span: self.span_since(start),
        })
    }

    fn parse_params(&mut self) -> Result<Vec<HirParam>, HirError> {
        if self.peek().is_some_and(Self::is_close_paren) {
            return Ok(Vec::new());
        }

        let mut params = vec![self.parse_param()?];
        while self.eat(TokenKind::ParamComma).is_some() || self.eat(TokenKind::Comma).is_some() {
            params.push(self.parse_param()?);
        }
        Ok(params)
    }

    fn parse_param(&mut self) -> Result<HirParam, HirError> {
        let start = self.peek_start();
        let name =
            self.expect_name(&[TokenKind::ParamIdent, TokenKind::Ident], "parameter name")?;
        self.expect(TokenKind::Colon, "Colon")?;
        let ty = self.parse_type_expr()?;
        Ok(HirParam {
            name,
            ty,
            span: self.span_since(start),
        })
    }

    fn parse_type_expr(&mut self) -> Result<HirType, HirError> {
        let start = self.peek_start();
        if let Some(tok) = self.eat_any(&[TokenKind::TypeIdent, TokenKind::Ident]) {
            return Ok(HirType {
                kind: HirTypeKind::Name(self.lexeme(tok)),
                span: self.span_since(start),
            });
        }

        if self
            .eat_any(&[
                TokenKind::TypeArrayLBracket,
                TokenKind::ArrayLBracket,
                TokenKind::LBracket,
            ])
            .is_some()
        {
            let elem = self.parse_type_expr()?;
            self.expect_any(
                &[TokenKind::TypeSemicolon, TokenKind::Semicolon],
                "Semicolon",
            )?;
            let len_tok = self.expect(TokenKind::Int, "array length")?;
            let len = self.lexeme(len_tok);
            self.expect_any(
                &[
                    TokenKind::TypeArrayRBracket,
                    TokenKind::ArrayRBracket,
                    TokenKind::RBracket,
                ],
                "RBracket",
            )?;
            return Ok(HirType {
                kind: HirTypeKind::Array {
                    elem: Box::new(elem),
                    len,
                },
                span: self.span_since(start),
            });
        }

        Err(self.error("type expression"))
    }

    fn parse_block(&mut self) -> Result<HirBlock, HirError> {
        let start = self.peek_start();
        self.expect(TokenKind::LBrace, "LBrace")?;
        let mut stmts = Vec::new();
        while self.peek() != Some(TokenKind::RBrace) {
            if self.peek().is_none() {
                return Err(self.error("RBrace"));
            }
            stmts.push(self.parse_stmt()?);
        }
        self.expect(TokenKind::RBrace, "RBrace")?;
        Ok(HirBlock {
            stmts,
            span: self.span_since(start),
        })
    }

    fn parse_if_block(&mut self) -> Result<HirBlock, HirError> {
        let start = self.peek_start();
        self.expect_any(&[TokenKind::IfLBrace, TokenKind::LBrace], "IfLBrace")?;
        let mut stmts = Vec::new();
        while self.peek() != Some(TokenKind::IfRBrace) && self.peek() != Some(TokenKind::RBrace) {
            if self.peek().is_none() {
                return Err(self.error("IfRBrace"));
            }
            stmts.push(self.parse_stmt()?);
        }
        self.expect_any(&[TokenKind::IfRBrace, TokenKind::RBrace], "IfRBrace")?;
        Ok(HirBlock {
            stmts,
            span: self.span_since(start),
        })
    }

    fn parse_stmt(&mut self) -> Result<HirStmt, HirError> {
        let start = self.peek_start();
        if self.eat(TokenKind::Let).is_some() {
            let name =
                self.expect_name(&[TokenKind::LetIdent, TokenKind::Ident], "let binding name")?;
            let ty = if self.eat(TokenKind::Colon).is_some() {
                Some(self.parse_type_expr()?)
            } else {
                None
            };
            let value = if self.eat(TokenKind::LetAssign).is_some()
                || self.eat(TokenKind::Assign).is_some()
            {
                Some(self.parse_expr()?)
            } else {
                None
            };
            self.expect_semicolon()?;
            return Ok(HirStmt {
                kind: HirStmtKind::Let { name, ty, value },
                span: self.span_since(start),
            });
        }

        if self.eat(TokenKind::Return).is_some() {
            let value = if self.peek() == Some(TokenKind::Semicolon) {
                None
            } else {
                Some(self.parse_expr()?)
            };
            self.expect_semicolon()?;
            return Ok(HirStmt {
                kind: HirStmtKind::Return(value),
                span: self.span_since(start),
            });
        }

        if self.eat(TokenKind::If).is_some() {
            self.expect_any(&[TokenKind::GroupLParen, TokenKind::LParen], "if condition")?;
            let cond = self.parse_expr()?;
            self.expect_any(&[TokenKind::GroupRParen, TokenKind::RParen], "RParen")?;
            let then_block = self.parse_if_block()?;
            let else_block = if self.eat(TokenKind::Else).is_some() {
                Some(self.parse_block()?)
            } else {
                None
            };
            return Ok(HirStmt {
                kind: HirStmtKind::If {
                    cond,
                    then_block,
                    else_block,
                },
                span: self.span_since(start),
            });
        }

        if self.eat(TokenKind::While).is_some() {
            self.expect_any(
                &[TokenKind::GroupLParen, TokenKind::LParen],
                "while condition",
            )?;
            let cond = self.parse_expr()?;
            self.expect_any(&[TokenKind::GroupRParen, TokenKind::RParen], "RParen")?;
            let body = self.parse_block()?;
            return Ok(HirStmt {
                kind: HirStmtKind::While { cond, body },
                span: self.span_since(start),
            });
        }

        if self.eat(TokenKind::Break).is_some() {
            self.expect_semicolon()?;
            return Ok(HirStmt {
                kind: HirStmtKind::Break,
                span: self.span_since(start),
            });
        }

        if self.eat(TokenKind::Continue).is_some() {
            self.expect_semicolon()?;
            return Ok(HirStmt {
                kind: HirStmtKind::Continue,
                span: self.span_since(start),
            });
        }

        if self.peek() == Some(TokenKind::LBrace) {
            let block = self.parse_block()?;
            return Ok(HirStmt {
                kind: HirStmtKind::Block(block),
                span: self.span_since(start),
            });
        }

        let expr = self.parse_expr()?;
        self.expect_semicolon()?;
        Ok(HirStmt {
            kind: HirStmtKind::Expr(expr),
            span: self.span_since(start),
        })
    }

    fn parse_expr(&mut self) -> Result<HirExpr, HirError> {
        self.parse_assign()
    }

    fn parse_assign(&mut self) -> Result<HirExpr, HirError> {
        let lhs = self.parse_orexpr()?;
        if let Some(op) = self.eat_assign_op() {
            let start = lhs.span.start;
            let rhs = self.parse_assign()?;
            Ok(HirExpr {
                kind: HirExprKind::Assign {
                    op,
                    target: Box::new(lhs),
                    value: Box::new(rhs),
                },
                span: self.span_since(start),
            })
        } else {
            Ok(lhs)
        }
    }

    fn parse_orexpr(&mut self) -> Result<HirExpr, HirError> {
        self.parse_binary_left(Self::parse_andexpr, &[(TokenKind::OrOr, HirBinaryOp::Or)])
    }

    fn parse_andexpr(&mut self) -> Result<HirExpr, HirError> {
        self.parse_binary_left(Self::parse_bit_or, &[(TokenKind::AndAnd, HirBinaryOp::And)])
    }

    fn parse_bit_or(&mut self) -> Result<HirExpr, HirError> {
        self.parse_binary_left(
            Self::parse_bit_xor,
            &[(TokenKind::Pipe, HirBinaryOp::BitOr)],
        )
    }

    fn parse_bit_xor(&mut self) -> Result<HirExpr, HirError> {
        self.parse_binary_left(
            Self::parse_bit_and,
            &[(TokenKind::Caret, HirBinaryOp::BitXor)],
        )
    }

    fn parse_bit_and(&mut self) -> Result<HirExpr, HirError> {
        self.parse_binary_left(
            Self::parse_equality,
            &[(TokenKind::Ampersand, HirBinaryOp::BitAnd)],
        )
    }

    fn parse_equality(&mut self) -> Result<HirExpr, HirError> {
        self.parse_binary_left(
            Self::parse_compare,
            &[
                (TokenKind::EqEq, HirBinaryOp::Eq),
                (TokenKind::NotEqual, HirBinaryOp::Ne),
            ],
        )
    }

    fn parse_compare(&mut self) -> Result<HirExpr, HirError> {
        self.parse_binary_left(
            Self::parse_shift,
            &[
                (TokenKind::Lt, HirBinaryOp::Lt),
                (TokenKind::Gt, HirBinaryOp::Gt),
                (TokenKind::Le, HirBinaryOp::Le),
                (TokenKind::Ge, HirBinaryOp::Ge),
            ],
        )
    }

    fn parse_shift(&mut self) -> Result<HirExpr, HirError> {
        self.parse_binary_left(
            Self::parse_add,
            &[
                (TokenKind::Shl, HirBinaryOp::Shl),
                (TokenKind::Shr, HirBinaryOp::Shr),
            ],
        )
    }

    fn parse_add(&mut self) -> Result<HirExpr, HirError> {
        self.parse_binary_left(
            Self::parse_mul,
            &[
                (TokenKind::InfixPlus, HirBinaryOp::Add),
                (TokenKind::Plus, HirBinaryOp::Add),
                (TokenKind::InfixMinus, HirBinaryOp::Sub),
                (TokenKind::Minus, HirBinaryOp::Sub),
            ],
        )
    }

    fn parse_mul(&mut self) -> Result<HirExpr, HirError> {
        self.parse_binary_left(
            Self::parse_unary,
            &[
                (TokenKind::Star, HirBinaryOp::Mul),
                (TokenKind::Slash, HirBinaryOp::Div),
                (TokenKind::Percent, HirBinaryOp::Mod),
            ],
        )
    }

    fn parse_binary_left(
        &mut self,
        next: fn(&mut Self) -> Result<HirExpr, HirError>,
        ops: &[(TokenKind, HirBinaryOp)],
    ) -> Result<HirExpr, HirError> {
        let mut lhs = next(self)?;
        loop {
            let Some(op) = ops
                .iter()
                .find_map(|(kind, op)| self.eat(*kind).map(|_| *op))
            else {
                break;
            };
            let start = lhs.span.start;
            let rhs = next(self)?;
            lhs = HirExpr {
                kind: HirExprKind::Binary {
                    op,
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                },
                span: self.span_since(start),
            };
        }
        Ok(lhs)
    }

    fn parse_unary(&mut self) -> Result<HirExpr, HirError> {
        let start = self.peek_start();
        let op = if self.eat(TokenKind::Inc).is_some() {
            Some(HirUnaryOp::PreInc)
        } else if self.eat(TokenKind::Dec).is_some() {
            Some(HirUnaryOp::PreDec)
        } else if self.eat(TokenKind::PrefixPlus).is_some() || self.eat(TokenKind::Plus).is_some() {
            Some(HirUnaryOp::Plus)
        } else if self.eat(TokenKind::PrefixMinus).is_some() || self.eat(TokenKind::Minus).is_some()
        {
            Some(HirUnaryOp::Neg)
        } else if self.eat(TokenKind::Not).is_some() {
            Some(HirUnaryOp::Not)
        } else if self.eat(TokenKind::Tilde).is_some() {
            Some(HirUnaryOp::BitNot)
        } else {
            None
        };

        if let Some(op) = op {
            let expr = self.parse_unary()?;
            Ok(HirExpr {
                kind: HirExprKind::Unary {
                    op,
                    expr: Box::new(expr),
                },
                span: self.span_since(start),
            })
        } else {
            self.parse_postfix()
        }
    }

    fn parse_postfix(&mut self) -> Result<HirExpr, HirError> {
        let mut node = self.parse_primary()?;
        loop {
            if self.eat(TokenKind::CallLParen).is_some() || self.eat(TokenKind::LParen).is_some() {
                let start = node.span.start;
                let mut args = Vec::new();
                if self.eat(TokenKind::CallRParen).is_none()
                    && self.eat(TokenKind::RParen).is_none()
                {
                    args.push(self.parse_expr()?);
                    while self.eat(TokenKind::ArgComma).is_some()
                        || self.eat(TokenKind::Comma).is_some()
                    {
                        args.push(self.parse_expr()?);
                    }
                    self.expect_any(&[TokenKind::CallRParen, TokenKind::RParen], "RParen")?;
                }
                node = HirExpr {
                    kind: HirExprKind::Call {
                        callee: Box::new(node),
                        args,
                    },
                    span: self.span_since(start),
                };
                continue;
            }

            if self.eat(TokenKind::IndexLBracket).is_some()
                || self.eat(TokenKind::LBracket).is_some()
            {
                let start = node.span.start;
                let index = self.parse_expr()?;
                self.expect_any(&[TokenKind::IndexRBracket, TokenKind::RBracket], "RBracket")?;
                node = HirExpr {
                    kind: HirExprKind::Index {
                        base: Box::new(node),
                        index: Box::new(index),
                    },
                    span: self.span_since(start),
                };
                continue;
            }

            if self.eat(TokenKind::Dot).is_some() {
                let start = node.span.start;
                let member = self.expect_name(&[TokenKind::Ident], "member name")?;
                node = HirExpr {
                    kind: HirExprKind::Member {
                        base: Box::new(node),
                        member,
                    },
                    span: self.span_since(start),
                };
                continue;
            }

            if self.eat(TokenKind::Inc).is_some() {
                let start = node.span.start;
                node = HirExpr {
                    kind: HirExprKind::Unary {
                        op: HirUnaryOp::PostInc,
                        expr: Box::new(node),
                    },
                    span: self.span_since(start),
                };
                continue;
            }

            if self.eat(TokenKind::Dec).is_some() {
                let start = node.span.start;
                node = HirExpr {
                    kind: HirExprKind::Unary {
                        op: HirUnaryOp::PostDec,
                        expr: Box::new(node),
                    },
                    span: self.span_since(start),
                };
                continue;
            }

            break;
        }
        Ok(node)
    }

    fn parse_primary(&mut self) -> Result<HirExpr, HirError> {
        if self.eat(TokenKind::GroupLParen).is_some() || self.eat(TokenKind::LParen).is_some() {
            let expr = self.parse_expr()?;
            self.expect_any(&[TokenKind::GroupRParen, TokenKind::RParen], "RParen")?;
            return Ok(expr);
        }

        let start = self.peek_start();
        if self.eat(TokenKind::ArrayLBracket).is_some() || self.eat(TokenKind::LBracket).is_some() {
            let mut elems = Vec::new();
            if self.eat(TokenKind::ArrayRBracket).is_none()
                && self.eat(TokenKind::RBracket).is_none()
            {
                elems.push(self.parse_expr()?);
                while self.eat(TokenKind::ArrayComma).is_some()
                    || self.eat(TokenKind::Comma).is_some()
                {
                    elems.push(self.parse_expr()?);
                }
                self.expect_any(&[TokenKind::ArrayRBracket, TokenKind::RBracket], "RBracket")?;
            }
            return Ok(HirExpr {
                kind: HirExprKind::Array(elems),
                span: self.span_since(start),
            });
        }

        if let Some(tok) = self.eat(TokenKind::Ident) {
            return Ok(HirExpr {
                kind: HirExprKind::Name(self.lexeme(tok)),
                span: self.span_since(start),
            });
        }

        for (kind, lit_kind) in [
            (TokenKind::Int, HirLiteralKind::Int),
            (TokenKind::Float, HirLiteralKind::Float),
            (TokenKind::String, HirLiteralKind::String),
            (TokenKind::Char, HirLiteralKind::Char),
        ] {
            if let Some(tok) = self.eat(kind) {
                return Ok(HirExpr {
                    kind: HirExprKind::Literal {
                        kind: lit_kind,
                        text: self.lexeme(tok),
                    },
                    span: self.span_since(start),
                });
            }
        }

        Err(self.error("primary"))
    }

    fn eat_assign_op(&mut self) -> Option<HirAssignOp> {
        for (kind, op) in [
            (TokenKind::Assign, HirAssignOp::Assign),
            (TokenKind::PlusAssign, HirAssignOp::Add),
            (TokenKind::MinusAssign, HirAssignOp::Sub),
            (TokenKind::StarAssign, HirAssignOp::Mul),
            (TokenKind::SlashAssign, HirAssignOp::Div),
            (TokenKind::PercentAssign, HirAssignOp::Mod),
            (TokenKind::ShlAssign, HirAssignOp::Shl),
            (TokenKind::ShrAssign, HirAssignOp::Shr),
            (TokenKind::AmpAssign, HirAssignOp::BitAnd),
            (TokenKind::CaretAssign, HirAssignOp::BitXor),
            (TokenKind::PipeAssign, HirAssignOp::BitOr),
        ] {
            if self.eat(kind).is_some() {
                return Some(op);
            }
        }
        None
    }

    fn expect_semicolon(&mut self) -> Result<HirToken, HirError> {
        self.expect(TokenKind::Semicolon, "Semicolon")
    }

    fn expect_name(
        &mut self,
        kinds: &[TokenKind],
        expected: &'static str,
    ) -> Result<String, HirError> {
        let tok = self.expect_any(kinds, expected)?;
        Ok(self.lexeme(tok))
    }

    fn expect(&mut self, kind: TokenKind, expected: &'static str) -> Result<HirToken, HirError> {
        self.eat(kind).ok_or_else(|| self.error(expected))
    }

    fn expect_any(
        &mut self,
        kinds: &[TokenKind],
        expected: &'static str,
    ) -> Result<HirToken, HirError> {
        self.eat_any(kinds).ok_or_else(|| self.error(expected))
    }

    fn eat_any(&mut self, kinds: &[TokenKind]) -> Option<HirToken> {
        for kind in kinds {
            if let Some(token) = self.eat(*kind) {
                return Some(token);
            }
        }
        None
    }

    fn eat(&mut self, kind: TokenKind) -> Option<HirToken> {
        if self.peek() == Some(kind) {
            let tok = self.tokens[self.i];
            self.i += 1;
            Some(tok)
        } else {
            None
        }
    }

    fn peek(&self) -> Option<TokenKind> {
        self.tokens.get(self.i).map(|token| token.kind)
    }

    fn is_close_paren(kind: TokenKind) -> bool {
        matches!(
            kind,
            TokenKind::GroupRParen
                | TokenKind::CallRParen
                | TokenKind::ParamRParen
                | TokenKind::RParen
        )
    }

    fn lexeme(&self, tok: HirToken) -> String {
        let end = tok.start.saturating_add(tok.len);
        self.src.get(tok.start..end).unwrap_or("").to_string()
    }

    fn peek_start(&self) -> usize {
        self.tokens
            .get(self.i)
            .map(|token| token.start)
            .unwrap_or_else(|| self.prev_end())
    }

    fn prev_start(&self) -> usize {
        if self.i == 0 {
            0
        } else {
            self.tokens[self.i - 1].start
        }
    }

    fn prev_end(&self) -> usize {
        if self.i == 0 {
            0
        } else {
            let tok = self.tokens[self.i - 1];
            tok.start.saturating_add(tok.len)
        }
    }

    fn empty_span(&self) -> Span {
        Span {
            start: self.peek_start(),
            len: 0,
        }
    }

    fn span_since(&self, start: usize) -> Span {
        Span {
            start,
            len: self.prev_end().saturating_sub(start),
        }
    }

    fn error(&self, expected: &'static str) -> HirError {
        HirError::Parse {
            pos: self.i,
            expected,
            found: self.peek(),
        }
    }
}
