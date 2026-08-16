(*
MIT License

Copyright (c) 2026 by.LaoZhang qq600585

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*)
{ ******************************************************************************
  * Z.Parsing – Lexical Analysis and Text Manipulation Engine
  *
  * This unit provides a high-performance, multi‑style lexical analyser and
  * text processing framework. It is the foundation for expression parsers
  * (e.g., Z.Expression) and any component that needs to tokenise, analyse,
  * or transform source code or structured text.
  *
  * ===========================================================================
  * Core capabilities
  * ===========================================================================
  *   • Multi‑style support – Pascal, C, and plain text.
  *   • Full tokenisation – numbers, identifiers, symbols, string literals,
  *     comments, and multi‑character special symbols (e.g., ‘>=’).
  *   • Caching – builds an indexed token stream and a character‑to‑token
  *     map for O(1) lookups.
  *   • Text editing – delete, insert, remove comments, and convert between
  *     Pascal and C string/comment styles.
  *   • Advanced probing – search left/right for tokens, match parentheses
  *     and brackets, extract comma‑separated vectors and matrices.
  *   • Performance – block memory operations, binary search, precomputed
  *     caches, and minimal heap allocations.
  *   • Cross‑compiler – unifies Delphi and Free Pascal string types.
  *   • Unicode‑aware – handles UTF‑16 characters correctly.
  *
  * ===========================================================================
  * Typical workflow
  * ===========================================================================
  *   1. Create a TTextParsing instance with your source text and style.
  *   2. The constructor automatically builds the cache (comments, strings,
  *      tokens, and char‑token map).
  *   3. Use the Probe* methods to locate tokens, the Split* methods to
  *      extract vectors, and the GetText* methods to retrieve substrings.
  *   4. If you modify the text (via DeletePos, InsertTextBlock, etc.),
  *      call RebuildParsingCache to refresh the internal structures.
  *   5. Use the Translate_* class methods to convert between Pascal/C
  *      string and comment declarations.
  *
  * ===========================================================================
  * Example (basic tokenisation and probing)
  * ===========================================================================
  *   var
  *     Parser: TTextParsing;
  *     Tok: PTokenData;
  *   begin
  *     // Parse a Pascal expression
  *     Parser := TTextParsing.Create('x := 42 + sin(y);', tsPascal);
  *     try
  *       // Find the first identifier (token type ttAscii)
  *       Tok := Parser.TokenProbeR(0, [ttAscii]);
  *       if Tok <> nil then
  *         DoStatus('First identifier: ' + Tok^.Text.Text);   // 'x'
  *
  *       // Find the assignment symbol ':=' (a special symbol)
  *       Tok := Parser.TokenProbeR(0, [ttSpecialSymbol]);
  *       if Tok <> nil then
  *         DoStatus('Assignment token: ' + Tok^.Text.Text);   // ':='
  *
  *       // Extract all numbers from the text
  *       for i := 0 to Parser.TokenCount - 1 do
  *         if Parser.Tokens[i]^.tokenType = ttNumber then
  *           DoStatus('Number: ' + Parser.Tokens[i]^.Text.Text);
  *     finally
  *       Parser.Free;
  *     end;
  *   end;
  *
  * ===========================================================================
  * Example (extracting a vector from a comma‑separated list)
  * ===========================================================================
  *   var
  *     Parser: TTextParsing;
  *     Vec: TSymbolVector;
  *     i: Integer;
  *   begin
  *     Parser := TTextParsing.Create('a, b+c, (d*e), f[g]', tsPascal);
  *     try
  *       Vec := Parser.Extract_Symbol_Vector;   // returns an array of strings
  *       for i := 0 to High(Vec) do
  *         DoStatus('Element ' + IntToStr(i) + ': ' + Vec[i].Text);
  *       // Output:
  *       // Element 0: a
  *       // Element 1: b+c
  *       // Element 2: (d*e)
  *       // Element 3: f[g]
  *     finally
  *       Parser.Free;
  *     end;
  *   end;
  *
  * ===========================================================================
  * Example (converting a Pascal string declaration to plain text)
  * ===========================================================================
  *   var
  *     Plain: TP_String;
  *   begin
  *     Plain := TTextParsing.Translate_Pascal_Decl_To_Text(''Hello,'+#10+'World'');
  *     // Plain becomes 'Hello,' + #10 + 'World' (two lines)
  *   end;
  ****************************************************************************** }
unit Z.Parsing;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses
  Types,
{$IFDEF FPC}
  Z.FPC.GenericList,
{$ENDIF FPC}
  Z.Core,
  Z.PascalStrings,
  Z.UPascalStrings,
  Z.ListEngine;

