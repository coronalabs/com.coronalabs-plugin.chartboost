//
//  ChartboostPlugin.mm
//  Chartboost Plugin
//
//  Copyright (c) 2016 Corona Labs Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "CoronaRuntime.h"
#import "CoronaAssert.h"
#import "CoronaEvent.h"
#import "CoronaLua.h"
#import "CoronaLuaIOS.h"
#import "CoronaLibrary.h"

#import "ChartboostPlugin.h"
#import <ChartboostSDK/Chartboost.h>
#include <AppTrackingTransparency/AppTrackingTransparency.h>

// some macros to make life easier, and code more readable
#define UTF8StringWithFormat(format, ...) [[NSString stringWithFormat:format, ##__VA_ARGS__] UTF8String]
#define UTF8IsEqual(utf8str1, utf8str2) (strcmp(utf8str1, utf8str2) == 0)
#define MsgFormat(format, ...) [NSString stringWithFormat:format, ##__VA_ARGS__]

// ----------------------------------------------------------------------------
// Plugin Constants
// ----------------------------------------------------------------------------

#define PLUGIN_NAME        "plugin.chartboost"
#define PLUGIN_VERSION     "2.2.0"
#define PLUGIN_SDK_VERSION [Chartboost getSDKVersion]

static const char EVENT_NAME[]    = "adsRequest";
static const char PROVIDER_NAME[] = "chartboost";

// ad types
static const char TYPE_INTERSTITIAL[]   = "interstitial";
static const char TYPE_REWARDED_VIDEO[] = "rewardedVideo";

// valid ad types
static const NSArray *validAdTypes = @[
	@(TYPE_INTERSTITIAL),
	@(TYPE_REWARDED_VIDEO)
];

// event phases
static NSString * const PHASE_INIT      = @"init";
static NSString * const PHASE_DISPLAYED = @"displayed";
static NSString * const PHASE_LOADED    = @"loaded";
static NSString * const PHASE_FAILED    = @"failed";
static NSString * const PHASE_CLOSED    = @"closed";
static NSString * const PHASE_CLICKED   = @"clicked";
static NSString * const PHASE_REWARD    = @"reward";

// missing Corona Event Keys
static NSString * const CORONA_EVENT_DATA_KEY = @"data";

// response keys
static NSString * const RESPONSE_LOAD_FAILED = @"loadFailed";

// message constants
static NSString * const ERROR_MSG   = @"ERROR: ";
static NSString * const WARNING_MSG = @"WARNING: ";

// saved objects (apiKey, ad state, etc)
static NSMutableDictionary *chartboostObjects;

// object dictionary keys
static NSString * const SDK_READY_KEY     = @"sdkReady";
static NSString * const APP_ID_KEY        = @"appID";
static NSString * const APP_SIGNATURE_KEY = @"appSignature";
static NSString * const AUTO_CACHE_KEY    = @"autoCache";

// ----------------------------------------------------------------------------
// plugin class and delegate definitions
// ----------------------------------------------------------------------------

// INT_MAX used to define no data for delegate function params
#define NO_DATA INT_MAX

// Chartboost delegate
@interface ChartboostDelegate: NSObject <CHBInterstitialDelegate, CHBRewardedDelegate>

@property (nonatomic, assign) CoronaLuaRef coronaListener;             // Reference to the Lua listener
@property (nonatomic, assign) id<CoronaRuntime> coronaRuntime;           // Pointer to the Corona runtime

@property (nonatomic, strong) NSMutableDictionary<NSString*, NSMutableDictionary<NSString*, id<CHBAd>>*>* ads;

- (id<CHBAd>)getAd:(NSString*)type location:(NSString*)location;
+ (NSString*)adTypeFromEvent:(CHBAdEvent*)event;
- (void)didInitialize:(BOOL)status;
- (void)dispatchLuaEvent:(NSDictionary *)dict;
- (void)resumeSession;

@end

// ----------------------------------------------------------------------------

