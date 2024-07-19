package patches.buildTypes

import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.ui.*

create(RelativeId("Testbench"), BuildType({
    templates(RelativeId("Ribasim_Linux"))
    id("Testbench_Regression")
    name = "Regression"

    vcs {
        root(DslContext.settingsRoot)
    }
}))