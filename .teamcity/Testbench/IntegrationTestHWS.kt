package Testbench

import Templates.*
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.Project


object IntegrationTestHWS : Project ({
    id("IntegrationTestHWS")
    name = "IntegrationTestHWS"

    buildType(IntegrationTest_Windows)
    buildType(IntegrationTest_Linux)

    template(IntegrationTestWindows)
    template(IntegrationTestLinux)
})

object IntegrationTest_Windows : BuildType({
    name = "IntegrationTestWindows"
    templates(WindowsAgent, GithubCommitStatusIntegration, IntegrationTestWindows)
})

object IntegrationTest_Linux : BuildType({
    templates(LinuxAgent, GithubCommitStatusIntegration, IntegrationTestLinux)
    name = "IntegrationTestLinux"
})