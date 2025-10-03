import os
import shutil
import hashlib
import sys

def clean_line(line):
    """Remove comments from a line (anything after //)."""
    return line.split("//", 1)[0].strip()

def get_file_hash(file_path):
    """Compute hash of a file to detect duplicates."""
    hasher = hashlib.md5()
    with open(file_path, "rb") as f:
        hasher.update(f.read())
    return hasher.hexdigest()

def append_to_filelist(file_name, flist_dst):
    """Append a file name to filelist_merge in order."""
    with open(flist_dst, "a") as f:
        f.write(file_name + "\n")

def append_to_awl(file_name, awl_file):
    """Append a file name to the AWL file (without path)."""
    with open(awl_file, "a") as f:
        f.write(f"waive -file {{ {file_name} }}\n")

def read_exclude_folders(exclude_file):
    """Read tracked folders from exclude_folders file."""
    if not os.path.isfile(exclude_file):
        print(f"Warning: {exclude_file} does not exist. No folders will be tracked.")
        return set()
    
    with open(exclude_file, "r") as f:
        return {line.strip() for line in f if line.strip()}

def process_filelist(filelist_path, dest_folder, include_folder, flist_dst, awl_file, tracked_folders, processed_files=set(), incdirs=set(), success_files=set(), fail_files=[]):
    """Recursively process filelists and copy files to appropriate folders."""
    filelist_path = os.path.abspath(filelist_path)

    if filelist_path in processed_files:
        return success_files, fail_files  # Avoid infinite recursion

    processed_files.add(filelist_path)

    os.makedirs(dest_folder, exist_ok=True)
    os.makedirs(include_folder, exist_ok=True)
    
    with open(filelist_path, 'r') as f:
        for line in f:
            line = clean_line(line)  # Remove comments
            if not line:  # Ignore empty lines
                continue

            # Expand environment variables in paths
            line = os.path.expandvars(line)

            # Handle nested filelists (-F or -f options)
            if line.startswith("-F") or line.startswith("-f"):
                nested_filelist_path = line[2:].strip()
                if os.path.isfile(nested_filelist_path):
                    success_files, fail_files = process_filelist(nested_filelist_path, dest_folder, include_folder, flist_dst, awl_file, tracked_folders, processed_files, incdirs, success_files, fail_files)
                else:
                    fail_files.append(nested_filelist_path)
                continue

            # Handle -v file references, copy only .v, .sv, .vhdl, .vhd files
            if line.startswith("-v"):
                file_path = os.path.abspath(line[2:].strip())
                if os.path.isfile(file_path):
                    if file_path.endswith((".v", ".sv")) and os.path.isfile(file_path):
                        try:
                            shutil.copy(file_path, dest_folder)
                            success_files.add(file_path)
                            append_to_filelist(os.path.basename(file_path), flist_dst)  # Add to filelist_merge
    
                            # Check if the file is from a tracked folder, add to AWL
                            if any(folder in file_path for folder in tracked_folders):
                                append_to_awl(os.path.basename(file_path), awl_file)
    
                        except Exception:
                            fail_files.append(file_path)
                            print(f"Failed to copy file [Unkown Reason]: {file_path}")
                    else:
                        fail_files.append(file_path)
                        print(f"Failed to copy file [not ending with .v or .sv]: {file_path}")
                else:
                    fail_files.append(file_path)
                    print(f"Failed to copy file [no file found]: {file_path}")
                continue

            # Handle include directories (+incdir+)
            if line.startswith("+incdir+"):
                incdir_path = os.path.abspath(line[8:].strip())
                if os.path.isdir(incdir_path):
                    incdirs.add(incdir_path)  # Store for later use
                else:
                    fail_files.append(incdir_path)
                continue

            # Process regular file paths
            file_path = os.path.abspath(line)

            if os.path.isfile(file_path):
                try:
                    # Copy to modules folder and add to filelist_merge
                    shutil.copy(file_path, dest_folder)
                    success_files.add(file_path)
                    append_to_filelist(os.path.basename(file_path), flist_dst)  # Add to filelist_merge

                    # Check if the file is from a tracked folder, add to AWL
                    if any(folder in file_path for folder in tracked_folders):
                        append_to_awl(os.path.basename(file_path), awl_file)

                except Exception:
                    fail_files.append(file_path)
            else:
                fail_files.append(file_path)


    # Copy all files from include directories (excluding .pyv files)
    for incdir in incdirs:
        for root, _, files in os.walk(incdir):
            for file in files:
                file_path = os.path.join(root, file)

                # Skip .pyv files when copying to include folder
                if file.endswith(".pyv"):
                    continue

                # Determine target directory
                if "axi" in os.path.basename(root):  # If folder name is "axi"
                    target_folder = os.path.join(include_folder, "axi")
                else:
                    target_folder = include_folder

                os.makedirs(target_folder, exist_ok=True)

                try:
                    shutil.copy(file_path, target_folder)
                    success_files.add(file_path)
                except Exception:
                    fail_files.append(file_path)

    return success_files, fail_files

