package Testbench.IntegrationTestHWS

import Ribasim_Linux.Linux_BuildRibasim
import Ribasim_Windows.Windows_BuildRibasim
import Templates.*
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.Project
import jetbrains.buildServer.configs.kotlin.triggers.schedule

object IntegrationTestHWS : Project ({
    id("IntegrationTestHWS")
    name = "IntegrationTestHWS"

    buildType(IntegrationTest_Windows)
    buildType(IntegrationTest_Linux)

    template(IntegrationTestWindows)
    template(IntegrationTestLinux)
})

object IntegrationTest_Windows : BuildType({
    name = "IntegrationTestWindows"
    templates(WindowsAgent, GithubCommitStatusIntegration, IntegrationTestWindows)

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

object IntegrationTest_Linux : BuildType({
    name = "IntegrationTestLinux"
    templates(LinuxAgent, GithubCommitStatusIntegration, IntegrationTestLinux)

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