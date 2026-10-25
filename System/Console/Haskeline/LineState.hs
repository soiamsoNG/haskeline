{- |
This module contains the various datatypes which model the state of the line; that is, the characters displayed and the position of the cursor.
-}
module System.Console.Haskeline.LineState(
                    -- * Graphemes
                    Grapheme(),
                    baseChar,
                    graphemeChars,
                    combiningChars,
                    isCombiningChar,
                    stringToGraphemes,
                    graphemesToString,
                    modifyBaseChar,
                    mapBaseChars,
                    -- * Line State class
                    LineState(..),
                    Prefix,
                    -- ** Convenience functions for the drawing backends
                    LineChars,
                    lineChars,
                    lengthToEnd,
                    -- ** Supplementary classes
                    Result(..),
                    Save(..),
                    listSave,
                    listRestore,
                    Move(..),
                    -- * Instances
                    -- ** InsertMode
                    InsertMode(..),
                    emptyIM,
                    insertChar,
                    insertString,
                    replaceCharIM,
                    insertGraphemes,
                    deleteNext,
                    deletePrev,
                    skipLeft,
                    skipRight,
                    transposeChars,
                    -- *** Moving to word boundaries
                    goRightUntil,
                    goLeftUntil,
                    atStart,
                    atEnd,
                    beforeChar,
                    afterChar,
                    overChar,
                    -- ** CommandMode
                    CommandMode(..),
                    deleteChar,
                    replaceChar,
                    pasteGraphemesBefore,
                    pasteGraphemesAfter,
                    -- *** Transitioning between modes
                    enterCommandMode,
                    enterCommandModeRight,
                    insertFromCommandMode,
                    appendFromCommandMode,
                    withCommandMode,
                    -- ** ArgMode
                    ArgMode(..),
                    startArg,
                    addNum,
                    applyArg,
                    applyCmdArg,
                    -- ** Other line state types
                    Message(..),
                    Password(..),
                    addPasswordChar,
                    deletePasswordChar,
                    ) where

import Data.Char

-- | A 'Grapheme' is a fundamental unit of display for the UI.  Several characters in sequence
-- can represent one grapheme; for example, an @a@ followed by the diacritic @\'\\768\'@ should
-- be treated as one unit.
data Grapheme = Grapheme {gBaseChar :: Char,
                          combiningChars :: [Char]}
                    deriving Eq

instance Show Grapheme where
    show g = show (gBaseChar g : combiningChars g)

baseChar :: Grapheme -> Char
baseChar = gBaseChar

modifyBaseChar :: (Char -> Char) -> Grapheme -> Grapheme
modifyBaseChar f g = g {gBaseChar = f (gBaseChar g)}

mapBaseChars :: (Char -> Char) -> [Grapheme] -> [Grapheme]
mapBaseChars f = map (modifyBaseChar f)

-- | Create a 'Grapheme' from a single base character.
--
-- NOTE: Careful, don't use outside this module; and inside, make sure this is only
-- ever called on non-combining characters.
baseGrapheme :: Char -> Grapheme
baseGrapheme c = Grapheme {gBaseChar = c, combiningChars = []}

-- | Add a character to the given 'Grapheme'.
addCombiner :: Grapheme -> Char -> Grapheme
addCombiner g c = g {combiningChars = combiningChars g ++ [c]}

-- | All characters making up a grapheme, starting with its base character.
graphemeChars :: Grapheme -> String
graphemeChars g = gBaseChar g : combiningChars g

-- | Characters which attach to the preceding grapheme.  Besides combining
-- marks, this includes the joiners and modifiers used by emoji sequences,
-- such as ZWJ, variation selectors, skin-tone modifiers and tag characters.
isCombiningChar :: Char -> Bool
isCombiningChar c =
    generalCategory c `elem` [NonSpacingMark, EnclosingMark]
    || c == '\x200C' || c == '\x200D'
    || isVariationSelector c
    || isEmojiModifier c
    || isEmojiTag c

