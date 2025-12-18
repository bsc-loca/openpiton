#!/usr/bin/env python3
import argparse
import sys
import re
from math import log2, ceil

# OpenPiton Constants
OP_L2_CACHELINE_SIZE = 64
OP_ADDR_SIZE = 40
OP_L15_TAG_WIDTH = 33 # Hardcoded to 33
OP_L15_DATA_WIDTH = 128 # 512b divided into 4x 128b sublines
OP_L2_DATA_WIDTH = 144 # 128b sublines + ECC

def clog2(num):
    return ceil(log2(num))

def csv_header(file):
    file.write("name,depth,width,count,port\n")

def l1i_srams(options, file):
    size = options.config_l1i_size
    ways = options.config_l1i_associativity
    line_size = options.config_l15_l1d_cacheline_size
    sets = ceil(size / line_size / ways)
    tag_width = OP_ADDR_SIZE - clog2(line_size) - clog2(sets)

    file.write(f'l1i_tag,{sets},{tag_width*ways},1,1\n')
    file.write(f'l1i_data,{sets},{line_size*8},{ways},1\n')

def l1d_srams(options, file):
    size = options.config_l1d_size
    ways = options.config_l1d_associativity
    line_size = options.config_l15_l1d_cacheline_size
    sets = ceil(size / line_size / ways)
    tag_width = OP_ADDR_SIZE - clog2(line_size) - clog2(sets) 
    dir_width = tag_width + 4
    data_depth = ceil(line_size/(options.hpdc_access_words*8)*options.hpdc_sets_per_ram)
    data_width = 64 * options.hpdc_ways_per_ramword
    data_count = options.hpdc_access_words * ceil(ways/options.hpdc_ways_per_ramword) * ceil(sets/options.hpdc_sets_per_ram)
    mshr_sets = ceil(options.l15_num_threads / options.hpdc_mshr_ways)
    mshr_width = options.hpdc_mshr_ways * (tag_width + options.hpdc_tid_width + options.hpdc_sid_width + clog2(line_size/8) + clog2(ways) + 3)
    file.write(f'l1d_dir,{sets},{dir_width},{ways},1\n')
    file.write(f'l1d_data,{data_depth},{data_width},{ways},1\n')
    file.write(f'l1d_mshr,{mshr_sets},{mshr_width},1,1\n')

def l15_srams(options, file):
    size = options.config_l15_size
    ways = options.config_l15_associativity
    line_size = options.config_l15_l1d_cacheline_size
    sets = ceil(size / line_size / ways)
    tag_width = OP_L15_TAG_WIDTH

    file.write(f'l15_tag,{sets},{tag_width*ways},1,1\n')
    file.write(f'l15_data,{sets*ways},{OP_L15_DATA_WIDTH},{4},1\n')

def l2_srams(options, file):
    size = options.config_l2_size
    ways = options.config_l2_associativity
    line_size = OP_L2_CACHELINE_SIZE
    sets = ceil(size / line_size / ways)
    tag_width = OP_ADDR_SIZE - clog2(line_size) - clog2(sets)
    cores = options.x_tiles * options.y_tiles
    owner_bit = int(1) if cores <= 2 else clog2(cores) 
    state_width = (owner_bit + 9) * ways + clog2(ways) + ways

    file.write(f'l2_tag,{sets},{tag_width*ways},1,1\n')
    file.write(f'l2_data,{sets*ways},{OP_L2_DATA_WIDTH},{4},1\n')
    file.write(f'l2_state,{sets},{state_width},1,2\n')
    file.write(f'l2_dir,{sets*ways},{cores},1,1\n')

def preprocess_config(contents: str, defines=None):
    comment_pattern = r"""
        //.*?$            |   # single-line comments
        /\*.*?\*/             # multi-line comments
    """
    contents_no_comment = re.sub(comment_pattern, "", contents, flags=re.DOTALL | re.MULTILINE | re.VERBOSE)

    if defines is None:
        defines = set()

    out = []
    skip = False

    for line in contents_no_comment.splitlines():
        stripped = line.strip()

        if stripped == '' or stripped.startswith("<"):
            continue
        elif stripped.startswith("#ifdef "):
            macro = stripped.split()[1]
            skip = macro not in defines
            continue
        elif stripped.startswith("#ifndef "):
            macro = stripped.split()[1]
            skip = macro in defines
            continue
        elif stripped.startswith("#endif"):
            skip = False
            continue
        elif skip:
            continue
        else:
            out.append(stripped)

    return out

class ReadConfigfile (argparse.Action):
    def __call__ (self, parser, namespace, values, option_string = None):
        with values as f:
            # parse arguments in the file and store them in the target namespace
            new_args = preprocess_config(f.read(), ["FLIST_SARG"])
            parser.parse_known_args(new_args, namespace)

def parse_args():
    parser = argparse.ArgumentParser(description="Get a list of SRAMs with sizes from an OpenPiton configuration file.")

    parser.add_argument("-x_tiles", type=int, help="Number of tiles in X direction")
    parser.add_argument("-y_tiles", type=int, help="Number of tiles in X direction")
    parser.add_argument("-sys", type=open, action=ReadConfigfile, help="System (manycore or hpc)")

    parser.add_argument("-config_l15_l1d_cacheline_size", type=int, help="L1 & L1.5 cacheline size in bytes")

    parser.add_argument("-config_l1i_size", type=int, help="L1 iCache size in bytes")
    parser.add_argument("-config_l1i_associativity", type=int, help="L1 iCache associativity")

    parser.add_argument("-config_l1d_size", type=int, help="L1 dCache size in bytes")
    parser.add_argument("-config_l1d_associativity", type=int, help="L1 dCache associativity")
    parser.add_argument("-hpdc_access_words", type=int, default=8, help="HPDC access words")
    parser.add_argument("-hpdc_sets_per_ram", type=int, help="HPDC number of sets per SRAM")
    parser.add_argument("-hpdc_ways_per_ramword", type=int, default=2, help="HPDC number of ways per SRAM word")
    parser.add_argument("-hpdc_mshr_ways", type=int, default=2, help="HPDC MSHR ways")
    parser.add_argument("-hpdc_tid_width", type=int, default=7, help="HPDC width of core tid")
    parser.add_argument("-hpdc_sid_width", type=int, default=3, help="HPDC width of core sid")

    parser.add_argument("-config_l15_size", type=int, help="L1.5 size in bytes")
    parser.add_argument("-config_l15_associativity", type=int, help="L.5 associativity")
    parser.add_argument("-l15_num_threads", type=int, help="L1 & L1.5 MSHRs")

    parser.add_argument("-config_l2_size", type=int, help="L2 size in bytes")
    parser.add_argument("-config_l2_associativity", type=int, help="L2 associativity")
    parser.add_argument("-l2_mshr_entries", type=int, help="L2 MSHRs")

    options, _ = parser.parse_known_args()

    if options.hpdc_sets_per_ram is None:
        options.hpdc_sets_per_ram = options.config_l1d_size / options.config_l15_l1d_cacheline_size / options.config_l15_associativity
    
    return options

def main():
    args = parse_args()

    with open("srams.csv", "w") as file:
        csv_header(file)
        l1i_srams(args, file)
        l1d_srams(args, file)
        l15_srams(args, file)
        l2_srams(args, file)

if __name__ == "__main__":
    main()