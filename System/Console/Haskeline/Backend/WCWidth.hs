{-# LANGUAGE BangPatterns #-}
module System.Console.Haskeline.Backend.WCWidth(
                            WidthPolicy(..),
                            defaultWidthPolicy,
                            gWidth,
                            gWidthWith,
                            gsWidth,
                            gsWidthWith,
                            gsWidthM,
                            gsWidthFor,
                            splitAtWidth,
                            splitAtWidthWith,
                            splitAtWidthM,
                            takeWidth,
                            takeWidthWith,
                            takeWidthM,
                            ) where

-- Certain characters are "wide", i.e. take up two spaces in the terminal.
-- This module wraps the necessary foreign routines, and also provides some convenience
-- functions for width-breaking code.

import System.Console.Haskeline.Backend.Layout
import System.Console.Haskeline.Backend.WidthPolicy
import System.Console.Haskeline.LineState
import System.Console.Haskeline.Monads (MonadReader, asks)

import Foreign.C.Types

-- | Read the width policy from the current terminal's 'Layout'.
widthPolicyM :: MonadReader Layout m => m WidthPolicy
widthPolicyM = asks widthPolicy
{-# INLINE widthPolicyM #-}

foreign import ccall unsafe haskeline_mk_wcwidth :: CInt -> CInt

{-# INLINE wcwidth #-}
wcwidth :: Char -> Int
wcwidth c = case haskeline_mk_wcwidth $ toEnum $ fromEnum c of
                -1 -> 0 -- Control characters have zero width.  (Used by the
                        -- "\SOH...\STX" hack in LineState.stringToGraphemes.)
                w -> fromIntegral w

-- | Width of a single codepoint, with an ASCII fast path.  Control
-- characters (including DEL) have width zero.
codepointWidth :: Char -> Int
codepointWidth c
    | c >= ' ' && c < '\DEL' = 1
    | c < '\x80' = 0
    | otherwise = wcwidth c
{-# INLINE codepointWidth #-}

-- | The width of a grapheme under the codepoint-sum policy.  A grapheme may
-- consist of several codepoints (for example a base character plus combining
-- marks, or an emoji ZWJ sequence).  We add the width of each codepoint,
-- which matches how terminals such as VTE lay out these sequences: the
-- family emoji is eight columns wide, because its four emoji components are
-- each two columns wide while the joiners are zero-width.
--
-- ASCII is the common case.  Avoid the FFI call and the intermediate list.
gWidth :: Grapheme -> Int
gWidth g = case combiningChars g of
                [] -> case baseChar g of
                        c | c >= ' ' && c < '\DEL' -> 1
                          | c < '\x80' -> 0
                          | otherwise -> wcwidth c
                _ -> foldl' (+) 0 . map wcwidth . graphemeChars $ g

-- | The width of a grapheme under the grapheme-cluster policy.  Terminals
-- with grapheme-cluster support draw the cluster as one glyph.  An emoji
-- presentation selector, keycap mark or regional-indicator pair makes the
-- whole cluster two columns; otherwise the widest codepoint in the cluster
-- determines its width (so a base character plus combining marks keeps the
-- base width, and Hangul jamo stay two columns).
clusterWidth :: Grapheme -> Int
clusterWidth g = case combiningChars g of
                    [] -> codepointWidth (baseChar g)
                    cs -> let chars = baseChar g : cs
                          in if isRegionalIndicatorPair chars
                                then 2
                                else widest 0 chars
  where
    widest !w [] = w
    widest !w (c:cs)
        | isEmojiSelector c = 2
        | otherwise = widest (max w (wcwidth c)) cs

isEmojiSelector :: Char -> Bool
isEmojiSelector c = c == '\xFE0F' || c == '\x20E3'

isRegionalIndicatorPair :: String -> Bool
isRegionalIndicatorPair [a,b] = isRegionalIndicator a && isRegionalIndicator b
isRegionalIndicatorPair _ = False

isRegionalIndicator :: Char -> Bool
isRegionalIndicator c = c >= '\x1F1E6' && c <= '\x1F1FF'

gWidthWith :: WidthPolicy -> Grapheme -> Int
gWidthWith CodepointSum = gWidth
gWidthWith GraphemeCluster = clusterWidth
{-# INLINE gWidthWith #-}

gsWidth :: [Grapheme] -> Int
gsWidth = go 0
  where
    go !w [] = w
    go !w (g:gs) = go (w + gWidth g) gs

gsWidthWith :: WidthPolicy -> [Grapheme] -> Int
gsWidthWith policy = go 0
  where
    width = gWidthWith policy
    go !w [] = w
    go !w (g:gs) = go (w + width g) gs

-- | Width of a grapheme list, using the policy supplied by the current
-- terminal monad.
gsWidthM :: MonadReader Layout m => [Grapheme] -> m Int
gsWidthM gs = do
    policy <- widthPolicyM
    return $! gsWidthWith policy gs
{-# INLINE gsWidthM #-}

-- | Pure variant for code which already has a 'Layout'.
gsWidthFor :: Layout -> [Grapheme] -> Int
gsWidthFor lay = gsWidthWith (widthPolicy lay)
{-# INLINE gsWidthFor #-}

-- | Split off the maximal list which is no more than the given width.
-- returns the width of that list.
splitAtWidth :: Int -> [Grapheme] -> ([Grapheme],[Grapheme],Int)
splitAtWidth n xs = case splitAtWidth' gWidth n xs of
                        (this,rest,remaining) -> (this,rest,n-remaining)

splitAtWidthWith :: WidthPolicy -> Int -> [Grapheme]
                 -> ([Grapheme],[Grapheme],Int)
splitAtWidthWith policy n xs = case splitAtWidth' (gWidthWith policy) n xs of
                        (this,rest,remaining) -> (this,rest,n-remaining)

splitAtWidthM :: MonadReader Layout m => Int -> [Grapheme]
              -> m ([Grapheme],[Grapheme],Int)
splitAtWidthM n gs = do
    policy <- widthPolicyM
    return $! splitAtWidthWith policy n gs

-- Returns the amount of unused space in the line.
splitAtWidth' :: (Grapheme -> Int) -> Int -> [Grapheme]
              -> ([Grapheme],[Grapheme],Int)
splitAtWidth' _ w [] = ([],[],w)
splitAtWidth' width w (g:gs)
    | gw > w = ([],g:gs,w)
    | otherwise = (g:gs',gs'',r)
  where
    gw = width g
    (gs',gs'',r) = splitAtWidth' width (w-gw) gs

-- Returns the longest prefix less than or equal to the given width
-- plus the width of that list.
takeWidth :: Int -> [Grapheme] -> ([Grapheme],Int)
takeWidth = takeWidthWith CodepointSum

takeWidthWith :: WidthPolicy -> Int -> [Grapheme] -> ([Grapheme],Int)
takeWidthWith policy n gs = case splitAtWidthWith policy n gs of
                    (gs',_,len) -> (gs',len)

takeWidthM :: MonadReader Layout m => Int -> [Grapheme] -> m ([Grapheme],Int)
takeWidthM n gs = do
    policy <- widthPolicyM
    return $! takeWidthWith policy n gs
