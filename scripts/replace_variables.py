#!/usr/bin/env python3
"""
Script to replace variables in Markdown files with values from a JSON configuration file.

Variables in Markdown files should be formatted as {{{ .path.to.variable }}} and will be replaced with corresponding values from the JSON file.
"""

import json
import re
import sys
from pathlib import Path
from typing import Any


def create_variable_replacer(variables_file: Path):
    """
    Create a regex replacement function that replaces variable placeholders with actual values.

    Args:
        variables_file (Path): Path to JSON file containing variable definitions

    Returns:
        function: A replacement function for use with re.sub()
    """
    with open(variables_file, "r") as f:
        variables: dict[str, Any] = json.load(f)

    def replace_variable_match(match: re.Match) -> str:
        """
        Replace a single variable match with its value from the configuration.

        Args:
            match: Regex match object containing the variable path

        Returns:
            str: The variable value as a string
        """
        variable_path = match.group(1).strip()
        path_segments = variable_path.split(".")
        current_value = variables

        # Traverse through the nested dictionary structure using path segments.
        for segment in path_segments:
            if segment not in current_value:
                raise KeyError(f"Variable {variable_path} is not defined in the configuration file.")
            current_value = current_value[segment]

        # Ensure the final value is a string before returning it.
        if isinstance(current_value, str):
            return current_value
        raise ValueError(f"Variable {variable_path} exists but its value is not a string.")

    return replace_variable_match


def replace_variables(target_path: Path, variables_file: Path):
    """
    Replace all variables in Markdown files with their actual values.

    Variables are defined in a JSON file and referenced in Markdown files using the syntax {{{ .path.to.variable }}}.

    Args:
        target_path (Path): File or directory path to process
        variables_file (Path): Path to JSON file with variable definitions
    """
    variable_replacer = create_variable_replacer(variables_file)
    variable_pattern = re.compile(r"{{{\s*\.(.+?)\s*}}}")

    markdown_files = []

    if target_path.is_file():
        if target_path.suffix == ".md":
            markdown_files = [target_path]
    elif target_path.is_dir():
        markdown_files = target_path.glob("**/*.md")
    else:
        print(f"Error: The target path {target_path} is not a valid file or directory.")
        sys.exit(1)

    for file_path in markdown_files:
        with open(file_path, "r") as f:
            file_content = f.read()
        new_content = re.sub(variable_pattern, variable_replacer, file_content)
        with open(file_path, "w") as f:
            f.write(new_content)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <target_path> <variables_file>")
        sys.exit(1)

    replace_variables(Path(sys.argv[1]), Path(sys.argv[2]))
