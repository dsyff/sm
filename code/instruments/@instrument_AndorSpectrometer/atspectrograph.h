#ifndef atspectrographH
#define atspectrographH

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__linux__)  || defined(__APPLE__)
  #define WINAPI
  #define DLL_DEF
#else
  #include <windows.h>
	#if defined (EXPORT_SPECTROGRAPH_INTERFACE)
		#define DLL_DEF __declspec(dllexport)
	#elif defined (_BUILDMICRODLL)
		#ifndef DLL_DEF
			#define DLL_DEF  __declspec(dllimport)
		#endif
	#else
		#define DLL_DEF __declspec(dllimport)
	#endif

#endif


/// <summary>The possible error codes returned by the ATSpectrograph SDK functions are the following:</summary>
typedef enum eATSpectrographReturnCodes {
    /// <summary>A general communication error occurred. Retry the command, if the problem persists check the connection to the spectrograph.</summary>
    /// <typeparam name="eATSpectrographReturnCodes"/>
    ATSPECTROGRAPH_COMMUNICATION_ERROR = 20201,
    /// <summary>The command succeeded.</summary>
    /// <typeparam name="eATSpectrographReturnCodes"/>
    ATSPECTROGRAPH_SUCCESS = 20202,
    /// <summary>The command failed.</summary>
    /// <typeparam name="eATSpectrographReturnCodes"/>
    ATSPECTROGRAPH_ERROR = 20249,
    /// <summary>The first parameter was out of range.</summary>
    /// <typeparam name="eATSpectrographReturnCodes"/>
    ATSPECTROGRAPH_P1INVALID = 20266,
    /// <summary>The second parameter was out of range.</summary>
    /// <typeparam name="eATSpectrographReturnCodes"/>
    ATSPECTROGRAPH_P2INVALID = 20267,
    /// <summary>The third parameter was out of range.</summary>
    /// <typeparam name="eATSpectrographReturnCodes"/>
    ATSPECTROGRAPH_P3INVALID = 20268,
    /// <summary>The fourth parameter was out of range.</summary>
    /// <typeparam name="eATSpectrographReturnCodes"/>
    ATSPECTROGRAPH_P4INVALID = 20269,
    /// <summary>The fifth parameter was out of range.</summary>
    /// <typeparam name="eATSpectrographReturnCodes"/>
    ATSPECTROGRAPH_P5INVALID = 20270,
    /// <summary>The requested spectrograph was not initialized.</summary>
    /// <typeparam name="eATSpectrographReturnCodes"/>
    ATSPECTROGRAPH_NOT_INITIALIZED = 20275,
	/// <summary>The requested speectrograph was not available.</summary>
    /// <typeparam name="eATSpectrographReturnCodes"/>
    ATSPECTROGRAPH_NOT_AVAILABLE = 20292,
}eATSpectrographReturnCodes;

/// <summary>This indicates which port flipper mirror to talk to.</summary>
typedef enum eATSpectrographFlipper {
    /// <summary>The input flipper mirror.</summary>
    /// <typeparam name="eATSpectrographFlipper"/>
    INPUT_FLIPPER = 1,
    /// <summary>The output flipper mirror.</summary>
    /// <typeparam name="eATSpectrographFlipper"/>
    OUTPUT_FLIPPER = 2,
}eATSpectrographFlipper;

/// <summary>This indicates a position for a port (input or output).</summary>
typedef enum eATSpectrographPortPosition {
    /// <summary>The DIRECT input or output.</summary>
    /// <typeparam name="eATSpectrographPortPosition"/>
    DIRECT = 0,
    /// <summary>The SIDE input or output.</summary>
    /// <typeparam name="eATSpectrographPortPosition"/>
    SIDE = 1,
}eATSpectrographPortPosition;

/// <summary>This indicates a slit position.</summary>
typedef enum eATSpectrographSlitIndex {
    /// <summary>The side input slit.</summary>
    /// <typeparam name="eATSpectrographSlitIndex"/>
    INPUT_SIDE = 1,
    /// <summary>The direct input slit.</summary>
    /// <typeparam name="eATSpectrographSlitIndex"/>
    INPUT_DIRECT = 2,
    /// <summary>The side output slit.</summary>
    /// <typeparam name="eATSpectrographSlitIndex"/>
    OUTPUT_SIDE = 3,
    /// <summary>The direct output slit.</summary>
    /// <typeparam name="eATSpectrographSlitIndex"/>
    OUTPUT_DIRECT = 4
}eATSpectrographSlitIndex;

/// <summary>This indicates the mode of the shutter.</summary>
typedef enum eATSpectrographShutterMode {
    /// <summary>The shutter is open always.</summary>
    /// <typeparam name="eATSpectrographShutterMode"/>
    SHUTTER_CLOSED = 0,
    /// <summary>The shutter is closed always.</summary>
    /// <typeparam name="eATSpectrographShutterMode"/>
    SHUTTER_OPEN = 1,
    /// <summary>The shutter will open when a TTL high is present on the external shutter BNC connected. Note this does not apply to the SR-303 as it has no external shutter BNC connector.</summary>
    /// <typeparam name="eATSpectrographShutterMode"/>
    SHUTTER_BNC = 2,
}eATSpectrographShutterMode;

