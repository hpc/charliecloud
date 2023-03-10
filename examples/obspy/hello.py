#!/usr/bin/env python3

# “Reading Seismograms” example from §3 of the ObsPy tutorial, with some of
# the prints commented out and taking the plot file from the command line.
#
# See: https://docs.obspy.org/tutorial/code_snippets/reading_seismograms.html

import sys


# §3.0

from obspy import read

st = read('RJOB_061005_072159.ehz.new')
#print(st)
#print(len(st))
tr = st[0]  # assign first and only trace to new variable
print(tr)

# §3.1

print(tr.stats)
#print(tr.stats.station)
#print(tr.stats.datatype)

# §3.2

#print(tr.data)
print(tr.data[0:3])
print(len(tr))

# §3.3

tr.plot(outfile=sys.argv[1])
