#!/usr/bin/env python3
# Copyright 2019 ETH Zurich and University of Bologna.
# Copyright and related rights are licensed under the Solderpad Hardware
# License, Version 0.51 (the "License"); you may not use this file except in
# compliance with the License.  You may obtain a copy of the License at
# http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
# or agreed to in writing, software, hardware and materials distributed under
# this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.
#
# Author: Michael Schaffner <schaffner@iis.ee.ethz.ch>, ETH Zurich
# Date: 04.02.2019
# Description: Device tree generation script for OpenPiton+Ariane.


import pyhplib
import os
import subprocess
from pyhplib import *
import time

# this prints some system information, to be printed by the bootrom at power-on
def get_bootrom_info(devices, nCpus, cpuFreq, timeBaseFreq, periphFreq, dtsPath, timeStamp):

    if os.environ.get('PITON_ARIANE') == '1':
        core = 'Ariane'
        root =  os.environ['ARIANE_ROOT']
    elif os.environ.get('PITON_SARG') == '1':
        core = 'Sarg'
        root =  os.environ['SARG_ROOT']
    elif os.environ.get('PITON_LOX') == '1':
        core = 'Ox'
        root =  os.environ['LOX_ROOT']
    else :
        core = 'Unknown'
        root =  os.environ['PITON_ROOT']
     
    #root = os.environ[root_key]

    gitver_cmd = "git log | grep commit -m1 | LD_LIBRARY_PATH= awk -e '{print $2;}'"
    piton_ver  = subprocess.check_output([gitver_cmd], shell=True)
    core_ver =  subprocess.check_output(["cd %s && %s" % (root, gitver_cmd)], shell=True)

    # get length of memory
    memLen  = 0
    for i in range(len(devices)):
        if devices[i]["name"] == "mem":
            memLen  = devices[i]["length"]

    if 'PROTOSYN_RUNTIME_BOARD' in os.environ:
        boardName = os.environ['PROTOSYN_RUNTIME_BOARD']
        if not boardName:
            boardName = 'None (Simulation)'
    else:
        boardName = 'None (Simulation)'

    if 'CONFIG_SYS_FREQ' in os.environ:
        sysFreq = os.environ['CONFIG_SYS_FREQ']
        sysFreq = "%d MHz" % int(float(int(sysFreq))/1e6)
    else:
        sysFreq = "Unknown"

    tmpStr = f'''// Info string generated with get_bootrom_info(...)
// OpenPiton +  {core} framework
// Date: {timeStamp}

const char info[] = {{
"\\r\\n\\r\\n"
"----------------------------------------\\r\\n"
"--     OpenPiton+{core} Platform      --\\r\\n"
"----------------------------------------\\r\\n"
"OpenPiton Version: {piton_ver[0:8]}\\r\\n"
"{core:<9} Version: {core_ver[0:8]}\\r\\n"
"\\r\\n"
"Platform Info:\\r\\n"
"\tFPGA Board: {boardName}\\r\\n"
"\tBootrom Build Date: {timeStamp}\\r\\n"
"\tNetwork: {os.environ['PITON_NETWORK_CONFIG']}\\r\\n"
"\tDRAM Size: {memLen/1024/1024} MB\\r\\n"
"\\r\\n"
"Core Info:\\r\\n"
"\t#X-Tiles: {os.environ['PITON_X_TILES']}\\r\\n"
"\t#Y-Tiles: {os.environ['PITON_Y_TILES']}\\r\\n"
"\t#Cores:   {os.environ['PITON_NUM_TILES']}\\r\\n"
"\tCore Freq: {sysFreq}\\r\\n"
"\\r\\n"
"Cache Info:\\r\\n"
"\tL1I Size / Assoc: {int(os.environ['CONFIG_L1I_SIZE'])/1024:>4.0f} kB / {os.environ['CONFIG_L1I_ASSOCIATIVITY']:>2}\\r\\n"
"\tL1D Size / Assoc: {int(os.environ['CONFIG_L1D_SIZE'])/1024:>4.0f} kB / {os.environ['CONFIG_L1D_ASSOCIATIVITY']:>2}\\r\\n"
"\tL15 Size / Assoc: {CONFIG_L15_SIZE/1024:>4.0f} kB / {os.environ['CONFIG_L15_ASSOCIATIVITY']:>2}\\r\\n"
"\tL2  Size / Assoc: {int(os.environ['CONFIG_L1I_SIZE'])/1024:>4.0f} kB / {os.environ['CONFIG_L2_ASSOCIATIVITY']:>2}\\r\\n"
"\tL15/L1D Cacheline size: {os.environ['CONFIG_L15_L1D_CACHELINE_SIZE']}B\\r\\n"
"\\r\\n"
"MSHRs:\\r\\n"
"\tL1D: {os.environ['L15_NUM_THREADS']:>3}\\r\\n"
"\tL15: {os.environ['L15_NUM_THREADS']:>3}\\r\\n"
"\tL2:  {os.environ['L2_MSHR_ENTRIES']:>3}\\r\\n"
"\\r\\n"
"NoC Widths:\\r\\n"
"\tNoC 1: {os.environ['NOC1_WIDTH']:>3}b\\r\\n"
"\tNoC 2: {os.environ['NOC2_WIDTH']:>3}b\\r\\n"
"\tNoC 3: {os.environ['NOC3_WIDTH']:>3}b\\r\\n"
"\\r\\n"
"Additional features:\\r\\n"
"\tWrite Coalescing: {"Yes" if 'WRITE_BYTE_MASK' in os.environ else "No"}\\r\\n"
"\tParallel SRAMs: {"Yes" if 'PARALLEL_SRAMS' in os.environ else "No"}\\r\\n"
"\tL1 Data Cache: {"HPDcache" if 'PITON_ARIANE_HPDC' in os.environ else "WT_CACHE" if 'WT_CACHE' in os.environ else "Unknown"}\\r\\n"
"----------------------------------------\\r\\n\\r\\n\\r\\n"
}};

'''

    with open(dtsPath + '/info.h','w') as file:
        file.write(tmpStr)


