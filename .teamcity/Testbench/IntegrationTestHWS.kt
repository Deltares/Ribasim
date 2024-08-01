package Testbench

import Templates.*
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.Project
import jetbrains.buildServer.configs.kotlin.triggers.schedule


object RibasimTestbench : Project ({
    id("Testbench")
    name = "Testbench"

    buildType(IntegrationTest_Windows)

    template(IntegrationTestWindows)
})

object IntegrationTest_Windows : BuildType({
    templates(WindowsAgent, GithubCommitStatusIntegration, IntegrationTestWindows)
    name = "IntegrationTestWindows"

    triggers{
        schedule {
            id = ""
            schedulingPolicy = daily {
                hour = 0
            }

            branchFilter = "+:<default>"
            triggerBuild = always()
            withPendingChangesOnly = false
        }
    }

    dependencies {
        dependency(Ribasim_Windows.Windows_BuildRibasim) {
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