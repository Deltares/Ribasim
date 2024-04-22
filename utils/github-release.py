import subprocess


def current_git_branch():
    result = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def main():
    # Get the name of the currently checked out tag
    tag_name = subprocess.check_output(
        ["git", "describe", "--tags", "--exact-match"], text=True
    ).strip()

    print(f"Currently checked out tag: {tag_name}")

    # Create a release using gh
    subprocess.check_call(
        [
            "gh",
            "release",
            "create",
            tag_name,
            "--generate-notes",
            "ribasim_cli_linux.zip",
            "ribasim_cli_windows.zip",
            "ribasim_qgis.zip",
            "generated_testmodels.zip",
        ]
    )


if __name__ == "__main__":
    if current_git_branch().startswith("v20"):
        main()
    else:
        print("Branch doesn't start with 'v20', no release made.")
