# TODO: add comments: credit Dan Love, gripe about lack of 'recommends' or 
# 'suggests', running test suite, etc.

%define versionize_script() (sed -i 's,#!/bin/env python,#!/bin/%1,g' %2)

%bcond_with python3
%bcond_with test

%{!?build_cflags:%global build_cflags $RPM_OPT_FLAGS}
%{!?build_ldflags:%global build_ldflags %nil}

Name:           charliecloud
Version:        @VERSION@
Release:        @RELEASE@%{?dist}
Summary:        Lightweight user-defined software stacks for high-performance computing
License:        ASL 2.0
URL:            https://hpc.github.io/%{name}/
Source0:        https://github.com/hpc/%{name}/releases/download/v%{version}/%{name}-%{version}.tar.gz
BuildRequires:  gcc    >= 4.8.5
BuildRequires:  make   >= 3.82

%if %{with python3}
BuildRequires: python >= 3.4
%else
BuildRequires: python >= 2.7
%endif

%package test
Summary:       Charliecloud examples and test suite
Requires:      %{name}%{?_isa} = %{version}-%{release}
Requires:      bats >= 0.4.0
Requires:      bash >= 4.2.46
Requires:      wget >= 1.14

%if %{with python3}
Requires: python >= 3.4
%else
Requires: python >= 2.7
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
Charliecloud test suite and examples. The test suite will take advantage of
container image builders such as Docker, Skopeo, and Buildah.

%prep
%setup -q

%if %{with python3}
%{versionize_script python3 test/make-auto}
%else
%{versionize_script python2 test/make-auto}
%endif

%build
%make_build CFLAGS="%build_cflags -std=c11 -pthread" LDFLAGS="%build_ldflags"

%install
%make_install PREFIX=%{_prefix}

%check
%(ch-run --version)

# Don't try to complie python files with /usr/bin/python
%{?el7:%global __python %__python3}

cat > README.EL7 <<EOF
To run in RHEL7 you must increase the number of user available user namespaces
to a non-zero number (note the number below is take from the default for RHEL8):

  echo user.max_user_namespaces=3171 >/etc/sysctl.d/51-userns.conf
  # FIXME: Must we reboot?
  # FIXME: In our vagrant file we do set enable user namespaces via grubby,
  # do we still need to? 
EOF

%files
%license LICENSE
%doc %{_datadir}/doc/%{name}/LICENSE 
%doc %{_datadir}/doc/%{name}/README.rst 
%{?_el7:%doc ${_datadir}/%{name}/README.EL7}
%doc %{_mandir}/man1/ch*

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
%{_libexecdir}/%{name}/examples
%{_libexecdir}/%{name}/test
%exclude %{_libexecdir}/%{name}/examples/*/*.c
%exclude %{_libexecdir}/%{name}/test/*/*.c

%changelog
* Thu Mar 14 2019  <jogas@lanl.gov> 0.9.8-1
- Add initial Fedora/EPEL package.
