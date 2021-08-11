#!/usr/bin/env python3

# "Reading Seismograms" example from §3 of the ObsPy tutorial.
# See: https://docs.obspy.org/tutorial/code_snippets/reading_seismograms.html

# §3.0

from obspy import read
import sys

output_file = sys.argv[1]

stream = read('RJOB_061005_072159.ehz.new')
trace = stream[0]  # assign first and only trace to new variable
print(trace)

# §3.1

print(trace.stats)

# §3.2

print(trace.data[0:3])
print(len(trace))

# §3.3

trace.plot(outfile=output_file)
