// src/parser/cpu.rs
//
// A plain CPU recursive-descent parser for the grammar in grammar/lanius.bnf.
// It is intentionally straightforward and acts as the correctness oracle while
// the GPU parser catches up to the full grammar.
//
// This module only depends on the public token kinds from the lexer tables.
//

use serde::Serialize;

use crate::lexer::tables::tokens;

#[derive(Debug, Clone, Serialize)]
pub struct Ast {
    /// Index of the root node in `nodes`.
    pub root: u32,
    /// All nodes in stable indices.
    pub nodes: Vec<AstNode>,
}

#[derive(Debug, Clone, Serialize)]
pub struct AstNode {
    /// Grammar-tag-like label: e.g. "group", "array_lit", "call", "index",
    /// "ident", "int", "string", "pos", "neg", "not", "mul", "add", "sub",
    /// "lt", "gt", "le", "ge", "eq", "and", "or", "set",
    /// plus file/item additions: "file", "fn", "param", "type_ident",
    /// "type_generic", "type_array", "block", "stmt_let", "stmt_return",
    /// "stmt_if", "stmt_while", "stmt_break", "stmt_continue", "stmt_expr",
    /// "enum", "enum_variant", "enum_fields", "enum_fields_none",
    /// "type_params".
    pub tag: &'static str,
    /// Children node ids in source order.
    pub children: Vec<u32>,
}

/// Lightweight parse error without extra deps.
#[derive(Debug, Clone)]
pub struct ParseError {
    pub pos: usize,
    pub expected: &'static str,
    pub found: Option<tokens::TokenKind>,
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self.found {
            Some(k) => write!(
                f,
                "parse error at token #{}, expected {}, found {:?}",
                self.pos, self.expected, k
            ),
            None => write!(
                f,
                "parse error at token #{}, expected {}, found <eof>",
                self.pos, self.expected
            ),
        }
    }
}
impl std::error::Error for ParseError {}

/// Public entrypoint: parse a full file.
pub fn parse_from_token_kinds(kinds: &[tokens::TokenKind]) -> Result<Ast, ParseError> {
    let mut p = Parser {
        kinds,
        i: 0,
        nodes: Vec::new(),
    };

    let root = p.parse_file()?;

    // Must also be at EOF (no stray tokens). If you prefer partial-consume, remove this.
    if p.peek().is_some() {
        return Err(ParseError {
            pos: p.i,
            expected: "end of input",
            found: p.peek(),
        });
    }
    Ok(Ast {
        root,
        nodes: p.nodes,
    })
}

/// Pretty-print the AST (useful in demos).
pub fn format_pretty(ast: &Ast) -> String {
    fn rec(nodes: &[AstNode], id: u32, indent: usize, out: &mut String) {
        let n = &nodes[id as usize];
        out.push_str(&format!("{}{}#{id}\n", "  ".repeat(indent), n.tag));
        for &c in &n.children {
            rec(nodes, c, indent + 1, out);
        }
    }
    let mut s = String::new();
    rec(&ast.nodes, ast.root, 0, &mut s);
    s
}

// ---------------------------------------------------------------------------
// Parser impl
// ---------------------------------------------------------------------------

struct Parser<'a> {
    kinds: &'a [tokens::TokenKind],
    i: usize,
    nodes: Vec<AstNode>,
}

impl<'a> Parser<'a> {
    // ------------- utilities -------------

    fn push(&mut self, tag: &'static str, children: Vec<u32>) -> u32 {
        let id = self.nodes.len() as u32;
        self.nodes.push(AstNode { tag, children });
        id
    }

    fn peek(&self) -> Option<tokens::TokenKind> {
        self.kinds.get(self.i).copied()
    }

    fn eat(&mut self, k: tokens::TokenKind) -> bool {
        if self.peek() == Some(k) {
            self.i += 1;
            true
        } else {
            false
        }
    }

    fn expect(&mut self, k: tokens::TokenKind, expected: &'static str) -> Result<(), ParseError> {
        if self.eat(k) {
            Ok(())
        } else {
            Err(ParseError {
                pos: self.i,
                expected,
                found: self.peek(),
            })
        }
    }

    fn is_close_paren(k: tokens::TokenKind) -> bool {
        matches!(
            k,
            tokens::TokenKind::GroupRParen
                | tokens::TokenKind::CallRParen
                | tokens::TokenKind::ParamRParen
                | tokens::TokenKind::RParen
        )
    }