class ChartboostPlugin
{
public:
	typedef ChartboostPlugin Self;
	
public:
	static const char kName[];
	
public:
	static int Open( lua_State *L );
	static int Finalizer( lua_State *L );
	static Self *ToLibrary( lua_State *L );
	
protected:
	ChartboostPlugin();
	bool Initialize( void *platformContext );
	
public:
	static int init( lua_State *L );
	static int load( lua_State *L );
	static int isLoaded( lua_State *L );
	static int isAdVisible( lua_State *L );
	static int show( lua_State *L );
	static int hide( lua_State *L );
	static int onBackPressed( lua_State *L );
	
private: // internal helper functions
	static void logMsg(lua_State *L, NSString *msgType,  NSString *errorMsg);
	static bool isSDKInitialized(lua_State *L);
	
private:
	NSString *functionSignature;                                  // used in logMsg to identify function
	UIViewController *coronaViewController;                       // application's view controller
};

const char ChartboostPlugin::kName[] = PLUGIN_NAME;
ChartboostDelegate *chartboostDelegate;                           // Chartboost delegate

// ----------------------------------------------------------------------------
// helper functions
// ----------------------------------------------------------------------------

// log message to console
void
ChartboostPlugin::logMsg(lua_State *L, NSString* msgType, NSString* errorMsg)
{
	Self *context = ToLibrary(L);
	
	if (context) {
		Self& library = *context;
		
		NSString *functionID = [library.functionSignature copy];
		if (functionID.length > 0) {
			functionID = [functionID stringByAppendingString:@", "];
		}
		
		CoronaLuaLogPrefix(L, [msgType UTF8String], UTF8StringWithFormat(@"%@%@", functionID, errorMsg));
	}
}

// check if SDK calls can be made
bool
ChartboostPlugin::isSDKInitialized(lua_State *L)
{
	// has init() been called?
	if (chartboostDelegate.coronaListener == NULL) {
		logMsg(L, ERROR_MSG, @"chartboost.init() must be called before calling other API methods");
		return false;
	}
	
	// has the 'init' event been received?
	if (! [chartboostObjects[SDK_READY_KEY] boolValue]) {
		logMsg(L, ERROR_MSG, @"Please wait for the 'init' event before calling other API methods");
		return false;
	}
	
	return true;
}


// ----------------------------------------------------------------------------
// plugin implementation
// ----------------------------------------------------------------------------

int
ChartboostPlugin::Open( lua_State *L )
{
	// Register __gc callback
	const char kMetatableName[] = __FILE__; // Globally unique string to prevent collision
	CoronaLuaInitializeGCMetatable( L, kMetatableName, Finalizer );
	
	void *platformContext = CoronaLuaGetContext( L );
	
	// Set library as upvalue for each library function
	Self *library = new Self;
	
	if ( library->Initialize( platformContext ) ) {
		// Functions in library
		static const luaL_Reg kFunctions[] = {
			{"init", init},
			{"load", load},
			{"isLoaded", isLoaded},
			{"isAdVisible", isAdVisible},
			{"show", show},
			{"hide", hide},
			{"onBackPressed", onBackPressed}, // Android only (iOS stub)
			{NULL, NULL}
		};
		
		// Register functions as closures, giving each access to the
		// 'library' instance via ToLibrary()
		{
			CoronaLuaPushUserdata( L, library, kMetatableName );
			luaL_openlib( L, kName, kFunctions, 1 ); // leave "library" on top of stack
		}
	}
	
	return 1;
}

int
ChartboostPlugin::Finalizer( lua_State *L )
{
	Self *library = (Self *)CoronaLuaToUserdata(L, 1);
	
	// Free the Lua listener
	CoronaLuaDeleteRef(L, chartboostDelegate.coronaListener);
	chartboostDelegate = nil;
	
	delete library;
	
	return 0;
}

ChartboostPlugin*
ChartboostPlugin::ToLibrary( lua_State *L )
{
	// library is pushed as part of the closure
	Self *library = (Self *)CoronaLuaToUserdata( L, lua_upvalueindex( 1 ) );
	return library;
}

ChartboostPlugin::ChartboostPlugin()
: coronaViewController( nil )
{
}

bool
ChartboostPlugin::Initialize( void *platformContext )
{
	bool shouldInit = (! coronaViewController);
	
	if ( shouldInit ) {
		id<CoronaRuntime> runtime = (__bridge id<CoronaRuntime>)platformContext;
		coronaViewController = runtime.appViewController;
		
		functionSignature = @"";
		
		// initialize the delegate
		chartboostDelegate = [ChartboostDelegate new];
		chartboostDelegate.coronaRuntime = runtime;
		
		// initialize the ad object dictionary
		chartboostObjects = [NSMutableDictionary new];
		chartboostObjects[SDK_READY_KEY] = @(false);
	}
	
	return shouldInit;
}

