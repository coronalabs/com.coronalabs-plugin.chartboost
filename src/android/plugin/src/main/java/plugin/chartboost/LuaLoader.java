// LuaLoader.java
// Chartboost Plugin
//
// Copyright (c) 2016 CoronaLabs inc. All rights reserved.

// @formatter:off

package plugin.chartboost;

import com.naef.jnlua.LuaState;
import com.naef.jnlua.JavaFunction;
import com.naef.jnlua.LuaType;
import com.naef.jnlua.NamedJavaFunction;

import com.ansca.corona.CoronaLua;
import com.ansca.corona.CoronaLuaEvent;
import com.ansca.corona.CoronaRuntimeTask;
import com.ansca.corona.CoronaRuntimeTaskDispatcher;
import com.ansca.corona.CoronaActivity;
import com.ansca.corona.CoronaEnvironment;
import com.ansca.corona.CoronaRuntime;
import com.ansca.corona.CoronaRuntimeListener;
import com.ansca.corona.CoronaBeacon;

import android.content.Context;
import android.util.Log;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.HashMap;
import java.util.Map;

// Chartboost imports
import com.chartboost.sdk.Chartboost;
import com.chartboost.sdk.CBLocation;
import com.chartboost.sdk.ChartboostDelegate;
import com.chartboost.sdk.Model.CBError;

/**
 * Implements the Lua interface for the Chartboost plugin.
 * <p>
 * Only one instance of this class will be created by Corona for the lifetime of the application.
 * This instance will be re-used for every new Corona activity that gets created.
 */
@SuppressWarnings("unused")
public class LuaLoader implements JavaFunction, CoronaRuntimeListener
{
  private static final String PLUGIN_NAME        = "plugin.chartboost";
  private static final String PLUGIN_VERSION     = "2.0.9";
  private static final String PLUGIN_SDK_VERSION = Chartboost.getSDKVersion();

  private static final String EVENT_NAME    = "adsRequest";
  private static final String PROVIDER_NAME = "chartboost";

  // event types
  private static final String TYPE_INTERSTITIAL   = "interstitial";
  private static final String TYPE_REWARDED_VIDEO = "rewardedVideo";

  // validation arrays
  private static final List<String> validAdTypes = new ArrayList<>();

  // data keysof user feedback
  private static final String DATA_LOCATION_KEY  = "location";
  private static final String DATA_ERRORMSG_KEY  = "errorMsg";
  private static final String DATA_ERRORCODE_KEY = "errorCode";
  private static final String DATA_REWARD_KEY    = "reward";

  // add missing keys
  private static final String EVENT_PHASE_KEY = "phase";
  private static final String EVENT_TYPE_KEY  = "type";
  private static final String EVENT_DATA_KEY  = "data";

  // response keys
  private static final String RESPONSE_LOAD_FAILED = "loadFailed";

  // event phases
  private static final String PHASE_INIT      = "init";
  private static final String PHASE_DISPLAYED = "displayed";
  private static final String PHASE_FAILED    = "failed";
  private static final String PHASE_CLOSED    = "closed";
  private static final String PHASE_CLICKED   = "clicked";
  private static final String PHASE_LOADED    = "loaded";
  private static final String PHASE_REWARD    = "reward";

  private static int coronaListener = CoronaLua.REFNIL;
  private static CoronaRuntime coronaRuntime;
  private static CoronaRuntimeTaskDispatcher coronaRuntimeTaskDispatcher = null;

  // detect soft boot (needed to initialize SDK)
  // used to send 'init' event on second+ launch as 'init' is only sent by the SDK on first launch
  private static boolean softBoot = false;

  // message constants
  private static final String CORONA_TAG  = "Corona";
  private static final String ERROR_MSG   = "ERROR: ";
  private static final String WARNING_MSG = "WARNING: ";

  private static String functionSignature = "";                                  // used in error reporting functions
  private static final Map<String, Object> chartboostObjects = new HashMap<>();  // keep track of loaded objects

  // object dictionary keys
  private static final String SDK_READY_KEY     = "sdkReady";
  private static final String APP_ID_KEY        = "appID";
  private static final String APP_SIGNATURE_KEY = "appSignature";

  // Corona APP ID / SIG

  // delegates
  private static CoronaChartboostDelegate coronaChartboostDelegate = null;

  // -------------------------------------------------------------------
  // Plugin lifecycle events
  // -------------------------------------------------------------------

