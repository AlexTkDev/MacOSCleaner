let slideIndex = 0;
const slides = document.querySelectorAll('.carousel-slide');
const tabs = document.querySelectorAll('.shot-tabs .shot-tab');
const track = document.querySelector('.carousel-track');
const viewport = document.querySelector('.shot-viewport');

function syncViewportHeight() {
  if (!viewport) return;
  const img = slides[slideIndex]?.querySelector('img');
  if (!img) return;

  const apply = () => {
    if (!img.naturalWidth) return;
    const height = viewport.clientWidth * (img.naturalHeight / img.naturalWidth);
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

// Crypto modal
const cryptoModal = document.getElementById('crypto-modal');
const cryptoModalClose = document.getElementById('crypto-modal-close');
const cryptoTabs = document.querySelectorAll('#crypto-tabs .shot-tab');
const cryptoPanels = document.querySelectorAll('.crypto-panel');

if (cryptoModal) {
  const openCrypto = (e) => {
    e.preventDefault();
    cryptoModal.style.display = 'flex';
    cryptoModal.setAttribute('aria-hidden', 'false');
    requestAnimationFrame(() => cryptoModal.classList.add('show'));
    document.body.style.overflow = 'hidden';
  };

  document.querySelectorAll('#open-crypto-modal, #open-crypto-modal-support, [data-open-crypto]').forEach(btn => {
    btn.addEventListener('click', openCrypto);
  });

  const closeCryptoModal = () => {
    cryptoModal.classList.remove('show');
    cryptoModal.setAttribute('aria-hidden', 'true');
    setTimeout(() => {
      cryptoModal.style.display = 'none';
    }, 300);
    document.body.style.overflow = '';
  };

  if (cryptoModalClose) {
    cryptoModalClose.addEventListener('click', closeCryptoModal);
  }

  cryptoModal.addEventListener('click', (e) => {
    if (e.target === cryptoModal) closeCryptoModal();
  });

  cryptoTabs.forEach(tab => {
    tab.addEventListener('click', () => {
      cryptoTabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      const cryptoId = tab.getAttribute('data-crypto');
      cryptoPanels.forEach(p => {
        p.style.display = p.id === 'crypto-' + cryptoId ? 'block' : 'none';
      });
    });
  });
}
