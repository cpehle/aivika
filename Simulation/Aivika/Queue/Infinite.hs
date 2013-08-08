
-- |
-- Module     : Simulation.Aivika.Queue.Infinite
-- Copyright  : Copyright (c) 2009-2013, David Sorokin <david.sorokin@gmail.com>
-- License    : OtherLicense
-- Maintainer : David Sorokin <david.sorokin@gmail.com>
-- Stability  : experimental
-- Tested with: GHC 7.6.3
--
-- This module defines an infinite queue that can use the specified strategies.
--
module Simulation.Aivika.Queue.Infinite
       (-- * Queue Types
        FCFSQueue,
        LCFSQueue,
        SIROQueue,
        PriorityQueue,
        Queue,
        -- * Creating Queue
        newFCFSQueue,
        newLCFSQueue,
        newSIROQueue,
        newPriorityQueue,
        newQueue,
        -- * Queue Properties and Activities
        queueNull,
        queueStoringStrategy,
        queueOutputStrategy,
        queueCount,
        queueStoreCount,
        queueOutputCount,
        queueStoreRate,
        queueOutputRate,
        queueWaitTime,
        queueOutputWaitTime,
        -- * Dequeuing and Enqueuing
        dequeue,
        dequeueWithOutputPriority,
        tryDequeue,
        enqueue,
        enqueueWithStoringPriority,
        -- * Processing Queue
        queueProcessor,
        queueProcessorLoop,
        -- * Signals
        enqueueStored,
        dequeueRequested,
        dequeueExtracted) where

import Data.IORef
import Data.Monoid

import Control.Monad
import Control.Monad.Trans

import Simulation.Aivika.Internal.Simulation
import Simulation.Aivika.Internal.Dynamics
import Simulation.Aivika.Internal.Event
import Simulation.Aivika.Internal.Process
import Simulation.Aivika.Internal.Signal
import Simulation.Aivika.Internal.Observable
import Simulation.Aivika.Signal
import Simulation.Aivika.Resource
import Simulation.Aivika.QueueStrategy
import Simulation.Aivika.Statistics
import Simulation.Aivika.Stream
import Simulation.Aivika.Processor

import qualified Simulation.Aivika.DoubleLinkedList as DLL 
import qualified Simulation.Aivika.Vector as V
import qualified Simulation.Aivika.PriorityQueue as PQ

-- | A type synonym for the ordinary FIFO queue also known as the FCFS
-- (First Come - First Serviced) queue.
type FCFSQueue a =
  Queue FCFS DLL.DoubleLinkedList FCFS DLL.DoubleLinkedList a

-- | A type synonym for the ordinary LIFO queue also known as the LCFS
-- (Last Come - First Serviced) queue.
type LCFSQueue a =
  Queue LCFS DLL.DoubleLinkedList FCFS DLL.DoubleLinkedList a

-- | A type synonym for the SIRO (Serviced in Random Order) queue.
type SIROQueue a =
  Queue SIRO V.Vector FCFS DLL.DoubleLinkedList a

-- | A type synonym for the queue with static priorities applied when
-- storing the elements in the queue.
type PriorityQueue a =
  Queue StaticPriorities PQ.PriorityQueue FCFS DLL.DoubleLinkedList a

-- | Represents the infinite queue using the specified strategies for
-- internal storing (in memory) @sm@ and output @so@, where @a@ denotes
-- the type of items stored in the queue. Types @qm@ and @qo@ are
-- determined automatically and you should not care about them - they
-- are dependent types.
data Queue sm qm so qo a =
  Queue { queueStoringStrategy :: sm,
          -- ^ The strategy applied when storing (in memory) items in the queue.
          queueOutputStrategy :: so,
          -- ^ The strategy applied to the output (dequeuing) process.
          queueStore :: qm (QueueItem a),
          queueOutputRes :: Resource so qo,
          queueCountRef :: IORef Int,
          queueStoreCountRef :: IORef Int,
          queueOutputCountRef :: IORef Int,
          queueWaitTimeRef :: IORef (SamplingStats Double),
          queueOutputWaitTimeRef :: IORef (SamplingStats Double),
          enqueueStoredSource :: SignalSource a,
          dequeueRequestedSource :: SignalSource (),
          dequeueExtractedSource :: SignalSource a }

-- | Stores the item and a time of its enqueuing. 
data QueueItem a =
  QueueItem { itemValue :: a,
              -- ^ Return the item value.
              itemStoringTime :: Double
              -- ^ Return the time of storing in the queue.
            }
  
