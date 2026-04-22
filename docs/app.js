const siteData = {
  productName: "LocalDrop",
  currentVersion: "1.0.1",
  releaseDate: "April 22, 2026",
  publisher: "Algorithm LLC",
  privacyPolicyUrl: "https://github.com/Algorithm-LLC/local_drop/blob/main/PRIVACY_POLICY.md",
  githubUrl: "https://github.com/Algorithm-LLC/local_drop",
  githubLatestReleaseUrl: "https://github.com/Algorithm-LLC/local_drop/releases/latest",
  supportEmail: "support_algorithm@proton.me",
  releases: [
    {
      id: "google-play",
      channel: "Google Play",
      title: "Android store build",
      platform: "Android",
      version: "0.0.0",
      releaseState: "Public channel",
      note: "Best for mainstream installs, automatic updates, and Play Protect.",
      fileType: "Store listing",
      compatibility: "Android 8.0 and newer",
      ctaLabel: "Open Google Play",
      url: "<GOOGLE_PLAY_URL>",
    },
    {
      id: "app-store",
      channel: "App Store",
      title: "iPhone and iPad store build",
      platform: "iOS / iPadOS",
      version: "0.0.0",
      releaseState: "Public channel",
      note: "Recommended for public iPhone and iPad installs through Apple's store flow.",
      fileType: "Store listing",
      compatibility: "iOS 16 and newer",
      ctaLabel: "Open App Store",
      url: "<APPLE_APP_STORE_URL>",
    },
    {
      id: "ios-ipa",
      channel: "Direct build",
      title: "iPhone .ipa",
      platform: "iOS / iPadOS",
      version: "1.0.1",
      releaseState: "Manual install",
      note: "Useful for sideloading, internal testing, and manual device installs outside the public store flow.",
      fileType: ".ipa",
      compatibility: "iPhone and iPad sideloading workflows",
      ctaLabel: "Download .ipa",
      url: "https://github.com/Algorithm-LLC/local_drop/releases/download/%version%/LocalDrop-ios-%version%.ipa",
    },
    {
      id: "android-apk",
      channel: "Direct build",
      title: "Android APK",
      platform: "Android",
      version: "1.0.1",
      releaseState: "Manual install",
      note: "Useful for staged rollouts, internal teams, and direct QA distribution.",
      fileType: "APK package",
      compatibility: "ARM64 and compatible devices",
      ctaLabel: "Download APK",
      url: "https://github.com/Algorithm-LLC/local_drop/releases/download/%version%/LocalDrop-android-%version%.apk",
    },
    {
      id: "windows",
      channel: "Desktop build",
      title: "Windows",
      platform: "Windows",
      version: "1.0.1",
      releaseState: "Direct download",
      note: "Package this as an installer or archive for your Windows release channel.",
      fileType: "EXE or ZIP",
      compatibility: "Windows 10 and newer",
      ctaLabel: "Download .zip",
      url: "https://github.com/Algorithm-LLC/local_drop/releases/download/%version%/LocalDrop-win-%version%.zip",
    },
    {
      id: "macos",
      channel: "Desktop build",
      title: "macOS",
      platform: "macOS",
      version: "1.0.1",
      releaseState: "Direct download",
      note: "Use this for notarized macOS releases, beta packages, or direct distribution.",
      fileType: "DMG or ZIP",
      compatibility: "Apple Silicon and Intel, as packaged",
      ctaLabel: "Download .dmg",
      url: "https://github.com/Algorithm-LLC/local_drop/releases/download/%version%/LocalDrop-macos-%version%.dmg",
    },
    {
      id: "linux-appimage",
      channel: "Desktop build",
      title: "Linux AppImage",
      platform: "Linux",
      version: "1.0.1",
      releaseState: "Direct download",
      note: "Best for portable Linux installs with a single downloadable build.",
      fileType: "AppImage",
      compatibility: "Desktop Linux environments",
      ctaLabel: "Download .AppImage",
      url: "https://github.com/Algorithm-LLC/local_drop/releases/download/%version%/LocalDrop-linux-%version%.AppImage",
    },
    {
      id: "linux-tar-gz",
      channel: "Desktop build",
      title: "Linux .tar.gz",
      platform: "Linux",
      version: "1.0.1",
      releaseState: "Direct download",
      note: "Use this for archive-based Linux distribution or manual extraction installs.",
      fileType: ".tar.gz",
      compatibility: "Desktop Linux environments",
      ctaLabel: "Download .tar.gz",
      url: "https://github.com/Algorithm-LLC/local_drop/releases/download/%version%/LocalDrop-linux-%version%.tar.gz",
    },
  ],
};

