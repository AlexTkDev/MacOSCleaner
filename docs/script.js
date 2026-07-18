let slideIndex = 0;
const slides = document.querySelectorAll('.carousel-slide');
const dots = document.querySelectorAll('.dot');
const track = document.querySelector('.carousel-track');
let autoPlayTimer;

function updateCarousel() {
  if (!track || slides.length === 0) return;
  track.style.transform = `translateX(-${slideIndex * 100}%)`;
  dots.forEach(dot => dot.classList.remove('active'));
  if (dots[slideIndex]) dots[slideIndex].classList.add('active');
}

function moveSlide(n) {
  slideIndex += n;
  if (slideIndex >= slides.length) slideIndex = 0;
  if (slideIndex < 0) slideIndex = slides.length - 1;
  updateCarousel();
  resetAutoPlay();
}

function currentSlide(n) {
  slideIndex = n;
  updateCarousel();
  resetAutoPlay();
}

function startAutoPlay() {
  if (slides.length === 0) return;
  autoPlayTimer = setInterval(() => {
    slideIndex = (slideIndex + 1) % slides.length;
    updateCarousel();
  }, 4000);
}

function resetAutoPlay() {
  clearInterval(autoPlayTimer);
  startAutoPlay();
}

startAutoPlay();

// Interactive Antigravity background light
document.addEventListener('mousemove', (event) => {
  document.body.style.setProperty('--mouse-x', `${event.clientX}px`);
  document.body.style.setProperty('--mouse-y', `${event.clientY}px`);
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
  if (touchEndX < touchStartX - threshold) moveSlide(1);
  if (touchEndX > touchStartX + threshold) moveSlide(-1);
}

// Screenshot modal
const modal = document.getElementById('image-modal');
const modalImg = document.getElementById('modal-img');
const modalClose = document.getElementById('modal-close');

if (modal && modalImg && modalClose) {
  const updateModalImage = () => {
    if (slides[slideIndex]) {
      modalImg.src = slides[slideIndex].getAttribute('href');
      updateCarousel();
    }
  };

  const closeModal = () => {
    modal.classList.remove('show');
    modal.setAttribute('aria-hidden', 'true');
    setTimeout(() => {
      modal.style.display = 'none';
      modalImg.src = '';
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
    slide.addEventListener('click', (e) => {
      e.preventDefault();
      openModal(index);
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

  modal.addEventListener('touchstart', (e) => {
    modalTouchStartX = e.changedTouches[0].screenX;
  }, { passive: true });

  modal.addEventListener('touchend', (e) => {
    modalTouchEndX = e.changedTouches[0].screenX;
    const threshold = 50;
    if (modalTouchEndX < modalTouchStartX - threshold) {
      slideIndex = (slideIndex + 1) % slides.length;
      updateModalImage();
      resetAutoPlay();
    }
    if (modalTouchEndX > modalTouchStartX + threshold) {
      slideIndex = (slideIndex - 1 + slides.length) % slides.length;
      updateModalImage();
      resetAutoPlay();
    }
  }, { passive: true });

  document.addEventListener('keydown', (e) => {
    if (!modal.classList.contains('show')) return;
    if (e.key === 'ArrowRight') {
      slideIndex = (slideIndex + 1) % slides.length;
      updateModalImage();
      resetAutoPlay();
    } else if (e.key === 'ArrowLeft') {
      slideIndex = (slideIndex - 1 + slides.length) % slides.length;
      updateModalImage();
      resetAutoPlay();
    } else if (e.key === 'Escape') {
      closeModal();
    }
  });

  const modalPrev = document.getElementById('modal-prev');
  const modalNext = document.getElementById('modal-next');

  if (modalPrev && modalNext) {
    modalPrev.addEventListener('click', (e) => {
      e.stopPropagation();
      slideIndex = (slideIndex - 1 + slides.length) % slides.length;
      updateModalImage();
      resetAutoPlay();
    });
    modalNext.addEventListener('click', (e) => {
      e.stopPropagation();
      slideIndex = (slideIndex + 1) % slides.length;
      updateModalImage();
      resetAutoPlay();
    });
  }
}
