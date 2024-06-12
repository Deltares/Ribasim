package Ribasim_Linux

import Ribasim_Linux.buildTypes.*
import jetbrains.buildServer.configs.kotlin.Project

object Project : Project({
    id("Ribasim_Linux")
    name = "Ribasim_Linux"

    buildType(Linux_BuildRibasim)
    buildType(Linux_TestRibasimBinaries)
})
