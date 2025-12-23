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
    normal_pattern = r"^v20\d{2}\.[1-9]\.\d{1,2}$"
    prerelease_pattern = r"^v20\d{2}\.[1-9]\.\d{1,2}-rc[1-9]\d?$"

    is_normal = re.match(normal_pattern, tag_name)
    is_prerelease = re.match(prerelease_pattern, tag_name)

    if not (is_normal or is_prerelease):
        raise ValueError(f"Tag name '{tag_name}' does not match expected pattern.")

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
