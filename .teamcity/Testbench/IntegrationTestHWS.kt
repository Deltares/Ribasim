package Testbench

import Ribasim_Windows.Windows_BuildRibasim
import Ribasim_Linux.Linux_BuildRibasim
import Templates.*
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.Project
import jetbrains.buildServer.configs.kotlin.triggers.schedule


object RibasimTestbench : Project ({
    id("Testbench")
    name = "Testbench"

    buildType(IntegrationTest_Windows)

    template(IntegrationTestWindows)
    template(IntegrationTestLinux)
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
            withPendingChangesOnly = true
        }
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

object IntegrationTest_Linux : BuildType({
    templates(LinuxAgent, GithubCommitStatusIntegration, IntegrationTestLinux)
    name = "IntegrationTestLinux"

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

    dependencies {
        dependency(Linux_BuildRibasim) {
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