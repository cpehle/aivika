
{-# LANGUAGE TypeFamilies, RankNTypes, FlexibleInstances #-}

-- |
-- Module     : Simulation.Aivika.Trans.ProtoRef
-- Copyright  : Copyright (c) 2009-2014, David Sorokin <david.sorokin@gmail.com>
-- License    : BSD3
-- Maintainer : David Sorokin <david.sorokin@gmail.com>
-- Stability  : experimental
-- Tested with: GHC 7.8.3
--
-- It defines a prototype of all mutable references.
--
module Simulation.Aivika.Trans.ProtoRef
       (ProtoReferring(..),
        ProtoRef(..)) where

import Data.IORef

import Simulation.Aivika.Trans.Session

-- | A monad within which computation we can create and work with
-- the prototype of mutable reference.
class Monad m => ProtoReferring m where
  
  -- | A prototype of mutable reference.
  data ProtoRefT m :: * -> *

  -- | Create a new ptototype of mutable reference by the specified session and initial value.
  newProtoRef :: SessionT m -> a -> m (ProtoRefT m a)

  -- | Read the contents of the prototype of mutable reference.
  readProtoRef :: ProtoRefT m a -> m a

  -- | Write a new value in the prototype of mutable reference.
  writeProtoRef :: ProtoRefT m a -> a -> m ()

  -- | Modify a value stored in the prototype of mutable reference.
  modifyProtoRef :: ProtoRefT m a -> (a -> a) -> m ()

  -- | Whether two prototypes of mutable references are equal.
  equalProtoRef :: ProtoRefT m a -> ProtoRefT m a -> Bool

instance ProtoReferring IO where

  newtype ProtoRefT IO a = ProtoRef (IORef a)

  {-# SPECIALIZE INLINE newProtoRef :: Session -> a -> IO (ProtoRef a) #-}
  newProtoRef session a = fmap ProtoRef $ newIORef a

  {-# SPECIALIZE INLINE readProtoRef :: ProtoRef a -> IO a #-}
  readProtoRef (ProtoRef x) = readIORef x

  {-# SPECIALIZE INLINE writeProtoRef :: ProtoRef a -> a -> IO () #-}
  writeProtoRef (ProtoRef x) = writeIORef x

  {-# SPECIALIZE INLINE modifyProtoRef :: ProtoRef a -> (a -> a) -> IO () #-}
  modifyProtoRef (ProtoRef x) = modifyIORef x

  {-# SPECIALIZE INLINE equalProtoRef :: ProtoRef a -> ProtoRef a -> Bool #-}
  equalProtoRef (ProtoRef x) (ProtoRef y) = x == y

-- | A conventient type synonym.
type ProtoRef = ProtoRefT IO

instance ProtoReferring m => Eq (ProtoRefT m a) where

  {-# INLINE (==) #-}
  (==) = equalProtoRef