isVariationSelector :: Char -> Bool
isVariationSelector c =
    (c >= '\xFE00' && c <= '\xFE0F')
    || (c >= '\xE0100' && c <= '\xE01EF')

isEmojiModifier :: Char -> Bool
isEmojiModifier c = c >= '\x1F3FB' && c <= '\x1F3FF'

isEmojiTag :: Char -> Bool
isEmojiTag c = c >= '\xE0020' && c <= '\xE007F'

isRegionalIndicator :: Char -> Bool
isRegionalIndicator c = c >= '\x1F1E6' && c <= '\x1F1FF'

-- | A deliberately broad approximation of Unicode's Extended_Pictographic
-- property.  It only controls whether a character following ZWJ is joined
-- into the same grapheme, so over-approximating is harmless.
isExtendedPictographic :: Char -> Bool
isExtendedPictographic c =
    generalCategory c == OtherSymbol
    || (c >= '\x1F000' && c <= '\x1FAFF')
    || (c >= '\x1FC00' && c <= '\x1FFFD')

isHangulL, isHangulV, isHangulT, isHangulLV, isHangulLVT :: Char -> Bool
isHangulL c = (c >= '\x1100' && c <= '\x115F')
           || (c >= '\xA960' && c <= '\xA97C')
isHangulV c = (c >= '\x1160' && c <= '\x11A7')
           || (c >= '\xD7B0' && c <= '\xD7C6')
isHangulT c = (c >= '\x11A8' && c <= '\x11FF')
           || (c >= '\xD7CB' && c <= '\xD7FB')
isHangulLV c = c >= '\xAC00' && c <= '\xD7A3'
               && (fromEnum c - 0xAC00) `mod` 28 == 0
isHangulLVT c = c >= '\xAC00' && c <= '\xD7A3'
                 && (fromEnum c - 0xAC00) `mod` 28 /= 0

-- | Should the character be part of the same grapheme as the given one?
joinsGrapheme :: Grapheme -> Char -> Bool
joinsGrapheme g c
    | isCombiningChar c = True
    | isRegionalIndicator c = all isRegionalIndicator cs
                              && odd (length cs)
    | isExtendedPictographic c = endsWithZWJ
    | isHangulL c = isHangulL lastChar
    | isHangulV c = isHangulL lastChar
                    || isHangulV lastChar
                    || isHangulLV lastChar
    | isHangulT c = isHangulV lastChar
                    || isHangulT lastChar
                    || isHangulLV lastChar
                    || isHangulLVT lastChar
    | otherwise = False
  where
    cs = graphemeChars g
    lastChar = last cs
    endsWithZWJ = lastChar == '\x200D'

-- | Converts a string into a sequence of graphemes.
--
-- NOTE: Drops any initial, unattached combining characters.
stringToGraphemes :: String -> [Grapheme]
stringToGraphemes = mkString . dropWhile isCombiningChar
    where
        mkString [] = []
        -- Minor hack: "\ESC...\STX" or "\SOH\ESC...\STX", where "\ESC..." is some
        -- control sequence (e.g., ANSI colors), is represented as a grapheme
        -- of zero length with '\ESC' as the base character.
        -- Note that this won't round-trip correctly with graphemesToString.
        -- In practice, however, that's fine since control characters can only occur
        -- in the prompt.
        mkString ('\SOH':cs) = stringToGraphemes cs
        mkString ('\ESC':cs) | (ctrl,'\STX':rest) <- break (=='\STX') cs
                    = Grapheme '\ESC' ctrl : stringToGraphemes rest
        mkString (c:cs) = let (g,rest) = spanGrapheme (baseGrapheme c) cs
                          in g : mkString rest

        spanGrapheme g (c:cs)
            | joinsGrapheme g c = spanGrapheme (addCombiner g c) cs
        spanGrapheme g rest = (g,rest)

