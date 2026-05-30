//! Lexical formatter for the currently supported alpha language slice.
//!
//! This formatter intentionally does not parse or typecheck on the CPU. It keeps
//! every non-whitespace token spelling intact and only synthesizes conservative
//! whitespace, newlines, and brace indentation around lexical boundaries.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum TokenKind {
    Atom,
    Word,
    StringLike,
    LineComment,
    BlockComment,
    OpenParen,
    CloseParen,
    OpenBracket,
    CloseBracket,
    OpenBrace,
    CloseBrace,
    Comma,
    Semicolon,
    Colon,
    PathColon,
    Dot,
    Arrow,
    Assignment,
    Minus,
    Bang,
    SpacedOperator,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Token<'a> {
    kind: TokenKind,
    text: &'a str,
}

/// Format Lanius source using only bounded lexical whitespace rules.
///
/// The API is intentionally conservative for `unstable-alpha`: it does not
/// perform CPU parsing, CPU type checking, import resolution, or semantic
/// rewriting. String literals, character literals, comments, identifiers, and
/// punctuation are copied exactly as they appear in the input.
#[must_use]
pub fn format_source(source: &str) -> String {
    let tokens = tokenize(source);
    if tokens.is_empty() {
        return String::new();
    }

    let mut formatter = Formatter::new(source.len());
    formatter.write_tokens(&tokens);
    formatter.finish()
}

struct Formatter {
    out: String,
    indent: usize,
    paren_depth: usize,
    bracket_depth: usize,
    line_start: bool,
    compact_next_token: bool,
    where_clause: bool,
    where_angle_depth: usize,
}

impl Formatter {
    fn new(source_len: usize) -> Self {
        Self {
            out: String::with_capacity(source_len.saturating_add(source_len / 8)),
            indent: 0,
            paren_depth: 0,
            bracket_depth: 0,
            line_start: true,
            compact_next_token: false,
            where_clause: false,
            where_angle_depth: 0,
        }
    }