  /**
   * <p>
   * Note that a new LuaLoader instance will not be created for every CoronaActivity instance.
   * That is, only one instance of this class will be created for the lifetime of the application process.
   * This gives a plugin the option to do operations in the background while the CoronaActivity is destroyed.
   */
  @SuppressWarnings("unused")
  public LuaLoader()
  {
    // Set up this plugin to listen for Corona runtime events to be received by methods
    // onLoaded(), onStarted(), onSuspended(), onResumed(), and onExiting().
    CoronaEnvironment.addRuntimeListener(this);
  }
 
  /**
   * Called when this plugin is being loaded via the Lua require() function.
   * <p>
   * Note that this method will be called every time a new CoronaActivity has been launched.
   * This means that you'll need to re-initialize this plugin here.
   * <p>
   * Warning! This method is not called on the main UI thread.
   * @param L Reference to the Lua state that the require() function was called from.
   * @return Returns the number of values that the require() function will return.
   *         <p>
   *         Expected to return 1, the library that the require() function is loading.
   */
  @Override
  public int invoke( LuaState L )
  {
    // Register this plugin into Lua with the following functions.
    NamedJavaFunction[] luaFunctions = new NamedJavaFunction[] {
      new Init(),
      new Load(),
      new IsLoaded(),
      new IsAdVisible(),
      new Show(),
      new Hide(),
      new OnBackPressed()
    };
    String libName = L.toString( 1 );
    L.register( libName, luaFunctions );
 
    // Returning 1 indicates that the Lua require() function will return the above Lua
    return 1;
  }

  /**
   * Called after the Corona runtime has been created and just before executing the "main.lua" file.
   * <p>
   * Warning! This method is not called on the main thread.
   * @param runtime Reference to the CoronaRuntime object that has just been loaded/initialized.
   *                Provides a LuaState object that allows the application to extend the Lua API.
   */
  @Override
  public void onLoaded(CoronaRuntime runtime)
  {
    // Note that this method will not be called the first time a Corona activity has been launched.
    // This is because this listener cannot be added to the CoronaEnvironment until after
    // this plugin has been required-in by Lua, which occurs after the onLoaded() event.
    // However, this method will be called when a 2nd Corona activity has been created.

    if (coronaRuntimeTaskDispatcher == null) {
      coronaRuntimeTaskDispatcher = new CoronaRuntimeTaskDispatcher(runtime);
      coronaRuntime = runtime;

      // initialize validation
      validAdTypes.add(TYPE_INTERSTITIAL);
      validAdTypes.add(TYPE_REWARDED_VIDEO);

      // initialize chartboost object dictionary
      chartboostObjects.put(SDK_READY_KEY, false);

      // initialize delegate
      coronaChartboostDelegate = new CoronaChartboostDelegate();
    }
  }
 
  /**
   * Called just after the Corona runtime has executed the "main.lua" file.
   * <p>
   * Warning! This method is not called on the main thread.
   * @param runtime Reference to the CoronaRuntime object that has just been started.
   */
  @Override
  public void onStarted( CoronaRuntime runtime )
  {
  }
 
  /**
   * Called just after the Corona runtime has been suspended which pauses all rendering, audio, timers,
   * and other Corona related operations. This can happen when another Android activity (ie: window) has
   * been displayed, when the screen has been powered off, or when the screen lock is shown.
   * <p>
   * Warning! This method is not called on the main thread.
   * @param runtime Reference to the CoronaRuntime object that has just been suspended.
   */
  @Override
  public void onSuspended( CoronaRuntime runtime )
  {
  }
 
  /**
   * Called just after the Corona runtime has been resumed after a suspend.
   * <p>
   * Warning! This method is not called on the main thread.
   * @param runtime Reference to the CoronaRuntime object that has just been resumed.
   */
  @Override
  public void onResumed( CoronaRuntime runtime )
  {
  }
 
  /**
   * Called just before the Corona runtime terminates.
   * <p>
   * This happens when the Corona activity is being destroyed which happens when the user presses the Back button
   * on the activity, when the native.requestExit() method is called in Lua, or when the activity's finish()
   * method is called. This does not mean that the application is exiting.
   * <p>
   * Warning! This method is not called on the main thread.
   * @param runtime Reference to the CoronaRuntime object that is being terminated.
   */
  @Override
  public void onExiting(CoronaRuntime runtime)
  {
    Chartboost.setDelegate(null);

    CoronaLua.deleteRef(runtime.getLuaState(), coronaListener);
    coronaListener = CoronaLua.REFNIL;
    coronaRuntime = null;
    coronaRuntimeTaskDispatcher = null;

    // release all objects
    chartboostObjects.clear();
    validAdTypes.clear();
    coronaChartboostDelegate = null;
  }

  // -------------------------------------------------------------------
  // helper functions
  // -------------------------------------------------------------------