// [Lua] chartboost.init(listener, options)
int
ChartboostPlugin::init( lua_State *L )
{
	Self *context = ToLibrary(L);
	
	if (! context) { // abort if no valid context
		return 0;
	}
	
	Self& library = *context;
	
	library.functionSignature = @"chartboost.init(listener, options)";
	
	// prevent init from being called twice
	if (chartboostDelegate.coronaListener != NULL) {
		logMsg(L, WARNING_MSG, @"init() should only be called once");
		return 0;
	}
	
	// get number of arguments
	int nargs = lua_gettop(L);
	if (nargs != 2) {
		logMsg(L, ERROR_MSG, MsgFormat(@"Expected 2 arguments, got %d", nargs));
		return 0;
	}
	
	const char *appId = NULL;
	const char *appSig = NULL;
	const char *customId = NULL;
	bool autoCacheAds = false;
	NSNumber *hasUserConsent = nil;
	
	// Get listener key (required)
	if (CoronaLuaIsListener(L, 1, PROVIDER_NAME)) {
		chartboostDelegate.coronaListener = CoronaLuaNewRef(L, 1);
	}
	else {
		logMsg(L, ERROR_MSG, MsgFormat(@"listener expected, got: %s", luaL_typename(L, 1)));
		return 0;
	}
	
	// check for options table (required)
	if (lua_type(L, 2) == LUA_TTABLE) {
		// traverse and verify all options
		for (lua_pushnil(L); lua_next(L, 2) != 0; lua_pop(L, 1)) {
			const char *key = lua_tostring(L, -2);
			
			if (UTF8IsEqual(key, "appId")) {
				if (lua_type(L, -1) == LUA_TSTRING) {
					appId = lua_tostring(L, -1);
				}
				else {
					logMsg(L, ERROR_MSG, MsgFormat(@"appId (string) expected, got: %s", luaL_typename(L, -1)));
					return 0;
				}
			}
			else if (UTF8IsEqual(key, "appSig")) {
				if (lua_type(L, -1) == LUA_TSTRING) {
					appSig = lua_tostring(L, -1);
				}
				else {
					logMsg(L, ERROR_MSG, MsgFormat(@"appSig (string) expected, got: %s", luaL_typename(L, -1)));
					return 0;
				}
			}
			else if (UTF8IsEqual(key, "hasUserConsent")) {
				if (lua_type(L, -1) == LUA_TBOOLEAN) {
					hasUserConsent = [NSNumber numberWithBool:lua_toboolean(L, -1)];
				}
				else {
					logMsg(L, ERROR_MSG, MsgFormat(@"options.hasUserConsent (boolean) expected, got: %s", luaL_typename(L, -1)));
					return 0;
				}
			}
			else {
				logMsg(L, ERROR_MSG, MsgFormat(@"Invalid option '%s'", key));
				return 0;
			}
		}
	}
	// no options table
	else {
		logMsg(L, ERROR_MSG, MsgFormat(@"options table expected, got %s", luaL_typename(L, 2)));
		return 0;
	}
	
	// validate appId / sig
	if (appId == NULL) {
		logMsg(L, ERROR_MSG, @"options.appId required");
		return 0;
	}
	
	if (appSig == NULL) {
		logMsg(L, ERROR_MSG, @"options.appSig required");
		return 0;
	}
	
	if (hasUserConsent != nil) {
		if ([hasUserConsent boolValue]) {
			[Chartboost addDataUseConsent:[CHBGDPRDataUseConsent gdprConsent:CHBGDPRConsentBehavioral]];
		} else {
			[Chartboost addDataUseConsent:[CHBGDPRDataUseConsent gdprConsent:CHBGDPRConsentNonBehavioral]];
		}
	} else {
		[Chartboost clearDataUseConsentForPrivacyStandard:CHBPrivacyStandardGDPR];
	}
	
	// initialize the SDK
	bool noAtt = true;
	if (@available(iOS 14, tvOS 14, *)) {
		if([[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSUserTrackingUsageDescription"]) {
			noAtt = false;
			[ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) {
				[[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [Chartboost startWithAppID:@(appId) appSignature:@(appSig) completion:^(CHBStartError * _Nullable error) {
                        if(error){
                            [chartboostDelegate didInitialize:false];
                        }else{
                            [chartboostDelegate didInitialize:true];
                        }
                    }];
				}];
			}];
		}
	}
	if(noAtt) {
        [Chartboost startWithAppID:@(appId) appSignature:@(appSig) completion:^(CHBStartError * _Nullable error) {
            if(error){
                [chartboostDelegate didInitialize:false];
            }else{
                [chartboostDelegate didInitialize:true];
            }
        }];
	}
	
	
	// all settings must be done *after* SDK init
	chartboostObjects[AUTO_CACHE_KEY] = @(autoCacheAds);
	
	// store data in object dictionary for later use
	chartboostObjects[APP_ID_KEY] = @(appId);
	chartboostObjects[APP_SIGNATURE_KEY] = @(appSig);
	
	// need to call startSession() on app resume. set selector to get notified
	[[NSNotificationCenter defaultCenter]
	 addObserver:chartboostDelegate
	 selector:@selector(resumeSession)
	 name:UIApplicationDidBecomeActiveNotification
	 object:nil
	 ];
	
	// log plugin version to the console
	NSLog(@"%s: %s (SDK: %@)", PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_SDK_VERSION);
	
	return 0;
}

// [Lua] chartboost.load( adType [, namedLocation] )
int
ChartboostPlugin::load( lua_State *L )
{
	Self *context = ToLibrary(L);
	
	if (! context) { // abort if no valid context
		return 0;
	}
	
	Self& library = *context;
	
	library.functionSignature = @"chartboost.load(adType [, namedLocation])";
	
	if (! isSDKInitialized(L)) {
		return 0;
	}
	
	// get number of arguments
	int nargs = lua_gettop(L);
	if ((nargs < 1) || (nargs > 2)) {
		logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 or 2 arguments, got %d", nargs));
		return 0;
	}
	
	const char *adType = NULL;
	const char *namedLocation = NULL;
	
	// Get the ad type
	if (lua_type(L, 1) == LUA_TSTRING) {
		adType = lua_tostring(L, 1);
	}
	else {
		logMsg(L, ERROR_MSG, MsgFormat(@"adType expected (string), got %s", luaL_typename(L, 1)));
		return 0;
	}
	
	// Get the named location
	if (! lua_isnoneornil(L, 2)) {
		if (lua_type(L, 2) == LUA_TSTRING) {
			namedLocation = lua_tostring(L, 2);
		}
		else {
			logMsg(L, ERROR_MSG, MsgFormat(@"namedLocation expected (string), got %s", luaL_typename(L, 2)));
			return 0;
		}
	}
	
	// validate adType
	if (! [validAdTypes containsObject:@(adType)]) {
		logMsg(L, ERROR_MSG, MsgFormat(@"Invalid adType '%s'", adType));
		return 0;
	}
	
	// load an ad
	[[NSOperationQueue mainQueue] addOperationWithBlock:^{
		// get location
		NSString *location = (namedLocation == NULL) ? @"default" : @(namedLocation);
		[[chartboostDelegate getAd:@(adType) location:location] cache];
	}];
	
	return 0;
}

// [Lua] chartboost.isLoaded(adType [, namedLocation]) -> boolean
int
ChartboostPlugin::isLoaded( lua_State *L )
{
	Self *context = ToLibrary(L);
	
	if (! context) { // abort if no valid context
		return 0;
	}
	
	Self& library = *context;
	
	library.functionSignature = @"chartboost.isLoaded(adType [, namedLocation])";
	
	if (! isSDKInitialized(L)) {
		return 0;
	}
	
	// get number of arguments
	int nargs = lua_gettop(L);
	if ((nargs < 1) || (nargs > 2)) {
		logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 or 2 arguments, got %d", nargs));
		return 0;
	}
	
	const char *adType = NULL;
	const char *namedLocation = NULL;
	
	// Get the ad type
	if (lua_type(L, 1) == LUA_TSTRING) {
		adType = lua_tostring(L, 1);
	}
	else {
		logMsg(L, ERROR_MSG, MsgFormat(@"adType expected (string), got %s", luaL_typename(L, 1)));
		return 0;
	}
	
	// Get the named location
	if (! lua_isnoneornil(L, 2)) {
		if (lua_type(L, 2) == LUA_TSTRING) {
			namedLocation = lua_tostring(L, 2);
		}
		else {
			logMsg(L, ERROR_MSG, MsgFormat(@"namedLocation expected (string), got %s", luaL_typename(L, 2)));
			return 0;
		}
	}
	
	// validate adType
	if (! [validAdTypes containsObject:@(adType)]) {
		logMsg(L, ERROR_MSG, MsgFormat(@"Invalid adType '%s'", adType));
		return 0;
	}
	
	// get location
    
	NSString *location = (namedLocation == NULL) ? @"default" : @(namedLocation);
	bool isLoaded = false;
	
	// check if ad is loaded
    isLoaded = [[chartboostDelegate getAd:@(adType) location:location] isCached];
	
	// push result to Lua stack
	lua_pushboolean(L, isLoaded);
	
	return 1;
}

// [Lua] chartboost.isAdVisible() (deprecated since chartboost.closeImpression has been removed)
// removed from Corona plugin documentation
int
ChartboostPlugin::isAdVisible(lua_State *L)
{
	lua_pushboolean(L, false);
	return 1;
}

//  [Lua] chartboost.show(adType [, namedLocation])
int
ChartboostPlugin::show( lua_State *L )
{
	Self *context = ToLibrary(L);
	
	if (! context) { // abort if no valid context
		return 0;
	}
	
	Self& library = *context;
	
	library.functionSignature = @"chartboost.show(adType [, namedLocation])";
	
	if ( ! isSDKInitialized(L) ) {
		return 0;
	}
	
	// get number of arguments
	int nargs = lua_gettop(L);
	if ((nargs < 1) || (nargs > 2)) {
		logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 or 2 arguments, got %d", nargs));
		return 0;
	}
	
	const char *adType = NULL;
	const char *namedLocation = NULL;
	
	// Get the ad type
	if (lua_type(L, 1) == LUA_TSTRING) {
		adType = lua_tostring(L, 1);
	}
	else {
		logMsg(L, ERROR_MSG, MsgFormat(@"adType expected (string), got %s", luaL_typename(L, 1)));
		return 0;
	}
	
	// Get the named location
	if (! lua_isnoneornil(L, 2)) {
		if (lua_type(L, 2) == LUA_TSTRING) {
			namedLocation = lua_tostring(L, 2);
		}
		else {
			logMsg(L, ERROR_MSG, MsgFormat(@"namedLocation expected (string), got %s", luaL_typename(L, 2)));
			return 0;
		}
	}
	
	// validate adType
	if (! [validAdTypes containsObject:@(adType)]) {
		logMsg(L, ERROR_MSG, MsgFormat(@"Invalid adType '%s'", adType));
		return 0;
	}
	
	// get location
	NSString *location = (namedLocation == NULL) ? @"default" : @(namedLocation);
	
	id<CHBAd> ad = [chartboostDelegate getAd:@(adType) location:location];
	bool isLoaded = [ad isCached];
	
	if (! isLoaded) {
		logMsg(L, ERROR_MSG, MsgFormat(@"adType '%s' not loaded", adType));
		return 0;
	}
	
	// show an ad
	[[NSOperationQueue mainQueue] addOperationWithBlock:^{
		[ad showFromViewController:context->coronaViewController];
	}];
	
	return 0;
}

// [Lua] chartboost.hide() (removed as of Chartboost SDK 6.5.1)
// removed from Corona plugin documentation
int
ChartboostPlugin::hide(lua_State *L)
{
	// NOP as of Chartboost SDK 6.5.1
	return 0;
}

// [Lua] chartboost.onBackPressed()
int
ChartboostPlugin::onBackPressed(lua_State *L)
{
	// Android only, NOP on iOS.
	return 0;
}

// ============================================================================
// delegate implementation
// ============================================================================

@implementation ChartboostDelegate

- (instancetype)init {
	if (self = [super init]) {
		self.coronaListener = NULL;
		self.coronaRuntime = NULL;
		self.ads = [[NSMutableDictionary alloc] init];
	}
	
	return self;
}

-(id<CHBAd>)getAd:(NSString *)type location:(NSString*)location
{
	NSMutableDictionary<NSString*, id<CHBAd>>* adDict = [self.ads objectForKey:type];
	if(!adDict) {
		adDict = [NSMutableDictionary dictionaryWithCapacity:1];
		[self.ads setObject:adDict forKey:type];
	}
	id<CHBAd> ret = [adDict objectForKey:location];

	if(!ret) {
		if([type isEqualToString:@(TYPE_REWARDED_VIDEO)]) {
			ret = [[CHBRewarded alloc] initWithLocation:location delegate:self];
		}
		else if([type isEqualToString:@(TYPE_INTERSTITIAL)]) {
			ret = [[CHBInterstitial alloc] initWithLocation:location delegate:self];
		}
		if(ret) {
			[adDict setObject:ret forKey:location];
		}
	}
	return ret;
}

// dispatch a new Lua event
- (void)dispatchLuaEvent:(NSDictionary *)dict
{
	[[NSOperationQueue mainQueue] addOperationWithBlock:^{
		lua_State *L = self.coronaRuntime.L;
		CoronaLuaRef coronaListener = self.coronaListener;
		bool hasErrorKey = false;
		
		// create new event
		CoronaLuaNewEvent(L, EVENT_NAME);
		
		for (NSString *key in dict) {
			CoronaLuaPushValue(L, [dict valueForKey:key]);
			lua_setfield(L, -2, key.UTF8String);
			
			if (! hasErrorKey) {
				hasErrorKey = [key isEqualToString:@(CoronaEventIsErrorKey())];
			}
		}
		
		// add error key if not in dict
		if (! hasErrorKey) {
			lua_pushboolean(L, false);
			lua_setfield(L, -2, CoronaEventIsErrorKey());
		}
		
		// add provider
		lua_pushstring(L, PROVIDER_NAME );
		lua_setfield(L, -2, CoronaEventProviderKey());
		
		CoronaLuaDispatchEvent(L, coronaListener, 0);
	}];
}

// create JSON string from CBlocation, reward and error
- (NSString *)getJSONStringForLocation:(NSString*)location reward:(NSInteger)reward errorString:(NSString*)error andCode:(long)errorCode;
{
	NSMutableDictionary *dataDictionary = [NSMutableDictionary new];
	dataDictionary[@"location"] = location;
	
	if (reward != NO_DATA) {
		dataDictionary[@"reward"] = @(reward);
	}
	
	if (error) {
		dataDictionary[@"errorMsg"] = error;
		dataDictionary[@"errorCode"] = @(errorCode);
	}
	
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dataDictionary options:0 error:nil];
	
	return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

// will be called every time the app resumes
- (void) resumeSession {
	// initialize SDK on resume
	if ([chartboostObjects[SDK_READY_KEY] boolValue]) {
		NSString *appID = chartboostObjects[APP_ID_KEY];
		NSString *appSignature =  chartboostObjects[APP_SIGNATURE_KEY];
        [Chartboost startWithAppID:appID appSignature:appSignature completion:^(CHBStartError * _Nullable error) {
            if(error){
                [chartboostDelegate didInitialize:false];
            }else{
                [chartboostDelegate didInitialize:true];
            }
        }];
	}
}

// SDK initialization delegate method
- (void)didInitialize:(BOOL)status
{
	// did init fail?
	if (status == NO) {
		// NOTE: Android doesn't pass a status to didInitialize.
		// if status=NO, call has failed. return without sending 'init' event
		// to keep the event postings the same on both platforms.
		return;
	}
	
	// flag the SDK as ready for API calls
	chartboostObjects[SDK_READY_KEY] = @(true);
	
	// send Corona Lua event
	NSDictionary *coronaEvent = @{
		@(CoronaEventPhaseKey()) : PHASE_INIT
	};
	[self dispatchLuaEvent:coronaEvent];
}

+ (NSString *)adTypeFromEvent:(CHBAdEvent *)event {
	if([event.ad isKindOfClass:[CHBInterstitial class]]) {
		return @(TYPE_INTERSTITIAL);
	}
	if([event.ad isKindOfClass:[CHBRewarded class]]) {
		return @(TYPE_REWARDED_VIDEO);
	}
	return @"UNKNOWN";
}

-(void)didShowAd:(CHBShowEvent *)event error:(CHBShowError *)error {
	NSDictionary *coronaEvent;
	if(!error) {
		coronaEvent = @{
			@(CoronaEventPhaseKey()) : PHASE_DISPLAYED,
			@(CoronaEventTypeKey()) : [ChartboostDelegate adTypeFromEvent:event],
			CORONA_EVENT_DATA_KEY : [self getJSONStringForLocation:event.ad.location reward:NO_DATA errorString:nil andCode:0]
		};
	} else
	{
        NSError *mainError = (NSError *)error;
		coronaEvent = @{
			@(CoronaEventPhaseKey()) : PHASE_FAILED,
			@(CoronaEventTypeKey()) : [ChartboostDelegate adTypeFromEvent:event],
			@(CoronaEventIsErrorKey()) : @(true),
			@(CoronaEventResponseKey()) : RESPONSE_LOAD_FAILED,
            CORONA_EVENT_DATA_KEY : [self getJSONStringForLocation:event.ad.location reward:NO_DATA errorString:mainError.localizedDescription andCode:mainError.code]
		};
	}
	[self dispatchLuaEvent:coronaEvent];
	if(!error && [chartboostObjects objectForKey:AUTO_CACHE_KEY]) {
		[event.ad cache];
	}
}

-(void)didDismissAd:(CHBDismissEvent *)event{
	NSDictionary *coronaEvent = @{
		@(CoronaEventPhaseKey()) : PHASE_CLOSED,
		@(CoronaEventTypeKey()) : [ChartboostDelegate adTypeFromEvent:event],
		CORONA_EVENT_DATA_KEY : [self getJSONStringForLocation:event.ad.location reward:NO_DATA errorString:nil andCode:0]
	};
	[self dispatchLuaEvent:coronaEvent];
}

- (void)didClickAd:(CHBClickEvent *)event error:(CHBClickError *)error {
	NSDictionary *coronaEvent = @{
		@(CoronaEventPhaseKey()) : PHASE_CLICKED,
		@(CoronaEventTypeKey()) : [ChartboostDelegate adTypeFromEvent:event],
		CORONA_EVENT_DATA_KEY : [self getJSONStringForLocation:event.ad.location reward:NO_DATA errorString:nil andCode:0]
	};
	[self dispatchLuaEvent:coronaEvent];
	
}

- (void)didCacheAd:(CHBCacheEvent *)event error:(CHBCacheError *)error {
	NSDictionary *coronaEvent;
    
	if(!error) {
		coronaEvent = @{
			@(CoronaEventPhaseKey()) : PHASE_LOADED,
			@(CoronaEventTypeKey()) : [ChartboostDelegate adTypeFromEvent:event],
			CORONA_EVENT_DATA_KEY : [self getJSONStringForLocation:event.ad.location reward:NO_DATA errorString:nil andCode:0]
		};
	}
	else
	{
        NSError *mainError = (NSError *)error;
		coronaEvent = @{
			@(CoronaEventPhaseKey()) : PHASE_FAILED,
			@(CoronaEventTypeKey()) : [ChartboostDelegate adTypeFromEvent:event],
			@(CoronaEventIsErrorKey()) : @(true),
			@(CoronaEventResponseKey()) : RESPONSE_LOAD_FAILED,
            CORONA_EVENT_DATA_KEY : [self getJSONStringForLocation:event.ad.location reward:NO_DATA errorString:mainError.localizedDescription andCode:mainError.code]
		};
	}
	[self dispatchLuaEvent:coronaEvent];
	
	
}

-(void)didEarnReward:(CHBRewardEvent *)event
{
	NSDictionary *coronaEvent = @{
		@(CoronaEventPhaseKey()) : PHASE_REWARD,
		@(CoronaEventTypeKey()) : @(TYPE_REWARDED_VIDEO),
		CORONA_EVENT_DATA_KEY : [self getJSONStringForLocation:event.ad.location reward:event.reward errorString:nil andCode:0]
	};
	[self dispatchLuaEvent:coronaEvent];
	
}

@end

// ----------------------------------------------------------------------------

CORONA_EXPORT int
luaopen_plugin_chartboost( lua_State *L )
{
	return ChartboostPlugin::Open( L );
}
