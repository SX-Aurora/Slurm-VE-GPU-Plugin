# SX-Aurora Vector Engine SLURM Integration

## Contents
 - [Overview](#overview)
 - [Build and Install](#build-and-install)
   - [Build Within SLURM RPM](#build-within-slurm-rpm)
   - [Build Outside the SLURM RPM](#build-outside-the-slurm-rpm)
   - [Install Scripts](#install-scripts)
 - [Configure](#configure)
 - [Running non-MPI Jobs](#running-non-mpi-jobs)
 - [NEC-MPI in SLURM](#nec-mpi-in-slurm)
   - [Single Node](#single-node)
   - [Multiple Nodes](#multiple-nodes)
   - [VH-VE Hybrid MPI Jobs](#vh-ve-hybrid-mpi-jobs)


## Overview

The NEC SX-Aurora Vector Engine (VE) is an accelerator card in the
format of a double wide PCIe card, like GPUs, but with a different
approach to programming and usage. It can run entire programs in
native VE mode with just little support from the host (vector host,
VH), parallelized with OpenMP or pthreads, run MPI connected native VE
programs, hybrid MPI programs composed of processes running on x86_64
nodes and on VEs, or programs that run mainly on the VH and offload
parts of the computation to the VE (accelerator, offloading
mode). Managing and enforcing the allocation VEs in a cluster needs to
be possible for all the usage modes. This document describes ways of
adapting and configuring SLURM to support integrating VEs in most of
the possible usage scenarios.

There are several ways to integrate VE resource management with
SLURM. We decided to use the existing GPU GRES integration and adjust
it to set various VE specific environment variables. Unlike the [VE
GRES project](https://github.com/SX-Aurora/SX-Aurora-Slurm-Plugin)
this project does not add a different type of GRES for VE, but uses
the GPU GRES and expects that the Vector Engines are configured with a
type name of **ve**. The reason for this is that SLURM is ill prepared
for general accelerators as GRES but offers plenty of features for
GPUs that actually are interesting for all possible types of non-GPU
accelerators, like `--gpu-bind`, `--gpu-freq`, `--gpus-per-node`,
`--gpus-per-socket`, `--gpus-per-task`, `--mem-per-gpu`,
`--ntasks-per-gpu`, `--cpus-per-gpu`... Adding all these options for
the VE, a new type of accelerator managed through a different GRES
name would have meant to massively patch SLURM and replicate a lot of
GPU specific functionality. Whether SLURM will implement a more
generic accelerator support of which GPUs are just a subclass and
which can be extended by other accelerator types easily, is out of our
possibilities and scope. It would be desirable to have such a generic
GRES class with corresponding command line options and environment
variables.


NEC MPI is a critical component for the SLURM integration of Vector
Engines. It supports the execution of pure host programs, native VE
programs and VH-VE hybrid MPI programs and is deeply integrated with
NEC's NQSV batch resource manager and scheduler. Since NEC MPI is not
supporting currently any of SLURM's PMI2, PMIx or srun mechanisms,
it's ssh-based job startup would evade the resource enforcing and
monitoring of SLURM in multi-node jobs. We implemented a wrapper
(`smpirun`) which is using srun under the hood for starting NEC MPI's
mpid daemons, allowing SLURM to keep the job processes and resources
under control. For single node VE jobs the original `mpirun` command
can be used.


VE Offloaded programms using (A)VEO or VEDA which use only one VE
device should run with no issues as a SLURM job or step because the
environment variables `_VENODELIST` and `VEDA_VISIBLE_DEVICES` are
properly set. When submitting such programs to run in parallel under
multiple tasks of a job step they would need to have the environment
variable `VE_NODE_NUMBER` set accordingly in each of the job step
tasks. With the current SLURM implementation we can achieve this only
by using a TaskProlog script (see **Configure** section).


This approach of integrating Vector Engines with SLURM is aiming for
simplicity and minimal code changes. It has limitations and certainly
has flaws. We are happy to accept bug reports and contributions that
help improve it.



## Build and Install

### Build within SLURM RPM

Clone the VE gres plugin repository:
```
git clone https://github.com/sx-aurora/slurm-ve-gpu-plugin.git
```

Install build prerequisites for SLURM (these are useful defaults):
```
sudo yum install -y lua-devel pmix-devel
```

Adjust the SVER variable inside the top Makefile. Then type:
```
make slurm-rpms
```

This step downloads, unpacks and patches SLURM. The spec file is
modified, it gets the value of SREL as new release number, by default
this is: `1ve`. If you modify this value, change it such that it is
not equal to "1".

If everything went well, the SLURM RPMs end up in the RPMS
subdirectory. From there install them on the master node. If you
already had SLURM installed on the node, do:
```
cd RPMS
sudo rpm -Uhv slurm-*$SVER-$SREL*.rpm
cd ..
```

Otherwise it is recommendable to start with reading a guide like
https://slurm.schedmd.com/quickstart_admin.html .


Finally install the needed client SLURM RPMs on the client compute
nodes.



### Build outside the SLURM RPM

The alternative to building the SLURM RPMs is to use a SLURM tree
which has been already used for building SLURM, that means `configure`
and `make` has been called inside the source tree with appropriate
options. Such a source tree is stored in
`~/rpmbuild/BUILD/slurm-$SVER-$SREL` if you actually have built the
RPMs of SLURM as described in the previous section. Not having to
rebuild and install the SLURM RPMs every time is helpful during
development of the gres plugin.

Clone the VE gres repository:
```
git clone https://github.com/sx-aurora/slurm-ve-gpu-plugin.git
```

Build the `gres_gpu.so` plugin, only, while making sure to point the
variable `SLURM_SRC` to the 'built' source of SLURM:
```
cd slurm-ve-gpu-plugin
make plugin SLURM_SRC=~/rpmbuild/BUILD/slurm-20.11.6-1ve
```

Install the plugin by overwriting the old one from the RPM:
```
sudo make install-plugin
```

Now you'll need to propagate the plugin to the proper place on the
client compute nodes and restart the slurm `slurmd` daemons. On the
master node restart `slurmctld` as well.


### Install Scripts

Copy the `taskplugin.sh` script to the `/etc/slurm` directory and
`smpirun`, `vehcalist` to `/usr/bin`. These are needed on every node!
```
sudo make install-scripts
```


## Configure

Add the nodes GRES configuration to `/etc/slurm/gres.conf`, for example:
```
NodeName=aurora[0-7] Name=gpu Type=ve1 File=/dev/veslot0 Cores=0-5
NodeName=aurora[0-7] Name=gpu Type=ve1 File=/dev/veslot1 Cores=6-11
```

The GRES GPU Type name is used for specifying which kind of VE is
configured. Any name that starts with "ve" (lower case) will be
considered a vector engine, in this case we set the type to ve1. This
way we can differentiate between the vector engine generations. Just
setting `Type=ve` is also valid. When a VE is recognized in the
`gres_gpu` module, an alternative code path is executed and VE
specific environment variables are set in SLURM.


Configure the **cgroup** support in `/etc/slurm/cgroup.conf`:
```
CgroupAutomount=yes
ConstrainCores=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes
TaskAffinity=yes
ConstrainDevices=yes
```
This ensures (among others) that only the Aurora VE devices that
are assigned to a job are accessible to it.

Enable the gpu GRES plugin, enable the TaskPlugin and configure the
nodes in `/etc/slurm/slurm.conf`:
```
...
TaskProlog=/etc/slurm/taskprolog.sh
...
GresTypes=gpu
DebugFlags=NodeFeatures,Gres
...
NodeName=aurora[0-7] Gres=gpu:ve1:2 CPUs=24 Boards=1 SocketsPerBoard=1 CoresPerSocket=12 ThreadsPerCore=2 RealMemory=95116 State=UNKNOWN
```

Configure the VE to Infiniband HCA assignment in
`/etc/slurm/vehca.conf` of each node that has a VE. This can differ
from node to node. For example: a A300-2 with two VEs and one IB card
would assign all VEs to the same card:
```
# VE HCA assignment
0 1 => mlx5_0:1

# CPU HCA assignment
CPU => mlx5_0:1
```

On a A300-8 one can configure:
```
# VE HCAs
0 1 2 3 => mlx5_0:1
4 5 6 7 => mlx5_1:1
# CPU HCA
CPU => mlx5_0:1,mlx5_1:1
```

You could also assign two HCAs to each VE:
```
# VE HCAs
0 1 2 3 => mlx5_0:1,mlx5_1:1
4 5 6 7 => mlx5_1:1,mlx5_0:1
# CPU HCA
CPU => mlx5_0:1,mlx5_1:1
```
In the last example make sure there is only a comma between the HCAs
and no blank!

A CPU HCA assignment is needed for hybrid NEC-MPI jobs that use both,
VE and VH processes. Assigning it more selectively (per core) is
useless because the core assignment is not known inside a job step.


## Running non-MPI Jobs

These are the simplest cases of jobs which need VEs for running. They
can be started by either `srun`, `sbatch` or `salloc` with the proper
selection of resources. VEs are assigned to jobs entirely, are not
split by cores among jobs.

The following job script shows an example for submitting a simple
process that uses 1 VE and 2 CPU cores and uses 16GB of RAM on the
host for the job.

```
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --gpus=ve1:1
#SBATCH --mem-per-gpu=16G

srun ./veo_exec
```

If our job is a multi-VE but single node process, like a SOL-PyTorch
process, we could submit it from the command line as follows:
```
srun -N 1 -n 1 --gpus=ve1:4 --cpus-per-gpu=2 python resnet_train.py lot1
```


## NEC-MPI in SLURM

### Single Node

Single node NEC-MPI jobs require no communication through Infiniband
among the processes. Make sure to reserve the appropriate number of
VEs, CPUs, memory and simply call `mpirun` with appropriate parameters
inside the job script.

```
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gpus=ve1:2
#SBATCH --cpus-per-gpu=1
#SBATCH --mem-per-gpu=32G

mpirun -np 16 ./a.out
```

The `mpirun` command can use the arguments `-ve 0` or similar to
address the relative vector engine Id that is allocated inside the
job.

In the single node case it is possible to run MPI processes inside
interactive SLURM jobs, for example for debugging.


### Multiple Nodes

NEC-MPI jobs that require multiple vector hosts (VH) can not be
executed by calling `mpirun` inside SLURM. Besides needing a list of
hosts in the form of a machine file, `mpirun` would try to start on
each host a `mpid` daemon through `ssh`. The `mpid` would be a child
process of `sshd` and escape the control and restrictions of SLURM's
cgroups.

Our approach uses a wrapper script to `mpirun` which we called
`smpirun`. It uses the "batch" mode of NEC-MPI that allows `mpid`'s to
be started in advance through SLURM mechanisms (srun, actually), and
connect later to the `mpirun` binary and each other in a tree-like
hierarchy. Arguments to `smpirun` are simply passed to `mpirun`.

A simple example of a two node MPI job script that starts the
**a.out** VE process on 4 VEs spread over 2 nodes:
```
#!/bin/bash
#SBATCH -N 2
#SBATCH --gpus=ve1:4
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-gpu=8

smpirun -nn 2 -ppn 16 ./a.out myargs
```

The `smpirun` wrapper is creating a machinefile for the first `mpid`
in the current working directory. This file will be removed when
`smpirun` finishes.


**Limitations:**

Only one `mpid` is started on each VH node. SLURM can not use the
"logical-VH" concept of NEC's NQSV resource management system.

Multi-node NEC-MPI VE jobs cannot be run interactively in a
debugger. It is still possible to attach a debugger to an MPI process.



### VH-VE Hybrid MPI Jobs

NEC-MPI supports running heterogeneous MPI jobs consisting of VH
processes and VE processes. It requires using the heterogeneous job
features of SLURM and carefully selecting the heterogeneous steps'
resources.

SLURM heterogeneous jobs are composed of several job step resource
allocations, like in the example below:
```
#SBATCH --ntasks=1 --cpus-per-task=1 --mem-per-cpu=4g
#SBATCH hetjob
#SBATCH --nodes=2 --ntasks-per-node=1 --cpus-per-task=8 --gpus-per-node=ve1:2 --mem-per-cpu=1g -O
```

Here the first part of the hetjob requires one CPU and 4GB memory, the
second part requires 2 nodes with 2 VEs per node and 8 CPUs per node,
as well as 1GB memory per CPU. This resource allocation would match a
NEC-MPI hybrid process that schedules a single VH process followed by
VE processes that fill 4 VEs, for example:
```
smpirun -vh -np 1 ./exe.vh : -np 32 ./exe.ve
```

Some details behind the heterogeneous jobs:
* Each segment of the resource allocation can have different requirements.
* Hetjob segments should have only one jobstep task per node configured.
* Hetjob segments either require VEs (in which case they will run VE programs) or not. If not, they run VH programs). No mixing within a segment is possible.
* Hetjob segments should correspond to the NEC-MPI hybrid segments separated by ":".
* Each segment of the resource allocation is starting an `mpid` per jobstep-task. NEC-MPI hybrid processes running on VH (or another scalar node) communicate with the VE processes through Infiniband and need to belong to separate `mpid`s, even if running on the same node.

The SLURM backfilling algorithm has a problem with scheduling because it expects to be able to theoretically schedule each hetjob segment on different nodes. Therefore, if the cluster in the example above consists of just two nodes, the backfill scheduler will not be able to start because it needs one node for the first segment and two nodes for the second hetjob segment. Following quote from https://slurm.schedmd.com/heterogeneous_jobs.html explains the problem:

> The backfill scheduler has limitations in how it tracks usage of CPUs and memory in the future. This typically requires the backfill scheduler be able to allocate each component of a heterogeneous job on a different node in order to begin its resource allocation, even if multiple components of the job do actually get allocated resources on the same node.

