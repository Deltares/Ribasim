package Ribasim.buildTypes

import jetbrains.buildServer.configs.kotlin.*

object Linux_1 : Template({
    id("Ribasim_Linux")
    name = "Ribasim_Linux"
    description = "Template for agent that uses Linux OS"

    publishArtifacts = PublishMode.SUCCESSFUL

    vcs {
        cleanCheckout = true
    }

    requirements {
        equals("teamcity.agent.jvm.os.name", "Ribasim_Linux", "RQ_418")
    }
})
