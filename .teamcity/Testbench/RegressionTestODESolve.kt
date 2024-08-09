package Testbench.RegressionTestODESolve

import Ribasim_Windows.Windows_BuildRibasim
import Ribasim_Linux.Linux_BuildRibasim
import Templates.*
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.Project
import jetbrains.buildServer.configs.kotlin.matrix
import jetbrains.buildServer.configs.kotlin.triggers.schedule
import jetbrains.buildServer.configs.kotlin.*

object RegressionTestODESolve : Project({
    id("RegressionTestODE")
    name = "RegressionTestODE"

    buildType(RegressionTest_Windows)
    buildType(RegressionTest_Linux)

    template(RegressionTestWindows)
    template(RegressionTestLinux)
})

object RegressionTest_Windows : BuildType({
    name = "RegressionTestWindows"
    templates(WindowsAgent, GithubCommitStatusIntegration, RegressionTestWindows)

    triggers{
        schedule {
            id = ""
            schedulingPolicy = daily {
                hour = 0
            }

            branchFilter = "+:<default>"
            triggerBuild = always()
            withPendingChangesOnly = true
        }
    }
})

object RegressionTest_Linux : BuildType({
    name = "RegressionTestLinux"
    templates(LinuxAgent, GithubCommitStatusIntegration, RegressionTestLinux)

    triggers{
        schedule {
            id = ""
            schedulingPolicy = daily {
                hour = 0
            }

            branchFilter = "+:<default>"
            triggerBuild = always()
            withPendingChangesOnly = true
        }
    }
})