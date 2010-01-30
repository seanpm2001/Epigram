\section{Cochon Command Lexer}

%if False

> {-# OPTIONS_GHC -F -pgmF she #-}
> {-# LANGUAGE TypeOperators, TypeSynonymInstances, GADTs,
>     DeriveFunctor, DeriveFoldable, DeriveTraversable #-}

> module Cochon.CommandLexer where

> import Control.Applicative
> import Control.Monad.State
> import Control.Monad.Error
> import Data.Foldable hiding (find)
> import Data.List
> import Data.Traversable hiding (sequence)
> import System.Exit
> import System.IO 

> import Kit.BwdFwd
> import Kit.Parsley
> import Kit.MissingLibrary

> import NameSupply.NameSupply

> import Evidences.Tm hiding (In)

> import DisplayLang.Lexer
> import DisplayLang.Naming
> import DisplayLang.TmParse
> import DisplayLang.Elaborator
> import DisplayLang.DisplayTm

> import ProofState.Developments
> import ProofState.ProofContext
> import ProofState.ProofState
> import ProofState.ProofKit

> import Tactics.Elimination
> import Tactics.Induction
> import Tactics.PropSimp

> import Cochon.DisplayCommands

> import Compiler.Compiler

%endif

\pierre{This needs some story.}

\subsection{Tokens}

Because Cochon tactics can take different types of arguments,
we need a tagging mechanism to distinguish them, together
with projection functions.

> data CochonArg = StrArg String 
>                | InArg InDTmRN 
>                | ExArg ExDTmRN
>                | Optional CochonArg
>                | NoCochonArg


\subsection{Tokenizer combinators}

> parseExTm :: Parsley Token CochonArg
> parseExTm = (| ExArg pExDTm |)

> parseAscription :: Parsley Token CochonArg
> parseAscription = (| ExArg pAscriptionTC |)

> parseInTm :: Parsley Token CochonArg
> parseInTm = (| InArg pInDTm |)

> parseName :: Parsley Token CochonArg
> parseName = (| (ExArg . DP) nameParse |)

> parseString :: Parsley Token CochonArg
> parseString = (| StrArg ident |)

> parseOption :: Parsley Token CochonArg -> Parsley Token CochonArg
> parseOption p = (| Optional (bracket Square p) 
>                  | NoCochonArg |)


\subsection{Printers}

> argToStr :: CochonArg -> String
> argToStr (StrArg s) = s

> argToIn :: CochonArg -> InDTmRN
> argToIn (InArg a) = a

> argToEx :: CochonArg -> ExDTmRN
> argToEx (ExArg a) = a

> argOption :: (CochonArg -> a) -> CochonArg -> Maybe a
> argOption p (Optional x) = Just $ p x
> argOption _ NoCochonArg = Nothing