    fn write_tokens(&mut self, tokens: &[Token<'_>]) {
        for i in 0..tokens.len() {
            let token = tokens[i];
            let prev = i.checked_sub(1).map(|prev_i| tokens[prev_i]);
            let next = tokens.get(i + 1).copied();

            match token.kind {
                TokenKind::OpenBrace => self.write_open_brace(prev, token),
                TokenKind::CloseBrace => self.write_close_brace(next, token),
                TokenKind::Semicolon => self.write_semicolon(token),
                TokenKind::Comma => self.write_comma(prev, next, token),
                TokenKind::LineComment => self.write_line_comment(token),
                TokenKind::BlockComment => self.write_block_comment(prev, token),
                TokenKind::Minus => self.write_minus(prev, token),
                TokenKind::Bang => self.write_bang(prev, token),
                TokenKind::Word if token.text == "where" => self.write_where_keyword(token),
                TokenKind::OpenParen => {
                    self.write_regular_token(prev, token);
                    self.paren_depth = self.paren_depth.saturating_add(1);
                }
                TokenKind::CloseParen => {
                    self.write_regular_token(prev, token);
                    self.paren_depth = self.paren_depth.saturating_sub(1);
                }
                TokenKind::OpenBracket => {
                    self.write_regular_token(prev, token);
                    self.bracket_depth = self.bracket_depth.saturating_add(1);
                }
                TokenKind::CloseBracket => {
                    self.write_regular_token(prev, token);
                    self.bracket_depth = self.bracket_depth.saturating_sub(1);
                }
                _ => self.write_regular_token(prev, token),
            }
        }
    }

    fn finish(mut self) -> String {
        trim_line_end(&mut self.out);
        if !self.out.is_empty() && !self.out.ends_with('\n') {
            self.out.push('\n');
        }
        self.out
    }

    fn write_open_brace(&mut self, prev: Option<Token<'_>>, token: Token<'_>) {
        self.compact_next_token = false;
        if self.where_clause {
            self.where_clause = false;
            self.where_angle_depth = 0;
            if !self.line_start {
                self.newline();
            }
        } else if needs_space_before(prev, token) {
            self.ensure_space();
        }
        self.write_raw_token(token.text);
        self.indent = self.indent.saturating_add(1);
        self.newline();
    }

    fn write_close_brace(&mut self, next: Option<Token<'_>>, token: Token<'_>) {
        self.compact_next_token = false;
        self.where_clause = false;
        self.where_angle_depth = 0;
        self.indent = self.indent.saturating_sub(1);
        if !self.line_start {
            self.newline();
        }
        self.write_raw_token(token.text);
        match next.map(|token| token.kind) {
            Some(TokenKind::Comma | TokenKind::Semicolon) => {}
            _ if next.map(|token| token.text) == Some("else") => self.ensure_space(),
            Some(_) => self.newline(),
            None => {}
        }
    }

    fn write_semicolon(&mut self, token: Token<'_>) {
        self.compact_next_token = false;
        trim_line_end(&mut self.out);
        self.write_raw_token(token.text);
        self.where_clause = false;
        self.where_angle_depth = 0;
        if self.paren_depth == 0 && self.bracket_depth == 0 {
            self.newline();
        } else {
            self.ensure_space();
        }
    }

    fn write_comma(&mut self, prev: Option<Token<'_>>, next: Option<Token<'_>>, token: Token<'_>) {
        self.compact_next_token = false;
        trim_line_end(&mut self.out);
        self.write_raw_token(token.text);
        match next.map(|token| token.kind) {
            Some(TokenKind::CloseParen | TokenKind::CloseBracket | TokenKind::CloseBrace)
            | None => {}
            _ if prev.is_some_and(|prev| prev.kind == TokenKind::CloseBrace)
                && self.paren_depth == 0
                && self.bracket_depth == 0 =>
            {
                self.newline();
            }
            _ if self.indent > 0 && self.paren_depth == 0 && self.bracket_depth == 0 => {
                self.newline();
            }
            _ if self.where_clause
                && self.paren_depth == 0
                && self.bracket_depth == 0
                && self.where_angle_depth == 0 =>
            {
                self.newline();
            }
            _ => self.ensure_space(),
        }
    }

    fn write_line_comment(&mut self, token: Token<'_>) {
        self.compact_next_token = false;
        if !self.line_start {
            self.ensure_space();
        }
        self.write_raw_token(token.text);
        self.newline();
    }

    fn write_block_comment(&mut self, prev: Option<Token<'_>>, token: Token<'_>) {
        self.compact_next_token = false;
        let standalone = self.line_start;
        if !standalone && needs_space_before(prev, token) {
            self.ensure_space();
        }
        self.write_raw_token(token.text);
        if standalone {
            self.newline();
        }
    }

    fn write_minus(&mut self, prev: Option<Token<'_>>, token: Token<'_>) {
        let after_prefix_minus = self.compact_next_token;
        self.compact_next_token = false;
        let prefix = is_prefix_minus(prev);

        if after_prefix_minus || prev.is_some_and(|token| token.kind == TokenKind::Minus) {
            self.ensure_space();
        } else if prefix {
            if needs_space_before_prefix_operator(prev) {
                self.ensure_space();
            }
        } else {
            self.ensure_space();
        }

        self.write_raw_token(token.text);

        if prefix {
            self.compact_next_token = true;
        } else {
            self.ensure_space();
        }
    }

    fn write_bang(&mut self, prev: Option<Token<'_>>, token: Token<'_>) {
        if !self.compact_next_token && needs_space_before_prefix_operator(prev) {
            self.ensure_space();
        }
        self.write_raw_token(token.text);
        self.compact_next_token = true;
    }

    fn write_where_keyword(&mut self, token: Token<'_>) {
        self.compact_next_token = false;
        if !self.line_start {
            self.newline();
        }
        self.write_raw_token(token.text);
        self.newline();
        self.where_clause = true;
        self.where_angle_depth = 0;
    }

    fn write_regular_token(&mut self, prev: Option<Token<'_>>, token: Token<'_>) {
        let compact = self.compact_next_token;
        self.compact_next_token = false;
        if !compact && needs_space_before(prev, token) {
            self.ensure_space();
        }
        self.write_raw_token(token.text);
        self.update_where_angle_depth(token);
    }

    fn update_where_angle_depth(&mut self, token: Token<'_>) {
        if !self.where_clause || token.kind != TokenKind::Atom {
            return;
        }

        match token.text {
            "<" => self.where_angle_depth = self.where_angle_depth.saturating_add(1),
            ">" => self.where_angle_depth = self.where_angle_depth.saturating_sub(1),
            _ => {}
        }
    }

    fn write_raw_token(&mut self, text: &str) {
        if self.line_start {
            let indent = self.indent + usize::from(self.where_clause);
            for _ in 0..indent {
                self.out.push_str("    ");
            }
            self.line_start = false;
        }
        self.out.push_str(text);
    }

    fn ensure_space(&mut self) {
        if self.line_start
            || matches!(
                self.out.as_bytes().last(),
                None | Some(b' ' | b'\n' | b'\t')
            )
        {
            return;
        }
        self.out.push(' ');
    }

    fn newline(&mut self) {
        trim_line_end(&mut self.out);
        if !self.out.is_empty() && !self.out.ends_with('\n') {
            self.out.push('\n');
        }
        self.line_start = true;
    }
}

fn tokenize(source: &str) -> Vec<Token<'_>> {
    let mut tokens = Vec::new();
    let mut i = 0;

