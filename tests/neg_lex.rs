//! Negative lexer tests that should fail on CPU (lex_on_cpu returns Err).

use laniusc::lexer::cpu::lex_on_cpu;

#[test]
fn unterminated_string_eof() {
    let src = "s=\"hello"; // missing closing quote
    assert!(lex_on_cpu(src).is_err(), "unterminated string should error");
}

#[test]
fn newline_in_string() {
    let src = "s=\"hello\nworld\""; // newline inside string not allowed
    assert!(lex_on_cpu(src).is_err(), "newline in string should error");
}

#[test]
fn unterminated_char_eof() {
    let src = "c='a"; // missing closing quote
    assert!(lex_on_cpu(src).is_err(), "unterminated char should error");
}

#[test]
fn unterminated_block_comment() {
    let src = "a = 1 /* comment"; // no closing */
    assert!(lex_on_cpu(src).is_err(), "unterminated block comment should error");
}