    fn eat_open_group_paren(&mut self) -> bool {
        self.eat(tokens::TokenKind::GroupLParen) || self.eat(tokens::TokenKind::LParen)
    }

    fn eat_close_group_paren(&mut self) -> bool {
        self.eat(tokens::TokenKind::GroupRParen) || self.eat(tokens::TokenKind::RParen)
    }

    fn expect_semicolon(&mut self) -> Result<(), ParseError> {
        self.expect(tokens::TokenKind::Semicolon, "Semicolon")
    }

    // ------------- file / items / statements -------------

    fn parse_file(&mut self) -> Result<u32, ParseError> {
        let mut items = Vec::new();
        while self.peek().is_some() {
            items.push(self.parse_item()?);
        }
        Ok(self.push("file", items))
    }

    fn parse_item(&mut self) -> Result<u32, ParseError> {
        if self.eat(tokens::TokenKind::Pub) {
            let item = if self.peek() == Some(tokens::TokenKind::Enum) {
                self.parse_enum_item()?
            } else if self.peek() == Some(tokens::TokenKind::Struct) {
                self.parse_struct_item()?
            } else {
                self.parse_fn_item()?
            };
            Ok(self.push("pub", vec![item]))
        } else if self.peek() == Some(tokens::TokenKind::Fn) {
            self.parse_fn_item()
        } else if self.peek() == Some(tokens::TokenKind::Const) {
            self.parse_const_item()
        } else if self.peek() == Some(tokens::TokenKind::Enum) {
            self.parse_enum_item()
        } else if self.peek() == Some(tokens::TokenKind::Struct) {
            self.parse_struct_item()
        } else {
            self.parse_stmt()
        }
    }

    /// Parse a top-level `fn` item.
    fn parse_fn_item(&mut self) -> Result<u32, ParseError> {
        self.expect(tokens::TokenKind::Fn, "Fn")?;
        self.expect(tokens::TokenKind::Ident, "function name")?;
        let name_id = self.push("ident", vec![]);

        if !(self.eat(tokens::TokenKind::ParamLParen) || self.eat(tokens::TokenKind::CallLParen)) {
            self.expect(tokens::TokenKind::LParen, "function parameter list")?;
        }
        let params = self.parse_param_list_opt()?;
        if !(self.eat(tokens::TokenKind::ParamRParen) || self.eat(tokens::TokenKind::CallRParen)) {
            self.expect(tokens::TokenKind::RParen, "RParen")?;
        }

        let ret = if self.eat(tokens::TokenKind::Arrow) {
            self.parse_type_expr()?
        } else {
            self.push("type_void", vec![])
        };

        let body = self.parse_block()?;
        Ok(self.push("fn", vec![name_id, params, ret, body]))
    }

    /// Parse a top-level `const` item.
    fn parse_const_item(&mut self) -> Result<u32, ParseError> {
        self.expect(tokens::TokenKind::Const, "Const")?;
        self.expect(tokens::TokenKind::Ident, "constant name")?;
        let name_id = self.push("ident", vec![]);
        self.expect(tokens::TokenKind::Colon, "Colon")?;
        let ty = self.parse_type_expr()?;
        self.expect(tokens::TokenKind::Assign, "Assign")?;
        let value = self.parse_expr()?;
        self.expect_semicolon()?;
        Ok(self.push("const", vec![name_id, ty, value]))
    }

    /// Parse a top-level `enum` item.
    fn parse_enum_item(&mut self) -> Result<u32, ParseError> {
        self.expect(tokens::TokenKind::Enum, "Enum")?;
        self.expect(tokens::TokenKind::Ident, "enum name")?;
        let name_id = self.push("ident", vec![]);
        let type_params = self.parse_type_params_opt()?;
        self.expect(tokens::TokenKind::LBrace, "LBrace")?;

        let mut variants = Vec::new();
        while self.peek() != Some(tokens::TokenKind::RBrace) {
            if self.peek().is_none() {
                return Err(ParseError {
                    pos: self.i,
                    expected: "RBrace",
                    found: None,
                });
            }
            variants.push(self.parse_enum_variant()?);
            if self.eat(tokens::TokenKind::Comma) || self.eat(tokens::TokenKind::ArgComma) {
                if self.peek() == Some(tokens::TokenKind::RBrace) {
                    break;
                }
                continue;
            }
            if self.peek() != Some(tokens::TokenKind::RBrace) {
                return Err(ParseError {
                    pos: self.i,
                    expected: "Comma or RBrace",
                    found: self.peek(),
                });
            }
        }

        self.expect(tokens::TokenKind::RBrace, "RBrace")?;
        Ok(self.push("enum", [vec![name_id, type_params], variants].concat()))
    }

