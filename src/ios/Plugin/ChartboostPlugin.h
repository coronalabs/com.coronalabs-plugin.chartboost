//
//  ChartboostPlugin.h
//  Chartboost Plugin
//
//  Copyright (c) 2016 Corona Labs Inc. All rights reserved.
//

#ifndef _ChartboostPlugin_H_
#define _ChartboostPlugin_H_

#import "CoronaLua.h"
#import "CoronaMacros.h"

// This corresponds to the name of the library, e.g. [Lua] require "plugin.library"
// where the '.' is replaced with '_'
CORONA_EXPORT int luaopen_plugin_chartboost( lua_State *L );

#endif // _ChartboostPlugin_H_
