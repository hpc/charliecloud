# Charliecloud fedora package spec file
#
# Contributors:
#    Dave Love           @loveshack
#    Michael Jennings    @mej
#    Jordan Ogas         @jogas
#    Reid Priedhorksy    @reidpr

# Don't try to compile python3 files with /usr/bin/python.
%{?el7:%global __python %__python3}

Name:          charliecloud
Version:       0.26
Release:       1%{?dist}
Summary:       Lightweight user-defined software stacks for high-performance computing
License:       ASL 2.0
URL:           https://hpc.github.io/%{name}/
Source0:       https://github.com/hpc/%{name}/releases/downloads/v%{version}/%{name}-%{version}.tar.gz
BuildRequires: gcc rsync bash
Requires:      squashfuse squashfs-tools
Patch1:        el7-pkgdir.patch
Patch2:        printf.patch

%description
Charliecloud uses Linux user namespaces to run containers with no privileged
operations or daemons and minimal configuration changes on center resources.
This simple approach avoids most security risks while maintaining access to
the performance and functionality already on offer.

Container images can be built using Docker or anything else that can generate
a standard Linux filesystem tree.

For more information: https://hpc.github.io/charliecloud

%package builder
Summary:       Charliecloud container image building tools
License:       ASL 2.0 and MIT
BuildArch:     noarch
BuildRequires: python3-devel
BuildRequires: python%{python3_pkgversion}-lark-parser
BuildRequires: python%{python3_pkgversion}-requests
Requires:      %{name}
Requires:      python3
Requires:      python%{python3_pkgversion}-lark-parser
Requires:      python%{python3_pkgversion}-requests
Provides:      bundled(python%{python3_pkgversion}-lark-parser) = 0.11.3

%description builder
This package provides ch-image, Charliecloud's completely unprivileged container
image manipulation tool.

%package       doc
Summary:       Charliecloud html documentation
License:       BSD and ASL 2.0
BuildArch:     noarch
Obsoletes:     %{name}-doc < %{version}-%{release}
BuildRequires: python%{python3_pkgversion}-sphinx
BuildRequires: python%{python3_pkgversion}-sphinx_rtd_theme
Requires:      python%{python3_pkgversion}-sphinx_rtd_theme

%description doc
Html and man page documentation for %{name}.

%package   test
Summary:   Charliecloud test suite
License:   ASL 2.0
Requires:  %{name} %{name}-builder /usr/bin/bats
Obsoletes: %{name}-test < %{version}-%{release}

%description test
Test fixtures for %{name}.

%prep
%setup -q

%if 0%{?el7}
%patch1 -p1
%endif

%patch2 -p1

%build
# Use old inlining behavior, see:
# https://github.com/hpc/charliecloud/issues/735
CFLAGS=${CFLAGS:-%optflags -fgnu89-inline}; export CFLAGS
%configure --docdir=%{_pkgdocdir} \
           --libdir=%{_prefix}/lib \
           --with-python=/usr/bin/python3 \
%if 0%{?el7}
           --with-sphinx-build=%{_bindir}/sphinx-build-3.6
%else
           --with-sphinx-build=%{_bindir}/sphinx-build
%endif

%install
%make_install

cat > README.EL7 <<EOF
For RHEL7 you must increase the number of available user namespaces to a non-
zero number (note the number below is taken from the default for RHEL8):

  echo user.max_user_namespaces=3171 >/etc/sysctl.d/51-userns.conf
  sysctl -p /etc/sysctl.d/51-userns.conf

Note for versions below RHEL7.6, you will also need to enable user namespaces:

  grubby --args=namespace.unpriv_enable=1 --update-kernel=ALL
  reboot

Please visit https://hpc.github.io/charliecloud/ for more information.
EOF

# Remove bundled sphinx bits.
%{__rm} -rf %{buildroot}%{_pkgdocdir}/html/_static/css
%{__rm} -rf %{buildroot}%{_pkgdocdir}/html/_static/fonts
%{__rm} -rf %{buildroot}%{_pkgdocdir}/html/_static/js

# Use Fedora package sphinx bits.
sphinxdir=%{python3_sitelib}/sphinx_rtd_theme/static
ln -s "${sphinxdir}/css"   %{buildroot}%{_pkgdocdir}/html/_static/css
ln -s "${sphinxdir}/fonts" %{buildroot}%{_pkgdocdir}/html/_static/fonts
ln -s "${sphinxdir}/js"    %{buildroot}%{_pkgdocdir}/html/_static/js

# Remove bundled license and readme (prefer license and doc macros).
%{__rm} -f %{buildroot}%{_pkgdocdir}/LICENSE
%{__rm} -f %{buildroot}%{_pkgdocdir}/README.rst