    fn parse_type_params_opt(&mut self) -> Result<u32, ParseError> {
        if !self.eat(tokens::TokenKind::Lt) {
            return Ok(self.push("type_params_none", vec![]));
        }

        let mut params = Vec::new();
        self.expect(tokens::TokenKind::Ident, "type parameter name")?;
        params.push(self.push("ident", vec![]));
        while self.eat(tokens::TokenKind::Comma) {
            self.expect(tokens::TokenKind::Ident, "type parameter name")?;
            params.push(self.push("ident", vec![]));
        }
        self.expect(tokens::TokenKind::Gt, "Gt")?;
        Ok(self.push("type_params", params))
    }

    /// Parse a top-level `struct` item.
    fn parse_struct_item(&mut self) -> Result<u32, ParseError> {
        self.expect(tokens::TokenKind::Struct, "Struct")?;
        self.expect(tokens::TokenKind::Ident, "struct name")?;
        let name_id = self.push("ident", vec![]);
        let type_params = self.parse_type_params_opt()?;
        self.expect(tokens::TokenKind::LBrace, "LBrace")?;

        let mut fields = Vec::new();
        while self.peek() != Some(tokens::TokenKind::RBrace) {
            if self.peek().is_none() {
                return Err(ParseError {
                    pos: self.i,
                    expected: "RBrace",
                    found: None,
                });
            }
            fields.push(self.parse_struct_field()?);
            if self.eat(tokens::TokenKind::Comma) || self.eat(tokens::TokenKind::ArgComma) {
                if self.peek() == Some(tokens::TokenKind::RBrace) {
                    break;
                }
                continue;
            }
            if self.peek() != Some(tokens::TokenKind::RBrace) {
                return Err(ParseError {
                    pos: self.i,
                    expected: "Comma or RBrace",
                    found: self.peek(),
                });
            }
        }

        self.expect(tokens::TokenKind::RBrace, "RBrace")?;
        Ok(self.push("struct", [vec![name_id, type_params], fields].concat()))
    }

    fn parse_struct_field(&mut self) -> Result<u32, ParseError> {
        self.expect(tokens::TokenKind::Ident, "struct field name")?;
        let name_id = self.push("ident", vec![]);
        self.expect(tokens::TokenKind::Colon, "Colon")?;
        let ty = self.parse_type_expr()?;
        Ok(self.push("struct_field", vec![name_id, ty]))
    }

    fn parse_enum_variant(&mut self) -> Result<u32, ParseError> {
        self.expect(tokens::TokenKind::Ident, "enum variant name")?;
        let name_id = self.push("ident", vec![]);
        let fields = if self.eat(tokens::TokenKind::CallLParen)
            || self.eat(tokens::TokenKind::GroupLParen)
            || self.eat(tokens::TokenKind::LParen)
        {
            let fields = self.parse_enum_fields()?;
            if !(self.eat(tokens::TokenKind::CallRParen)
                || self.eat(tokens::TokenKind::GroupRParen)
                || self.eat(tokens::TokenKind::RParen))
            {
                return Err(ParseError {
                    pos: self.i,
                    expected: "RParen",
                    found: self.peek(),
                });
            }
            fields
        } else {
            self.push("enum_fields_none", vec![])
        };
        Ok(self.push("enum_variant", vec![name_id, fields]))
    }

    fn parse_enum_fields(&mut self) -> Result<u32, ParseError> {
        if matches!(
            self.peek(),
            Some(
                tokens::TokenKind::CallRParen
                    | tokens::TokenKind::GroupRParen
                    | tokens::TokenKind::RParen
            )
        ) {
            return Ok(self.push("enum_fields", vec![]));
        }

        let mut fields = vec![self.parse_type_expr()?];
        while self.eat(tokens::TokenKind::ArgComma) || self.eat(tokens::TokenKind::Comma) {
            if matches!(
                self.peek(),
                Some(
                    tokens::TokenKind::CallRParen
                        | tokens::TokenKind::GroupRParen
                        | tokens::TokenKind::RParen
                )
            ) {
                break;
            }
            fields.push(self.parse_type_expr()?);
        }
        Ok(self.push("enum_fields", fields))
    }

