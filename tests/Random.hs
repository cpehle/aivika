
{-# LANGUAGE FlexibleContexts #-}

import Control.Monad
import Control.Monad.Trans

import Simulation.Aivika
import Simulation.Aivika.Experiment
import Simulation.Aivika.Experiment.Chart
import Simulation.Aivika.Experiment.Chart.Backend.Cairo

import Graphics.Rendering.Chart.Backend.Cairo

specs = Specs 0 200 0.1 RungeKutta4 SimpleGenerator

experiment = 
  defaultExperiment {
    experimentTitle = "Test of Random Number Generators",
    experimentSpecs = specs }

seriesGenerator title description series =
  [outputView $ defaultTimeSeriesView {
      timeSeriesTitle = title ++ " - Time Series",
      timeSeriesDescription = description,
      timeSeriesLeftYSeries = series },
   outputView $ defaultHistogramView {
     histogramTitle = title ++ " - Histogram",
     histogramDescription = description,
     histogramSeries = series },
   outputView $ defaultTimingStatsView {
     timingStatsTitle = title ++ " - Statistics",
     timingStatsDescription = description,
     timingStatsSeries = series }]

uniformTitle  = "Uniform Random"
uniformDescr  = "Uniform " ++ show (m1, m2)
uniformSeries = resultByName "rnd"

triagTitle  = "Triangle Random"
triagDescr  = "Triangle " ++ show (m1, m3, m2) ++
              ", EX = " ++ show (triangularMean m1 m3 m2) ++
              ", sqrt(DX) = " ++ show (triangularDeviation m1 m3 m2)
triagSeries = resultByName "triag"

normalTitle  = "Normal Random"
normalDescr  = "Normal " ++ show (mu, nu)
normalSeries = resultByName "normal"

logNormalTitle  = "LogNormal Random"
logNormalDescr  = "LogNormal " ++ show (logMu, logNu) ++
                  ", EX = " ++ show (logNormalMean logMu logNu) ++
                  ", sqrt(DX) = " ++ show (logNormalDeviation logMu logNu)
logNormalSeries = resultByName "lognormal"

expTitle  = "Exponential Random"
expDescr  = "Exponential (" ++ show mu ++ ")"
expSeries = resultByName "exp"

poissonTitle  = "Poisson Random"
poissonDescr  = "Poisson (" ++ show mu ++ ")"
poissonSeries = resultByName "poisson"

binomialTitle  = "Binomial Random"
binomialDescr  = "Binomial " ++ show (p, n)
binomialSeries = resultByName "binomial"

generators =
  [outputView defaultExperimentSpecsView] ++
  seriesGenerator uniformTitle uniformDescr uniformSeries ++
  seriesGenerator triagTitle triagDescr triagSeries ++
  seriesGenerator normalTitle normalDescr normalSeries ++
  seriesGenerator logNormalTitle logNormalDescr logNormalSeries ++
  seriesGenerator expTitle expDescr expSeries ++
  seriesGenerator poissonTitle poissonDescr poissonSeries ++
  seriesGenerator binomialTitle binomialDescr binomialSeries

triangularMean a m b = (a + m + b) / 3
triangularDeviation a m b = sqrt $ (a*(a-m) + b*(b-a) + m*(m-b)) / 18

logNormalMean mu nu = exp (mu + nu * nu / 2)
logNormalDeviation mu nu = sqrt $ exp (nu * nu + 2 * mu) * (exp (nu * nu) - 1)

m1 = 2 :: Double
m2 = 8 :: Double
m3 = 6 :: Double

mu = 5 :: Double
nu = 3 :: Double

logMu = 0 :: Double
logNu = 0.3 :: Double

p = 0.1 :: Double
n = 5 :: Int

model :: Simulation Results
model =
  do rndX <- memoRandomUniformDynamics (return m1) (return m2)
     triagX <- memoRandomTriangularDynamics (return m1) (return m3) (return m2)
     normalX <- memoRandomNormalDynamics (return mu) (return nu)
     logNormalX <- memoRandomLogNormalDynamics (return logMu) (return logNu)
     expX <- memoRandomExponentialDynamics (return mu)
     poissonX <- memoRandomPoissonDynamics (return mu)
     binomialX <- memoRandomBinomialDynamics (return p) (return n)
     return $
       results
       [resultSource "rnd" "rnd" rndX,
        resultSource "triag" "triag" triagX,
        resultSource "normal" "normal" normalX,
        resultSource "lognormal" "lognormal" logNormalX,
        resultSource "exp" "exp" expX,
        resultSource "poisson" "poisson" poissonX,
        resultSource "binomial" "binomial" binomialX]
    
main = runExperiment experiment generators (WebPageRenderer $ CairoRenderer PNG) model
