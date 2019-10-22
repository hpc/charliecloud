What is Charliecloud?
---------------------

Charliecloud provides user-defined software stacks (UDSS) for high-performance
computing (HPC) centers. This "bring your own software stack" functionality
addresses needs such as:

* software dependencies that are numerous, complex, unusual, differently
  configured, or simply newer/older than what the center provides;

* build-time requirements unavailable within the center, such as relatively
  unfettered internet access;

* validated software stacks and configuration to meet the standards of a
  particular field of inquiry;

* portability of environments between resources, including workstations and
  other test and development system not managed by the center;

* consistent environments, even archivally so, that can be easily, reliabily,
  and verifiably reproduced in the future; and/or

* usability and comprehensibility.

How does it work?
-----------------

Charliecloud uses Linux user namespaces to run containers with no privileged
operations or daemons and minimal configuration changes on center resources.
This simple approach avoids most security risks while maintaining access to
the performance and functionality already on offer.

Container images can be built using Docker or anything else that can generate
a standard Linux filesystem tree.

How do I learn more?
--------------------

* Documentation: https://hpc.github.io/charliecloud

* GitHub repository: https://github.com/hpc/charliecloud

* We wrote an article for USENIX's magazine *;login:* that explains in more
  detail the motivation for Charliecloud and the technology upon which it is
  based: https://www.usenix.org/publications/login/fall2017/priedhorsky

* A more technical resource is our Supercomputing 2017 paper:
  https://dl.acm.org/citation.cfm?id=3126925

Who is responsible?
-------------------

Contributors:

* Rusty Davis <rustyd@lanl.gov>
* Hunter Easterday <heasterday@lanl.gov>
* Oliver Freyermuth <o.freyermuth@googlemail.com>
* Shane Goff <rgoff@lanl.gov>
* Michael Jennings <mej@lanl.gov>
* Christoph Junghans <junghans@lanl.gov>
* Jordan Ogas <jogas@lanl.gov>
* Kevin Pelzel <kpelzel@lanl.gov>
* Reid Priedhorsky <reidpr@lanl.gov>, co-founder and project lead
* Tim Randles <trandles@lanl.gov>, co-founder
* Matthew Vernon <mv3@sanger.ac.uk>
* Peter Wienemann <wienemann@physik.uni-bonn.de>
* Lowell Wofford <lowell@lanl.gov>

How can I participate?
----------------------

Questions, comments, feature requests, bug reports, etc. can be directed to:

* our mailing list: *charliecloud@groups.io* or https://groups.io/g/charliecloud

* issues on GitHub

Patches are much appreciated on the software itself as well as documentation.
Optionally, please include in your first patch a credit for yourself in the
list above.

We are friendly and welcoming of diversity on all dimensions.

Copyright and license
---------------------

Charliecloud is copyright © 2014–2019 Triad National Security, LLC.

This software was produced under U.S. Government contract 89233218CNA000001
for Los Alamos National Laboratory (LANL), which is operated by Triad National
Security, LLC for the U.S. Department of Energy/National Nuclear Security
Administration.

This is open source software (LA-CC 14-096); you can redistribute it and/or
modify it under the terms of the Apache License, Version 2.0. A copy is
included in file LICENSE. You may not use this software except in compliance
with the license.

The Government is granted for itself and others acting on its behalf a
nonexclusive, paid-up, irrevocable worldwide license in this material to
reproduce, prepare derivative works, distribute copies to the public, perform
publicly and display publicly, and to permit others to do so.

Neither the government nor Triad National Security, LLC makes any warranty,
express or implied, or assumes any liability for use of this software.

If software is modified to produce derivative works, such derivative works
should be clearly marked, so as not to confuse it with the version available
from LANL.
