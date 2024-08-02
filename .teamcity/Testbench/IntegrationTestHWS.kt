package Testbench

import Ribasim_Windows.Windows_BuildRibasim
import Ribasim_Linux.Linux_BuildRibasim
import Templates.*
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.Project
import jetbrains.buildServer.configs.kotlin.matrix
import jetbrains.buildServer.configs.kotlin.triggers.schedule
import jetbrains.buildServer.configs.kotlin.*


object RibasimTestbench : Project ({
    id("Testbench")
    name = "Testbench"

    buildType(IntegrationTest_Windows)
//    buildType(IntegrationTest_Linux)

    template(IntegrationTestWindows)
    template(IntegrationTestLinux)
})

object IntegrationTest_Windows : BuildType({
    features {
        matrix {
            os = listOf(
                value("Windows"),
                value("Linux")
            )
        }
    }

    if ("teamcity.agent.jvm.os.name" == "Windows"){
        templates(WindowsAgent, GithubCommitStatusIntegration, IntegrationTestWindows)
        name = "IntegrationTestWindows"
    } else {
        templates(LinuxAgent, GithubCommitStatusIntegration, IntegrationTestLinux)
        name = "IntegrationTestLinux"
    }

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

//object IntegrationTest_Linux : BuildType({
//    templates(LinuxAgent, GithubCommitStatusIntegration, IntegrationTestLinux)
//    name = "IntegrationTestLinux"
//
//    triggers{
//        schedule {
//            id = ""
//            schedulingPolicy = daily {
//                hour = 0
//            }
//
//            branchFilter = "+:<default>"
//            triggerBuild = always()
//            withPendingChangesOnly = true
//        }
//    }
//
//    dependencies {
//        dependency(Linux_BuildRibasim) {
//            snapshot {
//            }
//
//            artifacts {
//                id = "ARTIFACT_DEPENDENCY_570"
//                cleanDestination = true
//                artifactRules = """
//                    ribasim_windows.zip!** => ribasim/build/ribasim
//                """.trimIndent()
//            }
//        }
//    }
//})