-- | Create a new infinite FCFS queue.  
newFCFSQueue :: Simulation (FCFSQueue a)  
newFCFSQueue = newQueue FCFS FCFS
  
-- | Create a new infinite LCFS queue.  
newLCFSQueue :: Simulation (LCFSQueue a)  
newLCFSQueue = newQueue LCFS FCFS
  
-- | Create a new infinite SIRO queue.  
newSIROQueue :: Simulation (SIROQueue a)  
newSIROQueue = newQueue SIRO FCFS
  
-- | Create a new infinite priority queue.  
newPriorityQueue :: Simulation (PriorityQueue a)  
newPriorityQueue = newQueue StaticPriorities FCFS
  
-- | Create a new infinite queue with the specified strategies.  
newQueue :: (QueueStrategy sm qm,
             QueueStrategy so qo) =>
            sm
            -- ^ the strategy applied when storing items in the queue
            -> so
            -- ^ the strategy applied to the output (dequeuing) process
            -> Simulation (Queue sm qm so qo a)  
newQueue sm so =
  do i  <- liftIO $ newIORef 0
     cm <- liftIO $ newIORef 0
     co <- liftIO $ newIORef 0
     qm <- newStrategyQueue sm
     ro <- newResourceWithMaxCount so 0 Nothing
     w  <- liftIO $ newIORef mempty
     wo <- liftIO $ newIORef mempty 
     s3 <- newSignalSource
     s4 <- newSignalSource
     s5 <- newSignalSource
     return Queue { queueStoringStrategy = sm,
                    queueOutputStrategy = so,
                    queueStore = qm,
                    queueOutputRes = ro,
                    queueCountRef = i,
                    queueStoreCountRef = cm,
                    queueOutputCountRef = co,
                    queueWaitTimeRef = w,
                    queueOutputWaitTimeRef = wo,
                    enqueueStoredSource = s3,
                    dequeueRequestedSource = s4,
                    dequeueExtractedSource = s5 }
  
-- | Test whether the queue is empty.
queueNull :: Queue sm qm so qo a -> Event Bool
queueNull q =
  Event $ \p ->
  do n <- readIORef (queueCountRef q)
     return (n == 0)

-- | Return the queue size.
queueCount :: Queue sm qm so qo a -> Observable Int
queueCount q =
  let read = Event $ \p -> readIORef (queueCountRef q)
  in Observable { readObservable = read,
                  observableChanged_ =
                    mapSignal (const ()) (enqueueStored q) <>
                    mapSignal (const ()) (dequeueExtracted q) }
  
-- | Return the total number of input items that were stored.
queueStoreCount :: Queue sm qm so qo a -> Observable Int
queueStoreCount q =
  let read = Event $ \p -> readIORef (queueStoreCountRef q)
  in Observable { readObservable = read,
                  observableChanged_ =
                    mapSignal (const ()) (enqueueStored q) }
      
-- | Return the total number of output items that were dequeued.
queueOutputCount :: Queue sm qm so qo a -> Observable Int
queueOutputCount q =
  let read = Event $ \p -> readIORef (queueOutputCountRef q)
  in Observable { readObservable = read,
                  observableChanged_ =
                    mapSignal (const ()) (dequeueExtracted q) }

-- | Return the rate of the items that were stored: how many items
-- per time.
queueStoreRate :: Queue sm qm so qo a -> Event Double
queueStoreRate q =
  Event $ \p ->
  do x <- readIORef (queueStoreCountRef q)
     t <- invokeDynamics p $ time
     return (fromIntegral x / t)
      
-- | Return the rate of the output items that were dequeued: how many items
-- per time.
queueOutputRate :: Queue sm qm so qo a -> Event Double
queueOutputRate q =
  Event $ \p ->
  do x <- readIORef (queueOutputCountRef q)
     t <- invokeDynamics p $ time
     return (fromIntegral x / t)
      
-- | Return the wait time from the time at which the item was stored in the queue to
-- the time at which it was dequeued.
queueWaitTime :: Queue sm qm so qo a -> Observable (SamplingStats Double)
queueWaitTime q =
  let read = Event $ \p -> readIORef (queueWaitTimeRef q)
  in Observable { readObservable = read,
                  observableChanged_ =
                    mapSignal (const ()) (dequeueExtracted q) }
      
-- | Return the output wait time from the time at which the item was requested
-- for dequeuing to the time at which it was actually dequeued.
queueOutputWaitTime :: Queue sm qm so qo a -> Observable (SamplingStats Double)
queueOutputWaitTime q =
  let read = Event $ \p -> readIORef (queueOutputWaitTimeRef q)
  in Observable { readObservable = read,
                  observableChanged_ =
                    mapSignal (const ()) (dequeueExtracted q) }
  
