What is Charliecloud?
---------------------

Charliecloud provides user-defined software stacks (UDSS) for high-performance
computing (HPC) centers. This "bring your own software stack" functionality
addresses needs such as:

* software dependencies that are numerous, complex, unusual, diferently
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

This is done using Linux user namespaces to run industry-standard Docker
containers with no privileged operations or daemons and minimal configuration
changes on center resources. This simple approach avoids most security risks
while maintaining access to the performance and functionality already on
offer.

Because user namespaces are available only in newer kernel versions, an
experimental setuid mode is also provided to let sites evaluate Charliecloud
even if they do not have user namespace-capable kernels readily available.

How do I learn more?
--------------------

* Documentation: https://hpc.github.io/charliecloud

* GitHub repository: https://github.com/hpc/charliecloud

* We wrote an article for USENIX's magazine *;login:* that explains in more
  detail the motivation for Charliecloud and the technology upon which it is
  based: https://www.usenix.org/publications/login/fall2017/priedhorsky

* A more technical resource is our Supercomputing 2017 paper:
  http://permalink.lanl.gov/object/tr?what=info:lanl-repo/lareport/LA-UR-16-22370

Who is responsible?
-------------------

The core Charliecloud team at Los Alamos is:

* Reid Priedhorsky <reidpr@lanl.gov>, co-founder and BDFL
* Tim Randles <trandles@lanl.gov>, co-founder
* Michael Jennings <mej@lanl.gov>

Patches (code, documentation, etc.) contributed by:

* Reid Priedhorsky <reidpr@lanl.gov>
* Oliver Freyermuth <o.freyermuth@googlemail.com>
* Matthew Vernon <mv3@sanger.ac.uk>
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