def remove_duplicates_in_include(include_folder):
    """Remove duplicate files in the same folder (include or include/axi) based on content hash."""
    folder_hashes = {}  # Dictionary to store hashes separately for each folder
    removed_files = set()

    for root, _, files in os.walk(include_folder):
        folder_hashes[root] = {}  # Track hashes separately for each folder

        for file in files:
            file_path = os.path.join(root, file)

            # Compute file hash
            file_hash = get_file_hash(file_path)

            if file_hash in folder_hashes[root]:  # Check only within the same folder
                os.remove(file_path)  # Remove duplicate
                removed_files.add(file_path)
            else:
                folder_hashes[root][file_hash] = file_path  # Store hash in the folder scope

    return removed_files

def remove_duplicates_and_cleanup(filelist_merge_path, modules_dir):
    """Remove duplicate file entries in filelist_merge based on file content."""
    file_hashes = {}
    unique_files = []
    removed_files = set()

    with open(filelist_merge_path, "r") as f:
        file_entries = f.read().splitlines()

    for file_name in file_entries:
        file_path = os.path.join(modules_dir, file_name)
        if not os.path.isfile(file_path):  # Skip missing files
            continue

        file_hash = get_file_hash(file_path)
        if file_hash in file_hashes:
            os.remove(file_path)  # Remove duplicate file
            removed_files.add(file_name)
        else:
            file_hashes[file_hash] = file_path
            unique_files.append(file_name)

    # Rewrite filelist_merge without duplicates
    with open(filelist_merge_path, "w") as f:
        for file in unique_files:
            f.write(file + "\n")

    return removed_files

def main():
    # Ensure correct number of arguments
    if len(sys.argv) < 4:
        print("Usage: python script.py <filelist> <uncore_folder> <linting_script_folder>")
        sys.exit(1)

    flist = sys.argv[1]  # Get filelist from command-line argument
    uncore = sys.argv[2]  # Get filelist from command-line argument
    linting_script_folder = sys.argv[3] # Linting script folder
    # Read tracked folders from exclude_folders file
    exclude_folders_path = linting_script_folder+"/exclude_folders.txt"
    tracked_folders = read_exclude_folders(exclude_folders_path)

    # Define paths
    MODULES_DIR = uncore+"/modules"  # Destination directory for compiled files
    INCLUDE_DIR = uncore+"/include"  # Directory for +incdir+ files
    FILELIST_MERGE = uncore+"/filelist_merge"  # File to maintain module file order
    AWL_FILE = linting_script_folder+"/exclude_nonuncore_autogenerated.awl"  # AWL output file

    # 1. Remove the existing uncore folder before regenerating
    shutil.rmtree(uncore, ignore_errors=True)

    # 2. Remove the AWL file at the beginning to avoid appending
    if os.path.exists(AWL_FILE):
        os.remove(AWL_FILE)

    # 3. Process the filelist and copy files
    success_files, fail_files = process_filelist(flist, MODULES_DIR, INCLUDE_DIR, FILELIST_MERGE, AWL_FILE, tracked_folders)
    
    # 4. Remove duplicates from include folder
    remove_duplicates_in_include(INCLUDE_DIR)

    # 5. Remove duplicates from filelist_merge
    removed_files = remove_duplicates_and_cleanup(FILELIST_MERGE, MODULES_DIR)

    # Calculate the final success count
    final_success_count = len(success_files) - len(removed_files)
    # Print summary
    print("\nSummary:")
    print(f"Successfully copied: {len(success_files)} files")
    print(f"Failed to copy: {len(fail_files)} files")

    if fail_files:
        print("\nFailed files:")
        for file in fail_files:
            print(file)
        sys.exit(1) 

if __name__ == "__main__":
    main()