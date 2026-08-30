import Lanius.Extraction.VerifiedLexerProgram
import Lanius.FunctionalViewCoreStatefulReification

namespace Lanius.Extraction.Lexer.Scanners

open Lanius.Core
open Lanius.Typing
open Lanius.Extraction
open Lanius.Extraction.CoreTyping
open Lanius.Compiler.Lexer.Program
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Stateful.Reification

def scanIdentifierEndFunction : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", "scan_identifier_end")

def scanWhitespaceEndFunction : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", "scan_whitespace_end")

def scanQuotedEndFunction : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", "scan_quoted_end")

def scanStringEndFunction : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", "scan_string_end")

def scanCharacterEndFunction : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", "scan_character_end")

def scanLineCommentEndFunction : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", "scan_line_comment_end")

def scanBlockCommentEndFunction : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", "scan_block_comment_end")

private def functionBody (function : Function) : Stmt :=
  function.body.getD .skip

def scanIdentifierEndBody : Stmt := functionBody scanIdentifierEndFunction
def scanWhitespaceEndBody : Stmt := functionBody scanWhitespaceEndFunction
def scanQuotedEndBody : Stmt := functionBody scanQuotedEndFunction
def scanStringEndBody : Stmt := functionBody scanStringEndFunction
def scanCharacterEndBody : Stmt := functionBody scanCharacterEndFunction
def scanLineCommentEndBody : Stmt := functionBody scanLineCommentEndFunction
def scanBlockCommentEndBody : Stmt := functionBody scanBlockCommentEndFunction

theorem verifiedFrontendLexerCore_finds_scanIdentifierEnd :
    verifiedFrontendLexerCore.function? scanIdentifierEndFunction.id =
      some scanIdentifierEndFunction := by
  rfl

theorem verifiedFrontendLexerCore_finds_scanWhitespaceEnd :
    verifiedFrontendLexerCore.function? scanWhitespaceEndFunction.id =
      some scanWhitespaceEndFunction := by
  rfl

theorem verifiedFrontendLexerCore_finds_scanQuotedEnd :
    verifiedFrontendLexerCore.function? scanQuotedEndFunction.id =
      some scanQuotedEndFunction := by
  rfl

theorem verifiedFrontendLexerCore_finds_scanStringEnd :
    verifiedFrontendLexerCore.function? scanStringEndFunction.id =
      some scanStringEndFunction := by
  rfl

theorem verifiedFrontendLexerCore_finds_scanCharacterEnd :
    verifiedFrontendLexerCore.function? scanCharacterEndFunction.id =
      some scanCharacterEndFunction := by
  rfl

theorem verifiedFrontendLexerCore_finds_scanLineCommentEnd :
    verifiedFrontendLexerCore.function? scanLineCommentEndFunction.id =
      some scanLineCommentEndFunction := by
  rfl

theorem verifiedFrontendLexerCore_finds_scanBlockCommentEnd :
    verifiedFrontendLexerCore.function? scanBlockCommentEndFunction.id =
      some scanBlockCommentEndFunction := by
  rfl

theorem scanIdentifierEndFunction_has_body :
    scanIdentifierEndFunction.body = some scanIdentifierEndBody := by
  rfl

theorem scanWhitespaceEndFunction_has_body :
    scanWhitespaceEndFunction.body = some scanWhitespaceEndBody := by
  rfl

theorem scanQuotedEndFunction_has_body :
    scanQuotedEndFunction.body = some scanQuotedEndBody := by
  rfl

theorem scanStringEndFunction_has_body :
    scanStringEndFunction.body = some scanStringEndBody := by
  rfl

theorem scanCharacterEndFunction_has_body :
    scanCharacterEndFunction.body = some scanCharacterEndBody := by
  rfl

theorem scanLineCommentEndFunction_has_body :
    scanLineCommentEndFunction.body = some scanLineCommentEndBody := by
  rfl

theorem scanBlockCommentEndFunction_has_body :
    scanBlockCommentEndFunction.body = some scanBlockCommentEndBody := by
  rfl

theorem scanIdentifierEndFunction_eq_extracted :
    scanIdentifierEndFunction = extractedScanIdentifierEndFunction := by
  rfl

theorem scanWhitespaceEndFunction_eq_extracted :
    scanWhitespaceEndFunction = extractedScanWhitespaceEndFunction := by
  rfl