    fn parse_param_list_opt(&mut self) -> Result<u32, ParseError> {
        if self.peek().map_or(false, Parser::is_close_paren) {
            return Ok(self.push("params_none", vec![]));
        }

        let mut params = Vec::new();
        params.push(self.parse_param()?);
        while self.eat(tokens::TokenKind::ParamComma) || self.eat(tokens::TokenKind::Comma) {
            params.push(self.parse_param()?);
        }
        Ok(self.push("params", params))
    }

    fn parse_param(&mut self) -> Result<u32, ParseError> {
        if !(self.eat(tokens::TokenKind::ParamIdent) || self.eat(tokens::TokenKind::Ident)) {
            return Err(ParseError {
                pos: self.i,
                expected: "parameter name",
                found: self.peek(),
            });
        }
        let name = self.push("ident", vec![]);
        self.expect(tokens::TokenKind::Colon, "Colon")?;
        let ty = self.parse_type_expr()?;
        Ok(self.push("param", vec![name, ty]))
    }

    fn parse_type_expr(&mut self) -> Result<u32, ParseError> {
        if self.eat(tokens::TokenKind::TypeIdent) || self.eat(tokens::TokenKind::Ident) {
            let args = self.parse_type_args_opt()?;
            if self.nodes[args as usize].children.is_empty()
                && self.nodes[args as usize].tag == "type_args_none"
            {
                return Ok(self.push("type_ident", vec![]));
            }
            return Ok(self.push("type_generic", vec![args]));
        }

        if self.eat(tokens::TokenKind::TypeArrayLBracket)
            || self.eat(tokens::TokenKind::ArrayLBracket)
            || self.eat(tokens::TokenKind::LBracket)
        {
            let elem = self.parse_type_expr()?;
            if self.eat(tokens::TokenKind::TypeArrayRBracket)
                || self.eat(tokens::TokenKind::ArrayRBracket)
                || self.eat(tokens::TokenKind::RBracket)
            {
                return Ok(self.push("type_slice", vec![elem]));
            }
            if !(self.eat(tokens::TokenKind::TypeSemicolon)
                || self.eat(tokens::TokenKind::Semicolon))
            {
                return Err(ParseError {
                    pos: self.i,
                    expected: "Semicolon or RBracket",
                    found: self.peek(),
                });
            }
            self.expect(tokens::TokenKind::Int, "array length")?;
            if !(self.eat(tokens::TokenKind::TypeArrayRBracket)
                || self.eat(tokens::TokenKind::ArrayRBracket))
            {
                self.expect(tokens::TokenKind::RBracket, "RBracket")?;
            }
            return Ok(self.push("type_array", vec![elem]));
        }

        if self.eat(tokens::TokenKind::Ampersand) {
            let inner = self.parse_type_expr()?;
            return Ok(self.push("type_ref", vec![inner]));
        }

        Err(ParseError {
            pos: self.i,
            expected: "type expression",
            found: self.peek(),
        })
    }

    fn parse_type_args_opt(&mut self) -> Result<u32, ParseError> {
        if !self.eat(tokens::TokenKind::Lt) {
            return Ok(self.push("type_args_none", vec![]));
        }

        let mut args = vec![self.parse_type_expr()?];
        while self.eat(tokens::TokenKind::Comma) {
            args.push(self.parse_type_expr()?);
        }
        self.expect(tokens::TokenKind::Gt, "Gt")?;
        Ok(self.push("type_args", args))
    }

    /// Parse a block: `{ stmt* }`
    fn parse_block(&mut self) -> Result<u32, ParseError> {
        self.expect(tokens::TokenKind::LBrace, "LBrace")?;
        let mut kids = Vec::new();
        while self.peek() != Some(tokens::TokenKind::RBrace) {
            if self.peek().is_none() {
                return Err(ParseError {
                    pos: self.i,
                    expected: "RBrace",
                    found: None,
                });
            }
            let s = self.parse_stmt()?;
            kids.push(s);
        }
        self.expect(tokens::TokenKind::RBrace, "RBrace")?;
        Ok(self.push("block", kids))
    }