    while i < source.len() {
        let Some(ch) = source[i..].chars().next() else {
            break;
        };

        if ch.is_whitespace() {
            i += ch.len_utf8();
            continue;
        }

        if starts_with(source, i, "//") {
            let mut end = source[i..]
                .find('\n')
                .map(|offset| i + offset)
                .unwrap_or(source.len());
            if source[..end].ends_with('\r') {
                end -= 1;
            }
            tokens.push(Token {
                kind: TokenKind::LineComment,
                text: &source[i..end],
            });
            i = end;
            continue;
        }

        if starts_with(source, i, "/*") {
            let end = source[i + 2..]
                .find("*/")
                .map(|offset| i + 2 + offset + 2)
                .unwrap_or(source.len());
            tokens.push(Token {
                kind: TokenKind::BlockComment,
                text: &source[i..end],
            });
            i = end;
            continue;
        }

        if ch == '"' || ch == '\'' {
            let end = quoted_literal_end(source, i, ch);
            tokens.push(Token {
                kind: TokenKind::StringLike,
                text: &source[i..end],
            });
            i = end;
            continue;
        }

        if is_word_start(ch) {
            let end = word_end(source, i);
            tokens.push(Token {
                kind: TokenKind::Word,
                text: &source[i..end],
            });
            i = end;
            continue;
        }

        let (kind, width) = punctuator(source, i, ch);
        tokens.push(Token {
            kind,
            text: &source[i..i + width],
        });
        i += width;
    }

    tokens
}

fn quoted_literal_end(source: &str, start: usize, quote: char) -> usize {
    let mut escaped = false;
    let mut i = start + quote.len_utf8();

    while i < source.len() {
        let Some(ch) = source[i..].chars().next() else {
            break;
        };
        i += ch.len_utf8();

        if escaped {
            escaped = false;
            continue;
        }
        if ch == '\\' {
            escaped = true;
            continue;
        }
        if ch == quote {
            break;
        }
    }

    i
}

fn word_end(source: &str, start: usize) -> usize {
    let mut i = start;
    while i < source.len() {
        let Some(ch) = source[i..].chars().next() else {
            break;
        };
        if !is_word_continue(ch) {
            break;
        }
        i += ch.len_utf8();
    }
    i
}

