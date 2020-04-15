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
BuildRequires: gcc rsync autoconf /usr/bin/python3
Patch0:        ch-test.lib.patch
%if 0%{?el7}
Patch1:        ch-test.el7.patch
%endif

%description
Charliecloud uses Linux user namespaces to run containers with no privileged
operations or daemons and minimal configuration changes on center resources.
This simple approach avoids most security risks while maintaining access to
the performance and functionality already on offer.

Container images can be built using Docker or anything else that can generate
a standard Linux filesystem tree.

For more information: https://hpc.github.io/charliecloud/

%package       doc
Summary:       Charliecloud html documentation
License:       BSD and ASL 2.0
BuildArch:     noarch
Obsoletes:     %{name}-doc < %{version}-%{release}
%if 0%{?el7}
BuildRequires: python36-sphinx
BuildRequires: python36-sphinx_rtd_theme
%else
BuildRequires: python3-sphinx
BuildRequires: python3-sphinx_rtd_theme
%endif

%description doc
Html and man page documentation for %{name}.

%package   test
Summary:   Charliecloud test suite
License:   ASL 2.0
Obsoletes: %{name}-test < %{version}-%{release}
Requires:  %{name} bash /usr/bin/bats /usr/bin/python3

%description test
Test fixtures for %{name}.

%prep
%setup -q

%patch0 -p1
%if 0%{?el7}
%patch1 -p0
%endif

%build
%configure --prefix=%{_prefix} \
           --libdir=%{_libdir} \
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
  sysctl -p #FIXME: determine file

Please visit https://hpc.github.io/charliecloud/ for more information.
EOF

#

# Use Fedora packaged sphinx_rtd_theme fonts; remove corresponding
# bundled bits.
%{__rm} -rf %{buildroot}%{_docdir}/%{name}/html/_static/css
%{__rm} -rf %{buildroot}%{_docdir}/%{name}/html/_static/fonts
%{__rm} -rf %{buildroot}%{_docdir}/%{name}/html/_static/js

sphinxdir=%{python3_sitelib}/sphinx_rtd_theme/static
ln -s "${sphinxdir}/css"   %{buildroot}%{_docdir}/%{name}/html/_static/css
ln -s "${sphinxdir}/fonts" %{buildroot}%{_docdir}/%{name}/html/_static/fonts
ln -s "${sphinxdir}/js"    %{buildroot}%{_docdir}/%{name}/html/_static/js

%if 0%{?el7}
%{__mv} %{buildroot}/%{_docdir}/%{name} %{buildroot}%{_docdir}/%{name}-%{version}
%endif

%files
%license LICENSE
%doc README.rst %{?el7:README.EL7}
%{_pkgdocdir}/examples
%{_mandir}/man1/ch*

# Library files.
%{_libdir}/%{name}/base.sh
%{_libdir}/%{name}/charliecloud.py
%{_libdir}/%{name}/contributors.bash
%{_libdir}/%{name}/version.py
%{_libdir}/%{name}/version.sh
%{_libdir}/%{name}/version.txt

# Binary files.
%{_bindir}/ch-*
%exclude %{_bindir}/ch-test

# Exclude bundled license and readme
%if 0%{?el7}
%exclude %{_docdir}/%{name}-%{version}/LICENSE
%exclude %{_docdir}/%{name}-%{version}/README.rst
%else
%exclude %{_docdir}/%{name}/LICENSE
%exclude %{_docdir}/%{name}/README.rst
%endif

# Exclude test artifacts
%exclude %{_libdir}/%{name}/test

%files doc
%license LICENSE
%{_pkgdocdir}/html

%files test
%license LICENSE
%{_libexecdir}/%{name}/test
%{_bindir}/ch-test
%{_mandir}/man1/ch-test.1*

%changelog
* Tue Feb 25 2020 <jogas@lanl.gov> - @VERSION@-@RELEASE@
- Add charliecloud @VERSION@ package