# format reg leaf entry
def _reg_fmt(addrBase, addrLen, addrCells, sizeCells):

    assert addrCells >= 1 or addrCells <= 2
    assert sizeCells >= 0 or sizeCells <= 2

    tmpStr = " "

    if addrCells >= 2:
        tmpStr += "0x%08x " % (addrBase >> 32)

    if addrCells >= 1:
        tmpStr += "0x%08x " % (addrBase & 0xFFFFFFFF)

    if sizeCells >= 2:
        tmpStr += "0x%08x " % (addrLen >> 32)

    if sizeCells >= 1:
        tmpStr += "0x%08x " % (addrLen & 0xFFFFFFFF)

    return tmpStr

def gen_riscv_dts(devices, nCpus, cpuFreq, timeBaseFreq, periphFreq, dtsPath, timeStamp):

    assert nCpus >= 1

    # get UART base
    uartBase = 0xDEADBEEF
    for i in range(len(devices)):
        if devices[i]["name"] == "uart":
            uartBase = devices[i]["base"]


    tmpStr = '''// DTS generated with gen_riscv_dts(...)
// OpenPiton + Ariane framework
// Date: %s

/dts-v1/;

/ {
    #address-cells = <2>;
    #size-cells = <2>;
    u-boot,dm-pre-reloc;
    compatible = "openpiton,cva6platform";

    chosen {
    u-boot,dm-pre-reloc;
    stdout-path = "uart0:115200";
    };

    aliases {
        u-boot,dm-pre-reloc;
        console = &uart0;
        serial0 = &uart0;
    };

    cpus {
        #address-cells = <1>;
        #size-cells = <0>;
        u-boot,dm-pre-reloc;
        timebase-frequency = <%d>;
    ''' % (timeStamp, timeBaseFreq)

    for k in range(nCpus):
        tmpStr += '''
        CPU%d: cpu@%d {
            clock-frequency = <%d>;
            u-boot,dm-pre-reloc;
            device_type = "cpu";
            reg = <%d>;
            status = "okay";
            compatible = "openhwgroup, cva6", "riscv";
            riscv,isa = "rv64imafd";
            mmu-type = "riscv,sv39";
            tlb-split;
            // HLIC - hart local interrupt controller
            CPU%d_intc: interrupt-controller {
                #interrupt-cells = <1>;
                interrupt-controller;
                compatible = "riscv,cpu-intc";
            };
        };
        ''' % (k,k,cpuFreq,k,k)

    tmpStr += '''
    };
    '''

    # this parses the device structure read from the OpenPiton devices*.xml file
    # only get main memory ranges here
    for i in range(len(devices)):
        if devices[i]["name"] == "mem":
            addrBase = devices[i]["base"]
            addrLen  = devices[i]["length"]
            tmpStr += '''
    memory@%08x {
        u-boot,dm-pre-reloc;
        device_type = "memory";
        reg = <%s>;
    };
            ''' % (addrBase, _reg_fmt(addrBase, addrLen, 2, 2))

    for i in range(len(devices)):
        if devices[i]["name"] == "dma_pool":
            addrBase = devices[i]["base"]
            addrLen  = devices[i]["length"]
            # Small hack to be able to access the whole space defined in the devices.xml file
            # but still using just a fragment (256M) for particular dma pool.
            addrFrag  = devices[i]["fragment"]
            addrOnic  = addrBase + addrLen - addrFrag
            tmpStr += '''
    reserved-memory {
        #address-cells = <2>;
        #size-cells = <2>;
        ranges;
        
        eth_pool: eth_pool_node {
            reg = <%s>;
            compatible = "shared-dma-pool";
        }; 
        onic_pool: onic_pool_node {
            reg = <%s>;
            compatible = "shared-dma-pool";
        }; 
    };
            ''' % (_reg_fmt(addrBase, addrFrag, 2, 2),
                   _reg_fmt(addrOnic, addrFrag, 2, 2))
            #''' % (addrBase, _reg_fmt(addrBase, addrLen, 2, 2))

    tmpStr += '''
    eth0_clk: eth0_clk {
        compatible = "fixed-clock";
        #clock-cells = <0>;
        clock-frequency = <156250000>;
    };
    '''

    # TODO: this needs to be extended
    # get the number of interrupt sources
    # When using Ethernet + DMA, the number of IRQs for Ethernet is 2 instead of 1
    # TODO: Make a difference in the devices_$(core).xml between "net" and "dma_net", as the number of interrupts is different.
    # TODO: An alternative is to add a field in the device xml file that holds the number of interrupts.
    numIrqs = 0
    devWithIrq = ["uart", "net"];
    for i in range(len(devices)):
        if devices[i]["name"] in devWithIrq:
            numIrqs += 1
            if devices[i]["name"] == "net":
                numIrqs += 1


    # get the remaining periphs
    ioDeviceNr=1
    for i in range(len(devices)):
        # CLINT
        if devices[i]["name"] == "ariane_clint":
            addrBase = devices[i]["base"]
            addrLen  = devices[i]["length"]
            tmpStr += '''
        clint@%08x {
            u-boot,dm-pre-reloc;
            compatible = "riscv,clint0";
            interrupts-extended = <''' % (addrBase)
            for k in range(nCpus):
                tmpStr += "&CPU%d_intc 3 &CPU%d_intc 7 " % (k,k)
            tmpStr += '''>;
            reg = <%s>;
            reg-names = "control";
        };
            ''' % (_reg_fmt(addrBase, addrLen, 2, 2))
        # PLIC
        if devices[i]["name"] == "ariane_plic":
            addrBase = devices[i]["base"]
            addrLen  = devices[i]["length"]
            tmpStr += '''
        PLIC0: plic@%08x {
            u-boot,dm-pre-reloc;
            #address-cells = <0>;
            #interrupt-cells = <1>;
            compatible = "riscv,plic0";
            interrupt-controller;
            interrupts-extended = <''' % (addrBase)
            for k in range(nCpus):
                tmpStr += "&CPU%d_intc 11 &CPU%d_intc 9 " % (k,k)
            tmpStr += '''>;
            reg = <%s>;
            riscv,max-priority = <7>;
            riscv,ndev = <%d>;
        };
            ''' % (_reg_fmt(addrBase, addrLen, 2, 2), numIrqs)

        # UART
        # TODO: update uart sequence numbers
        if devices[i]["name"] == "uart":
            addrBase = devices[i]["base"]
            addrLen  = devices[i]["length"]
            tmpStr += '''
        uart0: uart@%08x {
            u-boot,dm-pre-reloc;
            compatible = "ns16550";
            reg = <%s>;
            clock-frequency = <%d>;
            current-speed = <115200>;
            interrupt-parent = <&PLIC0>;
            interrupts = <%d>;
            reg-shift = <0>; // regs are spaced on 8 bit boundary (modified from Xilinx UART16550 to be ns16550 compatible)
        };
            ''' % (addrBase, _reg_fmt(addrBase, addrLen, 2, 2), periphFreq, ioDeviceNr)
            ioDeviceNr+=1

        # sd card
        if devices[i]["name"] == "sd":
            addrBase = devices[i]["base"]
            addrLen  = devices[i]["length"]
            tmpStr += '''
        sdhci_0: sdhci@%08x {
            u-boot,dm-pre-reloc;
            status = "okay";
            compatible = "openpiton,piton-mmc";
            reg = <%s>;
        };
            ''' %(addrBase, _reg_fmt(addrBase, addrLen, 2, 2))

        # Ethernet
        if devices[i]["name"] == "net":
            addrBase = devices[i]["base"]
            addrLen  = devices[i]["length"]
            dmaChannelMM2S = addrBase + 0x0
            dmaChannelS2MM = addrBase + 0x30
            tmpStr += '''
        ethernet0 {
            xlnx,rxmem = <0x5f2>;
            carv,mtu = <0x5dc>;
            carv,no-mac;
            device_type = "network";       
            local-mac-address = [00 0a 35 23 07 84];
            axistream-connected = <0xfe>;
            compatible = "xlnx,xxv-ethernet-1.0-carv";
            memory-region = <&eth_pool>;
        };
        
        dma_eth: dma@%08x {
            xlnx,include-dre;
            phandle = <0xfe>;
            #dma-cells = <1>;
            compatible = "xlnx,axi-dma-1.00.a";
            clock-names = "s_axi_lite_aclk", "m_axi_mm2s_aclk", "m_axi_s2mm_aclk", "m_axi_sg_aclk";
            clocks = <&eth0_clk>, <&eth0_clk>, <&eth0_clk>, <&eth0_clk>;
            reg = <%s>;
            interrupt-names = "mm2s_introut", "s2mm_introut";
            interrupt-parent = <&PLIC0>;
            interrupts = <%d %d>;
            xlnx,addrwidth = <0x28>;
            xlnx,include-sg;
            xlnx,sg-length-width = <0x17>;
            
            dma-channel@%08x {
                compatible = "xlnx,axi-dma-mm2s-channel";
                dma-channels = <1>;
                interrupts = <%d>;
                xlnx,datawidth = <0x40>;
                xlnx,device-id = <0x00>;
                xlnx,include-dre;                        
            };
            
            dma-channel@%08x {
                compatible = "xlnx,axi-dma-s2mm-channel";
                dma-channels = <1>;
                interrupts = <%d>;
                xlnx,datawidth = <0x40>;
                xlnx,device-id = <0x00>;
                xlnx,include-dre;            
            };
        };
            ''' % (addrBase, _reg_fmt(addrBase, addrLen, 2, 2), ioDeviceNr, ioDeviceNr+1, dmaChannelMM2S, ioDeviceNr, dmaChannelS2MM, ioDeviceNr+1)
            ioDeviceNr+=2                       

    tmpStr += '''

    pmu {
        compatible = "riscv,pmu";
        riscv,event-to-mhpmevent = <0x3 0x0 0x22>,
                                   <0x4 0x0 0x26>,
                                   <0x5 0x0 0x2>,
                                   <0x6 0x0 0x1>,
                                   <0x10000 0x0 0x22>,
                                   <0x10001 0x0 0x26>,
                                   <0x10002 0x0 0x23>,
                                   <0x10003 0x0 0x27>,
                                   <0x10008 0x0 0x6>,
                                   <0x10009 0x0 0xd>,
                                   <0x10010 0x0 0x2c>,
                                   <0x10011 0x0 0x2b>,
                                   <0x10018 0x0 0x18>,
                                   <0x10019 0x0 0x19>,
                                   <0x10020 0x0 0x16>,
                                   <0x10021 0x0 0x17>;
        riscv,event-to-mhpmcounters = <0x3 0x6 0xfffffff8>,
                                      <0x10000 0x10003 0xfffffff8>,
                                      <0x10008 0x10011 0xfffffff8>,
                                      <0x10018 0x10021 0xfffffff8>;
        riscv,raw-event-to-mhpmcounters = <0x0 0x1 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x2 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x3 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x4 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x5 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x6 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x7 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x8 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x9 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0xa 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0xb 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0xc 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0xd 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0xe 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0xf 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x10 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x11 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x12 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x13 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x14 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x15 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x16 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x17 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x18 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x19 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x1a 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x1b 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x1c 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x1d 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x1e 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x1f 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x20 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x21 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x22 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x23 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x24 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x25 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x26 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x27 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x28 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x29 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x2a 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x2b 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x2c 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x2d 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x2e 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x2f 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x30 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x31 0xffffffff 0xffffffff 0xfffffff8>,
                                          <0x0 0x32 0xffffffff 0xffffffff 0xfffffff8>;
    };

};
    '''

    # this needs to match
    assert ioDeviceNr-1 == numIrqs

    with open(dtsPath + '/rv64_platform.dts','w+') as file:
        file.write(tmpStr)

def main():
    devices = pyhplib.ReadDevicesXMLFile()

    # just use a default frequency for device tree generation if not defined
    sysFreq = 50000000
    if 'CONFIG_SYS_FREQ' in os.environ:
        sysFreq = int(os.environ['CONFIG_SYS_FREQ'])

    timeStamp = time.strftime("%b %d %Y %H:%M:%S", time.localtime())
    gen_riscv_dts(devices, PITON_NUM_TILES, sysFreq, sysFreq/128, sysFreq, os.environ['DV_ROOT']+"/design/chipset/rv64_platform/bootrom/", timeStamp)
    get_bootrom_info(devices, PITON_NUM_TILES, sysFreq, sysFreq/128, sysFreq, os.environ['DV_ROOT']+"/design/chipset/rv64_platform/bootrom/", timeStamp)

if __name__ == "__main__":
    main()


