import Lanius.Basic

namespace Lanius.Compiler

/-- Raw lexer token identities. Their explicit codes are the compatibility
    boundary with the production GPU compiler; parser-context retags are not
    raw lexer tokens. -/
inductive TokenKind where
  | identifier
  | integer
  | whitespace
  | leftParen
  | rightParen
  | plus
  | star
  | assign
  | slash
  | lineComment
  | blockComment
  | less
  | greater
  | lessEqual
  | greaterEqual
  | equal
  | logicalAnd
  | logicalOr
  | not
  | leftBracket
  | rightBracket
  | leftBrace
  | rightBrace
  | angleGeneric
  | ampersand
  | pipe
  | minus
  | string
  | float
  | character
  | dot
  | comma
  | semicolon
  | colon
  | question
  | notEqual
  | percent
  | caret
  | shiftLeft
  | shiftRight
  | tilde
  | plusAssign
  | minusAssign
  | starAssign
  | slashAssign
  | percentAssign
  | caretAssign
  | shiftLeftAssign
  | shiftRightAssign
  | ampersandAssign
  | pipeAssign
  | increment
  | decrement
  | pubKeyword
  | fnKeyword
  | letKeyword
  | returnKeyword
  | ifKeyword
  | elseKeyword
  | whileKeyword
  | breakKeyword
  | continueKeyword
  | arrow
  | trueKeyword
  | falseKeyword
  | constKeyword
  | enumKeyword
  | structKeyword
  | matchKeyword
  | importKeyword
  | moduleKeyword
  | implKeyword
  | traitKeyword
  | forKeyword
  | inKeyword
  | externKeyword
  | typeKeyword
  | whereKeyword
  | selfKeyword
  | matchArrow
  | dotDot
  | dotDotEqual
deriving DecidableEq, Repr

def TokenKind.gpuCode : TokenKind → Nat
  | .identifier => 1
  | .integer => 2
  | .whitespace => 3
  | .leftParen => 4
  | .rightParen => 5
  | .plus => 6
  | .star => 7
  | .assign => 8
  | .slash => 9
  | .lineComment => 10
  | .blockComment => 11
  | .less => 12
  | .greater => 13
  | .lessEqual => 14
  | .greaterEqual => 15
  | .equal => 16
  | .logicalAnd => 17
  | .logicalOr => 18
  | .not => 19
  | .leftBracket => 20
  | .rightBracket => 21
  | .leftBrace => 22
  | .rightBrace => 23
  | .angleGeneric => 24
  | .ampersand => 25
  | .pipe => 26
  | .minus => 27
  | .string => 32
  | .float => 33
  | .character => 34
  | .dot => 35
  | .comma => 36
  | .semicolon => 37
  | .colon => 38
  | .question => 39
  | .notEqual => 40
  | .percent => 41
  | .caret => 42
  | .shiftLeft => 43
  | .shiftRight => 44
  | .tilde => 45
  | .plusAssign => 46
  | .minusAssign => 47
  | .starAssign => 48
  | .slashAssign => 49
  | .percentAssign => 50
  | .caretAssign => 51
  | .shiftLeftAssign => 52
  | .shiftRightAssign => 53
  | .ampersandAssign => 54
  | .pipeAssign => 55
  | .increment => 56
  | .decrement => 57
  | .pubKeyword => 66
  | .fnKeyword => 67
  | .letKeyword => 68
  | .returnKeyword => 69
  | .ifKeyword => 70
  | .elseKeyword => 71
  | .whileKeyword => 72
  | .breakKeyword => 73
  | .continueKeyword => 74
  | .arrow => 75
  | .trueKeyword => 90
  | .falseKeyword => 91
  | .constKeyword => 92
  | .enumKeyword => 93
  | .structKeyword => 94
  | .matchKeyword => 95
  | .importKeyword => 96
  | .moduleKeyword => 97
  | .implKeyword => 98
  | .traitKeyword => 99
  | .forKeyword => 100
  | .inKeyword => 101
  | .externKeyword => 102
  | .typeKeyword => 103
  | .whereKeyword => 104
  | .selfKeyword => 105
  | .matchArrow => 113
  | .dotDot => 182
  | .dotDotEqual => 189

/-- Decode the stable token code used at the Rust/Lean extraction boundary.
    Contextual parser retags are deliberately absent: this decoder accepts
    only canonical lexer tokens. -/
def TokenKind.ofGpuCode : Nat → Option TokenKind
  | 1 => some .identifier
  | 2 => some .integer
  | 3 => some .whitespace
  | 4 => some .leftParen
  | 5 => some .rightParen
  | 6 => some .plus
  | 7 => some .star
  | 8 => some .assign
  | 9 => some .slash
  | 10 => some .lineComment
  | 11 => some .blockComment
  | 12 => some .less
  | 13 => some .greater
  | 14 => some .lessEqual
  | 15 => some .greaterEqual
  | 16 => some .equal
  | 17 => some .logicalAnd
  | 18 => some .logicalOr
  | 19 => some .not
  | 20 => some .leftBracket
  | 21 => some .rightBracket
  | 22 => some .leftBrace
  | 23 => some .rightBrace
  | 24 => some .angleGeneric
  | 25 => some .ampersand
  | 26 => some .pipe
  | 27 => some .minus
  | 32 => some .string
  | 33 => some .float
  | 34 => some .character
  | 35 => some .dot
  | 36 => some .comma
  | 37 => some .semicolon
  | 38 => some .colon
  | 39 => some .question
  | 40 => some .notEqual
  | 41 => some .percent
  | 42 => some .caret
  | 43 => some .shiftLeft
  | 44 => some .shiftRight
  | 45 => some .tilde
  | 46 => some .plusAssign
  | 47 => some .minusAssign
  | 48 => some .starAssign
  | 49 => some .slashAssign
  | 50 => some .percentAssign
  | 51 => some .caretAssign
  | 52 => some .shiftLeftAssign
  | 53 => some .shiftRightAssign
  | 54 => some .ampersandAssign
  | 55 => some .pipeAssign
  | 56 => some .increment
  | 57 => some .decrement
  | 66 => some .pubKeyword
  | 67 => some .fnKeyword
  | 68 => some .letKeyword
  | 69 => some .returnKeyword
  | 70 => some .ifKeyword
  | 71 => some .elseKeyword
  | 72 => some .whileKeyword
  | 73 => some .breakKeyword
  | 74 => some .continueKeyword
  | 75 => some .arrow
  | 90 => some .trueKeyword
  | 91 => some .falseKeyword
  | 92 => some .constKeyword
  | 93 => some .enumKeyword
  | 94 => some .structKeyword
  | 95 => some .matchKeyword
  | 96 => some .importKeyword
  | 97 => some .moduleKeyword
  | 98 => some .implKeyword
  | 99 => some .traitKeyword
  | 100 => some .forKeyword
  | 101 => some .inKeyword
  | 102 => some .externKeyword
  | 103 => some .typeKeyword
  | 104 => some .whereKeyword
  | 105 => some .selfKeyword
  | 113 => some .matchArrow
  | 182 => some .dotDot
  | 189 => some .dotDotEqual
  | _ => none

theorem TokenKind.ofGpuCode_gpuCode (kind : TokenKind) :
    TokenKind.ofGpuCode kind.gpuCode = some kind := by
  cases kind <;> rfl

theorem TokenKind.gpuCode_injective : Function.Injective TokenKind.gpuCode := by
  intro left right equalCodes
  cases left <;> cases right <;> simp [TokenKind.gpuCode] at equalCodes <;> rfl

end Lanius.Compiler
