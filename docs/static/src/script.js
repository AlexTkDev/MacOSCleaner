let slideIndex = 0;
const slides = document.querySelectorAll('.carousel-slide');
const tabs = document.querySelectorAll('.shot-tabs .shot-tab');
const track = document.querySelector('.carousel-track');
const viewport = document.querySelector('.shot-viewport');

function syncViewportHeight() {
  if (!viewport) return;
  const currentSlide = slides[slideIndex];
  if (!currentSlide) return;
  const img = currentSlide.querySelector('img');
  if (!img) return;

  const apply = () => {
    if (!img.naturalWidth) return;
    let height;
    if (currentSlide.classList.contains('carousel-slide--compact')) {
      const rendered = img.offsetHeight;
      height = rendered > 0 ? rendered + 24 : Math.min(640, viewport.clientWidth * 0.75);
    } else {
      height = viewport.clientWidth * (img.naturalHeight / img.naturalWidth);
    }
    viewport.style.height = `${Math.round(height)}px`;
  };

  if (img.complete && img.naturalWidth) {
    apply();
  } else {
    img.addEventListener('load', apply, { once: true });
  }
}

const demoVideo = document.getElementById('demo-video');

function updateCarousel() {
  if (!track || slides.length === 0) return;
  track.style.transform = `translateX(-${slideIndex * 100}%)`;
  tabs.forEach((tab, i) => {
    const on = i === slideIndex;
    tab.classList.toggle('active', on);
    if (on) tab.setAttribute('aria-current', 'true');
    else tab.removeAttribute('aria-current');
  });
  syncViewportHeight();
  // Play/pause demo video based on active slide
  if (demoVideo) {
    if (slideIndex === 0) {
      demoVideo.play().catch(() => {});
    } else {
      demoVideo.pause();
    }
  }
}

function goToSlide(n) {
  slideIndex = (n + slides.length) % slides.length;
  updateCarousel();
}

if (demoVideo) {
  demoVideo.addEventListener('click', () => {
    if (demoVideo.paused) demoVideo.play().catch(() => {});
    else demoVideo.pause();
  });
}

tabs.forEach(tab => {
  tab.addEventListener('click', () => goToSlide(Number(tab.dataset.index)));
});

const shotPrev = document.getElementById('shot-prev');
const shotNext = document.getElementById('shot-next');

if (shotPrev) shotPrev.addEventListener('click', () => goToSlide(slideIndex - 1));
if (shotNext) shotNext.addEventListener('click', () => goToSlide(slideIndex + 1));

window.addEventListener('resize', syncViewportHeight);
updateCarousel();

document.addEventListener('keydown', (e) => {
  const screenshots = document.getElementById('screenshots');
  const imageModal = document.getElementById('image-modal');
  if (!screenshots || imageModal?.classList.contains('show')) return;
  const inView = screenshots.getBoundingClientRect().top < window.innerHeight
    && screenshots.getBoundingClientRect().bottom > 0;
  if (!inView) return;
  if (e.key === 'ArrowRight') goToSlide(slideIndex + 1);
  if (e.key === 'ArrowLeft') goToSlide(slideIndex - 1);
});

// Theme toggle
const themeToggle = document.getElementById('theme-toggle');
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
let themeTransitionTimer = 0;

function syncThemeToggleLabel(theme) {
  if (!themeToggle) return;
  themeToggle.setAttribute(
    'aria-label',
    theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme'
  );
}

function applyTheme(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  localStorage.setItem('theme', theme);
  syncThemeToggleLabel(theme);
}

function setTheme(theme, { animate = true } = {}) {
  if (!animate || reduceMotion.matches) {
    applyTheme(theme);
    return;
  }

  const root = document.documentElement;

  if (typeof document.startViewTransition === 'function') {
    document.startViewTransition(() => applyTheme(theme));
    return;
  }

  root.classList.add('theme-transition');
  applyTheme(theme);
  clearTimeout(themeTransitionTimer);
  themeTransitionTimer = window.setTimeout(() => {
    root.classList.remove('theme-transition');
  }, 500);
}

syncThemeToggleLabel(document.documentElement.getAttribute('data-theme') || 'light');

if (themeToggle) {
  themeToggle.addEventListener('click', () => {
    const next = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    setTheme(next);
  });
}

window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
  if (localStorage.getItem('theme')) return;
  setTheme(e.matches ? 'dark' : 'light');
});

// Mobile nav
const nav = document.getElementById('main-nav');
const navToggle = document.getElementById('nav-toggle');

if (nav && navToggle) {
  navToggle.addEventListener('click', (e) => {
    e.stopPropagation();
    nav.classList.toggle('open');
  });

  document.addEventListener('click', (e) => {
    if (nav.classList.contains('open') && !nav.contains(e.target)) {
      nav.classList.remove('open');
    }
  });

  nav.querySelectorAll('a').forEach(link => {
    link.addEventListener('click', () => {
      nav.classList.remove('open');
    });
  });
}

// Carousel swipe
let touchStartX = 0;
let touchEndX = 0;

