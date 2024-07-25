package Ribasim_Windows

import Ribasim_Windows.buildTypes.Windows_BuildRibasim
import Ribasim_Windows.buildTypes.Windows_TestDelwaqCoupling
import Ribasim_Windows.buildTypes.Windows_TestRibasimBinaries
import Templates.GithubCommitStatusIntegration
import Templates.GithubPullRequestsIntegration
import Templates.WindowsAgent
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