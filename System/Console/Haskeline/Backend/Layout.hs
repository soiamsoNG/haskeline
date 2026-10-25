module System.Console.Haskeline.Backend.Layout(
                            Layout(..)
                            ) where

import System.Console.Haskeline.Backend.WidthPolicy

-- | The current terminal geometry and the width policy used to interpret
-- grapheme clusters.
data Layout = Layout {width, height :: Int, widthPolicy :: WidthPolicy}
                    deriving (Show,Eq)
