import Lanius.Extraction.CanonicalTokens.KeywordExecution2
import Lanius.Extraction.CanonicalTokens.KeywordExecution3
import Lanius.Extraction.CanonicalTokens.KeywordExecution4
import Lanius.Extraction.CanonicalTokens.KeywordExecution5
import Lanius.Extraction.CanonicalTokens.KeywordExecution6
import Lanius.Extraction.CanonicalTokens.KeywordExecution8
import Lanius.Extraction.CanonicalTokens.KeywordExecutionUnsupported

namespace Lanius.Extraction.CanonicalTokens.KeywordExecution

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core.Stateful
open Lanius.Extraction.CanonicalTokens

abbrev TM := KeywordDispatchSemantics.TM
abbrev SM := KeywordDispatchSemantics.SM

/-- The mechanically recovered checked keyword command implements the logical
keyword lookup for an arbitrary embedded spelling. -/
theorem command_evaluates (leading spelling trailing : List Int)
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (Model.keywordEnvironment (leading ++ spelling ++ trailing)
        leading.length (leading.length + spelling.length)) KeywordCommand.command =
    some (.returned (some (.signed .i32
        (Model.keywordKind spelling 0 spelling.length))),
      Model.keywordWorld (leading ++ spelling ++ trailing),
      Model.keywordEnvironment (leading ++ spelling ++ trailing)
        leading.length (leading.length + spelling.length)) := by
  have spellingBound : spelling.length ≤ 2147483647 := by
    have boundedLengths :
        leading.length + spelling.length + trailing.length ≤ 2147483647 := by
      simpa only [List.length_append, Nat.add_assoc] using bounded
    omega
  cases spelling with
  | nil =>
      exact KeywordExecutionUnsupported.command_evaluates leading [] trailing
        spellingBound (by simp) (by simp) (by simp) (by simp)
        (by simp) (by simp)
  | cons first rest1 =>
      cases rest1 with
      | nil =>
          exact KeywordExecutionUnsupported.command_evaluates leading [first] trailing
            spellingBound (by simp) (by simp) (by simp) (by simp)
            (by simp) (by simp)
      | cons second rest2 =>
          cases rest2 with
          | nil => simpa using (KeywordExecution2.command_evaluates
              leading trailing first second bounded)
          | cons third rest3 =>
              cases rest3 with
              | nil => simpa using (KeywordExecution3.command_evaluates
                  leading trailing first second third bounded)
              | cons fourth rest4 =>
                  cases rest4 with
                  | nil => simpa using (KeywordExecution4.command_evaluates
                      leading trailing first second third fourth bounded)
                  | cons fifth rest5 =>
                      cases rest5 with
                      | nil => simpa using (KeywordExecution5.command_evaluates
                          leading trailing first second third fourth fifth bounded)
                      | cons sixth rest6 =>
                          cases rest6 with
                          | nil => simpa using (KeywordExecution6.command_evaluates
                              leading trailing first second third fourth fifth sixth bounded)
                          | cons seventh rest7 =>
                              cases rest7 with
                              | nil =>
                                  exact KeywordExecutionUnsupported.command_evaluates
                                    leading
                                    [first, second, third, fourth, fifth, sixth, seventh]
                                    trailing spellingBound (by simp) (by simp)
                                    (by simp) (by simp) (by simp) (by simp)
                              | cons eighth rest8 =>
                                  cases rest8 with
                                  | nil => simpa using (KeywordExecution8.command_evaluates
                                      leading trailing first second third fourth fifth
                                      sixth seventh eighth bounded)
                                  | cons ninth rest9 =>
                                      exact KeywordExecutionUnsupported.command_evaluates
                                        leading
                                        (first :: second :: third :: fourth :: fifth ::
                                          sixth :: seventh :: eighth :: ninth :: rest9)
                                        trailing spellingBound (by simp) (by simp) (by simp)
                                        (by simp) (by simp) (by simp)

end Lanius.Extraction.CanonicalTokens.KeywordExecution
