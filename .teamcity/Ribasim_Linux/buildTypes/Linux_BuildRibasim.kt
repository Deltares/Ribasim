package Ribasim_Linux.buildTypes

import Templates.BuildLinux
import Templates.GithubCommitStatusIntegration
import Templates.LinuxAgent
import jetbrains.buildServer.configs.kotlin.BuildType

object Linux_BuildRibasim : BuildType({
    templates(
        LinuxAgent,
        GithubCommitStatusIntegration,
        BuildLinux
    )

    name = "Build Ribasim"
})
