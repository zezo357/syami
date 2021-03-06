import 'dart:io';
import 'dart:ui';

import 'package:catcher/catcher.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:dio/adapter.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:dio/dio.dart' as dio;
import 'package:path_provider/path_provider.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:syami/constants/String%20constants.dart';
import 'package:syami/controller/classes.dart';
import 'package:syami/controller/locator.dart';
import 'package:version/version.dart';
import 'package:window_manager/window_manager.dart';
import 'package:geocoding/geocoding.dart';

class SearchEngine extends GetxController {
  /*late Catcher catcher;

  SearchEngine(Catcher catcher2) {
    catcher = catcher2;
  }

   */

  String serverUrlApi = "http://api.aladhan.com/v1/";
  String appVersion = "1.0.8";
  List<UpdateVersion> releaseNotes = [];

  RxString loadingState = "".obs;
  RxBool appLoaded = false.obs;
  RxBool loadingFailed = false.obs;
  RxString city = "".obs;
  RxString country = "".obs;
  RefreshController listRefresher = RefreshController(initialRefresh: false);

  dio.CancelToken token = dio.CancelToken();
  late dio.Dio dioInter;

  Version? latestVersion;
  RxList<DayPrayer> userPrayer = RxList<DayPrayer>();
  RxList<DayPrayer> meccaPrayer = RxList<DayPrayer>();
  int monthLoaded = 0;
  int yearLoaded = 0;
  Position meccaPosition = const Position(
      speedAccuracy: 0,
      heading: 0,
      longitude: 39.826168,
      speed: 0,
      altitude: 0,
      latitude: 21.422510,
      timestamp: null,
      accuracy: 0);
  Position? userPosition;
  @override
  void dispose() {
    //  flutterWebviewPlugin.dispose();
    // _onStateChanged.cancel();
    super.dispose();
  }

  @override
  Future<void> onReady() async {
    //Size windowSize = await windowManager.getSize();
    if (GetPlatform.isWindows) {
      await windowManager.ensureInitialized();
      await windowManager.setMinimumSize(const Size(600, 600));
      //windowManager.getSize().asStream().listen((event) {
      //print(event);
      //});
    }

    await initScreenUtil();

    //setCatcherLogsPath();

    dioInter = dio.Dio();
    (dioInter.httpClientAdapter as DefaultHttpClientAdapter)
        .onHttpClientCreate = (HttpClient client) {
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      return client;
    };
    dioInter.options.connectTimeout = 5 * 1000;
    dioInter.interceptors.add(RetryInterceptor(
      dio: dioInter,
      logPrint: print,
      // specify log function (optional)
      onRetry: (e) {
        loadingState.value = StringConstants.loadingLinkError;
      },
      retries: 3,
      // retry count (optional)
      retryDelays: const [
        // set delays between retries (optional)
        Duration(seconds: 1), // wait 1 sec before first retry
        Duration(seconds: 2), // wait 2 sec before second retry
        Duration(seconds: 3), // wait 3 sec before third retry
      ],
    ));
    appLoaded.value = true;
    await getPrayerTimes(month: monthLoaded);

    //update();
    //afterLoading();
  }

  Future<void> getLocation() async {
    loadingState.value = "Getting Location";
    Map<String, String> location =
        await getCityFromPosition(await determinePosition());
    print(location);
    await getApiForLocation(location["city"]!, location["country"]!);
    print("###########################");
  }

//https://api.aladhan.com/v1/calendar?latitude=51.508515&longitude=-0.1254872
  Future<void> getApiForLocation(String city, String country) async {
    loadingState.value = "Getting Prayer Times";
    List<dynamic>? jsonResponse = [];
    String urlDone =
        serverUrlApi + "calendarByCity?city=$city&country=$country";
    dio.Response response = await loadLink(urlDone);
    //print(response.data);
    if (response.statusCode == 200) {
      //print(response.data);
      jsonResponse = response.data["data"];

      //print(jsonResponse);
    }
  }

  Future<dynamic> getApiForPosition(Position pos, int month, int year) async {
    List<dynamic>? jsonResponse = [];
    String urlDone = serverUrlApi +
        "calendar?latitude=${pos.latitude}&longitude=${pos.longitude}&month=$month&year=$year";
    dio.Response response = await loadLink(urlDone);
    //print(response.data);
    if (response.statusCode == 200) {
      //print(response.data);
      jsonResponse = response.data["data"];
      return jsonResponse;
      //print(jsonResponse);
    }
  }

  Future<dio.Response> loadLink(
    String? url, {
    Map<String, String>? param,
    Map<String, String>? headers,
  }) async {
    try {
      /*
    dio.BaseOptions(

        headers: headers,
        connectTimeout: 5000,
        followRedirects: true,
        receiveDataWhenStatusError: true,*/
      return await dioInter.get(url!,
          queryParameters: param,
          options: dio.Options(
            headers: headers,
            followRedirects: true,
            receiveDataWhenStatusError: true,
          ));
    } catch (_) {
      print("loadLink " + _.toString());
      if (_ is dio.DioError) {
        return _.response ??
            dio.Response(
                requestOptions: dio.RequestOptions(path: ''), statusCode: 1);
      } else {
        return dio.Response(
            requestOptions: dio.RequestOptions(path: ''), statusCode: 1);
      }
      //final response= dio.Response(requestOptions: null);
      //response.statusCode=987654;
      //return _;
    }
  }

  Future<void> getUserLocation({bool getNewLocation = false}) async {
    loadingState.value = "Getting your location";
    userPosition = await determinePosition(getNew: getNewLocation);
    Map<String, String> location = await getCityFromPosition(userPosition!);
    print(location);
    city.value = location["city"] ?? "Unknown";
    country.value = location["country"] ?? "Unknown";
  }

