import re


def _pascal_to_snake(pascal_str):
    # Insert a '_' before all uppercase letters that are not at the start of the string
    # and convert the string to lowercase
    return re.sub(r"(?<!^)(?=[A-Z])", "_", pascal_str).lower()


class MissingOptionalModule:
    """Presents a clear error for optional modules."""

    def __init__(self, name):
        self.name = name

    def __getattr__(self, name):
        raise ImportError(f"{self.name} is required for this functionality")
