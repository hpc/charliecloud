# Charliecloud fedora package spec file
#
# Contributors:
#    Dave Love           @loveshack
#    Michael Jennings    @mej
#    Jordan Ogas         @jogas
#    Reid Priedhorksy    @reidpr

# Don't try to compile python3 files with /usr/bin/python.
%{?el7:%global __python %__python3}

# Python files should specify a version, e.g., python3, python2.
%define versionize_script() (sed -i 's,/env python,/env %1,g' %2)

Name:           charliecloud
Version:        @VERSION@
Release:        @RELEASE@%{?dist}
Summary:        Lightweight user-defined software stacks for high-performance computing
License:        ASL 2.0
URL:            https://hpc.github.io/%{name}/
Source0:        https://github.com/hpc/%{name}/archive/v%{version}.tar.gz
BuildRequires:  gcc rsync
%if 0%{?el7}
BuildRequires:  /usr/bin/python2
%else
BuildRequires:  /usr/bin/python3
%endif

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
Requires:       %{name}%{?_isa} = %{version}-%{release}
%if 0%{?el7}
BuildRequires:  python-sphinx python-sphinx_rtd_theme
%else
BuildRequires:  python3-sphinx python3-sphinx_rtd_theme
%endif

%description doc
Html documentation for %{name}.

%prep
%setup -q
# Do not treat warnings as errors on el7
%if 0%{?el7}
sed -i 's/ -W / /' doc-src/Makefile
sed -i '/^ *:widths: auto/d' doc-src/*.rst
%endif

%if 0%{?el7}
%{versionize_script python2 test/make-auto}
%{versionize_script python2 test/make-perms-test}
%else
%{versionize_script python3 test/make-auto}
%{versionize_script python3 test/make-perms-test}
%endif

%build
%make_build CFLAGS="-std=c11 -pthread -g"
# Remove sphinx version dependency for el7
sed -i 's@needs_sphinx@#needs_sphinx@g' doc-src/conf.py
make -C doc-src -k || :

%install
%make_install PREFIX=%{_prefix}

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

# This kludge is necessary due to the change of installation path for the
# documentation, test, and example dirs from PR #448. This kludge will be
# removed when the v0.10 spec file changes (issue #504) is resolved.
%{__mv} %{buildroot}/%{_libexecdir}/%{name}-%{version} %{buildroot}%{_libexecdir}/%{name}
%{__mv} %{buildroot}/%{_docdir}/%{name}-%{version} %{buildroot}%{_docdir}/%{name}

# Use python-sphinx_rtd_theme packaged fonts
%{__rm}  -f %{buildroot}%{_docdir}/%{name}/LICENSE
%{__rm}  -f %{buildroot}%{_docdir}/%{name}/README.rst
%{__rm} -rf %{buildroot}%{_docdir}/%{name}/html/_static/css
%{__rm} -rf %{buildroot}%{_docdir}/%{name}/html/_static/fonts
%{__rm} -rf %{buildroot}%{_docdir}/%{name}/html/_static/js
%if 0%{?el7}
sphinxdir=%{_prefix}/lib/python2.7/site-packages/sphinx_rtd_theme/static
%else
sphinxdir=%{_prefix}/lib/python3.6/site-packages/sphinx_rtd_theme/static
%endif
ln -s "${sphinxdir}/css"   %{buildroot}%{_docdir}/%{name}/html/_static/css
ln -s "${sphinxdir}/fonts" %{buildroot}%{_docdir}/%{name}/html/_static/fonts
ln -s "${sphinxdir}/js"    %{buildroot}%{_docdir}/%{name}/html/_static/js
%if 0%{?el7}
%{__mv} %{buildroot}/%{_docdir}/%{name} %{buildroot}%{_docdir}/%{name}-%{version}
%endif

%files
%license LICENSE
%doc README.rst %{?el7:README.EL7}
%{_mandir}/man1/ch*

# Helper scripts and binaries
%{_libexecdir}/%{name}/base.sh
%{_libexecdir}/%{name}/version.sh
%{_bindir}/ch-*

# Temporarly remove test suite packaging.
%exclude %{_libexecdir}/%{name}/test
%exclude %{_libexecdir}/%{name}/examples

%files doc
%license LICENSE
%{_pkgdocdir}/html
%changelog
* Thu Mar 14 2019 <jogas@lanl.gov> @VERSION@-@RELEASE@
- Add initial Fedora/EPEL package.