  // log message to console
  private void logMsg(String msgType, String errorMsg)
  {
    String functionID = functionSignature;
    if (!functionID.isEmpty()) {
      functionID += ", ";
    }

    Log.i(CORONA_TAG, msgType + functionID + errorMsg);
  }

  // return true if SDK is properly initialized
  private boolean isSDKInitialized()
  {
    if (coronaListener == CoronaLua.REFNIL) {
      logMsg(ERROR_MSG, "chartboost.init() must be called before calling other API functions");
      return false;
    }

    if (! (boolean)chartboostObjects.get(SDK_READY_KEY)) {
      logMsg(ERROR_MSG, "Please wait for the 'init' event before calling other API functions");
      return false;
    }

    return true;
  }

  // dispatch a Lua event to our callback (dynamic handling of properties through map)
  private void dispatchLuaEvent(final Map<String, Object> event) {
    if (coronaRuntimeTaskDispatcher != null) {
      coronaRuntimeTaskDispatcher.send(new CoronaRuntimeTask() {
        @Override
        public void executeUsing(CoronaRuntime runtime) {
          try {
            LuaState L = runtime.getLuaState();
            CoronaLua.newEvent(L, EVENT_NAME);
            boolean hasErrorKey = false;

            // add event parameters from map
            for (String key: event.keySet()) {
              CoronaLua.pushValue(L, event.get(key));           // push value
              L.setField(-2, key);                              // push key

              if (! hasErrorKey) {
                hasErrorKey = key.equals(CoronaLuaEvent.ISERROR_KEY);
              }
            }

            // add error key if not in map
            if (! hasErrorKey) {
              L.pushBoolean(false);
              L.setField(-2, CoronaLuaEvent.ISERROR_KEY);
            }

            // add provider
            L.pushString(PROVIDER_NAME);
            L.setField(-2, CoronaLuaEvent.PROVIDER_KEY);

            CoronaLua.dispatchEvent(L, coronaListener, 0);
          }
          catch (Exception ex) {
            ex.printStackTrace();
          }
        }
      });
    }
  }

  // -------------------------------------------------------------------
  // Plugin implementation
  // -------------------------------------------------------------------

  // [Lua] chartboost.init(listener , options)
  public class Init implements NamedJavaFunction
  {
    /**
     * Gets the name of the Lua function as it would appear in the Lua script.
     * @return Returns the name of the custom Lua function.
     */
    @Override
    public String getName() {
      return "init";
    }

