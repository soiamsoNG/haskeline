module System.Console.Haskeline.Term.Layout(
                            Layout(..)
                            ) where

import System.Console.Haskeline.Term.WidthPolicy

-- | The current terminal geometry and the width policy used to interpret
-- grapheme clusters.
data Layout = Layout {width, height :: Int, widthPolicy :: WidthPolicy}
                    deriving (Show,Eq)
