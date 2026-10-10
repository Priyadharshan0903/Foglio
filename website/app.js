document.documentElement.classList.add('js');

const motion = matchMedia('(prefers-reduced-motion: reduce)');
const desktop = matchMedia('(min-width: 761px)');
const header = document.querySelector('.site-header');
const hero = document.querySelector('.hero');
const product = document.querySelector('.hero-product');
const downloadSection = document.querySelector('.download-section');
const progress = document.querySelector('.scroll-progress');
let framePending = false;

function updateScroll() {
  framePending = false;
  const y = scrollY;
  header.classList.toggle('scrolled', y > 24);
  const length = document.documentElement.scrollHeight - innerHeight;
  progress.style.transform = `scaleX(${length > 0 ? Math.min(1, y / length) : 0})`;
  if (motion.matches || !desktop.matches) return;
  if (y < hero.offsetHeight + innerHeight) {
    hero.style.setProperty('--landscape-y', `${Math.min(y * .12, 140)}px`);
    product.style.setProperty('--product-y', `${Math.min(y * .045, 48)}px`);
    product.style.setProperty('--hero-rotate', `${Math.max(0, 8 - y * .018)}deg`);
  }
  const box = downloadSection.getBoundingClientRect();
  if (box.top < innerHeight && box.bottom > 0) {
    const offset = Math.max(-1, Math.min(1, (box.top - innerHeight / 2) / innerHeight));
    downloadSection.style.setProperty('--paper-y', `${offset * 45}px`);
    downloadSection.style.setProperty('--paper-rotate', `${-9 + offset * 8}deg`);
  }
}
function scheduleScroll() {
  if (!framePending) { framePending = true; requestAnimationFrame(updateScroll); }
}
addEventListener('scroll', scheduleScroll, { passive: true });
addEventListener('resize', scheduleScroll, { passive: true });
motion.addEventListener('change', scheduleScroll);
updateScroll();

const revealObserver = new IntersectionObserver(entries => {
  for (const entry of entries) {
    if (entry.isIntersecting) { entry.target.classList.add('visible'); revealObserver.unobserve(entry.target); }
  }
}, { threshold: .08 });
document.querySelectorAll('.reveal').forEach(element => revealObserver.observe(element));

product.addEventListener('pointermove', event => {
  if (motion.matches || !desktop.matches || event.pointerType !== 'mouse') return;
  const box = product.getBoundingClientRect();
  product.style.setProperty('--pointer-x', `${((event.clientX - box.left) / box.width - .5) * 2.5}deg`);
});
product.addEventListener('pointerleave', () => product.style.setProperty('--pointer-x', '0deg'));

const sceneButtons = [...document.querySelectorAll('[data-scene]')];
const scenePanes = [...document.querySelectorAll('[data-pane]')];
const sceneCaption = document.querySelector('#scene-caption');
function setScene(name) {
  sceneButtons.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.scene === name)));
  scenePanes.forEach(pane => {
    const active = pane.dataset.pane === name;
    pane.classList.toggle('active', active);
    pane.setAttribute('aria-hidden', String(!active));
  });
  sceneCaption.textContent = name === 'calendar' ? 'Calendar illustration · Example schedule' : 'Actual app preview · Example content';
}
sceneButtons.forEach(button => button.addEventListener('click', () => {
  setScene(button.dataset.scene);
  document.querySelector(`#${button.dataset.scene}-step`).scrollIntoView({ behavior: motion.matches ? 'auto' : 'smooth', block: 'center' });
}));
const stepObserver = new IntersectionObserver(entries => {
  if (!desktop.matches) return;
  const visible = entries.filter(entry => entry.isIntersecting).sort((a,b) => b.intersectionRatio - a.intersectionRatio);
  if (visible[0]) setScene(visible[0].target.dataset.step);
}, { rootMargin: '-30% 0px -30% 0px', threshold: 0 });
document.querySelectorAll('[data-step]').forEach(step => stepObserver.observe(step));

