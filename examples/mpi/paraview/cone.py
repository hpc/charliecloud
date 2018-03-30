# Draw a cone and write it out to sys.argv[1] in a few different ways. All
# output files should be bit-for-bit reproducible, i.e., no embedded
# timestamps, hostnames, floating point error, etc.

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

# Even if you start multiple pvbatch using MPI, this script is only
# executed by rank 0. Check this assumption.
assert mpi4py.MPI.COMM_WORLD.rank == 0

# Output directory provided on command line.
outdir = sys.argv[1]

# Render a cone.
pv.Cone()
pv.Show()
pv.Render()
print("rendered")

# PNG image (serial).
filename = "%s/cone.png" % outdir
pv.SaveScreenshot(filename)
print(filename)

# Legacy VTK file (ASCII, serial).
filename = "%s/cone.vtk" % outdir
pv.SaveData(filename, FileType="Ascii")
print(filename)

# XML VTK files (parallel).
filename=("%s/cone.pvtp" % outdir)
writer = pv.XMLPPolyDataWriter(FileName=filename)
writer.UpdatePipeline()
print(filename)

# Done.
print("done")
