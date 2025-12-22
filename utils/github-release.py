import re
import subprocess


def git_describe() -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "describe", "--tags", "--exact-match"],
        capture_output=True,
        text=True,
    )


def main(proc: subprocess.CompletedProcess[str]):
    # Get the name of the currently checked out tag
    tag_name = proc.stdout.strip()

    print(f"Currently checked out tag: {tag_name}")

    # Define regex patterns for valid tag names
    # v20XX.X.X - minor must be 1-9
    normal_pattern = r"^v20\d{2}\.[1-9]\.\d$"
    # v20XX.X.X.devX or v20XX.X.XrcX - minor and prerelease digit must be 1-9
    dev_pattern = r"^v20\d{2}\.[1-9]\.\d\.dev[1-9]$"
    rc_pattern = r"^v20\d{2}\.[1-9]\.\drc[1-9]$"

    is_normal = re.match(normal_pattern, tag_name)
    is_prerelease = re.match(dev_pattern, tag_name) or re.match(rc_pattern, tag_name)

    if not (is_normal or is_prerelease):
        raise ValueError(
            f"Tag name '{tag_name}' does not match expected pattern. "
            f"Expected v20XX.X.X or v20XX.X.X.devX or v20XX.X.XrcX "
            f"(where minor and prerelease digits must be 1-9)"
        )

    # Build the command
    cmd = [
        "gh",
        "release",
        "create",
        tag_name,
        "--generate-notes",
    ]

    if is_prerelease:
        cmd.append("--prerelease")

    cmd.extend(
        [
            "ribasim_linux.zip",
            "ribasim_windows.zip",
            "ribasim_qgis.zip",
            "generated_testmodels.zip",
        ]
    )

    # Create a release using gh
    subprocess.check_call(cmd)


if __name__ == "__main__":
    proc = git_describe()
    if proc.returncode == 0 and proc.stdout.startswith("v20"):
        main(proc)
    else:
        print("Current checkout is not a tag starting with 'v20', no release made.")
        print(proc.stderr)