#define ATSPECTROGRAPH_ERRORLENGTH 64

DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographInitialize(const char *iniPath);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographClose();
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetNumberDevices(int *noDevices);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetFunctionReturnDescription(eATSpectrographReturnCodes error, char *description, int maxDescStrLen);

DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetSerialNumber(int device, char *serial, int maxSerialStrLen);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographEepromSetOpticalParams(int device, float focalLength, float angularDeviation, float focalTilt);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographEepromGetOpticalParams(int device, float *focalLength, float *angularDeviation, float *focalTilt);

DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetNumberGratings(int device, int *noGratings);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetGrating(int device, int grating);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetGrating(int device, int *grating);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetGratingInfo(int device, int grating, float *lines, char* blaze, int maxBlazeStrLen, int *home, int *offset);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGratingIsPresent(int device, int *present);

DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetDetectorOffset(int device, eATSpectrographPortPosition entrancePort, eATSpectrographPortPosition exitPort, int offset);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetDetectorOffset(int device, eATSpectrographPortPosition entrancePort, eATSpectrographPortPosition exitPort, int *offset);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetGratingOffset(int device, int grating, int offset);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetGratingOffset(int device, int grating, int *offset);

DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetTurret(int device, int turret);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetTurret(int device, int *turret);

DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographWavelengthIsPresent(int device, int *present);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographWavelengthReset(int device);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetWavelength(int device, float wavelength);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetWavelength(int device, float *wavelength);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGotoZeroOrder(int device);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographAtZeroOrder(int device, int *atZeroOrder);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetWavelengthLimits(int device, int grating, float *min, float *max);

DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSlitIsPresent(int device, eATSpectrographSlitIndex slit, int *present);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSlitReset(int device, eATSpectrographSlitIndex slit);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetSlitWidth(int device, eATSpectrographSlitIndex slit, float width);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetSlitWidth(int device, eATSpectrographSlitIndex slit, float *width);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetSlitZeroPosition(int device, eATSpectrographSlitIndex slit, int offset);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetSlitZeroPosition(int device, eATSpectrographSlitIndex slit, int *offset);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetSlitCoefficients(int device, int x1, int y1, int x2, int y2);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetSlitCoefficients(int device, int *x1, int *y1, int *x2, int *y2);

DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographShutterIsPresent(int device, int *present);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographIsShutterModePossible(int device, eATSpectrographShutterMode mode, int *possible);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetShutter(int device, eATSpectrographShutterMode mode);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetShutter(int device, eATSpectrographShutterMode *mode);

DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographFilterIsPresent(int device, int *present);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographFilterReset(int device);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetFilter(int device, int filter);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetFilter(int device, int *filter);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetFilterInfo(int device, int Filter, char* info, int maxInfoLen);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetFilterInfo(int device, int Filter, char* info);

DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographFlipperMirrorIsPresent(int device, eATSpectrographFlipper flipper, int *present);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographFlipperMirrorReset(int device, eATSpectrographFlipper flipper);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetFlipperMirror(int device, eATSpectrographFlipper flipper, eATSpectrographPortPosition port);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetFlipperMirror(int device, eATSpectrographFlipper flipper, eATSpectrographPortPosition *port);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetFlipperMirrorPosition(int device, eATSpectrographFlipper flipper, int position);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetFlipperMirrorPosition(int device, eATSpectrographFlipper flipper, int *position);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetFlipperMirrorMaxPosition(int device, eATSpectrographFlipper flipper, int *maxPosition);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetCCDLimits(int device, eATSpectrographPortPosition port, float *low, float *high);

DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographAccessoryIsPresent(int device, int *present);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetAccessoryState(int device, int accessory, int state);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetAccessoryState(int device, int accessory, int *state);

DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographFocusMirrorIsPresent(int device, int *present);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographFocusMirrorReset(int device);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetFocusMirror(int device, int focus);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetFocusMirror(int device, int *focus);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetFocusMirrorMaxSteps(int device, int *steps);

DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetPixelWidth(int device, float width);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetPixelWidth(int device, float* width);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetNumberPixels(int device, int numberPixels);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetNumberPixels(int device, int* numberPixels);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetCalibration(int device, float* calibrationValues, int numberPixels);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetPixelCalibrationCoefficients(int device, float* A, float* B, float* C, float* D);

DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographIrisIsPresent(int device, eATSpectrographPortPosition iris, int *present);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographSetIris(int device, eATSpectrographPortPosition iris, int value);
DLL_DEF eATSpectrographReturnCodes WINAPI ATSpectrographGetIris(int device, eATSpectrographPortPosition iris, int *value);

#ifdef __cplusplus
}
#endif

#endif