if (track) {
  track.addEventListener('touchstart', (e) => {
    touchStartX = e.changedTouches[0].screenX;
  }, { passive: true });

  track.addEventListener('touchend', (e) => {
    touchEndX = e.changedTouches[0].screenX;
    handleGesture();
  }, { passive: true });
}

function handleGesture() {
  const threshold = 50;
  if (touchEndX < touchStartX - threshold) goToSlide(slideIndex + 1);
  if (touchEndX > touchStartX + threshold) goToSlide(slideIndex - 1);
}

// Reveal on scroll
const revealEls = document.querySelectorAll('.reveal');

if ('IntersectionObserver' in window && revealEls.length > 0) {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('in');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.12 });

  revealEls.forEach(el => observer.observe(el));
} else {
  revealEls.forEach(el => el.classList.add('in'));
}

// Screenshot modal
const modal = document.getElementById('image-modal');
const modalImg = document.getElementById('modal-img');
const modalClose = document.getElementById('modal-close');

if (modal && modalImg && modalClose) {
  const updateModalImage = () => {
    if (slides[slideIndex]) {
      const img = slides[slideIndex].querySelector('img');
      modalImg.src = img ? img.src : '';
      modalImg.alt = img && img.alt ? `Zoomed: ${img.alt}` : 'Zoomed screenshot';
      updateCarousel();
    }
  };

  const closeModal = () => {
    modal.classList.remove('show');
    modal.setAttribute('aria-hidden', 'true');
    setTimeout(() => {
      modal.style.display = 'none';
      modalImg.src = '';
      modalImg.alt = 'Zoomed screenshot';
    }, 300);
    document.body.style.overflow = '';
  };

  const openModal = (index) => {
    slideIndex = index;
    updateModalImage();
    modal.style.display = 'flex';
    modal.setAttribute('aria-hidden', 'false');
    requestAnimationFrame(() => modal.classList.add('show'));
    document.body.style.overflow = 'hidden';
  };

  slides.forEach((slide, index) => {
    slide.addEventListener('click', () => {
      if (!slide.classList.contains('carousel-slide--video')) {
        openModal(index);
      }
    });
  });

  modalClose.addEventListener('click', closeModal);
  modalClose.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      closeModal();
    }
  });

  modal.addEventListener('click', (e) => {
    if (e.target === modal) closeModal();
  });

  let modalTouchStartX = 0;
  let modalTouchEndX = 0;

  const navigateModal = (direction) => {
    let nextIndex = slideIndex + direction;
    if (nextIndex >= slides.length) nextIndex = 0;
    if (nextIndex < 0) nextIndex = slides.length - 1;
    
    // Skip video slides in modal
    while (slides[nextIndex] && slides[nextIndex].classList.contains('carousel-slide--video')) {
      nextIndex += direction;
      if (nextIndex >= slides.length) nextIndex = 0;
      if (nextIndex < 0) nextIndex = slides.length - 1;
    }
    
    goToSlide(nextIndex);
    updateModalImage();
  };

  modal.addEventListener('touchstart', (e) => {
    modalTouchStartX = e.changedTouches[0].screenX;
  }, { passive: true });

  modal.addEventListener('touchend', (e) => {
    modalTouchEndX = e.changedTouches[0].screenX;
    const threshold = 50;
    if (modalTouchEndX < modalTouchStartX - threshold) {
      navigateModal(1);
    }
    if (modalTouchEndX > modalTouchStartX + threshold) {
      navigateModal(-1);
    }
  }, { passive: true });

  document.addEventListener('keydown', (e) => {
    if (!modal.classList.contains('show')) return;
    if (e.key === 'ArrowRight') {
      navigateModal(1);
    } else if (e.key === 'ArrowLeft') {
      navigateModal(-1);
    } else if (e.key === 'Escape') {
      closeModal();
    }
  });

  const modalPrev = document.getElementById('modal-prev');
  const modalNext = document.getElementById('modal-next');

  if (modalPrev && modalNext) {
    modalPrev.addEventListener('click', (e) => {
      e.stopPropagation();
      navigateModal(-1);
    });
    modalNext.addEventListener('click', (e) => {
      e.stopPropagation();
      navigateModal(1);
    });
  }
}

// Hero background cursor tracking with trailing effect
const heroSection = document.querySelector('.hero');
if (heroSection) {
  let mouseX = 0;
  let mouseY = 0;
  let currentX = 0;
  let currentY = 0;
  let isHovering = false;
  
  heroSection.addEventListener('mousemove', (e) => {
    const rect = heroSection.getBoundingClientRect();
    mouseX = e.clientX - rect.left;
    mouseY = e.clientY - rect.top;
  }, { passive: true });

  heroSection.addEventListener('mouseenter', () => {
    isHovering = true;
  });

  heroSection.addEventListener('mouseleave', () => {
    isHovering = false;
  });

  function animateHeroDots() {
    if (isHovering) {
      currentX += (mouseX - currentX) * 0.08;
      currentY += (mouseY - currentY) * 0.08;
      heroSection.style.setProperty('--mouse-x', `${currentX}px`);
      heroSection.style.setProperty('--mouse-y', `${currentY}px`);
    }
    requestAnimationFrame(animateHeroDots);
  }
  animateHeroDots();
}

