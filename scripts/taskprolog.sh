#!/bin/bash
if [ -n "$_VENODELIST" ]; then
    declare -a VE_NODE_IDS
    VE_NODE_IDS=($_VENODELIST)
    NB_VE=${#VE_NODE_IDS[@]}
    LOCALID=$(( ${SLURM_LOCALID} % ${NB_VE} ))
    [ -z "${SLURMD_TRES_BIND}" ] && echo "export VE_NODE_NUMBER=${VE_NODE_IDS[$LOCALID]}"
    echo "export _NECMPI_VH_NODENUM=${SLURM_NODEID}"
fi
