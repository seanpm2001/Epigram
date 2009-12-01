\section{Proof State}

%if False

> {-# OPTIONS_GHC -F -pgmF she #-}
> {-# LANGUAGE TypeOperators, TypeSynonymInstances #-}

> module Elaborator where

> import Control.Applicative
> import Control.Monad
> import Control.Monad.State
> import Data.Foldable
> import Data.Traversable
> import Debug.Trace

> import BwdFwd
> import Developments
> import DevLoad
> import PrettyPrint
> import Root
> import Rooty
> import Rules
> import Tm
> import MissingLibrary

%endif

\subsection{Proof Context}

Recall from Section~\ref{sec:developments} that

< type Dev = (Bwd Entry, Tip, Root)

We ``unzip`` (cf. Huet's Zipper) this type to produce a type representing its
one-hole context, which allows us to keep track of the location of a working
development and perform local navigation easily.
Each |Layer| of the structure is a record with the following fields:
\begin{description}
\item[|elders|] entries appearing above the working development
\item[|mother|] the |REF| of the |Entry| that contains the working development
\item[|cadets|] entries appearing below the working development
\item[|laytip|] the |Tip| of the containing development
\item[|layroot|] the |Root| of the containing development
\end{description}

> data Layer = Layer
>   {  elders  :: Bwd Entry
>   ,  mother  :: REF
>   ,  cadets  :: Fwd Entry
>   ,  laytip  :: Tip
>   ,  layroot :: Root }
>   deriving Show

The current proof context is then represented by a stack of |Layer|s, along with the
current working development:

> type ProofContext = (Bwd Layer, Dev)

The |greatAuncles| function returns the elder aunts or uncles of the current development,
not including its contents.

> greatAuncles :: ProofContext -> Bwd Entry
> greatAuncles (ls, _) = foldMap elders ls

The |auncles| function returns the elder aunts or uncles of the current insertion point,
including the contents of the current development, thereby giving a list of entries that
are currently in scope.

> auncles :: ProofContext -> Bwd Entry
> auncles c@(_, (es, _, _)) = greatAuncles c <+> es


\subsection{Proof State Monad}

The proof state monad provides access to the |ProofContext| as in a |State| monad,
but with the possibility of command failure represented by |Maybe|. 

> type ProofState = StateT ProofContext Maybe

Handily, |Maybe| is a |MonadPlus|, and |StateT| preserves this, so we can easily
make |ProofState| an |Alternative|:

> instance Applicative ProofState where
>     pure = return
>     (<*>) = ap

> instance Alternative ProofState where
>     empty = mzero
>     (<|>) = mplus

We provide various functions to get information from the proof state and store
updated information, providing a friendlier interface than |get| and |put|.

> getDev :: ProofState Dev
> getDev = gets snd

> getDevEntries :: ProofState (Bwd Entry)
> getDevEntries = do
>     (es, _, _) <- getDev
>     return es

> getDevRoot :: ProofState Root
> getDevRoot = do
>     (_, _, root) <- getDev
>     return root

> getDevTip :: ProofState Tip
> getDevTip = do
>     (_, tip, _) <- getDev
>     return tip

> getLayer :: ProofState Layer
> getLayer = do
>     ls :< l <- gets fst
>     return l

> getMother :: ProofState REF
> getMother = do
>     l <- getLayer
>     return (mother l)

> insertCadet :: Entry -> ProofState ()
> insertCadet e = do
>     l <- getLayer
>     replaceLayer l{cadets = e :> cadets l}
>     return ()

> putDev :: Dev -> ProofState ()
> putDev dev = do
>     ls <- gets fst
>     put (ls, dev)

> putDevEntry :: Entry -> ProofState ()
> putDevEntry e = do
>     (es, tip, root) <- getDev
>     putDev (es :< e, tip, root)

> putDevEntries :: Bwd Entry -> ProofState ()
> putDevEntries es = do
>     (_, tip, root) <- getDev
>     putDev (es, tip, root)

> putDevRoot :: Root -> ProofState ()
> putDevRoot r = do
>     (es, tip, _) <- getDev
>     putDev (es, tip, r)

> putDevTip :: Tip -> ProofState ()
> putDevTip tip = do
>     (es, _, r) <- getDev
>     putDev (es, tip, r)

> putLayer :: Layer -> ProofState ()
> putLayer l = do
>     (ls, dev) <- get
>     put (ls :< l, dev)

> putMother :: REF -> ProofState ()
> putMother ref = do
>     l <- getLayer
>     _ <- replaceLayer l{mother=ref}
>     return ()

> removeDevEntry :: ProofState (Maybe Entry)
> removeDevEntry = do
>     es <- getDevEntries
>     case es of
>       B0 -> return Nothing
>       (es' :< e) -> do
>         putDevEntries es'
>         return (Just e)

> removeLayer :: ProofState Layer
> removeLayer = do
>     (ls :< l, dev) <- get
>     put (ls, dev)
>     return l

> replaceDev :: Dev -> ProofState Dev
> replaceDev dev = do
>     (ls, dev') <- get
>     put (ls, dev)
>     return dev'

> replaceLayer :: Layer -> ProofState Layer
> replaceLayer l = do
>     (ls :< l', dev) <- get
>     put (ls :< l, dev)
>     return l'


A |ProofState| is not |Rooty| because the semantics of the latter are not compatible
with the caching of |Root|s in the proof context. However, it can provide the current
|Root| to a function that requires it. Note that this function has no way to return
an updated root to the proof context, so it must not leave any references around
when it has finished.

> withRoot :: (Root -> x) -> ProofState x
> withRoot f = getDevRoot >>= return . f

Presumably we should be able to do something similar for running tactics?

< withTac :: TY -> Tac x -> ProofState x


\subsubsection{Navigation Commands}

Now we provide commands to navigate the proof state:
\begin{itemize}
\item |goIn| changes the current location to the bottom-most girl in the current development;
\item |goOut| goes up a layer, so the focus changes to the development containing
the current working location;
\item |goUp| moves the focus to the next eldest girl;
\item |goDown| moves the focus to the next youngest girl.
\end{itemize}

These commands fail (yielding |Nothing|) if they are impossible because the proof context
is not in the required form.

> goIn :: ProofState ()
> goIn = goInAcc F0 
>   where
>     goInAcc :: Fwd Entry -> ProofState ()
>     goInAcc cadets = do
>         (ls, (es :< e, tip, root)) <- get
>         case e of
>             E ref _ (Girl LETG dev) -> put (ls :< Layer es ref cadets tip root, dev)
>             _ -> put (ls, (es, tip, root)) >> goInAcc (e :> cadets)

> goOut :: ProofState ()
> goOut = do
>     Layer elders mother cadets tip root <- removeLayer
>     dev <- getDev
>     putDev (elders :< E mother (lastName mother) (Girl LETG dev) {- <>< cadets-}, tip, root)        
>     propagateNews [] cadets

> goUp :: ProofState ()
> goUp = goUpAcc F0
>   where
>     goUpAcc :: Fwd Entry -> ProofState ()
>     goUpAcc acc = do
>         l@(Layer (es :< e) oldRef cadets tip root) <- removeLayer
>         oldDev <- getDev
>         case e of
>             E newRef _ (Girl LETG newDev) ->
>                 putDev newDev >>
>                 putLayer l{elders=es, mother=newRef,cadets=(acc <+> 
>                     (E oldRef (lastName oldRef) (Girl LETG oldDev) :> cadets))}
>             _ -> putLayer l{elders=es} >> goUpAcc (e :> acc)

> goDown :: ProofState ()
> goDown = goDownAcc B0
>   where
>     goDownAcc :: Bwd Entry -> ProofState ()
>     goDownAcc acc = do
>         l@(Layer elders ref (e :> es) tip root) <- removeLayer
>         case e of
>             E newRef _ (Girl LETG newDev) -> do
>                 oldDev <- replaceDev newDev
>                 putLayer  l{elders=(elders:<E ref (lastName ref) (Girl LETG oldDev)) <+> acc,
>                               mother=newRef, cadets=es}
>             _ -> putLayer l{cadets=es} >> goDownAcc (acc :< e)


\subsubsection{Goal Search Commands}

To implement goal search, we need a few useful bits of kit...

The |untilA| operator runs its first argument one or more times until its second
argument succeeds, at which point it returns the result. If the first argument
fails, the whole operation fails.

> untilA :: Alternative f => f () -> f a -> f a
> g `untilA` test = g *> try
>     where try = test <|> (g *> try)

The |much| operator runs its argument until it fails, then returns the state of
its last success.

> much :: Alternative f => f () -> f ()
> much f = (f *> much f) <|> pure ()

The |isGoal| command succeeds (returning |()|) if the current location is a goal,
and fails (yielding |Nothing|) if not.

> isGoal :: ProofState ()
> isGoal = do
>     Unknown _ <- getDevTip
>     return ()

We can now compactly describe how to search the proof state for goals, by giving
several alternatives for where to go next and continuing until a goal is reached.

> prevStep :: ProofState ()
> prevStep = (goUp >> much goIn) <|> goOut

> prevGoal :: ProofState ()
> prevGoal = prevStep `untilA` isGoal

> nextStep :: ProofState ()
> nextStep = (goIn >> much goUp) <|> goDown <|> (goOut `untilA` goDown)

> nextGoal :: ProofState ()
> nextGoal = nextStep `untilA` isGoal


\subsubsection{Construction Commands}

The |make| command adds a named goal of the given type to the bottom of the
current development, after checking that the purported type is in fact a type.

> make :: (String :<: INTM) -> ProofState ()
> make (s:<:ty) = do
>     root <- getDevRoot
>     () <- lift (check (SET :>: ty) root)
>     let ty' = eval ty B0
>     n <- withRoot (flip name s)
>     putDevEntry (E (n := HOLE :<: ty') (last n) (Girl LETG 
>                                                  (B0, Unknown (ty :=>: ty'), room root s)))
>     putDevRoot (roos root)

The |piBoy| command checks that the current goal is of type SET, and that the supplied type
is also a set; if so, it appends a $\Pi$-abstraction to the current development.

> piBoy :: (String :<: INTM) -> ProofState ()
> piBoy (s:<:ty) = do
>     Unknown (_ :=>: SET) <- getDevTip     
>     root <- getDevRoot
>     () <- lift (check (SET :>: ty) root)
>     let ty' = eval ty B0
>     Root.freshRef (s :<: ty')
>         (\ref r -> putDevEntry (E ref (lastName ref) (Boy (PIB ty))) >> putDevRoot r) root

The |lambdaBoy| command checks that the current goal is a $\Pi$-type, and if so,
appends a $\lambda$-abstraction with the appropriate type to the current development.

> lambdaBoy :: String -> ProofState ()
> lambdaBoy x = do
>     Unknown (pi :=>: PI s t) <- getDevTip
>     root <- getDevRoot
>     Root.freshRef (x :<: s)
>         (\ref r -> do
>            putDevEntry (E ref (lastName ref) (Boy LAMB))
>            let tipTyv = t $$ A (N (P ref))
>            putDevTip (Unknown (bquote B0 tipTyv r :=>: tipTyv))
>            putDevRoot r
>          ) root

The |give| command checks the provided term has the goal type, and if so, fills in
the goal and updates the reference.

> give :: INTM -> ProofState ()
> give tm = do
>     Unknown (tipTyTm :=>: tipTy) <- getDevTip
>     root <- getDevRoot
>     () <- lift (check (tipTy :>: tm) root)
>     putDevTip (Defined tm (tipTyTm :=>: tipTy))
>     loc <- get
>     let aus = greatAuncles loc
>     sibs <- getDevEntries
>     let tm' = eval (parBind aus sibs tm) B0
>     name := _ :<: ty <- getMother
>     let ref = name := DEFN tm' :<: ty
>     putMother ref
>     updateRef ref
>     goOut


\subsection{Wire Service}

Here we describe how to handle updates to references in the proof state, caused by
refinement commands like |give|. The idea is to deal with updates lazily, to avoid
unnecessary traversals of the proof tree. When |updateRef| is called to announce
a changed reference (that the current development has already processed), it simply
inserts a news bulletin below the current development.

> updateRef :: REF -> ProofState ()
> updateRef ref = insertCadet (R [(ref, GoodNews)])

The |propagateNews| function takes a current news bulletin and a list of entries
to add to the current development. It applies the news bulletin to each entry
in turn, picking up other bulletins along the way. This function should be called
when navigating to a development that may contain news bulletins, so they can be
pushed out of sight.

> propagateNews :: NewsBulletin -> Fwd Entry -> ProofState ()

If there are no entries to process, we should stash the bulletin after the current
location (if the bulletin is non-empty) and stop. Note that the insertion is
optional because it will fail when we have reached the end of the module, at which
point everyone knows the news anyway.

> propagateNews []   F0         = return ()
> propagateNews news F0         = optional (insertCadet (R news)) >> return ()

\question{|LAMB|s and |Girl|s do not contain a term representation of their type, so
where can we get it from?}

> propagateNews news (e@(E (name := DECL :<: ty) sn (Boy LAMB)) :> es) = do
>     putDevEntry (E (name := DECL :<: ty) sn (Boy LAMB))
>     propagateNews news es

To update a |PIB|, we tell the news to its domain type. If the type changes, we update
the boy's reference and add the change to the bulletin.

> propagateNews news (e@(E (name := DECL :<: ty) sn (Boy (PIB s))) :> es) = do
>     case tellNews news s of
>         (_,   NoNews)    -> putDevEntry e >> propagateNews news es
>         (s',  GoodNews)  -> do
>             let ref = name := DECL :<: (eval s' B0)
>             putDevEntry (E ref sn (Boy (PIB s')))
>             propagateNews ((ref, GoodNews):news) es

Updating girls is a bit more complicated. First we have to check whether the tip type
needs to be updated, and re-evaluate it if necessary. 

> propagateNews news (e@(E (name := HOLE :<: ty) sn 
>   (Girl LETG (cs, Unknown (tipTy :=>: tipTyv), root))) :> es) = case tellNews news tipTy of
>     (_,      NoNews)    -> putDevEntry e >> propagateNews news es
>     (tipTy', GoodNews)  -> do
>         putDevEntry (E (name := HOLE :<: ty) sn 
>             (Girl LETG (cs, Unknown (tipTy' :=>: eval tipTy' B0), root)))

> propagateNews news (e@(E (name := DEFN v :<: ty) sn 
>   (Girl LETG (cs, Defined tm (tipTy :=>: tipTyv), root))) :> es) = do
>     let  tt = case tellNews news tipTy of
>             (_,       NoNews)    -> tipTy :=>: tipTyv
>             (tipTy',  GoodNews)  -> tipTy' :=>: eval tipTy' B0
>          (tm', v') = case tellNews news tm of
>             (_ ,   NoNews)    -> (tm, v)
>             (tm',  GoodNews)  -> (tm', eval tm' B0)
>     putDevEntry (E (name := DEFN v' :<: ty) sn (Girl LETG (cs, Defined tm' tt, root)))
>     goIn
>     es' <- getDevEntries
>     putDevEntries B0
>     propagateNews news (es' <>> F0)
>     goOut
>     propagateNews news es

Finally, if we encounter an older news bulletin when propagating news, we can simply
merge the two together.

> propagateNews news (R oldNews :> es) = propagateNews (mergeNews oldNews news) es


The |tellNews| function applies a bulletin to a term. It returns the updated
term and the news about it.

> tellNews :: NewsBulletin -> Tm {d, TT} REF -> (Tm {d, TT} REF, News)
> tellNews []    tm = (tm, NoNews)
> tellNews news  tm = case foldMap (lookupNews news) tm of
>     NoNews  -> (tm, NoNews)
>     n       -> (fmap (getLatest news) tm, n)




\subsection{Command-Line Interface}

Here we have a very basic command-driven interface to the proof state monad.

> cochon :: ProofContext -> IO ()
> cochon loc@(ls, dev) = do
>     printDev dev
>     putStr (showPrompt ls)
>     l <- getLine
>     let ws = words l
>     if (head ws == "quit")
>         then return ()
>         else case runStateT (elabParse ws) loc of
>             Just (s, loc') -> do
>                 putStrLn s 
>                 printChanges (auncles loc) (auncles loc')
>                 cochon loc'
>             Nothing ->  putStrLn "I'm sorry, Dave. I'm afraid I can't do that."
>                         >> cochon loc

> elabParse :: [String] -> ProofState String
> elabParse ("in":_)       = goIn         >> return "Going in..."
> elabParse ("out":_)      = goOut        >> return "Going out..."
> elabParse ("up":_)       = goUp         >> return "Going up..."
> elabParse ("down":_)     = goDown       >> return "Going down..."
> elabParse ("top":_)      = much goUp    >> return "Going to top..."
> elabParse ("bottom":_)   = much goDown  >> return "Going to bottom..."
> elabParse ("module":_)     = much goOut   >> return "Going to module..."
> elabParse ("prev":_)     = prevGoal     >> return "Searching for previous goal..."
> elabParse ("next":_)     = nextGoal     >> return "Searching for next goal..."

> elabParse ("make":x:":":tss)   = do
>     c <- get
>     ty <- lift (parseTerm (unwords tss) (auncles c))
>     make (x :<: ty)
>     goIn
>     return "Appended goal!"

> elabParse ("pi":x:":":tss) = do
>     c <- get
>     ty <- lift (parseTerm (unwords tss) (auncles c))
>     piBoy (x :<: ty)
>     return "Made pi boy!"

> elabParse ("lambda":x:_) = do
>     lambdaBoy x
>     return "Made lambda boy!"

> elabParse ("give":tss) = do
>     c <- get
>     tm <- lift (parseTerm (unwords tss) (auncles c))
>     give tm
>     return "Thank you."

> elabParse ("dump":_)     = do
>     c <- get
>     trace (show c) $ return "Done."
> elabParse ("auncles":_)  = get >>= return . showEntries . (<>> F0) . auncles
> elabParse _ = return "???"

> showPrompt :: Bwd Layer -> String
> showPrompt (_ :< Layer _ (n := _) _ _ _)  = prettyName n ++ " > "
> showPrompt B0        = "> "

> printChanges :: Bwd Entry -> Bwd Entry -> IO ()
> printChanges as bs | as /= bs = do
>     let (lost, gained)  = trace ("diff (" ++ showEntries (as <>> F0) ++ ") (" ++ showEntries (bs <>> F0) ++ ")") $ diff (as <>> F0) (bs <>> F0)
>     if lost /= F0
>         then putStrLn ("Left scope: " ++ showEntries lost)
>         else putStrLn "Nothing went out of scope."
>     if gained /= F0
>        then putStrLn ("Entered scope: " ++ showEntries gained)
>        else putStrLn "Nothing came into scope."
> printChanges _ _ = return ()

> diff :: (Eq a, Show a) => Fwd a -> Fwd a -> (Fwd a, Fwd a)
> diff (x :> xs) (y :> ys)
>     | x == y     = diff xs ys
>     | otherwise  = (x :> xs, y :> ys)
> diff xs ys = (xs, ys)

> showEntries :: Fwd Entry -> String
> showEntries = foldMap (\e -> case e of (E ref _ _) -> show (prettyRef B0 ref) ++ ", "
>                                        (R news) -> "News: " ++ show news)


\section{Elab Monad}

> data Elab x
>   = Bale x
>   | Cry
>   | Hope
>   | EDef String INTM (Elab INTM) (VAL -> Elab x)
>   | ELam String (VAL -> Elab x)
>   | EPi String INTM (VAL -> Elab x)

> instance Monad Elab where
>   return = Bale
>   Bale x        >>= k = k x
>   Cry           >>= k = Cry
>   Hope          >>= k = Hope
>   EDef x y d f  >>= k = EDef x y d ((k =<<) . f)
>   ELam x f      >>= k = ELam x ((k =<<) . f)
>   EPi x y f     >>= k = EPi x y ((k =<<) . f)
>
> instance Functor Elab where
>   fmap = ap . return
>
> instance Applicative Elab where
>   pure = return
>   (<*>) = ap
