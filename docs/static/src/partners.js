// Footer "Our partners" carousel.
// Add a catalog by appending one object to PARTNERS:
//   official: { href, alt, w, h, light, dark } or { href, alt, w, h, src }
//   local:    { href, alt, w, h, local }  → static/assets/badges/<local>.svg and <local>-dark.svg
// Optional fields: title, loading.
const PARTNERS = [
  { href: "https://macoscleaner.macupdate.com/", alt: "Listed on MacUpdate", local: "macupdate", w: 122, h: 40 },
  { href: "https://alternativeto.net/software/macoscleaner/about/?utm_source=badge&utm_medium=referral", alt: "MacOSCleaner | AlternativeTo", light: "https://alternativeto.net/static/badges/badge-compact-light.svg", dark: "https://alternativeto.net/static/badges/badge-compact-dark.svg", w: 244, h: 83 },
  { href: "https://macworthy.com/apps/macos-cleaner/", alt: "Listed on MacWorthy", local: "macworthy", w: 122, h: 40 },
  { href: "https://macigniter.com/apps/macos-cleaner", alt: "Listed on MacIgniter", local: "macigniter", w: 116, h: 40 },
  { href: "https://macappindex.com/apps/macos-cleaner?ref=badge", title: "MacOS Cleaner on Mac App Index", alt: "MacOS Cleaner on Mac App Index", light: "https://macappindex.com/apps/macos-cleaner/badge.svg?theme=light&height=40", dark: "https://macappindex.com/apps/macos-cleaner/badge.svg?theme=dark&height=40", w: 160, h: 40 },
  { href: "https://allmacapps.com/app/macoscleaner", alt: "MacOSCleaner on All Mac Apps", light: "https://badges.allmacapps.com/macoscleaner.svg", dark: "https://badges.allmacapps.com/macoscleaner.svg?theme=dark", w: 208, h: 48 },
  { href: "https://macnative.io/apps/macoscleaner?utm_source=macnative-badge&utm_medium=referral", alt: "Listed on MacNative", light: "https://macnative.io/badge?kind=listed&theme=light&slug=macoscleaner&small=1&rounded=1", dark: "https://macnative.io/badge?kind=listed&theme=dark&slug=macoscleaner&small=1&rounded=1", w: 168, h: 44 },
  { href: "https://www.saashub.com/macoscleaner?utm_source=badge&utm_campaign=badge&utm_content=macoscleaner&badge_variant=color&badge_kind=approved", alt: "MacOSCleaner badge", light: "https://cdn-b.saashub.com/img/badges/approved-color.png?v=1", dark: "https://cdn-b.saashub.com/img/badges/approved-dark.png?v=1", w: 300, h: 100 },
  { href: "https://www.oldergeeks.com/downloads/file.php?id=5046", alt: "Listed on OlderGeeks", local: "oldergeeks", w: 122, h: 40 },
  { href: "https://opendmg.app/apps/cleaner/", alt: "Listed on OpenDMG", local: "opendmg", w: 114, h: 40 },
  { href: "https://macpip.com/apps/macos-cleaner?ref=badge", alt: "Listed on MacPip", light: "https://macpip.com/badge/macos-cleaner.svg?theme=light", dark: "https://macpip.com/badge/macos-cleaner.svg?theme=dark", w: 174, h: 58 },
  { href: "https://www.no-subscription.com/apps/macoscleaner", alt: "Listed on no-subscription.com", local: "no-subscription", w: 180, h: 40 },
  { href: "https://www.mactools.pro", alt: "Listed on MacTools Pro", light: "https://www.mactools.pro/mactools-badge-light.svg", dark: "https://www.mactools.pro/mactools-badge-dark.svg", w: 240, h: 60 },
];

