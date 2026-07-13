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
document.addEventListener('mousemove', (e) => {
  document.body.style.setProperty('--mouse-x', `${e.clientX}px`);
  document.body.style.setProperty('--mouse-y', `${e.clientY}px`);
});

// Mobile navigation menu toggle
const nav = document.getElementById('main-nav');
const navToggle = document.getElementById('nav-toggle');

if (nav && navToggle) {
  navToggle.addEventListener('click', (e) => {
    e.stopPropagation();
    nav.classList.toggle('open');
  });

  // Close menu when clicking outside
  document.addEventListener('click', (e) => {
    if (nav.classList.contains('open') && !nav.contains(e.target)) {
      nav.classList.remove('open');
    }
  });

  // Close menu when clicking a link
  nav.querySelectorAll('a').forEach(link => {
    link.addEventListener('click', () => {
      nav.classList.remove('open');
    });
  });
}
