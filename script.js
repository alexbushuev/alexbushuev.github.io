const translations = {
  ru: {
    // Navbar & brand
    'brand.name':  'Александр Бушуев',
    'brand.title': 'Аналитик данных',

    // Nav tabs
    'nav.portfolio': 'Портфолио',
    'nav.resume':    'Резюме',

    // Modal
    'modal.title':    'Связаться',
    'modal.call':     'Позвонить',
    'modal.telegram': 'Написать в Telegram',
    'modal.email':    'Написать email',

    // Hero
    'hero.eyebrow': 'Открыт к новым возможностям',
    'hero.name':    'Александр Бушуев',
    'hero.role':    'Аналитик данных & Tech Lead',
    'hero.bio':     'Аналитик данных и Tech Lead с 5+ годами опыта в e-commerce. Специализируюсь на BI-отчётности и аналитической инфраструктуре: SQL, Power BI, DataLens, Python. Разработанные дашборды используют 2 000+ сотрудников ежедневно, одно аналитическое решение принесло ~100 млн ₽ экономии чистой прибыли в месяц.',
    'hero.contact':  'Связаться',
    'hero.download': 'Скачать резюме',

    // Contacts
    'resume.city':      'Москва',
    'resume.city.long': 'Москва, Россия',

    // Portfolio
    'skills.title':   'Навыки',
    'projects.title': 'Кейсы',

    // Project 1
    'project1.name':   'Defect Rate Report',
    'project1.desc':   'Выявил системный рост дефектных заказов и с нуля разработал отчёт (SQL + Power BI). Снижение доли брака на 50%, экономия ~100 млн ₽ чистой прибыли в месяц.',
    'project1.metric': '−50% брака · ~100 млн ₽/мес',

    // Project 2
    'project2.name':   'Operational Dashboard Suite',
    'project2.desc':   'Спроектировал и вывел в production 30+ регулярных дашбордов (Power BI / DataLens) для кросс-функциональных команд. Сокращение time-to-insight по ключевым операционным метрикам.',
    'project2.metric': '2 000+ DAU · 30+ дашбордов',

    // Project 3
    'project3.name':   'DataLens Migration',
    'project3.desc':   'Инициировал и реализовал перевод аналитической инфраструктуры на DataLens. Унифицировал слои трансформации данных, что сократило среднее время разработки новых дашбордов.',
    'project3.metric': 'Ускорение разработки · Унификация стека',

    // Project 4
    'project4.name':   'Logistics KPI Automation',
    'project4.desc':   'Автоматизировал ежедневную операционную отчётность по KPI логистики с помощью Python (Pandas) + SQL. Устранена рутинная ручная работа для всей команды.',
    'project4.metric': '~15 ч/нед ручной работы устранено',

    // Project 5
    'project5.name':   'Analytics Team Development',
    'project5.desc':   'Выстроил систему менторства для 5 аналитиков: 3 из 5 получили повышение до Senior за 2 года. Внедрил стандарты code review и шаблоны архитектурных решений.',
    'project5.metric': '3 из 5 → Senior за 2 года',

    // Resume section titles
    'resume.contact':   'Контакты',
    'resume.skills':    'Навыки',
    'resume.education': 'Образование',
    'resume.languages': 'Языки',
    'resume.experience': 'Опыт работы',

    // Skill categories
    'skills.cat.languages': 'Языки',
    'skills.cat.bi':        'BI & Визуализация',
    'skills.cat.analytics': 'Аналитика',
    'skills.cat.tools':     'Инструменты',

    // Education
    'edu1.name':        'Уральский федеральный университет',
    'edu1.degree1':     'Магистратура — Математическое моделирование, 2018',
    'edu1.degree2':     'Бакалавриат — Математическое моделирование, 2016',
    'edu.courses.label': 'Курсы и сертификаты',

    // Human languages
    'lang.ru': 'Русский — родной',
    'lang.en': 'Английский — B1–B2 (технические тексты, деловая переписка)',

    // Experience
    'exp.present':   'настоящее время',

    'exp1.company': 'Tech Lead, Data & Analytics · Lamoda',
    'exp1.context': 'e-commerce, топ-5 онлайн-ретейлеров СНГ, ~30 млн пользователей',
    'exp1.bullet1': 'Руковожу командой 2–3 аналитиков: data modeling стандарты, code review, бэклог и stakeholder management',
    'exp1.bullet2': 'Инициировал переход аналитической инфраструктуры на DataLens: унификация трансформаций, ускорение разработки',
    'exp1.bullet3': 'Регулярно готовлю C-level аналитику по KPI склада, логистики и качества заказов',

    'exp2.company': 'Senior Data Analyst · Lamoda',
    'exp2.bullet1': 'Выявил рост дефектных заказов → разработал Defect Rate report (SQL + Power BI) → −50% брака, ~100 млн ₽/мес экономии',
    'exp2.bullet2': 'Вывел в production 30+ дашбордов (Power BI / DataLens) → 2 000+ DAU, снижение time-to-insight',
    'exp2.bullet3': 'Менторство 5 аналитиков: 3 из 5 выросли до Senior за 2 года; внедрил стандарты code review',
    'exp2.bullet4': 'Автоматизировал KPI-отчётность логистики (Python + SQL) → устранил ~15 ч/нед ручной работы',

    'exp3.company': 'Middle Data Analyst · Lamoda',
    'exp3.bullet1': 'SQL-запросы для операционной отчётности: витрины >100 млн строк, оконные функции, CTE',
    'exp3.bullet2': 'Создал первые Power BI шаблоны по качеству заказов — основа для масштабирования на весь операционный блок',

    'exp4.company': 'Инженер-конструктор · ОКБ «Новатор»',
    'exp4.location': 'Екатеринбург',
    'exp4.bullet1': 'Количественный анализ испытательных данных, автоматизация обработки в Excel и Python',

    // Footer
    'footer.text': '© 2026 Александр Бушуев. Сделано с ❤️ и кофе.',
  },

  en: {
    // Navbar & brand
    'brand.name':  'Alexander Bushuev',
    'brand.title': 'Data Analyst',

    // Nav tabs
    'nav.portfolio': 'Portfolio',

    // Modal
    'modal.title':    'Get in touch',
    'modal.call':     'Call',
    'modal.telegram': 'Message on Telegram',
    'modal.email':    'Send email',
    'nav.resume':    'Resume',

    // Hero
    'hero.eyebrow': 'Open to new opportunities',
    'hero.name':    'Alexander Bushuev',
    'hero.role':    'Data Analyst & Analytics Tech Lead',
    'hero.bio':     'Data Analyst and Analytics Tech Lead with 5+ years of e-commerce experience at Lamoda (top-5 CIS online retailer, ~30M users). Expert in BI reporting infrastructure: SQL, Power BI, DataLens, Python. Dashboards I designed serve 2,000+ daily users; a single analytical solution drives ~$1M+/month in net profit savings.',
    'hero.contact':  'Get in touch',
    'hero.download': 'Download CV',

    // Contacts
    'resume.city':      'Moscow',
    'resume.city.long': 'Moscow, Russia',

    // Portfolio
    'skills.title':   'Skills',
    'projects.title': 'Case Studies',

    // Project 1
    'project1.name':   'Defect Rate Report',
    'project1.desc':   'Identified a systemic increase in defective orders and built the Defect Rate report from scratch (SQL + Power BI). Reduced defective order share by 50%, driving ~$1M+/month in net profit savings.',
    'project1.metric': '−50% defects · ~$1M+/month savings',

    // Project 2
    'project2.name':   'Operational Dashboard Suite',
    'project2.desc':   'Designed and delivered 30+ production dashboards (Power BI / DataLens) for cross-functional teams. Reduced time-to-insight across key operational metrics.',
    'project2.metric': '2,000+ DAU · 30+ dashboards',

    // Project 3
    'project3.name':   'DataLens Migration',
    'project3.desc':   'Initiated and delivered migration of core reporting infrastructure to DataLens. Unified data transformation layers, reducing average dashboard development time for the team.',
    'project3.metric': 'Faster delivery · Unified stack',

    // Project 4
    'project4.name':   'Logistics KPI Automation',
    'project4.desc':   'Automated daily logistics KPI reporting using Python (Pandas) + SQL. Eliminated routine manual work for the entire analytics team.',
    'project4.metric': '~15 hrs/week manual work eliminated',

    // Project 5
    'project5.name':   'Analytics Team Development',
    'project5.desc':   'Built a mentoring framework for 5 analysts: 3 out of 5 promoted to Senior within 2 years. Introduced code review standards and architectural decision templates.',
    'project5.metric': '3 of 5 → Senior in 2 years',

    // Resume section titles
    'resume.contact':   'Contacts',
    'resume.skills':    'Skills',
    'resume.education': 'Education',
    'resume.languages': 'Languages',
    'resume.experience': 'Experience',

    // Skill categories
    'skills.cat.languages': 'Languages',
    'skills.cat.bi':        'BI & Visualization',
    'skills.cat.analytics': 'Analytics',
    'skills.cat.tools':     'Tools',

    // Education
    'edu1.name':        'Ural Federal University (UrFU)',
    'edu1.degree1':     'Master\'s — Mathematical Modeling, 2018',
    'edu1.degree2':     'Bachelor\'s — Mathematical Modeling, 2016',
    'edu.courses.label': 'Certifications & Courses',

    // Human languages
    'lang.ru': 'Russian — Native',
    'lang.en': 'English — B1–B2 (technical docs, business correspondence)',

    // Experience
    'exp.present':   'Present',

    'exp1.company': 'Tech Lead, Data & Analytics · Lamoda',
    'exp1.context': 'Top-5 fashion e-commerce in the CIS (comparable to ASOS/Zalando), ~30M users',
    'exp1.bullet1': 'Lead a team of 2–3 analysts: data modeling standards, code reviews, backlog alignment with business priorities',
    'exp1.bullet2': 'Initiated and delivered reporting infrastructure migration to DataLens: unified transformation layers, reduced dev time',
    'exp1.bullet3': 'Regularly present and defend C-level analytics on operational KPIs — warehouse, logistics, order quality',

    'exp2.company': 'Senior Data Analyst · Lamoda',
    'exp2.bullet1': 'Identified systemic defect growth → built Defect Rate report (SQL + Power BI) → −50% defects, ~$1M+/month savings',
    'exp2.bullet2': 'Delivered 30+ production dashboards (Power BI / DataLens) → 2,000+ DAU, reduced time-to-insight',
    'exp2.bullet3': 'Mentored 5 analysts: 3 of 5 promoted to Senior in 2 years; introduced code review process',
    'exp2.bullet4': 'Automated logistics KPI reporting (Python + SQL) → eliminated ~15 hrs/week of manual work',

    'exp3.company': 'Junior Data Analyst · Lamoda',
    'exp3.bullet1': 'Advanced SQL for operational reporting: data marts with 100M+ rows, window functions, CTEs',
    'exp3.bullet2': 'Built initial Power BI report templates for order quality — foundation for scaling across operations division',

    'exp4.company': 'Design Engineer · OKB Novator',
    'exp4.location': 'Yekaterinburg',
    'exp4.bullet1': 'Quantitative analysis of test data; automated routine data processing in Excel and Python',

    // Footer
    'footer.text': '© 2026 Alexander Bushuev. Made with ❤️ and coffee.',
  },
};

