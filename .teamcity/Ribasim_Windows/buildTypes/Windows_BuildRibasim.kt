package Ribasim_Windows.buildTypes

import Templates.BuildWindows
import Templates.GithubCommitStatusIntegration
import Templates.WindowsAgent
import jetbrains.buildServer.configs.kotlin.BuildType

object Windows_BuildRibasim : BuildType({
    templates(WindowsAgent, GithubCommitStatusIntegration, BuildWindows)
    name = "Build Ribasim"
})