    /// Parse a statement.
    fn parse_stmt(&mut self) -> Result<u32, ParseError> {
        if self.eat(tokens::TokenKind::Let) {
            if !(self.eat(tokens::TokenKind::LetIdent) || self.eat(tokens::TokenKind::Ident)) {
                return Err(ParseError {
                    pos: self.i,
                    expected: "let binding name",
                    found: self.peek(),
                });
            }
            let name = self.push("ident", vec![]);
            let ty = if self.eat(tokens::TokenKind::Colon) {
                self.parse_type_expr()?
            } else {
                self.push("type_infer", vec![])
            };
            let value =
                if self.eat(tokens::TokenKind::LetAssign) || self.eat(tokens::TokenKind::Assign) {
                    self.parse_expr()?
                } else {
                    self.push("init_none", vec![])
                };
            self.expect_semicolon()?;
            return Ok(self.push("stmt_let", vec![name, ty, value]));
        }

        if self.eat(tokens::TokenKind::Return) {
            let value = if self.peek() == Some(tokens::TokenKind::Semicolon) {
                self.push("return_void", vec![])
            } else {
                self.parse_expr()?
            };
            self.expect_semicolon()?;
            return Ok(self.push("stmt_return", vec![value]));
        }

        if self.eat(tokens::TokenKind::If) {
            if !self.eat_open_group_paren() {
                return Err(ParseError {
                    pos: self.i,
                    expected: "if condition",
                    found: self.peek(),
                });
            }
            let cond = self.parse_expr()?;
            if !self.eat_close_group_paren() {
                self.expect(tokens::TokenKind::RParen, "RParen")?;
            }
            let then_block = self.parse_if_block()?;
            let else_block = if self.eat(tokens::TokenKind::Else) {
                self.parse_block()?
            } else {
                self.push("else_none", vec![])
            };
            return Ok(self.push("stmt_if", vec![cond, then_block, else_block]));
        }

        if self.eat(tokens::TokenKind::While) {
            if !self.eat_open_group_paren() {
                return Err(ParseError {
                    pos: self.i,
                    expected: "while condition",
                    found: self.peek(),
                });
            }
            let cond = self.parse_expr()?;
            if !self.eat_close_group_paren() {
                self.expect(tokens::TokenKind::RParen, "RParen")?;
            }
            let body = self.parse_block()?;
            return Ok(self.push("stmt_while", vec![cond, body]));
        }

        if self.eat(tokens::TokenKind::Break) {
            self.expect_semicolon()?;
            return Ok(self.push("stmt_break", vec![]));
        }

        if self.eat(tokens::TokenKind::Continue) {
            self.expect_semicolon()?;
            return Ok(self.push("stmt_continue", vec![]));
        }

        if self.peek() == Some(tokens::TokenKind::LBrace) {
            let block = self.parse_block()?;
            return Ok(self.push("stmt_block", vec![block]));
        }

        let e = self.parse_expr()?;
        self.expect_semicolon()?;
        Ok(self.push("stmt_expr", vec![e]))
    }

    fn parse_if_block(&mut self) -> Result<u32, ParseError> {
        if !(self.eat(tokens::TokenKind::IfLBrace) || self.eat(tokens::TokenKind::LBrace)) {
            return Err(ParseError {
                pos: self.i,
                expected: "IfLBrace",
                found: self.peek(),
            });
        }
        let mut kids = Vec::new();
        while self.peek() != Some(tokens::TokenKind::IfRBrace)
            && self.peek() != Some(tokens::TokenKind::RBrace)
        {
            if self.peek().is_none() {
                return Err(ParseError {
                    pos: self.i,
                    expected: "IfRBrace",
                    found: None,
                });
            }
            kids.push(self.parse_stmt()?);
        }
        if !(self.eat(tokens::TokenKind::IfRBrace) || self.eat(tokens::TokenKind::RBrace)) {
            return Err(ParseError {
                pos: self.i,
                expected: "IfRBrace",
                found: self.peek(),
            });
        }
        Ok(self.push("block", kids))
    }

    // ------------- expressions --------------

    // expr -> assign
    fn parse_expr(&mut self) -> Result<u32, ParseError> {
        self.parse_assign()
    }

    // assign [set] -> orexpr 'Assign' assign | orexpr
    // Right-associative.
    fn parse_assign(&mut self) -> Result<u32, ParseError> {
        let lhs = self.parse_orexpr()?;
        if let Some(tag) = self.eat_assign_op() {
            let rhs = self.parse_assign()?;
            Ok(self.push(tag, vec![lhs, rhs]))
        } else {
            Ok(lhs)
        }
    }