let currentLang  = localStorage.getItem('lang')  || null;  // null = not yet decided
let currentTheme = localStorage.getItem('theme') || 'dark';

function applyTranslations(lang) {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.getAttribute('data-i18n');
    if (translations[lang][key] !== undefined) {
      el.textContent = translations[lang][key];
    }
  });
  document.documentElement.lang = lang;
  document.title = lang === 'ru'
    ? 'Александр Бушуев — Аналитик данных'
    : 'Alexander Bushuev — Data Analyst';
}

function applyTheme(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  document.querySelector('.theme-icon').textContent = theme === 'dark' ? '☀️' : '🌙';
  localStorage.setItem('theme', theme);
}

function switchTab(tabName) {
  document.querySelectorAll('.tab').forEach(btn =>
    btn.classList.toggle('active', btn.dataset.tab === tabName)
  );
  document.querySelectorAll('.tab-content').forEach(section =>
    section.classList.toggle('active', section.id === tabName)
  );
}

const PDF = { ru: 'BushuevA_RU.pdf', en: 'BushuevA_EN.pdf' };

function setLang(lang) {
  currentLang = lang;
  document.querySelectorAll('.lang-btn').forEach(btn =>
    btn.classList.toggle('active', btn.dataset.lang === lang)
  );
  applyTranslations(lang);
  localStorage.setItem('lang', lang);
  // Update download link to the correct PDF
  const dlBtn = document.getElementById('downloadBtn');
  if (dlBtn) {
    dlBtn.href = PDF[lang];
    dlBtn.download = PDF[lang];
  }
}

