package Testbench

import Templates.*
import Testbench.IntegrationTestHWS.IntegrationTestHWS
import Testbench.RegressionTestODESolve.RegressionTestODESolve
import jetbrains.buildServer.configs.kotlin.Project

object Testbench : Project({
    name = "Testbench"
    subProject(IntegrationTestHWS)
    subProject(RegressionTestODESolve)
})