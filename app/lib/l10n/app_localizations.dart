import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('zh')];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'Look Studio'**
  String get appTitle;

  /// No description provided for @levelStandard.
  ///
  /// In zh, this message translates to:
  /// **'标准'**
  String get levelStandard;

  /// No description provided for @levelMedium.
  ///
  /// In zh, this message translates to:
  /// **'中'**
  String get levelMedium;

  /// No description provided for @levelHigh.
  ///
  /// In zh, this message translates to:
  /// **'高'**
  String get levelHigh;

  /// No description provided for @colorAzure.
  ///
  /// In zh, this message translates to:
  /// **'湛蓝'**
  String get colorAzure;

  /// No description provided for @colorIndigo.
  ///
  /// In zh, this message translates to:
  /// **'黛青'**
  String get colorIndigo;

  /// No description provided for @colorPine.
  ///
  /// In zh, this message translates to:
  /// **'松绿'**
  String get colorPine;

  /// No description provided for @colorAmber.
  ///
  /// In zh, this message translates to:
  /// **'琥珀'**
  String get colorAmber;

  /// No description provided for @colorCinnabar.
  ///
  /// In zh, this message translates to:
  /// **'朱砂'**
  String get colorCinnabar;

  /// No description provided for @colorBegonia.
  ///
  /// In zh, this message translates to:
  /// **'海棠'**
  String get colorBegonia;

  /// No description provided for @colorWisteria.
  ///
  /// In zh, this message translates to:
  /// **'藤紫'**
  String get colorWisteria;

  /// No description provided for @colorGraphite.
  ///
  /// In zh, this message translates to:
  /// **'石墨'**
  String get colorGraphite;

  /// No description provided for @schemeTonalSpot.
  ///
  /// In zh, this message translates to:
  /// **'柔和'**
  String get schemeTonalSpot;

  /// No description provided for @schemeNeutral.
  ///
  /// In zh, this message translates to:
  /// **'中性'**
  String get schemeNeutral;

  /// No description provided for @schemeVibrant.
  ///
  /// In zh, this message translates to:
  /// **'鲜明'**
  String get schemeVibrant;

  /// No description provided for @schemeExpressive.
  ///
  /// In zh, this message translates to:
  /// **'表现'**
  String get schemeExpressive;

  /// No description provided for @schemeFidelity.
  ///
  /// In zh, this message translates to:
  /// **'忠实'**
  String get schemeFidelity;

  /// No description provided for @schemeContent.
  ///
  /// In zh, this message translates to:
  /// **'内容'**
  String get schemeContent;

  /// No description provided for @schemeMonochrome.
  ///
  /// In zh, this message translates to:
  /// **'单色'**
  String get schemeMonochrome;

  /// No description provided for @fontSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统默认'**
  String get fontSystem;

  /// No description provided for @fontHarmonySans.
  ///
  /// In zh, this message translates to:
  /// **'鸿蒙黑体'**
  String get fontHarmonySans;

  /// No description provided for @fontSourceHanSans.
  ///
  /// In zh, this message translates to:
  /// **'思源黑体'**
  String get fontSourceHanSans;

  /// No description provided for @fontLxgwWenKai.
  ///
  /// In zh, this message translates to:
  /// **'霞鹜文楷'**
  String get fontLxgwWenKai;

  /// No description provided for @fontInterWithSystem.
  ///
  /// In zh, this message translates to:
  /// **'Inter + 系统中文'**
  String get fontInterWithSystem;

  /// No description provided for @durationHoursMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{h} 小时 {m} 分'**
  String durationHoursMinutes(Object h, Object m);

  /// No description provided for @durationHours.
  ///
  /// In zh, this message translates to:
  /// **'{h} 小时'**
  String durationHours(Object h);

  /// No description provided for @durationMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{m} 分钟'**
  String durationMinutes(Object m);

  /// No description provided for @weekdayShort1.
  ///
  /// In zh, this message translates to:
  /// **'一'**
  String get weekdayShort1;

  /// No description provided for @weekdayShort2.
  ///
  /// In zh, this message translates to:
  /// **'二'**
  String get weekdayShort2;

  /// No description provided for @weekdayShort3.
  ///
  /// In zh, this message translates to:
  /// **'三'**
  String get weekdayShort3;

  /// No description provided for @weekdayShort4.
  ///
  /// In zh, this message translates to:
  /// **'四'**
  String get weekdayShort4;

  /// No description provided for @weekdayShort5.
  ///
  /// In zh, this message translates to:
  /// **'五'**
  String get weekdayShort5;

  /// No description provided for @weekdayShort6.
  ///
  /// In zh, this message translates to:
  /// **'六'**
  String get weekdayShort6;

  /// No description provided for @weekdayShort7.
  ///
  /// In zh, this message translates to:
  /// **'日'**
  String get weekdayShort7;

  /// No description provided for @timeToday.
  ///
  /// In zh, this message translates to:
  /// **'今天 {hm}'**
  String timeToday(Object hm);

  /// No description provided for @timeYesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天 {hm}'**
  String timeYesterday(Object hm);

  /// No description provided for @timeTomorrow.
  ///
  /// In zh, this message translates to:
  /// **'明天 {hm}'**
  String timeTomorrow(Object hm);

  /// No description provided for @weekdayName.
  ///
  /// In zh, this message translates to:
  /// **'周{value}'**
  String weekdayName(Object value);

  /// No description provided for @dateMonthDayWeekday.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日 {wd}'**
  String dateMonthDayWeekday(Object month, Object day, Object wd);

  /// No description provided for @dateYearMonthDay.
  ///
  /// In zh, this message translates to:
  /// **'{year}年{month}月{day}日'**
  String dateYearMonthDay(Object year, Object month, Object day);

  /// No description provided for @timeJustNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In zh, this message translates to:
  /// **'{inMinutes} 分钟前'**
  String timeMinutesAgo(Object inMinutes);

  /// No description provided for @timeHoursAgo.
  ///
  /// In zh, this message translates to:
  /// **'{inHours} 小时前'**
  String timeHoursAgo(Object inHours);

  /// No description provided for @timeDaysAgo.
  ///
  /// In zh, this message translates to:
  /// **'{inDays} 天前'**
  String timeDaysAgo(Object inDays);

  /// No description provided for @dateMonthDay.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日'**
  String dateMonthDay(Object month, Object day);

  /// No description provided for @timeExpired.
  ///
  /// In zh, this message translates to:
  /// **'已过期'**
  String get timeExpired;

  /// No description provided for @durationDaysHours.
  ///
  /// In zh, this message translates to:
  /// **'{inDays} 天 {value} 小时'**
  String durationDaysHours(Object inDays, Object value);

  /// No description provided for @durationHoursMinutesShort.
  ///
  /// In zh, this message translates to:
  /// **'{inHours} 小时 {value} 分'**
  String durationHoursMinutesShort(Object inHours, Object value);

  /// No description provided for @durationMinutesLong.
  ///
  /// In zh, this message translates to:
  /// **'{inMinutes} 分钟'**
  String durationMinutesLong(Object inMinutes);

  /// No description provided for @assetVideo.
  ///
  /// In zh, this message translates to:
  /// **'视频'**
  String get assetVideo;

  /// No description provided for @assetCourseware.
  ///
  /// In zh, this message translates to:
  /// **'课件'**
  String get assetCourseware;

  /// No description provided for @assetTranscript.
  ///
  /// In zh, this message translates to:
  /// **'转写'**
  String get assetTranscript;

  /// No description provided for @assetAudio.
  ///
  /// In zh, this message translates to:
  /// **'音频'**
  String get assetAudio;

  /// No description provided for @assetParse.
  ///
  /// In zh, this message translates to:
  /// **'课件解析'**
  String get assetParse;

  /// No description provided for @dateMonthDayWeek.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日 周{value}'**
  String dateMonthDayWeek(Object month, Object day, Object value);

  /// No description provided for @screenHome.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get screenHome;

  /// No description provided for @termAutumn.
  ///
  /// In zh, this message translates to:
  /// **'{y} 秋'**
  String termAutumn(Object y);

  /// No description provided for @termSpring.
  ///
  /// In zh, this message translates to:
  /// **'{value} 春'**
  String termSpring(Object value);

  /// No description provided for @avatarShapeCircle.
  ///
  /// In zh, this message translates to:
  /// **'圆形'**
  String get avatarShapeCircle;

  /// No description provided for @avatarShapeSquircle.
  ///
  /// In zh, this message translates to:
  /// **'圆角方'**
  String get avatarShapeSquircle;

  /// No description provided for @avatarShapeCookie.
  ///
  /// In zh, this message translates to:
  /// **'曲奇'**
  String get avatarShapeCookie;

  /// No description provided for @avatarShapePetal.
  ///
  /// In zh, this message translates to:
  /// **'花瓣'**
  String get avatarShapePetal;

  /// No description provided for @pluginContextLine.
  ///
  /// In zh, this message translates to:
  /// **'{value}：{value2}'**
  String pluginContextLine(Object value, Object value2);

  /// No description provided for @commonNotes.
  ///
  /// In zh, this message translates to:
  /// **'笔记'**
  String get commonNotes;

  /// No description provided for @pluginCategoryVisualize.
  ///
  /// In zh, this message translates to:
  /// **'可视化'**
  String get pluginCategoryVisualize;

  /// No description provided for @pluginCategoryReview.
  ///
  /// In zh, this message translates to:
  /// **'复习'**
  String get pluginCategoryReview;

  /// No description provided for @pluginCategoryProgramming.
  ///
  /// In zh, this message translates to:
  /// **'编程'**
  String get pluginCategoryProgramming;

  /// No description provided for @pluginCategoryConnector.
  ///
  /// In zh, this message translates to:
  /// **'连接器'**
  String get pluginCategoryConnector;

  /// No description provided for @pluginCategoryTutor.
  ///
  /// In zh, this message translates to:
  /// **'学习方式'**
  String get pluginCategoryTutor;

  /// No description provided for @commonAssignments.
  ///
  /// In zh, this message translates to:
  /// **'作业'**
  String get commonAssignments;

  /// No description provided for @backgroundJobs.
  ///
  /// In zh, this message translates to:
  /// **'正在处理 {active} 个下载或转写任务'**
  String backgroundJobs(Object active);

  /// No description provided for @backgroundSyncing.
  ///
  /// In zh, this message translates to:
  /// **'正在同步数据'**
  String get backgroundSyncing;

  /// No description provided for @daemonNotFound.
  ///
  /// In zh, this message translates to:
  /// **'找不到后台服务 lookd。开发环境请先构建：cd lookd && go build -o bin/lookd ./cmd/lookd'**
  String get daemonNotFound;

  /// No description provided for @daemonCannotReadAppDir.
  ///
  /// In zh, this message translates to:
  /// **'无法读取应用目录：{e}'**
  String daemonCannotReadAppDir(Object e);

  /// No description provided for @daemonCannotStart.
  ///
  /// In zh, this message translates to:
  /// **'无法启动后台服务：{e}'**
  String daemonCannotStart(Object e);

  /// No description provided for @daemonKeepsExiting.
  ///
  /// In zh, this message translates to:
  /// **'后台服务反复退出（退出码 {code}），可以重新启动再试。'**
  String daemonKeepsExiting(Object code);

  /// No description provided for @mirrorTuna.
  ///
  /// In zh, this message translates to:
  /// **'清华大学'**
  String get mirrorTuna;

  /// No description provided for @mirrorUstc.
  ///
  /// In zh, this message translates to:
  /// **'中国科学技术大学'**
  String get mirrorUstc;

  /// No description provided for @mirrorUbuntu.
  ///
  /// In zh, this message translates to:
  /// **'Ubuntu 官方'**
  String get mirrorUbuntu;

  /// No description provided for @workspaceStepUnpack.
  ///
  /// In zh, this message translates to:
  /// **'解压 Ubuntu 基础系统'**
  String get workspaceStepUnpack;

  /// No description provided for @workspaceStepConfigure.
  ///
  /// In zh, this message translates to:
  /// **'配置工作区'**
  String get workspaceStepConfigure;

  /// No description provided for @workspaceStepDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载 Ubuntu 基础系统'**
  String get workspaceStepDownload;

  /// No description provided for @workspaceDownloadHttpError.
  ///
  /// In zh, this message translates to:
  /// **'下载失败（HTTP {statusCode}），可以换一个镜像再试'**
  String workspaceDownloadHttpError(Object statusCode);

  /// No description provided for @workspaceDownloadTimeout.
  ///
  /// In zh, this message translates to:
  /// **'下载超时，请检查网络或换一个镜像'**
  String get workspaceDownloadTimeout;

  /// No description provided for @workspaceMirrorUnreachable.
  ///
  /// In zh, this message translates to:
  /// **'无法连接镜像站：{message}'**
  String workspaceMirrorUnreachable(Object message);

  /// No description provided for @workspaceChecksumFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载的文件校验失败，请重试'**
  String get workspaceChecksumFailed;

  /// No description provided for @workspaceUnpackFailed.
  ///
  /// In zh, this message translates to:
  /// **'解压失败：{msg}'**
  String workspaceUnpackFailed(Object msg);

  /// No description provided for @workspaceInstallFfmpeg.
  ///
  /// In zh, this message translates to:
  /// **'安装 ffmpeg'**
  String get workspaceInstallFfmpeg;

  /// No description provided for @workspaceAptExit.
  ///
  /// In zh, this message translates to:
  /// **'apt-get 退出码 {code}'**
  String workspaceAptExit(Object code);

  /// No description provided for @workspaceFfmpegFailed.
  ///
  /// In zh, this message translates to:
  /// **'安装 ffmpeg 失败：{e}'**
  String workspaceFfmpegFailed(Object e);

  /// No description provided for @commonLoading.
  ///
  /// In zh, this message translates to:
  /// **'加载中'**
  String get commonLoading;

  /// No description provided for @courseDownloadedKind.
  ///
  /// In zh, this message translates to:
  /// **'已下载{label}'**
  String courseDownloadedKind(Object label);

  /// No description provided for @stateSessionExpired.
  ///
  /// In zh, this message translates to:
  /// **'登录已失效'**
  String get stateSessionExpired;

  /// No description provided for @stateLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法加载'**
  String get stateLoadFailed;

  /// No description provided for @commonRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get commonRetry;

  /// No description provided for @readerNoHeadings.
  ///
  /// In zh, this message translates to:
  /// **'这篇没有小标题'**
  String get readerNoHeadings;

  /// No description provided for @readerFindHint.
  ///
  /// In zh, this message translates to:
  /// **'在本文中查找'**
  String get readerFindHint;

  /// No description provided for @readerNoMatches.
  ///
  /// In zh, this message translates to:
  /// **'无结果'**
  String get readerNoMatches;

  /// No description provided for @readerPreviousMatch.
  ///
  /// In zh, this message translates to:
  /// **'上一处'**
  String get readerPreviousMatch;

  /// No description provided for @readerNextMatch.
  ///
  /// In zh, this message translates to:
  /// **'下一处'**
  String get readerNextMatch;

  /// No description provided for @commonClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get commonClose;

  /// No description provided for @chartTotal.
  ///
  /// In zh, this message translates to:
  /// **'合计'**
  String get chartTotal;

  /// No description provided for @dateMonth.
  ///
  /// In zh, this message translates to:
  /// **'{month}月'**
  String dateMonth(Object month);

  /// No description provided for @weekdayMon.
  ///
  /// In zh, this message translates to:
  /// **'周一'**
  String get weekdayMon;

  /// No description provided for @weekdayWed.
  ///
  /// In zh, this message translates to:
  /// **'周三'**
  String get weekdayWed;

  /// No description provided for @weekdayFri.
  ///
  /// In zh, this message translates to:
  /// **'周五'**
  String get weekdayFri;

  /// No description provided for @dateMonthOf.
  ///
  /// In zh, this message translates to:
  /// **'{value}月'**
  String dateMonthOf(Object value);

  /// No description provided for @heatmapLess.
  ///
  /// In zh, this message translates to:
  /// **'少'**
  String get heatmapLess;

  /// No description provided for @heatmapMore.
  ///
  /// In zh, this message translates to:
  /// **'多'**
  String get heatmapMore;

  /// No description provided for @durationHoursOnly.
  ///
  /// In zh, this message translates to:
  /// **'{value} 小时'**
  String durationHoursOnly(Object value);

  /// No description provided for @durationHoursMinutesOf.
  ///
  /// In zh, this message translates to:
  /// **'{value} 小时 {value2} 分'**
  String durationHoursMinutesOf(Object value, Object value2);

  /// No description provided for @linkNotInLibrary.
  ///
  /// In zh, this message translates to:
  /// **'这个文件不在课程库里'**
  String get linkNotInLibrary;

  /// No description provided for @linkCannotOpenFile.
  ///
  /// In zh, this message translates to:
  /// **'无法打开 {value}'**
  String linkCannotOpenFile(Object value);

  /// No description provided for @linkCannotOpen.
  ///
  /// In zh, this message translates to:
  /// **'这个链接无法打开'**
  String get linkCannotOpen;

  /// No description provided for @markdownImageUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'图片不可用'**
  String get markdownImageUnavailable;

  /// No description provided for @timestampOpenLecture.
  ///
  /// In zh, this message translates to:
  /// **'打开对应课次并跳到这里'**
  String get timestampOpenLecture;

  /// No description provided for @timestampSeek.
  ///
  /// In zh, this message translates to:
  /// **'跳到这里播放'**
  String get timestampSeek;

  /// No description provided for @scrollLeft.
  ///
  /// In zh, this message translates to:
  /// **'向左滚动'**
  String get scrollLeft;

  /// No description provided for @scrollRight.
  ///
  /// In zh, this message translates to:
  /// **'向右滚动'**
  String get scrollRight;

  /// No description provided for @commonChoose.
  ///
  /// In zh, this message translates to:
  /// **'选择'**
  String get commonChoose;

  /// No description provided for @pickerChooseFolder.
  ///
  /// In zh, this message translates to:
  /// **'选择文件夹'**
  String get pickerChooseFolder;

  /// No description provided for @commonSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get commonSave;

  /// No description provided for @pickerSaveToFolder.
  ///
  /// In zh, this message translates to:
  /// **'保存到哪个文件夹'**
  String get pickerSaveToFolder;

  /// No description provided for @pickerFolderPath.
  ///
  /// In zh, this message translates to:
  /// **'文件夹路径'**
  String get pickerFolderPath;

  /// No description provided for @commonCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @loginHeadline.
  ///
  /// In zh, this message translates to:
  /// **'课堂录像，\n变成你的知识库。'**
  String get loginHeadline;

  /// No description provided for @loginFeatureDownload.
  ///
  /// In zh, this message translates to:
  /// **'高速下载录像、PPT 与课件，断点续传'**
  String get loginFeatureDownload;

  /// No description provided for @loginFeatureTranscribe.
  ///
  /// In zh, this message translates to:
  /// **'自动转写，按时间轴全文检索'**
  String get loginFeatureTranscribe;

  /// No description provided for @loginFeatureAssistant.
  ///
  /// In zh, this message translates to:
  /// **'常驻助手帮你梳理每一节课'**
  String get loginFeatureAssistant;

  /// No description provided for @loginMissingCredentials.
  ///
  /// In zh, this message translates to:
  /// **'请输入学号和密码'**
  String get loginMissingCredentials;

  /// No description provided for @loginSignInAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新登录'**
  String get loginSignInAgain;

  /// No description provided for @loginSignIn.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get loginSignIn;

  /// No description provided for @loginChooseSchool.
  ///
  /// In zh, this message translates to:
  /// **'选择学校，用统一身份认证账号登录'**
  String get loginChooseSchool;

  /// No description provided for @loginHintTongji.
  ///
  /// In zh, this message translates to:
  /// **'连接同济 Look 录课平台（look.tongji.edu.cn）'**
  String get loginHintTongji;

  /// No description provided for @loginHintFudan.
  ///
  /// In zh, this message translates to:
  /// **'经复旦 WebVPN 连接 iCourse，登录约需半分钟'**
  String get loginHintFudan;

  /// No description provided for @loginSchoolsFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取学校列表：{e}'**
  String loginSchoolsFailed(Object e);

  /// No description provided for @loginStudentId.
  ///
  /// In zh, this message translates to:
  /// **'学号 / 工号'**
  String get loginStudentId;

  /// No description provided for @commonPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get commonPassword;

  /// No description provided for @commonShowPassword.
  ///
  /// In zh, this message translates to:
  /// **'显示密码'**
  String get commonShowPassword;

  /// No description provided for @commonHidePassword.
  ///
  /// In zh, this message translates to:
  /// **'隐藏密码'**
  String get commonHidePassword;

  /// No description provided for @loginCaptcha.
  ///
  /// In zh, this message translates to:
  /// **'验证码'**
  String get loginCaptcha;

  /// No description provided for @loginStaySignedIn.
  ///
  /// In zh, this message translates to:
  /// **'保持登录'**
  String get loginStaySignedIn;

  /// No description provided for @loginStaySignedInHint.
  ///
  /// In zh, this message translates to:
  /// **'登录过期时自动续期，密码加密保存在本机'**
  String get loginStaySignedInHint;

  /// No description provided for @loginPrivacy.
  ///
  /// In zh, this message translates to:
  /// **'学号和密码只发送给学校的统一身份认证，保持登录时加密保存在本机。'**
  String get loginPrivacy;

  /// No description provided for @homeGreetingNight.
  ///
  /// In zh, this message translates to:
  /// **'夜深了'**
  String get homeGreetingNight;

  /// No description provided for @homeGreetingMorning.
  ///
  /// In zh, this message translates to:
  /// **'早上好'**
  String get homeGreetingMorning;

  /// No description provided for @homeGreetingNoon.
  ///
  /// In zh, this message translates to:
  /// **'中午好'**
  String get homeGreetingNoon;

  /// No description provided for @homeGreetingAfternoon.
  ///
  /// In zh, this message translates to:
  /// **'下午好'**
  String get homeGreetingAfternoon;

  /// No description provided for @homeGreetingEvening.
  ///
  /// In zh, this message translates to:
  /// **'晚上好'**
  String get homeGreetingEvening;

  /// No description provided for @homeUpNext.
  ///
  /// In zh, this message translates to:
  /// **'接下来'**
  String get homeUpNext;

  /// No description provided for @commonSchedule.
  ///
  /// In zh, this message translates to:
  /// **'日程'**
  String get commonSchedule;

  /// No description provided for @commonActivity.
  ///
  /// In zh, this message translates to:
  /// **'学习足迹'**
  String get commonActivity;

  /// No description provided for @homeStatistics.
  ///
  /// In zh, this message translates to:
  /// **'统计'**
  String get homeStatistics;

  /// No description provided for @homeContinueWatching.
  ///
  /// In zh, this message translates to:
  /// **'继续观看'**
  String get homeContinueWatching;

  /// No description provided for @homeDownloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下载'**
  String get homeDownloading;

  /// No description provided for @commonAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get commonAll;

  /// No description provided for @commonCourses.
  ///
  /// In zh, this message translates to:
  /// **'课程'**
  String get commonCourses;

  /// No description provided for @homeThisTermCourses.
  ///
  /// In zh, this message translates to:
  /// **'本学期课程'**
  String get homeThisTermCourses;

  /// No description provided for @homeAllCourses.
  ///
  /// In zh, this message translates to:
  /// **'全部课程'**
  String get homeAllCourses;

  /// No description provided for @commonLibrary.
  ///
  /// In zh, this message translates to:
  /// **'课程库'**
  String get commonLibrary;

  /// No description provided for @homeGreeting.
  ///
  /// In zh, this message translates to:
  /// **'{greeting}，'**
  String homeGreeting(Object greeting);

  /// No description provided for @profileEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑个人资料'**
  String get profileEdit;

  /// No description provided for @homeNextQuote.
  ///
  /// In zh, this message translates to:
  /// **'换一句'**
  String get homeNextQuote;

  /// No description provided for @homeStatLecturesSaved.
  ///
  /// In zh, this message translates to:
  /// **'节已存本地'**
  String get homeStatLecturesSaved;

  /// No description provided for @homeStatStorage.
  ///
  /// In zh, this message translates to:
  /// **'占用空间'**
  String get homeStatStorage;

  /// No description provided for @homeStatSegments.
  ///
  /// In zh, this message translates to:
  /// **'句转写'**
  String get homeStatSegments;

  /// No description provided for @homeStatNotes.
  ///
  /// In zh, this message translates to:
  /// **'篇笔记'**
  String get homeStatNotes;

  /// No description provided for @listSeparator.
  ///
  /// In zh, this message translates to:
  /// **'、'**
  String get listSeparator;

  /// No description provided for @courseLectureCount.
  ///
  /// In zh, this message translates to:
  /// **'{lectureTotal} 节'**
  String courseLectureCount(Object lectureTotal);

  /// No description provided for @coursesSync.
  ///
  /// In zh, this message translates to:
  /// **'从平台同步'**
  String get coursesSync;

  /// No description provided for @coursesSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索课程或老师'**
  String get coursesSearchHint;

  /// No description provided for @coursesAllTerms.
  ///
  /// In zh, this message translates to:
  /// **'全部学期'**
  String get coursesAllTerms;

  /// No description provided for @coursesHiddenCount.
  ///
  /// In zh, this message translates to:
  /// **'已隐藏 {hiddenCount}'**
  String coursesHiddenCount(Object hiddenCount);

  /// No description provided for @coursesSyncing.
  ///
  /// In zh, this message translates to:
  /// **'正在同步课程'**
  String get coursesSyncing;

  /// No description provided for @coursesEmptyTerm.
  ///
  /// In zh, this message translates to:
  /// **'这个学期没有课程'**
  String get coursesEmptyTerm;

  /// No description provided for @coursesNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配“{text}”的课程'**
  String coursesNoMatch(Object text);

  /// No description provided for @coursesUnpin.
  ///
  /// In zh, this message translates to:
  /// **'取消置顶'**
  String get coursesUnpin;

  /// No description provided for @coursesPin.
  ///
  /// In zh, this message translates to:
  /// **'置顶'**
  String get coursesPin;

  /// No description provided for @commonRename.
  ///
  /// In zh, this message translates to:
  /// **'重命名'**
  String get commonRename;

  /// No description provided for @coursesColor.
  ///
  /// In zh, this message translates to:
  /// **'课程颜色'**
  String get coursesColor;

  /// No description provided for @coursesUnhide.
  ///
  /// In zh, this message translates to:
  /// **'取消隐藏'**
  String get coursesUnhide;

  /// No description provided for @commonHide.
  ///
  /// In zh, this message translates to:
  /// **'隐藏'**
  String get commonHide;

  /// No description provided for @coursesRenameTitle.
  ///
  /// In zh, this message translates to:
  /// **'重命名课程'**
  String get coursesRenameTitle;

  /// No description provided for @coursesOriginalName.
  ///
  /// In zh, this message translates to:
  /// **'原名：{rawTitle}'**
  String coursesOriginalName(Object rawTitle);

  /// No description provided for @coursesDisplayName.
  ///
  /// In zh, this message translates to:
  /// **'显示名称'**
  String get coursesDisplayName;

  /// No description provided for @coursesDisplayNameHelper.
  ///
  /// In zh, this message translates to:
  /// **'留空则使用原名，不影响本地文件夹'**
  String get coursesDisplayNameHelper;

  /// No description provided for @downloadVideoHint.
  ///
  /// In zh, this message translates to:
  /// **'多路分段并发下载，可断点续传'**
  String get downloadVideoHint;

  /// No description provided for @assetSlides.
  ///
  /// In zh, this message translates to:
  /// **'PPT 截图'**
  String get assetSlides;

  /// No description provided for @downloadSlidesHint.
  ///
  /// In zh, this message translates to:
  /// **'按时间戳命名，可与视频同步'**
  String get downloadSlidesHint;

  /// No description provided for @assetAsr.
  ///
  /// In zh, this message translates to:
  /// **'语音转写'**
  String get assetAsr;

  /// No description provided for @downloadAsrHint.
  ///
  /// In zh, this message translates to:
  /// **'必剪 / 剪映免费识别，分段并行，带时间戳'**
  String get downloadAsrHint;

  /// No description provided for @downloadQueued.
  ///
  /// In zh, this message translates to:
  /// **'已加入 {length} 个任务'**
  String downloadQueued(Object length);

  /// No description provided for @downloadQueueFailed.
  ///
  /// In zh, this message translates to:
  /// **'加入失败：{e}'**
  String downloadQueueFailed(Object e);

  /// No description provided for @downloadThisLecture.
  ///
  /// In zh, this message translates to:
  /// **'下载这节课'**
  String get downloadThisLecture;

  /// No description provided for @downloadLectures.
  ///
  /// In zh, this message translates to:
  /// **'下载 {count} 节课'**
  String downloadLectures(Object count);

  /// No description provided for @downloadSavedToLibrary.
  ///
  /// In zh, this message translates to:
  /// **'文件保存在课程库里，按课程与日期整理'**
  String get downloadSavedToLibrary;

  /// No description provided for @downloadNeedsFfmpeg.
  ///
  /// In zh, this message translates to:
  /// **'需要安装 ffmpeg'**
  String get downloadNeedsFfmpeg;

  /// No description provided for @downloadNoCourseware.
  ///
  /// In zh, this message translates to:
  /// **'平台不提供课件。在播放器的「资料 → 课件」里上传，MinerU 会解析成可检索的文字。'**
  String get downloadNoCourseware;

  /// No description provided for @downloadDeleteVideoAfterAsr.
  ///
  /// In zh, this message translates to:
  /// **'已开启「转写完成后删除视频」：视频会在文字稿生成后被删除'**
  String get downloadDeleteVideoAfterAsr;

  /// No description provided for @downloadDeleteLocalVideoAfterAsr.
  ///
  /// In zh, this message translates to:
  /// **'已开启「转写完成后删除视频」：本地已有的视频会在转写完成后删除'**
  String get downloadDeleteLocalVideoAfterAsr;

  /// No description provided for @downloadChooseContent.
  ///
  /// In zh, this message translates to:
  /// **'选择要下载的内容'**
  String get downloadChooseContent;

  /// No description provided for @downloadStart.
  ///
  /// In zh, this message translates to:
  /// **'开始下载'**
  String get downloadStart;

  /// No description provided for @courseUnscheduled.
  ///
  /// In zh, this message translates to:
  /// **'未排期'**
  String get courseUnscheduled;

  /// No description provided for @dateYearMonth.
  ///
  /// In zh, this message translates to:
  /// **'{year}年{month}月'**
  String dateYearMonth(Object year, Object month);

  /// No description provided for @screenCourse.
  ///
  /// In zh, this message translates to:
  /// **'课程详情'**
  String get screenCourse;

  /// No description provided for @courseSelectedCount.
  ///
  /// In zh, this message translates to:
  /// **'已选 {length} 节'**
  String courseSelectedCount(Object length);

  /// No description provided for @commonDeselectAll.
  ///
  /// In zh, this message translates to:
  /// **'取消全选'**
  String get commonDeselectAll;

  /// No description provided for @commonSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get commonSelectAll;

  /// No description provided for @courseAssistant.
  ///
  /// In zh, this message translates to:
  /// **'课程助手'**
  String get courseAssistant;

  /// No description provided for @courseRefreshSchedule.
  ///
  /// In zh, this message translates to:
  /// **'刷新课表'**
  String get courseRefreshSchedule;

  /// No description provided for @commonMore.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get commonMore;

  /// No description provided for @courseLoadingSchedule.
  ///
  /// In zh, this message translates to:
  /// **'正在读取课表'**
  String get courseLoadingSchedule;

  /// No description provided for @courseLectureTotal.
  ///
  /// In zh, this message translates to:
  /// **'{length} 节课'**
  String courseLectureTotal(Object length);

  /// No description provided for @courseNewestFirst.
  ///
  /// In zh, this message translates to:
  /// **'最新在前'**
  String get courseNewestFirst;

  /// No description provided for @courseOldestFirst.
  ///
  /// In zh, this message translates to:
  /// **'第一节在前'**
  String get courseOldestFirst;

  /// No description provided for @courseBatchDownload.
  ///
  /// In zh, this message translates to:
  /// **'批量下载'**
  String get courseBatchDownload;

  /// No description provided for @courseDownloadSelected.
  ///
  /// In zh, this message translates to:
  /// **'下载 {length} 节'**
  String courseDownloadSelected(Object length);

  /// No description provided for @courseStatLectures.
  ///
  /// In zh, this message translates to:
  /// **'{lectures} 节'**
  String courseStatLectures(Object lectures);

  /// No description provided for @courseStatLocal.
  ///
  /// In zh, this message translates to:
  /// **'本地 {local} 节'**
  String courseStatLocal(Object local);

  /// No description provided for @courseProgress.
  ///
  /// In zh, this message translates to:
  /// **'学习进度 {value}%'**
  String courseProgress(Object value);

  /// No description provided for @courseContinue.
  ///
  /// In zh, this message translates to:
  /// **'继续学习'**
  String get courseContinue;

  /// No description provided for @courseStart.
  ///
  /// In zh, this message translates to:
  /// **'开始学习'**
  String get courseStart;

  /// No description provided for @lectureOrdinal.
  ///
  /// In zh, this message translates to:
  /// **'第 {ordinal} 节'**
  String lectureOrdinal(Object ordinal);

  /// No description provided for @lectureNotStarted.
  ///
  /// In zh, this message translates to:
  /// **'未开始'**
  String get lectureNotStarted;

  /// No description provided for @lectureNoReplay.
  ///
  /// In zh, this message translates to:
  /// **'暂无回放'**
  String get lectureNoReplay;

  /// No description provided for @commonDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get commonDownload;

  /// No description provided for @commonPlay.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get commonPlay;

  /// No description provided for @playerSeekToast.
  ///
  /// In zh, this message translates to:
  /// **'{value}{s} 秒'**
  String playerSeekToast(Object value, Object s);

  /// No description provided for @playerVolumeToast.
  ///
  /// In zh, this message translates to:
  /// **'音量 {value}%'**
  String playerVolumeToast(Object value);

  /// No description provided for @playerSpeedToast.
  ///
  /// In zh, this message translates to:
  /// **'倍速 {value}'**
  String playerSpeedToast(Object value);

  /// No description provided for @playerBoosting.
  ///
  /// In zh, this message translates to:
  /// **'{value} 快进中'**
  String playerBoosting(Object value);

  /// No description provided for @commonBack.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get commonBack;

  /// No description provided for @playerCollapsePanel.
  ///
  /// In zh, this message translates to:
  /// **'收起侧栏'**
  String get playerCollapsePanel;

  /// No description provided for @playerExpandPanel.
  ///
  /// In zh, this message translates to:
  /// **'展开侧栏'**
  String get playerExpandPanel;

  /// No description provided for @playerLocalSuffix.
  ///
  /// In zh, this message translates to:
  /// **'（本地）'**
  String get playerLocalSuffix;

  /// No description provided for @playerPip.
  ///
  /// In zh, this message translates to:
  /// **'画中画'**
  String get playerPip;

  /// No description provided for @playerSeekBack.
  ///
  /// In zh, this message translates to:
  /// **'后退 {seekStepSec} 秒 (←)'**
  String playerSeekBack(Object seekStepSec);

  /// No description provided for @playerSeekForward.
  ///
  /// In zh, this message translates to:
  /// **'前进 {seekStepSec} 秒 (→)'**
  String playerSeekForward(Object seekStepSec);

  /// No description provided for @playerSpeedTooltip.
  ///
  /// In zh, this message translates to:
  /// **'倍速 ([ / ])'**
  String get playerSpeedTooltip;

  /// No description provided for @playerSubtitlesTooltip.
  ///
  /// In zh, this message translates to:
  /// **'字幕 (C)'**
  String get playerSubtitlesTooltip;

  /// No description provided for @playerBookmarkTooltip.
  ///
  /// In zh, this message translates to:
  /// **'添加书签 (B)'**
  String get playerBookmarkTooltip;

  /// No description provided for @playerBookmarkAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加书签 {value}'**
  String playerBookmarkAdded(Object value);

  /// No description provided for @playerExitFullscreen.
  ///
  /// In zh, this message translates to:
  /// **'退出全屏 (F)'**
  String get playerExitFullscreen;

  /// No description provided for @playerFullscreen.
  ///
  /// In zh, this message translates to:
  /// **'全屏 (F)'**
  String get playerFullscreen;

  /// No description provided for @playerMute.
  ///
  /// In zh, this message translates to:
  /// **'静音 (M)'**
  String get playerMute;

  /// No description provided for @playerResumedFrom.
  ///
  /// In zh, this message translates to:
  /// **'已从 {value} 继续'**
  String playerResumedFrom(Object value);

  /// No description provided for @playerStartOver.
  ///
  /// In zh, this message translates to:
  /// **'从头播放'**
  String get playerStartOver;

  /// No description provided for @playerPauseTooltip.
  ///
  /// In zh, this message translates to:
  /// **'暂停 (空格)'**
  String get playerPauseTooltip;

  /// No description provided for @playerPlayTooltip.
  ///
  /// In zh, this message translates to:
  /// **'播放 (空格)'**
  String get playerPlayTooltip;

  /// No description provided for @playerError.
  ///
  /// In zh, this message translates to:
  /// **'播放出错'**
  String get playerError;

  /// No description provided for @playerReload.
  ///
  /// In zh, this message translates to:
  /// **'重新加载'**
  String get playerReload;

  /// No description provided for @playerNoLectureAtTime.
  ///
  /// In zh, this message translates to:
  /// **'这个时间点没有对应的课次'**
  String get playerNoLectureAtTime;

  /// No description provided for @playerPreparing.
  ///
  /// In zh, this message translates to:
  /// **'正在准备播放'**
  String get playerPreparing;

  /// No description provided for @screenPlayer.
  ///
  /// In zh, this message translates to:
  /// **'播放器'**
  String get screenPlayer;

  /// No description provided for @outlineFailed.
  ///
  /// In zh, this message translates to:
  /// **'大纲生成失败：{e}'**
  String outlineFailed(Object e);

  /// No description provided for @outlineNeedsTranscript.
  ///
  /// In zh, this message translates to:
  /// **'大纲需要文字稿'**
  String get outlineNeedsTranscript;

  /// No description provided for @outlineNeedsTranscriptBody.
  ///
  /// In zh, this message translates to:
  /// **'先转写这节课，助手才能读完内容、按话题分章。'**
  String get outlineNeedsTranscriptBody;

  /// No description provided for @asrQueued.
  ///
  /// In zh, this message translates to:
  /// **'已加入转写队列'**
  String get asrQueued;

  /// No description provided for @asrStart.
  ///
  /// In zh, this message translates to:
  /// **'开始转写'**
  String get asrStart;

  /// No description provided for @outlineTitle.
  ///
  /// In zh, this message translates to:
  /// **'给这节课分章'**
  String get outlineTitle;

  /// No description provided for @outlineBody.
  ///
  /// In zh, this message translates to:
  /// **'助手读完整份文字稿，按话题切成章节。点章节即可跳转，进度条上也会分段显示。'**
  String get outlineBody;

  /// No description provided for @outlineLastError.
  ///
  /// In zh, this message translates to:
  /// **'上次没有成功：{outlineError}'**
  String outlineLastError(Object outlineError);

  /// No description provided for @outlineGenerate.
  ///
  /// In zh, this message translates to:
  /// **'生成大纲'**
  String get outlineGenerate;

  /// No description provided for @outlineRegenerating.
  ///
  /// In zh, this message translates to:
  /// **'正在重新分章…'**
  String get outlineRegenerating;

  /// No description provided for @outlineSummary.
  ///
  /// In zh, this message translates to:
  /// **'{length} 章 · {value}'**
  String outlineSummary(Object length, Object value);

  /// No description provided for @commonRegenerate.
  ///
  /// In zh, this message translates to:
  /// **'重新生成'**
  String get commonRegenerate;

  /// No description provided for @outlineCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制大纲'**
  String get outlineCopied;

  /// No description provided for @commonCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get commonCopy;

  /// No description provided for @outlineDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除大纲'**
  String get outlineDeleted;

  /// No description provided for @commonUndo.
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get commonUndo;

  /// No description provided for @commonDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get commonDelete;

  /// No description provided for @outlineOptions.
  ///
  /// In zh, this message translates to:
  /// **'大纲选项'**
  String get outlineOptions;

  /// No description provided for @durationUnderMinute.
  ///
  /// In zh, this message translates to:
  /// **'不到 1 分钟'**
  String get durationUnderMinute;

  /// No description provided for @outlineWorking.
  ///
  /// In zh, this message translates to:
  /// **'正在通读文字稿并分章'**
  String get outlineWorking;

  /// No description provided for @outlineWorkingHint.
  ///
  /// In zh, this message translates to:
  /// **'长课可能需要一两分钟，可以先去看别的。'**
  String get outlineWorkingHint;

  /// No description provided for @commonLocal.
  ///
  /// In zh, this message translates to:
  /// **'本地'**
  String get commonLocal;

  /// No description provided for @playerNoVideo.
  ///
  /// In zh, this message translates to:
  /// **'这节课没有可播放的视频'**
  String get playerNoVideo;

  /// No description provided for @commonOutline.
  ///
  /// In zh, this message translates to:
  /// **'大纲'**
  String get commonOutline;

  /// No description provided for @commonTranscript.
  ///
  /// In zh, this message translates to:
  /// **'文字稿'**
  String get commonTranscript;

  /// No description provided for @panelMaterials.
  ///
  /// In zh, this message translates to:
  /// **'资料'**
  String get panelMaterials;

  /// No description provided for @commonAssistant.
  ///
  /// In zh, this message translates to:
  /// **'助手'**
  String get commonAssistant;

  /// No description provided for @panelSlidesCount.
  ///
  /// In zh, this message translates to:
  /// **'PPT 截图 {length}'**
  String panelSlidesCount(Object length);

  /// No description provided for @panelCoursewareCount.
  ///
  /// In zh, this message translates to:
  /// **'课件 {length}'**
  String panelCoursewareCount(Object length);

  /// No description provided for @slidesEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这节课没有 PPT 截图'**
  String get slidesEmpty;

  /// No description provided for @slidesEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'平台只在老师投屏时生成截图'**
  String get slidesEmptyBody;

  /// No description provided for @slidesPageOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅换页'**
  String get slidesPageOnly;

  /// No description provided for @slidesFollow.
  ///
  /// In zh, this message translates to:
  /// **'跟随播放'**
  String get slidesFollow;

  /// No description provided for @slidesDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载 PPT'**
  String get slidesDownload;

  /// No description provided for @slidesIndex.
  ///
  /// In zh, this message translates to:
  /// **'第 {idx} 张'**
  String slidesIndex(Object idx);

  /// No description provided for @slidesPosition.
  ///
  /// In zh, this message translates to:
  /// **'{value} / {length} · 从 {value2} 播放'**
  String slidesPosition(Object value, Object length, Object value2);

  /// No description provided for @transcriptEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有文字稿'**
  String get transcriptEmpty;

  /// No description provided for @transcriptEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'转写会提取音频并生成带时间戳的文字，之后可以搜索、做字幕，也能让助手整理笔记。'**
  String get transcriptEmptyBody;

  /// No description provided for @asrQueuedShowLater.
  ///
  /// In zh, this message translates to:
  /// **'已加入转写队列，完成后自动显示'**
  String get asrQueuedShowLater;

  /// No description provided for @transcriptFindHint.
  ///
  /// In zh, this message translates to:
  /// **'在文字稿中查找'**
  String get transcriptFindHint;

  /// No description provided for @transcriptMatches.
  ///
  /// In zh, this message translates to:
  /// **'{length} 处'**
  String transcriptMatches(Object length);

  /// No description provided for @transcriptFollowOn.
  ///
  /// In zh, this message translates to:
  /// **'跟随播放：开'**
  String get transcriptFollowOn;

  /// No description provided for @transcriptFollowOff.
  ///
  /// In zh, this message translates to:
  /// **'跟随播放：关'**
  String get transcriptFollowOff;

  /// No description provided for @transcriptCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制全文'**
  String get transcriptCopied;

  /// No description provided for @transcriptCopyAll.
  ///
  /// In zh, this message translates to:
  /// **'复制全文'**
  String get transcriptCopyAll;

  /// No description provided for @promptNotes.
  ///
  /// In zh, this message translates to:
  /// **'请为这节课整理一份完整的学习笔记并保存：以字幕为主，找出重点和不确定的地方，对照当时的 PPT 和已上传的课件核实，公式用 LaTeX，要点附时间戳。'**
  String get promptNotes;

  /// No description provided for @panelAskNotes.
  ///
  /// In zh, this message translates to:
  /// **'让助手整理笔记'**
  String get panelAskNotes;

  /// No description provided for @panelQuizMore.
  ///
  /// In zh, this message translates to:
  /// **'出题练习…'**
  String get panelQuizMore;

  /// No description provided for @promptSummarizeRecent.
  ///
  /// In zh, this message translates to:
  /// **'用几句话概括我刚才看的这一段（当前播放位置前 5 分钟）讲了什么。'**
  String get promptSummarizeRecent;

  /// No description provided for @panelSummarizeRecent.
  ///
  /// In zh, this message translates to:
  /// **'概括刚才这段'**
  String get panelSummarizeRecent;

  /// No description provided for @commonBookmarks.
  ///
  /// In zh, this message translates to:
  /// **'书签'**
  String get commonBookmarks;

  /// No description provided for @panelCurrentPosition.
  ///
  /// In zh, this message translates to:
  /// **'当前位置'**
  String get panelCurrentPosition;

  /// No description provided for @bookmarksHint.
  ///
  /// In zh, this message translates to:
  /// **'按 B 键或点播放器上的书签按钮标记重点'**
  String get bookmarksHint;

  /// No description provided for @commonNew.
  ///
  /// In zh, this message translates to:
  /// **'新建'**
  String get commonNew;

  /// No description provided for @notesHint.
  ///
  /// In zh, this message translates to:
  /// **'笔记以 Markdown 文件保存在课程库中，助手也能读取'**
  String get notesHint;

  /// No description provided for @commonPractice.
  ///
  /// In zh, this message translates to:
  /// **'练习'**
  String get commonPractice;

  /// No description provided for @panelQuiz.
  ///
  /// In zh, this message translates to:
  /// **'出题'**
  String get panelQuiz;

  /// No description provided for @panelQuizHint.
  ///
  /// In zh, this message translates to:
  /// **'让助手根据这节课出一组选择题，每题附解析和出处'**
  String get panelQuizHint;

  /// No description provided for @downloadsClearTitle.
  ///
  /// In zh, this message translates to:
  /// **'清除已完成的任务'**
  String get downloadsClearTitle;

  /// No description provided for @downloadsClearBody.
  ///
  /// In zh, this message translates to:
  /// **'任务记录会被清除。已下载的文件默认保留在课程库中。'**
  String get downloadsClearBody;

  /// No description provided for @downloadsClearAlsoFiles.
  ///
  /// In zh, this message translates to:
  /// **'同时删除已下载的文件'**
  String get downloadsClearAlsoFiles;

  /// No description provided for @downloadsClearAlsoFilesHint.
  ///
  /// In zh, this message translates to:
  /// **'视频、PPT、课件和文字稿会从磁盘移除，不可恢复'**
  String get downloadsClearAlsoFilesHint;

  /// No description provided for @downloadsClearAndDelete.
  ///
  /// In zh, this message translates to:
  /// **'清除并删除文件'**
  String get downloadsClearAndDelete;

  /// No description provided for @downloadsClearRecords.
  ///
  /// In zh, this message translates to:
  /// **'清除记录'**
  String get downloadsClearRecords;

  /// No description provided for @downloadsClearedFreed.
  ///
  /// In zh, this message translates to:
  /// **'已清除，释放 {value}'**
  String downloadsClearedFreed(Object value);

  /// No description provided for @downloadsCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清除任务记录'**
  String get downloadsCleared;

  /// No description provided for @downloadsClearFailed.
  ///
  /// In zh, this message translates to:
  /// **'清除失败：{e}'**
  String downloadsClearFailed(Object e);

  /// No description provided for @downloadsRunningSummary.
  ///
  /// In zh, this message translates to:
  /// **'{running} 个任务进行中 · {value}'**
  String downloadsRunningSummary(Object running, Object value);

  /// No description provided for @downloadsNoneRunning.
  ///
  /// In zh, this message translates to:
  /// **'没有进行中的任务'**
  String get downloadsNoneRunning;

  /// No description provided for @downloadsWaiting.
  ///
  /// In zh, this message translates to:
  /// **'{length} 个任务等待中'**
  String downloadsWaiting(Object length);

  /// No description provided for @commonTasks.
  ///
  /// In zh, this message translates to:
  /// **'任务'**
  String get commonTasks;

  /// No description provided for @commonTasksCount.
  ///
  /// In zh, this message translates to:
  /// **'任务 {length}'**
  String commonTasksCount(Object length);

  /// No description provided for @commonDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'已下载'**
  String get commonDownloaded;

  /// No description provided for @downloadsPauseAll.
  ///
  /// In zh, this message translates to:
  /// **'全部暂停'**
  String get downloadsPauseAll;

  /// No description provided for @downloadsResumeAll.
  ///
  /// In zh, this message translates to:
  /// **'全部继续'**
  String get downloadsResumeAll;

  /// No description provided for @downloadsClearDone.
  ///
  /// In zh, this message translates to:
  /// **'清除已完成'**
  String get downloadsClearDone;

  /// No description provided for @screenDownloads.
  ///
  /// In zh, this message translates to:
  /// **'下载管理'**
  String get screenDownloads;

  /// No description provided for @downloadsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有下载'**
  String get downloadsEmpty;

  /// No description provided for @downloadsEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'在课程里选择课次，点下载按钮。视频、PPT、课件和文字稿会按课程整理到课程库。'**
  String get downloadsEmptyBody;

  /// No description provided for @downloadsSectionActive.
  ///
  /// In zh, this message translates to:
  /// **'进行中'**
  String get downloadsSectionActive;

  /// No description provided for @commonFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get commonFailed;

  /// No description provided for @downloadsRetryAll.
  ///
  /// In zh, this message translates to:
  /// **'全部重试'**
  String get downloadsRetryAll;

  /// No description provided for @commonDone.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get commonDone;

  /// No description provided for @downloadsBulkDone.
  ///
  /// In zh, this message translates to:
  /// **'{value} {n} 个任务'**
  String downloadsBulkDone(Object value, Object n);

  /// No description provided for @commonPaused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get commonPaused;

  /// No description provided for @downloadsResumed.
  ///
  /// In zh, this message translates to:
  /// **'已继续'**
  String get downloadsResumed;

  /// No description provided for @downloadsRetried.
  ///
  /// In zh, this message translates to:
  /// **'已重试'**
  String get downloadsRetried;

  /// No description provided for @commonActionFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{e}'**
  String commonActionFailed(Object e);

  /// No description provided for @downloadsDeleteFilesTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除文件？'**
  String get downloadsDeleteFilesTitle;

  /// No description provided for @downloadsDeleteFilesBody.
  ///
  /// In zh, this message translates to:
  /// **'将从磁盘删除{what}，不可恢复。需要时可以重新下载。'**
  String downloadsDeleteFilesBody(Object what);

  /// No description provided for @downloadsDeletedFreed.
  ///
  /// In zh, this message translates to:
  /// **'已删除，释放 {value}'**
  String downloadsDeletedFreed(Object value);

  /// No description provided for @commonDeleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'删除失败：{e}'**
  String commonDeleteFailed(Object e);

  /// No description provided for @downloadsLocalEmpty.
  ///
  /// In zh, this message translates to:
  /// **'本地还没有文件'**
  String get downloadsLocalEmpty;

  /// No description provided for @downloadsLocalEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'下载完成的视频、PPT、课件和文字稿会出现在这里。'**
  String get downloadsLocalEmptyBody;

  /// No description provided for @downloadsDeleteKindFiles.
  ///
  /// In zh, this message translates to:
  /// **'删除{value}文件'**
  String downloadsDeleteKindFiles(Object value);

  /// No description provided for @downloadsLectureKind.
  ///
  /// In zh, this message translates to:
  /// **'这节课的{value}（{value2}）'**
  String downloadsLectureKind(Object value, Object value2);

  /// No description provided for @commonShowInFolder.
  ///
  /// In zh, this message translates to:
  /// **'在文件夹中显示'**
  String get commonShowInFolder;

  /// No description provided for @downloadsLectureAllFiles.
  ///
  /// In zh, this message translates to:
  /// **'这节课的全部文件（{value}）'**
  String downloadsLectureAllFiles(Object value);

  /// No description provided for @downloadsDeleteAllFiles.
  ///
  /// In zh, this message translates to:
  /// **'删除全部文件'**
  String get downloadsDeleteAllFiles;

  /// No description provided for @commonCannotOpenFolder.
  ///
  /// In zh, this message translates to:
  /// **'无法打开文件夹'**
  String get commonCannotOpenFolder;

  /// No description provided for @downloadsStateRunning.
  ///
  /// In zh, this message translates to:
  /// **'下载中'**
  String get downloadsStateRunning;

  /// No description provided for @downloadsStateRetrying.
  ///
  /// In zh, this message translates to:
  /// **'网络中断，{value} 自动重试'**
  String downloadsStateRetrying(Object value);

  /// No description provided for @commonQueued.
  ///
  /// In zh, this message translates to:
  /// **'排队中'**
  String get commonQueued;

  /// No description provided for @commonCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get commonCancelled;

  /// No description provided for @downloadsConnections.
  ///
  /// In zh, this message translates to:
  /// **'{conns} 路并发'**
  String downloadsConnections(Object conns);

  /// No description provided for @commonPause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get commonPause;

  /// No description provided for @commonResume.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get commonResume;

  /// No description provided for @downloadsRemoveRecordOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅移除记录'**
  String get downloadsRemoveRecordOnly;

  /// No description provided for @downloadsJobFiles.
  ///
  /// In zh, this message translates to:
  /// **'「{title}」的{value}文件{value2}'**
  String downloadsJobFiles(Object title, Object value, Object value2);

  /// No description provided for @downloadsSizeSuffix.
  ///
  /// In zh, this message translates to:
  /// **'（{value}）'**
  String downloadsSizeSuffix(Object value);

  /// No description provided for @downloadsDeleteRecordAndFiles.
  ///
  /// In zh, this message translates to:
  /// **'删除记录和文件'**
  String get downloadsDeleteRecordAndFiles;

  /// No description provided for @noteUntitled.
  ///
  /// In zh, this message translates to:
  /// **'未命名笔记'**
  String get noteUntitled;

  /// No description provided for @noteSaved.
  ///
  /// In zh, this message translates to:
  /// **'笔记已保存'**
  String get noteSaved;

  /// No description provided for @commonSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{e}'**
  String commonSaveFailed(Object e);

  /// No description provided for @commonTitle.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get commonTitle;

  /// No description provided for @commonEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get commonEdit;

  /// No description provided for @commonPreview.
  ///
  /// In zh, this message translates to:
  /// **'预览'**
  String get commonPreview;

  /// No description provided for @noteEditorHint.
  ///
  /// In zh, this message translates to:
  /// **'支持 Markdown。{value}内容保存在课程库的 notes 文件夹。'**
  String noteEditorHint(Object value);

  /// No description provided for @noteEditorHintTimestamp.
  ///
  /// In zh, this message translates to:
  /// **'点“插入时间”记录当前播放位置，'**
  String get noteEditorHintTimestamp;

  /// No description provided for @noteInsertTime.
  ///
  /// In zh, this message translates to:
  /// **'插入时间'**
  String get noteInsertTime;

  /// No description provided for @noteUnsaved.
  ///
  /// In zh, this message translates to:
  /// **'未保存'**
  String get noteUnsaved;

  /// No description provided for @searchFailed.
  ///
  /// In zh, this message translates to:
  /// **'搜索失败：{e}'**
  String searchFailed(Object e);

  /// No description provided for @screenLibrary.
  ///
  /// In zh, this message translates to:
  /// **'资料库'**
  String get screenLibrary;

  /// No description provided for @libraryWriteNote.
  ///
  /// In zh, this message translates to:
  /// **'写笔记'**
  String get libraryWriteNote;

  /// No description provided for @librarySearchTitle.
  ///
  /// In zh, this message translates to:
  /// **'全文搜索所有文字稿与笔记'**
  String get librarySearchTitle;

  /// No description provided for @librarySearchHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：傅里叶变换、期中、作业'**
  String get librarySearchHint;

  /// No description provided for @libraryAllCourses.
  ///
  /// In zh, this message translates to:
  /// **'所有课程'**
  String get libraryAllCourses;

  /// No description provided for @librarySearchEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有找到“{value}”'**
  String librarySearchEmpty(Object value);

  /// No description provided for @librarySearchEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'只有转写过的课和笔记可以被搜索。'**
  String get librarySearchEmptyBody;

  /// No description provided for @librarySearchCount.
  ///
  /// In zh, this message translates to:
  /// **'{length} 条结果'**
  String librarySearchCount(Object length);

  /// No description provided for @libraryNotesCount.
  ///
  /// In zh, this message translates to:
  /// **'笔记 · {length}'**
  String libraryNotesCount(Object length);

  /// No description provided for @libraryNotesEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'在播放器里边看边记，或让助手根据文字稿整理笔记。'**
  String get libraryNotesEmptyHint;

  /// No description provided for @libraryNotesEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这门课还没有笔记。'**
  String get libraryNotesEmpty;

  /// No description provided for @commonUncategorized.
  ///
  /// In zh, this message translates to:
  /// **'未归类'**
  String get commonUncategorized;

  /// No description provided for @libraryStatLocal.
  ///
  /// In zh, this message translates to:
  /// **'节课在本地'**
  String get libraryStatLocal;

  /// No description provided for @libraryStatSegments.
  ///
  /// In zh, this message translates to:
  /// **'句文字稿'**
  String get libraryStatSegments;

  /// No description provided for @libraryLayoutHint.
  ///
  /// In zh, this message translates to:
  /// **'每节课一个文件夹：video.mp4、slides/、courseware/、transcript.md/.srt、lecture.json。根目录的 README.md 说明了结构，方便 AI 工具直接阅读；library.db 是可重建的索引。'**
  String get libraryLayoutHint;

  /// No description provided for @commonOpenFolder.
  ///
  /// In zh, this message translates to:
  /// **'打开文件夹'**
  String get commonOpenFolder;

  /// No description provided for @libraryReindexed.
  ///
  /// In zh, this message translates to:
  /// **'已重建索引，{value} 节课'**
  String libraryReindexed(Object value);

  /// No description provided for @libraryReindexFailed.
  ///
  /// In zh, this message translates to:
  /// **'重建失败：{e}'**
  String libraryReindexFailed(Object e);

  /// No description provided for @libraryReindex.
  ///
  /// In zh, this message translates to:
  /// **'从文件重建索引'**
  String get libraryReindex;

  /// No description provided for @noteDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除这篇笔记？'**
  String get noteDeleteTitle;

  /// No description provided for @noteDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'笔记文件会从课程库中删除。'**
  String get noteDeleteBody;

  /// No description provided for @noteNew.
  ///
  /// In zh, this message translates to:
  /// **'新笔记'**
  String get noteNew;

  /// No description provided for @commonFind.
  ///
  /// In zh, this message translates to:
  /// **'查找'**
  String get commonFind;

  /// No description provided for @commonContents.
  ///
  /// In zh, this message translates to:
  /// **'目录'**
  String get commonContents;

  /// No description provided for @noteOpenLecture.
  ///
  /// In zh, this message translates to:
  /// **'打开对应课次'**
  String get noteOpenLecture;

  /// No description provided for @noteCopiedMarkdown.
  ///
  /// In zh, this message translates to:
  /// **'已复制 Markdown'**
  String get noteCopiedMarkdown;

  /// No description provided for @noteCopyMarkdown.
  ///
  /// In zh, this message translates to:
  /// **'复制 Markdown'**
  String get noteCopyMarkdown;

  /// No description provided for @noteUpdated.
  ///
  /// In zh, this message translates to:
  /// **'· {value}更新'**
  String noteUpdated(Object value);

  /// No description provided for @noteByAssistant.
  ///
  /// In zh, this message translates to:
  /// **'助手整理'**
  String get noteByAssistant;

  /// No description provided for @noteMine.
  ///
  /// In zh, this message translates to:
  /// **'我的笔记'**
  String get noteMine;

  /// No description provided for @noteSlideRef.
  ///
  /// In zh, this message translates to:
  /// **'PPT 第 {slideIdx} 张 · {value}'**
  String noteSlideRef(Object slideIdx, Object value);

  /// No description provided for @noteAudioRef.
  ///
  /// In zh, this message translates to:
  /// **'课堂原声 · {value}'**
  String noteAudioRef(Object value);

  /// No description provided for @noteSlideAt.
  ///
  /// In zh, this message translates to:
  /// **'当时的 PPT · 第 {idx} 张，{value} 起'**
  String noteSlideAt(Object idx, Object value);

  /// No description provided for @notePlayFrom.
  ///
  /// In zh, this message translates to:
  /// **'从 {value} 播放'**
  String notePlayFrom(Object value);

  /// No description provided for @noteNoTranscriptHere.
  ///
  /// In zh, this message translates to:
  /// **'这段没有文字稿'**
  String get noteNoTranscriptHere;

  /// No description provided for @coursewareGone.
  ///
  /// In zh, this message translates to:
  /// **'课件已不存在'**
  String get coursewareGone;

  /// No description provided for @coursewareNotParsed.
  ///
  /// In zh, this message translates to:
  /// **'这个课件还没有解析'**
  String get coursewareNotParsed;

  /// No description provided for @coursewareReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取失败：HTTP {statusCode}'**
  String coursewareReadFailed(Object statusCode);

  /// No description provided for @readerFullscreen.
  ///
  /// In zh, this message translates to:
  /// **'全屏阅读'**
  String get readerFullscreen;

  /// No description provided for @coursewareParsedBy.
  ///
  /// In zh, this message translates to:
  /// **'MinerU 解析{value}'**
  String coursewareParsedBy(Object value);

  /// No description provided for @coursewarePages.
  ///
  /// In zh, this message translates to:
  /// **' · {pages} 页'**
  String coursewarePages(Object pages);

  /// No description provided for @readerOpen.
  ///
  /// In zh, this message translates to:
  /// **'在阅读器中打开'**
  String get readerOpen;

  /// No description provided for @chatNew.
  ///
  /// In zh, this message translates to:
  /// **'新对话'**
  String get chatNew;

  /// No description provided for @modelNone.
  ///
  /// In zh, this message translates to:
  /// **'未选择模型'**
  String get modelNone;

  /// No description provided for @modelsImported.
  ///
  /// In zh, this message translates to:
  /// **'导入了 {value} 个服务商、{value2} 个密钥'**
  String modelsImported(Object value, Object value2);

  /// No description provided for @botDefaultName.
  ///
  /// In zh, this message translates to:
  /// **'小 Look'**
  String get botDefaultName;

  /// No description provided for @chatOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开对话：{e}'**
  String chatOpenFailed(Object e);

  /// No description provided for @scheduleDaily.
  ///
  /// In zh, this message translates to:
  /// **'每天 {value}'**
  String scheduleDaily(Object value);

  /// No description provided for @scheduleWorkdays.
  ///
  /// In zh, this message translates to:
  /// **'工作日 {value}'**
  String scheduleWorkdays(Object value);

  /// No description provided for @scheduleWeekly.
  ///
  /// In zh, this message translates to:
  /// **'每周{value} {value2}'**
  String scheduleWeekly(Object value, Object value2);

  /// No description provided for @scheduleOnce.
  ///
  /// In zh, this message translates to:
  /// **'一次'**
  String get scheduleOnce;

  /// No description provided for @scheduleOnceAt.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日 {value}（一次）'**
  String scheduleOnceAt(Object month, Object day, Object value);

  /// No description provided for @commonToday.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get commonToday;

  /// No description provided for @commonTomorrow.
  ///
  /// In zh, this message translates to:
  /// **'明天'**
  String get commonTomorrow;

  /// No description provided for @commonYesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天'**
  String get commonYesterday;

  /// No description provided for @commonFinished.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get commonFinished;

  /// No description provided for @runCostLimit.
  ///
  /// In zh, this message translates to:
  /// **'超出费用上限'**
  String get runCostLimit;

  /// No description provided for @runAborted.
  ///
  /// In zh, this message translates to:
  /// **'已中止'**
  String get runAborted;

  /// No description provided for @runMissed.
  ///
  /// In zh, this message translates to:
  /// **'已错过'**
  String get runMissed;

  /// No description provided for @tasksBusy.
  ///
  /// In zh, this message translates to:
  /// **'助手正在回复，请稍后再查看'**
  String get tasksBusy;

  /// No description provided for @tasksSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'按计划在新对话里复盘、出题、汇总截止事项'**
  String get tasksSubtitle;

  /// No description provided for @tasksCount.
  ///
  /// In zh, this message translates to:
  /// **'{length} 个任务'**
  String tasksCount(Object length);

  /// No description provided for @commonAllEnabled.
  ///
  /// In zh, this message translates to:
  /// **'全部启用'**
  String get commonAllEnabled;

  /// No description provided for @tasksEnabledCount.
  ///
  /// In zh, this message translates to:
  /// **'{length} 个启用'**
  String tasksEnabledCount(Object length);

  /// No description provided for @tasksNextUp.
  ///
  /// In zh, this message translates to:
  /// **'下一个「{value}」{value2}'**
  String tasksNextUp(Object value, Object value2);

  /// No description provided for @tasksNew.
  ///
  /// In zh, this message translates to:
  /// **'新建任务'**
  String get tasksNew;

  /// No description provided for @commonScheduledTasks.
  ///
  /// In zh, this message translates to:
  /// **'定时任务'**
  String get commonScheduledTasks;

  /// No description provided for @tasksRuns.
  ///
  /// In zh, this message translates to:
  /// **'运行记录'**
  String get tasksRuns;

  /// No description provided for @tasksRunsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'任务运行后，结果会按时间出现在这里'**
  String get tasksRunsEmpty;

  /// No description provided for @tasksRunsNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'没有符合条件的运行'**
  String get tasksRunsNoMatch;

  /// No description provided for @tasksWorkdays.
  ///
  /// In zh, this message translates to:
  /// **'工作日'**
  String get tasksWorkdays;

  /// No description provided for @commonRunning.
  ///
  /// In zh, this message translates to:
  /// **'运行中'**
  String get commonRunning;

  /// No description provided for @commonEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get commonEnabled;

  /// No description provided for @tasksRunningNow.
  ///
  /// In zh, this message translates to:
  /// **'正在运行'**
  String get tasksRunningNow;

  /// No description provided for @tasksNoNextRun.
  ///
  /// In zh, this message translates to:
  /// **'没有下次运行'**
  String get tasksNoNextRun;

  /// No description provided for @tasksNextRun.
  ///
  /// In zh, this message translates to:
  /// **'下次 {value}'**
  String tasksNextRun(Object value);

  /// No description provided for @tasksNotFound.
  ///
  /// In zh, this message translates to:
  /// **'任务不存在'**
  String get tasksNotFound;

  /// No description provided for @tasksDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除任务？'**
  String get tasksDeleteTitle;

  /// No description provided for @tasksDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'以后不会再运行。已经生成的对话、笔记和练习会保留，运行记录仍可在「运行记录」里查看。'**
  String get tasksDeleteBody;

  /// No description provided for @commonEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用'**
  String get commonEnable;

  /// No description provided for @tasksStarted.
  ///
  /// In zh, this message translates to:
  /// **'已开始运行'**
  String get tasksStarted;

  /// No description provided for @tasksRunNow.
  ///
  /// In zh, this message translates to:
  /// **'立即运行'**
  String get tasksRunNow;

  /// No description provided for @tasksNextRunLabel.
  ///
  /// In zh, this message translates to:
  /// **'下次运行'**
  String get tasksNextRunLabel;

  /// No description provided for @commonNone.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get commonNone;

  /// No description provided for @tasksLastResult.
  ///
  /// In zh, this message translates to:
  /// **'上次结果'**
  String get tasksLastResult;

  /// No description provided for @tasksNeverRun.
  ///
  /// In zh, this message translates to:
  /// **'还没运行'**
  String get tasksNeverRun;

  /// No description provided for @tasksCostLimitCatchUp.
  ///
  /// In zh, this message translates to:
  /// **'单次上限 · 补跑'**
  String get tasksCostLimitCatchUp;

  /// No description provided for @tasksCostLimit.
  ///
  /// In zh, this message translates to:
  /// **'单次上限'**
  String get tasksCostLimit;

  /// No description provided for @tasksReadOnly.
  ///
  /// In zh, this message translates to:
  /// **'只读：结果写在总结里，不改动课程库'**
  String get tasksReadOnly;

  /// No description provided for @tasksAllowed.
  ///
  /// In zh, this message translates to:
  /// **'允许：{value}'**
  String tasksAllowed(Object value);

  /// No description provided for @tasksPrompt.
  ///
  /// In zh, this message translates to:
  /// **'任务内容'**
  String get tasksPrompt;

  /// No description provided for @tasksRecentRuns.
  ///
  /// In zh, this message translates to:
  /// **'最近 {length} 次'**
  String tasksRecentRuns(Object length);

  /// No description provided for @tasksNoRunsYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有运行过。可以点「立即运行」先试一次。'**
  String get tasksNoRunsYet;

  /// No description provided for @durationSeconds.
  ///
  /// In zh, this message translates to:
  /// **'{secs} 秒'**
  String durationSeconds(Object secs);

  /// No description provided for @durationMinutesSeconds.
  ///
  /// In zh, this message translates to:
  /// **'{value} 分 {value2} 秒'**
  String durationMinutesSeconds(Object value, Object value2);

  /// No description provided for @tasksManualSuffix.
  ///
  /// In zh, this message translates to:
  /// **' · 手动'**
  String get tasksManualSuffix;

  /// No description provided for @tasksDeletedTask.
  ///
  /// In zh, this message translates to:
  /// **'已删除的任务'**
  String get tasksDeletedTask;

  /// No description provided for @tasksDeletedSuffix.
  ///
  /// In zh, this message translates to:
  /// **'（已删除）'**
  String get tasksDeletedSuffix;

  /// No description provided for @commonNewBadge.
  ///
  /// In zh, this message translates to:
  /// **'新'**
  String get commonNewBadge;

  /// No description provided for @tasksIntroTitle.
  ///
  /// In zh, this message translates to:
  /// **'让助手按计划替你做事'**
  String get tasksIntroTitle;

  /// No description provided for @tasksIntroBody.
  ///
  /// In zh, this message translates to:
  /// **'每次运行都会开一个新对话，结果可在「运行记录」里查看。任务只在 Look Studio 打开时执行；错过的时间可以在 12 小时内启动时补跑。'**
  String get tasksIntroBody;

  /// No description provided for @tasksFromBlank.
  ///
  /// In zh, this message translates to:
  /// **'从空白开始'**
  String get tasksFromBlank;

  /// No description provided for @tasksWriteNotes.
  ///
  /// In zh, this message translates to:
  /// **'保存笔记与大纲'**
  String get tasksWriteNotes;

  /// No description provided for @tasksWriteSchedule.
  ///
  /// In zh, this message translates to:
  /// **'标记与修改日程'**
  String get tasksWriteSchedule;

  /// No description provided for @tasksWriteQuizzes.
  ///
  /// In zh, this message translates to:
  /// **'创建练习'**
  String get tasksWriteQuizzes;

  /// No description provided for @taskTemplateReviewName.
  ///
  /// In zh, this message translates to:
  /// **'每晚复盘今天的课'**
  String get taskTemplateReviewName;

  /// No description provided for @taskTemplateReviewPrompt.
  ///
  /// In zh, this message translates to:
  /// **'看看今天有哪些课的转写已经完成，为每节课写一份简明的复盘笔记并保存：核心概念、关键公式与例题、老师强调的要点，附时间戳。没有新课就简单说明。'**
  String get taskTemplateReviewPrompt;

  /// No description provided for @taskTemplateQuizName.
  ///
  /// In zh, this message translates to:
  /// **'每周一出一组复习题'**
  String get taskTemplateQuizName;

  /// No description provided for @taskTemplateQuizPrompt.
  ///
  /// In zh, this message translates to:
  /// **'回顾上周转写过的课程，为每门课出一组 10 道中等难度的选择题并保存为练习，重点覆盖上周的新内容。'**
  String get taskTemplateQuizPrompt;

  /// No description provided for @taskTemplateDeadlinesName.
  ///
  /// In zh, this message translates to:
  /// **'每天早上汇总近期截止'**
  String get taskTemplateDeadlinesName;

  /// No description provided for @taskTemplateDeadlinesPrompt.
  ///
  /// In zh, this message translates to:
  /// **'列出今天起 7 天内的作业、考试和截止事项，按日期排序，提醒最紧急的两件；如果有已经过期但没完成的也指出来。'**
  String get taskTemplateDeadlinesPrompt;

  /// No description provided for @tasksNewTitle.
  ///
  /// In zh, this message translates to:
  /// **'新建定时任务'**
  String get tasksNewTitle;

  /// No description provided for @tasksEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑定时任务'**
  String get tasksEditTitle;

  /// No description provided for @commonName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get commonName;

  /// No description provided for @tasksPromptLabel.
  ///
  /// In zh, this message translates to:
  /// **'让助手做什么'**
  String get tasksPromptLabel;

  /// No description provided for @commonTime.
  ///
  /// In zh, this message translates to:
  /// **'时间'**
  String get commonTime;

  /// No description provided for @commonDaily.
  ///
  /// In zh, this message translates to:
  /// **'每天'**
  String get commonDaily;

  /// No description provided for @commonWeekly.
  ///
  /// In zh, this message translates to:
  /// **'每周'**
  String get commonWeekly;

  /// No description provided for @tasksAllowLabel.
  ///
  /// In zh, this message translates to:
  /// **'允许它'**
  String get tasksAllowLabel;

  /// No description provided for @tasksAllowHint.
  ///
  /// In zh, this message translates to:
  /// **'运行时只允许勾选的写入；都不选则只读，结果写在总结里。任务读到的转写稿、课件等资料不能让它做别的修改。'**
  String get tasksAllowHint;

  /// No description provided for @tasksLimits.
  ///
  /// In zh, this message translates to:
  /// **'限制'**
  String get tasksLimits;

  /// No description provided for @tasksCostLimitLabel.
  ///
  /// In zh, this message translates to:
  /// **'单次费用上限'**
  String get tasksCostLimitLabel;

  /// No description provided for @tasksCostLimitHelper.
  ///
  /// In zh, this message translates to:
  /// **'超过后中止这次运行（按模型价格估算）'**
  String get tasksCostLimitHelper;

  /// No description provided for @tasksCatchUp.
  ///
  /// In zh, this message translates to:
  /// **'错过时补跑'**
  String get tasksCatchUp;

  /// No description provided for @tasksCatchUpHint.
  ///
  /// In zh, this message translates to:
  /// **'应用在计划时间未运行时，12 小时内启动会补跑一次'**
  String get tasksCatchUpHint;

  /// No description provided for @tasksRunReason.
  ///
  /// In zh, this message translates to:
  /// **'：{value}'**
  String tasksRunReason(Object value);

  /// No description provided for @tasksRunNotice.
  ///
  /// In zh, this message translates to:
  /// **'定时任务「{value}」{label}{why}'**
  String tasksRunNotice(Object value, Object label, Object why);

  /// No description provided for @commonView.
  ///
  /// In zh, this message translates to:
  /// **'查看'**
  String get commonView;

  /// No description provided for @runtimeReady.
  ///
  /// In zh, this message translates to:
  /// **'运行环境已就绪'**
  String get runtimeReady;

  /// No description provided for @runtimeInstallTitle.
  ///
  /// In zh, this message translates to:
  /// **'安装助手运行环境'**
  String get runtimeInstallTitle;

  /// No description provided for @runtimeIntro.
  ///
  /// In zh, this message translates to:
  /// **'助手运行在 Node.js 上，并使用 Pi SDK。缺少的部分会安装到 Look Studio 的数据目录，不改动系统；安装包会按官方发布的 SHA-256 校验。'**
  String get runtimeIntro;

  /// No description provided for @runtimeReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取运行环境：{error}'**
  String runtimeReadFailed(Object error);

  /// No description provided for @runtimeSourceManaged.
  ///
  /// In zh, this message translates to:
  /// **'应用内安装'**
  String get runtimeSourceManaged;

  /// No description provided for @runtimeSourceSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get runtimeSourceSystem;

  /// No description provided for @runtimeNodeMissing.
  ///
  /// In zh, this message translates to:
  /// **'未找到可用的 Node.js 22+'**
  String get runtimeNodeMissing;

  /// No description provided for @runtimeDeps.
  ///
  /// In zh, this message translates to:
  /// **'助手依赖（Pi SDK）'**
  String get runtimeDeps;

  /// No description provided for @commonInstalled.
  ///
  /// In zh, this message translates to:
  /// **'已安装'**
  String get commonInstalled;

  /// No description provided for @commonNotInstalled.
  ///
  /// In zh, this message translates to:
  /// **'未安装'**
  String get commonNotInstalled;

  /// No description provided for @runtimeInstallDeps.
  ///
  /// In zh, this message translates to:
  /// **'安装依赖'**
  String get runtimeInstallDeps;

  /// No description provided for @runtimeStartAssistant.
  ///
  /// In zh, this message translates to:
  /// **'启动助手'**
  String get runtimeStartAssistant;

  /// No description provided for @runtimeStarting.
  ///
  /// In zh, this message translates to:
  /// **'正在启动…'**
  String get runtimeStarting;

  /// No description provided for @runtimeStartsAfterInstall.
  ///
  /// In zh, this message translates to:
  /// **'安装完成后自动启动'**
  String get runtimeStartsAfterInstall;

  /// No description provided for @commonMirror.
  ///
  /// In zh, this message translates to:
  /// **'下载源'**
  String get commonMirror;

  /// No description provided for @runtimeMirrorChina.
  ///
  /// In zh, this message translates to:
  /// **'国内镜像'**
  String get runtimeMirrorChina;

  /// No description provided for @runtimeMirrorOfficial.
  ///
  /// In zh, this message translates to:
  /// **'官方源'**
  String get runtimeMirrorOfficial;

  /// No description provided for @runtimeInstallLog.
  ///
  /// In zh, this message translates to:
  /// **'安装日志'**
  String get runtimeInstallLog;

  /// No description provided for @runtimeRecheck.
  ///
  /// In zh, this message translates to:
  /// **'重新检查'**
  String get runtimeRecheck;

  /// No description provided for @runtimeInstalling.
  ///
  /// In zh, this message translates to:
  /// **'正在安装'**
  String get runtimeInstalling;

  /// No description provided for @runtimeInstall.
  ///
  /// In zh, this message translates to:
  /// **'开始安装'**
  String get runtimeInstall;

  /// No description provided for @commonLecture.
  ///
  /// In zh, this message translates to:
  /// **'课次'**
  String get commonLecture;

  /// No description provided for @commonPlugins.
  ///
  /// In zh, this message translates to:
  /// **'插件'**
  String get commonPlugins;

  /// No description provided for @commonSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get commonSettings;

  /// No description provided for @commonUsage.
  ///
  /// In zh, this message translates to:
  /// **'用量'**
  String get commonUsage;

  /// No description provided for @botOpened.
  ///
  /// In zh, this message translates to:
  /// **'已打开 {value}'**
  String botOpened(Object value);

  /// No description provided for @botResumed.
  ///
  /// In zh, this message translates to:
  /// **'已继续播放'**
  String get botResumed;

  /// No description provided for @botPaused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停播放'**
  String get botPaused;

  /// No description provided for @botSeeked.
  ///
  /// In zh, this message translates to:
  /// **'已跳转'**
  String get botSeeked;

  /// No description provided for @botRateSet.
  ///
  /// In zh, this message translates to:
  /// **'已调到 {value}×'**
  String botRateSet(Object value);

  /// No description provided for @commonUndone.
  ///
  /// In zh, this message translates to:
  /// **'已撤销'**
  String get commonUndone;

  /// No description provided for @proposalApplied.
  ///
  /// In zh, this message translates to:
  /// **'已应用'**
  String get proposalApplied;

  /// No description provided for @proposalIgnored.
  ///
  /// In zh, this message translates to:
  /// **'已忽略'**
  String get proposalIgnored;

  /// No description provided for @proposalExpired.
  ///
  /// In zh, this message translates to:
  /// **'已过期，请让助手重新生成'**
  String get proposalExpired;

  /// No description provided for @proposalFailed.
  ///
  /// In zh, this message translates to:
  /// **'执行失败'**
  String get proposalFailed;

  /// No description provided for @proposalPending.
  ///
  /// In zh, this message translates to:
  /// **'等你确认'**
  String get proposalPending;

  /// No description provided for @commonIgnore.
  ///
  /// In zh, this message translates to:
  /// **'忽略'**
  String get commonIgnore;

  /// No description provided for @commonApply.
  ///
  /// In zh, this message translates to:
  /// **'应用'**
  String get commonApply;

  /// No description provided for @memoryAboutYou.
  ///
  /// In zh, this message translates to:
  /// **'关于你'**
  String get memoryAboutYou;

  /// No description provided for @memoryPreferences.
  ///
  /// In zh, this message translates to:
  /// **'偏好'**
  String get memoryPreferences;

  /// No description provided for @memoryRoutines.
  ///
  /// In zh, this message translates to:
  /// **'做法'**
  String get memoryRoutines;

  /// No description provided for @commonOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get commonOther;

  /// No description provided for @botSectionLook.
  ///
  /// In zh, this message translates to:
  /// **'形象'**
  String get botSectionLook;

  /// No description provided for @botName.
  ///
  /// In zh, this message translates to:
  /// **'名字'**
  String get botName;

  /// No description provided for @commonColor.
  ///
  /// In zh, this message translates to:
  /// **'颜色'**
  String get commonColor;

  /// No description provided for @botSectionPersona.
  ///
  /// In zh, this message translates to:
  /// **'相处方式'**
  String get botSectionPersona;

  /// No description provided for @botPersonaHint.
  ///
  /// In zh, this message translates to:
  /// **'比如：说话轻松一点，先给结论；复习时多出几道题考我。'**
  String get botPersonaHint;

  /// No description provided for @botSectionMemory.
  ///
  /// In zh, this message translates to:
  /// **'记忆'**
  String get botSectionMemory;

  /// No description provided for @memoryAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加记忆'**
  String get memoryAdd;

  /// No description provided for @memoryConsolidating.
  ///
  /// In zh, this message translates to:
  /// **'正在沉淀'**
  String get memoryConsolidating;

  /// No description provided for @memoryConsolidateNow.
  ///
  /// In zh, this message translates to:
  /// **'立即沉淀'**
  String get memoryConsolidateNow;

  /// No description provided for @memoryIntro.
  ///
  /// In zh, this message translates to:
  /// **'{botName} 会把你说过的、反复用到的做法整理成记忆文件，每次对话都会带上「关于你」和「偏好」。这些文件只保存在本机，不会记下密码、证件号、银行卡号、手机号和密钥。'**
  String memoryIntro(Object botName);

  /// No description provided for @memoryReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取记忆失败：{value}'**
  String memoryReadFailed(Object value);

  /// No description provided for @memoryRuns.
  ///
  /// In zh, this message translates to:
  /// **'沉淀记录'**
  String get memoryRuns;

  /// No description provided for @memoryRunsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有沉淀过。对话结束两分钟后会自动整理。'**
  String get memoryRunsEmpty;

  /// No description provided for @memoryAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动沉淀'**
  String get memoryAuto;

  /// No description provided for @memoryAutoHint.
  ///
  /// In zh, this message translates to:
  /// **'对话停下两分钟、或攒够六轮后，在后台整理记忆'**
  String get memoryAutoHint;

  /// No description provided for @memoryFromCourses.
  ///
  /// In zh, this message translates to:
  /// **'从课程会话中学习'**
  String get memoryFromCourses;

  /// No description provided for @memoryFromCoursesHint.
  ///
  /// In zh, this message translates to:
  /// **'课程助手里的对话也参与沉淀'**
  String get memoryFromCoursesHint;

  /// No description provided for @botRestartTitle.
  ///
  /// In zh, this message translates to:
  /// **'重新开始对话？'**
  String get botRestartTitle;

  /// No description provided for @botRestartBody.
  ///
  /// In zh, this message translates to:
  /// **'{botName} 的对话会从头开始，记忆保留。'**
  String botRestartBody(Object botName);

  /// No description provided for @botRestart.
  ///
  /// In zh, this message translates to:
  /// **'重新开始'**
  String get botRestart;

  /// No description provided for @botRestartChat.
  ///
  /// In zh, this message translates to:
  /// **'重新开始对话'**
  String get botRestartChat;

  /// No description provided for @botMoodLabel.
  ///
  /// In zh, this message translates to:
  /// **'{botName}，{value}'**
  String botMoodLabel(Object botName, Object value);

  /// No description provided for @memoryEmptyShort.
  ///
  /// In zh, this message translates to:
  /// **'还没有记忆'**
  String get memoryEmptyShort;

  /// No description provided for @memoryCount.
  ///
  /// In zh, this message translates to:
  /// **'记得 {length} 件事'**
  String memoryCount(Object length);

  /// No description provided for @memoryWorking.
  ///
  /// In zh, this message translates to:
  /// **'正在整理记忆'**
  String get memoryWorking;

  /// No description provided for @memoryLastRun.
  ///
  /// In zh, this message translates to:
  /// **'上次沉淀 {value}'**
  String memoryLastRun(Object value);

  /// No description provided for @memoryWhen.
  ///
  /// In zh, this message translates to:
  /// **'适用：{when}'**
  String memoryWhen(Object when);

  /// No description provided for @memoryDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除这条记忆？'**
  String get memoryDeleteTitle;

  /// No description provided for @memoryDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'「{title}」会被忘掉，之后的对话不再用到。'**
  String memoryDeleteBody(Object title);

  /// No description provided for @memoryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有记忆。和 {name} 聊聊你的专业、学习习惯，或者直接说「记住……」。'**
  String memoryEmpty(Object name);

  /// No description provided for @memoryRunChanged.
  ///
  /// In zh, this message translates to:
  /// **'整理了 {length} 处'**
  String memoryRunChanged(Object length);

  /// No description provided for @memoryRunUnfinished.
  ///
  /// In zh, this message translates to:
  /// **'没有完成'**
  String get memoryRunUnfinished;

  /// No description provided for @memoryRunNothing.
  ///
  /// In zh, this message translates to:
  /// **'没有需要记的'**
  String get memoryRunNothing;

  /// No description provided for @memoryRunScope.
  ///
  /// In zh, this message translates to:
  /// **'{value} 个对话 {value2} 轮'**
  String memoryRunScope(Object value, Object value2);

  /// No description provided for @memoryUpdated.
  ///
  /// In zh, this message translates to:
  /// **'更新'**
  String get memoryUpdated;

  /// No description provided for @memoryAppended.
  ///
  /// In zh, this message translates to:
  /// **'追加'**
  String get memoryAppended;

  /// No description provided for @memoryFileNameInvalid.
  ///
  /// In zh, this message translates to:
  /// **'名称只能用小写字母、数字、- 和 _'**
  String get memoryFileNameInvalid;

  /// No description provided for @memoryFileName.
  ///
  /// In zh, this message translates to:
  /// **'文件名'**
  String get memoryFileName;

  /// No description provided for @memoryFileHint.
  ///
  /// In zh, this message translates to:
  /// **'---\ntitle: 标题\ndescription: 一句话说明\n---\n内容'**
  String get memoryFileHint;

  /// No description provided for @commonSaving.
  ///
  /// In zh, this message translates to:
  /// **'保存中…'**
  String get commonSaving;

  /// No description provided for @botMoodIdle.
  ///
  /// In zh, this message translates to:
  /// **'在这儿'**
  String get botMoodIdle;

  /// No description provided for @botMoodListening.
  ///
  /// In zh, this message translates to:
  /// **'在听'**
  String get botMoodListening;

  /// No description provided for @botMoodThinking.
  ///
  /// In zh, this message translates to:
  /// **'在想'**
  String get botMoodThinking;

  /// No description provided for @botMoodWorking.
  ///
  /// In zh, this message translates to:
  /// **'在做事'**
  String get botMoodWorking;

  /// No description provided for @botMoodTalking.
  ///
  /// In zh, this message translates to:
  /// **'在说'**
  String get botMoodTalking;

  /// No description provided for @botMoodHappy.
  ///
  /// In zh, this message translates to:
  /// **'完成了'**
  String get botMoodHappy;

  /// No description provided for @botMoodConfused.
  ///
  /// In zh, this message translates to:
  /// **'出了点问题'**
  String get botMoodConfused;

  /// No description provided for @botMoodDreaming.
  ///
  /// In zh, this message translates to:
  /// **'在整理记忆'**
  String get botMoodDreaming;

  /// No description provided for @botMoodNotify.
  ///
  /// In zh, this message translates to:
  /// **'有卡片等你确认'**
  String get botMoodNotify;

  /// No description provided for @botAccessoryAntenna.
  ///
  /// In zh, this message translates to:
  /// **'天线'**
  String get botAccessoryAntenna;

  /// No description provided for @botAccessoryCatEars.
  ///
  /// In zh, this message translates to:
  /// **'猫耳'**
  String get botAccessoryCatEars;

  /// No description provided for @botAccessorySprout.
  ///
  /// In zh, this message translates to:
  /// **'豆芽'**
  String get botAccessorySprout;

  /// No description provided for @botAccessoryBunnyEars.
  ///
  /// In zh, this message translates to:
  /// **'兔耳'**
  String get botAccessoryBunnyEars;

  /// No description provided for @botAccessoryFeelers.
  ///
  /// In zh, this message translates to:
  /// **'触角'**
  String get botAccessoryFeelers;

  /// No description provided for @botAccessoryHeadphones.
  ///
  /// In zh, this message translates to:
  /// **'耳机'**
  String get botAccessoryHeadphones;

  /// No description provided for @botAccessoryDrop.
  ///
  /// In zh, this message translates to:
  /// **'水滴'**
  String get botAccessoryDrop;

  /// No description provided for @botAccessoryGhost.
  ///
  /// In zh, this message translates to:
  /// **'小幽灵'**
  String get botAccessoryGhost;

  /// No description provided for @commonFollowTheme.
  ///
  /// In zh, this message translates to:
  /// **'跟随主题'**
  String get commonFollowTheme;

  /// No description provided for @toolHelp.
  ///
  /// In zh, this message translates to:
  /// **'查阅功能说明'**
  String get toolHelp;

  /// No description provided for @toolCurrentContext.
  ///
  /// In zh, this message translates to:
  /// **'读取当前界面'**
  String get toolCurrentContext;

  /// No description provided for @toolListCourses.
  ///
  /// In zh, this message translates to:
  /// **'查看课程'**
  String get toolListCourses;

  /// No description provided for @toolListLectures.
  ///
  /// In zh, this message translates to:
  /// **'查看课次'**
  String get toolListLectures;

  /// No description provided for @toolReadTranscript.
  ///
  /// In zh, this message translates to:
  /// **'阅读文字稿'**
  String get toolReadTranscript;

  /// No description provided for @toolLectureDetail.
  ///
  /// In zh, this message translates to:
  /// **'查看课次详情'**
  String get toolLectureDetail;

  /// No description provided for @toolSearchLibrary.
  ///
  /// In zh, this message translates to:
  /// **'搜索课程库'**
  String get toolSearchLibrary;

  /// No description provided for @toolListNotes.
  ///
  /// In zh, this message translates to:
  /// **'查看笔记'**
  String get toolListNotes;

  /// No description provided for @toolReadNote.
  ///
  /// In zh, this message translates to:
  /// **'阅读笔记'**
  String get toolReadNote;

  /// No description provided for @toolSaveNote.
  ///
  /// In zh, this message translates to:
  /// **'保存笔记'**
  String get toolSaveNote;

  /// No description provided for @toolPrepare.
  ///
  /// In zh, this message translates to:
  /// **'准备操作'**
  String get toolPrepare;

  /// No description provided for @toolFindTools.
  ///
  /// In zh, this message translates to:
  /// **'加载工具'**
  String get toolFindTools;

  /// No description provided for @toolMarkSchedule.
  ///
  /// In zh, this message translates to:
  /// **'标记日程'**
  String get toolMarkSchedule;

  /// No description provided for @toolListSchedule.
  ///
  /// In zh, this message translates to:
  /// **'查看日程'**
  String get toolListSchedule;

  /// No description provided for @toolEditSchedule.
  ///
  /// In zh, this message translates to:
  /// **'修改日程'**
  String get toolEditSchedule;

  /// No description provided for @toolReadOutline.
  ///
  /// In zh, this message translates to:
  /// **'读取大纲'**
  String get toolReadOutline;

  /// No description provided for @toolSaveOutline.
  ///
  /// In zh, this message translates to:
  /// **'保存大纲'**
  String get toolSaveOutline;

  /// No description provided for @toolListCourseware.
  ///
  /// In zh, this message translates to:
  /// **'查看课件'**
  String get toolListCourseware;

  /// No description provided for @toolReadCourseware.
  ///
  /// In zh, this message translates to:
  /// **'阅读课件'**
  String get toolReadCourseware;

  /// No description provided for @toolSearchCourseware.
  ///
  /// In zh, this message translates to:
  /// **'搜索课件'**
  String get toolSearchCourseware;

  /// No description provided for @toolListSlides.
  ///
  /// In zh, this message translates to:
  /// **'查看 PPT'**
  String get toolListSlides;

  /// No description provided for @toolViewImage.
  ///
  /// In zh, this message translates to:
  /// **'查看插图'**
  String get toolViewImage;

  /// No description provided for @toolCreateQuiz.
  ///
  /// In zh, this message translates to:
  /// **'生成练习'**
  String get toolCreateQuiz;

  /// No description provided for @toolListQuizzes.
  ///
  /// In zh, this message translates to:
  /// **'查看练习'**
  String get toolListQuizzes;

  /// No description provided for @toolReadAttempts.
  ///
  /// In zh, this message translates to:
  /// **'查看作答'**
  String get toolReadAttempts;

  /// No description provided for @toolOpenPage.
  ///
  /// In zh, this message translates to:
  /// **'打开页面'**
  String get toolOpenPage;

  /// No description provided for @toolControlPlayer.
  ///
  /// In zh, this message translates to:
  /// **'控制播放'**
  String get toolControlPlayer;

  /// No description provided for @toolReadSettings.
  ///
  /// In zh, this message translates to:
  /// **'读取设置'**
  String get toolReadSettings;

  /// No description provided for @toolChangeSettings.
  ///
  /// In zh, this message translates to:
  /// **'调整设置'**
  String get toolChangeSettings;

  /// No description provided for @toolManageDownloads.
  ///
  /// In zh, this message translates to:
  /// **'管理下载'**
  String get toolManageDownloads;

  /// No description provided for @toolListDownloads.
  ///
  /// In zh, this message translates to:
  /// **'查看下载'**
  String get toolListDownloads;

  /// No description provided for @toolDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get toolDownload;

  /// No description provided for @toolPrepareDelete.
  ///
  /// In zh, this message translates to:
  /// **'准备删除文件'**
  String get toolPrepareDelete;

  /// No description provided for @toolOrganizeCourses.
  ///
  /// In zh, this message translates to:
  /// **'整理课程'**
  String get toolOrganizeCourses;

  /// No description provided for @toolSyncCourses.
  ///
  /// In zh, this message translates to:
  /// **'同步课程'**
  String get toolSyncCourses;

  /// No description provided for @toolCreateTask.
  ///
  /// In zh, this message translates to:
  /// **'创建定时任务'**
  String get toolCreateTask;

  /// No description provided for @toolTogglePlugin.
  ///
  /// In zh, this message translates to:
  /// **'开关插件'**
  String get toolTogglePlugin;

  /// No description provided for @toolListMemory.
  ///
  /// In zh, this message translates to:
  /// **'翻看记忆'**
  String get toolListMemory;

  /// No description provided for @toolRecall.
  ///
  /// In zh, this message translates to:
  /// **'回想'**
  String get toolRecall;

  /// No description provided for @toolRemember.
  ///
  /// In zh, this message translates to:
  /// **'记下来'**
  String get toolRemember;

  /// No description provided for @toolEditMemory.
  ///
  /// In zh, this message translates to:
  /// **'改记忆'**
  String get toolEditMemory;

  /// No description provided for @toolForget.
  ///
  /// In zh, this message translates to:
  /// **'忘掉'**
  String get toolForget;

  /// No description provided for @botNoLecture.
  ///
  /// In zh, this message translates to:
  /// **'没有指明要打开哪一节课'**
  String get botNoLecture;

  /// No description provided for @botNoCourse.
  ///
  /// In zh, this message translates to:
  /// **'没有指明要打开哪门课'**
  String get botNoCourse;

  /// No description provided for @botNoNote.
  ///
  /// In zh, this message translates to:
  /// **'没有指明要打开哪篇笔记'**
  String get botNoNote;

  /// No description provided for @botNoDownload.
  ///
  /// In zh, this message translates to:
  /// **'没有指明要下载哪一节课'**
  String get botNoDownload;

  /// No description provided for @botUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'这个版本还不支持该操作'**
  String get botUnsupported;

  /// No description provided for @chatSessions.
  ///
  /// In zh, this message translates to:
  /// **'会话'**
  String get chatSessions;

  /// No description provided for @chatNewSession.
  ///
  /// In zh, this message translates to:
  /// **'新会话'**
  String get chatNewSession;

  /// No description provided for @commonCollapse.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get commonCollapse;

  /// No description provided for @chatAllSessions.
  ///
  /// In zh, this message translates to:
  /// **'全部会话'**
  String get chatAllSessions;

  /// No description provided for @chatOtherSessions.
  ///
  /// In zh, this message translates to:
  /// **'其他对话'**
  String get chatOtherSessions;

  /// No description provided for @chatNoSessions.
  ///
  /// In zh, this message translates to:
  /// **'还没有会话'**
  String get chatNoSessions;

  /// No description provided for @chatSessionMeta.
  ///
  /// In zh, this message translates to:
  /// **'{value} · {messages} 条'**
  String chatSessionMeta(Object value, Object messages);

  /// No description provided for @assistantStarting.
  ///
  /// In zh, this message translates to:
  /// **'正在启动助手'**
  String get assistantStarting;

  /// No description provided for @assistantNotStarted.
  ///
  /// In zh, this message translates to:
  /// **'助手没有启动'**
  String get assistantNotStarted;

  /// No description provided for @assistantSetupModel.
  ///
  /// In zh, this message translates to:
  /// **'先配置一个模型'**
  String get assistantSetupModel;

  /// No description provided for @assistantSetupModelBody.
  ///
  /// In zh, this message translates to:
  /// **'助手通过 Pi SDK 调用你自己的模型服务。填入 API Key，或导入 Pi CLI 的配置。'**
  String get assistantSetupModelBody;

  /// No description provided for @assistantSetupModelAction.
  ///
  /// In zh, this message translates to:
  /// **'配置模型'**
  String get assistantSetupModelAction;

  /// No description provided for @suggestSpeed.
  ///
  /// In zh, this message translates to:
  /// **'把播放速度调到 1.5 倍'**
  String get suggestSpeed;

  /// No description provided for @suggestDownloadRecent.
  ///
  /// In zh, this message translates to:
  /// **'下载这门课最近三节的视频和转写'**
  String get suggestDownloadRecent;

  /// No description provided for @suggestBiggerText.
  ///
  /// In zh, this message translates to:
  /// **'把界面字号调大一点'**
  String get suggestBiggerText;

  /// No description provided for @suggestRemember.
  ///
  /// In zh, this message translates to:
  /// **'记住：我更喜欢先给结论的简短回答'**
  String get suggestRemember;

  /// No description provided for @suggestWeeklyReview.
  ///
  /// In zh, this message translates to:
  /// **'每周日晚上帮我复习本周的课'**
  String get suggestWeeklyReview;

  /// No description provided for @suggestPauseDownloads.
  ///
  /// In zh, this message translates to:
  /// **'暂停所有下载'**
  String get suggestPauseDownloads;

  /// No description provided for @suggestSummarizeLecture.
  ///
  /// In zh, this message translates to:
  /// **'总结这节课到目前为止讲了什么'**
  String get suggestSummarizeLecture;

  /// No description provided for @suggestReviewNotes.
  ///
  /// In zh, this message translates to:
  /// **'把这节课整理成一份复习笔记'**
  String get suggestReviewNotes;

  /// No description provided for @suggestConceptElsewhere.
  ///
  /// In zh, this message translates to:
  /// **'刚才提到的概念在哪些课里出现过？'**
  String get suggestConceptElsewhere;

  /// No description provided for @suggestCourseRecent.
  ///
  /// In zh, this message translates to:
  /// **'这门课最近几节讲了什么？'**
  String get suggestCourseRecent;

  /// No description provided for @suggestUnwatched.
  ///
  /// In zh, this message translates to:
  /// **'帮我挑出还没看的课'**
  String get suggestUnwatched;

  /// No description provided for @suggestQuizCourse.
  ///
  /// In zh, this message translates to:
  /// **'出一组题考考我这门课的重点'**
  String get suggestQuizCourse;

  /// No description provided for @suggestWhatCanYouDo.
  ///
  /// In zh, this message translates to:
  /// **'这个 App 能帮我做什么？'**
  String get suggestWhatCanYouDo;

  /// No description provided for @suggestRecentUnwatched.
  ///
  /// In zh, this message translates to:
  /// **'最近有哪些课还没看？'**
  String get suggestRecentUnwatched;

  /// No description provided for @suggestSearchMidterm.
  ///
  /// In zh, this message translates to:
  /// **'在我的课程库里搜索「期中」'**
  String get suggestSearchMidterm;

  /// No description provided for @botIntroTitle.
  ///
  /// In zh, this message translates to:
  /// **'我是 {botName}'**
  String botIntroTitle(Object botName);

  /// No description provided for @botIntroBody.
  ///
  /// In zh, this message translates to:
  /// **'我会记住你告诉我的事，也能替你在应用里动手：下载、调设置、整理课程、安排定时任务，做完都可以撤销。想先过目，就在输入框旁切到「询问」；删除文件总会先问你。'**
  String get botIntroBody;

  /// No description provided for @courseAssistantTitle.
  ///
  /// In zh, this message translates to:
  /// **'{value}助手'**
  String courseAssistantTitle(Object value);

  /// No description provided for @courseTitleQuoted.
  ///
  /// In zh, this message translates to:
  /// **'《{title}》'**
  String courseTitleQuoted(Object title);

  /// No description provided for @courseAssistantIntro.
  ///
  /// In zh, this message translates to:
  /// **'这个会话只围绕这门课：讲解、找知识点、整理笔记、出题。关于你的偏好来自 {botName} 的记忆。'**
  String courseAssistantIntro(Object botName);

  /// No description provided for @chatWelcomeTitle.
  ///
  /// In zh, this message translates to:
  /// **'有什么可以帮你？'**
  String get chatWelcomeTitle;

  /// No description provided for @chatWelcomeBody.
  ///
  /// In zh, this message translates to:
  /// **'我能读取课表、文字稿和笔记，帮你整理内容、定位知识点。下载由你点按钮决定。'**
  String get chatWelcomeBody;

  /// No description provided for @chatSwitchCourse.
  ///
  /// In zh, this message translates to:
  /// **'改为「{value}」的课程助手'**
  String chatSwitchCourse(Object value);

  /// No description provided for @chatCurrentCourse.
  ///
  /// In zh, this message translates to:
  /// **'当前课程'**
  String get chatCurrentCourse;

  /// No description provided for @chatContextPlaying.
  ///
  /// In zh, this message translates to:
  /// **'正在播放 · 助手可见当前进度'**
  String get chatContextPlaying;

  /// No description provided for @chatContextScreen.
  ///
  /// In zh, this message translates to:
  /// **'当前：{value}'**
  String chatContextScreen(Object value);

  /// No description provided for @chatInputHint.
  ///
  /// In zh, this message translates to:
  /// **'问点什么…（Shift+Enter 换行）'**
  String get chatInputHint;

  /// No description provided for @commonStop.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get commonStop;

  /// No description provided for @chatSend.
  ///
  /// In zh, this message translates to:
  /// **'发送 (Enter)'**
  String get chatSend;

  /// No description provided for @pluginsDiscover.
  ///
  /// In zh, this message translates to:
  /// **'发现插件'**
  String get pluginsDiscover;

  /// No description provided for @pluginsManage.
  ///
  /// In zh, this message translates to:
  /// **'管理插件'**
  String get pluginsManage;

  /// No description provided for @chatMoreTools.
  ///
  /// In zh, this message translates to:
  /// **'更多功能'**
  String get chatMoreTools;

  /// No description provided for @thinkingTitle.
  ///
  /// In zh, this message translates to:
  /// **'思考强度'**
  String get thinkingTitle;

  /// No description provided for @modelsSearchAll.
  ///
  /// In zh, this message translates to:
  /// **'搜索全部模型…'**
  String get modelsSearchAll;

  /// No description provided for @modelsSettings.
  ///
  /// In zh, this message translates to:
  /// **'模型设置…'**
  String get modelsSettings;

  /// No description provided for @contextUsage.
  ///
  /// In zh, this message translates to:
  /// **'上下文 {value} / {value2}（{value3}%）'**
  String contextUsage(Object value, Object value2, Object value3);

  /// No description provided for @contextTokens.
  ///
  /// In zh, this message translates to:
  /// **'本对话累计 输入 {value} · 输出 {value2}{value3}'**
  String contextTokens(Object value, Object value2, Object value3);

  /// No description provided for @contextCost.
  ///
  /// In zh, this message translates to:
  /// **'估算费用 \${cost}'**
  String contextCost(Object cost);

  /// No description provided for @contextCompactHint.
  ///
  /// In zh, this message translates to:
  /// **'接近上限时 Pi 会自动压缩较早的对话。'**
  String get contextCompactHint;

  /// No description provided for @contextCompactNow.
  ///
  /// In zh, this message translates to:
  /// **'立即压缩上下文'**
  String get contextCompactNow;

  /// No description provided for @usageView.
  ///
  /// In zh, this message translates to:
  /// **'查看用量'**
  String get usageView;

  /// No description provided for @contextUsageTooltip.
  ///
  /// In zh, this message translates to:
  /// **'上下文用量 {value}%'**
  String contextUsageTooltip(Object value);

  /// No description provided for @chatThinking.
  ///
  /// In zh, this message translates to:
  /// **'正在思考…'**
  String get chatThinking;

  /// No description provided for @toolReturned.
  ///
  /// In zh, this message translates to:
  /// **'已返回'**
  String get toolReturned;

  /// No description provided for @commonCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get commonCopied;

  /// No description provided for @chatThinkingNow.
  ///
  /// In zh, this message translates to:
  /// **'思考中'**
  String get chatThinkingNow;

  /// No description provided for @chatThinkingProcess.
  ///
  /// In zh, this message translates to:
  /// **'思考过程'**
  String get chatThinkingProcess;

  /// No description provided for @toolArgs.
  ///
  /// In zh, this message translates to:
  /// **'参数'**
  String get toolArgs;

  /// No description provided for @toolResult.
  ///
  /// In zh, this message translates to:
  /// **'结果'**
  String get toolResult;

  /// No description provided for @chatOutlineChapters.
  ///
  /// In zh, this message translates to:
  /// **'大纲 · {length} 个章节'**
  String chatOutlineChapters(Object length);

  /// No description provided for @chatSlideRef.
  ///
  /// In zh, this message translates to:
  /// **'PPT 第 {value} 张'**
  String chatSlideRef(Object value);

  /// No description provided for @chatVisionTranscribed.
  ///
  /// In zh, this message translates to:
  /// **'由识图模型转写给助手'**
  String get chatVisionTranscribed;

  /// No description provided for @chatVisionUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前模型不能看图，可以在「设置 → 助手 → 识图模型」里设置'**
  String get chatVisionUnavailable;

  /// No description provided for @chatSavedToLibrary.
  ///
  /// In zh, this message translates to:
  /// **'已保存到课程库 · 点击阅读'**
  String get chatSavedToLibrary;

  /// No description provided for @chatCodeCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制代码'**
  String get chatCodeCopied;

  /// No description provided for @thinkingMinimal.
  ///
  /// In zh, this message translates to:
  /// **'最少'**
  String get thinkingMinimal;

  /// No description provided for @thinkingLow.
  ///
  /// In zh, this message translates to:
  /// **'低'**
  String get thinkingLow;

  /// No description provided for @thinkingMax.
  ///
  /// In zh, this message translates to:
  /// **'最高'**
  String get thinkingMax;

  /// No description provided for @thinkingHintOff.
  ///
  /// In zh, this message translates to:
  /// **'直接回答，不做额外推理'**
  String get thinkingHintOff;

  /// No description provided for @thinkingHintMinimal.
  ///
  /// In zh, this message translates to:
  /// **'只做最少的推理，回复最快'**
  String get thinkingHintMinimal;

  /// No description provided for @thinkingHintLow.
  ///
  /// In zh, this message translates to:
  /// **'简单推理，适合日常问答'**
  String get thinkingHintLow;

  /// No description provided for @thinkingHintMedium.
  ///
  /// In zh, this message translates to:
  /// **'兼顾速度与深度'**
  String get thinkingHintMedium;

  /// No description provided for @thinkingHintHigh.
  ///
  /// In zh, this message translates to:
  /// **'推理更充分，等待更久'**
  String get thinkingHintHigh;

  /// No description provided for @thinkingHintMax.
  ///
  /// In zh, this message translates to:
  /// **'尽可能深入，最慢，花费也最多'**
  String get thinkingHintMax;

  /// No description provided for @thinkingSheetBody.
  ///
  /// In zh, this message translates to:
  /// **'更强的思考回答更周全，也更慢、更费 token。'**
  String get thinkingSheetBody;

  /// No description provided for @commonModel.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get commonModel;

  /// No description provided for @modelsImportPi.
  ///
  /// In zh, this message translates to:
  /// **'导入 Pi CLI 配置'**
  String get modelsImportPi;

  /// No description provided for @modelsCatalogUpdated.
  ///
  /// In zh, this message translates to:
  /// **'已更新 models.dev 目录'**
  String get modelsCatalogUpdated;

  /// No description provided for @modelsUpdateCatalog.
  ///
  /// In zh, this message translates to:
  /// **'更新 models.dev 目录'**
  String get modelsUpdateCatalog;

  /// No description provided for @modelsAddProvider.
  ///
  /// In zh, this message translates to:
  /// **'添加服务商'**
  String get modelsAddProvider;

  /// No description provided for @modelsAssistantNotStarted.
  ///
  /// In zh, this message translates to:
  /// **'助手还没启动'**
  String get modelsAssistantNotStarted;

  /// No description provided for @modelsAssistantNotStartedBody.
  ///
  /// In zh, this message translates to:
  /// **'启动后才能读取 Pi SDK 的模型注册表'**
  String get modelsAssistantNotStartedBody;

  /// No description provided for @modelsConfigError.
  ///
  /// In zh, this message translates to:
  /// **'配置文件有误：{value}'**
  String modelsConfigError(Object value);

  /// No description provided for @modelsProviders.
  ///
  /// In zh, this message translates to:
  /// **'已添加的服务商'**
  String get modelsProviders;

  /// No description provided for @commonAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get commonAdd;

  /// No description provided for @modelsNoProviders.
  ///
  /// In zh, this message translates to:
  /// **'还没有服务商。点「添加服务商」，从 30 多家预设或 models.dev 目录里选择。'**
  String get modelsNoProviders;

  /// No description provided for @modelsStepProvider.
  ///
  /// In zh, this message translates to:
  /// **'选择服务商'**
  String get modelsStepProvider;

  /// No description provided for @modelsStepProviderHint.
  ///
  /// In zh, this message translates to:
  /// **'30+ 预设，或 models.dev 收录的 200 多家'**
  String get modelsStepProviderHint;

  /// No description provided for @modelsStepKey.
  ///
  /// In zh, this message translates to:
  /// **'填入 API Key'**
  String get modelsStepKey;

  /// No description provided for @modelsStepKeyHint.
  ///
  /// In zh, this message translates to:
  /// **'只保存在本机，可一键测试连接'**
  String get modelsStepKeyHint;

  /// No description provided for @modelsStepModels.
  ///
  /// In zh, this message translates to:
  /// **'挑选模型'**
  String get modelsStepModels;

  /// No description provided for @modelsStepModelsHint.
  ///
  /// In zh, this message translates to:
  /// **'从服务商拉取模型列表，自动补全价格和上下文长度'**
  String get modelsStepModelsHint;

  /// No description provided for @modelsOnboardingTitle.
  ///
  /// In zh, this message translates to:
  /// **'给助手接上一个模型'**
  String get modelsOnboardingTitle;

  /// No description provided for @commonGetStarted.
  ///
  /// In zh, this message translates to:
  /// **'开始'**
  String get commonGetStarted;

  /// No description provided for @modelsCurrent.
  ///
  /// In zh, this message translates to:
  /// **'助手正在使用'**
  String get modelsCurrent;

  /// No description provided for @commonChange.
  ///
  /// In zh, this message translates to:
  /// **'更换'**
  String get commonChange;

  /// No description provided for @modelsPersona.
  ///
  /// In zh, this message translates to:
  /// **'附加指令（可选）'**
  String get modelsPersona;

  /// No description provided for @modelsPersonaHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：回答尽量简短；术语保留英文并附中文解释'**
  String get modelsPersonaHint;

  /// No description provided for @modelsPersonaSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存附加指令'**
  String get modelsPersonaSaved;

  /// No description provided for @modelsAutoTitle.
  ///
  /// In zh, this message translates to:
  /// **'自动为对话命名'**
  String get modelsAutoTitle;

  /// No description provided for @commonInUse.
  ///
  /// In zh, this message translates to:
  /// **'使用中'**
  String get commonInUse;

  /// No description provided for @modelsAvailableCount.
  ///
  /// In zh, this message translates to:
  /// **'{available} 个可用模型'**
  String modelsAvailableCount(Object available);

  /// No description provided for @modelsNoKey.
  ///
  /// In zh, this message translates to:
  /// **'未填写密钥'**
  String get modelsNoKey;

  /// No description provided for @commonCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get commonCustom;

  /// No description provided for @commonBuiltIn.
  ///
  /// In zh, this message translates to:
  /// **'内置'**
  String get commonBuiltIn;

  /// No description provided for @modelsSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索模型'**
  String get modelsSearch;

  /// No description provided for @modelsNoneAvailable.
  ///
  /// In zh, this message translates to:
  /// **'没有可用的模型'**
  String get modelsNoneAvailable;

  /// No description provided for @regionChina.
  ///
  /// In zh, this message translates to:
  /// **'国内'**
  String get regionChina;

  /// No description provided for @regionGlobal.
  ///
  /// In zh, this message translates to:
  /// **'海外'**
  String get regionGlobal;

  /// No description provided for @providerDeepseekBlurb.
  ///
  /// In zh, this message translates to:
  /// **'深度求索，性价比高的推理与对话模型'**
  String get providerDeepseekBlurb;

  /// No description provided for @providerSiliconflow.
  ///
  /// In zh, this message translates to:
  /// **'硅基流动'**
  String get providerSiliconflow;

  /// No description provided for @providerSiliconflowBlurb.
  ///
  /// In zh, this message translates to:
  /// **'聚合 Qwen、DeepSeek、GLM 等开源模型'**
  String get providerSiliconflowBlurb;

  /// No description provided for @providerBailian.
  ///
  /// In zh, this message translates to:
  /// **'阿里云百炼'**
  String get providerBailian;

  /// No description provided for @providerBailianBlurb.
  ///
  /// In zh, this message translates to:
  /// **'通义千问 Qwen 全系列'**
  String get providerBailianBlurb;

  /// No description provided for @providerZhipu.
  ///
  /// In zh, this message translates to:
  /// **'智谱 BigModel'**
  String get providerZhipu;

  /// No description provided for @providerZhipuBlurb.
  ///
  /// In zh, this message translates to:
  /// **'GLM 系列'**
  String get providerZhipuBlurb;

  /// No description provided for @providerMoonshot.
  ///
  /// In zh, this message translates to:
  /// **'Kimi 月之暗面'**
  String get providerMoonshot;

  /// No description provided for @providerMoonshotBlurb.
  ///
  /// In zh, this message translates to:
  /// **'长上下文的 Kimi 模型'**
  String get providerMoonshotBlurb;

  /// No description provided for @providerVolcengine.
  ///
  /// In zh, this message translates to:
  /// **'火山方舟 · 豆包'**
  String get providerVolcengine;

  /// No description provided for @providerVolcengineBlurb.
  ///
  /// In zh, this message translates to:
  /// **'字节跳动豆包大模型'**
  String get providerVolcengineBlurb;

  /// No description provided for @providerMinimaxBlurb.
  ///
  /// In zh, this message translates to:
  /// **'稀宇科技 MiniMax 模型'**
  String get providerMinimaxBlurb;

  /// No description provided for @providerHunyuan.
  ///
  /// In zh, this message translates to:
  /// **'腾讯混元'**
  String get providerHunyuan;

  /// No description provided for @providerHunyuanBlurb.
  ///
  /// In zh, this message translates to:
  /// **'腾讯混元大模型'**
  String get providerHunyuanBlurb;

  /// No description provided for @providerQianfan.
  ///
  /// In zh, this message translates to:
  /// **'百度千帆'**
  String get providerQianfan;

  /// No description provided for @providerQianfanBlurb.
  ///
  /// In zh, this message translates to:
  /// **'文心 ERNIE 系列'**
  String get providerQianfanBlurb;

  /// No description provided for @providerStepfun.
  ///
  /// In zh, this message translates to:
  /// **'阶跃星辰'**
  String get providerStepfun;

  /// No description provided for @providerStepfunBlurb.
  ///
  /// In zh, this message translates to:
  /// **'Step 系列多模态模型'**
  String get providerStepfunBlurb;

  /// No description provided for @providerMimo.
  ///
  /// In zh, this message translates to:
  /// **'小米 MiMo'**
  String get providerMimo;

  /// No description provided for @providerMimoBlurb.
  ///
  /// In zh, this message translates to:
  /// **'小米 MiMo 推理模型'**
  String get providerMimoBlurb;

  /// No description provided for @providerModelscope.
  ///
  /// In zh, this message translates to:
  /// **'魔搭 ModelScope'**
  String get providerModelscope;

  /// No description provided for @providerModelscopeBlurb.
  ///
  /// In zh, this message translates to:
  /// **'每日免费额度的开源模型推理'**
  String get providerModelscopeBlurb;

  /// No description provided for @providerPayAsYouGoBlurb.
  ///
  /// In zh, this message translates to:
  /// **'按量付费的模型聚合平台'**
  String get providerPayAsYouGoBlurb;

  /// No description provided for @providerOneKeyBlurb.
  ///
  /// In zh, this message translates to:
  /// **'一个 Key 调用多家模型'**
  String get providerOneKeyBlurb;

  /// No description provided for @providerPpio.
  ///
  /// In zh, this message translates to:
  /// **'PPIO 派欧云'**
  String get providerPpio;

  /// No description provided for @providerPpioBlurb.
  ///
  /// In zh, this message translates to:
  /// **'分布式云上的开源模型 API'**
  String get providerPpioBlurb;

  /// No description provided for @providerOpenaiBlurb.
  ///
  /// In zh, this message translates to:
  /// **'GPT 系列'**
  String get providerOpenaiBlurb;

  /// No description provided for @providerAnthropicBlurb.
  ///
  /// In zh, this message translates to:
  /// **'Claude 系列'**
  String get providerAnthropicBlurb;

  /// No description provided for @providerGoogleBlurb.
  ///
  /// In zh, this message translates to:
  /// **'Gemini 系列，AI Studio 密钥'**
  String get providerGoogleBlurb;

  /// No description provided for @providerOpenrouterBlurb.
  ///
  /// In zh, this message translates to:
  /// **'数百个模型的统一入口'**
  String get providerOpenrouterBlurb;

  /// No description provided for @providerXaiBlurb.
  ///
  /// In zh, this message translates to:
  /// **'Grok 系列'**
  String get providerXaiBlurb;

  /// No description provided for @providerGroqBlurb.
  ///
  /// In zh, this message translates to:
  /// **'LPU 极速推理'**
  String get providerGroqBlurb;

  /// No description provided for @providerFreeTrialBlurb.
  ///
  /// In zh, this message translates to:
  /// **'免费试用额度'**
  String get providerFreeTrialBlurb;

  /// No description provided for @providerPerplexityBlurb.
  ///
  /// In zh, this message translates to:
  /// **'联网搜索的 Sonar 模型'**
  String get providerPerplexityBlurb;

  /// No description provided for @providerOllamaBlurb.
  ///
  /// In zh, this message translates to:
  /// **'在本机运行开源模型'**
  String get providerOllamaBlurb;

  /// No description provided for @providerLmstudioBlurb.
  ///
  /// In zh, this message translates to:
  /// **'图形化的本地模型服务'**
  String get providerLmstudioBlurb;

  /// No description provided for @modelTagReasoning.
  ///
  /// In zh, this message translates to:
  /// **'思考'**
  String get modelTagReasoning;

  /// No description provided for @modelTagVision.
  ///
  /// In zh, this message translates to:
  /// **'识图'**
  String get modelTagVision;

  /// No description provided for @modelTagContext.
  ///
  /// In zh, this message translates to:
  /// **'{value} 上下文'**
  String modelTagContext(Object value);

  /// No description provided for @modelTagOutput.
  ///
  /// In zh, this message translates to:
  /// **'输出 {value}'**
  String modelTagOutput(Object value);

  /// No description provided for @modelTagFree.
  ///
  /// In zh, this message translates to:
  /// **'免费'**
  String get modelTagFree;

  /// No description provided for @modelTagDeprecated.
  ///
  /// In zh, this message translates to:
  /// **'已弃用'**
  String get modelTagDeprecated;

  /// No description provided for @apiOpenaiCompatible.
  ///
  /// In zh, this message translates to:
  /// **'OpenAI Chat Completions 兼容'**
  String get apiOpenaiCompatible;

  /// No description provided for @providerCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义服务'**
  String get providerCustom;

  /// No description provided for @providerSource.
  ///
  /// In zh, this message translates to:
  /// **'服务商'**
  String get providerSource;

  /// No description provided for @providerPickModel.
  ///
  /// In zh, this message translates to:
  /// **'至少选择一个模型'**
  String get providerPickModel;

  /// No description provided for @providerKeyMissing.
  ///
  /// In zh, this message translates to:
  /// **'请先填写 API Key'**
  String get providerKeyMissing;

  /// No description provided for @providerSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {name}'**
  String providerSaved(Object name);

  /// No description provided for @providerTestOk.
  ///
  /// In zh, this message translates to:
  /// **'{value} 响应正常 · {value2} ms'**
  String providerTestOk(Object value, Object value2);

  /// No description provided for @providerRemoveKeyTitle.
  ///
  /// In zh, this message translates to:
  /// **'移除 {name} 的密钥？'**
  String providerRemoveKeyTitle(Object name);

  /// No description provided for @providerDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除 {name}？'**
  String providerDeleteTitle(Object name);

  /// No description provided for @providerRemoveKeyBody.
  ///
  /// In zh, this message translates to:
  /// **'内置服务商仍会保留在目录中，填入密钥即可重新使用。'**
  String get providerRemoveKeyBody;

  /// No description provided for @providerDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'会删除这个服务及其模型配置。'**
  String get providerDeleteBody;

  /// No description provided for @providerAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加 {name}'**
  String providerAddTitle(Object name);

  /// No description provided for @providerBuiltIn.
  ///
  /// In zh, this message translates to:
  /// **'Pi SDK 内置服务商'**
  String get providerBuiltIn;

  /// No description provided for @commonConnect.
  ///
  /// In zh, this message translates to:
  /// **'连接'**
  String get commonConnect;

  /// No description provided for @providerKeySaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存（{value}），输入新值以替换'**
  String providerKeySaved(Object value);

  /// No description provided for @providerKeyHint.
  ///
  /// In zh, this message translates to:
  /// **'粘贴你的密钥'**
  String get providerKeyHint;

  /// No description provided for @commonPaste.
  ///
  /// In zh, this message translates to:
  /// **'粘贴'**
  String get commonPaste;

  /// No description provided for @commonShow.
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get commonShow;

  /// No description provided for @providerLocalNoKey.
  ///
  /// In zh, this message translates to:
  /// **'本地服务通常不需要密钥。确认服务已在本机启动。'**
  String get providerLocalNoKey;

  /// No description provided for @providerGetKey.
  ///
  /// In zh, this message translates to:
  /// **'还没有密钥？去 {name} 获取'**
  String providerGetKey(Object name);

  /// No description provided for @providerDownloadApp.
  ///
  /// In zh, this message translates to:
  /// **'下载 {name}'**
  String providerDownloadApp(Object name);

  /// No description provided for @commonAdvanced.
  ///
  /// In zh, this message translates to:
  /// **'高级'**
  String get commonAdvanced;

  /// No description provided for @providerApi.
  ///
  /// In zh, this message translates to:
  /// **'接口协议'**
  String get providerApi;

  /// No description provided for @providerId.
  ///
  /// In zh, this message translates to:
  /// **'服务 ID'**
  String get providerId;

  /// No description provided for @providerIdHelper.
  ///
  /// In zh, this message translates to:
  /// **'本地标识，字母数字及 . _ -'**
  String get providerIdHelper;

  /// No description provided for @providerTestsOnSave.
  ///
  /// In zh, this message translates to:
  /// **'保存后会测试一次连接'**
  String get providerTestsOnSave;

  /// No description provided for @providerChosenModels.
  ///
  /// In zh, this message translates to:
  /// **'已选 {length} 个模型 · 保存后测试连接'**
  String providerChosenModels(Object length);

  /// No description provided for @providerSaveAndTest.
  ///
  /// In zh, this message translates to:
  /// **'保存并测试'**
  String get providerSaveAndTest;

  /// No description provided for @providerBuiltInHint.
  ///
  /// In zh, this message translates to:
  /// **'Pi SDK 已内置这家的模型目录，填好密钥即可使用。点模型可设为助手默认。'**
  String get providerBuiltInHint;

  /// No description provided for @providerMoreModels.
  ///
  /// In zh, this message translates to:
  /// **'还有 {value} 个，搜索以缩小范围'**
  String providerMoreModels(Object value);

  /// No description provided for @providerChosen.
  ///
  /// In zh, this message translates to:
  /// **'已选择'**
  String get providerChosen;

  /// No description provided for @providerFetchModels.
  ///
  /// In zh, this message translates to:
  /// **'从服务商获取模型列表'**
  String get providerFetchModels;

  /// No description provided for @providerFetchNeedsKey.
  ///
  /// In zh, this message translates to:
  /// **'填写密钥后获取模型列表'**
  String get providerFetchNeedsKey;

  /// No description provided for @providerFromCatalog.
  ///
  /// In zh, this message translates to:
  /// **'从 models.dev 选择'**
  String get providerFromCatalog;

  /// No description provided for @providerNoModelList.
  ///
  /// In zh, this message translates to:
  /// **'这家服务可能不提供模型列表接口，可以改从 models.dev 目录选择或手动添加。'**
  String get providerNoModelList;

  /// No description provided for @providerOfferedCount.
  ///
  /// In zh, this message translates to:
  /// **'{length} 个 · 来自{offeredFrom}'**
  String providerOfferedCount(Object length, Object offeredFrom);

  /// No description provided for @providerNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的模型'**
  String get providerNoMatch;

  /// No description provided for @providerNotInCatalog.
  ///
  /// In zh, this message translates to:
  /// **'models.dev 未收录'**
  String get providerNotInCatalog;

  /// No description provided for @providerManualModel.
  ///
  /// In zh, this message translates to:
  /// **'手动添加模型 ID'**
  String get providerManualModel;

  /// No description provided for @providerManualModelHint.
  ///
  /// In zh, this message translates to:
  /// **'例如 deepseek-chat'**
  String get providerManualModelHint;

  /// No description provided for @providerCatalogNote.
  ///
  /// In zh, this message translates to:
  /// **'价格（美元 / 百万 token）、上下文长度和能力标签来自 models.dev，保存时写入 Pi 的模型配置，用于上下文管理和用量统计。'**
  String get providerCatalogNote;

  /// No description provided for @addProviderSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索服务商，例如 硅基、qwen、groq'**
  String get addProviderSearchHint;

  /// No description provided for @addProviderLoadingCatalog.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的预设，正在加载 models.dev 目录…'**
  String get addProviderLoadingCatalog;

  /// No description provided for @addProviderNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'没有找到“{q}”。可以用下方「自定义服务」手动填写。'**
  String addProviderNoMatch(Object q);

  /// No description provided for @addProviderCatalog.
  ///
  /// In zh, this message translates to:
  /// **'models.dev 目录'**
  String get addProviderCatalog;

  /// No description provided for @addProviderMatches.
  ///
  /// In zh, this message translates to:
  /// **'{length} 个匹配'**
  String addProviderMatches(Object length);

  /// No description provided for @addProviderCatalogEntry.
  ///
  /// In zh, this message translates to:
  /// **'{value} 个模型 · {value2}'**
  String addProviderCatalogEntry(Object value, Object value2);

  /// No description provided for @addProviderNotFound.
  ///
  /// In zh, this message translates to:
  /// **'找不到？'**
  String get addProviderNotFound;

  /// No description provided for @addProviderCompatibleHint.
  ///
  /// In zh, this message translates to:
  /// **'任何兼容 OpenAI / Anthropic / Gemini 接口的地址，包括中转和自建服务'**
  String get addProviderCompatibleHint;

  /// No description provided for @addProviderCatalogError.
  ///
  /// In zh, this message translates to:
  /// **'models.dev 目录暂时不可用：{catalogError}'**
  String addProviderCatalogError(Object catalogError);

  /// No description provided for @addProviderCatalogLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在加载 models.dev 目录…'**
  String get addProviderCatalogLoading;

  /// No description provided for @addProviderSearchesMore.
  ///
  /// In zh, this message translates to:
  /// **'搜索时还会在 models.dev 收录的另外 {moreCount} 家服务商中查找。'**
  String addProviderSearchesMore(Object moreCount);

  /// No description provided for @addProviderCompatible.
  ///
  /// In zh, this message translates to:
  /// **'兼容接口'**
  String get addProviderCompatible;

  /// No description provided for @addProviderBuiltInKeyOnly.
  ///
  /// In zh, this message translates to:
  /// **'Pi SDK 内置，只需密钥'**
  String get addProviderBuiltInKeyOnly;

  /// No description provided for @asrChannelSlots.
  ///
  /// In zh, this message translates to:
  /// **'{value} {value2} 段'**
  String asrChannelSlots(Object value, Object value2);

  /// No description provided for @asrPerChannelLimits.
  ///
  /// In zh, this message translates to:
  /// **'每个渠道有各自的并发上限'**
  String get asrPerChannelLimits;

  /// No description provided for @asrChannelLimits.
  ///
  /// In zh, this message translates to:
  /// **'渠道上限：{value}；调高不一定更快，容易触发限流'**
  String asrChannelLimits(Object value);

  /// No description provided for @asrIntro.
  ///
  /// In zh, this message translates to:
  /// **'长音频会切成 20 分钟的段，分给下面的渠道识别；某个渠道被限流时自动冷却，由其他渠道接手。已识别的段会保留，重试时只补缺失的部分。'**
  String get asrIntro;

  /// No description provided for @asrLocalEnabled.
  ///
  /// In zh, this message translates to:
  /// **'本地识别已启用'**
  String get asrLocalEnabled;

  /// No description provided for @asrTryLocal.
  ///
  /// In zh, this message translates to:
  /// **'免费渠道限流太厉害？改用本地模型'**
  String get asrTryLocal;

  /// No description provided for @asrLocalUnlimited.
  ///
  /// In zh, this message translates to:
  /// **'{value} · 不受额度限制'**
  String asrLocalUnlimited(Object value);

  /// No description provided for @asrLocalHint.
  ///
  /// In zh, this message translates to:
  /// **'下载一个识别模型到本机，看对比图选适合你电脑的那个'**
  String get asrLocalHint;

  /// No description provided for @asrDistribution.
  ///
  /// In zh, this message translates to:
  /// **'分配方式'**
  String get asrDistribution;

  /// No description provided for @asrBalanced.
  ///
  /// In zh, this message translates to:
  /// **'均衡'**
  String get asrBalanced;

  /// No description provided for @asrPrefer.
  ///
  /// In zh, this message translates to:
  /// **'优先{value}'**
  String asrPrefer(Object value);

  /// No description provided for @asrConcurrency.
  ///
  /// In zh, this message translates to:
  /// **'同时识别的段数'**
  String get asrConcurrency;

  /// No description provided for @asrSegments.
  ///
  /// In zh, this message translates to:
  /// **'{value} 段'**
  String asrSegments(Object value);

  /// No description provided for @asrDeleteVideo.
  ///
  /// In zh, this message translates to:
  /// **'转写完成后删除视频'**
  String get asrDeleteVideo;

  /// No description provided for @asrDeleteVideoHint.
  ///
  /// In zh, this message translates to:
  /// **'只保留文字稿、PPT 和课件，视频文件在转写成功后立即删除，节省磁盘空间。在线播放不受影响。'**
  String get asrDeleteVideoHint;

  /// No description provided for @asrReady.
  ///
  /// In zh, this message translates to:
  /// **'就绪'**
  String get asrReady;

  /// No description provided for @asrBusy.
  ///
  /// In zh, this message translates to:
  /// **'识别中 {value} 段'**
  String asrBusy(Object value);

  /// No description provided for @asrCooling.
  ///
  /// In zh, this message translates to:
  /// **'冷却至 {value}'**
  String asrCooling(Object value);

  /// No description provided for @asrQuotaFull.
  ///
  /// In zh, this message translates to:
  /// **'额度已满'**
  String get asrQuotaFull;

  /// No description provided for @commonDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已停用'**
  String get commonDisabled;

  /// No description provided for @asrQuotaUsage.
  ///
  /// In zh, this message translates to:
  /// **'12 小时内 {value} / {value2}'**
  String asrQuotaUsage(Object value, Object value2);

  /// No description provided for @asrOkSegments.
  ///
  /// In zh, this message translates to:
  /// **'成功 {value} 段'**
  String asrOkSegments(Object value);

  /// No description provided for @asrFailedSegments.
  ///
  /// In zh, this message translates to:
  /// **'失败 {value} 段'**
  String asrFailedSegments(Object value);

  /// No description provided for @commonLastUsed.
  ///
  /// In zh, this message translates to:
  /// **'上次 {value}'**
  String commonLastUsed(Object value);

  /// No description provided for @asrRecent.
  ///
  /// In zh, this message translates to:
  /// **'最近识别记录'**
  String get asrRecent;

  /// No description provided for @asrRecentSummary.
  ///
  /// In zh, this message translates to:
  /// **'最近 {length} 次 · 失败 {fails} 次'**
  String asrRecentSummary(Object length, Object fails);

  /// No description provided for @asrEventLine.
  ///
  /// In zh, this message translates to:
  /// **'{value}  {value2} · 第 {value3} 段 · {value4}音频 · 用时 {value5} 秒'**
  String asrEventLine(
    Object value,
    Object value2,
    Object value3,
    Object value4,
    Object value5,
  );

  /// No description provided for @commonConnectionOk.
  ///
  /// In zh, this message translates to:
  /// **'连接正常'**
  String get commonConnectionOk;

  /// No description provided for @mineruIntro.
  ///
  /// In zh, this message translates to:
  /// **'上传的课件（PDF、PPT、Word、图片）交给 MinerU 解析成 Markdown，保留公式、表格和图片，可以全文阅读，也能让助手引用。'**
  String get mineruIntro;

  /// No description provided for @mineruPrecise.
  ///
  /// In zh, this message translates to:
  /// **'精准解析 · Token ••••{value}'**
  String mineruPrecise(Object value);

  /// No description provided for @mineruLite.
  ///
  /// In zh, this message translates to:
  /// **'未配置 Token · 使用免登录的轻量解析'**
  String get mineruLite;

  /// No description provided for @commonTest.
  ///
  /// In zh, this message translates to:
  /// **'测试'**
  String get commonTest;

  /// No description provided for @mineruChangeToken.
  ///
  /// In zh, this message translates to:
  /// **'更换 Token'**
  String get mineruChangeToken;

  /// No description provided for @mineruTokenExpired.
  ///
  /// In zh, this message translates to:
  /// **'Token 已于 {value} 过期，请重新生成'**
  String mineruTokenExpired(Object value);

  /// No description provided for @mineruTokenExpires.
  ///
  /// In zh, this message translates to:
  /// **'Token 有效期至 {value}{value2}'**
  String mineruTokenExpires(Object value, Object value2);

  /// No description provided for @mineruTokenDaysLeft.
  ///
  /// In zh, this message translates to:
  /// **'（还剩 {expDays} 天）'**
  String mineruTokenDaysLeft(Object expDays);

  /// No description provided for @mineruTokenHint.
  ///
  /// In zh, this message translates to:
  /// **'在 MinerU 官网「API 管理」中创建'**
  String get mineruTokenHint;

  /// No description provided for @mineruGetToken.
  ///
  /// In zh, this message translates to:
  /// **'获取 Token'**
  String get mineruGetToken;

  /// No description provided for @commonRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get commonRemove;

  /// No description provided for @mineruQuotaToday.
  ///
  /// In zh, this message translates to:
  /// **'今日额度'**
  String get mineruQuotaToday;

  /// No description provided for @mineruQuotaPages.
  ///
  /// In zh, this message translates to:
  /// **' / {daily} 页'**
  String mineruQuotaPages(Object daily);

  /// No description provided for @mineruQuotaBody.
  ///
  /// In zh, this message translates to:
  /// **'今天解析了 {files} 个文件。高优先级额度每天 {daily} 页，超出后排队变慢；单文件上限 {value}、{value2} 页。额度由本机按解析结果统计，以官网为准。'**
  String mineruQuotaBody(
    Object files,
    Object daily,
    Object value,
    Object value2,
  );

  /// No description provided for @mineruLiteBody.
  ///
  /// In zh, this message translates to:
  /// **'轻量解析不需要 Token，但单文件限 10 MB、20 页，输出不含图片。配置 Token 后使用精准解析（每天 1000 页高优先级额度）。'**
  String get mineruLiteBody;

  /// No description provided for @mineruModel.
  ///
  /// In zh, this message translates to:
  /// **'解析模型'**
  String get mineruModel;

  /// No description provided for @mineruVlm.
  ///
  /// In zh, this message translates to:
  /// **'VLM 精准'**
  String get mineruVlm;

  /// No description provided for @mineruPipelineHint.
  ///
  /// In zh, this message translates to:
  /// **'Pipeline：传统版面分析，速度快、更稳定，适合排版简单的讲义。'**
  String get mineruPipelineHint;

  /// No description provided for @mineruVlmHint.
  ///
  /// In zh, this message translates to:
  /// **'VLM：视觉大模型，公式、表格和复杂版面效果更好，推荐。'**
  String get mineruVlmHint;

  /// No description provided for @mineruForceOcr.
  ///
  /// In zh, this message translates to:
  /// **'强制 OCR'**
  String get mineruForceOcr;

  /// No description provided for @mineruForceOcrHint.
  ///
  /// In zh, this message translates to:
  /// **'扫描版或文字无法复制的 PDF 打开'**
  String get mineruForceOcrHint;

  /// No description provided for @mineruAutoParse.
  ///
  /// In zh, this message translates to:
  /// **'上传后自动解析'**
  String get mineruAutoParse;

  /// No description provided for @mineruAutoParseHint.
  ///
  /// In zh, this message translates to:
  /// **'关闭后需要在课件卡片上手动点「解析」'**
  String get mineruAutoParseHint;

  /// No description provided for @mineruRecent.
  ///
  /// In zh, this message translates to:
  /// **'最近解析'**
  String get mineruRecent;

  /// No description provided for @commonPages.
  ///
  /// In zh, this message translates to:
  /// **'{value} 页'**
  String commonPages(Object value);

  /// No description provided for @mineruModeLite.
  ///
  /// In zh, this message translates to:
  /// **'轻量'**
  String get mineruModeLite;

  /// No description provided for @mineruModePrecise.
  ///
  /// In zh, this message translates to:
  /// **'精准'**
  String get mineruModePrecise;

  /// No description provided for @benchSortBy.
  ///
  /// In zh, this message translates to:
  /// **'按{label}'**
  String benchSortBy(Object label);

  /// No description provided for @benchMetricSource.
  ///
  /// In zh, this message translates to:
  /// **'{label}：{source}'**
  String benchMetricSource(Object label, Object source);

  /// No description provided for @benchUntested.
  ///
  /// In zh, this message translates to:
  /// **'未测'**
  String get benchUntested;

  /// No description provided for @listComma.
  ///
  /// In zh, this message translates to:
  /// **'，'**
  String get listComma;

  /// No description provided for @benchRowLabel.
  ///
  /// In zh, this message translates to:
  /// **'{name}，{summary}'**
  String benchRowLabel(Object name, Object summary);

  /// No description provided for @asrModelRecommended.
  ///
  /// In zh, this message translates to:
  /// **'推荐'**
  String get asrModelRecommended;

  /// No description provided for @asrModelFastest.
  ///
  /// In zh, this message translates to:
  /// **'最快'**
  String get asrModelFastest;

  /// No description provided for @asrModelAccurate.
  ///
  /// In zh, this message translates to:
  /// **'最准'**
  String get asrModelAccurate;

  /// No description provided for @benchCer.
  ///
  /// In zh, this message translates to:
  /// **'错字率'**
  String get benchCer;

  /// No description provided for @benchLowerIsBetter.
  ///
  /// In zh, this message translates to:
  /// **'越短越准'**
  String get benchLowerIsBetter;

  /// No description provided for @benchCerSource.
  ///
  /// In zh, this message translates to:
  /// **'WenetSpeech 会议测试集（最接近课堂录音）的字错误率，取自各模型的论文；来源不同，相差 1% 以内可视为持平'**
  String get benchCerSource;

  /// No description provided for @benchTime.
  ///
  /// In zh, this message translates to:
  /// **'转写用时'**
  String get benchTime;

  /// No description provided for @benchTimeHint.
  ///
  /// In zh, this message translates to:
  /// **'一节 90 分钟的课'**
  String get benchTimeHint;

  /// No description provided for @benchMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{value} 分钟'**
  String benchMinutes(Object value);

  /// No description provided for @benchTimeSource.
  ///
  /// In zh, this message translates to:
  /// **'在 {value} 上实测（{value2}，含加载模型），你的设备会有不同'**
  String benchTimeSource(Object value, Object value2);

  /// No description provided for @benchReferenceMachine.
  ///
  /// In zh, this message translates to:
  /// **'参考机器'**
  String get benchReferenceMachine;

  /// No description provided for @benchMemory.
  ///
  /// In zh, this message translates to:
  /// **'内存'**
  String get benchMemory;

  /// No description provided for @benchMemoryHint.
  ///
  /// In zh, this message translates to:
  /// **'识别时的峰值'**
  String get benchMemoryHint;

  /// No description provided for @benchMemorySource.
  ///
  /// In zh, this message translates to:
  /// **'同一次实测的进程峰值内存'**
  String get benchMemorySource;

  /// No description provided for @asrModelDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除 {value}？'**
  String asrModelDeleteTitle(Object value);

  /// No description provided for @asrModelDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'会释放 {value} 空间。已经转写好的文字稿不受影响，之后可以重新下载。'**
  String asrModelDeleteBody(Object value);

  /// No description provided for @asrModelLocation.
  ///
  /// In zh, this message translates to:
  /// **'模型存储位置'**
  String get asrModelLocation;

  /// No description provided for @asrModelLocationChanged.
  ///
  /// In zh, this message translates to:
  /// **'之后下载的模型会保存到新位置'**
  String get asrModelLocationChanged;

  /// No description provided for @asrLocalTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地识别模型'**
  String get asrLocalTitle;

  /// No description provided for @asrUnsupportedTitle.
  ///
  /// In zh, this message translates to:
  /// **'本机暂不支持'**
  String get asrUnsupportedTitle;

  /// No description provided for @asrUnsupportedBody.
  ///
  /// In zh, this message translates to:
  /// **'本地识别引擎没有提供 {value} 的预编译版本，转写会继续使用免费云端渠道。'**
  String asrUnsupportedBody(Object value);

  /// No description provided for @asrHowToChoose.
  ///
  /// In zh, this message translates to:
  /// **'怎么选'**
  String get asrHowToChoose;

  /// No description provided for @asrHowToChooseBody.
  ///
  /// In zh, this message translates to:
  /// **'三项都是越短越好。点一行可以在下面看到详情。没有特别需求就选带 ★ 的推荐模型。'**
  String get asrHowToChooseBody;

  /// No description provided for @asrStorage.
  ///
  /// In zh, this message translates to:
  /// **'存储位置'**
  String get asrStorage;

  /// No description provided for @asrSource.
  ///
  /// In zh, this message translates to:
  /// **'下载来源'**
  String get asrSource;

  /// No description provided for @asrSourceVerify.
  ///
  /// In zh, this message translates to:
  /// **'所有文件都会按目录里记录的 SHA-256 校验，来源被篡改或版本不一致时会直接报错，不会装上。中断后再次下载会从断点继续。'**
  String get asrSourceVerify;

  /// No description provided for @asrCustomLocation.
  ///
  /// In zh, this message translates to:
  /// **'自定义位置'**
  String get asrCustomLocation;

  /// No description provided for @asrDefaultLocation.
  ///
  /// In zh, this message translates to:
  /// **'默认位置'**
  String get asrDefaultLocation;

  /// No description provided for @asrUsedSpace.
  ///
  /// In zh, this message translates to:
  /// **'已用 {value}'**
  String asrUsedSpace(Object value);

  /// No description provided for @asrFreeSpace.
  ///
  /// In zh, this message translates to:
  /// **'磁盘剩余 {value}'**
  String asrFreeSpace(Object value);

  /// No description provided for @asrLowSpace.
  ///
  /// In zh, this message translates to:
  /// **'这块磁盘剩余空间不多，模型可能下载不完。可以换到空间更大的磁盘。'**
  String get asrLowSpace;

  /// No description provided for @asrChangeLocation.
  ///
  /// In zh, this message translates to:
  /// **'更改位置'**
  String get asrChangeLocation;

  /// No description provided for @commonOpenInFileManager.
  ///
  /// In zh, this message translates to:
  /// **'在文件管理器中打开'**
  String get commonOpenInFileManager;

  /// No description provided for @asrResetLocation.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get asrResetLocation;

  /// No description provided for @asrLocationAfterDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载完成后才能更改位置'**
  String get asrLocationAfterDownload;

  /// No description provided for @asrMoveTitle.
  ///
  /// In zh, this message translates to:
  /// **'把已下载的模型一起移过去？'**
  String get asrMoveTitle;

  /// No description provided for @asrMoveBody.
  ///
  /// In zh, this message translates to:
  /// **'移动：{value} 的引擎和模型会搬到新位置，旧位置随后清空。跨磁盘时需要复制一会儿，期间不能转写。'**
  String asrMoveBody(Object value);

  /// No description provided for @asrChangeOnlyBody.
  ///
  /// In zh, this message translates to:
  /// **'只更改位置：旧文件留在原处，之后下载到新位置；新位置里已有的模型会直接可用。'**
  String get asrChangeOnlyBody;

  /// No description provided for @asrChangeOnly.
  ///
  /// In zh, this message translates to:
  /// **'只更改位置'**
  String get asrChangeOnly;

  /// No description provided for @asrMove.
  ///
  /// In zh, this message translates to:
  /// **'移动'**
  String get asrMove;

  /// No description provided for @asrMoving.
  ///
  /// In zh, this message translates to:
  /// **'正在移动模型'**
  String get asrMoving;

  /// No description provided for @asrMovingBody.
  ///
  /// In zh, this message translates to:
  /// **'移动完成前本地识别暂停，云端渠道照常转写。可以离开这个页面。'**
  String get asrMovingBody;

  /// No description provided for @asrUsingModel.
  ///
  /// In zh, this message translates to:
  /// **'正在使用 {value}'**
  String asrUsingModel(Object value);

  /// No description provided for @asrUsingModelBody.
  ///
  /// In zh, this message translates to:
  /// **'转写会交给本机模型，不受限流和额度影响；开着的云端渠道也会并行分担一部分。想让音频完全不离开本机，在「设置 → 转写」里关掉云端渠道。'**
  String get asrUsingModelBody;

  /// No description provided for @asrDownloadingModel.
  ///
  /// In zh, this message translates to:
  /// **'正在下载 {value}'**
  String asrDownloadingModel(Object value);

  /// No description provided for @asrDownloadingModelBody.
  ///
  /// In zh, this message translates to:
  /// **'下载完成后会自动启用。可以离开这个页面，进度会在后台继续。'**
  String get asrDownloadingModelBody;

  /// No description provided for @asrLocalHeroTitle.
  ///
  /// In zh, this message translates to:
  /// **'在本机识别'**
  String get asrLocalHeroTitle;

  /// No description provided for @asrLocalHeroBody.
  ///
  /// In zh, this message translates to:
  /// **'下载一个语音识别模型到本机，转写不再受免费云端渠道的限流和额度影响，音频也不会离开本机。'**
  String get asrLocalHeroBody;

  /// No description provided for @commonDownloadSize.
  ///
  /// In zh, this message translates to:
  /// **'下载 {value}'**
  String commonDownloadSize(Object value);

  /// No description provided for @asrModelMemory.
  ///
  /// In zh, this message translates to:
  /// **'内存约 {value}'**
  String asrModelMemory(Object value);

  /// No description provided for @asrModelSpeed.
  ///
  /// In zh, this message translates to:
  /// **'90 分钟课约 {value} 分钟'**
  String asrModelSpeed(Object value);

  /// No description provided for @asrModelCer.
  ///
  /// In zh, this message translates to:
  /// **'错字率 {value}%'**
  String asrModelCer(Object value);

  /// No description provided for @asrModelPunctuated.
  ///
  /// In zh, this message translates to:
  /// **'自带标点'**
  String get asrModelPunctuated;

  /// No description provided for @asrModelAutoPunctuation.
  ///
  /// In zh, this message translates to:
  /// **'自动补标点'**
  String get asrModelAutoPunctuation;

  /// No description provided for @asrModelCerSource.
  ///
  /// In zh, this message translates to:
  /// **'错字率来源：{value}'**
  String asrModelCerSource(Object value);

  /// No description provided for @commonLicense.
  ///
  /// In zh, this message translates to:
  /// **'许可：{value}'**
  String commonLicense(Object value);

  /// No description provided for @asrModelOriginal.
  ///
  /// In zh, this message translates to:
  /// **'原始模型'**
  String get asrModelOriginal;

  /// No description provided for @asrModelDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载失败：{value}'**
  String asrModelDownloadFailed(Object value);

  /// No description provided for @asrModelResume.
  ///
  /// In zh, this message translates to:
  /// **'继续下载'**
  String get asrModelResume;

  /// No description provided for @asrModelDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载 {value}{value2}'**
  String asrModelDownload(Object value, Object value2);

  /// No description provided for @asrModelIncludesEngine.
  ///
  /// In zh, this message translates to:
  /// **'（含引擎等）'**
  String get asrModelIncludesEngine;

  /// No description provided for @commonDisable.
  ///
  /// In zh, this message translates to:
  /// **'停用'**
  String get commonDisable;

  /// No description provided for @asrModelUse.
  ///
  /// In zh, this message translates to:
  /// **'使用这个模型'**
  String get asrModelUse;

  /// No description provided for @commonTimeLeft.
  ///
  /// In zh, this message translates to:
  /// **'还需 {value}'**
  String commonTimeLeft(Object value);

  /// No description provided for @asrSourceHfMirror.
  ///
  /// In zh, this message translates to:
  /// **'无需任何配置。hf-mirror.com 是社区维护的 Hugging Face 镜像，国内大多数网络可以直连，目录里的全部模型都能从这里下载。'**
  String get asrSourceHfMirror;

  /// No description provided for @asrSourceModelscope.
  ///
  /// In zh, this message translates to:
  /// **'无需账号或 Token，公开模型直接下载。魔搭上目前只有 Qwen3-ASR 0.6B 和语音检测模型有与原版逐字节相同的副本（社区用户上传），选它们时走魔搭；其余文件自动改用 HF-Mirror，下载时会提示。'**
  String get asrSourceModelscope;

  /// No description provided for @asrSourceHuggingface.
  ///
  /// In zh, this message translates to:
  /// **'官方源，文件最全，但国内通常需要代理。Look Studio 的后台服务会使用系统的 HTTPS_PROXY 环境变量。'**
  String get asrSourceHuggingface;

  /// No description provided for @asrSourceCustom.
  ///
  /// In zh, this message translates to:
  /// **'适合学校、实验室或自建的 Hugging Face 兼容镜像。填写地址模板，\'{\'repo\'}\' 会换成模型仓库名，\'{\'file\'}\' 换成文件路径，例如 https://hf-mirror.com/\'{\'repo\'}\'/resolve/main/\'{\'file\'}\'。'**
  String get asrSourceCustom;

  /// No description provided for @asrSourceTemplate.
  ///
  /// In zh, this message translates to:
  /// **'地址模板'**
  String get asrSourceTemplate;

  /// No description provided for @asrEngineSource.
  ///
  /// In zh, this message translates to:
  /// **'识别引擎（GitHub）'**
  String get asrEngineSource;

  /// No description provided for @asrEngineSourceBody.
  ///
  /// In zh, this message translates to:
  /// **'第一次下载时会从 GitHub Releases 取 sherpa-onnx 识别引擎（约 25 MB）。GitHub 很慢时，可以填一个 GitHub 下载加速服务的前缀，实际地址为「前缀 + 原始地址」，同样会校验 SHA-256。'**
  String get asrEngineSourceBody;

  /// No description provided for @asrEngineProxy.
  ///
  /// In zh, this message translates to:
  /// **'加速前缀（可选）'**
  String get asrEngineProxy;

  /// No description provided for @asrThreads.
  ///
  /// In zh, this message translates to:
  /// **'识别线程'**
  String get asrThreads;

  /// No description provided for @asrThreadCount.
  ///
  /// In zh, this message translates to:
  /// **'{value} 线程'**
  String asrThreadCount(Object value);

  /// No description provided for @asrThreadsHint.
  ///
  /// In zh, this message translates to:
  /// **'线程越多越快，但转写时设备会更忙、更费电。本机有 {cpus} 个逻辑核心，默认用一半（最多 4 个）。'**
  String asrThreadsHint(Object cpus);

  /// No description provided for @watchCheckStarted.
  ///
  /// In zh, this message translates to:
  /// **'已开始检查，有变化会马上通知你'**
  String get watchCheckStarted;

  /// No description provided for @watchTitle.
  ///
  /// In zh, this message translates to:
  /// **'后台自动检查新回放和新课次'**
  String get watchTitle;

  /// No description provided for @watchBody.
  ///
  /// In zh, this message translates to:
  /// **'刚下课的课每 10 分钟查一次回放，之后逐渐放缓；其他课程每 6 小时同步一次；已连接的 Canvas 每 15 分钟同步作业和公告。有变化时立即提醒，课程页也会自动刷新。'**
  String get watchBody;

  /// No description provided for @watchAwaiting.
  ///
  /// In zh, this message translates to:
  /// **'正在等待 {awaiting} 节课的回放'**
  String watchAwaiting(Object awaiting);

  /// No description provided for @watchNoneAwaiting.
  ///
  /// In zh, this message translates to:
  /// **'没有等待中的回放'**
  String get watchNoneAwaiting;

  /// No description provided for @watchNextCheck.
  ///
  /// In zh, this message translates to:
  /// **'下次检查 {value}'**
  String watchNextCheck(Object value);

  /// No description provided for @watchLastError.
  ///
  /// In zh, this message translates to:
  /// **'最近一次检查失败：{err}'**
  String watchLastError(Object err);

  /// No description provided for @watchCheckNow.
  ///
  /// In zh, this message translates to:
  /// **'立即检查'**
  String get watchCheckNow;

  /// No description provided for @obsidianVault.
  ///
  /// In zh, this message translates to:
  /// **'Obsidian 仓库'**
  String get obsidianVault;

  /// No description provided for @commonSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get commonSaved;

  /// No description provided for @obsidianChooseVaultFirst.
  ///
  /// In zh, this message translates to:
  /// **'先选择 Obsidian 仓库文件夹'**
  String get obsidianChooseVaultFirst;

  /// No description provided for @obsidianExported.
  ///
  /// In zh, this message translates to:
  /// **'已导出：新写入 {value}，未变 {value2}，清理 {value3}'**
  String obsidianExported(Object value, Object value2, Object value3);

  /// No description provided for @obsidianConflicts.
  ///
  /// In zh, this message translates to:
  /// **'{conflicts} 个文件在 Obsidian 中改过，已保留你的版本（笔记的新版本另存为「(Look Studio)」副本）'**
  String obsidianConflicts(Object conflicts);

  /// No description provided for @obsidianNotVault.
  ///
  /// In zh, this message translates to:
  /// **'目标文件夹不是 Obsidian 仓库（没有 .obsidian），仍已导出'**
  String get obsidianNotVault;

  /// No description provided for @listSemicolon.
  ///
  /// In zh, this message translates to:
  /// **'；'**
  String get listSemicolon;

  /// No description provided for @commonExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败：{e}'**
  String commonExportFailed(Object e);

  /// No description provided for @linkRegistered.
  ///
  /// In zh, this message translates to:
  /// **'已注册：点击 lookstudio:// 链接会打开 Look Studio'**
  String get linkRegistered;

  /// No description provided for @linkRegisterPartial.
  ///
  /// In zh, this message translates to:
  /// **'已写入 {name}，但 xdg-mime 失败：{stderr}'**
  String linkRegisterPartial(Object name, Object stderr);

  /// No description provided for @linkRegisterFailed.
  ///
  /// In zh, this message translates to:
  /// **'注册失败：{e}'**
  String linkRegisterFailed(Object e);

  /// No description provided for @obsidianNoVault.
  ///
  /// In zh, this message translates to:
  /// **'未设置仓库'**
  String get obsidianNoVault;

  /// No description provided for @obsidianStatus.
  ///
  /// In zh, this message translates to:
  /// **'导出到 {value}{value2}'**
  String obsidianStatus(Object value, Object value2);

  /// No description provided for @commonAutoSuffix.
  ///
  /// In zh, this message translates to:
  /// **' · 自动'**
  String get commonAutoSuffix;

  /// No description provided for @obsidianBody.
  ///
  /// In zh, this message translates to:
  /// **'把课程库单向导出到 Obsidian 仓库的一个文件夹：总的「课程库」页，每门课一个文件夹，里面分「笔记」（按节次，含引用的 PPT 和课件）和「转写稿」。点击时间戳会回到 Look Studio；在 Obsidian 里改过的文件不会被覆盖。'**
  String get obsidianBody;

  /// No description provided for @commonLocation.
  ///
  /// In zh, this message translates to:
  /// **'位置'**
  String get commonLocation;

  /// No description provided for @obsidianFolder.
  ///
  /// In zh, this message translates to:
  /// **'仓库内的文件夹'**
  String get obsidianFolder;

  /// No description provided for @obsidianFolderHelper.
  ///
  /// In zh, this message translates to:
  /// **'只写入这个文件夹，仓库里的其他笔记不受影响'**
  String get obsidianFolderHelper;

  /// No description provided for @obsidianSaveLocation.
  ///
  /// In zh, this message translates to:
  /// **'保存位置'**
  String get obsidianSaveLocation;

  /// No description provided for @commonExport.
  ///
  /// In zh, this message translates to:
  /// **'导出'**
  String get commonExport;

  /// No description provided for @obsidianAutoExport.
  ///
  /// In zh, this message translates to:
  /// **'笔记变化后自动导出'**
  String get obsidianAutoExport;

  /// No description provided for @obsidianAutoExportHint.
  ///
  /// In zh, this message translates to:
  /// **'保存或删除笔记后几秒内刷新'**
  String get obsidianAutoExportHint;

  /// No description provided for @commonExporting.
  ///
  /// In zh, this message translates to:
  /// **'正在导出'**
  String get commonExporting;

  /// No description provided for @commonExportNow.
  ///
  /// In zh, this message translates to:
  /// **'立即导出'**
  String get commonExportNow;

  /// No description provided for @obsidianBackLinks.
  ///
  /// In zh, this message translates to:
  /// **'回到 Look Studio'**
  String get obsidianBackLinks;

  /// No description provided for @obsidianBackLinksBody.
  ///
  /// In zh, this message translates to:
  /// **'导出的时间戳和课次链接是 lookstudio:// 链接。注册后，在 Obsidian 里点击会打开对应的课和时刻。'**
  String get obsidianBackLinksBody;

  /// No description provided for @linkRegister.
  ///
  /// In zh, this message translates to:
  /// **'注册 lookstudio:// 链接'**
  String get linkRegister;

  /// No description provided for @notionSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'同步到你的 Notion 工作区'**
  String get notionSubtitle;

  /// No description provided for @commonSyncing.
  ///
  /// In zh, this message translates to:
  /// **'正在同步…'**
  String get commonSyncing;

  /// No description provided for @notionNoParent.
  ///
  /// In zh, this message translates to:
  /// **'已连接 · 还没选同步位置'**
  String get notionNoParent;

  /// No description provided for @notionStatus.
  ///
  /// In zh, this message translates to:
  /// **'{value} · {value2} 个页面{value3}'**
  String notionStatus(Object value, Object value2, Object value3);

  /// No description provided for @notionDisconnectTitle.
  ///
  /// In zh, this message translates to:
  /// **'断开 Notion？'**
  String get notionDisconnectTitle;

  /// No description provided for @notionDisconnectBody.
  ///
  /// In zh, this message translates to:
  /// **'会删除本机保存的令牌和同步记录。已经同步到 Notion 的页面会留在那里；之后重新连接时会新建一份。'**
  String get notionDisconnectBody;

  /// No description provided for @commonDisconnect.
  ///
  /// In zh, this message translates to:
  /// **'断开'**
  String get commonDisconnect;

  /// No description provided for @notionChangeParentTitle.
  ///
  /// In zh, this message translates to:
  /// **'换一个同步位置？'**
  String get notionChangeParentTitle;

  /// No description provided for @notionChangeParentBody.
  ///
  /// In zh, this message translates to:
  /// **'之后会在新页面下重新创建课程库。原来同步过去的页面留在原处，不再更新。'**
  String get notionChangeParentBody;

  /// No description provided for @notionConnectedTo.
  ///
  /// In zh, this message translates to:
  /// **'已连接到 {value}'**
  String notionConnectedTo(Object value);

  /// No description provided for @notionWorkspace.
  ///
  /// In zh, this message translates to:
  /// **'工作区'**
  String get notionWorkspace;

  /// No description provided for @commonNotConnected.
  ///
  /// In zh, this message translates to:
  /// **'未连接'**
  String get commonNotConnected;

  /// No description provided for @notionBody.
  ///
  /// In zh, this message translates to:
  /// **'把课程库同步到 Notion 的一个页面下：每门课、每节课一个页面，下面是笔记和转写稿。只写入 Look Studio 创建的页面；在 Notion 里改过的页面不会被覆盖。'**
  String get notionBody;

  /// No description provided for @notionCreateIntegration.
  ///
  /// In zh, this message translates to:
  /// **'创建集成'**
  String get notionCreateIntegration;

  /// No description provided for @notionStep1.
  ///
  /// In zh, this message translates to:
  /// **'在 Notion 的「集成」页新建一个 Internal 集成，名称填 Look Studio，选择要同步到的工作区'**
  String get notionStep1;

  /// No description provided for @notionStep2.
  ///
  /// In zh, this message translates to:
  /// **'在「功能」里保留读取、更新和插入内容，其余可以关闭'**
  String get notionStep2;

  /// No description provided for @notionStep3.
  ///
  /// In zh, this message translates to:
  /// **'复制「Internal Integration Secret」，粘贴到下面'**
  String get notionStep3;

  /// No description provided for @notionOpenIntegrations.
  ///
  /// In zh, this message translates to:
  /// **'打开 Notion 集成页'**
  String get notionOpenIntegrations;

  /// No description provided for @notionSecret.
  ///
  /// In zh, this message translates to:
  /// **'集成密钥'**
  String get notionSecret;

  /// No description provided for @notionSecretHelper.
  ///
  /// In zh, this message translates to:
  /// **'用本机密钥加密保存，只用来访问你授权给集成的页面'**
  String get notionSecretHelper;

  /// No description provided for @commonConnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在连接'**
  String get commonConnecting;

  /// No description provided for @notionShareHint.
  ///
  /// In zh, this message translates to:
  /// **'连接后，还要在 Notion 里把一个页面分享给这个集成，课程库会建在那个页面下面。'**
  String get notionShareHint;

  /// No description provided for @notionParent.
  ///
  /// In zh, this message translates to:
  /// **'同步位置'**
  String get notionParent;

  /// No description provided for @notionParentStep1.
  ///
  /// In zh, this message translates to:
  /// **'在 Notion 打开想放课程库的页面'**
  String get notionParentStep1;

  /// No description provided for @notionParentStep2.
  ///
  /// In zh, this message translates to:
  /// **'点右上角「···」→「连接」，选择你的集成'**
  String get notionParentStep2;

  /// No description provided for @notionParentStep3.
  ///
  /// In zh, this message translates to:
  /// **'回到这里选择这个页面'**
  String get notionParentStep3;

  /// No description provided for @notionChoosePage.
  ///
  /// In zh, this message translates to:
  /// **'选择页面'**
  String get notionChoosePage;

  /// No description provided for @notionParentHint.
  ///
  /// In zh, this message translates to:
  /// **'课程库在这个页面下的「Look Studio 课程库」里'**
  String get notionParentHint;

  /// No description provided for @notionOpenInNotion.
  ///
  /// In zh, this message translates to:
  /// **'在 Notion 中打开'**
  String get notionOpenInNotion;

  /// No description provided for @notionIntegration.
  ///
  /// In zh, this message translates to:
  /// **'集成'**
  String get notionIntegration;

  /// No description provided for @notionSecretTail.
  ///
  /// In zh, this message translates to:
  /// **'集成密钥 ••••{value}'**
  String notionSecretTail(Object value);

  /// No description provided for @notionLimits.
  ///
  /// In zh, this message translates to:
  /// **'Notion 里的时间戳显示为文字，图片和课件不上传；需要跳回课堂时刻可以用 Obsidian 导出。'**
  String get notionLimits;

  /// No description provided for @commonSync.
  ///
  /// In zh, this message translates to:
  /// **'同步'**
  String get commonSync;

  /// No description provided for @notionAutoSync.
  ///
  /// In zh, this message translates to:
  /// **'笔记变化后自动同步'**
  String get notionAutoSync;

  /// No description provided for @notionAutoSyncHint.
  ///
  /// In zh, this message translates to:
  /// **'保存或删除笔记约 1 分钟后，只同步改动的页面'**
  String get notionAutoSyncHint;

  /// No description provided for @commonSyncProgress.
  ///
  /// In zh, this message translates to:
  /// **'正在同步 {done} / {total}'**
  String commonSyncProgress(Object done, Object total);

  /// No description provided for @commonChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在检查'**
  String get commonChecking;

  /// No description provided for @notionConflicts.
  ///
  /// In zh, this message translates to:
  /// **'{length} 个页面在 Notion 里改过，保留了你的版本'**
  String notionConflicts(Object length);

  /// No description provided for @notionErrors.
  ///
  /// In zh, this message translates to:
  /// **'{length} 个页面没有同步成功'**
  String notionErrors(Object length);

  /// No description provided for @commonStartSync.
  ///
  /// In zh, this message translates to:
  /// **'开始同步'**
  String get commonStartSync;

  /// No description provided for @commonSyncNow.
  ///
  /// In zh, this message translates to:
  /// **'立即同步'**
  String get commonSyncNow;

  /// No description provided for @notionFullCheckHint.
  ///
  /// In zh, this message translates to:
  /// **'逐页确认还在，补建在 Notion 里删掉的页面；页面多时较慢'**
  String get notionFullCheckHint;

  /// No description provided for @notionFullCheck.
  ///
  /// In zh, this message translates to:
  /// **'完整检查'**
  String get notionFullCheck;

  /// No description provided for @syncCreated.
  ///
  /// In zh, this message translates to:
  /// **'新建 {value}'**
  String syncCreated(Object value);

  /// No description provided for @syncUpdated.
  ///
  /// In zh, this message translates to:
  /// **'更新 {value}'**
  String syncUpdated(Object value);

  /// No description provided for @syncTrashed.
  ///
  /// In zh, this message translates to:
  /// **'移到废纸篓 {value}'**
  String syncTrashed(Object value);

  /// No description provided for @syncUnchanged.
  ///
  /// In zh, this message translates to:
  /// **'未变 {value}'**
  String syncUnchanged(Object value);

  /// No description provided for @commonLastSynced.
  ///
  /// In zh, this message translates to:
  /// **'上次同步 {value}'**
  String commonLastSynced(Object value);

  /// No description provided for @notionMoreItems.
  ///
  /// In zh, this message translates to:
  /// **'还有 {value} 项'**
  String notionMoreItems(Object value);

  /// No description provided for @notionChooseParent.
  ///
  /// In zh, this message translates to:
  /// **'选择同步位置'**
  String get notionChooseParent;

  /// No description provided for @notionChooseParentHint.
  ///
  /// In zh, this message translates to:
  /// **'这里只列出分享给集成的页面。也可以粘贴页面链接。'**
  String get notionChooseParentHint;

  /// No description provided for @notionSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索页面或粘贴链接'**
  String get notionSearchHint;

  /// No description provided for @notionUseLink.
  ///
  /// In zh, this message translates to:
  /// **'使用这个链接'**
  String get notionUseLink;

  /// No description provided for @commonUntitled.
  ///
  /// In zh, this message translates to:
  /// **'无标题'**
  String get commonUntitled;

  /// No description provided for @notionNoPages.
  ///
  /// In zh, this message translates to:
  /// **'集成还没有可用的页面'**
  String get notionNoPages;

  /// No description provided for @notionNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'没有找到「{q}」'**
  String notionNoMatch(Object q);

  /// No description provided for @notionShareSteps.
  ///
  /// In zh, this message translates to:
  /// **'在 Notion 打开目标页面，点右上角「···」→「连接」，选择你的集成，然后刷新。'**
  String get notionShareSteps;

  /// No description provided for @commonRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get commonRefresh;

  /// No description provided for @knowledgeConnectApps.
  ///
  /// In zh, this message translates to:
  /// **'连接到笔记应用'**
  String get knowledgeConnectApps;

  /// No description provided for @knowledgeObsidianSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'导出到本地仓库，时间戳可点回 Look Studio'**
  String get knowledgeObsidianSubtitle;

  /// No description provided for @knowledgeAutoExportSuffix.
  ///
  /// In zh, this message translates to:
  /// **' · 自动导出'**
  String get knowledgeAutoExportSuffix;

  /// No description provided for @commonOpen.
  ///
  /// In zh, this message translates to:
  /// **'打开'**
  String get commonOpen;

  /// No description provided for @knowledgeFolderTemplates.
  ///
  /// In zh, this message translates to:
  /// **'文件夹命名模板'**
  String get knowledgeFolderTemplates;

  /// No description provided for @knowledgeFolderTemplatesHint.
  ///
  /// In zh, this message translates to:
  /// **'课程可用 \'{\'title\'}\' \'{\'teacher\'}\' \'{\'term\'}\' \'{\'id\'}\'；课次可用 \'{\'date\'}\' \'{\'title\'}\' \'{\'sub_id\'}\' \'{\'lecturer\'}\'。只影响之后新建的文件夹。'**
  String get knowledgeFolderTemplatesHint;

  /// No description provided for @knowledgeCourseFolder.
  ///
  /// In zh, this message translates to:
  /// **'课程文件夹'**
  String get knowledgeCourseFolder;

  /// No description provided for @knowledgeLectureFolder.
  ///
  /// In zh, this message translates to:
  /// **'课次文件夹'**
  String get knowledgeLectureFolder;

  /// No description provided for @knowledgeTemplatesSaved.
  ///
  /// In zh, this message translates to:
  /// **'模板已保存'**
  String get knowledgeTemplatesSaved;

  /// No description provided for @knowledgeSkillExport.
  ///
  /// In zh, this message translates to:
  /// **'导出为 Look-Tongji-Notes 技能格式'**
  String get knowledgeSkillExport;

  /// No description provided for @knowledgeSkillExportHint.
  ///
  /// In zh, this message translates to:
  /// **'以硬链接生成 raw/<课程>/<节次>/原始数据/ 目录，不额外占空间'**
  String get knowledgeSkillExportHint;

  /// No description provided for @knowledgeSkillExportAction.
  ///
  /// In zh, this message translates to:
  /// **'导出到技能目录'**
  String get knowledgeSkillExportAction;

  /// No description provided for @knowledgeTargetFolder.
  ///
  /// In zh, this message translates to:
  /// **'目标文件夹'**
  String get knowledgeTargetFolder;

  /// No description provided for @knowledgeTargetFolderHelper.
  ///
  /// In zh, this message translates to:
  /// **'Look-Tongji-Notes 技能所在的文件夹'**
  String get knowledgeTargetFolderHelper;

  /// No description provided for @knowledgeExported.
  ///
  /// In zh, this message translates to:
  /// **'已导出 {value} 节课'**
  String knowledgeExported(Object value);

  /// No description provided for @commonConnected.
  ///
  /// In zh, this message translates to:
  /// **'已连接'**
  String get commonConnected;

  /// No description provided for @webdavAccount.
  ///
  /// In zh, this message translates to:
  /// **'账号'**
  String get webdavAccount;

  /// No description provided for @webdavAppPassword.
  ///
  /// In zh, this message translates to:
  /// **'应用密码'**
  String get webdavAppPassword;

  /// No description provided for @webdavJianguoyun.
  ///
  /// In zh, this message translates to:
  /// **'坚果云'**
  String get webdavJianguoyun;

  /// No description provided for @webdavJianguoyunHint.
  ///
  /// In zh, this message translates to:
  /// **'账号是坚果云登录邮箱；在网页版「账户信息 → 安全选项 → 第三方应用管理」添加应用，得到应用密码'**
  String get webdavJianguoyunHint;

  /// No description provided for @webdavJianguoyunUser.
  ///
  /// In zh, this message translates to:
  /// **'坚果云账号（邮箱）'**
  String get webdavJianguoyunUser;

  /// No description provided for @webdavNextcloudHint.
  ///
  /// In zh, this message translates to:
  /// **'地址形如 https://域名/remote.php/dav/files/用户名/；在「个人设置 → 安全」创建应用密码'**
  String get webdavNextcloudHint;

  /// No description provided for @webdavAlistHint.
  ///
  /// In zh, this message translates to:
  /// **'地址形如 http://主机:5244/dav/，账号和密码用 AList 的用户'**
  String get webdavAlistHint;

  /// No description provided for @webdavOtherHint.
  ///
  /// In zh, this message translates to:
  /// **'填写服务商提供的 WebDAV 地址、账号和密码'**
  String get webdavOtherHint;

  /// No description provided for @webdavSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'用坚果云、Nextcloud 等网盘在设备间同步'**
  String get webdavSubtitle;

  /// No description provided for @webdavNeverSynced.
  ///
  /// In zh, this message translates to:
  /// **'还没同步过'**
  String get webdavNeverSynced;

  /// No description provided for @webdavSyncedAgo.
  ///
  /// In zh, this message translates to:
  /// **'{value}同步'**
  String webdavSyncedAgo(Object value);

  /// No description provided for @webdavStopTitle.
  ///
  /// In zh, this message translates to:
  /// **'停止同步？'**
  String get webdavStopTitle;

  /// No description provided for @webdavStopBody.
  ///
  /// In zh, this message translates to:
  /// **'会删除本机保存的 WebDAV 账号和同步记录。网盘和本机上的文件都会保留；之后重新设置时会按文件内容重新比对。'**
  String get webdavStopBody;

  /// No description provided for @webdavStop.
  ///
  /// In zh, this message translates to:
  /// **'停止同步'**
  String get webdavStop;

  /// No description provided for @webdavTitle.
  ///
  /// In zh, this message translates to:
  /// **'WebDAV 同步'**
  String get webdavTitle;

  /// No description provided for @webdavConnectedTo.
  ///
  /// In zh, this message translates to:
  /// **'已连接 {host}'**
  String webdavConnectedTo(Object host);

  /// No description provided for @commonNotSet.
  ///
  /// In zh, this message translates to:
  /// **'未设置'**
  String get commonNotSet;

  /// No description provided for @webdavBody.
  ///
  /// In zh, this message translates to:
  /// **'在电脑、手机之间同步课程库和助手对话：笔记、转写稿、PPT 截图、题目与学习记录、播放进度和书签。每台设备只上传改动过的文件；两边都改过的文件保留较新的一份，另一份放进冲突文件夹。'**
  String get webdavBody;

  /// No description provided for @webdavPrivacy.
  ///
  /// In zh, this message translates to:
  /// **'登录状态、模型密钥和本机设置不会上传，每台设备分别登录。同步目录里的文件按原样保存，不做加密，请使用可信的网盘。'**
  String get webdavPrivacy;

  /// No description provided for @webdavEditAccount.
  ///
  /// In zh, this message translates to:
  /// **'修改账号'**
  String get webdavEditAccount;

  /// No description provided for @webdavConnect.
  ///
  /// In zh, this message translates to:
  /// **'连接网盘'**
  String get webdavConnect;

  /// No description provided for @webdavServer.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get webdavServer;

  /// No description provided for @webdavKeepPassword.
  ///
  /// In zh, this message translates to:
  /// **'留空则沿用已保存的密码'**
  String get webdavKeepPassword;

  /// No description provided for @webdavPasswordSealed.
  ///
  /// In zh, this message translates to:
  /// **'用本机密钥加密保存'**
  String get webdavPasswordSealed;

  /// No description provided for @webdavFolder.
  ///
  /// In zh, this message translates to:
  /// **'同步目录'**
  String get webdavFolder;

  /// No description provided for @webdavFolderHelper.
  ///
  /// In zh, this message translates to:
  /// **'在网盘里新建，所有设备填同一个'**
  String get webdavFolderHelper;

  /// No description provided for @commonAutoSync.
  ///
  /// In zh, this message translates to:
  /// **'自动同步'**
  String get commonAutoSync;

  /// No description provided for @webdavAutoHint.
  ///
  /// In zh, this message translates to:
  /// **'打开应用时、每 30 分钟，以及笔记改动约 2 分钟后'**
  String get webdavAutoHint;

  /// No description provided for @webdavMedia.
  ///
  /// In zh, this message translates to:
  /// **'同步视频与录音'**
  String get webdavMedia;

  /// No description provided for @webdavMediaHint.
  ///
  /// In zh, this message translates to:
  /// **'文件很大，会占用较多网盘空间和流量；不同步时可以在其他设备上重新下载'**
  String get webdavMediaHint;

  /// No description provided for @webdavConnectAndSync.
  ///
  /// In zh, this message translates to:
  /// **'连接并同步'**
  String get webdavConnectAndSync;

  /// No description provided for @webdavSyncing.
  ///
  /// In zh, this message translates to:
  /// **'正在同步'**
  String get webdavSyncing;

  /// No description provided for @webdavConflicts.
  ///
  /// In zh, this message translates to:
  /// **'{value} 个文件在两台设备上都改过，保留了较新的版本，另一份在冲突文件夹里'**
  String webdavConflicts(Object value);

  /// No description provided for @webdavErrors.
  ///
  /// In zh, this message translates to:
  /// **'{length} 个文件没有同步成功：{first}'**
  String webdavErrors(Object length, Object first);

  /// No description provided for @webdavMediaTitle.
  ///
  /// In zh, this message translates to:
  /// **'视频与录音'**
  String get webdavMediaTitle;

  /// No description provided for @webdavMediaOn.
  ///
  /// In zh, this message translates to:
  /// **'一起同步'**
  String get webdavMediaOn;

  /// No description provided for @webdavMediaOff.
  ///
  /// In zh, this message translates to:
  /// **'不同步，在其他设备上重新下载'**
  String get webdavMediaOff;

  /// No description provided for @commonModify.
  ///
  /// In zh, this message translates to:
  /// **'修改'**
  String get commonModify;

  /// No description provided for @syncUploaded.
  ///
  /// In zh, this message translates to:
  /// **'上传 {value}'**
  String syncUploaded(Object value);

  /// No description provided for @syncDeleted.
  ///
  /// In zh, this message translates to:
  /// **'删除 {value}'**
  String syncDeleted(Object value);

  /// No description provided for @syncInSync.
  ///
  /// In zh, this message translates to:
  /// **'两边已经一致'**
  String get syncInSync;

  /// No description provided for @backupTypeLabel.
  ///
  /// In zh, this message translates to:
  /// **'Look Studio 备份'**
  String get backupTypeLabel;

  /// No description provided for @backupFileName.
  ///
  /// In zh, this message translates to:
  /// **'LookStudio-备份-{year}{value}{value2}.zip'**
  String backupFileName(Object year, Object value, Object value2);

  /// No description provided for @backupSaved.
  ///
  /// In zh, this message translates to:
  /// **'备份已保存（{value}）'**
  String backupSaved(Object value);

  /// No description provided for @backupNotSaved.
  ///
  /// In zh, this message translates to:
  /// **'没有保存备份'**
  String get backupNotSaved;

  /// No description provided for @backupExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败：{err}'**
  String backupExportFailed(Object err);

  /// No description provided for @commonFilePickerFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开文件选择器：{message}'**
  String commonFilePickerFailed(Object message);

  /// No description provided for @backupReading.
  ///
  /// In zh, this message translates to:
  /// **'正在读取备份'**
  String get backupReading;

  /// No description provided for @backupRestoring.
  ///
  /// In zh, this message translates to:
  /// **'正在恢复'**
  String get backupRestoring;

  /// No description provided for @backupNothingToRestore.
  ///
  /// In zh, this message translates to:
  /// **'没有需要恢复的文件，本机已是最新'**
  String get backupNothingToRestore;

  /// No description provided for @backupRestored.
  ///
  /// In zh, this message translates to:
  /// **'已恢复 {value} 个文件（{value2}）'**
  String backupRestored(Object value, Object value2);

  /// No description provided for @backupViewReplaced.
  ///
  /// In zh, this message translates to:
  /// **'查看被替换的文件'**
  String get backupViewReplaced;

  /// No description provided for @backupRestoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'恢复失败：{e}'**
  String backupRestoreFailed(Object e);

  /// No description provided for @storageCleanSyncTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空同步冲突与回收站？'**
  String get storageCleanSyncTitle;

  /// No description provided for @storageCleanSyncBody.
  ///
  /// In zh, this message translates to:
  /// **'其中是同步时被替换或在其他设备上删除的文件副本，清空后无法找回。'**
  String get storageCleanSyncBody;

  /// No description provided for @commonEmpty.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get commonEmpty;

  /// No description provided for @storageFreed.
  ///
  /// In zh, this message translates to:
  /// **'已释放 {value}'**
  String storageFreed(Object value);

  /// No description provided for @storageCleanFailed.
  ///
  /// In zh, this message translates to:
  /// **'清理失败：{e}'**
  String storageCleanFailed(Object e);

  /// No description provided for @dataSyncTitle.
  ///
  /// In zh, this message translates to:
  /// **'多端同步'**
  String get dataSyncTitle;

  /// No description provided for @backupTitle.
  ///
  /// In zh, this message translates to:
  /// **'备份与恢复'**
  String get backupTitle;

  /// No description provided for @backupIntro.
  ///
  /// In zh, this message translates to:
  /// **'把课程库和助手对话打包成一个 zip，换电脑或重装时恢复。登录状态和密钥不在备份里。'**
  String get backupIntro;

  /// No description provided for @backupIncludeMedia.
  ///
  /// In zh, this message translates to:
  /// **'包含视频与录音'**
  String get backupIncludeMedia;

  /// No description provided for @backupNoMedia.
  ///
  /// In zh, this message translates to:
  /// **'课程库里还没有视频'**
  String get backupNoMedia;

  /// No description provided for @backupMediaSize.
  ///
  /// In zh, this message translates to:
  /// **'{value} 个文件，另需 {value2}'**
  String backupMediaSize(Object value, Object value2);

  /// No description provided for @backupExport.
  ///
  /// In zh, this message translates to:
  /// **'导出备份'**
  String get backupExport;

  /// No description provided for @backupExportSize.
  ///
  /// In zh, this message translates to:
  /// **'导出备份 · 约 {value}'**
  String backupExportSize(Object value);

  /// No description provided for @backupRestoreFrom.
  ///
  /// In zh, this message translates to:
  /// **'从备份恢复'**
  String get backupRestoreFrom;

  /// No description provided for @backupRestore.
  ///
  /// In zh, this message translates to:
  /// **'恢复备份'**
  String get backupRestore;

  /// No description provided for @backupPreviewMeta.
  ///
  /// In zh, this message translates to:
  /// **'{value} {value2}:{value3} 导出{value4} · {value5} 个文件 · {value6}'**
  String backupPreviewMeta(
    Object value,
    Object value2,
    Object value3,
    Object value4,
    Object value5,
    Object value6,
  );

  /// No description provided for @restoreNew.
  ///
  /// In zh, this message translates to:
  /// **'本机没有'**
  String get restoreNew;

  /// No description provided for @restoreNewer.
  ///
  /// In zh, this message translates to:
  /// **'备份里的较新'**
  String get restoreNewer;

  /// No description provided for @restoreOlder.
  ///
  /// In zh, this message translates to:
  /// **'本机的较新'**
  String get restoreOlder;

  /// No description provided for @restoreSame.
  ///
  /// In zh, this message translates to:
  /// **'相同'**
  String get restoreSame;

  /// No description provided for @restoreSkipped.
  ///
  /// In zh, this message translates to:
  /// **'不会恢复（密钥或无效路径）'**
  String get restoreSkipped;

  /// No description provided for @restoreMerge.
  ///
  /// In zh, this message translates to:
  /// **'合并'**
  String get restoreMerge;

  /// No description provided for @restoreOverwrite.
  ///
  /// In zh, this message translates to:
  /// **'以备份为准'**
  String get restoreOverwrite;

  /// No description provided for @restoreMergeHint.
  ///
  /// In zh, this message translates to:
  /// **'补上本机没有的文件，更新较旧的文件；本机较新的文件保持不变。'**
  String get restoreMergeHint;

  /// No description provided for @restoreOverwriteHint.
  ///
  /// In zh, this message translates to:
  /// **'所有文件换成备份里的版本；被替换的较新文件会移到课程库的 .sync-conflicts 文件夹。'**
  String get restoreOverwriteHint;

  /// No description provided for @commonRestore.
  ///
  /// In zh, this message translates to:
  /// **'恢复'**
  String get commonRestore;

  /// No description provided for @storageTitle.
  ///
  /// In zh, this message translates to:
  /// **'存储空间'**
  String get storageTitle;

  /// No description provided for @storageCache.
  ///
  /// In zh, this message translates to:
  /// **'转写缓存与未完成下载'**
  String get storageCache;

  /// No description provided for @storageCacheCleanable.
  ///
  /// In zh, this message translates to:
  /// **'可释放 {value} · 进行中和暂停的任务会保留'**
  String storageCacheCleanable(Object value);

  /// No description provided for @storageCacheEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有可清理的缓存'**
  String get storageCacheEmpty;

  /// No description provided for @commonClean.
  ///
  /// In zh, this message translates to:
  /// **'清理'**
  String get commonClean;

  /// No description provided for @storageCleaningCache.
  ///
  /// In zh, this message translates to:
  /// **'正在清理缓存'**
  String get storageCleaningCache;

  /// No description provided for @storageSync.
  ///
  /// In zh, this message translates to:
  /// **'同步冲突与回收站'**
  String get storageSync;

  /// No description provided for @storageSyncSize.
  ///
  /// In zh, this message translates to:
  /// **'{value} · 同步时替换或删除的文件副本'**
  String storageSyncSize(Object value);

  /// No description provided for @storageNoFiles.
  ///
  /// In zh, this message translates to:
  /// **'没有文件'**
  String get storageNoFiles;

  /// No description provided for @storageEmptying.
  ///
  /// In zh, this message translates to:
  /// **'正在清空'**
  String get storageEmptying;

  /// No description provided for @storageCompact.
  ///
  /// In zh, this message translates to:
  /// **'整理索引'**
  String get storageCompact;

  /// No description provided for @storageCompactHint.
  ///
  /// In zh, this message translates to:
  /// **'合并写入日志、回收空闲空间，让搜索和列表更快'**
  String get storageCompactHint;

  /// No description provided for @storageCompactAction.
  ///
  /// In zh, this message translates to:
  /// **'整理'**
  String get storageCompactAction;

  /// No description provided for @storageCompacting.
  ///
  /// In zh, this message translates to:
  /// **'正在整理索引'**
  String get storageCompacting;

  /// No description provided for @storageModels.
  ///
  /// In zh, this message translates to:
  /// **'本地语音模型'**
  String get storageModels;

  /// No description provided for @storageAssistant.
  ///
  /// In zh, this message translates to:
  /// **'助手对话、记忆与插件'**
  String get storageAssistant;

  /// No description provided for @storageRuntime.
  ///
  /// In zh, this message translates to:
  /// **'助手运行环境（Node.js 与依赖）'**
  String get storageRuntime;

  /// No description provided for @diagDaemon.
  ///
  /// In zh, this message translates to:
  /// **'后台服务'**
  String get diagDaemon;

  /// No description provided for @diagDaemonDetail.
  ///
  /// In zh, this message translates to:
  /// **'版本 {value} · 端口 {port}'**
  String diagDaemonDetail(Object value, Object port);

  /// No description provided for @diagNotStarted.
  ///
  /// In zh, this message translates to:
  /// **'没有启动'**
  String get diagNotStarted;

  /// No description provided for @commonStarting.
  ///
  /// In zh, this message translates to:
  /// **'正在启动'**
  String get commonStarting;

  /// No description provided for @diagWorkspace.
  ///
  /// In zh, this message translates to:
  /// **'Linux 工作区'**
  String get diagWorkspace;

  /// No description provided for @diagFfmpegOk.
  ///
  /// In zh, this message translates to:
  /// **'转写可用'**
  String get diagFfmpegOk;

  /// No description provided for @diagFfmpegMissingWorkspace.
  ///
  /// In zh, this message translates to:
  /// **'未安装，转写需要它'**
  String get diagFfmpegMissingWorkspace;

  /// No description provided for @diagFfmpegMissing.
  ///
  /// In zh, this message translates to:
  /// **'未找到，请用系统的包管理器安装后重启后台'**
  String get diagFfmpegMissing;

  /// No description provided for @diagAgentRunningNode.
  ///
  /// In zh, this message translates to:
  /// **'运行中 · Node.js {value}'**
  String diagAgentRunningNode(Object value);

  /// No description provided for @diagAgentNotRunning.
  ///
  /// In zh, this message translates to:
  /// **'没有运行'**
  String get diagAgentNotRunning;

  /// No description provided for @diagSetupRuntime.
  ///
  /// In zh, this message translates to:
  /// **'设置运行环境'**
  String get diagSetupRuntime;

  /// No description provided for @diagReportLine.
  ///
  /// In zh, this message translates to:
  /// **'{title}：{detail}'**
  String diagReportLine(Object title, Object detail);

  /// No description provided for @diagReportLibrary.
  ///
  /// In zh, this message translates to:
  /// **'课程库：{value}'**
  String diagReportLibrary(Object value);

  /// No description provided for @diagWorkspaceSuffix.
  ///
  /// In zh, this message translates to:
  /// **' · Linux 工作区'**
  String get diagWorkspaceSuffix;

  /// No description provided for @diagCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制诊断信息'**
  String get diagCopied;

  /// No description provided for @diagStatus.
  ///
  /// In zh, this message translates to:
  /// **'运行状态'**
  String get diagStatus;

  /// No description provided for @diagLogs.
  ///
  /// In zh, this message translates to:
  /// **'日志'**
  String get diagLogs;

  /// No description provided for @diagDaemonLog.
  ///
  /// In zh, this message translates to:
  /// **'后台日志'**
  String get diagDaemonLog;

  /// No description provided for @diagAgentLog.
  ///
  /// In zh, this message translates to:
  /// **'助手日志'**
  String get diagAgentLog;

  /// No description provided for @diagMaintenance.
  ///
  /// In zh, this message translates to:
  /// **'维护'**
  String get diagMaintenance;

  /// No description provided for @diagRestart.
  ///
  /// In zh, this message translates to:
  /// **'重启后台服务'**
  String get diagRestart;

  /// No description provided for @diagRestartHint.
  ///
  /// In zh, this message translates to:
  /// **'后台没有响应时使用；下载和转写会在重启后继续'**
  String get diagRestartHint;

  /// No description provided for @diagRestartAction.
  ///
  /// In zh, this message translates to:
  /// **'重启'**
  String get diagRestartAction;

  /// No description provided for @diagIssues.
  ///
  /// In zh, this message translates to:
  /// **'{issues} 项需要处理'**
  String diagIssues(Object issues);

  /// No description provided for @diagAllGood.
  ///
  /// In zh, this message translates to:
  /// **'一切正常'**
  String get diagAllGood;

  /// No description provided for @diagCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制诊断信息'**
  String get diagCopy;

  /// No description provided for @diagOk.
  ///
  /// In zh, this message translates to:
  /// **'正常'**
  String get diagOk;

  /// No description provided for @commonNeedsAttention.
  ///
  /// In zh, this message translates to:
  /// **'需要处理'**
  String get commonNeedsAttention;

  /// No description provided for @diagChecking.
  ///
  /// In zh, this message translates to:
  /// **'检查中'**
  String get diagChecking;

  /// No description provided for @commonCopyPath.
  ///
  /// In zh, this message translates to:
  /// **'复制路径'**
  String get commonCopyPath;

  /// No description provided for @commonPathCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制路径'**
  String get commonPathCopied;

  /// No description provided for @diagLogEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无记录'**
  String get diagLogEmpty;

  /// No description provided for @diagLogLines.
  ///
  /// In zh, this message translates to:
  /// **'{length} 行'**
  String diagLogLines(Object length);

  /// No description provided for @diagLogRecent.
  ///
  /// In zh, this message translates to:
  /// **'最近 {length} 行'**
  String diagLogRecent(Object length);

  /// No description provided for @commonCopyAll.
  ///
  /// In zh, this message translates to:
  /// **'复制全部'**
  String get commonCopyAll;

  /// No description provided for @diagLogCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制日志'**
  String get diagLogCopied;

  /// No description provided for @diagLogNothing.
  ///
  /// In zh, this message translates to:
  /// **'后台还没有写下任何记录'**
  String get diagLogNothing;

  /// No description provided for @settingsAccount.
  ///
  /// In zh, this message translates to:
  /// **'账户与学校'**
  String get settingsAccount;

  /// No description provided for @settingsAccountHint.
  ///
  /// In zh, this message translates to:
  /// **'统一身份认证、Canvas'**
  String get settingsAccountHint;

  /// No description provided for @authTongji.
  ///
  /// In zh, this message translates to:
  /// **'统一身份认证'**
  String get authTongji;

  /// No description provided for @authRenewNow.
  ///
  /// In zh, this message translates to:
  /// **'立即续期'**
  String get authRenewNow;

  /// No description provided for @authSignOut.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get authSignOut;

  /// No description provided for @settingsProfileKeyword.
  ///
  /// In zh, this message translates to:
  /// **'昵称和头像'**
  String get settingsProfileKeyword;

  /// No description provided for @commonSchool.
  ///
  /// In zh, this message translates to:
  /// **'学校'**
  String get commonSchool;

  /// No description provided for @settingsCanvasKeyword.
  ///
  /// In zh, this message translates to:
  /// **'作业与课件'**
  String get settingsCanvasKeyword;

  /// No description provided for @settingsAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观与播放'**
  String get settingsAppearance;

  /// No description provided for @settingsAppearanceHint.
  ///
  /// In zh, this message translates to:
  /// **'主题、字体、播放器'**
  String get settingsAppearanceHint;

  /// No description provided for @settingsDarkMode.
  ///
  /// In zh, this message translates to:
  /// **'深色模式'**
  String get settingsDarkMode;

  /// No description provided for @settingsThemeColor.
  ///
  /// In zh, this message translates to:
  /// **'主题色'**
  String get settingsThemeColor;

  /// No description provided for @settingsSystemAccent.
  ///
  /// In zh, this message translates to:
  /// **'系统强调色'**
  String get settingsSystemAccent;

  /// No description provided for @settingsSchemeStyle.
  ///
  /// In zh, this message translates to:
  /// **'配色风格'**
  String get settingsSchemeStyle;

  /// No description provided for @settingsContrast.
  ///
  /// In zh, this message translates to:
  /// **'对比度'**
  String get settingsContrast;

  /// No description provided for @settingsFont.
  ///
  /// In zh, this message translates to:
  /// **'字体'**
  String get settingsFont;

  /// No description provided for @settingsTextSize.
  ///
  /// In zh, this message translates to:
  /// **'文字大小'**
  String get settingsTextSize;

  /// No description provided for @settingsCompact.
  ///
  /// In zh, this message translates to:
  /// **'紧凑布局'**
  String get settingsCompact;

  /// No description provided for @settingsReduceMotion.
  ///
  /// In zh, this message translates to:
  /// **'减少动画'**
  String get settingsReduceMotion;

  /// No description provided for @settingsDefaultSpeed.
  ///
  /// In zh, this message translates to:
  /// **'默认倍速'**
  String get settingsDefaultSpeed;

  /// No description provided for @settingsBoostSpeed.
  ///
  /// In zh, this message translates to:
  /// **'长按快进倍速'**
  String get settingsBoostSpeed;

  /// No description provided for @settingsSeekStepKeyword.
  ///
  /// In zh, this message translates to:
  /// **'快进快退步长'**
  String get settingsSeekStepKeyword;

  /// No description provided for @settingsSubtitleSize.
  ///
  /// In zh, this message translates to:
  /// **'字幕大小'**
  String get settingsSubtitleSize;

  /// No description provided for @settingsResume.
  ///
  /// In zh, this message translates to:
  /// **'从上次位置继续'**
  String get settingsResume;

  /// No description provided for @settingsShowSubtitles.
  ///
  /// In zh, this message translates to:
  /// **'显示字幕'**
  String get settingsShowSubtitles;

  /// No description provided for @settingsSlidesFollow.
  ///
  /// In zh, this message translates to:
  /// **'PPT 跟随播放'**
  String get settingsSlidesFollow;

  /// No description provided for @settingsShortcuts.
  ///
  /// In zh, this message translates to:
  /// **'快捷键'**
  String get settingsShortcuts;

  /// No description provided for @settingsAssistant.
  ///
  /// In zh, this message translates to:
  /// **'助手与插件'**
  String get settingsAssistant;

  /// No description provided for @settingsAssistantHint.
  ///
  /// In zh, this message translates to:
  /// **'模型、Bot、插件'**
  String get settingsAssistantHint;

  /// No description provided for @settingsModels.
  ///
  /// In zh, this message translates to:
  /// **'模型与服务商'**
  String get settingsModels;

  /// No description provided for @settingsVisionModel.
  ///
  /// In zh, this message translates to:
  /// **'识图模型'**
  String get settingsVisionModel;

  /// No description provided for @settingsBotKeyword.
  ///
  /// In zh, this message translates to:
  /// **'Bot 形象与记忆'**
  String get settingsBotKeyword;

  /// No description provided for @settingsRuntimeKeyword.
  ///
  /// In zh, this message translates to:
  /// **'运行环境 Node.js'**
  String get settingsRuntimeKeyword;

  /// No description provided for @settingsUsage.
  ///
  /// In zh, this message translates to:
  /// **'用量与费用'**
  String get settingsUsage;

  /// No description provided for @settingsDockKeyword.
  ///
  /// In zh, this message translates to:
  /// **'宽屏常驻右侧'**
  String get settingsDockKeyword;

  /// No description provided for @settingsBubblesKeyword.
  ///
  /// In zh, this message translates to:
  /// **'回复气泡'**
  String get settingsBubblesKeyword;

  /// No description provided for @settingsShowThinking.
  ///
  /// In zh, this message translates to:
  /// **'显示思考过程'**
  String get settingsShowThinking;

  /// No description provided for @settingsStreamAnimation.
  ///
  /// In zh, this message translates to:
  /// **'流式输出动画'**
  String get settingsStreamAnimation;

  /// No description provided for @settingsChatTextSize.
  ///
  /// In zh, this message translates to:
  /// **'对话文字大小'**
  String get settingsChatTextSize;

  /// No description provided for @settingsTransfer.
  ///
  /// In zh, this message translates to:
  /// **'下载与转写'**
  String get settingsTransfer;

  /// No description provided for @settingsTransferHint.
  ///
  /// In zh, this message translates to:
  /// **'下载速度、语音转写、课件解析'**
  String get settingsTransferHint;

  /// No description provided for @settingsConnectionsKeyword.
  ///
  /// In zh, this message translates to:
  /// **'并发连接'**
  String get settingsConnectionsKeyword;

  /// No description provided for @settingsVideoParallel.
  ///
  /// In zh, this message translates to:
  /// **'同时下载的视频数'**
  String get settingsVideoParallel;

  /// No description provided for @settingsRateLimit.
  ///
  /// In zh, this message translates to:
  /// **'总速度上限'**
  String get settingsRateLimit;

  /// No description provided for @settingsStream.
  ///
  /// In zh, this message translates to:
  /// **'下载哪个画面'**
  String get settingsStream;

  /// No description provided for @settingsAsrChannels.
  ///
  /// In zh, this message translates to:
  /// **'转写渠道'**
  String get settingsAsrChannels;

  /// No description provided for @settingsLocalModels.
  ///
  /// In zh, this message translates to:
  /// **'本地模型'**
  String get settingsLocalModels;

  /// No description provided for @settingsMineru.
  ///
  /// In zh, this message translates to:
  /// **'MinerU 课件解析'**
  String get settingsMineru;

  /// No description provided for @settingsKnowledge.
  ///
  /// In zh, this message translates to:
  /// **'知识库'**
  String get settingsKnowledge;

  /// No description provided for @settingsKnowledgeHint.
  ///
  /// In zh, this message translates to:
  /// **'课程库、Obsidian、Notion'**
  String get settingsKnowledgeHint;

  /// No description provided for @settingsLibraryLocation.
  ///
  /// In zh, this message translates to:
  /// **'课程库位置'**
  String get settingsLibraryLocation;

  /// No description provided for @settingsSkillExport.
  ///
  /// In zh, this message translates to:
  /// **'技能格式导出'**
  String get settingsSkillExport;

  /// No description provided for @settingsData.
  ///
  /// In zh, this message translates to:
  /// **'数据与同步'**
  String get settingsData;

  /// No description provided for @settingsDataHint.
  ///
  /// In zh, this message translates to:
  /// **'WebDAV 同步、备份恢复、存储空间'**
  String get settingsDataHint;

  /// No description provided for @settingsSyncMedia.
  ///
  /// In zh, this message translates to:
  /// **'同步视频'**
  String get settingsSyncMedia;

  /// No description provided for @settingsCleanCache.
  ///
  /// In zh, this message translates to:
  /// **'清理缓存'**
  String get settingsCleanCache;

  /// No description provided for @commonNotifications.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get commonNotifications;

  /// No description provided for @settingsNotificationsHint.
  ///
  /// In zh, this message translates to:
  /// **'新回放、新课次与自动检查'**
  String get settingsNotificationsHint;

  /// No description provided for @settingsWatchKeyword.
  ///
  /// In zh, this message translates to:
  /// **'自动检查新回放'**
  String get settingsWatchKeyword;

  /// No description provided for @settingsRemindersKeyword.
  ///
  /// In zh, this message translates to:
  /// **'提醒'**
  String get settingsRemindersKeyword;

  /// No description provided for @settingsDiagnostics.
  ///
  /// In zh, this message translates to:
  /// **'诊断'**
  String get settingsDiagnostics;

  /// No description provided for @settingsDiagnosticsHint.
  ///
  /// In zh, this message translates to:
  /// **'后台状态与日志'**
  String get settingsDiagnosticsHint;

  /// No description provided for @settingsDaemonKeyword.
  ///
  /// In zh, this message translates to:
  /// **'后台服务'**
  String get settingsDaemonKeyword;

  /// No description provided for @settingsRestartKeyword.
  ///
  /// In zh, this message translates to:
  /// **'重启后台服务'**
  String get settingsRestartKeyword;

  /// No description provided for @settingsSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索设置'**
  String get settingsSearch;

  /// No description provided for @commonClear.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get commonClear;

  /// No description provided for @settingsNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'没有和「{value}」相关的设置'**
  String settingsNoMatch(Object value);

  /// No description provided for @settingsSchoolCanvas.
  ///
  /// In zh, this message translates to:
  /// **'学校与 Canvas'**
  String get settingsSchoolCanvas;

  /// No description provided for @settingsAppearanceGroup.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get settingsAppearanceGroup;

  /// No description provided for @settingsWatchGroup.
  ///
  /// In zh, this message translates to:
  /// **'通知与自动刷新'**
  String get settingsWatchGroup;

  /// No description provided for @commonUnlimited.
  ///
  /// In zh, this message translates to:
  /// **'不限'**
  String get commonUnlimited;

  /// No description provided for @settingsConnections.
  ///
  /// In zh, this message translates to:
  /// **'单个视频的并发连接'**
  String get settingsConnections;

  /// No description provided for @settingsConnectionsHint.
  ///
  /// In zh, this message translates to:
  /// **'分段并行下载，支持断点续传；校园网瓶颈时增加连接帮助有限'**
  String get settingsConnectionsHint;

  /// No description provided for @settingsConnectionsValue.
  ///
  /// In zh, this message translates to:
  /// **'{value} 路'**
  String settingsConnectionsValue(Object value);

  /// No description provided for @settingsVideoParallelValue.
  ///
  /// In zh, this message translates to:
  /// **'{value} 个'**
  String settingsVideoParallelValue(Object value);

  /// No description provided for @commonAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get commonAuto;

  /// No description provided for @streamScreen.
  ///
  /// In zh, this message translates to:
  /// **'屏幕'**
  String get streamScreen;

  /// No description provided for @streamTeacher.
  ///
  /// In zh, this message translates to:
  /// **'教师'**
  String get streamTeacher;

  /// No description provided for @streamStudent.
  ///
  /// In zh, this message translates to:
  /// **'学生'**
  String get streamStudent;

  /// No description provided for @settingsStreamHint.
  ///
  /// In zh, this message translates to:
  /// **'自动：优先屏幕（含 PPT），没有时用第一个画面。'**
  String get settingsStreamHint;

  /// No description provided for @settingsAccountSummary.
  ///
  /// In zh, this message translates to:
  /// **'{value} · 同济大学 · Canvas'**
  String settingsAccountSummary(Object value);

  /// No description provided for @authSignedIn.
  ///
  /// In zh, this message translates to:
  /// **'已登录'**
  String get authSignedIn;

  /// No description provided for @authSignedOut.
  ///
  /// In zh, this message translates to:
  /// **'未登录'**
  String get authSignedOut;

  /// No description provided for @authRenewing.
  ///
  /// In zh, this message translates to:
  /// **'正在续期…'**
  String get authRenewing;

  /// No description provided for @authNeedsSignIn.
  ///
  /// In zh, this message translates to:
  /// **'需要重新登录'**
  String get authNeedsSignIn;

  /// No description provided for @authMethodPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码登录'**
  String get authMethodPassword;

  /// No description provided for @authMethodSso.
  ///
  /// In zh, this message translates to:
  /// **'统一认证静默续期'**
  String get authMethodSso;

  /// No description provided for @authMethodSavedPassword.
  ///
  /// In zh, this message translates to:
  /// **'已保存的密码续期'**
  String get authMethodSavedPassword;

  /// No description provided for @authMethodRestored.
  ///
  /// In zh, this message translates to:
  /// **'从本地会话恢复'**
  String get authMethodRestored;

  /// No description provided for @profileEditTooltip.
  ///
  /// In zh, this message translates to:
  /// **'编辑昵称和头像'**
  String get profileEditTooltip;

  /// No description provided for @schoolTongji.
  ///
  /// In zh, this message translates to:
  /// **'同济大学'**
  String get schoolTongji;

  /// No description provided for @schoolFudan.
  ///
  /// In zh, this message translates to:
  /// **'复旦大学'**
  String get schoolFudan;

  /// No description provided for @settingsAbout.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get settingsAbout;

  /// No description provided for @settingsAboutHint.
  ///
  /// In zh, this message translates to:
  /// **'版本、更新和反馈'**
  String get settingsAboutHint;

  /// No description provided for @aboutVersion.
  ///
  /// In zh, this message translates to:
  /// **'版本 {value}'**
  String aboutVersion(Object value);

  /// No description provided for @aboutUpdates.
  ///
  /// In zh, this message translates to:
  /// **'更新'**
  String get aboutUpdates;

  /// No description provided for @aboutCheckHint.
  ///
  /// In zh, this message translates to:
  /// **'从 GitHub Releases 检查是否有新版本'**
  String get aboutCheckHint;

  /// No description provided for @aboutChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在检查…'**
  String get aboutChecking;

  /// No description provided for @aboutCheckUpdates.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get aboutCheckUpdates;

  /// No description provided for @aboutUpToDate.
  ///
  /// In zh, this message translates to:
  /// **'已是最新版本'**
  String get aboutUpToDate;

  /// No description provided for @aboutNewVersion.
  ///
  /// In zh, this message translates to:
  /// **'有新版本 {version}（{when}发布）'**
  String aboutNewVersion(Object version, Object when);

  /// No description provided for @aboutDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载 {version}'**
  String aboutDownload(Object version);

  /// No description provided for @aboutReleaseNotes.
  ///
  /// In zh, this message translates to:
  /// **'查看更新说明'**
  String get aboutReleaseNotes;

  /// No description provided for @aboutCheckFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法检查更新：{e}。请检查网络后重试。'**
  String aboutCheckFailed(Object e);

  /// No description provided for @aboutLinks.
  ///
  /// In zh, this message translates to:
  /// **'链接'**
  String get aboutLinks;

  /// No description provided for @aboutRepo.
  ///
  /// In zh, this message translates to:
  /// **'代码仓库'**
  String get aboutRepo;

  /// No description provided for @aboutFeedback.
  ///
  /// In zh, this message translates to:
  /// **'反馈问题'**
  String get aboutFeedback;

  /// No description provided for @aboutFeedbackHint.
  ///
  /// In zh, this message translates to:
  /// **'在 GitHub 提交问题，自动附上版本和系统'**
  String get aboutFeedbackHint;

  /// No description provided for @aboutFeedbackBody.
  ///
  /// In zh, this message translates to:
  /// **'请描述遇到的问题和复现步骤：\n\n\n---\n版本：{version}\n系统：{os}'**
  String aboutFeedbackBody(Object version, Object os);

  /// No description provided for @authExpires.
  ///
  /// In zh, this message translates to:
  /// **'凭证 {value}后到期，会在到期前自动续期'**
  String authExpires(Object value);

  /// No description provided for @authLastRenewed.
  ///
  /// In zh, this message translates to:
  /// **'上次续期 {value}（{method}）'**
  String authLastRenewed(Object value, Object method);

  /// No description provided for @authPasswordSaved.
  ///
  /// In zh, this message translates to:
  /// **'已在本机加密保存密码，统一认证失效时用于自动登录'**
  String get authPasswordSaved;

  /// No description provided for @authPasswordNotSaved.
  ///
  /// In zh, this message translates to:
  /// **'未保存密码：统一认证会话失效后需要手动登录'**
  String get authPasswordNotSaved;

  /// No description provided for @authRenewed.
  ///
  /// In zh, this message translates to:
  /// **'已续期'**
  String get authRenewed;

  /// No description provided for @authRenewFailed.
  ///
  /// In zh, this message translates to:
  /// **'续期失败：{e}'**
  String authRenewFailed(Object e);

  /// No description provided for @authSignOutTitle.
  ///
  /// In zh, this message translates to:
  /// **'退出登录？'**
  String get authSignOutTitle;

  /// No description provided for @authSignOutBody.
  ///
  /// In zh, this message translates to:
  /// **'会清除本机保存的会话和密码。已下载的文件不受影响。'**
  String get authSignOutBody;

  /// No description provided for @authSignOutAction.
  ///
  /// In zh, this message translates to:
  /// **'退出'**
  String get authSignOutAction;

  /// No description provided for @themeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @settingsUseSystemAccent.
  ///
  /// In zh, this message translates to:
  /// **'使用系统强调色'**
  String get settingsUseSystemAccent;

  /// No description provided for @settingsUseSystemAccentHint.
  ///
  /// In zh, this message translates to:
  /// **'从系统主题取色生成配色'**
  String get settingsUseSystemAccentHint;

  /// No description provided for @settingsBoostSpeedHint.
  ///
  /// In zh, this message translates to:
  /// **'长按画面或按住 → 键临时加速'**
  String get settingsBoostSpeedHint;

  /// No description provided for @settingsSeekStep.
  ///
  /// In zh, this message translates to:
  /// **'快进 / 快退步长'**
  String get settingsSeekStep;

  /// No description provided for @commonSecondsValue.
  ///
  /// In zh, this message translates to:
  /// **'{seekStepSec} 秒'**
  String commonSecondsValue(Object seekStepSec);

  /// No description provided for @settingsShowSubtitlesHint.
  ///
  /// In zh, this message translates to:
  /// **'有文字稿时显示字幕'**
  String get settingsShowSubtitlesHint;

  /// No description provided for @settingsSlidesFollowHint.
  ///
  /// In zh, this message translates to:
  /// **'PPT 跟随播放进度'**
  String get settingsSlidesFollowHint;

  /// No description provided for @settingsShortcutsBody.
  ///
  /// In zh, this message translates to:
  /// **'快捷键：空格 播放/暂停 · ←/→ 快退/快进 · ↑/↓ 音量 · [ ] 倍速 · F 全屏 · C 字幕 · B 书签 · P 侧栏 · M 静音'**
  String get settingsShortcutsBody;

  /// No description provided for @commonNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置'**
  String get commonNotConfigured;

  /// No description provided for @settingsBotHint.
  ///
  /// In zh, this message translates to:
  /// **'常驻 bot 的形象、记忆与学习方式'**
  String get settingsBotHint;

  /// No description provided for @settingsRuntime.
  ///
  /// In zh, this message translates to:
  /// **'运行环境'**
  String get settingsRuntime;

  /// No description provided for @settingsRuntimeReady.
  ///
  /// In zh, this message translates to:
  /// **'Node.js 与 Pi SDK 已就绪'**
  String get settingsRuntimeReady;

  /// No description provided for @settingsRuntimeMissing.
  ///
  /// In zh, this message translates to:
  /// **'助手未运行 · 检查或安装 Node.js 与 Pi SDK'**
  String get settingsRuntimeMissing;

  /// No description provided for @settingsUsageHint.
  ///
  /// In zh, this message translates to:
  /// **'按模型、用途和对话查看 token 与估算费用'**
  String get settingsUsageHint;

  /// No description provided for @settingsTasksHint.
  ///
  /// In zh, this message translates to:
  /// **'让助手按计划复盘、出题、汇总截止事项'**
  String get settingsTasksHint;

  /// No description provided for @settingsDock.
  ///
  /// In zh, this message translates to:
  /// **'宽屏时常驻在右侧'**
  String get settingsDock;

  /// No description provided for @settingsBubbles.
  ///
  /// In zh, this message translates to:
  /// **'回复使用气泡'**
  String get settingsBubbles;

  /// No description provided for @streamFade.
  ///
  /// In zh, this message translates to:
  /// **'淡入'**
  String get streamFade;

  /// No description provided for @streamBlur.
  ///
  /// In zh, this message translates to:
  /// **'模糊显现'**
  String get streamBlur;

  /// No description provided for @streamTypewriter.
  ///
  /// In zh, this message translates to:
  /// **'打字机'**
  String get streamTypewriter;

  /// No description provided for @streamWave.
  ///
  /// In zh, this message translates to:
  /// **'波浪'**
  String get streamWave;

  /// No description provided for @visionNative.
  ///
  /// In zh, this message translates to:
  /// **'当前模型可以直接看 PPT 和插图{value}'**
  String visionNative(Object value);

  /// No description provided for @visionNativeFallback.
  ///
  /// In zh, this message translates to:
  /// **'；换成纯文本模型时使用 {vision}'**
  String visionNativeFallback(Object vision);

  /// No description provided for @visionNeeded.
  ///
  /// In zh, this message translates to:
  /// **'当前模型不能看图。选一个识图模型，助手写笔记时才能核对 PPT 和课件插图'**
  String get visionNeeded;

  /// No description provided for @visionUsing.
  ///
  /// In zh, this message translates to:
  /// **'{vision} · 为纯文本模型转写 PPT 和插图'**
  String visionUsing(Object vision);

  /// No description provided for @visionUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'{vision} 不可用（检查服务商密钥）'**
  String visionUnavailable(Object vision);

  /// No description provided for @visionBody.
  ///
  /// In zh, this message translates to:
  /// **'只用来把 PPT 和课件插图转写成文字，交给不能看图的对话模型。结果按图片缓存，同一张图只识别一次。'**
  String get visionBody;

  /// No description provided for @visionNone.
  ///
  /// In zh, this message translates to:
  /// **'不使用'**
  String get visionNone;

  /// No description provided for @visionNoModels.
  ///
  /// In zh, this message translates to:
  /// **'已配置的服务商里没有支持图片输入的模型。'**
  String get visionNoModels;

  /// No description provided for @commonImage.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get commonImage;

  /// No description provided for @profileImageFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法使用这张图片：{e}'**
  String profileImageFailed(Object e);

  /// No description provided for @profilePickEmoji.
  ///
  /// In zh, this message translates to:
  /// **'选择表情'**
  String get profilePickEmoji;

  /// No description provided for @profileFromFile.
  ///
  /// In zh, this message translates to:
  /// **'从图片文件…'**
  String get profileFromFile;

  /// No description provided for @profileFromUrl.
  ///
  /// In zh, this message translates to:
  /// **'输入图片链接…'**
  String get profileFromUrl;

  /// No description provided for @profileFromQq.
  ///
  /// In zh, this message translates to:
  /// **'使用 QQ 头像…'**
  String get profileFromQq;

  /// No description provided for @profileRandomShape.
  ///
  /// In zh, this message translates to:
  /// **'随机生成图形'**
  String get profileRandomShape;

  /// No description provided for @profileResetInitial.
  ///
  /// In zh, this message translates to:
  /// **'重置为首字'**
  String get profileResetInitial;

  /// No description provided for @profileTitle.
  ///
  /// In zh, this message translates to:
  /// **'个人资料'**
  String get profileTitle;

  /// No description provided for @profileLocalOnly.
  ///
  /// In zh, this message translates to:
  /// **'昵称和头像只保存在本机'**
  String get profileLocalOnly;

  /// No description provided for @profileNickname.
  ///
  /// In zh, this message translates to:
  /// **'昵称'**
  String get profileNickname;

  /// No description provided for @profileNicknameHelper.
  ///
  /// In zh, this message translates to:
  /// **'留空则显示「{fallback}」'**
  String profileNicknameHelper(Object fallback);

  /// No description provided for @profileInspiration.
  ///
  /// In zh, this message translates to:
  /// **'灵感'**
  String get profileInspiration;

  /// No description provided for @profileTapToUse.
  ///
  /// In zh, this message translates to:
  /// **'点一下换上'**
  String get profileTapToUse;

  /// No description provided for @profileShuffle.
  ///
  /// In zh, this message translates to:
  /// **'换一批'**
  String get profileShuffle;

  /// No description provided for @profileShape.
  ///
  /// In zh, this message translates to:
  /// **'轮廓'**
  String get profileShape;

  /// No description provided for @profileBackground.
  ///
  /// In zh, this message translates to:
  /// **'底色'**
  String get profileBackground;

  /// No description provided for @profileShowQuote.
  ///
  /// In zh, this message translates to:
  /// **'首页显示一言'**
  String get profileShowQuote;

  /// No description provided for @profileShowQuoteHint.
  ///
  /// In zh, this message translates to:
  /// **'欢迎语下方展示一句文学、诗词或哲思'**
  String get profileShowQuoteHint;

  /// No description provided for @profileChangeAvatar.
  ///
  /// In zh, this message translates to:
  /// **'更换头像'**
  String get profileChangeAvatar;

  /// No description provided for @profileBackgroundIndex.
  ///
  /// In zh, this message translates to:
  /// **'底色 {index}'**
  String profileBackgroundIndex(Object index);

  /// No description provided for @profileUseQq.
  ///
  /// In zh, this message translates to:
  /// **'使用 QQ 头像'**
  String get profileUseQq;

  /// No description provided for @profileImageUrl.
  ///
  /// In zh, this message translates to:
  /// **'图片链接'**
  String get profileImageUrl;

  /// No description provided for @profileQqNumber.
  ///
  /// In zh, this message translates to:
  /// **'QQ 号'**
  String get profileQqNumber;

  /// No description provided for @profileImageAddress.
  ///
  /// In zh, this message translates to:
  /// **'图片地址'**
  String get profileImageAddress;

  /// No description provided for @profileQqHint.
  ///
  /// In zh, this message translates to:
  /// **'5–12 位数字'**
  String get profileQqHint;

  /// No description provided for @profileQqInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入 5–12 位 QQ 号'**
  String get profileQqInvalid;

  /// No description provided for @profileUrlInvalid.
  ///
  /// In zh, this message translates to:
  /// **'需要 http(s) 链接'**
  String get profileUrlInvalid;

  /// No description provided for @profileQqNote.
  ///
  /// In zh, this message translates to:
  /// **'头像从 QQ 公开头像服务加载，需要联网'**
  String get profileQqNote;

  /// No description provided for @commonUse.
  ///
  /// In zh, this message translates to:
  /// **'使用'**
  String get commonUse;

  /// No description provided for @emojiStudy.
  ///
  /// In zh, this message translates to:
  /// **'学习'**
  String get emojiStudy;

  /// No description provided for @emojiFaces.
  ///
  /// In zh, this message translates to:
  /// **'表情'**
  String get emojiFaces;

  /// No description provided for @emojiAnimals.
  ///
  /// In zh, this message translates to:
  /// **'动物'**
  String get emojiAnimals;

  /// No description provided for @emojiNature.
  ///
  /// In zh, this message translates to:
  /// **'自然'**
  String get emojiNature;

  /// No description provided for @emojiFood.
  ///
  /// In zh, this message translates to:
  /// **'食物'**
  String get emojiFood;

  /// No description provided for @emojiHobbies.
  ///
  /// In zh, this message translates to:
  /// **'爱好'**
  String get emojiHobbies;

  /// No description provided for @profileEmojiHint.
  ///
  /// In zh, this message translates to:
  /// **'输入或粘贴任意表情'**
  String get profileEmojiHint;

  /// No description provided for @scheduleNoTodos.
  ///
  /// In zh, this message translates to:
  /// **'没有待办'**
  String get scheduleNoTodos;

  /// No description provided for @scheduleOpenTodos.
  ///
  /// In zh, this message translates to:
  /// **'{open} 项待办'**
  String scheduleOpenTodos(Object open);

  /// No description provided for @scheduleOverdue.
  ///
  /// In zh, this message translates to:
  /// **'{overdue} 项已逾期'**
  String scheduleOverdue(Object overdue);

  /// No description provided for @scheduleTodos.
  ///
  /// In zh, this message translates to:
  /// **'待办'**
  String get scheduleTodos;

  /// No description provided for @scheduleEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有日程'**
  String get scheduleEmpty;

  /// No description provided for @scheduleEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'老师在课上说到带日期的作业、考试或活动时，助手可以把它标记进来，并附上原话和录像时间点。也可以自己添加。'**
  String get scheduleEmptyBody;

  /// No description provided for @scheduleAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加日程'**
  String get scheduleAdd;

  /// No description provided for @schedulePrevWeek.
  ///
  /// In zh, this message translates to:
  /// **'上一周'**
  String get schedulePrevWeek;

  /// No description provided for @schedulePrevMonth.
  ///
  /// In zh, this message translates to:
  /// **'上个月'**
  String get schedulePrevMonth;

  /// No description provided for @scheduleNextWeek.
  ///
  /// In zh, this message translates to:
  /// **'下一周'**
  String get scheduleNextWeek;

  /// No description provided for @scheduleNextMonth.
  ///
  /// In zh, this message translates to:
  /// **'下个月'**
  String get scheduleNextMonth;

  /// No description provided for @scheduleExpandMonth.
  ///
  /// In zh, this message translates to:
  /// **'展开月历'**
  String get scheduleExpandMonth;

  /// No description provided for @scheduleCollapseMonth.
  ///
  /// In zh, this message translates to:
  /// **'收起月历'**
  String get scheduleCollapseMonth;

  /// No description provided for @scheduleDayLabel.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日{value}'**
  String scheduleDayLabel(Object month, Object day, Object value);

  /// No description provided for @scheduleDayItems.
  ///
  /// In zh, this message translates to:
  /// **'，{length} 项日程'**
  String scheduleDayItems(Object length);

  /// No description provided for @scheduleOverdueHeader.
  ///
  /// In zh, this message translates to:
  /// **'已逾期'**
  String get scheduleOverdueHeader;

  /// No description provided for @scheduleDayEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这天没有安排'**
  String get scheduleDayEmpty;

  /// No description provided for @scheduleKindExam.
  ///
  /// In zh, this message translates to:
  /// **'考试'**
  String get scheduleKindExam;

  /// No description provided for @scheduleKindEvent.
  ///
  /// In zh, this message translates to:
  /// **'活动'**
  String get scheduleKindEvent;

  /// No description provided for @scheduleKindDeadline.
  ///
  /// In zh, this message translates to:
  /// **'截止'**
  String get scheduleKindDeadline;

  /// No description provided for @commonDayAfterTomorrow.
  ///
  /// In zh, this message translates to:
  /// **'后天'**
  String get commonDayAfterTomorrow;

  /// No description provided for @scheduleOverdueDays.
  ///
  /// In zh, this message translates to:
  /// **'逾期 {value} 天'**
  String scheduleOverdueDays(Object value);

  /// No description provided for @scheduleDaysLeft.
  ///
  /// In zh, this message translates to:
  /// **'还有 {diff} 天'**
  String scheduleDaysLeft(Object diff);

  /// No description provided for @commonUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新失败：{e}'**
  String commonUpdateFailed(Object e);

  /// No description provided for @scheduleRemovedNotice.
  ///
  /// In zh, this message translates to:
  /// **'{value}「{title}」'**
  String scheduleRemovedNotice(Object value, Object title);

  /// No description provided for @scheduleHiddenFromSchedule.
  ///
  /// In zh, this message translates to:
  /// **'已从日程隐藏'**
  String get scheduleHiddenFromSchedule;

  /// No description provided for @commonDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除'**
  String get commonDeleted;

  /// No description provided for @scheduleOpenInCanvas.
  ///
  /// In zh, this message translates to:
  /// **'在 Canvas 打开'**
  String get scheduleOpenInCanvas;

  /// No description provided for @scheduleHide.
  ///
  /// In zh, this message translates to:
  /// **'从日程隐藏'**
  String get scheduleHide;

  /// No description provided for @scheduleJumpToSource.
  ///
  /// In zh, this message translates to:
  /// **'跳到老师提到的地方'**
  String get scheduleJumpToSource;

  /// No description provided for @scheduleNew.
  ///
  /// In zh, this message translates to:
  /// **'新建日程'**
  String get scheduleNew;

  /// No description provided for @scheduleEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑日程'**
  String get scheduleEdit;

  /// No description provided for @scheduleTitleHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：实验二报告'**
  String get scheduleTitleHint;

  /// No description provided for @dateYearMonthDayWeek.
  ///
  /// In zh, this message translates to:
  /// **'{year}年{month}月{day}日 周{value}'**
  String dateYearMonthDayWeek(
    Object year,
    Object month,
    Object day,
    Object value,
  );

  /// No description provided for @scheduleDueDate.
  ///
  /// In zh, this message translates to:
  /// **'截止日期'**
  String get scheduleDueDate;

  /// No description provided for @scheduleAllDay.
  ///
  /// In zh, this message translates to:
  /// **'全天'**
  String get scheduleAllDay;

  /// No description provided for @scheduleNoCourse.
  ///
  /// In zh, this message translates to:
  /// **'不关联课程'**
  String get scheduleNoCourse;

  /// No description provided for @scheduleNote.
  ///
  /// In zh, this message translates to:
  /// **'备注'**
  String get scheduleNote;

  /// No description provided for @scheduleNoteHint.
  ///
  /// In zh, this message translates to:
  /// **'要求、提交方式…'**
  String get scheduleNoteHint;

  /// No description provided for @scheduleAlreadyAdded.
  ///
  /// In zh, this message translates to:
  /// **'日程里已有'**
  String get scheduleAlreadyAdded;

  /// No description provided for @scheduleMarkUndone.
  ///
  /// In zh, this message translates to:
  /// **'标为未完成'**
  String get scheduleMarkUndone;

  /// No description provided for @coursewareUploadFailed.
  ///
  /// In zh, this message translates to:
  /// **'{value} 上传失败：{e}'**
  String coursewareUploadFailed(Object value, Object e);

  /// No description provided for @coursewareUploadedParsing.
  ///
  /// In zh, this message translates to:
  /// **'已上传 {ok} 个文件，正在用 MinerU 解析'**
  String coursewareUploadedParsing(Object ok);

  /// No description provided for @coursewareUploaded.
  ///
  /// In zh, this message translates to:
  /// **'已上传 {ok} 个文件'**
  String coursewareUploaded(Object ok);

  /// No description provided for @coursewareUploadTitle.
  ///
  /// In zh, this message translates to:
  /// **'上传这节课的课件'**
  String get coursewareUploadTitle;

  /// No description provided for @coursewareUploadBody.
  ///
  /// In zh, this message translates to:
  /// **'Look 不提供课件。把老师发的 PDF、PPT、Word 传上来，MinerU 会把它解析成文字，可以全文阅读，助手也能引用。'**
  String get coursewareUploadBody;

  /// No description provided for @commonChooseFiles.
  ///
  /// In zh, this message translates to:
  /// **'选择文件'**
  String get commonChooseFiles;

  /// No description provided for @coursewareParsing.
  ///
  /// In zh, this message translates to:
  /// **'正在解析…'**
  String get coursewareParsing;

  /// No description provided for @commonFilesCount.
  ///
  /// In zh, this message translates to:
  /// **'{length} 个文件'**
  String commonFilesCount(Object length);

  /// No description provided for @commonUpload.
  ///
  /// In zh, this message translates to:
  /// **'上传'**
  String get commonUpload;

  /// No description provided for @coursewareParsed.
  ///
  /// In zh, this message translates to:
  /// **'已解析{value}'**
  String coursewareParsed(Object value);

  /// No description provided for @coursewarePagesSuffix.
  ///
  /// In zh, this message translates to:
  /// **' {pages} 页'**
  String coursewarePagesSuffix(Object pages);

  /// No description provided for @coursewareParseFailed.
  ///
  /// In zh, this message translates to:
  /// **'解析失败'**
  String get coursewareParseFailed;

  /// No description provided for @coursewareParseQueued.
  ///
  /// In zh, this message translates to:
  /// **'等待解析'**
  String get coursewareParseQueued;

  /// No description provided for @coursewareNotParsedState.
  ///
  /// In zh, this message translates to:
  /// **'未解析'**
  String get coursewareNotParsedState;

  /// No description provided for @coursewareParseQueuedToast.
  ///
  /// In zh, this message translates to:
  /// **'已加入解析队列'**
  String get coursewareParseQueuedToast;

  /// No description provided for @coursewareParseTooltip.
  ///
  /// In zh, this message translates to:
  /// **'用 MinerU 解析'**
  String get coursewareParseTooltip;

  /// No description provided for @coursewareDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除课件？'**
  String get coursewareDeleteTitle;

  /// No description provided for @coursewareDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」和它的解析结果会从课程库中删除。'**
  String coursewareDeleteBody(Object name);

  /// No description provided for @coursewareReadParsed.
  ///
  /// In zh, this message translates to:
  /// **'阅读解析结果'**
  String get coursewareReadParsed;

  /// No description provided for @coursewareOpenOriginal.
  ///
  /// In zh, this message translates to:
  /// **'打开原文件'**
  String get coursewareOpenOriginal;

  /// No description provided for @coursewareReparse.
  ///
  /// In zh, this message translates to:
  /// **'重新解析'**
  String get coursewareReparse;

  /// No description provided for @coursewareParse.
  ///
  /// In zh, this message translates to:
  /// **'解析'**
  String get coursewareParse;

  /// No description provided for @usagePurposeChat.
  ///
  /// In zh, this message translates to:
  /// **'对话'**
  String get usagePurposeChat;

  /// No description provided for @usagePurposeTest.
  ///
  /// In zh, this message translates to:
  /// **'连接测试'**
  String get usagePurposeTest;

  /// No description provided for @usagePurposeMemory.
  ///
  /// In zh, this message translates to:
  /// **'记忆沉淀'**
  String get usagePurposeMemory;

  /// No description provided for @range7Days.
  ///
  /// In zh, this message translates to:
  /// **'7 天'**
  String get range7Days;

  /// No description provided for @range30Days.
  ///
  /// In zh, this message translates to:
  /// **'30 天'**
  String get range30Days;

  /// No description provided for @range90Days.
  ///
  /// In zh, this message translates to:
  /// **'90 天'**
  String get range90Days;

  /// No description provided for @rangeThisYear.
  ///
  /// In zh, this message translates to:
  /// **'今年'**
  String get rangeThisYear;

  /// No description provided for @commonNoData.
  ///
  /// In zh, this message translates to:
  /// **'没有数据'**
  String get commonNoData;

  /// No description provided for @usageEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这段时间没有用量'**
  String get usageEmpty;

  /// No description provided for @usageEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'和助手对话、生成大纲或识图后，这里会按天统计 token 和估算费用。'**
  String get usageEmptyBody;

  /// No description provided for @usageDaily.
  ///
  /// In zh, this message translates to:
  /// **'每日用量'**
  String get usageDaily;

  /// No description provided for @usageBreakdown.
  ///
  /// In zh, this message translates to:
  /// **'明细'**
  String get usageBreakdown;

  /// No description provided for @usageRecentCalls.
  ///
  /// In zh, this message translates to:
  /// **'最近调用'**
  String get usageRecentCalls;

  /// No description provided for @usageCallsInRange.
  ///
  /// In zh, this message translates to:
  /// **'{label}内的调用'**
  String usageCallsInRange(Object label);

  /// No description provided for @usageCost.
  ///
  /// In zh, this message translates to:
  /// **'费用'**
  String get usageCost;

  /// No description provided for @usageChart.
  ///
  /// In zh, this message translates to:
  /// **'图表'**
  String get usageChart;

  /// No description provided for @usageTable.
  ///
  /// In zh, this message translates to:
  /// **'表格'**
  String get usageTable;

  /// No description provided for @usagePurpose.
  ///
  /// In zh, this message translates to:
  /// **'用途'**
  String get usagePurpose;

  /// No description provided for @usageEstimatedCost.
  ///
  /// In zh, this message translates to:
  /// **'估算费用'**
  String get usageEstimatedCost;

  /// No description provided for @usageInput.
  ///
  /// In zh, this message translates to:
  /// **'输入'**
  String get usageInput;

  /// No description provided for @usageCacheHit.
  ///
  /// In zh, this message translates to:
  /// **'缓存命中'**
  String get usageCacheHit;

  /// No description provided for @usageOutput.
  ///
  /// In zh, this message translates to:
  /// **'输出'**
  String get usageOutput;

  /// No description provided for @usageChartSemantics.
  ///
  /// In zh, this message translates to:
  /// **'每日{value}柱状图，可切换为表格查看'**
  String usageChartSemantics(Object value);

  /// No description provided for @usageTokens.
  ///
  /// In zh, this message translates to:
  /// **'token 用量'**
  String get usageTokens;

  /// No description provided for @commonNoRecords.
  ///
  /// In zh, this message translates to:
  /// **'没有记录'**
  String get commonNoRecords;

  /// No description provided for @usageDeletedChat.
  ///
  /// In zh, this message translates to:
  /// **'已删除的对话'**
  String get usageDeletedChat;

  /// No description provided for @usageCalls.
  ///
  /// In zh, this message translates to:
  /// **'{value} 次'**
  String usageCalls(Object value);

  /// No description provided for @usageInputTokens.
  ///
  /// In zh, this message translates to:
  /// **'输入 {value}'**
  String usageInputTokens(Object value);

  /// No description provided for @usageLastYear.
  ///
  /// In zh, this message translates to:
  /// **'去年同期'**
  String get usageLastYear;

  /// No description provided for @usagePreviousDays.
  ///
  /// In zh, this message translates to:
  /// **'前 {days} 天'**
  String usagePreviousDays(Object days);

  /// No description provided for @usageNoneIn.
  ///
  /// In zh, this message translates to:
  /// **'{span}无用量'**
  String usageNoneIn(Object span);

  /// No description provided for @usageSameAs.
  ///
  /// In zh, this message translates to:
  /// **'与{span}持平'**
  String usageSameAs(Object span);

  /// No description provided for @usageCompare.
  ///
  /// In zh, this message translates to:
  /// **'比{span}{value} {value2}%'**
  String usageCompare(Object span, Object value, Object value2);

  /// No description provided for @usageInputOutput.
  ///
  /// In zh, this message translates to:
  /// **'输入 {value} · 输出 {value2}'**
  String usageInputOutput(Object value, Object value2);

  /// No description provided for @usageCallCount.
  ///
  /// In zh, this message translates to:
  /// **'调用次数'**
  String get usageCallCount;

  /// No description provided for @usageFailedCalls.
  ///
  /// In zh, this message translates to:
  /// **'失败 {value} 次'**
  String usageFailedCalls(Object value);

  /// No description provided for @usageCacheRate.
  ///
  /// In zh, this message translates to:
  /// **'缓存命中率'**
  String get usageCacheRate;

  /// No description provided for @usageCacheTokens.
  ///
  /// In zh, this message translates to:
  /// **'命中 {value} tokens'**
  String usageCacheTokens(Object value);

  /// No description provided for @commonDate.
  ///
  /// In zh, this message translates to:
  /// **'日期'**
  String get commonDate;

  /// No description provided for @usageCachedSuffix.
  ///
  /// In zh, this message translates to:
  /// **'（缓存 {value}）'**
  String usageCachedSuffix(Object value);

  /// No description provided for @usageFirstToken.
  ///
  /// In zh, this message translates to:
  /// **'首字 {value}s'**
  String usageFirstToken(Object value);

  /// No description provided for @usageNoCalls.
  ///
  /// In zh, this message translates to:
  /// **'没有调用记录'**
  String get usageNoCalls;

  /// No description provided for @activityWatching.
  ///
  /// In zh, this message translates to:
  /// **'看课'**
  String get activityWatching;

  /// No description provided for @activityReading.
  ///
  /// In zh, this message translates to:
  /// **'阅读'**
  String get activityReading;

  /// No description provided for @activityNone.
  ///
  /// In zh, this message translates to:
  /// **'没有学习记录'**
  String get activityNone;

  /// No description provided for @activityStudyTime.
  ///
  /// In zh, this message translates to:
  /// **'学习 {value}'**
  String activityStudyTime(Object value);

  /// No description provided for @activityQuizzes.
  ///
  /// In zh, this message translates to:
  /// **'练习 {quizzes} 组'**
  String activityQuizzes(Object quizzes);

  /// No description provided for @activityAsks.
  ///
  /// In zh, this message translates to:
  /// **'提问 {asks} 次'**
  String activityAsks(Object asks);

  /// No description provided for @activityNotes.
  ///
  /// In zh, this message translates to:
  /// **'笔记 {value} 篇'**
  String activityNotes(Object value);

  /// No description provided for @activityDayLabel.
  ///
  /// In zh, this message translates to:
  /// **'{value}，{value2}'**
  String activityDayLabel(Object value, Object value2);

  /// No description provided for @activityHasRecord.
  ///
  /// In zh, this message translates to:
  /// **'有学习记录'**
  String get activityHasRecord;

  /// No description provided for @activityNoStudy.
  ///
  /// In zh, this message translates to:
  /// **'没有学习'**
  String get activityNoStudy;

  /// No description provided for @activityThisWeek.
  ///
  /// In zh, this message translates to:
  /// **'本周'**
  String get activityThisWeek;

  /// No description provided for @commonDays.
  ///
  /// In zh, this message translates to:
  /// **'{current} 天'**
  String commonDays(Object current);

  /// No description provided for @activityStreak.
  ///
  /// In zh, this message translates to:
  /// **'连续学习'**
  String get activityStreak;

  /// No description provided for @activityLongestDays.
  ///
  /// In zh, this message translates to:
  /// **'{longest} 天'**
  String activityLongestDays(Object longest);

  /// No description provided for @activityLongestStreak.
  ///
  /// In zh, this message translates to:
  /// **'最长连续'**
  String get activityLongestStreak;

  /// No description provided for @activityEmpty.
  ///
  /// In zh, this message translates to:
  /// **'开始看课或做题后，这里会记录你的学习足迹'**
  String get activityEmpty;

  /// No description provided for @activityDuration.
  ///
  /// In zh, this message translates to:
  /// **'学习时长'**
  String get activityDuration;

  /// No description provided for @activityDaysCount.
  ///
  /// In zh, this message translates to:
  /// **'学习天数'**
  String get activityDaysCount;

  /// No description provided for @activityActiveDays.
  ///
  /// In zh, this message translates to:
  /// **'{activeDays} 天'**
  String activityActiveDays(Object activeDays);

  /// No description provided for @activityCurrentStreak.
  ///
  /// In zh, this message translates to:
  /// **'当前连续'**
  String get activityCurrentStreak;

  /// No description provided for @activityYear.
  ///
  /// In zh, this message translates to:
  /// **'{year} 年'**
  String activityYear(Object year);

  /// No description provided for @activityByKind.
  ///
  /// In zh, this message translates to:
  /// **'按类型'**
  String get activityByKind;

  /// No description provided for @activityByCourse.
  ///
  /// In zh, this message translates to:
  /// **'按课程'**
  String get activityByCourse;

  /// No description provided for @activityByCourseEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有按课程记录的学习时间'**
  String get activityByCourseEmpty;

  /// No description provided for @activityStatsTitle.
  ///
  /// In zh, this message translates to:
  /// **'学习统计'**
  String get activityStatsTitle;

  /// No description provided for @activityPrevYear.
  ///
  /// In zh, this message translates to:
  /// **'上一年'**
  String get activityPrevYear;

  /// No description provided for @activityNextYear.
  ///
  /// In zh, this message translates to:
  /// **'下一年'**
  String get activityNextYear;

  /// No description provided for @activityDaySummary.
  ///
  /// In zh, this message translates to:
  /// **'完成练习 {quizzes} 组 · 向助手提问 {asks} 次 · 新建笔记 {notes} 篇'**
  String activityDaySummary(Object quizzes, Object asks, Object notes);

  /// No description provided for @activityQuizzesDone.
  ///
  /// In zh, this message translates to:
  /// **'完成练习 {quizzes} 组'**
  String activityQuizzesDone(Object quizzes);

  /// No description provided for @activityNotesCreated.
  ///
  /// In zh, this message translates to:
  /// **'新建笔记 {notesCreated} 篇'**
  String activityNotesCreated(Object notesCreated);

  /// No description provided for @activityNotesEdited.
  ///
  /// In zh, this message translates to:
  /// **'编辑笔记 {notesEdited} 篇'**
  String activityNotesEdited(Object notesEdited);

  /// No description provided for @activityTranscripts.
  ///
  /// In zh, this message translates to:
  /// **'完成转写 {transcripts} 节'**
  String activityTranscripts(Object transcripts);

  /// No description provided for @activityUntimed.
  ///
  /// In zh, this message translates to:
  /// **'没有计时的学习'**
  String get activityUntimed;

  /// No description provided for @activityDayEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这天没有学习记录'**
  String get activityDayEmpty;

  /// No description provided for @activityTranscriptsHeader.
  ///
  /// In zh, this message translates to:
  /// **'完成转写'**
  String get activityTranscriptsHeader;

  /// No description provided for @practiceScoreNotSaved.
  ///
  /// In zh, this message translates to:
  /// **'成绩没有保存：{e}'**
  String practiceScoreNotSaved(Object e);

  /// No description provided for @practiceOption.
  ///
  /// In zh, this message translates to:
  /// **'{value}「{text}」'**
  String practiceOption(Object value, Object text);

  /// No description provided for @promptExplainQuestion.
  ///
  /// In zh, this message translates to:
  /// **'讲解练习「{title}」第 {value} 题：{stem}\n选项：{value2}\n我选了 {value3}，正确答案是 {value4}。{value5}{value6}'**
  String promptExplainQuestion(
    Object title,
    Object value,
    Object stem,
    Object value2,
    Object value3,
    Object value4,
    Object value5,
    Object value6,
  );

  /// No description provided for @promptRetryWrong.
  ///
  /// In zh, this message translates to:
  /// **'根据我在练习「{title}」（id {id}）中做错的题，针对这些知识点再出一组练习题。'**
  String promptRetryWrong(Object title, Object id);

  /// No description provided for @practiceRetryTitle.
  ///
  /// In zh, this message translates to:
  /// **'重做错题 · {title}'**
  String practiceRetryTitle(Object title);

  /// No description provided for @practiceQuestionNumber.
  ///
  /// In zh, this message translates to:
  /// **'第 {number} 题'**
  String practiceQuestionNumber(Object number);

  /// No description provided for @practiceHint.
  ///
  /// In zh, this message translates to:
  /// **'提示'**
  String get practiceHint;

  /// No description provided for @practiceExplain.
  ///
  /// In zh, this message translates to:
  /// **'讲解'**
  String get practiceExplain;

  /// No description provided for @practiceSource.
  ///
  /// In zh, this message translates to:
  /// **'查看出处'**
  String get practiceSource;

  /// No description provided for @practicePrevious.
  ///
  /// In zh, this message translates to:
  /// **'上一题'**
  String get practicePrevious;

  /// No description provided for @practiceBackToSummary.
  ///
  /// In zh, this message translates to:
  /// **'返回总结'**
  String get practiceBackToSummary;

  /// No description provided for @practiceNext.
  ///
  /// In zh, this message translates to:
  /// **'下一题'**
  String get practiceNext;

  /// No description provided for @practiceCorrectAnswer.
  ///
  /// In zh, this message translates to:
  /// **'正确答案'**
  String get practiceCorrectAnswer;

  /// No description provided for @practiceYourChoice.
  ///
  /// In zh, this message translates to:
  /// **'你的选择'**
  String get practiceYourChoice;

  /// No description provided for @practiceOptionLabel.
  ///
  /// In zh, this message translates to:
  /// **'选项 {letter}{value}'**
  String practiceOptionLabel(Object letter, Object value);

  /// No description provided for @practiceOptionNote.
  ///
  /// In zh, this message translates to:
  /// **'，{note}'**
  String practiceOptionNote(Object note);

  /// No description provided for @practiceSecondsSuffix.
  ///
  /// In zh, this message translates to:
  /// **' {value} 秒'**
  String practiceSecondsSuffix(Object value);

  /// No description provided for @practiceRetryDone.
  ///
  /// In zh, this message translates to:
  /// **'重做完成'**
  String get practiceRetryDone;

  /// No description provided for @practiceDone.
  ///
  /// In zh, this message translates to:
  /// **'练习完成'**
  String get practiceDone;

  /// No description provided for @practiceScoreSemantics.
  ///
  /// In zh, this message translates to:
  /// **'答对 {correct} 题，共 {length} 题'**
  String practiceScoreSemantics(Object correct, Object length);

  /// No description provided for @practiceAccuracy.
  ///
  /// In zh, this message translates to:
  /// **'正确率 {value}%'**
  String practiceAccuracy(Object value);

  /// No description provided for @practiceTime.
  ///
  /// In zh, this message translates to:
  /// **'用时 {time}'**
  String practiceTime(Object time);

  /// No description provided for @commonSavingShort.
  ///
  /// In zh, this message translates to:
  /// **'正在保存'**
  String get commonSavingShort;

  /// No description provided for @practiceBest.
  ///
  /// In zh, this message translates to:
  /// **'最好成绩 {label}'**
  String practiceBest(Object label);

  /// No description provided for @practiceRetryWrong.
  ///
  /// In zh, this message translates to:
  /// **'重做错题 {length}'**
  String practiceRetryWrong(Object length);

  /// No description provided for @practiceMoreOnWrong.
  ///
  /// In zh, this message translates to:
  /// **'再出一组（针对错题）'**
  String get practiceMoreOnWrong;

  /// No description provided for @practiceByTopic.
  ///
  /// In zh, this message translates to:
  /// **'按知识点'**
  String get practiceByTopic;

  /// No description provided for @practiceReview.
  ///
  /// In zh, this message translates to:
  /// **'逐题回顾'**
  String get practiceReview;

  /// No description provided for @practiceCorrect.
  ///
  /// In zh, this message translates to:
  /// **'答对'**
  String get practiceCorrect;

  /// No description provided for @practiceUnanswered.
  ///
  /// In zh, this message translates to:
  /// **'未作答'**
  String get practiceUnanswered;

  /// No description provided for @practiceWrong.
  ///
  /// In zh, this message translates to:
  /// **'答错'**
  String get practiceWrong;

  /// No description provided for @quizCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 题'**
  String quizCount(Object count);

  /// No description provided for @quizEasy.
  ///
  /// In zh, this message translates to:
  /// **'简单'**
  String get quizEasy;

  /// No description provided for @quizHard.
  ///
  /// In zh, this message translates to:
  /// **'困难'**
  String get quizHard;

  /// No description provided for @quizMedium.
  ///
  /// In zh, this message translates to:
  /// **'中等'**
  String get quizMedium;

  /// No description provided for @quizAssistantBusy.
  ///
  /// In zh, this message translates to:
  /// **'助手正在回复，请稍后再试'**
  String get quizAssistantBusy;

  /// No description provided for @quizAssistantNotReady.
  ///
  /// In zh, this message translates to:
  /// **'助手还没有就绪'**
  String get quizAssistantNotReady;

  /// No description provided for @quizNone.
  ///
  /// In zh, this message translates to:
  /// **'还没有练习'**
  String get quizNone;

  /// No description provided for @quizBestAttempts.
  ///
  /// In zh, this message translates to:
  /// **'最好 {label} · 练过 {attempts} 次'**
  String quizBestAttempts(Object label, Object attempts);

  /// No description provided for @quizStart.
  ///
  /// In zh, this message translates to:
  /// **'开始练习'**
  String get quizStart;

  /// No description provided for @quizAgain.
  ///
  /// In zh, this message translates to:
  /// **'再练一次'**
  String get quizAgain;

  /// No description provided for @promptCreateQuiz.
  ///
  /// In zh, this message translates to:
  /// **'请为这节课（lecture_id {lectureId}）出 {count} 道{value}难度的选择题，保存为练习{value2}。'**
  String promptCreateQuiz(
    Object lectureId,
    Object count,
    Object value,
    Object value2,
  );

  /// No description provided for @quizCreateTitle.
  ///
  /// In zh, this message translates to:
  /// **'出题练习'**
  String get quizCreateTitle;

  /// No description provided for @quizCreateHint.
  ///
  /// In zh, this message translates to:
  /// **'助手会先读完字幕并核对 PPT 与课件，每道题都附出处和解析。'**
  String get quizCreateHint;

  /// No description provided for @quizSize.
  ///
  /// In zh, this message translates to:
  /// **'题量'**
  String get quizSize;

  /// No description provided for @quizQuestions.
  ///
  /// In zh, this message translates to:
  /// **'{n} 题'**
  String quizQuestions(Object n);

  /// No description provided for @quizDifficulty.
  ///
  /// In zh, this message translates to:
  /// **'难度'**
  String get quizDifficulty;

  /// No description provided for @quizFocus.
  ///
  /// In zh, this message translates to:
  /// **'侧重（可选）'**
  String get quizFocus;

  /// No description provided for @quizFocusHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：卷积的性质、例题的解法'**
  String get quizFocusHint;

  /// No description provided for @quizCreate.
  ///
  /// In zh, this message translates to:
  /// **'让助手出题'**
  String get quizCreate;

  /// No description provided for @pluginError.
  ///
  /// In zh, this message translates to:
  /// **'{pluginTitle}：{value}'**
  String pluginError(Object pluginTitle, Object value);

  /// No description provided for @pluginViewList.
  ///
  /// In zh, this message translates to:
  /// **'清单'**
  String get pluginViewList;

  /// No description provided for @pluginViewUnknown.
  ///
  /// In zh, this message translates to:
  /// **'「{kind}」视图'**
  String pluginViewUnknown(Object kind);

  /// No description provided for @pluginViewUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前版本的应用还不能显示这种视图，更新应用后即可查看'**
  String get pluginViewUnsupported;

  /// No description provided for @pluginViewAlternative.
  ///
  /// In zh, this message translates to:
  /// **'换种方式看'**
  String get pluginViewAlternative;

  /// No description provided for @pluginSlotNoteToolbar.
  ///
  /// In zh, this message translates to:
  /// **'笔记工具栏'**
  String get pluginSlotNoteToolbar;

  /// No description provided for @pluginSlotLectureMenu.
  ///
  /// In zh, this message translates to:
  /// **'课次菜单'**
  String get pluginSlotLectureMenu;

  /// No description provided for @pluginSlotCourseMenu.
  ///
  /// In zh, this message translates to:
  /// **'课程菜单'**
  String get pluginSlotCourseMenu;

  /// No description provided for @pluginSlotScheduleItem.
  ///
  /// In zh, this message translates to:
  /// **'日程条目'**
  String get pluginSlotScheduleItem;

  /// No description provided for @pluginSlotAssignment.
  ///
  /// In zh, this message translates to:
  /// **'作业页'**
  String get pluginSlotAssignment;

  /// No description provided for @pluginSlotComposer.
  ///
  /// In zh, this message translates to:
  /// **'输入框的「+」菜单'**
  String get pluginSlotComposer;

  /// No description provided for @pluginsAllowThirdPartyTitle.
  ///
  /// In zh, this message translates to:
  /// **'允许第三方插件？'**
  String get pluginsAllowThirdPartyTitle;

  /// No description provided for @pluginsAllowThirdPartyBody.
  ///
  /// In zh, this message translates to:
  /// **'第三方插件不是 Look Studio 发布的，与助手运行在同一进程中。只安装你信任的作者的插件；每次安装前都会列出它需要的权限。'**
  String get pluginsAllowThirdPartyBody;

  /// No description provided for @commonAllow.
  ///
  /// In zh, this message translates to:
  /// **'允许'**
  String get commonAllow;

  /// No description provided for @pluginsInstalled.
  ///
  /// In zh, this message translates to:
  /// **'已安装的插件'**
  String get pluginsInstalled;

  /// No description provided for @pluginsAfterAssistant.
  ///
  /// In zh, this message translates to:
  /// **'助手启动后可用'**
  String get pluginsAfterAssistant;

  /// No description provided for @pluginsNoneInstalled.
  ///
  /// In zh, this message translates to:
  /// **'还没有安装插件'**
  String get pluginsNoneInstalled;

  /// No description provided for @pluginsEnabledSummary.
  ///
  /// In zh, this message translates to:
  /// **'{on} 个已启用{value}'**
  String pluginsEnabledSummary(Object on, Object value);

  /// No description provided for @pluginsAttentionSuffix.
  ///
  /// In zh, this message translates to:
  /// **' · {attention} 个需要处理'**
  String pluginsAttentionSuffix(Object attention);

  /// No description provided for @pluginsTagline.
  ///
  /// In zh, this message translates to:
  /// **'引导式提问、思维导图、闪卡复习……让助手学会新本事'**
  String get pluginsTagline;

  /// No description provided for @pluginsNeedAssistant.
  ///
  /// In zh, this message translates to:
  /// **'插件在助手里运行，助手启动后就能浏览和管理插件。'**
  String get pluginsNeedAssistant;

  /// No description provided for @pluginsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'让助手学会新本事：换一种方式讲题、把笔记画成导图、连接你常用的工具'**
  String get pluginsSubtitle;

  /// No description provided for @pluginsInstalledCount.
  ///
  /// In zh, this message translates to:
  /// **'{n} 个已安装'**
  String pluginsInstalledCount(Object n);

  /// No description provided for @pluginsEnabledCount.
  ///
  /// In zh, this message translates to:
  /// **'{on} 个启用'**
  String pluginsEnabledCount(Object on);

  /// No description provided for @pluginsAttentionCount.
  ///
  /// In zh, this message translates to:
  /// **'{attention} 个需要处理'**
  String pluginsAttentionCount(Object attention);

  /// No description provided for @pluginsUpdatesCount.
  ///
  /// In zh, this message translates to:
  /// **'{updates} 个可更新'**
  String pluginsUpdatesCount(Object updates);

  /// No description provided for @pluginsDiscoverTab.
  ///
  /// In zh, this message translates to:
  /// **'发现'**
  String get pluginsDiscoverTab;

  /// No description provided for @pluginsInstalledTab.
  ///
  /// In zh, this message translates to:
  /// **'已安装 {n}'**
  String pluginsInstalledTab(Object n);

  /// No description provided for @pluginsOtherSource.
  ///
  /// In zh, this message translates to:
  /// **'其他来源'**
  String get pluginsOtherSource;

  /// No description provided for @pluginsSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索插件'**
  String get pluginsSearch;

  /// No description provided for @pluginsCatalogErrors.
  ///
  /// In zh, this message translates to:
  /// **'有 {length} 个插件目录无法加载'**
  String pluginsCatalogErrors(Object length);

  /// No description provided for @pluginsNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'没有找到插件'**
  String get pluginsNoMatch;

  /// No description provided for @pluginsNoMatchBody.
  ///
  /// In zh, this message translates to:
  /// **'换个关键词，或在「来源」里添加更多插件目录'**
  String get pluginsNoMatchBody;

  /// No description provided for @pluginsOfficial.
  ///
  /// In zh, this message translates to:
  /// **'Look Studio 官方'**
  String get pluginsOfficial;

  /// No description provided for @pluginsMoreHint.
  ///
  /// In zh, this message translates to:
  /// **'想要更多？允许第三方插件后，可以添加社区的插件目录，或从文件夹、npm、Git 安装。安装前都会列出它需要的权限。'**
  String get pluginsMoreHint;

  /// No description provided for @pluginsEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'在「发现」里挑几个：换一种方式讲题、把笔记画成导图、连接你常用的工具。'**
  String get pluginsEmptyBody;

  /// No description provided for @pluginsGoDiscover.
  ///
  /// In zh, this message translates to:
  /// **'去发现'**
  String get pluginsGoDiscover;

  /// No description provided for @pluginsAllowThirdParty.
  ///
  /// In zh, this message translates to:
  /// **'允许第三方插件'**
  String get pluginsAllowThirdParty;

  /// No description provided for @pluginsCatalogs.
  ///
  /// In zh, this message translates to:
  /// **'插件目录…'**
  String get pluginsCatalogs;

  /// No description provided for @pluginsInstallFrom.
  ///
  /// In zh, this message translates to:
  /// **'从文件夹、npm 或 Git 安装…'**
  String get pluginsInstallFrom;

  /// No description provided for @pluginsSources.
  ///
  /// In zh, this message translates to:
  /// **'插件来源'**
  String get pluginsSources;

  /// No description provided for @pluginsSourcesTab.
  ///
  /// In zh, this message translates to:
  /// **'来源'**
  String get pluginsSourcesTab;

  /// No description provided for @pluginsNeedsGrant.
  ///
  /// In zh, this message translates to:
  /// **'需要授权'**
  String get pluginsNeedsGrant;

  /// No description provided for @pluginsErrored.
  ///
  /// In zh, this message translates to:
  /// **'出错'**
  String get pluginsErrored;

  /// No description provided for @pluginsUpdatable.
  ///
  /// In zh, this message translates to:
  /// **'可更新'**
  String get pluginsUpdatable;

  /// No description provided for @pluginsFeatured.
  ///
  /// In zh, this message translates to:
  /// **'精选'**
  String get pluginsFeatured;

  /// No description provided for @commonInstall.
  ///
  /// In zh, this message translates to:
  /// **'安装'**
  String get commonInstall;

  /// No description provided for @pluginsInstallOther.
  ///
  /// In zh, this message translates to:
  /// **'从其他来源安装'**
  String get pluginsInstallOther;

  /// No description provided for @commonFolder.
  ///
  /// In zh, this message translates to:
  /// **'文件夹'**
  String get commonFolder;

  /// No description provided for @pluginsPinnedVersion.
  ///
  /// In zh, this message translates to:
  /// **'需要写明固定版本'**
  String get pluginsPinnedVersion;

  /// No description provided for @commonNext.
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get commonNext;

  /// No description provided for @pluginsCatalog.
  ///
  /// In zh, this message translates to:
  /// **'插件目录'**
  String get pluginsCatalog;

  /// No description provided for @pluginsBundled.
  ///
  /// In zh, this message translates to:
  /// **'随应用提供'**
  String get pluginsBundled;

  /// No description provided for @pluginsLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败：{value}'**
  String pluginsLoadFailed(Object value);

  /// No description provided for @pluginsCatalogHint.
  ///
  /// In zh, this message translates to:
  /// **'owner/repo 或 https://…/look-catalog.json'**
  String get pluginsCatalogHint;

  /// No description provided for @pluginsFetching.
  ///
  /// In zh, this message translates to:
  /// **'正在获取插件…'**
  String get pluginsFetching;

  /// No description provided for @pluginsFetchFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法获取插件：{value}'**
  String pluginsFetchFailed(Object value);

  /// No description provided for @pluginsInstalling.
  ///
  /// In zh, this message translates to:
  /// **'正在安装…'**
  String get pluginsInstalling;

  /// No description provided for @pluginsInstalledLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'已安装，但加载失败：{value}'**
  String pluginsInstalledLoadFailed(Object value);

  /// No description provided for @pluginsInstalledToast.
  ///
  /// In zh, this message translates to:
  /// **'已安装「{value}」'**
  String pluginsInstalledToast(Object value);

  /// No description provided for @pluginsInstallFailed.
  ///
  /// In zh, this message translates to:
  /// **'安装失败：{value}'**
  String pluginsInstallFailed(Object value);

  /// No description provided for @pluginsInstallTitle.
  ///
  /// In zh, this message translates to:
  /// **'安装「{value}」？'**
  String pluginsInstallTitle(Object value);

  /// No description provided for @pluginsUpdateTitle.
  ///
  /// In zh, this message translates to:
  /// **'更新「{value}」？'**
  String pluginsUpdateTitle(Object value);

  /// No description provided for @pluginsCurrentVersion.
  ///
  /// In zh, this message translates to:
  /// **'当前 v{value}'**
  String pluginsCurrentVersion(Object value);

  /// No description provided for @pluginsThirdPartyWarning.
  ///
  /// In zh, this message translates to:
  /// **'第三方插件，来源：{value}。它与助手运行在同一进程中，请确认你信任作者。'**
  String pluginsThirdPartyWarning(Object value);

  /// No description provided for @pluginsNoPermissions.
  ///
  /// In zh, this message translates to:
  /// **'不需要额外权限'**
  String get pluginsNoPermissions;

  /// No description provided for @pluginsWillBeAble.
  ///
  /// In zh, this message translates to:
  /// **'它将可以'**
  String get pluginsWillBeAble;

  /// No description provided for @pluginsNewPermissions.
  ///
  /// In zh, this message translates to:
  /// **'新增'**
  String get pluginsNewPermissions;

  /// No description provided for @pluginsContribAlternative.
  ///
  /// In zh, this message translates to:
  /// **'笔记的「换种方式看」'**
  String get pluginsContribAlternative;

  /// No description provided for @pluginsContribExport.
  ///
  /// In zh, this message translates to:
  /// **'{value}导出菜单'**
  String pluginsContribExport(Object value);

  /// No description provided for @pluginsContribPage.
  ///
  /// In zh, this message translates to:
  /// **'插件页面'**
  String get pluginsContribPage;

  /// No description provided for @pluginsVersionAvailable.
  ///
  /// In zh, this message translates to:
  /// **'v{value} 可用'**
  String pluginsVersionAvailable(Object value);

  /// No description provided for @pluginsReviewGrant.
  ///
  /// In zh, this message translates to:
  /// **'查看并授权'**
  String get pluginsReviewGrant;

  /// No description provided for @commonUninstall.
  ///
  /// In zh, this message translates to:
  /// **'卸载'**
  String get commonUninstall;

  /// No description provided for @pluginsHomepage.
  ///
  /// In zh, this message translates to:
  /// **'主页'**
  String get pluginsHomepage;

  /// No description provided for @pluginsTryAsking.
  ///
  /// In zh, this message translates to:
  /// **'试试这样问'**
  String get pluginsTryAsking;

  /// No description provided for @pluginsTryAfterEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用后可以这样问'**
  String get pluginsTryAfterEnable;

  /// No description provided for @pluginsCapabilities.
  ///
  /// In zh, this message translates to:
  /// **'助手获得的能力'**
  String get pluginsCapabilities;

  /// No description provided for @pluginsAppearsIn.
  ///
  /// In zh, this message translates to:
  /// **'会出现在'**
  String get pluginsAppearsIn;

  /// No description provided for @pluginsPermissions.
  ///
  /// In zh, this message translates to:
  /// **'权限'**
  String get pluginsPermissions;

  /// No description provided for @pluginsGuidanceOnly.
  ///
  /// In zh, this message translates to:
  /// **'只在对话中提供指导与工具'**
  String get pluginsGuidanceOnly;

  /// No description provided for @pluginsSettingsSaved.
  ///
  /// In zh, this message translates to:
  /// **'设置已保存'**
  String get pluginsSettingsSaved;

  /// No description provided for @pluginsSource.
  ///
  /// In zh, this message translates to:
  /// **'来源：{value}'**
  String pluginsSource(Object value);

  /// No description provided for @pluginsUninstallTitle.
  ///
  /// In zh, this message translates to:
  /// **'卸载「{value}」？'**
  String pluginsUninstallTitle(Object value);

  /// No description provided for @pluginsUninstallBody.
  ///
  /// In zh, this message translates to:
  /// **'插件保存的数据会一起删除。已经生成的笔记、练习等内容不受影响。'**
  String get pluginsUninstallBody;

  /// No description provided for @pluginsSettingRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入{value}'**
  String pluginsSettingRequired(Object value);

  /// No description provided for @pluginsSettingText.
  ///
  /// In zh, this message translates to:
  /// **'文字'**
  String get pluginsSettingText;

  /// No description provided for @pluginsSettingNumber.
  ///
  /// In zh, this message translates to:
  /// **'数字'**
  String get pluginsSettingNumber;

  /// No description provided for @pluginsSettingRange.
  ///
  /// In zh, this message translates to:
  /// **'应在 {value}–{value2} 之间'**
  String pluginsSettingRange(Object value, Object value2);

  /// No description provided for @pluginsSaveSettings.
  ///
  /// In zh, this message translates to:
  /// **'保存设置'**
  String get pluginsSaveSettings;

  /// No description provided for @notificationsTooltip.
  ///
  /// In zh, this message translates to:
  /// **'通知（{unread} 条未读）'**
  String notificationsTooltip(Object unread);

  /// No description provided for @notificationsClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭通知'**
  String get notificationsClose;

  /// No description provided for @notificationsMarkAllRead.
  ///
  /// In zh, this message translates to:
  /// **'全部已读'**
  String get notificationsMarkAllRead;

  /// No description provided for @notificationsIntro.
  ///
  /// In zh, this message translates to:
  /// **'新回放、新课次、Canvas 作业和公告会出现在这里。Look Studio 打开时在后台自动检查。'**
  String get notificationsIntro;

  /// No description provided for @notificationsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂时没有通知'**
  String get notificationsEmpty;

  /// No description provided for @notificationsEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'有新回放或新作业时会第一时间提醒你'**
  String get notificationsEmptyBody;

  /// No description provided for @notificationsUnread.
  ///
  /// In zh, this message translates to:
  /// **'未读'**
  String get notificationsUnread;

  /// No description provided for @schoolEmblem.
  ///
  /// In zh, this message translates to:
  /// **'{name}校徽'**
  String schoolEmblem(Object name);

  /// No description provided for @schoolOther.
  ///
  /// In zh, this message translates to:
  /// **'其他学校'**
  String get schoolOther;

  /// No description provided for @canvasConnected.
  ///
  /// In zh, this message translates to:
  /// **'已连接 Canvas，正在同步课程和作业'**
  String get canvasConnected;

  /// No description provided for @canvasDisconnectTitle.
  ///
  /// In zh, this message translates to:
  /// **'断开 Canvas？'**
  String get canvasDisconnectTitle;

  /// No description provided for @canvasDisconnectBody.
  ///
  /// In zh, this message translates to:
  /// **'日程里的 Canvas 作业和课程关联会一起移除，已下载的课件保留。{value}'**
  String canvasDisconnectBody(Object value);

  /// No description provided for @canvasRevokesToken.
  ///
  /// In zh, this message translates to:
  /// **'Look Studio 创建的访问令牌也会被撤销。'**
  String get canvasRevokesToken;

  /// No description provided for @canvasConnectTitle.
  ///
  /// In zh, this message translates to:
  /// **'连接你学校的 Canvas'**
  String get canvasConnectTitle;

  /// No description provided for @canvasConnectBody.
  ///
  /// In zh, this message translates to:
  /// **'作业会进入日程，截止前一天提醒你；课件可以直接下载到对应课程的文件夹。Look Studio 只读取，不会提交或修改任何内容。'**
  String get canvasConnectBody;

  /// No description provided for @canvasUrl.
  ///
  /// In zh, this message translates to:
  /// **'Canvas 地址'**
  String get canvasUrl;

  /// No description provided for @canvasSignInMethod.
  ///
  /// In zh, this message translates to:
  /// **'登录方式'**
  String get canvasSignInMethod;

  /// No description provided for @canvasAccessToken.
  ///
  /// In zh, this message translates to:
  /// **'访问令牌'**
  String get canvasAccessToken;

  /// No description provided for @canvasFudanId.
  ///
  /// In zh, this message translates to:
  /// **'复旦 UIS 学号'**
  String get canvasFudanId;

  /// No description provided for @canvasFudanPassword.
  ///
  /// In zh, this message translates to:
  /// **'UIS 密码'**
  String get canvasFudanPassword;

  /// No description provided for @canvasFudanPasswordHelper.
  ///
  /// In zh, this message translates to:
  /// **'用本机密钥加密保存，只用来登录复旦 UIS'**
  String get canvasFudanPasswordHelper;

  /// No description provided for @canvasNeedsTongji.
  ///
  /// In zh, this message translates to:
  /// **'需要先在 Look Studio 登录同济统一身份认证。'**
  String get canvasNeedsTongji;

  /// No description provided for @canvasTongjiTitle.
  ///
  /// In zh, this message translates to:
  /// **'沿用 Look Studio 的同济登录'**
  String get canvasTongjiTitle;

  /// No description provided for @canvasFudanTitle.
  ///
  /// In zh, this message translates to:
  /// **'用复旦 UIS 登录 Canvas'**
  String get canvasFudanTitle;

  /// No description provided for @canvasTongjiBody.
  ///
  /// In zh, this message translates to:
  /// **'不在 Canvas 账户里创建任何东西。Canvas 的登录过期时，会用和 Look 相同的方式自动续上：先静默单点登录，必要时用你记住的密码。'**
  String get canvasTongjiBody;

  /// No description provided for @canvasFudanBody.
  ///
  /// In zh, this message translates to:
  /// **'不在 Canvas 账户里创建任何东西。Canvas 的登录过期时，会用保存的 UIS 账号自动重新登录。'**
  String get canvasFudanBody;

  /// No description provided for @canvasAutoTokenTitle.
  ///
  /// In zh, this message translates to:
  /// **'由 Look Studio 创建并自动续期'**
  String get canvasAutoTokenTitle;

  /// No description provided for @canvasAutoTokenBody.
  ///
  /// In zh, this message translates to:
  /// **'通过统一身份认证在你的 Canvas 账户里新建一个 90 天的访问令牌，到期前 14 天自动换新，断开时撤销'**
  String get canvasAutoTokenBody;

  /// No description provided for @canvasManualToken.
  ///
  /// In zh, this message translates to:
  /// **'手动获取令牌'**
  String get canvasManualToken;

  /// No description provided for @canvasTokenStep1.
  ///
  /// In zh, this message translates to:
  /// **'打开 Canvas，进入「账户 → 设置」'**
  String get canvasTokenStep1;

  /// No description provided for @canvasTokenStep2.
  ///
  /// In zh, this message translates to:
  /// **'在「已批准的集成」下点「新建访问许可证」，用途填 Look Studio；过期日期可以留空'**
  String get canvasTokenStep2;

  /// No description provided for @canvasTokenStep3.
  ///
  /// In zh, this message translates to:
  /// **'复制生成的令牌（只显示一次），粘贴到下面'**
  String get canvasTokenStep3;

  /// No description provided for @canvasOpenSettings.
  ///
  /// In zh, this message translates to:
  /// **'打开 Canvas 设置页'**
  String get canvasOpenSettings;

  /// No description provided for @canvasTokenHelper.
  ///
  /// In zh, this message translates to:
  /// **'加密保存在本机，界面上只显示末 4 位。令牌到期或被撤销时会提醒你重新粘贴'**
  String get canvasTokenHelper;

  /// No description provided for @canvasSessionAuth.
  ///
  /// In zh, this message translates to:
  /// **'统一身份认证会话 · 过期自动续上'**
  String get canvasSessionAuth;

  /// No description provided for @canvasTokenTail.
  ///
  /// In zh, this message translates to:
  /// **'访问令牌 ····{value}'**
  String canvasTokenTail(Object value);

  /// No description provided for @canvasAutoRenew.
  ///
  /// In zh, this message translates to:
  /// **'自动续期'**
  String get canvasAutoRenew;

  /// No description provided for @canvasTokenExpires.
  ///
  /// In zh, this message translates to:
  /// **'{value}到期 {value2}'**
  String canvasTokenExpires(Object value, Object value2);

  /// No description provided for @canvasCurrentToken.
  ///
  /// In zh, this message translates to:
  /// **'当前令牌'**
  String get canvasCurrentToken;

  /// No description provided for @canvasConnectedAs.
  ///
  /// In zh, this message translates to:
  /// **'已连接为 {value}'**
  String canvasConnectedAs(Object value);

  /// No description provided for @canvasNotSynced.
  ///
  /// In zh, this message translates to:
  /// **'还没有同步'**
  String get canvasNotSynced;

  /// No description provided for @canvasSyncInterval.
  ///
  /// In zh, this message translates to:
  /// **'每 15 分钟自动同步'**
  String get canvasSyncInterval;

  /// No description provided for @canvasSummary.
  ///
  /// In zh, this message translates to:
  /// **'{length} 门课程 · {open} 项作业待交'**
  String canvasSummary(Object length, Object open);

  /// No description provided for @canvasChangeMethod.
  ///
  /// In zh, this message translates to:
  /// **'更改登录方式'**
  String get canvasChangeMethod;

  /// No description provided for @canvasCourseLinks.
  ///
  /// In zh, this message translates to:
  /// **'课程关联'**
  String get canvasCourseLinks;

  /// No description provided for @canvasCourseLinksBody.
  ///
  /// In zh, this message translates to:
  /// **'作业按关联的 Look 课程归类，课件会下载到那门课的文件夹。同名课程会自动关联。'**
  String get canvasCourseLinksBody;

  /// No description provided for @canvasLoadingCourses.
  ///
  /// In zh, this message translates to:
  /// **'正在读取课程…'**
  String get canvasLoadingCourses;

  /// No description provided for @canvasNoCourses.
  ///
  /// In zh, this message translates to:
  /// **'这个学期在 Canvas 上没有课程'**
  String get canvasNoCourses;

  /// No description provided for @canvasLookReplay.
  ///
  /// In zh, this message translates to:
  /// **'Look 录播'**
  String get canvasLookReplay;

  /// No description provided for @canvasAnySite.
  ///
  /// In zh, this message translates to:
  /// **'任意 Canvas 站点，用访问令牌'**
  String get canvasAnySite;

  /// No description provided for @canvasNoLink.
  ///
  /// In zh, this message translates to:
  /// **'不关联'**
  String get canvasNoLink;

  /// No description provided for @canvasAutoNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'自动：未找到同名课程'**
  String get canvasAutoNoMatch;

  /// No description provided for @canvasAutoMatch.
  ///
  /// In zh, this message translates to:
  /// **'自动：{title}'**
  String canvasAutoMatch(Object title);

  /// No description provided for @canvasOpenAssignments.
  ///
  /// In zh, this message translates to:
  /// **'{open} 项作业待交'**
  String canvasOpenAssignments(Object open);

  /// No description provided for @canvasNoOpenAssignments.
  ///
  /// In zh, this message translates to:
  /// **'没有待交作业'**
  String get canvasNoOpenAssignments;

  /// No description provided for @canvasLinkCourse.
  ///
  /// In zh, this message translates to:
  /// **'关联到 Look 课程'**
  String get canvasLinkCourse;

  /// No description provided for @canvasAutoLink.
  ///
  /// In zh, this message translates to:
  /// **'自动匹配同名课程'**
  String get canvasAutoLink;

  /// No description provided for @canvasSchoolConnected.
  ///
  /// In zh, this message translates to:
  /// **'{value} Canvas 已连接'**
  String canvasSchoolConnected(Object value);

  /// No description provided for @canvasConnect.
  ///
  /// In zh, this message translates to:
  /// **'连接 Canvas'**
  String get canvasConnect;

  /// No description provided for @canvasEntryHint.
  ///
  /// In zh, this message translates to:
  /// **'同济、复旦或其他学校的 Canvas：作业进日程，课件下载到课程文件夹'**
  String get canvasEntryHint;

  /// No description provided for @dateMonthDayTime.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日 {value}:{value2}'**
  String dateMonthDayTime(
    Object month,
    Object day,
    Object value,
    Object value2,
  );

  /// No description provided for @assignmentGradedScore.
  ///
  /// In zh, this message translates to:
  /// **'已批改 · {value} 分'**
  String assignmentGradedScore(Object value);

  /// No description provided for @assignmentGraded.
  ///
  /// In zh, this message translates to:
  /// **'已批改'**
  String get assignmentGraded;

  /// No description provided for @assignmentMissing.
  ///
  /// In zh, this message translates to:
  /// **'已截止 · 未提交'**
  String get assignmentMissing;

  /// No description provided for @assignmentTimeLeft.
  ///
  /// In zh, this message translates to:
  /// **'还剩 {value}'**
  String assignmentTimeLeft(Object value);

  /// No description provided for @assignmentNoDue.
  ///
  /// In zh, this message translates to:
  /// **'没有截止时间'**
  String get assignmentNoDue;

  /// No description provided for @assignmentOpenCount.
  ///
  /// In zh, this message translates to:
  /// **'{length} 项待交'**
  String assignmentOpenCount(Object length);

  /// No description provided for @assignmentDue.
  ///
  /// In zh, this message translates to:
  /// **'截止 {value} · {label}'**
  String assignmentDue(Object value, Object label);

  /// No description provided for @canvasAssignmentsTab.
  ///
  /// In zh, this message translates to:
  /// **'作业 {length}'**
  String canvasAssignmentsTab(Object length);

  /// No description provided for @canvasAnnouncementsTab.
  ///
  /// In zh, this message translates to:
  /// **'公告 {length}'**
  String canvasAnnouncementsTab(Object length);

  /// No description provided for @canvasSavedToCourse.
  ///
  /// In zh, this message translates to:
  /// **'已保存到课程文件夹'**
  String get canvasSavedToCourse;

  /// No description provided for @commonDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载失败：{e}'**
  String commonDownloadFailed(Object e);

  /// No description provided for @canvasAnnouncement.
  ///
  /// In zh, this message translates to:
  /// **'公告'**
  String get canvasAnnouncement;

  /// No description provided for @canvasNoAssignments.
  ///
  /// In zh, this message translates to:
  /// **'没有作业'**
  String get canvasNoAssignments;

  /// No description provided for @canvasNoAssignmentsBody.
  ///
  /// In zh, this message translates to:
  /// **'老师在 Canvas 上布置作业后，会出现在这里和日程里。'**
  String get canvasNoAssignmentsBody;

  /// No description provided for @assignmentDueShort.
  ///
  /// In zh, this message translates to:
  /// **'截止 {value}'**
  String assignmentDueShort(Object value);

  /// No description provided for @assignmentPoints.
  ///
  /// In zh, this message translates to:
  /// **'{pts} 分'**
  String assignmentPoints(Object pts);

  /// No description provided for @canvasLoadingFiles.
  ///
  /// In zh, this message translates to:
  /// **'正在读取 Canvas 课件'**
  String get canvasLoadingFiles;

  /// No description provided for @canvasNoFiles.
  ///
  /// In zh, this message translates to:
  /// **'没有可见的课件'**
  String get canvasNoFiles;

  /// No description provided for @canvasNoFilesBody.
  ///
  /// In zh, this message translates to:
  /// **'这门课的文件页和单元里都没有你能下载的文件。'**
  String get canvasNoFilesBody;

  /// No description provided for @canvasFileUpdated.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日更新'**
  String canvasFileUpdated(Object month, Object day);

  /// No description provided for @canvasFileLocked.
  ///
  /// In zh, this message translates to:
  /// **'老师已锁定'**
  String get canvasFileLocked;

  /// No description provided for @canvasDownloadToCourse.
  ///
  /// In zh, this message translates to:
  /// **'下载到课程文件夹'**
  String get canvasDownloadToCourse;

  /// No description provided for @canvasNoAnnouncements.
  ///
  /// In zh, this message translates to:
  /// **'最近 30 天没有公告'**
  String get canvasNoAnnouncements;

  /// No description provided for @workspaceTitle.
  ///
  /// In zh, this message translates to:
  /// **'准备 Linux 工作区'**
  String get workspaceTitle;

  /// No description provided for @workspaceBody.
  ///
  /// In zh, this message translates to:
  /// **'Look Studio 在手机上运行一个精简的 Ubuntu 环境，下载、转写、同步和助手都在里面工作，和电脑版一样。首次需要下载约 30 MB，安装后占用约 140 MB，只保存在本应用内。'**
  String get workspaceBody;

  /// No description provided for @workspacePreparing.
  ///
  /// In zh, this message translates to:
  /// **'正在准备'**
  String get workspacePreparing;

  /// No description provided for @workspaceStart.
  ///
  /// In zh, this message translates to:
  /// **'开始准备'**
  String get workspaceStart;

  /// No description provided for @workspaceUninstallNote.
  ///
  /// In zh, this message translates to:
  /// **'需要联网。卸载应用会删除工作区和其中的课程库；可以先在「设置 → 数据与同步」导出备份。'**
  String get workspaceUninstallNote;

  /// No description provided for @workspaceConnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在连接镜像…'**
  String get workspaceConnecting;

  /// No description provided for @workspaceFfmpegInstalled.
  ///
  /// In zh, this message translates to:
  /// **'已安装 ffmpeg。'**
  String get workspaceFfmpegInstalled;

  /// No description provided for @navCourses.
  ///
  /// In zh, this message translates to:
  /// **'课程列表'**
  String get navCourses;

  /// No description provided for @navTasks.
  ///
  /// In zh, this message translates to:
  /// **'定时'**
  String get navTasks;

  /// No description provided for @shellProfileTooltip.
  ///
  /// In zh, this message translates to:
  /// **'{value} · 个人资料'**
  String shellProfileTooltip(Object value);

  /// No description provided for @shellSessionExpired.
  ///
  /// In zh, this message translates to:
  /// **'登录已过期，自动续期没有成功。点这里重新登录。'**
  String get shellSessionExpired;

  /// No description provided for @appDaemonFailed.
  ///
  /// In zh, this message translates to:
  /// **'后台服务无法启动'**
  String get appDaemonFailed;

  /// No description provided for @appRestart.
  ///
  /// In zh, this message translates to:
  /// **'重新启动'**
  String get appRestart;

  /// No description provided for @homeDate.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日 · 周{wd}'**
  String homeDate(Object month, Object day, Object wd);

  /// No description provided for @quizFocusAll.
  ///
  /// In zh, this message translates to:
  /// **'，覆盖整节课的重点'**
  String get quizFocusAll;

  /// No description provided for @quizFocusOn.
  ///
  /// In zh, this message translates to:
  /// **'，侧重：{focus}'**
  String quizFocusOn(Object focus);

  /// No description provided for @practiceAskWhyRight.
  ///
  /// In zh, this message translates to:
  /// **'请讲讲背后的原理，帮我巩固。'**
  String get practiceAskWhyRight;

  /// No description provided for @practiceAskWhyWrong.
  ///
  /// In zh, this message translates to:
  /// **'请解释为什么错，以及我可能混淆了什么。'**
  String get practiceAskWhyWrong;

  /// No description provided for @practiceSourceRef.
  ///
  /// In zh, this message translates to:
  /// **'出处：{ref}'**
  String practiceSourceRef(Object ref);

  /// No description provided for @practiceOptionSeparator.
  ///
  /// In zh, this message translates to:
  /// **'；'**
  String get practiceOptionSeparator;

  /// No description provided for @backupFromDevice.
  ///
  /// In zh, this message translates to:
  /// **'自 {device}'**
  String backupFromDevice(Object device);

  /// No description provided for @contextCacheHit.
  ///
  /// In zh, this message translates to:
  /// **' · 缓存命中 {value}'**
  String contextCacheHit(Object value);

  /// No description provided for @noteEmptyPreview.
  ///
  /// In zh, this message translates to:
  /// **'_（空）_'**
  String get noteEmptyPreview;

  /// No description provided for @outlineChapterLine.
  ///
  /// In zh, this message translates to:
  /// **'{start}-{end}：{title}'**
  String outlineChapterLine(Object start, Object end, Object title);

  /// No description provided for @downloadsSelectJobs.
  ///
  /// In zh, this message translates to:
  /// **'选择任务'**
  String get downloadsSelectJobs;

  /// No description provided for @downloadsSelectedCount.
  ///
  /// In zh, this message translates to:
  /// **'已选 {n} 项'**
  String downloadsSelectedCount(Object n);

  /// No description provided for @downloadsExitSelection.
  ///
  /// In zh, this message translates to:
  /// **'退出选择'**
  String get downloadsExitSelection;

  /// No description provided for @downloadsSelectNone.
  ///
  /// In zh, this message translates to:
  /// **'全不选'**
  String get downloadsSelectNone;

  /// No description provided for @downloadsCancelTitle.
  ///
  /// In zh, this message translates to:
  /// **'取消 {n} 个下载？'**
  String downloadsCancelTitle(Object n);

  /// No description provided for @downloadsCancelBody.
  ///
  /// In zh, this message translates to:
  /// **'已下载的部分会保留，之后在课程里重新下载会从断点继续。'**
  String get downloadsCancelBody;

  /// No description provided for @downloadsCancelConfirm.
  ///
  /// In zh, this message translates to:
  /// **'取消下载'**
  String get downloadsCancelConfirm;

  /// No description provided for @downloadsKeep.
  ///
  /// In zh, this message translates to:
  /// **'保留下载'**
  String get downloadsKeep;

  /// No description provided for @downloadsPercent.
  ///
  /// In zh, this message translates to:
  /// **'{value}%'**
  String downloadsPercent(Object value);

  /// No description provided for @downloadsSizeProgress.
  ///
  /// In zh, this message translates to:
  /// **'{done} / {total}'**
  String downloadsSizeProgress(Object done, Object total);

  /// No description provided for @downloadsPausedSummary.
  ///
  /// In zh, this message translates to:
  /// **'{n} 个任务已暂停'**
  String downloadsPausedSummary(Object n);

  /// No description provided for @approvalTooltip.
  ///
  /// In zh, this message translates to:
  /// **'操作模式'**
  String get approvalTooltip;

  /// No description provided for @approvalAsk.
  ///
  /// In zh, this message translates to:
  /// **'询问'**
  String get approvalAsk;

  /// No description provided for @approvalAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get approvalAuto;

  /// No description provided for @approvalAskDetail.
  ///
  /// In zh, this message translates to:
  /// **'改动先生成卡片，由你应用'**
  String get approvalAskDetail;

  /// No description provided for @approvalAutoDetail.
  ///
  /// In zh, this message translates to:
  /// **'直接执行，可以撤销'**
  String get approvalAutoDetail;

  /// No description provided for @approvalDeleteNote.
  ///
  /// In zh, this message translates to:
  /// **'删除文件在两种模式下都会先问你'**
  String get approvalDeleteNote;

  /// No description provided for @approvalSwitchHint.
  ///
  /// In zh, this message translates to:
  /// **'Shift+Tab 切换'**
  String get approvalSwitchHint;

  /// No description provided for @approvalFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法切换操作模式。确认助手已启动后再试'**
  String get approvalFailed;

  /// No description provided for @aboutTagline.
  ///
  /// In zh, this message translates to:
  /// **'课堂录像的回放、转写与笔记'**
  String get aboutTagline;

  /// No description provided for @aboutPreview.
  ///
  /// In zh, this message translates to:
  /// **'预览版'**
  String get aboutPreview;

  /// No description provided for @aboutLicenses.
  ///
  /// In zh, this message translates to:
  /// **'开源许可'**
  String get aboutLicenses;

  /// No description provided for @aboutLicensesHint.
  ///
  /// In zh, this message translates to:
  /// **'Look Studio 用到的开源组件'**
  String get aboutLicensesHint;

  /// No description provided for @aboutReward.
  ///
  /// In zh, this message translates to:
  /// **'赞赏'**
  String get aboutReward;

  /// No description provided for @aboutRewardTitle.
  ///
  /// In zh, this message translates to:
  /// **'请作者喝杯咖啡'**
  String get aboutRewardTitle;

  /// No description provided for @aboutRewardBody.
  ///
  /// In zh, this message translates to:
  /// **'觉得 Look Studio 有用，可以用微信扫码赞赏。'**
  String get aboutRewardBody;

  /// No description provided for @aboutRewardPhoneHint.
  ///
  /// In zh, this message translates to:
  /// **'在本机上可以先截屏，再在微信「扫一扫」里从相册识别。'**
  String get aboutRewardPhoneHint;

  /// No description provided for @aboutRewardImage.
  ///
  /// In zh, this message translates to:
  /// **'微信赞赏码'**
  String get aboutRewardImage;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
