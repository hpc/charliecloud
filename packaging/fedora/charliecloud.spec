# Charliecloud fedora package spec file
#
# Contributors:
#    Dave Love           @loveshack
#    Michael Jennings    @mej
#    Jordan Ogas         @jogas
#    Reid Priedhorksy    @reidpr

# Don't try to compile python files with /usr/bin/python
%{?el7:%global __python %__python3}

# Define libexecdir to ensure consistency.
%define _libexecdir %{_prefix}/libexec

# Specify python version of a given file
%define versionize_script() (sed -i 's,/env python,/env %1,g' %2)

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

%package   test
Summary:   Charliecloud examples and test suite
Requires:  %{name}%{?_isa} = %{version}-%{release}
Requires:  bats
Requires:  bash
Requires:  wget
Requires:  /usr/bin/python3

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

%{versionize_script python3 test/docs-sane}
%{versionize_script python3 test/make-auto}
%{versionize_script python3 test/make-perms-test}

%build
%make_build CFLAGS="%build_cflags -std=c11 -pthread" LDFLAGS="%build_ldflags"

%install
%make_install PREFIX=%{_prefix}

cat > README.EL7 <<EOF
For RHEL7 you must increase the number of available user namespaces to a non-
zero number (note the number below is taken from the default for RHEL8):

  echo user.max_user_namespaces=3171 >/etc/sysctl.d/51-userns.conf
  systemctl -p

Note for versions below RHEL7.6, you will also need to enable user namespaces:

  grubby --args=namespace.unpriv_enable=1 --update-kernel=ALL
  systemctl -p
EOF

%check

%files
%license LICENSE
%doc doc README.rst %{?el7:README.EL7}
%{_mandir}/man1/ch*

# Binaries and helper scripts
%{_libexecdir}/%{name}-%{version}/base.sh
%{_libexecdir}/%{name}-%{version}/version.sh
%{_bindir}/ch-*

%files test
%{_libexecdir}/%{name}-%{version}/examples
%{_libexecdir}/%{name}-%{version}/test
%exclude %{_datadir}/doc/%{name}-%{version}

%changelog
* Thu Mar 14 2019 <jogas@lanl.gov> @VERSION@-@RELEASE@
- Add initial Fedora/EPEL package.
