package Testbench_Integration

import Ribasim_Linux.Linux_BuildRibasim
import Ribasim_Windows.Windows_BuildRibasim
import Templates.*
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.Project


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

    dependencies{
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

    dependencies{
        dependency(Linux_BuildRibasim) {
            snapshot {
            }

            artifacts {
                id = "ARTIFACT_DEPENDENCY_570"
                cleanDestination = true
                artifactRules = """
                    ribasim_linux.zip!** => ribasim/build/ribasim
                """.trimIndent()
            }
        }
    }
})