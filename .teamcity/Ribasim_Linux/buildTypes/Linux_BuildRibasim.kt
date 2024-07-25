package Ribasim_Linux.buildTypes

import Templates.Build
import Templates.GithubCommitStatusIntegration
import Templates.LinuxAgent
import jetbrains.buildServer.configs.kotlin.BuildType

object Linux_BuildRibasim : BuildType({
    templates(
        LinuxAgent,
        GithubCommitStatusIntegration,
        Build.create("Linux")
    )

    name = "Build Ribasim"
})