fn punctuator(source: &str, i: usize, ch: char) -> (TokenKind, usize) {
    for (text, kind) in [
        (">>=", TokenKind::SpacedOperator),
        ("<<=", TokenKind::SpacedOperator),
        ("::", TokenKind::PathColon),
        ("->", TokenKind::Arrow),
        ("=>", TokenKind::Arrow),
        ("==", TokenKind::SpacedOperator),
        ("!=", TokenKind::SpacedOperator),
        ("<=", TokenKind::SpacedOperator),
        (">=", TokenKind::SpacedOperator),
        ("&&", TokenKind::SpacedOperator),
        ("||", TokenKind::SpacedOperator),
        ("+=", TokenKind::SpacedOperator),
        ("-=", TokenKind::SpacedOperator),
        ("*=", TokenKind::SpacedOperator),
        ("/=", TokenKind::SpacedOperator),
        ("%=", TokenKind::SpacedOperator),
        ("^=", TokenKind::SpacedOperator),
        ("<<", TokenKind::SpacedOperator),
        (">>", TokenKind::SpacedOperator),
        ("++", TokenKind::Atom),
        ("--", TokenKind::Atom),
    ] {
        if starts_with(source, i, text) {
            return (kind, text.len());
        }
    }

    let kind = match ch {
        '(' => TokenKind::OpenParen,
        ')' => TokenKind::CloseParen,
        '[' => TokenKind::OpenBracket,
        ']' => TokenKind::CloseBracket,
        '{' => TokenKind::OpenBrace,
        '}' => TokenKind::CloseBrace,
        ',' => TokenKind::Comma,
        ';' => TokenKind::Semicolon,
        ':' => TokenKind::Colon,
        '.' => TokenKind::Dot,
        '=' => TokenKind::Assignment,
        '-' => TokenKind::Minus,
        '!' => TokenKind::Bang,
        '+' | '*' | '/' | '%' => TokenKind::SpacedOperator,
        _ => TokenKind::Atom,
    };
    (kind, ch.len_utf8())
}

fn needs_space_before(prev: Option<Token<'_>>, current: Token<'_>) -> bool {
    let Some(prev) = prev else {
        return false;
    };

    match (prev.kind, current.kind) {
        (TokenKind::PathColon | TokenKind::Dot, _) | (_, TokenKind::PathColon | TokenKind::Dot) => {
            false
        }
        (_, TokenKind::CloseParen | TokenKind::CloseBracket | TokenKind::CloseBrace) => false,
        (TokenKind::OpenParen | TokenKind::OpenBracket, _) => false,
        (_, TokenKind::OpenBrace) => true,
        (_, TokenKind::OpenParen) => {
            prev.text == "if" || prev.text == "while" || prev.text == "match"
        }
        (_, TokenKind::OpenBracket) => false,
        (_, TokenKind::Comma | TokenKind::Semicolon | TokenKind::Colon) => false,
        (TokenKind::Colon, _) => true,
        (TokenKind::Assignment | TokenKind::Arrow | TokenKind::SpacedOperator, _) => true,
        (_, TokenKind::Assignment | TokenKind::Arrow | TokenKind::SpacedOperator) => true,
        (
            TokenKind::Word
            | TokenKind::StringLike
            | TokenKind::LineComment
            | TokenKind::BlockComment,
            TokenKind::Word
            | TokenKind::StringLike
            | TokenKind::LineComment
            | TokenKind::BlockComment,
        ) => true,
        (
            TokenKind::CloseParen | TokenKind::CloseBracket,
            TokenKind::Word | TokenKind::StringLike | TokenKind::BlockComment,
        ) => true,
        _ => false,
    }
}

fn is_prefix_minus(prev: Option<Token<'_>>) -> bool {
    let Some(prev) = prev else {
        return true;
    };

    match prev.kind {
        TokenKind::OpenParen
        | TokenKind::OpenBracket
        | TokenKind::OpenBrace
        | TokenKind::Comma
        | TokenKind::Semicolon
        | TokenKind::Colon
        | TokenKind::Assignment
        | TokenKind::Arrow
        | TokenKind::Minus
        | TokenKind::SpacedOperator => true,
        TokenKind::Word => matches!(prev.text, "if" | "match" | "return" | "while"),
        _ => false,
    }
}

fn needs_space_before_prefix_operator(prev: Option<Token<'_>>) -> bool {
    prev.is_some_and(|prev| {
        !matches!(
            prev.kind,
            TokenKind::OpenParen | TokenKind::OpenBracket | TokenKind::OpenBrace
        )
    })
}

fn starts_with(source: &str, offset: usize, needle: &str) -> bool {
    source
        .get(offset..)
        .is_some_and(|tail| tail.starts_with(needle))
}

fn is_word_start(ch: char) -> bool {
    ch == '_' || ch.is_ascii_alphanumeric()
}

fn is_word_continue(ch: char) -> bool {
    ch == '_' || ch.is_ascii_alphanumeric()
}

fn trim_line_end(out: &mut String) {
    while matches!(out.as_bytes().last(), Some(b' ' | b'\t')) {
        out.pop();
    }
}