type
  { ============================================================================
    Cross‑compiler type aliases
    ============================================================================
    These aliases unify Delphi and Free Pascal string and character types so
    that the rest of the unit can be written without conditional compilation.
    Under FPC we use the Unicode types (TU...), under Delphi we use the
    pre‑Unicode types (which are also Unicode under recent Delphi versions).
    -------------------------------------------------------------------------- }
{$IFDEF FPC}
  TP_String = TUPascalString; // Unicode string type (UTF‑16)
  TP_PString = PUPascalString; // Pointer to TP_String
  TP_SystemString = USystemString; // Native system string (UnicodeString)
  TP_Char = USystemChar; // Unicode character (UTF‑16 code unit)
  TP_ArrayString = TUArrayPascalString; // Dynamic array of TP_String
  TP_OrdChar = TUOrdChar; // Character category enum (e.g., uc0to9)
  TP_OrdChars = TUOrdChars; // Set of TP_OrdChar
{$ELSE FPC}
  TP_String = TPascalString; // Pascal string (UTF‑16 in Delphi)
  TP_PString = PPascalString; // Pointer to TP_String
  TP_SystemString = SystemString; // Native string
  TP_Char = SystemChar; // System character (WideChar)
  TP_ArrayString = TArrayPascalString;
  TP_OrdChar = TOrdChar;
  TP_OrdChars = TOrdChars;
{$ENDIF FPC}
  { ----------------------------------------------------------------------------
    TTextStyle – syntax rules for parsing
    - tsPascal : single‑quoted strings, #‑numbered chars, Pascal comments
    - tsC      : double‑quoted strings with escapes, C‑style comments
    - tsText   : no special interpretation (literal text)
  }
  TTextStyle = (tsPascal, tsC, tsText);

  { ----------------------------------------------------------------------------
    TTokenType – classifies a lexical token
    - ttTextDecl   : string literal (e.g., 'hello', "world", #65)
    - ttComment    : comment block
    - ttNumber     : numeric literal (integer, float, hex)
    - ttSymbol     : single‑character operator/punctuation (e.g., '+', ',')
    - ttAscii      : alphanumeric identifier (e.g., 'variable', 'sin')
    - ttSpecialSymbol : multi‑character symbol (e.g., '>=', ':=', '<<')
    - ttUnknow     : unrecognised sequence (should not occur normally)
  }
  TTokenType = (ttTextDecl, ttComment, ttNumber, ttSymbol, ttAscii,
    ttSpecialSymbol, ttUnknow);
  TTokenTypes = set of TTokenType; // Used for filtering in probing methods

  { TTokenStatistics – counts of each token type in the parsed text }
  TTokenStatistics = array [TTokenType] of Integer;

  { ----------------------------------------------------------------------------
    TTextPos – describes a contiguous range (span) in the source text.
    - bPos : 1‑based start index (inclusive).
    - ePos : 1‑based end index (exclusive – the first character after the span).
    - Text : the actual substring (cached for fast access).
  }
  TTextPos = record
    bPos, ePos: Integer;
    Text: TP_String;
  end;

  PTextPos = ^TTextPos;

  { ----------------------------------------------------------------------------
    TTokenData – stores information about a single token.
    - bPos/ePos   : source range.
    - Text        : the token’s textual content.
    - tokenType   : classification.
    - Index       : sequential position in the token list (0‑based).
  }
  TTokenData = record
    bPos, ePos: Integer;
    Text: TP_String;
    tokenType: TTokenType;
    Index: Integer;
    procedure Init; // initialises all fields to default values
  end;

  PTokenData = ^TTokenData;

  { Internal generic lists used to store collections of text positions and tokens }
  TTextPosList_Decl = TGenericsList<PTextPos>;
  TTokenDataList_Decl = TGenericsList<PTokenData>;

  { ----------------------------------------------------------------------------
    TTextParsingCache – holds all pre‑computed parsing information.
    - CommentDecls : list of comment ranges.
    - TextDecls    : list of string literal ranges.
    - TokenDataList: ordered list of all tokens (in source order).
    - CharToken    : array mapping each character position (0‑based) to its
    owning token. This enables O(1) token lookup by position.
  }
  TTextParsingCache = record
    CommentDecls, TextDecls: TTextPosList_Decl;
    TokenDataList: TTokenDataList_Decl;
    CharToken: array of PTokenData;
  end;

  { ----------------------------------------------------------------------------
    TTextParsingData – runtime data container for a parser instance.
    - Cache : the parsed cache.
    - Text  : the source text (with an appended space for safe scanning).
    - L     : length of the text.
  }
  TTextParsingData = record
    Cache: TTextParsingCache;
    Text: TP_String;
    L: Integer;
    property Len: Integer read L; // alias for L
  end;

  { TSymbolVector – dynamic array of TP_String, used to represent a list of
    expressions (vector) extracted from the source. }
  TSymbolVector = TP_ArrayString;

  { TSymbolMatrix – 2D array of TSymbolVector, used to represent a matrix
    of expressions (rows × columns). }
  TSymbolMatrix = array of TSymbolVector;

  { ============================================================================
    TTextParsing – main lexical analysis and text manipulation class.
    ============================================================================
    This class is the primary entry point. It parses the source text,
    builds internal caches, and provides a rich set of methods for probing,
    extracting, and transforming the text.

    Properties and fields are public for direct access, but you normally
    use the provided methods.
  }
  TTextParsing = class(TCore_Object_Intermediate)
  public
    TextStyle: TTextStyle; // Parsing style (Pascal, C, or Text)
    ParsingData: TTextParsingData; // Internal cache and source text
    SymbolTable: TP_String; // Characters treated as single symbols (e.g., operators)
    TokenStatistics: TTokenStatistics; // Counts of each token type
    SpecialSymbol: TListPascalString; // List of multi‑character symbols (e.g., '>=', '<<')
    RebuildCacheBusy: Boolean; // Internal flag to prevent re‑entrant cache rebuilds

    { ==========================================================================
      Character classification helpers (class methods)
      ==========================================================================
      These overloaded functions test whether a character belongs to a set
      of characters, a string, an ordinal category, or a combination.
    }
    class function Char_is(c: TP_Char; SomeChars: array of TP_Char): Boolean; overload;
    class function Char_is(c: TP_Char; SomeChar: TP_Char): Boolean; overload;
    class function Char_is(c: TP_Char; s: TP_String): Boolean; overload;
    class function Char_is(c: TP_Char; p: TP_PString): Boolean; overload;
    class function Char_is(c: TP_Char; SomeCharsets: TP_OrdChars): Boolean; overload;
    class function Char_is(c: TP_Char; SomeCharset: TP_OrdChar): Boolean; overload;
    class function Char_is(c: TP_Char; SomeCharsets: TP_OrdChars; SomeChars: TP_String): Boolean; overload;
    class function Char_is(c: TP_Char; SomeCharsets: TP_OrdChars; p: TP_PString): Boolean; overload;

    { ==========================================================================
      Position‑based comparison
      ==========================================================================
      These methods check if the text at a given offset (1‑based) matches a
      literal string or character. Useful during manual scanning.
    }
    function ComparePosStr(cOffset: Integer; t: TP_String): Boolean; overload;
    function ComparePosStr(cOffset: Integer; p: TP_PString): Boolean; overload;
    function ComparePosChar(cOffset: Integer; c: TP_Char): Boolean; overload;
    function ComparePosChar(cOffset: Integer; c: TP_Char; ignoreCase_: Boolean): Boolean; overload;

    { ==========================================================================
      Comment and text declaration boundaries
      ==========================================================================
      These functions determine the end position of a comment or string literal
      starting at the given offset. They use the cache if available, otherwise
      they perform a full scan.
    }
    function CompareCommentGetEndPos(cOffset: Integer): Integer;
    function CompareTextDeclGetEndPos(cOffset: Integer): Integer;

    { ==========================================================================
      Cache rebuilding
      ==========================================================================
      RebuildParsingCache   : rebuilds the entire cache from the current Text.
      RebuildText           : updates the Text from the cached comment/string ranges
      (used after modifying those ranges).
      RebuildToken          : rebuilds the Text from the token list.
      FastRebuildTokenTo    : returns a new TP_String built from tokens without
      modifying the internal state.
    }
    procedure RebuildParsingCache;
    procedure RebuildText;
    procedure RebuildToken;
    function FastRebuildTokenTo(): TP_String;

    { ==========================================================================
      Context (token) boundaries
      ==========================================================================
      GetContextBeginPos and GetContextEndPos return the start/end character
      positions of the token that contains the given offset.
    }
    function GetContextBeginPos(cOffset: Integer): Integer;
    function GetContextEndPos(cOffset: Integer): Integer;

    { ==========================================================================
      Special symbol detection
      ==========================================================================
      isSpecialSymbol checks if a position starts a multi‑character symbol
      (e.g., '>=', ':=', '<<'). The overloaded version also returns the end
      position of that symbol.
    }
    function isSpecialSymbol(cOffset: Integer): Boolean; overload;
    function isSpecialSymbol(cOffset: Integer; var speicalSymbolEndPos: Integer): Boolean; overload;
    function GetSpecialSymbolEndPos(cOffset: Integer): Integer; // returns end pos, or cOffset if not found

    { ==========================================================================
      Number detection
      ==========================================================================
      isNumber checks if a position starts a numeric literal (decimal, hex,
      with optional sign). The overloaded version also indicates whether it
      is hex and returns the start position (ignoring leading '+'/'-').
      GetNumberEndPos returns the exclusive end of the number.
    }
    function isNumber(cOffset: Integer): Boolean; overload;
    function isNumber(cOffset: Integer; var NumberBegin: Integer; var IsHex: Boolean): Boolean; overload;
    function GetNumberEndPos(cOffset: Integer): Integer;

    { ==========================================================================
      String literal (text declaration) detection
      ==========================================================================
      isTextDecl     : checks if a position starts a string literal.
      GetTextDeclEndPos / GetTextDeclBeginPos : get the end/start of the literal.
      GetTextBody    : extracts the actual content (without quotes/escapes) from a
      literal text.
      GetTextDeclPos : fills the begin/end positions of the literal containing
      the given offset; returns True if found.
    }
    function isTextDecl(cOffset: Integer): Boolean;
    function GetTextDeclEndPos(cOffset: Integer): Integer;
    function GetTextDeclBeginPos(cOffset: Integer): Integer;
    function GetTextBody(Text_: TP_String): TP_String;
    function GetTextDeclPos(cOffset: Integer; var charBeginPos, charEndPos: Integer): Boolean;

    { ==========================================================================
      Single‑character symbol detection
      ==========================================================================
      isSymbol checks if a position is a single‑character symbol (as defined
      in SymbolTable). GetSymbolEndPos returns the end (cOffset+1) if it is.
    }
    function isSymbol(cOffset: Integer): Boolean;
    function GetSymbolEndPos(cOffset: Integer): Integer;

    { ==========================================================================
      ASCII / identifier detection
      ==========================================================================
      isAscii checks if a position is part of an alphanumeric identifier
      (not a comment, string, number, or symbol). GetAsciiBeginPos and
      GetAsciiEndPos return the boundaries of the identifier.
    }
    function isAscii(cOffset: Integer): Boolean;
    function GetAsciiBeginPos(cOffset: Integer): Integer;
    function GetAsciiEndPos(cOffset: Integer): Integer;

    { ==========================================================================
      Comment detection
      ==========================================================================
      isComment checks if a position lies inside a comment. GetCommentEndPos,
      GetCommentBeginPos, and GetCommentPos provide the boundaries.
      GetDeletedCommentText returns a copy of the source with all comments removed.
    }
    function isComment(cOffset: Integer): Boolean;
    function GetCommentEndPos(cOffset: Integer): Integer;
    function GetCommentBeginPos(cOffset: Integer): Integer;
    function GetCommentPos(cOffset: Integer; var charBeginPos, charEndPos: Integer): Boolean;
    function GetDeletedCommentText: TP_String;

    { ==========================================================================
      Composite checks
      ==========================================================================
      isTextOrComment   : checks if position is inside a string or comment.
      isCommentOrText   : same order (alias).
    }
    function isTextOrComment(cOffset: Integer): Boolean;
    function isCommentOrText(cOffset: Integer): Boolean;

    { ==========================================================================
      Word splitting helpers
      ==========================================================================
      isWordSplitChar checks if a character is a word separator (space,
      punctuation, etc.). Overloads allow customising the split characters
      and whether to include control characters (0‑32).
      GetWordBeginPos and GetWordEndPos return the boundaries of the word
      (contiguous non‑separator characters) containing the given offset.
    }
    class function isWordSplitChar(c: TP_Char): Boolean; overload;
    class function isWordSplitChar(c: TP_Char; Split_Token_Char: TP_String): Boolean; overload;
    class function isWordSplitChar(c: TP_Char; Include_C_0_to_32: Boolean; Split_Token_Char: TP_String): Boolean; overload;
    function GetWordBeginPos(cOffset: Integer; Split_Token_Char: TP_String): Integer; overload;
    function GetWordBeginPos(cOffset: Integer): Integer; overload;
    function GetWordBeginPos(cOffset: Integer; Include_C_0_to_32: Boolean; Split_Token_Char: TP_String): Integer; overload;
    function GetWordEndPos(cOffset: Integer; Split_Token_Char: TP_String): Integer; overload;
    function GetWordEndPos(cOffset: Integer): Integer; overload;
    function GetWordEndPos(cOffset: Integer; BeginSplitCharSet, EndSplitCharSet: TP_String): Integer; overload;
    function GetWordEndPos(cOffset: Integer; Include_C_0_to_32: Boolean; BeginSplitCharSet: TP_String; EndDefaultChar: Boolean; EndSplitCharSet: TP_String): Integer; overload;

    { ==========================================================================
      Sniffing – find the next occurrence of a specific character
      ==========================================================================
      SniffingNextChar skips whitespace, comments, and string literals, and
      looks for a character that belongs to the given set. Returns True if found
      and sets OutPos to its position.
    }
    function SniffingNextChar(cOffset: Integer; declChar: TP_String): Boolean; overload;
    function SniffingNextChar(cOffset: Integer; declChar: TP_String; out OutPos: Integer): Boolean; overload;

    { ==========================================================================
      Splitting text into a vector
      ==========================================================================
      SplitChar splits the text using single characters as delimiters.
      SplitString uses multi‑character strings as delimiters.
      Overloads allow specifying start offset, end delimiter, and whether to
      include control characters.
      The result is placed in the dynamic array SplitOutput, and the LastPos
      parameter receives the position after the last processed character.
      Returns the number of elements extracted.
    }
    function SplitChar(cOffset: Integer; var LastPos: Integer;
      Include_C_0_to_32: Boolean; Split_Token_Char, Split_End_Token_Char: TP_String;
      var SplitOutput: TSymbolVector): Integer; overload;
    function SplitChar(cOffset: Integer; var LastPos: Integer;
      Split_Token_Char, Split_End_Token_Char: TP_String;
      var SplitOutput: TSymbolVector): Integer; overload;
    function SplitChar(cOffset: Integer; Split_Token_Char, Split_End_Token_Char: TP_String;
      var SplitOutput: TSymbolVector): Integer; overload;
    function SplitString(cOffset: Integer; var LastPos: Integer;
      SplitTokenS, SplitEndTokenS: TP_String; var SplitOutput: TSymbolVector): Integer; overload;
    function SplitString(cOffset: Integer; SplitTokenS, SplitEndTokenS: TP_String;
      var SplitOutput: TSymbolVector): Integer; overload;

    { ==========================================================================
      Token access and manipulation
      ==========================================================================
      CompareTokenText / CompareTokenChar compare a token’s text with a string
      or character at a given offset.
      GetToken returns the token containing a character position.
      TokenCount gives the total number of tokens.
      TokenCountT counts tokens of a specific type.
      Tokens provides indexed access to tokens.
      FirstToken / LastToken give the first/last token.
      NextToken / PrevToken move to adjacent tokens.
      TokenCombine (and Combine alias) concatenates tokens from a range,
      optionally filtering by token type.
    }
    function CompareTokenText(cOffset: Integer; t: TP_String): Boolean;
    function CompareTokenChar(cOffset: Integer; c: array of TP_Char): Boolean;
    function GetToken(cOffset: Integer): PTokenData;
    property TokenPos[cOffset: Integer]: PTokenData read GetToken;
    property CharToken[cOffset: Integer]: PTokenData read GetToken;
    function GetTokenIndex(t: TTokenType; idx: Integer): PTokenData;
    property TokenIndex[t: TTokenType; idx: Integer]: PTokenData read GetTokenIndex;
    function TokenCount: Integer; overload;
    function TokenCountT(t: TTokenTypes): Integer; overload;
    function GetTokens(idx: Integer): PTokenData;
    property Tokens[idx: Integer]: PTokenData read GetTokens; default;
    property Token[idx: Integer]: PTokenData read GetTokens;
    property Count: Integer read TokenCount;
    function FirstToken: PTokenData;
    function LastToken: PTokenData;
    function NextToken(p: PTokenData): PTokenData;
    function PrevToken(p: PTokenData): PTokenData;
    function TokenCombine(bTokenI, eTokenI: Integer; acceptT: TTokenTypes): TP_String; overload;
    function TokenCombine(bTokenI, eTokenI: Integer): TP_String; overload;
    function Combine(bTokenI, eTokenI: Integer; acceptT: TTokenTypes): TP_String; overload;
    function Combine(bTokenI, eTokenI: Integer): TP_String; overload;

    { ==========================================================================
      Token probing (left/right search)
      ==========================================================================
      TokenProbeL searches leftwards from a given token index for a token that
      matches certain criteria (type, text, or both). TokenProbeR searches
      rightwards. Overloads allow multiple text options.
      Shorter aliases: ProbeL, LProbe, ProbeR, RProbe.
    }
    function TokenProbeL(startI: Integer; acceptT: TTokenTypes): PTokenData; overload;
    function TokenProbeL(startI: Integer; t: TP_String): PTokenData; overload;
    function TokenProbeL(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData; overload;
    function TokenProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2: TP_String): PTokenData; overload;
    function TokenProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2, t3: TP_String): PTokenData; overload;
    function TokenProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4: TP_String): PTokenData; overload;
    function TokenProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4, t5: TP_String): PTokenData; overload;
    function TokenProbeR(startI: Integer; acceptT: TTokenTypes): PTokenData; overload;
    function TokenProbeR(startI: Integer; t: TP_String): PTokenData; overload;
    function TokenProbeR(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData; overload;
    function TokenProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2: TP_String): PTokenData; overload;
    function TokenProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2, t3: TP_String): PTokenData; overload;
    function TokenProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4: TP_String): PTokenData; overload;
    function TokenProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4, t5: TP_String): PTokenData; overload;

    function ProbeL(startI: Integer; acceptT: TTokenTypes): PTokenData; overload;
    function ProbeL(startI: Integer; t: TP_String): PTokenData; overload;
    function ProbeL(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData; overload;
    function ProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2: TP_String): PTokenData; overload;
    function ProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2, t3: TP_String): PTokenData; overload;
    function ProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4: TP_String): PTokenData; overload;
    function ProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4, t5: TP_String): PTokenData; overload;
    function LProbe(startI: Integer; acceptT: TTokenTypes): PTokenData; overload;
    function LProbe(startI: Integer; t: TP_String): PTokenData; overload;
    function LProbe(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData; overload;
    function LProbe(startI: Integer; acceptT: TTokenTypes; t1, t2: TP_String): PTokenData; overload;
    function LProbe(startI: Integer; acceptT: TTokenTypes; t1, t2, t3: TP_String): PTokenData; overload;
    function LProbe(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4: TP_String): PTokenData; overload;
    function LProbe(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4, t5: TP_String): PTokenData; overload;

    function ProbeR(startI: Integer; acceptT: TTokenTypes): PTokenData; overload;
    function ProbeR(startI: Integer; t: TP_String): PTokenData; overload;
    function ProbeR(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData; overload;
    function ProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2: TP_String): PTokenData; overload;
    function ProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2, t3: TP_String): PTokenData; overload;
    function ProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4: TP_String): PTokenData; overload;
    function ProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4, t5: TP_String): PTokenData; overload;
    function RProbe(startI: Integer; acceptT: TTokenTypes): PTokenData; overload;
    function RProbe(startI: Integer; t: TP_String): PTokenData; overload;
    function RProbe(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData; overload;
    function RProbe(startI: Integer; acceptT: TTokenTypes; t1, t2: TP_String): PTokenData; overload;
    function RProbe(startI: Integer; acceptT: TTokenTypes; t1, t2, t3: TP_String): PTokenData; overload;
    function RProbe(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4: TP_String): PTokenData; overload;
    function RProbe(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4, t5: TP_String): PTokenData; overload;

    { ==========================================================================
      Extended probing – search for a token whose text starts with a given
      string (full‑string match). Useful for identifying prefixes.
    }
    function TokenFullStringProbe(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData;
    function StringProbe(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData;

    { ==========================================================================
      Indent (parentheses/brackets) matching
      ==========================================================================
      IndentSymbolEndProbeR finds the matching closing symbol for an opening
      symbol (e.g., ‘)’ for ‘(’). IndentSymbolBeginProbeL does the reverse.
    }
    function IndentSymbolEndProbeR(startI: Integer; indent_begin_symbol, indent_end_symbol: TP_String): PTokenData;
    function IndentSymbolBeginProbeL(startI: Integer; indent_begin_symbol, indent_end_symbol: TP_String): PTokenData;

    { ==========================================================================
      Vector / matrix extraction
      ==========================================================================
      DetectSymbolVector checks if the text contains a top‑level vector
      (comma‑separated list) by scanning for comma/semicolon tokens.
      Extract_Symbol_Vector returns the vector elements as a TPascalStringList
      or a dynamic array (TSymbolVector).
      FillSymbolMatrix fills a matrix (rows × columns) from a flat vector.
    }
    function DetectSymbolVector: Boolean;
    function Extract_Symbol_Vector(L: TPascalStringList): Boolean; overload;
    function Extract_Symbol_Vector: TSymbolVector; overload;
    function FillSymbolMatrix(W, H: Integer; var symbolMatrix: TSymbolMatrix): Boolean;

    { ==========================================================================
      Text extraction and editing
      ==========================================================================
      GetText / GetStr retrieve a substring by character range.
      GetWord extracts the word (identifier) at a given position.
      GetPoint converts a character position to line/column (TPoint).
      GetChar returns the character at a given offset.
      DeletePos removes a range, InsertTextBlock inserts text at a position.
      DeletedComment removes all comments from the text.
      SearchWordBody searches for an exact word and returns its position.
    }
    function GetText(bPos, ePos: Integer): TP_String; overload;
    function GetStr(bPos, ePos: Integer): TP_String; overload;
    function GetStr(tp: TTextPos): TP_String; overload;
    function GetWord(cOffset: Integer): TP_String; overload;
    function GetPoint(cOffset: Integer): TPoint;
    function GetChar(cOffset: Integer): TP_Char;
    property Len: Integer read ParsingData.L;
    property ParseText: TP_String read ParsingData.Text;
    property Text: TP_String read ParsingData.Text;

    procedure DeletePos(bPos, ePos: Integer); overload;
    procedure DeletePos(tp: TTextPos); overload;
    procedure DeletedComment;
    procedure InsertTextBlock(bPos, ePos: Integer; InsertText_: TP_String); overload;
    procedure InsertTextBlock(tp: TTextPos; InsertText_: TP_String); overload;
    function SearchWordBody(initPos: Integer; wordInfo: TP_String; var OutPos: TTextPos): Boolean;

    { ==========================================================================
      String declaration conversion (class methods)
      ==========================================================================
      Translate_Pascal_Decl_To_Text   : converts a Pascal string literal to plain text.
      Translate_Text_To_Pascal_Decl   : converts plain text to Pascal string literal.
      Translate_Text_To_Pascal_Decl_With_Unicode : same but encodes non‑ASCII as #... sequences.
      Translate_C_Decl_To_Text        : converts a C string literal to plain text.
      Translate_Text_To_C_Decl        : converts plain text to C string literal with escapes.
    }
    class function Translate_Pascal_Decl_To_Text(Decl: TP_String): TP_String;
    class function Translate_Text_To_Pascal_Decl(Decl: TP_String): TP_String;
    class function Translate_Text_To_Pascal_Decl_With_Unicode(Decl: TP_String): TP_String;
    class function Translate_C_Decl_To_Text(Decl: TP_String): TP_String;
    class function Translate_Text_To_C_Decl(Decl: TP_String): TP_String;

    { ==========================================================================
      Comment declaration conversion (class methods)
      ==========================================================================
      Translate_Pascal_Decl_Comment_To_Text   : extracts content from Pascal comment.
      Translate_Text_To_Pascal_Decl_Comment   : wraps text in Pascal comment.
      Translate_C_Decl_Comment_To_Text        : extracts content from C comment.
      Translate_Text_To_C_Decl_Comment        : wraps text in C comment.
    }
    class function Translate_Pascal_Decl_Comment_To_Text(Decl: TP_String): TP_String;
    class function Translate_Text_To_Pascal_Decl_Comment(Decl: TP_String): TP_String;
    class function Translate_C_Decl_Comment_To_Text(Decl: TP_String): TP_String;
    class function Translate_Text_To_C_Decl_Comment(Decl: TP_String): TP_String;

    { ==========================================================================
      Constructors and destructor
      ==========================================================================
      Create(Text_, Style_, SpecialSymbol_, SpacerSymbol_) : full constructor.
      Create(Text_, Style_, SpecialSymbol_)                  : uses global SpacerSymbol.
      Create(Text_, Style_)                                  : no special symbols.
      Create(Text_)                                          : tsText style.
      The constructor automatically builds the parsing cache.
      Destroy frees all internal resources.
    }
    constructor Create(Text_: TP_String; Style_: TTextStyle;
      SpecialSymbol_: TListPascalString; SpacerSymbol_: TP_SystemString); overload;
    constructor Create(Text_: TP_String; Style_: TTextStyle;
      SpecialSymbol_: TListPascalString); overload;
    constructor Create(Text_: TP_String; Style_: TTextStyle); overload;
    constructor Create(Text_: TP_String); overload;
    destructor Destroy; override;

    { ==========================================================================
      Virtual hooks for descendants
      ==========================================================================
      Init    : called after construction; override for custom initialisation.
      Parsing : override to implement custom parsing logic (returns True on success).
    }
    procedure Init; virtual;
    function Parsing: Boolean; virtual;

    { ==========================================================================
      Debug output
      ==========================================================================
      Print writes all tokens to the status console (Z.Status).
    }
    procedure Print;
  end;

  { TTextParsingClass – meta‑class for dynamic creation of TTextParsing descendants }
  TTextParsingClass = class of TTextParsing;

const
  { C_SpacerSymbol – default set of single‑character symbols (operators and
    punctuation) used when no custom symbol table is provided. }
  C_SpacerSymbol = #44#43#45#42#47#40#41#59#58#61#35#64#94#38#37#33#34#91#93#60#62#63#123#125#39#36#124;

var
  { SpacerSymbol – global atomically‑reference‑counted string that holds the
    default symbol table. It can be changed at runtime. }
  SpacerSymbol: TAtomString;

implementation

uses Z.Status, Z.UnicodeMixedLib, TypInfo;

type
  { ----------------------------------------------------------------------------
    TCTranslateStruct – internal mapping between a control character and its
    C‑style escape sequence (e.g., #10 -> '\n').
  }
  TCTranslateStruct = record
    s: TP_Char; // character to be escaped
    c: TP_SystemString; // escape sequence (string)
  end;

const
  { NullTokenStatistics – a zero‑initialised token statistics record }
  NullTokenStatistics: TTokenStatistics = (0, 0, 0, 0, 0, 0, 0);

  { CTranslateTable – translation table for common C escapes }
  CTranslateTable: array [0 .. 11] of TCTranslateStruct = (
    (s: #007; c: '\a'),
    (s: #008; c: '\b'),
    (s: #012; c: '\f'),
    (s: #010; c: '\n'),
    (s: #013; c: '\r'),
    (s: #009; c: '\t'),
    (s: #011; c: '\v'),
    (s: #092; c: '\\'),
    (s: #063; c: '\?'),
    (s: #039; c: '\'#39), // single quote
    (s: #034; c: '\"'), // double quote
    (s: #000; c: '\0')
    );

  { TTokenData.Init -------------------------------------------------------------
    * Resets all fields of a TTokenData record to safe default values.
  }
procedure TTokenData.Init;
begin
  bPos := -1;
  ePos := -1;
  Text := '';
  tokenType := ttUnknow;
  Index := -1;
end;

{ ============================================================================
  Character classification – delegate to the appropriate CharIn function
  depending on the compiler. These are thin wrappers that make the code
  easier to read.
  ============================================================================ }
class function TTextParsing.Char_is(c: TP_Char; SomeChars: array of TP_Char): Boolean;
begin
  Result := {$IFDEF FPC}UCharIn{$ELSE FPC}CharIn{$ENDIF FPC}(c, SomeChars);
end;

class function TTextParsing.Char_is(c: TP_Char; SomeChar: TP_Char): Boolean;
begin
  Result := {$IFDEF FPC}UCharIn{$ELSE FPC}CharIn{$ENDIF FPC}(c, SomeChar);
end;

class function TTextParsing.Char_is(c: TP_Char; s: TP_String): Boolean;
begin
  Result := {$IFDEF FPC}UCharIn{$ELSE FPC}CharIn{$ENDIF FPC}(c, s);
end;

class function TTextParsing.Char_is(c: TP_Char; p: TP_PString): Boolean;
begin
  Result := {$IFDEF FPC}UCharIn{$ELSE FPC}CharIn{$ENDIF FPC}(c, p);
end;

class function TTextParsing.Char_is(c: TP_Char; SomeCharsets: TP_OrdChars): Boolean;
begin
  Result := {$IFDEF FPC}UCharIn{$ELSE FPC}CharIn{$ENDIF FPC}(c, SomeCharsets);
end;

class function TTextParsing.Char_is(c: TP_Char; SomeCharset: TP_OrdChar): Boolean;
begin
  Result := {$IFDEF FPC}UCharIn{$ELSE FPC}CharIn{$ENDIF FPC}(c, SomeCharset);
end;

class function TTextParsing.Char_is(c: TP_Char; SomeCharsets: TP_OrdChars; SomeChars: TP_String): Boolean;
begin
  Result := {$IFDEF FPC}UCharIn{$ELSE FPC}CharIn{$ENDIF FPC}(c, SomeCharsets, SomeChars);
end;

class function TTextParsing.Char_is(c: TP_Char; SomeCharsets: TP_OrdChars; p: TP_PString): Boolean;
begin
  Result := {$IFDEF FPC}UCharIn{$ELSE FPC}CharIn{$ENDIF FPC}(c, SomeCharsets, p);
end;

{ ============================================================================
  Position‑based comparisons
  ============================================================================ }

function TTextParsing.ComparePosStr(cOffset: Integer; t: TP_String): Boolean;
{ * Compares the substring starting at cOffset with the given string t.
  * Uses the built‑in ComparePos method of TP_String.
  * @Param cOffset   : 1‑based start position.
  * @Param t         : string to compare.
  * @Return True if the substring at cOffset exactly matches t.
  * @Example:
  *   if Parser.ComparePosStr(5, 'then') then ... // checks if position 5 starts with 'then'
}
begin
  Result := ParsingData.Text.ComparePos(cOffset, t);
end;

function TTextParsing.ComparePosStr(cOffset: Integer; p: TP_PString): Boolean;
{ * Same as above, but takes a pointer to a TP_String.
}
begin
  Result := ParsingData.Text.ComparePos(cOffset, p);
end;

function TTextParsing.ComparePosChar(cOffset: Integer; c: TP_Char): Boolean;
{ * Compares the character at cOffset with the given character c.
}
begin
  Result := ParsingData.Text[cOffset] = c;
end;

function TTextParsing.ComparePosChar(cOffset: Integer; c: TP_Char; ignoreCase_: Boolean): Boolean;
{ * Compares the character at cOffset with c, optionally ignoring case.
  * When ignoreCase_ is True, uses ComparePosStr which does a case‑insensitive
  * comparison (depending on the TP_String implementation).
}
begin
  if ignoreCase_ then
      Result := ComparePosStr(cOffset, c)
  else
      Result := ComparePosChar(cOffset, c);
end;

{ ============================================================================
  Comment and text declaration boundaries
  ============================================================================ }

function TTextParsing.CompareCommentGetEndPos(cOffset: Integer): Integer;
{ * Determines the end position of a comment that starts at or contains cOffset.
  * It first checks the cache; if not available, it performs a manual scan
  * based on the current TextStyle.
  * @Param cOffset : 1‑based position within the text.
  * @Return The exclusive end position of the comment, or cOffset if no comment.
}
var
  L: Integer;
  cPos: Integer;
  tmpPos: Integer;
  p: PTokenData;
begin
  if not RebuildCacheBusy then
    begin
      // Use cached token if available
      p := TokenPos[cOffset];
      if p <> nil then
        begin
          if p^.tokenType = TTokenType.ttComment then
              Result := p^.ePos
          else
              Result := cOffset;
          exit;
        end;
    end;

  L := ParsingData.L;
  cPos := cOffset;
  if cPos < 1 then
      cPos := 1;
  if cPos > L then
      cPos := L;

  Result := cPos;

  if (TextStyle in [tsPascal, tsC]) and (ComparePosStr(Result, '//')) then
    begin
      // Pascal/C++ style single‑line comment
      inc(Result, 2);
      while not Char_is(ParsingData.Text[Result], [#13, #10]) do
        begin
          if Result + 1 > L then
              Break;
          inc(Result);
        end;
    end
  else if (TextStyle = tsC) and (ComparePosChar(Result, '#')) then
    begin
      // C preprocessor line (treated as comment)
      inc(Result, 1);
      while not Char_is(ParsingData.Text[Result], [#13, #10]) do
        begin
          if Result + 1 > L then
              Break;
          inc(Result);
        end;
    end
  else if (TextStyle = tsC) and (ComparePosStr(Result, '/*')) then
    begin
      // C multi‑line comment
      inc(Result, 2);
      while not ComparePosStr(Result, '*/') do
        begin
          if Result + 1 > L then
              Break;
          inc(Result);
        end;
      inc(Result, 2);
    end
  else if (TextStyle = tsPascal) and (ComparePosChar(Result, '{')) then
    begin
      // Pascal brace comment
      inc(Result, 1);
      while ParsingData.Text[Result] <> '}' do
        begin
          if Result + 1 > L then
              Break;
          inc(Result);
        end;
      inc(Result, 1);
    end
  else if (TextStyle = tsPascal) and (ComparePosStr(Result, '(*')) then
    begin
      // Pascal (* ... *) comment
      inc(Result, 2);
      while not ComparePosStr(Result, '*)') do
        begin
          if Result + 1 > L then
              Break;
          inc(Result);
        end;
      inc(Result, 2);
    end;
  if Result > L + 1 then
      Result := L + 1; // Ensure we don't go beyond the end
end;

function TTextParsing.CompareTextDeclGetEndPos(cOffset: Integer): Integer;
{ * Determines the end position of a string literal that starts at or contains
  * cOffset. Handles Pascal single‑quoted strings, C single‑ and double‑quoted
  * strings, and Pascal #‑encoded characters.
  * Uses cache if available.
  * @Param cOffset : 1‑based position.
  * @Return Exclusive end position of the literal.
}
var
  L: Integer;
  cPos: Integer;
  tmpPos: Integer;
  p: PTokenData;
begin
  if not RebuildCacheBusy then
    begin
      p := TokenPos[cOffset];
      if p <> nil then
        begin
          if p^.tokenType = TTokenType.ttTextDecl then
              Result := p^.ePos
          else
              Result := cOffset;
          exit;
        end;
    end;

  L := ParsingData.L;
  cPos := cOffset;
  if cPos < 1 then
      cPos := 1;
  if cPos > L then
      cPos := L;

  // Pascal single‑quoted string (including doubled quotes for embedded quote)
  if (cPos + 1 < L) and (TextStyle = tsPascal) and (ParsingData.Text[cPos] = #39) then
    begin
      if ComparePosStr(cPos, #39#39#39#39) then
        begin
          // Handle four consecutive quotes: '' '' -> literal string with empty?
          cPos := CompareTextDeclGetEndPos(cPos + 4);
          exit(cPos);
        end;
      inc(cPos, 1);
      while ParsingData.Text[cPos] <> #39 do
        begin
          if cPos + 1 > L then
              Break;
          if ParsingData.Text[cPos] = #10 then // line break inside string => error
              exit(cPos);
          inc(cPos);
        end;
      inc(cPos, 1);
    end;

  // C single‑quoted character literal (can contain escapes)
  if (cPos + 1 < L) and (TextStyle = tsC) and (ParsingData.Text[cPos] = #39) then
    begin
      inc(cPos, 1);
      while ParsingData.Text[cPos] <> #39 do
        begin
          if ComparePosStr(cPos, '\' + #39) then // escaped quote
              inc(cPos, 1);
          if cPos + 1 > L then
              Break;
          if ParsingData.Text[cPos] = #10 then
              exit(cPos);
          inc(cPos);
        end;
      inc(cPos, 1);
    end;

  // C double‑quoted string
  if (cPos + 1 < L) and (TextStyle = tsC) and (ParsingData.Text[cPos] = '"') then
    begin
      inc(cPos, 1);
      while ParsingData.Text[cPos] <> '"' do
        begin
          if ComparePosStr(cPos, '\"') then // escaped quote
              inc(cPos, 1);
          if cPos + 1 > L then
              Break;
          if ParsingData.Text[cPos] = #10 then
              exit(cPos);
          inc(cPos);
        end;
      inc(cPos, 1);
    end;

  // Pascal #‑encoded characters (e.g., #65#66)
  if (cPos + 1 < L) and (TextStyle = tsPascal) and (ParsingData.Text[cPos] = '#') then
    begin
      repeat
        inc(cPos, 1);
        // skip whitespace
        while isWordSplitChar(ParsingData.Text[cPos], True, SymbolTable) do
          begin
            if cPos + 1 > L then
                exit(cPos);
            inc(cPos);
          end;
        // read hexadecimal or decimal number
        while Char_is(ParsingData.Text[cPos], [{$IFDEF FPC}ucHex{$ELSE FPC}cHex{$ENDIF FPC}], '$') do
          begin
            if cPos + 1 > L then
                exit(cPos);
            inc(cPos);
          end;
        tmpPos := cPos;
        // skip whitespace after number
        while isWordSplitChar(ParsingData.Text[cPos], True, SymbolTable) do
          begin
            if cPos + 1 > L then
                exit(cPos);
            inc(cPos);
          end;
      until not ComparePosStr(cPos, '#'); // continue if next is '#'
      cPos := CompareTextDeclGetEndPos(tmpPos); // recursively parse next part
    end;

  Result := cPos;
end;

{ ============================================================================
  Cache rebuilding
  ============================================================================ }

procedure TTextParsing.RebuildParsingCache;
{ * Rebuilds the entire parsing cache from the current ParsingData.Text.
  * This is the most comprehensive cache rebuild. It clears and then
  * reconstructs:
  *   - CommentDecls (list of comment ranges)
  *   - TextDecls (list of string literal ranges)
  *   - TokenDataList (all tokens)
  *   - CharToken (character‑to‑token map)
  * It also updates TokenStatistics.
  * This method is called automatically in the constructor and after any
  * text‑modifying operation that requires a refresh.
  *
  * @Note This method is relatively expensive; avoid calling it repeatedly.
}
var
  i, j: Integer;
  L: Integer;
  bPos: Integer;
  ePos: Integer;
  textPosPtr: PTextPos;
  TokenDataPtr: PTokenData;
begin
  RebuildCacheBusy := True;

  // --- Free existing cache structures ---
  if ParsingData.Cache.CommentDecls <> nil then
    begin
      for i := 0 to ParsingData.Cache.CommentDecls.Count - 1 do
        begin
          ParsingData.Cache.CommentDecls[i]^.Text := '';
          Dispose(ParsingData.Cache.CommentDecls[i]);
        end;
      DisposeObject(ParsingData.Cache.CommentDecls);
      ParsingData.Cache.CommentDecls := nil;
    end;

  if ParsingData.Cache.TextDecls <> nil then
    begin
      for i := 0 to ParsingData.Cache.TextDecls.Count - 1 do
        begin
          ParsingData.Cache.TextDecls[i]^.Text := '';
          Dispose(ParsingData.Cache.TextDecls[i]);
        end;
      DisposeObject(ParsingData.Cache.TextDecls);
      ParsingData.Cache.TextDecls := nil;
    end;

  if ParsingData.Cache.TokenDataList <> nil then
    begin
      for i := 0 to ParsingData.Cache.TokenDataList.Count - 1 do
        begin
          ParsingData.Cache.TokenDataList[i]^.Text := '';
          Dispose(ParsingData.Cache.TokenDataList[i]);
        end;
      DisposeObject(ParsingData.Cache.TokenDataList);
      ParsingData.Cache.TokenDataList := nil;
    end;

  TokenStatistics := NullTokenStatistics;
  ParsingData.Cache.CommentDecls := TTextPosList_Decl.Create;
  ParsingData.Cache.TextDecls := TTextPosList_Decl.Create;
  ParsingData.Cache.TokenDataList := TTokenDataList_Decl.Create;
  SetLength(ParsingData.Cache.CharToken, 0);

  // --- Step 1: Find all comments and string literals ---
  L := ParsingData.L;
  bPos := 1;
  ePos := bPos;
  while (bPos <= L) do
    begin
      ePos := CompareCommentGetEndPos(bPos);
      if ePos > bPos then
        begin
          new(textPosPtr);
          textPosPtr^.bPos := bPos;
          textPosPtr^.ePos := ePos;
          textPosPtr^.Text := GetStr(textPosPtr^);
          ParsingData.Cache.CommentDecls.Add(textPosPtr);
          bPos := ePos;
        end
      else
        begin
          ePos := CompareTextDeclGetEndPos(bPos);
          if ePos > bPos then
            begin
              new(textPosPtr);
              textPosPtr^.bPos := bPos;
              textPosPtr^.ePos := ePos;
              textPosPtr^.Text := GetStr(textPosPtr^);
              ParsingData.Cache.TextDecls.Add(textPosPtr);
              bPos := ePos;
            end
          else
            begin
              inc(bPos);
              ePos := bPos;
            end;
        end;
    end;

  // --- Step 2: Tokenise the text ---
  bPos := 1;
  ePos := bPos;
  TokenDataPtr := nil;
  while bPos <= L do
    begin
      if isSpecialSymbol(bPos, ePos) then
        begin
          new(TokenDataPtr);
          TokenDataPtr^.Init;
          TokenDataPtr^.bPos := bPos;
          TokenDataPtr^.ePos := ePos;
          TokenDataPtr^.Text := GetStr(bPos, ePos);
          TokenDataPtr^.tokenType := ttSpecialSymbol;
          TokenDataPtr^.Index := ParsingData.Cache.TokenDataList.Count;
          ParsingData.Cache.TokenDataList.Add(TokenDataPtr);
          inc(TokenStatistics[TokenDataPtr^.tokenType]);
          bPos := ePos
        end
      else if isTextDecl(bPos) then
        begin
          ePos := GetTextDeclEndPos(bPos);
          new(TokenDataPtr);
          TokenDataPtr^.Init;
          TokenDataPtr^.bPos := bPos;
          TokenDataPtr^.ePos := ePos;
          TokenDataPtr^.Text := GetStr(bPos, ePos);
          TokenDataPtr^.tokenType := ttTextDecl;
          TokenDataPtr^.Index := ParsingData.Cache.TokenDataList.Count;
          ParsingData.Cache.TokenDataList.Add(TokenDataPtr);
          inc(TokenStatistics[TokenDataPtr^.tokenType]);
          bPos := ePos
        end
      else if isComment(bPos) then
        begin
          ePos := GetCommentEndPos(bPos);
          new(TokenDataPtr);
          TokenDataPtr^.Init;
          TokenDataPtr^.bPos := bPos;
          TokenDataPtr^.ePos := ePos;
          TokenDataPtr^.Text := GetStr(bPos, ePos);
          TokenDataPtr^.tokenType := ttComment;
          TokenDataPtr^.Index := ParsingData.Cache.TokenDataList.Count;
          ParsingData.Cache.TokenDataList.Add(TokenDataPtr);
          inc(TokenStatistics[TokenDataPtr^.tokenType]);
          bPos := ePos;
        end
      else if isNumber(bPos) then
        begin
          ePos := GetNumberEndPos(bPos);
          new(TokenDataPtr);
          TokenDataPtr^.Init;
          TokenDataPtr^.bPos := bPos;
          TokenDataPtr^.ePos := ePos;
          TokenDataPtr^.Text := GetStr(bPos, ePos);
          TokenDataPtr^.tokenType := ttNumber;
          TokenDataPtr^.Index := ParsingData.Cache.TokenDataList.Count;
          ParsingData.Cache.TokenDataList.Add(TokenDataPtr);
          inc(TokenStatistics[TokenDataPtr^.tokenType]);
          bPos := ePos;
        end
      else if isSymbol(bPos) then
        begin
          ePos := GetSymbolEndPos(bPos);
          new(TokenDataPtr);
          TokenDataPtr^.Init;
          TokenDataPtr^.bPos := bPos;
          TokenDataPtr^.ePos := ePos;
          TokenDataPtr^.Text := GetStr(bPos, ePos);
          TokenDataPtr^.tokenType := ttSymbol;
          TokenDataPtr^.Index := ParsingData.Cache.TokenDataList.Count;
          ParsingData.Cache.TokenDataList.Add(TokenDataPtr);
          inc(TokenStatistics[TokenDataPtr^.tokenType]);
          bPos := ePos;
        end
      else if isAscii(bPos) then
        begin
          ePos := GetAsciiEndPos(bPos);
          new(TokenDataPtr);
          TokenDataPtr^.Init;
          TokenDataPtr^.bPos := bPos;
          TokenDataPtr^.ePos := ePos;
          TokenDataPtr^.Text := GetStr(bPos, ePos);
          TokenDataPtr^.tokenType := ttAscii;
          TokenDataPtr^.Index := ParsingData.Cache.TokenDataList.Count;
          ParsingData.Cache.TokenDataList.Add(TokenDataPtr);
          inc(TokenStatistics[TokenDataPtr^.tokenType]);
          bPos := ePos;
        end
      else
        begin
          // Unrecognised character – treat as an unknown token
          ePos := bPos + 1;
          if (TokenDataPtr = nil) or (TokenDataPtr^.tokenType <> ttUnknow) then
            begin
              new(TokenDataPtr);
              TokenDataPtr^.Init;
              TokenDataPtr^.bPos := bPos;
              TokenDataPtr^.ePos := ePos;
              TokenDataPtr^.Text := GetStr(bPos, ePos);
              TokenDataPtr^.tokenType := ttUnknow;
              TokenDataPtr^.Index := ParsingData.Cache.TokenDataList.Count;
              ParsingData.Cache.TokenDataList.Add(TokenDataPtr);
              inc(TokenStatistics[TokenDataPtr^.tokenType]);
            end
          else
            begin
              // Extend the current unknown token
              TokenDataPtr^.ePos := ePos;
              TokenDataPtr^.Text.Append(GetChar(bPos));
            end;
          bPos := ePos;
        end;
    end;

  // --- Step 3: Build the character‑to‑token map for O(1) lookups ---
  SetLength(ParsingData.Cache.CharToken, L);
  for i := 0 to ParsingData.Cache.TokenDataList.Count - 1 do
    begin
      TokenDataPtr := ParsingData.Cache.TokenDataList[i];
      for j := TokenDataPtr^.bPos to TokenDataPtr^.ePos - 1 do
          ParsingData.Cache.CharToken[j - 1] := TokenDataPtr;
    end;

  RebuildCacheBusy := False;
end;

procedure TTextParsing.RebuildText;
{ * Rebuilds the source text from the cached comment and string literal ranges.
  * This is used after modifying those ranges (e.g., changing the content of
  * a comment or string) to bring the internal Text in sync.
  * It adjusts the positions of subsequent ranges and finally calls
  * RebuildParsingCache to refresh the token cache.
}
  procedure Recompute(bPos, d: Integer);
  var
    i: Integer;
    p: PTextPos;
  begin
    // Shift all text positions that come after bPos by the delta d
    for i := 0 to ParsingData.Cache.TextDecls.Count - 1 do
      begin
        p := PTextPos(ParsingData.Cache.TextDecls[i]);
        if bPos < p^.bPos then
          begin
            p^.bPos := p^.bPos - d;
            p^.ePos := p^.ePos - d;
          end;
      end;
    for i := 0 to ParsingData.Cache.CommentDecls.Count - 1 do
      begin
        p := PTextPos(ParsingData.Cache.CommentDecls[i]);
        if bPos < p^.bPos then
          begin
            p^.bPos := p^.bPos - d;
            p^.ePos := p^.ePos - d;
          end;
      end;
  end;

var
  p: PTextPos;
  i: Integer;
begin
  // First, adjust positions for any length changes in text declarations
  for i := 0 to ParsingData.Cache.TextDecls.Count - 1 do
    begin
      p := PTextPos(ParsingData.Cache.TextDecls[i]);
      if p^.ePos - p^.bPos <> (p^.Text.L) then
          Recompute(p^.bPos, (p^.ePos - p^.bPos) - p^.Text.L);

      ParsingData.Text := GetStr(1, p^.bPos) + p^.Text + GetStr(p^.ePos, ParsingData.Text.L + 1);
      ParsingData.L := ParsingData.Text.L;
      p^.ePos := p^.bPos + p^.Text.L;
    end;

  // Then, adjust for comment declarations
  for i := 0 to ParsingData.Cache.CommentDecls.Count - 1 do
    begin
      p := PTextPos(ParsingData.Cache.CommentDecls[i]);
      if p^.ePos - p^.bPos <> (p^.Text.L) then
          Recompute(p^.bPos, (p^.ePos - p^.bPos) - p^.Text.L);

      ParsingData.Text := GetStr(1, p^.bPos) + p^.Text + GetStr(p^.ePos, ParsingData.Text.L + 1);
      ParsingData.L := ParsingData.Text.L;
      p^.ePos := p^.bPos + p^.Text.L;
    end;

  RebuildParsingCache;
end;

procedure TTextParsing.RebuildToken;
{ * Rebuilds the source text from the token list (TokenDataList).
  * This is the inverse of tokenisation: it concatenates all token texts
  * in order to produce the original text. After rebuilding, it refreshes
  * the cache.
}
var
  p: PTokenData;
  i, j: Integer;
begin
  ParsingData.Text := '';

  // Calculate total length
  j := 0;
  for i := 0 to ParsingData.Cache.TokenDataList.Count - 1 do
    with ParsingData.Cache.TokenDataList[i]^ do
        inc(j, Text.L);

  // Allocate and fill
  ParsingData.Text.L := j;
  j := 0;
  for i := 0 to ParsingData.Cache.TokenDataList.Count - 1 do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[i]);
      if p^.Text.L > 0 then
        begin
          CopyPtr(@p^.Text.buff[0], @ParsingData.Text.buff[j], p^.Text.L * SizeOf(TP_Char));
          inc(j, p^.Text.L);
        end;
    end;
  ParsingData.L := ParsingData.Text.L;
  RebuildParsingCache;
end;

function TTextParsing.FastRebuildTokenTo(): TP_String;
{ * Similar to RebuildToken, but returns a new TP_String without modifying
  * the internal state. Useful when you need the token‑concatenated text
  * without affecting the parser's cache.
}
var
  p: PTokenData;
  i, j: Integer;
begin
  Result := '';

  j := 0;
  for i := 0 to ParsingData.Cache.TokenDataList.Count - 1 do
    with ParsingData.Cache.TokenDataList[i]^ do
        inc(j, Text.L);

  Result.L := j;
  j := 0;
  for i := 0 to ParsingData.Cache.TokenDataList.Count - 1 do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[i]);
      if p^.Text.L > 0 then
        begin
          CopyPtr(@p^.Text.buff[0], @Result.buff[j], p^.Text.L * SizeOf(TP_Char));
          inc(j, p^.Text.L);
        end;
    end;
end;

{ ============================================================================
  Context (token) boundaries
  ============================================================================ }

function TTextParsing.GetContextBeginPos(cOffset: Integer): Integer;
{ * Returns the start position of the token that contains the given offset.
  * If no token is found, returns the offset itself.
}
var
  p: PTokenData;
begin
  Result := cOffset;
  p := TokenPos[cOffset];
  if p = nil then
      exit;
  Result := p^.bPos;
end;

function TTextParsing.GetContextEndPos(cOffset: Integer): Integer;
{ * Returns the exclusive end position of the token containing cOffset.
  * If none, returns cOffset.
}
var
  p: PTokenData;
begin
  Result := cOffset;
  p := TokenPos[cOffset];
  if p = nil then
      exit;
  Result := p^.ePos;
end;

{ ============================================================================
  Special symbol detection
  ============================================================================ }

function TTextParsing.isSpecialSymbol(cOffset: Integer): Boolean;
var
  ePos: Integer;
begin
  Result := isSpecialSymbol(cOffset, ePos);
end;

function TTextParsing.isSpecialSymbol(cOffset: Integer; var speicalSymbolEndPos: Integer): Boolean;
{ * Checks whether the position cOffset starts a multi‑character special symbol
  * (listed in SpecialSymbol). If so, returns True and sets speicalSymbolEndPos
  * to the exclusive end of that symbol.
}
var
  i, EP: Integer;
  p: PTokenData;
begin
  // Use cache if available
  if not RebuildCacheBusy then
    begin
      p := TokenPos[cOffset];
      if p <> nil then
        begin
          Result := p^.tokenType = TTokenType.ttSpecialSymbol;
          if Result then
              speicalSymbolEndPos := p^.ePos;
          exit;
        end;
    end;

  Result := False;
  speicalSymbolEndPos := cOffset;

  if SpecialSymbol.Count = 0 then
      exit;

  if isComment(cOffset) then
      exit;

  if isTextDecl(cOffset) then
      exit;

  speicalSymbolEndPos := cOffset;
  for i := 0 to SpecialSymbol.Count - 1 do
    if ComparePosStr(cOffset, SpecialSymbol.Items[i]) then
      begin
        EP := cOffset + SpecialSymbol[i].L;
        if EP > speicalSymbolEndPos then
            speicalSymbolEndPos := EP;
        Result := True;
      end;
end;

function TTextParsing.GetSpecialSymbolEndPos(cOffset: Integer): Integer;
begin
  if not isSpecialSymbol(cOffset, Result) then
      Result := cOffset;
end;

{ ============================================================================
  Number detection
  ============================================================================ }

function TTextParsing.isNumber(cOffset: Integer): Boolean;
var
  tmp: Integer;
  IsHex: Boolean;
begin
  Result := isNumber(cOffset, tmp, IsHex);
end;

function TTextParsing.isNumber(cOffset: Integer; var NumberBegin: Integer; var IsHex: Boolean): Boolean;
{ * Determines if the position cOffset begins a numeric literal.
  * It can detect decimal integers, floating‑point numbers, and hexadecimal
  * numbers (with '$' or '0x' prefix). On success, NumberBegin is set to the
  * start of the actual numeric digits (skipping leading sign), and IsHex
  * indicates whether it is hexadecimal.
  * @Return True if a number is found.
}
var
  c: TP_Char;
  L: Integer;
  cPos, bkPos: Integer;
  nc: Integer;
  dotNum: Integer;
  eNum: Integer;
  eSymNum: Integer;
  pSym: Integer;
  p: PTokenData;
begin
  if not RebuildCacheBusy then
    begin
      p := TokenPos[cOffset];
      if p <> nil then
        begin
          Result := p^.tokenType = TTokenType.ttNumber;
          if Result then
            begin
              NumberBegin := p^.bPos;
              IsHex := p^.Text.ComparePos(1, '$') or p^.Text.ComparePos(1, '0x');
            end;
          exit;
        end;
    end;

  Result := False;

  cPos := cOffset;
  L := ParsingData.L;
  if cPos < 1 then
      cPos := 1;
  if cPos > L then
      cPos := L;

  if cPos = L then
      exit;

  IsHex := False;
  try
    if (Char_is(ParsingData.Text[cPos], '$')) then
      begin
        // Pascal hex: $ABCD
        IsHex := True;
        inc(cPos);
        if cPos > L then
            exit;
      end
    else if ComparePosStr(cPos, '0x') then
      begin
        // C hex: 0xABCD
        IsHex := True;
        inc(cPos, 2);
        if cPos > L then
            exit;
      end;
  except
  end;

  if IsHex then
    begin
      bkPos := cPos;
      nc := 0;
      while True do
        begin
          cPos := GetTextDeclEndPos(GetCommentEndPos(cPos));

          if cPos > L then
              Break;
          c := ParsingData.Text[cPos];

          if isWordSplitChar(c, True, SymbolTable) then
            begin
              if nc > 0 then
                  Break;
            end
          else if Char_is(c, {$IFDEF FPC}ucHex{$ELSE FPC}cHex{$ENDIF FPC}) then
              inc(nc)
          else
            begin
              Result := False;
              exit;
            end;

          inc(cPos);
        end;

      Result := (nc > 0);
      NumberBegin := bkPos;
      exit;
    end;

  c := ParsingData.Text[cPos];
  if Char_is(c, {$IFDEF FPC}uc0to9{$ELSE FPC}c0to9{$ENDIF FPC}) then
    begin
      bkPos := cPos;
      nc := 0;
      dotNum := 0;
      eNum := 0;
      eSymNum := 0;
      while True do
        begin
          cPos := GetTextDeclEndPos(GetCommentEndPos(cPos));

          if cPos > L then
              Break;
          c := ParsingData.Text[cPos];

          if Char_is(c, '.') then
            begin
              inc(dotNum);
              if dotNum > 1 then
                  Break;
            end
          else if Char_is(c, {$IFDEF FPC}uc0to9{$ELSE FPC}c0to9{$ENDIF FPC}) then
              inc(nc)
          else if (nc > 0) and (eNum = 0) and Char_is(c, 'eE') then
            begin
              inc(eNum);
            end
          else if (nc > 0) and (eNum = 1) and Char_is(c, '-+') then
            begin
              inc(eSymNum);
            end
          else if isWordSplitChar(c, True, SymbolTable) then
            begin
              Break;
            end
          else if Char_is(c, [{$IFDEF FPC}ucAtoZ, ucDoubleChar{$ELSE FPC}cAtoZ, cDoubleChar{$ENDIF FPC}]) then
            begin
              Result := False;
              exit;
            end;

          inc(cPos);
        end;

      Result := (nc > 0) and (dotNum <= 1);
      NumberBegin := bkPos;
      exit;
    end
  else if Char_is(c, '+-.') then
    begin
      bkPos := cPos;
      nc := 0;
      dotNum := 0;
      eNum := 0;
      eSymNum := 0;
      pSym := 0;
      while True do
        begin
          cPos := GetTextDeclEndPos(GetCommentEndPos(cPos));

          if cPos > L then
              Break;
          c := ParsingData.Text[cPos];

          if (nc = 0) and (eSymNum = 0) and (eNum = 0) and Char_is(c, '-+') then
            begin
              inc(pSym);
            end
          else if Char_is(c, '.') then
            begin
              inc(dotNum);
              if dotNum > 1 then
                  Break;
            end
          else if Char_is(c, {$IFDEF FPC}uc0to9{$ELSE FPC}c0to9{$ENDIF FPC}) then
              inc(nc)
          else if (nc > 0) and (eNum = 0) and Char_is(c, 'eE') then
            begin
              inc(eNum);
            end
          else if (nc > 0) and (eNum = 1) and Char_is(c, '-+') then
            begin
              inc(eSymNum);
            end
          else if isWordSplitChar(c, True, SymbolTable) then
            begin
              Break
            end
          else if Char_is(c, [{$IFDEF FPC}ucAtoZ, ucDoubleChar{$ELSE FPC}cAtoZ, cDoubleChar{$ENDIF FPC}]) then
            begin
              Result := False;
              exit;
            end;

          inc(cPos);
        end;

      Result := (nc > 0) and (dotNum <= 1);
      NumberBegin := bkPos;
      exit;
    end;
end;

function TTextParsing.GetNumberEndPos(cOffset: Integer): Integer;
{ * Returns the exclusive end position of the number that starts at cOffset.
  * If no number is found, returns cOffset.
}
var
  IsHex: Boolean;
  L: Integer;
  cPos: Integer;
  c: TP_Char;
  nc: Integer;
  dotNum: Integer;
  eNum: Integer;
  p: PTokenData;
begin
  if not RebuildCacheBusy then
    begin
      p := TokenPos[cOffset];
      if p <> nil then
        begin
          if p^.tokenType = TTokenType.ttNumber then
              Result := p^.ePos
          else
              Result := cOffset;
          exit;
        end;
    end;

  L := ParsingData.L;
  cPos := cOffset;
  if cPos < 1 then
      cPos := 1;
  if cPos > L then
      cPos := L;

  if isNumber(cPos, Result, IsHex) then
    begin
      nc := 0;
      dotNum := 0;
      eNum := 0;
      while True do
        begin
          if isComment(Result) or isTextDecl(Result) then
              Break;
          c := ParsingData.Text[Result];

          if (not Char_is(c, [{$IFDEF FPC}uc0to9{$ELSE FPC}c0to9{$ENDIF FPC}])) then
            begin
              if Char_is(c, '+-') then
                begin
                  if nc > 0 then
                    begin
                      if eNum = 1 then
                          inc(eNum)
                      else
                          exit;
                    end;
                end
              else if (not IsHex) and Char_is(c, '.') then
                begin
                  if (dotNum > 1) then
                      exit;
                  inc(dotNum);
                end
              else if (not IsHex) and Char_is(c, 'eE') then
                begin
                  if (eNum > 1) then
                      exit;
                  inc(eNum);
                end
              else if (IsHex and (Char_is(c, [{$IFDEF FPC}ucLoAtoF, ucHiAtoF{$ELSE FPC}cLoAtoF, cHiAtoF{$ENDIF FPC}]))) then
                  inc(nc)
              else
                  exit;
            end
          else
              inc(nc);

          inc(Result);
          if Result > L then
              exit;
        end;
    end
  else
      Result := cPos;
end;

{ ============================================================================
  String literal (text declaration) detection
  ============================================================================ }

function TTextParsing.isTextDecl(cOffset: Integer): Boolean;
var
  bPos, ePos: Integer;
begin
  Result := GetTextDeclPos(cOffset, bPos, ePos);
end;

function TTextParsing.GetTextDeclEndPos(cOffset: Integer): Integer;
var
  bPos, ePos: Integer;
begin
  if GetTextDeclPos(cOffset, bPos, ePos) then
      Result := ePos
  else
      Result := cOffset;
end;

function TTextParsing.GetTextDeclBeginPos(cOffset: Integer): Integer;
var
  bPos, ePos: Integer;
begin
  if GetTextDeclPos(cOffset, bPos, ePos) then
      Result := bPos
  else
      Result := cOffset;
end;

function TTextParsing.GetTextBody(Text_: TP_String): TP_String;
{ * Extracts the actual content of a string literal by removing quotes and
  * interpreting escape sequences based on the current TextStyle.
  * For Pascal, it uses Translate_Pascal_Decl_To_Text; for C, it uses
  * Translate_C_Decl_To_Text; for tsText, it returns the text unchanged.
}
begin
  if TextStyle = tsPascal then
      Result := Translate_Pascal_Decl_To_Text(Text_)
  else if TextStyle = tsC then
      Result := Translate_C_Decl_To_Text(Text_)
  else
      Result := Text_;
end;

function TTextParsing.GetTextDeclPos(cOffset: Integer; var charBeginPos, charEndPos: Integer): Boolean;
{ * Locates the string literal that contains the given offset.
  * Uses binary search on the TextDecls list.
  * @Return True if a literal is found, and fills charBeginPos/charEndPos.
}
  function CompLst(idx: Integer): Integer;
  begin
    with PTextPos(ParsingData.Cache.TextDecls[idx])^ do
      begin
        if (cOffset >= bPos) and (cOffset < ePos) then
            Result := 0
        else if (cOffset >= ePos) then
            Result := -1
        else if (cOffset < bPos) then
            Result := 1
        else
            Result := -2;
      end;
  end;

var
  cPos, L, r, M: Integer;
  p: PTokenData;
begin
  if not RebuildCacheBusy then
    begin
      p := TokenPos[cOffset];
      if p <> nil then
        begin
          Result := p^.tokenType = TTokenType.ttTextDecl;
          if Result then
            begin
              charBeginPos := p^.bPos;
              charEndPos := p^.ePos;
            end;
          exit;
        end;
    end;

  cPos := cOffset;
  if cPos < 1 then
      cPos := 1;
  if cPos > ParsingData.L then
      cPos := ParsingData.L;

  if ParsingData.Cache.TextDecls = nil then
      RebuildParsingCache;

  Result := False;

  L := 0;
  r := ParsingData.Cache.TextDecls.Count - 1;
  while L <= r do
    begin
      M := (L + r) div 2;
      case CompLst(M) of
        0:
          begin
            with PTextPos(ParsingData.Cache.TextDecls[M])^ do
              begin
                charBeginPos := bPos;
                charEndPos := ePos;
              end;
            Result := True;
            exit;
          end;
        -1: L := M + 1;
        1: r := M - 1;
        else RaiseInfo('struct error');
      end;
    end;
end;

{ ============================================================================
  Single‑character symbol detection
  ============================================================================ }

function TTextParsing.isSymbol(cOffset: Integer): Boolean;
var
  p: PTokenData;
begin
  if not RebuildCacheBusy then
    begin
      p := TokenPos[cOffset];
      if p <> nil then
        begin
          Result := p^.tokenType = TTokenType.ttSymbol;
          exit;
        end;
    end;
  Result := Char_is(ParsingData.Text[cOffset], SymbolTable)
end;

function TTextParsing.GetSymbolEndPos(cOffset: Integer): Integer;
begin
  if isSymbol(cOffset) then
      Result := cOffset + 1
  else
      Result := cOffset;
end;

{ ============================================================================
  ASCII / identifier detection
  ============================================================================ }

function TTextParsing.isAscii(cOffset: Integer): Boolean;
{ * Checks if the position is part of an identifier (alphanumeric sequence)
  * that is not a comment, string, number, or symbol.
  * It is essentially a word that consists only of alphanumeric characters
  * and underscores, excluding the above categories.
}
var
  p: PTokenData;
begin
  if not RebuildCacheBusy then
    begin
      p := TokenPos[cOffset];
      if p <> nil then
        begin
          Result := p^.tokenType = TTokenType.ttAscii;
          exit;
        end;
    end;
  Result := False;

  if isComment(cOffset) then
      exit;

  if isTextDecl(cOffset) then
      exit;

  if isSpecialSymbol(cOffset) then
      exit;

  Result := (not isSymbol(cOffset)) and (not isWordSplitChar(ParsingData.Text[cOffset], True, SymbolTable)) and (not isNumber(cOffset));
end;

function TTextParsing.GetAsciiBeginPos(cOffset: Integer): Integer;
{ * Returns the start of the identifier containing cOffset.
}
var
  p: PTokenData;
begin
  if not RebuildCacheBusy then
    begin
      p := TokenPos[cOffset];
      if p <> nil then
        begin
          if p^.tokenType = TTokenType.ttAscii then
              Result := p^.bPos
          else
              Result := cOffset;
          exit;
        end;
    end;
  Result := GetWordBeginPos(cOffset, True, SymbolTable);
end;

function TTextParsing.GetAsciiEndPos(cOffset: Integer): Integer;
var
  p: PTokenData;
begin
  if not RebuildCacheBusy then
    begin
      p := TokenPos[cOffset];
      if p <> nil then
        begin
          if p^.tokenType = TTokenType.ttAscii then
              Result := p^.ePos
          else
              Result := cOffset;
          exit;
        end;
    end;
  Result := GetWordEndPos(cOffset, True, SymbolTable, True, SymbolTable);
end;

{ ============================================================================
  Comment detection
  ============================================================================ }

function TTextParsing.isComment(cOffset: Integer): Boolean;
var
  bPos, ePos: Integer;
  p: PTokenData;
begin
  if not RebuildCacheBusy then
    begin
      p := TokenPos[cOffset];
      if p <> nil then
        begin
          Result := p^.tokenType = TTokenType.ttComment;
          exit;
        end;
    end;
  Result := GetCommentPos(cOffset, bPos, ePos);
end;

function TTextParsing.GetCommentEndPos(cOffset: Integer): Integer;
var
  bPos, ePos: Integer;
  p: PTokenData;
begin
  if not RebuildCacheBusy then
    begin
      p := TokenPos[cOffset];
      if p <> nil then
        begin
          if p^.tokenType = TTokenType.ttComment then
              Result := p^.ePos
          else
              Result := cOffset;
          exit;
        end;
    end;

  if GetCommentPos(cOffset, bPos, ePos) then
      Result := ePos
  else
      Result := cOffset;
end;

function TTextParsing.GetCommentBeginPos(cOffset: Integer): Integer;
var
  bPos, ePos: Integer;
  p: PTokenData;
begin
  if not RebuildCacheBusy then
    begin
      p := TokenPos[cOffset];
      if p <> nil then
        begin
          if p^.tokenType = TTokenType.ttComment then
              Result := p^.bPos
          else
              Result := cOffset;
          exit;
        end;
    end;

  if GetCommentPos(cOffset, bPos, ePos) then
      Result := bPos
  else
      Result := cOffset;
end;

function TTextParsing.GetCommentPos(cOffset: Integer; var charBeginPos, charEndPos: Integer): Boolean;
{ * Locates the comment that contains the given offset using binary search
  * on CommentDecls.
}
  function CompLst(idx: Integer): Integer;
  begin
    with PTextPos(ParsingData.Cache.CommentDecls[idx])^ do
      begin
        if (cOffset >= bPos) and (cOffset < ePos) then
            Result := 0
        else if (cOffset >= ePos) then
            Result := -1
        else if (cOffset < bPos) then
            Result := 1
        else
            Result := -2;
      end;
  end;

var
  cPos, L, r, M: Integer;
  p: PTokenData;
begin
  if not RebuildCacheBusy then
    begin
      p := TokenPos[cOffset];
      if p <> nil then
        begin
          Result := p^.tokenType = TTokenType.ttComment;
          if Result then
            begin
              charBeginPos := p^.bPos;
              charEndPos := p^.ePos;
            end;
          exit;
        end;
    end;

  cPos := cOffset;
  if cPos < 1 then
      cPos := 1;
  if cPos > ParsingData.L then
      cPos := ParsingData.L;

  if ParsingData.Cache.CommentDecls = nil then
      RebuildParsingCache;

  Result := False;

  L := 0;
  r := ParsingData.Cache.CommentDecls.Count - 1;
  while L <= r do
    begin
      M := (L + r) div 2;
      case CompLst(M) of
        0:
          begin
            with PTextPos(ParsingData.Cache.CommentDecls[M])^ do
              begin
                charBeginPos := bPos;
                charEndPos := ePos;
              end;
            Result := True;
            exit;
          end;
        -1: L := M + 1;
        1: r := M - 1;
        else RaiseInfo('struct error');
      end;
    end;
end;

function TTextParsing.GetDeletedCommentText: TP_String;
{ * Returns a copy of the source text with all comments removed.
  * It works by scanning the text and skipping comment ranges.
}
var
  oriPos, cPos, nPos: Integer;
begin
  Result := '';

  cPos := 1;
  oriPos := cPos;

  while cPos < ParsingData.L do
    begin
      nPos := CompareCommentGetEndPos(cPos);
      if nPos > cPos then
        begin
          Result := Result + GetStr(oriPos, cPos);
          cPos := nPos;
          oriPos := cPos;
        end
      else
        begin
          inc(cPos);
        end;
    end;
  if oriPos <= ParsingData.L then
      Result := Result + GetStr(oriPos, ParsingData.L + 1);

  Result := Result.TrimChar(#32);
end;

{ ============================================================================
  Composite checks
  ============================================================================ }

function TTextParsing.isTextOrComment(cOffset: Integer): Boolean;
begin
  Result := isTextDecl(cOffset) or isComment(cOffset);
end;

function TTextParsing.isCommentOrText(cOffset: Integer): Boolean;
begin
  Result := isComment(cOffset) or isTextDecl(cOffset);
end;

{ ============================================================================
  Word splitting helpers
  ============================================================================ }

class function TTextParsing.isWordSplitChar(c: TP_Char): Boolean;
begin
  Result := Char_is(c, [{$IFDEF FPC}uc0to32{$ELSE FPC}c0to32{$ENDIF FPC}]);
end;

class function TTextParsing.isWordSplitChar(c: TP_Char; Split_Token_Char: TP_String): Boolean;
begin
  Result := isWordSplitChar(c, True, Split_Token_Char);
end;

class function TTextParsing.isWordSplitChar(c: TP_Char; Include_C_0_to_32: Boolean; Split_Token_Char: TP_String): Boolean;
begin
  if Include_C_0_to_32 then
      Result := Char_is(c, [{$IFDEF FPC}uc0to32{$ELSE FPC}c0to32{$ENDIF FPC}], Split_Token_Char)
  else
      Result := Char_is(c, Split_Token_Char);
end;

function TTextParsing.GetWordBeginPos(cOffset: Integer; Split_Token_Char: TP_String): Integer;
begin
  Result := GetWordBeginPos(cOffset, True, Split_Token_Char);
end;

function TTextParsing.GetWordBeginPos(cOffset: Integer): Integer;
begin
  Result := GetWordBeginPos(cOffset, True, '');
end;

function TTextParsing.GetWordBeginPos(cOffset: Integer; Include_C_0_to_32: Boolean; Split_Token_Char: TP_String): Integer;
{ * Finds the start of the word (contiguous non‑separator characters) that
  * contains cOffset. Skips comments and string literals.
  * @Param Include_C_0_to_32 : if True, characters 0‑32 are considered separators.
  * @Param Split_Token_Char  : additional separator characters.
}
var
  L: Integer;
  cPos: Integer;
  tbPos: Integer;
begin
  L := ParsingData.L;
  cPos := cOffset;
  if cPos < 1 then
      exit(1);
  if cPos > L then
      exit(L);

  repeat
    cPos := GetCommentEndPos(cPos);

    tbPos := GetTextDeclBeginPos(cPos);
    if tbPos <> cPos then
        exit(tbPos);

    while (isWordSplitChar(ParsingData.Text[cPos], Include_C_0_to_32, Split_Token_Char)) do
      begin
        if cPos >= L then
            Break;
        inc(cPos);
      end;
  until not isComment(cPos);

  Result := cPos;
  while (not isWordSplitChar(ParsingData.Text[Result], Include_C_0_to_32, Split_Token_Char)) do
    begin
      if Result - 1 <= 0 then
          Break;
      dec(Result);
    end;

  if isWordSplitChar(ParsingData.Text[Result], Split_Token_Char) then
      inc(Result);
end;

function TTextParsing.GetWordEndPos(cOffset: Integer; Split_Token_Char: TP_String): Integer;
begin
  Result := GetWordEndPos(cOffset, True, Split_Token_Char, True, Split_Token_Char);
end;

function TTextParsing.GetWordEndPos(cOffset: Integer): Integer;
begin
  Result := GetWordEndPos(cOffset, True, '', True, '');
end;

function TTextParsing.GetWordEndPos(cOffset: Integer; BeginSplitCharSet, EndSplitCharSet: TP_String): Integer;
begin
  Result := GetWordEndPos(cOffset, True, BeginSplitCharSet, True, EndSplitCharSet);
end;

function TTextParsing.GetWordEndPos(cOffset: Integer; Include_C_0_to_32: Boolean; BeginSplitCharSet: TP_String; EndDefaultChar: Boolean; EndSplitCharSet: TP_String): Integer;
{ * Finds the end of the word that contains cOffset.
  * @Param BeginSplitCharSet : characters that delimit the start of the word.
  * @Param EndDefaultChar    : if True, uses Include_C_0_to_32 to determine separators.
  * @Param EndSplitCharSet   : additional characters that delimit the end.
}
var
  L: Integer;
begin
  L := ParsingData.L;
  if cOffset < 1 then
      exit(1);
  if cOffset > L then
      exit(L);

  Result := GetWordBeginPos(cOffset, Include_C_0_to_32, BeginSplitCharSet);

  while (not isWordSplitChar(ParsingData.Text[Result], EndDefaultChar, EndSplitCharSet)) do
    begin
      inc(Result);
      if Result > L then
          Break;
    end;
end;

{ ============================================================================
  Sniffing
  ============================================================================ }

function TTextParsing.SniffingNextChar(cOffset: Integer; declChar: TP_String): Boolean;
var
  tmp: Integer;
begin
  Result := SniffingNextChar(cOffset, declChar, tmp);
end;

function TTextParsing.SniffingNextChar(cOffset: Integer; declChar: TP_String; out OutPos: Integer): Boolean;
{ * Scans forward from cOffset, skipping whitespace, comments, and string
  * literals, until it finds a character that belongs to the set declChar.
  * Returns True and sets OutPos to the position of that character.
}
var
  L: Integer;
  cPos: Integer;
begin
  L := ParsingData.L;
  cPos := cOffset;
  if cPos < 1 then
      cPos := 1;
  if cPos > L then
      exit(False);

  while isWordSplitChar(ParsingData.Text[cPos], True, '') or (isTextOrComment(cPos)) do
    begin
      inc(cPos);
      if cPos > L then
          exit(False);
    end;

  if (cPos < L) then
      Result := Char_is(ParsingData.Text[cPos], declChar)
  else
      Result := False;

  if Result then
      OutPos := cPos;
end;

{ ============================================================================
  Splitting text into a vector (character‑based)
  ============================================================================ }

function TTextParsing.SplitChar(cOffset: Integer; var LastPos: Integer;
  Include_C_0_to_32: Boolean; Split_Token_Char, Split_End_Token_Char: TP_String;
  var SplitOutput: TSymbolVector): Integer;
{ * Splits the text starting at cOffset using the characters in Split_Token_Char
  * as delimiters. Ignores comments and string literals. Optionally includes
  * control characters (0‑32) as delimiters. If Split_End_Token_Char is provided,
  * stops before that character.
  * @Param LastPos : returns the position after the last processed character.
  * @Param SplitOutput : receives the extracted elements.
  * @Return number of elements.
}
  procedure AddS(s: TP_String);
  var
    n: TP_String;
    L: Integer;
  begin
    n := s.TrimChar(#32#0);
    if n.L = 0 then
        exit;
    L := Length(SplitOutput);
    SetLength(SplitOutput, L + 1);
    SplitOutput[L] := n;
    inc(Result);
  end;

type
  TLastSym = (lsBody, lsNone);

var
  L: Integer;
  c: TP_Char;
  cPos, bPos, ePos: Integer;
  LastSym: TLastSym;
begin
  Result := 0;
  SetLength(SplitOutput, 0);
  LastPos := cOffset;
  L := ParsingData.L;
  cPos := cOffset;
  if cPos < 1 then
      cPos := 1;
  if cPos > L then
      exit;

  bPos := cPos;
  ePos := bPos;
  LastSym := lsNone;
  while (cPos <= L) do
    begin
      if isComment(cPos) then
        begin
          cPos := GetCommentEndPos(cPos);
          Continue;
        end;
      if isTextDecl(cPos) then
        begin
          cPos := GetTextDeclEndPos(cPos);
          Continue;
        end;
      c := ParsingData.Text[cPos];
      if isWordSplitChar(c, Include_C_0_to_32, Split_Token_Char) then
        begin
          if LastSym = lsBody then
            begin
              ePos := cPos;
              AddS(GetStr(bPos, ePos));
              LastSym := lsNone;
            end;
          inc(cPos);
          Continue;
        end;
      if (Split_End_Token_Char <> '') and (isWordSplitChar(c, False, Split_End_Token_Char)) then
        begin
          if LastSym = lsBody then
            begin
              ePos := cPos;
              AddS(GetStr(bPos, ePos));
              LastSym := lsNone;
            end;
          LastPos := cPos;
          exit;
        end;

      if LastSym = lsNone then
        begin
          bPos := cPos;
          LastSym := lsBody;
        end;
      inc(cPos);
    end;

  if LastSym = lsBody then
    begin
      ePos := cPos;
      AddS(GetStr(bPos, ePos));
      LastSym := lsNone;
    end;
  LastPos := cPos;
end;

function TTextParsing.SplitChar(cOffset: Integer; var LastPos: Integer;
  Split_Token_Char, Split_End_Token_Char: TP_String;
  var SplitOutput: TSymbolVector): Integer;
begin
  Result := SplitChar(cOffset, LastPos, False, Split_Token_Char, Split_End_Token_Char, SplitOutput);
end;

function TTextParsing.SplitChar(cOffset: Integer; Split_Token_Char, Split_End_Token_Char: TP_String;
  var SplitOutput: TSymbolVector): Integer;
var
  t: Integer;
begin
  Result := SplitChar(cOffset, t, Split_Token_Char, Split_End_Token_Char, SplitOutput);
end;

{ ============================================================================
  Splitting text into a vector (string‑based)
  ============================================================================ }

function TTextParsing.SplitString(cOffset: Integer; var LastPos: Integer;
  SplitTokenS, SplitEndTokenS: TP_String; var SplitOutput: TSymbolVector): Integer;
{ * Similar to SplitChar, but uses multi‑character strings as delimiters.
}
  procedure AddS(s: TP_String);
  var
    n: TP_String;
    L: Integer;
  begin
    n := s.TrimChar(#32#0);
    if n.L = 0 then
        exit;
    L := Length(SplitOutput);
    SetLength(SplitOutput, L + 1);
    SplitOutput[L] := n;
    inc(Result);
  end;

type
  TLastSym = (lsBody, lsNone);

var
  L: Integer;
  c: TP_Char;
  cPos, bPos, ePos: Integer;
  LastSym: TLastSym;
begin
  Result := 0;
  SetLength(SplitOutput, 0);
  LastPos := cOffset;
  L := ParsingData.L;
  cPos := cOffset;
  if cPos < 1 then
      cPos := 1;
  if cPos > L then
      exit;

  bPos := cPos;
  ePos := bPos;
  LastSym := lsNone;
  while (cPos <= L) do
    begin
      if isComment(cPos) then
        begin
          cPos := GetCommentEndPos(cPos);
          Continue;
        end;
      if isTextDecl(cPos) then
        begin
          cPos := GetTextDeclEndPos(cPos);
          Continue;
        end;
      if ComparePosStr(cPos, SplitTokenS) then
        begin
          if LastSym = lsBody then
            begin
              ePos := cPos;
              AddS(GetStr(bPos, ePos));
              LastSym := lsNone;
            end;
          inc(cPos, SplitTokenS.L);
          Continue;
        end;
      if (SplitEndTokenS <> '') and ComparePosStr(cPos, SplitEndTokenS) then
        begin
          if LastSym = lsBody then
            begin
              ePos := cPos;
              AddS(GetStr(bPos, ePos));
              LastSym := lsNone;
            end;
          LastPos := cPos;
          exit;
        end;

      if LastSym = lsNone then
        begin
          bPos := cPos;
          LastSym := lsBody;
        end;
      inc(cPos);
    end;

  if LastSym = lsBody then
    begin
      ePos := cPos;
      AddS(GetStr(bPos, ePos));
      LastSym := lsNone;
    end;
  LastPos := cPos;
end;

function TTextParsing.SplitString(cOffset: Integer; SplitTokenS, SplitEndTokenS: TP_String;
  var SplitOutput: TSymbolVector): Integer;
var
  t: Integer;
begin
  Result := SplitString(cOffset, t, SplitTokenS, SplitEndTokenS, SplitOutput);
end;

{ ============================================================================
  Token access and manipulation
  ============================================================================ }

function TTextParsing.CompareTokenText(cOffset: Integer; t: TP_String): Boolean;
{ * Compares the token text at the given offset with t.
  * Uses case‑insensitive comparison (Same).
}
var
  p: PTokenData;
begin
  Result := False;
  p := GetToken(cOffset);
  if p = nil then
      exit;
  Result := p^.Text.Same(t);
end;

function TTextParsing.CompareTokenChar(cOffset: Integer; c: array of TP_Char): Boolean;
{ * Checks if the token at cOffset is a single character that matches any
  * of the characters in the array.
}
var
  p: PTokenData;
begin
  Result := False;
  p := GetToken(cOffset);
  if p = nil then
      exit;
  if p^.Text.L <> 1 then
      exit;
  Result := Char_is(p^.Text.First, c);
end;

function TTextParsing.GetToken(cOffset: Integer): PTokenData;
{ * Returns the token that contains the character position cOffset.
  * Uses the precomputed CharToken array for O(1) lookup.
}
begin
  if (cOffset - 1 >= 0) and (cOffset - 1 < Length(ParsingData.Cache.CharToken)) then
      Result := ParsingData.Cache.CharToken[cOffset - 1]
  else
      Result := nil;
end;

function TTextParsing.GetTokenIndex(t: TTokenType; idx: Integer): PTokenData;
{ * Returns the idx‑th token of the given type (0‑based).
}
var
  i, c: Integer;
  p: PTokenData;
begin
  Result := nil;
  c := 0;
  for i := 0 to ParsingData.Cache.TokenDataList.Count - 1 do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[i]);
      if p^.tokenType = t then
        begin
          if c = idx then
              exit(p)
          else
              inc(c);
        end;
    end;
end;

function TTextParsing.TokenCount: Integer;
begin
  Result := ParsingData.Cache.TokenDataList.Count;
end;

function TTextParsing.TokenCountT(t: TTokenTypes): Integer;
{ * Counts how many tokens have a type that is a member of the set t.
}
var
  i: Integer;
begin
  Result := 0;
  for i := ParsingData.Cache.TokenDataList.Count - 1 downto 0 do
    if GetTokens(i)^.tokenType in t then
        inc(Result);
end;

function TTextParsing.GetTokens(idx: Integer): PTokenData;
begin
  Result := PTokenData(ParsingData.Cache.TokenDataList[idx]);
end;

function TTextParsing.FirstToken: PTokenData;
begin
  Result := GetTokens(0);
end;

function TTextParsing.LastToken: PTokenData;
begin
  Result := GetTokens(TokenCount - 1);
end;

function TTextParsing.NextToken(p: PTokenData): PTokenData;
{ * Returns the token immediately after p, or nil if p is the last.
}
begin
  Result := nil;
  if (p = nil) or (p^.Index + 1 >= TokenCount) then
      exit;
  Result := Tokens[p^.Index + 1];
end;

function TTextParsing.PrevToken(p: PTokenData): PTokenData;
{ * Returns the token immediately before p, or nil if p is the first.
}
begin
  Result := nil;
  if (p = nil) or (p^.Index - 1 >= 0) then
      exit;
  Result := Tokens[p^.Index - 1];
end;

function TTextParsing.TokenCombine(bTokenI, eTokenI: Integer; acceptT: TTokenTypes): TP_String;
{ * Concatenates the texts of tokens from index bTokenI to eTokenI (inclusive)
  * that have a token type in acceptT. The result is a single string.
  * Leading/trailing spaces are trimmed.
}
var
  bi, ei: Integer;
  p: PTokenData;
begin
  Result := '';

  if (bTokenI < 0) or (eTokenI < 0) then
      exit;

  if bTokenI > eTokenI then
    begin
      bi := eTokenI;
      ei := bTokenI;
    end
  else
    begin
      bi := bTokenI;
      ei := eTokenI;
    end;

  while (bi <= ei) and (bi < TokenCount) do
    begin
      p := Tokens[bi];
      if p^.tokenType in acceptT then
          Result.Append(p^.Text);
      inc(bi);
    end;

  if (bi >= TokenCount) then
    begin
      while (Result.L > 0) and (Result.Last = #0) do
          Result.DeleteLast;

      if (Result.L > 0) and (Result.Last = #32) then
          Result.DeleteLast;
    end;
end;

function TTextParsing.TokenCombine(bTokenI, eTokenI: Integer): TP_String;
begin
  Result := TokenCombine(bTokenI, eTokenI, [ttTextDecl, ttComment, ttNumber, ttSymbol, ttAscii, ttSpecialSymbol, ttUnknow]);
end;

function TTextParsing.Combine(bTokenI, eTokenI: Integer; acceptT: TTokenTypes): TP_String;
begin
  Result := TokenCombine(bTokenI, eTokenI, acceptT);
end;

function TTextParsing.Combine(bTokenI, eTokenI: Integer): TP_String;
begin
  Result := TokenCombine(bTokenI, eTokenI);
end;

{ ============================================================================
  Token probing (left/right search)
  ============================================================================ }

function TTextParsing.TokenProbeL(startI: Integer; acceptT: TTokenTypes): PTokenData;
{ * Searches leftwards from startI (token index) for a token whose type is in
  * acceptT. Returns the first matching token, or nil.
}
var
  idx: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  while idx >= 0 do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);
      if (p^.tokenType in acceptT) then
        begin
          Result := p;
          exit;
        end
      else
          dec(idx);
    end;
end;

function TTextParsing.TokenProbeL(startI: Integer; t: TP_String): PTokenData;
{ * Searches leftwards for a token whose text equals t (case‑insensitive).
}
var
  idx: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  while idx >= 0 do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);
      if (p^.Text.Same(t)) then
        begin
          Result := p;
          exit;
        end
      else
          dec(idx);
    end;
end;

function TTextParsing.TokenProbeL(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData;
{ * Searches leftwards for a token whose type is in acceptT and text equals t.
}
var
  idx: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  while idx >= 0 do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);
      if (p^.tokenType in acceptT) and (p^.Text.Same(t)) then
        begin
          Result := p;
          exit;
        end
      else
          dec(idx);
    end;
end;

function TTextParsing.TokenProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2: TP_String): PTokenData;
{ * Searches leftwards for a token whose type is in acceptT and text matches
  * any of t1 or t2.
}
var
  idx: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  while idx >= 0 do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);
      if (p^.tokenType in acceptT) and (p^.Text.Same(t1, t2)) then
        begin
          Result := p;
          exit;
        end
      else
          dec(idx);
    end;
end;

// Additional overloads for up to 5 strings are implemented similarly.
function TTextParsing.TokenProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2, t3: TP_String): PTokenData;
var
  idx: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  while idx >= 0 do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);
      if (p^.tokenType in acceptT) and (p^.Text.Same(t1, t2, t3)) then
        begin
          Result := p;
          exit;
        end
      else
          dec(idx);
    end;
end;

function TTextParsing.TokenProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4: TP_String): PTokenData;
var
  idx: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  while idx >= 0 do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);
      if (p^.tokenType in acceptT) and (p^.Text.Same(t1, t2, t3, t4)) then
        begin
          Result := p;
          exit;
        end
      else
          dec(idx);
    end;
end;

function TTextParsing.TokenProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4, t5: TP_String): PTokenData;
var
  idx: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  while idx >= 0 do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);
      if (p^.tokenType in acceptT) and (p^.Text.Same(t1, t2, t3, t4, t5)) then
        begin
          Result := p;
          exit;
        end
      else
          dec(idx);
    end;
end;

function TTextParsing.TokenProbeR(startI: Integer; acceptT: TTokenTypes): PTokenData;
{ * Searches rightwards from startI for a token whose type is in acceptT.
}
var
  idx: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  while idx < ParsingData.Cache.TokenDataList.Count do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);
      if (p^.tokenType in acceptT) then
        begin
          Result := p;
          exit;
        end
      else
          inc(idx);
    end;
end;

function TTextParsing.TokenProbeR(startI: Integer; t: TP_String): PTokenData;
var
  idx: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  while idx < ParsingData.Cache.TokenDataList.Count do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);
      if (p^.Text.Same(t)) then
        begin
          Result := p;
          exit;
        end
      else
          inc(idx);
    end;
end;

function TTextParsing.TokenProbeR(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData;
var
  idx: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  while idx < ParsingData.Cache.TokenDataList.Count do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);
      if (p^.tokenType in acceptT) and (p^.Text.Same(t)) then
        begin
          Result := p;
          exit;
        end
      else
          inc(idx);
    end;
end;

function TTextParsing.TokenProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2: TP_String): PTokenData;
var
  idx: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  while idx < ParsingData.Cache.TokenDataList.Count do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);
      if (p^.tokenType in acceptT) and (p^.Text.Same(t1, t2)) then
        begin
          Result := p;
          exit;
        end
      else
          inc(idx);
    end;
end;

function TTextParsing.TokenProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2, t3: TP_String): PTokenData;
var
  idx: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  while idx < ParsingData.Cache.TokenDataList.Count do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);
      if (p^.tokenType in acceptT) and (p^.Text.Same(t1, t2, t3)) then
        begin
          Result := p;
          exit;
        end
      else
          inc(idx);
    end;
end;

function TTextParsing.TokenProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4: TP_String): PTokenData;
var
  idx: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  while idx < ParsingData.Cache.TokenDataList.Count do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);
      if (p^.tokenType in acceptT) and (p^.Text.Same(t1, t2, t3, t4)) then
        begin
          Result := p;
          exit;
        end
      else
          inc(idx);
    end;
end;

function TTextParsing.TokenProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4, t5: TP_String): PTokenData;
var
  idx: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  while idx < ParsingData.Cache.TokenDataList.Count do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);
      if (p^.tokenType in acceptT) and (p^.Text.Same(t1, t2, t3, t4, t5)) then
        begin
          Result := p;
          exit;
        end
      else
          inc(idx);
    end;
end;

// Short aliases (ProbeL, LProbe, ProbeR, RProbe) simply forward to the above.
function TTextParsing.ProbeL(startI: Integer; acceptT: TTokenTypes): PTokenData;
begin Result := TokenProbeL(startI, acceptT);
end;

function TTextParsing.ProbeL(startI: Integer; t: TP_String): PTokenData;
begin Result := TokenProbeL(startI, t);
end;

function TTextParsing.ProbeL(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData;
begin Result := TokenProbeL(startI, acceptT, t);
end;

function TTextParsing.ProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2: TP_String): PTokenData;
begin Result := TokenProbeL(startI, acceptT, t1, t2);
end;

function TTextParsing.ProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2, t3: TP_String): PTokenData;
begin Result := TokenProbeL(startI, acceptT, t1, t2, t3);
end;

function TTextParsing.ProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4: TP_String): PTokenData;
begin Result := TokenProbeL(startI, acceptT, t1, t2, t3, t4);
end;

function TTextParsing.ProbeL(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4, t5: TP_String): PTokenData;
begin Result := TokenProbeL(startI, acceptT, t1, t2, t3, t4, t5);
end;

function TTextParsing.LProbe(startI: Integer; acceptT: TTokenTypes): PTokenData;
begin Result := TokenProbeL(startI, acceptT);
end;

function TTextParsing.LProbe(startI: Integer; t: TP_String): PTokenData;
begin Result := TokenProbeL(startI, t);
end;

function TTextParsing.LProbe(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData;
begin Result := TokenProbeL(startI, acceptT, t);
end;

function TTextParsing.LProbe(startI: Integer; acceptT: TTokenTypes; t1, t2: TP_String): PTokenData;
begin Result := TokenProbeL(startI, acceptT, t1, t2);
end;

function TTextParsing.LProbe(startI: Integer; acceptT: TTokenTypes; t1, t2, t3: TP_String): PTokenData;
begin Result := TokenProbeL(startI, acceptT, t1, t2, t3);
end;

function TTextParsing.LProbe(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4: TP_String): PTokenData;
begin Result := TokenProbeL(startI, acceptT, t1, t2, t3, t4);
end;

function TTextParsing.LProbe(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4, t5: TP_String): PTokenData;
begin Result := TokenProbeL(startI, acceptT, t1, t2, t3, t4, t5);
end;

function TTextParsing.ProbeR(startI: Integer; acceptT: TTokenTypes): PTokenData;
begin Result := TokenProbeR(startI, acceptT);
end;

function TTextParsing.ProbeR(startI: Integer; t: TP_String): PTokenData;
begin Result := TokenProbeR(startI, t);
end;

function TTextParsing.ProbeR(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData;
begin Result := TokenProbeR(startI, acceptT, t);
end;

function TTextParsing.ProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2: TP_String): PTokenData;
begin Result := TokenProbeR(startI, acceptT, t1, t2);
end;

function TTextParsing.ProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2, t3: TP_String): PTokenData;
begin Result := TokenProbeR(startI, acceptT, t1, t2, t3);
end;

function TTextParsing.ProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4: TP_String): PTokenData;
begin Result := TokenProbeR(startI, acceptT, t1, t2, t3, t4);
end;

function TTextParsing.ProbeR(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4, t5: TP_String): PTokenData;
begin Result := TokenProbeR(startI, acceptT, t1, t2, t3, t4, t5);
end;

function TTextParsing.RProbe(startI: Integer; acceptT: TTokenTypes): PTokenData;
begin Result := TokenProbeR(startI, acceptT);
end;

function TTextParsing.RProbe(startI: Integer; t: TP_String): PTokenData;
begin Result := TokenProbeR(startI, t);
end;

function TTextParsing.RProbe(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData;
begin Result := TokenProbeR(startI, acceptT, t);
end;

function TTextParsing.RProbe(startI: Integer; acceptT: TTokenTypes; t1, t2: TP_String): PTokenData;
begin Result := TokenProbeR(startI, acceptT, t1, t2);
end;

function TTextParsing.RProbe(startI: Integer; acceptT: TTokenTypes; t1, t2, t3: TP_String): PTokenData;
begin Result := TokenProbeR(startI, acceptT, t1, t2, t3);
end;

function TTextParsing.RProbe(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4: TP_String): PTokenData;
begin Result := TokenProbeR(startI, acceptT, t1, t2, t3, t4);
end;

function TTextParsing.RProbe(startI: Integer; acceptT: TTokenTypes; t1, t2, t3, t4, t5: TP_String): PTokenData;
begin Result := TokenProbeR(startI, acceptT, t1, t2, t3, t4, t5);
end;

{ ============================================================================
  Extended probing (full‑string match)
  ============================================================================ }

function TTextParsing.TokenFullStringProbe(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData;
begin
  Result := StringProbe(startI, acceptT, t);
end;

function TTextParsing.StringProbe(startI: Integer; acceptT: TTokenTypes; t: TP_String): PTokenData;
{ * Searches rightwards from startI for a token whose text starts with t
  * (not necessarily equal). Uses ComparePosStr to test if the token's text
  * begins with t.
}
var
  idx: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  while idx < ParsingData.Cache.TokenDataList.Count do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);
      if (p^.tokenType in acceptT) and (ComparePosStr(p^.bPos, t)) then
        begin
          Result := p;
          exit;
        end
      else
          inc(idx);
    end;
end;

{ ============================================================================
  Indent (parentheses/brackets) matching
  ============================================================================ }

function TTextParsing.IndentSymbolEndProbeR(startI: Integer; indent_begin_symbol, indent_end_symbol: TP_String): PTokenData;
{ * Finds the matching closing token for an opening indent symbol.
  * For example, given '(' and ')', it returns the token ')' that matches
  * the '(' token at startI. It handles nesting.
  * @Param startI : the index of the opening token.
  * @Param indent_begin_symbol : the opening symbol (e.g., '(').
  * @Param indent_end_symbol   : the closing symbol (e.g., ')').
  * @Return the matching closing token, or nil if not found.
}
var
  idx, bC, eC: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  bC := 0;
  eC := 0;
  while idx < ParsingData.Cache.TokenDataList.Count do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);

      if indent_begin_symbol.Exists(p^.Text.buff) then
          inc(bC)
      else if indent_end_symbol.Exists(p^.Text.buff) then
          inc(eC);

      if (bC > 0) and (eC = bC) then
        begin
          Result := p;
          exit;
        end;

      inc(idx);
    end;
end;

function TTextParsing.IndentSymbolBeginProbeL(startI: Integer; indent_begin_symbol, indent_end_symbol: TP_String): PTokenData;
{ * Finds the matching opening token for a closing indent symbol.
  * Works similarly but searches leftwards.
}
var
  idx, bC, eC: Integer;
  p: PTokenData;
begin
  Result := nil;
  if ParsingData.Cache.TokenDataList.Count <= 0 then
      exit;
  idx := startI;
  bC := 0;
  eC := 0;
  while idx >= 0 do
    begin
      p := PTokenData(ParsingData.Cache.TokenDataList[idx]);

      if indent_begin_symbol.Exists(p^.Text.buff) then
          inc(bC)
      else if indent_end_symbol.Exists(p^.Text.buff) then
          inc(eC);

      if (eC > 0) and (eC = bC) then
        begin
          Result := p;
          exit;
        end;

      dec(idx);
    end;
end;

{ ============================================================================
  Vector / matrix extraction
  ============================================================================ }

function TTextParsing.DetectSymbolVector: Boolean;
{ * Determines whether the parsed text contains a top‑level comma‑ or
  * semicolon‑separated vector. It scans for symbols that are not inside
  * parentheses or brackets.
  * @Return True if at least two elements are found.
}
var
  i: Integer;
  p1, p2, paramB, paramE: PTokenData;
  vExp: TP_String;
  VectorNum: Integer;
begin
  Result := False;

  i := 0;
  p1 := nil;
  p2 := nil;
  paramB := FirstToken;
  paramE := paramB;
  VectorNum := 0;

  while i < TokenCount do
    begin
      p1 := TokenProbeR(i, [ttSymbol]);
      if p1 = nil then
        begin
          inc(VectorNum);
          Break;
        end;
      if p1^.Text.Same(',', ';') then
        begin
          paramE := p1;
          inc(VectorNum);
          paramB := NextToken(paramE);
          if paramB = nil then
              Break;
          i := paramB^.Index;
        end
      else if p1^.Text.Same('(') then
        begin
          p2 := IndentSymbolEndProbeR(p1^.Index, '(', ')');
          if p2 = nil then
              exit;
          i := p2^.Index + 1;
        end
      else if p1^.Text.Same('[') then
        begin
          p2 := IndentSymbolEndProbeR(p1^.Index, '[', ']');
          if p2 = nil then
              exit;
          i := p2^.Index + 1;
        end
      else
          inc(i);
    end;

  Result := VectorNum > 1;
end;

function TTextParsing.Extract_Symbol_Vector(L: TPascalStringList): Boolean;
{ * Extracts the top‑level vector elements into a TPascalStringList.
  * Each element is the text of a sub‑expression between delimiters.
}
var
  i: Integer;
  p1, p2, paramB, paramE: PTokenData;
  vExp: TP_String;
begin
  Result := False;

  i := 0;
  p1 := nil;
  p2 := nil;
  paramB := FirstToken;
  paramE := paramB;

  while i < TokenCount do
    begin
      p1 := TokenProbeR(i, [ttSymbol]);
      if p1 = nil then
        begin
          vExp := TokenCombine(paramB^.Index, TokenCount - 1);
          L.Add(vExp.Text);
          Break;
        end;
      if p1^.Text.Same(',', ';') then
        begin
          paramE := p1;
          if paramB <> paramE then
              vExp := TokenCombine(paramB^.Index, paramE^.Index - 1)
          else
              vExp := '';
          L.Add(vExp.Text);
          paramB := NextToken(paramE);
          if paramB = nil then
              Break;
          i := paramB^.Index;
        end
      else if p1^.Text.Same('(') then
        begin
          p2 := IndentSymbolEndProbeR(p1^.Index, '(', ')');
          if p2 = nil then
              exit;
          i := p2^.Index + 1;
        end
      else if p1^.Text.Same('[') then
        begin
          p2 := IndentSymbolEndProbeR(p1^.Index, '[', ']');
          if p2 = nil then
              exit;
          i := p2^.Index + 1;
        end
      else
          inc(i);
    end;

  Result := True;
end;

function TTextParsing.Extract_Symbol_Vector: TSymbolVector;
{ * Returns the vector as a dynamic array of TP_String.
}
var
  L: TPascalStringList;
  i: Integer;
begin
  L := TPascalStringList.Create;
  if Extract_Symbol_Vector(L) then
    begin
      SetLength(Result, L.Count);
      for i := 0 to L.Count - 1 do
          Result[i] := L[i];
    end
  else
      SetLength(Result, 0);
  DisposeObject(L);
end;

function TTextParsing.FillSymbolMatrix(W, H: Integer; var symbolMatrix: TSymbolMatrix): Boolean;
{ * Fills a 2D matrix (rows × columns) from a flat vector extracted from the text.
  * The vector must have at least W*H elements.
}
var
  L: TPascalStringList;
  i, j, k: Integer;
begin
  SetLength(symbolMatrix, 0, 0);
  L := TPascalStringList.Create;
  Result := Extract_Symbol_Vector(L);
  if L.Count >= W * H then
    begin
      SetLength(symbolMatrix, H, W);
      k := 0;
      for j := 0 to H - 1 do
        for i := 0 to W - 1 do
          begin
            symbolMatrix[j, i] := L[k];
            inc(k);
          end;
    end;
  DisposeObject(L);
end;

{ ============================================================================
  Text extraction and editing
  ============================================================================ }

function TTextParsing.GetText(bPos, ePos: Integer): TP_String;
begin
  Result := GetStr(bPos, ePos);
end;

function TTextParsing.GetStr(bPos, ePos: Integer): TP_String;
{ * Returns the substring from bPos (inclusive) to ePos (exclusive).
  * If ePos is beyond the text length, it adjusts to include up to the end.
}
begin
  if ePos >= ParsingData.L then
    begin
      Result := ParsingData.Text.GetString(bPos, ePos + 1);
      while (Result.L > 0) and (Result.Last = #0) do
          Result.DeleteLast;
      if (Result.L > 0) and (Result.Last = #32) then
          Result.DeleteLast;
    end
  else
      Result := ParsingData.Text.GetString(bPos, ePos);
end;

function TTextParsing.GetStr(tp: TTextPos): TP_String;
begin
  Result := GetStr(tp.bPos, tp.ePos);
end;

function TTextParsing.GetWord(cOffset: Integer): TP_String;
begin
  Result := GetStr(GetAsciiBeginPos(cOffset), GetAsciiEndPos(cOffset));
end;

function TTextParsing.GetPoint(cOffset: Integer): TPoint;
{ * Converts a character position to a TPoint (X = column, Y = line).
  * Both are 1‑based.
}
var
  i: Integer;
  cPos: Integer;
begin
  cPos := cOffset;
  Result := Point(1, 1);
  if cPos > ParsingData.L then
      cPos := ParsingData.L;
  for i := 1 to cPos - 1 do
    begin
      if ParsingData.Text[i] = #10 then
        begin
          inc(Result.y);
          Result.x := 0;
        end
      else if not Char_is(ParsingData.Text[i], [#13]) then
          inc(Result.x);
    end;
end;

function TTextParsing.GetChar(cOffset: Integer): TP_Char;
begin
  Result := ParsingData.Text[cOffset];
end;

procedure TTextParsing.DeletePos(bPos, ePos: Integer);
{ * Deletes the range from bPos (inclusive) to ePos (exclusive).
  * Rebuilds the cache after modification.
}
begin
  ParsingData.Text := GetStr(1, bPos) + GetStr(ePos, Len);
  ParsingData.L := ParsingData.Text.L;
  RebuildParsingCache;
end;

procedure TTextParsing.DeletePos(tp: TTextPos);
begin
  DeletePos(tp.bPos, tp.ePos);
end;

procedure TTextParsing.DeletedComment;
{ * Removes all comments from the text and rebuilds cache.
}
begin
  ParsingData.Text := GetDeletedCommentText.TrimChar(#32);
  ParsingData.L := ParsingData.Text.L;
  RebuildParsingCache;
end;

procedure TTextParsing.InsertTextBlock(bPos, ePos: Integer; InsertText_: TP_String);
{ * Inserts InsertText_ at the given range (replaces the range).
}
begin
  ParsingData.Text := GetStr(1, bPos) + InsertText_ + GetStr(ePos, Len + 1);
  ParsingData.L := ParsingData.Text.L;
  RebuildParsingCache;
end;

procedure TTextParsing.InsertTextBlock(tp: TTextPos; InsertText_: TP_String);
begin
  InsertTextBlock(tp.bPos, tp.ePos, InsertText_);
end;

function TTextParsing.SearchWordBody(initPos: Integer; wordInfo: TP_String; var OutPos: TTextPos): Boolean;
{ * Searches for an exact word (identifier) that equals wordInfo, starting
  * from initPos. Returns True and fills OutPos if found.
}
var
  cp: Integer;
  ePos: Integer;
begin
  Result := False;

  cp := initPos;

  while cp <= ParsingData.L do
    begin
      if isTextDecl(cp) then
        begin
          ePos := GetTextDeclEndPos(cp);
          cp := ePos;
        end
      else if isComment(cp) then
        begin
          ePos := GetCommentEndPos(cp);
          cp := ePos;
        end
      else if isNumber(cp) then
        begin
          ePos := GetNumberEndPos(cp);
          if GetStr(cp, ePos).Same(wordInfo) then
            begin
              OutPos.bPos := cp;
              OutPos.ePos := ePos;
              Result := True;
              Break;
            end;
          cp := ePos;
        end
      else if isSymbol(cp) then
        begin
          ePos := GetSymbolEndPos(cp);
          cp := ePos;
        end
      else if isAscii(cp) then
        begin
          ePos := GetAsciiEndPos(cp);
          if GetStr(cp, ePos).Same(wordInfo) then
            begin
              OutPos.bPos := cp;
              OutPos.ePos := ePos;
              Result := True;
              Break;
            end;
          cp := ePos;
        end
      else
          inc(cp);
    end;
end;

{ ============================================================================
  String declaration conversion (class methods)
  ============================================================================ }

class function TTextParsing.Translate_Pascal_Decl_To_Text(Decl: TP_String): TP_String;
{ * Converts a Pascal string literal (e.g., ''Hello'+#10+'World'') to plain text.
  * Handles:
  *   - single‑quoted strings with doubled quotes for embedded quotes.
  *   - #‑encoded characters (decimal or hex with $).
  *   - concatenation of adjacent literals.
}
var
  cPos: Integer;
  VIsTextDecl: Boolean;
  nText: TP_String;
begin
  cPos := 1;
  VIsTextDecl := False;
  Result := '';
  while cPos <= Decl.L do
    begin
      if Decl.ComparePos(cPos, #39#39#39#39) then
        begin
          Result.Append(#39);
          inc(cPos, 4);
        end
      else if Decl[cPos] = #39 then
        begin
          VIsTextDecl := not VIsTextDecl;
          inc(cPos);
        end
      else
        begin
          if VIsTextDecl then
            begin
              Result.Append(Decl[cPos]);
              inc(cPos);
            end
          else if Decl[cPos] = '#' then
            begin
              nText := '';
              inc(cPos);
              while cPos <= Decl.L do
                begin
                  if Char_is(Decl[cPos], [{$IFDEF FPC}ucHex{$ELSE FPC}cHex{$ENDIF FPC}], '$') then
                    begin
                      nText.Append(Decl[cPos]);
                      inc(cPos);
                    end
                  else
                      Break;
                end;
              Result.Append(TP_Char(umlStrToInt(nText, 0)));
            end
          else
              inc(cPos);
        end;
    end;
end;

class function TTextParsing.Translate_Text_To_Pascal_Decl(Decl: TP_String): TP_String;
{ * Converts plain text to a Pascal string literal.
  * Encodes control characters (0‑31) and the single quote as #... sequences.
  * All other characters are placed inside quotes.
}
var
  cPos: Integer;
  c: TP_Char;
  LastIsOrdChar: Boolean;
  ordCharInfo: TP_String;
begin
  if Decl.L = 0 then
    begin
      Result := #39#39;
      exit;
    end;

  ordCharInfo.L := 32;
  for cPos := 0 to 31 do
      ordCharInfo.buff[cPos] := TP_Char(Ord(cPos));
  ordCharInfo[32] := #39;

  Result := '';
  LastIsOrdChar := False;
  for cPos := 1 to Decl.L do
    begin
      c := Decl[cPos];
      if Char_is(c, ordCharInfo) then
        begin
          if Result.L = 0 then
              Result := '#' + umlIntToStr(Ord(c))
          else if LastIsOrdChar then
              Result.Append('#' + umlIntToStr(Ord(c)))
          else
              Result.Append(#39 + '#' + umlIntToStr(Ord(c)));
          LastIsOrdChar := True;
        end
      else
        begin
          if Result.L = 0 then
              Result := #39 + c
          else if LastIsOrdChar then
              Result.Append(#39 + c)
          else
              Result.Append(c);

          LastIsOrdChar := False;
        end;
    end;

  if not LastIsOrdChar then
      Result.Append(#39);
end;

class function TTextParsing.Translate_Text_To_Pascal_Decl_With_Unicode(Decl: TP_String): TP_String;
{ * Similar to Translate_Text_To_Pascal_Decl, but also encodes any character
  * with ordinal >= $80 as #... to avoid Unicode issues in Pascal source.
}
var
  cPos: Integer;
  c: TP_Char;
  LastIsOrdChar: Boolean;
  ordCharInfo: TP_String;
begin
  if Decl.L = 0 then
    begin
      Result := #39#39;
      exit;
    end;

  ordCharInfo.L := 32 + 1;
  for cPos := 0 to 31 do
      ordCharInfo[cPos + 1] := TP_Char(Ord(cPos));
  ordCharInfo[33] := #39;

  Result := '';
  LastIsOrdChar := False;
  for cPos := 1 to Decl.L do
    begin
      c := Decl[cPos];
      if Char_is(c, ordCharInfo) or (Ord(c) >= $80) then
        begin
          if Result.L = 0 then
              Result := '#' + umlIntToStr(Ord(c))
          else if LastIsOrdChar then
              Result.Append('#' + umlIntToStr(Ord(c)))
          else
              Result.Append(#39 + '#' + umlIntToStr(Ord(c)));
          LastIsOrdChar := True;
        end
      else
        begin
          if Result.L = 0 then
              Result := #39 + c
          else if LastIsOrdChar then
              Result.Append(#39 + c)
          else
              Result.Append(c);

          LastIsOrdChar := False;
        end;
    end;

  if not LastIsOrdChar then
      Result.Append(#39);
end;

class function TTextParsing.Translate_C_Decl_To_Text(Decl: TP_String): TP_String;
{ * Converts a C string literal (with escapes) to plain text.
  * Handles the standard escape sequences listed in CTranslateTable.
}
var
  cPos: Integer;
  i: Integer;
  VIsCharDecl: Boolean;
  VIsTextDecl: Boolean;
  nText: TP_String;
  wasC: Boolean;
begin
  cPos := 1;
  VIsCharDecl := False;
  VIsTextDecl := False;
  Result := '';
  while cPos <= Decl.L do
    begin
      if Decl[cPos] = #39 then
        begin
          VIsCharDecl := not VIsCharDecl;
          inc(cPos);
        end
      else if Decl[cPos] = '"' then
        begin
          VIsTextDecl := not VIsTextDecl;
          inc(cPos);
        end
      else
        begin
          wasC := False;
          for i := low(CTranslateTable) to high(CTranslateTable) do
            begin
              if Decl.ComparePos(cPos, CTranslateTable[i].c) then
                begin
                  inc(cPos, Length(CTranslateTable[i].c));
                  Result.Append(CTranslateTable[i].s);
                  wasC := True;
                  Break;
                end;
            end;
          if (not wasC) then
            begin
              if VIsTextDecl or VIsCharDecl then
                  Result.Append(Decl[cPos]);
              inc(cPos);
            end;
        end;
    end;
end;

class function TTextParsing.Translate_Text_To_C_Decl(Decl: TP_String): TP_String;
{ * Converts plain text to a C string literal with escapes.
  * Characters that need escaping are replaced according to CTranslateTable.
}
  function GetCStyle(c: TP_Char): TP_SystemString;
  var
    i: Integer;
  begin
    Result := '';
    for i := low(CTranslateTable) to high(CTranslateTable) do
      if c = CTranslateTable[i].s then
        begin
          Result := CTranslateTable[i].c;
          Break;
        end;
  end;

var
  cPos: Integer;
  c: TP_Char;
  LastIsOrdChar: Boolean;
  n: TP_SystemString;
begin
  if Decl.L = 0 then
    begin
      Result := '""';
      exit;
    end;

  Result := '';
  LastIsOrdChar := False;
  for cPos := 1 to Decl.L do
    begin
      c := Decl[cPos];

      if Result.L = 0 then
          Result := '"' + c
      else
        begin
          n := GetCStyle(c);
          if n <> '' then
              Result.Append(n)
          else
              Result.Append(c);
        end;
    end;

  if not LastIsOrdChar then
      Result.Append('"');
end;

{ ============================================================================
  Comment declaration conversion (class methods)
  ============================================================================ }

class function TTextParsing.Translate_Pascal_Decl_Comment_To_Text(Decl: TP_String): TP_String;
{ * Removes Pascal comment delimiters and returns the content.
}
begin
  Result := Decl.TrimChar(#32#9);
  if umlMultipleMatch(False, '{*}', Result) then
    begin
      Result.DeleteFirst;
      Result.DeleteLast;
      if umlMultipleMatch(False, '$*', Result.TrimChar(#32#9)) then
          Result := Decl;
    end
  else if umlMultipleMatch(False, '(*?*)', Result, '?', '') then
    begin
      Result.DeleteFirst;
      Result.DeleteFirst;
      Result.DeleteLast;
      Result.DeleteLast;
    end
  else if umlMultipleMatch(False, '////*', Result) then
    begin
      Result.DeleteFirst;
      Result.DeleteFirst;
      Result.DeleteFirst;
      Result.DeleteFirst;
      while Char_is(Result.Last, [#13, #10]) do
          Result.DeleteLast;
    end
  else if umlMultipleMatch(False, '///*', Result) then
    begin
      Result.DeleteFirst;
      Result.DeleteFirst;
      Result.DeleteFirst;
      while Char_is(Result.Last, [#13, #10]) do
          Result.DeleteLast;
    end
  else if umlMultipleMatch(False, '//*', Result) then
    begin
      Result.DeleteFirst;
      Result.DeleteFirst;
      while Char_is(Result.Last, [#13, #10]) do
          Result.DeleteLast;
    end;
end;

class function TTextParsing.Translate_Text_To_Pascal_Decl_Comment(Decl: TP_String): TP_String;
var
  n: TP_String;
begin
  n := Decl.TrimChar(#32#9);
  if umlMultipleMatch(False, '(*?*)', n, '?', '') then
      Result := Decl
  else if umlMultipleMatch(False, '{*}', n) then
      Result := Decl
  else if n.Exists(['{', '}']) then
      Result := '(* ' + Decl.Text + ' *)'
  else
      Result := '{ ' + Decl.Text + ' }';
end;

class function TTextParsing.Translate_C_Decl_Comment_To_Text(Decl: TP_String): TP_String;
{ * Removes C comment delimiters: /* ... */, //, and # (preprocessor).
}
begin
  Result := Decl.TrimChar(#32#9);
  if umlMultipleMatch(False, '#*', Result) then
    begin
      Result := Decl;
    end
  else if umlMultipleMatch(False, '/*?*/', Result, '?', '') then
    begin
      Result.DeleteFirst;
      Result.DeleteFirst;
      Result.DeleteLast;
      Result.DeleteLast;
    end
  else if umlMultipleMatch(False, '////*', Result) then
    begin
      Result.DeleteFirst;
      Result.DeleteFirst;
      Result.DeleteFirst;
      Result.DeleteFirst;
    end
  else if umlMultipleMatch(False, '///*', Result) then
    begin
      Result.DeleteFirst;
      Result.DeleteFirst;
      Result.DeleteFirst;
    end
  else if umlMultipleMatch(False, '//*', Result) then
    begin
      Result.DeleteFirst;
      Result.DeleteFirst;
    end;
end;

class function TTextParsing.Translate_Text_To_C_Decl_Comment(Decl: TP_String): TP_String;
{ * Wraps text in C comment delimiters /* ... */. If the text already looks
  * like a preprocessor directive (#), it leaves it unchanged.
}
var
  n: TP_String;
begin
  n := Decl.TrimChar(#32#9);
  if umlMultipleMatch(False, '#*', n) then
      Result := Decl
  else
      Result := '/* ' + n.Text + ' */';
end;

{ ============================================================================
  Constructors and destructor
  ============================================================================ }

constructor TTextParsing.Create(Text_: TP_String; Style_: TTextStyle;
  SpecialSymbol_: TListPascalString; SpacerSymbol_: TP_SystemString);
begin
  inherited Create;
  ParsingData.Cache.CommentDecls := nil;
  ParsingData.Cache.TextDecls := nil;
  ParsingData.Cache.TokenDataList := nil;
  SetLength(ParsingData.Cache.CharToken, 0);
  if Text_.L = 0 then
      ParsingData.Text := #13#10
  else
      ParsingData.Text := Text_.Text + #32; // append space for safe scanning
  ParsingData.L := ParsingData.Text.L;
  TextStyle := Style_;
  SymbolTable := SpacerSymbol_;
  TokenStatistics := NullTokenStatistics;
  SpecialSymbol := TListPascalString.Create;
  if SpecialSymbol_ <> nil then
      SpecialSymbol.Assign(SpecialSymbol_);
  RebuildCacheBusy := False;

  RebuildParsingCache;

  Init;
end;

constructor TTextParsing.Create(Text_: TP_String; Style_: TTextStyle; SpecialSymbol_: TListPascalString);
begin
  Create(Text_, Style_, SpecialSymbol_, SpacerSymbol.V);
end;

constructor TTextParsing.Create(Text_: TP_String; Style_: TTextStyle);
begin
  Create(Text_, Style_, nil, SpacerSymbol.V);
end;

constructor TTextParsing.Create(Text_: TP_String);
begin
  Create(Text_, tsText, nil, SpacerSymbol.V);
end;

destructor TTextParsing.Destroy;
{ * Releases all cached structures and owned objects.
}
var
  i: Integer;
begin
  if ParsingData.Cache.CommentDecls <> nil then
    begin
      for i := 0 to ParsingData.Cache.CommentDecls.Count - 1 do
        begin
          ParsingData.Cache.CommentDecls[i]^.Text := '';
          Dispose(ParsingData.Cache.CommentDecls[i]);
        end;
      DisposeObject(ParsingData.Cache.CommentDecls);
      ParsingData.Cache.CommentDecls := nil;
    end;

  if ParsingData.Cache.TextDecls <> nil then
    begin
      for i := 0 to ParsingData.Cache.TextDecls.Count - 1 do
        begin
          ParsingData.Cache.TextDecls[i]^.Text := '';
          Dispose(ParsingData.Cache.TextDecls[i]);
        end;
      DisposeObject(ParsingData.Cache.TextDecls);
      ParsingData.Cache.TextDecls := nil;
    end;

  if ParsingData.Cache.TokenDataList <> nil then
    begin
      for i := 0 to ParsingData.Cache.TokenDataList.Count - 1 do
        begin
          ParsingData.Cache.TokenDataList[i]^.Text := '';
          Dispose(ParsingData.Cache.TokenDataList[i]);
        end;
      DisposeObject(ParsingData.Cache.TokenDataList);
      ParsingData.Cache.TokenDataList := nil;
    end;
  SetLength(ParsingData.Cache.CharToken, 0);

  TokenStatistics := NullTokenStatistics;
  DisposeObject(SpecialSymbol);
  inherited Destroy;
end;

{ ============================================================================
  Virtual hooks
  ============================================================================ }

procedure TTextParsing.Init;
{ * Called after construction; override in subclasses for custom initialisation.
  * Does nothing by default.
}
begin
end;

function TTextParsing.Parsing: Boolean;
{ * Override to implement custom parsing logic. Should return True on success.
  * By default returns False.
}
begin
  Result := False;
end;

{ ============================================================================
  Debug output
  ============================================================================ }

procedure TTextParsing.Print;
{ * Prints all tokens to the status console using Z.Status.
  * Useful for debugging.
}
var
  i: Integer;
  pt: PTokenData;
begin
  for i := 0 to ParsingData.Cache.TokenDataList.Count - 1 do
    begin
      pt := ParsingData.Cache.TokenDataList[i];
      DoStatus(PFormat('index: %d type: %s value: %s', [i, GetEnumName(TypeInfo(TTokenType), Ord(pt^.tokenType)), pt^.Text.Text]));
    end;
end;

{ ============================================================================
  Test helper (internal)
  ============================================================================ }

procedure FillSymbol_Test_;
var
  t: TTextParsing;
  SM: TSymbolMatrix;
begin
  t := TTextParsing.Create('1,2,3,4,5,6,7,8,9', tsPascal);
  t.FillSymbolMatrix(3, 2, SM);
  DisposeObject(t);
end;

{ ============================================================================
  Unit initialisation and finalisation
  ============================================================================ }

initialization

SpacerSymbol := TAtomString.Create(C_SpacerSymbol);

finalization

DisposeObjectAndNil(SpacerSymbol);

end.
 