-- | Dequeue suspending the process if the queue is empty.
dequeue :: (DequeueStrategy sm qm,
            EnqueueStrategy so qo)
           => Queue sm qm so qo a
           -- ^ the queue
           -> Process a
           -- ^ the dequeued value
dequeue q =
  do t <- liftEvent $ dequeueRequest q
     requestResource (queueOutputRes q)
     liftEvent $ dequeueExtract q t
  
-- | Dequeue with the output priority suspending the process if the queue is empty.
dequeueWithOutputPriority :: (DequeueStrategy sm qm,
                              PriorityQueueStrategy so qo po)
                             => Queue sm qm so qo a
                             -- ^ the queue
                             -> po
                             -- ^ the priority for output
                             -> Process a
                             -- ^ the dequeued value
dequeueWithOutputPriority q po =
  do t <- liftEvent $ dequeueRequest q
     requestResourceWithPriority (queueOutputRes q) po
     liftEvent $ dequeueExtract q t
  
-- | Try to dequeue immediately.
tryDequeue :: DequeueStrategy sm qm
              => Queue sm qm so qo a
              -- ^ the queue
              -> Event (Maybe a)
              -- ^ the dequeued value of 'Nothing'
tryDequeue q =
  do x <- tryRequestResourceWithinEvent (queueOutputRes q)
     if x 
       then do t <- dequeueRequest q
               fmap Just $ dequeueExtract q t
       else return Nothing

-- | Enqueue the item.  
enqueue :: (EnqueueStrategy sm qm,
            DequeueStrategy so qo)
           => Queue sm qm so qo a
           -- ^ the queue
           -> a
           -- ^ the item to enqueue
           -> Event ()
enqueue = enqueueStore
     
-- | Enqueue with the storing priority the item.  
enqueueWithStoringPriority :: (PriorityQueueStrategy sm qm pm,
                               DequeueStrategy so qo)
                              => Queue sm qm so qo a
                              -- ^ the queue
                              -> pm
                              -- ^ the priority for storing
                              -> a
                              -- ^ the item to enqueue
                              -> Event ()
enqueueWithStoringPriority = enqueueStoreWithPriority

-- | Return a signal that notifies when the enqueued item
-- is stored in the internal memory of the queue.
enqueueStored :: Queue sm qm so qo a -> Signal a
enqueueStored q = publishSignal (enqueueStoredSource q)

-- | Return a signal that notifies when the dequeuing operation was requested.
dequeueRequested :: Queue sm qm so qo a -> Signal ()
dequeueRequested q = publishSignal (dequeueRequestedSource q)

-- | Return a signal that notifies when the item was extracted from the internal
-- storage of the queue and prepared for immediate receiving by the dequeuing process.
dequeueExtracted :: Queue sm qm so qo a -> Signal a
dequeueExtracted q = publishSignal (dequeueExtractedSource q)

-- | Store the item.
enqueueStore :: (EnqueueStrategy sm qm,
                 DequeueStrategy so qo)
                => Queue sm qm so qo a
                -- ^ the queue
                -> a
                -- ^ the item to be stored
                -> Event ()
enqueueStore q a =
  Event $ \p ->
  do t <- invokeDynamics p time
     let i = QueueItem { itemValue = a,
                         itemStoringTime = t }
     invokeEvent p $
       strategyEnqueue (queueStoringStrategy q) (queueStore q) i
     modifyIORef (queueCountRef q) (+ 1)
     modifyIORef (queueStoreCountRef q) (+ 1)
     invokeEvent p $
       releaseResourceWithinEvent (queueOutputRes q)
     invokeEvent p $
       triggerSignal (enqueueStoredSource q) (itemValue i)

-- | Store with the priority the item.
enqueueStoreWithPriority :: (PriorityQueueStrategy sm qm pm,
                             DequeueStrategy so qo)
                            => Queue sm qm so qo a
                            -- ^ the queue
                            -> pm
                            -- ^ the priority for storing
                            -> a
                            -- ^ the item to be enqueued
                            -> Event ()
