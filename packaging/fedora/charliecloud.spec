# Charliecloud fedora package spec file
#
# Contributors:
#    Dave Love           @loveshack
#    Michael Jennings    @mej
#    Jordan Ogas         @jogas
#    Reid Priedhorksy    @reidpr

# Don't try to compile python3 files with /usr/bin/python.
%{?el7:%global __python %__python3}

Name:           charliecloud
Version:        0.14
Release:        1%{?dist}
Summary:        Lightweight user-defined software stacks for high-performance computing
License:        ASL 2.0
URL:            https://hpc.github.io/%{name}/
Source0:        https://github.com/hpc/%{name}/releases/downloads/v%{version}/%{name}-%{version}.tar.gz
BuildRequires:  gcc rsync autoconf /usr/bin/python3

%description
Charliecloud uses Linux user namespaces to run containers with no privileged
operations or daemons and minimal configuration changes on center resources.
This simple approach avoids most security risks while maintaining access to
the performance and functionality already on offer.

Container images can be built using Docker or anything else that can generate
a standard Linux filesystem tree.

For more information: https://hpc.github.io/charliecloud/

%package        doc
Summary:        %{name} html documentation
License:        BSD and MIT and ASL 2.0
BuildArch:      noarch
Obsoletes:      %{name}-doc < %{version}-%{release}
BuildRequires:  python3-sphinx
%if 0%{?el7}
BuildRequires:  python36-sphinx_rtd_theme
%else
BuildRequires:  python3-sphinx_rtd_theme
%endif

%description doc
Html and man page documentation for %{name}.

%package        test
Summary:        %{name} test suite
License:        ASL 2.0
Obsoletes:      %{name}-test < %{version}-%{release}
Requires:       %{name} bash bats /usr/bin/python3

%description test
Test fixtures for %{name}.

%prep
%setup -q

%build

%configure --prefix=%{_prefix} \
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
  reboot

Note for versions below RHEL7.6, you will also need to enable user namespaces:

  grubby --args=namespace.unpriv_enable=1 --update-kernel=ALL
  reboot

Please visit https://hpc.github.io/charliecloud/ for more information.
EOF

# Use python-sphinx_rtd_theme packaged fonts.
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

# FIXME: change permissions of base.sh, VERSION, etc.

%files
%license LICENSE
%doc README.rst %{?el7:README.EL7}
%{_pkgdocdir}/examples
%{_mandir}/man1/ch*

# Helper scripts and binaries
%{_libexecdir}/%{name}/base.sh
%{_libexecdir}/%{name}/version.sh
%{_bindir}/ch-*

# Exclude bundled license and readme
%if 0%{?el7}
%exclude %{_docdir}/%{name}-%{version}/LICENSE
%exclude %{_docdir}/%{name}-%{version}/README.rst
%else
%exclude %{_docdir}/%{name}/LICENSE
%exclude %{_docdir}/%{name}/README.rst
%endif

# Exclude test artifacts
%exclude %{_libexecdir}/%{name}/test

%files doc
%license LICENSE
%{_pkgdocdir}/html

%files test
%license LICENSE
%{_libexecdir}/${name}/test

%changelog
