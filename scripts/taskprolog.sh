#!/bin/bash
if [ -n "$_VENODELIST" ]; then
    declare -a VE_NODE_IDS
    VE_NODE_IDS=($_VENODELIST)
    echo "export VE_NODE_NUMBER=${VE_NODE_IDS[$SLURM_LOCALID]}"
    echo "export _NECMPI_VH_NODENUM=${SLURM_NODEID}"
fi
