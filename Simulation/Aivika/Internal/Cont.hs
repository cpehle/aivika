
-- |
-- Module     : Simulation.Aivika.Internal.Cont
-- Copyright  : Copyright (c) 2009-2013, David Sorokin <david.sorokin@gmail.com>
-- License    : BSD3
-- Maintainer : David Sorokin <david.sorokin@gmail.com>
-- Stability  : experimental
-- Tested with: GHC 7.6.3
--
-- The 'Cont' monad is a variation of the standard Cont monad 
-- and F# async workflow, where the result of applying 
-- the continuations is the 'Event' computation.
--
module Simulation.Aivika.Internal.Cont
       (Cont(..),
        ContParams,
        invokeCont,
        runCont,
        catchCont,
        finallyCont,
        throwCont,
        resumeCont,
        contCancelled) where

import Data.IORef

import qualified Control.Exception as C
import Control.Exception (IOException, throw)

import Control.Monad
import Control.Monad.Trans

import Simulation.Aivika.Internal.Specs
import Simulation.Aivika.Internal.Simulation
import Simulation.Aivika.Internal.Dynamics
import Simulation.Aivika.Internal.Event

-- | The 'Cont' type is similar to the standard Cont monad 
-- and F# async workflow but only the result of applying
-- the continuations return the 'Event' computation.
newtype Cont a = Cont (ContParams a -> Event ())

-- | The continuation parameters.
data ContParams a = 
  ContParams { contCont :: a -> Event (), 
               contAux  :: ContParamsAux }

-- | The auxiliary continuation parameters.
data ContParamsAux =
  ContParamsAux { contECont :: IOException -> Event (),
                  contCCont :: () -> Event (),
                  contCancelRef :: IORef Bool,
                  contCatchFlag   :: Bool }

instance Monad Cont where
  return  = returnC
  m >>= k = bindC m k

instance SimulationLift Cont where
  liftSimulation = liftSC

instance DynamicsLift Cont where
  liftDynamics = liftDC

instance EventLift Cont where
  liftEvent = liftEC

instance Functor Cont where
  fmap = liftM

instance MonadIO Cont where
  liftIO = liftIOC 

