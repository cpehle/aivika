
{-# LANGUAGE RecursiveDo #-}

import Data.Array

import Simulation.Aivika.Dynamics
import Simulation.Aivika.Dynamics.Simulation
import Simulation.Aivika.Dynamics.SystemDynamics

specs = Specs { spcStartTime = 0, 
                spcStopTime = 13, 
                spcDT = 0.01,
                -- spcDT = 0.000005,
                spcMethod = RungeKutta4 }

model :: Simulation Double
model =
  do rec -- integrals --
         fish <- integ (fishHatchRate - fishDeathRate - totalCatchPerYear) 1000
         ships <- integ shipBuildingRate 10
         totalProfit <- integ annualProfit 0
         -- auxiliary values --
         let annualProfit = profit
             area = 100
             carryingCapacity = 1000
             catchPerShip = 
               lookupD density $
               listArray (1, 11) [(0.0, -0.048), (1.2, 10.875), (2.4, 17.194), 
                                  (3.6, 20.548), (4.8, 22.086), (6.0, 23.344), 
                                  (7.2, 23.903), (8.4, 24.462), (9.6, 24.882), 
                                  (10.8, 25.301), (12.0, 25.86)]
             deathFraction = 
               lookupD (fish / carryingCapacity) $
               listArray (1, 11) [(0.0, 5.161), (0.1, 5.161), (0.2, 5.161), 
                                  (0.3, 5.161), (0.4, 5.161), (0.5, 5.161), 
                                  (0.6, 5.118), (0.7, 5.247), (0.8, 5.849), 
                                  (0.9, 6.151), (10.0, 6.194)]
             density = fish / area
             fishDeathRate = maxDynamics 0 (fish * deathFraction)
             fishHatchRate = maxDynamics 0 (fish * hatchFraction)
             fishPrice = 20
             fractionInvested = 0.2
             hatchFraction = 6
             operatingCost = ships * 250
             profit = revenue - operatingCost
             revenue = totalCatchPerYear * fishPrice
             shipBuildingRate = maxDynamics 0 (profit * fractionInvested / shipCost)
             shipCost = 300
             totalCatchPerYear = maxDynamics 0 (ships * catchPerShip)
     -- results --
     runDynamicsInStopTime annualProfit

main = runSimulation model specs >>= print
