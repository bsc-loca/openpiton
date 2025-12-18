
include_dir=""
include_files=""
inc_opts=""

declare -A included_paths  # associative array to track processed includes 
n=0

process_flist() {
    local flist_in="$1"
    local dirname="$2"
    local src_hdl="$3"
    info "Processing file list: $flist_in"
    echo process_flist "$flist_in" "$dirname" "$src_hdl" 
    while IFS= read -r line || [ -n "$line" ]; do
        #echo "Processing line: $line"
        # Remove trailing newline
        line="${line//$'\r'/}"
        # Remove -v or -sv at the beginning
        line="${line#-v }"
        line="${line#-sv }"
        # Remove comments
        # Remove // comments but only if they start after whitespace or at the start
        line="$(sed 's:[[:space:]]\+//.*$::; s:^//.*$::' <<< "$line")"
        #replace linux variables
        line=$(eval echo "$line")
        # Remove leading/trailing spaces
        line="${line#"${line%%[![:space:]]*}"}"   # remove leading spaces
        line="${line%"${line##*[![:space:]]}"}"   # remove trailing spaces
        # Replace ./ with $dirname
        line="${line/#.\//$dirname/}"
        line="${line/-F .\//-F $dirname/}"
        line="${line/-f .\//-f $dirname/}"
        # Fix +incdir+./ replacement
        line="${line/+incdir+./+incdir+$dirname/}"
        # Remove /./
        line="${line//\/.\//\/}"
        # Remove double slashes
        line="$(echo "$line" | sed 's|//\+|/|g')"
        # Skip empty lines
        [[ -z "$line" ]] && continue
        # skip exceptions
        for ex in "${flist_exceptions[@]}"; do
            if [[ "$line" =~ $ex ]]; then
                echo "Skipping exception file: $line"
                continue 2   # continue loop of outer context
            fi
        done
        # Handle +incdir+
        if [[ "$line" =~ ^\+incdir\+ ]]; then
            include="${line#+incdir+}"
            ff="$include"
            [[ -d "$dirname/$include" ]] && include="$dirname/$include"
            include=$(realpath "$include" 2>/dev/null) || {
                warning " parsing flist:$flist_in, line:$line: Invalid include path: $include"
                continue
            }
            # Skip if already processed
            if [[ -n "${included_paths[$include]}" ]]; then
                echo "Exclude $include"
                continue
            fi
            # Mark as processed
            included_paths["$include"]=1
            include_abs=$(readlink -f "$include")
            dirname_abs=$(readlink -f "$dirname")
            name=$(basename "$include")
            if [[ "$include_abs" == "$dirname_abs w" ]]; then
                echo "$line"
                echo "$include_abs == $dirname_abs"
                echo "+incdir+$dirname" 
                #echo "+incdir+$dirname" >> "$FLIST_OUT"
            else
                #echo "$include_abs == $dirname_abs"
                #echo "mkdir -p $new_folder && cp -r $include/* $new_folder/"
                new_folder="$src_hdl/f$n/$name"
                if [[ -d "$include" ]]; then
                    run_cmd mkdir -p "$new_folder"
                    run_cmd rsync -av   \
                        --include='*/' \
                        --include='*.svh' \
                        --include='*.sv' \
                        --include='*.v' \
                        --include='*.h' \
                        --include='*.vh' \
                        --exclude='*' \
                        "$include"/ "$new_folder"/
                fi
                # echo "+incdir+$new_folder" >> "$FLIST_OUT"
                if [ "$name" != ".." ]; then 
                    inc_opts="$inc_opts 
lappend search_path \$SRC_HDL/f$n/$name"
                ((n++))
                fi
            fi
        # Handle regular files
        elif [[ -f "$line" || -f "$dirname/$line" ]]; then
            [[ -f "$dirname/$line" ]] && line="$dirname/$line"
            name=$(basename "$line")
            ext="${name##*.}"
            new_file="$src_hdl/$name"
            #if [[ -f "$new_file" ]]; then
            #echo "$new_file"
            #       new_file="$src_hdl/f$n/$name"
            #       mkdir -p "$src_hdl/f$n"
            #       ((n++))
            #else
                cp "$line" "$new_file" || { echo "Copy failed: $line"; exit 1; }
                #echo "$new_file" >> "$FLIST_OUT"
                if [[ "$ext" == "v" || "$ext" == "sv" || "$ext" == "h" ]]; then
                    include_files="$include_files
$name"
                fi
            #fi
        # Handle -F (file of file list)
        elif [[ "$line" =~ ^-F ]]; then
            fname="${line#-F }"
            [[ -f "$dirname/$fname" ]] && fname="$dirname/$fname"
            fdir=$(dirname "$fname")
            process_flist "$fname" "$fdir" "$src_hdl" 

        # Handle -f (file of file list)
        elif [[ "$line" =~ ^-f ]]; then
            fname="${line#-f }"
            [[ -f "$dirname/$fname" ]] && fname="$dirname/$fname"
            fdir=$(dirname "$fname")
            process_flist "$fname" "$fdir" "$src_hdl" 

        else
            failed "Cannot convert $line to the new filelist."
        fi
    done < "$flist_in"
}