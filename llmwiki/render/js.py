"""Inline JavaScript for the static site viewer (v1.1 · #217).

Extracted from ``llmwiki/build.py`` in the #217 refactor. Byte-identical
to the pre-refactor constant — verified by ``llmwiki build`` hash.

Vanilla JS, no framework. Handles:
  - Theme toggle (light/dark/system) with localStorage persistence
  - Cmd+K command palette + fuzzy search against search-index.json
  - Keyboard shortcuts (/, g h/p/s, j/k, ?)
  - Copy-as-markdown + copy-code buttons
  - Reading progress bar on long pages
  - Sticky table headers on the sessions index
  - Filter bar on sessions table (project/model/date/text)
  - Mobile bottom nav
  - Hover-to-preview wikilinks
  - Deep-link anchors on headings
  - Related pages panel
"""

from __future__ import annotations

JS = r"""// llmwiki viewer — theme + copy + search palette + keyboard shortcuts + progress bar + filter bar
// Vanilla JS, no framework.

// ─── Look Tongji i18n + media enhancements ───────────────────────────────
(function () {
  const SUBTITLE_STYLE_KEY = "look-tongji-subtitle-style-v1";
  const dict = {
    "zh-Hans": {
      home: "首页",
      graph: "图谱",
      search: "搜索",
      theme: "主题",
      projects: "课程",
      sessions: "课次",
      allCourses: "全部课程",
      allLessons: "全部课次",
      course: "课程",
      from: "从",
      to: "到",
      lesson: "课次",
      clear: "清除",
      agent: "代理",
      date: "日期",
      duration: "时长",
      timeline: "时间轴",
      lectureVideo: "课程视频",
      switchLanguage: "切换界面语言",
      languageMenu: "语言选择",
      githubTitle: "GitHub",
      footerHint: "课程知识库 · 首页 · 按 ? 查看快捷键",
      keyboardShortcuts: "键盘快捷键",
      structuredQueries: "结构化查询",
      structuredQueriesHint: "可以把 key:value 筛选和自由文本一起使用：",
      searchPages: "搜索页面",
      searchPlaceholder: "搜索… 或输入：type:lesson project:look-tongji-notes date:>2026-03 sort:date",
      navigate: "上下移动",
      open: "打开",
      close: "关闭",
      overview: "概览",
      activityLast365Days: "活跃度 · 最近 365 天",
      activityProjectPrefix: "活跃度 · 最近 365 天 · ",
      lessonsPrefix: "课次（",
      lessonUnit: "节",
      courseUnit: "门课程",
      filterPlaceholder: "输入课次标题中的部分内容…",
      shownSuffix: " 条",
      tocTitle: "本页内容",
      tocAria: "页面目录",
      relatedPages: "相关页面",
      copyMarkdown: "复制 Markdown",
      backToCourse: "← 返回课程",
      downloadMd: "下载 .md",
      plainTextExport: "纯文本导出",
      jsonExport: "结构化 JSON 导出",
      toolCalls: "工具调用",
      toolCallsAggregateSuffix: "汇总",
      updatedAtPrefix: "更新于 ",
      updatedAtTitlePrefix: "最后更新于 ",
      updatedUnknown: "更新时间未知",
      updatedUnknownTitle: "没有最后更新时间",
      dayAgo: function (count) { return count + " 天前"; },
      weekAgo: function (count) { return count + " 周前"; },
      monthAgo: function (count) { return count + " 个月前"; },
      yearAgo: function (count) { return count + " 年前"; },
      today: "今天",
      yesterday: "昨天",
      coursePrefix: "课程：",
      copied: "已复制",
      failed: "失败",
      copy: "复制",
      breadcrumbs: "导航路径",
      mainNavigation: "主导航",
      mobileNavigation: "移动导航",
      commandPalette: "命令面板",
      openNavigation: "打开导航菜单",
      closeNavigation: "关闭导航菜单",
      activityTimelineAria: "课次活动时间线",
      activityTimelineSingle: function (maxCount) {
        return "活动时间线 · 1 天 · 峰值 " + maxCount + " 节课次";
      },
      activityTimelineRange: function (spanDays, activeDays, maxCount) {
        return "活动时间线 · " + spanDays + " 天 · " + activeDays +
          " 个活跃日 · 峰值 " + maxCount + " 节课次/天";
      },
      copySectionLink: "复制本节链接",
      themeLabels: {
        darkDesktop: "主题：深色，点击切到浅色",
        lightDesktop: "主题：浅色，点击切回跟随系统",
        systemDesktop: "主题：跟随系统，点击切到深色",
        darkMobile: "主题：深色，点击切到浅色",
        lightMobile: "主题：浅色，点击切回跟随系统",
        systemMobile: "主题：跟随系统，点击切到深色"
      },
      mediaEmpty: "暂无课程视频链接。",
      timelineEmpty: "暂无时间轴条目。",
      captureFrame: "视频截图",
      token: {
        sessionStats: "课次统计",
        projectTimeline: "Token 使用时间线",
        totalPrefix: "总计 ",
        totalSuffix: "",
        cacheHitRatio: "缓存命中率",
        totalWord: "总计",
        cacheHitWord: "缓存命中",
        ratioHealthy: "良好",
        ratioWarming: "升温中",
        ratioCold: "冷缓存",
        ratioUnknown: "未知",
        totalLessons: "总课次",
        totalDuration: "总时长",
        mostActiveCourse: "最活跃课程",
        totalSubtitleWords: "总字幕字数"
      },
      subtitle: {
        size: "字幕字号",
        position: "字幕位置",
        color: "字幕颜色",
        background: "字幕底色",
        shadow: "字幕阴影",
        reset: "重置字幕样式",
        resetDone: "已重置",
        defaultLabel: "默认",
        on: "开",
        off: "关",
        colors: {
          white: "白色",
          yellow: "黄色",
          cyan: "青色",
          pink: "粉色"
        },
        backgrounds: {
          none: "无底色",
          soft: "柔和底色",
          solid: "深色底板"
        }
      }
    },
    "zh-Hant": {
      home: "首頁",
      graph: "圖譜",
      search: "搜尋",
      theme: "主題",
      projects: "課程",
      sessions: "課次",
      allCourses: "全部課程",
      allLessons: "全部課次",
      course: "課程",
      from: "從",
      to: "到",
      lesson: "課次",
      clear: "清除",
      agent: "代理",
      date: "日期",
      duration: "時長",
      timeline: "時間軸",
      lectureVideo: "課程影片",
      switchLanguage: "切換介面語言",
      languageMenu: "語言選擇",
      githubTitle: "GitHub",
      footerHint: "課程知識庫 · 首頁 · 按 ? 查看快捷鍵",
      keyboardShortcuts: "鍵盤快捷鍵",
      structuredQueries: "結構化查詢",
      structuredQueriesHint: "可以把 key:value 篩選和自由文字一起使用：",
      searchPages: "搜尋頁面",
      searchPlaceholder: "搜尋… 或輸入：type:lesson project:look-tongji-notes date:>2026-03 sort:date",
      navigate: "上下移動",
      open: "打開",
      close: "關閉",
      overview: "概覽",
      activityLast365Days: "活躍度 · 最近 365 天",
      activityProjectPrefix: "活躍度 · 最近 365 天 · ",
      lessonsPrefix: "課次（",
      lessonUnit: "節",
      courseUnit: "門課程",
      filterPlaceholder: "輸入課次標題中的部分內容…",
      shownSuffix: " 條",
      tocTitle: "本頁內容",
      tocAria: "頁面目錄",
      relatedPages: "相關頁面",
      copyMarkdown: "複製 Markdown",
      backToCourse: "← 返回課程",
      downloadMd: "下載 .md",
      plainTextExport: "純文字匯出",
      jsonExport: "結構化 JSON 匯出",
      toolCalls: "工具呼叫",
      toolCallsAggregateSuffix: "彙總",
      updatedAtPrefix: "更新於 ",
      updatedAtTitlePrefix: "最後更新於 ",
      updatedUnknown: "更新時間未知",
      updatedUnknownTitle: "沒有最後更新時間",
      dayAgo: function (count) { return count + " 天前"; },
      weekAgo: function (count) { return count + " 週前"; },
      monthAgo: function (count) { return count + " 個月前"; },
      yearAgo: function (count) { return count + " 年前"; },
      today: "今天",
      yesterday: "昨天",
      coursePrefix: "課程：",
      copied: "已複製",
      failed: "失敗",
      copy: "複製",
      breadcrumbs: "導覽路徑",
      mainNavigation: "主導覽",
      mobileNavigation: "行動導覽",
      commandPalette: "命令面板",
      openNavigation: "打開導覽選單",
      closeNavigation: "關閉導覽選單",
      activityTimelineAria: "課次活動時間線",
      activityTimelineSingle: function (maxCount) {
        return "活動時間線 · 1 天 · 峰值 " + maxCount + " 節課次";
      },
      activityTimelineRange: function (spanDays, activeDays, maxCount) {
        return "活動時間線 · " + spanDays + " 天 · " + activeDays +
          " 個活躍日 · 峰值 " + maxCount + " 節課次/天";
      },
      copySectionLink: "複製本節連結",
      themeLabels: {
        darkDesktop: "主題：深色，點擊切到淺色",
        lightDesktop: "主題：淺色，點擊切回跟隨系統",
        systemDesktop: "主題：跟隨系統，點擊切到深色",
        darkMobile: "主題：深色，點擊切到淺色",
        lightMobile: "主題：淺色，點擊切回跟隨系統",
        systemMobile: "主題：跟隨系統，點擊切到深色"
      },
      mediaEmpty: "暫無課程影片連結。",
      timelineEmpty: "暫無時間軸條目。",
      captureFrame: "影片截圖",
      token: {
        sessionStats: "課次統計",
        projectTimeline: "Token 使用時間線",
        totalPrefix: "總計 ",
        totalSuffix: "",
        cacheHitRatio: "快取命中率",
        totalWord: "總計",
        cacheHitWord: "快取命中",
        ratioHealthy: "良好",
        ratioWarming: "升溫中",
        ratioCold: "冷快取",
        ratioUnknown: "未知",
        totalLessons: "總課次",
        totalDuration: "總時長",
        mostActiveCourse: "最活躍課程",
        totalSubtitleWords: "總字幕字數"
      },
      subtitle: {
        size: "字幕字號",
        position: "字幕位置",
        color: "字幕顏色",
        background: "字幕底色",
        shadow: "字幕陰影",
        reset: "重置字幕樣式",
        resetDone: "已重置",
        defaultLabel: "預設",
        on: "開",
        off: "關",
        colors: {
          white: "白色",
          yellow: "黃色",
          cyan: "青色",
          pink: "粉色"
        },
        backgrounds: {
          none: "無底色",
          soft: "柔和底色",
          solid: "深色底板"
        }
      }
    },
    en: {
      home: "Home",
      graph: "Graph",
      search: "Search",
      theme: "Theme",
      projects: "Courses",
      sessions: "Lessons",
      allCourses: "All courses",
      allLessons: "All lessons",
      course: "Course",
      from: "From",
      to: "To",
      lesson: "Lesson",
      clear: "Clear",
      agent: "Agent",
      date: "Date",
      duration: "Duration",
      timeline: "Timeline",
      lectureVideo: "Lecture Video",
      switchLanguage: "Switch interface language",
      languageMenu: "Language menu",
      githubTitle: "GitHub",
      footerHint: "Course knowledge base · home · press ? for shortcuts",
      keyboardShortcuts: "Keyboard shortcuts",
      structuredQueries: "Structured queries",
      structuredQueriesHint: "Mix key:value filters with free text in the palette:",
      searchPages: "Search pages",
      searchPlaceholder: "Search… or type:type:lesson project:look-tongji-notes date:>2026-03 sort:date",
      navigate: "navigate",
      open: "open",
      close: "close",
      overview: "Overview",
      activityLast365Days: "Activity · last 365 days",
      activityProjectPrefix: "Activity · last 365 days · ",
      lessonsPrefix: "Lessons (",
      lessonUnit: "lessons",
      courseUnit: "courses",
      filterPlaceholder: "part of lesson title…",
      shownSuffix: " shown",
      tocTitle: "On this page",
      tocAria: "Table of contents",
      relatedPages: "Related pages",
      copyMarkdown: "Copy as markdown",
      backToCourse: "← Back to course",
      downloadMd: "Download .md",
      plainTextExport: "Plain text export",
      jsonExport: "Structured JSON export",
      toolCalls: "Tool calls",
      toolCallsAggregateSuffix: "aggregate",
      updatedAtPrefix: "Updated ",
      updatedAtTitlePrefix: "Last updated ",
      updatedUnknown: "Update time unknown",
      updatedUnknownTitle: "No last updated time",
      dayAgo: function (count) { return count + " day" + (count === 1 ? "" : "s") + " ago"; },
      weekAgo: function (count) { return count + " week" + (count === 1 ? "" : "s") + " ago"; },
      monthAgo: function (count) { return count + " month" + (count === 1 ? "" : "s") + " ago"; },
      yearAgo: function (count) { return count + " year" + (count === 1 ? "" : "s") + " ago"; },
      today: "today",
      yesterday: "yesterday",
      coursePrefix: "Course: ",
      copied: "Copied!",
      failed: "Failed",
      copy: "Copy",
      breadcrumbs: "Breadcrumbs",
      mainNavigation: "Main navigation",
      mobileNavigation: "Mobile navigation",
      commandPalette: "Command palette",
      openNavigation: "Open navigation menu",
      closeNavigation: "Close navigation menu",
      activityTimelineAria: "Lesson activity timeline",
      activityTimelineSingle: function (maxCount) {
        return "Activity timeline · 1 day · peak " + maxCount + (maxCount === 1 ? " lesson" : " lessons");
      },
      activityTimelineRange: function (spanDays, activeDays, maxCount) {
        return "Activity timeline · " + spanDays + " days · " + activeDays +
          " active · peak " + maxCount + (maxCount === 1 ? " lesson/day" : " lessons/day");
      },
      copySectionLink: "Copy link to this section",
      themeLabels: {
        darkDesktop: "Theme: dark — click for light",
        lightDesktop: "Theme: light — click for system default",
        systemDesktop: "Theme: follows system — click for dark",
        darkMobile: "Theme: dark — tap for light",
        lightMobile: "Theme: light — tap for system default",
        systemMobile: "Theme: follows system — tap for dark"
      },
      mediaEmpty: "No lecture video URL yet.",
      timelineEmpty: "No timeline entries yet.",
      captureFrame: "Capture frame",
      token: {
        sessionStats: "Lesson stats",
        projectTimeline: "Token usage · timeline",
        totalPrefix: "",
        totalSuffix: " total",
        cacheHitRatio: "Cache hit ratio",
        totalWord: "total",
        cacheHitWord: "cache hit",
        ratioHealthy: "healthy",
        ratioWarming: "warming up",
        ratioCold: "cold cache",
        ratioUnknown: "n/a",
        totalLessons: "Total lessons",
        totalDuration: "Total duration",
        mostActiveCourse: "Most active course",
        totalSubtitleWords: "Subtitle words"
      },
      subtitle: {
        size: "Subtitle size",
        position: "Subtitle position",
        color: "Subtitle color",
        background: "Subtitle background",
        shadow: "Subtitle shadow",
        reset: "Reset subtitle style",
        resetDone: "Reset",
        defaultLabel: "Default",
        on: "On",
        off: "Off",
        colors: {
          white: "White",
          yellow: "Yellow",
          cyan: "Cyan",
          pink: "Pink"
        },
        backgrounds: {
          none: "None",
          soft: "Soft",
          solid: "Solid"
        }
      }
    }
  };
  function normalizeLang(lang) {
    if (!lang) return "zh-Hans";
    if (lang === "zh") return "zh-Hans";
    if (lang === "zh-CN" || lang === "zh-SG" || lang === "zh-Hans") return "zh-Hans";
    if (lang === "zh-TW" || lang === "zh-HK" || lang === "zh-MO" || lang === "zh-Hant") return "zh-Hant";
    if (lang === "en" || lang.indexOf("en-") === 0) return "en";
    return dict[lang] ? lang : "zh-Hans";
  }
  function currentText() {
    return dict[getLang()] || dict.en;
  }
  function shouldUseLocalVideoProxy() {
    return window.location.protocol === "http:" && (
      window.location.hostname === "127.0.0.1" ||
      window.location.hostname === "localhost"
    );
  }
  function resolveVideoSrc(url) {
    if (!url || !shouldUseLocalVideoProxy()) return url;
    if (!/^https?:\/\//i.test(url)) return url;
    return "/__llmwiki_video_proxy__?url=" + encodeURIComponent(url);
  }
  function translateRelativeAge(raw, text) {
    if (!raw) return raw;
    if (raw === "today" || raw === "今天") return text.today;
    if (raw === "yesterday" || raw === "昨天") return text.yesterday;
    var match = raw.match(/^(\d+)\s+days?\s+ago$/i);
    if (match) return text.dayAgo(Number(match[1]));
    match = raw.match(/^(\d+)\s+weeks?\s+ago$/i);
    if (match) return text.weekAgo(Number(match[1]));
    match = raw.match(/^(\d+)\s+months?\s+ago$/i);
    if (match) return text.monthAgo(Number(match[1]));
    match = raw.match(/^(\d+)\s+years?\s+ago$/i);
    if (match) return text.yearAgo(Number(match[1]));
    return raw;
  }
  function getLang() {
    try {
      return normalizeLang(localStorage.getItem("look-tongji-lang") || document.documentElement.lang || "zh-Hans");
    } catch (e) {
      return "zh-Hans";
    }
  }
  function setLang(lang) {
    const next = normalizeLang(lang);
    try { localStorage.setItem("look-tongji-lang", next); } catch (e) {}
    return next;
  }
  function loadSubtitlePrefs() {
    const defaults = {
      fontSize: 18,
      bottom: 8,
      color: "#ffffff",
      background: "soft",
      shadow: true
    };
    try {
      const raw = localStorage.getItem(SUBTITLE_STYLE_KEY);
      if (!raw) return defaults;
      const parsed = JSON.parse(raw);
      return Object.assign({}, defaults, parsed || {});
    } catch (e) {
      return defaults;
    }
  }
  function saveSubtitlePrefs(prefs) {
    try { localStorage.setItem(SUBTITLE_STYLE_KEY, JSON.stringify(prefs)); } catch (e) {}
  }
  function subtitleBackgroundValue(mode) {
    if (mode === "none") return "transparent";
    if (mode === "solid") return "rgba(0,0,0,0.72)";
    return "rgba(0,0,0,0.45)";
  }
  function subtitleBackgroundLabel(mode) {
    const backgrounds = currentText().subtitle.backgrounds;
    if (mode === "none") return backgrounds.none;
    if (mode === "solid") return backgrounds.solid;
    return backgrounds.soft;
  }
  function buildSubtitleStyle(prefs) {
    const background = subtitleBackgroundValue(prefs.background);
    const hasBackground = background !== "transparent";
    return {
      color: prefs.color || "#ffffff",
      fontSize: String(Math.max(14, Math.min(32, Number(prefs.fontSize) || 18))) + "px",
      bottom: String(Math.max(0, Math.min(20, Number(prefs.bottom) || 8))) + "%",
      fontWeight: "600",
      textShadow: prefs.shadow ? "0 2px 6px rgba(0,0,0,0.85)" : "none",
      background: background,
      padding: hasBackground ? "4px 10px" : "0",
      borderRadius: hasBackground ? "6px" : "0"
    };
  }
  function applySubtitleStyle(art, prefs) {
    if (!art || !art.subtitle || !art.subtitle.style) return;
    art.subtitle.style(buildSubtitleStyle(prefs));
  }
  function createSubtitleSettings(getArt, prefs) {
    const subtitleText = currentText().subtitle;
    const colorOptions = [
      { html: subtitleText.colors.white, value: "#ffffff" },
      { html: subtitleText.colors.yellow, value: "#ffe066" },
      { html: subtitleText.colors.cyan, value: "#7ee7ff" },
      { html: subtitleText.colors.pink, value: "#ffb4d9" }
    ];
    const backgroundOptions = [
      { html: subtitleText.backgrounds.none, value: "none" },
      { html: subtitleText.backgrounds.soft, value: "soft" },
      { html: subtitleText.backgrounds.solid, value: "solid" }
    ];
    return [
      {
        name: "look-tongji-subtitle-size",
        html: subtitleText.size,
        tooltip: String(prefs.fontSize) + "px",
        range: [prefs.fontSize, 14, 32, 1],
        onRange(item) {
          prefs.fontSize = Number(item.range[0]) || 18;
          saveSubtitlePrefs(prefs);
          applySubtitleStyle(getArt(), prefs);
          item.tooltip = String(prefs.fontSize) + "px";
          return item.tooltip;
        }
      },
      {
        name: "look-tongji-subtitle-bottom",
        html: subtitleText.position,
        tooltip: String(prefs.bottom) + "%",
        range: [prefs.bottom, 0, 20, 1],
        onRange(item) {
          prefs.bottom = Number(item.range[0]) || 8;
          saveSubtitlePrefs(prefs);
          applySubtitleStyle(getArt(), prefs);
          item.tooltip = String(prefs.bottom) + "%";
          return item.tooltip;
        }
      },
      {
        name: "look-tongji-subtitle-color",
        html: subtitleText.color,
        tooltip: colorOptions.find(function (opt) { return opt.value === prefs.color; })?.html || subtitleText.colors.white,
        selector: colorOptions.map(function (opt) {
          return {
            default: opt.value === prefs.color,
            html: opt.html,
            value: opt.value
          };
        }),
        onSelect(item) {
          prefs.color = item.value;
          saveSubtitlePrefs(prefs);
          applySubtitleStyle(getArt(), prefs);
          return item.html;
        }
      },
      {
        name: "look-tongji-subtitle-background",
        html: subtitleText.background,
        tooltip: subtitleBackgroundLabel(prefs.background),
        selector: backgroundOptions.map(function (opt) {
          return {
            default: opt.value === prefs.background,
            html: opt.html,
            value: opt.value
          };
        }),
        onSelect(item) {
          prefs.background = item.value;
          saveSubtitlePrefs(prefs);
          applySubtitleStyle(getArt(), prefs);
          return item.html;
        }
      },
      {
        name: "look-tongji-subtitle-shadow",
        html: subtitleText.shadow,
        tooltip: prefs.shadow ? subtitleText.on : subtitleText.off,
        switch: !!prefs.shadow,
        onSwitch(item) {
          const next = !item.switch;
          prefs.shadow = next;
          saveSubtitlePrefs(prefs);
          applySubtitleStyle(getArt(), prefs);
          item.tooltip = next ? subtitleText.on : subtitleText.off;
          return next;
        }
      },
      {
        name: "look-tongji-subtitle-reset",
        html: subtitleText.reset,
        tooltip: subtitleText.defaultLabel,
        onClick() {
          const defaults = loadSubtitlePrefs();
          prefs.fontSize = defaults.fontSize;
          prefs.bottom = defaults.bottom;
          prefs.color = defaults.color;
          prefs.background = defaults.background;
          prefs.shadow = defaults.shadow;
          saveSubtitlePrefs(prefs);
          applySubtitleStyle(getArt(), prefs);
          const art = getArt();
          if (art && art.setting && art.setting.update) {
            art.setting.update({ name: "look-tongji-subtitle-size", range: [prefs.fontSize, 14, 32, 1], tooltip: String(prefs.fontSize) + "px" });
            art.setting.update({ name: "look-tongji-subtitle-bottom", range: [prefs.bottom, 0, 20, 1], tooltip: String(prefs.bottom) + "%" });
            art.setting.update({ name: "look-tongji-subtitle-color", tooltip: colorOptions.find(function (opt) { return opt.value === prefs.color; })?.html || subtitleText.colors.white });
            art.setting.update({ name: "look-tongji-subtitle-background", tooltip: subtitleBackgroundLabel(prefs.background) });
            art.setting.update({ name: "look-tongji-subtitle-shadow", tooltip: prefs.shadow ? subtitleText.on : subtitleText.off, switch: !!prefs.shadow });
          }
          return subtitleText.resetDone;
        }
      }
    ];
  }
  window.__lookTongjiI18n = {
    getLang: getLang,
    setLang: setLang,
    currentText: currentText
  };
  function applyLang(lang) {
    const text = dict[lang] || dict.en;
    const normalized = normalizeLang(lang);
    document.documentElement.lang = normalized === "zh-Hans" ? "zh-CN" : normalized === "zh-Hant" ? "zh-Hant" : "en";
    document.documentElement.setAttribute("data-ui-lang", normalized);
    const btn = document.getElementById("lang-toggle");
    if (btn) btn.setAttribute("aria-label", text.switchLanguage);
    const menu = document.getElementById("lang-menu");
    if (menu) menu.setAttribute("aria-label", text.languageMenu);
    document.querySelectorAll(".lang-menu-item").forEach(function (item) {
      const active = item.getAttribute("data-lang") === normalized;
      item.classList.toggle("active", active);
      item.setAttribute("aria-checked", active ? "true" : "false");
      item.tabIndex = active ? 0 : -1;
    });
    const drawer = document.getElementById("nav-drawer");
    if (drawer) drawer.setAttribute("aria-label", text.mainNavigation);
    const mobileNav = document.querySelector(".mobile-bottom-nav");
    if (mobileNav) mobileNav.setAttribute("aria-label", text.mobileNavigation);
    const breadcrumbs = document.querySelector(".breadcrumbs");
    if (breadcrumbs) breadcrumbs.setAttribute("aria-label", text.breadcrumbs);
    document.querySelectorAll(".breadcrumbs a, .breadcrumbs span[aria-current='page']").forEach(function (node) {
      const raw = (node.textContent || "").trim();
      if (raw === "首页" || raw === "首頁" || raw === "Home") node.textContent = text.home;
      if (raw === "课程" || raw === "課程" || raw === "Courses") node.textContent = text.projects;
      if (raw === "课次" || raw === "課次" || raw === "Lessons") node.textContent = text.sessions;
      if (raw === "图谱" || raw === "圖譜" || raw === "Graph") node.textContent = text.graph;
    });
    const palette = document.querySelector(".palette-modal");
    if (palette) palette.setAttribute("aria-label", text.commandPalette);
    document.querySelectorAll(".nav-links a, .nav-drawer-link, .mobile-bottom-nav .mbn-link span").forEach(function (node) {
      const raw = (node.textContent || "").trim();
      if (raw === "首页" || raw === "Home") node.textContent = text.home;
      if (raw === "首頁") node.textContent = text.home;
      if (raw === "图谱" || raw === "Graph") node.textContent = text.graph;
      if (raw === "圖譜") node.textContent = text.graph;
      if (raw === "搜索" || raw === "Search") node.textContent = text.search;
      if (raw === "搜尋") node.textContent = text.search;
      if (raw === "主题" || raw === "Theme") node.textContent = text.theme;
      if (raw === "主題") node.textContent = text.theme;
      if (raw === "课程" || raw === "Courses" || raw === "Projects") node.textContent = text.projects;
      if (raw === "課程") node.textContent = text.projects;
      if (raw === "节次" || raw === "课次" || raw === "Sessions" || raw === "Lessons") node.textContent = text.sessions;
      if (raw === "課次") node.textContent = text.sessions;
    });
    document.querySelectorAll(".footer .muted").forEach(function (node) {
      node.textContent = text.footerHint;
    });
    const paletteInput = document.getElementById("palette-input");
    if (paletteInput) {
      paletteInput.setAttribute("aria-label", text.searchPages);
      paletteInput.setAttribute("placeholder", text.searchPlaceholder);
    }
    const paletteBtn = document.getElementById("open-palette");
    if (paletteBtn) {
      paletteBtn.setAttribute("aria-label", text.searchPages);
      const label = paletteBtn.querySelector("span");
      if (label) label.textContent = text.search;
    }
    const navHamburger = document.getElementById("nav-hamburger");
    if (navHamburger) {
      navHamburger.setAttribute(
        "aria-label",
        navHamburger.getAttribute("aria-expanded") === "true" ? text.closeNavigation : text.openNavigation,
      );
    }
    const mbnSearch = document.getElementById("mbn-search");
    if (mbnSearch) mbnSearch.setAttribute("aria-label", text.search);
    const mbnTheme = document.getElementById("mbn-theme");
    if (mbnTheme) mbnTheme.querySelector("span").textContent = text.theme;
    document.querySelectorAll(".palette-footer span").forEach(function (node) {
      const raw = (node.textContent || "").trim();
      if (raw.indexOf("↑↓") === 0) node.innerHTML = "<kbd>↑↓</kbd> " + text.navigate;
      if (raw.indexOf("↵") === 0) node.innerHTML = "<kbd>↵</kbd> " + text.open;
      if (raw.indexOf("ESC") === 0) node.innerHTML = "<kbd>ESC</kbd> " + text.close;
    });
    const github = document.querySelector(".github-link");
    if (github) {
      github.setAttribute("aria-label", text.githubTitle);
      github.setAttribute("title", text.githubTitle);
    }
    document.querySelectorAll(".help-modal h2").forEach(function (node) {
      node.textContent = text.keyboardShortcuts;
    });
    document.querySelectorAll(".help-modal h3").forEach(function (node) {
      node.textContent = text.structuredQueries;
    });
    document.querySelectorAll(".help-dialog-hint").forEach(function (node) {
      node.textContent = text.structuredQueriesHint;
    });
    document.querySelectorAll(".synthesis h2").forEach(function (node) {
      node.textContent = text.overview;
    });
    document.querySelectorAll(".toc-sidebar").forEach(function (node) {
      node.setAttribute("aria-label", text.tocAria);
    });
    document.querySelectorAll(".toc-title").forEach(function (node) {
      node.textContent = text.tocTitle;
    });
    document.querySelectorAll(".related-pages h3").forEach(function (node) {
      node.textContent = text.relatedPages;
    });
    document.querySelectorAll(".heatmap-label").forEach(function (node) {
      const raw = (node.textContent || "").trim();
      if (raw === "活跃度 · 最近 365 天" || raw === "活躍度 · 最近 365 天" || raw === "Activity · last 365 days") {
        node.textContent = text.activityLast365Days;
      } else if (raw.indexOf("活跃度 · 最近 365 天 · ") === 0 || raw.indexOf("活躍度 · 最近 365 天 · ") === 0 || raw.indexOf("Activity · last 365 days · ") === 0) {
        const parts = raw.split(" · ");
        const name = parts[parts.length - 1] || "";
        node.textContent = text.activityProjectPrefix + name;
      }
    });
    document.querySelectorAll(".section h2").forEach(function (node) {
      const raw = (node.textContent || "").trim();
      if (raw === "课程" || raw === "課程" || raw === "Courses" || raw === "Projects") node.textContent = text.projects;
      if ((raw.indexOf("Lessons (") === 0 || raw.indexOf("课次（") === 0 || raw.indexOf("課次（") === 0) && /[\d]+/.test(raw)) {
        const count = raw.replace(/[^\d]/g, "");
        node.textContent = text.lessonsPrefix + count + (normalized === "en" ? ")" : "）");
      }
    });
    document.querySelectorAll(".hero h1").forEach(function (node) {
      const raw = (node.textContent || "").trim();
      if (raw === "全部课程" || raw === "全部課程" || raw === "All courses") node.textContent = text.allCourses;
      if (raw === "全部课次" || raw === "全部課次" || raw === "All lessons") node.textContent = text.allLessons;
      if (raw === "课程" || raw === "課程" || raw === "Courses" || raw === "Projects") node.textContent = text.projects;
      if (raw === "课次" || raw === "課次" || raw === "Lessons" || raw === "Sessions") node.textContent = text.sessions;
    });
    document.querySelectorAll(".hero:not(.hero-home) .hero-sub").forEach(function (node) {
      const counts = Array.from((node.textContent || "").matchAll(/\d+/g)).map(function (match) { return match[0]; });
      if (counts.length === 1) {
        const title = (node.previousElementSibling && node.previousElementSibling.textContent || "").trim();
        const isCourseIndexHero = title === text.allCourses || title === text.projects || title === "全部课程" || title === "全部課程" || title === "All courses" || title === "课程" || title === "課程" || title === "Courses";
        node.textContent = counts[0] + " " + (isCourseIndexHero ? text.courseUnit : text.lessonUnit);
      }
    });
    document.querySelectorAll(".hero-home .hero-sub").forEach(function (node) {
      const counts = Array.from((node.textContent || "").matchAll(/\d+/g)).map(function (match) { return match[0]; });
      if (counts.length >= 2) {
        if (normalized === "en") node.textContent = counts[0] + " " + text.lessonUnit + " · " + counts[1] + " " + text.courseUnit;
        else node.textContent = counts[0] + " " + text.lessonUnit + " · " + counts[1] + " " + text.courseUnit;
      }
    });
    document.querySelectorAll(".project-description").forEach(function (node) {
      var content = (node.textContent || "").replace(/^(课程：|課程：|Course:\s*)/, "");
      node.textContent = text.coursePrefix + content;
    });
    document.querySelectorAll(".hero-sub a[href*=\"/projects/\"]").forEach(function (node) {
      const href = node.getAttribute("href") || "";
      const slugMatch = href.match(/\/projects\/([^\/?#]+)\.html$/) || href.match(/projects\/([^\/?#]+)\.html$/);
      const slug = slugMatch ? slugMatch[1] : "";
      const card = slug ? document.querySelector(".card[href*=\"/" + slug + ".html\"], .card[href$=\"" + slug + ".html\"] .card-title") : null;
      if (slug && !/^\d+$/.test(node.textContent || "")) return;
      if (slug) {
        const titleNode = document.querySelector(".card[href$=\"" + slug + ".html\"] .card-title");
        if (titleNode) node.textContent = (titleNode.textContent || "").trim();
      }
    });
    document.querySelectorAll(".card-meta[data-lesson-count]").forEach(function (node) {
      const count = node.getAttribute("data-lesson-count");
      if (!count) return;
      if (normalized === "en") node.textContent = count + " " + text.lessonUnit;
      else node.textContent = count + " " + text.lessonUnit;
    });
    document.querySelectorAll(".freshness").forEach(function (node) {
      const title = node.getAttribute("title") || "";
      if (title === "没有最后更新时间" || title === "沒有最後更新時間" || title === "No last updated time") {
        node.setAttribute("title", text.updatedUnknownTitle);
        node.textContent = text.updatedUnknown;
        return;
      }
      const isoMatch = title.match(/(\d{4}-\d{2}-\d{2})/);
      if (isoMatch) node.setAttribute("title", text.updatedAtTitlePrefix + isoMatch[1]);
      const raw = (node.textContent || "").replace(/^(更新于 |更新於 |Updated )/, "").trim();
      node.textContent = text.updatedAtPrefix + translateRelativeAge(raw, text);
    });
    document.querySelectorAll(".tool-chart-label").forEach(function (node) {
      const raw = (node.textContent || "").trim();
      if (raw === "Tool calls" || raw === "工具调用" || raw === "工具呼叫") {
        node.textContent = text.toolCalls;
        return;
      }
      if (/^(Tool calls|工具调用|工具呼叫)\s·\s/.test(raw)) {
        const parts = raw.split(" · ");
        const tail = parts.slice(1).join(" · ");
        if (!tail) {
          node.textContent = text.toolCalls;
        } else if (/(aggregate|汇总|彙總)$/.test(tail)) {
          const courseName = tail.replace(/\s*(aggregate|汇总|彙總)\s*$/, "").trim();
          node.textContent = text.toolCalls + " · " + courseName + " " + text.toolCallsAggregateSuffix;
        } else {
          node.textContent = text.toolCalls + " · " + tail;
        }
      }
    });
    document.querySelectorAll(".filter-bar label").forEach(function (label) {
      const textNode = Array.from(label.childNodes).find(function (child) { return child.nodeType === Node.TEXT_NODE; });
      if (!textNode) return;
      const raw = (textNode.textContent || "").trim();
      if (raw === "Course" || raw === "课程" || raw === "課程") textNode.textContent = text.course + "\n        ";
      if (raw === "From" || raw === "从") textNode.textContent = text.from + "\n        ";
      if (raw === "從") textNode.textContent = text.from + "\n        ";
      if (raw === "To" || raw === "到") textNode.textContent = text.to + "\n        ";
      if (raw === "Lesson" || raw === "课次" || raw === "課次") textNode.textContent = text.lesson + "\n        ";
    });
    const filterProject = document.querySelector("#filter-project option[value='']");
    if (filterProject) filterProject.textContent = text.allCourses;
    const filterText = document.getElementById("filter-text");
    if (filterText) filterText.setAttribute("placeholder", text.filterPlaceholder);
    const filterClear = document.getElementById("filter-clear");
    if (filterClear) filterClear.textContent = text.clear;
    const filterCount = document.getElementById("filter-count");
    if (filterCount) {
      const count = (filterCount.textContent || "").match(/\d+/);
      if (count) filterCount.textContent = count[0] + text.shownSuffix;
    }
    document.querySelectorAll(".sessions-table thead th").forEach(function (th) {
      const raw = (th.textContent || "").trim();
      if (raw === "Lesson" || raw === "课次" || raw === "課次") th.textContent = text.lesson;
      if (raw === "Agent" || raw === "执行 Agent") th.textContent = text.agent;
      if (raw === "Course" || raw === "课程" || raw === "課程") th.textContent = text.course;
      if (raw === "Date" || raw === "日期") th.textContent = text.date;
      if (raw === "Duration" || raw === "时长" || raw === "時長") th.textContent = text.duration;
    });
    document.querySelectorAll(".tongji-media-details > summary").forEach(function (node) {
      const label = node.querySelector(".tongji-summary-label");
      if (label) label.textContent = text.lectureVideo;
      else node.textContent = text.lectureVideo;
    });
    document.querySelectorAll(".tongji-timeline-panel h2").forEach(function (node) {
      node.textContent = text.timeline;
    });
    document.querySelectorAll(".tongji-player-empty .muted").forEach(function (node) {
      node.textContent = text.mediaEmpty;
    });
    document.querySelectorAll(".tongji-timeline-list .muted").forEach(function (node) {
      node.textContent = text.timelineEmpty;
    });
    document.querySelectorAll(".session-actions .btn.btn-primary").forEach(function (node) {
      node.textContent = text.copyMarkdown;
      node.setAttribute("title", text.copyMarkdown);
      node.setAttribute("aria-label", text.copyMarkdown);
    });
    document.querySelectorAll(".session-actions a.btn").forEach(function (node) {
      const href = node.getAttribute("href") || "";
      if (href.endsWith(".txt")) {
        node.setAttribute("title", text.plainTextExport);
        node.setAttribute("aria-label", text.plainTextExport);
      }
      if (href.endsWith(".json")) {
        node.setAttribute("title", text.jsonExport);
        node.setAttribute("aria-label", text.jsonExport);
      }
      if (/projects\/.+\.html$/.test(href)) {
        node.textContent = text.backToCourse;
        node.setAttribute("aria-label", text.backToCourse);
      }
      if (href.endsWith(".md")) {
        node.textContent = text.downloadMd;
        node.setAttribute("aria-label", text.downloadMd);
      }
    });
    document.querySelectorAll(".copy-code-btn").forEach(function (node) {
      if (!node.classList.contains("copied")) node.textContent = text.copy;
      node.setAttribute("aria-label", text.copy);
      node.setAttribute("title", text.copy);
    });
    document.querySelectorAll(".token-ratio-label").forEach(function (node) {
      node.textContent = text.token.cacheHitRatio;
    });
    document.querySelectorAll(".token-ratio-tier").forEach(function (node) {
      const raw = (node.textContent || "").trim();
      if (/healthy|良好/i.test(raw)) node.textContent = "· " + text.token.ratioHealthy;
      else if (/warming|升温中|升溫中/i.test(raw)) node.textContent = "· " + text.token.ratioWarming;
      else if (/cold|冷缓存|冷快取/i.test(raw)) node.textContent = "· " + text.token.ratioCold;
      else node.textContent = "· " + text.token.ratioUnknown;
    });
    document.querySelectorAll(".token-card-title").forEach(function (node) {
      const raw = (node.textContent || "").trim();
      if (raw === "课次统计" || raw === "課次統計" || raw === "Lesson stats") node.textContent = text.token.sessionStats;
      if (raw === "Token usage · timeline") node.textContent = text.token.projectTimeline;
    });
    document.querySelectorAll(".token-card-total").forEach(function (node) {
      const stat = node.getAttribute("data-token-total");
      const ratio = node.getAttribute("data-token-ratio");
      const tier = node.getAttribute("data-token-ratio-tier");
      if (stat) {
        node.textContent = text.token.totalPrefix + stat + text.token.totalSuffix;
      } else if (ratio) {
        const ratioLabel = tier === "healthy" ? text.token.ratioHealthy : tier === "warming" ? text.token.ratioWarming : tier === "cold" ? text.token.ratioCold : text.token.ratioUnknown;
        const ratioValue = node.querySelector(".token-ratio-value");
        const ratioHtml = ratioValue ? ratioValue.outerHTML : ratio;
        if (normalized === "en") {
          node.innerHTML = ratio + " " + text.token.totalWord + " · " + ratioHtml + " " + text.token.cacheHitWord + " · " + ratioLabel;
        } else {
          node.innerHTML = text.token.totalWord + " " + ratio + " · " + ratioHtml + " " + text.token.cacheHitWord + " · " + ratioLabel;
        }
      }
    });
    document.querySelectorAll(".token-stat-label").forEach(function (node) {
      const raw = (node.textContent || "").trim();
      if (raw === "总课次" || raw === "總課次" || raw === "Total lessons") node.textContent = text.token.totalLessons;
      if (raw === "总时长" || raw === "總時長" || raw === "Total duration") node.textContent = text.token.totalDuration;
      if (raw === "最活跃课程" || raw === "最活躍課程" || raw === "Most active course") node.textContent = text.token.mostActiveCourse;
      if (raw === "总字幕字数" || raw === "總字幕字數" || raw === "Subtitle words") node.textContent = text.token.totalSubtitleWords;
    });
    document.querySelectorAll(".heatmap-svg").forEach(function (svg) {
      const start = svg.getAttribute("data-heatmap-start");
      const end = svg.getAttribute("data-heatmap-end");
      const kind = svg.getAttribute("data-heatmap-kind");
      const projectName = svg.getAttribute("data-heatmap-project-name") || "";
      if (start && end) {
        if (kind === "project" && projectName) {
          svg.setAttribute("aria-label", text.activityProjectPrefix + projectName + "，" + start + " to " + end);
        } else {
          svg.setAttribute("aria-label", text.activityLast365Days + "，" + start + " to " + end);
        }
      }
      svg.querySelectorAll("text[data-month]").forEach(function (label) {
        const month = Number(label.getAttribute("data-month") || "0");
        if (!month) return;
        if (normalized === "en") label.textContent = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][month - 1];
        else if (normalized === "zh-Hant") label.textContent = month + "月";
        else label.textContent = month + "月";
      });
      svg.querySelectorAll("text[data-weekday]").forEach(function (label) {
        const day = Number(label.getAttribute("data-weekday") || "0");
        if (normalized === "en") {
          label.textContent = day === 1 ? "Mon" : day === 3 ? "Wed" : day === 5 ? "Fri" : "";
        } else if (normalized === "zh-Hant") {
          label.textContent = day === 1 ? "週一" : day === 3 ? "週三" : day === 5 ? "週五" : "";
        } else {
          label.textContent = day === 1 ? "周一" : day === 3 ? "周三" : day === 5 ? "周五" : "";
        }
      });
      svg.querySelectorAll("rect[data-date][data-count]").forEach(function (rect) {
        const date = rect.getAttribute("data-date");
        const count = rect.getAttribute("data-count");
        const title = rect.querySelector("title");
        if (!title) return;
        if (normalized === "en") title.textContent = "Activity " + date + " — " + count + " lessons";
        else if (normalized === "zh-Hant") title.textContent = "活躍度 " + date + " — " + count + " 節課次";
        else title.textContent = "活跃度 " + date + " — " + count + " 节课次";
      });
    });
    document.querySelectorAll(".timeline-block").forEach(function (block) {
      const svg = block.querySelector("svg");
      const label = block.querySelector(".timeline-label");
      if (!svg || !label) return;
      const rects = Array.from(svg.querySelectorAll("rect[data-date][data-count]"));
      const dates = rects.map(function (rect) { return rect.getAttribute("data-date") || ""; }).filter(Boolean).sort();
      const counts = rects.map(function (rect) { return Number(rect.getAttribute("data-count") || "0"); });
      const maxCount = counts.length ? Math.max.apply(Math, counts) : 0;
      if (!dates.length) return;
      const first = new Date(dates[0] + "T00:00:00Z");
      const last = new Date(dates[dates.length - 1] + "T00:00:00Z");
      const spanDays = Math.round((last - first) / 86400000) + 1;
      label.textContent = spanDays === 1 ? text.activityTimelineSingle(maxCount) : text.activityTimelineRange(spanDays, dates.length, maxCount);
      svg.setAttribute("aria-label", text.activityTimelineAria);
    });
    window.dispatchEvent(new CustomEvent("look-tongji:langchange", { detail: { lang: normalized, text: text } }));
  }
  document.addEventListener("DOMContentLoaded", function () {
    applyLang(getLang());
    const btn = document.getElementById("lang-toggle");
    const menu = document.getElementById("lang-menu");
    function positionLangMenu() {
      if (!btn || !menu) return;
      const nav = btn.closest(".lang-switcher");
      if (!nav) return;
      menu.style.left = "auto";
      menu.style.right = "auto";
      const btnRect = btn.getBoundingClientRect();
      const hostRect = nav.getBoundingClientRect();
      const menuRect = menu.getBoundingClientRect();
      const preferredLeft = btnRect.right - hostRect.left + 8;
      const maxLeft = Math.max(0, window.innerWidth - hostRect.left - menuRect.width - 8);
      const minLeft = Math.max(0, 8 - hostRect.left);
      const resolvedLeft = Math.max(minLeft, Math.min(preferredLeft, maxLeft));
      menu.style.left = resolvedLeft + "px";
      menu.style.right = "auto";
    }
    function closeLangMenu() {
      if (!btn || !menu) return;
      btn.setAttribute("aria-expanded", "false");
      menu.setAttribute("hidden", "");
    }
    function openLangMenu() {
      if (!btn || !menu) return;
      btn.setAttribute("aria-expanded", "true");
      menu.removeAttribute("hidden");
      positionLangMenu();
    }
    if (btn && menu) {
      btn.addEventListener("click", function (event) {
        event.stopPropagation();
        if (btn.getAttribute("aria-expanded") === "true") closeLangMenu();
        else openLangMenu();
      });
      menu.querySelectorAll(".lang-menu-item").forEach(function (item) {
        item.addEventListener("click", function () {
          const next = setLang(item.getAttribute("data-lang") || "zh-Hans");
          applyLang(next);
          closeLangMenu();
        });
      });
      document.addEventListener("click", function (event) {
        if (!menu.contains(event.target) && !btn.contains(event.target)) closeLangMenu();
      });
      document.addEventListener("keydown", function (event) {
        if (event.key === "Escape") closeLangMenu();
      });
      window.addEventListener("resize", function () {
        if (btn.getAttribute("aria-expanded") === "true") positionLangMenu();
      });
    }
    document.querySelectorAll("[data-artplayer]").forEach(function (node) {
      const rawVideoSrc = node.getAttribute("data-video-src") || "";
      const videoSrc = resolveVideoSrc(rawVideoSrc);
      if (!videoSrc || !window.Artplayer) return;
      const subtitleSrc = node.getAttribute("data-subtitle-src") || "";
      const subtitlePrefs = loadSubtitlePrefs();
      try {
        let art = null;
        const options = {
          container: node,
          url: videoSrc,
          setting: true,
          subtitleOffset: !!subtitleSrc,
          playbackRate: true,
          fullscreen: true,
          fullscreenWeb: true,
          miniProgressBar: true,
          screenshot: true
        };
        if (subtitleSrc) {
          options.subtitle = {
            url: subtitleSrc,
            type: "srt",
            style: buildSubtitleStyle(subtitlePrefs)
          };
          options.settings = createSubtitleSettings(function () { return art; }, subtitlePrefs);
        }
        art = new window.Artplayer(options);
        applySubtitleStyle(art, subtitlePrefs);
        window.__lookTongjiArt = art;
      } catch (e) {}
    });
    document.querySelectorAll(".tongji-timeline-item[data-seek]").forEach(function (node) {
      node.addEventListener("click", function () {
        const sec = Number(node.getAttribute("data-seek") || "0");
        const art = window.__lookTongjiArt;
        if (art && art.video && Number.isFinite(sec)) {
          art.video.currentTime = sec;
          art.play().catch(function () {});
        }
      });
    });
  });
})();

// ─── Theme toggle ─────────────────────────────────────────────────────────
(function () {
  const root = document.documentElement;
  // v0.5: Keep the highlight.js theme in sync with the page theme by
  // swapping which stylesheet is "disabled". Runs on page load and on every
  // toggle. Falls back silently if the tags are absent.
  function syncHljsTheme() {
    const light = document.getElementById("hljs-light");
    const dark = document.getElementById("hljs-dark");
    if (!light || !dark) return;
    let active = root.getAttribute("data-theme");
    if (!active) {
      active = (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) ? "dark" : "light";
    }
    const isDark = active === "dark";
    light.disabled = isDark;
    dark.disabled = !isDark;
  }
  // #ui-h4 (#566): localStorage access can throw in Safari Private Mode,
  // sandboxed iframes, and some embedded browsers. Wrap reads + writes
  // in try/catch so a thrown SecurityError doesn't kill the whole
  // theme + hljs-sync wiring.
  let saved = null;
  try { saved = localStorage.getItem("llmwiki-theme"); } catch (e) { /* private mode */ }
  if (saved === "dark" || saved === "light") root.setAttribute("data-theme", saved);
  // `system` and the missing-key case both mean "follow OS preference"
  // — leave data-theme unset so the @media (prefers-color-scheme)
  // rules in css.py drive the palette.
  syncHljsTheme();
  // #ui-h6 (#567): keep the page palette in sync if the OS theme
  // changes WHILE we're on `system` mode. Without this listener, a
  // user who toggles their OS dark mode mid-session sees the page
  // stay on whatever it was rendered with.
  if (window.matchMedia) {
    try {
      window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function () {
        let s = null;
        try { s = localStorage.getItem("llmwiki-theme"); } catch (e) {}
        if (s !== "dark" && s !== "light") syncHljsTheme();
      });
    } catch (e) { /* old Safari uses addListener */ }
  }
  document.addEventListener("DOMContentLoaded", function () {
    syncHljsTheme();
    const btn = document.getElementById("theme-toggle");
    if (!btn) return;
    // #ui-h8 (#568): aria state mirrors the current cycle position so
    // assistive tech announces what's pinned, not just "pressed".
    // #v1378-review: aria-pressed collapses 3 states (system / dark /
    // light) to 2 (true|false) — both "system" and "light" mapped to
    // "false", so a screen-reader user couldn't tell which state they
    // were in. Switched to a dynamic aria-label describing the
    // current theme + the next-tap action. aria-pressed is also kept
    // for back-compat with anything reading the binary signal.
    function syncAriaState() {
      let stored = null;
      try { stored = localStorage.getItem("llmwiki-theme"); } catch (e) {}
      const i18n = window.__lookTongjiI18n;
      const text = i18n ? i18n.currentText() : null;
      const isDark = (root.getAttribute("data-theme") || (
        (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) ? "dark" : "light"
      )) === "dark";
      btn.setAttribute("aria-pressed", isDark ? "true" : "false");
      const labels = text ? {
        dark: text.themeLabels.darkDesktop,
        light: text.themeLabels.lightDesktop,
      } : {
        dark: "Theme: dark — click for light",
        light: "Theme: light — click for system default",
      };
      const systemLabel = text ? text.themeLabels.systemDesktop : "Theme: follows system — click for dark";
      btn.setAttribute(
        "aria-label",
        labels[stored] || systemLabel,
      );
    }
    const syncAriaPressed = syncAriaState; // alias kept for older call sites
    syncAriaPressed();
    btn.addEventListener("click", function () {
      // #ui-h6 (#567): tri-state toggle. The cycle is:
      //   system → dark → light → system → ...
      // `system` means: data-theme attribute removed, palette follows
      // @media (prefers-color-scheme). Pinning a value moves out of
      // system mode; clicking back to system clears the localStorage
      // entry so a fresh tab also follows the OS.
      let stored = null;
      try { stored = localStorage.getItem("llmwiki-theme"); } catch (e) {}
      let next;
      if (stored !== "dark" && stored !== "light") {
        // Currently following system → pin to dark.
        next = "dark";
      } else if (stored === "dark") {
        next = "light";
      } else {
        // stored === "light" → return to system.
        next = null;
      }
      if (next === null) {
        root.removeAttribute("data-theme");
        try { localStorage.removeItem("llmwiki-theme"); } catch (e) {}
      } else {
        root.setAttribute("data-theme", next);
        try { localStorage.setItem("llmwiki-theme", next); } catch (e) {}
      }
      syncHljsTheme();
      syncAriaPressed();
    });
  });
  // Also respond to the mobile bottom nav theme button (bound later in script.js).
  window.__llmwikiSyncHljsTheme = syncHljsTheme;
})();

// ─── #460: Mobile/tablet hamburger nav drawer ─────────────────────────────
// Wires the hamburger button to toggle the drawer with proper aria state.
// ESC closes and returns focus to the hamburger. Click-outside closes.
// Drawer items are real <a>; tabbing flows naturally. No focus trap needed
// because the drawer is non-modal — the rest of the page is still
// interactive when it's open.
(function () {
  document.addEventListener("DOMContentLoaded", function () {
    const btn = document.getElementById("nav-hamburger");
    const drawer = document.getElementById("nav-drawer");
    if (!btn || !drawer) return;
    function setOpen(open) {
      btn.setAttribute("aria-expanded", open ? "true" : "false");
      // #v1378-review: aria-label was static "Open navigation menu"
      // even when the drawer was already open; screen readers
      // announced the wrong action. Toggle it alongside aria-expanded.
      const text = window.__lookTongjiI18n ? window.__lookTongjiI18n.currentText() : null;
      btn.setAttribute("aria-label", open ? (text ? text.closeNavigation : "关闭导航菜单") : (text ? text.openNavigation : "打开导航菜单"));
      if (open) drawer.removeAttribute("hidden");
      else drawer.setAttribute("hidden", "");
    }
    btn.addEventListener("click", function () {
      setOpen(btn.getAttribute("aria-expanded") !== "true");
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && btn.getAttribute("aria-expanded") === "true") {
        setOpen(false);
        btn.focus();
      }
    });
    // Click outside the drawer closes it.
    document.addEventListener("click", function (e) {
      if (btn.getAttribute("aria-expanded") !== "true") return;
      if (drawer.contains(e.target) || btn.contains(e.target)) return;
      setOpen(false);
    });
    // Close after navigating to one of the drawer items so the next page
    // doesn't briefly render with the drawer still open above the fold.
    drawer.querySelectorAll("a").forEach(function (a) {
      a.addEventListener("click", function () { setOpen(false); });
    });
  });
})();

// ─── Reading progress bar ────────────────────────────────────────────────
(function () {
  const bar = document.getElementById("progress-bar");
  if (!bar) return;
  function update() {
    const h = document.documentElement;
    const scrolled = h.scrollTop || document.body.scrollTop;
    const height = (h.scrollHeight || document.body.scrollHeight) - h.clientHeight;
    const pct = height > 0 ? (scrolled / height) * 100 : 0;
    bar.style.width = Math.min(100, Math.max(0, pct)) + "%";
  }
  window.addEventListener("scroll", update, { passive: true });
  update();
})();

// ─── Reading position persistence (session pages only, localStorage) ─────
(function () {
  const CAP_KEY = "llmwiki-scroll-log";
  const MAX_ENTRIES = 30;
  const article = document.querySelector(".content[itemscope]");
  if (!article) return;
  const key = location.pathname;
  let log = {};
  try { log = JSON.parse(localStorage.getItem(CAP_KEY) || "{}") || {}; } catch (e) { log = {}; }

  function restore() {
    // Restore only if deep into page (5%-95%) and no URL hash override
    if (location.hash || !log[key] || typeof log[key].pct !== "number") return;
    const pct = log[key].pct;
    if (pct <= 0.05 || pct >= 0.95) return;
    const h = document.documentElement;
    const height = h.scrollHeight - h.clientHeight;
    window.scrollTo(0, Math.max(0, height * pct));
  }
  // Restore after `load` so images/fonts are in and scrollHeight is accurate.
  // If the document is already loaded (e.g. script injected late), run now.
  if (document.readyState === "complete") restore();
  else window.addEventListener("load", restore);

  let timer = null;
  function save() {
    const h = document.documentElement;
    const height = h.scrollHeight - h.clientHeight;
    const pct = height > 0 ? h.scrollTop / height : 0;
    log[key] = { pct: Math.round(pct * 10000) / 10000, t: Date.now() };
    const entries = Object.entries(log);
    if (entries.length > MAX_ENTRIES) {
      entries.sort(function (a, b) { return (b[1].t || 0) - (a[1].t || 0); });
      log = {};
      entries.slice(0, MAX_ENTRIES).forEach(function (e) { log[e[0]] = e[1]; });
    }
    try { localStorage.setItem(CAP_KEY, JSON.stringify(log)); } catch (e) { /* quota exceeded */ }
  }
  window.addEventListener("scroll", function () {
    if (timer) return;
    timer = setTimeout(function () { timer = null; save(); }, 400);
  }, { passive: true });
})();

// ─── TOC sidebar + scroll-spy (session pages only, desktop only) ─────────
(function () {
  document.addEventListener("DOMContentLoaded", function () {
    const article = document.querySelector(".content[itemscope]");
    if (!article) return;
    const headings = article.querySelectorAll("h2[id], h3[id], h4[id]");
    if (headings.length < 3) return;
    const aside = document.createElement("aside");
    aside.className = "toc-sidebar";
    aside.setAttribute("aria-label", "页面目录");
    const title = document.createElement("div");
    title.className = "toc-title";
    const tocText = window.__lookTongjiI18n ? window.__lookTongjiI18n.currentText().tocTitle : "On this page";
    title.textContent = tocText;
    aside.appendChild(title);
    const ul = document.createElement("ul");
    const linkMap = new Map();
    headings.forEach(function (h) {
      const li = document.createElement("li");
      li.className = "toc-" + h.tagName.toLowerCase();
      const a = document.createElement("a");
      a.href = "#" + h.id;
      a.className = "toc-link";
      // The `toc` markdown extension appends a permalink anchor; strip its text.
      const clean = (h.textContent || "").replace(/\u00b6\s*$/, "").trim();
      a.textContent = clean;
      a.title = clean;
      li.appendChild(a);
      ul.appendChild(li);
      linkMap.set(h.id, a);
    });
    aside.appendChild(ul);
    document.body.appendChild(aside);
    function updateTocSidebarPosition() {
      const nav = document.querySelector(".nav");
      const navBottom = nav ? nav.getBoundingClientRect().bottom : 56;
      const stickyTop = Math.max(88, Math.round(navBottom + 16));
      const articleTop = Math.round(article.getBoundingClientRect().top);
      const top = Math.max(stickyTop, articleTop);
      const maxHeight = Math.max(220, Math.round(window.innerHeight - top - 24));
      aside.style.top = top + "px";
      aside.style.maxHeight = maxHeight + "px";
    }
    updateTocSidebarPosition();
    window.addEventListener("resize", updateTocSidebarPosition, { passive: true });
    window.addEventListener("scroll", updateTocSidebarPosition, { passive: true });
    // Scroll-spy via IntersectionObserver
    if (!("IntersectionObserver" in window)) return;
    const visible = new Set();
    function clearActive() { linkMap.forEach(function (a) { a.classList.remove("active"); }); }
    function setActive(id) {
      const link = linkMap.get(id);
      if (link) link.classList.add("active");
    }
    function applySpy() {
      clearActive();
      // Near-bottom fallback: the rootMargin creates a dead zone at the bottom
      // of the page, so the last heading would otherwise never activate.
      const doc = document.documentElement;
      const atBottom = (window.innerHeight + window.scrollY) >= (doc.scrollHeight - 24);
      if (atBottom) {
        setActive(headings[headings.length - 1].id);
        return;
      }
      if (visible.size > 0) {
        for (const h of headings) {
          if (visible.has(h.id)) { setActive(h.id); return; }
        }
      }
    }
    const obs = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) visible.add(e.target.id);
        else visible.delete(e.target.id);
      });
      applySpy();
    }, { rootMargin: "-80px 0px -70% 0px", threshold: 0 });
    headings.forEach(function (h) { obs.observe(h); });
    // Scroll listener handles the bottom-of-page edge case.
    window.addEventListener("scroll", applySpy, { passive: true });
  });
})();

// ─── Mobile bottom nav active-state + button wiring ──────────────────────
(function () {
  document.addEventListener("DOMContentLoaded", function () {
    // Mark the active link based on current path
    const path = location.pathname;
    document.querySelectorAll(".mobile-bottom-nav .mbn-link[data-page]").forEach(function (a) {
      const page = a.getAttribute("data-page");
      if (page === "home" && (path.endsWith("/") || path.endsWith("/index.html"))) a.classList.add("active");
      else if (page === "projects" && path.indexOf("/projects/") !== -1) a.classList.add("active");
      else if (page === "sessions" && path.indexOf("/sessions/") !== -1) a.classList.add("active");
    });
    // Wire the search button — delegate to the header palette trigger so that
    // the existing openPalette() runs (clears input, loads index, renders).
    const searchBtn = document.getElementById("mbn-search");
    if (searchBtn) {
      searchBtn.addEventListener("click", function () {
        const trigger = document.getElementById("open-palette");
        if (trigger) trigger.click();
      });
    }
    // Wire the theme button to toggle
    const themeBtn = document.getElementById("mbn-theme");
    if (themeBtn) {
      // #v1378-review: same dynamic aria-label treatment as the
      // desktop button — aria-pressed alone collapses the tri-state
      // (system / dark / light) into a binary signal. The label
      // describes the current state plus the next-tap action.
      function _mbnSyncPressed() {
        let stored = null;
        try { stored = localStorage.getItem("llmwiki-theme"); } catch (e) { /* private mode */ }
        const i18n = window.__lookTongjiI18n;
        const text = i18n ? i18n.currentText() : null;
        const isDark = (document.documentElement.getAttribute("data-theme") || (
          (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) ? "dark" : "light"
        )) === "dark";
        themeBtn.setAttribute("aria-pressed", isDark ? "true" : "false");
        const labels = text ? {
          dark: text.themeLabels.darkMobile,
          light: text.themeLabels.lightMobile,
        } : {
          dark: "Theme: dark — tap for light",
          light: "Theme: light — tap for system default",
        };
        const systemLabel = text ? text.themeLabels.systemMobile : "Theme: follows system — tap for dark";
        themeBtn.setAttribute("aria-label", labels[stored] || systemLabel);
      }
      _mbnSyncPressed();
      themeBtn.addEventListener("click", function () {
        // Post-final-review: mirror the desktop tri-state cycle
        // (system → dark → light → system) instead of a binary
        // dark/light flip. The old binary path would silently move
        // the user out of "system" mode on the first tap and there
        // was no way back from the mobile menu — desktop and mobile
        // diverged behaviorally. Cycle source-of-truth is desktop.
        const root = document.documentElement;
        let stored = null;
        try { stored = localStorage.getItem("llmwiki-theme"); } catch (e) { /* private mode */ }
        let next;
        if (stored !== "dark" && stored !== "light") {
          next = "dark";
        } else if (stored === "dark") {
          next = "light";
        } else {
          next = null; // back to system
        }
        if (next === null) {
          root.removeAttribute("data-theme");
          try { localStorage.removeItem("llmwiki-theme"); } catch (e) { /* private mode */ }
        } else {
          root.setAttribute("data-theme", next);
          try { localStorage.setItem("llmwiki-theme", next); } catch (e) { /* private mode */ }
        }
        if (window.__llmwikiSyncHljsTheme) window.__llmwikiSyncHljsTheme();
        _mbnSyncPressed();
      });
    }
  });
})();

// ─── Copy-as-markdown (inline handler) ───────────────────────────────────
function copyMarkdown(btn) {
  const ta = btn.parentElement.querySelector(".md-source");
  if (!ta) return;
  const text = ta.value.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;/g, "'");
  const finish = function (ok) {
    const t = window.__lookTongjiI18n ? window.__lookTongjiI18n.currentText() : null;
    btn.textContent = ok ? (t ? t.copied : "Copied!") : (t ? t.failed : "Failed");
    btn.classList.add("copied");
    setTimeout(function () {
      const nextText = window.__lookTongjiI18n ? window.__lookTongjiI18n.currentText() : null;
      btn.textContent = nextText ? nextText.copyMarkdown : "Copy as markdown";
      btn.classList.remove("copied");
    }, 1800);
  };
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).then(function () { finish(true); }, function () { finish(false); });
  } else {
    const tmp = document.createElement("textarea");
    tmp.value = text; tmp.style.position = "fixed"; tmp.style.left = "-9999px";
    document.body.appendChild(tmp); tmp.select();
    try { document.execCommand("copy"); finish(true); } catch (e) { finish(false); }
    document.body.removeChild(tmp);
  }
}

// ─── Copy-code buttons on every <pre> ────────────────────────────────────
document.addEventListener("DOMContentLoaded", function () {
  document.querySelectorAll(".content pre").forEach(function (pre) {
    if (pre.parentElement && pre.parentElement.classList.contains("code-wrap")) return;
    const wrap = document.createElement("div"); wrap.className = "code-wrap";
    pre.parentNode.insertBefore(wrap, pre);
    wrap.appendChild(pre);
    const btn = document.createElement("button");
    const text = window.__lookTongjiI18n ? window.__lookTongjiI18n.currentText() : null;
    btn.className = "copy-code-btn"; btn.type = "button"; btn.textContent = text ? text.copy : "Copy";
    btn.addEventListener("click", function () {
      const code = pre.querySelector("code");
      const text = code ? code.innerText : pre.innerText;
      const finish = function (ok) {
        const t = window.__lookTongjiI18n ? window.__lookTongjiI18n.currentText() : null;
        btn.textContent = ok ? (t ? t.copied : "Copied!") : (t ? t.failed : "Failed"); btn.classList.add("copied");
        setTimeout(function () {
          const resetText = window.__lookTongjiI18n ? window.__lookTongjiI18n.currentText() : null;
          btn.textContent = resetText ? resetText.copy : "Copy";
          btn.classList.remove("copied");
        }, 1500);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () { finish(true); }, function () { finish(false); });
      } else {
        const tmp = document.createElement("textarea");
        tmp.value = text; tmp.style.position = "fixed"; tmp.style.left = "-9999px";
        document.body.appendChild(tmp); tmp.select();
        try { document.execCommand("copy"); finish(true); } catch (e) { finish(false); }
        document.body.removeChild(tmp);
      }
    });
    wrap.appendChild(btn);
  });
});

// ─── Auto-collapse long tool results into <details> ──────────────────────
// #476: the summary used to read "Tool results (544 chars) — click to
// expand" — pure char-count, no signal. Now extracts the first non-
// blank line as a preview, detects ok/error from a leading `(ok)` or
// `(ERROR)` marker the markdown emit puts in, and counts result lines.
// Renders as a richer card: `[ok] preview text · 412 lines · click to
// expand`. Keeps the same <details>/<summary> structure so existing CSS
// + a11y plumbing continues to work.
document.addEventListener("DOMContentLoaded", function () {
  const markers = document.querySelectorAll(".content p strong");
  markers.forEach(function (s) {
    const text = (s.textContent || "").trim();
    if (text !== "Tool results:") return;
    const p = s.closest("p");
    if (!p) return;
    let next = p.nextElementSibling;
    if (!next) return;
    const combinedText = (next.innerText || "").trim();
    if (combinedText.length < 500) return;

    // Outcome detection: the markdown emit prepends "→ result (ok):" or
    // "→ result (ERROR):" to each block. First match wins.
    const outcome = /\(ERROR\)/.test(combinedText) ? "error" : "ok";
    // Preview: first non-blank line, stripped of "→ result (ok):" prefix
    // and arrow indent. Truncate at 80 chars on a word boundary.
    const lines = combinedText.split(/\r?\n/);
    let preview = "";
    for (const raw of lines) {
      const line = raw.replace(/^\s*→\s*result\s*\((?:ok|ERROR)\):\s*/, "").trim();
      if (line) { preview = line; break; }
    }
    if (preview.length > 80) {
      const cut = preview.lastIndexOf(" ", 77);
      preview = (cut > 40 ? preview.slice(0, cut) : preview.slice(0, 77)) + "...";
    }
    const lineCount = lines.length;

    // Wrap next element in a <details>.
    const det = document.createElement("details");
    det.className = "collapsible-result outcome-" + outcome;
    const sum = document.createElement("summary");
    // Build the summary as DOM nodes (not innerHTML) so a malicious
    // preview can't inject markup.
    const badge = document.createElement("span");
    badge.className = "tool-result-badge tool-result-" + outcome;
    badge.textContent = outcome === "error" ? "ERROR" : "ok";
    sum.appendChild(badge);
    if (preview) {
      const previewEl = document.createElement("span");
      previewEl.className = "tool-result-preview";
      previewEl.textContent = " " + preview;
      sum.appendChild(previewEl);
    }
    const meta = document.createElement("span");
    meta.className = "tool-result-meta muted";
    meta.textContent = " · " + lineCount + (lineCount === 1 ? " line" : " lines") +
                       " · " + combinedText.length + " chars";
    sum.appendChild(meta);
    det.appendChild(sum);
    next.parentNode.insertBefore(det, next);
    det.appendChild(next);
  });
});

// ─── Command palette (Cmd+K) + search index loader ─────────────────────
(function () {
  let idx = null;
  let idxPromise = null;
  let metaEntries = null;  // project + page entries (loaded first, fast)
  let activeIdx = 0;
  let currentResults = [];

  // Lazy-chunked loader (#47): loads the small meta index first (projects +
  // static pages), then fetches per-project session chunks in parallel on
  // first demand. Backwards-compatible with the old flat-array format.
  function loadIndex() {
    if (idx) return Promise.resolve(idx);
    if (idxPromise) return idxPromise;
    const url = window.LLMWIKI_INDEX_URL || "search-index.json";
    const base = url.substring(0, url.lastIndexOf("/") + 1);
    idxPromise = fetch(url)
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (data) {
        // Old format: flat array → return as-is
        if (Array.isArray(data)) { idx = data; return idx; }
        // New format: {entries: [...], _chunks: ["search-chunks/foo.json", ...]}
        metaEntries = data.entries || [];
        var chunkUrls = data._chunks || [];
        if (!chunkUrls.length) { idx = metaEntries; return idx; }
        return Promise.all(chunkUrls.map(function (cu) {
          return fetch(base + cu)
            .then(function (r) { return r.ok ? r.json() : []; })
            .catch(function () { return []; });
        })).then(function (chunks) {
          idx = metaEntries.slice();
          chunks.forEach(function (c) {
            if (Array.isArray(c)) { for (var i = 0; i < c.length; i++) idx.push(c[i]); }
          });
          return idx;
        });
      })
      .catch(function () { idx = []; return idx; });
    return idxPromise;
  }
  // Expose the shared loader so wikilink-preview + related-pages can reuse it
  window.__llmwikiLoadIndex = loadIndex;

  // Return the meta entries (projects + pages) synchronously if available,
  // otherwise trigger a full load. Used for instant palette rendering before
  // session chunks arrive.
  function getMetaSync() { return metaEntries || idx || []; }

  function score(entry, query) {
    if (!query) return 0;
    const q = query.toLowerCase();
    const title = (entry.title || "").toLowerCase();
    const project = (entry.project || "").toLowerCase();
    const body = (entry.body || "").toLowerCase();
    let s = 0;
    if (title === q) s += 100;
    else if (title.indexOf(q) === 0) s += 60;
    else if (title.indexOf(q) !== -1) s += 40;
    if (project.indexOf(q) !== -1) s += 20;
    if (body.indexOf(q) !== -1) s += 10;
    // Token match
    const tokens = q.split(/\s+/).filter(Boolean);
    let allMatch = true;
    tokens.forEach(function (t) {
      if (title.indexOf(t) === -1 && project.indexOf(t) === -1 && body.indexOf(t) === -1) allMatch = false;
    });
    if (allMatch && tokens.length > 1) s += 30;
    return s;
  }

  // v0.8 (#97): Dataview-style structured queries. Users can type
  // key:value pairs alongside free text to filter by metadata:
  //   type:session project:llm-wiki model:claude date:>2026-03-01 sort:date rust
  // Supported keys: type, project, model, date (range with > / <), tags, sort
  // Anything that doesn't match key:value is treated as free-text fuzzy search.
  function parseStructuredQuery(raw) {
    var filters = {};
    var freeText = [];
    var tokens = raw.split(/\s+/).filter(Boolean);
    tokens.forEach(function (t) {
      var m = t.match(/^(type|project|model|date|tags|sort):(.+)$/i);
      if (m) { filters[m[1].toLowerCase()] = m[2]; }
      else { freeText.push(t); }
    });
    return { filters: filters, freeText: freeText.join(" ") };
  }

  function matchesFilters(entry, filters) {
    if (filters.type && (entry.type || "").toLowerCase() !== filters.type.toLowerCase()) return false;
    if (filters.project && (entry.project || "").toLowerCase().indexOf(filters.project.toLowerCase()) === -1) return false;
    if (filters.model && (entry.model || "").toLowerCase().indexOf(filters.model.toLowerCase()) === -1) return false;
    if (filters.tags) {
      var want = filters.tags.toLowerCase();
      var entryBody = ((entry.body || "") + " " + (entry.title || "")).toLowerCase();
      if (entryBody.indexOf(want) === -1) return false;
    }
    if (filters.date) {
      var d = entry.date || "";
      var op = filters.date.charAt(0);
      if (op === ">" && d <= filters.date.substring(1)) return false;
      if (op === "<" && d >= filters.date.substring(1)) return false;
      if (op !== ">" && op !== "<" && d.indexOf(filters.date) === -1) return false;
    }
    return true;
  }

  function search(query) {
    if (!idx) return [];
    if (!query) return idx.slice(0, 10);
    var parsed = parseStructuredQuery(query);
    var filtered = idx;
    if (Object.keys(parsed.filters).length > 0) {
      filtered = idx.filter(function (e) { return matchesFilters(e, parsed.filters); });
    }
    var sortKey = parsed.filters.sort;
    if (sortKey === "date") {
      return filtered
        .slice()
        .sort(function (a, b) { return (b.date || "").localeCompare(a.date || ""); })
        .slice(0, 20);
    }
    if (!parsed.freeText) return filtered.slice(0, 20);
    return filtered
      .map(function (e) { return { entry: e, score: score(e, parsed.freeText) }; })
      .filter(function (r) { return r.score > 0; })
      .sort(function (a, b) { return b.score - a.score; })
      .slice(0, 15)
      .map(function (r) { return r.entry; });
  }

  function renderResults(results) {
    const ul = document.getElementById("palette-results");
    if (!ul) return;
    currentResults = results;
    activeIdx = 0;
    ul.innerHTML = results.map(function (r, i) {
      const meta = [r.project, r.date, r.model].filter(Boolean).join(" · ");
      return '<li data-i="' + i + '" class="' + (i === 0 ? 'active' : '') + '">' +
        '<span class="result-type">' + (r.type || 'page') + '</span>' +
        '<span class="result-title">' + escapeHtml(r.title) + '</span>' +
        (meta ? '<div class="result-meta">' + escapeHtml(meta) + '</div>' : '') +
        '</li>';
    }).join("");
    ul.querySelectorAll("li").forEach(function (li) {
      li.addEventListener("click", function () {
        const i = parseInt(li.getAttribute("data-i"));
        openResult(i);
      });
    });
  }

  function escapeHtml(s) {
    return String(s || "").replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function openResult(i) {
    if (!currentResults[i]) return;
    const r = currentResults[i];
    // #277: slash commands don't have URLs — copy the command text
    // to the clipboard + flash a hint instead of navigating.
    if (r.type === "slash" || !r.url) {
      try { navigator.clipboard && navigator.clipboard.writeText(r.title); } catch (e) {}
      const input = document.getElementById("palette-input");
      if (input) { input.value = r.title; input.placeholder = "copied — paste inside Claude Code"; }
      return;
    }
    const pageUrl = window.LLMWIKI_INDEX_URL || "";
    // Compute base dir from current page URL
    const pathPrefix = pageUrl.substring(0, pageUrl.lastIndexOf("/") + 1) || "";
    window.location.href = pathPrefix + r.url;
  }

  // #478, #479: dialog focus + inert helpers shared by palette + help.
  // Stash who opened the dialog so we can restore focus on close.
  // Apply `inert` to every direct child of <body> EXCEPT the dialog
  // itself so AT users can't tab into the page chrome behind the
  // backdrop (the previous aria-hidden gate left siblings reachable).
  //
  // Post-review: stash is a Map keyed by dialog.id so opening a second
  // dialog while the first is still open doesn't clobber the first
  // dialog's restoration target. Equally, inert is only removed from
  // siblings that are NOT themselves currently-open dialogs, so closing
  // help while palette is still open doesn't strip the palette's inert
  // wrapping of the rest of the chrome.
  var __dialogLastFocus = new Map();
  function __getInertSiblings(dialog) {
    return Array.prototype.filter.call(
      document.body.children,
      function (el) { return el !== dialog; }
    );
  }
  function __isOpenDialog(el) {
    return el && el.classList && el.classList.contains("open") &&
           (el.id === "palette" || el.id === "help-dialog");
  }
  function __isDialogOpen(dialog) {
    return dialog && dialog.classList.contains("open");
  }
  function __getFocusable(container) {
    return Array.prototype.filter.call(
      container.querySelectorAll(
        'a[href], button:not([disabled]), input:not([disabled]), ' +
        'select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
      ),
      function (el) { return !el.hasAttribute("disabled") && el.offsetParent !== null; }
    );
  }
  function __syncTriggerAriaExpanded(dialog, value) {
    // #ui-h8 (#568): trigger button's aria-expanded must mirror the
    // dialog's open/closed state so AT users hear the right thing
    // when they re-focus the trigger.
    if (!dialog || !dialog.id) return;
    const trigger = document.querySelector('[aria-controls="' + dialog.id + '"]');
    if (trigger) trigger.setAttribute("aria-expanded", value ? "true" : "false");
  }
  function __openDialog(dialog, firstFocus) {
    if (!dialog || dialog.classList.contains("open")) return;
    if (dialog.id) __dialogLastFocus.set(dialog.id, document.activeElement);
    dialog.classList.add("open");
    __syncTriggerAriaExpanded(dialog, true);
    __getInertSiblings(dialog).forEach(function (s) { s.setAttribute("inert", ""); });
    if (firstFocus && firstFocus.focus) firstFocus.focus();
  }
  function __closeDialog(dialog) {
    if (!dialog || !dialog.classList.contains("open")) return;
    dialog.classList.remove("open");
    __syncTriggerAriaExpanded(dialog, false);
    // Only strip inert from siblings that are NOT themselves an open
    // dialog — otherwise closing the help-dialog while palette is open
    // re-exposes the palette's inert chrome guard.
    __getInertSiblings(dialog).forEach(function (s) {
      if (!__isOpenDialog(s)) s.removeAttribute("inert");
    });
    var lf = dialog.id ? __dialogLastFocus.get(dialog.id) : null;
    if (lf && lf.focus) {
      try { lf.focus(); } catch (e) { /* trigger gone */ }
    }
    if (dialog.id) __dialogLastFocus.delete(dialog.id);
  }
  // Trap Tab + Shift+Tab inside `dialog` so focus can't escape into
  // the inert page chrome and become visually invisible.
  function __trapTab(dialog) {
    return function (e) {
      if (e.key !== "Tab" || !__isDialogOpen(dialog)) return;
      const focusable = __getFocusable(dialog);
      if (focusable.length === 0) { e.preventDefault(); return; }
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault(); last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault(); first.focus();
      }
    };
  }

  function openPalette() {
    const p = document.getElementById("palette");
    if (!p) return;
    const input = document.getElementById("palette-input");
    if (input) { input.value = ""; }
    __openDialog(p, input);
    // Show meta entries immediately while chunks load
    var meta = getMetaSync();
    if (meta.length && !idx) renderResults(meta.slice(0, 10));
    loadIndex().then(function () { renderResults(search(input ? input.value : "")); });
  }

  function closePalette() {
    const p = document.getElementById("palette");
    __closeDialog(p);
  }

  function openHelp() {
    const d = document.getElementById("help-dialog");
    if (!d) return;
    const closeBtn = document.getElementById("help-close");
    __openDialog(d, closeBtn);
  }
  function closeHelp() {
    const d = document.getElementById("help-dialog");
    __closeDialog(d);
  }

  document.addEventListener("DOMContentLoaded", function () {
    // Wire up buttons
    const openBtn = document.getElementById("open-palette");
    if (openBtn) openBtn.addEventListener("click", openPalette);

    const backdrop = document.getElementById("palette-backdrop");
    if (backdrop) backdrop.addEventListener("click", closePalette);

    const input = document.getElementById("palette-input");
    if (input) {
      input.addEventListener("input", function () { renderResults(search(input.value)); });
      input.addEventListener("keydown", function (e) {
        const items = document.querySelectorAll("#palette-results li");
        if (e.key === "ArrowDown") { e.preventDefault(); activeIdx = Math.min(items.length - 1, activeIdx + 1); updateActive(); }
        else if (e.key === "ArrowUp") { e.preventDefault(); activeIdx = Math.max(0, activeIdx - 1); updateActive(); }
        else if (e.key === "Enter") { e.preventDefault(); openResult(activeIdx); }
      });
    }

    const helpBackdrop = document.getElementById("help-backdrop");
    if (helpBackdrop) helpBackdrop.addEventListener("click", closeHelp);
    const helpClose = document.getElementById("help-close");
    if (helpClose) helpClose.addEventListener("click", closeHelp);

    // #479: Tab focus traps. Listening on document so the handler fires
    // even when the focused element is a backdrop / non-focusable.
    const paletteEl = document.getElementById("palette");
    if (paletteEl) document.addEventListener("keydown", __trapTab(paletteEl));
    const helpEl = document.getElementById("help-dialog");
    if (helpEl) document.addEventListener("keydown", __trapTab(helpEl));
  });

  function updateActive() {
    const items = document.querySelectorAll("#palette-results li");
    items.forEach(function (li, i) { li.classList.toggle("active", i === activeIdx); });
    const active = items[activeIdx];
    if (active) active.scrollIntoView({ block: "nearest" });
  }

  // ─── Keyboard shortcuts ─────────────────────────────────────────────────
  let gPressed = false;
  let gPressedTimer = null;
  document.addEventListener("keydown", function (e) {
    const inInput = e.target && (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.tagName === "SELECT");

    // Cmd/Ctrl+K opens palette everywhere
    if ((e.metaKey || e.ctrlKey) && e.key === "k") {
      e.preventDefault();
      openPalette();
      return;
    }
    // Esc closes palette / help / clears focus
    if (e.key === "Escape") {
      const p = document.getElementById("palette");
      const h = document.getElementById("help-dialog");
      // #478: state check now reads the .open class (was aria-hidden).
      if (p && p.classList.contains("open")) { closePalette(); return; }
      if (h && h.classList.contains("open")) { closeHelp(); return; }
      if (inInput) { e.target.blur(); return; }
    }

    // Shortcuts only work when not typing in an input
    if (inInput) return;

    if (e.key === "/") { e.preventDefault(); openPalette(); return; }
    if (e.key === "?") { e.preventDefault(); openHelp(); return; }

    // g-prefix shortcuts
    if (e.key === "g" && !gPressed) {
      gPressed = true;
      gPressedTimer = setTimeout(function () { gPressed = false; }, 1000);
      return;
    }
    if (gPressed) {
      gPressed = false;
      if (gPressedTimer) clearTimeout(gPressedTimer);
      const rel = window.LLMWIKI_INDEX_URL || "";
      const base = rel.substring(0, rel.lastIndexOf("/") + 1);
      if (e.key === "h") { window.location.href = base + "index.html"; return; }
      if (e.key === "p") { window.location.href = base + "projects/index.html"; return; }
      if (e.key === "s") { window.location.href = base + "sessions/index.html"; return; }
    }

    // j/k on sessions table
    const tbody = document.getElementById("sessions-tbody");
    if (tbody && (e.key === "j" || e.key === "k")) {
      e.preventDefault();
      const visibleRows = Array.from(tbody.querySelectorAll("tr")).filter(function (r) { return !r.hidden; });
      if (!visibleRows.length) return;
      let cur = visibleRows.findIndex(function (r) { return r.classList.contains("selected"); });
      if (cur === -1) cur = 0;
      else cur = e.key === "j" ? Math.min(visibleRows.length - 1, cur + 1) : Math.max(0, cur - 1);
      visibleRows.forEach(function (r) { r.classList.remove("selected"); });
      visibleRows[cur].classList.add("selected");
      visibleRows[cur].scrollIntoView({ block: "nearest" });
      // Enter on selected row navigates
    }
    if (e.key === "Enter" && tbody) {
      const sel = tbody.querySelector("tr.selected a");
      if (sel) { window.location.href = sel.href; }
    }
  });
})();

// ─── Sessions table filter bar ────────────────────────────────────────────
document.addEventListener("DOMContentLoaded", function () {
  const tbody = document.getElementById("sessions-tbody");
  if (!tbody) return;
  const table = document.querySelector(".sessions-table");
  const fProject = document.getElementById("filter-project");
  const fFrom = document.getElementById("filter-date-from");
  const fTo = document.getElementById("filter-date-to");
  const fText = document.getElementById("filter-text");
  const fClear = document.getElementById("filter-clear");
  const fCount = document.getElementById("filter-count");

  // #ui-m1 (#572): persist filter selections to sessionStorage so a
  // navigation away + back doesn't lose the user's filter state.
  // sessionStorage (not localStorage) is the right scope: it survives
  // back/forward but clears on tab close, matching user expectations
  // for a transient filter view.
  const STORAGE_KEY = "llmwiki-sessions-filters";
  function _readSaved() {
    try {
      const raw = sessionStorage.getItem(STORAGE_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch (e) { return null; }
  }
  function _writeSaved() {
    try {
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify({
        p: fProject ? fProject.value : "",
        from: fFrom ? fFrom.value : "",
        to: fTo ? fTo.value : "",
        txt: fText ? fText.value : "",
      }));
    } catch (e) { /* private mode */ }
  }
  // Restore on page load.
  const saved = _readSaved();
  if (saved) {
    if (fProject && saved.p) fProject.value = saved.p;
    if (fFrom && saved.from) fFrom.value = saved.from;
    if (fTo && saved.to) fTo.value = saved.to;
    if (fText && saved.txt) fText.value = saved.txt;
  }

  function apply() {
    const p = fProject ? fProject.value : "";
    const from = fFrom ? fFrom.value : "";
    const to = fTo ? fTo.value : "";
    const txt = fText ? fText.value.toLowerCase() : "";
    let shown = 0;
    Array.from(tbody.querySelectorAll("tr")).forEach(function (r) {
      const rp = r.getAttribute("data-project") || "";
      const rd = r.getAttribute("data-date") || "";
      const rs = (r.getAttribute("data-slug") || "").toLowerCase();
      let show = true;
      if (p && rp !== p) show = false;
      if (from && rd < from) show = false;
      if (to && rd > to) show = false;
      if (txt && rs.indexOf(txt) === -1) show = false;
      r.hidden = !show;
      if (show) shown++;
    });
    if (fCount) {
      const text = window.__lookTongjiI18n ? window.__lookTongjiI18n.currentText() : null;
      fCount.textContent = shown + (text ? text.shownSuffix : " shown");
    }
    _writeSaved();
  }

  [fProject, fFrom, fTo, fText].forEach(function (el) {
    if (el) el.addEventListener("input", apply);
  });
  if (fClear) fClear.addEventListener("click", function () {
    if (fProject) fProject.value = "";
    if (fFrom) fFrom.value = "";
    if (fTo) fTo.value = "";
    if (fText) fText.value = "";
    try { sessionStorage.removeItem(STORAGE_KEY); } catch (e) {}
    apply();
  });
  apply();
  if (table) {
    function updateStickyHead() {
      const rect = table.getBoundingClientRect();
      const shouldStick = rect.top <= 56 && rect.bottom > 96;
      table.classList.toggle("sticky-head", shouldStick);
    }
    updateStickyHead();
    window.addEventListener("scroll", updateStickyHead, { passive: true });
    window.addEventListener("resize", updateStickyHead, { passive: true });
  }
});

// ─── Hover-to-preview wikilinks ───────────────────────────────────────────
// When the user hovers over a wikilink (an <a> whose text starts with "[["
// or whose href is a wiki page), fetch the target's first ~300 chars and
// show a floating preview card. Uses the client-side search index.
(function () {
  let idx = null;
  let previewEl = null;
  let hideTimer = null;

  function getPreviewEl() {
    if (previewEl) return previewEl;
    previewEl = document.createElement("div");
    previewEl.className = "wikilink-preview";
    previewEl.setAttribute("hidden", "");
    previewEl.innerHTML = '<div class="wl-title"></div><div class="wl-body"></div>';
    document.body.appendChild(previewEl);
    previewEl.addEventListener("mouseenter", function () {
      if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
    });
    previewEl.addEventListener("mouseleave", function () {
      hidePreview();
    });
    return previewEl;
  }

  function loadIndex() {
    if (idx) return Promise.resolve(idx);
    // Reuse the shared chunked loader from the palette IIFE (#47)
    if (window.__llmwikiLoadIndex) {
      return window.__llmwikiLoadIndex().then(function (data) { idx = data; return idx; });
    }
    var url = window.LLMWIKI_INDEX_URL || "search-index.json";
    return fetch(url)
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (data) {
        idx = Array.isArray(data) ? data : (data.entries || []);
        return idx;
      })
      .catch(function () { idx = []; return idx; });
  }

  function findEntry(keyOrText) {
    if (!idx) return null;
    const needle = (keyOrText || "").toLowerCase().trim();
    if (!needle) return null;
    // Try exact title match first
    for (const e of idx) {
      if ((e.title || "").toLowerCase() === needle) return e;
    }
    // Fall back to prefix
    for (const e of idx) {
      if ((e.title || "").toLowerCase().startsWith(needle)) return e;
    }
    // Fall back to substring
    for (const e of idx) {
      if ((e.title || "").toLowerCase().indexOf(needle) !== -1) return e;
    }
    return null;
  }

  function showPreview(target, entry) {
    const el = getPreviewEl();
    el.querySelector(".wl-title").textContent = entry.title || entry.id || "";
    el.querySelector(".wl-body").textContent = (entry.body || "").slice(0, 300);
    // Position below the target
    const rect = target.getBoundingClientRect();
    el.style.position = "fixed";
    el.style.top = (rect.bottom + 8) + "px";
    el.style.left = Math.min(window.innerWidth - 380, Math.max(16, rect.left)) + "px";
    el.removeAttribute("hidden");
  }

  function hidePreview() {
    if (previewEl) previewEl.setAttribute("hidden", "");
  }

  function attach(a) {
    const text = (a.textContent || "").trim();
    // Only target links that look like wikilinks (starting with [[) or that
    // point to another page in site/sessions, site/projects, or site/.
    const isWiki = text.startsWith("[[") || /sessions\/|projects\//.test(a.getAttribute("href") || "");
    if (!isWiki) return;
    let key = text.replace(/^\[\[|\]\]$/g, "").trim();
    if (!key) {
      // Derive from href
      const href = a.getAttribute("href") || "";
      const m = href.match(/([^/]+)\.html$/);
      if (m) key = m[1];
    }
    if (!key) return;

    function _show() {
      if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
      loadIndex().then(function () {
        const entry = findEntry(key);
        if (entry) showPreview(a, entry);
      });
    }
    function _hide() {
      hideTimer = setTimeout(hidePreview, 200);
    }
    // #ui-h13 (#570): keyboard parity for the hover preview. Show on
    // focus + hide on blur so a Tab-only user gets the same affordance
    // a mouse user gets. ESC dismisses immediately and returns nothing
    // to do (focus is already on the link).
    a.addEventListener("mouseenter", _show);
    a.addEventListener("mouseleave", _hide);
    a.addEventListener("focus", _show);
    a.addEventListener("blur", _hide);
    a.addEventListener("keydown", function (e) {
      if (e.key === "Escape") {
        if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
        hidePreview();
      }
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll(".content a").forEach(attach);
  });
})();

// ─── Timeline view on sessions index ──────────────────────────────────────
// Render a compact sparkline above the sessions table showing session count
// per day over the last 60 days.
(function () {
  // Post-final-review: local attribute escaper. The timeline SVG below
  // string-concatenates `data-date` and `data-count` into HTML; while
  // the values come from controlled `data-date` row attributes (built
  // in build.py from frontmatter dates), defense-in-depth escapes them
  // anyway. The palette IIFE has its own `escapeHtml` but it's out of
  // scope here, hence the local copy.
  function escAttr(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  document.addEventListener("DOMContentLoaded", function () {
    const tbody = document.getElementById("sessions-tbody");
    if (!tbody) return;
    // Only run on the sessions index page
    const container = document.querySelector(".section .container");
    if (!container || !container.querySelector(".filter-bar")) return;

    // Collect dates
    const rows = Array.from(tbody.querySelectorAll("tr"));
    const counts = new Map();
    rows.forEach(function (r) {
      const d = r.getAttribute("data-date");
      if (!d) return;
      counts.set(d, (counts.get(d) || 0) + 1);
    });
    if (!counts.size) return;

    // Sort dates ascending
    const dates = Array.from(counts.keys()).sort();
    const maxCount = Math.max(...counts.values());

    // #453: position bars by calendar date so gaps between active days are
    // visible. The previous behaviour stretched dates.length bars across
    // the full width with equal spacing, which hid 6-month gaps. We now
    // compute calendar span (minDate→maxDate) in days and lay bars out
    // proportional to their date offset. Single-day collections fall back
    // to a single centred bar.
    const minDate = new Date(dates[0] + "T00:00:00Z");
    const maxDate = new Date(dates[dates.length - 1] + "T00:00:00Z");
    const dayMs = 86400000;
    const spanDays = Math.round((maxDate - minDate) / dayMs) + 1;

    // Build an SVG sparkline
    const w = 800;
    const h = 60;
    const padX = 4;
    const innerW = w - 2 * padX;
    const slotW = spanDays > 1 ? innerW / spanDays : innerW;
    const bars = dates.map(function (d) {
      const count = counts.get(d);
      const offset = spanDays > 1
        ? Math.round((new Date(d + "T00:00:00Z") - minDate) / dayMs)
        : 0;
      const x = spanDays > 1 ? padX + offset * slotW : padX + innerW / 2 - 2;
      const barW = Math.max(2, slotW - 1);
      const barH = (count / maxCount) * (h - 16);
      const y = h - barH - 4;
      return '<rect x="' + x + '" y="' + y + '" width="' + barW + '" height="' + barH +
             '" fill="var(--accent)" opacity="0.7" data-date="' + escAttr(d) + '" data-count="' + escAttr(count) + '"></rect>';
    }).join("");

    const svg =
      '<svg viewBox="0 0 ' + w + ' ' + h + '" preserveAspectRatio="none" ' +
      'style="width:100%;height:' + h + 'px;display:block" aria-label="Session activity timeline">' +
      bars + '</svg>';

    // #453: label now shows calendar span (matches the geometry above) plus
    // active-day count and peak so users can read both stories from one line.
    const text = window.__lookTongjiI18n ? window.__lookTongjiI18n.currentText() : null;
    const labelText = spanDays === 1
      ? (text ? text.activityTimelineSingle(maxCount) : ('Activity timeline · 1 day · peak ' + maxCount + (maxCount === 1 ? ' session' : ' sessions')))
      : (text ? text.activityTimelineRange(spanDays, dates.length, maxCount) : ('Activity timeline · ' + spanDays + ' days · ' + dates.length +
        ' active · peak ' + maxCount + (maxCount === 1 ? ' session/day' : ' sessions/day')));

    // Create the timeline block. #v1378-review: previously assigned
    // the label + svg via innerHTML, which interpolated `labelText`
    // (currently number-only — safe today) into HTML without escaping.
    // Defense-in-depth: build the label as a real element with
    // textContent so a future change feeding a user-derived string
    // into the label can't introduce XSS. The svg string itself is
    // already escaped via escAttr() at every data-* interpolation
    // and uses only static structural markup elsewhere.
    const tl = document.createElement("div");
    tl.className = "timeline-block";
    const labelEl = document.createElement("div");
    labelEl.className = "timeline-label muted";
    labelEl.textContent = labelText;
    tl.appendChild(labelEl);
    tl.insertAdjacentHTML("beforeend", svg);

    // Insert above the filter bar
    const filter = container.querySelector(".filter-bar");
    if (filter) container.insertBefore(tl, filter);
  });
})();

// ─── v0.4: Related pages panel ────────────────────────────────────────────
// On a session page, find 3-5 other sessions that share wikilink targets
// or project, and display them at the bottom under a "Related pages" heading.
(function () {
  document.addEventListener("DOMContentLoaded", function () {
    const article = document.querySelector("article.content");
    if (!article) return;
    // Only on session pages (have a breadcrumb + back-to-project link)
    const backBtn = document.querySelector(".session-actions a.btn");
    if (!backBtn) return;

    // Extract current page metadata from the llmwiki:metadata comment
    const html = document.documentElement.outerHTML;
    const m = html.match(/llmwiki:metadata\n([\s\S]*?)-->/);
    if (!m) return;
    const meta = {};
    m[1].split("\n").forEach(function (line) {
      const idx = line.indexOf(":");
      if (idx > 0) {
        const k = line.slice(0, idx).trim();
        const v = line.slice(idx + 1).trim();
        if (k && v) meta[k] = v;
      }
    });
    const currentProject = meta.project || "";
    const currentSlug = meta.slug || "";
    if (!currentProject) return;

    // Reuse the shared chunked loader (#47) — includes session entries
    var loader = window.__llmwikiLoadIndex
      ? window.__llmwikiLoadIndex()
      : fetch(window.LLMWIKI_INDEX_URL || "search-index.json")
          .then(function (r) { return r.ok ? r.json() : []; })
          .then(function (d) { return Array.isArray(d) ? d : (d.entries || []); });
    loader
      .then(function (entries) {
        if (!entries || !entries.length) return;
        // Score each other session: same project = 2 pts, shared wikilink targets = +1 per token
        const scored = entries
          .filter(function (e) {
            return e.type === "session" && e.url && !e.url.endsWith(currentSlug + ".html");
          })
          .map(function (e) {
            let score = 0;
            if (e.project === currentProject) score += 2;
            return { entry: e, score: score };
          })
          .filter(function (s) { return s.score > 0; })
          .sort(function (a, b) { return b.score - a.score; })
          .slice(0, 5);
        if (!scored.length) return;

        // Post-review remediation: title + url + date used to be
        // interpolated into innerHTML without escaping. Build the DOM
        // tree explicitly with createElement / textContent so a malicious
        // session frontmatter title (e.g. "<img src=x onerror=...>") or
        // a `javascript:` URL can't execute in the visitor's browser.
        function _safeHref(raw) {
          // Reject anything that isn't a relative path or http(s).
          // Same-origin checks happen at the browser; we just gate the
          // protocol prefix here to stop `javascript:` / `data:` etc.
          var s = String(raw || "");
          if (/^(javascript|data|vbscript):/i.test(s)) return "#";
          return s;
        }
        const section = document.createElement("div");
        section.className = "related-pages";
        const heading = document.createElement("h3");
        const text = window.__lookTongjiI18n ? window.__lookTongjiI18n.currentText() : null;
        heading.textContent = text ? text.relatedPages : "Related pages";
        section.appendChild(heading);
        const ul = document.createElement("ul");
        scored.forEach(function (s) {
          const li = document.createElement("li");
          const a = document.createElement("a");
          a.href = _safeHref("../../" + (s.entry.url || ""));
          a.textContent = String(s.entry.title || "");
          li.appendChild(a);
          if (s.entry.date) {
            const span = document.createElement("span");
            span.className = "muted";
            span.textContent = " \u00b7 " + String(s.entry.date);
            li.appendChild(span);
          }
          ul.appendChild(li);
        });
        section.appendChild(ul);
        article.appendChild(section);
      })
      .catch(function () {});
  });
})();

// v0.8 (#64, #72): the v0.4 JS-based tiny-strip heatmap is gone. The 365-day
// GitLab/GitHub-style grid is now rendered at build time as pure SVG by
// llmwiki/viz_heatmap.py and inlined into index.html + each project page.
// The page CSS (--heatmap-0..4) picks up the current theme automatically —
// no JS wiring needed.

// ─── v0.4: Search result highlights ──────────────────────────────────────
// When showing search palette results, highlight the matched query in the
// title and body snippet.
(function () {
  function highlight(text, query) {
    if (!query || !text) return escapeLocalHtml(text);
    const q = query.toLowerCase();
    const lower = text.toLowerCase();
    const i = lower.indexOf(q);
    if (i === -1) return escapeLocalHtml(text);
    return escapeLocalHtml(text.slice(0, i)) +
      '<mark>' + escapeLocalHtml(text.slice(i, i + q.length)) + '</mark>' +
      escapeLocalHtml(text.slice(i + q.length));
  }
  function escapeLocalHtml(s) {
    return String(s || "").replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  // Expose so the palette renderer can call it if it chooses
  window.llmwikiHighlight = highlight;
})();

// ─── v0.4: Deep-link icon next to headings ────────────────────────────────
(function () {
  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll(".content h2[id], .content h3[id], .content h4[id]").forEach(function (h) {
      if (h.querySelector(".deep-link")) return;
      const icon = document.createElement("a");
      icon.className = "deep-link";
      icon.href = "#" + h.id;
      icon.innerHTML = "🔗";
      const text = window.__lookTongjiI18n ? window.__lookTongjiI18n.currentText() : null;
      icon.title = text ? text.copySectionLink : "Copy link to this section";
      icon.addEventListener("click", function (ev) {
        ev.preventDefault();
        const url = window.location.origin + window.location.pathname + "#" + h.id;
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(url).then(function () {
            icon.textContent = "✓";
            setTimeout(function () { icon.textContent = "🔗"; }, 1200);
          });
        }
      });
      h.appendChild(icon);
    });
  });
})();
"""
