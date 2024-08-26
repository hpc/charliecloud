Technical charter
*****************

Charliecloud is a member project of the `High Performance Software Foundation
<https://hpsf.io/>`_, and transitively the `Linux Foundation
<https://www.linuxfoundation.org/>`_.

.. Formatting notes.

   1. The formal title is kludged as “centered” block, because it’s too long
      to include in the sidebar and I couldn’t think of anything better.

   2. The document contains no auto-numbered lists; rather, everything is a
      normal paragraph with manual numbers. This is because both internal and
      external references may refer to these paragraph numbers, so we don’t
      want them changing without a deliberate decision. However, the notation
      we use is interpreted by Sphinx as lists, with various unpleasant side
      effects. To defeat this, put a non-breaking space after the paragraph
      number (U+00A0 NO-BREAK SPACE, option-space on a Mac).

.. centered:: Technical Charter (the “Charter”) for Charliecloud a Series of LF Projects, LLC

.. centered:: Adopted August 16, 2024

This Charter sets forth the responsibilities and procedures for technical
contribution to, and oversight of, the Charliecloud open source project, which
has been established as Charliecloud a Series of LF Projects, LLC (the
“Project”). LF Projects, LLC (“LF Projects”) is a Delaware series limited
liability company. All contributors (including committers, maintainers, and
other technical positions) and other participants in the Project
(collectively, “Collaborators”) must comply with the terms of this Charter.

.. contents::
   :depth: 2
   :local:

Mission and scope of the Project
================================

(a) The mission of the Project is to enable running and management of
lightweight, fully unprivileged containers for HPC applications.

(b) The scope of the Project includes collaborative development under the
Project License (as defined herein) supporting the mission, including
documentation, testing, integration and the creation of other artifacts that
aid the development, deployment, operation or adoption of the open source
project.

(c) Participation is especially welcome by people who can contribute
perspectives not yet well represented in the Project, whether technical or
non-technical.

Technical steering committee
============================

(a) The Technical Steering Committee (the “TSC”) is responsible for all
technical oversight of the open source Project.

(b) The initial TSC members are: Lucas Caudill, Jordan Ogas, Megan Phinney,
Reid Priedhorsky, and Nicholas Sly. The TSC sets its own procedures for member
appointment and removal. Current members and procedures are documented in the
Project’s code repository.

(c) Unless otherwise documented, project roles are:

   (i) Contributors are anyone that contributes code, documentation, or other
   technical artifacts to the Project.

   (ii) Maintainers are Contributors who have the authority to merge changes
   to (“commit”) technical artifacts to the Project’s code repository.

   (iii) Maintainers are appointed and removed by a majority of the entire
   TSC.

(d) Participation in the Project through becoming a Contributor and/or
Maintainer is open to anyone who abides by the terms of this Charter.

(e) The TSC may elect a TSC Chair who presides over meetings of the TSC and
serves until their resignation or replacement by the TSC.

(f) The TSC is responsible for all aspects of oversight relating to the
Project, which may include:

   (i) coordinating the technical direction of the Project;

   (ii) establishing requirements for the promotion of Contributors to
   Maintainer status;

   (iii) creating, eliminating, amending, adjusting, and/or refining Project
   roles;

   (iv) approving sub-project or system proposals (including, but not limited
   to, incubation, deprecation, and changes to a sub-project’s scope);

   (v) approving and organizing sub-projects and removing or closing
   sub-projects;

   (vi) creating sub-committees or working groups;

   (vii) appointing representatives to work with other projects or
   organizations;

   (viii) establishing community norms, workflows, release procedures, and
   security issue reporting policies;

   (ix) approving and implementing policies and processes for contributing;

   (x) coordinating with the series manager of the Project (as provided for in
   the Series Agreement, the “Series Manager”) to resolve matters or concerns
   that may arise as set forth in Section 7 of this Charter;

   (xi) discussing, seeking consensus, and where necessary, voting on
   technical matters, including those that affect multiple projects;

   (xii) coordinating marketing, events, or communications regarding the
   Project; and

   (xiii) establishing procedures for all oversight matters.

TSC meetings and voting
=======================

(a) The TSC will operate on consensus whenever practical. If a decision does
require a vote to move the Project forward, TSC members have one vote per
member.

(b) TSC meeting quorum is a majority of members. If a quorum is not present, a
meeting may continue, but no decisions may be made.

(c) Except as provided in §7(c) and §8(a), votes in a meeting require a
majority of TSC members present to pass. Electronic votes outside a meeting
require a majority of all members to pass.

