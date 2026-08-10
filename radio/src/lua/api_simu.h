/*
 * Copyright (C) EdgeTX
 *
 * Widget Studio sim-only Lua module.  Compiled for the simu target only and
 * gated by WIDGET_STUDIO (see radio/src/targets/simu/CMakeLists.txt).  The
 * module surface is frozen by the Widget Studio plan (Phase 1) and must not
 * grow into firmware feature territory.
 *
 * License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html
 */

#pragma once

#if defined(COLORLCD) && defined(SIMU) && defined(WIDGET_STUDIO)
extern LROT_TABLE(simulib);
#endif