    /**
     * This method is called when the Lua function is called.
     * <p>
     * Warning! This method is not called on the main UI thread.
     * @param luaState Reference to the Lua state.
     *                 Needed to retrieve the Lua function's parameters and to return values back to Lua.
     * @return Returns the number of values to be returned by the Lua function.
     */
    @Override
    public int invoke( final LuaState luaState )
    {
      // set function signature for error / warning messages
      functionSignature = "chartboost.init(listener, options)";

      // prevent init from being called twice
      if (coronaListener != CoronaLua.REFNIL) {
        logMsg(ERROR_MSG, "init() should only be called once");
        return 0;
      }

      String appId = null;
      String appSig = null;
      String customId = null;
      boolean autoCacheAds = false;
      Boolean hasUserConsent = null;

      // check number of arguments passed
      int nargs = luaState.getTop();
      if (nargs != 2) {
        logMsg(ERROR_MSG, "2 arguments expected. got " + nargs);
        return 0;
      }

      // get listener (required)
      if (CoronaLua.isListener(luaState, 1, PROVIDER_NAME)) {
        coronaListener = CoronaLua.newRef(luaState, 1);
      }
      else {
        logMsg(ERROR_MSG, "listener function expected, got: " + luaState.typeName(1));
        return 0;
      }

      // check for options table
      if (luaState.type(2) == LuaType.TABLE) {
        for (luaState.pushNil(); luaState.next(2); luaState.pop(1)) {
          String key = luaState.toString(-2);

          if (key.equals("appId")) {
            if (luaState.type(-1) == LuaType.STRING) {
              appId = luaState.toString(-1);
            }
            else {
              logMsg(ERROR_MSG, "options.appId expected (string). Got " + luaState.typeName(-1));
              return 0;
            }
          }
          else if (key.equals("appSig")) {
            if (luaState.type(-1) == LuaType.STRING) {
              appSig = luaState.toString(-1);
            }
            else {
              logMsg(ERROR_MSG, "options.appSig expected (string). Got " + luaState.typeName(-1));
              return 0;
            }
          }
          else if (key.equals("customId")) {
            if (luaState.type(-1) == LuaType.STRING) {
              customId = luaState.toString(-1);
            }
            else {
              logMsg(ERROR_MSG, "options.customId expected (string). Got " + luaState.typeName(-1));
              return 0;
            }
          }
          else if (key.equals("autoCacheAds")) {
            if (luaState.type(-1) == LuaType.BOOLEAN) {
              autoCacheAds = luaState.toBoolean(-1);
            }
            else {
              logMsg(ERROR_MSG, "options.autoCacheAds expected (boolean). Got " + luaState.typeName(-1));
              return 0;
            }
          }
          else if (key.equals("hasUserConsent")) {
            if (luaState.type(-1) == LuaType.BOOLEAN) {
              hasUserConsent = luaState.toBoolean(-1);
            }
            else {
              logMsg(ERROR_MSG, "options.hasUserConsent expected (boolean). Got " + luaState.typeName(-1));
              return 0;
            }
          }
          else {
            logMsg(ERROR_MSG, "Invalid option '" + key + "'");
            return 0;
          }
        }
      }
      else {
        logMsg(ERROR_MSG, "options table expected. Got " + luaState.typeName(2));
        return 0;
      }

      // validate appId and appSig
      if (appId == null) {
        logMsg(ERROR_MSG, "options.appId is required");
        return 0;
      }
      if (appSig == null) {
        logMsg(ERROR_MSG, "options.appSig is required");
        return 0;
      }

      // log plugin version to the console
      Log.i(CORONA_TAG, PLUGIN_NAME + ": " + PLUGIN_VERSION + " (SDK: " + PLUGIN_SDK_VERSION + ")");

      // store data in object dictionary for later use
      chartboostObjects.put(APP_ID_KEY, appId);
      chartboostObjects.put(APP_SIGNATURE_KEY, appSig);

      // declare final variables for inner loop
      final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
      final Context applicationContext = CoronaEnvironment.getApplicationContext();
      final String fAppId = appId;
      final String fAppSignature = appSig;
      final String fCustomId = customId;
      final boolean fAutoCacheAds = autoCacheAds;
      final Boolean fHasUserConsent = hasUserConsent;

      if (coronaActivity != null) {
        Runnable runnableActivity = new Runnable() {
          public void run() {
            if (fHasUserConsent != null) {
              if (fHasUserConsent) {
                Chartboost.setPIDataUseConsent(applicationContext, Chartboost.CBPIDataUseConsent.YES_BEHAVIORAL);
              } else {
                Chartboost.setPIDataUseConsent(applicationContext, Chartboost.CBPIDataUseConsent.NO_BEHAVIORAL);
              }
            } else {
              Chartboost.setPIDataUseConsent(applicationContext, Chartboost.CBPIDataUseConsent.UNKNOWN);
            }

            // initialize SDK
            Chartboost.startWithAppId(applicationContext, fAppId, fAppSignature);

            // setup must be done after SDK init
            Chartboost.setAutoCacheAds(fAutoCacheAds);
            Chartboost.setShouldPrefetchVideoContent(true);
            Chartboost.setShouldRequestInterstitialsInFirstSession(true);
            if (fCustomId != null) {
              Chartboost.setCustomId(fCustomId);
            }
            Chartboost.setFramework(Chartboost.CBFramework.CBFrameworkCorona, PLUGIN_VERSION);
            Chartboost.setDelegate(coronaChartboostDelegate);

            // send init event on soft boot as the Chartboost SDK doesn't do it
            if (softBoot) {
              coronaChartboostDelegate.didInitialize();
            }
          }
        };

        coronaActivity.runOnUiThread( runnableActivity );
      }

      return 0;
    }
  }

  // [Lua] chartboost.load(adType [, namedLocation])
  public class Load implements NamedJavaFunction
  {
    /**
     * Gets the name of the Lua function as it would appear in the Lua script.
     * @return Returns the name of the custom Lua function.
     */
    @Override
    public String getName() {
      return "load";
    }

