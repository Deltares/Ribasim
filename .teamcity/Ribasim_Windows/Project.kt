package Ribasim_Windows

import Ribasim_Windows.buildTypes.Windows_BuildRibasim
import Ribasim_Windows.buildTypes.Windows_TestDelwaqCoupling
import Ribasim_Windows.buildTypes.Windows_TestRibasimBinaries
import jetbrains.buildServer.configs.kotlin.Project

object Project : Project({
    id("Ribasim_Windows")
    name = "Ribasim_Windows"

    buildType(Main)
    buildType(Windows_BuildRibasim)
    buildType(Windows_TestDelwaqCoupling)
    buildType(Windows_TestRibasimBinaries)
})

object Main : BuildType({
    name = "RibasimMain"

    allowExternalStatus = true
    type = Type.COMPOSITE

    vcs {
        root(RibasimVcs, ". => ribasim")
    }

    triggers {
        vcs {
        }
    }

    features {
        commitStatusPublisher {
            vcsRootExtId = "${RibasimVcs.id}"
            publisher = github {
                githubUrl = "https://api.github.com"
                authType = personalToken {
                    token = "credentialsJSON:6b37af71-1f2f-4611-8856-db07965445c0"
                }
            }
        }
        pullRequests {
            vcsRootExtId = "${RibasimVcs.id}"
            provider = github {
                authType = token {
                    token = "credentialsJSON:6b37af71-1f2f-4611-8856-db07965445c0"
                }
                filterAuthorRole = PullRequests.GitHubRoleFilter.MEMBER
            }
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