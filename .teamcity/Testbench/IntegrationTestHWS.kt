package Testbench

import Ribasim_Windows.Windows_BuildRibasim
import Ribasim_Linux.Linux_BuildRibasim
import Templates.*
import jetbrains.buildServer.configs.kotlin.BuildType
import jetbrains.buildServer.configs.kotlin.Project
import jetbrains.buildServer.configs.kotlin.matrix
import jetbrains.buildServer.configs.kotlin.triggers.schedule
import jetbrains.buildServer.configs.kotlin.*


object RibasimTestbench : Project ({
    id("Testbench")
    name = "Testbench"

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