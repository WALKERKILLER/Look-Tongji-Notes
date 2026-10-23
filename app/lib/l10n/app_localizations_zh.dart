// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Look Studio';

  @override
  String get levelStandard => '标准';

  @override
  String get levelMedium => '中';

  @override
  String get levelHigh => '高';

  @override
  String get colorTongjiBlue => '同济蓝';

  @override
  String get colorIndigo => '黛青';

  @override
  String get colorPine => '松绿';

  @override
  String get colorAmber => '琥珀';

  @override
  String get colorCinnabar => '朱砂';

  @override
  String get colorBegonia => '海棠';

  @override
  String get colorWisteria => '藤紫';

  @override
  String get colorGraphite => '石墨';

  @override
  String get schemeTonalSpot => '柔和';

  @override
  String get schemeNeutral => '中性';

  @override
  String get schemeVibrant => '鲜明';

  @override
  String get schemeExpressive => '表现';

  @override
  String get schemeFidelity => '忠实';

  @override
  String get schemeContent => '内容';

  @override
  String get schemeMonochrome => '单色';

  @override
  String get fontSystem => '系统默认';

  @override
  String get fontHarmonySans => '鸿蒙黑体';

  @override
  String get fontSourceHanSans => '思源黑体';

  @override
  String get fontLxgwWenKai => '霞鹜文楷';

  @override
  String get fontInterWithSystem => 'Inter + 系统中文';

  @override
  String durationHoursMinutes(Object h, Object m) {
    return '$h 小时 $m 分';
  }

  @override
  String durationHours(Object h) {
    return '$h 小时';
  }

  @override
  String durationMinutes(Object m) {
    return '$m 分钟';
  }

  @override
  String get weekdayShort1 => '一';

  @override
  String get weekdayShort2 => '二';

  @override
  String get weekdayShort3 => '三';

  @override
  String get weekdayShort4 => '四';

  @override
  String get weekdayShort5 => '五';

  @override
  String get weekdayShort6 => '六';

  @override
  String get weekdayShort7 => '日';

  @override
  String timeToday(Object hm) {
    return '今天 $hm';
  }

  @override
  String timeYesterday(Object hm) {
    return '昨天 $hm';
  }

  @override
  String timeTomorrow(Object hm) {
    return '明天 $hm';
  }

  @override
  String weekdayName(Object value) {
    return '周$value';
  }

  @override
  String dateMonthDayWeekday(Object month, Object day, Object wd) {
    return '$month月$day日 $wd';
  }

  @override
  String dateYearMonthDay(Object year, Object month, Object day) {
    return '$year年$month月$day日';
  }

  @override
  String get timeJustNow => '刚刚';

  @override
  String timeMinutesAgo(Object inMinutes) {
    return '$inMinutes 分钟前';
  }

  @override
  String timeHoursAgo(Object inHours) {
    return '$inHours 小时前';
  }

  @override
  String timeDaysAgo(Object inDays) {
    return '$inDays 天前';
  }

  @override
  String dateMonthDay(Object month, Object day) {
    return '$month月$day日';
  }

  @override
  String get timeExpired => '已过期';

  @override
  String durationDaysHours(Object inDays, Object value) {
    return '$inDays 天 $value 小时';
  }

  @override
  String durationHoursMinutesShort(Object inHours, Object value) {
    return '$inHours 小时 $value 分';
  }

  @override
  String durationMinutesLong(Object inMinutes) {
    return '$inMinutes 分钟';
  }

  @override
  String get assetVideo => '视频';

  @override
  String get assetCourseware => '课件';

  @override
  String get assetTranscript => '转写';

  @override
  String get assetAudio => '音频';

  @override
  String get assetParse => '课件解析';

  @override
  String dateMonthDayWeek(Object month, Object day, Object value) {
    return '$month月$day日 周$value';
  }

  @override
  String get screenHome => '首页';

  @override
  String termAutumn(Object y) {
    return '$y 秋';
  }

  @override
  String termSpring(Object value) {
    return '$value 春';
  }

  @override
  String get avatarShapeCircle => '圆形';

  @override
  String get avatarShapeSquircle => '圆角方';

  @override
  String get avatarShapeCookie => '曲奇';

  @override
  String get avatarShapePetal => '花瓣';

  @override
  String pluginContextLine(Object value, Object value2) {
    return '$value：$value2';
  }

  @override
  String get commonNotes => '笔记';

  @override
  String get pluginCategoryVisualize => '可视化';

  @override
  String get pluginCategoryReview => '复习';

  @override
  String get pluginCategoryProgramming => '编程';

  @override
  String get pluginCategoryConnector => '连接器';

  @override
  String get pluginCategoryTutor => '学习方式';

  @override
  String get commonAssignments => '作业';

  @override
  String backgroundJobs(Object active) {
    return '正在处理 $active 个下载或转写任务';
  }

  @override
  String get backgroundSyncing => '正在同步数据';

  @override
  String get daemonNotFound =>
      '找不到后台服务 lookd。开发环境请先构建：cd lookd && go build -o bin/lookd ./cmd/lookd';

  @override
  String daemonCannotReadAppDir(Object e) {
    return '无法读取应用目录：$e';
  }

  @override
  String daemonCannotStart(Object e) {
    return '无法启动后台服务：$e';
  }

  @override
  String daemonKeepsExiting(Object code) {
    return '后台服务反复退出（退出码 $code），可以重新启动再试。';
  }

  @override
  String get mirrorTuna => '清华大学';

  @override
  String get mirrorUstc => '中国科学技术大学';

  @override
  String get mirrorUbuntu => 'Ubuntu 官方';

  @override
  String get workspaceStepUnpack => '解压 Ubuntu 基础系统';

  @override
  String get workspaceStepConfigure => '配置工作区';

  @override
  String get workspaceStepDownload => '下载 Ubuntu 基础系统';

  @override
  String workspaceDownloadHttpError(Object statusCode) {
    return '下载失败（HTTP $statusCode），可以换一个镜像再试';
  }

  @override
  String get workspaceDownloadTimeout => '下载超时，请检查网络或换一个镜像';

  @override
  String workspaceMirrorUnreachable(Object message) {
    return '无法连接镜像站：$message';
  }

  @override
  String get workspaceChecksumFailed => '下载的文件校验失败，请重试';

  @override
  String workspaceUnpackFailed(Object msg) {
    return '解压失败：$msg';
  }

  @override
  String get workspaceInstallFfmpeg => '安装 ffmpeg';

  @override
  String workspaceAptExit(Object code) {
    return 'apt-get 退出码 $code';
  }

  @override
  String workspaceFfmpegFailed(Object e) {
    return '安装 ffmpeg 失败：$e';
  }

  @override
  String get commonLoading => '加载中';

  @override
  String courseDownloadedKind(Object label) {
    return '已下载$label';
  }

  @override
  String get stateSessionExpired => '登录已失效';

  @override
  String get stateLoadFailed => '无法加载';

  @override
  String get commonRetry => '重试';

  @override
  String get readerNoHeadings => '这篇没有小标题';

  @override
  String get readerFindHint => '在本文中查找';

  @override
  String get readerNoMatches => '无结果';

  @override
  String get readerPreviousMatch => '上一处';

  @override
  String get readerNextMatch => '下一处';

  @override
  String get commonClose => '关闭';

  @override
  String get chartTotal => '合计';

  @override
  String dateMonth(Object month) {
    return '$month月';
  }

  @override
  String get weekdayMon => '周一';

  @override
  String get weekdayWed => '周三';

  @override
  String get weekdayFri => '周五';

  @override
  String dateMonthOf(Object value) {
    return '$value月';
  }

  @override
  String get heatmapLess => '少';

  @override
  String get heatmapMore => '多';

  @override
  String durationHoursOnly(Object value) {
    return '$value 小时';
  }

  @override
  String durationHoursMinutesOf(Object value, Object value2) {
    return '$value 小时 $value2 分';
  }

  @override
  String get linkNotInLibrary => '这个文件不在课程库里';

  @override
  String linkCannotOpenFile(Object value) {
    return '无法打开 $value';
  }

  @override
  String get linkCannotOpen => '这个链接无法打开';

  @override
  String get markdownImageUnavailable => '图片不可用';

  @override
  String get timestampOpenLecture => '打开对应课次并跳到这里';

  @override
  String get timestampSeek => '跳到这里播放';

  @override
  String get scrollLeft => '向左滚动';

  @override
  String get scrollRight => '向右滚动';

  @override
  String get commonChoose => '选择';

  @override
  String get pickerChooseFolder => '选择文件夹';

  @override
  String get commonSave => '保存';

  @override
  String get pickerSaveToFolder => '保存到哪个文件夹';

  @override
  String get pickerFolderPath => '文件夹路径';

  @override
  String get commonCancel => '取消';

  @override
  String get loginHeadline => '课堂录像，\n变成你的知识库。';

  @override
  String get loginFeatureDownload => '高速下载录像、PPT 与课件，断点续传';

  @override
  String get loginFeatureTranscribe => '自动转写，按时间轴全文检索';

  @override
  String get loginFeatureAssistant => '常驻助手帮你梳理每一节课';

  @override
  String get loginMissingCredentials => '请输入学号和密码';

  @override
  String get loginSignInAgain => '重新登录';

  @override
  String get loginSignIn => '登录';

  @override
  String get loginWithTongji => '使用同济大学统一身份认证';

  @override
  String get loginStudentId => '学号 / 工号';

  @override
  String get commonPassword => '密码';

  @override
  String get commonShowPassword => '显示密码';

  @override
  String get commonHidePassword => '隐藏密码';

  @override
  String get loginCaptcha => '验证码';

  @override
  String get loginStaySignedIn => '保持登录';

  @override
  String get loginStaySignedInHint => '令牌到期前自动续期，密码加密保存在本机';

  @override
  String get loginPrivacy => '账号只用于登录 look.tongji.edu.cn，凭据仅保存在本机。';

  @override
  String get homeGreetingNight => '夜深了';

  @override
  String get homeGreetingMorning => '早上好';

  @override
  String get homeGreetingNoon => '中午好';

  @override
  String get homeGreetingAfternoon => '下午好';

  @override
  String get homeGreetingEvening => '晚上好';

  @override
  String get homeUpNext => '接下来';

  @override
  String get commonSchedule => '日程';

  @override
  String get commonActivity => '学习足迹';

  @override
  String get homeStatistics => '统计';

  @override
  String get homeContinueWatching => '继续观看';

  @override
  String get homeDownloading => '正在下载';

  @override
  String get commonAll => '全部';

  @override
  String get commonCourses => '课程';

  @override
  String get homeThisTermCourses => '本学期课程';

  @override
  String get homeAllCourses => '全部课程';

  @override
  String get commonLibrary => '课程库';

  @override
  String homeGreeting(Object greeting) {
    return '$greeting，';
  }

  @override
  String get profileEdit => '编辑个人资料';

  @override
  String get homeNextQuote => '换一句';

  @override
  String get homeStatLecturesSaved => '节已存本地';

  @override
  String get homeStatStorage => '占用空间';

  @override
  String get homeStatSegments => '句转写';

  @override
  String get homeStatNotes => '篇笔记';

  @override
  String get listSeparator => '、';

  @override
  String courseLectureCount(Object lectureTotal) {
    return '$lectureTotal 节';
  }

  @override
  String get coursesSync => '从平台同步';

  @override
  String get coursesSearchHint => '搜索课程或老师';

  @override
  String get coursesAllTerms => '全部学期';

  @override
  String coursesHiddenCount(Object hiddenCount) {
    return '已隐藏 $hiddenCount';
  }

  @override
  String get coursesSyncing => '正在同步课程';

  @override
  String get coursesEmptyTerm => '这个学期没有课程';

  @override
  String coursesNoMatch(Object text) {
    return '没有匹配“$text”的课程';
  }

  @override
  String get coursesUnpin => '取消置顶';

  @override
  String get coursesPin => '置顶';

  @override
  String get commonRename => '重命名';

  @override
  String get coursesColor => '课程颜色';

  @override
  String get coursesUnhide => '取消隐藏';

  @override
  String get commonHide => '隐藏';

  @override
  String get coursesRenameTitle => '重命名课程';

  @override
  String coursesOriginalName(Object rawTitle) {
    return '原名：$rawTitle';
  }

  @override
  String get coursesDisplayName => '显示名称';

  @override
  String get coursesDisplayNameHelper => '留空则使用原名，不影响本地文件夹';

  @override
  String get downloadVideoHint => '多路分段并发下载，可断点续传';

  @override
  String get assetSlides => 'PPT 截图';

  @override
  String get downloadSlidesHint => '按时间戳命名，可与视频同步';

  @override
  String get assetAsr => '语音转写';

  @override
  String get downloadAsrHint => '必剪 / 剪映免费识别，分段并行，带时间戳';

  @override
  String downloadQueued(Object length) {
    return '已加入 $length 个任务';
  }

  @override
  String downloadQueueFailed(Object e) {
    return '加入失败：$e';
  }

  @override
  String get downloadThisLecture => '下载这节课';

  @override
  String downloadLectures(Object count) {
    return '下载 $count 节课';
  }

  @override
  String get downloadSavedToLibrary => '文件保存在课程库里，按课程与日期整理';

  @override
  String get downloadNeedsFfmpeg => '需要安装 ffmpeg';

  @override
  String get downloadNoCourseware =>
      '平台不提供课件。在播放器的「资料 → 课件」里上传，MinerU 会解析成可检索的文字。';

  @override
  String get downloadDeleteVideoAfterAsr => '已开启「转写完成后删除视频」：视频会在文字稿生成后被删除';

  @override
  String get downloadDeleteLocalVideoAfterAsr =>
      '已开启「转写完成后删除视频」：本地已有的视频会在转写完成后删除';

  @override
  String get downloadChooseContent => '选择要下载的内容';

  @override
  String get downloadStart => '开始下载';

  @override
  String get courseUnscheduled => '未排期';

  @override
  String dateYearMonth(Object year, Object month) {
    return '$year年$month月';
  }

  @override
  String get screenCourse => '课程详情';

  @override
  String courseSelectedCount(Object length) {
    return '已选 $length 节';
  }

  @override
  String get commonDeselectAll => '取消全选';

  @override
  String get commonSelectAll => '全选';

  @override
  String get courseAssistant => '课程助手';

  @override
  String get courseRefreshSchedule => '刷新课表';

  @override
  String get commonMore => '更多';

  @override
  String get courseLoadingSchedule => '正在读取课表';

  @override
  String courseLectureTotal(Object length) {
    return '$length 节课';
  }

  @override
  String get courseNewestFirst => '最新在前';

  @override
  String get courseOldestFirst => '第一节在前';

  @override
  String get courseBatchDownload => '批量下载';

  @override
  String courseDownloadSelected(Object length) {
    return '下载 $length 节';
  }

  @override
  String courseStatLectures(Object lectures) {
    return '$lectures 节';
  }

  @override
  String courseStatLocal(Object local) {
    return '本地 $local 节';
  }

  @override
  String courseProgress(Object value) {
    return '学习进度 $value%';
  }

  @override
  String get courseContinue => '继续学习';

  @override
  String get courseStart => '开始学习';

  @override
  String lectureOrdinal(Object ordinal) {
    return '第 $ordinal 节';
  }

  @override
  String get lectureNotStarted => '未开始';

  @override
  String get lectureNoReplay => '暂无回放';

  @override
  String get commonDownload => '下载';

  @override
  String get commonPlay => '播放';

  @override
  String playerSeekToast(Object value, Object s) {
    return '$value$s 秒';
  }

  @override
  String playerVolumeToast(Object value) {
    return '音量 $value%';
  }

  @override
  String playerSpeedToast(Object value) {
    return '倍速 $value';
  }

  @override
  String playerBoosting(Object value) {
    return '$value 快进中';
  }

  @override
  String get commonBack => '返回';

  @override
  String get playerCollapsePanel => '收起侧栏';

  @override
  String get playerExpandPanel => '展开侧栏';

  @override
  String get playerLocalSuffix => '（本地）';

  @override
  String get playerPip => '画中画';

  @override
  String playerSeekBack(Object seekStepSec) {
    return '后退 $seekStepSec 秒 (←)';
  }

  @override
  String playerSeekForward(Object seekStepSec) {
    return '前进 $seekStepSec 秒 (→)';
  }

  @override
  String get playerSpeedTooltip => '倍速 ([ / ])';

  @override
  String get playerSubtitlesTooltip => '字幕 (C)';

  @override
  String get playerBookmarkTooltip => '添加书签 (B)';

  @override
  String playerBookmarkAdded(Object value) {
    return '已添加书签 $value';
  }

  @override
  String get playerExitFullscreen => '退出全屏 (F)';

  @override
  String get playerFullscreen => '全屏 (F)';

  @override
  String get playerMute => '静音 (M)';

  @override
  String playerResumedFrom(Object value) {
    return '已从 $value 继续';
  }

  @override
  String get playerStartOver => '从头播放';

  @override
  String get playerPauseTooltip => '暂停 (空格)';

  @override
  String get playerPlayTooltip => '播放 (空格)';

  @override
  String get playerError => '播放出错';

  @override
  String get playerReload => '重新加载';

  @override
  String get playerNoLectureAtTime => '这个时间点没有对应的课次';

  @override
  String get playerPreparing => '正在准备播放';

  @override
  String get screenPlayer => '播放器';

  @override
  String outlineFailed(Object e) {
    return '大纲生成失败：$e';
  }

  @override
  String get outlineNeedsTranscript => '大纲需要文字稿';

  @override
  String get outlineNeedsTranscriptBody => '先转写这节课，助手才能读完内容、按话题分章。';

  @override
  String get asrQueued => '已加入转写队列';

  @override
  String get asrStart => '开始转写';

  @override
  String get outlineTitle => '给这节课分章';

  @override
  String get outlineBody => '助手读完整份文字稿，按话题切成章节。点章节即可跳转，进度条上也会分段显示。';

  @override
  String outlineLastError(Object outlineError) {
    return '上次没有成功：$outlineError';
  }

  @override
  String get outlineGenerate => '生成大纲';

  @override
  String get outlineRegenerating => '正在重新分章…';

  @override
  String outlineSummary(Object length, Object value) {
    return '$length 章 · $value';
  }

  @override
  String get commonRegenerate => '重新生成';

  @override
  String get outlineCopied => '已复制大纲';

  @override
  String get commonCopy => '复制';

  @override
  String get outlineDeleted => '已删除大纲';

  @override
  String get commonUndo => '撤销';

  @override
  String get commonDelete => '删除';

  @override
  String get outlineOptions => '大纲选项';

  @override
  String get durationUnderMinute => '不到 1 分钟';

  @override
  String get outlineWorking => '正在通读文字稿并分章';

  @override
  String get outlineWorkingHint => '长课可能需要一两分钟，可以先去看别的。';

  @override
  String get commonLocal => '本地';

  @override
  String get playerNoVideo => '这节课没有可播放的视频';

  @override
  String get commonOutline => '大纲';

  @override
  String get commonTranscript => '文字稿';

  @override
  String get panelMaterials => '资料';

  @override
  String get commonAssistant => '助手';

  @override
  String panelSlidesCount(Object length) {
    return 'PPT 截图 $length';
  }

  @override
  String panelCoursewareCount(Object length) {
    return '课件 $length';
  }

  @override
  String get slidesEmpty => '这节课没有 PPT 截图';

  @override
  String get slidesEmptyBody => '平台只在老师投屏时生成截图';

  @override
  String get slidesPageOnly => '仅换页';

  @override
  String get slidesFollow => '跟随播放';

  @override
  String get slidesDownload => '下载 PPT';

  @override
  String slidesIndex(Object idx) {
    return '第 $idx 张';
  }

  @override
  String slidesPosition(Object value, Object length, Object value2) {
    return '$value / $length · 从 $value2 播放';
  }

  @override
  String get transcriptEmpty => '还没有文字稿';

  @override
  String get transcriptEmptyBody => '转写会提取音频并生成带时间戳的文字，之后可以搜索、做字幕，也能让助手整理笔记。';

  @override
  String get asrQueuedShowLater => '已加入转写队列，完成后自动显示';

  @override
  String get transcriptFindHint => '在文字稿中查找';

  @override
  String transcriptMatches(Object length) {
    return '$length 处';
  }

  @override
  String get transcriptFollowOn => '跟随播放：开';

  @override
  String get transcriptFollowOff => '跟随播放：关';

  @override
  String get transcriptCopied => '已复制全文';

  @override
  String get transcriptCopyAll => '复制全文';

  @override
  String get promptNotes =>
      '请为这节课整理一份完整的学习笔记并保存：以字幕为主，找出重点和不确定的地方，对照当时的 PPT 和已上传的课件核实，公式用 LaTeX，要点附时间戳。';

  @override
  String get panelAskNotes => '让助手整理笔记';

  @override
  String get panelQuizMore => '出题练习…';

  @override
  String get promptSummarizeRecent => '用几句话概括我刚才看的这一段（当前播放位置前 5 分钟）讲了什么。';

  @override
  String get panelSummarizeRecent => '概括刚才这段';

  @override
  String get commonBookmarks => '书签';

  @override
  String get panelCurrentPosition => '当前位置';

  @override
  String get bookmarksHint => '按 B 键或点播放器上的书签按钮标记重点';

  @override
  String get commonNew => '新建';

  @override
  String get notesHint => '笔记以 Markdown 文件保存在课程库中，助手也能读取';

  @override
  String get commonPractice => '练习';

  @override
  String get panelQuiz => '出题';

  @override
  String get panelQuizHint => '让助手根据这节课出一组选择题，每题附解析和出处';

  @override
  String get downloadsClearTitle => '清除已完成的任务';

  @override
  String get downloadsClearBody => '任务记录会被清除。已下载的文件默认保留在课程库中。';

  @override
  String get downloadsClearAlsoFiles => '同时删除已下载的文件';

  @override
  String get downloadsClearAlsoFilesHint => '视频、PPT、课件和文字稿会从磁盘移除，不可恢复';

  @override
  String get downloadsClearAndDelete => '清除并删除文件';

  @override
  String get downloadsClearRecords => '清除记录';

  @override
  String downloadsClearedFreed(Object value) {
    return '已清除，释放 $value';
  }

  @override
  String get downloadsCleared => '已清除任务记录';

  @override
  String downloadsClearFailed(Object e) {
    return '清除失败：$e';
  }

  @override
  String downloadsRunningSummary(Object running, Object value) {
    return '$running 个任务进行中 · $value';
  }

  @override
  String get downloadsNoneRunning => '没有进行中的任务';

  @override
  String downloadsWaiting(Object length) {
    return '$length 个任务等待中';
  }

  @override
  String get commonTasks => '任务';

  @override
  String commonTasksCount(Object length) {
    return '任务 $length';
  }

  @override
  String get commonDownloaded => '已下载';

  @override
  String get downloadsPauseAll => '全部暂停';

  @override
  String get downloadsResumeAll => '全部继续';

  @override
  String get downloadsClearDone => '清除已完成';

  @override
  String get screenDownloads => '下载管理';

  @override
  String get downloadsEmpty => '还没有下载';

  @override
  String get downloadsEmptyBody => '在课程里选择课次，点下载按钮。视频、PPT、课件和文字稿会按课程整理到课程库。';

  @override
  String get downloadsSectionActive => '进行中';

  @override
  String get commonFailed => '失败';

  @override
  String get downloadsRetryAll => '全部重试';

  @override
  String get commonDone => '已完成';

  @override
  String downloadsBulkDone(Object value, Object n) {
    return '$value $n 个任务';
  }

  @override
  String get commonPaused => '已暂停';

  @override
  String get downloadsResumed => '已继续';

  @override
  String get downloadsRetried => '已重试';

  @override
  String commonActionFailed(Object e) {
    return '操作失败：$e';
  }

  @override
  String get downloadsDeleteFilesTitle => '删除文件？';

  @override
  String downloadsDeleteFilesBody(Object what) {
    return '将从磁盘删除$what，不可恢复。需要时可以重新下载。';
  }

  @override
  String downloadsDeletedFreed(Object value) {
    return '已删除，释放 $value';
  }

  @override
  String commonDeleteFailed(Object e) {
    return '删除失败：$e';
  }

  @override
  String get downloadsLocalEmpty => '本地还没有文件';

  @override
  String get downloadsLocalEmptyBody => '下载完成的视频、PPT、课件和文字稿会出现在这里。';

  @override
  String downloadsDeleteKindFiles(Object value) {
    return '删除$value文件';
  }

  @override
  String downloadsLectureKind(Object value, Object value2) {
    return '这节课的$value（$value2）';
  }

  @override
  String get commonShowInFolder => '在文件夹中显示';

  @override
  String downloadsLectureAllFiles(Object value) {
    return '这节课的全部文件（$value）';
  }

  @override
  String get downloadsDeleteAllFiles => '删除全部文件';

  @override
  String get commonCannotOpenFolder => '无法打开文件夹';

  @override
  String get downloadsStateRunning => '下载中';

  @override
  String downloadsStateRetrying(Object value) {
    return '网络中断，$value 自动重试';
  }

  @override
  String get commonQueued => '排队中';

  @override
  String get commonCancelled => '已取消';

  @override
  String downloadsConnections(Object conns) {
    return '$conns 路并发';
  }

  @override
  String get commonPause => '暂停';

  @override
  String get commonResume => '继续';

  @override
  String get downloadsRemoveRecordOnly => '仅移除记录';

  @override
  String downloadsJobFiles(Object title, Object value, Object value2) {
    return '「$title」的$value文件$value2';
  }

  @override
  String downloadsSizeSuffix(Object value) {
    return '（$value）';
  }

  @override
  String get downloadsDeleteRecordAndFiles => '删除记录和文件';

  @override
  String get noteUntitled => '未命名笔记';

  @override
  String get noteSaved => '笔记已保存';

  @override
  String commonSaveFailed(Object e) {
    return '保存失败：$e';
  }

  @override
  String get commonTitle => '标题';

  @override
  String get commonEdit => '编辑';

  @override
  String get commonPreview => '预览';

  @override
  String noteEditorHint(Object value) {
    return '支持 Markdown。$value内容保存在课程库的 notes 文件夹。';
  }

  @override
  String get noteEditorHintTimestamp => '点“插入时间”记录当前播放位置，';

  @override
  String get noteInsertTime => '插入时间';

  @override
  String get noteUnsaved => '未保存';

  @override
  String searchFailed(Object e) {
    return '搜索失败：$e';
  }

  @override
  String get screenLibrary => '资料库';

  @override
  String get libraryWriteNote => '写笔记';

  @override
  String get librarySearchTitle => '全文搜索所有文字稿与笔记';

  @override
  String get librarySearchHint => '例如：傅里叶变换、期中、作业';

  @override
  String get libraryAllCourses => '所有课程';

  @override
  String librarySearchEmpty(Object value) {
    return '没有找到“$value”';
  }

  @override
  String get librarySearchEmptyBody => '只有转写过的课和笔记可以被搜索。';

  @override
  String librarySearchCount(Object length) {
    return '$length 条结果';
  }

  @override
  String libraryNotesCount(Object length) {
    return '笔记 · $length';
  }

  @override
  String get libraryNotesEmptyHint => '在播放器里边看边记，或让助手根据文字稿整理笔记。';

  @override
  String get libraryNotesEmpty => '这门课还没有笔记。';

  @override
  String get commonUncategorized => '未归类';

  @override
  String get libraryStatLocal => '节课在本地';

  @override
  String get libraryStatSegments => '句文字稿';

  @override
  String get libraryLayoutHint =>
      '每节课一个文件夹：video.mp4、slides/、courseware/、transcript.md/.srt、lecture.json。根目录的 README.md 说明了结构，方便 AI 工具直接阅读；library.db 是可重建的索引。';

  @override
  String get commonOpenFolder => '打开文件夹';

  @override
  String libraryReindexed(Object value) {
    return '已重建索引，$value 节课';
  }

  @override
  String libraryReindexFailed(Object e) {
    return '重建失败：$e';
  }

  @override
  String get libraryReindex => '从文件重建索引';

  @override
  String get noteDeleteTitle => '删除这篇笔记？';

  @override
  String get noteDeleteBody => '笔记文件会从课程库中删除。';

  @override
  String get noteNew => '新笔记';

  @override
  String get commonFind => '查找';

  @override
  String get commonContents => '目录';

  @override
  String get noteOpenLecture => '打开对应课次';

  @override
  String get noteCopiedMarkdown => '已复制 Markdown';

  @override
  String get noteCopyMarkdown => '复制 Markdown';

  @override
  String noteUpdated(Object value) {
    return '· $value更新';
  }

  @override
  String get noteByAssistant => '助手整理';

  @override
  String get noteMine => '我的笔记';

  @override
  String noteSlideRef(Object slideIdx, Object value) {
    return 'PPT 第 $slideIdx 张 · $value';
  }

  @override
  String noteAudioRef(Object value) {
    return '课堂原声 · $value';
  }

  @override
  String noteSlideAt(Object idx, Object value) {
    return '当时的 PPT · 第 $idx 张，$value 起';
  }

  @override
  String notePlayFrom(Object value) {
    return '从 $value 播放';
  }

  @override
  String get noteNoTranscriptHere => '这段没有文字稿';

  @override
  String get coursewareGone => '课件已不存在';

  @override
  String get coursewareNotParsed => '这个课件还没有解析';

  @override
  String coursewareReadFailed(Object statusCode) {
    return '读取失败：HTTP $statusCode';
  }

  @override
  String get readerFullscreen => '全屏阅读';

  @override
  String coursewareParsedBy(Object value) {
    return 'MinerU 解析$value';
  }

  @override
  String coursewarePages(Object pages) {
    return ' · $pages 页';
  }

  @override
  String get readerOpen => '在阅读器中打开';

  @override
  String get chatNew => '新对话';

  @override
  String get modelNone => '未选择模型';

  @override
  String modelsImported(Object value, Object value2) {
    return '导入了 $value 个服务商、$value2 个密钥';
  }

  @override
  String get botDefaultName => '小 Look';

  @override
  String chatOpenFailed(Object e) {
    return '无法打开对话：$e';
  }

  @override
  String scheduleDaily(Object value) {
    return '每天 $value';
  }

  @override
  String scheduleWorkdays(Object value) {
    return '工作日 $value';
  }

  @override
  String scheduleWeekly(Object value, Object value2) {
    return '每周$value $value2';
  }

  @override
  String get scheduleOnce => '一次';

  @override
  String scheduleOnceAt(Object month, Object day, Object value) {
    return '$month月$day日 $value（一次）';
  }

  @override
  String get commonToday => '今天';

  @override
  String get commonTomorrow => '明天';

  @override
  String get commonYesterday => '昨天';

  @override
  String get commonFinished => '完成';

  @override
  String get runCostLimit => '超出费用上限';

  @override
  String get runAborted => '已中止';

  @override
  String get runMissed => '已错过';

  @override
  String get tasksBusy => '助手正在回复，请稍后再查看';

  @override
  String get tasksSubtitle => '按计划在新对话里复盘、出题、汇总截止事项';

  @override
  String tasksCount(Object length) {
    return '$length 个任务';
  }

  @override
  String get commonAllEnabled => '全部启用';

  @override
  String tasksEnabledCount(Object length) {
    return '$length 个启用';
  }

  @override
  String tasksNextUp(Object value, Object value2) {
    return '下一个「$value」$value2';
  }

  @override
  String get tasksNew => '新建任务';

  @override
  String get commonScheduledTasks => '定时任务';

  @override
  String get tasksRuns => '运行记录';

  @override
  String get tasksRunsEmpty => '任务运行后，结果会按时间出现在这里';

  @override
  String get tasksRunsNoMatch => '没有符合条件的运行';

  @override
  String get tasksWorkdays => '工作日';

  @override
  String get commonRunning => '运行中';

  @override
  String get commonEnabled => '已启用';

  @override
  String get tasksRunningNow => '正在运行';

  @override
  String get tasksNoNextRun => '没有下次运行';

  @override
  String tasksNextRun(Object value) {
    return '下次 $value';
  }

  @override
  String get tasksNotFound => '任务不存在';

  @override
  String get tasksDeleteTitle => '删除任务？';

  @override
  String get tasksDeleteBody => '以后不会再运行。已经生成的对话、笔记和练习会保留，运行记录仍可在「运行记录」里查看。';

  @override
  String get commonEnable => '启用';

  @override
  String get tasksStarted => '已开始运行';

  @override
  String get tasksRunNow => '立即运行';

  @override
  String get tasksNextRunLabel => '下次运行';

  @override
  String get commonNone => '无';

  @override
  String get tasksLastResult => '上次结果';

  @override
  String get tasksNeverRun => '还没运行';

  @override
  String get tasksCostLimitCatchUp => '单次上限 · 补跑';

  @override
  String get tasksCostLimit => '单次上限';

  @override
  String get tasksReadOnly => '只读：结果写在总结里，不改动课程库';

  @override
  String tasksAllowed(Object value) {
    return '允许：$value';
  }

  @override
  String get tasksPrompt => '任务内容';

  @override
  String tasksRecentRuns(Object length) {
    return '最近 $length 次';
  }

  @override
  String get tasksNoRunsYet => '还没有运行过。可以点「立即运行」先试一次。';

  @override
  String durationSeconds(Object secs) {
    return '$secs 秒';
  }

  @override
  String durationMinutesSeconds(Object value, Object value2) {
    return '$value 分 $value2 秒';
  }

  @override
  String get tasksManualSuffix => ' · 手动';

  @override
  String get tasksDeletedTask => '已删除的任务';

  @override
  String get tasksDeletedSuffix => '（已删除）';

  @override
  String get commonNewBadge => '新';

  @override
  String get tasksIntroTitle => '让助手按计划替你做事';

  @override
  String get tasksIntroBody =>
      '每次运行都会开一个新对话，结果可在「运行记录」里查看。任务只在 Look Studio 打开时执行；错过的时间可以在 12 小时内启动时补跑。';

  @override
  String get tasksFromBlank => '从空白开始';

  @override
  String get tasksWriteNotes => '保存笔记与大纲';

  @override
  String get tasksWriteSchedule => '标记与修改日程';

  @override
  String get tasksWriteQuizzes => '创建练习';

  @override
  String get taskTemplateReviewName => '每晚复盘今天的课';

  @override
  String get taskTemplateReviewPrompt =>
      '看看今天有哪些课的转写已经完成，为每节课写一份简明的复盘笔记并保存：核心概念、关键公式与例题、老师强调的要点，附时间戳。没有新课就简单说明。';

  @override
  String get taskTemplateQuizName => '每周一出一组复习题';

  @override
  String get taskTemplateQuizPrompt =>
      '回顾上周转写过的课程，为每门课出一组 10 道中等难度的选择题并保存为练习，重点覆盖上周的新内容。';

  @override
  String get taskTemplateDeadlinesName => '每天早上汇总近期截止';

  @override
  String get taskTemplateDeadlinesPrompt =>
      '列出今天起 7 天内的作业、考试和截止事项，按日期排序，提醒最紧急的两件；如果有已经过期但没完成的也指出来。';

  @override
  String get tasksNewTitle => '新建定时任务';

  @override
  String get tasksEditTitle => '编辑定时任务';

  @override
  String get commonName => '名称';

  @override
  String get tasksPromptLabel => '让助手做什么';

  @override
  String get commonTime => '时间';

  @override
  String get commonDaily => '每天';

  @override
  String get commonWeekly => '每周';

  @override
  String get tasksAllowLabel => '允许它';

  @override
  String get tasksAllowHint =>
      '运行时只允许勾选的写入；都不选则只读，结果写在总结里。任务读到的转写稿、课件等资料不能让它做别的修改。';

  @override
  String get tasksLimits => '限制';

  @override
  String get tasksCostLimitLabel => '单次费用上限';

  @override
  String get tasksCostLimitHelper => '超过后中止这次运行（按模型价格估算）';

  @override
  String get tasksCatchUp => '错过时补跑';

  @override
  String get tasksCatchUpHint => '应用在计划时间未运行时，12 小时内启动会补跑一次';

  @override
  String tasksRunReason(Object value) {
    return '：$value';
  }

  @override
  String tasksRunNotice(Object value, Object label, Object why) {
    return '定时任务「$value」$label$why';
  }

  @override
  String get commonView => '查看';

  @override
  String get runtimeReady => '运行环境已就绪';

  @override
  String get runtimeInstallTitle => '安装助手运行环境';

  @override
  String get runtimeIntro =>
      '助手运行在 Node.js 上，并使用 Pi SDK。缺少的部分会安装到 Look Studio 的数据目录，不改动系统；安装包会按官方发布的 SHA-256 校验。';

  @override
  String runtimeReadFailed(Object error) {
    return '无法读取运行环境：$error';
  }

  @override
  String get runtimeSourceManaged => '应用内安装';

  @override
  String get runtimeSourceSystem => '系统';

  @override
  String get runtimeNodeMissing => '未找到可用的 Node.js 22+';

  @override
  String get runtimeDeps => '助手依赖（Pi SDK）';

  @override
  String get commonInstalled => '已安装';

  @override
  String get commonNotInstalled => '未安装';

  @override
  String get runtimeInstallDeps => '安装依赖';

  @override
  String get runtimeStartAssistant => '启动助手';

  @override
  String get runtimeStarting => '正在启动…';

  @override
  String get runtimeStartsAfterInstall => '安装完成后自动启动';

  @override
  String get commonMirror => '下载源';

  @override
  String get runtimeMirrorChina => '国内镜像';

  @override
  String get runtimeMirrorOfficial => '官方源';

  @override
  String get runtimeInstallLog => '安装日志';

  @override
  String get runtimeRecheck => '重新检查';

  @override
  String get runtimeInstalling => '正在安装';

  @override
  String get runtimeInstall => '开始安装';

  @override
  String get commonLecture => '课次';

  @override
  String get commonPlugins => '插件';

  @override
  String get commonSettings => '设置';

  @override
  String get commonUsage => '用量';

  @override
  String botOpened(Object value) {
    return '已打开 $value';
  }

  @override
  String get botResumed => '已继续播放';

  @override
  String get botPaused => '已暂停播放';

  @override
  String get botSeeked => '已跳转';

  @override
  String botRateSet(Object value) {
    return '已调到 $value×';
  }

  @override
  String get commonUndone => '已撤销';

  @override
  String get proposalApplied => '已应用';

  @override
  String get proposalIgnored => '已忽略';

  @override
  String get proposalExpired => '已过期，请让助手重新生成';

  @override
  String get proposalFailed => '执行失败';

  @override
  String get proposalPending => '等你确认';

  @override
  String get commonIgnore => '忽略';

  @override
  String get commonApply => '应用';

  @override
  String get memoryAboutYou => '关于你';

  @override
  String get memoryPreferences => '偏好';

  @override
  String get memoryRoutines => '做法';

  @override
  String get commonOther => '其他';

  @override
  String get botSectionLook => '形象';

  @override
  String get botName => '名字';

  @override
  String get commonColor => '颜色';

  @override
  String get botSectionPersona => '相处方式';

  @override
  String get botPersonaHint => '比如：说话轻松一点，先给结论；复习时多出几道题考我。';

  @override
  String get botSectionMemory => '记忆';

  @override
  String get memoryAdd => '添加记忆';

  @override
  String get memoryConsolidating => '正在沉淀';

  @override
  String get memoryConsolidateNow => '立即沉淀';

  @override
  String memoryIntro(Object botName) {
    return '$botName 会把你说过的、反复用到的做法整理成记忆文件，每次对话都会带上「关于你」和「偏好」。这些文件只保存在本机，不会记下密码、证件号、银行卡号、手机号和密钥。';
  }

  @override
  String memoryReadFailed(Object value) {
    return '读取记忆失败：$value';
  }

  @override
  String get memoryRuns => '沉淀记录';

  @override
  String get memoryRunsEmpty => '还没有沉淀过。对话结束两分钟后会自动整理。';

  @override
  String get memoryAuto => '自动沉淀';

  @override
  String get memoryAutoHint => '对话停下两分钟、或攒够六轮后，在后台整理记忆';

  @override
  String get memoryFromCourses => '从课程会话中学习';

  @override
  String get memoryFromCoursesHint => '课程助手里的对话也参与沉淀';

  @override
  String get botRestartTitle => '重新开始对话？';

  @override
  String botRestartBody(Object botName) {
    return '$botName 的对话会从头开始，记忆保留。';
  }

  @override
  String get botRestart => '重新开始';

  @override
  String get botRestartChat => '重新开始对话';

  @override
  String botMoodLabel(Object botName, Object value) {
    return '$botName，$value';
  }

  @override
  String get memoryEmptyShort => '还没有记忆';

  @override
  String memoryCount(Object length) {
    return '记得 $length 件事';
  }

  @override
  String get memoryWorking => '正在整理记忆';

  @override
  String memoryLastRun(Object value) {
    return '上次沉淀 $value';
  }

  @override
  String memoryWhen(Object when) {
    return '适用：$when';
  }

  @override
  String get memoryDeleteTitle => '删除这条记忆？';

  @override
  String memoryDeleteBody(Object title) {
    return '「$title」会被忘掉，之后的对话不再用到。';
  }

  @override
  String memoryEmpty(Object name) {
    return '还没有记忆。和 $name 聊聊你的专业、学习习惯，或者直接说「记住……」。';
  }

  @override
  String memoryRunChanged(Object length) {
    return '整理了 $length 处';
  }

  @override
  String get memoryRunUnfinished => '没有完成';

  @override
  String get memoryRunNothing => '没有需要记的';

  @override
  String memoryRunScope(Object value, Object value2) {
    return '$value 个对话 $value2 轮';
  }

  @override
  String get memoryUpdated => '更新';

  @override
  String get memoryAppended => '追加';

  @override
  String get memoryFileNameInvalid => '名称只能用小写字母、数字、- 和 _';

  @override
  String get memoryFileName => '文件名';

  @override
  String get memoryFileHint => '---\ntitle: 标题\ndescription: 一句话说明\n---\n内容';

  @override
  String get commonSaving => '保存中…';

  @override
  String get botMoodIdle => '在这儿';

  @override
  String get botMoodListening => '在听';

  @override
  String get botMoodThinking => '在想';

  @override
  String get botMoodWorking => '在做事';

  @override
  String get botMoodTalking => '在说';

  @override
  String get botMoodHappy => '完成了';

  @override
  String get botMoodConfused => '出了点问题';

  @override
  String get botMoodDreaming => '在整理记忆';

  @override
  String get botMoodNotify => '有卡片等你确认';

  @override
  String get botAccessoryAntenna => '天线';

  @override
  String get botAccessoryCatEars => '猫耳';

  @override
  String get botAccessorySprout => '豆芽';

  @override
  String get botAccessoryBunnyEars => '兔耳';

  @override
  String get botAccessoryFeelers => '触角';

  @override
  String get botAccessoryHeadphones => '耳机';

  @override
  String get botAccessoryDrop => '水滴';

  @override
  String get botAccessoryGhost => '小幽灵';

  @override
  String get commonFollowTheme => '跟随主题';

  @override
  String get toolHelp => '查阅功能说明';

  @override
  String get toolCurrentContext => '读取当前界面';

  @override
  String get toolListCourses => '查看课程';

  @override
  String get toolListLectures => '查看课次';

  @override
  String get toolReadTranscript => '阅读文字稿';

  @override
  String get toolLectureDetail => '查看课次详情';

  @override
  String get toolSearchLibrary => '搜索课程库';

  @override
  String get toolListNotes => '查看笔记';

  @override
  String get toolReadNote => '阅读笔记';

  @override
  String get toolSaveNote => '保存笔记';

  @override
  String get toolPrepare => '准备操作';

  @override
  String get toolFindTools => '加载工具';

  @override
  String get toolMarkSchedule => '标记日程';

  @override
  String get toolListSchedule => '查看日程';

  @override
  String get toolEditSchedule => '修改日程';

  @override
  String get toolReadOutline => '读取大纲';

  @override
  String get toolSaveOutline => '保存大纲';

  @override
  String get toolListCourseware => '查看课件';

  @override
  String get toolReadCourseware => '阅读课件';

  @override
  String get toolSearchCourseware => '搜索课件';

  @override
  String get toolListSlides => '查看 PPT';

  @override
  String get toolViewImage => '查看插图';

  @override
  String get toolCreateQuiz => '生成练习';

  @override
  String get toolListQuizzes => '查看练习';

  @override
  String get toolReadAttempts => '查看作答';

  @override
  String get toolOpenPage => '打开页面';

  @override
  String get toolControlPlayer => '控制播放';

  @override
  String get toolReadSettings => '读取设置';

  @override
  String get toolChangeSettings => '调整设置';

  @override
  String get toolManageDownloads => '管理下载';

  @override
  String get toolPrepareDownload => '准备下载';

  @override
  String get toolPrepareDelete => '准备删除文件';

  @override
  String get toolOrganizeCourses => '整理课程';

  @override
  String get toolSyncCourses => '同步课程';

  @override
  String get toolPrepareTask => '准备定时任务';

  @override
  String get toolPreparePlugin => '准备开关插件';

  @override
  String get toolListMemory => '翻看记忆';

  @override
  String get toolRecall => '回想';

  @override
  String get toolRemember => '记下来';

  @override
  String get toolEditMemory => '改记忆';

  @override
  String get toolForget => '忘掉';

  @override
  String get botNoLecture => '没有指明要打开哪一节课';

  @override
  String get botNoCourse => '没有指明要打开哪门课';

  @override
  String get botNoNote => '没有指明要打开哪篇笔记';

  @override
  String get botNoDownload => '没有指明要下载哪一节课';

  @override
  String get botUnsupported => '这个版本还不支持该操作';

  @override
  String get chatSessions => '会话';

  @override
  String get chatNewSession => '新会话';

  @override
  String get commonCollapse => '收起';

  @override
  String get chatAllSessions => '全部会话';

  @override
  String get chatOtherSessions => '其他对话';

  @override
  String get chatNoSessions => '还没有会话';

  @override
  String chatSessionMeta(Object value, Object messages) {
    return '$value · $messages 条';
  }

  @override
  String get assistantStarting => '正在启动助手';

  @override
  String get assistantNotStarted => '助手没有启动';

  @override
  String get assistantSetupModel => '先配置一个模型';

  @override
  String get assistantSetupModelBody =>
      '助手通过 Pi SDK 调用你自己的模型服务。填入 API Key，或导入 Pi CLI 的配置。';

  @override
  String get assistantSetupModelAction => '配置模型';

  @override
  String get suggestSpeed => '把播放速度调到 1.5 倍';

  @override
  String get suggestDownloadRecent => '下载这门课最近三节的视频和转写';

  @override
  String get suggestBiggerText => '把界面字号调大一点';

  @override
  String get suggestRemember => '记住：我更喜欢先给结论的简短回答';

  @override
  String get suggestWeeklyReview => '每周日晚上帮我复习本周的课';

  @override
  String get suggestPauseDownloads => '暂停所有下载';

  @override
  String get suggestSummarizeLecture => '总结这节课到目前为止讲了什么';

  @override
  String get suggestReviewNotes => '把这节课整理成一份复习笔记';

  @override
  String get suggestConceptElsewhere => '刚才提到的概念在哪些课里出现过？';

  @override
  String get suggestCourseRecent => '这门课最近几节讲了什么？';

  @override
  String get suggestUnwatched => '帮我挑出还没看的课';

  @override
  String get suggestQuizCourse => '出一组题考考我这门课的重点';

  @override
  String get suggestWhatCanYouDo => '这个 App 能帮我做什么？';

  @override
  String get suggestRecentUnwatched => '最近有哪些课还没看？';

  @override
  String get suggestSearchMidterm => '在我的课程库里搜索「期中」';

  @override
  String botIntroTitle(Object botName) {
    return '我是 $botName';
  }

  @override
  String get botIntroBody =>
      '我会记住你告诉我的事，也能替你在应用里动手：调设置、整理课程、管理下载、安排定时任务。下载和删除这类操作会先给你一张卡片确认。';

  @override
  String courseAssistantTitle(Object value) {
    return '$value助手';
  }

  @override
  String courseTitleQuoted(Object title) {
    return '《$title》';
  }

  @override
  String courseAssistantIntro(Object botName) {
    return '这个会话只围绕这门课：讲解、找知识点、整理笔记、出题。关于你的偏好来自 $botName 的记忆。';
  }

  @override
  String get chatWelcomeTitle => '有什么可以帮你？';

  @override
  String get chatWelcomeBody => '我能读取课表、文字稿和笔记，帮你整理内容、定位知识点。下载由你点按钮决定。';

  @override
  String chatSwitchCourse(Object value) {
    return '改为「$value」的课程助手';
  }

  @override
  String get chatCurrentCourse => '当前课程';

  @override
  String get chatContextPlaying => '正在播放 · 助手可见当前进度';

  @override
  String chatContextScreen(Object value) {
    return '当前：$value';
  }

  @override
  String get chatInputHint => '问点什么…（Shift+Enter 换行）';

  @override
  String get commonStop => '停止';

  @override
  String get chatSend => '发送 (Enter)';

  @override
  String get pluginsDiscover => '发现插件';

  @override
  String get pluginsManage => '管理插件';

  @override
  String get chatMoreTools => '更多功能';

  @override
  String get thinkingTitle => '思考强度';

  @override
  String get modelsSearchAll => '搜索全部模型…';

  @override
  String get modelsSettings => '模型设置…';

  @override
  String contextUsage(Object value, Object value2, Object value3) {
    return '上下文 $value / $value2（$value3%）';
  }

  @override
  String contextTokens(Object value, Object value2, Object value3) {
    return '本对话累计 输入 $value · 输出 $value2$value3';
  }

  @override
  String contextCost(Object cost) {
    return '估算费用 \$$cost';
  }

  @override
  String get contextCompactHint => '接近上限时 Pi 会自动压缩较早的对话。';

  @override
  String get contextCompactNow => '立即压缩上下文';

  @override
  String get usageView => '查看用量';

  @override
  String contextUsageTooltip(Object value) {
    return '上下文用量 $value%';
  }

  @override
  String get chatThinking => '正在思考…';

  @override
  String get toolReturned => '已返回';

  @override
  String get commonCopied => '已复制';

  @override
  String get chatThinkingNow => '思考中';

  @override
  String get chatThinkingProcess => '思考过程';

  @override
  String get toolArgs => '参数';

  @override
  String get toolResult => '结果';

  @override
  String chatOutlineChapters(Object length) {
    return '大纲 · $length 个章节';
  }

  @override
  String chatSlideRef(Object value) {
    return 'PPT 第 $value 张';
  }

  @override
  String get chatVisionTranscribed => '由识图模型转写给助手';

  @override
  String get chatVisionUnavailable => '当前模型不能看图，可以在「设置 → 助手 → 识图模型」里设置';

  @override
  String get chatSavedToLibrary => '已保存到课程库 · 点击阅读';

  @override
  String get chatCodeCopied => '已复制代码';

  @override
  String get thinkingMinimal => '最少';

  @override
  String get thinkingLow => '低';

  @override
  String get thinkingMax => '最高';

  @override
  String get thinkingHintOff => '直接回答，不做额外推理';

  @override
  String get thinkingHintMinimal => '只做最少的推理，回复最快';

  @override
  String get thinkingHintLow => '简单推理，适合日常问答';

  @override
  String get thinkingHintMedium => '兼顾速度与深度';

  @override
  String get thinkingHintHigh => '推理更充分，等待更久';

  @override
  String get thinkingHintMax => '尽可能深入，最慢，花费也最多';

  @override
  String get thinkingSheetBody => '更强的思考回答更周全，也更慢、更费 token。';

  @override
  String get commonModel => '模型';

  @override
  String get modelsImportPi => '导入 Pi CLI 配置';

  @override
  String get modelsCatalogUpdated => '已更新 models.dev 目录';

  @override
  String get modelsUpdateCatalog => '更新 models.dev 目录';

  @override
  String get modelsAddProvider => '添加服务商';

  @override
  String get modelsAssistantNotStarted => '助手还没启动';

  @override
  String get modelsAssistantNotStartedBody => '启动后才能读取 Pi SDK 的模型注册表';

  @override
  String modelsConfigError(Object value) {
    return '配置文件有误：$value';
  }

  @override
  String get modelsProviders => '已添加的服务商';

  @override
  String get commonAdd => '添加';

  @override
  String get modelsNoProviders =>
      '还没有服务商。点「添加服务商」，从 30 多家预设或 models.dev 目录里选择。';

  @override
  String get modelsStepProvider => '选择服务商';

  @override
  String get modelsStepProviderHint => '30+ 预设，或 models.dev 收录的 200 多家';

  @override
  String get modelsStepKey => '填入 API Key';

  @override
  String get modelsStepKeyHint => '只保存在本机，可一键测试连接';

  @override
  String get modelsStepModels => '挑选模型';

  @override
  String get modelsStepModelsHint => '从服务商拉取模型列表，自动补全价格和上下文长度';

  @override
  String get modelsOnboardingTitle => '给助手接上一个模型';

  @override
  String get commonGetStarted => '开始';

  @override
  String get modelsCurrent => '助手正在使用';

  @override
  String get commonChange => '更换';

  @override
  String get modelsPersona => '附加指令（可选）';

  @override
  String get modelsPersonaHint => '例如：回答尽量简短；术语保留英文并附中文解释';

  @override
  String get modelsPersonaSaved => '已保存附加指令';

  @override
  String get modelsAutoTitle => '自动为对话命名';

  @override
  String get commonInUse => '使用中';

  @override
  String modelsAvailableCount(Object available) {
    return '$available 个可用模型';
  }

  @override
  String get modelsNoKey => '未填写密钥';

  @override
  String get commonCustom => '自定义';

  @override
  String get commonBuiltIn => '内置';

  @override
  String get modelsSearch => '搜索模型';

  @override
  String get modelsNoneAvailable => '没有可用的模型';

  @override
  String get regionChina => '国内';

  @override
  String get regionGlobal => '海外';

  @override
  String get providerDeepseekBlurb => '深度求索，性价比高的推理与对话模型';

  @override
  String get providerSiliconflow => '硅基流动';

  @override
  String get providerSiliconflowBlurb => '聚合 Qwen、DeepSeek、GLM 等开源模型';

  @override
  String get providerBailian => '阿里云百炼';

  @override
  String get providerBailianBlurb => '通义千问 Qwen 全系列';

  @override
  String get providerZhipu => '智谱 BigModel';

  @override
  String get providerZhipuBlurb => 'GLM 系列';

  @override
  String get providerMoonshot => 'Kimi 月之暗面';

  @override
  String get providerMoonshotBlurb => '长上下文的 Kimi 模型';

  @override
  String get providerVolcengine => '火山方舟 · 豆包';

  @override
  String get providerVolcengineBlurb => '字节跳动豆包大模型';

  @override
  String get providerMinimaxBlurb => '稀宇科技 MiniMax 模型';

  @override
  String get providerHunyuan => '腾讯混元';

  @override
  String get providerHunyuanBlurb => '腾讯混元大模型';

  @override
  String get providerQianfan => '百度千帆';

  @override
  String get providerQianfanBlurb => '文心 ERNIE 系列';

  @override
  String get providerStepfun => '阶跃星辰';

  @override
  String get providerStepfunBlurb => 'Step 系列多模态模型';

  @override
  String get providerMimo => '小米 MiMo';

  @override
  String get providerMimoBlurb => '小米 MiMo 推理模型';

  @override
  String get providerModelscope => '魔搭 ModelScope';

  @override
  String get providerModelscopeBlurb => '每日免费额度的开源模型推理';

  @override
  String get providerPayAsYouGoBlurb => '按量付费的模型聚合平台';

  @override
  String get providerOneKeyBlurb => '一个 Key 调用多家模型';

  @override
  String get providerPpio => 'PPIO 派欧云';

  @override
  String get providerPpioBlurb => '分布式云上的开源模型 API';

  @override
  String get providerOpenaiBlurb => 'GPT 系列';

  @override
  String get providerAnthropicBlurb => 'Claude 系列';

  @override
  String get providerGoogleBlurb => 'Gemini 系列，AI Studio 密钥';

  @override
  String get providerOpenrouterBlurb => '数百个模型的统一入口';

  @override
  String get providerXaiBlurb => 'Grok 系列';

  @override
  String get providerGroqBlurb => 'LPU 极速推理';

  @override
  String get providerFreeTrialBlurb => '免费试用额度';

  @override
  String get providerPerplexityBlurb => '联网搜索的 Sonar 模型';

  @override
  String get providerOllamaBlurb => '在本机运行开源模型';

  @override
  String get providerLmstudioBlurb => '图形化的本地模型服务';

  @override
  String get modelTagReasoning => '思考';

  @override
  String get modelTagVision => '识图';

  @override
  String modelTagContext(Object value) {
    return '$value 上下文';
  }

  @override
  String modelTagOutput(Object value) {
    return '输出 $value';
  }

  @override
  String get modelTagFree => '免费';

  @override
  String get modelTagDeprecated => '已弃用';

  @override
  String get apiOpenaiCompatible => 'OpenAI Chat Completions 兼容';

  @override
  String get providerCustom => '自定义服务';

  @override
  String get providerSource => '服务商';

  @override
  String get providerPickModel => '至少选择一个模型';

  @override
  String get providerKeyMissing => '请先填写 API Key';

  @override
  String providerSaved(Object name) {
    return '已保存 $name';
  }

  @override
  String providerTestOk(Object value, Object value2) {
    return '$value 响应正常 · $value2 ms';
  }

  @override
  String providerRemoveKeyTitle(Object name) {
    return '移除 $name 的密钥？';
  }

  @override
  String providerDeleteTitle(Object name) {
    return '删除 $name？';
  }

  @override
  String get providerRemoveKeyBody => '内置服务商仍会保留在目录中，填入密钥即可重新使用。';

  @override
  String get providerDeleteBody => '会删除这个服务及其模型配置。';

  @override
  String providerAddTitle(Object name) {
    return '添加 $name';
  }

  @override
  String get providerBuiltIn => 'Pi SDK 内置服务商';

  @override
  String get commonConnect => '连接';

  @override
  String providerKeySaved(Object value) {
    return '已保存（$value），输入新值以替换';
  }

  @override
  String get providerKeyHint => '粘贴你的密钥';

  @override
  String get commonPaste => '粘贴';

  @override
  String get commonShow => '显示';

  @override
  String get providerLocalNoKey => '本地服务通常不需要密钥。确认服务已在本机启动。';

  @override
  String providerGetKey(Object name) {
    return '还没有密钥？去 $name 获取';
  }

  @override
  String providerDownloadApp(Object name) {
    return '下载 $name';
  }

  @override
  String get commonAdvanced => '高级';

  @override
  String get providerApi => '接口协议';

  @override
  String get providerId => '服务 ID';

  @override
  String get providerIdHelper => '本地标识，字母数字及 . _ -';

  @override
  String get providerTestsOnSave => '保存后会测试一次连接';

  @override
  String providerChosenModels(Object length) {
    return '已选 $length 个模型 · 保存后测试连接';
  }

  @override
  String get providerSaveAndTest => '保存并测试';

  @override
  String get providerBuiltInHint => 'Pi SDK 已内置这家的模型目录，填好密钥即可使用。点模型可设为助手默认。';

  @override
  String providerMoreModels(Object value) {
    return '还有 $value 个，搜索以缩小范围';
  }

  @override
  String get providerChosen => '已选择';

  @override
  String get providerFetchModels => '从服务商获取模型列表';

  @override
  String get providerFetchNeedsKey => '填写密钥后获取模型列表';

  @override
  String get providerFromCatalog => '从 models.dev 选择';

  @override
  String get providerNoModelList =>
      '这家服务可能不提供模型列表接口，可以改从 models.dev 目录选择或手动添加。';

  @override
  String providerOfferedCount(Object length, Object offeredFrom) {
    return '$length 个 · 来自$offeredFrom';
  }

  @override
  String get providerNoMatch => '没有匹配的模型';

  @override
  String get providerNotInCatalog => 'models.dev 未收录';

  @override
  String get providerManualModel => '手动添加模型 ID';

  @override
  String get providerManualModelHint => '例如 deepseek-chat';

  @override
  String get providerCatalogNote =>
      '价格（美元 / 百万 token）、上下文长度和能力标签来自 models.dev，保存时写入 Pi 的模型配置，用于上下文管理和用量统计。';

  @override
  String get addProviderSearchHint => '搜索服务商，例如 硅基、qwen、groq';

  @override
  String get addProviderLoadingCatalog => '没有匹配的预设，正在加载 models.dev 目录…';

  @override
  String addProviderNoMatch(Object q) {
    return '没有找到“$q”。可以用下方「自定义服务」手动填写。';
  }

  @override
  String get addProviderCatalog => 'models.dev 目录';

  @override
  String addProviderMatches(Object length) {
    return '$length 个匹配';
  }

  @override
  String addProviderCatalogEntry(Object value, Object value2) {
    return '$value 个模型 · $value2';
  }

  @override
  String get addProviderNotFound => '找不到？';

  @override
  String get addProviderCompatibleHint =>
      '任何兼容 OpenAI / Anthropic / Gemini 接口的地址，包括中转和自建服务';

  @override
  String addProviderCatalogError(Object catalogError) {
    return 'models.dev 目录暂时不可用：$catalogError';
  }

  @override
  String get addProviderCatalogLoading => '正在加载 models.dev 目录…';

  @override
  String addProviderSearchesMore(Object moreCount) {
    return '搜索时还会在 models.dev 收录的另外 $moreCount 家服务商中查找。';
  }

  @override
  String get addProviderCompatible => '兼容接口';

  @override
  String get addProviderBuiltInKeyOnly => 'Pi SDK 内置，只需密钥';

  @override
  String asrChannelSlots(Object value, Object value2) {
    return '$value $value2 段';
  }

  @override
  String get asrPerChannelLimits => '每个渠道有各自的并发上限';

  @override
  String asrChannelLimits(Object value) {
    return '渠道上限：$value；调高不一定更快，容易触发限流';
  }

  @override
  String get asrIntro =>
      '长音频会切成 20 分钟的段，分给下面的渠道识别；某个渠道被限流时自动冷却，由其他渠道接手。已识别的段会保留，重试时只补缺失的部分。';

  @override
  String get asrLocalEnabled => '本地识别已启用';

  @override
  String get asrTryLocal => '免费渠道限流太厉害？改用本地模型';

  @override
  String asrLocalUnlimited(Object value) {
    return '$value · 不受额度限制';
  }

  @override
  String get asrLocalHint => '下载一个识别模型到本机，看对比图选适合你电脑的那个';

  @override
  String get asrDistribution => '分配方式';

  @override
  String get asrBalanced => '均衡';

  @override
  String asrPrefer(Object value) {
    return '优先$value';
  }

  @override
  String get asrConcurrency => '同时识别的段数';

  @override
  String asrSegments(Object value) {
    return '$value 段';
  }

  @override
  String get asrDeleteVideo => '转写完成后删除视频';

  @override
  String get asrDeleteVideoHint =>
      '只保留文字稿、PPT 和课件，视频文件在转写成功后立即删除，节省磁盘空间。在线播放不受影响。';

  @override
  String get asrReady => '就绪';

  @override
  String asrBusy(Object value) {
    return '识别中 $value 段';
  }

  @override
  String asrCooling(Object value) {
    return '冷却至 $value';
  }

  @override
  String get asrQuotaFull => '额度已满';

  @override
  String get commonDisabled => '已停用';

  @override
  String asrQuotaUsage(Object value, Object value2) {
    return '12 小时内 $value / $value2';
  }

  @override
  String asrOkSegments(Object value) {
    return '成功 $value 段';
  }

  @override
  String asrFailedSegments(Object value) {
    return '失败 $value 段';
  }

  @override
  String commonLastUsed(Object value) {
    return '上次 $value';
  }

  @override
  String get asrRecent => '最近识别记录';

  @override
  String asrRecentSummary(Object length, Object fails) {
    return '最近 $length 次 · 失败 $fails 次';
  }

  @override
  String asrEventLine(
    Object value,
    Object value2,
    Object value3,
    Object value4,
    Object value5,
  ) {
    return '$value  $value2 · 第 $value3 段 · $value4音频 · 用时 $value5 秒';
  }

  @override
  String get commonConnectionOk => '连接正常';

  @override
  String get mineruIntro =>
      '上传的课件（PDF、PPT、Word、图片）交给 MinerU 解析成 Markdown，保留公式、表格和图片，可以全文阅读，也能让助手引用。';

  @override
  String mineruPrecise(Object value) {
    return '精准解析 · Token ••••$value';
  }

  @override
  String get mineruLite => '未配置 Token · 使用免登录的轻量解析';

  @override
  String get commonTest => '测试';

  @override
  String get mineruChangeToken => '更换 Token';

  @override
  String mineruTokenExpired(Object value) {
    return 'Token 已于 $value 过期，请重新生成';
  }

  @override
  String mineruTokenExpires(Object value, Object value2) {
    return 'Token 有效期至 $value$value2';
  }

  @override
  String mineruTokenDaysLeft(Object expDays) {
    return '（还剩 $expDays 天）';
  }

  @override
  String get mineruTokenHint => '在 MinerU 官网「API 管理」中创建';

  @override
  String get mineruGetToken => '获取 Token';

  @override
  String get commonRemove => '移除';

  @override
  String get mineruQuotaToday => '今日额度';

  @override
  String mineruQuotaPages(Object daily) {
    return ' / $daily 页';
  }

  @override
  String mineruQuotaBody(
    Object files,
    Object daily,
    Object value,
    Object value2,
  ) {
    return '今天解析了 $files 个文件。高优先级额度每天 $daily 页，超出后排队变慢；单文件上限 $value、$value2 页。额度由本机按解析结果统计，以官网为准。';
  }

  @override
  String get mineruLiteBody =>
      '轻量解析不需要 Token，但单文件限 10 MB、20 页，输出不含图片。配置 Token 后使用精准解析（每天 1000 页高优先级额度）。';

  @override
  String get mineruModel => '解析模型';

  @override
  String get mineruVlm => 'VLM 精准';

  @override
  String get mineruPipelineHint => 'Pipeline：传统版面分析，速度快、更稳定，适合排版简单的讲义。';

  @override
  String get mineruVlmHint => 'VLM：视觉大模型，公式、表格和复杂版面效果更好，推荐。';

  @override
  String get mineruForceOcr => '强制 OCR';

  @override
  String get mineruForceOcrHint => '扫描版或文字无法复制的 PDF 打开';

  @override
  String get mineruAutoParse => '上传后自动解析';

  @override
  String get mineruAutoParseHint => '关闭后需要在课件卡片上手动点「解析」';

  @override
  String get mineruRecent => '最近解析';

  @override
  String commonPages(Object value) {
    return '$value 页';
  }

  @override
  String get mineruModeLite => '轻量';

  @override
  String get mineruModePrecise => '精准';

  @override
  String benchSortBy(Object label) {
    return '按$label';
  }

  @override
  String benchMetricSource(Object label, Object source) {
    return '$label：$source';
  }

  @override
  String get benchUntested => '未测';

  @override
  String get listComma => '，';

  @override
  String benchRowLabel(Object name, Object summary) {
    return '$name，$summary';
  }

  @override
  String get asrModelRecommended => '推荐';

  @override
  String get asrModelFastest => '最快';

  @override
  String get asrModelAccurate => '最准';

  @override
  String get benchCer => '错字率';

  @override
  String get benchLowerIsBetter => '越短越准';

  @override
  String get benchCerSource =>
      'WenetSpeech 会议测试集（最接近课堂录音）的字错误率，取自各模型的论文；来源不同，相差 1% 以内可视为持平';

  @override
  String get benchTime => '转写用时';

  @override
  String get benchTimeHint => '一节 90 分钟的课';

  @override
  String benchMinutes(Object value) {
    return '$value 分钟';
  }

  @override
  String benchTimeSource(Object value, Object value2) {
    return '在 $value 上实测（$value2，含加载模型），你的设备会有不同';
  }

  @override
  String get benchReferenceMachine => '参考机器';

  @override
  String get benchMemory => '内存';

  @override
  String get benchMemoryHint => '识别时的峰值';

  @override
  String get benchMemorySource => '同一次实测的进程峰值内存';

  @override
  String asrModelDeleteTitle(Object value) {
    return '删除 $value？';
  }

  @override
  String asrModelDeleteBody(Object value) {
    return '会释放 $value 空间。已经转写好的文字稿不受影响，之后可以重新下载。';
  }

  @override
  String get asrModelLocation => '模型存储位置';

  @override
  String get asrModelLocationChanged => '之后下载的模型会保存到新位置';

  @override
  String get asrLocalTitle => '本地识别模型';

  @override
  String get asrUnsupportedTitle => '本机暂不支持';

  @override
  String asrUnsupportedBody(Object value) {
    return '本地识别引擎没有提供 $value 的预编译版本，转写会继续使用免费云端渠道。';
  }

  @override
  String get asrHowToChoose => '怎么选';

  @override
  String get asrHowToChooseBody => '三项都是越短越好。点一行可以在下面看到详情。没有特别需求就选带 ★ 的推荐模型。';

  @override
  String get asrStorage => '存储位置';

  @override
  String get asrSource => '下载来源';

  @override
  String get asrSourceVerify =>
      '所有文件都会按目录里记录的 SHA-256 校验，来源被篡改或版本不一致时会直接报错，不会装上。中断后再次下载会从断点继续。';

  @override
  String get asrCustomLocation => '自定义位置';

  @override
  String get asrDefaultLocation => '默认位置';

  @override
  String asrUsedSpace(Object value) {
    return '已用 $value';
  }

  @override
  String asrFreeSpace(Object value) {
    return '磁盘剩余 $value';
  }

  @override
  String get asrLowSpace => '这块磁盘剩余空间不多，模型可能下载不完。可以换到空间更大的磁盘。';

  @override
  String get asrChangeLocation => '更改位置';

  @override
  String get commonOpenInFileManager => '在文件管理器中打开';

  @override
  String get asrResetLocation => '恢复默认';

  @override
  String get asrLocationAfterDownload => '下载完成后才能更改位置';

  @override
  String get asrMoveTitle => '把已下载的模型一起移过去？';

  @override
  String asrMoveBody(Object value) {
    return '移动：$value 的引擎和模型会搬到新位置，旧位置随后清空。跨磁盘时需要复制一会儿，期间不能转写。';
  }

  @override
  String get asrChangeOnlyBody => '只更改位置：旧文件留在原处，之后下载到新位置；新位置里已有的模型会直接可用。';

  @override
  String get asrChangeOnly => '只更改位置';

  @override
  String get asrMove => '移动';

  @override
  String get asrMoving => '正在移动模型';

  @override
  String get asrMovingBody => '移动完成前本地识别暂停，云端渠道照常转写。可以离开这个页面。';

  @override
  String asrUsingModel(Object value) {
    return '正在使用 $value';
  }

  @override
  String get asrUsingModelBody =>
      '转写会交给本机模型，不受限流和额度影响；开着的云端渠道也会并行分担一部分。想让音频完全不离开本机，在「设置 → 转写」里关掉云端渠道。';

  @override
  String asrDownloadingModel(Object value) {
    return '正在下载 $value';
  }

  @override
  String get asrDownloadingModelBody => '下载完成后会自动启用。可以离开这个页面，进度会在后台继续。';

  @override
  String get asrLocalHeroTitle => '在本机识别';

  @override
  String get asrLocalHeroBody => '下载一个语音识别模型到本机，转写不再受免费云端渠道的限流和额度影响，音频也不会离开本机。';

  @override
  String commonDownloadSize(Object value) {
    return '下载 $value';
  }

  @override
  String asrModelMemory(Object value) {
    return '内存约 $value';
  }

  @override
  String asrModelSpeed(Object value) {
    return '90 分钟课约 $value 分钟';
  }

  @override
  String asrModelCer(Object value) {
    return '错字率 $value%';
  }

  @override
  String get asrModelPunctuated => '自带标点';

  @override
  String get asrModelAutoPunctuation => '自动补标点';

  @override
  String asrModelCerSource(Object value) {
    return '错字率来源：$value';
  }

  @override
  String commonLicense(Object value) {
    return '许可：$value';
  }

  @override
  String get asrModelOriginal => '原始模型';

  @override
  String asrModelDownloadFailed(Object value) {
    return '下载失败：$value';
  }

  @override
  String get asrModelResume => '继续下载';

  @override
  String asrModelDownload(Object value, Object value2) {
    return '下载 $value$value2';
  }

  @override
  String get asrModelIncludesEngine => '（含引擎等）';

  @override
  String get commonDisable => '停用';

  @override
  String get asrModelUse => '使用这个模型';

  @override
  String commonTimeLeft(Object value) {
    return '还需 $value';
  }

  @override
  String get asrSourceHfMirror =>
      '无需任何配置。hf-mirror.com 是社区维护的 Hugging Face 镜像，国内大多数网络可以直连，目录里的全部模型都能从这里下载。';

  @override
  String get asrSourceModelscope =>
      '无需账号或 Token，公开模型直接下载。魔搭上目前只有 Qwen3-ASR 0.6B 和语音检测模型有与原版逐字节相同的副本（社区用户上传），选它们时走魔搭；其余文件自动改用 HF-Mirror，下载时会提示。';

  @override
  String get asrSourceHuggingface =>
      '官方源，文件最全，但国内通常需要代理。Look Studio 的后台服务会使用系统的 HTTPS_PROXY 环境变量。';

  @override
  String get asrSourceCustom =>
      '适合学校、实验室或自建的 Hugging Face 兼容镜像。填写地址模板，{repo} 会换成模型仓库名，{file} 换成文件路径，例如 https://hf-mirror.com/{repo}/resolve/main/{file}。';

  @override
  String get asrSourceTemplate => '地址模板';

  @override
  String get asrEngineSource => '识别引擎（GitHub）';

  @override
  String get asrEngineSourceBody =>
      '第一次下载时会从 GitHub Releases 取 sherpa-onnx 识别引擎（约 25 MB）。GitHub 很慢时，可以填一个 GitHub 下载加速服务的前缀，实际地址为「前缀 + 原始地址」，同样会校验 SHA-256。';

  @override
  String get asrEngineProxy => '加速前缀（可选）';

  @override
  String get asrThreads => '识别线程';

  @override
  String asrThreadCount(Object value) {
    return '$value 线程';
  }

  @override
  String asrThreadsHint(Object cpus) {
    return '线程越多越快，但转写时设备会更忙、更费电。本机有 $cpus 个逻辑核心，默认用一半（最多 4 个）。';
  }

  @override
  String get watchCheckStarted => '已开始检查，有变化会马上通知你';

  @override
  String get watchTitle => '后台自动检查新回放和新课次';

  @override
  String get watchBody =>
      '刚下课的课每 10 分钟查一次回放，之后逐渐放缓；其他课程每 6 小时同步一次；已连接的 Canvas 每 15 分钟同步作业和公告。有变化时立即提醒，课程页也会自动刷新。';

  @override
  String watchAwaiting(Object awaiting) {
    return '正在等待 $awaiting 节课的回放';
  }

  @override
  String get watchNoneAwaiting => '没有等待中的回放';

  @override
  String watchNextCheck(Object value) {
    return '下次检查 $value';
  }

  @override
  String watchLastError(Object err) {
    return '最近一次检查失败：$err';
  }

  @override
  String get watchCheckNow => '立即检查';

  @override
  String get obsidianVault => 'Obsidian 仓库';

  @override
  String get commonSaved => '已保存';

  @override
  String get obsidianChooseVaultFirst => '先选择 Obsidian 仓库文件夹';

  @override
  String obsidianExported(Object value, Object value2, Object value3) {
    return '已导出：新写入 $value，未变 $value2，清理 $value3';
  }

  @override
  String obsidianConflicts(Object conflicts) {
    return '$conflicts 个文件在 Obsidian 中改过，已保留你的版本（笔记的新版本另存为「(Look Studio)」副本）';
  }

  @override
  String get obsidianNotVault => '目标文件夹不是 Obsidian 仓库（没有 .obsidian），仍已导出';

  @override
  String get listSemicolon => '；';

  @override
  String commonExportFailed(Object e) {
    return '导出失败：$e';
  }

  @override
  String get linkRegistered => '已注册：点击 lookstudio:// 链接会打开 Look Studio';

  @override
  String linkRegisterPartial(Object name, Object stderr) {
    return '已写入 $name，但 xdg-mime 失败：$stderr';
  }

  @override
  String linkRegisterFailed(Object e) {
    return '注册失败：$e';
  }

  @override
  String get obsidianNoVault => '未设置仓库';

  @override
  String obsidianStatus(Object value, Object value2) {
    return '导出到 $value$value2';
  }

  @override
  String get commonAutoSuffix => ' · 自动';

  @override
  String get obsidianBody =>
      '把课程库单向导出到 Obsidian 仓库的一个文件夹：总的「课程库」页，每门课一个文件夹，里面分「笔记」（按节次，含引用的 PPT 和课件）和「转写稿」。点击时间戳会回到 Look Studio；在 Obsidian 里改过的文件不会被覆盖。';

  @override
  String get commonLocation => '位置';

  @override
  String get obsidianFolder => '仓库内的文件夹';

  @override
  String get obsidianFolderHelper => '只写入这个文件夹，仓库里的其他笔记不受影响';

  @override
  String get obsidianSaveLocation => '保存位置';

  @override
  String get commonExport => '导出';

  @override
  String get obsidianAutoExport => '笔记变化后自动导出';

  @override
  String get obsidianAutoExportHint => '保存或删除笔记后几秒内刷新';

  @override
  String get commonExporting => '正在导出';

  @override
  String get commonExportNow => '立即导出';

  @override
  String get obsidianBackLinks => '回到 Look Studio';

  @override
  String get obsidianBackLinksBody =>
      '导出的时间戳和课次链接是 lookstudio:// 链接。注册后，在 Obsidian 里点击会打开对应的课和时刻。';

  @override
  String get linkRegister => '注册 lookstudio:// 链接';

  @override
  String get notionSubtitle => '同步到你的 Notion 工作区';

  @override
  String get commonSyncing => '正在同步…';

  @override
  String get notionNoParent => '已连接 · 还没选同步位置';

  @override
  String notionStatus(Object value, Object value2, Object value3) {
    return '$value · $value2 个页面$value3';
  }

  @override
  String get notionDisconnectTitle => '断开 Notion？';

  @override
  String get notionDisconnectBody =>
      '会删除本机保存的令牌和同步记录。已经同步到 Notion 的页面会留在那里；之后重新连接时会新建一份。';

  @override
  String get commonDisconnect => '断开';

  @override
  String get notionChangeParentTitle => '换一个同步位置？';

  @override
  String get notionChangeParentBody => '之后会在新页面下重新创建课程库。原来同步过去的页面留在原处，不再更新。';

  @override
  String notionConnectedTo(Object value) {
    return '已连接到 $value';
  }

  @override
  String get notionWorkspace => '工作区';

  @override
  String get commonNotConnected => '未连接';

  @override
  String get notionBody =>
      '把课程库同步到 Notion 的一个页面下：每门课、每节课一个页面，下面是笔记和转写稿。只写入 Look Studio 创建的页面；在 Notion 里改过的页面不会被覆盖。';

  @override
  String get notionCreateIntegration => '创建集成';

  @override
  String get notionStep1 =>
      '在 Notion 的「集成」页新建一个 Internal 集成，名称填 Look Studio，选择要同步到的工作区';

  @override
  String get notionStep2 => '在「功能」里保留读取、更新和插入内容，其余可以关闭';

  @override
  String get notionStep3 => '复制「Internal Integration Secret」，粘贴到下面';

  @override
  String get notionOpenIntegrations => '打开 Notion 集成页';

  @override
  String get notionSecret => '集成密钥';

  @override
  String get notionSecretHelper => '用本机密钥加密保存，只用来访问你授权给集成的页面';

  @override
  String get commonConnecting => '正在连接';

  @override
  String get notionShareHint => '连接后，还要在 Notion 里把一个页面分享给这个集成，课程库会建在那个页面下面。';

  @override
  String get notionParent => '同步位置';

  @override
  String get notionParentStep1 => '在 Notion 打开想放课程库的页面';

  @override
  String get notionParentStep2 => '点右上角「···」→「连接」，选择你的集成';

  @override
  String get notionParentStep3 => '回到这里选择这个页面';

  @override
  String get notionChoosePage => '选择页面';

  @override
  String get notionParentHint => '课程库在这个页面下的「Look Studio 课程库」里';

  @override
  String get notionOpenInNotion => '在 Notion 中打开';

  @override
  String get notionIntegration => '集成';

  @override
  String notionSecretTail(Object value) {
    return '集成密钥 ••••$value';
  }

  @override
  String get notionLimits =>
      'Notion 里的时间戳显示为文字，图片和课件不上传；需要跳回课堂时刻可以用 Obsidian 导出。';

  @override
  String get commonSync => '同步';

  @override
  String get notionAutoSync => '笔记变化后自动同步';

  @override
  String get notionAutoSyncHint => '保存或删除笔记约 1 分钟后，只同步改动的页面';

  @override
  String commonSyncProgress(Object done, Object total) {
    return '正在同步 $done / $total';
  }

  @override
  String get commonChecking => '正在检查';

  @override
  String notionConflicts(Object length) {
    return '$length 个页面在 Notion 里改过，保留了你的版本';
  }

  @override
  String notionErrors(Object length) {
    return '$length 个页面没有同步成功';
  }

  @override
  String get commonStartSync => '开始同步';

  @override
  String get commonSyncNow => '立即同步';

  @override
  String get notionFullCheckHint => '逐页确认还在，补建在 Notion 里删掉的页面；页面多时较慢';

  @override
  String get notionFullCheck => '完整检查';

  @override
  String syncCreated(Object value) {
    return '新建 $value';
  }

  @override
  String syncUpdated(Object value) {
    return '更新 $value';
  }

  @override
  String syncTrashed(Object value) {
    return '移到废纸篓 $value';
  }

  @override
  String syncUnchanged(Object value) {
    return '未变 $value';
  }

  @override
  String commonLastSynced(Object value) {
    return '上次同步 $value';
  }

  @override
  String notionMoreItems(Object value) {
    return '还有 $value 项';
  }

  @override
  String get notionChooseParent => '选择同步位置';

  @override
  String get notionChooseParentHint => '这里只列出分享给集成的页面。也可以粘贴页面链接。';

  @override
  String get notionSearchHint => '搜索页面或粘贴链接';

  @override
  String get notionUseLink => '使用这个链接';

  @override
  String get commonUntitled => '无标题';

  @override
  String get notionNoPages => '集成还没有可用的页面';

  @override
  String notionNoMatch(Object q) {
    return '没有找到「$q」';
  }

  @override
  String get notionShareSteps => '在 Notion 打开目标页面，点右上角「···」→「连接」，选择你的集成，然后刷新。';

  @override
  String get commonRefresh => '刷新';

  @override
  String get knowledgeConnectApps => '连接到笔记应用';

  @override
  String get knowledgeObsidianSubtitle => '导出到本地仓库，时间戳可点回 Look Studio';

  @override
  String get knowledgeAutoExportSuffix => ' · 自动导出';

  @override
  String get commonOpen => '打开';

  @override
  String get knowledgeFolderTemplates => '文件夹命名模板';

  @override
  String get knowledgeFolderTemplatesHint =>
      '课程可用 {title} {teacher} {term} {id}；课次可用 {date} {title} {sub_id} {lecturer}。只影响之后新建的文件夹。';

  @override
  String get knowledgeCourseFolder => '课程文件夹';

  @override
  String get knowledgeLectureFolder => '课次文件夹';

  @override
  String get knowledgeTemplatesSaved => '模板已保存';

  @override
  String get knowledgeSkillExport => '导出为 Look-Tongji-Notes 技能格式';

  @override
  String get knowledgeSkillExportHint => '以硬链接生成 raw/<课程>/<节次>/原始数据/ 目录，不额外占空间';

  @override
  String get knowledgeSkillExportAction => '导出到技能目录';

  @override
  String get knowledgeTargetFolder => '目标文件夹';

  @override
  String get knowledgeTargetFolderHelper => 'Look-Tongji-Notes 技能所在的文件夹';

  @override
  String knowledgeExported(Object value) {
    return '已导出 $value 节课';
  }

  @override
  String get commonConnected => '已连接';

  @override
  String get webdavAccount => '账号';

  @override
  String get webdavAppPassword => '应用密码';

  @override
  String get webdavJianguoyun => '坚果云';

  @override
  String get webdavJianguoyunHint =>
      '账号是坚果云登录邮箱；在网页版「账户信息 → 安全选项 → 第三方应用管理」添加应用，得到应用密码';

  @override
  String get webdavJianguoyunUser => '坚果云账号（邮箱）';

  @override
  String get webdavNextcloudHint =>
      '地址形如 https://域名/remote.php/dav/files/用户名/；在「个人设置 → 安全」创建应用密码';

  @override
  String get webdavAlistHint => '地址形如 http://主机:5244/dav/，账号和密码用 AList 的用户';

  @override
  String get webdavOtherHint => '填写服务商提供的 WebDAV 地址、账号和密码';

  @override
  String get webdavSubtitle => '用坚果云、Nextcloud 等网盘在设备间同步';

  @override
  String get webdavNeverSynced => '还没同步过';

  @override
  String webdavSyncedAgo(Object value) {
    return '$value同步';
  }

  @override
  String get webdavStopTitle => '停止同步？';

  @override
  String get webdavStopBody =>
      '会删除本机保存的 WebDAV 账号和同步记录。网盘和本机上的文件都会保留；之后重新设置时会按文件内容重新比对。';

  @override
  String get webdavStop => '停止同步';

  @override
  String get webdavTitle => 'WebDAV 同步';

  @override
  String webdavConnectedTo(Object host) {
    return '已连接 $host';
  }

  @override
  String get commonNotSet => '未设置';

  @override
  String get webdavBody =>
      '在电脑、手机之间同步课程库和助手对话：笔记、转写稿、PPT 截图、题目与学习记录、播放进度和书签。每台设备只上传改动过的文件；两边都改过的文件保留较新的一份，另一份放进冲突文件夹。';

  @override
  String get webdavPrivacy =>
      '登录状态、模型密钥和本机设置不会上传，每台设备分别登录。同步目录里的文件按原样保存，不做加密，请使用可信的网盘。';

  @override
  String get webdavEditAccount => '修改账号';

  @override
  String get webdavConnect => '连接网盘';

  @override
  String get webdavServer => '服务器地址';

  @override
  String get webdavKeepPassword => '留空则沿用已保存的密码';

  @override
  String get webdavPasswordSealed => '用本机密钥加密保存';

  @override
  String get webdavFolder => '同步目录';

  @override
  String get webdavFolderHelper => '在网盘里新建，所有设备填同一个';

  @override
  String get commonAutoSync => '自动同步';

  @override
  String get webdavAutoHint => '打开应用时、每 30 分钟，以及笔记改动约 2 分钟后';

  @override
  String get webdavMedia => '同步视频与录音';

  @override
  String get webdavMediaHint => '文件很大，会占用较多网盘空间和流量；不同步时可以在其他设备上重新下载';

  @override
  String get webdavConnectAndSync => '连接并同步';

  @override
  String get webdavSyncing => '正在同步';

  @override
  String webdavConflicts(Object value) {
    return '$value 个文件在两台设备上都改过，保留了较新的版本，另一份在冲突文件夹里';
  }

  @override
  String webdavErrors(Object length, Object first) {
    return '$length 个文件没有同步成功：$first';
  }

  @override
  String get webdavMediaTitle => '视频与录音';

  @override
  String get webdavMediaOn => '一起同步';

  @override
  String get webdavMediaOff => '不同步，在其他设备上重新下载';

  @override
  String get commonModify => '修改';

  @override
  String syncUploaded(Object value) {
    return '上传 $value';
  }

  @override
  String syncDeleted(Object value) {
    return '删除 $value';
  }

  @override
  String get syncInSync => '两边已经一致';

  @override
  String get backupTypeLabel => 'Look Studio 备份';

  @override
  String backupFileName(Object year, Object value, Object value2) {
    return 'LookStudio-备份-$year$value$value2.zip';
  }

  @override
  String backupSaved(Object value) {
    return '备份已保存（$value）';
  }

  @override
  String get backupNotSaved => '没有保存备份';

  @override
  String backupExportFailed(Object err) {
    return '导出失败：$err';
  }

  @override
  String commonFilePickerFailed(Object message) {
    return '无法打开文件选择器：$message';
  }

  @override
  String get backupReading => '正在读取备份';

  @override
  String get backupRestoring => '正在恢复';

  @override
  String get backupNothingToRestore => '没有需要恢复的文件，本机已是最新';

  @override
  String backupRestored(Object value, Object value2) {
    return '已恢复 $value 个文件（$value2）';
  }

  @override
  String get backupViewReplaced => '查看被替换的文件';

  @override
  String backupRestoreFailed(Object e) {
    return '恢复失败：$e';
  }

  @override
  String get storageCleanSyncTitle => '清空同步冲突与回收站？';

  @override
  String get storageCleanSyncBody => '其中是同步时被替换或在其他设备上删除的文件副本，清空后无法找回。';

  @override
  String get commonEmpty => '清空';

  @override
  String storageFreed(Object value) {
    return '已释放 $value';
  }

  @override
  String storageCleanFailed(Object e) {
    return '清理失败：$e';
  }

  @override
  String get dataSyncTitle => '多端同步';

  @override
  String get backupTitle => '备份与恢复';

  @override
  String get backupIntro => '把课程库和助手对话打包成一个 zip，换电脑或重装时恢复。登录状态和密钥不在备份里。';

  @override
  String get backupIncludeMedia => '包含视频与录音';

  @override
  String get backupNoMedia => '课程库里还没有视频';

  @override
  String backupMediaSize(Object value, Object value2) {
    return '$value 个文件，另需 $value2';
  }

  @override
  String get backupExport => '导出备份';

  @override
  String backupExportSize(Object value) {
    return '导出备份 · 约 $value';
  }

  @override
  String get backupRestoreFrom => '从备份恢复';

  @override
  String get backupRestore => '恢复备份';

  @override
  String backupPreviewMeta(
    Object value,
    Object value2,
    Object value3,
    Object value4,
    Object value5,
    Object value6,
  ) {
    return '$value $value2:$value3 导出$value4 · $value5 个文件 · $value6';
  }

  @override
  String get restoreNew => '本机没有';

  @override
  String get restoreNewer => '备份里的较新';

  @override
  String get restoreOlder => '本机的较新';

  @override
  String get restoreSame => '相同';

  @override
  String get restoreSkipped => '不会恢复（密钥或无效路径）';

  @override
  String get restoreMerge => '合并';

  @override
  String get restoreOverwrite => '以备份为准';

  @override
  String get restoreMergeHint => '补上本机没有的文件，更新较旧的文件；本机较新的文件保持不变。';

  @override
  String get restoreOverwriteHint =>
      '所有文件换成备份里的版本；被替换的较新文件会移到课程库的 .sync-conflicts 文件夹。';

  @override
  String get commonRestore => '恢复';

  @override
  String get storageTitle => '存储空间';

  @override
  String get storageCache => '转写缓存与未完成下载';

  @override
  String storageCacheCleanable(Object value) {
    return '可释放 $value · 进行中和暂停的任务会保留';
  }

  @override
  String get storageCacheEmpty => '没有可清理的缓存';

  @override
  String get commonClean => '清理';

  @override
  String get storageCleaningCache => '正在清理缓存';

  @override
  String get storageSync => '同步冲突与回收站';

  @override
  String storageSyncSize(Object value) {
    return '$value · 同步时替换或删除的文件副本';
  }

  @override
  String get storageNoFiles => '没有文件';

  @override
  String get storageEmptying => '正在清空';

  @override
  String get storageCompact => '整理索引';

  @override
  String get storageCompactHint => '合并写入日志、回收空闲空间，让搜索和列表更快';

  @override
  String get storageCompactAction => '整理';

  @override
  String get storageCompacting => '正在整理索引';

  @override
  String get storageModels => '本地语音模型';

  @override
  String get storageAssistant => '助手对话、记忆与插件';

  @override
  String get storageRuntime => '助手运行环境（Node.js 与依赖）';

  @override
  String get diagDaemon => '后台服务';

  @override
  String diagDaemonDetail(Object value, Object port) {
    return '版本 $value · 端口 $port';
  }

  @override
  String get diagNotStarted => '没有启动';

  @override
  String get commonStarting => '正在启动';

  @override
  String get diagWorkspace => 'Linux 工作区';

  @override
  String get diagFfmpegOk => '转写可用';

  @override
  String get diagFfmpegMissingWorkspace => '未安装，转写需要它';

  @override
  String get diagFfmpegMissing => '未找到，请用系统的包管理器安装后重启后台';

  @override
  String diagAgentRunningNode(Object value) {
    return '运行中 · Node.js $value';
  }

  @override
  String get diagAgentNotRunning => '没有运行';

  @override
  String get diagSetupRuntime => '设置运行环境';

  @override
  String diagReportLine(Object title, Object detail) {
    return '$title：$detail';
  }

  @override
  String diagReportLibrary(Object value) {
    return '课程库：$value';
  }

  @override
  String get diagWorkspaceSuffix => ' · Linux 工作区';

  @override
  String get diagCopied => '已复制诊断信息';

  @override
  String get diagStatus => '运行状态';

  @override
  String get diagLogs => '日志';

  @override
  String get diagDaemonLog => '后台日志';

  @override
  String get diagAgentLog => '助手日志';

  @override
  String get diagMaintenance => '维护';

  @override
  String get diagRestart => '重启后台服务';

  @override
  String get diagRestartHint => '后台没有响应时使用；下载和转写会在重启后继续';

  @override
  String get diagRestartAction => '重启';

  @override
  String diagIssues(Object issues) {
    return '$issues 项需要处理';
  }

  @override
  String get diagAllGood => '一切正常';

  @override
  String get diagCopy => '复制诊断信息';

  @override
  String get diagOk => '正常';

  @override
  String get commonNeedsAttention => '需要处理';

  @override
  String get diagChecking => '检查中';

  @override
  String get commonCopyPath => '复制路径';

  @override
  String get commonPathCopied => '已复制路径';

  @override
  String get diagLogEmpty => '暂无记录';

  @override
  String diagLogLines(Object length) {
    return '$length 行';
  }

  @override
  String diagLogRecent(Object length) {
    return '最近 $length 行';
  }

  @override
  String get commonCopyAll => '复制全部';

  @override
  String get diagLogCopied => '已复制日志';

  @override
  String get diagLogNothing => '后台还没有写下任何记录';

  @override
  String get settingsAccount => '账户与学校';

  @override
  String get settingsAccountHint => '统一身份认证、Canvas';

  @override
  String get authTongji => '统一身份认证';

  @override
  String get authRenewNow => '立即续期';

  @override
  String get authSignOut => '退出登录';

  @override
  String get settingsProfileKeyword => '昵称和头像';

  @override
  String get commonSchool => '学校';

  @override
  String get settingsCanvasKeyword => '作业与课件';

  @override
  String get settingsAppearance => '外观与播放';

  @override
  String get settingsAppearanceHint => '主题、字体、播放器';

  @override
  String get settingsDarkMode => '深色模式';

  @override
  String get settingsThemeColor => '主题色';

  @override
  String get settingsSystemAccent => '系统强调色';

  @override
  String get settingsSchemeStyle => '配色风格';

  @override
  String get settingsContrast => '对比度';

  @override
  String get settingsFont => '字体';

  @override
  String get settingsTextSize => '文字大小';

  @override
  String get settingsCompact => '紧凑布局';

  @override
  String get settingsReduceMotion => '减少动画';

  @override
  String get settingsDefaultSpeed => '默认倍速';

  @override
  String get settingsBoostSpeed => '长按快进倍速';

  @override
  String get settingsSeekStepKeyword => '快进快退步长';

  @override
  String get settingsSubtitleSize => '字幕大小';

  @override
  String get settingsResume => '从上次位置继续';

  @override
  String get settingsShowSubtitles => '显示字幕';

  @override
  String get settingsSlidesFollow => 'PPT 跟随播放';

  @override
  String get settingsShortcuts => '快捷键';

  @override
  String get settingsAssistant => '助手与插件';

  @override
  String get settingsAssistantHint => '模型、Bot、插件';

  @override
  String get settingsModels => '模型与服务商';

  @override
  String get settingsVisionModel => '识图模型';

  @override
  String get settingsBotKeyword => 'Bot 形象与记忆';

  @override
  String get settingsRuntimeKeyword => '运行环境 Node.js';

  @override
  String get settingsUsage => '用量与费用';

  @override
  String get settingsDockKeyword => '宽屏常驻右侧';

  @override
  String get settingsBubblesKeyword => '回复气泡';

  @override
  String get settingsShowThinking => '显示思考过程';

  @override
  String get settingsStreamAnimation => '流式输出动画';

  @override
  String get settingsChatTextSize => '对话文字大小';

  @override
  String get settingsTransfer => '下载与转写';

  @override
  String get settingsTransferHint => '下载速度、语音转写、课件解析';

  @override
  String get settingsConnectionsKeyword => '并发连接';

  @override
  String get settingsVideoParallel => '同时下载的视频数';

  @override
  String get settingsRateLimit => '总速度上限';

  @override
  String get settingsStream => '下载哪个画面';

  @override
  String get settingsAsrChannels => '转写渠道';

  @override
  String get settingsLocalModels => '本地模型';

  @override
  String get settingsMineru => 'MinerU 课件解析';

  @override
  String get settingsKnowledge => '知识库';

  @override
  String get settingsKnowledgeHint => '课程库、Obsidian、Notion';

  @override
  String get settingsLibraryLocation => '课程库位置';

  @override
  String get settingsSkillExport => '技能格式导出';

  @override
  String get settingsData => '数据与同步';

  @override
  String get settingsDataHint => 'WebDAV 同步、备份恢复、存储空间';

  @override
  String get settingsSyncMedia => '同步视频';

  @override
  String get settingsCleanCache => '清理缓存';

  @override
  String get commonNotifications => '通知';

  @override
  String get settingsNotificationsHint => '新回放、新课次与自动检查';

  @override
  String get settingsWatchKeyword => '自动检查新回放';

  @override
  String get settingsRemindersKeyword => '提醒';

  @override
  String get settingsDiagnostics => '诊断';

  @override
  String get settingsDiagnosticsHint => '后台状态与日志';

  @override
  String get settingsDaemonKeyword => '后台服务';

  @override
  String get settingsRestartKeyword => '重启后台服务';

  @override
  String get settingsSearch => '搜索设置';

  @override
  String get commonClear => '清除';

  @override
  String settingsNoMatch(Object value) {
    return '没有和「$value」相关的设置';
  }

  @override
  String get settingsSchoolCanvas => '学校与 Canvas';

  @override
  String get settingsAppearanceGroup => '外观';

  @override
  String get settingsWatchGroup => '通知与自动刷新';

  @override
  String get commonUnlimited => '不限';

  @override
  String get settingsConnections => '单个视频的并发连接';

  @override
  String get settingsConnectionsHint => '分段并行下载，支持断点续传；校园网瓶颈时增加连接帮助有限';

  @override
  String settingsConnectionsValue(Object value) {
    return '$value 路';
  }

  @override
  String settingsVideoParallelValue(Object value) {
    return '$value 个';
  }

  @override
  String get commonAuto => '自动';

  @override
  String get streamScreen => '屏幕';

  @override
  String get streamTeacher => '教师';

  @override
  String get streamStudent => '学生';

  @override
  String get settingsStreamHint => '自动：优先屏幕（含 PPT），没有时用第一个画面。';

  @override
  String settingsAccountSummary(Object value) {
    return '$value · 同济大学 · Canvas';
  }

  @override
  String get authSignedIn => '已登录';

  @override
  String get authSignedOut => '未登录';

  @override
  String get authRenewing => '正在续期…';

  @override
  String get authNeedsSignIn => '需要重新登录';

  @override
  String get authMethodPassword => '密码登录';

  @override
  String get authMethodSso => '统一认证静默续期';

  @override
  String get authMethodSavedPassword => '已保存的密码续期';

  @override
  String get authMethodRestored => '从本地会话恢复';

  @override
  String get profileEditTooltip => '编辑昵称和头像';

  @override
  String get schoolTongji => '同济大学';

  @override
  String authExpires(Object value) {
    return '凭证 $value后到期，会在到期前自动续期';
  }

  @override
  String authLastRenewed(Object value, Object method) {
    return '上次续期 $value（$method）';
  }

  @override
  String get authPasswordSaved => '已在本机加密保存密码，统一认证失效时用于自动登录';

  @override
  String get authPasswordNotSaved => '未保存密码：统一认证会话失效后需要手动登录';

  @override
  String get authRenewed => '已续期';

  @override
  String authRenewFailed(Object e) {
    return '续期失败：$e';
  }

  @override
  String get authSignOutTitle => '退出登录？';

  @override
  String get authSignOutBody => '会清除本机保存的会话和密码。已下载的文件不受影响。';

  @override
  String get authSignOutAction => '退出';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get settingsUseSystemAccent => '使用系统强调色';

  @override
  String get settingsUseSystemAccentHint => '从系统主题取色生成配色';

  @override
  String get settingsBoostSpeedHint => '长按画面或按住 → 键临时加速';

  @override
  String get settingsSeekStep => '快进 / 快退步长';

  @override
  String commonSecondsValue(Object seekStepSec) {
    return '$seekStepSec 秒';
  }

  @override
  String get settingsShowSubtitlesHint => '有文字稿时显示字幕';

  @override
  String get settingsSlidesFollowHint => 'PPT 跟随播放进度';

  @override
  String get settingsShortcutsBody =>
      '快捷键：空格 播放/暂停 · ←/→ 快退/快进 · ↑/↓ 音量 · [ ] 倍速 · F 全屏 · C 字幕 · B 书签 · P 侧栏 · M 静音';

  @override
  String get commonNotConfigured => '未配置';

  @override
  String get settingsBotHint => '常驻 bot 的形象、记忆与学习方式';

  @override
  String get settingsRuntime => '运行环境';

  @override
  String get settingsRuntimeReady => 'Node.js 与 Pi SDK 已就绪';

  @override
  String get settingsRuntimeMissing => '助手未运行 · 检查或安装 Node.js 与 Pi SDK';

  @override
  String get settingsUsageHint => '按模型、用途和对话查看 token 与估算费用';

  @override
  String get settingsTasksHint => '让助手按计划复盘、出题、汇总截止事项';

  @override
  String get settingsDock => '宽屏时常驻在右侧';

  @override
  String get settingsBubbles => '回复使用气泡';

  @override
  String get streamFade => '淡入';

  @override
  String get streamBlur => '模糊显现';

  @override
  String get streamTypewriter => '打字机';

  @override
  String get streamWave => '波浪';

  @override
  String visionNative(Object value) {
    return '当前模型可以直接看 PPT 和插图$value';
  }

  @override
  String visionNativeFallback(Object vision) {
    return '；换成纯文本模型时使用 $vision';
  }

  @override
  String get visionNeeded => '当前模型不能看图。选一个识图模型，助手写笔记时才能核对 PPT 和课件插图';

  @override
  String visionUsing(Object vision) {
    return '$vision · 为纯文本模型转写 PPT 和插图';
  }

  @override
  String visionUnavailable(Object vision) {
    return '$vision 不可用（检查服务商密钥）';
  }

  @override
  String get visionBody => '只用来把 PPT 和课件插图转写成文字，交给不能看图的对话模型。结果按图片缓存，同一张图只识别一次。';

  @override
  String get visionNone => '不使用';

  @override
  String get visionNoModels => '已配置的服务商里没有支持图片输入的模型。';

  @override
  String get commonImage => '图片';

  @override
  String profileImageFailed(Object e) {
    return '无法使用这张图片：$e';
  }

  @override
  String get profilePickEmoji => '选择表情';

  @override
  String get profileFromFile => '从图片文件…';

  @override
  String get profileFromUrl => '输入图片链接…';

  @override
  String get profileFromQq => '使用 QQ 头像…';

  @override
  String get profileRandomShape => '随机生成图形';

  @override
  String get profileResetInitial => '重置为首字';

  @override
  String get profileTitle => '个人资料';

  @override
  String get profileLocalOnly => '昵称和头像只保存在本机';

  @override
  String get profileNickname => '昵称';

  @override
  String profileNicknameHelper(Object fallback) {
    return '留空则显示「$fallback」';
  }

  @override
  String get profileInspiration => '灵感';

  @override
  String get profileTapToUse => '点一下换上';

  @override
  String get profileShuffle => '换一批';

  @override
  String get profileShape => '轮廓';

  @override
  String get profileBackground => '底色';

  @override
  String get profileShowQuote => '首页显示一言';

  @override
  String get profileShowQuoteHint => '欢迎语下方展示一句文学、诗词或哲思';

  @override
  String get profileChangeAvatar => '更换头像';

  @override
  String profileBackgroundIndex(Object index) {
    return '底色 $index';
  }

  @override
  String get profileUseQq => '使用 QQ 头像';

  @override
  String get profileImageUrl => '图片链接';

  @override
  String get profileQqNumber => 'QQ 号';

  @override
  String get profileImageAddress => '图片地址';

  @override
  String get profileQqHint => '5–12 位数字';

  @override
  String get profileQqInvalid => '请输入 5–12 位 QQ 号';

  @override
  String get profileUrlInvalid => '需要 http(s) 链接';

  @override
  String get profileQqNote => '头像从 QQ 公开头像服务加载，需要联网';

  @override
  String get commonUse => '使用';

  @override
  String get emojiStudy => '学习';

  @override
  String get emojiFaces => '表情';

  @override
  String get emojiAnimals => '动物';

  @override
  String get emojiNature => '自然';

  @override
  String get emojiFood => '食物';

  @override
  String get emojiHobbies => '爱好';

  @override
  String get profileEmojiHint => '输入或粘贴任意表情';

  @override
  String get scheduleNoTodos => '没有待办';

  @override
  String scheduleOpenTodos(Object open) {
    return '$open 项待办';
  }

  @override
  String scheduleOverdue(Object overdue) {
    return '$overdue 项已逾期';
  }

  @override
  String get scheduleTodos => '待办';

  @override
  String get scheduleEmpty => '还没有日程';

  @override
  String get scheduleEmptyBody =>
      '老师在课上说到带日期的作业、考试或活动时，助手可以把它标记进来，并附上原话和录像时间点。也可以自己添加。';

  @override
  String get scheduleAdd => '添加日程';

  @override
  String get schedulePrevWeek => '上一周';

  @override
  String get schedulePrevMonth => '上个月';

  @override
  String get scheduleNextWeek => '下一周';

  @override
  String get scheduleNextMonth => '下个月';

  @override
  String get scheduleExpandMonth => '展开月历';

  @override
  String get scheduleCollapseMonth => '收起月历';

  @override
  String scheduleDayLabel(Object month, Object day, Object value) {
    return '$month月$day日$value';
  }

  @override
  String scheduleDayItems(Object length) {
    return '，$length 项日程';
  }

  @override
  String get scheduleOverdueHeader => '已逾期';

  @override
  String get scheduleDayEmpty => '这天没有安排';

  @override
  String get scheduleKindExam => '考试';

  @override
  String get scheduleKindEvent => '活动';

  @override
  String get scheduleKindDeadline => '截止';

  @override
  String get commonDayAfterTomorrow => '后天';

  @override
  String scheduleOverdueDays(Object value) {
    return '逾期 $value 天';
  }

  @override
  String scheduleDaysLeft(Object diff) {
    return '还有 $diff 天';
  }

  @override
  String commonUpdateFailed(Object e) {
    return '更新失败：$e';
  }

  @override
  String scheduleRemovedNotice(Object value, Object title) {
    return '$value「$title」';
  }

  @override
  String get scheduleHiddenFromSchedule => '已从日程隐藏';

  @override
  String get commonDeleted => '已删除';

  @override
  String get scheduleOpenInCanvas => '在 Canvas 打开';

  @override
  String get scheduleHide => '从日程隐藏';

  @override
  String get scheduleJumpToSource => '跳到老师提到的地方';

  @override
  String get scheduleNew => '新建日程';

  @override
  String get scheduleEdit => '编辑日程';

  @override
  String get scheduleTitleHint => '例如：实验二报告';

  @override
  String dateYearMonthDayWeek(
    Object year,
    Object month,
    Object day,
    Object value,
  ) {
    return '$year年$month月$day日 周$value';
  }

  @override
  String get scheduleDueDate => '截止日期';

  @override
  String get scheduleAllDay => '全天';

  @override
  String get scheduleNoCourse => '不关联课程';

  @override
  String get scheduleNote => '备注';

  @override
  String get scheduleNoteHint => '要求、提交方式…';

  @override
  String get scheduleAlreadyAdded => '日程里已有';

  @override
  String get scheduleMarkUndone => '标为未完成';

  @override
  String coursewareUploadFailed(Object value, Object e) {
    return '$value 上传失败：$e';
  }

  @override
  String coursewareUploadedParsing(Object ok) {
    return '已上传 $ok 个文件，正在用 MinerU 解析';
  }

  @override
  String coursewareUploaded(Object ok) {
    return '已上传 $ok 个文件';
  }

  @override
  String get coursewareUploadTitle => '上传这节课的课件';

  @override
  String get coursewareUploadBody =>
      'Look 不提供课件。把老师发的 PDF、PPT、Word 传上来，MinerU 会把它解析成文字，可以全文阅读，助手也能引用。';

  @override
  String get commonChooseFiles => '选择文件';

  @override
  String get coursewareParsing => '正在解析…';

  @override
  String commonFilesCount(Object length) {
    return '$length 个文件';
  }

  @override
  String get commonUpload => '上传';

  @override
  String coursewareParsed(Object value) {
    return '已解析$value';
  }

  @override
  String coursewarePagesSuffix(Object pages) {
    return ' $pages 页';
  }

  @override
  String get coursewareParseFailed => '解析失败';

  @override
  String get coursewareParseQueued => '等待解析';

  @override
  String get coursewareNotParsedState => '未解析';

  @override
  String get coursewareParseQueuedToast => '已加入解析队列';

  @override
  String get coursewareParseTooltip => '用 MinerU 解析';

  @override
  String get coursewareDeleteTitle => '删除课件？';

  @override
  String coursewareDeleteBody(Object name) {
    return '「$name」和它的解析结果会从课程库中删除。';
  }

  @override
  String get coursewareReadParsed => '阅读解析结果';

  @override
  String get coursewareOpenOriginal => '打开原文件';

  @override
  String get coursewareReparse => '重新解析';

  @override
  String get coursewareParse => '解析';

  @override
  String get usagePurposeChat => '对话';

  @override
  String get usagePurposeTest => '连接测试';

  @override
  String get usagePurposeMemory => '记忆沉淀';

  @override
  String get range7Days => '7 天';

  @override
  String get range30Days => '30 天';

  @override
  String get range90Days => '90 天';

  @override
  String get rangeThisYear => '今年';

  @override
  String get commonNoData => '没有数据';

  @override
  String get usageEmpty => '这段时间没有用量';

  @override
  String get usageEmptyBody => '和助手对话、生成大纲或识图后，这里会按天统计 token 和估算费用。';

  @override
  String get usageDaily => '每日用量';

  @override
  String get usageBreakdown => '明细';

  @override
  String get usageRecentCalls => '最近调用';

  @override
  String usageCallsInRange(Object label) {
    return '$label内的调用';
  }

  @override
  String get usageCost => '费用';

  @override
  String get usageChart => '图表';

  @override
  String get usageTable => '表格';

  @override
  String get usagePurpose => '用途';

  @override
  String get usageEstimatedCost => '估算费用';

  @override
  String get usageInput => '输入';

  @override
  String get usageCacheHit => '缓存命中';

  @override
  String get usageOutput => '输出';

  @override
  String usageChartSemantics(Object value) {
    return '每日$value柱状图，可切换为表格查看';
  }

  @override
  String get usageTokens => 'token 用量';

  @override
  String get commonNoRecords => '没有记录';

  @override
  String get usageDeletedChat => '已删除的对话';

  @override
  String usageCalls(Object value) {
    return '$value 次';
  }

  @override
  String usageInputTokens(Object value) {
    return '输入 $value';
  }

  @override
  String get usageLastYear => '去年同期';

  @override
  String usagePreviousDays(Object days) {
    return '前 $days 天';
  }

  @override
  String usageNoneIn(Object span) {
    return '$span无用量';
  }

  @override
  String usageSameAs(Object span) {
    return '与$span持平';
  }

  @override
  String usageCompare(Object span, Object value, Object value2) {
    return '比$span$value $value2%';
  }

  @override
  String usageInputOutput(Object value, Object value2) {
    return '输入 $value · 输出 $value2';
  }

  @override
  String get usageCallCount => '调用次数';

  @override
  String usageFailedCalls(Object value) {
    return '失败 $value 次';
  }

  @override
  String get usageCacheRate => '缓存命中率';

  @override
  String usageCacheTokens(Object value) {
    return '命中 $value tokens';
  }

  @override
  String get commonDate => '日期';

  @override
  String usageCachedSuffix(Object value) {
    return '（缓存 $value）';
  }

  @override
  String usageFirstToken(Object value) {
    return '首字 ${value}s';
  }

  @override
  String get usageNoCalls => '没有调用记录';

  @override
  String get activityWatching => '看课';

  @override
  String get activityReading => '阅读';

  @override
  String get activityNone => '没有学习记录';

  @override
  String activityStudyTime(Object value) {
    return '学习 $value';
  }

  @override
  String activityQuizzes(Object quizzes) {
    return '练习 $quizzes 组';
  }

  @override
  String activityAsks(Object asks) {
    return '提问 $asks 次';
  }

  @override
  String activityNotes(Object value) {
    return '笔记 $value 篇';
  }

  @override
  String activityDayLabel(Object value, Object value2) {
    return '$value，$value2';
  }

  @override
  String get activityHasRecord => '有学习记录';

  @override
  String get activityNoStudy => '没有学习';

  @override
  String get activityThisWeek => '本周';

  @override
  String commonDays(Object current) {
    return '$current 天';
  }

  @override
  String get activityStreak => '连续学习';

  @override
  String activityLongestDays(Object longest) {
    return '$longest 天';
  }

  @override
  String get activityLongestStreak => '最长连续';

  @override
  String get activityEmpty => '开始看课或做题后，这里会记录你的学习足迹';

  @override
  String get activityDuration => '学习时长';

  @override
  String get activityDaysCount => '学习天数';

  @override
  String activityActiveDays(Object activeDays) {
    return '$activeDays 天';
  }

  @override
  String get activityCurrentStreak => '当前连续';

  @override
  String activityYear(Object year) {
    return '$year 年';
  }

  @override
  String get activityByKind => '按类型';

  @override
  String get activityByCourse => '按课程';

  @override
  String get activityByCourseEmpty => '还没有按课程记录的学习时间';

  @override
  String get activityStatsTitle => '学习统计';

  @override
  String get activityPrevYear => '上一年';

  @override
  String get activityNextYear => '下一年';

  @override
  String activityDaySummary(Object quizzes, Object asks, Object notes) {
    return '完成练习 $quizzes 组 · 向助手提问 $asks 次 · 新建笔记 $notes 篇';
  }

  @override
  String activityQuizzesDone(Object quizzes) {
    return '完成练习 $quizzes 组';
  }

  @override
  String activityNotesCreated(Object notesCreated) {
    return '新建笔记 $notesCreated 篇';
  }

  @override
  String activityNotesEdited(Object notesEdited) {
    return '编辑笔记 $notesEdited 篇';
  }

  @override
  String activityTranscripts(Object transcripts) {
    return '完成转写 $transcripts 节';
  }

  @override
  String get activityUntimed => '没有计时的学习';

  @override
  String get activityDayEmpty => '这天没有学习记录';

  @override
  String get activityTranscriptsHeader => '完成转写';

  @override
  String practiceScoreNotSaved(Object e) {
    return '成绩没有保存：$e';
  }

  @override
  String practiceOption(Object value, Object text) {
    return '$value「$text」';
  }

  @override
  String promptExplainQuestion(
    Object title,
    Object value,
    Object stem,
    Object value2,
    Object value3,
    Object value4,
    Object value5,
    Object value6,
  ) {
    return '讲解练习「$title」第 $value 题：$stem\n选项：$value2\n我选了 $value3，正确答案是 $value4。$value5$value6';
  }

  @override
  String promptRetryWrong(Object title, Object id) {
    return '根据我在练习「$title」（id $id）中做错的题，针对这些知识点再出一组练习题。';
  }

  @override
  String practiceRetryTitle(Object title) {
    return '重做错题 · $title';
  }

  @override
  String practiceQuestionNumber(Object number) {
    return '第 $number 题';
  }

  @override
  String get practiceHint => '提示';

  @override
  String get practiceExplain => '讲解';

  @override
  String get practiceSource => '查看出处';

  @override
  String get practicePrevious => '上一题';

  @override
  String get practiceBackToSummary => '返回总结';

  @override
  String get practiceNext => '下一题';

  @override
  String get practiceCorrectAnswer => '正确答案';

  @override
  String get practiceYourChoice => '你的选择';

  @override
  String practiceOptionLabel(Object letter, Object value) {
    return '选项 $letter$value';
  }

  @override
  String practiceOptionNote(Object note) {
    return '，$note';
  }

  @override
  String practiceSecondsSuffix(Object value) {
    return ' $value 秒';
  }

  @override
  String get practiceRetryDone => '重做完成';

  @override
  String get practiceDone => '练习完成';

  @override
  String practiceScoreSemantics(Object correct, Object length) {
    return '答对 $correct 题，共 $length 题';
  }

  @override
  String practiceAccuracy(Object value) {
    return '正确率 $value%';
  }

  @override
  String practiceTime(Object time) {
    return '用时 $time';
  }

  @override
  String get commonSavingShort => '正在保存';

  @override
  String practiceBest(Object label) {
    return '最好成绩 $label';
  }

  @override
  String practiceRetryWrong(Object length) {
    return '重做错题 $length';
  }

  @override
  String get practiceMoreOnWrong => '再出一组（针对错题）';

  @override
  String get practiceByTopic => '按知识点';

  @override
  String get practiceReview => '逐题回顾';

  @override
  String get practiceCorrect => '答对';

  @override
  String get practiceUnanswered => '未作答';

  @override
  String get practiceWrong => '答错';

  @override
  String quizCount(Object count) {
    return '$count 题';
  }

  @override
  String get quizEasy => '简单';

  @override
  String get quizHard => '困难';

  @override
  String get quizMedium => '中等';

  @override
  String get quizAssistantBusy => '助手正在回复，请稍后再试';

  @override
  String get quizAssistantNotReady => '助手还没有就绪';

  @override
  String get quizNone => '还没有练习';

  @override
  String quizBestAttempts(Object label, Object attempts) {
    return '最好 $label · 练过 $attempts 次';
  }

  @override
  String get quizStart => '开始练习';

  @override
  String get quizAgain => '再练一次';

  @override
  String promptCreateQuiz(
    Object lectureId,
    Object count,
    Object value,
    Object value2,
  ) {
    return '请为这节课（lecture_id $lectureId）出 $count 道$value难度的选择题，保存为练习$value2。';
  }

  @override
  String get quizCreateTitle => '出题练习';

  @override
  String get quizCreateHint => '助手会先读完字幕并核对 PPT 与课件，每道题都附出处和解析。';

  @override
  String get quizSize => '题量';

  @override
  String quizQuestions(Object n) {
    return '$n 题';
  }

  @override
  String get quizDifficulty => '难度';

  @override
  String get quizFocus => '侧重（可选）';

  @override
  String get quizFocusHint => '例如：卷积的性质、例题的解法';

  @override
  String get quizCreate => '让助手出题';

  @override
  String pluginError(Object pluginTitle, Object value) {
    return '$pluginTitle：$value';
  }

  @override
  String get pluginViewList => '清单';

  @override
  String pluginViewUnknown(Object kind) {
    return '「$kind」视图';
  }

  @override
  String get pluginViewUnsupported => '当前版本的应用还不能显示这种视图，更新应用后即可查看';

  @override
  String get pluginViewAlternative => '换种方式看';

  @override
  String get pluginSlotNoteToolbar => '笔记工具栏';

  @override
  String get pluginSlotLectureMenu => '课次菜单';

  @override
  String get pluginSlotCourseMenu => '课程菜单';

  @override
  String get pluginSlotScheduleItem => '日程条目';

  @override
  String get pluginSlotAssignment => '作业页';

  @override
  String get pluginSlotComposer => '输入框的「+」菜单';

  @override
  String get pluginsAllowThirdPartyTitle => '允许第三方插件？';

  @override
  String get pluginsAllowThirdPartyBody =>
      '第三方插件不是 Look Studio 发布的，与助手运行在同一进程中。只安装你信任的作者的插件；每次安装前都会列出它需要的权限。';

  @override
  String get commonAllow => '允许';

  @override
  String get pluginsInstalled => '已安装的插件';

  @override
  String get pluginsAfterAssistant => '助手启动后可用';

  @override
  String get pluginsNoneInstalled => '还没有安装插件';

  @override
  String pluginsEnabledSummary(Object on, Object value) {
    return '$on 个已启用$value';
  }

  @override
  String pluginsAttentionSuffix(Object attention) {
    return ' · $attention 个需要处理';
  }

  @override
  String get pluginsTagline => '引导式提问、思维导图、闪卡复习……让助手学会新本事';

  @override
  String get pluginsNeedAssistant => '插件在助手里运行，助手启动后就能浏览和管理插件。';

  @override
  String get pluginsSubtitle => '让助手学会新本事：换一种方式讲题、把笔记画成导图、连接你常用的工具';

  @override
  String pluginsInstalledCount(Object n) {
    return '$n 个已安装';
  }

  @override
  String pluginsEnabledCount(Object on) {
    return '$on 个启用';
  }

  @override
  String pluginsAttentionCount(Object attention) {
    return '$attention 个需要处理';
  }

  @override
  String pluginsUpdatesCount(Object updates) {
    return '$updates 个可更新';
  }

  @override
  String get pluginsDiscoverTab => '发现';

  @override
  String pluginsInstalledTab(Object n) {
    return '已安装 $n';
  }

  @override
  String get pluginsOtherSource => '其他来源';

  @override
  String get pluginsSearch => '搜索插件';

  @override
  String pluginsCatalogErrors(Object length) {
    return '有 $length 个插件目录无法加载';
  }

  @override
  String get pluginsNoMatch => '没有找到插件';

  @override
  String get pluginsNoMatchBody => '换个关键词，或在「来源」里添加更多插件目录';

  @override
  String get pluginsOfficial => 'Look Studio 官方';

  @override
  String get pluginsMoreHint =>
      '想要更多？允许第三方插件后，可以添加社区的插件目录，或从文件夹、npm、Git 安装。安装前都会列出它需要的权限。';

  @override
  String get pluginsEmptyBody => '在「发现」里挑几个：换一种方式讲题、把笔记画成导图、连接你常用的工具。';

  @override
  String get pluginsGoDiscover => '去发现';

  @override
  String get pluginsAllowThirdParty => '允许第三方插件';

  @override
  String get pluginsCatalogs => '插件目录…';

  @override
  String get pluginsInstallFrom => '从文件夹、npm 或 Git 安装…';

  @override
  String get pluginsSources => '插件来源';

  @override
  String get pluginsSourcesTab => '来源';

  @override
  String get pluginsNeedsGrant => '需要授权';

  @override
  String get pluginsErrored => '出错';

  @override
  String get pluginsUpdatable => '可更新';

  @override
  String get pluginsFeatured => '精选';

  @override
  String get commonInstall => '安装';

  @override
  String get pluginsInstallOther => '从其他来源安装';

  @override
  String get commonFolder => '文件夹';

  @override
  String get pluginsPinnedVersion => '需要写明固定版本';

  @override
  String get commonNext => '下一步';

  @override
  String get pluginsCatalog => '插件目录';

  @override
  String get pluginsBundled => '随应用提供';

  @override
  String pluginsLoadFailed(Object value) {
    return '加载失败：$value';
  }

  @override
  String get pluginsCatalogHint => 'owner/repo 或 https://…/look-catalog.json';

  @override
  String get pluginsFetching => '正在获取插件…';

  @override
  String pluginsFetchFailed(Object value) {
    return '无法获取插件：$value';
  }

  @override
  String get pluginsInstalling => '正在安装…';

  @override
  String pluginsInstalledLoadFailed(Object value) {
    return '已安装，但加载失败：$value';
  }

  @override
  String pluginsInstalledToast(Object value) {
    return '已安装「$value」';
  }

  @override
  String pluginsInstallFailed(Object value) {
    return '安装失败：$value';
  }

  @override
  String pluginsInstallTitle(Object value) {
    return '安装「$value」？';
  }

  @override
  String pluginsUpdateTitle(Object value) {
    return '更新「$value」？';
  }

  @override
  String pluginsCurrentVersion(Object value) {
    return '当前 v$value';
  }

  @override
  String pluginsThirdPartyWarning(Object value) {
    return '第三方插件，来源：$value。它与助手运行在同一进程中，请确认你信任作者。';
  }

  @override
  String get pluginsNoPermissions => '不需要额外权限';

  @override
  String get pluginsWillBeAble => '它将可以';

  @override
  String get pluginsNewPermissions => '新增';

  @override
  String get pluginsContribAlternative => '笔记的「换种方式看」';

  @override
  String pluginsContribExport(Object value) {
    return '$value导出菜单';
  }

  @override
  String get pluginsContribPage => '插件页面';

  @override
  String pluginsVersionAvailable(Object value) {
    return 'v$value 可用';
  }

  @override
  String get pluginsReviewGrant => '查看并授权';

  @override
  String get commonUninstall => '卸载';

  @override
  String get pluginsHomepage => '主页';

  @override
  String get pluginsTryAsking => '试试这样问';

  @override
  String get pluginsTryAfterEnable => '启用后可以这样问';

  @override
  String get pluginsCapabilities => '助手获得的能力';

  @override
  String get pluginsAppearsIn => '会出现在';

  @override
  String get pluginsPermissions => '权限';

  @override
  String get pluginsGuidanceOnly => '只在对话中提供指导与工具';

  @override
  String get pluginsSettingsSaved => '设置已保存';

  @override
  String pluginsSource(Object value) {
    return '来源：$value';
  }

  @override
  String pluginsUninstallTitle(Object value) {
    return '卸载「$value」？';
  }

  @override
  String get pluginsUninstallBody => '插件保存的数据会一起删除。已经生成的笔记、练习等内容不受影响。';

  @override
  String pluginsSettingRequired(Object value) {
    return '请输入$value';
  }

  @override
  String get pluginsSettingText => '文字';

  @override
  String get pluginsSettingNumber => '数字';

  @override
  String pluginsSettingRange(Object value, Object value2) {
    return '应在 $value–$value2 之间';
  }

  @override
  String get pluginsSaveSettings => '保存设置';

  @override
  String notificationsTooltip(Object unread) {
    return '通知（$unread 条未读）';
  }

  @override
  String get notificationsClose => '关闭通知';

  @override
  String get notificationsMarkAllRead => '全部已读';

  @override
  String get notificationsIntro =>
      '新回放、新课次、Canvas 作业和公告会出现在这里。Look Studio 打开时在后台自动检查。';

  @override
  String get notificationsEmpty => '暂时没有通知';

  @override
  String get notificationsEmptyBody => '有新回放或新作业时会第一时间提醒你';

  @override
  String get notificationsUnread => '未读';

  @override
  String schoolEmblem(Object name) {
    return '$name校徽';
  }

  @override
  String get schoolOther => '其他学校';

  @override
  String get canvasConnected => '已连接 Canvas，正在同步课程和作业';

  @override
  String get canvasDisconnectTitle => '断开 Canvas？';

  @override
  String canvasDisconnectBody(Object value) {
    return '日程里的 Canvas 作业和课程关联会一起移除，已下载的课件保留。$value';
  }

  @override
  String get canvasRevokesToken => 'Look Studio 创建的访问令牌也会被撤销。';

  @override
  String get canvasConnectTitle => '连接你学校的 Canvas';

  @override
  String get canvasConnectBody =>
      '作业会进入日程，截止前一天提醒你；课件可以直接下载到对应课程的文件夹。Look Studio 只读取，不会提交或修改任何内容。';

  @override
  String get canvasUrl => 'Canvas 地址';

  @override
  String get canvasSignInMethod => '登录方式';

  @override
  String get canvasAccessToken => '访问令牌';

  @override
  String get canvasFudanId => '复旦 UIS 学号';

  @override
  String get canvasFudanPassword => 'UIS 密码';

  @override
  String get canvasFudanPasswordHelper => '用本机密钥加密保存，只用来登录复旦 UIS';

  @override
  String get canvasNeedsTongji => '需要先在 Look Studio 登录同济统一身份认证。';

  @override
  String get canvasTongjiTitle => '沿用 Look Studio 的同济登录';

  @override
  String get canvasFudanTitle => '用复旦 UIS 登录 Canvas';

  @override
  String get canvasTongjiBody =>
      '不在 Canvas 账户里创建任何东西。Canvas 的登录过期时，会用和 Look 相同的方式自动续上：先静默单点登录，必要时用你记住的密码。';

  @override
  String get canvasFudanBody =>
      '不在 Canvas 账户里创建任何东西。Canvas 的登录过期时，会用保存的 UIS 账号自动重新登录。';

  @override
  String get canvasAutoTokenTitle => '由 Look Studio 创建并自动续期';

  @override
  String get canvasAutoTokenBody =>
      '通过统一身份认证在你的 Canvas 账户里新建一个 90 天的访问令牌，到期前 14 天自动换新，断开时撤销';

  @override
  String get canvasManualToken => '手动获取令牌';

  @override
  String get canvasTokenStep1 => '打开 Canvas，进入「账户 → 设置」';

  @override
  String get canvasTokenStep2 =>
      '在「已批准的集成」下点「新建访问许可证」，用途填 Look Studio；过期日期可以留空';

  @override
  String get canvasTokenStep3 => '复制生成的令牌（只显示一次），粘贴到下面';

  @override
  String get canvasOpenSettings => '打开 Canvas 设置页';

  @override
  String get canvasTokenHelper => '加密保存在本机，界面上只显示末 4 位。令牌到期或被撤销时会提醒你重新粘贴';

  @override
  String get canvasSessionAuth => '统一身份认证会话 · 过期自动续上';

  @override
  String canvasTokenTail(Object value) {
    return '访问令牌 ····$value';
  }

  @override
  String get canvasAutoRenew => '自动续期';

  @override
  String canvasTokenExpires(Object value, Object value2) {
    return '$value到期 $value2';
  }

  @override
  String get canvasCurrentToken => '当前令牌';

  @override
  String canvasConnectedAs(Object value) {
    return '已连接为 $value';
  }

  @override
  String get canvasNotSynced => '还没有同步';

  @override
  String get canvasSyncInterval => '每 15 分钟自动同步';

  @override
  String canvasSummary(Object length, Object open) {
    return '$length 门课程 · $open 项作业待交';
  }

  @override
  String get canvasChangeMethod => '更改登录方式';

  @override
  String get canvasCourseLinks => '课程关联';

  @override
  String get canvasCourseLinksBody =>
      '作业按关联的 Look 课程归类，课件会下载到那门课的文件夹。同名课程会自动关联。';

  @override
  String get canvasLoadingCourses => '正在读取课程…';

  @override
  String get canvasNoCourses => '这个学期在 Canvas 上没有课程';

  @override
  String get canvasLookReplay => 'Look 录播';

  @override
  String get canvasAnySite => '任意 Canvas 站点，用访问令牌';

  @override
  String get canvasNoLink => '不关联';

  @override
  String get canvasAutoNoMatch => '自动：未找到同名课程';

  @override
  String canvasAutoMatch(Object title) {
    return '自动：$title';
  }

  @override
  String canvasOpenAssignments(Object open) {
    return '$open 项作业待交';
  }

  @override
  String get canvasNoOpenAssignments => '没有待交作业';

  @override
  String get canvasLinkCourse => '关联到 Look 课程';

  @override
  String get canvasAutoLink => '自动匹配同名课程';

  @override
  String canvasSchoolConnected(Object value) {
    return '$value Canvas 已连接';
  }

  @override
  String get canvasConnect => '连接 Canvas';

  @override
  String get canvasEntryHint => '同济、复旦或其他学校的 Canvas：作业进日程，课件下载到课程文件夹';

  @override
  String dateMonthDayTime(
    Object month,
    Object day,
    Object value,
    Object value2,
  ) {
    return '$month月$day日 $value:$value2';
  }

  @override
  String assignmentGradedScore(Object value) {
    return '已批改 · $value 分';
  }

  @override
  String get assignmentGraded => '已批改';

  @override
  String get assignmentMissing => '已截止 · 未提交';

  @override
  String assignmentTimeLeft(Object value) {
    return '还剩 $value';
  }

  @override
  String get assignmentNoDue => '没有截止时间';

  @override
  String assignmentOpenCount(Object length) {
    return '$length 项待交';
  }

  @override
  String assignmentDue(Object value, Object label) {
    return '截止 $value · $label';
  }

  @override
  String canvasAssignmentsTab(Object length) {
    return '作业 $length';
  }

  @override
  String canvasAnnouncementsTab(Object length) {
    return '公告 $length';
  }

  @override
  String get canvasSavedToCourse => '已保存到课程文件夹';

  @override
  String commonDownloadFailed(Object e) {
    return '下载失败：$e';
  }

  @override
  String get canvasAnnouncement => '公告';

  @override
  String get canvasNoAssignments => '没有作业';

  @override
  String get canvasNoAssignmentsBody => '老师在 Canvas 上布置作业后，会出现在这里和日程里。';

  @override
  String assignmentDueShort(Object value) {
    return '截止 $value';
  }

  @override
  String assignmentPoints(Object pts) {
    return '$pts 分';
  }

  @override
  String get canvasLoadingFiles => '正在读取 Canvas 课件';

  @override
  String get canvasNoFiles => '没有可见的课件';

  @override
  String get canvasNoFilesBody => '这门课的文件页和单元里都没有你能下载的文件。';

  @override
  String canvasFileUpdated(Object month, Object day) {
    return '$month月$day日更新';
  }

  @override
  String get canvasFileLocked => '老师已锁定';

  @override
  String get canvasDownloadToCourse => '下载到课程文件夹';

  @override
  String get canvasNoAnnouncements => '最近 30 天没有公告';

  @override
  String get workspaceTitle => '准备 Linux 工作区';

  @override
  String get workspaceBody =>
      'Look Studio 在手机上运行一个精简的 Ubuntu 环境，下载、转写、同步和助手都在里面工作，和电脑版一样。首次需要下载约 30 MB，安装后占用约 140 MB，只保存在本应用内。';

  @override
  String get workspacePreparing => '正在准备';

  @override
  String get workspaceStart => '开始准备';

  @override
  String get workspaceUninstallNote =>
      '需要联网。卸载应用会删除工作区和其中的课程库；可以先在「设置 → 数据与同步」导出备份。';

  @override
  String get workspaceConnecting => '正在连接镜像…';

  @override
  String get workspaceFfmpegInstalled => '已安装 ffmpeg。';

  @override
  String get navCourses => '课程列表';

  @override
  String get navTasks => '定时';

  @override
  String shellProfileTooltip(Object value) {
    return '$value · 个人资料';
  }

  @override
  String get shellSessionExpired => '登录已过期，自动续期没有成功。点这里重新登录。';

  @override
  String get appDaemonFailed => '后台服务无法启动';

  @override
  String get appRestart => '重新启动';

  @override
  String homeDate(Object month, Object day, Object wd) {
    return '$month月$day日 · 周$wd';
  }

  @override
  String get quizFocusAll => '，覆盖整节课的重点';

  @override
  String quizFocusOn(Object focus) {
    return '，侧重：$focus';
  }

  @override
  String get practiceAskWhyRight => '请讲讲背后的原理，帮我巩固。';

  @override
  String get practiceAskWhyWrong => '请解释为什么错，以及我可能混淆了什么。';

  @override
  String practiceSourceRef(Object ref) {
    return '出处：$ref';
  }

  @override
  String get practiceOptionSeparator => '；';

  @override
  String backupFromDevice(Object device) {
    return '自 $device';
  }

  @override
  String contextCacheHit(Object value) {
    return ' · 缓存命中 $value';
  }

  @override
  String get noteEmptyPreview => '_（空）_';

  @override
  String outlineChapterLine(Object start, Object end, Object title) {
    return '$start-$end：$title';
  }

  @override
  String get downloadsSelectJobs => '选择任务';

  @override
  String downloadsSelectedCount(Object n) {
    return '已选 $n 项';
  }

  @override
  String get downloadsExitSelection => '退出选择';

  @override
  String get downloadsSelectNone => '全不选';

  @override
  String downloadsCancelTitle(Object n) {
    return '取消 $n 个下载？';
  }

  @override
  String get downloadsCancelBody => '已下载的部分会保留，之后在课程里重新下载会从断点继续。';

  @override
  String get downloadsCancelConfirm => '取消下载';

  @override
  String get downloadsKeep => '保留下载';

  @override
  String downloadsPercent(Object value) {
    return '$value%';
  }

  @override
  String downloadsSizeProgress(Object done, Object total) {
    return '$done / $total';
  }

  @override
  String downloadsPausedSummary(Object n) {
    return '$n 个任务已暂停';
  }
}
