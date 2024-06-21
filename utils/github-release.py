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

    # Create a release using gh
    subprocess.check_call(
        [
            "gh",
            "release",
            "create",
            tag_name,
            "--generate-notes",
            "ribasim_linux.zip",
            "ribasim_windows.zip",
            "ribasim_qgis.zip",
            "generated_testmodels.zip",
        ]
    )


if __name__ == "__main__":
    proc = git_describe()
    if proc.returncode == 0 and proc.stdout.startswith("v20"):
        main(proc)
    else:
        print("Current checkout is not a tag starting with 'v20', no release made.")
        print(proc.stderr)
