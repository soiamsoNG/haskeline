-- | How a terminal advances the cursor across a grapheme cluster.
--
-- Terminals do not agree on the width of a single grapheme cluster.  VTE
-- lays out the codepoints separately, so a family emoji is four two-column
-- glyphs and advances eight columns.  kitty, WezTerm and some newer
-- terminals draw the whole cluster as one glyph and advance two columns.
-- There is no portable query for this policy, so we keep it as an explicit
-- value instead of baking one terminal's behaviour into the width tables.
module System.Console.Haskeline.Term.WidthPolicy
    ( WidthPolicy(..)
    , defaultWidthPolicy
    , detectWidthPolicy
    ) where

import Data.Char (toLower)
import Data.Maybe (isJust)
import System.Environment (lookupEnv)

data WidthPolicy
    = CodepointSum
      -- ^ Sum the widths of the codepoints in the cluster (VTE).
    | GraphemeCluster
      -- ^ Use the width of the rendered cluster (kitty, WezTerm, ...).
    deriving (Eq, Show)

defaultWidthPolicy :: WidthPolicy
defaultWidthPolicy = CodepointSum

-- | Choose a policy from the environment.  An explicit
-- @HASKELINE_WIDTH_POLICY=codepoint@ or @...=grapheme@ always wins; this is
-- also useful for tests.  Otherwise known terminal markers select a policy,
-- and unknown terminals keep the historical codepoint-sum behaviour.
detectWidthPolicy :: IO WidthPolicy
detectWidthPolicy = do
    override <- fmap (fmap normalize) (lookupEnv "HASKELINE_WIDTH_POLICY")
    case override of
        Just "codepoint" -> return CodepointSum
        Just "codepointsum" -> return CodepointSum
        Just "grapheme" -> return GraphemeCluster
        Just "graphemecluster" -> return GraphemeCluster
        _ -> detectFromEnvironment

detectFromEnvironment :: IO WidthPolicy
detectFromEnvironment = do
    vte <- lookupEnv "VTE_VERSION"
    kittyWindow <- lookupEnv "KITTY_WINDOW_ID"
    term <- fmap (fmap normalize) (lookupEnv "TERM")
    termProgram <- fmap (fmap normalize) (lookupEnv "TERM_PROGRAM")
    weztermPane <- lookupEnv "WEZTERM_PANE"
    let modern = isJust kittyWindow
              || isJust weztermPane
              || term `elem` [Just "xterm-kitty", Just "xterm-ghostty"]
              || termProgram `elem` [Just "wezterm", Just "ghostty"]
    return $ if isJust vte
                then CodepointSum
                else if modern then GraphemeCluster else CodepointSum

normalize :: String -> String
normalize = map toLower
