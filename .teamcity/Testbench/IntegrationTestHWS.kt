package Testbench

import Template.*
import jetbrains.buildServer.configs.kotlin.AbsoluteId
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.FailureAction
import jetbrains.buildServer.configs.kotlin.Project
import jetbrains.buildServer.configs.kotlin.triggers.vcs
import Ribasim.vcsRoots.Ribasim as RibasimVcs

object RibasimTestbench : Project ({
    id("Testbench")
    name = "Testbench"

    buildType(IntegrationTest_Windows)

    template(WindowsAgent)
    template(BuildWindows)
    template(IntegrationTest)
})

object IntegrationTest_Windows : BuildType({
    templates(WindowsAgent, GithubCommitStatusIntegration, IntegrationTest)
    name = "Test Ribasim Binaries"

    schedule {
        id = ""
        schedulingPolicy = daily {
            hour = 0
        }

        branchFilter = "+:<default>"
        triggerBuild = always()
        withPendingChangesOnly = false
    }

    dependencies {
        dependency(Windows_BuildRibasim) {
            snapshot {
            }

            artifacts {
                id = "ARTIFACT_DEPENDENCY_570"
                cleanDestination = true
                artifactRules = """
                    ribasim_windows.zip!** => ribasim/build/ribasim
                """.trimIndent()
            }
        }
    }
})