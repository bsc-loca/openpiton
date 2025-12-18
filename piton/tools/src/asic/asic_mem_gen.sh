#!/usr/bin/env bash
# Usage: ./asic_mem_gen.sh <words> <bits>
# Example: ./asic_mem_gen.sh 1024 192

full_path=$(realpath "$0")
script_path=$(dirname "$full_path")


WORDS=$1
BITS=$2
PORTS=$3

PITON_ROOT=$(realpath "$script_path/../../../..")
ASIC_RAM_DIR="$PITON_ROOT/build/ASIC_RAMS" #can be changed to current directory if needed
default_asic_ram_dir="$PITON_ROOT/build/ASIC_RAMS"
ram_dir="$default_asic_ram_dir"
if [ -n "$ASIC_RAM_DIR" ]; then
    ram_dir="$ASIC_RAM_DIR"
fi

if [ $PORTS -eq 1 ]; then ram_v="$ram_dir/asic_ram_1p.sv"; fi
if [ $PORTS -eq 2 ]; then ram_v="$ram_dir/asic_ram_2p.sv"; fi

ram_flist="$ram_dir/flist.f"

if [[ -z "$WORDS" || -z "$BITS" || -z "$PORTS" ]]; then
    echo "Usage: $0 <words> <bits> <ports>"
    exit 1
fi

failed(){
    echo -e "\e[5;41m Error:\e[0m: $1!" >&2;
    exit 1;
}

run_cmd() {
    echo "[INFO] Running: $*"
    "$@" || { failed "Command failed: $* "; }
}

add_rtl() {
    rtl_code="$1"
    loop_name="$2"
    echo $rtl_code;

    if [ ! -f "$ram_v" ]; then
        echo "[error] File $ram_v not found!"
        return 1
    fi

    tmpfile=$(mktemp)

    awk '
        /generate/ {
            print
            while ((getline line < "/dev/fd/3") > 0) print line
            next
        }
        { print }
    ' 3<<< "$rtl_code" "$ram_v" > "$tmpfile" && mv "$tmpfile" "$ram_v"

    echo "[info] $loop_name is added to $ram_v file"
}

# ---------------------------------------------------------------------
# Single Port SRAM High Density Embedded (SRAM_SP_HDE) and
# Single Port Register File (RF_SP) memory compiler options
# ---------------------------------------------------------------------
# Table entries format:
# RamType Mux Banks Slices WordMin WordMax WordStep BitMin BitMax BitStep
# ---------------------------------------------------------------------
TABLE1=(
"SRAM_SP_HDE 2 4 2 512 2048 64 8 160 2"
"SRAM_SP_HDE 4 4 2 1024 4096 128 4 160 1"
"SRAM_SP_HDE 4 8 2 2048 8192 256 4 160 1"
"SRAM_SP_HDE 8 4 2 2048 8192 256 4 80 1"
"SRAM_SP_HDE 8 8 2 4096 16384 512 4 80 1"
"SRAM_SP_HDE 16 4 2 4096 16384 512 4 40 1"
"SRAM_SP_HDE 16 8 2 8192 32768 1024 4 40 1"
"RF_SP 2 1 1 16 512 8 8 80 2"
"RF_SP 2 1 2 16 512 8 8 160 2"
"RF_SP 2 2 2 256 1024 16 8 160 2"
"RF_SP 4 1 1 64 1024 16 4 80 1"
"RF_SP 4 1 2 64 1024 16 4 160 1"
"RF_SP 4 2 2 512 2048 32 4 160 1"
"RF_SP 8 1 1 128 2048 32 4 40 1"
"RF_SP 8 1 2 128 2048 32 4 80 1"
"RF_SP 8 2 2 1024 4096 64 4 80 1"
"RF_SP 16 1 1 256 4096 64 4 20 1"
"RF_SP 16 1 2 256 4096 64 4 40 1"
"RF_SP 16 2 2 2048 8192 128 4 40 1"
)

# ---------------------------------------------------------------------
# Dual Port SRAM High Speed Compiler (SRAM_2P) and
# Dual Port Register File High Speed Compiler (RF_2P) memory compiler options
# ---------------------------------------------------------------------
# Table2 entries format:
# RamType Mux Banks Slices WordMin WordMax WordStep BitMin BitMax BitStep
# ---------------------------------------------------------------------
TABLE2=(
    # ==============================
    # RF_2P: rf_2p_hsc_svt_mvt
    # ==============================
    # Multiplexers | Banking | Words (min:max) | Bits (min:max)
    # Note: RF_2P rows do not list “Slices” in the source table → set Slices=1
    "RF_2P 1 1 1 8 64 8 16 320  ?"
    "RF_2P 1 2 1 16 128  ? 16 320  ?"
    "RF_2P 1 4 1 66 256  ? 16 320  ?"
    "RF_2P 1 8 1 130 512 ? 16 320 ?"
    "RF_2P 2 2 1 32 256 ? 8 160 ?"
    "RF_2P 2 4 1 132 512 ? 8 160 ?"
    "RF_2P 2 8 1 260 1024 ? 8 160 ?"
    "RF_2P 4 2 1 64 512 ? 4 80 ?"
    "RF_2P 4 4 1 264 1024 ? 4 80 ?"
    "RF_2P 4 8 1 520 2048 ? 4 80 ?"
    "RF_2P 8 2 1 128 1024 ? 4 40 ?"
    "RF_2P 8 4 1 528 2048 ? 4 40 ?"
    "RF_2P 8 8 1 1040 4096 ? 4 40 ?"
    # ==============================
    # SRAM_2P: sram_2p_uhde_svt_mvt
    # ==============================
    # Multiplexer | Banking | Words | Bits
    # Slices = 1 (not given in original table)
    "SRAM_2P 2 1 1 32 2048 8 8 160 2"
    "SRAM_2P 4 1 1 64 4096 16 4 160 1"
    "SRAM_2P 8 1 1 128 8192 32 4 80 1"
)