graphemesToString :: [Grapheme] -> String
graphemesToString = concatMap (\g -> (baseChar g : combiningChars g))

-- | This class abstracts away the internal representations of the line state,
-- for use by the drawing actions.  Line state is generally stored in a zipper format.
class LineState s where
    beforeCursor :: Prefix -- ^ The input prefix.
                    -> s -- ^ The current line state.
                    -> [Grapheme] -- ^ The text to the left of the cursor
                                  -- (including the prefix).
    afterCursor :: s -> [Grapheme] -- ^ The text under and to the right of the cursor.

type Prefix = [Grapheme]

-- | The characters in the line (with the cursor in the middle).  NOT in a zippered format;
-- both lists are in the order left->right that appears on the screen.
type LineChars = ([Grapheme],[Grapheme])

-- | Accessor function for the various backends.
lineChars :: LineState s => Prefix -> s -> LineChars
lineChars prefix s = (beforeCursor prefix s, afterCursor s)

-- | Compute the number of characters under and to the right of the cursor.
lengthToEnd :: LineChars -> Int
lengthToEnd = length . snd

class LineState s => Result s where
    toResult :: s -> String

class LineState s => Save s where
    save :: s -> InsertMode
    restore :: InsertMode -> s

listSave :: Save s => s -> [Grapheme]
listSave s = case save s of IMode xs ys -> reverse xs ++ ys

listRestore :: Save s => [Grapheme] -> s
listRestore xs = restore $ IMode (reverse xs) []

class Move s where
    goLeft, goRight, moveToStart, moveToEnd :: s -> s

-- | The standard line state representation; considers the cursor to be located
-- between two characters.  The first list is reversed.
data InsertMode = IMode [Grapheme] [Grapheme]
                    deriving (Show, Eq)

instance LineState InsertMode where
    beforeCursor prefix (IMode xs _) = prefix ++ reverse xs
    afterCursor (IMode _ ys) = ys

instance Result InsertMode where
    toResult (IMode xs ys) = graphemesToString $ reverse xs ++ ys

instance Save InsertMode where
    save = id
    restore = id

instance Move InsertMode where
    goLeft im@(IMode [] _) = im
    goLeft (IMode (x:xs) ys) = IMode xs (x:ys)

    goRight im@(IMode _ []) = im
    goRight (IMode ys (x:xs)) = IMode (x:ys) xs

    moveToStart (IMode xs ys) = IMode [] (reverse xs ++ ys)
    moveToEnd (IMode xs ys) = IMode (reverse ys ++ xs) []

emptyIM :: InsertMode
emptyIM = IMode [] []

-- | Insert one character, which may be combining, to the left of the cursor.
--
insertChar :: Char -> InsertMode -> InsertMode
insertChar c im@(IMode xs ys)
    | isCombiningChar c = case xs of
                            []   -> im -- drop a combining character if it
                                       -- appears at the start of the line.
                            z:zs -> IMode (addCombiner z c : zs) ys
    | (z:zs) <- xs, joinsGrapheme z c
                        = IMode (addCombiner z c : zs) ys
    | otherwise         = IMode (baseGrapheme c : xs) ys

-- | Insert a sequence of characters to the left of the cursor.
insertString :: String -> InsertMode -> InsertMode
insertString s (IMode xs ys) = IMode (reverse (stringToGraphemes s) ++ xs) ys

deleteNext, deletePrev :: InsertMode -> InsertMode
deleteNext im@(IMode _ []) = im
deleteNext (IMode xs (_:ys)) = IMode xs ys

deletePrev im@(IMode [] _) = im
deletePrev (IMode (_:xs) ys) = IMode xs ys

skipLeft, skipRight :: (Char -> Bool) -> InsertMode -> InsertMode
skipLeft f (IMode xs ys) = let (ws,zs) = span (f . baseChar) xs
                           in IMode zs (reverse ws ++ ys)