// Crypto modal (dynamically injected single component)
const CRYPTO_MODAL_HTML = `
<div id="crypto-modal" class="modal" role="dialog" aria-modal="true" aria-hidden="true" style="align-items: center; justify-content: center;">
  <div style="background: var(--bg-elevated); padding: 32px; border-radius: var(--radius); border: 1px solid var(--line); max-width: 95%; width: 520px; text-align: center; position: relative; box-shadow: var(--shadow-window);">
    <span class="modal-close" id="crypto-modal-close" role="button" tabindex="0" aria-label="Close" style="top: 16px; right: 20px; font-size: 28px; color: var(--text-muted); cursor: pointer;">&times;</span>
    
    <h3 style="margin-bottom: 20px; font-size: 1.2rem; font-weight: 600; letter-spacing: -0.02em;">Donate Crypto</h3>
    
    <div style="display: flex; justify-content: center; gap: 6px; margin-bottom: 24px; flex-wrap: wrap;" id="crypto-tabs">
      <button class="shot-tab active" data-crypto="usdt-trc20" style="display: inline-flex; align-items: center; gap: 5px;">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#26A17B"/><path d="M13.5 10.5V8.5H18V6H6V8.5H10.5V10.5C7.5 10.7 5.5 11.5 5.5 12.5C5.5 13.5 7.5 14.3 10.5 14.5V18H13.5V14.5C16.5 14.3 18.5 13.5 18.5 12.5C18.5 11.5 16.5 10.7 13.5 10.5ZM12 13.3C9.3 13.3 7.8 12.7 7.8 12.5C7.8 12.3 9.3 11.7 12 11.7C14.7 11.7 16.2 12.3 16.2 12.5C16.2 12.7 14.7 13.3 12 13.3Z" fill="white"/></svg>
        USDT (TRC20)
      </button>
      <button class="shot-tab" data-crypto="usdt-bep20" style="display: inline-flex; align-items: center; gap: 5px;">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#26A17B"/><path d="M13.5 10.5V8.5H18V6H6V8.5H10.5V10.5C7.5 10.7 5.5 11.5 5.5 12.5C5.5 13.5 7.5 14.3 10.5 14.5V18H13.5V14.5C16.5 14.3 18.5 13.5 18.5 12.5C18.5 11.5 16.5 10.7 13.5 10.5ZM12 13.3C9.3 13.3 7.8 12.7 7.8 12.5C7.8 12.3 9.3 11.7 12 11.7C14.7 11.7 16.2 12.3 16.2 12.5C16.2 12.7 14.7 13.3 12 13.3Z" fill="white"/></svg>
        USDT (BEP20)
      </button>
      <button class="shot-tab" data-crypto="usdt-ton" style="display: inline-flex; align-items: center; gap: 5px;">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#26A17B"/><path d="M13.5 10.5V8.5H18V6H6V8.5H10.5V10.5C7.5 10.7 5.5 11.5 5.5 12.5C5.5 13.5 7.5 14.3 10.5 14.5V18H13.5V14.5C16.5 14.3 18.5 13.5 18.5 12.5C18.5 11.5 16.5 10.7 13.5 10.5ZM12 13.3C9.3 13.3 7.8 12.7 7.8 12.5C7.8 12.3 9.3 11.7 12 11.7C14.7 11.7 16.2 12.3 16.2 12.5C16.2 12.7 14.7 13.3 12 13.3Z" fill="white"/></svg>
        USDT (TON)
      </button>
      <button class="shot-tab" data-crypto="btc" style="display: inline-flex; align-items: center; gap: 5px;">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#F7931A"/><path d="M14.7 10.5C15.1 10.1 15.3 9.5 15.2 8.8C15 7.6 13.9 6.8 12.5 6.8H9V17H13.2C14.7 17 15.8 16.1 16 14.7C16.1 13.7 15.6 12.8 14.7 12.4C15.2 12 15.4 11.2 14.7 10.5ZM11 8.5H12.5C13 8.5 13.5 8.9 13.5 9.4C13.5 9.9 13.1 10.3 12.5 10.3H11V8.5ZM13 15.2H11V12.1H13C13.6 12.1 14.1 12.6 14.1 13.2C14.1 13.8 13.6 15.2 13 15.2Z" fill="white"/></svg>
        BTC
      </button>
      <button class="shot-tab" data-crypto="sol" style="display: inline-flex; align-items: center; gap: 5px;">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#9945FF"/><path d="M7 15.5L8.5 14H17L15.5 15.5H7ZM7 11.5L8.5 10H17L15.5 11.5H7ZM7 7.5L8.5 9H17L15.5 7.5H7Z" stroke="white" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
        SOL
      </button>
      <button class="shot-tab" data-crypto="eth" style="display: inline-flex; align-items: center; gap: 5px;">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#627EEA"/><path d="M12 4L6.5 13L12 16.5L17.5 13L12 4Z" fill="white" fill-opacity="0.9"/><path d="M12 17.5L6.5 14L12 20L17.5 14L12 17.5Z" fill="white"/></svg>
        ETH
      </button>
      <button class="shot-tab" data-crypto="bnb" style="display: inline-flex; align-items: center; gap: 5px;">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#F3BA2F"/><path d="M12 6L14.2 8.2L12 10.4L9.8 8.2L12 6ZM7.8 10.2L10 12.4L7.8 14.6L5.6 12.4L7.8 10.2ZM16.2 10.2L18.4 12.4L16.2 14.6L14 12.4L16.2 10.2ZM12 14.4L14.2 16.6L12 18.8L9.8 16.6L12 14.4ZM12 11.2L13.2 12.4L12 13.6L10.8 12.4L12 11.2Z" fill="white"/></svg>
        BNB
      </button>
      <button class="shot-tab" data-crypto="trx" style="display: inline-flex; align-items: center; gap: 5px;">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#EF0027"/><path d="M6.5 7.5L17.5 6L14.5 18L6.5 7.5ZM8.5 9L13.5 15.5L15.5 8L8.5 9Z" fill="white"/></svg>
        TRX
      </button>
      <button class="shot-tab" data-crypto="binance-pay" style="display: inline-flex; align-items: center; gap: 5px;">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#F3BA2F"/><path d="M12 6L14.2 8.2L12 10.4L9.8 8.2L12 6ZM7.8 10.2L10 12.4L7.8 14.6L5.6 12.4L7.8 10.2ZM16.2 10.2L18.4 12.4L16.2 14.6L14 12.4L16.2 10.2ZM12 14.4L14.2 16.6L12 18.8L9.8 16.6L12 14.4ZM12 11.2L13.2 12.4L12 13.6L10.8 12.4L12 11.2Z" fill="white"/></svg>
        Binance Pay
      </button>
    </div>
    
    <div id="crypto-usdt-trc20" class="crypto-panel">
      <div style="background: #1e2329; border-radius: 16px; padding: 24px 20px; max-width: 320px; margin: 0 auto 20px; border: 1px solid #2b313a; box-shadow: 0 8px 24px rgba(0,0,0,0.3); text-align: center;">
        <div style="display: flex; align-items: center; justify-content: center; gap: 8px; margin-bottom: 10px; color: #26A17B; font-weight: 700; font-size: 1.05rem; letter-spacing: 0.05em;">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#26A17B"/><path d="M13.5 10.5V8.5H18V6H6V8.5H10.5V10.5C7.5 10.7 5.5 11.5 5.5 12.5C5.5 13.5 7.5 14.3 10.5 14.5V18H13.5V14.5C16.5 14.3 18.5 13.5 18.5 12.5C18.5 11.5 16.5 10.7 13.5 10.5ZM12 13.3C9.3 13.3 7.8 12.7 7.8 12.5C7.8 12.3 9.3 11.7 12 11.7C14.7 11.7 16.2 12.3 16.2 12.5C16.2 12.7 14.7 13.3 12 13.3Z" fill="white"/></svg>
          USDT (TRC20)
        </div>
        <p style="font-size: 0.78rem; color: #848e9c; margin-bottom: 16px;">TRON Network (Low Fee)</p>
        <div style="position: relative; width: 220px; height: 220px; margin: 0 auto; background: #ffffff; padding: 8px; border-radius: 12px; display: flex; align-items: center; justify-content: center;">
          <img src="static/assets/crypto/USDT%20(TRC20).webp" alt="USDT TRC20 QR" style="width: 100%; height: 100%; display: block; border-radius: 4px; object-fit: contain;">
        </div>
      </div>
      <p style="font-family: var(--font-mono); font-size: 0.78rem; word-break: break-all; margin-bottom: 16px; padding: 12px; background: var(--bg); border-radius: 8px; border: 1px solid var(--line); user-select: all; color: var(--text-muted);">TAQBrzZuAvJ5Zga7touVzNGXXJykEVp7sp</p>
      <a href="tron:TAQBrzZuAvJ5Zga7touVzNGXXJykEVp7sp" class="btn btn-primary" style="width: 100%; justify-content: center; border-radius: 8px;">Open Wallet</a>
    </div>
    
    <div id="crypto-usdt-bep20" class="crypto-panel" style="display: none;">
      <div style="background: #1e2329; border-radius: 16px; padding: 24px 20px; max-width: 320px; margin: 0 auto 20px; border: 1px solid #2b313a; box-shadow: 0 8px 24px rgba(0,0,0,0.3); text-align: center;">
        <div style="display: flex; align-items: center; justify-content: center; gap: 8px; margin-bottom: 10px; color: #26A17B; font-weight: 700; font-size: 1.05rem; letter-spacing: 0.05em;">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#26A17B"/><path d="M13.5 10.5V8.5H18V6H6V8.5H10.5V10.5C7.5 10.7 5.5 11.5 5.5 12.5C5.5 13.5 7.5 14.3 10.5 14.5V18H13.5V14.5C16.5 14.3 18.5 13.5 18.5 12.5C18.5 11.5 16.5 10.7 13.5 10.5ZM12 13.3C9.3 13.3 7.8 12.7 7.8 12.5C7.8 12.3 9.3 11.7 12 11.7C14.7 11.7 16.2 12.3 16.2 12.5C16.2 12.7 14.7 13.3 12 13.3Z" fill="white"/></svg>
          USDT (BEP20)
        </div>
        <p style="font-size: 0.78rem; color: #848e9c; margin-bottom: 16px;">BNB Smart Chain (Low Fee)</p>
        <div style="position: relative; width: 220px; height: 220px; margin: 0 auto; background: #ffffff; padding: 8px; border-radius: 12px; display: flex; align-items: center; justify-content: center;">
          <img src="static/assets/crypto/USDT%20(BEP20%20%3A%20BNB%20Smart%20Chain).webp" alt="USDT BEP20 QR" style="width: 100%; height: 100%; display: block; border-radius: 4px; object-fit: contain;">
        </div>
      </div>
      <p style="font-family: var(--font-mono); font-size: 0.78rem; word-break: break-all; margin-bottom: 16px; padding: 12px; background: var(--bg); border-radius: 8px; border: 1px solid var(--line); user-select: all; color: var(--text-muted);">0x04b972bD6deF9d97bEe305CC22FED8f04D9BcAC4</p>
      <a href="ethereum:0x04b972bD6deF9d97bEe305CC22FED8f04D9BcAC4" class="btn btn-primary" style="width: 100%; justify-content: center; border-radius: 8px;">Open Wallet</a>
    </div>

    <div id="crypto-usdt-ton" class="crypto-panel" style="display: none;">
      <div style="background: #1e2329; border-radius: 16px; padding: 24px 20px; max-width: 320px; margin: 0 auto 20px; border: 1px solid #2b313a; box-shadow: 0 8px 24px rgba(0,0,0,0.3); text-align: center;">
        <div style="display: flex; align-items: center; justify-content: center; gap: 8px; margin-bottom: 10px; color: #26A17B; font-weight: 700; font-size: 1.05rem; letter-spacing: 0.05em;">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#26A17B"/><path d="M13.5 10.5V8.5H18V6H6V8.5H10.5V10.5C7.5 10.7 5.5 11.5 5.5 12.5C5.5 13.5 7.5 14.3 10.5 14.5V18H13.5V14.5C16.5 14.3 18.5 13.5 18.5 12.5C18.5 11.5 16.5 10.7 13.5 10.5ZM12 13.3C9.3 13.3 7.8 12.7 7.8 12.5C7.8 12.3 9.3 11.7 12 11.7C14.7 11.7 16.2 12.3 16.2 12.5C16.2 12.7 14.7 13.3 12 13.3Z" fill="white"/></svg>
          USDT (TON)
        </div>
        <p style="font-size: 0.78rem; color: #848e9c; margin-bottom: 16px;">TON Network (Low Fee)</p>
        <div style="position: relative; width: 220px; height: 220px; margin: 0 auto; background: #ffffff; padding: 8px; border-radius: 12px; display: flex; align-items: center; justify-content: center;">
          <img src="static/assets/crypto/USDT%20(TON).webp" alt="USDT TON QR" style="width: 100%; height: 100%; display: block; border-radius: 4px; object-fit: contain;">
        </div>
      </div>
      <p style="font-family: var(--font-mono); font-size: 0.78rem; word-break: break-all; margin-bottom: 16px; padding: 12px; background: var(--bg); border-radius: 8px; border: 1px solid var(--line); user-select: all; color: var(--text-muted);">UQDalQWmfsFTIEAT_t-urAoCCw_KzxBsRwcnfTZZfPCak2Ge</p>
      <a href="ton://transfer/UQDalQWmfsFTIEAT_t-urAoCCw_KzxBsRwcnfTZZfPCak2Ge" class="btn btn-primary" style="width: 100%; justify-content: center; border-radius: 8px;">Open Wallet</a>
    </div>
    
    <div id="crypto-btc" class="crypto-panel" style="display: none;">
      <div style="background: #1e2329; border-radius: 16px; padding: 24px 20px; max-width: 320px; margin: 0 auto 20px; border: 1px solid #2b313a; box-shadow: 0 8px 24px rgba(0,0,0,0.3); text-align: center;">
        <div style="display: flex; align-items: center; justify-content: center; gap: 8px; margin-bottom: 10px; color: #F7931A; font-weight: 700; font-size: 1.05rem; letter-spacing: 0.05em;">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#F7931A"/><path d="M14.7 10.5C15.1 10.1 15.3 9.5 15.2 8.8C15 7.6 13.9 6.8 12.5 6.8H9V17H13.2C14.7 17 15.8 16.1 16 14.7C16.1 13.7 15.6 12.8 14.7 12.4C15.2 12 15.4 11.2 14.7 10.5ZM11 8.5H12.5C13 8.5 13.5 8.9 13.5 9.4C13.5 9.9 13.1 10.3 12.5 10.3H11V8.5ZM13 15.2H11V12.1H13C13.6 12.1 14.1 12.6 14.1 13.2C14.1 13.8 13.6 15.2 13 15.2Z" fill="white"/></svg>
          BITCOIN (BTC)
        </div>
        <p style="font-size: 0.78rem; color: #848e9c; margin-bottom: 16px;">Bitcoin Network (Native SegWit)</p>
        <div style="position: relative; width: 220px; height: 220px; margin: 0 auto; background: #ffffff; padding: 8px; border-radius: 12px; display: flex; align-items: center; justify-content: center;">
          <img src="static/assets/crypto/Bitcoin%20(BTC).webp" alt="BTC QR" style="width: 100%; height: 100%; display: block; border-radius: 4px; object-fit: contain;">
        </div>
      </div>
      <p style="font-family: var(--font-mono); font-size: 0.78rem; word-break: break-all; margin-bottom: 16px; padding: 12px; background: var(--bg); border-radius: 8px; border: 1px solid var(--line); user-select: all; color: var(--text-muted);">bc1q4myt8cj8a67twf6038mmaaes6xxst502lxe7kk</p>
      <a href="bitcoin:bc1q4myt8cj8a67twf6038mmaaes6xxst502lxe7kk" class="btn btn-primary" style="width: 100%; justify-content: center; border-radius: 8px;">Open Wallet</a>
    </div>
    
    <div id="crypto-sol" class="crypto-panel" style="display: none;">
      <div style="background: #1e2329; border-radius: 16px; padding: 24px 20px; max-width: 320px; margin: 0 auto 20px; border: 1px solid #2b313a; box-shadow: 0 8px 24px rgba(0,0,0,0.3); text-align: center;">
        <div style="display: flex; align-items: center; justify-content: center; gap: 8px; margin-bottom: 10px; color: #9945FF; font-weight: 700; font-size: 1.05rem; letter-spacing: 0.05em;">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#9945FF"/><path d="M7 15.5L8.5 14H17L15.5 15.5H7ZM7 11.5L8.5 10H17L15.5 11.5H7ZM7 7.5L8.5 9H17L15.5 7.5H7Z" stroke="white" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
          SOLANA (SOL)
        </div>
        <p style="font-size: 0.78rem; color: #848e9c; margin-bottom: 16px;">Solana Native Network</p>
        <div style="position: relative; width: 220px; height: 220px; margin: 0 auto; background: #ffffff; padding: 8px; border-radius: 12px; display: flex; align-items: center; justify-content: center;">
          <img src="static/assets/crypto/Solana%20(SOL).webp" alt="SOL QR" style="width: 100%; height: 100%; display: block; border-radius: 4px; object-fit: contain;">
        </div>
      </div>
      <p style="font-family: var(--font-mono); font-size: 0.78rem; word-break: break-all; margin-bottom: 16px; padding: 12px; background: var(--bg); border-radius: 8px; border: 1px solid var(--line); user-select: all; color: var(--text-muted);">4cg4Exxajew3xr5oyDFuz6EseD8Eq7oN8Fibvrka7A5</p>
      <a href="solana:4cg4Exxajew3xr5oyDFuz6EseD8Eq7oN8Fibvrka7A5" class="btn btn-primary" style="width: 100%; justify-content: center; border-radius: 8px;">Open Wallet</a>
    </div>

    <div id="crypto-eth" class="crypto-panel" style="display: none;">
      <div style="background: #1e2329; border-radius: 16px; padding: 24px 20px; max-width: 320px; margin: 0 auto 20px; border: 1px solid #2b313a; box-shadow: 0 8px 24px rgba(0,0,0,0.3); text-align: center;">
        <div style="display: flex; align-items: center; justify-content: center; gap: 8px; margin-bottom: 10px; color: #627EEA; font-weight: 700; font-size: 1.05rem; letter-spacing: 0.05em;">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#627EEA"/><path d="M12 4L6.5 13L12 16.5L17.5 13L12 4Z" fill="white" fill-opacity="0.9"/><path d="M12 17.5L6.5 14L12 20L17.5 14L12 17.5Z" fill="white"/></svg>
          ETHEREUM (ETH)
        </div>
        <p style="font-size: 0.78rem; color: #848e9c; margin-bottom: 16px;">Ethereum Network (ERC20)</p>
        <div style="position: relative; width: 220px; height: 220px; margin: 0 auto; background: #ffffff; padding: 8px; border-radius: 12px; display: flex; align-items: center; justify-content: center;">
          <img src="static/assets/crypto/Ethereum%20(ETH%20%3A%20ERC20).webp" alt="ETH QR" style="width: 100%; height: 100%; display: block; border-radius: 4px; object-fit: contain;">
        </div>
      </div>
      <p style="font-family: var(--font-mono); font-size: 0.78rem; word-break: break-all; margin-bottom: 16px; padding: 12px; background: var(--bg); border-radius: 8px; border: 1px solid var(--line); user-select: all; color: var(--text-muted);">0x04b972bD6deF9d97bEe305CC22FED8f04D9BcAC4</p>
      <a href="ethereum:0x04b972bD6deF9d97bEe305CC22FED8f04D9BcAC4" class="btn btn-primary" style="width: 100%; justify-content: center; border-radius: 8px;">Open Wallet</a>
    </div>

    <div id="crypto-bnb" class="crypto-panel" style="display: none;">
      <div style="background: #1e2329; border-radius: 16px; padding: 24px 20px; max-width: 320px; margin: 0 auto 20px; border: 1px solid #2b313a; box-shadow: 0 8px 24px rgba(0,0,0,0.3); text-align: center;">
        <div style="display: flex; align-items: center; justify-content: center; gap: 8px; margin-bottom: 10px; color: #F3BA2F; font-weight: 700; font-size: 1.05rem; letter-spacing: 0.05em;">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#F3BA2F"/><path d="M12 6L14.2 8.2L12 10.4L9.8 8.2L12 6ZM7.8 10.2L10 12.4L7.8 14.6L5.6 12.4L7.8 10.2ZM16.2 10.2L18.4 12.4L16.2 14.6L14 12.4L16.2 10.2ZM12 14.4L14.2 16.6L12 18.8L9.8 16.6L12 14.4ZM12 11.2L13.2 12.4L12 13.6L10.8 12.4L12 11.2Z" fill="white"/></svg>
          BNB CHAIN
        </div>
        <p style="font-size: 0.78rem; color: #848e9c; margin-bottom: 16px;">BNB Smart Chain (BEP20)</p>
        <div style="position: relative; width: 220px; height: 220px; margin: 0 auto; background: #ffffff; padding: 8px; border-radius: 12px; display: flex; align-items: center; justify-content: center;">
          <img src="static/assets/crypto/BNB%20(BEP20).webp" alt="BNB QR" style="width: 100%; height: 100%; display: block; border-radius: 4px; object-fit: contain;">
        </div>
      </div>
      <p style="font-family: var(--font-mono); font-size: 0.78rem; word-break: break-all; margin-bottom: 16px; padding: 12px; background: var(--bg); border-radius: 8px; border: 1px solid var(--line); user-select: all; color: var(--text-muted);">0x04b972bD6deF9d97bEe305CC22FED8f04D9BcAC4</p>
      <a href="ethereum:0x04b972bD6deF9d97bEe305CC22FED8f04D9BcAC4" class="btn btn-primary" style="width: 100%; justify-content: center; border-radius: 8px;">Open Wallet</a>
    </div>

    <div id="crypto-trx" class="crypto-panel" style="display: none;">
      <div style="background: #1e2329; border-radius: 16px; padding: 24px 20px; max-width: 320px; margin: 0 auto 20px; border: 1px solid #2b313a; box-shadow: 0 8px 24px rgba(0,0,0,0.3); text-align: center;">
        <div style="display: flex; align-items: center; justify-content: center; gap: 8px; margin-bottom: 10px; color: #EF0027; font-weight: 700; font-size: 1.05rem; letter-spacing: 0.05em;">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="#EF0027"/><path d="M6.5 7.5L17.5 6L14.5 18L6.5 7.5ZM8.5 9L13.5 15.5L15.5 8L8.5 9Z" fill="white"/></svg>
          TRON (TRX)
        </div>
        <p style="font-size: 0.78rem; color: #848e9c; margin-bottom: 16px;">TRON Network</p>
        <div style="position: relative; width: 220px; height: 220px; margin: 0 auto; background: #ffffff; padding: 8px; border-radius: 12px; display: flex; align-items: center; justify-content: center;">
          <img src="static/assets/crypto/TRON%20(TRX).webp" alt="TRX QR" style="width: 100%; height: 100%; display: block; border-radius: 4px; object-fit: contain;">
        </div>
      </div>
      <p style="font-family: var(--font-mono); font-size: 0.78rem; word-break: break-all; margin-bottom: 16px; padding: 12px; background: var(--bg); border-radius: 8px; border: 1px solid var(--line); user-select: all; color: var(--text-muted);">TAQBrzZuAvJ5Zga7touVzNGXXJykEVp7sp</p>
      <a href="tron:TAQBrzZuAvJ5Zga7touVzNGXXJykEVp7sp" class="btn btn-primary" style="width: 100%; justify-content: center; border-radius: 8px;">Open Wallet</a>
    </div>

    <div id="crypto-binance-pay" class="crypto-panel" style="display: none;">
      <div style="background: #1e2329; border-radius: 16px; padding: 24px 20px; max-width: 320px; margin: 0 auto 20px; border: 1px solid #2b313a; box-shadow: 0 8px 24px rgba(0,0,0,0.3); text-align: center;">
        <div style="display: flex; align-items: center; justify-content: center; gap: 8px; margin-bottom: 10px; color: #F0B90B; font-weight: 700; font-size: 1.05rem; letter-spacing: 0.05em;">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="#F0B90B"><path d="M12 6L14.2 8.2L12 10.4L9.8 8.2L12 6ZM7.8 10.2L10 12.4L7.8 14.6L5.6 12.4L7.8 10.2ZM16.2 10.2L18.4 12.4L16.2 14.6L14 12.4L16.2 10.2ZM12 14.4L14.2 16.6L12 18.8L9.8 16.6L12 14.4ZM12 11.2L13.2 12.4L12 13.6L10.8 12.4L12 11.2Z"/></svg>
          BINANCE PAY
        </div>
        <p style="font-size: 0.78rem; color: #848e9c; margin-bottom: 16px;">Scan with Binance App (0% Fee)</p>
        <div style="position: relative; width: 220px; height: 220px; margin: 0 auto 16px; background: #ffffff; padding: 8px; border-radius: 12px; display: flex; align-items: center; justify-content: center;">
          <img src="static/assets/crypto/binance_pay.webp" alt="Binance Pay QR" style="width: 100%; height: 100%; display: block; border-radius: 4px; object-fit: contain;">
        </div>
        <div style="font-family: var(--font-mono); font-size: 1rem; font-weight: 700; color: #ffffff; letter-spacing: 0.03em;">Alex8695</div>
      </div>
      <p style="font-family: var(--font-mono); font-size: 0.78rem; word-break: break-all; margin-bottom: 16px; padding: 12px; background: var(--bg); border-radius: 8px; border: 1px solid var(--line); user-select: all; color: var(--text-muted);">Binance Pay Nickname / ID: <strong>Alex8695</strong></p>
      <a href="https://www.binance.com/en/support/faq/3771bb743ee54151a2d255641d902b67" target="_blank" rel="noopener" class="btn btn-primary" style="width: 100%; justify-content: center; border-radius: 8px;">How to pay? (FAQ)</a>
    </div>
  </div>
</div>
`;