%files
%license LICENSE
%doc README.rst %{?el7:README.EL7}
%{_bindir}/ch-checkns
%{_bindir}/ch-convert
%{_bindir}/ch-fromhost
%{_bindir}/ch-run
%{_bindir}/ch-run-oci
%{_bindir}/ch-ssh
%{_mandir}/man1/ch-checkns.1*
%{_mandir}/man1/ch-convert.1*
%{_mandir}/man1/ch-fromhost.1*
%{_mandir}/man1/ch-run.1*
%{_mandir}/man1/ch-run-oci.1*
%{_mandir}/man1/ch-ssh.1*
%{_mandir}/man7/charliecloud.7*
%{_prefix}/lib/%{name}/base.sh
%{_prefix}/lib/%{name}/contributors.bash
%{_prefix}/lib/%{name}/version.sh
%{_prefix}/lib/%{name}/version.txt

%files builder
%{_bindir}/ch-image
%{_mandir}/man1/ch-image.1*
%{_prefix}/lib/%{name}/build.py
%{_prefix}/lib/%{name}/charliecloud.py
%{_prefix}/lib/%{name}/fakeroot.py
%{_prefix}/lib/%{name}/lark
%{_prefix}/lib/%{name}/lark-0.11.3.dist-info
%{_prefix}/lib/%{name}/lark-stubs
%{_prefix}/lib/%{name}/misc.py
%{_prefix}/lib/%{name}/pull.py
%{_prefix}/lib/%{name}/push.py
%{_prefix}/lib/%{name}/version.py
%{?el7:%{_prefix}/lib/%{name}/__pycache__}

