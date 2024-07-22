package Ribasim_Windows

import Ribasim_Windows.buildTypes.Windows_BuildRibasim
import Ribasim_Windows.buildTypes.Windows_TestDelwaqCoupling
import Ribasim_Windows.buildTypes.Windows_TestRibasimBinaries
import jetbrains.buildServer.configs.kotlin.Project

object Project : Project({
    id("Ribasim_Windows")
    name = "Ribasim_Windows"

    buildType(Windows_BuildRibasim)
    buildType(Windows_TestDelwaqCoupling)
    buildType(Windows_TestRibasimBinaries)
})