invokeCont :: ContParams a -> Cont a -> Event ()
{-# INLINE invokeCont #-}
invokeCont p (Cont m) = m p

cancelCont :: Point -> ContParams a -> IO ()
{-# NOINLINE cancelCont #-}
cancelCont p c =
  do writeIORef (contCancelRef $ contAux c) False
     invokeEvent p $ (contCCont $ contAux c) ()

returnC :: a -> Cont a
{-# INLINE returnC #-}
returnC a = 
  Cont $ \c ->
  Event $ \p ->
  do z <- contCancelled c
     if z 
       then cancelCont p c
       else invokeEvent p $ contCont c a
                          
-- bindC :: Cont a -> (a -> Cont b) -> Cont b
-- {-# INLINE bindC #-}
-- bindC m k = 
--   Cont $ \c -> 
--   if (contCatchFlag . contAux $ c) 
--   then bindWithCatch m k c
--   else bindWithoutCatch m k c
  
bindC :: Cont a -> (a -> Cont b) -> Cont b
{-# INLINE bindC #-}
bindC m k = 
  Cont $ bindWithoutCatch m k  -- Another version is not tail recursive!
  
bindWithoutCatch :: Cont a -> (a -> Cont b) -> ContParams b -> Event ()
{-# INLINE bindWithoutCatch #-}
bindWithoutCatch (Cont m) k c = 
  Event $ \p ->
  do z <- contCancelled c
     if z 
       then cancelCont p c
       else invokeEvent p $ m $ 
            let cont a = invokeCont c (k a)
            in c { contCont = cont }

-- It is not tail recursive!
bindWithCatch :: Cont a -> (a -> Cont b) -> ContParams b -> Event ()
{-# NOINLINE bindWithCatch #-}
bindWithCatch (Cont m) k c = 
  Event $ \p ->
  do z <- contCancelled c
     if z 
       then cancelCont p c
       else invokeEvent p $ m $ 
            let cont a = catchEvent 
                         (invokeCont c (k a))
                         (contECont $ contAux c)
            in c { contCont = cont }

-- Like "bindWithoutCatch (return a) k"
callWithoutCatch :: (a -> Cont b) -> a -> ContParams b -> Event ()
callWithoutCatch k a c =
  Event $ \p ->
  do z <- contCancelled c
     if z 
       then cancelCont p c
       else invokeEvent p $ invokeCont c (k a)

-- Like "bindWithCatch (return a) k" but it is not tail recursive!
callWithCatch :: (a -> Cont b) -> a -> ContParams b -> Event ()
callWithCatch k a c =
  Event $ \p ->
  do z <- contCancelled c
     if z 
       then cancelCont p c
       else invokeEvent p $ catchEvent 
            (invokeCont c (k a))
            (contECont $ contAux c)

-- | Exception handling within 'Cont' computations.
catchCont :: Cont a -> (IOException -> Cont a) -> Cont a
catchCont m h = 
  Cont $ \c -> 
  if contCatchFlag . contAux $ c
  then catchWithCatch m h c
  else error $
       "To catch exceptions, the process must be created " ++
       "with help of newProcessIDWithCatch: catchCont."
  
catchWithCatch :: Cont a -> (IOException -> Cont a) -> ContParams a -> Event ()
catchWithCatch (Cont m) h c =
  Event $ \p -> 
  do z <- contCancelled c
     if z 
       then cancelCont p c
       else invokeEvent p $ m $
            -- let econt e = callWithCatch h e c   -- not tail recursive!
            let econt e = callWithoutCatch h e c
            in c { contAux = (contAux c) { contECont = econt } }
               
-- | A computation with finalization part.
finallyCont :: Cont a -> Cont b -> Cont a
finallyCont m m' = 
  Cont $ \c -> 
  if contCatchFlag . contAux $ c
  then finallyWithCatch m m' c
  else error $
       "To finalize computation, the process must be created " ++
       "with help of newProcessIdWithCatch: finallyCont."
  
finallyWithCatch :: Cont a -> Cont b -> ContParams a -> Event ()               
finallyWithCatch (Cont m) (Cont m') c =
  Event $ \p ->
  do z <- contCancelled c
     if z 
       then cancelCont p c
       else invokeEvent p $ m $
            let cont a   = 
                  Event $ \p ->
                  invokeEvent p $ m' $
                  let cont b = contCont c a
                  in c { contCont = cont }
                econt e  =
                  Event $ \p ->
                  invokeEvent p $ m' $
                  let cont b = (contECont . contAux $ c) e
                  in c { contCont = cont }
                ccont () = 
                  Event $ \p ->
                  invokeEvent p $ m' $
                  let cont b  = (contCCont . contAux $ c) ()
                      econt e = (contCCont . contAux $ c) ()
                  in c { contCont = cont,
                         contAux  = (contAux c) { contECont = econt } }
            in c { contCont = cont,
                   contAux  = (contAux c) { contECont = econt,
                                            contCCont = ccont } }

-- | Throw the exception with the further exception handling.
-- By some reasons, the standard 'throw' function per se is not handled 
-- properly within 'Cont' computations, altough it will be still handled 
-- if it will be hidden under the 'liftIO' function. The problem arises 
-- namely with the @throw@ function, not 'IO' computations.
throwCont :: IOException -> Cont a
throwCont e = liftIO $ throw e

-- | Run the 'Cont' computation with the specified cancelation token 
-- and flag indicating whether to catch exceptions.
runCont :: Cont a ->
           -- ^ the computation to run
           (a -> Event ()) ->
           -- ^ the main branch 
           (IOError -> Event ()) ->
           -- ^ the branch for handing exceptions
           (() -> Event ()) ->
           -- ^ the branch for cancellation
           IORef Bool ->
           -- ^ the cancellation token
           Bool ->
           -- ^ whether to support the exception catching
           Event ()
runCont (Cont m) cont econt ccont cancelRef catchFlag = 
  m ContParams { contCont = cont,
                 contAux  = 
                   ContParamsAux { contECont = econt,
                                   contCCont = ccont,
                                   contCancelRef = cancelRef, 
                                   contCatchFlag = catchFlag } }

-- | Lift the 'Simulation' computation.
liftSC :: Simulation a -> Cont a
liftSC (Simulation m) = 
  Cont $ \c ->
  Event $ \p ->
  if contCatchFlag . contAux $ c
  then liftIOWithCatch (m $ pointRun p) p c
  else liftIOWithoutCatch (m $ pointRun p) p c
     
-- | Lift the 'Dynamics' computation.
liftDC :: Dynamics a -> Cont a
liftDC (Dynamics m) =
  Cont $ \c ->
  Event $ \p ->
  if contCatchFlag . contAux $ c
  then liftIOWithCatch (m p) p c
  else liftIOWithoutCatch (m p) p c
     
-- | Lift the 'Event' computation.
liftEC :: Event a -> Cont a
liftEC (Event m) =
  Cont $ \c ->
  Event $ \p ->
  if contCatchFlag . contAux $ c
  then liftIOWithCatch (m p) p c
  else liftIOWithoutCatch (m p) p c
     
-- | Lift the IO computation.
liftIOC :: IO a -> Cont a
liftIOC m =
  Cont $ \c ->
  Event $ \p ->
  if contCatchFlag . contAux $ c
  then liftIOWithCatch m p c
  else liftIOWithoutCatch m p c
  
liftIOWithoutCatch :: IO a -> Point -> ContParams a -> IO ()
{-# INLINE liftIOWithoutCatch #-}
liftIOWithoutCatch m p c =
  do z <- contCancelled c
     if z
       then cancelCont p c
       else do a <- m
               invokeEvent p $ contCont c a

liftIOWithCatch :: IO a -> Point -> ContParams a -> IO ()
{-# NOINLINE liftIOWithCatch #-}
liftIOWithCatch m p c =
  do z <- contCancelled c
     if z
       then cancelCont p c
       else do aref <- newIORef undefined
               eref <- newIORef Nothing
               C.catch (m >>= writeIORef aref) 
                 (writeIORef eref . Just)
               e <- readIORef eref
               case e of
                 Nothing -> 
                   do a <- readIORef aref
                      -- tail recursive
                      invokeEvent p $ contCont c a
                 Just e ->
                   -- tail recursive
                   invokeEvent p $ (contECont . contAux) c e

-- | Resume the computation by the specified parameters.
resumeCont :: ContParams a -> a -> Event ()
{-# INLINE resumeCont #-}
resumeCont c a = 
  Event $ \p ->
  do z <- contCancelled c
     if z
       then cancelCont p c
       else invokeEvent p $ contCont c a

-- | Test whether the computation is canceled
contCancelled :: ContParams a -> IO Bool
{-# INLINE contCancelled #-}
contCancelled c = readIORef $ contCancelRef $ contAux c