function getOrInjectCryptoModal() {
  let modal = document.getElementById('crypto-modal');
  if (!modal) {
    document.body.insertAdjacentHTML('beforeend', CRYPTO_MODAL_HTML);
    modal = document.getElementById('crypto-modal');
    setupCryptoModalEvents(modal);
  }
  return modal;
}

function setupCryptoModalEvents(modal) {
  const closeBtn = modal.querySelector('#crypto-modal-close');
  const tabs = modal.querySelectorAll('#crypto-tabs .shot-tab');
  const panels = modal.querySelectorAll('.crypto-panel');

  const closeModal = () => {
    modal.classList.remove('show');
    if (modal.contains(document.activeElement)) {
      document.activeElement.blur();
    }
    modal.inert = true;
    modal.setAttribute('aria-hidden', 'true');
    setTimeout(() => { modal.style.display = 'none'; }, 300);
    document.body.style.overflow = '';
  };

  if (closeBtn) closeBtn.addEventListener('click', closeModal);
  modal.addEventListener('click', (e) => {
    if (e.target === modal) closeModal();
  });

  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      tabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      const cryptoId = tab.getAttribute('data-crypto');
      panels.forEach(p => {
        p.style.display = p.id === 'crypto-' + cryptoId ? 'block' : 'none';
      });
    });
  });
}

