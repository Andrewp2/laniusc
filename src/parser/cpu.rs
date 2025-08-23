// src/parser/cpu.rs
//
// A plain CPU recursive-descent parser for the grammar in grammar/lanius.bnf.
// Extended to accept file items, blocks, and statements so that realistic
// samples like parser_tests/file.lani parse successfully.
//
// - Expressions are exactly as before (assign/or/and/eq/compare/add/mul/unary/postfix/primary).
// - NEW:
//     * file-or-expr entrypoint that recognizes a top-level fn-item or a block,
//       otherwise falls back to expression parsing.
//     * blocks: { stmt* } with semicolon-separated statements
//     * let statements via a soft-keyword shape: Ident Ident Assign ...
//       (we skip the first Ident and parse the assignment).
//
// AST nodes now include: "fn", "block", "stmt_let", "stmt_expr" in addition to
// the previous tags.
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
    /// plus file/stmt additions: "fn", "block", "stmt_let", "stmt_expr".
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

/// Public entrypoint: parse a full file-or-expression with the CPU parser.
///
/// Behavior:
/// - If input looks like a top-level fn item (optionally `pub fn name(...) { ... }`), parse that.
/// - Else if it starts with a block `{ ... }`, parse the block.
/// - Else parse a single expression (the previous behavior).
pub fn parse_from_token_kinds(kinds: &[tokens::TokenKind]) -> Result<Ast, ParseError> {
    let mut p = Parser {
        kinds,
        i: 0,
        nodes: Vec::new(),
    };

    let root = if p.looks_like_fn_item() {
        p.parse_fn_item()?
    } else if p.peek_is_lbrace() {
        p.parse_block()?
    } else {
        // default to the original expression parser
        p.parse_expr()?
    };

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

    fn la(&self, n: usize) -> Option<tokens::TokenKind> {
        self.kinds.get(self.i + n).copied()
    }

    fn bump(&mut self) -> Option<tokens::TokenKind> {
        let k = self.peek()?;
        self.i += 1;
        Some(k)
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

    fn is_open_paren(k: tokens::TokenKind) -> bool {
        matches!(
            k,
            tokens::TokenKind::GroupLParen
                | tokens::TokenKind::CallLParen
                | tokens::TokenKind::LParen
        )
    }

    fn is_open_bracket(k: tokens::TokenKind) -> bool {
        matches!(
            k,
            tokens::TokenKind::ArrayLBracket
                | tokens::TokenKind::IndexLBracket
                | tokens::TokenKind::LBracket
        )
    }

    fn peek_is_lbrace(&self) -> bool {
        self.peek() == Some(tokens::TokenKind::LBrace)
    }

    /// Heuristic: does the file start like `[pub] fn name ( ... ) {` ?
    /// We don't have keyword tokens; we look for:
    ///   Ident Ident Ident '(' or Ident Ident '('
    /// followed by a block `{ ... }` (we only check the paren now, the block is parsed later).
    fn looks_like_fn_item(&self) -> bool {
        match (self.la(0), self.la(1), self.la(2), self.la(3)) {
            // pub fn name (
            (
                Some(tokens::TokenKind::Ident),
                Some(tokens::TokenKind::Ident),
                Some(tokens::TokenKind::Ident),
                Some(op),
            ) if Parser::is_open_paren(op) => true,
            // fn name (
            (Some(tokens::TokenKind::Ident), Some(tokens::TokenKind::Ident), Some(op), _)
                if Parser::is_open_paren(op) =>
            {
                true
            }
            _ => false,
        }
    }

    /// Skip a balanced parenthesis group starting at the current token (which must be an open paren).
    /// Also tolerates nested brackets inside param lists (e.g. array types like `[u32; 10]`).
    fn skip_balanced_parens(&mut self) -> Result<(), ParseError> {
        let mut paren_depth = 0i32;
        let mut bracket_depth = 0i32;

        // first must be an open paren
        let k = self.bump().ok_or(ParseError {
            pos: self.i,
            expected: "open paren",
            found: None,
        })?;
        if !Parser::is_open_paren(k) {
            return Err(ParseError {
                pos: self.i - 1,
                expected: "open paren",
                found: Some(k),
            });
        }
        paren_depth += 1;

        while paren_depth > 0 {
            let Some(k) = self.bump() else {
                return Err(ParseError {
                    pos: self.i,
                    expected: "RParen",
                    found: None,
                });
            };
            if Parser::is_open_paren(k) {
                paren_depth += 1;
            } else if k == tokens::TokenKind::RParen {
                paren_depth -= 1;
            } else if Parser::is_open_bracket(k) {
                bracket_depth += 1;
            } else if k == tokens::TokenKind::RBracket {
                if bracket_depth == 0 {
                    return Err(ParseError {
                        pos: self.i - 1,
                        expected: "matching RBracket",
                        found: Some(k),
                    });
                }
                bracket_depth -= 1;
            } else {
                // other tokens are fine (idents, commas, colons, semicolons, ints, etc.)
            }
        }
        Ok(())
    }

    // ------------- file / items / statements -------------

    /// Parse a top-level `fn` item with optional leading `pub` (both seen as `Ident`).
    /// Grammar (soft-keyword heuristic):
    ///   item_fn -> [Ident] Ident Ident '(' params ')' block
    ///              ^pub?   ^fn   ^name
    fn parse_fn_item(&mut self) -> Result<u32, ParseError> {
        // Accept either 3 idents before '(' (pub fn name) or 2 (fn name).
        let name_is_at = if matches!(self.la(0), Some(tokens::TokenKind::Ident))
            && matches!(self.la(1), Some(tokens::TokenKind::Ident))
            && matches!(self.la(2), Some(tokens::TokenKind::Ident))
            && self.la(3).map_or(false, Parser::is_open_paren)
        {
            2usize // pub, fn, name
        } else if matches!(self.la(0), Some(tokens::TokenKind::Ident))
            && matches!(self.la(1), Some(tokens::TokenKind::Ident))
            && self.la(2).map_or(false, Parser::is_open_paren)
        {
            1usize // fn, name
        } else {
            return Err(ParseError {
                pos: self.i,
                expected: "fn item",
                found: self.peek(),
            });
        };

        // Consume leading idents up to the name.
        for _ in 0..name_is_at {
            let _ = self.bump(); // 'pub' and/or 'fn'
        }

        // Name
        self.expect(tokens::TokenKind::Ident, "function name")?;
        let name_id = self.push("ident", vec![]);

        // Params (skip balanced, we don't build a typed AST for them here)
        if !self.peek().map_or(false, Parser::is_open_paren) {
            return Err(ParseError {
                pos: self.i,
                expected: "function parameter list",
                found: self.peek(),
            });
        }
        self.skip_balanced_parens()?;

        // Body block
        let body = self.parse_block()?;
        Ok(self.push("fn", vec![name_id, body]))
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

    /// Parse a statement:
    ///   - let-stmt (soft keyword): Ident Ident Assign assign ';'?
    ///                               ^let   ^name
    ///   - expr-stmt: expr ';'?
    fn parse_stmt(&mut self) -> Result<u32, ParseError> {
        // let-stmt heuristic: Ident Ident Assign ...
        if matches!(self.la(0), Some(tokens::TokenKind::Ident))
            && matches!(self.la(1), Some(tokens::TokenKind::Ident))
            && matches!(self.la(2), Some(tokens::TokenKind::Assign))
        {
            // consume the leading "let" ident (soft keyword)
            let _let_kw = self.bump();
            // now parse as a normal assignment starting from the variable ident
            let set = self.parse_assign()?;
            let _ = self.eat(tokens::TokenKind::Semicolon);
            return Ok(self.push("stmt_let", vec![set]));
        }

        // expr-stmt
        let e = self.parse_expr()?;
        let _ = self.eat(tokens::TokenKind::Semicolon);
        Ok(self.push("stmt_expr", vec![e]))
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
        if self.eat(tokens::TokenKind::Assign) {
            let rhs = self.parse_assign()?;
            Ok(self.push("set", vec![lhs, rhs]))
        } else {
            Ok(lhs)
        }
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
        let mut lhs = self.parse_equality()?;
        while self.eat(tokens::TokenKind::AndAnd) {
            let rhs = self.parse_equality()?;
            lhs = self.push("and", vec![lhs, rhs]);
        }
        Ok(lhs)
    }

    // equality [eq] / [base]
    fn parse_equality(&mut self) -> Result<u32, ParseError> {
        let mut lhs = self.parse_compare()?;
        while self.eat(tokens::TokenKind::EqEq) {
            let rhs = self.parse_compare()?;
            lhs = self.push("eq", vec![lhs, rhs]);
        }
        Ok(lhs)
    }

    // compare [lt|gt|le|ge|base]
    fn parse_compare(&mut self) -> Result<u32, ParseError> {
        let mut lhs = self.parse_add()?;
        loop {
            if self.eat(tokens::TokenKind::Lt) {
                let rhs = self.parse_add()?;
                lhs = self.push("lt", vec![lhs, rhs]);
            } else if self.eat(tokens::TokenKind::Gt) {
                let rhs = self.parse_add()?;
                lhs = self.push("gt", vec![lhs, rhs]);
            } else if self.eat(tokens::TokenKind::Le) {
                let rhs = self.parse_add()?;
                lhs = self.push("le", vec![lhs, rhs]);
            } else if self.eat(tokens::TokenKind::Ge) {
                let rhs = self.parse_add()?;
                lhs = self.push("ge", vec![lhs, rhs]);
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
            if self.eat(tokens::TokenKind::Plus) {
                let rhs = self.parse_mul()?;
                lhs = self.push("add", vec![lhs, rhs]);
            } else if self.eat(tokens::TokenKind::Minus) {
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
        while self.eat(tokens::TokenKind::Star) {
            let rhs = self.parse_unary()?;
            lhs = self.push("mul", vec![lhs, rhs]);
        }
        Ok(lhs)
    }

    // unary [pos|neg|not|base]
    fn parse_unary(&mut self) -> Result<u32, ParseError> {
        if self.eat(tokens::TokenKind::Plus) {
            let rhs = self.parse_unary()?;
            Ok(self.push("pos", vec![rhs]))
        } else if self.eat(tokens::TokenKind::Minus) {
            let rhs = self.parse_unary()?;
            Ok(self.push("neg", vec![rhs]))
        } else if self.eat(tokens::TokenKind::Not) {
            let rhs = self.parse_unary()?;
            Ok(self.push("not", vec![rhs]))
        } else {
            self.parse_postfix()
        }
    }

    // postfix [base|call|index] – left-assoc, repeatedly applies:
    //   base:     primary
    //   call:     postfix 'CallLParen' arg_list_opt 'RParen'
    //   index:    postfix 'IndexLBracket' expr 'RBracket'
    fn parse_postfix(&mut self) -> Result<u32, ParseError> {
        let mut node = self.parse_primary()?;
        loop {
            if self.eat(tokens::TokenKind::CallLParen) || self.eat(tokens::TokenKind::LParen) {
                // arg_list_opt -> ; | expr arg_tail
                let mut args = Vec::new();
                if !self.eat(tokens::TokenKind::RParen) {
                    // some
                    let first = self.parse_expr()?;
                    args.push(first);
                    // arg_tail -> 'Comma' expr arg_tail | ;
                    while self.eat(tokens::TokenKind::Comma) {
                        let a = self.parse_expr()?;
                        args.push(a);
                    }
                    self.expect(tokens::TokenKind::RParen, "RParen")?;
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
                self.expect(tokens::TokenKind::RBracket, "RBracket")?;
                node = self.push("index", vec![node, index]);
                continue;
            }

            break;
        }
        Ok(node)
    }

    // primary [group|array_lit|ident|int|string]
    //   group:      '(' expr ')'
    //   array_lit:  '[' array_elems_opt ']'
    //   ident:      'Ident'
    //   int:        'Int'
    //   string:     'String'
    fn parse_primary(&mut self) -> Result<u32, ParseError> {
        if self.eat(tokens::TokenKind::GroupLParen) || self.eat(tokens::TokenKind::LParen) {
            let e = self.parse_expr()?;
            self.expect(tokens::TokenKind::RParen, "RParen")?;
            return Ok(self.push("group", vec![e]));
        }

        if self.eat(tokens::TokenKind::ArrayLBracket) || self.eat(tokens::TokenKind::LBracket) {
            // array_elems_opt -> ; | expr array_elems_tail
            let mut elems = Vec::new();
            if !self.eat(tokens::TokenKind::RBracket) {
                let first = self.parse_expr()?;
                elems.push(first);
                // array_elems_tail -> 'Comma' expr array_elems_tail | ;
                while self.eat(tokens::TokenKind::Comma) {
                    let e = self.parse_expr()?;
                    elems.push(e);
                }
                self.expect(tokens::TokenKind::RBracket, "RBracket")?;
            }
            return Ok(self.push("array_lit", elems));
        }

        if self.eat(tokens::TokenKind::Ident) {
            return Ok(self.push("ident", vec![]));
        }
        if self.eat(tokens::TokenKind::Int) {
            return Ok(self.push("int", vec![]));
        }
        if self.eat(tokens::TokenKind::String) {
            return Ok(self.push("string", vec![]));
        }

        Err(ParseError {
            pos: self.i,
            expected: "primary",
            found: self.peek(),
        })
    }
}
