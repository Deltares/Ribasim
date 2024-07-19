package Testbench

import Testbench.buildTypes.*
import jetbrains.buildServer.configs.kotlin.Project

object Project : Project({
    id("Testbench")
    name = "Testbench"

    buildType(Linux_BuildRibasim)
    buildType(Regression)
})
