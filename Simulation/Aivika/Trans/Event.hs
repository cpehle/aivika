
-- |
-- Module     : Simulation.Aivika.Trans.Event
-- Copyright  : Copyright (c) 2009-2014, David Sorokin <david.sorokin@gmail.com>
-- License    : BSD3
-- Maintainer : David Sorokin <david.sorokin@gmail.com>
-- Stability  : experimental
-- Tested with: GHC 7.8.3
--
-- The module defines the 'Event' monad which is very similar to the 'Dynamics'
-- monad but only now the computation is strongly synchronized with the event queue.
--
module Simulation.Aivika.Trans.Event
       (-- * Event Monad
        EventT,
        Event,
        EventLift(..),
        EventProcessing(..),
        runEventInStartTime,
        runEventInStopTime,
        -- * Event Queue
        EventQueueable(..),
        EventQueueing(..),
        enqueueEventWithCancellation,
        enqueueEventWithTimes,
        enqueueEventWithIntegTimes,
        yieldEvent,
        -- * Cancelling Event
        EventTCancellation,
        EventCancellation,
        cancelEvent,
        eventCancelled,
        eventFinished,
        -- * Error Handling
        catchEvent,
        finallyEvent,
        throwEvent,
        -- * Memoization
        memoEvent,
        memoEventInTime,
        -- * Disposable
        DisposableEventT(..),
        DisposableEvent(..)) where

import Simulation.Aivika.Trans.Internal.Event