(d) In the event a matter cannot be resolved by the TSC, any member may refer
it to the Series Manager for assistance in reaching a resolution.

(e) The TSC determines the rules and procedures for its meetings and Project discussions.

Compliance with policies
========================

(a) This Charter is subject to the Series Agreement for the Project and the
Operating Agreement of LF Projects. Contributors will comply with the policies
of LF Projects as may be adopted and amended by LF Projects, including without
limitation the policies listed at https://lfprojects.org/policies/.

(b) The TSC will adopt a code of conduct (“COC”) for the Project, subject to
approval by the Series Manager. In the event that a Project-specific COC has
not been approved, the LF Projects Code of Conduct listed at
https://lfprojects.org/policies will apply. All Contributors must follow the
COC. The TSC and/or Series Manager enforce the COC and may impose disciplinary
measures, including banning a person/organization from the Project and
reporting incidents to employers, professional societies, and other
supervisory bodies.

(c) When amending or adopting any policy applicable to the Project, LF
Projects will publish such policy, as to be amended or adopted, on its web
site at least 30 days prior to such policy taking effect; provided, however,
that in the case of any amendment of the Trademark Policy or Terms of Use of
LF Projects, any such amendment is effective upon publication on LF Project’s
web site.

(d) All Collaborators must allow open participation from any individual or
organization meeting the requirements for contributing under this Charter and
any policies adopted for all Collaborators by the TSC, regardless of
competitive interests. Put another way, the Project community must not seek to
exclude any participant based on any criteria, requirement, or reason other
than those that are reasonable and applied on a non-discriminatory basis to
all Collaborators in the Project community.

(e) The Project will operate in a transparent, open, collaborative, inclusive,
and ethical manner at all times. The output of all Project discussions,
proposals, timelines, decisions, and status will made open and easily visible
to all, unless required by law or LF Projects policy or to protect individual
privacy and safety. Any potential violations of this requirement should be
reported immediately to the Series Manager.

Community assets
================

(a) LF Projects will hold title to all trade or service marks used by the
Project (“Project Trademarks”), whether based on common law or registered
rights. Project Trademarks will be transferred and assigned to LF Projects to
hold on behalf of the Project. Any use of any Project Trademarks by
Collaborators in the Project will be in accordance with the license from LF
Projects and inure to the benefit of LF Projects.

(b) The Project will, as permitted and in accordance with such license from LF
Projects, develop and own all Project code repositories and related
infrastructure, social media accounts, and domain names.

(c) Under no circumstances will LF Projects be expected or required to
undertake any action on behalf of the Project that is inconsistent with the
tax-exempt status or purpose, as applicable, of the Joint Development
Foundation or LF Projects, LLC.

General rules and operations
============================

(a) The Project will operate in a professional manner consistent with
maintaining a cohesive and effective community while also maintaining the
goodwill and esteem of LF Projects, Joint Development Foundation, and other
partner organizations in the open source community.

(b) The Project will respect the rights of all trademark owners, including any
branding and trademark usage guidelines.

Intellectual property policy
============================

(a) Contributors acknowledge that (i) the copyright in all new contributions
will be retained by the copyright holder as independent works of authorship
and (ii) no contributor or copyright holder will be required to assign
copyrights to the Project.

(b) Except as described in Section 7(c), all contributions to the Project are
subject to:

   (i) All new inbound contributions of code and documentation to the Project
   must be made using Apache License, Version 2.0 available at
   http://www.apache.org/licenses/LICENSE-2.0 (the “Project License”).

   (ii) All new inbound contributions must also be accompanied by a Developer
   Certificate of Origin (http://developercertificate.org) sign-off that binds
   the authorized contributor and, if not self-employed, their employer to the
   applicable license;

   (iii) All outbound contributions will be made available under the Project
   License.

   (iv) The Project may seek to integrate and contribute back to other open
   source projects (“Upstream Projects”). In such cases, the Project will
   conform to all license requirements of the Upstream Projects, including
   dependencies, leveraged by the Project. Upstream Project code contributions
   not stored within the Project’s main code repository will comply with the
   contribution process and license terms for the applicable Upstream Project.

(c) The TSC may approve the use of alternative license(s) for inbound or
outbound contributions on an exception basis. License exceptions must be
approved by a two-thirds vote of the entire TSC.

(d) Contributed files should contain license information, such as SPDX short
form identifiers, indicating the open source license(s) pertaining to the
file.

Amendments
==========

(a) This charter may be amended by two-thirds vote of the entire TSC and
approval by LF Projects.
