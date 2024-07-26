package Templates

import Ribasim.vcsRoots.Ribasim
import jetbrains.buildServer.configs.kotlin.Template
import jetbrains.buildServer.configs.kotlin.buildFeatures.PullRequests
import jetbrains.buildServer.configs.kotlin.buildFeatures.commitStatusPublisher
import jetbrains.buildServer.configs.kotlin.buildFeatures.pullRequests

object GithubCommitStatusIntegration : Template({
    name = "GithubCommitStatusIntegrationTemplate"

    features {
        commitStatusPublisher {
            vcsRootExtId = "${Ribasim.id}"
            publisher = github {
                githubUrl = "https://api.github.com"
                authType = personalToken {
                    token = "credentialsJSON:6b37af71-1f2f-4611-8856-db07965445c0"
                }
            }
        }
    }
})

object GithubPullRequestsIntegration : Template({
    name = "GithubPullRequestsIntegrationTemplate"

    features {
        pullRequests {
            vcsRootExtId = "${Ribasim.id}"
            provider = github {
                authType = token {
                    token = "credentialsJSON:6b37af71-1f2f-4611-8856-db07965445c0"
                }
                filterAuthorRole = PullRequests.GitHubRoleFilter.MEMBER
            }
        }
    }
})