(function () {
  const marquee = document.querySelector("[data-partners-marquee]");
  if (!marquee) return;

  const motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");

  function badgeBase() {
    const script = document.querySelector("script[src*='partners.js']");
    const src = script ? script.getAttribute("src") : "static/src/partners.js";
    return src.replace(/src\/partners\.js(?:\?[^#]*)?$/, "assets/badges/");
  }

  const base = badgeBase();

  function image(src, alt, partner, className, loading) {
    const img = document.createElement("img");
    img.src = src;
    img.alt = alt;
    img.width = partner.w;
    img.height = partner.h;
    if (className) img.className = className;
    if (loading) img.loading = loading;
    return img;
  }

  function partnerLink(partner, decorative) {
    const link = document.createElement("a");
    link.href = partner.href;
    link.target = "_blank";
    link.rel = "noopener";
    if (!decorative && partner.title) link.title = partner.title;
    if (decorative) link.tabIndex = -1;
    const alt = decorative ? "" : partner.alt;
    const loading = decorative ? "eager" : partner.loading;
    if (partner.local) {
      link.appendChild(image(base + partner.local + ".svg", alt, partner, "badge-for-light", loading));
      link.appendChild(image(base + partner.local + "-dark.svg", alt, partner, "badge-for-dark", loading));
    } else if (partner.light) {
      link.appendChild(image(partner.light, alt, partner, "badge-for-light", loading));
      link.appendChild(image(partner.dark, alt, partner, "badge-for-dark", loading));
    } else {
      link.appendChild(image(partner.src, alt, partner, "", loading));
    }
    return link;
  }

  function awesomeGroup(partner, decorative) {
    const group = document.createElement("div");
    group.className = "partner-awesome";
    const kicker = document.createElement("span");
    kicker.className = "partner-awesome-kicker";
    kicker.textContent = partner.group;
    group.appendChild(kicker);
    const links = document.createElement("span");
    links.className = "partner-awesome-links";
    partner.links.forEach((item, index) => {
      if (index > 0) {
        const sep = document.createElement("span");
        sep.className = "partner-awesome-sep";
        sep.setAttribute("aria-hidden", "true");
        sep.textContent = "·";
        links.appendChild(sep);
      }
      const link = document.createElement("a");
      link.href = item.href;
      link.target = "_blank";
      link.rel = "noopener";
      link.textContent = item.label;
      if (decorative) link.tabIndex = -1;
      links.appendChild(link);
    });
    group.appendChild(links);
    return group;
  }

  function buildSet(decorative) {
    const list = document.createElement("ul");
    list.className = "footer-partners-set";
    if (decorative) {
      list.setAttribute("aria-hidden", "true");
      list.inert = true;
    }
    PARTNERS.forEach((partner) => {
      const item = document.createElement("li");
      item.appendChild(partner.group ? awesomeGroup(partner, decorative) : partnerLink(partner, decorative));
      list.appendChild(item);
    });
    return list;
  }

  const track = document.createElement("div");
  track.className = "footer-partners-track";
  track.appendChild(buildSet(false));
  track.appendChild(buildSet(true));
  marquee.appendChild(track);

  function currentX() {
    const transform = getComputedStyle(track).transform;
    if (!transform || transform === "none") return 0;
    return new DOMMatrixReadOnly(transform).m41;
  }

  function clearShift() {
    track.style.animation = "";
    track.style.transform = "";
  }

  marquee.addEventListener("focusin", (event) => {
    const link = event.target.closest("a");
    if (!link || motionQuery.matches || link.closest("[aria-hidden='true']")) return;
    const box = marquee.getBoundingClientRect();
    const group = link.closest(".partner-awesome");
    const groupBox = group ? group.getBoundingClientRect() : null;
    const target = groupBox && groupBox.width <= box.width - 32 ? group : link;
    const rect = target.getBoundingClientRect();
    const pad = 12;
    let dx = 0;
    if (rect.left < box.left + pad) dx = box.left + pad - rect.left;
    else if (rect.right > box.right - pad) dx = box.right - pad - rect.right;
    if (!dx) return;
    const x = currentX() + dx;
    track.style.animation = "none";
    track.style.transform = "translate3d(" + x + "px,0,0)";
    marquee.scrollLeft = 0;
  });

  marquee.addEventListener("focusout", (event) => {
    if (marquee.contains(event.relatedTarget)) return;
    clearShift();
  });

  motionQuery.addEventListener("change", () => {
    if (motionQuery.matches) clearShift();
  });
})();