    /**
     * This method is called when the Lua function is called.
     * <p>
     * Warning! This method is not called on the main UI thread.
     * @param luaState Reference to the Lua state.
     *                 Needed to retrieve the Lua function's parameters and to return values back to Lua.
     * @return Returns the number of values to be returned by the Lua function.
     */
    @Override
    public int invoke( LuaState luaState )
    {
      functionSignature = "chartboost.load(adType [, namedLocation])";

      if (! isSDKInitialized()) {
        return 0;
      }

      // get number of arguments
      int nargs = luaState.getTop();
      if ((nargs < 1) || (nargs > 2)) {
        logMsg(ERROR_MSG, "Expected 1 or 2 arguments, got " + nargs);
        return 0;
      }

      String adType = null;
      String namedLocation = null;

      // Get the ad type
      if (luaState.type(1) == LuaType.STRING) {
        adType = luaState.toString(1);
      }
      else {
        logMsg(ERROR_MSG, "adType expected (string), got " + luaState.typeName(1));
        return 0;
      }

      // Get the named location
      if (! luaState.isNoneOrNil(2)) {
        if (luaState.type(2) == LuaType.STRING) {
          namedLocation = luaState.toString(2);
        }
        else {
          logMsg(ERROR_MSG, "namedLocation expected (string), got " + luaState.typeName(2));
          return 0;
        }
      }

      if (! validAdTypes.contains(adType)) {
        logMsg(ERROR_MSG, "invalid adType '"+ adType + "'");
        return 0;
      }

      // declare final variables for inner loop
      final String fAdType = adType;
      final String fNamedLocation = namedLocation;
      final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();

      // Run the activity on the uiThread
      if (coronaActivity != null) {
        // Create a new runnable object to invoke our activity
        Runnable runnableActivity = new Runnable() {
          public void run() {
            String location = (fNamedLocation != null) ? fNamedLocation : CBLocation.LOCATION_DEFAULT;

            if (fAdType.equals(TYPE_REWARDED_VIDEO)) {
              Chartboost.cacheRewardedVideo(location);
            }
            else if (fAdType.equals(TYPE_INTERSTITIAL)) {
              Chartboost.cacheInterstitial(location);
            }
            else {
              logMsg(ERROR_MSG, "Invalid ad type '" + fAdType + "'");
            }
          }
        };

        coronaActivity.runOnUiThread(runnableActivity);
      }

      return 0;
    }
  }

  // [Lua] chartboost.isLoaded(adType [, namedLocation])
  public class IsLoaded implements NamedJavaFunction
  {
    /**
     * Gets the name of the Lua function as it would appear in the Lua script.
     * @return Returns the name of the custom Lua function.
     */
    @Override
    public String getName() {
      return "isLoaded";
    }

    /**
     * This method is called when the Lua function is called.
     * <p>
     * Warning! This method is not called on the main UI thread.
     * @param luaState Reference to the Lua state.
     *                 Needed to retrieve the Lua function's parameters and to return values back to Lua.
     * @return Returns the number of values to be returned by the Lua function.
     */
    @Override
    public int invoke( LuaState luaState )
    {
      functionSignature = "chartboost.isLoaded(adType [, namedLocation])";

      if (! isSDKInitialized()) {
        return 0;
      }

      // get number of arguments
      int nargs = luaState.getTop();
      if ((nargs < 1) || (nargs > 2)) {
        logMsg(ERROR_MSG, "Expected 1 or 2 arguments, got " + nargs);
        return 0;
      }

      String adType = null;
      String namedLocation = null;

      // Get the ad type
      if (luaState.type(1) == LuaType.STRING) {
        adType = luaState.toString(1);
      }
      else {
        logMsg(ERROR_MSG, "adType expected (string), got " + luaState.typeName(1));
        return 0;
      }

      // Get the named location
      if (! luaState.isNoneOrNil(2)) {
        if (luaState.type(2) == LuaType.STRING) {
          namedLocation = luaState.toString(2);
        }
        else {
          logMsg(ERROR_MSG, "namedLocation expected (string), got " + luaState.typeName(2));
          return 0;
        }
      }

      if (! validAdTypes.contains(adType)){
        logMsg(ERROR_MSG, "invalid adType '"+ adType + "'");
        return 0;
      }

      boolean isLoaded = false;
      String location = (namedLocation != null) ? namedLocation : CBLocation.LOCATION_DEFAULT;

      if (adType.equals(TYPE_REWARDED_VIDEO)) {
        isLoaded = Chartboost.hasRewardedVideo(location);
      }
      else if (adType.equals(TYPE_INTERSTITIAL)) {
        isLoaded = Chartboost.hasInterstitial(location);
      }
      else {
        logMsg(ERROR_MSG, "Invalid ad type '" + adType + "'");
      }

      luaState.pushBoolean(isLoaded);

      return 1;
    }
  }

  // [Lua] chartboost.isAdVisible()
  public class IsAdVisible implements NamedJavaFunction
  {
    /**
     * Gets the name of the Lua function as it would appear in the Lua script.
     * @return Returns the name of the custom Lua function.
     */
    @Override
    public String getName() {
      return "isAdVisible";
    }

    /**
     * This method is called when the Lua function is called.
     * <p>
     * Warning! This method is not called on the main UI thread.
     * @param luaState Reference to the Lua state.
     *                 Needed to retrieve the Lua function's parameters and to return values back to Lua.
     * @return Returns the number of values to be returned by the Lua function.
     */
    @Override
    public int invoke( LuaState luaState )  {
      functionSignature = "chartboost.isAdVisible()";

      if (! isSDKInitialized()) {
        return 0;
      }

      // get number of arguments
      int nargs = luaState.getTop();
      if (nargs != 0) {
        logMsg(ERROR_MSG, "Expected no arguments, got " + nargs);
        return 0;
      }

      // return true if an ad is visible
      luaState.pushBoolean(Chartboost.isAnyViewVisible());

      return 1;
    }
  }

