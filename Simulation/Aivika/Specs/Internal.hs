
-- |
-- Module     : Simulation.Aivika.Specs.Internal
-- Copyright  : Copyright (c) 2009-2013, David Sorokin <david.sorokin@gmail.com>
-- License    : BSD3
-- Maintainer : David Sorokin <david.sorokin@gmail.com>
-- Stability  : experimental
-- Tested with: GHC 7.6.3
--
-- It defines the simulation specs and related stuff.
module Simulation.Aivika.Specs.Internal
       (Specs(..),
        Method(..),
        Run(..),
        Point(..),
        EventQueue(..),
        newEventQueue,
        basicTime,
        integIterationBnds,
        integIterationHiBnd,
        integIterationLoBnd,
        integPhaseBnds,
        integPhaseHiBnd,
        integPhaseLoBnd) where

import Data.IORef

import qualified Simulation.Aivika.PriorityQueue as PQ

-- | It defines the simulation specs.
data Specs = Specs { spcStartTime :: Double,    -- ^ the start time
                     spcStopTime :: Double,     -- ^ the stop time
                     spcDT :: Double,           -- ^ the integration time step
                     spcMethod :: Method        -- ^ the integration method
                   } deriving (Eq, Ord, Show)

-- | It defines the integration method.
data Method = Euler          -- ^ Euler's method
            | RungeKutta2    -- ^ the 2nd order Runge-Kutta method
            | RungeKutta4    -- ^ the 4th order Runge-Kutta method
            deriving (Eq, Ord, Show)

-- | It indentifies the simulation run.
data Run = Run { runSpecs :: Specs,  -- ^ the simulation specs
                 runIndex :: Int,    -- ^ the current simulation run index
                 runCount :: Int,    -- ^ the total number of runs in this experiment
                 runEventQueue :: EventQueue   -- ^ the event queue
               }

-- | It defines the simulation point appended with the additional information.
data Point = Point { pointSpecs :: Specs,    -- ^ the simulation specs
                     pointRun :: Run,        -- ^ the simulation run
                     pointTime :: Double,    -- ^ the current time
                     pointIteration :: Int,  -- ^ the current iteration
                     pointPhase :: Int       -- ^ the current phase
                   }

-- | It represents the event queue.
data EventQueue = EventQueue { queuePQ :: PQ.PriorityQueue (Point -> IO ()),
                               -- ^ the underlying priority queue
                               queueBusy :: IORef Bool,
                               -- ^ whether the queue is currently processing events
                               queueTime :: IORef Double
                               -- ^ the actual time of the event queue
                             }

-- | Create a new event queue by the specified specs.
newEventQueue :: Specs -> IO EventQueue
newEventQueue specs = 
  do f <- newIORef False
     t <- newIORef $ spcStartTime specs
     pq <- PQ.newQueue
     return EventQueue { queuePQ   = pq,
                         queueBusy = f,
                         queueTime = t }

-- | Returns the integration iterations starting from zero.
integIterations :: Specs -> [Int]
integIterations sc = [i1 .. i2] where
  i1 = 0
  i2 = round ((spcStopTime sc - 
               spcStartTime sc) / spcDT sc)

-- | Returns the first and last integration iterations.
integIterationBnds :: Specs -> (Int, Int)
integIterationBnds sc = (0, round ((spcStopTime sc - 
                                    spcStartTime sc) / spcDT sc))

-- | Returns the first integration iteration, i.e. zero.
integIterationLoBnd :: Specs -> Int
integIterationLoBnd sc = 0

-- | Returns the last integration iteration.
integIterationHiBnd :: Specs -> Int
integIterationHiBnd sc = round ((spcStopTime sc - 
                                 spcStartTime sc) / spcDT sc)

-- | Returns the phases for the specified simulation specs starting from zero.
integPhases :: Specs -> [Int]
integPhases sc = 
  case spcMethod sc of
    Euler -> [0]
    RungeKutta2 -> [0, 1]
    RungeKutta4 -> [0, 1, 2, 3]

-- | Returns the first and last integration phases.
integPhaseBnds :: Specs -> (Int, Int)
integPhaseBnds sc = 
  case spcMethod sc of
    Euler -> (0, 0)
    RungeKutta2 -> (0, 1)
    RungeKutta4 -> (0, 3)

-- | Returns the first integration phase, i.e. zero.
integPhaseLoBnd :: Specs -> Int
integPhaseLoBnd sc = 0
                  
-- | Returns the last integration phase, 0 for Euler's method, 1 for RK2 and 3 for RK4.
integPhaseHiBnd :: Specs -> Int
integPhaseHiBnd sc = 
  case spcMethod sc of
    Euler -> 0
    RungeKutta2 -> 1
    RungeKutta4 -> 3

-- | Returns a simulation time for the integration point specified by 
-- the specs, iteration and phase.
basicTime :: Specs -> Int -> Int -> Double
basicTime sc n ph =
  if ph < 0 then 
    error "Incorrect phase: basicTime"
  else
    spcStartTime sc + n' * spcDT sc + delta (spcMethod sc) ph 
      where n' = fromIntegral n
            delta Euler       0 = 0
            delta RungeKutta2 0 = 0
            delta RungeKutta2 1 = spcDT sc
            delta RungeKutta4 0 = 0
            delta RungeKutta4 1 = spcDT sc / 2
            delta RungeKutta4 2 = spcDT sc / 2
            delta RungeKutta4 3 = spcDT sc
