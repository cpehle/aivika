
-- |
-- Module     : Simulation.Aivika.Dynamics
-- Copyright  : Copyright (c) 2009-2013, David Sorokin <david.sorokin@gmail.com>
-- License    : BSD3
-- Maintainer : David Sorokin <david.sorokin@gmail.com>
-- Stability  : experimental
-- Tested with: GHC 7.6.3
--
-- The module defines the 'Dynamics' monad representing an abstract dynamic 
-- process, i.e. a time varying polymorphic function. 
--
module Simulation.Aivika.Dynamics 
       (-- * Dynamics
        Dynamics,
        DynamicsLift(..),
        runDynamicsInStartTime,
        runDynamicsInStopTime,
        runDynamicsInIntegTimes,
        runDynamicsInTime,
        runDynamicsInTimes,
        -- * Error Handling
        catchDynamics,
        finallyDynamics,
        throwDynamics) where

import Simulation.Aivika.Dynamics.Internal.Dynamics