  // [Lua] chartboost.show(adType [, namedLocation])
  public class Show implements NamedJavaFunction
  {
    /**
     * Gets the name of the Lua function as it would appear in the Lua script.
     * @return Returns the name of the custom Lua function.
     */
    @Override
    public String getName() {
      return "show";
    }

    /**
     * This method is called when the Lua function is called.
     * <p>
     * Warning! This method is not called on the main UI thread.
     * @param luaState Reference to the Lua state.
     *                 Needed to retrieve the Lua function's parameters and to return values back to Lua.
     * @return Returns the number of values to be returned by the Lua function.
     */
    @Override
    public int invoke( LuaState luaState )
    {
      functionSignature = "chartboost.show(adType [, namedLocation])";

      if (! isSDKInitialized()) {
        return 0;
      }

      // get number of arguments
      int nargs = luaState.getTop();
      if ((nargs < 1) || (nargs > 2)) {
        logMsg(ERROR_MSG, "Expected 1 or 2 arguments, got " + nargs);
        return 0;
      }

      String adType = null;
      String namedLocation = null;

      // Get the ad type
      if (luaState.type(1) == LuaType.STRING) {
        adType = luaState.toString(1);
      }
      else {
        logMsg(ERROR_MSG, "adType expected (string), got " + luaState.typeName(1));
        return 0;
      }

      // Get the named location
      if (! luaState.isNoneOrNil(2)) {
        if (luaState.type(2) == LuaType.STRING) {
          namedLocation = luaState.toString(2);
        }
        else {
          logMsg(ERROR_MSG, "namedLocation expected (string), got " + luaState.typeName(2));
          return 0;
        }
      }

      if (! validAdTypes.contains(adType)){
        logMsg(ERROR_MSG, "invalid adType '"+ adType + "'");
        return 0;
      }

      boolean isLoaded = false;
      String location = (namedLocation != null) ? namedLocation : CBLocation.LOCATION_DEFAULT;

      if (adType.equals(TYPE_REWARDED_VIDEO)) {
        isLoaded = Chartboost.hasRewardedVideo(location);
      }
      else if (adType.equals(TYPE_INTERSTITIAL)) {
        isLoaded = Chartboost.hasInterstitial(location);
      }
      else {
        logMsg(ERROR_MSG, "Invalid ad type '" + adType + "'");
      }

      // can't show unless ad is loaded
      if (! isLoaded) {
        logMsg(ERROR_MSG, "adType '" + adType + "' not loaded");
        return 0;
      }

      // declare final variables for inner loop
      final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
      final String fAdType = adType;
      final String fNamedLocation = namedLocation;
      final String fLocation = location;

      // Run the activity on the uiThread
      if (coronaActivity != null) {
        // Create a new runnable object to invoke our activity
        Runnable runnableActivity = new Runnable() {
          public void run() {
            if (fAdType.equals(TYPE_REWARDED_VIDEO)) {
              Chartboost.showRewardedVideo(fLocation);
            }
            else if (fAdType.equals(TYPE_INTERSTITIAL)) {
              Chartboost.showInterstitial(fLocation);
            }
            else {
              logMsg(ERROR_MSG, "Invalid ad type '" + fAdType + "'");
            }
          }
        };

        coronaActivity.runOnUiThread(runnableActivity);
      }

      return 0;
    }
  }

  // [Lua] chartboost.hide()
  public class Hide implements NamedJavaFunction
  {
    /**
     * Gets the name of the Lua function as it would appear in the Lua script.
     * @return Returns the name of the custom Lua function.
     */
    @Override
    public String getName() {
      return "hide";
    }

    /**
     * This method is called when the Lua function is called.
     * <p>
     * Warning! This method is not called on the main UI thread.
     * @param luaState Reference to the Lua state.
     *                 Needed to retrieve the Lua function's parameters and to return values back to Lua.
     * @return Returns the number of values to be returned by the Lua function.
     */
    @Override
    public int invoke( LuaState luaState )  {
      functionSignature = "chartboost.hide()";

      if (! isSDKInitialized()) {
        return 0;
      }

      // get number of arguments
      int nargs = luaState.getTop();
      if (nargs != 0) {
        logMsg(ERROR_MSG, "Expected no arguments, got " + nargs);
        return 0;
      }

      final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();

      // Run the activity on the uiThread
      if (coronaActivity != null) {
        // Create a new runnable object to invoke our activity
        Runnable runnableActivity = new Runnable() {
          public void run() {
          }
        };

        coronaActivity.runOnUiThread(runnableActivity);
      }

      return 0;
    }
  }