// ── Modal ──────────────────────────────────────────────────────────────────
function openModal()  { document.getElementById('contactModal').classList.add('open'); }
function closeModal() { document.getElementById('contactModal').classList.remove('open'); }

// ── IP-based language detection ────────────────────────────────────────────
async function detectLangByIP() {
  try {
    const res = await fetch('https://api.country.is/', { signal: AbortSignal.timeout(3000) });
    const { country } = await res.json();
    return country === 'RU' ? 'ru' : 'en';
  } catch {
    return 'ru'; // fallback on network error / timeout
  }
}

document.addEventListener('DOMContentLoaded', async () => {
  applyTheme(currentTheme);

  // Determine language: saved pref → IP detection → 'ru'
  if (!currentLang) {
    currentLang = await detectLangByIP();
  }
  setLang(currentLang);

  document.querySelectorAll('.tab').forEach(btn =>
    btn.addEventListener('click', () => switchTab(btn.dataset.tab))
  );

  document.getElementById('themeToggle').addEventListener('click', () => {
    currentTheme = currentTheme === 'dark' ? 'light' : 'dark';
    applyTheme(currentTheme);
  });

  document.querySelectorAll('.lang-btn').forEach(btn =>
    btn.addEventListener('click', () => setLang(btn.dataset.lang))
  );

  // Contact modal
  document.getElementById('contactBtn').addEventListener('click', openModal);
  document.getElementById('modalClose').addEventListener('click', closeModal);
  document.getElementById('contactModal').addEventListener('click', e => {
    if (e.target === e.currentTarget) closeModal();
  });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape') closeModal();
  });
});
