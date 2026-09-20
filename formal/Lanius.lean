import Lanius.Declarations
import Lanius.Declarations.SourceCheck
import Lanius.Declarations.CatalogCheck
import Lanius.Execution
import Lanius.Layout
import Lanius.ScopeGraph
import Lanius.SurfaceElaboration
import Lanius.Core.Equality
import Lanius.Semantics
import Lanius.Semantics.WellFormed
import Lanius.Semantics.Pure
import Lanius.Semantics.Rules
import Lanius.Semantics.Assignment
import Lanius.Semantics.CallerFrame
import Lanius.Semantics.Loop
import Lanius.Semantics.MutableLocal
import Lanius.Semantics.ReadOnlySlice
import Lanius.Compiler.Lexer.UnaryI32Predicate
import Lanius.Compiler.FrontendArtifact
import Lanius.Compiler.Phase
import Lanius.Compiler.DeclarationCheck
import Lanius.Compiler.EligibilityCheck
import Lanius.Compiler.ImportSynthesis
import Lanius.Compiler.SourcePackCheck
import Lanius.Compiler.FrontendCheck
import Lanius.Compiler.CatalogSynthesis
import Lanius.Compiler.FrontendBoundary
import Lanius.Compiler.ProgramLowering
import Lanius.Compiler.BodyCheck
import Lanius.Compiler.SourceCoreBoundary
import Lanius.Compiler.CoreBoundary
import Lanius.Compiler.ExecutableBoundary
import Lanius.Compiler.EntrypointCheck
import Lanius.Compiler.BackendInputCheck
import Lanius.Compiler.ImportCheck

import Lanius.Compiler.LexerCanonical
import Lanius.Compiler.Lexer.Artifact
import Lanius.Compiler.Lexer.ArtifactClassifier
import Lanius.Compiler.Lexer.Classifier
import Lanius.Compiler.Lexer.ClassifierCorrect
import Lanius.Compiler.Lexer.Predicate
import Lanius.Compiler.Lexer.PredicateStable
import Lanius.Compiler.Lexer.Correct
import Lanius.Compiler.Lexer.ScannerFunction
import Lanius.Compiler.Lexer.ScanEndFunctions
import Lanius.Compiler.Lexer.CommentScannerFunction
import Lanius.Compiler.Lexer.BlockCommentFunction
import Lanius.Compiler.Lexer.QuotedWrappers

import Lanius.Extraction.ArtifactQuote
import Lanius.Extraction.ArtifactView
import Lanius.Extraction.CompactDecode.Reader
import Lanius.Extraction.CompactGrammarAuth
import Lanius.Extraction.OutputPacking.Prefix
import Lanius.Extraction.SurfaceReconstruct
import Lanius.Extraction.SurfaceCheck
import Lanius.Extraction.SyntaxCheck.Pack
import Lanius.Extraction.SyntaxCheck.Soundness
import Lanius.Extraction.CompactBoundary

import Lanius.Typing.Check

import Lanius.X86.Encoding
import Lanius.X86.Machine.Encoding
import Lanius.X86.Machine.Block
import Lanius.X86.Machine.DecodeBlock
import Lanius.X86.Machine.AluEncoding
import Lanius.X86.Transport
import Lanius.X86.ParameterReturn

/-!
# Lanius formal foundation

This library intentionally contains only the definitions that survive the
proof reset: language syntax and semantics, the mathematical lexer model, the
artifact/deep-embedding boundary, and the x86 machine model.

The facade exposes completed classifier, scanner, scan-end, and comment
contracts; quoted-function proofs remain outside until their contract chain is
complete.
-/
