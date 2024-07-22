package Ribasim.buildTypes

import jetbrains.buildServer.configs.kotlin.*

object Windows_1 : Template({
    id("Ribasim_Windows")
    name = "Ribasim_Windows"
    description = "Template for agent that uses Windows OS"

    vcs {
        cleanCheckout = true
    }

    requirements {
        contains("teamcity.agent.jvm.os.name", "Windows", "RQ_422")
    }
})