document.querySelectorAll('#open-crypto-modal, #open-crypto-modal-support, [data-open-crypto]').forEach(btn => {
  btn.addEventListener('click', (e) => {
    e.preventDefault();
    const modal = getOrInjectCryptoModal();
    if (modal) {
      modal.inert = false;
      modal.style.display = 'flex';
      modal.setAttribute('aria-hidden', 'false');
      requestAnimationFrame(() => modal.classList.add('show'));
      document.body.style.overflow = 'hidden';
    }
  });
});

// Fast animated stats counters with IntersectionObserver
function initStatCounters() {
  const statElements = document.querySelectorAll('.stat-num[data-count]');
  if (!statElements.length) return;

  const animateCount = (el) => {
    const target = parseInt(el.getAttribute('data-count'), 10);
    const suffix = el.getAttribute('data-suffix') || '';
    if (isNaN(target)) return;
    if (target === 0) {
      el.textContent = '0' + suffix;
      return;
    }

    const duration = 1200; // ms
    const startTime = performance.now();

    const easeOutCubic = (t) => 1 - Math.pow(1 - t, 3);

    const update = (now) => {
      const elapsed = now - startTime;
      const progress = Math.min(elapsed / duration, 1);
      const easedProgress = easeOutCubic(progress);
      const current = Math.floor(easedProgress * target);

      el.textContent = current + suffix;

      if (progress < 1) {
        requestAnimationFrame(update);
      } else {
        el.textContent = target + suffix;
      }
    };

    requestAnimationFrame(update);
  };

  const observer = new IntersectionObserver((entries, obs) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        animateCount(entry.target);
        obs.unobserve(entry.target);
      }
    });
  }, { threshold: 0.2 });

  statElements.forEach(el => observer.observe(el));
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initStatCounters);
} else {
  initStatCounters();
}

