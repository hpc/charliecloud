#!/usr/bin/env python3

# "Reading Seismograms" example from §3 of the ObsPy tutorial.
# See: https://docs.obspy.org/tutorial/code_snippets/reading_seismograms.html

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

tr.plot(outfile="/mnt/obspy.pdf")
