# **Linting Scripts for Uncore/OpenPiton**

Linting_scripts folder contains a set of scripts and configurations for performing linting checks on the OpenPiton project in Uncore repo. 

---

## **Contents**

Linting_scripts folder includes the following key files:

- **Waiver Files**: These files (TCL or AWL format) define exceptions for specific linting rules.
- **`exclude_folders.txt`**: Includes folders which should be excluded from linting check.
- **`linting_report_ref.txt`**: Includes linting reports to be used as reference.
- **`lint_rules.tcl`**: Contains linting rules to be enforced during the analysis.
- **`lint_intel_grade.tcl`**: The main TCL script that runs the linting check using **Synopsys**.
- **`gen_files.py`**: Parses the project's filelist and collects all Verilog files into a designated folder.
- **`lint_checker.py`**: Analyzes the linting report and extracts the number of errors and warnings.
- **`lint_compare.py`**: Compares the linting report with `linting_report_ref.txt` and reports errors and warnings which do not exist in `linting_report_ref.txt`.
- **`Makefile`**: Defines the sequence of commands to perform the linting check.

---

## **Prerequisites**

### **1. Export Synopsys License**
Run the following command on `epi02` to export the Synopsys license:

```sh
source /apps/synopsys/lic_synopsys_epi.sh
```

### **2. Build with QuestaSim**
The design must be built with **QuestaSim** to generate the filelist and make environment variables visible to the linting scripts.

To build with QuestaSim (and Lox on `epi02`):

```sh
# Step 1: Export QuestaSim license
source /eda/env.sh

# Step 2: Set up OpenPiton environment for lox core
cd openpiton
source piton/lox_setup.sh

# Step 3: Build the project with lox core
cd build
sims -sys=manycore -x_tiles=1 -y_tiles=1 -msm_build -lox
```

---

## **Running the Linting Check**

### **1. Set Required Variables in the Makefile**
Before running the linting check, configure the following variables in the `Makefile`:

```make
FLIST = <path_to_design_flist>
REPORT_DIR = <path_to_report_folder>
UNCORE_MERGED_DIR = <path_to_verilog_files_folder>
```

### **2. Execute the Linting Check**
linting result comparison could be done in 2 ways, independent and relative.

- In the independent mode, the linting report is checked independently and the Fail or Pass is determined based on reported number of errors and warnings.
- In the relative mode, the linting report is compared with a reference linting report and the Fail or Pass is determined based on the  number of relatively new errors and warnings (errors and warnings that do not exist in the reference linting report).



Run the following command for an independent linting analysis:

```sh
make VC_IND
```

Run the following command for a relative linting analysis:

```sh
make VC_REL
```

In uncore we use `make VC_REL`

### **3. View Detailed Results**
After the linting check, you can review the detailed results in the following report files:

- **Linting Summary Report For Independent Mode**:  
  ```sh
  cat $(REPORT_DIR)/linting_report.txt
  ```

- **Linting Summary Report For Relative Mode**: 
  ```sh
  cat $(REPORT_DIR)/linting_report_relative.txt
  ```

---

## **Notes**
- Ensure all environment variables are correctly set before running the scripts.
- Modify `lint_rules.tcl` as needed to adjust the linting rules according to project requirements.
- If the linting check fails, depending on the mode, review `linting_report.txt` or `linting_report_relative.txt` to identify and resolve issues.

---