    fn eat_assign_op(&mut self) -> Option<&'static str> {
        let ops = [
            (tokens::TokenKind::Assign, "set"),
            (tokens::TokenKind::PlusAssign, "add_set"),
            (tokens::TokenKind::MinusAssign, "sub_set"),
            (tokens::TokenKind::StarAssign, "mul_set"),
            (tokens::TokenKind::SlashAssign, "div_set"),
            (tokens::TokenKind::PercentAssign, "mod_set"),
            (tokens::TokenKind::CaretAssign, "xor_set"),
            (tokens::TokenKind::ShlAssign, "shl_set"),
            (tokens::TokenKind::ShrAssign, "shr_set"),
            (tokens::TokenKind::AmpAssign, "band_set"),
            (tokens::TokenKind::PipeAssign, "bor_set"),
        ];
        for (kind, tag) in ops {
            if self.eat(kind) {
                return Some(tag);
            }
        }
        None
    }

    // orexpr [or] / [base]
    // left-assoc: orexpr -> orexpr 'OrOr' andexpr | andexpr
    fn parse_orexpr(&mut self) -> Result<u32, ParseError> {
        let mut lhs = self.parse_andexpr()?;
        while self.eat(tokens::TokenKind::OrOr) {
            let rhs = self.parse_andexpr()?;
            lhs = self.push("or", vec![lhs, rhs]);
        }
        Ok(lhs)
    }

    // andexpr [and] / [base]
    fn parse_andexpr(&mut self) -> Result<u32, ParseError> {
        let mut lhs = self.parse_bit_or()?;
        while self.eat(tokens::TokenKind::AndAnd) {
            let rhs = self.parse_bit_or()?;
            lhs = self.push("and", vec![lhs, rhs]);
        }
        Ok(lhs)
    }

    fn parse_bit_or(&mut self) -> Result<u32, ParseError> {
        let mut lhs = self.parse_bit_xor()?;
        while self.eat(tokens::TokenKind::Pipe) {
            let rhs = self.parse_bit_xor()?;
            lhs = self.push("bor", vec![lhs, rhs]);
        }
        Ok(lhs)
    }

    fn parse_bit_xor(&mut self) -> Result<u32, ParseError> {
        let mut lhs = self.parse_bit_and()?;
        while self.eat(tokens::TokenKind::Caret) {
            let rhs = self.parse_bit_and()?;
            lhs = self.push("xor", vec![lhs, rhs]);
        }
        Ok(lhs)
    }

    fn parse_bit_and(&mut self) -> Result<u32, ParseError> {
        let mut lhs = self.parse_equality()?;
        while self.eat(tokens::TokenKind::Ampersand) {
            let rhs = self.parse_equality()?;
            lhs = self.push("band", vec![lhs, rhs]);
        }
        Ok(lhs)
    }

    // equality [eq] / [base]
    fn parse_equality(&mut self) -> Result<u32, ParseError> {
        let mut lhs = self.parse_compare()?;
        loop {
            if self.eat(tokens::TokenKind::EqEq) {
                let rhs = self.parse_compare()?;
                lhs = self.push("eq", vec![lhs, rhs]);
            } else if self.eat(tokens::TokenKind::NotEqual) {
                let rhs = self.parse_compare()?;
                lhs = self.push("ne", vec![lhs, rhs]);
            } else {
                break;
            }
        }
        Ok(lhs)
    }

    // compare [lt|gt|le|ge|base]
    fn parse_compare(&mut self) -> Result<u32, ParseError> {
        let mut lhs = self.parse_shift()?;
        loop {
            if self.eat(tokens::TokenKind::Lt) {
                let rhs = self.parse_shift()?;
                lhs = self.push("lt", vec![lhs, rhs]);
            } else if self.eat(tokens::TokenKind::Gt) {
                let rhs = self.parse_shift()?;
                lhs = self.push("gt", vec![lhs, rhs]);
            } else if self.eat(tokens::TokenKind::Le) {
                let rhs = self.parse_shift()?;
                lhs = self.push("le", vec![lhs, rhs]);
            } else if self.eat(tokens::TokenKind::Ge) {
                let rhs = self.parse_shift()?;
                lhs = self.push("ge", vec![lhs, rhs]);
            } else {
                break;
            }
        }
        Ok(lhs)
    }

    fn parse_shift(&mut self) -> Result<u32, ParseError> {
        let mut lhs = self.parse_add()?;
        loop {
            if self.eat(tokens::TokenKind::Shl) {
                let rhs = self.parse_add()?;
                lhs = self.push("shl", vec![lhs, rhs]);
            } else if self.eat(tokens::TokenKind::Shr) {
                let rhs = self.parse_add()?;
                lhs = self.push("shr", vec![lhs, rhs]);
            } else {
                break;
            }
        }
        Ok(lhs)
    }

    // add [add_l|sub_l|add_r]
    fn parse_add(&mut self) -> Result<u32, ParseError> {
        let mut lhs = self.parse_mul()?;
        loop {
            if self.eat(tokens::TokenKind::InfixPlus) || self.eat(tokens::TokenKind::Plus) {
                let rhs = self.parse_mul()?;
                lhs = self.push("add", vec![lhs, rhs]);
            } else if self.eat(tokens::TokenKind::InfixMinus) || self.eat(tokens::TokenKind::Minus)
            {
                let rhs = self.parse_mul()?;
                lhs = self.push("sub", vec![lhs, rhs]);
            } else {
                break;
            }
        }
        Ok(lhs)
    }

    // mul [mul_l|mul_r]
    fn parse_mul(&mut self) -> Result<u32, ParseError> {
        let mut lhs = self.parse_unary()?;
        loop {
            if self.eat(tokens::TokenKind::Star) {
                let rhs = self.parse_unary()?;
                lhs = self.push("mul", vec![lhs, rhs]);
            } else if self.eat(tokens::TokenKind::Slash) {
                let rhs = self.parse_unary()?;
                lhs = self.push("div", vec![lhs, rhs]);
            } else if self.eat(tokens::TokenKind::Percent) {
                let rhs = self.parse_unary()?;
                lhs = self.push("mod", vec![lhs, rhs]);
            } else {
                break;
            }
        }
        Ok(lhs)
    }

    // unary [pos|neg|not|base]
    fn parse_unary(&mut self) -> Result<u32, ParseError> {
        if self.eat(tokens::TokenKind::Inc) {
            let rhs = self.parse_unary()?;
            Ok(self.push("pre_inc", vec![rhs]))
        } else if self.eat(tokens::TokenKind::Dec) {
            let rhs = self.parse_unary()?;
            Ok(self.push("pre_dec", vec![rhs]))
        } else if self.eat(tokens::TokenKind::PrefixPlus) || self.eat(tokens::TokenKind::Plus) {
            let rhs = self.parse_unary()?;
            Ok(self.push("pos", vec![rhs]))
        } else if self.eat(tokens::TokenKind::PrefixMinus) || self.eat(tokens::TokenKind::Minus) {
            let rhs = self.parse_unary()?;
            Ok(self.push("neg", vec![rhs]))
        } else if self.eat(tokens::TokenKind::Not) {
            let rhs = self.parse_unary()?;
            Ok(self.push("not", vec![rhs]))
        } else if self.eat(tokens::TokenKind::Tilde) {
            let rhs = self.parse_unary()?;
            Ok(self.push("bit_not", vec![rhs]))
        } else {
            self.parse_postfix()
        }
    }

    // postfix [base|call|index] – left-assoc, repeatedly applies:
    //   base:     primary
    //   call:     postfix 'CallLParen' arg_list_opt 'CallRParen'
    //   index:    postfix 'IndexLBracket' expr 'IndexRBracket'
    fn parse_postfix(&mut self) -> Result<u32, ParseError> {
        let mut node = self.parse_primary()?;
        loop {
            if self.eat(tokens::TokenKind::CallLParen) || self.eat(tokens::TokenKind::LParen) {
                // arg_list_opt -> ; | expr arg_tail
                let mut args = Vec::new();
                if !self.eat(tokens::TokenKind::CallRParen) && !self.eat(tokens::TokenKind::RParen)
                {
                    // some
                    let first = self.parse_expr()?;
                    args.push(first);
                    // arg_tail -> 'Comma' expr arg_tail | ;
                    while self.eat(tokens::TokenKind::ArgComma)
                        || self.eat(tokens::TokenKind::Comma)
                    {
                        let a = self.parse_expr()?;
                        args.push(a);
                    }
                    if !self.eat(tokens::TokenKind::CallRParen) {
                        self.expect(tokens::TokenKind::RParen, "RParen")?;
                    }
                }
                // Node: call(callee, a1, a2, ...)
                let mut children = Vec::with_capacity(1 + args.len());
                children.push(node);
                children.extend(args);
                node = self.push("call", children);
                continue;
            }

            if self.eat(tokens::TokenKind::IndexLBracket) || self.eat(tokens::TokenKind::LBracket) {
                let index = self.parse_expr()?;
                if !self.eat(tokens::TokenKind::IndexRBracket) {
                    self.expect(tokens::TokenKind::RBracket, "RBracket")?;
                }
                node = self.push("index", vec![node, index]);
                continue;
            }

            if self.eat(tokens::TokenKind::Dot) {
                self.expect(tokens::TokenKind::Ident, "member name")?;
                let member = self.push("ident", vec![]);
                node = self.push("member", vec![node, member]);
                continue;
            }

            if self.eat(tokens::TokenKind::Inc) {
                node = self.push("post_inc", vec![node]);
                continue;
            }

            if self.eat(tokens::TokenKind::Dec) {
                node = self.push("post_dec", vec![node]);
                continue;
            }

            break;
        }
        Ok(node)
    }

    // primary [group|array_lit|ident|int|bool|string]
    //   group:      'GroupLParen' expr 'GroupRParen'
    //   array_lit:  'ArrayLBracket' array_elems_opt 'ArrayRBracket'
    //   ident:      'Ident'
    //   int:        'Int'
    //   string:     'String'
    fn parse_primary(&mut self) -> Result<u32, ParseError> {
        if self.eat(tokens::TokenKind::GroupLParen) || self.eat(tokens::TokenKind::LParen) {
            let e = self.parse_expr()?;
            if !self.eat(tokens::TokenKind::GroupRParen) {
                self.expect(tokens::TokenKind::RParen, "RParen")?;
            }
            return Ok(self.push("group", vec![e]));
        }

        if self.eat(tokens::TokenKind::ArrayLBracket) || self.eat(tokens::TokenKind::LBracket) {
            // array_elems_opt -> ; | expr array_elems_tail
            let mut elems = Vec::new();
            if !self.eat(tokens::TokenKind::ArrayRBracket) && !self.eat(tokens::TokenKind::RBracket)
            {
                let first = self.parse_expr()?;
                elems.push(first);
                // array_elems_tail -> 'Comma' expr array_elems_tail | ;
                while self.eat(tokens::TokenKind::ArrayComma) || self.eat(tokens::TokenKind::Comma)
                {
                    let e = self.parse_expr()?;
                    elems.push(e);
                }
                if !self.eat(tokens::TokenKind::ArrayRBracket) {
                    self.expect(tokens::TokenKind::RBracket, "RBracket")?;
                }
            }
            return Ok(self.push("array_lit", elems));
        }

        if self.eat(tokens::TokenKind::Ident) {
            let ident = self.push("ident", vec![]);
            if self.eat(tokens::TokenKind::LBrace) {
                let mut fields = Vec::new();
                if !self.eat(tokens::TokenKind::RBrace) {
                    fields.push(self.parse_struct_lit_field()?);
                    while self.eat(tokens::TokenKind::Comma)
                        || self.eat(tokens::TokenKind::ArgComma)
                    {
                        if self.eat(tokens::TokenKind::RBrace) {
                            break;
                        }
                        fields.push(self.parse_struct_lit_field()?);
                    }
                    if !self.eat(tokens::TokenKind::RBrace) {
                        self.expect(tokens::TokenKind::RBrace, "RBrace")?;
                    }
                }
                let mut children = Vec::with_capacity(1 + fields.len());
                children.push(ident);
                children.extend(fields);
                return Ok(self.push("struct_lit", children));
            }
            return Ok(ident);
        }
        if self.eat(tokens::TokenKind::Int) {
            return Ok(self.push("int", vec![]));
        }
        if self.eat(tokens::TokenKind::True) {
            return Ok(self.push("true", vec![]));
        }
        if self.eat(tokens::TokenKind::False) {
            return Ok(self.push("false", vec![]));
        }
        if self.eat(tokens::TokenKind::Float) {
            return Ok(self.push("float", vec![]));
        }
        if self.eat(tokens::TokenKind::String) {
            return Ok(self.push("string", vec![]));
        }
        if self.eat(tokens::TokenKind::Char) {
            return Ok(self.push("char", vec![]));
        }

        Err(ParseError {
            pos: self.i,
            expected: "primary",
            found: self.peek(),
        })
    }

    fn parse_struct_lit_field(&mut self) -> Result<u32, ParseError> {
        if !self.eat(tokens::TokenKind::Ident) && !self.eat(tokens::TokenKind::TypeIdent) {
            self.expect(tokens::TokenKind::Ident, "struct literal field name")?;
        }
        let name = self.push("ident", vec![]);
        self.expect(tokens::TokenKind::Colon, "Colon")?;
        let value = self.parse_expr()?;
        Ok(self.push("struct_lit_field", vec![name, value]))
    }
}
