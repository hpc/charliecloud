# Charliecloud fedora package spec file
#
# Contributors:
#    Dave Love           @loveshack
#    Michael Jennings    @mej
#    Jordan Ogas         @jogas
#    Reid Priedhorksy    @reidpr


# Since SUSE conditionals are not allowed by Fedora we define the libexecdir 
# to ensure proper building.
%define _libexecdir %{_prefix}/libexec

# Fedora requires python files to specify a version, e.g., /usr/bin/python3,
# /usr/bin/python2.
%define versionize_script() (sed -i 's,/env python,/%1,g' %2)

# Enable users with spec file to build with python2.
%bcond_with python2

%{!?build_cflags:%global build_cflags $RPM_OPT_FLAGS}
%{!?build_ldflags:%global build_ldflags %nil}

Name:           charliecloud
Version:        @VERSION@
Release:        @RELEASE@%{?dist}
Summary:        Lightweight user-defined software stacks for high-performance computing
License:        ASL 2.0
URL:            https://hpc.github.io/%{name}/
Source0:        https://github.com/hpc/%{name}/releases/download/v%{version}/%{name}-%{version}.tar.gz
BuildRequires:  gcc

%if %{with python2}
BuildRequires: /usr/bin/python2
%else
BuildRequires: /usr/bin/python3
%endif

%package test
Summary:   Charliecloud examples and test suite
Requires:  %{name}%{?_isa} = %{version}-%{release}
Requires:  bats
Requires:  bash
Requires:  wget

%if %{with python2}
Requires: /usr/bin/python2
%else
Requires: /usr/bin/python3
%endif

%description
Charliecloud uses Linux user namespaces to run containers with no privileged
operations or daemons and minimal configuration changes on center resources.
This simple approach avoids most security risks while maintaining access to
the performance and functionality already on offer.

Container images can be built using Docker or anything else that can generate
a standard Linux filesystem tree.

For more information: https://hpc.github.io/charliecloud/

%description test
Charliecloud test suite and examples. The test suite takes advantage of
container image builders such as Docker, Skopeo, and Buildah.

%prep
%setup -q

%if %{with python2}
%{versionize_script python2 test/make-auto}
%{versionize_script python2 test/make-perms-test}
%else
%{versionize_script python3 test/make-auto}
%{versionize_script python3 test/make-perms-test}
%endif

%build
%make_build CFLAGS="%build_cflags -std=c11 -pthread" LDFLAGS="%build_ldflags"

%install
%make_install PREFIX=%{_prefix}

%check

# Don't try to compile python files with /usr/bin/python
%if %{with python2}
%{?el7:%global __python %__python2}
%else
%{?el7:%global __python %__python3}
%endif

cat > README.EL7 <<EOF
For RHEL7 you must increase the number of available user namespaces to a non-
zero number (note the number below is taken from the default for RHEL8):

  echo user.max_user_namespaces=3171 >/etc/sysctl.d/51-userns.conf
  systemctl -p

Note for versions below RHEL7.6, you will also need to enable user namespaces:

  grubby --args=namespace.unpriv_enable=1 --update-kernel=ALL
  systemctl -p
EOF

# README for test suite; obsolete in 0.9.9.
cat > README.tests <<EOF
Charliecloud comes with a fairly comprehensive Bats test suite. For testing
instructions visit: https://hpc.github.io/charliecloud/test.html
EOF

%files
%license LICENSE
%doc README.rst %{?el7:README.EL7}
%{_mandir}/man1/ch*
%exclude %{_datadir}/doc/%{name}

# Helper scripts
%{_libexecdir}/%{name}/base.sh
%{_libexecdir}/%{name}/version.sh
%{_bindir}/ch-build
%{_bindir}/ch-build2dir
%{_bindir}/ch-docker2tar
%{_bindir}/ch-fromhost
%{_bindir}/ch-pull2dir
%{_bindir}/ch-pull2tar
%{_bindir}/ch-tar2dir

# Binaries
%{_bindir}/ch-run
%{_bindir}/ch-ssh

%files test
%doc README.tests
%{_libexecdir}/%{name}/examples
%{_libexecdir}/%{name}/test
%exclude %{_datadir}/doc/%{name}

%changelog
* Thu Mar 14 2019  <jogas@lanl.gov> 0.9.8-1
- Add initial Fedora/EPEL package.
