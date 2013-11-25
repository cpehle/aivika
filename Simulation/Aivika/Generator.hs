
-- |
-- Module     : Simulation.Aivika.Generator
-- Copyright  : Copyright (c) 2009-2013, David Sorokin <david.sorokin@gmail.com>
-- License    : BSD3
-- Maintainer : David Sorokin <david.sorokin@gmail.com>
-- Stability  : experimental
-- Tested with: GHC 7.6.3
--
-- Below is defined a type class of the random number generator.
--
module Simulation.Aivika.Generator 
       (Generator(..),
        GeneratorType(..),
        newGenerator,
        newRandomGenerator) where

import System.Random
import Data.IORef

-- | Defines a random number generator.
data Generator =
  Generator { generatorUniform :: Double -> Double -> IO Double,
              -- ^ Generate an uniform random number
              -- with the specified minimum and maximum.
              generatorNormal :: Double -> Double -> IO Double,
              -- ^ Generate the normal random number
              -- with the specified mean and deviation.
              generatorExponential :: Double -> IO Double,
              -- ^ Generate the random number distributed exponentially
              -- with the specified mean (the reciprocal of the rate).
              generatorErlang :: Double -> Int -> IO Double,
              -- ^ Generate the Erlang random number
              -- with the specified scale (the reciprocal of the rate) and integer shape.
              generatorPoisson :: Double -> IO Int,
              -- ^ Generate the Poisson random number
              -- with the specified mean.
              generatorBinomial :: Double -> Int -> IO Int
              -- ^ Generate the binomial random number
              -- with the specified probability and number of trials.
            }

-- | Generate the uniform random number with the specified minimum and maximum.
generateUniform :: IO Double
                   -- ^ the generator
                   -> Double
                   -- ^ minimum
                   -> Double
                   -- ^ maximum
                   -> IO Double
generateUniform g min max =
  do x <- g
     return $ min + x * (max - min)

-- | Create a normal random number generator with mean 0 and variance 1
-- by the specified generator of uniform random numbers from 0 to 1.
newNormalGenerator :: IO Double
                      -- ^ the generator
                      -> IO (IO Double)
newNormalGenerator g =
  do nextRef <- newIORef 0.0
     flagRef <- newIORef False
     xi1Ref  <- newIORef 0.0
     xi2Ref  <- newIORef 0.0
     psiRef  <- newIORef 0.0
     let loop =
           do psi <- readIORef psiRef
              if (psi >= 1.0) || (psi == 0.0)
                then do g1 <- g
                        g2 <- g
                        let xi1 = 2.0 * g1 - 1.0
                            xi2 = 2.0 * g2 - 1.0
                            psi = xi1 * xi1 + xi2 * xi2
                        writeIORef xi1Ref xi1
                        writeIORef xi2Ref xi2
                        writeIORef psiRef psi
                        loop
                else writeIORef psiRef $ sqrt (- 2.0 * log psi / psi)
     return $
       do flag <- readIORef flagRef
          if flag
            then do writeIORef flagRef False
                    readIORef nextRef
            else do writeIORef xi1Ref 0.0
                    writeIORef xi2Ref 0.0
                    writeIORef psiRef 0.0
                    loop
                    xi1 <- readIORef xi1Ref
                    xi2 <- readIORef xi2Ref
                    psi <- readIORef psiRef
                    writeIORef flagRef True
                    writeIORef nextRef $ xi2 * psi
                    return $ xi1 * psi

-- | Return the exponential random number with the specified mean.
generateExponential :: IO Double
                       -- ^ the generator
                       -> Double
                       -- ^ the mean
                       -> IO Double
generateExponential g mu =
  do x <- g
     return (- log x * mu)

-- | Return the Erlang random number.
generateErlang :: IO Double
                  -- ^ the generator
                  -> Double
                  -- ^ the scale
                  -> Int
                  -- ^ the shape
                  -> IO Double
generateErlang g beta m =
  do x <- loop m 1
     return (- log x * beta)
       where loop m acc
               | m < 0     = error "Negative shape: generateErlang."
               | m == 0    = return acc
               | otherwise = do x <- g
                                loop (m - 1) (x * acc)

-- | Generate the Poisson random number with the specified mean.
generatePoisson :: IO Double
                   -- ^ the generator
                   -> Double
                   -- ^ the mean
                   -> IO Int
generatePoisson g mu =
  do prob0 <- g
     let loop prob prod acc
           | prob <= prod = return acc
           | otherwise    = loop
                            (prob - prod)
                            (prod * mu / fromIntegral (acc + 1))
                            (acc + 1)
     loop prob0 (exp (- mu)) 0

-- | Generate a binomial random number with the specified probability and number of trials. 
generateBinomial :: IO Double
                    -- ^ the generator
                    -> Double 
                    -- ^ the probability
                    -> Int
                    -- ^ the number of trials
                    -> IO Int
generateBinomial g prob trials = loop trials 0 where
  loop n acc
    | n < 0     = error "Negative number of trials: generateBinomial."
    | n == 0    = return acc
    | otherwise = do x <- g
                     if x <= prob
                       then loop (n - 1) (acc + 1)
                       else loop (n - 1) acc

-- | Defines a type of the random number generator.
data GeneratorType = SimpleGenerator
                     -- ^ The simple random number generator.
                   | SimpleGeneratorWithSeed Int
                     -- ^ The simple random number generator with the specified seed.
                   | CustomGenerator (IO Generator)
                     -- ^ The custom random number generator.

-- | Create a new random number generator by the specified type.
newGenerator :: GeneratorType -> IO Generator
newGenerator tp =
  case tp of
    SimpleGenerator ->
      newStdGen >>= newRandomGenerator
    SimpleGeneratorWithSeed x ->
      newRandomGenerator $ mkStdGen x
    CustomGenerator g ->
      g

-- | Create a new random generator by the specified standard generator.
newRandomGenerator :: RandomGen g => g -> IO Generator
newRandomGenerator g =
  do r <- newIORef g
     let g1 = do g <- readIORef r
                 let (x, g') = random g
                 writeIORef r g'
                 return x
     g2 <- newNormalGenerator g1
     let g3 mu nu =
           do x <- g2
              return $ mu + nu * x
     return Generator { generatorUniform = generateUniform g1,
                        generatorNormal = g3,
                        generatorExponential = generateExponential g1,
                        generatorErlang = generateErlang g1,
                        generatorPoisson = generatePoisson g1,
                        generatorBinomial = generateBinomial g1 }
