/* Copyright © Triad National Security, LLC, and others.

   This interface contains the seccomp filter for root emulation. */

#define _GNU_SOURCE
#pragma once

#include "core.h"

void rootemu_init(struct container *c);
