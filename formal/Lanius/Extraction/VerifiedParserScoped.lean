import Lanius.Extraction.VerifiedParserProgram

namespace Lanius.Extraction

open Lanius.Extraction.ScopedSurface

def verifiedParserScopedFunctions : List CheckedFunction :=
  verifiedParserScopedArtifact.functions

def verifiedParserScopedFunctionNames : List String :=
  verifiedParserScopedFunctions.map (·.source.name.text)

theorem verifiedParser_scoped_function_names :
    verifiedParserScopedFunctionNames = [
      "parse_status", "parse_state_count", "parse_root_state",
      "parse_error_position", "parse_result", "state_seed",
      "append_result", "range_valid", "grammar_is_valid", "chart_word",
      "state_word", "state_value", "find_state", "append_state",
      "production_rhs_length", "production_rhs_symbol", "production_lhs",
      "scan_terminal", "append_or_full", "recognize"] := by
  native_decide

end Lanius.Extraction
