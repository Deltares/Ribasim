package Templates

import jetbrains.buildServer.configs.kotlin.*

object LinuxAgent : Template({
    id("Ribasim_Linux")
    name = "Ribasim_Linux"
    description = "Template for agent that uses Linux OS"

    publishArtifacts = PublishMode.SUCCESSFUL

    requirements {
        equals("teamcity.agent.jvm.os.name", "Linux", "RQ_418")
    }
})
