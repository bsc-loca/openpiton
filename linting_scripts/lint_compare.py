import os
import re
import sys

def extract_warnings_header(file_path):
    with open(file_path, 'r') as file:
        lines = file.readlines()

    for i in range(len(lines) - 2):  # Ensure we don't go out of index range
        line = lines[i].strip()
        next_line = lines[i + 1].strip()
        if line.startswith("-" * 77) and lines[i + 2].strip().startswith("-" * 77):
            if re.search(r"\(\d+ warnings/\d+ waived\)", next_line, re.IGNORECASE):
                print(next_line)


def extract_lint_data(file_path):
    with open(file_path, 'r') as file:
        lines = file.readlines()

    errors = []
    warnings = []
    current_category = None  # Track whether we're in "errors" or "warnings"
    i = 0

    while i < len(lines):
        line = lines[i].strip()

        # Detect category from error/warning/info headers
        if line.startswith("-" * 77) and i + 2 < len(lines) and lines[i + 2].strip().startswith("-" * 77):
            next_line = lines[i + 1].strip()
            if re.search(r"\(\d+ (error|errors|fatal|fatals)/\d+ waived\)", next_line, re.IGNORECASE):
                current_category = "errors"
            elif re.search(r"\(\d+ warning|warnings/\d+ waived\)", next_line, re.IGNORECASE):
                current_category = "warnings"
            elif re.search(r"\(\d+ info|infos/\d+ waived\)", next_line, re.IGNORECASE):
                current_category = None  # Ignore "infos" and other categories 
            i += 2

        # Detect block start (when encountering "Tag" after a separator)
        elif lines[i].strip().startswith("-" * 77) and i + 1 < len(lines) and lines[i + 1].strip().startswith("Tag"):
            j = 1
            while (i + j + 1 < len(lines) and
                   not lines[i + j].strip().startswith("-" * 77) and
                   lines[i + j].strip() != ""):
                j += 1

            # Extract the block
            block_lines = lines[i + 1:i + j]

            # Modify FileName line if found
            modified_block = []
            for block_line in block_lines:
                if block_line.strip().startswith("FileName"):
                    parts = block_line.split(":", 1)
                    if len(parts) == 2:
                        file_path = parts[1].strip()
                        file_name = os.path.basename(file_path)
                        modified_block.append(f"{parts[0]}: {file_name}\n")
                    else:
                        modified_block.append(block_line)
                else:
                    modified_block.append(block_line)

            if current_category == "errors":
                errors.append("".join(modified_block))
            elif current_category == "warnings":
                warnings.append("".join(modified_block))

            i += j  # Skip to the next possible block

        else:
            i += 1  # Move to the next line

    return errors, warnings



#This function removes lines starting with Violation and LineNumber before comparison
def normalize_errors(errors):
    normalized_errors = []
    for error in errors:
        modified_block = []
        for line in error.splitlines():
            stripped_line = line.strip()  # or line.lstrip() if you want to keep right-side formatting
            if stripped_line.startswith("LineNumber") or stripped_line.startswith("Violation"):
                continue
            modified_block.append(line+'\n')
        normalized_errors.append("".join(modified_block))
    return normalized_errors
    
    
    
def find_new_errors(errors_ref, errors_dut):
    normalized_ref = normalize_errors(errors_ref);
    normalized_dut = normalize_errors(errors_dut);
    
    new_errors = []
    for i, error in enumerate(normalized_dut):
        if error not in normalized_ref:  # If error is not found in reference set
            new_errors.append(errors_dut[i])

    return new_errors

def main():

    if len(sys.argv) < 4:
        print("Usage: python3 lint_compare.py <reference_linting_report> <dut_linting_report> <diff_linting_output>")
        sys.exit(1)

    file_path_ref = sys.argv[1]
    file_path_dut = sys.argv[2]
    output_file   = sys.argv[3]

    if not os.path.exists(file_path_ref):
        print(f"Error: {file_path_ref} not found.")
        #sys.exit(1)
        
    if not os.path.exists(file_path_dut):
        print(f"Error: {file_path_dut} not found.")
        #sys.exit(1)

        
    errors_ref = []
    errors_dut = []
    warnings_ref = []
    warnings_dut = []
    new_errors = []
    new_warnings = []
    
    errors_ref, warnings_ref = extract_lint_data(file_path_ref)
    errors_dut, warnings_dut = extract_lint_data(file_path_dut)
    
    # Find new errors
    new_errors   = find_new_errors(errors_ref, errors_dut)
    new_warnings = find_new_errors(warnings_ref, warnings_dut)
    
    if os.path.exists(output_file):
        os.remove(output_file)
        
    with open(output_file, "w") as f:
        f.write(f"Reference errors: {len(errors_ref)}\n")
        f.write(f"Reference warnings: {len(warnings_ref)}\n\n")
    
        f.write(f"DUT errors: {len(errors_dut)}\n")
        f.write(f"DUT warnings: {len(warnings_dut)}\n\n")
    
        f.write(f"New errors: {len(new_errors)}\n")
        f.write(f"New warnings: {len(new_warnings)}\n\n")
    
        if len(new_errors) > 0:
            f.write("\n  -----------------------------------------------------------------------------\n")
            f.write("  List of New Errors:\n")
            f.write("  -----------------------------------------------------------------------------\n")
            for error in new_errors:
                f.write(error + "\n")
                f.write("  -----------------------------------------------------------------------------\n")
    
        if len(new_warnings) > 0:
            f.write("\n  -----------------------------------------------------------------------------\n")
            f.write("  List of New Warnings:\n")
            f.write("  -----------------------------------------------------------------------------\n")
            for warning in new_warnings:
                f.write(warning + "\n")
                f.write("  -----------------------------------------------------------------------------\n")
           

    print(f"Relatively new errors: {len(new_errors)}")
    print(f"Relatively new warnings: {len(new_warnings)}")
    
    if len(new_errors) > 0 or len(new_warnings) > 0:
        print("\n \n \033[5;41m FAIL \033[0m\n ")
        print(f"For more information refer to {output_file}")
        sys.exit(1)
    else:
        print("\n \n \033[5;42m SUCCESS \033[0m\n \n ")        
        

if __name__ == "__main__":
    main()