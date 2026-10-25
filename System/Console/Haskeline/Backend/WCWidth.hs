{-# LANGUAGE BangPatterns #-}
module System.Console.Haskeline.Backend.WCWidth(
                            gsWidth,
                            splitAtWidth,
                            takeWidth,
                            ) where

-- Certain characters are "wide", i.e. take up two spaces in the terminal.
-- This module wraps the necessary foreign routines, and also provides some convenience
-- functions for width-breaking code.

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

-- | The width of a grapheme.  A grapheme may consist of several
-- codepoints (for example a base character plus combining marks, or an
-- emoji ZWJ sequence).  We compute its width by adding the width of each
-- codepoint, which matches how terminals such as VTE lay out these
-- sequences: the family emoji is eight columns wide, because its four
-- emoji components are each two columns wide while the joiners are
-- zero-width.  
-- ASCII is the common case.  Avoid the FFI call and the intermediate
-- list; control characters (including DEL) have width zero.
gWidth :: Grapheme -> Int
gWidth g = case combiningChars g of
                [] -> case baseChar g of
                        c | c >= ' ' && c < '\DEL' -> 1
                          | c < '\x80' -> 0
                          | otherwise -> wcwidth c
                _ -> foldl' (+) 0 . map wcwidth . graphemeChars $ g

gsWidth :: [Grapheme] -> Int
gsWidth = go 0
  where
    go !w [] = w
    go !w (g:gs) = go (w + gWidth g) gs

-- | Split off the maximal list which is no more than the given width.
-- returns the width of that list.
splitAtWidth :: Int -> [Grapheme] -> ([Grapheme],[Grapheme],Int)
splitAtWidth n xs = case splitAtWidth' n xs of
                        (this,rest,remaining) -> (this,rest,n-remaining)

-- Returns the amount of unused space in the line.
splitAtWidth' :: Int -> [Grapheme] -> ([Grapheme],[Grapheme],Int)
splitAtWidth' w [] = ([],[],w)
splitAtWidth' w (g:gs)
    | gw > w = ([],g:gs,w)
    | otherwise = (g:gs',gs'',r)
  where
    gw = gWidth g
    (gs',gs'',r) = splitAtWidth' (w-gw) gs

-- Returns the longest prefix less than or equal to the given width
-- plus the width of that list.
takeWidth :: Int -> [Grapheme] -> ([Grapheme],Int)
takeWidth n gs = case splitAtWidth n gs of
                    (gs',_,len) -> (gs',len)
