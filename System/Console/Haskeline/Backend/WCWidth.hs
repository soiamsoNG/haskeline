{-# LANGUAGE BangPatterns #-}
module System.Console.Haskeline.Backend.WCWidth(
                            WidthPolicy(..),
                            defaultWidthPolicy,
                            gWidth,
                            gWidthWith,
                            gsWidth,
                            gsWidthWith,
                            splitAtWidth,
                            splitAtWidthWith,
                            takeWidth,
                            takeWidthWith,
                            ) where

-- Certain characters are "wide", i.e. take up two spaces in the terminal.
-- This module wraps the necessary foreign routines, and also provides some convenience
-- functions for width-breaking code.

import System.Console.Haskeline.Backend.WidthPolicy
import System.Console.Haskeline.LineState

import Data.List (foldl')
import Foreign.C.Types

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
                [] -> codepointWidth (baseChar g)
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
gsWidth = gsWidthWith CodepointSum

gsWidthWith :: WidthPolicy -> [Grapheme] -> Int
gsWidthWith policy = go 0
  where
    width = gWidthWith policy
    go !w [] = w
    go !w (g:gs) = go (w + width g) gs

-- | Split off the maximal list which is no more than the given width.
-- returns the width of that list.
splitAtWidth :: Int -> [Grapheme] -> ([Grapheme],[Grapheme],Int)
splitAtWidth = splitAtWidthWith CodepointSum

splitAtWidthWith :: WidthPolicy -> Int -> [Grapheme]
                 -> ([Grapheme],[Grapheme],Int)
splitAtWidthWith policy n xs = case splitAtWidth' (gWidthWith policy) n xs of
                        (this,rest,remaining) -> (this,rest,n-remaining)

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
