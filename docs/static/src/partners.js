// Footer "Our partners" carousel.
// The list is static HTML in .footer-partners-set. This script clones it
// into a second, decorative copy so the row can scroll as a seamless loop.
// Add a partner by appending an <li><a>…</a></li> to that list on each page.
(function () {
  const marquee = document.querySelector("[data-partners-marquee]");
  if (!marquee) return;

  const source = marquee.querySelector(":scope > .footer-partners-set");
  if (!source) return;

  const motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");

  const decorative = source.cloneNode(true);
  decorative.setAttribute("aria-hidden", "true");
  decorative.inert = true;
  decorative.querySelectorAll("a").forEach((link) => {
    link.tabIndex = -1;
    link.removeAttribute("title");
  });
  decorative.querySelectorAll("img").forEach((img) => {
    img.alt = "";
    img.loading = "eager";
  });

  const track = document.createElement("div");
  track.className = "footer-partners-track";
  track.appendChild(source);
  track.appendChild(decorative);
  marquee.replaceChildren(track);

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
