#!/bin/bash -l
### Script for running the open-closed coolings DrivAer with a static mesh
### Original authors: Charles Mockett, Hendrik Hetmann and Felix Kramer (Upstream CFD GmbH), 2022-2023
### Modified setup for OpenFOAM HPC Challenge (OHC-1): Mark Wasserman (Huawei) and Sergey Lesnik (Wikki GmbH), 2025

# Based on the geometry and setup of the AutoCFD4 Workshop:
# Hupertz, B., Chalupa, K., Krueger, L., Howard, K., Glueck, H.-D., Lewington, N., . . . Shin, Y.-s. (2021). On the Aerodynamics of the Notchback Open Cooling DrivAer: A Detailed Investigation of Wind Tunnel Data for Improved Correlation and Reference. SAE Int. J. Adv. & Curr. Prac. in Mobility, 3(4), 1726-1747. doi:https://doi.org/10.4271/2021-01-0958

### example for slurm submission
# adapt to your needs or ignore if not submitting to a queuing system
#SBATCH --job-name "DrivAer_RANS_1536"
##SBATCH --partition=arm
#SBATCH --output=%x-%j.out
#SBATCH --error=%x-%j.err

#SBATCH --nodes=8               # Number compute nodes on the cluster. 
#SBATCH --wckey=P3950.E.3.05.03  # PSP-Element    # PSP-Element

## Maximal allowed runtime
##SBATCH --time=72:00:00        # Expected runtime

## Advanced options:
##SBATCH --ntasks-per-node=192   # For small jobs < 1 mio cells, change to ~"cellnumber/10000" or smaller! (~ 1/2 or 1/4 or ... of a node)
#SBATCH --exclusive

### Solver
solverRANS="simpleFoam"

### Used directories
logDir="logFiles"

### Misc
fvSolution=fvSolution.fixedIter # fvSolution.fixedTol
controlDict=controlDict.noWrite # controlDict.withWrite
fileHandler=" "                 # "-fileHandler hostCollated "

# function to read parameters from caseDefinition...
function getInputParam ()
{
    varVal=`grep -w ${1} system/include/caseDefinition | cut -d ";" -f 1 | grep -v '//'`
    varVal=`echo ${varVal:${#1}}`
    echo $varVal
}

# get input parameters
nProcs=`getInputParam nCores`
TIMESTAMP=$(date "+%Y-%m-%d_%H-%M-%S")

# copy controlDict/fvSolution files

cp system/${controlDict} system/controlDict
cp system/${fvSolution} system/fvSolution

# extra mpi flags
OMPI_FLAGS="" #  "--mca pml ucx"

#parEx="mpirun -np ${nProcs} ${OMPI_FLAGS}"
parEx="srun -n ${nProcs}"
#source ~/OpenFOAM-v2406/etc/bashrc
source /sw/apps/openfoam/v2412/source_v2412

. ${WM_PROJECT_DIR:?}/bin/tools/RunFunctions

# ---- initialise & run simulation
mkdir $logDir
echo; echo "decomposePar"
time decomposePar -constant $fileHandler > $logDir/10_decomposePar.log 2>&1 || exit 1

echo; echo "restore 0 Directory"
restore0Dir -processor

echo; echo "renumberMesh"
time $parEx renumberMesh -constant -overwrite -parallel $fileHandler > $logDir/20_renumberMesh.log 2>&1 || exit 1

echo; echo "potentialFoam"
time $parEx potentialFoam -initialiseUBCs -parallel $fileHandler > $logDir/30_potentialFoam.log 2>&1 || exit 1

echo; echo "applyBoundaryLayer"
time $parEx applyBoundaryLayer -ybl "0.0450244" -parallel $fileHandler > $logDir/40_applyBoundaryLayer.log 2>&1 || exit 1

echo; echo $solverRANS
time $parEx $solverRANS -parallel $fileHandler > $logDir/50_$solverRANS.$TIMESTAMP.log 2>&1 || exit 1
echo "... done!"
