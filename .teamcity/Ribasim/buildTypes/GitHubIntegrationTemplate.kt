package Ribasim.buildTypes

import Ribasim.vcsRoots.Ribasim as RibasimVcs
import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildFeatures.commitStatusPublisher

object GitHubIntegrationTemplate : Template({
    name = "GitHubIntegrationTemplate"

    vcs {
        root(RibasimVcs, ". => ribasim")
    }

    features {
        commitStatusPublisher {
            id = "TEMPLATE_BUILD_EXT_1"
            vcsRootExtId = "${RibasimVcs.id}"
            publisher = github {
                githubUrl = "https://api.github.com"
                authType = personalToken {
                    token = "credentialsJSON:6b37af71-1f2f-4611-8856-db07965445c0"
                }
            }
        }
    }
})
