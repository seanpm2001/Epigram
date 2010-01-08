\section{Display Commands}

%if False

> {-# OPTIONS_GHC -F -pgmF she #-}
> {-# LANGUAGE GADTs, TypeOperators #-}

> module DisplayCommands where

> import Control.Applicative hiding (empty)
> import Control.Monad.State
> import Text.PrettyPrint.HughesPJ

> import BwdFwd hiding ((<+>))
> import Developments
> import DisplayTm
> import Distiller
> import Elaborator
> import MissingLibrary
> import Naming
> import PrettyPrint
> import ProofState
> import Root
> import Rooty
> import Rules hiding (($$))
> import Tm

%endif


The |infoElaborate| command calls |elabInfer| on the given neutral display term,
evaluates the resulting term, bquotes it and returns a pretty-printed string
representation. Note that it works in its own module which it discards at the
end, so it will not leave any subgoals lying around in the proof state.

> infoElaborate :: INDTM -> ProofState String
> infoElaborate (DN tm) = do
>     makeModule "__infoElaborate"
>     goIn
>     ty :>: tm' <- elabInfer tm
>     tm'' <- bquoteHere (evTm (N tm'))
>     s <- prettyHere (ty :>: tm'')
>     goOut
>     dropModule
>     return (show s)
> infoElaborate _ = throwError' "infoElaborate: can only elaborate neutral terms."


The |infoInfer| command is similar to |infoElaborate|, but it returns a string
representation of the resulting type.

> infoInfer :: INDTM -> ProofState String
> infoInfer (DN tm) = do
>     makeModule "__infoInfer"
>     goIn
>     ty :>: _ <- elabInfer tm
>     ty' <- bquoteHere ty
>     s <- prettyHere (SET :>: ty')
>     goOut
>     dropModule
>     return (show s)
> infoInfer _ = throwError' "infoInfer: can only infer the type of neutral terms."


The |infoHypotheses| command displays a distilled list of things in the context.
This is written using a horrible imperative hack that saves the state, throws
away bits of the context to produce an answer, then restores the saved state.

> infoHypotheses :: ProofState String
> infoHypotheses = do
>     save <- get
>     aus <- getAuncles
>     me <- getMotherName
>     ds <- many (hypsHere aus me <* optional killCadets <* goOut <* removeDevEntry)
>     d <- hypsHere aus me
>     put save
>     return (show (vcat (d:reverse ds)))
>  where
>    hypsHere :: Entries -> Name -> ProofState Doc
>    hypsHere aus me = do
>        es <- getDevEntries
>        d <- hyps aus me
>        putDevEntries es
>        return d
>    
>    killCadets = do
>        l <- getLayer
>        replaceLayer (l { cadets = NF F0 })
>
>    hyps :: Entries -> Name -> ProofState Doc
>    hyps aus me = do
>        es <- getDevEntries
>        case es of
>            B0 -> return empty
>            (es' :< E ref _ (Boy k) _) -> do
>                putDevEntries es'
>                ty' <- bquoteHere (pty ref)
>                docTy <- prettyHere (SET :>: ty')
>                d <- hyps aus me
>                return (d $$ prettyBKind k (text (christenREF aus me ref) <+> text ":" <+> docTy))
>            (es' :< E ref _ (Girl LETG _) _) -> do
>                goIn
>                es <- getDevEntries
>                (ty :=>: _) <- getGoal "hyps"
>                ty' <- bquoteHere (evTm (inferGoalType es ty))
>                docTy <- prettyHere (SET :>: ty')
>                goOut
>                putDevEntries es'
>                d <- hyps aus me
>                return (d $$ (text (christenREF aus me ref) <+> text ":" <+> docTy))
>            (es' :< _) -> putDevEntries es' >> hyps aus me


The |prettyHere| command distills a term in the current context,
then passes it to the pretty-printer.

> prettyHere :: (TY :>: INTM) -> ProofState Doc
> prettyHere tt = do
>     aus <- getAuncles
>     dtm :=>: _ <- distill aus tt
>     return (pretty dtm)