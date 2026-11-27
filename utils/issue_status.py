"""Set the Status of a Ribasim issue on the Team Hydro Core project board.

"In progress" also puts the issue in the current Iteration, and assigns it to you
if nobody is assigned yet. It stops if someone else is assigned.

Usage: pixi run issue-status <number> [status]
"""

import json
import subprocess
import sys
from datetime import date, timedelta

REPO = "Deltares/Ribasim"
OWNER = "Deltares"
PROJECT = 138
STATUSES = ["Todo", "In progress", "Review", "Done"]


def gh(*args: str) -> str:
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode != 0:
        if "project" in result.stderr and "scope" in result.stderr:
            sys.exit(
                "gh needs the project scope; ask the person you work for to run: "
                "gh auth refresh -s project"
            )
        sys.exit(result.stderr.strip())
    return result.stdout


def graphql(query: str, **variables: str | int) -> dict:
    # -F would turn an all-digit option ID into a number, so only ints use it
    args = []
    for key, value in variables.items():
        args += ["-F" if isinstance(value, int) else "-f", f"{key}={value}"]
    return json.loads(gh("api", "graphql", "-f", f"query={query}", *args))["data"]


PROJECT_QUERY = """
query($owner: String!, $number: Int!) {
  organization(login: $owner) {
    projectV2(number: $number) {
      id
      status: field(name: "Status") {
        ... on ProjectV2SingleSelectField { id options { id name } }
      }
      iteration: field(name: "Iteration") {
        ... on ProjectV2IterationField {
          id configuration { iterations { id title startDate duration } }
        }
      }
    }
  }
}
"""

ADD_ITEM = """
mutation($project: ID!, $content: ID!) {
  addProjectV2ItemById(input: {projectId: $project, contentId: $content}) {
    item { id }
  }
}
"""

SET_STATUS = """
mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
  updateProjectV2ItemFieldValue(input: {projectId: $project, itemId: $item,
    fieldId: $field, value: {singleSelectOptionId: $option}}) { clientMutationId }
}
"""

SET_ITERATION = """
mutation($project: ID!, $item: ID!, $field: ID!, $iteration: String!) {
  updateProjectV2ItemFieldValue(input: {projectId: $project, itemId: $item,
    fieldId: $field, value: {iterationId: $iteration}}) { clientMutationId }
}
"""


def current_iteration(iterations: list[dict]) -> dict:
    today = date.today()
    for iteration in iterations:
        start = date.fromisoformat(iteration["startDate"])
        if start <= today < start + timedelta(days=iteration["duration"]):
            return iteration
    sys.exit("The project board has no iteration for today.")


def main(number: str, status: str) -> None:
    if status not in STATUSES:
        sys.exit(f"Unknown status {status!r}, use one of {STATUSES}.")

    issue = json.loads(
        gh("issue", "view", number, "--repo", REPO, "--json", "id,assignees")
    )
    notes = []
    if status == "In progress":
        me = gh("api", "user", "--jq", ".login").strip()
        assignees = [a["login"] for a in issue["assignees"]]
        if not assignees:
            gh("issue", "edit", number, "--repo", REPO, "--add-assignee", "@me")
            notes.append(f"assigned to {me}")
        elif me not in assignees:
            sys.exit(
                f"#{number} is assigned to {', '.join(assignees)}. Check with them "
                "first; to work on it anyway, add yourself as assignee and rerun."
            )

    data = graphql(PROJECT_QUERY, owner=OWNER, number=PROJECT)
    project = data["organization"]["projectV2"]
    item = graphql(ADD_ITEM, project=project["id"], content=issue["id"])
    item_id = item["addProjectV2ItemById"]["item"]["id"]

    options = {o["name"]: o["id"] for o in project["status"]["options"]}
    graphql(
        SET_STATUS,
        project=project["id"],
        item=item_id,
        field=project["status"]["id"],
        option=options[status],
    )
    if status == "In progress":
        iterations = project["iteration"]["configuration"]["iterations"]
        iteration = current_iteration(iterations)
        graphql(
            SET_ITERATION,
            project=project["id"],
            item=item_id,
            field=project["iteration"]["id"],
            iteration=iteration["id"],
        )
        notes.append(iteration["title"])

    print(f"#{number}: {', '.join([status, *notes])}")


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2] if len(sys.argv) == 3 else "In progress")