%files doc
%license LICENSE
%{_pkgdocdir}/examples
%{_pkgdocdir}/html
%{?el7:%exclude %{_pkgdocdir}/examples/*/__pycache__}

%files test
%{_bindir}/ch-test
%{_libexecdir}/%{name}/test
%{_mandir}/man1/ch-test.1*

%changelog
* Mon Jan 24 2022 Jordan Ogas <jogas@lanl.gov 0.26-1
- add printf patch for 32-bit
- add ch-convert script
- new version 0.26

* Wed Jan 19 2022 Fedora Release Engineering <releng@fedoraproject.org> - 0.25-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_36_Mass_Rebuild

* Mon Sep 20 2021 Jordan Ogas <jogas@lanl.gov 0.25-1
- bundle python lark parser
- new version

* Thu Aug 05 2021 Jordan Ogas <jogas@lanl.gov> 0.24-12
- remove version numbers from Obsolete
- remove Provides tag
- replace package name with macro
- tidy

* Thu Jul 29 2021 Jordan Ogas <jogas@lanl.gov> 0.24-11
- move -builder to noarch
- move examples back to -doc
- add versions to obsoletes
- use name macro

* Wed Jul 28 2021 Jordan Ogas <jogas@lanl.gov> 0.24-10
- fix yet another typo; BuildRequires

* Wed Jul 28 2021 Jordan Ogas <jogas@lanl.gov> 0.24-9
- add version to obsoletes

* Wed Jul 28 2021 Jordan Ogas <jogas@lanl.gov> 0.24-8
- fix provides typo

* Wed Jul 28 2021 Jordan Ogas <jogas@lanl.gov> 0.24-7
- add -common to obsoletes and provides

* Wed Jul 28 2021 Jordan Ogas <jogas@lanl.gov> - 0.24-6
* revert to meta-package; separate builder to -builder

* Wed Jul 21 2021 Fedora Release Engineering <releng@fedoraproject.org> - 0.24-5
- Rebuilt for https://fedoraproject.org/wiki/Fedora_35_Mass_Rebuild

* Mon Jul 19 2021 Jordan Ogas <jogas@lanl.gov> - 0.24-4
- fix epel7 python cache files

* Mon Jul 19 2021 Jordan Ogas <jogas@lanl.gov> - 0.24-3
- Tidy, alphabatize files
- Move builder exlusive python files out from -common
- Move generic helper scripts to -common
- Add requires runtime to -builders

* Tue Jul 13 2021 Dave Love <loveshack@fedoraproject.org> - 0.24-2
- Obsolete previous packge by -runtime, not -common

* Wed Jun 30 2021 Dave Love <loveshack@fedoraproject.org> - 0.24-1
- New version

* Sun Apr 18 2021 Dave Love <loveshack@fedoraproject.org> - 0.23-1
- New version
- Split main package into runtime, builder, and common sub-packages
- Require buildah and squashfs at run time
- Use /lib, not /lib64 for noarch; drop lib64 patch
- Don't BR squashfs-tools, squashfuse, buildah
- Require squashfs-tools in -builders

* Mon Mar 8 2021 Dave Love <loveshack@fedoraproject.org> <jogas@lanl.gov> - 0.22-2
- Fix source0 path
- Put man7 in base package

* Tue Feb 9 2021 Dave Love <loveshack@fedoraproject.org> <jogas@lanl.gov> - 0.22-1
- New version
- update lib64.patch
- add pull.py and push.py
- (Build)Require python3-lark-parser, python3-requests

* Wed Feb 3 2021 <jogas@lanl.gov> - 0.21-2
- Fix lib64.patch path for ch-image

* Tue Jan 05 2021 <loveshack@fedoraproject.org> <jogas@lanl.gov> - 0.21-1
- New version
- Ship charlicloud.7
- Require fakeroot
- Install fakeroot.py
- Always ship patch1
- Get python3_sitelib defined
- Move examples to -test and require sphinx_rtd_theme
- Include __pycache__ on el7
- Use %%python3_pkgversion
- BR python3, not /usr/bin/python3
- Fix comment capitalization and spacing

* Tue Sep 22 2020 <jogas@lanl.gov> - 0.19-1
- Package build.py and misc.py
- Remove unnecessary patch
- New release

* Mon Jul 27 2020 Fedora Release Engineering <releng@fedoraproject.org> - 0.15-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_33_Mass_Rebuild

* Thu Apr 16 2020 <jogas@lanl.gov> - 0.15-1
- Add test suite package
- Update spec for autoconf
- New release

* Tue Jan 28 2020 Fedora Release Engineering <releng@fedoraproject.org> - 0.10-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_32_Mass_Rebuild

* Wed Sep 04 2019 <jogas@lanl.gov> - 0.10-1
- Patch doc-src/conf.py for epel
- Fix doc-src/dev.rst
- Fix libexec and doc install path for 0.10 changes
- Tidy comments
- New release

* Thu Aug 22 2019 <jogas@lanl.gov> - 0.9.10-12
- Upate doc subpackage obsoletes

* Mon Aug 19 2019 Dave love <loveshack@fedoraproject.org> - 0.9.10-11
- Use canonical form for Source0
- Remove main package dependency from doc, and make it noarch

* Fri Aug 02 2019 <jogas@lanl.gov> 0.9.10-10
- Tidy comments; fix typ

* Thu Jul 25 2019 <jogas@lanl.gov> 0.9.10-9
- Use python site variable; fix doc file reference

* Tue Jul 23 2019 <jogas@lanl.gov> 0.9.10-8
- Remove bundled js, css, and font bits

* Mon Jul 22 2019 <jogas@lanl.gov 0.9.10-7
- Fix prep section to handle warnings
- Move documentation dependencies to doc package

* Fri Jul 19 2019 <jogas@lanl.gov> 0.9.10-6
- Temporarily remove test suite

* Wed Jul 10 2019 <jogas@lanl.gov> 0.9.10-5
- Revert test and example install path change
- Update test readme

* Wed Jul 3 2019 <jogas@lanl.gov> 0.9.10-4
- Add doc package

* Tue Jul 2 2019 <jogas@lanl.gov> 0.9.10-3
- Tidy comments
- Update source URL
- Build html documentation; add rsync dependency
- Add el7 conditionals for documentation
- Remove libexecdir definition
- Add test suite README.TEST

* Wed May 15 2019  <jogas@lanl.gov> 0.9.10-2
- Fix comment typo
- Move test suite install path

* Tue May 14 2019  <jogas@lanl.gov> 0.9.10-1
- New version
- Fix README.EL7 sysctl command instruction
- Add pre-built html documentation
- Fix python dependency
- Remove temporary test-package readme
- Fixed capitalization of change log messages

* Tue Apr 30 2019  <jogas@lanl.gov> 0.9.9-4
- Move global python declaration

* Mon Apr 29 2019  <jogas@lanl.gov> 0.9.9-3
- Match bin files with wildcard

* Mon Apr 29 2019  <jogas@lanl.gov> 0.9.9-2
- Update macro comment
- Fix release tag history

* Tue Apr 16 2019  <jogas@lanl.gov> 0.9.9-1
- New version
- Move temp readme creation to install segment
- Fix spec file macro

* Tue Apr 02 2019  <jogas@lanl.gov> 0.9.8-2
- Remove python2 build option

* Thu Mar 14 2019  <jogas@lanl.gov> 0.9.8-1
- Add initial Fedora/EPEL package
