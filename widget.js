// === Конфигурация рангов ===
const RANKS = [
  ...Array.from({ length: 5 }, (_, i) => ({ type: 'Bronze', level: 5 - i, img: 'assets/uploads/Bronze.png' })),
  ...Array.from({ length: 5 }, (_, i) => ({ type: 'Silver', level: 5 - i, img: 'assets/uploads/Silver.png' })),
  ...Array.from({ length: 5 }, (_, i) => ({ type: 'Gold', level: 5 - i, img: 'assets/uploads/Gold.png' })),
  ...Array.from({ length: 5 }, (_, i) => ({ type: 'Platinum', level: 5 - i, img: 'assets/uploads/Platinum.png' })),
  ...Array.from({ length: 5 }, (_, i) => ({ type: 'Diamond', level: 5 - i, img: 'assets/uploads/Diamond.png' })),
  ...Array.from({ length: 5 }, (_, i) => ({ type: 'Master', level: 5 - i, img: 'assets/uploads/Master.png' })),
  ...Array.from({ length: 5 }, (_, i) => ({ type: 'Grandmaster', level: 5 - i, img: 'assets/uploads/Grandmaster.png' })),
  ...Array.from({ length: 5 }, (_, i) => ({ type: 'Champion', level: 5 - i, img: 'assets/uploads/Champion.png' })),
  ...Array.from({ length: 500 }, (_, i) => ({ type: 'Top', level: 500 - i, img: 'assets/uploads/Top_500.png' }))
];

let currentRankIndex = 0;
let animationTimeout;
let currentConfig = getDefaultConfig();

function getDefaultConfig() {
  return {
      stats: { wins: 0, losses: 0, rankValue: `${RANKS[0].type} ${RANKS[0].level}` },
      rank: { image: RANKS[0].img },
      animation: { direction: 'left', durationIn: 1000, stayTime: 10000, durationOut: 1000, hiddenTime: 10000 },
      background: { type: 'color', color: 'rgba(0,0,0,0.7)', image: '' },
      colors: { wins: '#00ff00', losses: '#ff0000', rankText: '#ffffff' }
  };
}

function applyConfig(config) {
  const widget = document.getElementById('widget');

  // Устанавливаем фон (цвет или картинка)
  widget.style.background = (config.background.type === 'image' && config.background.image)
      ? `url('${config.background.image}') center/100% 100% no-repeat`
      : config.background.color;

  // Устанавливаем текст и цвет
  document.getElementById('wins').textContent = config.stats.wins;
  document.getElementById('losses').textContent = config.stats.losses;
  document.getElementById('rankValue').textContent = config.stats.rankValue;
  document.getElementById('rankImage').src = config.rank.image;

  document.documentElement.style.setProperty('--wins-color', config.colors.wins);
  document.documentElement.style.setProperty('--losses-color', config.colors.losses);
  document.documentElement.style.setProperty('--rank-text-color', config.colors.rankText);
}

function updateRank(increment) {
  const newIndex = currentRankIndex + increment;
  if (newIndex >= 0 && newIndex < RANKS.length) {
      currentRankIndex = newIndex;
      currentConfig.stats.rankValue = `${RANKS[currentRankIndex].type} ${RANKS[currentRankIndex].level}`;
      currentConfig.rank.image = RANKS[currentRankIndex].img;
      applyConfig(currentConfig);
  }
}

function resetStats() {
  currentConfig.stats.wins = 0;
  currentConfig.stats.losses = 0;
  applyConfig(currentConfig);
  saveConfig();
}

function resetToDefault() {
  currentConfig = getDefaultConfig();
  currentRankIndex = 0;
  applyConfig(currentConfig);
  localStorage.removeItem('widgetConfig');
  saveConfig();
}

function toggleVisibility() {
  const widget = document.getElementById('widget');
  widget.style.display = widget.style.display === 'none' ? 'flex' : 'none';
}

function saveConfig() {
  try {
      localStorage.setItem('widgetConfig', JSON.stringify(currentConfig));
  } catch (e) {
      console.error('Storage error:', e);
  }
}

function loadSavedConfig() {
  try {
      const saved = localStorage.getItem('widgetConfig');
      if (saved) {
          currentConfig = JSON.parse(saved);
          currentRankIndex = RANKS.findIndex(r => `${r.type} ${r.level}` === currentConfig.stats.rankValue);
          if (currentRankIndex === -1) currentRankIndex = 0;
      }
  } catch (e) {
      console.error('Error loading config:', e);
      resetToDefault();
  }
}

function startAnimation() {
  clearTimeout(animationTimeout);
  const widget = document.getElementById('widget');
  const anim = currentConfig.animation;
  const directionMap = { top: 'translateY(-100%)', bottom: 'translateY(100%)', left: 'translateX(-100%)', right: 'translateX(100%)' };
  const direction = directionMap[anim.direction];

  widget.style.transition = 'none';
  widget.style.transform = direction;
  widget.style.opacity = '0';
  void widget.offsetHeight;
  widget.style.transition = `all ${anim.durationIn}ms ease-in-out`;
  widget.style.transform = 'translate(0, 0)';
  widget.style.opacity = '1';

  animationTimeout = setTimeout(() => {
      widget.style.transition = `all ${anim.durationOut}ms ease-in-out`;
      widget.style.transform = direction;
      widget.style.opacity = '0';

      animationTimeout = setTimeout(startAnimation, anim.hiddenTime);
  }, anim.durationIn + anim.stayTime);
}

document.addEventListener('DOMContentLoaded', () => {
  const params = new URLSearchParams(window.location.search);

  // Загружаем сохранённые настройки
  loadSavedConfig();

  // Считываем параметры из URL
  if (params.has('wins')) currentConfig.stats.wins = parseInt(params.get('wins'));
  if (params.has('losses')) currentConfig.stats.losses = parseInt(params.get('losses'));
  if (params.has('rank')) {
      const newRank = parseInt(params.get('rank'));
      if (!isNaN(newRank) && newRank >= 0 && newRank < RANKS.length) {
          currentRankIndex = newRank;
          currentConfig.stats.rankValue = `${RANKS[currentRankIndex].type} ${RANKS[currentRankIndex].level}`;
          currentConfig.rank.image = RANKS[currentRankIndex].img;
      }
  }
  if (params.has('bgType')) currentConfig.background.type = params.get('bgType');
  if (params.has('bgColor')) currentConfig.background.color = params.get('bgColor');
  if (params.has('bgImage')) currentConfig.background.image = params.get('bgImage');
  if (params.has('winsColor')) currentConfig.colors.wins = params.get('winsColor');
  if (params.has('lossesColor')) currentConfig.colors.losses = params.get('lossesColor');
  if (params.has('rankTextColor')) currentConfig.colors.rankText = params.get('rankTextColor');
  if (params.has('font')) {
    currentConfig.font = params.get('font');
    document.documentElement.style.setProperty('--font', currentConfig.font);
}

  if (params.has('animDirection')) currentConfig.animation.direction = params.get('animDirection');
  if (params.has('animDurationIn')) currentConfig.animation.durationIn = parseInt(params.get('animDurationIn'));
  if (params.has('animStayTime')) currentConfig.animation.stayTime = parseInt(params.get('animStayTime'));
  if (params.has('animDurationOut')) currentConfig.animation.durationOut = parseInt(params.get('animDurationOut'));
  if (params.has('hiddenTime')) currentConfig.animation.hiddenTime = parseInt(params.get('hiddenTime'));

  applyConfig(currentConfig);
  startAnimation();
});