  Future<void> getPrayerTimes(
      {int month = 0, bool getNewLocation = false}) async {
    DateTime nowTime = (DateTime.now());
    int todayDay = nowTime.day;
    int todayMonth = nowTime.month;
    int todayYear = nowTime.year;
    int monthToGetTimesOn = 0;
    int yearToGetTimesOn = 0;
    if (yearLoaded == 0) {
      yearToGetTimesOn = todayYear;
      yearLoaded = todayYear;
    }
    if (month == 0) {
      monthToGetTimesOn = todayMonth;
    } else {
      if (month > 12) {
        monthToGetTimesOn = 1;
        yearToGetTimesOn = yearLoaded + 1;
      } else {
        monthToGetTimesOn = month;
      }
    }
    if (getNewLocation) {
      userPrayer.clear();
      meccaPrayer.clear();
    }
    if (userPosition == null || getNewLocation) {
      await getUserLocation(getNewLocation: getNewLocation);
    }

    loadingState.value = "Getting prayer times for " +
        (city.value == "Unknown" || city.value == ""
            ? country.value
            : city.value);

    var userPrayerTimes = await getApiForPosition(
        userPosition!, monthToGetTimesOn, yearToGetTimesOn);
    var meccaPrayerTimes = await getApiForPosition(
        meccaPosition, monthToGetTimesOn, yearToGetTimesOn);
    for (int i = 0; i < userPrayerTimes.length; i++) {
      DayPrayer dayPrayer = DayPrayer(
        userPrayerTimes[i]["date"]["gregorian"]["date"],
        userPrayerTimes[i]["date"]["gregorian"]["format"],
        userPrayerTimes[i]["date"]["gregorian"]["weekday"]["en"],
        userPrayerTimes[i]["timings"]["Fajr"],
        userPrayerTimes[i]["timings"]["Dhuhr"],
        userPrayerTimes[i]["timings"]["Asr"],
        userPrayerTimes[i]["timings"]["Maghrib"],
        userPrayerTimes[i]["timings"]["Isha"],
      );
      //print();
      if (dayPrayer.date.month == todayMonth) {
        if (dayPrayer.date.day >= todayDay) {
          userPrayer.add(dayPrayer);
        }
      } else {
        userPrayer.add(dayPrayer);
      }
    }

    //loadingState.value = "Getting Prayer Times for mecca";

    for (int i = 0; i < meccaPrayerTimes.length; i++) {
      DayPrayer dayPrayer = DayPrayer(
        meccaPrayerTimes[i]["date"]["gregorian"]["date"],
        meccaPrayerTimes[i]["date"]["gregorian"]["format"],
        meccaPrayerTimes[i]["date"]["gregorian"]["weekday"]["en"],
        meccaPrayerTimes[i]["timings"]["Fajr"],
        meccaPrayerTimes[i]["timings"]["Dhuhr"],
        meccaPrayerTimes[i]["timings"]["Asr"],
        meccaPrayerTimes[i]["timings"]["Maghrib"],
        meccaPrayerTimes[i]["timings"]["Isha"],
      );
      //print();
      if (dayPrayer.date.month == todayMonth) {
        if (dayPrayer.date.day >= todayDay) {
          meccaPrayer.add(dayPrayer);
        }
      } else {
        meccaPrayer.add(dayPrayer);
      }
    }
    print("meccaPrayerTimes" + meccaPrayerTimes.toString());

    yearLoaded = yearToGetTimesOn;
    monthLoaded = monthToGetTimesOn;
    if (meccaPrayer[0].date != userPrayer[0].date) {
      print("DATES ARE NOT ALIGNED");
    }
    //update();
    print("userPrayerTimes" + userPrayerTimes.toString());

    if (userPrayer.length < 5) {
      await getPrayerTimes(month: monthLoaded + 1);
    }
  }

  Future<void> loadMoreMonth() async {
    await getPrayerTimes(month: monthLoaded + 1);
    listRefresher.loadComplete();
  }
/*
  setCatcherLogsPath() async {
    CatcherOptions debugOptions = CatcherOptions(SilentReportMode(), [
      FileHandler(
          File(
              join((await getApplicationDocumentsDirectory()).path, "log.txt")),
          printLogs: true),
      ConsoleHandler(
          enableApplicationParameters: true,
          enableDeviceParameters: true,
          enableCustomParameters: true,
          enableStackTrace: true,
          handleWhenRejected: false)
    ]);
    CatcherOptions releaseOptions = CatcherOptions(SilentReportMode(), [
      FileHandler(File(
          join((await getApplicationDocumentsDirectory()).path, "log.txt"))),
      ConsoleHandler(
          enableApplicationParameters: false,
          enableDeviceParameters: false,
          enableCustomParameters: false,
          enableStackTrace: true,
          handleWhenRejected: false)
    ]);
    catcher.updateConfig(debugConfig: debugOptions, releaseConfig: releaseOptions);
  }*/

  Version jsonToVersion(String? response) {
    //print(response);
    return (Version.parse(response));
  }

  Future<void> initScreenUtil() async {
    double? width;
    double? height;
    //print("width:${Get.width} ,,, height:${Get.height} ");

    if (MediaQuery.of(Get.context!).orientation == Orientation.portrait ||
        Platform.isWindows) {
      height = Get.height;
      width = Get.width;
    } else {
      height = Get.width;
      width = Get.height;
    }
    ScreenUtil.init(
        /*
        BoxConstraints(
            maxWidth: width, //new width
            maxHeight: height //new height
            ),

       */
        Get.context!,
        designSize: Size(411.42857142857144, 683.4285714285714),
        orientation: Orientation.portrait,
        minTextAdapt: true);
    update();
  }
}
