Summary: Lightweight user-defined software stacks for high-performance computing
Name: charliecloud
Version: @VERSION@
Release: %{?dist}
License: Apache-2.0
Group: System Environment/Base
URL: https://hpc.github.io/charliecloud/
Source: %{name}-%{version}.tar.gz
ExclusiveOS: linux
BuildRoot: %{?_tmppath}%{!?_tmppath:/var/tmp}/%{name}-%{version}-%{release}-root
BuildRequires: python python-sphinx python-sphinx_rtd_theme rsync

%description
Charliecloud provides user-defined software stacks (UDSS) for
high-performance computing (HPC) centers.

%prep
%setup -q
# Required for CentOS 7 and older, which don't know of Docker lexer yet.
#find doc-src -type f -print0 | xargs -0 sed -i '/.*:language: docker.*/d'

%build
%{__make} %{?mflags}

%install
LIBEXEC_POSTFIX=$(echo %{_libexecdir} | sed 's#^/usr/##')
PREFIX=/usr LIBEXEC_DIR=${LIBEXEC_POSTFIX}/charliecloud DESTDIR=$RPM_BUILD_ROOT %{__make} install %{?mflags_install}
rm -rf $RPM_BUILD_ROOT/%{_defaultdocdir}/%{name}/examples
rm -rf $RPM_BUILD_ROOT/%{_defaultdocdir}/%{name}/doc
rm -rf $RPM_BUILD_ROOT/%{_defaultdocdir}/%{name}/test
rm -rf $RPM_BUILD_ROOT/%{_defaultdocdir}/%{name}/COPYRIGHT
rm -rf $RPM_BUILD_ROOT/%{_defaultdocdir}/%{name}/LICENSE
rm -rf $RPM_BUILD_ROOT/%{_defaultdocdir}/%{name}/README.rst

%clean
rm -rf $RPM_BUILD_ROOT

#%check
#%{__make} -C test test-quick

%files
%doc LICENSE README.rst examples
%{_mandir}/man1/*

# Helper scripts
%{_libexecdir}/%{name}/base.sh
%{_libexecdir}/%{name}/version.sh

# Binaries
%{_bindir}/ch-*

%changelog