best=""
if [[ "$PORTS" == "1" ]]; then
    TABLE=("${TABLE1[@]}")
elif [[ "$PORTS" == "2" ]]; then
    TABLE=("${TABLE2[@]}")
else
    failed "Unsupported PORTS value: $PORTS. Only 1 or 2 are supported."
fi

for entry in "${TABLE[@]}"; do
    set -- $entry
    RamType=$1; Mux=$2; Banks=$3; Slices=$4
    Wmin=$5; Wmax=$6; Wstep=$7
    Bmin=$8; Bmax=$9; Bstep=${10}

    # Replace "?" by 1
    [[ "$Wstep" == "?" ]] && Wstep=1
    [[ "$Bstep" == "?" ]] && Bstep=1

    # If needed for word/bits min/max too:
    [[ "$Wmin" == "?" ]] && Wmin=1
    [[ "$Wmax" == "?" ]] && Wmax=1
    [[ "$Bmin" == "?" ]] && Bmin=1
    [[ "$Bmax" == "?" ]] && Bmax=1

    # --- Words selection ---
    if (( WORDS < Wmin || WORDS > Wmax )); then
        continue
    fi
    # Round UP to nearest valid step
    offset=$(( ( (WORDS - Wmin + Wstep - 1) / Wstep ) * Wstep ))
    Wsel=$(( Wmin + offset ))
    if (( Wsel > Wmax )); then
        continue
    fi

    # --- Bits selection ---
    if (( BITS > Bmax )); then
        par=$(( (BITS + Bmax - 1) / Bmax ))   # number of parallel rams
        Bsel=$(( (BITS + par - 1) / par ))    # per-ram bit width
        # Round UP to nearest valid step
        if (( (Bsel - Bmin) % Bstep != 0 )); then
            Bsel=$(( ((Bsel - Bmin + Bstep - 1) / Bstep) * Bstep + Bmin ))
        fi
        if (( Bsel > Bmax )); then continue; fi
    else
        par=1
        Bsel=$BITS
        # Round UP to nearest valid step
        if (( (Bsel - Bmin) % Bstep != 0 )); then
            Bsel=$(( ((Bsel - Bmin + Bstep - 1) / Bstep) * Bstep + Bmin ))
        fi
        if (( Bsel < Bmin || Bsel > Bmax )); then continue; fi
    fi

    best="$par $RamType $Banks $Slices $Wsel $Bsel $Mux"
    break
done

if [ -z "$best" ]; then
    echo "No valid configuration found for Words=$WORDS Bits=$BITS"
    exit 1
fi

echo "Parallel RamType Banks Slices Words Bits Mux"
echo "$best"



# --- Fill variables ---
read parallel mem_type flex_bank flex_slice num_words num_bits mux<<< "$best"

#====================#
#                                                    #
#         PARAMETERS SETUP         #
#                                                    #
#====================#
# Compiler options: mem_type=RF_SP, RF_2P, SRAM_2P, SRAM_SP_HDE, SRAM_SP_UHDE
echo
echo "mem_type=$mem_type"
echo "num_words=$num_words"
echo "num_bits=$num_bits"
echo "mux=$mux"
echo "flex_bank=$flex_bank"
echo "flex_slice=$flex_slice"
echo "parallel=$parallel"

freq=2000

echo ""
echo "======================================================================="
echo "${mem_type}_${num_words}x${num_bits} (mux=$mux, flexible_banking=$flex_bank, flexible_slice=$flex_slice)"
echo "======================================================================="

target_dir="$ram_dir/${mem_type}_D${num_words}W${num_bits}"
mem_name="${mem_type}_${num_words}x${num_bits}_M${mux}B${flex_bank}S${flex_slice}"
loop_name="ram1p_${WORDS}x${BITS}_"

#########################
#  sram rtl instance gen
#########################
tmp1=$((parallel * num_bits -1))
tmp2=$((BITS-1))
if [[ "$PORTS" == "1" ]]; then
    rtl="    if ((DEPTH == ${WORDS}) && (DATA_WIDTH == ${BITS})) begin : ${loop_name}
        wire  [$tmp1 : 0] DI_tmp,BW_tmp,DO_tmp;
        assign DI_tmp [$tmp2 : 0] = DI;
        assign BW_tmp [$tmp2 : 0] = BW;
        assign DO = DO_tmp[$tmp2 : 0];"
