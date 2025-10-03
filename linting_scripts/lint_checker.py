import re
import sys
import os

def extract_count(pattern, file_content):
    match = re.search(pattern, file_content, re.MULTILINE)
    if match:
        return int(match.group(1))  # Extracts the first capture group
    return 0

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 lint_checker.py <vc_static_file>")
        sys.exit(1)

    vc_static_file = sys.argv[1]

    try:
        with open(vc_static_file, "r", encoding="utf-8") as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: {vc_static_file} not found.")
        sys.exit(1)

    # Updated patterns without \K
    fatals_pattern = r"^..Total\s+(\d+)"  # Capture first number (Fatal count)
    errors_pattern = r"^..Total\s+\d+\s+(\d+)"  # Capture second number (Error count)
    warnings_pattern = r"^..Total\s+\d+\s+\d+\s+(\d+)"  # Capture third number (Warning count)

    fatals = extract_count(fatals_pattern, content)
    errors = extract_count(errors_pattern, content)
    warnings = extract_count(warnings_pattern, content)

    directory = os.path.dirname(vc_static_file)
    linting_file_name = 'linting_report.txt'
    linting_file_path = os.path.join(directory, linting_file_name)

    print(f"FATALS   : {fatals}")
    print(f"ERRORS   : {errors}")
    print(f"WARNINGS : {warnings}")

    if errors > 0 or fatals > 0:
        print(f"\n {errors} errors / {fatals} fatals found\n \n \033[5;41m FAIL \033[0m\n ")
        print(f"For more information refer to {linting_file_path}")
        sys.exit(1)
    elif warnings > 0:
        print(f"{warnings} warnings\n \n \033[5;41m FAIL \033[0m\n \n ")
        sys.exit(1)
    else:
        print(f"0 errors, {warnings} warnings\n \n \033[5;42m SUCCESS \033[0m\n \n ")

if __name__ == "__main__":
    main()
