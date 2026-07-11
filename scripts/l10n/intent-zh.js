/*
 * Intent 运行时汉化(词典式 DOM 翻译)。
 *
 * 应用没有 i18n 框架,UI 文案硬编码在混淆后的 JS chunk 里,静态替换每个版本
 * 都会失配且可能改坏逻辑。此脚本改为在运行时翻译 DOM:MutationObserver 监听
 * 页面变化,文本节点/常用属性按"英文原文 → 中文"词典精确替换。
 * 与上游版本解耦:词典未覆盖的新文案只是保持英文,永远不会弄坏应用。
 *
 * 维护:往 DICT 里加"英文原文": "中文"即可(原文需与界面显示完全一致,含大小写);
 * 带数字等变量的文案加到 REGEX。repack.ps1 会把本文件注入 dist/renderer/。
 */
(() => {
  "use strict";

  // ponytail: 起步词典,覆盖主界面/设置/常用按钮;没命中的词条显示原文,按需增补
  const DICT = {
    // —— 主界面 / 面板 ——
    "New Chat": "新对话",
    "New Thread": "新会话",
    "Settings": "设置",
    "Agents": "智能体",
    "Agent": "智能体",
    "AGENTS": "智能体",
    "YOUR AGENTS": "你的智能体",
    "Coordinator": "协调者",
    "Context": "上下文",
    "Changes": "变更",
    "Files": "文件",
    "Spec": "规格",
    "Untitled": "未命名",
    "History": "历史",
    "Workspace": "工作区",
    "Workspaces": "工作区",
    "Terminal": "终端",
    "Editor": "编辑器",
    "View agent tree": "查看智能体树",
    "Agent orchestration": "智能体编排",
    "A coordinator agent breaks down your task into a spec, then delegates work to specialist agents that run in parallel.":
      "协调者智能体把你的任务拆解为规格说明，再分派给并行运行的专职智能体。",
    "The Coordinator can delegate and verify tasks for these agents":
      "协调者可以向这些智能体分派任务并验收结果",
    "Notes about the task, shared with all agents in this space.":
      "关于此任务的笔记，空间内所有智能体共享。",
    "Files changed manually or by agents working in this space.":
      "此空间中手动修改或由智能体修改的文件。",
    "Ask anything or type @ for context": "随便问点什么，或输入 @ 引用上下文",
    "Default model": "默认模型",
    "Response failed": "响应失败",
    "Try again": "重试",
    "Just now": "刚刚",
    "Today": "今天",
    "Yesterday": "昨天",
    "Note": "笔记",
    "Browser": "浏览器",
    "Search...": "搜索…",

    // —— 智能体面板 / 专职智能体(名称与描述来自 resources/specialists/*.md 的 frontmatter) ——
    "Agents working on your task in this space.": "在此空间中为你的任务工作的智能体。",
    "No agents yet": "还没有智能体",
    "Blank Agent": "空白智能体",
    "Start fresh, no custom prompt": "从零开始，无自定义提示词",
    "Specialists": "专职智能体",
    "are pre-configured agent types.": "是预先配置好的智能体类型。",
    "Customize specialists": "自定义专职智能体",
    "Plans work, breaks down tasks, coordinates sub-agents": "规划工作、拆解任务、协调子智能体",
    "Default for agent orchestration": "智能体编排的默认选项",
    "Chief of Staff": "幕僚长",
    "App-level assistant for workspaces, settings, specialists, and learning Intent":
      "应用级助手：负责工作区、设置、专职智能体与 Intent 上手指导",
    "Implementor": "实现者",
    "Executes implementation tasks, writes code": "执行实现任务、编写代码",
    "Developer": "开发者",
    "Plans then implements by itself": "自主规划并实现",
    "PR Reviewer": "PR 审查者",
    "Reviews pull requests with high-confidence, actionable feedback":
      "以高置信度、可执行的意见审查 Pull Request",
    "PR Shepherd": "PR 护航者",
    "Shepherds a PR to merge-ready state by coordinating fixes, CI, and reviews":
      "协调修复、CI 与评审，把 PR 推进到可合并状态",
    "Iterative work/test loop — plans with user, then autonomously works until tests pass":
      "迭代式工作/测试循环——先与用户定计划，再自主工作直到测试通过",
    "UI Designer": "UI 设计师",
    "Creates elegant, accessible, production-ready user interfaces":
      "创建优雅、无障碍、可用于生产的用户界面",
    "Verifier": "验收者",
    "Reviews work and verifies completeness": "审查工作成果并验证完整性",

    // —— 快捷键提示(空面板占位) ——
    "New Agent": "新建智能体",
    "Command Palette": "命令面板",
    "Reopen Closed Tab": "重新打开已关闭的标签页",
    "Cycle through panels": "在面板间循环切换",
    "Split Panel Horizontally": "水平拆分面板",
    "Keyboard shortcuts": "键盘快捷键",

    // —— 通用按钮 / 操作 ——
    "Cancel": "取消",
    "Save": "保存",
    "Delete": "删除",
    "Remove": "移除",
    "Copy": "复制",
    "Copied": "已复制",
    "Copied!": "已复制!",
    "Copy code": "复制代码",
    "Paste": "粘贴",
    "Cut": "剪切",
    "Close": "关闭",
    "Open": "打开",
    "Stop": "停止",
    "Retry": "重试",
    "Refresh": "刷新",
    "Send": "发送",
    "Edit": "编辑",
    "Rename": "重命名",
    "Duplicate": "创建副本",
    "Search": "搜索",
    "New": "新建",
    "Add": "添加",
    "Create": "创建",
    "Continue": "继续",
    "Back": "返回",
    "Next": "下一步",
    "Done": "完成",
    "Apply": "应用",
    "Reset": "重置",
    "Confirm": "确认",
    "Undo": "撤销",
    "Redo": "重做",
    "Share": "分享",
    "Export": "导出",
    "Import": "导入",
    "Archive": "归档",
    "Pin": "置顶",
    "Unpin": "取消置顶",
    "More": "更多",
    "Yes": "是",
    "No": "否",
    "OK": "好",
    "Learn more": "了解更多",
    "Show more": "展开更多",
    "Show less": "收起",
    "Loading...": "加载中…",
    "Loading…": "加载中…",

    // —— 设置页 ——
    "General": "通用",
    "Appearance": "外观",
    "Theme": "主题",
    "Dark": "深色",
    "Light": "浅色",
    "System": "跟随系统",
    "Language": "语言",
    "Account": "账户",
    "Advanced": "高级",
    "Notifications": "通知",
    "Keyboard Shortcuts": "键盘快捷键",
    "Privacy": "隐私",
    "Model": "模型",
    "Models": "模型",
    "About": "关于",
    "Version": "版本",
    "Check for Updates": "检查更新",
    "Sign in": "登录",
    "Sign out": "退出登录",
    "Log out": "退出登录",
    "Quit": "退出",
    "Feedback": "反馈",
    "Documentation": "文档",
    "Help": "帮助",

    // —— 状态 / 提示 ——
    "Error": "错误",
    "Warning": "警告",
    "Unknown error": "未知错误",
    "Something went wrong": "出错了",
    "Not supported": "不支持",
    "Connecting...": "连接中…",
    "Connecting…": "连接中…",
    "Running": "运行中",
    "Completed": "已完成",
    "Failed": "失败",
    "Pending": "等待中",
    "Canceled": "已取消",
    "Cancelled": "已取消",
  };

  // 含变量的文案:[匹配正则, 替换函数]
  const REGEX = [
    [/^\+\s?(\d+) more commits?$/, (m) => `+ 还有 ${m[1]} 个提交`],
    [/^(\d+) more commits?$/, (m) => `还有 ${m[1]} 个提交`],
    [/^(\d+) seconds? ago$/, (m) => `${m[1]} 秒前`],
    [/^(\d+) minutes? ago$/, (m) => `${m[1]} 分钟前`],
    [/^(\d+) hours? ago$/, (m) => `${m[1]} 小时前`],
    [/^(\d+) days? ago$/, (m) => `${m[1]} 天前`],
    [/^(\d+) weeks? ago$/, (m) => `${m[1]} 周前`],
    [/^(\d+) months? ago$/, (m) => `${m[1]} 个月前`],
  ];

  // 用户输入/代码区域不碰
  const SKIP_TAGS = new Set(["SCRIPT", "STYLE", "CODE", "PRE", "TEXTAREA", "INPUT"]);
  const ATTRS = ["placeholder", "title", "aria-label", "alt"];

  function translate(text) {
    const key = text.trim();
    if (!key) return null;
    const hit = DICT[key];
    if (hit !== undefined) return text.replace(key, hit);
    for (const [re, fn] of REGEX) {
      const m = key.match(re);
      if (m) return text.replace(key, fn(m));
    }
    return null;
  }

  function shouldSkip(el) {
    for (let e = el; e; e = e.parentElement) {
      if (SKIP_TAGS.has(e.tagName) || e.isContentEditable) return true;
    }
    return false;
  }

  // 属性翻译不走 SKIP_TAGS:placeholder/title 本身就长在 INPUT 等元素上,
  // 跳过名单只用于保护文本内容(代码块/用户输入)。
  function translateAttrs(el) {
    for (const a of ATTRS) {
      const v = el.getAttribute(a);
      if (v) {
        const t = translate(v);
        if (t !== null && t !== v) el.setAttribute(a, t);
      }
    }
  }

  function walk(root) {
    if (root.nodeType === Node.TEXT_NODE) {
      const parent = root.parentElement;
      if (parent && !shouldSkip(parent)) {
        const t = translate(root.nodeValue);
        if (t !== null && t !== root.nodeValue) root.nodeValue = t;
      }
      return;
    }
    if (root.nodeType !== Node.ELEMENT_NODE) return;
    translateAttrs(root);
    if (root.querySelectorAll) {
      for (const el of root.querySelectorAll("[placeholder],[title],[aria-label],[alt]")) translateAttrs(el);
    }
    if (shouldSkip(root)) return;
    const iter = document.createNodeIterator(root, NodeFilter.SHOW_TEXT);
    let n;
    while ((n = iter.nextNode())) {
      const parent = n.parentElement;
      if (parent && !shouldSkip(parent)) {
        const t = translate(n.nodeValue);
        if (t !== null && t !== n.nodeValue) n.nodeValue = t;
      }
    }
  }

  // Windows 去黑边:应用按 macOS 无边框窗口设计,主内容卡片带外边距和圆角,
  // 露出的窗口底色形成黑框。Windows 下已有原生窗框,把卡片贴满窗口即可。
  // 选择器精确匹配主内容卡片的类组合(全库唯一),不影响弹窗等其他圆角元素。
  function fixWindowChrome() {
    const style = document.createElement("style");
    style.textContent =
      ".panel-layout-container .mr-1\\.5.mb-1\\.5.rounded-xl.bg-sidebar{" +
      "margin-right:0!important;margin-bottom:0!important;border-radius:0!important;}";
    document.head.appendChild(style);
  }

  function start() {
    fixWindowChrome();
    walk(document.body);
    new MutationObserver((muts) => {
      for (const m of muts) {
        if (m.type === "characterData") walk(m.target);
        else if (m.type === "attributes") walk(m.target);
        else for (const node of m.addedNodes) walk(node);
      }
    }).observe(document.documentElement, {
      subtree: true,
      childList: true,
      characterData: true,
      attributes: true,
      attributeFilter: ATTRS,
    });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