enqueueStoreWithPriority q pm a =
  Event $ \p ->
  do t <- invokeDynamics p time
     let i = QueueItem { itemValue = a,
                         itemStoringTime = t }
     invokeEvent p $
       strategyEnqueueWithPriority (queueStoringStrategy q) (queueStore q) pm i
     modifyIORef (queueCountRef q) (+ 1)
     modifyIORef (queueStoreCountRef q) (+ 1)
     invokeEvent p $
       releaseResourceWithinEvent (queueOutputRes q)
     invokeEvent p $
       triggerSignal (enqueueStoredSource q) (itemValue i)

-- | Accept the dequeuing request and return the current simulation time.
dequeueRequest :: Queue sm qm so qo a
                 -- ^ the queue
                 -> Event Double
                 -- ^ the current time
dequeueRequest q =
  Event $ \p ->
  do invokeEvent p $
       triggerSignal (dequeueRequestedSource q) ()
     invokeDynamics p time 

-- | Extract an item for the dequeuing request.  
dequeueExtract :: DequeueStrategy sm qm
                  => Queue sm qm so qo a
                  -- ^ the queue
                  -> Double
                  -- ^ the time of the dequeuing request
                  -> Event a
                  -- ^ the dequeued value
dequeueExtract q t' =
  Event $ \p ->
  do i <- invokeEvent p $
          strategyDequeue (queueStoringStrategy q) (queueStore q)
     modifyIORef (queueCountRef q) (+ (- 1))
     modifyIORef (queueOutputCountRef q) (+ 1)
     invokeEvent p $
       dequeueStat q t' i
     invokeEvent p $
       triggerSignal (dequeueExtractedSource q) (itemValue i)
     return $ itemValue i

-- | Update the statistics for the output wait time of the dequeuing operation
-- and the wait time of storing in the queue.
dequeueStat :: Queue sm qm so qo a
               -- ^ the queue
               -> Double
               -- ^ the time of the dequeuing request
               -> QueueItem a
               -- ^ the item and its input time
               -> Event ()
               -- ^ the action of updating the statistics
dequeueStat q t' i =
  Event $ \p ->
  do let t1 = itemStoringTime i
     t <- invokeDynamics p time
     modifyIORef (queueOutputWaitTimeRef q) $
       addSamplingStats (t - t')
     modifyIORef (queueWaitTimeRef q) $
       addSamplingStats (t - t1)

-- | Return a processor for the queue that does not use priorities.
--
-- The function has the following definition:
--
-- @
-- queueProcessor q =
--   let consume a =
--         liftEvent $ enqueue q a
--   in bufferProcessor
--      (consumeStream consume)
--      (repeatProcess $ dequeue q)
-- @
--
-- In the same manner you can create a processor for the priority queue applying
-- the 'bufferProcessor' function, only it will require more glueing code using
-- the 'mapStreamM', 'zipStreamSeq' or 'zipStreamParallel' combinators
-- to include the stream or several streams of priorities in the resulting computation.
-- There are no predefined processors for the priority queues but such functions
-- can be easily created. The current function is just the most common use case.
queueProcessor :: (EnqueueStrategy sm qm,
                   EnqueueStrategy so qo)
                  => Queue sm qm so qo a
                  -- ^ the queue that is used for storing items
                  -> Processor a a
                  -- ^ the buffer processor that uses the queue to store the items
queueProcessor q =
  let consume a =
        liftEvent $ enqueue q a
  in bufferProcessor
     (consumeStream consume)
     (repeatProcess $ dequeue q)

-- | Like 'queueProcessor' but allows creating a loop when some items
-- can be returned for processing them again.
--
-- The function calls 'bufferProcessorLoop' and it has the following definition:
--
-- @
-- queueProcessorLoop q =
--   let consume a =
--         liftEvent $ enqueue q a
--   in bufferProcessorLoop
--      (\\as cs ->
--        consumeStream consume $
--        mergeStreams as cs)
--      (repeatProcess $ dequeue q)
-- @
--
-- Note that here stream @as@ is considered first, while stream @cs@ is considered
-- last when consuming data. You can redefine it if needed.
--
-- Finally, the priority queues can be treated in the same manner. Only it will require
-- more glueing code.
queueProcessorLoop :: (EnqueueStrategy sm qm,
                       EnqueueStrategy so qo)
                      => Queue sm qm so qo a
                      -- ^ the queue that is used for storing items
                      -> Processor a (Either a b)
                      -- ^ processs and then decide what values of type @a@
                      -- should be redirected to the queue again
                      -> Processor a b
queueProcessorLoop q =
  let consume a =
        liftEvent $ enqueue q a
  in bufferProcessorLoop
     (\as cs ->
       consumeStream consume $
       mergeStreams as cs)
     (repeatProcess $ dequeue q)