theorem scanIdentifierEndBody_eq_extracted :
    scanIdentifierEndBody = extractedScanIdentifierEndBody := by
  rfl

theorem scanWhitespaceEndBody_eq_extracted :
    scanWhitespaceEndBody = extractedScanWhitespaceEndBody := by
  rfl

private def scanner3Reification? (function : Function) (body : Stmt) :=
  reifyCommand? verifiedFrontendLexerCore function.returnType
    (parameterContext function.parameters) false
    (identityLayout (arity := 3)) 3 body

private def scanner4Reification? (function : Function) (body : Stmt) :=
  reifyCommand? verifiedFrontendLexerCore function.returnType
    (parameterContext function.parameters) false
    (identityLayout (arity := 4)) 4 body

theorem scanIdentifierEndReification_exists :
    (scanner3Reification? scanIdentifierEndFunction
      scanIdentifierEndBody).isSome := by
  native_decide

theorem scanWhitespaceEndReification_exists :
    (scanner3Reification? scanWhitespaceEndFunction
      scanWhitespaceEndBody).isSome := by
  native_decide

theorem scanQuotedEndReification_exists :
    (scanner4Reification? scanQuotedEndFunction scanQuotedEndBody).isSome := by
  native_decide

theorem scanStringEndReification_exists :
    (scanner3Reification? scanStringEndFunction scanStringEndBody).isSome := by
  native_decide

theorem scanCharacterEndReification_exists :
    (scanner3Reification? scanCharacterEndFunction
      scanCharacterEndBody).isSome := by
  native_decide

theorem scanLineCommentEndReification_exists :
    (scanner3Reification? scanLineCommentEndFunction
      scanLineCommentEndBody).isSome := by
  native_decide

theorem scanBlockCommentEndReification_exists :
    (scanner3Reification? scanBlockCommentEndFunction
      scanBlockCommentEndBody).isSome := by
  native_decide

def scanIdentifierEndView :=
  (scanner3Reification? scanIdentifierEndFunction scanIdentifierEndBody).get
    scanIdentifierEndReification_exists

def scanWhitespaceEndView :=
  (scanner3Reification? scanWhitespaceEndFunction scanWhitespaceEndBody).get
    scanWhitespaceEndReification_exists

def scanQuotedEndView :=
  (scanner4Reification? scanQuotedEndFunction scanQuotedEndBody).get
    scanQuotedEndReification_exists

def scanStringEndView :=
  (scanner3Reification? scanStringEndFunction scanStringEndBody).get
    scanStringEndReification_exists

def scanCharacterEndView :=
  (scanner3Reification? scanCharacterEndFunction scanCharacterEndBody).get
    scanCharacterEndReification_exists

def scanLineCommentEndView :=
  (scanner3Reification? scanLineCommentEndFunction scanLineCommentEndBody).get
    scanLineCommentEndReification_exists

def scanBlockCommentEndView :=
  (scanner3Reification? scanBlockCommentEndFunction
    scanBlockCommentEndBody).get scanBlockCommentEndReification_exists

theorem scanIdentifierEndView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      identityLayout 3 scanIdentifierEndView.command =
      scanIdentifierEndBody :=
  scanIdentifierEndView.toCoreExactly

theorem scanWhitespaceEndView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      identityLayout 3 scanWhitespaceEndView.command =
      scanWhitespaceEndBody :=
  scanWhitespaceEndView.toCoreExactly

theorem scanQuotedEndView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      identityLayout 4 scanQuotedEndView.command =
      scanQuotedEndBody :=
  scanQuotedEndView.toCoreExactly

theorem scanStringEndView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      identityLayout 3 scanStringEndView.command =
      scanStringEndBody :=
  scanStringEndView.toCoreExactly

theorem scanCharacterEndView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      identityLayout 3 scanCharacterEndView.command =
      scanCharacterEndBody :=
  scanCharacterEndView.toCoreExactly

theorem scanLineCommentEndView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      identityLayout 3 scanLineCommentEndView.command =
      scanLineCommentEndBody :=
  scanLineCommentEndView.toCoreExactly

theorem scanBlockCommentEndView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      identityLayout 3 scanBlockCommentEndView.command =
      scanBlockCommentEndBody :=
  scanBlockCommentEndView.toCoreExactly

end Lanius.Extraction.Lexer.Scanners
