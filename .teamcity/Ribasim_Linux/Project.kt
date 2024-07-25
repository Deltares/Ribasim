package Ribasim_Linux

import Ribasim.vcsRoots.Ribasim
import Ribasim_Linux.buildTypes.Linux_BuildRibasim
import Ribasim_Linux.buildTypes.Linux_TestRibasimBinaries
import Templates.GithubCommitStatusIntegration
import Templates.GithubPullRequestsIntegration
import Templates.LinuxAgent
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.FailureAction
import jetbrains.buildServer.configs.kotlin.Project
import jetbrains.buildServer.configs.kotlin.triggers.vcs

object Project : Project({
    id("Ribasim_Linux")
    name = "Ribasim_Linux"

    buildType(Linux_Main)
    buildType(Linux_BuildRibasim)
    buildType(Linux_TestRibasimBinaries)

    template(LinuxAgent)
})

object Linux_Main : BuildType({
    name = "RibasimMain"

    templates(GithubCommitStatusIntegration, GithubPullRequestsIntegration)

    allowExternalStatus = true
    type = Type.COMPOSITE

    vcs {
        root(Ribasim, ". => ribasim")
        cleanCheckout = true
    }

    triggers {
        vcs {
        }
    }

    dependencies {
        snapshot(Linux_TestRibasimBinaries) {
            onDependencyFailure = FailureAction.FAIL_TO_START
        }
    }
})