skipRight f (IMode xs ys) = let (ws,zs) = span (f . baseChar) ys
                            in IMode (reverse ws ++ xs) zs

transposeChars :: InsertMode -> InsertMode
transposeChars (IMode (x:xs) (y:ys)) = IMode (x:y:xs) ys
transposeChars (IMode (y:x:xs) []) = IMode (x:y:xs) []
transposeChars im = im

insertGraphemes :: [Grapheme] -> InsertMode -> InsertMode
insertGraphemes s (IMode xs ys) = IMode (reverse s ++ xs) ys

-- For the 'R' command.
replaceCharIM :: Char -> InsertMode -> InsertMode
replaceCharIM c im
    | isCombiningChar c = case im of
                    IMode [] [] -> im
                    IMode [] (y:ys) -> IMode [] (addCombiner y c:ys)
                    IMode (x:xs) ys -> IMode (addCombiner x c:xs) ys
    | otherwise = let g = baseGrapheme c
                  in case im of
                    IMode xs [] -> IMode (g:xs) []
                    IMode xs (_:ys) -> IMode (g:xs) ys


-- | Used by vi mode.  Considers the cursor to be located over some specific character.
-- The first list is reversed.
data CommandMode = CMode [Grapheme] Grapheme [Grapheme] | CEmpty
                    deriving Show

instance LineState CommandMode where
    beforeCursor prefix CEmpty = prefix
    beforeCursor prefix (CMode xs _ _) = prefix ++ reverse xs
    afterCursor CEmpty = []
    afterCursor (CMode _ c ys) = c:ys

instance Result CommandMode where
    toResult CEmpty = ""
    toResult (CMode xs c ys) = graphemesToString $ reverse xs ++ (c:ys)

instance Save CommandMode where
    save = insertFromCommandMode
    restore = enterCommandModeRight

instance Move CommandMode where
    goLeft (CMode (x:xs) c ys) = CMode xs x (c:ys)
    goLeft cm = cm

    goRight (CMode xs c (y:ys)) = CMode (c:xs) y ys
    goRight cm = cm

    moveToStart (CMode xs c ys) = let zs = reverse xs ++ (c:ys) in CMode [] (head zs) (tail zs)
    moveToStart CEmpty = CEmpty

    moveToEnd (CMode xs c ys) = let zs = reverse ys ++ (c:xs) in CMode (tail zs) (head zs) []
    moveToEnd CEmpty = CEmpty

deleteChar :: CommandMode -> CommandMode
deleteChar (CMode xs _ (y:ys)) = CMode xs y ys
deleteChar (CMode (x:xs) _ []) = CMode xs x []
deleteChar _ = CEmpty

replaceChar :: Char -> CommandMode -> CommandMode
replaceChar c (CMode xs d ys)
    | not (isCombiningChar c)   = CMode xs (baseGrapheme c) ys
    | otherwise                 = CMode xs (addCombiner d c) ys
replaceChar _ CEmpty = CEmpty

pasteGraphemesBefore, pasteGraphemesAfter :: [Grapheme] -> CommandMode -> CommandMode
pasteGraphemesBefore [] = id
pasteGraphemesBefore s = enterCommandMode . insertGraphemes s . insertFromCommandMode

pasteGraphemesAfter [] = id
pasteGraphemesAfter s = enterCommandMode . insertGraphemes s . appendFromCommandMode

------------------------
-- Transitioning between modes

enterCommandMode, enterCommandModeRight :: InsertMode -> CommandMode
enterCommandMode (IMode (x:xs) ys) = CMode xs x ys
enterCommandMode (IMode [] (y:ys)) = CMode [] y ys
enterCommandMode _ = CEmpty

enterCommandModeRight (IMode xs (y:ys)) = CMode xs y ys
enterCommandModeRight (IMode (x:xs) []) = CMode xs x []
enterCommandModeRight _ = CEmpty