  // [Lua] chartboost.onBackPressed()
  public class OnBackPressed implements NamedJavaFunction
  {
    /**
     * Gets the name of the Lua function as it would appear in the Lua script.
     * @return Returns the name of the custom Lua function.
     */
    @Override
    public String getName() {
      return "onBackPressed";
    }

    /**
     * This method is called when the Lua function is called.
     * <p>
     * Warning! This method is not called on the main UI thread.
     * @param luaState Reference to the Lua state.
     *                 Needed to retrieve the Lua function's parameters and to return values back to Lua.
     * @return Returns the number of values to be returned by the Lua function.
     */
    @Override
    public int invoke( LuaState luaState ) {
      functionSignature = "chartboost.onBackPressed()";

      if (! isSDKInitialized()) {
        return 0;
      }

      // get number of arguments
      int nargs = luaState.getTop();
      if (nargs != 0) {
        logMsg(ERROR_MSG, "Expected no arguments, got " + nargs);
        return 0;
      }

      // See if the back key has been pressed
      boolean result = Chartboost.onBackPressed();

      luaState.pushBoolean(result);

      return 1;
    }
  }

  // -------------------------------------------------------------------
  // Delegates
  // -------------------------------------------------------------------

  class CoronaChartboostDelegate extends ChartboostDelegate
  {
    @Override
    public void didInitialize()
    {
      // flag the SDK as ready for API calls
      chartboostObjects.put(SDK_READY_KEY, true);
      softBoot = true;

      // send Corona Lua event
      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(EVENT_PHASE_KEY, PHASE_INIT);
      dispatchLuaEvent(coronaEvent);
    }

    // Interstitials
    @Override
    public boolean shouldRequestInterstitial(String location)
    {
      return true;
    }

    @Override
    public boolean shouldDisplayInterstitial(String location)
    {
      // Called just before an ad is displayed. The Lua event must be sent here
      // otherwise the event does not fire until *after* the ad is closed

      // create data
      JSONObject data = new JSONObject();
      try {
        data.put(DATA_LOCATION_KEY, location);
      }
      catch (Exception e) {
        System.err.println();
      }

      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(EVENT_PHASE_KEY, PHASE_DISPLAYED);
      coronaEvent.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);
      coronaEvent.put(EVENT_DATA_KEY, data.toString());
      dispatchLuaEvent(coronaEvent);

      // we should always display an ad
      return true;
    }

