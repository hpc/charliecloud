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
* Thu Apr 16 2020 <jogas@lanl.gov> - @VERSION@-@RELEASE@
- Add new charliecloud package.