const placeholderPrefix = "<";

function resolveVersionTokens(value, release = null) {
  if (!value) {
    return value;
  }

  const sourceVersion = `${release?.version ?? siteData.currentVersion}`.trim();
  const plainVersion = sourceVersion.replace(/^v/i, "");
  const version = sourceVersion.startsWith("v")
    ? sourceVersion
    : `v${plainVersion}`;

  return value
    .replaceAll("%version%", version)
    .replaceAll("%plainVersion%", plainVersion);
}

function isRealUrl(url) {
  return Boolean(url) && !url.startsWith(placeholderPrefix) && url !== "#";
}

function bindLink(id, url, fallback = "#", release = null) {
  const element = document.getElementById(id);
  if (!element) {
    return;
  }

  const resolvedUrl = resolveVersionTokens(url, release);

  if (isRealUrl(resolvedUrl)) {
    element.href = resolvedUrl;
    if (resolvedUrl.startsWith("http")) {
      element.target = "_blank";
      element.rel = "noreferrer";
    }
    return;
  }

  element.href = fallback;
  element.setAttribute("aria-disabled", "true");
  element.classList.add("is-disabled");
}

function renderReleaseCard(release) {
  const resolvedUrl = resolveVersionTokens(release.url, release);
  const ready = isRealUrl(resolvedUrl);
  const actionAttributes = ready
    ? `href="${resolvedUrl}" target="_blank" rel="noreferrer"`
    : `href="#" aria-disabled="true"`;
  const actionClasses = ready
    ? "button button-primary"
    : "button button-primary is-disabled";

  return `
    <article class="release-card">
      <div class="release-head">
        <div>
          <span class="release-channel">${release.channel}</span>
          <h3>${release.title}</h3>
          <p class="release-subtitle">${release.platform}</p>
        </div>
        <span class="release-state ${ready ? "is-ready" : ""}">
          ${release.version}
        </span>
      </div>

      <div>
        <p class="release-build-note">${release.note}</p>
      </div>

      <div class="release-meta">
        <div class="release-meta-block">
          <span class="release-meta-label">Package</span>
          <div class="release-meta-value">${release.fileType}</div>
        </div>
        <div class="release-meta-block">
          <span class="release-meta-label">Compatibility</span>
          <div class="release-meta-value">${release.compatibility}</div>
        </div>
      </div>

      <div class="release-footer">
        <span class="release-platform">${release.releaseState}</span>
        <a class="${actionClasses}" ${actionAttributes}>${release.ctaLabel}</a>
      </div>
    </article>
  `;
}

function applySiteData() {
  document.getElementById("heroVersion").textContent = siteData.currentVersion;
  document.getElementById("toolbarVersion").textContent = siteData.currentVersion;
  document.getElementById("footerVersion").textContent = `Version ${siteData.currentVersion}`;
  document.getElementById("heroReleaseDate").textContent = siteData.releaseDate;
  document.getElementById("footerPublisher").textContent = siteData.publisher;
  document.getElementById("footerYear").textContent = new Date().getFullYear();

  const play = siteData.releases.find((item) => item.id === "google-play");
  const appStore = siteData.releases.find((item) => item.id === "app-store");

  if (play) {
    document.getElementById("playVersionLabel").textContent = play.version;
  }
  if (appStore) {
    document.getElementById("appStoreVersionLabel").textContent = appStore.version;
  }

  bindLink("privacyLink", siteData.privacyPolicyUrl);
  bindLink("footerPrivacyLink", siteData.privacyPolicyUrl);
  bindLink("githubReleasesLink", siteData.githubLatestReleaseUrl);
  bindLink("footerGithubLink", siteData.githubUrl);

  const supportHref = siteData.supportEmail.startsWith("mailto:")
    ? siteData.supportEmail
    : `mailto:${siteData.supportEmail}`;
  bindLink(
    "footerSupportLink",
    siteData.supportEmail.startsWith("<") ? "#" : supportHref,
  );

  document.getElementById("downloadGrid").innerHTML = siteData.releases
    .map(renderReleaseCard)
    .join("");
}

applySiteData();
