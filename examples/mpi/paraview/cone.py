# Draw a cone and write it out to sys.argv[1] in a few different ways. All
# output files should be bit-for-bit reproducible, i.e., no embedded
# timestamps, hostnames, floating point error, etc.
#
# Note that even if you start multiple pvbatch using MPI, this script is only
# executed by rank 0.

from __future__ import print_function

import os
import platform
import sys

import mpi4py.MPI
import paraview.simple as pv

# Version information.
print("ParaView %d.%d.%d on Python %s"
      % (pv.paraview.servermanager.vtkSMProxyManager.GetVersionMajor(),
         pv.paraview.servermanager.vtkSMProxyManager.GetVersionMinor(),
         pv.paraview.servermanager.vtkSMProxyManager.GetVersionPatch(),
         platform.python_version()))

# Which rank am I?
rank = mpi4py.MPI.COMM_WORLD.rank
def print_wrote(filename):
   print("rank %d: wrote %s" % (rank, filename))

# Output directory provided on command line.
outdir = sys.argv[1]

# Render a cone.
pv.Cone()
pv.Show()
pv.Render()
print("rank %d: rendered" % rank)

# PNG image (serial).
if (rank == 0):
   filename = "%s/cone.png" % outdir
   pv.SaveScreenshot(filename)
   print_wrote(filename)

# Legacy VTK file (ASCII, serial).
if (rank == 0):
   filename = "%s/cone.vtk" % outdir
   pv.SaveData(filename, FileType="Ascii")
   print_wrote(filename)

# XML VTK files (parallel).
filename=("%s/cone_%d.pvtp" % (outdir, rank))
writer = pv.XMLPPolyDataWriter(FileName=filename)
writer.UpdatePipeline()
print_wrote(filename)

# Done.
print("rank %d: done" % rank)
