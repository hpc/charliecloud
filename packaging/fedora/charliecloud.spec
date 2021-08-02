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
Version:       @VERSION@
Release:       @RELEASE@%{?dist}
Summary:       Lightweight user-defined software stacks for high-performance computing
License:       ASL 2.0
URL:           https://hpc.github.io/%{name}/
Source0:       https://github.com/hpc/%{name}/releases/downloads/v%{version}/%{name}-%{version}.tar.gz
BuildRequires: gcc rsync bash
Requires:      squashfuse squashfs-tools
Patch1:        el7-pkgdir.patch
# Suggests:    name-builder docker buildah
Obsoletes:     %{name}-runtime
Obsoletes:     %{name}-common

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
BuildArch:     noarch
BuildRequires: python3-devel
BuildRequires: python%{python3_pkgversion}-lark-parser
BuildRequires: python%{python3_pkgversion}-requests
Requires:      %{name}
Requires:      python3
Requires:      python%{python3_pkgversion}-lark-parser
Requires:      python%{python3_pkgversion}-requests
Obsoletes:     %{name}-builders

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

%build
# Use old inlining behavior, see:
# https://github.com/hpc/charliecloud/issues/735
CFLAGS=${CFLAGS:-%optflags -fgnu89-inline}; export CFLAGS
%configure --docdir=%{_pkgdocdir} \
           --libdir=%{_prefix}/lib \
           --with-python=/usr/bin/python3 \
           --disable-bundled-lark \
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
%{_bindir}/ch-build
%{_bindir}/ch-build2dir
%{_bindir}/ch-builder2squash
%{_bindir}/ch-builder2tar
%{_bindir}/ch-checkns
%{_bindir}/ch-dir2squash
%{_bindir}/ch-fromhost
%{_bindir}/ch-mount
%{_bindir}/ch-pull2dir
%{_bindir}/ch-pull2tar
%{_bindir}/ch-run
%{_bindir}/ch-run-oci
%{_bindir}/ch-ssh
%{_bindir}/ch-umount
%{_bindir}/ch-tar2dir
%{_mandir}/man1/ch-build.1{,.gz}
%{_mandir}/man1/ch-build2dir.1{,.gz}
%{_mandir}/man1/ch-builder2squash.1{,.gz}
%{_mandir}/man1/ch-builder2tar.1{,.gz}
%{_mandir}/man1/ch-checkns.1{,.gz}
%{_mandir}/man1/ch-dir2squash.1{,.gz}
%{_mandir}/man1/ch-fromhost.1{,.gz}
%{_mandir}/man1/ch-mount.1{,.gz}
%{_mandir}/man1/ch-pull2dir.1{,.gz}
%{_mandir}/man1/ch-pull2tar.1{,.gz}
%{_mandir}/man1/ch-run.1{,.gz}
%{_mandir}/man1/ch-run-oci.1{,.gz}
%{_mandir}/man1/ch-ssh.1{,.gz}
%{_mandir}/man1/ch-tar2dir.1{,.gz}
%{_mandir}/man1/ch-umount.1{,.gz}
%{_mandir}/man7/charliecloud.7*
%{_prefix}/lib/%{name}/base.sh
%{_prefix}/lib/%{name}/contributors.bash
%{_prefix}/lib/%{name}/version.sh
%{_prefix}/lib/%{name}/version.txt

%files builder
%{_bindir}/ch-image
%{_mandir}/man1/ch-image.1{,.gz}
%{_prefix}/lib/%{name}/build.py
%{_prefix}/lib/%{name}/charliecloud.py
%{_prefix}/lib/%{name}/fakeroot.py
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
%{_mandir}/man1/ch-test.1{,.gz}

%changelog
* Thu Apr 16 2020 <jogas@lanl.gov> - @VERSION@-@RELEASE@
- Add new charliecloud package.