insertFromCommandMode, appendFromCommandMode :: CommandMode -> InsertMode

insertFromCommandMode CEmpty = emptyIM
insertFromCommandMode (CMode xs c ys) = IMode xs (c:ys)

appendFromCommandMode CEmpty = emptyIM
appendFromCommandMode (CMode xs c ys) = IMode (c:xs) ys

withCommandMode :: (InsertMode -> InsertMode) -> CommandMode -> CommandMode
withCommandMode f = enterCommandModeRight . f . insertFromCommandMode

----------------------
-- Supplementary modes

-- | Used for commands which take an integer argument.
data ArgMode s = ArgMode {arg :: Int, argState :: s}

instance Functor ArgMode where
    fmap f am = am {argState = f (argState am)}

instance LineState s => LineState (ArgMode s) where
    beforeCursor _ am = let pre = map baseGrapheme $ "(arg: " ++ show (arg am) ++ ") "
                             in beforeCursor pre (argState am)
    afterCursor = afterCursor . argState

instance Result s => Result (ArgMode s) where
    toResult = toResult . argState

instance Save s => Save (ArgMode s) where
    save = save . argState
    restore = startArg 0 . restore

startArg :: Int -> s -> ArgMode s
startArg = ArgMode

addNum :: Int -> ArgMode s -> ArgMode s
addNum n am
    | arg am >= 1000 = am -- shouldn't ever need more than 4 digits
    | otherwise = am {arg = arg am * 10 + n}

-- TODO: negatives
applyArg :: (s -> s) -> ArgMode s -> s
applyArg f am = repeatN (arg am) f (argState am)

repeatN :: Int -> (a -> a) -> a -> a
repeatN n f | n <= 1 = f
            | otherwise = f . repeatN (n-1) f

applyCmdArg :: (InsertMode -> InsertMode) -> ArgMode CommandMode -> CommandMode
applyCmdArg f am = withCommandMode (repeatN (arg am) f) (argState am)

---------------
newtype Message = Message {messageText :: String}

instance LineState Message where
    beforeCursor _ = stringToGraphemes . messageText
    afterCursor _ = []

----------------

data Password = Password {passwordState :: [Char], -- ^ reversed
                          passwordChar :: Maybe Char}

instance LineState Password where
    beforeCursor prefix p
        = prefix ++ (stringToGraphemes
                      $ case passwordChar p of
                        Nothing -> []
                        Just c -> replicate (length $ passwordState p) c)
    afterCursor _ = []

instance Result Password where
    toResult = reverse . passwordState

addPasswordChar :: Char -> Password -> Password
addPasswordChar c p = p {passwordState = c : passwordState p}

deletePasswordChar :: Password -> Password
deletePasswordChar (Password (_:cs) m) = Password cs m
deletePasswordChar p = p

-----------------
atStart, atEnd :: (Char -> Bool) -> InsertMode -> Bool
atStart f (IMode (x:_) (y:_)) = not (f (baseChar x)) && f (baseChar y)
atStart _ _ = False

atEnd f (IMode _ (y1:y2:_)) = f (baseChar y1) && not (f (baseChar y2))
atEnd _ _ = False

overChar, beforeChar, afterChar :: (Char -> Bool) -> InsertMode -> Bool
overChar f (IMode _ (y:_)) = f (baseChar y)
overChar _ _ = False

beforeChar f (IMode _ (_:y:_)) = f (baseChar y)
beforeChar _ _ = False

afterChar f (IMode (x:_) _) = f (baseChar x)
afterChar _ _ = False

goRightUntil, goLeftUntil :: (InsertMode -> Bool) -> InsertMode -> InsertMode
goRightUntil f = loop . goRight
    where
        loop im@(IMode _ ys) | null ys || f im = im
                             | otherwise = loop (goRight im)
goLeftUntil f = loop . goLeft
    where
        loop im@(IMode xs _) | null xs || f im = im
                             | otherwise = loop (goLeft im)
