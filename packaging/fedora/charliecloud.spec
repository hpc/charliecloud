Name:           charliecloud
Version:        @VERSION@
Release:        @RELEASE@%{?dist}
Summary:        Lightweight user-defined software stacks for high-performance computing
License:        ASL 2.0
URL:            https://hpc.github.io/%{name}/
Source0:        https://github.com/hpc/%{name}/archive/v%{version}/%{name}-%{version}.tar.gz
BuildRequires:  gcc  >= 4.8.5
BuildRequires:  make >= 3.82

%package doc
Summary:        Charliecloud examples and test suite
Requires:       %{name} = %{version}
Requires:       bats >= 0.4.0
Requires:       bash >= 4.2.46
Requires:       wget >= 1.14

%description
Charliecloud uses Linux user namespaces to run containers with no privileged
operations or daemons and minimal configuration changes on center resources.
This simple approach avoids most security risks while maintaining access to
the performance and functionality already on offer.

Container images can be built using Docker or anything else that can generate
a standard Linux filesystem tree.

For more information: https://hpc.github.io/charliecloud/

%description doc
Charliecloud test suite and examples.

# Voodoo to stop our python scripts from being byte compiled on Centos7, which
# otherwise results in rpmbuild failing to build the package. see:
# https://github.com/scylladb/scylla/issues/2235
%global __os_install_post    \
     /usr/lib/rpm/redhat/brp-compress \
     %{!?__debug_package:\
     /usr/lib/rpm/redhat/brp-strip %{__strip} \
     /usr/lib/rpm/redhat/brp-strip-comment-note %{__strip} %{__objdump} \
     } \
     /usr/lib/rpm/redhat/brp-strip-static-archive %{__strip} \
     %{!?__jar_repack:/usr/lib/rpm/redhat/brp-java-repack-jars} \
%{nil}

%prep
%setup -q

%build
%{__make} %{?mflags}

%install
%{__make} %{?mflags_install} install PREFIX=%{_prefix} DESTDIR=%{buildroot}

%files
# Documentation
%doc %{_datadir}/doc/%{name}/LICENSE
%doc %{_datadir}/doc/%{name}/README.rst
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
%{_bindir}/ch-run-oci
%{_bindir}/ch-tar2dir

# Binaries
%{_bindir}/ch-run
%{_bindir}/ch-ssh

%files doc
%doc %{_datadir}/doc/%{name}/LICENSE
%doc %{_datadir}/doc/%{name}/README.rst
%doc %{_datadir}/doc/%{name}/html
%{_libexecdir}/%{name}/examples
%{_libexecdir}/%{name}/test

%changelog