const themeImage = document.querySelector('#theme-image');
const themeCaption = document.querySelector('#theme-caption');
const themePreview = themeImage.closest('figure');
const themeShowcase = document.querySelector('.theme-showcase');
const themeButtons = [...document.querySelectorAll('[data-theme]')];
let themeRequest = 0;
let requestedTheme = 0;
let previousPreview;
async function selectTheme(button) {
  const request = ++themeRequest;
  requestedTheme = themeButtons.indexOf(button);
  const label = button.textContent.trim();
  const source = `assets/images/notes-${button.dataset.theme}.webp`;
  themePreview.classList.add('loading');
  themePreview.setAttribute('aria-busy', 'true');
  themeShowcase.classList.add('loading');
  const image = new Image();
  image.src = source;
  try { await image.decode(); } catch {
    if (request === themeRequest) {
      themePreview.classList.remove('loading');
      themePreview.setAttribute('aria-busy', 'false');
      themeShowcase.classList.remove('loading');
      requestedTheme = themeButtons.findIndex(other => other.getAttribute('aria-pressed') === 'true');
      themeCaption.textContent = 'Could not load this theme preview. Try another palette.';
    }
    return;
  }
  if (request !== themeRequest) return;
  previousPreview?.remove();
  if (!motion.matches && themeImage.getAttribute('src') !== source) {
    const previous = themeImage.cloneNode();
    previous.removeAttribute('id');
    previous.alt = '';
    previous.setAttribute('aria-hidden', 'true');
    previous.className = 'theme-previous';
    themePreview.append(previous);
    previousPreview = previous;
    requestAnimationFrame(() => previous.classList.add('leaving'));
    setTimeout(() => previous.remove(), 350);
  }
  themeImage.src = source;
  themeImage.alt = `Foglio Notes in the ${label} theme.`;
  themeButtons.forEach(other => other.setAttribute('aria-pressed', String(other === button)));
  themeShowcase.style.setProperty('--theme-accent', button.style.getPropertyValue('--swatch'));
  document.querySelector('#theme-name').textContent = label;
  document.querySelector('#theme-description').textContent = button.dataset.description;
  document.querySelector('#theme-count').textContent = `${String(requestedTheme + 1).padStart(2, '0')} / 08`;
  themeCaption.textContent = `${label} · Actual app preview with example content`;
  themePreview.classList.remove('loading');
  themePreview.setAttribute('aria-busy', 'false');
  themeShowcase.classList.remove('loading');
}
themeButtons.forEach(button => button.addEventListener('click', () => selectTheme(button)));
document.querySelector('[data-theme-previous]').addEventListener('click', () => selectTheme(themeButtons[(requestedTheme - 1 + themeButtons.length) % themeButtons.length]));
document.querySelector('[data-theme-next]').addEventListener('click', () => selectTheme(themeButtons[(requestedTheme + 1) % themeButtons.length]));
// Every swatch remains a standard keyboard-accessible button; arrows also
// provide a quick way to compare adjacent palettes without moving focus out.
document.querySelector('.theme-controls').addEventListener('keydown', event => {
  if (!event.target.matches('[data-theme]')) return;
  const index = themeButtons.indexOf(event.target);
  const direction = event.key === 'ArrowRight' || event.key === 'ArrowDown' ? 1 : event.key === 'ArrowLeft' || event.key === 'ArrowUp' ? -1 : 0;
  const next = event.key === 'Home' ? 0 : event.key === 'End' ? themeButtons.length - 1 : direction ? (index + direction + themeButtons.length) % themeButtons.length : undefined;
  if (next === undefined) return;
  event.preventDefault();
  themeButtons[next].focus();
  selectTheme(themeButtons[next]);
});

// The static fallback links also work when JavaScript is disabled. Builds
// update them from release.json; this keeps the local development page current.
fetch('release.json').then(response => response.ok ? response.json() : Promise.reject()).then(release => {
  if (!/^Foglio-\d+\.\d+\.\d+\.dmg$/.test(release.filename)) return;
  document.querySelectorAll('[data-download]').forEach(link => { link.href = `downloads/${release.filename}`; link.download = release.filename; });
  document.querySelectorAll('[data-version]').forEach(element => { element.textContent = release.version; });
  document.querySelector('[data-checksum]').href = `downloads/${release.filename}.sha256.txt`;
}).catch(() => {});