else
    rtl="    if ((DEPTH == ${WORDS}) && (DATA_WIDTH == ${BITS})) begin : ${loop_name}
        wire  [$tmp1 : 0] DB_tmp, QA_tmp, BWB_tmp;
        assign DB_tmp [$tmp2 : 0] = DB;
        assign BWB_tmp [$tmp2 : 0] = BWB;
        assign QA = QA_tmp[$tmp2 : 0];"
fi 
for ((i=0; i<parallel; i++)); do
    low=$((i * num_bits))
    high=$(((i + 1) * num_bits - 1))
    #if (( high > BITS-1 )); then
    #    high=$((BITS-1))
    #fi
    if [[ "$PORTS" == "1" ]]; then
        rtl+="
        $mem_name the_RAM$i \`ARM7FF_SP_INTERFACE($high,$low)"
    else 
        rtl+="
        $mem_name the_RAM$i \`ARM7FF_2P_INTERFACE($high,$low)"
    fi
done
rtl+="
    end else "

#check if loop_name exited in if asic_ram_1p.sv
if grep -q "$loop_name" $ram_v; then
    echo "[INFO] Found $loop_name in $ram_v. Skip sram generation"
    exit 0
else
    echo "[INFO] $loop_name not found in $ram_v. Start memory generation"
fi


file_v="./${mem_type}_D${num_words}W${num_bits}/${mem_type}_${num_words}x${num_bits}_M${mux}B${flex_bank}S${flex_slice}.v"
if [ -f "$ram_dir/$file_v" ]; then
    echo "[info] ASIC memory exists, only add $loop_name to rtl"
    add_rtl "$rtl" "$loop_name"
    exit 0
fi


mkdir -p ${target_dir}
cd $target_dir

if [[ $mem_type = "RF_SP" ]]; then
    mem_path=/technos/ARM7FF/mem_compilers/rf_sp_hde_svt_mvt/r3p3/bin/rf_sp_hde_svt_mvt
    lib_name=rf_sp_hde
    corners=tt_0p75v_0p75v_85c,ssgnp_cworstccworstt_0p675v_0p675v_125c
fi
if [[ $mem_type = "RF_2P" ]]; then
    mem_path=/technos/ARM7FF/mem_compilers/rf_2p_hsc_svt_mvt/r4p0/bin/rf_2p_hsc_svt_mvt
    lib_name=rf_2p_hsc
    corners=tt_0p75v_0p75v_85c
fi
if [[ $mem_type = "SRAM_2P" ]]; then
    mem_path=/technos/ARM7FF/mem_compilers/sram_2p_uhde_svt_mvt/r1p0/bin/sram_2p_uhde_svt_mvt
    lib_name=sram_2p
    corners=tt_0p75v_0p75v_85c
fi
if [[ $mem_type = "SRAM_SP_HDE" ]]; then
    mem_path=/technos/ARM7FF/mem_compilers/sram_sp_hde_svt_mvt/r2p2/bin/sram_sp_hde_svt_mvt
    lib_name=sram_sp_hde
    corners=tt_0p75v_0p75v_85c
fi
if [[ $mem_type = "RAM_SP_UHDE" ]]; then
    mem_path=/technos/ARM7FF/mem_compilers/sram_sp_uhde_svt_mvt/r2p3/bin/sram_sp_uhde_svt_mvt
    lib_name=sram_sp_uhde
    corners=tt_0p75v_0p75v_85c
fi

#======================#
# 
#   COMPILATION COMMANDS
#
#======================#

common_args=(
    -name_case upper -bus_notation on -site_def off -diodes on -activity_factor 50
    -drive 6 -write_mask on -right_bus_delim "]"
    -pwr_gnd_rename vddpe:VDDPE,vddce:VDDCE,vsse:VSSE
    -redundancy off -wp_size 1 -prefix "" -ema on -ser none
    -check_instname off -bmux off -metal_stack 1X1Xa1Ya
    -cust_comment "" -retention on -atf off -libertyviewstyle nldm
    -left_bus_delim "[" -power_gating off -scan off -mvt HS
    -libname "$lib_name"
    -frequency "$freq"
    -words "$num_words"
    -bits "$num_bits"
    -mux "$mux"
    -flexible_banking "$flex_bank"
    -instname "${mem_type}_${num_words}x${num_bits}_M${mux}B${flex_bank}S${flex_slice}"
    -corners "$corners"
)

# Add flexible_slice only if PORTS == 1
if [[ "$PORTS" == "1" ]]; then
    common_args+=(-flexible_slice "$flex_slice")
fi

run_cmd $mem_path liberty   "${common_args[@]}"
run_cmd $mem_path postscript "${common_args[@]}"
run_cmd $mem_path lef-fp    "${common_args[@]}"
run_cmd $mem_path verilog   "${common_args[@]}"

cd -


#now add memory instant to asic_ram_1p.sv and update the filelist

add_rtl "$rtl" $loop_name
# Append to ram_flist (assuming it's a file)
echo "$file_v" >> "$ram_flist"

