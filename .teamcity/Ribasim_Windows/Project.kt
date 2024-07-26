package Ribasim_Windows

import Ribasim_Windows.buildTypes.Windows_TestDelwaqCoupling
import Templates.*
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.FailureAction
import jetbrains.buildServer.configs.kotlin.Project
import jetbrains.buildServer.configs.kotlin.triggers.vcs
import Ribasim.vcsRoots.Ribasim as RibasimVcs

object Project : Project({
    id("Ribasim_Windows")
    name = "Ribasim_Windows"

    buildType(Windows_Main)
    buildType(Windows_BuildRibasim)
    buildType(Windows_TestDelwaqCoupling)
    buildType(Windows_TestRibasimBinaries)

    template(WindowsAgent)
    template(BuildWindows)
    template(TestBinariesWindows)
})

object Windows_Main : BuildType({
    name = "RibasimMain"

    templates(GithubCommitStatusIntegration, GithubPullRequestsIntegration)

    allowExternalStatus = true
    type = Type.COMPOSITE

    vcs {
        root(RibasimVcs, ". => ribasim")
        cleanCheckout = true
    }

    triggers {
        vcs {
        }
    }

    dependencies {
        snapshot(Windows_TestRibasimBinaries) {
            onDependencyFailure = FailureAction.FAIL_TO_START
        }
        snapshot(Windows_TestDelwaqCoupling) {
            onDependencyFailure = FailureAction.FAIL_TO_START
        }
    }
})

object Windows_BuildRibasim : BuildType({
    templates(WindowsAgent, GithubCommitStatusIntegration, BuildWindows)
    name = "Build Ribasim"

    artifactRules = """ribasim\build\ribasim => ribasim_windows.zip"""
})

object Windows_TestRibasimBinaries : BuildType({
    templates(WindowsAgent, GithubCommitStatusIntegration, TestBinariesWindows)
    name = "Test Ribasim Binaries"

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