    @Override
    public void didCacheInterstitial(String location)
    {
      // create data
      JSONObject data = new JSONObject();
      try {
        data.put(DATA_LOCATION_KEY, location);
      }
      catch (Exception e) {
        System.err.println();
      }

      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(EVENT_PHASE_KEY, PHASE_LOADED);
      coronaEvent.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);
      coronaEvent.put(EVENT_DATA_KEY, data.toString());
      dispatchLuaEvent(coronaEvent);
    }

    @Override
    public void didFailToLoadInterstitial(String location, CBError.CBImpressionError error) {
      // create data
      JSONObject data = new JSONObject();
      try {
        data.put(DATA_LOCATION_KEY, location);
        data.put(DATA_ERRORMSG_KEY, error.name());
        data.put(DATA_ERRORCODE_KEY, error.ordinal());
      }
      catch (Exception e) {
        System.err.println();
      }

      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(EVENT_PHASE_KEY, PHASE_FAILED);
      coronaEvent.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);
      coronaEvent.put(CoronaLuaEvent.RESPONSE_KEY, RESPONSE_LOAD_FAILED);
      coronaEvent.put(EVENT_DATA_KEY, data.toString());
      coronaEvent.put(CoronaLuaEvent.ISERROR_KEY, true);
      dispatchLuaEvent(coronaEvent);
    }

    @Override
    public void didDismissInterstitial(String location) {
      // No need to use. Called on Close/Click
    }

    @Override
    public void didCloseInterstitial(String location) {
      // create data
      JSONObject data = new JSONObject();
      try {
        data.put(DATA_LOCATION_KEY, location);
      }
      catch (Exception e) {
        System.err.println();
      }

      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(EVENT_PHASE_KEY, PHASE_CLOSED);
      coronaEvent.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);
      coronaEvent.put(EVENT_DATA_KEY, data.toString());
      dispatchLuaEvent(coronaEvent);
    }

    @Override
    public void didClickInterstitial(String location) {
      // create data
      JSONObject data = new JSONObject();
      try {
        data.put(DATA_LOCATION_KEY, location);
      }
      catch (Exception e) {
        System.err.println();
      }

      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(EVENT_PHASE_KEY, PHASE_CLICKED);
      coronaEvent.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);
      coronaEvent.put(EVENT_DATA_KEY, data.toString());
      dispatchLuaEvent(coronaEvent);
    }

    @Override
    public void didDisplayInterstitial(String location) {
      // event sent in shouldDisplayInterstitial()
    }

    // Rewarded Video
    @Override
    public boolean shouldDisplayRewardedVideo(String location) {
      // Called just before an ad is displayed. The Lua event must be sent here
      // otherwise the event does not fire until *after* the ad is closed

      // create data
      JSONObject data = new JSONObject();
      try {
        data.put(DATA_LOCATION_KEY, location);
      }
      catch (Exception e) {
        System.err.println();
      }

      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(EVENT_PHASE_KEY, PHASE_DISPLAYED);
      coronaEvent.put(EVENT_TYPE_KEY, TYPE_REWARDED_VIDEO);
      coronaEvent.put(EVENT_DATA_KEY, data.toString());
      dispatchLuaEvent(coronaEvent);

      // We should always display ad ad
      return true;
    }

    @Override
    public void didCacheRewardedVideo(String location) {
      // create data
      JSONObject data = new JSONObject();
      try {
        data.put(DATA_LOCATION_KEY, location);
      }
      catch (Exception e) {
        System.err.println();
      }

      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(EVENT_PHASE_KEY, PHASE_LOADED);
      coronaEvent.put(EVENT_TYPE_KEY, TYPE_REWARDED_VIDEO);
      coronaEvent.put(EVENT_DATA_KEY, data.toString());
      dispatchLuaEvent(coronaEvent);
    }

    @Override
    public void didFailToLoadRewardedVideo(String location, CBError.CBImpressionError error) {
      // create data
      JSONObject data = new JSONObject();
      try {
        data.put(DATA_LOCATION_KEY, location);
        data.put(DATA_ERRORMSG_KEY, error.name());
        data.put(DATA_ERRORCODE_KEY, error.ordinal());
      }
      catch (Exception e) {
        System.err.println();
      }

      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(EVENT_PHASE_KEY, PHASE_FAILED);
      coronaEvent.put(EVENT_TYPE_KEY, TYPE_REWARDED_VIDEO);
      coronaEvent.put(CoronaLuaEvent.RESPONSE_KEY, RESPONSE_LOAD_FAILED);
      coronaEvent.put(EVENT_DATA_KEY, data.toString());
      coronaEvent.put(CoronaLuaEvent.ISERROR_KEY, true);
      dispatchLuaEvent(coronaEvent);
    }

    @Override
    public void didDismissRewardedVideo( String location ) {
      // No need to use. Called on Close/Click
    }

    @Override
    public void didCloseRewardedVideo( String location ) {
      // create data
      JSONObject data = new JSONObject();
      try {
        data.put(DATA_LOCATION_KEY, location);
      }
      catch (Exception e) {
        System.err.println();
      }

      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(EVENT_PHASE_KEY, PHASE_CLOSED);
      coronaEvent.put(EVENT_TYPE_KEY, TYPE_REWARDED_VIDEO);
      coronaEvent.put(EVENT_DATA_KEY, data.toString());
      dispatchLuaEvent(coronaEvent);
    }

    @Override
    public void didClickRewardedVideo(String location) {
      // create data
      JSONObject data = new JSONObject();
      try {
        data.put(DATA_LOCATION_KEY, location);
      }
      catch (Exception e) {
        System.err.println();
      }

      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(EVENT_PHASE_KEY, PHASE_CLICKED);
      coronaEvent.put(EVENT_TYPE_KEY, TYPE_REWARDED_VIDEO);
      coronaEvent.put(EVENT_DATA_KEY, data.toString());
      dispatchLuaEvent(coronaEvent);
    }

    @Override
    public void didDisplayRewardedVideo( String location ) {
      // event sent in shouldDisplayRewardedVideo()
    }

    @Override
    public void didCompleteRewardedVideo(String location, int reward) {
      // create data
      JSONObject data = new JSONObject();
      try {
        data.put(DATA_LOCATION_KEY, location);
        data.put(DATA_REWARD_KEY, reward);
      }
      catch (Exception e) {
        System.err.println();
      }

      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(EVENT_PHASE_KEY, PHASE_REWARD);
      coronaEvent.put(EVENT_TYPE_KEY, TYPE_REWARDED_VIDEO);
      coronaEvent.put(EVENT_DATA_KEY, data.toString());
      dispatchLuaEvent(coronaEvent);
    }
  }
}
